#!/usr/bin/env bash
# config.sh — Configuration management for claude-bridge
set -euo pipefail

readonly CLAUDE_BRIDGE_DIR="${HOME}/.claude-bridge"
readonly CONFIG_FILE="${CLAUDE_BRIDGE_DIR}/sync.conf"
readonly MANIFEST_FILE="${CLAUDE_BRIDGE_DIR}/manifest.json"
readonly PASSPHRASE_FILE="${CLAUDE_BRIDGE_DIR}/passphrase"
readonly CONFLICTS_DIR="${CLAUDE_BRIDGE_DIR}/conflicts"

# Default values
readonly DEFAULT_CLAUDE_DIR="${HOME}/.claude"
readonly DEFAULT_SYNC_TARGETS="projects,history,settings,claude_md"
readonly DEFAULT_COMMIT_PREFIX="sync"

ensure_config_dir() {
    if [[ ! -d "${CLAUDE_BRIDGE_DIR}" ]]; then
        mkdir -p "${CLAUDE_BRIDGE_DIR}"
        chmod 700 "${CLAUDE_BRIDGE_DIR}"
    fi
}

ensure_config_file() {
    ensure_config_dir
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        cat > "${CONFIG_FILE}" <<CONF
# claude-bridge configuration
MACHINE_NAME=$(hostname -s)
CLAUDE_DIR=${DEFAULT_CLAUDE_DIR}
SYNC_TARGETS=${DEFAULT_SYNC_TARGETS}
COMMIT_PREFIX=${DEFAULT_COMMIT_PREFIX}
CONF
    fi
}

config_get() {
    local key="$1"
    ensure_config_file

    local value
    value=$(grep -E "^${key}=" "${CONFIG_FILE}" 2>/dev/null | head -1 | cut -d'=' -f2-)

    if [[ -z "${value}" ]]; then
        # Return defaults for known keys
        case "${key}" in
            MACHINE_NAME) printf "%s" "$(hostname -s)" ;;
            CLAUDE_DIR) printf "%s" "${DEFAULT_CLAUDE_DIR}" ;;
            SYNC_TARGETS) printf "%s" "${DEFAULT_SYNC_TARGETS}" ;;
            COMMIT_PREFIX) printf "%s" "${DEFAULT_COMMIT_PREFIX}" ;;
            *) return 1 ;;
        esac
    else
        printf "%s" "${value}"
    fi
}

config_set() {
    local key="$1"
    local value="$2"
    ensure_config_file

    if grep -qE "^${key}=" "${CONFIG_FILE}" 2>/dev/null; then
        # Update existing key — use a temp file for portability
        local tmpfile
        tmpfile=$(mktemp)
        sed "s|^${key}=.*|${key}=${value}|" "${CONFIG_FILE}" > "${tmpfile}"
        mv "${tmpfile}" "${CONFIG_FILE}"
    else
        printf "%s=%s\n" "${key}" "${value}" >> "${CONFIG_FILE}"
    fi
}

config_list() {
    ensure_config_file
    printf "Configuration (%s):\n\n" "${CONFIG_FILE}"
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "${line}" =~ ^#.*$ || -z "${line}" ]] && continue
        printf "  %s\n" "${line}"
    done < "${CONFIG_FILE}"
}

get_claude_dir() {
    config_get "CLAUDE_DIR"
}

get_sync_targets() {
    local targets
    targets=$(config_get "SYNC_TARGETS")
    printf "%s" "${targets}"
}

get_repo_dir() {
    # The repo dir is where bin/claude-bridge lives (parent of bin/)
    if [[ -n "${SCRIPT_DIR:-}" ]]; then
        printf "%s" "${SCRIPT_DIR}"
    else
        printf "%s" "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    fi
}

cmd_config() {
    if [[ $# -eq 0 ]]; then
        config_list
        return 0
    fi

    local subcmd="$1"
    shift

    case "${subcmd}" in
        get)
            if [[ $# -lt 1 ]]; then
                printf "Usage: claude-bridge config get <key>\n" >&2
                return 1
            fi
            local val
            if val=$(config_get "$1"); then
                printf "%s\n" "${val}"
            else
                printf "Error: unknown config key '%s'\n" "$1" >&2
                return 1
            fi
            ;;
        set)
            if [[ $# -lt 2 ]]; then
                printf "Usage: claude-bridge config set <key> <value>\n" >&2
                return 1
            fi
            config_set "$1" "$2"
            printf "Set %s=%s\n" "$1" "$2"
            ;;
        *)
            printf "Usage: claude-bridge config [get <key> | set <key> <value>]\n" >&2
            return 1
            ;;
    esac
}
