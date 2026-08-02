#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Carlos Cezar

# Gerenciador do controlador do botão físico.
# Chamado pelo menu do plugin TouchLockButtons.

PLUGIN_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)"
LUAJIT="/mnt/us/koreader/luajit"
DAEMON="$PLUGIN_DIR/pw4-powerbutton.lua"

PID_FILE="/tmp/touchlockbuttons-power.pid"
LOCK_DIR="/tmp/touchlockbuttons-power.lock"
CMD_FILE="/tmp/touchlockbuttons-power.cmd"
STOP_FILE="/tmp/touchlockbuttons-power.stop"
ACTIVE_FILE="/tmp/touchlockbuttons-power.active"
HOST_HEARTBEAT="/tmp/touchlockbuttons-koreader.heartbeat"
LOG_FILE="/tmp/touchlockbuttons-power.log"
STATE_FILE="/tmp/touchlockbuttons-power.state"

POWERD="com.lab126.powerd"

controller_alive()
{
    [ -s "$PID_FILE" ] || return 1
    WRAPPER_PID="$(awk '{ print $1 }' "$PID_FILE" 2>/dev/null)"
    [ -n "$WRAPPER_PID" ] || return 1
    kill -0 "$WRAPPER_PID" 2>/dev/null
}

start_controller()
{
    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        exit 0
    fi
    trap 'rmdir "$LOCK_DIR" 2>/dev/null' 0

    if controller_alive; then
        exit 0
    fi

    rm -f "$PID_FILE" "$STOP_FILE" "$ACTIVE_FILE" "$CMD_FILE"

    "$0" run "$@" >>"$LOG_FILE" 2>&1 </dev/null &
    START_PID=$!

    # O processo run substitui este valor por "wrapper child" ao iniciar o
    # LuaJIT. Este registro provisório já evita um segundo start simultâneo.
    echo "$START_PID" > "$PID_FILE"

    exit 0
}

stop_controller()
{
    touch "$STOP_FILE"

    COUNT=0
    while controller_alive && [ "$COUNT" -lt 40 ]; do
        sleep 0.1
        COUNT=$((COUNT + 1))
    done

    return 0
}

sleep_controller()
{
    stop_controller
    sleep 0.4

    # Guarantee that the screensaver inhibitor is restored even if the
    # controller wrapper took longer than expected to finish its cleanup.
    OLD=0
    if [ -s "$STATE_FILE" ]; then
        SAVED="$(cat "$STATE_FILE" 2>/dev/null)"
        case "$SAVED" in
            0|1) OLD="$SAVED" ;;
        esac
    fi
    lipc-set-prop -i "$POWERD" preventScreenSaver "$OLD" \
        >/dev/null 2>&1

    if ! lipc-set-prop -i "$POWERD" powerButton 1 >/dev/null 2>&1; then
        powerd_test -p >/dev/null 2>&1
    fi
    return 0
}

run_controller()
{
    OLD="$(lipc-get-prop -i "$POWERD" preventScreenSaver 2>/dev/null)"
    case "$OLD" in
        0|1) ;;
        *) OLD=0 ;;
    esac
    echo "$OLD" > "$STATE_FILE"

    CHILD_PID=""
    WATCHDOG_PID=""
    CLEANED=0

    cleanup()
    {
        [ "$CLEANED" -eq 0 ] || return
        CLEANED=1

        if [ -n "$WATCHDOG_PID" ]; then
            kill "$WATCHDOG_PID" 2>/dev/null
        fi

        if [ -n "$CHILD_PID" ]; then
            kill "$CHILD_PID" 2>/dev/null
        fi

        lipc-set-prop -i "$POWERD" preventScreenSaver "$OLD" \
            >/dev/null 2>&1

        rm -f "$PID_FILE" "$ACTIVE_FILE" "$STOP_FILE" "$STATE_FILE"
    }

    trap 'cleanup; exit 130' 1 2 15
    trap 'cleanup' 0

    lipc-set-prop -i "$POWERD" preventScreenSaver 1 \
        >/dev/null 2>&1 || exit 1

    "$LUAJIT" "$DAEMON" \
        --power /dev/input/event1 \
        --keycode 116 \
        --timeout 0 \
        --cmd-file "$CMD_FILE" \
        --stop-file "$STOP_FILE" \
        --active-file "$ACTIVE_FILE" \
        --host-heartbeat "$HOST_HEARTBEAT" \
        "$@" &
    CHILD_PID=$!

    echo "$$ $CHILD_PID" > "$PID_FILE"

    # Caso este wrapper seja morto com SIGKILL, restaura o powerd e encerra
    # o LuaJIT assim que detectar o desaparecimento do processo-pai.
    (
        PARENT_PID=$$
        while kill -0 "$PARENT_PID" 2>/dev/null; do
            sleep 2
        done
        kill "$CHILD_PID" 2>/dev/null
        lipc-set-prop -i "$POWERD" preventScreenSaver "$OLD" \
            >/dev/null 2>&1
    ) &
    WATCHDOG_PID=$!

    wait "$CHILD_PID"
    CHILD_PID=""

    cleanup
    trap - 0 1 2 15
    exit 0
}

case "$1" in
    start)
        shift
        start_controller "$@"
        ;;
    stop)
        stop_controller
        exit 0
        ;;
    sleep)
        sleep_controller
        exit 0
        ;;
    status)
        if controller_alive; then
            echo active
            exit 0
        fi
        echo inactive
        exit 1
        ;;
    run)
        shift
        run_controller "$@"
        ;;
    *)
        echo "Usage: $0 {start|stop|sleep|status}" >&2
        exit 2
        ;;
esac
