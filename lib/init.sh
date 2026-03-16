#!/usr/bin/env bash
# init.sh — Initial setup for claude-bridge
set -euo pipefail

# Source dependencies
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/crypto.sh"

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
    count=$(find "${encrypted_dir}" -type f ! -name ".gitkeep" ! -name "manifest.json" 2>/dev/null | wc -l | tr -d ' ')
    [[ "${count}" -gt 0 ]]
}

import_identity() {
    printf "To sync with an existing setup, copy the identity file from your first machine.\n" >&2
    printf "On your first machine, run:\n\n" >&2
    printf "  cat ~/.claude-bridge/identity.txt\n\n" >&2
    printf "Then paste the entire contents here (ends with an empty line):\n" >&2

    local identity_content=""
    local line
    while IFS= read -r line; do
        [[ -z "${line}" ]] && break
        identity_content+="${line}"$'\n'
    done

    if [[ -z "${identity_content}" ]]; then
        printf "Error: no identity provided.\n" >&2
        return 1
    fi

    ensure_config_dir
    printf "%s" "${identity_content}" > "${IDENTITY_FILE}"
    chmod 600 "${IDENTITY_FILE}"

    # Extract recipient from identity file
    local recipient
    recipient=$(age-keygen -y "${IDENTITY_FILE}" 2>/dev/null)
    if [[ -z "${recipient}" ]]; then
        printf "Error: invalid identity file.\n" >&2
        rm -f "${IDENTITY_FILE}"
        return 1
    fi
    printf "%s" "${recipient}" > "${RECIPIENT_FILE}"

    printf "Identity imported successfully.\n" >&2
}

cmd_init() {
    printf "Initializing claude-bridge...\n\n" >&2

    # Check if already initialized
    if [[ -f "${IDENTITY_FILE}" ]]; then
        printf "Warning: claude-bridge is already initialized.\n" >&2
        printf "Identity file exists at %s\n" "${IDENTITY_FILE}" >&2
        printf "To reinitialize, remove %s and run init again.\n" "${CLAUDE_BRIDGE_DIR}" >&2
        return 1
    fi

    check_age_installed || return 1

    # Ensure config directory and file
    ensure_config_dir
    ensure_config_file

    # Check if this repo already has encrypted data (joining existing)
    if has_encrypted_data; then
        printf "Existing encrypted data found in repository.\n" >&2
        printf "This appears to be a second machine joining an existing sync.\n\n" >&2
        import_identity || return 1
        printf "\nPulling and decrypting data from remote...\n\n" >&2
        create_initial_manifest
        source "$(dirname "${BASH_SOURCE[0]}")/pull.sh"
        cmd_pull
    else
        printf "Fresh setup — generating new encryption key.\n" >&2
        generate_identity
        printf "Encryption key generated.\n" >&2
        printf "  Identity:  %s\n" "${IDENTITY_FILE}" >&2
        printf "  Recipient: %s\n\n" "$(get_recipient)" >&2

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
    printf "\nIMPORTANT: To set up additional machines, you will need the identity file:\n" >&2
    printf "  %s\n" "${IDENTITY_FILE}" >&2
    printf "Keep it safe — anyone with this file can decrypt your data.\n" >&2
}
