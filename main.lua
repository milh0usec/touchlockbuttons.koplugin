-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Carlos Cezar

--[[--
Bottom virtual-button bar for KOReader.

Esta versão não sobrepõe o texto nem a barra de status do livro:
* a altura da barra de botões é incorporada ao espaço reservado pelo rodapé;
* a barra é desenhada imediatamente acima do rodapé nativo do KOReader;
* em documentos refluíveis, a margem inferior é recalculada;
* em documentos de página fixa, a área visível é recalculada.
--]]--

local Dispatcher      = require("dispatcher")
local DataStorage     = require("datastorage")
local lfs             = require("libs/libkoreader-lfs")
local USER_ICONS_DIR  = DataStorage:getDataDir() .. "/icons"
local USER_ICONS_DIR_WAS_PRESENT =
    lfs.attributes(USER_ICONS_DIR, "mode") == "directory"
local InputContainer  = require("ui/widget/container/inputcontainer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local Button          = require("ui/widget/button")
local UIManager       = require("ui/uimanager")
local Event           = require("ui/event")
local Geom            = require("ui/geometry")
local Size            = require("ui/size")
local Blitbuffer      = require("ffi/blitbuffer")
local Device          = require("device")
local logger          = require("logger")
local InfoMessage     = require("ui/widget/infomessage")
local ConfirmBox      = require("ui/widget/confirmbox")
local _               = require("gettext")

local Screen = Device.screen
local unpack = unpack or table.unpack

-- Each element has one responsibility. The bar-lock control, the independent
-- touchscreen indicator, and the sleep action use separate monochrome outlines
-- based on Font Awesome 4.7. No icon combines multiple states.
local LABEL_LOCKED    = "LOCK"
local LABEL_UNLOCKED  = "FREE"
local LABEL_TOUCH_ON  = "ON"
local LABEL_TOUCH_OFF = "OFF"
local LABEL_SLEEP     = "SLEEP"
local ICON_PREV       = "chevron.left"
local ICON_NEXT       = "chevron.right"
local ICON_FREE       = "touchlockbuttons-fa-unlock"
local ICON_LOCK       = "touchlockbuttons-fa-lock"
local ICON_TOUCH_ON   = "touchlockbuttons-fa-toggle-on"
local ICON_TOUCH_OFF  = "touchlockbuttons-fa-toggle-off"
local ICON_SLEEP      = "touchlockbuttons-fa-moon-o"
local BAR_ICON_SIZE   = Screen:scaleBySize(28)

local CUSTOM_ICON_NAMES = {
    ICON_FREE,
    ICON_LOCK,
    ICON_TOUCH_ON,
    ICON_TOUCH_OFF,
    ICON_SLEEP,
}

local LEGACY_ICON_NAMES = {
    "touchlockbuttons-free",
    "touchlockbuttons-lock",
    "touchlockbuttons-free-touch-off",
    "touchlockbuttons-lock-touch-off",
    "touchlockbuttons-bar-free",
    "touchlockbuttons-bar-lock",
}

local MAIN_SOURCE = debug.getinfo(1, "S").source or ""
local DETECTED_PLUGIN_DIR = MAIN_SOURCE:match("^@(.+)/main%.lua$")
local PLUGIN_DIR
if DETECTED_PLUGIN_DIR and DETECTED_PLUGIN_DIR:sub(1, 1) == "/" then
    PLUGIN_DIR = DETECTED_PLUGIN_DIR
elseif DETECTED_PLUGIN_DIR then
    PLUGIN_DIR = "/mnt/us/koreader/" .. DETECTED_PLUGIN_DIR:gsub("^%./", "")
else
    PLUGIN_DIR = "/mnt/us/koreader/plugins/touchlockbuttons.koplugin"
end

local KOREADER_DIR = PLUGIN_DIR:match("^(.*)/plugins/[^/]+$")
    or "/mnt/us/koreader"
local RESOURCE_ICONS_DIR = KOREADER_DIR .. "/resources/icons"

local POWER_WRAPPER = PLUGIN_DIR .. "/pw4-powerbutton.sh"
local POWER_CMD_FILE = "/tmp/touchlockbuttons-power.cmd"
local POWER_ACTIVE_FILE = "/tmp/touchlockbuttons-power.active"
local POWER_STOP_FILE = "/tmp/touchlockbuttons-power.stop"
local POWER_HOST_HEARTBEAT = "/tmp/touchlockbuttons-koreader.heartbeat"
local POWER_LOG_FILE = "/tmp/touchlockbuttons-power.log"

local SETTING_POWER_ENABLED = "touchlockbuttons_power_controller_enabled_v2"
local SETTING_DEFAULT_LOCKED = "touchlockbuttons_default_locked"
local SETTING_CLICK_WINDOW_MS = "touchlockbuttons_click_window_ms"

local TouchLockButtons = InputContainer:extend{
    name = "touchlockbuttons",
    is_doc_only = true,
}

local function rethrowResults(results)
    local ok = table.remove(results, 1)
    if not ok then
        error(results[1])
    end
    return unpack(results)
end

local function readFirstLine(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local line = file:read("*l")
    file:close()
    return line
end

local function writeTextFile(path, text)
    local file = io.open(path, "w")
    if not file then
        return false
    end
    file:write(text or "")
    file:close()
    return true
end

local function shellQuote(value)
    return string.format("%q", tostring(value))
end

local function readWholeFile(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local data = file:read("*a")
    file:close()
    return data
end

local function writeWholeFile(path, data)
    local file = io.open(path, "wb")
    if not file then
        return false
    end
    file:write(data)
    file:close()
    return true
end

function TouchLockButtons:installCustomIcons()
    local function ensureDirectory(path)
        if lfs.attributes(path, "mode") == "directory" then
            return true
        end
        return lfs.mkdir(path) and true or false
    end

    local function installInto(path)
        if not ensureDirectory(path) then
            logger.warn("touchlockbuttons: could not create icon directory", path)
            return false
        end

        for _, icon_name in ipairs(CUSTOM_ICON_NAMES) do
            local source = PLUGIN_DIR .. "/icons/" .. icon_name .. ".svg"
            local target = path .. "/" .. icon_name .. ".svg"
            local source_data = readWholeFile(source)

            if not source_data then
                logger.warn("touchlockbuttons: missing bundled icon", source)
                return false
            end

            if readWholeFile(target) ~= source_data
                    and not writeWholeFile(target, source_data) then
                logger.warn("touchlockbuttons: could not install icon", target)
                return false
            end
        end

        for _, icon_name in ipairs(LEGACY_ICON_NAMES) do
            os.remove(path .. "/" .. icon_name .. ".svg")
        end
        return true
    end

    -- Keep a user copy for subsequent KOReader sessions.
    local user_ok = installInto(USER_ICONS_DIR)

    -- IconWidget snapshots the list of user-icon directories when its module is
    -- first loaded. On a clean installation that may have happened before this
    -- plugin creates USER_ICONS_DIR. resources/icons is always in that snapshot,
    -- so this second unique-name copy makes the icons available immediately.
    local resource_ok = installInto(RESOURCE_ICONS_DIR)

    return resource_ok or (USER_ICONS_DIR_WAS_PRESENT and user_ok)
end

function TouchLockButtons:showStatusMessage(text, timeout, icon)
    if not self.ui or self.is_closing then
        return
    end

    UIManager:show(InfoMessage:new{
        text = text,
        timeout = timeout or 1.5,
        icon = icon or "notice-info",
    })
end

function TouchLockButtons:getLockStateIcon()
    return self.touch_locked and ICON_LOCK or ICON_FREE
end

function TouchLockButtons:getLockStateText()
    return self.touch_locked and LABEL_LOCKED or LABEL_UNLOCKED
end

function TouchLockButtons:updateLockButtonLabel()
    if not self.lock_button then
        return
    end

    if self.icons_available then
        self.lock_button:setIcon(
            self:getLockStateIcon(),
            self.lock_button.width
        )
    else
        self.lock_button:setText(
            self:getLockStateText(),
            self.lock_button.width
        )
    end
end

function TouchLockButtons:getPhysicalTouchIndicatorText()
    return self.physical_touch_locked and LABEL_TOUCH_OFF or LABEL_TOUCH_ON
end

function TouchLockButtons:getPhysicalTouchIndicatorIcon()
    return self.physical_touch_locked and ICON_TOUCH_OFF or ICON_TOUCH_ON
end

function TouchLockButtons:updatePhysicalTouchIndicator()
    if not self.touch_indicator then
        return
    end

    local width = self.touch_indicator_width or self.touch_indicator.width
    if self.icons_available then
        self.touch_indicator:setIcon(
            self:getPhysicalTouchIndicatorIcon(),
            width
        )
    else
        self.touch_indicator:setText(
            self:getPhysicalTouchIndicatorText(),
            width
        )
    end
end

function TouchLockButtons:showPhysicalTouchStatus()
    self:showStatusMessage(
        self.physical_touch_locked
            and _("Touchscreen disabled. Press Power three times to enable it.")
            or _("Touchscreen enabled. Press Power three times to disable it."),
        2.5,
        self.physical_touch_locked and "notice-warning" or "check"
    )
    return true
end

function TouchLockButtons:applyPhysicalTouchState(locked)
    -- Prefer the direct UIManager API. Broadcasting IgnoreTouchInput makes every
    -- InputContainer handle the event and may create KOReader's own notification,
    -- whose popup lifecycle can temporarily restore touch input.
    if UIManager.setIgnoreTouchInput then
        UIManager:setIgnoreTouchInput(locked)
    else
        -- Compatibility fallback for older KOReader builds.
        UIManager:broadcastEvent(Event:new("IgnoreTouchInput", locked))
    end
end

function TouchLockButtons:setPhysicalTouchLocked(locked, notify, force_apply)
    locked = locked and true or false

    local changed = self.physical_touch_locked ~= locked
    if not changed and not force_apply then
        return
    end

    self.physical_touch_locked = locked

    if locked then
        if changed and notify ~= false then
            self:showStatusMessage(
                _("Touchscreen disabled"),
                1.5,
                "notice-warning"
            )
        end

        -- Aguarda a mensagem entrar na fila de pintura antes de ignorar o touch.
        -- force_apply permite restaurar o bloqueio real após Resume, mesmo quando
        -- a variável de estado já continua marcada como true.
        self._physical_apply_pending = true
        UIManager:scheduleIn(0.05, function()
            self._physical_apply_pending = nil
            if not self.is_closing and self.physical_touch_locked then
                self:applyPhysicalTouchState(true)
            end
        end)
    else
        self._physical_apply_pending = nil
        self:applyPhysicalTouchState(false)
        if changed and notify ~= false then
            self:showStatusMessage(
                _("Touchscreen enabled"),
                1.5,
                "check"
            )
        end
    end

    self:updatePhysicalTouchIndicator()

    if self.ui then
        UIManager:setDirty(self.ui, "ui")
    end
end

function TouchLockButtons:ensurePhysicalTouchLockApplied()
    if not self.physical_touch_locked or self.is_closing
            or self._physical_apply_pending then
        return
    end

    -- KOReader temporarily restores gestures whenever an automatic popup is
    -- displayed. While this plugin's hardware lock is active, immediately
    -- reclaim the lock instead of allowing that temporary state to become a
    -- visible or persistent touchscreen reactivation.
    if UIManager._input_gestures_disabled ~= true then
        logger.warn(
            "touchlockbuttons: KOReader restored gestures while physical "
                .. "touch lock was active; reapplying lock"
        )
        self:applyPhysicalTouchState(true)
    end
end

function TouchLockButtons:restorePhysicalTouchLockAfterResume()
    if not self.physical_touch_locked or self.is_closing
            or self._physical_lock_restore_scheduled then
        return
    end

    self._physical_lock_restore_scheduled = true
    UIManager:scheduleIn(0.20, function()
        self._physical_lock_restore_scheduled = nil
        if not self.is_closing and self.physical_touch_locked then
            self:setPhysicalTouchLocked(true, false, true)
        end
    end)
end

function TouchLockButtons:togglePhysicalTouch()
    self:setPhysicalTouchLocked(not self.physical_touch_locked, true)
    return true
end

function TouchLockButtons:writePowerHostHeartbeat()
    writeTextFile(POWER_HOST_HEARTBEAT, tostring(os.time()) .. "\n")
end

function TouchLockButtons:hasFreshPowerHeartbeat()
    local heartbeat = tonumber(readFirstLine(POWER_ACTIVE_FILE) or "")
    return heartbeat and math.abs(os.time() - heartbeat) <= 5 or false
end

function TouchLockButtons:isPowerControllerActive()
    if self:hasFreshPowerHeartbeat() then
        return true
    end

    if self._power_start_requested_at
            and os.time() - self._power_start_requested_at <= 5 then
        return true
    end

    return false
end

function TouchLockButtons:processPowerCommands()
    local snapshot = POWER_CMD_FILE .. ".reading"

    os.remove(snapshot)
    if not os.rename(POWER_CMD_FILE, snapshot) then
        return
    end

    local file = io.open(snapshot, "r")
    if not file then
        os.remove(snapshot)
        return
    end

    local data = file:read("*a") or ""
    file:close()
    os.remove(snapshot)

    for command in data:gmatch("[^\r\n]+") do
        if command == "NEXT" then
            self:turnPage(1)
        elseif command == "PREV" then
            self:turnPage(-1)
        elseif command == "TOUCH_TOGGLE" then
            self:togglePhysicalTouch()
        elseif command == "TOUCH_OFF" then
            self:setPhysicalTouchLocked(true, true)
        elseif command == "TOUCH_ON" then
            self:setPhysicalTouchLocked(false, true)
        elseif command == "CONTROLLER_STOPPED" then
            self._power_start_requested_at = nil
        elseif command ~= "" then
            logger.warn("touchlockbuttons: comando físico desconhecido", command)
        end
    end
end

function TouchLockButtons:startPowerCommandPolling()
    if self._power_polling then
        return
    end

    self._power_polling = true

    local function poll()
        if self.is_closing then
            self._power_polling = nil
            return
        end

        self:writePowerHostHeartbeat()
        self:processPowerCommands()
        self:ensurePhysicalTouchLockApplied()

        local active = self:isPowerControllerActive()
        if self._power_was_active and not active then
            -- A transient heartbeat gap must never be interpreted as a request
            -- to re-enable touch. Only an explicit command may change the state.
            logger.warn(
                "touchlockbuttons: physical controller heartbeat lost; "
                    .. "preserving touchscreen state"
            )
        end
        if self._power_was_active ~= active then
            self._power_was_active = active
            if self.ui then
                UIManager:setDirty(self.ui, "ui")
            end
        end

        -- Keep a fast guard while the touchscreen is locked, even if the
        -- controller heartbeat is temporarily late. This prevents KOReader's
        -- popup/resume lifecycle from leaving gestures enabled.
        UIManager:scheduleIn(
            (active or self.physical_touch_locked) and 0.10 or 1.0,
            poll
        )
    end

    UIManager:scheduleIn(0.10, poll)
end

function TouchLockButtons:startPowerController(show_message)
    if self:isPowerControllerActive() then
        if show_message ~= false then
            self:showStatusMessage(
                _("Physical power-button controller is already enabled."),
                1.5,
                "notice-info"
            )
        end
        return true
    end

    self:writePowerHostHeartbeat()
    os.remove(POWER_STOP_FILE)

    local command = "sh " .. shellQuote(POWER_WRAPPER)
        .. " start --click-window "
        .. shellQuote((self.click_window_ms or 200) / 1000)
        .. " >/dev/null 2>&1 &"

    local result = os.execute(command)
    self._power_start_requested_at = os.time()

    local function verifyStart(attempt)
        UIManager:scheduleIn(0.5, function()
            if self.is_closing then
                return
            end

            if self:hasFreshPowerHeartbeat() then
                self._power_start_requested_at = nil
                if show_message ~= false then
                    self:showStatusMessage(
                        _("Physical power-button controller enabled."),
                        1.5,
                        "check"
                    )
                end
                if self.ui then
                    UIManager:setDirty(self.ui, "ui")
                end
                return
            end

            if attempt < 6 then
                verifyStart(attempt + 1)
                return
            end

            self._power_start_requested_at = nil
            self.power_enabled = false
            G_reader_settings:saveSetting(SETTING_POWER_ENABLED, false)
            -- Controller startup failure does not alter the touchscreen state.
            -- State changes require an explicit TOUCH_ON/TOUCH_OFF/TOUCH_TOGGLE
            -- command or an explicit menu action.
            self:showStatusMessage(
                _("Could not enable the physical power-button controller. See:\n")
                    .. POWER_LOG_FILE,
                4
            )
        end)
    end

    verifyStart(1)
    return result
end

function TouchLockButtons:stopPowerController(show_message)
    local was_active = self:isPowerControllerActive()

    -- Full touchscreen lock is unsafe without the physical controller because
    -- there would be no non-touch way to restore input.
    self:setPhysicalTouchLocked(false, false, true)
    self._power_start_requested_at = nil

    os.execute(
        "sh " .. shellQuote(POWER_WRAPPER)
            .. " stop >/dev/null 2>&1 &"
    )

    if show_message ~= false then
        if was_active then
            self:showStatusMessage(
                _("Physical power-button controller disabled."),
                1.5,
                "cancel"
            )
        else
            self:showStatusMessage(
                _("Physical power-button controller was already disabled."),
                1.5,
                "notice-info"
            )
        end
    end

    if self.ui then
        UIManager:setDirty(self.ui, "ui")
    end
    return true
end

function TouchLockButtons:setPowerControllerEnabled(enabled, show_message)
    enabled = enabled and true or false
    self.power_enabled = enabled
    G_reader_settings:saveSetting(SETTING_POWER_ENABLED, enabled)

    if enabled then
        return self:startPowerController(show_message)
    end
    return self:stopPowerController(show_message)
end

function TouchLockButtons:requestEnablePowerController()
    UIManager:show(ConfirmBox:new{
        text = _([[The physical controller intercepts the Kindle Power button.

While enabled, the native short-press and long-press Power actions are unavailable.

Physical controls:
- Click: next page
- Double-click: previous page
- Triple-click: enable or disable the touchscreen

After disabling the touchscreen, press Power three times to enable it again.]]),
        ok_text = _("Enable"),
        cancel_text = _("Cancel"),
        ok_callback = function()
            self:setPowerControllerEnabled(true, true)
        end,
    })
    return true
end

function TouchLockButtons:schedulePowerAutoStart()
    if not self.power_enabled or self.is_closing then
        return
    end

    UIManager:scheduleIn(0.6, function()
        if not self.is_closing and self.ui and self.ui.document then
            self:startPowerController(false)
        end
    end)
end

function TouchLockButtons:putKindleToSleep()
    -- Re-enable touch before sleeping and let the wrapper restore powerd before
    -- issuing the sleep request. The saved controller preference is preserved,
    -- so it starts again after wakeup.
    self:setPhysicalTouchLocked(false, false, true)
    self._power_start_requested_at = nil
    os.execute(
        "sh " .. shellQuote(POWER_WRAPPER)
            .. " sleep >/dev/null 2>&1 &"
    )
    return true
end

function TouchLockButtons:init()
    if not self.ui or not self.ui.document or not self.ui.view then
        return
    end

    self.default_locked =
        G_reader_settings:readSetting(SETTING_DEFAULT_LOCKED, false)
    self.touch_locked = self.default_locked
    self.physical_touch_locked = false
    self.is_closing = false
    self.dimen = Screen:getSize()

    -- A fresh installation starts with the physical controller disabled.
    -- It is managed explicitly from the plugin menu.
    self.power_enabled =
        G_reader_settings:readSetting(SETTING_POWER_ENABLED, false)
    self.click_window_ms =
        G_reader_settings:readSetting(SETTING_CLICK_WINDOW_MS, 200)

    self.icons_available = self:installCustomIcons()
    if not self.icons_available then
        logger.warn("touchlockbuttons: using text fallback for central button")
    end

    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    self:startPowerCommandPolling()

    self:buildButtonBar(self.dimen)
    self:installLayoutHooks()
    self:updateBarGeometry(self.dimen, true)
    self:registerBlockingZones(self.dimen)

    if self.ui.view.registerViewModule then
        self.ui.view:registerViewModule(self.name, self)
        logger.info("touchlockbuttons: módulo visual registrado com espaço reservado")
    else
        logger.err("touchlockbuttons: ReaderView sem registerViewModule")
    end

    -- O ReaderFooter ainda não concluiu seu primeiro layout neste ponto.
    -- A estabilização é feita depois do onReaderReady/onPageUpdate nativos,
    -- evitando que a barra de status nasça com larguras preliminares.
    self:scheduleFooterStabilization()
end

function TouchLockButtons:buildButtonBar(dimen)
    dimen = dimen or Screen:getSize()
    self.dimen = dimen

    if self[1] and self[1].free then
        self[1]:free()
    end
    self[1] = nil

    local frame_extra = 2 * Size.border.thick + 2 * Size.padding.small
    local usable_width = math.max(5, dimen.w - frame_extra)

    -- Five segments keep the independent touchscreen indicator geometrically
    -- centered: two equal controls on its left and two on its right.
    local btn_width = math.floor(usable_width / 5)
    local indicator_width = usable_width - (btn_width * 4)
    self.touch_indicator_width = indicator_width

    local btn_prev = Button:new{
        icon = ICON_PREV,
        icon_width = BAR_ICON_SIZE,
        icon_height = BAR_ICON_SIZE,
        width = btn_width,
        callback = function()
            self:turnPage(-1)
        end,
        hold_callback = function()
            self:turnPage(-10)
        end,
    }

    local lock_button_args = {
        width = btn_width,
        callback = function()
            self:toggleLock()
        end,
    }
    if self.icons_available then
        lock_button_args.icon = self:getLockStateIcon()
        lock_button_args.icon_width = BAR_ICON_SIZE
        lock_button_args.icon_height = BAR_ICON_SIZE
    else
        lock_button_args.text = self:getLockStateText()
    end
    self.lock_button = Button:new(lock_button_args)

    -- Read-only, independent indicator for the full touchscreen state.
    -- It occupies the exact middle segment and never controls the daemon.
    local touch_indicator_args = {
        width = indicator_width,
        callback = function()
            self:showPhysicalTouchStatus()
        end,
    }
    if self.icons_available then
        touch_indicator_args.icon = self:getPhysicalTouchIndicatorIcon()
        touch_indicator_args.icon_width = BAR_ICON_SIZE
        touch_indicator_args.icon_height = BAR_ICON_SIZE
    else
        touch_indicator_args.text = self:getPhysicalTouchIndicatorText()
    end
    self.touch_indicator = Button:new(touch_indicator_args)

    local sleep_button_args = {
        width = btn_width,
        callback = function()
            self:putKindleToSleep()
        end,
    }
    if self.icons_available then
        sleep_button_args.icon = ICON_SLEEP
        sleep_button_args.icon_width = BAR_ICON_SIZE
        sleep_button_args.icon_height = BAR_ICON_SIZE
    else
        sleep_button_args.text = LABEL_SLEEP
    end
    self.sleep_button = Button:new(sleep_button_args)

    local btn_next = Button:new{
        icon = ICON_NEXT,
        icon_width = BAR_ICON_SIZE,
        icon_height = BAR_ICON_SIZE,
        width = btn_width,
        callback = function()
            self:turnPage(1)
        end,
        hold_callback = function()
            self:turnPage(10)
        end,
    }

    local row = HorizontalGroup:new{
        align = "center",
        allow_mirroring = false,
        btn_prev,
        self.lock_button,
        self.touch_indicator,
        self.sleep_button,
        btn_next,
    }

    self.framed_bar = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.thick,
        padding = Size.padding.small,
        radius = 0,
        row,
    }

    self.bar_height = self.framed_bar:getSize().h

    self.bottom_container = BottomContainer:new{
        dimen = Geom:new{ x = 0, y = 0, w = dimen.w, h = dimen.h },
        self.framed_bar,
    }

    self[1] = self.bottom_container
end

function TouchLockButtons:getNativeFooterHeight()
    local footer = self.ui and self.ui.view and self.ui.view.footer
    if not footer then
        return 0
    end

    if self._footer_getHeight then
        local ok, height = pcall(self._footer_getHeight, footer)
        if ok and type(height) == "number" then
            return height
        end
    end

    return 0
end

function TouchLockButtons:getFooterSlotHeight()
    local view = self.ui and self.ui.view
    local footer = view and view.footer
    if not footer then
        return 0
    end

    local native_height = self:getNativeFooterHeight()
    local reclaim = footer.settings and footer.settings.reclaim_height
    if reclaim == nil then
        reclaim = footer.reclaim_height
    end

    -- Sem "reclaim height", o KOReader mantém a área do rodapé reservada mesmo
    -- quando ele está temporariamente oculto; a barra permanece estável.
    if not reclaim or view.footer_visible then
        return native_height
    end

    return 0
end

function TouchLockButtons:updateBarGeometry(dimen, force_zones)
    dimen = dimen or Screen:getSize()
    self.dimen = dimen

    local footer_slot_height = self:getFooterSlotHeight()
    local container_height = math.max(self.bar_height or 0, dimen.h - footer_slot_height)
    local new_bar_top = math.max(0, container_height - (self.bar_height or 0))

    if self.bottom_container then
        self.bottom_container.dimen.x = 0
        self.bottom_container.dimen.y = 0
        self.bottom_container.dimen.w = dimen.w
        self.bottom_container.dimen.h = container_height
        if self.bottom_container.resetLayout then
            self.bottom_container:resetLayout()
        end
    end

    local geometry_changed = self.bar_top ~= new_bar_top
        or self.footer_slot_height ~= footer_slot_height

    self.bar_top = new_bar_top
    self.footer_slot_height = footer_slot_height

    if geometry_changed and not force_zones and not self._zones_update_scheduled then
        self._zones_update_scheduled = true
        UIManager:nextTick(function()
            self._zones_update_scheduled = nil
            if not self.is_closing and self.ui and self.ui.document then
                self:registerBlockingZones(Screen:getSize())
            end
        end)
    end
end

function TouchLockButtons:paintTo(bb, x, y)
    -- A altura do rodapé pode mudar após alteração das opções da barra de status.
    self:updateBarGeometry(Screen:getSize(), false)
    return InputContainer.paintTo(self, bb, x, y)
end

function TouchLockButtons:installLayoutHooks()
    local view = self.ui.view
    local footer = view and view.footer
    if not footer or self._footer_getHeight then
        return
    end

    self._footer_getHeight = footer.getHeight
    self._footer_getHeight_wrapper = function(footer_self)
        local native_height = self._footer_getHeight(footer_self) or 0

        -- Durante os wrappers de recálculo, quando o usuário optou por
        -- "reclaim height", apenas a nossa barra deve ser reservada.
        if self._footer_height_context == "bar_only" then
            return self.bar_height or 0
        end

        return native_height + (self.bar_height or 0)
    end
    footer.getHeight = self._footer_getHeight_wrapper

    -- ReaderView usa settings.reclaim_height para decidir se subtrai a altura
    -- do rodapé. Fazemos o recálculo como se houvesse reserva, mas o getHeight
    -- retorna somente a barra quando o usuário quer o rodapé sobreposto.
    self._view_recalculate = view.recalculate
    self._view_recalculate_wrapper = function(view_self, ...)
        local footer_self = view_self.footer
        local old_reclaim = footer_self.settings and footer_self.settings.reclaim_height
        local old_context = self._footer_height_context

        self._footer_height_context = old_reclaim and "bar_only" or "combined"
        if footer_self.settings then
            footer_self.settings.reclaim_height = false
        end

        local args = { ... }
        local results = { pcall(function()
            return self._view_recalculate(view_self, unpack(args))
        end) }

        if footer_self.settings then
            footer_self.settings.reclaim_height = old_reclaim
        end
        self._footer_height_context = old_context

        return rethrowResults(results)
    end
    view.recalculate = self._view_recalculate_wrapper

    -- Em EPUB/FB2/TXT, ReaderTypeset soma footer:getHeight() à margem
    -- inferior. Este wrapper garante a reserva da barra mesmo com a opção
    -- "reclaim height" ligada, sem alterar permanentemente a preferência.
    local typeset = self.ui.typeset
    if typeset and typeset.onSetPageMargins then
        self._typeset_onSetPageMargins = typeset.onSetPageMargins
        self._typeset_onSetPageMargins_wrapper = function(typeset_self, ...)
            local footer_self = typeset_self.view and typeset_self.view.footer
                or (typeset_self.ui and typeset_self.ui.view and typeset_self.ui.view.footer)

            if not footer_self then
                return self._typeset_onSetPageMargins(typeset_self, ...)
            end

            local old_reclaim = footer_self.reclaim_height
            local old_context = self._footer_height_context

            self._footer_height_context = old_reclaim and "bar_only" or "combined"
            footer_self.reclaim_height = false

            local args = { ... }
            local results = { pcall(function()
                return self._typeset_onSetPageMargins(typeset_self, unpack(args))
            end) }

            footer_self.reclaim_height = old_reclaim
            self._footer_height_context = old_context

            return rethrowResults(results)
        end
        typeset.onSetPageMargins = self._typeset_onSetPageMargins_wrapper
    end

    -- O rodapé do KOReader só ativa a atualização real do texto no próprio
    -- onReaderReady(). Encadeamos esse evento e a primeira atualização de página
    -- para estabilizar o layout depois que largura, texto e barra de progresso
    -- já possuem valores definitivos.
    if footer.onReaderReady then
        self._footer_onReaderReady = footer.onReaderReady
        self._footer_onReaderReady_wrapper = function(footer_self, ...)
            local args = { ... }
            local results = { pcall(function()
                return self._footer_onReaderReady(footer_self, unpack(args))
            end) }
            if results[1] then
                self:scheduleFooterStabilization()
            end
            return rethrowResults(results)
        end
        footer.onReaderReady = self._footer_onReaderReady_wrapper
    end

    if footer.onPageUpdate then
        self._footer_onPageUpdate = footer.onPageUpdate
        self._footer_onPageUpdate_wrapper = function(footer_self, ...)
            local args = { ... }
            local results = { pcall(function()
                return self._footer_onPageUpdate(footer_self, unpack(args))
            end) }
            if results[1] and not self._footer_layout_stabilized then
                self:scheduleFooterStabilization()
            end
            return rethrowResults(results)
        end
        footer.onPageUpdate = self._footer_onPageUpdate_wrapper
    end

    if footer.onPosUpdate then
        self._footer_onPosUpdate = footer.onPosUpdate
        self._footer_onPosUpdate_wrapper = function(footer_self, ...)
            local args = { ... }
            local results = { pcall(function()
                return self._footer_onPosUpdate(footer_self, unpack(args))
            end) }
            if results[1] and not self._footer_layout_stabilized then
                self:scheduleFooterStabilization()
            end
            return rethrowResults(results)
        end
        footer.onPosUpdate = self._footer_onPosUpdate_wrapper
    end
end

function TouchLockButtons:uninstallLayoutHooks()
    local view = self.ui and self.ui.view
    local footer = view and view.footer

    if footer and self._footer_getHeight
            and footer.getHeight == self._footer_getHeight_wrapper then
        footer.getHeight = self._footer_getHeight
    end

    if footer and self._footer_onReaderReady
            and footer.onReaderReady == self._footer_onReaderReady_wrapper then
        footer.onReaderReady = self._footer_onReaderReady
    end

    if footer and self._footer_onPageUpdate
            and footer.onPageUpdate == self._footer_onPageUpdate_wrapper then
        footer.onPageUpdate = self._footer_onPageUpdate
    end

    if footer and self._footer_onPosUpdate
            and footer.onPosUpdate == self._footer_onPosUpdate_wrapper then
        footer.onPosUpdate = self._footer_onPosUpdate
    end

    if view and self._view_recalculate
            and view.recalculate == self._view_recalculate_wrapper then
        view.recalculate = self._view_recalculate
    end

    local typeset = self.ui and self.ui.typeset
    if typeset and self._typeset_onSetPageMargins
            and typeset.onSetPageMargins == self._typeset_onSetPageMargins_wrapper then
        typeset.onSetPageMargins = self._typeset_onSetPageMargins
    end
end

function TouchLockButtons:scheduleFooterStabilization()
    if self.is_closing or self._footer_layout_stabilized
            or self._footer_stabilization_scheduled then
        return
    end

    self._footer_stabilization_scheduled = true
    UIManager:nextTick(function()
        self._footer_stabilization_scheduled = nil
        if not self.is_closing then
            self:stabilizeFooterLayout()
        end
    end)
end

function TouchLockButtons:stabilizeFooterLayout()
    if self.is_closing or not self.ui or not self.ui.view then
        return
    end

    local footer = self.ui.view.footer
    if not footer then
        return
    end

    -- Antes do ReaderFooter:onReaderReady(), updateFooterText ainda é um noop.
    -- A primeira PageUpdate/PosUpdate também fornece o número da página, exigido
    -- por onUpdateFooter(). Se algo ainda não estiver pronto, tentamos de novo.
    local footer_ready = footer._updateFooterText
        and footer.updateFooterText == footer._updateFooterText
    local page_ready = type(footer.pageno) == "number"

    if not footer_ready or not page_ready then
        self._footer_stabilization_attempts = (self._footer_stabilization_attempts or 0) + 1
        if self._footer_stabilization_attempts <= 8 then
            UIManager:scheduleIn(0.05, function()
                if not self.is_closing then
                    self:scheduleFooterStabilization()
                end
            end)
        else
            -- Não deixamos de reservar a barra caso algum formato não emita
            -- PageUpdate/PosUpdate na abertura.
            self:refreshReservedLayout()
        end
        return
    end

    self._footer_stabilization_attempts = 0

    -- refreshFooter reconstrói o container, força resetLayout e executa
    -- onUpdateFooter. É a mesma recomposição que acontecia apenas no primeiro
    -- toque, mas agora ocorre antes da apresentação definitiva da página.
    if footer.refreshFooter then
        footer:refreshFooter(false, false)
    else
        if footer.resetLayout then
            footer:resetLayout(true)
        end
        if footer.onUpdateFooter then
            footer:onUpdateFooter(false, false)
        end
    end

    -- Uma segunda passagem garante que BottomContainer/CenterContainer adotem
    -- as dimensões calculadas pelo texto recém-atualizado.
    if footer.resetLayout then
        footer:resetLayout(true)
    end

    self._footer_layout_stabilized = true
    self:refreshReservedLayout()
end

function TouchLockButtons:refreshReservedLayout()
    if self.is_closing or not self.ui or not self.ui.document then
        return
    end

    self:updateBarGeometry(Screen:getSize(), true)
    self:registerBlockingZones(Screen:getSize())

    -- Documentos refluíveis: força nova margem inferior e repaginação.
    if self.ui.typeset and self.ui.typeset.unscaled_margins
            and self.ui.typeset.onSetPageMargins then
        self.ui.typeset:onSetPageMargins(self.ui.typeset.unscaled_margins)
    -- Documentos de página fixa: reduz a área visível sem alterar o arquivo.
    elseif self.ui.view and self.ui.view.recalculate then
        self.ui.view:recalculate()
    end

    UIManager:setDirty(self.ui, "ui")
end

function TouchLockButtons:registerBlockingZones(dimen)
    dimen = dimen or Screen:getSize()

    local blocked_height = math.max(0, math.min(dimen.h, self.bar_top or (dimen.h - (self.bar_height or 0))))
    local blocked_ratio_h = dimen.h > 0 and (blocked_height / dimen.h) or 0

    local gestures_to_guard = {
        "tap",
        "double_tap",
        "hold",
        "hold_release",
        "swipe",
        "pan",
        "pan_release",
        "two_finger_tap",
        "pinch",
        "spread",
    }

    local zones = {}
    for _, ges_name in ipairs(gestures_to_guard) do
        local gesture_name = ges_name
        table.insert(zones, {
            id = "touchlockbuttons_block_" .. gesture_name,
            ges = gesture_name,
            screen_zone = {
                ratio_x = 0,
                ratio_y = 0,
                ratio_w = 1,
                ratio_h = blocked_ratio_h,
            },
            handler = function()
                if self.touch_locked then
                    logger.dbg("touchlockbuttons: gesto bloqueado", gesture_name)
                    return true
                end
                return false
            end,
        })
    end

    self:registerTouchZones(zones)
end

function TouchLockButtons:turnPage(direction)
    if self.ui then
        self.ui:handleEvent(Event:new("GotoViewRel", direction))
    end
    return true
end

function TouchLockButtons:toggleLock()
    self.touch_locked = not self.touch_locked
    self:updateLockButtonLabel()

    self:showStatusMessage(
        self.touch_locked
            and _("Touch outside the button bar locked")
            or _("Touch outside the button bar free"),
        1.2,
        self.icons_available and self:getLockStateIcon() or "notice-info"
    )

    if self.ui then
        UIManager:setDirty(self.ui, "ui")
    end

    logger.info(
        "touchlockbuttons: bloqueio",
        self.touch_locked and "ativado" or "desativado"
    )
    return true
end

function TouchLockButtons:onDispatcherRegisterActions()
    Dispatcher:registerAction("touchlockbuttons_toggle", {
        category = "none",
        event = "ToggleTouchLockButtons",
        title = _("Toggle touch lock outside the button bar"),
        general = true,
    })
end

function TouchLockButtons:onToggleTouchLockButtons()
    return self:toggleLock()
end


function TouchLockButtons:setClickWindowMs(milliseconds)
    self.click_window_ms = milliseconds
    G_reader_settings:saveSetting(SETTING_CLICK_WINDOW_MS, milliseconds)

    if self.power_enabled or self:isPowerControllerActive() then
        self:stopPowerController(false)
        self.power_enabled = true
        G_reader_settings:saveSetting(SETTING_POWER_ENABLED, true)
        self:startPowerController(false)
    end
end

function TouchLockButtons:addToMainMenu(menu_items)
    menu_items.touchlockbuttons = {
        text = _("Virtual buttons"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = _("Lock gestures outside the bar by default"),
                checked_func = function()
                    return self.default_locked
                end,
                callback = function()
                    self.default_locked = not self.default_locked
                    G_reader_settings:saveSetting(
                        SETTING_DEFAULT_LOCKED,
                        self.default_locked
                    )
                end,
            },
            {
                text = _("Power-button controller (PW4)"),
                sub_item_table = {
                    {
                        text = _("Enable physical Power-button support"),
                        checked_func = function()
                            return self.power_enabled
                                or self:isPowerControllerActive()
                        end,
                        callback = function()
                            if self.power_enabled
                                    or self:isPowerControllerActive() then
                                self:setPowerControllerEnabled(false, true)
                            else
                                self:requestEnablePowerController()
                            end
                        end,
                    },
                    {
                        text_func = function()
                            return string.format(
                                _("Click latency: %d ms"),
                                self.click_window_ms or 200
                            )
                        end,
                        enabled_func = function()
                            return self.power_enabled
                                or self:isPowerControllerActive()
                        end,
                        sub_item_table = {
                            {
                                text = "200 ms",
                                checked_func = function()
                                    return self.click_window_ms == 200
                                end,
                                callback = function()
                                    self:setClickWindowMs(200)
                                end,
                            },
                            {
                                text = "250 ms",
                                checked_func = function()
                                    return self.click_window_ms == 250
                                end,
                                callback = function()
                                    self:setClickWindowMs(250)
                                end,
                            },
                            {
                                text = "300 ms",
                                checked_func = function()
                                    return self.click_window_ms == 300
                                end,
                                callback = function()
                                    self:setClickWindowMs(300)
                                end,
                            },
                        },
                    },
                    {
                        text = _("Hint: press Power three times to toggle the touchscreen"),
                        enabled_func = function() return false end,
                    },
                    {
                        text_func = function()
                            return self.physical_touch_locked
                                and _("Touchscreen status: disabled")
                                or _("Touchscreen status: enabled")
                        end,
                        enabled_func = function() return false end,
                    },
                },
            },
        },
    }
end

function TouchLockButtons:onReaderReady()
    self:scheduleFooterStabilization()
    self:schedulePowerAutoStart()
end

function TouchLockButtons:onWakeupFromSuspend()
    self:schedulePowerAutoStart()
    self:restorePhysicalTouchLockAfterResume()
end

function TouchLockButtons:onOutOfScreenSaver()
    self:schedulePowerAutoStart()
    self:restorePhysicalTouchLockAfterResume()
end

function TouchLockButtons:onResume()
    self:schedulePowerAutoStart()
    self:restorePhysicalTouchLockAfterResume()
end

function TouchLockButtons:onReaderFooterVisibilityChange()
    if self.is_closing then
        return
    end
    self:updateBarGeometry(Screen:getSize(), true)
    self:registerBlockingZones(Screen:getSize())
    if self.ui then
        UIManager:setDirty(self.ui, "ui")
    end
end

function TouchLockButtons:onScreenResize(dimen)
    if self.is_closing or not dimen then
        return
    end

    self._footer_layout_stabilized = nil
    self._footer_stabilization_attempts = 0
    self:buildButtonBar(dimen)
    self:updateBarGeometry(dimen, true)
    self:registerBlockingZones(dimen)
    self:scheduleFooterStabilization()
end

function TouchLockButtons:unregisterViewModule()
    if self.is_closing then
        return
    end

    self:stopPowerController(false)
    os.remove(POWER_HOST_HEARTBEAT)
    self.is_closing = true

    self:uninstallLayoutHooks()

    if self.ui and self.ui.view and self.ui.view.view_modules
            and self.ui.view.view_modules[self.name] == self then
        self.ui.view.view_modules[self.name] = nil
    end
end

function TouchLockButtons:onCloseDocument()
    self:unregisterViewModule()
end

function TouchLockButtons:onCloseWidget()
    self:unregisterViewModule()
end

return TouchLockButtons
