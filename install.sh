#!/usr/bin/env bash
# install.sh — Installer for claude-bridge
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BIN_DIR="${SCRIPT_DIR}/bin"

info() { printf "\033[1;34m[info]\033[0m %s\n" "$1"; }
ok()   { printf "\033[1;32m[ok]\033[0m   %s\n" "$1"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$1"; }
err()  { printf "\033[1;31m[err]\033[0m  %s\n" "$1" >&2; }

detect_os() {
    case "$(uname -s)" in
        Darwin) printf "macos" ;;
        Linux)  printf "linux" ;;
        *)      printf "unknown" ;;
    esac
}

detect_shell_profile() {
    local shell_name
    shell_name=$(basename "${SHELL:-/bin/bash}")

    case "${shell_name}" in
        zsh)  printf "%s/.zshrc" "${HOME}" ;;
        bash)
            if [[ -f "${HOME}/.bash_profile" ]]; then
                printf "%s/.bash_profile" "${HOME}"
            else
                printf "%s/.bashrc" "${HOME}"
            fi
            ;;
        *)    printf "%s/.profile" "${HOME}" ;;
    esac
}

check_git() {
    if command -v git &>/dev/null; then
        ok "git is installed ($(git --version | head -1))"
        return 0
    else
        err "git is not installed"
        return 1
    fi
}

check_age() {
    if command -v age &>/dev/null; then
        ok "age is installed ($(age --version 2>&1 | head -1))"
        return 0
    else
        return 1
    fi
}

install_age() {
    local os="$1"
    info "Installing age..."

    case "${os}" in
        macos)
            if command -v brew &>/dev/null; then
                brew install age
            else
                err "Homebrew not found. Install age manually: https://github.com/FiloSottile/age"
                return 1
            fi
            ;;
        linux)
            if command -v apt-get &>/dev/null; then
                sudo apt-get update -qq && sudo apt-get install -y -qq age
            elif command -v dnf &>/dev/null; then
                sudo dnf install -y age
            elif command -v pacman &>/dev/null; then
                sudo pacman -S --noconfirm age
            else
                err "No supported package manager found. Install age manually: https://github.com/FiloSottile/age"
                return 1
            fi
            ;;
        *)
            err "Unsupported OS. Install age manually: https://github.com/FiloSottile/age"
            return 1
            ;;
    esac

    if command -v age &>/dev/null; then
        ok "age installed successfully"
    else
        err "age installation failed"
        return 1
    fi
}

check_jq() {
    if command -v jq &>/dev/null; then
        ok "jq is installed ($(jq --version 2>&1))"
        return 0
    else
        warn "jq is not installed (recommended for full functionality)"
        local os
        os=$(detect_os)
        case "${os}" in
            macos) info "Install with: brew install jq" ;;
            linux) info "Install with: apt install jq" ;;
        esac
        return 0
    fi
}

add_to_path() {
    local profile
    profile=$(detect_shell_profile)
    local path_line="export PATH=\"${BIN_DIR}:\${PATH}\""

    # Check if already in PATH
    if printf "%s" "${PATH}" | tr ':' '\n' | grep -qx "${BIN_DIR}"; then
        ok "bin/ already in PATH"
        return 0
    fi

    # Check if already in profile
    if [[ -f "${profile}" ]] && grep -qF "${BIN_DIR}" "${profile}"; then
        ok "PATH entry already in ${profile}"
        return 0
    fi

    printf "\n# claude-bridge\n%s\n" "${path_line}" >> "${profile}"
    ok "Added to PATH in ${profile}"
    info "Run 'source ${profile}' or restart your shell to apply"
}

main() {
    printf "\n"
    printf "  claude-bridge installer\n"
    printf "  =======================\n\n"

    local os
    os=$(detect_os)
    info "Detected OS: ${os}"
    printf "\n"

    # Check dependencies
    info "Checking dependencies..."

    local has_errors=false

    check_git || has_errors=true

    if ! check_age; then
        info "age not found — attempting to install..."
        install_age "${os}" || has_errors=true
    fi

    check_jq

    if [[ "${has_errors}" == true ]]; then
        printf "\n"
        err "Some dependencies are missing. Please install them and try again."
        exit 1
    fi

    printf "\n"

    # Make CLI executable
    chmod +x "${BIN_DIR}/claude-bridge"
    ok "bin/claude-bridge is executable"

    # Add to PATH
    add_to_path

    printf "\n"
    printf "  Installation complete!\n\n"
    info "Next steps:"
    printf "    1. source %s   (or restart your shell)\n" "$(detect_shell_profile)"
    printf "    2. claude-bridge init\n"
    printf "\n"
}

main "$@"
