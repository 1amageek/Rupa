#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 3 || "$2" != "--" ]]; then
    echo "usage: $0 <seconds: 1...120> -- <command> [arguments...]" >&2
    exit 64
fi

timeout_seconds="$1"
shift 2

if ! [[ "$timeout_seconds" =~ ^[0-9]+$ ]] || (( timeout_seconds < 1 || timeout_seconds > 120 )); then
    echo "timeout must be an integer from 1 through 120 seconds" >&2
    exit 64
fi

terminate_tree() {
    local parent_pid="$1"
    local child_pid
    while read -r child_pid; do
        [[ -n "$child_pid" ]] || continue
        terminate_tree "$child_pid"
    done < <(pgrep -P "$parent_pid" 2>/dev/null || true)
    kill -TERM "$parent_pid" 2>/dev/null || true
}

"$@" &
command_pid=$!
deadline=$(( $(date +%s) + timeout_seconds ))

while kill -0 "$command_pid" 2>/dev/null; do
    if (( $(date +%s) >= deadline )); then
        echo "command exceeded ${timeout_seconds}s; terminating process tree" >&2
        terminate_tree "$command_pid"
        sleep 1
        kill -KILL "$command_pid" 2>/dev/null || true
        wait "$command_pid" 2>/dev/null || true
        exit 124
    fi
    sleep 1
done

wait "$command_pid"
