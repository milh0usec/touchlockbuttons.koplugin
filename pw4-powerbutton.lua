#!/usr/bin/env luajit
-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Copyright (C) 2026 Carlos Cezar

-- Controlador do botão físico para Kindle Paperwhite 4.
-- Executado pelo pw4-powerbutton.sh, não diretamente pelo usuário.

local ffi = require("ffi")
local bit = require("bit")

io.stdout:setvbuf("line")
io.stderr:setvbuf("line")

ffi.cdef[[
struct timeval {
    long tv_sec;
    long tv_usec;
};

struct input_event {
    struct timeval time;
    unsigned short type;
    unsigned short code;
    int value;
};

struct pollfd {
    int fd;
    short events;
    short revents;
};

struct timespec {
    long tv_sec;
    long tv_nsec;
};

int open(const char *pathname, int flags, ...);
int close(int fd);
long read(int fd, void *buf, unsigned long count);
int ioctl(int fd, unsigned long request, unsigned long arg);
int poll(struct pollfd *fds, unsigned long nfds, int timeout);
int clock_gettime(int clk_id, struct timespec *tp);
char *strerror(int errnum);
]]

local C = ffi.C

local O_RDONLY = 0
local O_NONBLOCK = 2048
local POLLIN = 0x0001
local EV_KEY = 1
local EVIOCGRAB = 0x40044590
local EAGAIN = 11
local CLOCK_BOOTTIME = 7

local EXIT_OK = 0

local opts = {
    power = "/dev/input/event1",
    keycode = 116,
    timeout = 0,
    cmd_file = "/tmp/touchlockbuttons-power.cmd",
    stop_file = "/tmp/touchlockbuttons-power.stop",
    active_file = "/tmp/touchlockbuttons-power.active",
    host_heartbeat = "/tmp/touchlockbuttons-koreader.heartbeat",
    click_window = 0.20,
    short_max = 0.70,
    host_timeout = 10,
}

local function parseArgs()
    local index = 1
    while index <= #arg do
        local item = arg[index]

        if item == "--power" then
            index = index + 1
            opts.power = assert(arg[index], "--power exige caminho")
        elseif item == "--keycode" then
            index = index + 1
            opts.keycode = tonumber(arg[index]) or error("--keycode inválido")
        elseif item == "--timeout" then
            index = index + 1
            opts.timeout = tonumber(arg[index]) or error("--timeout inválido")
        elseif item == "--cmd-file" then
            index = index + 1
            opts.cmd_file = assert(arg[index], "--cmd-file exige caminho")
        elseif item == "--stop-file" then
            index = index + 1
            opts.stop_file = assert(arg[index], "--stop-file exige caminho")
        elseif item == "--active-file" then
            index = index + 1
            opts.active_file = assert(arg[index], "--active-file exige caminho")
        elseif item == "--host-heartbeat" then
            index = index + 1
            opts.host_heartbeat =
                assert(arg[index], "--host-heartbeat exige caminho")
        elseif item == "--click-window" then
            index = index + 1
            opts.click_window =
                tonumber(arg[index]) or error("--click-window inválido")
        else
            error("Argumento desconhecido: " .. tostring(item))
        end

        index = index + 1
    end
end

parseArgs()

local function now()
    local timestamp = ffi.new("struct timespec[1]")
    if C.clock_gettime(CLOCK_BOOTTIME, timestamp) ~= 0 then
        return os.time()
    end

    return tonumber(timestamp[0].tv_sec)
        + tonumber(timestamp[0].tv_nsec) / 1000000000
end

local function errorText()
    local errno = ffi.errno()
    return string.format(
        "errno=%d (%s)",
        errno,
        ffi.string(C.strerror(errno))
    )
end

local function fileExists(path)
    local file = io.open(path, "r")
    if not file then
        return false
    end
    file:close()
    return true
end

local function readEpoch(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local value = tonumber(file:read("*l") or "")
    file:close()
    return value
end

local function writeFile(path, text)
    local file = io.open(path, "w")
    if not file then
        return false
    end
    file:write(text or "")
    file:close()
    return true
end

local function appendCommand(command)
    local file, err = io.open(opts.cmd_file, "a")
    if not file then
        io.stderr:write(
            "Falha ao escrever comando: " .. tostring(err) .. "\n"
        )
        return false
    end

    file:write(command, "\n")
    file:flush()
    file:close()
    print("KOReader <- " .. command)
    return true
end

local state = {
    power_fd = -1,
    power_grabbed = false,
}

local function setGrab(fd, enabled)
    local value = enabled and 1 or 0
    if C.ioctl(
            fd,
            EVIOCGRAB,
            ffi.cast("unsigned long", value)
        ) < 0 then
        return nil, errorText()
    end
    return true
end

local function cleanup()
    if state.power_fd >= 0 then
        if state.power_grabbed then
            C.ioctl(
                state.power_fd,
                EVIOCGRAB,
                ffi.cast("unsigned long", 0)
            )
        end
        C.close(state.power_fd)
        state.power_fd = -1
        state.power_grabbed = false
    end

    os.remove(opts.active_file)
    appendCommand("CONTROLLER_STOPPED")
end

local function main()
    os.remove(opts.stop_file)
    writeFile(opts.active_file, tostring(os.time()) .. "\n")

    local fd = C.open(opts.power, bit.bor(O_RDONLY, O_NONBLOCK))
    if fd < 0 then
        error("Falha ao abrir " .. opts.power .. ": " .. errorText())
    end
    state.power_fd = fd

    local ok, err = setGrab(state.power_fd, true)
    if not ok then
        error("EVIOCGRAB no botão falhou: " .. err)
    end
    state.power_grabbed = true

    print("Physical power-button controller started.")
    print("Device: " .. opts.power .. "; KEY_POWER=" .. opts.keycode)
    print("Map: click=NEXT; double-click=PREV; triple-click=TOUCH_TOGGLE")

    local pollfds = ffi.new("struct pollfd[1]")
    pollfds[0].fd = state.power_fd
    pollfds[0].events = POLLIN

    local event_buffer = ffi.new("struct input_event[1]")
    local event_size = ffi.sizeof(event_buffer[0])

    local pressed_at = nil
    local click_count = 0
    local click_deadline = 0
    local triple_click_cooldown_until = 0
    local started_at = now()
    local next_heartbeat = started_at + 1

    local function dispatchClicks()
        local count = click_count
        click_count = 0
        click_deadline = 0

        if count == 1 then
            appendCommand("NEXT")
        elseif count == 2 then
            appendCommand("PREV")
        end
    end

    local function handleEvent(event)
        local event_type = tonumber(event.type)
        local code = tonumber(event.code)
        local value = tonumber(event.value)

        if event_type ~= EV_KEY or code ~= opts.keycode then
            return nil
        end

        if value == 1 then
            pressed_at = now()
            return nil
        end

        if value ~= 0 then
            return nil
        end

        if not pressed_at then
            return nil
        end

        local released_at = now()
        local duration = released_at - pressed_at
        pressed_at = nil

        print(string.format("Botão: %.3f s", duration))

        if duration <= opts.short_max then
            if released_at < triple_click_cooldown_until then
                return nil
            end

            click_count = click_count + 1

            if click_count == 3 then
                click_count = 0
                click_deadline = 0
                triple_click_cooldown_until =
                    released_at + opts.click_window
                appendCommand("TOUCH_TOGGLE")
            else
                click_deadline = released_at + opts.click_window
            end
        else
            -- Long presses are deliberately ignored. The touchscreen is
            -- toggled exclusively by a triple-click sequence.
            click_count = 0
            click_deadline = 0
        end

        return nil
    end

    while true do
        local current = now()

        if opts.timeout > 0 and current - started_at >= opts.timeout then
            print("Watchdog temporal atingido.")
            break
        end

        if current >= next_heartbeat then
            writeFile(opts.active_file, tostring(os.time()) .. "\n")
            next_heartbeat = current + 1

            local host_epoch = readEpoch(opts.host_heartbeat)
            if not host_epoch
                    or math.abs(os.time() - host_epoch) > opts.host_timeout then
                print("Heartbeat do KOReader ausente; encerrando.")
                break
            end
        end

        if fileExists(opts.stop_file) then
            print("Solicitação de parada recebida.")
            break
        end

        if click_count > 0
                and not pressed_at
                and current >= click_deadline then
            dispatchClicks()
        end

        local wait_ms = 100
        if click_count > 0 and not pressed_at then
            wait_ms = math.max(
                1,
                math.min(
                    wait_ms,
                    math.floor((click_deadline - current) * 1000)
                )
            )
        end

        local result = C.poll(pollfds, 1, wait_ms)
        if result < 0 then
            error("poll falhou: " .. errorText())
        end

        if result > 0
                and bit.band(pollfds[0].revents, POLLIN) ~= 0 then
            while true do
                local bytes = C.read(
                    state.power_fd,
                    event_buffer,
                    event_size
                )

                if bytes == event_size then
                    handleEvent(event_buffer[0])
                elseif bytes < 0 and ffi.errno() == EAGAIN then
                    break
                else
                    break
                end
            end
        end
    end

    if click_count > 0 then
        dispatchClicks()
    end

    return EXIT_OK
end

local ok, result = xpcall(main, debug.traceback)
cleanup()
os.remove(opts.stop_file)

if not ok then
    io.stderr:write(tostring(result) .. "\n")
    os.exit(1)
end

os.exit(tonumber(result) or EXIT_OK)
