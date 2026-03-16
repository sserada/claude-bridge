#!/usr/bin/env bash
# diff.sh — Preview changes before push
set -euo pipefail

# Source dependencies
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/crypto.sh"
source "$(dirname "${BASH_SOURCE[0]}")/push.sh"

format_size() {
    local bytes="$1"
    if [[ "${bytes}" -ge 1048576 ]]; then
        printf "%.1fM" "$(echo "scale=1; ${bytes}/1048576" | bc)"
    elif [[ "${bytes}" -ge 1024 ]]; then
        printf "%.1fK" "$(echo "scale=1; ${bytes}/1024" | bc)"
    else
        printf "%dB" "${bytes}"
    fi
}

cmd_diff() {
    local show_content=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --content | -c)
                show_content=true
                shift
                ;;
            *)
                printf "Unknown option: %s\n" "$1" >&2
                return 1
                ;;
        esac
    done

    local claude_dir
    claude_dir=$(get_claude_dir)

    if [[ ! -f "${MANIFEST_FILE}" ]]; then
        printf "Not initialized. Run 'claude-bridge init' first.\n" >&2
        return 1
    fi

    if [[ ! -d "${claude_dir}" ]]; then
        printf "Claude directory not found at %s\n" "${claude_dir}" >&2
        return 1
    fi

    local sync_files
    sync_files=$(get_sync_files "${claude_dir}")

    if [[ -z "${sync_files}" ]]; then
        printf "No files to sync.\n"
        return 0
    fi

    local added=()
    local modified=()
    local deleted=()
    local added_sizes=()
    local modified_sizes=()

    # Check for added/modified files
    while IFS= read -r filepath; do
        [[ -z "${filepath}" ]] && continue

        local relative_path="${filepath#"${claude_dir}"/}"
        local current_hash
        current_hash=$(file_hash "${filepath}")
        local manifest_hash
        manifest_hash=$(get_manifest_hash "${relative_path}" 2>/dev/null || true)
        local file_size
        file_size=$(wc -c < "${filepath}" | tr -d ' ')

        if [[ -z "${manifest_hash}" ]]; then
            added+=("${relative_path}")
            added_sizes+=("${file_size}")
        elif [[ "${current_hash}" != "${manifest_hash}" ]]; then
            modified+=("${relative_path}")
            modified_sizes+=("${file_size}")
        fi
    done <<< "${sync_files}"

    # Check for deleted files
    if command -v jq &>/dev/null; then
        local manifest_files
        manifest_files=$(jq -r '.files | keys[]' "${MANIFEST_FILE}" 2>/dev/null || true)
        while IFS= read -r manifest_path; do
            [[ -z "${manifest_path}" ]] && continue
            if [[ ! -f "${claude_dir}/${manifest_path}" ]]; then
                deleted+=("${manifest_path}")
            fi
        done <<< "${manifest_files}"
    fi

    local total=$(( ${#added[@]} + ${#modified[@]} + ${#deleted[@]} ))

    if [[ "${total}" -eq 0 ]]; then
        printf "No changes. Everything is in sync.\n"
        return 0
    fi

    printf "Changes to push (%d file(s)):\n\n" "${total}"

    # Added files
    if [[ ${#added[@]} -gt 0 ]]; then
        printf "  New files (%d):\n" "${#added[@]}"
        for i in "${!added[@]}"; do
            printf "    + %-60s %s\n" "${added[${i}]}" "$(format_size "${added_sizes[${i}]}")"
        done
        printf "\n"
    fi

    # Modified files
    if [[ ${#modified[@]} -gt 0 ]]; then
        printf "  Modified files (%d):\n" "${#modified[@]}"
        for i in "${!modified[@]}"; do
            printf "    ~ %-60s %s\n" "${modified[${i}]}" "$(format_size "${modified_sizes[${i}]}")"
        done
        printf "\n"
    fi

    # Deleted files
    if [[ ${#deleted[@]} -gt 0 ]]; then
        printf "  Deleted files (%d):\n" "${#deleted[@]}"
        for f in "${deleted[@]}"; do
            printf "    - %s\n" "${f}"
        done
        printf "\n"
    fi

    # Content diff (optional)
    if [[ "${show_content}" == true && ${#modified[@]} -gt 0 ]]; then
        printf "Content changes:\n"
        printf "================\n\n"

        local repo_dir
        repo_dir=$(get_repo_dir)

        for rel_path in "${modified[@]}"; do
            local local_file="${claude_dir}/${rel_path}"
            local encrypted_file="${repo_dir}/encrypted/${rel_path}.age"

            # Only show diff for text files
            if file "${local_file}" | grep -q "text"; then
                printf "--- %s (synced)\n" "${rel_path}"
                printf "+++ %s (local)\n" "${rel_path}"

                if [[ -f "${encrypted_file}" ]]; then
                    local tmpfile
                    tmpfile=$(mktemp)
                    if decrypt_file "${encrypted_file}" "${tmpfile}" 2>/dev/null; then
                        diff -u "${tmpfile}" "${local_file}" 2>/dev/null | tail -n +3 || true
                    else
                        printf "  (unable to decrypt for diff)\n"
                    fi
                    rm -f "${tmpfile}"
                else
                    printf "  (no previous version available)\n"
                fi
                printf "\n"
            fi
        done
    fi

    printf "Run 'claude-bridge push' to sync these changes.\n"
}
