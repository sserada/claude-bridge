#!/usr/bin/env bash
# auto.sh — Automatic sync via cron
set -euo pipefail

# Source dependencies
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

AUTO_LOG="${CLAUDE_BRIDGE_DIR}/auto-sync.log"
CRON_MARKER="# claude-bridge auto-sync"

parse_interval() {
    local input="$1"
    local minutes

    if [[ "${input}" =~ ^([0-9]+)m$ ]]; then
        minutes="${BASH_REMATCH[1]}"
    elif [[ "${input}" =~ ^([0-9]+)h$ ]]; then
        minutes=$(( ${BASH_REMATCH[1]} * 60 ))
    elif [[ "${input}" =~ ^([0-9]+)$ ]]; then
        minutes="${input}"
    else
        printf "Error: invalid interval '%s'. Use format: 30m, 1h, or minutes.\n" "${input}" >&2
        return 1
    fi

    if [[ "${minutes}" -lt 1 ]]; then
        printf "Error: interval must be at least 1 minute.\n" >&2
        return 1
    fi

    printf "%s" "${minutes}"
}

get_cron_schedule() {
    local minutes="$1"

    if [[ "${minutes}" -lt 60 ]]; then
        printf "*/%d * * * *" "${minutes}"
    else
        local hours=$(( minutes / 60 ))
        printf "0 */%d * * *" "${hours}"
    fi
}

get_bridge_path() {
    local bin_path
    bin_path="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)/claude-bridge"
    printf "%s" "${bin_path}"
}

auto_on() {
    local interval="${1:-30m}"
    local minutes
    minutes=$(parse_interval "${interval}") || return 1

    local schedule
    schedule=$(get_cron_schedule "${minutes}")
    local bridge_path
    bridge_path=$(get_bridge_path)

    # Build cron command: only push if Claude is not running
    local cron_cmd="${schedule} ${bridge_path} push --force >> ${AUTO_LOG} 2>&1 ${CRON_MARKER}"

    # Remove existing claude-bridge cron entry if any
    local current_cron
    current_cron=$(crontab -l 2>/dev/null || true)
    local new_cron
    new_cron=$(printf "%s" "${current_cron}" | grep -v "${CRON_MARKER}" || true)

    # Add new entry
    if [[ -n "${new_cron}" ]]; then
        printf "%s\n%s\n" "${new_cron}" "${cron_cmd}" | crontab -
    else
        printf "%s\n" "${cron_cmd}" | crontab -
    fi

    printf "Auto-sync enabled.\n"
    printf "  Schedule: every %d minute(s) (%s)\n" "${minutes}" "${schedule}"
    printf "  Command:  %s push --force\n" "${bridge_path}"
    printf "  Log:      %s\n" "${AUTO_LOG}"
}

auto_off() {
    local current_cron
    current_cron=$(crontab -l 2>/dev/null || true)

    if ! printf "%s" "${current_cron}" | grep -q "${CRON_MARKER}"; then
        printf "Auto-sync is not enabled.\n"
        return 0
    fi

    local new_cron
    new_cron=$(printf "%s" "${current_cron}" | grep -v "${CRON_MARKER}" || true)

    if [[ -z "${new_cron}" ]]; then
        crontab -r 2>/dev/null || true
    else
        printf "%s\n" "${new_cron}" | crontab -
    fi

    printf "Auto-sync disabled.\n"
}

auto_status() {
    local current_cron
    current_cron=$(crontab -l 2>/dev/null || true)
    local cron_entry
    cron_entry=$(printf "%s" "${current_cron}" | grep "${CRON_MARKER}" || true)

    if [[ -z "${cron_entry}" ]]; then
        printf "Auto-sync: disabled\n"
    else
        printf "Auto-sync: enabled\n"
        printf "  Cron entry: %s\n" "${cron_entry%${CRON_MARKER}}"

        if [[ -f "${AUTO_LOG}" ]]; then
            local last_line
            last_line=$(tail -1 "${AUTO_LOG}" 2>/dev/null || true)
            if [[ -n "${last_line}" ]]; then
                printf "  Last log:   %s\n" "${last_line}"
            fi
            local log_size
            log_size=$(wc -l < "${AUTO_LOG}" | tr -d ' ')
            printf "  Log lines:  %s (%s)\n" "${log_size}" "${AUTO_LOG}"
        else
            printf "  Log:        (no runs yet)\n"
        fi
    fi
}

cmd_auto() {
    if [[ $# -eq 0 ]]; then
        auto_status
        return 0
    fi

    local subcmd="$1"
    shift

    case "${subcmd}" in
        on)
            auto_on "${1:-30m}"
            ;;
        off)
            auto_off
            ;;
        status)
            auto_status
            ;;
        *)
            printf "Usage: claude-bridge auto [on [interval] | off | status]\n" >&2
            printf "\n" >&2
            printf "  on [interval]  Enable auto-sync (default: 30m)\n" >&2
            printf "  off            Disable auto-sync\n" >&2
            printf "  status         Show auto-sync status\n" >&2
            printf "\n" >&2
            printf "Interval format: 30m, 1h, or minutes (e.g., 15)\n" >&2
            return 1
            ;;
    esac
}
