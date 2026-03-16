#!/usr/bin/env bash
# path_resolver.sh — Cross-machine path remapping for claude-bridge
set -euo pipefail

# Source dependencies
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

readonly MAPPINGS_FILE="${CLAUDE_BRIDGE_DIR}/path_mappings"

ensure_mappings_file() {
    ensure_config_dir
    if [[ ! -f "${MAPPINGS_FILE}" ]]; then
        cat > "${MAPPINGS_FILE}" <<'HEADER'
# Path mappings for cross-machine sync
# Format: <source_path> = <destination_path>
HEADER
    fi
}

add_mapping() {
    local src="$1"
    local dst="$2"

    ensure_mappings_file

    # Remove trailing slashes
    src="${src%/}"
    dst="${dst%/}"

    # Check if mapping already exists for this source
    if grep -q "^${src} = " "${MAPPINGS_FILE}" 2>/dev/null; then
        # Update existing
        local tmpfile
        tmpfile=$(mktemp)
        sed "s|^${src} = .*|${src} = ${dst}|" "${MAPPINGS_FILE}" > "${tmpfile}"
        mv "${tmpfile}" "${MAPPINGS_FILE}"
        printf "Updated mapping: %s → %s\n" "${src}" "${dst}"
    else
        printf "%s = %s\n" "${src}" "${dst}" >> "${MAPPINGS_FILE}"
        printf "Added mapping: %s → %s\n" "${src}" "${dst}"
    fi
}

remove_mapping() {
    local src="$1"
    src="${src%/}"

    if [[ ! -f "${MAPPINGS_FILE}" ]]; then
        printf "No mappings configured.\n" >&2
        return 1
    fi

    if ! grep -q "^${src} = " "${MAPPINGS_FILE}" 2>/dev/null; then
        printf "No mapping found for: %s\n" "${src}" >&2
        return 1
    fi

    local tmpfile
    tmpfile=$(mktemp)
    grep -v "^${src} = " "${MAPPINGS_FILE}" > "${tmpfile}"
    mv "${tmpfile}" "${MAPPINGS_FILE}"
    printf "Removed mapping for: %s\n" "${src}"
}

list_mappings() {
    ensure_mappings_file

    local has_mappings=false
    printf "Path mappings (%s):\n\n" "${MAPPINGS_FILE}"

    while IFS= read -r line; do
        [[ "${line}" =~ ^#.*$ || -z "${line}" ]] && continue
        has_mappings=true
        local src dst
        src=$(printf "%s" "${line}" | cut -d'=' -f1 | sed 's/[[:space:]]*$//')
        dst=$(printf "%s" "${line}" | cut -d'=' -f2- | sed 's/^[[:space:]]*//')
        printf "  %s → %s\n" "${src}" "${dst}"
    done < "${MAPPINGS_FILE}"

    if [[ "${has_mappings}" == false ]]; then
        printf "  (no mappings configured)\n"
    fi
}

# Resolve a relative path (from projects/) applying local mappings
# Used during pull: convert remote path to local path
resolve_path_for_pull() {
    local relative_path="$1"

    if [[ ! -f "${MAPPINGS_FILE}" ]]; then
        printf "%s" "${relative_path}"
        return 0
    fi

    local result="${relative_path}"

    while IFS= read -r line; do
        [[ "${line}" =~ ^#.*$ || -z "${line}" ]] && continue

        local src dst
        src=$(printf "%s" "${line}" | cut -d'=' -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        dst=$(printf "%s" "${line}" | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # Normalize: remove leading slash for pattern matching
        local src_norm="${src#/}"
        local dst_norm="${dst#/}"

        # In projects/, paths are stored as the absolute path without leading /
        # e.g., projects/home/alice/dev/myapp/...
        if [[ "${result}" == projects/${src_norm}/* || "${result}" == projects/${src_norm} ]]; then
            result="${result/projects\/${src_norm}/projects\/${dst_norm}}"
            break
        fi
    done < "${MAPPINGS_FILE}"

    printf "%s" "${result}"
}

# Resolve a relative path for push: convert local path to canonical form
# Used during push: normalize local machine paths
resolve_path_for_push() {
    local relative_path="$1"

    if [[ ! -f "${MAPPINGS_FILE}" ]]; then
        printf "%s" "${relative_path}"
        return 0
    fi

    local result="${relative_path}"

    while IFS= read -r line; do
        [[ "${line}" =~ ^#.*$ || -z "${line}" ]] && continue

        local src dst
        src=$(printf "%s" "${line}" | cut -d'=' -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        dst=$(printf "%s" "${line}" | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        local dst_norm="${dst#/}"
        local src_norm="${src#/}"

        # Reverse: local path (dst) → canonical path (src)
        if [[ "${result}" == projects/${dst_norm}/* || "${result}" == projects/${dst_norm} ]]; then
            result="${result/projects\/${dst_norm}/projects\/${src_norm}}"
            break
        fi
    done < "${MAPPINGS_FILE}"

    printf "%s" "${result}"
}

cmd_map() {
    if [[ $# -eq 0 ]]; then
        list_mappings
        return 0
    fi

    case "$1" in
        --list | -l)
            list_mappings
            ;;
        --remove | -r)
            if [[ $# -lt 2 ]]; then
                printf "Usage: claude-bridge map --remove <source_path>\n" >&2
                return 1
            fi
            remove_mapping "$2"
            ;;
        *)
            if [[ $# -lt 2 ]]; then
                printf "Usage: claude-bridge map <source_path> <destination_path>\n" >&2
                printf "       claude-bridge map --list\n" >&2
                printf "       claude-bridge map --remove <source_path>\n" >&2
                return 1
            fi
            add_mapping "$1" "$2"
            ;;
    esac
}
