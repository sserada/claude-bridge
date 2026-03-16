#!/usr/bin/env bash
# init.sh — Initial setup for claude-bridge
set -euo pipefail

# Source dependencies
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/crypto.sh"

prompt_passphrase() {
    local passphrase passphrase_confirm

    printf "Enter a passphrase for encrypting your Claude data.\n" >&2
    printf "Use the SAME passphrase on all machines.\n\n" >&2

    # Read passphrase (hide input)
    printf "Passphrase: " >&2
    read -rs passphrase
    printf "\n" >&2

    if [[ -z "${passphrase}" ]]; then
        printf "Error: passphrase cannot be empty.\n" >&2
        return 1
    fi

    printf "Confirm passphrase: " >&2
    read -rs passphrase_confirm
    printf "\n" >&2

    if [[ "${passphrase}" != "${passphrase_confirm}" ]]; then
        printf "Error: passphrases do not match.\n" >&2
        return 1
    fi

    printf "%s" "${passphrase}"
}

create_initial_manifest() {
    local claude_dir
    claude_dir=$(get_claude_dir)

    if command -v jq &>/dev/null; then
        jq -n \
            --arg version "1" \
            --arg updated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            --arg machine "$(config_get MACHINE_NAME)" \
            '{version: ($version | tonumber), updated_at: $updated_at, machine: $machine, files: {}}' \
            > "${MANIFEST_FILE}"
    else
        cat > "${MANIFEST_FILE}" <<JSON
{
  "version": 1,
  "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "machine": "$(config_get MACHINE_NAME)",
  "files": {}
}
JSON
    fi
}

has_encrypted_data() {
    local repo_dir
    repo_dir=$(get_repo_dir)
    local encrypted_dir="${repo_dir}/encrypted"

    # Check if there are any files besides .gitkeep
    local count
    count=$(find "${encrypted_dir}" -type f ! -name ".gitkeep" 2>/dev/null | wc -l | tr -d ' ')
    [[ "${count}" -gt 0 ]]
}

cmd_init() {
    printf "Initializing claude-bridge...\n\n" >&2

    # Check if already initialized
    if [[ -f "${PASSPHRASE_FILE}" ]]; then
        printf "Warning: claude-bridge is already initialized.\n" >&2
        printf "Passphrase file exists at %s\n" "${PASSPHRASE_FILE}" >&2
        printf "To reinitialize, remove %s and run init again.\n" "${CLAUDE_BRIDGE_DIR}" >&2
        return 1
    fi

    check_age_installed || return 1

    # Ensure config directory and file
    ensure_config_dir
    ensure_config_file

    # Prompt for passphrase
    local passphrase
    passphrase=$(prompt_passphrase) || return 1
    set_passphrase "${passphrase}"
    printf "Passphrase saved.\n\n" >&2

    # Check if this repo already has encrypted data (joining existing)
    if has_encrypted_data; then
        printf "Existing encrypted data found in repository.\n" >&2
        printf "Pulling and decrypting data from remote...\n\n" >&2
        source "$(dirname "${BASH_SOURCE[0]}")/pull.sh"
        cmd_pull
    else
        printf "Fresh setup — no existing data found.\n" >&2

        local claude_dir
        claude_dir=$(get_claude_dir)

        if [[ -d "${claude_dir}" ]]; then
            printf "Found Claude directory at %s\n" "${claude_dir}" >&2
            create_initial_manifest
            printf "Initial manifest created.\n\n" >&2
            printf "Run 'claude-bridge push' to encrypt and sync your data.\n" >&2
        else
            printf "No Claude directory found at %s\n" "${claude_dir}" >&2
            printf "Claude Code will create it when you first use it.\n" >&2
            create_initial_manifest
            printf "Initial manifest created.\n" >&2
        fi
    fi

    printf "\nclaude-bridge initialized successfully!\n" >&2
    printf "Machine: %s\n" "$(config_get MACHINE_NAME)" >&2
    printf "Config:  %s\n" "${CONFIG_FILE}" >&2
}
