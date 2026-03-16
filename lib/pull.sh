#!/usr/bin/env bash
# pull.sh — Pull and decrypt changes from remote
set -euo pipefail

# Source dependencies
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/crypto.sh"

backup_file() {
    local filepath="$1"
    local backup_dir="${CONFLICTS_DIR}/$(date +%Y%m%d_%H%M%S)"

    if [[ -f "${filepath}" ]]; then
        local relative
        relative="${filepath#"$(get_claude_dir)"/}"
        local backup_path="${backup_dir}/${relative}"
        mkdir -p "$(dirname "${backup_path}")"
        cp "${filepath}" "${backup_path}"
    fi
}

apply_path_mappings() {
    local relative_path="$1"
    local mappings_file="${CLAUDE_BRIDGE_DIR}/path_mappings"

    if [[ ! -f "${mappings_file}" ]]; then
        printf "%s" "${relative_path}"
        return 0
    fi

    local result="${relative_path}"
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "${line}" =~ ^#.*$ || -z "${line}" ]] && continue

        local src dst
        src=$(printf "%s" "${line}" | cut -d'=' -f1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        dst=$(printf "%s" "${line}" | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # Normalize paths: remove leading slash, replace / with directory separator in pattern
        local src_pattern="${src#/}"
        local dst_pattern="${dst#/}"

        # Replace source prefix with destination in projects/ paths
        if [[ "${result}" == projects/${src_pattern}/* ]]; then
            result="projects/${dst_pattern}/${result#projects/${src_pattern}/}"
            break
        fi
    done < "${mappings_file}"

    printf "%s" "${result}"
}

cmd_pull() {
    local project_filter=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project | -p)
                project_filter="$2"
                shift 2
                ;;
            *)
                printf "Unknown option: %s\n" "$1" >&2
                return 1
                ;;
        esac
    done

    local repo_dir
    repo_dir=$(get_repo_dir)
    local encrypted_dir="${repo_dir}/encrypted"
    local claude_dir
    claude_dir=$(get_claude_dir)

    if [[ ! -f "${PASSPHRASE_FILE}" ]]; then
        printf "Error: not initialized. Run 'claude-bridge init' first.\n" >&2
        return 1
    fi

    # Git pull
    printf "Pulling from remote...\n" >&2
    cd "${repo_dir}"
    git pull --ff-only 2>&1 | while IFS= read -r line; do
        printf "  %s\n" "${line}" >&2
    done

    # Check if there's a remote manifest
    local remote_manifest="${encrypted_dir}/manifest.json"
    if [[ ! -f "${remote_manifest}" ]]; then
        printf "No manifest found in remote. Nothing to pull.\n" >&2
        return 0
    fi

    # Read remote manifest to find files
    if ! command -v jq &>/dev/null; then
        printf "Error: jq is required for pull. Install it with: brew install jq / apt install jq\n" >&2
        return 1
    fi

    local file_count
    file_count=$(jq -r '.files | length' "${remote_manifest}")

    if [[ "${file_count}" -eq 0 ]]; then
        printf "No files in remote manifest.\n" >&2
        return 0
    fi

    printf "Decrypting %d file(s)...\n" "${file_count}" >&2

    local restored_count=0
    local skipped_count=0

    if [[ -n "${project_filter}" ]]; then
        printf "Filtering to project: %s\n" "${project_filter}" >&2
    fi

    # Process each file in the manifest
    jq -r '.files | keys[]' "${remote_manifest}" | while IFS= read -r relative_path; do
        [[ -z "${relative_path}" ]] && continue

        # Apply project filter if specified
        if [[ -n "${project_filter}" ]]; then
            if [[ "${relative_path}" != projects/*"${project_filter}"* ]]; then
                continue
            fi
        fi

        local encrypted_path="${encrypted_dir}/${relative_path}.age"

        if [[ ! -f "${encrypted_path}" ]]; then
            printf "  Warning: encrypted file missing for %s\n" "${relative_path}" >&2
            continue
        fi

        # Apply path mappings for cross-machine support
        local mapped_path
        mapped_path=$(apply_path_mappings "${relative_path}")

        local dest="${claude_dir}/${mapped_path}"

        # Check if local file exists and compare hashes
        local remote_hash
        remote_hash=$(jq -r --arg path "${relative_path}" '.files[$path].hash' "${remote_manifest}")

        if [[ -f "${dest}" ]]; then
            local local_hash
            local_hash=$(file_hash "${dest}")
            if [[ "${local_hash}" == "${remote_hash}" ]]; then
                # File unchanged, skip
                skipped_count=$((skipped_count + 1))
                continue
            fi
            # File differs — backup before overwrite
            backup_file "${dest}"
        fi

        # Decrypt and place
        printf "  Restoring: %s\n" "${mapped_path}" >&2
        mkdir -p "$(dirname "${dest}")"

        if ! decrypt_file "${encrypted_path}" "${dest}"; then
            printf "  Error: failed to decrypt %s\n" "${relative_path}" >&2
            continue
        fi

        restored_count=$((restored_count + 1))
    done

    # Update local manifest from remote
    cp "${remote_manifest}" "${MANIFEST_FILE}"

    printf "\nPull complete.\n" >&2
}
