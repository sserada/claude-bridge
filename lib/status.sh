#!/usr/bin/env bash
# status.sh — Show sync status
set -euo pipefail

# Source dependencies
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/crypto.sh"

# Re-use get_sync_files from push.sh
source "$(dirname "${BASH_SOURCE[0]}")/push.sh"

cmd_status() {
    local claude_dir
    claude_dir=$(get_claude_dir)
    local repo_dir
    repo_dir=$(get_repo_dir)

    if [[ ! -f "${MANIFEST_FILE}" ]]; then
        printf "Not initialized. Run 'claude-bridge init' first.\n" >&2
        return 1
    fi

    # Header
    printf "claude-bridge status\n"
    printf "====================\n\n"

    # Machine info
    printf "Machine:    %s\n" "$(config_get MACHINE_NAME)"
    printf "Claude dir: %s\n" "${claude_dir}"
    printf "Repo dir:   %s\n" "${repo_dir}"

    # Last sync info from manifest
    if command -v jq &>/dev/null && [[ -f "${MANIFEST_FILE}" ]]; then
        local last_updated last_machine file_count
        last_updated=$(jq -r '.updated_at // "never"' "${MANIFEST_FILE}")
        last_machine=$(jq -r '.machine // "unknown"' "${MANIFEST_FILE}")
        file_count=$(jq -r '.files | length' "${MANIFEST_FILE}")
        printf "Last sync:  %s (from %s)\n" "${last_updated}" "${last_machine}"
        printf "Tracked:    %d file(s)\n" "${file_count}"
    fi
    printf "\n"

    # Detect local changes
    if [[ ! -d "${claude_dir}" ]]; then
        printf "Claude directory not found at %s\n" "${claude_dir}"
        return 0
    fi

    local sync_files
    sync_files=$(get_sync_files "${claude_dir}")

    local added=()
    local modified=()
    local deleted=()

    # Check for added/modified files
    while IFS= read -r filepath; do
        [[ -z "${filepath}" ]] && continue

        local relative_path="${filepath#"${claude_dir}"/}"
        local current_hash
        current_hash=$(file_hash "${filepath}")
        local manifest_hash
        manifest_hash=$(get_manifest_hash "${relative_path}" 2>/dev/null || true)

        if [[ -z "${manifest_hash}" ]]; then
            added+=("${relative_path}")
        elif [[ "${current_hash}" != "${manifest_hash}" ]]; then
            modified+=("${relative_path}")
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

    # Display changes
    local total_changes=$(( ${#added[@]} + ${#modified[@]} + ${#deleted[@]} ))

    if [[ "${total_changes}" -eq 0 ]]; then
        printf "No local changes. Everything is in sync.\n"
    else
        printf "Local changes (%d):\n\n" "${total_changes}"

        for f in "${added[@]+"${added[@]}"}"; do
            [[ -n "${f}" ]] && printf "  + %s (new)\n" "${f}"
        done
        for f in "${modified[@]+"${modified[@]}"}"; do
            [[ -n "${f}" ]] && printf "  ~ %s (modified)\n" "${f}"
        done
        for f in "${deleted[@]+"${deleted[@]}"}"; do
            [[ -n "${f}" ]] && printf "  - %s (deleted)\n" "${f}"
        done

        printf "\nRun 'claude-bridge push' to sync changes.\n"
    fi

    # Check for conflicts
    if [[ -d "${CONFLICTS_DIR}" ]]; then
        local conflict_count
        conflict_count=$(find "${CONFLICTS_DIR}" -type f 2>/dev/null | wc -l | tr -d ' ')
        if [[ "${conflict_count}" -gt 0 ]]; then
            printf "\nConflicts: %d file(s) in %s\n" "${conflict_count}" "${CONFLICTS_DIR}"
        fi
    fi
}
