#!/usr/bin/env bash
# test_helper.sh — Simple test framework for claude-bridge
set -euo pipefail

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0
CURRENT_TEST=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Test temp directory
TEST_TMPDIR=""
ORIGINAL_HOME="${HOME}"

setup_test_env() {
    TEST_TMPDIR=$(mktemp -d)
    export HOME="${TEST_TMPDIR}/home"
    mkdir -p "${HOME}"

    # Create a fake repo dir
    export TEST_REPO_DIR="${TEST_TMPDIR}/repo"
    mkdir -p "${TEST_REPO_DIR}/encrypted"
    mkdir -p "${TEST_REPO_DIR}/lib"
    mkdir -p "${TEST_REPO_DIR}/bin"

    # Copy lib files to test repo
    local real_lib_dir
    real_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
    cp "${real_lib_dir}"/*.sh "${TEST_REPO_DIR}/lib/"

    # Create a fake claude dir
    export TEST_CLAUDE_DIR="${HOME}/.claude"
    mkdir -p "${TEST_CLAUDE_DIR}/projects/test-project"
}

teardown_test_env() {
    export HOME="${ORIGINAL_HOME}"
    if [[ -n "${TEST_TMPDIR}" && -d "${TEST_TMPDIR}" ]]; then
        rm -rf "${TEST_TMPDIR}"
    fi
}

describe() {
    printf "\n${YELLOW}%s${NC}\n" "$1"
}

it() {
    CURRENT_TEST="$1"
    TEST_COUNT=$((TEST_COUNT + 1))
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-"expected '${expected}', got '${actual}'"}"

    if [[ "${expected}" == "${actual}" ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        printf "  ${GREEN}✓${NC} %s\n" "${CURRENT_TEST}"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        printf "  ${RED}✗${NC} %s\n" "${CURRENT_TEST}"
        printf "    %s\n" "${msg}"
    fi
}

assert_true() {
    local condition="$1"
    local msg="${2:-"condition was false"}"

    if eval "${condition}"; then
        PASS_COUNT=$((PASS_COUNT + 1))
        printf "  ${GREEN}✓${NC} %s\n" "${CURRENT_TEST}"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        printf "  ${RED}✗${NC} %s\n" "${CURRENT_TEST}"
        printf "    %s\n" "${msg}"
    fi
}

assert_false() {
    local condition="$1"
    local msg="${2:-"condition was true"}"

    if ! eval "${condition}"; then
        PASS_COUNT=$((PASS_COUNT + 1))
        printf "  ${GREEN}✓${NC} %s\n" "${CURRENT_TEST}"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        printf "  ${RED}✗${NC} %s\n" "${CURRENT_TEST}"
        printf "    %s\n" "${msg}"
    fi
}

assert_file_exists() {
    local filepath="$1"
    if [[ -f "${filepath}" ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        printf "  ${GREEN}✓${NC} %s\n" "${CURRENT_TEST}"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        printf "  ${RED}✗${NC} %s\n" "${CURRENT_TEST}"
        printf "    file not found: %s\n" "${filepath}"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    if [[ "${haystack}" == *"${needle}"* ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        printf "  ${GREEN}✓${NC} %s\n" "${CURRENT_TEST}"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        printf "  ${RED}✗${NC} %s\n" "${CURRENT_TEST}"
        printf "    '%s' not found in output\n" "${needle}"
    fi
}

print_results() {
    printf "\n========================================\n"
    if [[ ${FAIL_COUNT} -eq 0 ]]; then
        printf "${GREEN}All %d tests passed${NC}\n" "${TEST_COUNT}"
    else
        printf "${RED}%d of %d tests failed${NC}\n" "${FAIL_COUNT}" "${TEST_COUNT}"
    fi
    printf "========================================\n"

    return "${FAIL_COUNT}"
}
