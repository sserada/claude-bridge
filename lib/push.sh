#!/usr/bin/env bash
# push.sh — Encrypt and push changes to remote
set -euo pipefail

# Source dependencies
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
source "$(dirname "${BASH_SOURCE[0]}")/crypto.sh"

check_claude_not_running() {
    if pgrep -f "claude" &>/dev/null; then
        printf "Warning: Claude Code appears to be running.\n" >&2
        printf "Pushing while Claude is active may result in incomplete data.\n" >&2
        printf "Please close Claude Code first, or use --force to push anyway.\n" >&2
        return 1
    fi
}

get_sync_files() {
    local claude_dir="$1"
    local targets
    targets=$(get_sync_targets)

    local files=()

    IFS=',' read -ra target_list <<< "${targets}"
    for target in "${target_list[@]}"; do
        case "${target}" in
            projects)
                if [[ -d "${claude_dir}/projects" ]]; then
                    while IFS= read -r -d '' file; do
                        files+=("${file}")
                    done < <(find "${claude_dir}/projects" -type f -print0 2>/dev/null)
                fi
                ;;
            history)
                if [[ -f "${claude_dir}/history.jsonl" ]]; then
                    files+=("${claude_dir}/history.jsonl")
                fi
                ;;
            settings)
                if [[ -f "${claude_dir}/settings.json" ]]; then
                    files+=("${claude_dir}/settings.json")
                fi
                ;;
            claude_md)
                if [[ -f "${claude_dir}/CLAUDE.md" ]]; then
                    files+=("${claude_dir}/CLAUDE.md")
                fi
                ;;
            agents)
                if [[ -d "${claude_dir}/agents" ]]; then
                    while IFS= read -r -d '' file; do
                        files+=("${file}")
                    done < <(find "${claude_dir}/agents" -type f -print0 2>/dev/null)
                fi
                ;;
            skills)
                if [[ -d "${claude_dir}/skills" ]]; then
                    while IFS= read -r -d '' file; do
                        files+=("${file}")
                    done < <(find "${claude_dir}/skills" -type f -print0 2>/dev/null)
                fi
                ;;
            plugins)
                if [[ -d "${claude_dir}/plugins" ]]; then
                    while IFS= read -r -d '' file; do
                        files+=("${file}")
                    done < <(find "${claude_dir}/plugins" -type f -print0 2>/dev/null)
                fi
                ;;
            rules)
                if [[ -d "${claude_dir}/rules" ]]; then
                    while IFS= read -r -d '' file; do
                        files+=("${file}")
                    done < <(find "${claude_dir}/rules" -type f -print0 2>/dev/null)
                fi
                ;;
        esac
    done

    printf "%s\n" "${files[@]}"
}

get_manifest_hash() {
    local relative_path="$1"

    if [[ ! -f "${MANIFEST_FILE}" ]]; then
        return 1
    fi

    if command -v jq &>/dev/null; then
        jq -r --arg path "${relative_path}" '.files[$path].hash // empty' "${MANIFEST_FILE}"
    else
        # Fallback: grep-based extraction
        grep -o "\"${relative_path}\"[^}]*\"hash\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "${MANIFEST_FILE}" 2>/dev/null \
            | grep -o '"hash"[[:space:]]*:[[:space:]]*"[^"]*"' \
            | grep -o '"[^"]*"$' \
            | tr -d '"' || true
    fi
}

update_manifest() {
    local relative_path="$1"
    local hash="$2"
    local size="$3"
    local modified="$4"

    if command -v jq &>/dev/null; then
        local tmpfile
        tmpfile=$(mktemp)
        jq --arg path "${relative_path}" \
           --arg hash "${hash}" \
           --arg size "${size}" \
           --arg modified "${modified}" \
           --arg updated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
           --arg machine "$(config_get MACHINE_NAME)" \
           '.updated_at = $updated_at | .machine = $machine | .files[$path] = {hash: $hash, size: ($size | tonumber), modified: $modified}' \
           "${MANIFEST_FILE}" > "${tmpfile}"
        mv "${tmpfile}" "${MANIFEST_FILE}"
    else
        # For non-jq fallback, rebuild manifest is complex — require jq for push
        printf "Error: jq is required for push. Install it with: brew install jq / apt install jq\n" >&2
        return 1
    fi
}

remove_from_manifest() {
    local relative_path="$1"

    if command -v jq &>/dev/null; then
        local tmpfile
        tmpfile=$(mktemp)
        jq --arg path "${relative_path}" \
           --arg updated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
           --arg machine "$(config_get MACHINE_NAME)" \
           '.updated_at = $updated_at | .machine = $machine | del(.files[$path])' \
           "${MANIFEST_FILE}" > "${tmpfile}"
        mv "${tmpfile}" "${MANIFEST_FILE}"
    fi
}

cmd_push() {
    local commit_message=""
    local force=false
    local project_filter=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --message | -m)
                commit_message="$2"
                shift 2
                ;;
            --force | -f)
                force=true
                shift
                ;;
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

    # Check Claude is not running (unless --force)
    if [[ "${force}" != true ]]; then
        check_claude_not_running || return 1
    fi

    local claude_dir
    claude_dir=$(get_claude_dir)
    local repo_dir
    repo_dir=$(get_repo_dir)
    local encrypted_dir="${repo_dir}/encrypted"

    if [[ ! -d "${claude_dir}" ]]; then
        printf "Error: Claude directory not found at %s\n" "${claude_dir}" >&2
        return 1
    fi

    if [[ ! -f "${MANIFEST_FILE}" ]]; then
        printf "Error: not initialized. Run 'claude-bridge init' first.\n" >&2
        return 1
    fi

    printf "Scanning %s for changes...\n" "${claude_dir}" >&2

    # Collect files to sync
    local sync_files
    sync_files=$(get_sync_files "${claude_dir}")

    # Apply project filter if specified
    if [[ -n "${project_filter}" ]]; then
        source "$(dirname "${BASH_SOURCE[0]}")/projects.sh"
        sync_files=$(filter_files_by_project "${sync_files}" "${project_filter}") || return 1
        printf "Filtering to project: %s\n" "${project_filter}" >&2
    fi

    if [[ -z "${sync_files}" ]]; then
        printf "No files to sync.\n" >&2
        return 0
    fi

    local changed_count=0
    local total_count=0

    while IFS= read -r filepath; do
        [[ -z "${filepath}" ]] && continue
        total_count=$((total_count + 1))

        # Compute relative path from claude_dir
        local relative_path="${filepath#"${claude_dir}"/}"
        local current_hash
        current_hash=$(file_hash "${filepath}")
        local manifest_hash
        manifest_hash=$(get_manifest_hash "${relative_path}" || true)

        if [[ "${current_hash}" == "${manifest_hash}" ]]; then
            continue
        fi

        # File has changed — encrypt it
        local encrypted_path="${encrypted_dir}/${relative_path}.age"
        printf "  Encrypting: %s\n" "${relative_path}" >&2
        encrypt_file "${filepath}" "${encrypted_path}" || {
            printf "Error: failed to encrypt %s\n" "${relative_path}" >&2
            return 1
        }

        # Update manifest
        local file_size
        file_size=$(wc -c < "${filepath}" | tr -d ' ')
        local file_modified
        file_modified=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        update_manifest "${relative_path}" "${current_hash}" "${file_size}" "${file_modified}"

        changed_count=$((changed_count + 1))
    done <<< "${sync_files}"

    # Check for deleted files: files in manifest but not on disk
    if command -v jq &>/dev/null; then
        local manifest_files
        manifest_files=$(jq -r '.files | keys[]' "${MANIFEST_FILE}" 2>/dev/null || true)
        while IFS= read -r manifest_path; do
            [[ -z "${manifest_path}" ]] && continue
            if [[ ! -f "${claude_dir}/${manifest_path}" ]]; then
                printf "  Removing deleted: %s\n" "${manifest_path}" >&2
                local encrypted_path="${encrypted_dir}/${manifest_path}.age"
                rm -f "${encrypted_path}"
                remove_from_manifest "${manifest_path}"
                changed_count=$((changed_count + 1))
            fi
        done <<< "${manifest_files}"
    fi

    if [[ "${changed_count}" -eq 0 ]]; then
        printf "No changes detected (%d files checked).\n" "${total_count}" >&2
        return 0
    fi

    printf "\n%d file(s) changed out of %d.\n" "${changed_count}" "${total_count}" >&2

    # Copy manifest to repo for tracking
    cp "${MANIFEST_FILE}" "${repo_dir}/encrypted/manifest.json"

    # Git operations
    cd "${repo_dir}"

    if [[ -z "${commit_message}" ]]; then
        commit_message="$(config_get COMMIT_PREFIX): $(config_get MACHINE_NAME) — ${changed_count} file(s) updated"
    fi

    git add encrypted/
    git commit -m "${commit_message}"
    git push

    printf "\nPushed successfully. %d file(s) synced.\n" "${changed_count}" >&2
}
