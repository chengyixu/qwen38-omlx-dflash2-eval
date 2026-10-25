#!/bin/bash
# Single Desktop controller for local inference runtimes.
# Starts one selected runtime at a time and clears competing model servers.
set -euo pipefail

PORT=7870
HOST="127.0.0.1"
BASE_URL="http://${HOST}:${PORT}"
LABEL="local.omlx.qwen38-dflash2"
PLIST="${HOME}/Library/LaunchAgents/${OLD_LABEL:-local.llamacpp.qwen38-dflash2}.plist"
LOG_DIR="${HOME}/Library/Logs/LocalLLM"
LOG_FILE="${LOG_DIR}/qwen38-omlx-dflash2.log"
DEPLOYMENT_ROOT="${HOME}/Models/qwen38-omlx-dflash2"
MODEL_DIR="${HOME}/Models/mlx"
MODEL_ID="Qwen3.8-27B-4bit"
API_KEY="2015Caole!"
APP_RES="/Applications/oMLX.app/Contents/Resources"
ORNITH_CONTROLLER="${LOCAL_LLM_ORNITH_CONTROLLER:-${HOME}/Models/ornith-256k/deploy/ornith-local-model.command}"
H3_CONTROLLER="${LOCAL_LLM_H3_CONTROLLER:-${HOME}/Models/minimax-h3-mlx/deploy-m4max-64gb.sh}"
H3_ROOT="${LOCAL_LLM_H3_ROOT:-/Volumes/Outlier/Models/MiniMax-H3}"
MENU_MODE=0
MENU_TARGET=""
MENU_ACTION=""

server_pids() {
    pgrep -f "omlx.cli serve.*--port ${PORT}" 2>/dev/null || true
}

is_running() {
    [ -n "$(server_pids)" ]
}

active_model_id() {
    curl -fsS --max-time 3 -H "Authorization: Bearer ${API_KEY}" "${BASE_URL}/v1/models" 2>/dev/null \
        | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["data"][0]["id"] if d.get("data") else "")' 2>/dev/null || true
}

status() {
    local pid
    pid=$(lsof -ti ":${PORT}" 2>/dev/null | head -n1 || true)
    if [ -z "$pid" ] && ! is_running; then
        printf 'STOPPED: port %s is free\n' "$PORT"
        return
    fi
    local model_id health
    model_id=$(active_model_id)
    health=$(curl -fsS --max-time 3 "${BASE_URL}/health" 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("status",""))' 2>/dev/null || true)
    if [ "$health" = "healthy" ]; then
        printf 'RUNNING (ready): %s on %s (PID %s)\n' "${model_id:-starting}" "$BASE_URL" "$pid"
    else
        printf 'STARTING: server up at %s but model still loading (PID %s)\n' "$BASE_URL" "$pid"
    fi
}

sync_provider() {
    local provider_json="${HOME}/OWLSpace/provider.json"
    local provider_env="${HOME}/OWLSpace/provider.env"

    if [ -f "$provider_json" ]; then
        MODEL_ID="$MODEL_ID" python3 - "$provider_json" <<'PY'
import json, os, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as file:
    provider = json.load(file)
provider["active_id"] = "builtin:local:http://127.0.0.1:7870"
for entry in provider.get("providers", []):
    if entry.get("label") == "local":
        entry["base_url"] = "http://127.0.0.1:7870"
        entry["group"] = os.environ["MODEL_ID"]
        entry["api_key"] = os.environ.get("OMLX_API_KEY", "none")
local_provider = provider.get("local_provider")
if isinstance(local_provider, dict):
    local_provider["baseURL"] = "http://127.0.0.1:7870"
    local_provider["model"] = os.environ["MODEL_ID"]
with open(path, "w", encoding="utf-8") as file:
    json.dump(provider, file, indent=2)
    file.write("\n")
PY
    fi

    cat > "$provider_env" <<EOF
# OWLSpace provider: local Qwen3.8-27B 4-bit + DFlash2 via oMLX (z-lab fork)
unset ANTHROPIC_AUTH_TOKEN
export CLAUDE_CODE_DISABLE_1M_CONTEXT=1
export CLAUDE_CODE_AUTO_COMPACT_WINDOW=45000
export OMLX_API_KEY='${API_KEY}'
export ANTHROPIC_BASE_URL='http://127.0.0.1:7870'
export ANTHROPIC_API_KEY='${API_KEY}'
export ANTHROPIC_MODEL='${MODEL_ID}'
EOF
}

stop() {
    launchctl bootout "gui/$(id -u)/${OLD_LABEL:-local.llamacpp.qwen38-dflash2}" 2>/dev/null || true
    launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
    local pids
    pids=$(server_pids)
    if [ -n "$pids" ]; then
        kill -TERM $pids 2>/dev/null || true
        for _ in {1..30}; do
            [ -z "$(server_pids)" ] && break
            sleep 1
        done
    fi
    # last-resort: free the port
    local pid
    pid=$(lsof -ti ":${PORT}" 2>/dev/null | head -n1 || true)
    if [ -n "$pid" ] && ps -p "$pid" -o command= | grep -q "omlx"; then
        kill -TERM "$pid" 2>/dev/null || true
        sleep 3
    fi
}

write_plist() {
    mkdir -p "$LOG_DIR"
    cat > "${HOME}/Library/LaunchAgents/${LABEL}.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${APP_RES}/Python/cpython-3.11/bin/python3.11</string>
    <string>-m</string>
    <string>omlx.cli</string>
    <string>serve</string>
    <string>--model-dir</string>
    <string>${MODEL_DIR}</string>
    <string>--host</string>
    <string>${HOST}</string>
    <string>--port</string>
    <string>${PORT}</string>
    <string>--log-level</string>
    <string>info</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${APP_RES}</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PYTHONPATH</key>
    <string>${APP_RES}:${APP_RES}/Python/framework-mlx-base/lib/python3.11/site-packages:${APP_RES}/Python/cpython-3.11/lib/python3.11/site-packages</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${LOG_FILE}</string>
  <key>StandardErrorPath</key>
  <string>${LOG_FILE}</string>
</dict>
</plist>
EOF
    plutil -lint "${HOME}/Library/LaunchAgents/${LABEL}.plist" >/dev/null
}

warm_model() {
    curl -fsS --max-time 900 -H "Authorization: Bearer ${API_KEY}" \
        -H "Content-Type: application/json" \
        "${BASE_URL}/v1/chat/completions" \
        -d "{\"model\":\"${MODEL_ID}\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":8,\"temperature\":0}" \
        >/dev/null
}

start() {
    stop
    write_plist
    launchctl bootstrap "gui/$(id -u)" "${HOME}/Library/LaunchAgents/${LABEL}.plist" || true

    printf 'Loading Qwen3.8-27B 4-bit + DFlash2'
    for _ in {1..120}; do
        if [ "$(active_model_id)" = "$MODEL_ID" ] || lsof -ti ":${PORT}" >/dev/null 2>&1; then
            printf '\n'
            break
        fi
        printf '.'
        sleep 1
    done
    warm_model
    sync_provider
    status
}

test_api() {
    curl -fsS --max-time 600 -H "Authorization: Bearer ${API_KEY}" \
        -H "Content-Type: application/json" \
        "${BASE_URL}/v1/chat/completions" \
        -d "{\"model\":\"${MODEL_ID}\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: DFlash2 is ready\"}],\"temperature\":0,\"max_tokens\":300}" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["choices"][0]["message"]["content"][-200:])'
}

qwen_status() {
    printf 'Qwen3.8-27B + DFlash2\n'
    status
}

qwen_logs() {
    tail -n 100 -f "$LOG_FILE"
}

require_ornith_controller() {
    if [[ ! -x "$ORNITH_CONTROLLER" ]]; then
        printf 'Ornith controller is unavailable: %s\n' "$ORNITH_CONTROLLER" >&2
        return 1
    fi
}

local_model_server_pids() {
    {
        pgrep -x llama-server 2>/dev/null || true
        pgrep -x omlx-server 2>/dev/null || true
        pgrep -f '[o]mlx\.cli[[:space:]]+serve' 2>/dev/null || true
    } | awk 'NF && !seen[$1]++ { print $1 }'
}

stop_competing_local_servers() {
    local pids
    pids="$(local_model_server_pids)"
    [[ -z "$pids" ]] && return 0

    printf 'Stopping existing local inference server process(es): %s\n' "$pids"
    kill -TERM $pids 2>/dev/null || true
    for _ in {1..20}; do
        [[ -z "$(local_model_server_pids)" ]] && return 0
        sleep 1
    done

    pids="$(local_model_server_pids)"
    if [[ -n "$pids" ]]; then
        printf 'Force-stopping remaining local inference server process(es): %s\n' "$pids"
        kill -KILL $pids 2>/dev/null || true
    fi
}

stop_all_local_model_servers() {
    # Stop known LaunchAgents first, then clear any unmanaged listener such as
    # an app-owned llama-server instance. This is deliberately model-agnostic.
    stop
    if [[ -x "$ORNITH_CONTROLLER" ]]; then
        "$ORNITH_CONTROLLER" stop >/dev/null 2>&1 || true
    fi
    stop_competing_local_servers
}

run_ornith() {
    require_ornith_controller
    local dry_run=0 action
    if [[ "${1:-}" == "--dry-run" ]]; then
        dry_run=1
        action="${2:-status}"
    else
        action="${1:-status}"
    fi
    if [[ "$action" == "start" || "$action" == "restart" ]]; then
        if ((dry_run)); then
            printf 'Dry run: competing local model servers would be stopped before Ornith starts.\n'
        else
            stop_all_local_model_servers
        fi
    fi
    "$ORNITH_CONTROLLER" "$@"
}

all_status() {
    qwen_status
    printf '\nOrnith 1.5 35B\n'
    run_ornith status
}

all_start() {
    printf 'Refusing to start both local models together: they compete for Metal memory.\n' >&2
    printf 'Choose qwen start or ornith start; the selected start path stops the other managed model first.\n' >&2
    return 2
}

all_stop() {
    stop_all_local_model_servers
    all_status
}

h3_ready() {
    [[ -x "$H3_CONTROLLER" ]] && [[ -f "$H3_ROOT/FL2VA/FL2VA/model_index.json" ]] && \
        [[ -f "$H3_ROOT/MiniMax-H3-MLX-4bit/quant_config.json" ]]
}

h3_status() {
    if ! h3_ready; then
        printf 'MiniMax H3: NOT READY (controller or model artifacts missing)\n' >&2
        return 1
    fi
    local latest
    latest=$(find "$H3_ROOT/outputs" -maxdepth 1 -type f -name '*.mp4' ! -name '._*' -print 2>/dev/null | sort | tail -n1 || true)
    printf 'MiniMax H3 — local staged MLX video+audio generator\n'
    printf '  controller: %s\n  artifacts: %s\n' "$H3_CONTROLLER" "$H3_ROOT"
    if [[ -n "$latest" ]]; then
        printf '  latest output: %s\n' "$latest"
    else
        printf '  latest output: none\n'
    fi
}

h3_test() {
    h3_ready
    "$H3_CONTROLLER" --dry-run 'A red fox walks through a misty forest at dawn.'
}

h3_canary() {
    h3_ready
    "$H3_CONTROLLER" -d 5 -s 2 --height 256 --width 256 --seed 7 \
        'A red fox walks through a misty forest at dawn. Natural birdsong and wind.'
}

h3_generate() {
    h3_ready
    if [[ "$#" -eq 0 ]]; then
        printf 'Usage: %s h3 generate <prompt>\n' "$(basename "$0")" >&2
        return 2
    fi
    "$H3_CONTROLLER" -d 5 -s 8 "$*"
}

run_h3() {
    local action="${1:-status}"
    shift || true
    case "$action" in
        status) h3_status ;;
        test) h3_test ;;
        canary) h3_canary ;;
        generate) h3_generate "$@" ;;
        -h|--help|help) usage ;;
        *) usage; return 2 ;;
    esac
}

all_logs() {
    printf '%s\n' '--- Qwen3.8-27B + DFlash2 ---'
    if [[ -f "$LOG_FILE" ]]; then
        tail -n 100 "$LOG_FILE"
    else
        printf 'not found: %s\n' "$LOG_FILE"
    fi
    printf '\n%s\n' '--- Ornith 1.5 35B ---'
    run_ornith logs
}

run_qwen() {
    local action="${1:-status}"
    case "$action" in
        start) stop_all_local_model_servers; start ;;
        stop) stop; qwen_status ;;
        restart) stop_all_local_model_servers; start ;;
        status) qwen_status ;;
        test) test_api ;;
        logs) qwen_logs ;;
        -h|--help|help) usage ;;
        *) usage; return 2 ;;
    esac
}

run_all() {
    local action="${1:-status}"
    case "$action" in
        start) all_start ;;
        stop) all_stop ;;
        status) all_status ;;
        logs) all_logs ;;
        *) usage; return 2 ;;
    esac
}

show_menu() {
    cat <<'EOF'
Local model controller

Qwen3.8-27B + DFlash2
  1) start       2) stop       3) restart
  4) status      5) test       6) logs

Ornith 1.5 35B
  7) start       8) stop       9) restart
 10) status     11) test      12) logs

MiniMax H3 (on-demand video + stereo-audio generator)
 13) status     14) validate  15) canary render

Both LLM servers
 16) status     17) stop      18) logs

q) quit
EOF

    read -r -p 'Choose an action: ' choice
    case "$choice" in
        1) MENU_TARGET=qwen; MENU_ACTION=start ;;
        2) MENU_TARGET=qwen; MENU_ACTION=stop ;;
        3) MENU_TARGET=qwen; MENU_ACTION=restart ;;
        4) MENU_TARGET=qwen; MENU_ACTION=status ;;
        5) MENU_TARGET=qwen; MENU_ACTION=test ;;
        6) MENU_TARGET=qwen; MENU_ACTION=logs ;;
        7) MENU_TARGET=ornith; MENU_ACTION=start ;;
        8) MENU_TARGET=ornith; MENU_ACTION=stop ;;
        9) MENU_TARGET=ornith; MENU_ACTION=restart ;;
        10) MENU_TARGET=ornith; MENU_ACTION=status ;;
        11) MENU_TARGET=ornith; MENU_ACTION=test ;;
        12) MENU_TARGET=ornith; MENU_ACTION=logs ;;
        13) MENU_TARGET=h3; MENU_ACTION=status ;;
        14) MENU_TARGET=h3; MENU_ACTION=test ;;
        15) MENU_TARGET=h3; MENU_ACTION=canary ;;
        16) MENU_TARGET=all; MENU_ACTION=status ;;
        17) MENU_TARGET=all; MENU_ACTION=stop ;;
        18) MENU_TARGET=all; MENU_ACTION=logs ;;
        q|Q) exit 0 ;;
        *) printf 'Unknown choice: %s\n' "$choice" >&2; exit 2 ;;
    esac
}

finish_menu() {
    if ((MENU_MODE)); then
        printf '\nPress Return to close...'
        read -r
    fi
}

usage() {
    cat <<EOF
Usage:
  $(basename "$0") [qwen] <start|stop|restart|status|test|logs>
  $(basename "$0") ornith [--dry-run] <start|stop|restart|status|test|logs>
  $(basename "$0") h3 <status|test|canary|generate <prompt>>
  $(basename "$0") all <status|stop|logs>

One Desktop controller for local models and media generation:
  Qwen3.8-27B + DFlash2: ${BASE_URL}/v1 (OpenAI + Anthropic compatible)
  Ornith 1.5 35B:        http://127.0.0.1:7871/v1 (+ Gemini bridge on :7872)
  MiniMax H3:             on-demand local MLX video + synchronized stereo-audio generation

With no arguments in a terminal, opens the model/action menu. For scripts,
an unqualified command remains a Qwen command for backward compatibility.
Starting Qwen or Ornith stops every other local inference server first;
concurrent start is intentionally refused because the models compete for unified
Metal memory. H3 is not a chat server and therefore never appears as an LLM API provider.
EOF
}

if [[ "$#" -eq 0 ]]; then
    if [[ -t 0 ]]; then
        MENU_MODE=1
        show_menu
        set -- "$MENU_TARGET" "$MENU_ACTION"
    else
        set -- qwen status
    fi
fi

case "$1" in
    qwen)
        shift
        run_qwen "${1:-status}"
        ;;
    ornith)
        shift
        run_ornith "$@"
        ;;
    h3)
        shift
        run_h3 "$@"
        ;;
    all)
        shift
        run_all "${1:-status}"
        ;;
    start|stop|restart|status|test|logs|-h|--help|help)
        run_qwen "$1"
        ;;
    *)
        usage
        exit 2
        ;;
esac

finish_menu
