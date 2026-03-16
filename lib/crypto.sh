#!/usr/bin/env bash
# crypto.sh — age encryption/decryption helpers for claude-bridge
set -euo pipefail

# Source config if not already loaded
if ! declare -f config_get &>/dev/null; then
    source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
fi

check_age_installed() {
    if ! command -v age &>/dev/null; then
        printf "Error: 'age' is not installed.\n" >&2
        printf "Install it with:\n" >&2
        printf "  macOS:  brew install age\n" >&2
        printf "  Linux:  apt install age  (or download from https://github.com/FiloSottile/age)\n" >&2
        return 1
    fi
}

get_passphrase() {
    if [[ ! -f "${PASSPHRASE_FILE}" ]]; then
        printf "Error: passphrase not set. Run 'claude-bridge init' first.\n" >&2
        return 1
    fi
    cat "${PASSPHRASE_FILE}"
}

set_passphrase() {
    local passphrase="$1"
    ensure_config_dir
    printf "%s" "${passphrase}" > "${PASSPHRASE_FILE}"
    chmod 600 "${PASSPHRASE_FILE}"
}

encrypt_file() {
    local input="$1"
    local output="$2"

    check_age_installed || return 1

    local passphrase
    passphrase=$(get_passphrase) || return 1

    # Create output directory if needed
    mkdir -p "$(dirname "${output}")"

    age --encrypt --passphrase <<< "${passphrase}" < "${input}" > "${output}" 2>/dev/null
}

decrypt_file() {
    local input="$1"
    local output="$2"

    check_age_installed || return 1

    local passphrase
    passphrase=$(get_passphrase) || return 1

    # Create output directory if needed
    mkdir -p "$(dirname "${output}")"

    age --decrypt --passphrase <<< "${passphrase}" < "${input}" > "${output}" 2>/dev/null
}

file_hash() {
    local filepath="$1"
    if command -v sha256sum &>/dev/null; then
        sha256sum "${filepath}" | cut -d' ' -f1
    else
        # macOS fallback
        shasum -a 256 "${filepath}" | cut -d' ' -f1
    fi
}
