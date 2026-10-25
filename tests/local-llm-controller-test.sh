#!/bin/bash
# Contract checks for the one Desktop local-model controller.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTROLLER="${ROOT}/bin/local-llm.command"

assert_contains() {
    local haystack="$1"
    local needle="$2"
    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'expected output to contain %q; got:\n%s\n' "$needle" "$haystack" >&2
        exit 1
    fi
}

help_output="$("$CONTROLLER" --help)"
assert_contains "$help_output" 'ornith [--dry-run]'

controller_source="$(<"$CONTROLLER")"
assert_contains "$controller_source" 'local_model_server_pids'
assert_contains "$controller_source" 'kill -TERM $pids'
assert_contains "$controller_source" 'Starting Qwen or Ornith stops every other local inference server first'

# The Ornith controller already owns its dry-run contract. The unified entry
# point must forward it without changing any LaunchAgent state.
ornith_dry_run="$("$CONTROLLER" ornith --dry-run start)"
assert_contains "$ornith_dry_run" 'Dry run: competing local model servers would be stopped before Ornith starts.'
assert_contains "$ornith_dry_run" 'Dry run: start Ornith services in dependency order'

# These are read-only status paths and are safe against the live host.
qwen_status="$("$CONTROLLER" qwen status)"
assert_contains "$qwen_status" 'Qwen3.8-27B + DFlash2'

both_status="$("$CONTROLLER" all status)"
assert_contains "$both_status" 'Qwen3.8-27B + DFlash2'
assert_contains "$both_status" 'Ornith 1.5 35B'

ornith_status="$("$CONTROLLER" ornith status)"
assert_contains "$ornith_status" 'Ornith local model'
assert_contains "$ornith_status" 'overall'

both_status="$("$CONTROLLER" all status)"

printf 'local-llm controller contract: PASS\n'
