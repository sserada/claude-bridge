#!/usr/bin/env bash
# projects.sh — List and filter synced projects
set -euo pipefail

# Source dependencies
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

list_local_projects() {
    local claude_dir
    claude_dir=$(get_claude_dir)
    local projects_dir="${claude_dir}/projects"

    if [[ ! -d "${projects_dir}" ]]; then
        return 0
    fi

    # Projects are stored as directory trees under projects/
    # e.g., projects/Users/sou/workspace/myapp/
    # Find leaf directories that contain actual files (session data)
    find "${projects_dir}" -type f -name "*.jsonl" -o -name "*.json" 2>/dev/null \
        | sed "s|^${projects_dir}/||" \
        | xargs -I{} dirname {} \
        | sort -u
}

list_synced_projects() {
    if [[ ! -f "${MANIFEST_FILE}" ]]; then
        return 0
    fi

    if command -v jq &>/dev/null; then
        jq -r '.files | keys[]' "${MANIFEST_FILE}" 2>/dev/null \
            | grep '^projects/' \
            | sed 's|^projects/||' \
            | xargs -I{} dirname {} 2>/dev/null \
            | sort -u
    fi
}

match_project() {
    local path="$1"
    local pattern="$2"

    # Match by project name (last component) or full path substring
    local project_name
    project_name=$(basename "${path}")

    if [[ "${project_name}" == "${pattern}" ]]; then
        return 0
    fi

    # Glob/substring match
    if [[ "${path}" == *"${pattern}"* ]]; then
        return 0
    fi

    return 1
}

# Filter sync files to only include a specific project
filter_files_by_project() {
    local files="$1"
    local project_filter="$2"
    local claude_dir
    claude_dir=$(get_claude_dir)

    # Find matching project paths
    local project_paths
    project_paths=$(list_local_projects)

    local matched_paths=()
    while IFS= read -r proj_path; do
        [[ -z "${proj_path}" ]] && continue
        if match_project "${proj_path}" "${project_filter}"; then
            matched_paths+=("${proj_path}")
        fi
    done <<< "${project_paths}"

    if [[ ${#matched_paths[@]} -eq 0 ]]; then
        printf "Error: no project matching '%s'\n" "${project_filter}" >&2
        printf "Run 'claude-bridge projects' to list available projects.\n" >&2
        return 1
    fi

    # Filter files to only those under matched project paths
    while IFS= read -r filepath; do
        [[ -z "${filepath}" ]] && continue
        local relative="${filepath#"${claude_dir}"/}"

        # Non-project files (settings, history, etc.) are excluded in project mode
        if [[ "${relative}" != projects/* ]]; then
            continue
        fi

        local rel_project="${relative#projects/}"
        for mp in "${matched_paths[@]}"; do
            if [[ "${rel_project}" == "${mp}"/* || "${rel_project}" == "${mp}" ]]; then
                printf "%s\n" "${filepath}"
                break
            fi
        done
    done <<< "${files}"
}

cmd_projects() {
    local claude_dir
    claude_dir=$(get_claude_dir)

    printf "Projects in %s/projects/:\n\n" "${claude_dir}"

    local local_projects
    local_projects=$(list_local_projects)

    local synced_projects
    synced_projects=$(list_synced_projects)

    if [[ -z "${local_projects}" ]]; then
        printf "  (no projects found)\n"
        return 0
    fi

    while IFS= read -r proj; do
        [[ -z "${proj}" ]] && continue
        local project_name
        project_name=$(basename "${proj}")
        local sync_marker=" "

        # Check if this project is synced
        if printf "%s\n" "${synced_projects}" | grep -qF "${proj}"; then
            sync_marker="✓"
        fi

        # Count files in this project
        local file_count
        file_count=$(find "${claude_dir}/projects/${proj}" -type f 2>/dev/null | wc -l | tr -d ' ')

        printf "  [%s] %-30s (%d files)  %s\n" "${sync_marker}" "${project_name}" "${file_count}" "${proj}"
    done <<< "${local_projects}"

    printf "\n  [✓] = synced, [ ] = not yet pushed\n"
}
