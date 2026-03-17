#!/usr/bin/env bash
# reset.sh — Reset claude-bridge to uninitialized state
set -euo pipefail

# Source dependencies
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

cmd_reset() {
    local force=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force | -f)
                force=true
                shift
                ;;
            *)
                printf "Unknown option: %s\n" "$1" >&2
                return 1
                ;;
        esac
    done

    if [[ ! -d "${CLAUDE_BRIDGE_DIR}" ]]; then
        printf "Nothing to reset. claude-bridge is not initialized.\n" >&2
        return 0
    fi

    # Confirmation prompt unless --force
    if [[ "${force}" != true ]]; then
        printf "This will remove all claude-bridge local configuration:\n\n" >&2
        printf "  %s\n" "${CLAUDE_BRIDGE_DIR}" >&2
        printf "\nThis includes:\n" >&2
        printf "  - Identity (encryption key pair)\n" >&2
        printf "  - Sync configuration\n" >&2
        printf "  - Manifest (sync state)\n" >&2
        printf "  - Path mappings\n" >&2
        printf "  - Auto-sync log\n" >&2
        printf "\nYour ~/.claude/ data and remote encrypted data are NOT affected.\n" >&2
        printf "\nAre you sure? [y/N] " >&2
        local answer
        read -r answer
        if [[ ! "${answer}" =~ ^[Yy]$ ]]; then
            printf "Cancelled.\n" >&2
            return 0
        fi
    fi

    # Disable auto-sync cron if active
    local cron_marker="# claude-bridge auto-sync"
    local current_cron
    current_cron=$(crontab -l 2>/dev/null || true)
    if printf "%s" "${current_cron}" | grep -q "${cron_marker}"; then
        local new_cron
        new_cron=$(printf "%s" "${current_cron}" | grep -v "${cron_marker}" || true)
        if [[ -z "${new_cron}" ]]; then
            crontab -r 2>/dev/null || true
        else
            printf "%s\n" "${new_cron}" | crontab -
        fi
        printf "Auto-sync cron job removed.\n" >&2
    fi

    rm -rf "${CLAUDE_BRIDGE_DIR}"
    printf "Reset complete. Run 'claude-bridge init' to set up again.\n" >&2
}
