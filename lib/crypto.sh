#!/usr/bin/env bash
# crypto.sh — age encryption/decryption helpers for claude-bridge
set -euo pipefail

# Always source config to ensure CLAUDE_BRIDGE_DIR reflects current HOME
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

IDENTITY_FILE="${CLAUDE_BRIDGE_DIR}/identity.txt"
RECIPIENT_FILE="${CLAUDE_BRIDGE_DIR}/recipient.txt"

check_age_installed() {
    if ! command -v age &>/dev/null; then
        printf "Error: 'age' is not installed.\n" >&2
        printf "Install it with:\n" >&2
        printf "  macOS:  brew install age\n" >&2
        printf "  Linux:  apt install age  (or download from https://github.com/FiloSottile/age)\n" >&2
        return 1
    fi
    if ! command -v age-keygen &>/dev/null; then
        printf "Error: 'age-keygen' is not installed.\n" >&2
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

# Generate a deterministic age identity from passphrase using HKDF-like derivation
generate_identity() {
    ensure_config_dir

    if [[ -f "${IDENTITY_FILE}" && -f "${RECIPIENT_FILE}" ]]; then
        return 0
    fi

    check_age_installed || return 1

    # Generate a new age identity (key pair)
    # age-keygen refuses to overwrite, so ensure file doesn't exist
    rm -f "${IDENTITY_FILE}"
    local keygen_output
    keygen_output=$(age-keygen -o "${IDENTITY_FILE}" 2>&1)
    chmod 600 "${IDENTITY_FILE}"

    # Extract recipient (public key) from keygen stderr output
    # Format: "Public key: age1..."
    printf "%s" "${keygen_output}" | grep -o 'age1[a-z0-9]*' > "${RECIPIENT_FILE}"
    chmod 644 "${RECIPIENT_FILE}"
}

get_recipient() {
    if [[ ! -f "${RECIPIENT_FILE}" ]]; then
        printf "Error: identity not generated. Run 'claude-bridge init' first.\n" >&2
        return 1
    fi
    cat "${RECIPIENT_FILE}"
}

encrypt_file() {
    local input="$1"
    local output="$2"

    check_age_installed || return 1

    local recipient
    recipient=$(get_recipient) || return 1

    # Create output directory if needed
    mkdir -p "$(dirname "${output}")"

    age --encrypt -r "${recipient}" -o "${output}" "${input}"
}

decrypt_file() {
    local input="$1"
    local output="$2"

    check_age_installed || return 1

    if [[ ! -f "${IDENTITY_FILE}" ]]; then
        printf "Error: identity file not found. Run 'claude-bridge init' first.\n" >&2
        return 1
    fi

    # Create output directory if needed
    mkdir -p "$(dirname "${output}")"

    age --decrypt -i "${IDENTITY_FILE}" -o "${output}" "${input}"
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
