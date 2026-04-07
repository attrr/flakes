#!/bin/bash
set -euo pipefail

# --- Configuration ---
LOG_LEVEL="${LOG_LEVEL:-info}"
PROXY_PORT="${PROXY_PORT:-1080}"
MODE="${MODE:-}"
WARP_STARTUP_TIMEOUT="${WARP_STARTUP_TIMEOUT:-120}"

# --- Globals ---
WARP_PID=""
SING_PID=""

# --- Helpers ---

log()   { echo "[$1] $2"; }
info()  { log "-" "$1"; }
ok()    { log "+" "$1"; }
err()   { log "!" "$1"; }
warp()  { warp-cli --accept-tos "$@" > /dev/null; }

cleanup() {
    err "Shutting down..."
    kill "$WARP_PID" "$SING_PID" 2>/dev/null || true
}

# --- Tokio Starvation Workaround ---
# On 1-core machines, warp-svc's Tokio runtime will only launch 1 worker thread.
# If a single task (like QUIC idle timeout) busy-loops, the whole daemon hangs
# and the watchdog eventually panics. By forcing 2 threads on 1-core systems,
# we allow the OS scheduler to preempt and keep the daemon responsive.
if [ "$(nproc)" -eq 1 ]; then
    info "Single-core system detected. Forcing TOKIO_WORKER_THREADS=2 to prevent starvation."
    export TOKIO_WORKER_THREADS="2"
fi

# --- Stages ---

init_dirs() {
    mkdir -p \
        /run/dbus \
        /var/run/cloudflare-warp \
        /var/log/cloudflare-warp \
        /var/lib/cloudflare-warp \
        /etc/sing-box
}

init_dbus() {
    dbus-uuidgen > /var/lib/dbus/machine-id
    dbus-daemon --config-file=/usr/share/dbus-1/system.conf --print-address --fork
}

start_warp() {
    info "Starting warp-svc..."

    if [ "$LOG_LEVEL" = "debug" ]; then
        info "Debug logging enabled"
        warp-svc 2>&1 &
    else
        warp-svc > >(grep --line-buffered -vE "INFO|DEBUG") 2>&1 &
    fi
    WARP_PID=$!
}

await_warp() {
    local elapsed=0

    while ! warp status > /dev/null 2>&1; do
        if ! kill -0 "$WARP_PID" 2>/dev/null; then
            err "warp-svc crashed during startup"
            exit 1
        fi
        if [ "$elapsed" -ge "$WARP_STARTUP_TIMEOUT" ]; then
            err "warp-svc failed to become ready within ${WARP_STARTUP_TIMEOUT}s"
            exit 1
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    ok "warp-svc is ready (took ~${elapsed}s)"
}

register_warp() {
    if [ -f /var/lib/cloudflare-warp/reg.json ]; then
        info "Already registered, skipping"
        return
    fi

    warp registration new && ok "Registered"

    if [ -n "${WARP_LICENSE_KEY:-}" ]; then
        info "Applying license key..."
        warp set-license "$WARP_LICENSE_KEY" && ok "License applied"
    fi
}

connect_warp() {
    [ "$MODE" = "proxy" ] && {
        warp set-proxy-port "$PROXY_PORT"
        warp set-mode proxy
        info "Proxy mode on port $PROXY_PORT"
    }

    warp dns log disable
    warp connect
    ok "WARP connected"
}

start_singbox() {
    if [ ! -f /etc/sing-box/config.json ]; then
        info "Generating sing-box config (port $PROXY_PORT)..."
        jq -n --argjson port "$PROXY_PORT" '{
            log:      { level: "error" },
            inbounds: [{
                type:        "shadowsocks",
                listen:      "0.0.0.0",
                listen_port: $port,
                method:      "none"
            }]
        }' > /etc/sing-box/config.json
    fi

    info "Starting sing-box..."
    sing-box run -C /etc/sing-box &
    SING_PID=$!
    ok "sing-box started"
}

await_exit() {
    ok "All services running — waiting for exit..."

    set +e
    wait -n
    local code=$?
    set -e
    err "A critical process died with exit code $code"
    exit "$code"
}

# --- Main ---

trap cleanup EXIT

init_dirs
init_dbus
start_warp
await_warp
register_warp
connect_warp
start_singbox
await_exit
