#!/usr/bin/env bash
# test_sync.sh — Test suite for claude-bridge
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${TESTS_DIR}/test_helper.sh"

# ============================================================
# Config tests
# ============================================================

test_config() {
    describe "Config management"
    setup_test_env

    # Override SCRIPT_DIR so get_repo_dir works
    export SCRIPT_DIR="${TEST_REPO_DIR}"
    source "${TEST_REPO_DIR}/lib/config.sh"

    it "creates config directory on first access"
    ensure_config_dir
    assert_true "[[ -d '${HOME}/.claude-bridge' ]]" "config dir not created"

    it "creates config file with defaults"
    ensure_config_file
    assert_file_exists "${HOME}/.claude-bridge/sync.conf"

    it "reads default CLAUDE_DIR"
    local claude_dir
    claude_dir=$(config_get "CLAUDE_DIR")
    assert_eq "${HOME}/.claude" "${claude_dir}"

    it "reads default SYNC_TARGETS"
    local targets
    targets=$(config_get "SYNC_TARGETS")
    assert_eq "projects,history,settings,claude_md" "${targets}"

    it "sets and gets a custom value"
    config_set "MACHINE_NAME" "test-machine"
    local name
    name=$(config_get "MACHINE_NAME")
    assert_eq "test-machine" "${name}"

    it "updates an existing value"
    config_set "MACHINE_NAME" "updated-machine"
    local updated
    updated=$(config_get "MACHINE_NAME")
    assert_eq "updated-machine" "${updated}"

    it "lists config without error"
    local output
    output=$(config_list)
    assert_contains "${output}" "MACHINE_NAME=updated-machine"

    teardown_test_env
}

# ============================================================
# Crypto tests
# ============================================================

test_crypto() {
    describe "Encryption helpers"
    setup_test_env

    export SCRIPT_DIR="${TEST_REPO_DIR}"
    source "${TEST_REPO_DIR}/lib/crypto.sh"

    it "checks age is installed"
    if command -v age &>/dev/null; then
        check_age_installed
        assert_true "true"
    else
        # Skip if age not installed
        PASS_COUNT=$((PASS_COUNT + 1))
        printf "  ${YELLOW}⊘${NC} %s (age not installed, skipped)\n" "${CURRENT_TEST}"
        teardown_test_env
        return 0
    fi

    it "generates identity and recipient files"
    generate_identity
    assert_file_exists "${HOME}/.claude-bridge/identity.txt"

    it "identity file has 600 permissions"
    local perms
    perms=$(stat -f "%Lp" "${HOME}/.claude-bridge/identity.txt" 2>/dev/null || stat -c "%a" "${HOME}/.claude-bridge/identity.txt" 2>/dev/null)
    assert_eq "600" "${perms}"

    it "recipient file exists"
    assert_file_exists "${HOME}/.claude-bridge/recipient.txt"

    it "recipient is a valid age public key"
    local recipient
    recipient=$(get_recipient)
    assert_true "[[ '${recipient}' == age1* ]]" "expected age1... public key"

    it "encrypts and decrypts a file (roundtrip)"
    local test_content="Hello, claude-bridge! 日本語テスト"
    printf "%s" "${test_content}" > "${TEST_TMPDIR}/plain.txt"
    encrypt_file "${TEST_TMPDIR}/plain.txt" "${TEST_TMPDIR}/encrypted.age"
    assert_file_exists "${TEST_TMPDIR}/encrypted.age"

    it "decrypted content matches original"
    decrypt_file "${TEST_TMPDIR}/encrypted.age" "${TEST_TMPDIR}/decrypted.txt"
    local decrypted
    decrypted=$(cat "${TEST_TMPDIR}/decrypted.txt")
    assert_eq "${test_content}" "${decrypted}"

    it "computes file hash"
    local hash
    hash=$(file_hash "${TEST_TMPDIR}/plain.txt")
    assert_true "[[ ${#hash} -eq 64 ]]" "hash length should be 64 chars (SHA-256)"

    it "same content produces same hash"
    printf "%s" "${test_content}" > "${TEST_TMPDIR}/plain2.txt"
    local hash2
    hash2=$(file_hash "${TEST_TMPDIR}/plain2.txt")
    assert_eq "${hash}" "${hash2}"

    teardown_test_env
}

# ============================================================
# Path resolver tests
# ============================================================

test_path_resolver() {
    describe "Path resolver"
    setup_test_env

    export SCRIPT_DIR="${TEST_REPO_DIR}"
    source "${TEST_REPO_DIR}/lib/path_resolver.sh"

    it "creates mappings file"
    ensure_mappings_file
    assert_file_exists "${HOME}/.claude-bridge/path_mappings"

    it "adds a mapping"
    local output
    output=$(add_mapping "/home/alice/dev/myapp" "/Users/alice/projects/myapp")
    assert_contains "${output}" "Added mapping"

    it "lists mappings"
    output=$(list_mappings)
    assert_contains "${output}" "/home/alice/dev/myapp"

    it "resolves path for pull (source → destination)"
    local resolved
    resolved=$(resolve_path_for_pull "projects/home/alice/dev/myapp/session.jsonl")
    assert_eq "projects/Users/alice/projects/myapp/session.jsonl" "${resolved}"

    it "resolves path for push (destination → source)"
    local canonical
    canonical=$(resolve_path_for_push "projects/Users/alice/projects/myapp/session.jsonl")
    assert_eq "projects/home/alice/dev/myapp/session.jsonl" "${canonical}"

    it "passes through unmapped paths"
    local unmapped
    unmapped=$(resolve_path_for_pull "projects/other/path/file.txt")
    assert_eq "projects/other/path/file.txt" "${unmapped}"

    it "updates an existing mapping"
    output=$(add_mapping "/home/alice/dev/myapp" "/Users/alice/workspace/myapp")
    assert_contains "${output}" "Updated mapping"

    it "removes a mapping"
    output=$(remove_mapping "/home/alice/dev/myapp")
    assert_contains "${output}" "Removed mapping"

    it "returns error for removing non-existent mapping"
    output=$(remove_mapping "/nonexistent/path" 2>&1 || true)
    assert_contains "${output}" "No mapping found"

    teardown_test_env
}

# ============================================================
# Manifest tests
# ============================================================

test_manifest() {
    describe "Manifest operations"
    setup_test_env

    if ! command -v jq &>/dev/null; then
        printf "  ${YELLOW}⊘${NC} skipped (jq not installed)\n"
        teardown_test_env
        return 0
    fi

    export SCRIPT_DIR="${TEST_REPO_DIR}"
    source "${TEST_REPO_DIR}/lib/config.sh"
    source "${TEST_REPO_DIR}/lib/crypto.sh"
    source "${TEST_REPO_DIR}/lib/push.sh"

    # Ensure config exists
    ensure_config_file
    config_set "MACHINE_NAME" "test-machine"

    # Create initial manifest
    source "${TEST_REPO_DIR}/lib/init.sh"

    it "creates initial manifest"
    create_initial_manifest
    assert_file_exists "${HOME}/.claude-bridge/manifest.json"

    it "manifest has correct structure"
    local version
    version=$(jq -r '.version' "${HOME}/.claude-bridge/manifest.json")
    assert_eq "1" "${version}"

    it "manifest has machine name"
    local machine
    machine=$(jq -r '.machine' "${HOME}/.claude-bridge/manifest.json")
    assert_eq "test-machine" "${machine}"

    it "manifest starts with empty files"
    local file_count
    file_count=$(jq -r '.files | length' "${HOME}/.claude-bridge/manifest.json")
    assert_eq "0" "${file_count}"

    it "updates manifest with a file entry"
    update_manifest "test/file.txt" "abc123hash" "1024" "2026-03-17T12:00:00Z"
    local hash
    hash=$(jq -r '.files["test/file.txt"].hash' "${HOME}/.claude-bridge/manifest.json")
    assert_eq "abc123hash" "${hash}"

    it "retrieves hash from manifest"
    local got_hash
    got_hash=$(get_manifest_hash "test/file.txt")
    assert_eq "abc123hash" "${got_hash}"

    it "returns empty for unknown file"
    local unknown
    unknown=$(get_manifest_hash "nonexistent.txt" || true)
    assert_eq "" "${unknown}"

    it "removes file from manifest"
    remove_from_manifest "test/file.txt"
    local after_count
    after_count=$(jq -r '.files | length' "${HOME}/.claude-bridge/manifest.json")
    assert_eq "0" "${after_count}"

    teardown_test_env
}

# ============================================================
# CLI tests
# ============================================================

test_cli() {
    describe "CLI entry point"

    local bin
    bin="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)/claude-bridge"

    it "shows version"
    local version_output
    version_output=$("${bin}" --version 2>&1)
    assert_contains "${version_output}" "claude-bridge v"

    it "shows help"
    local help_output
    help_output=$("${bin}" --help 2>&1)
    assert_contains "${help_output}" "Usage:"

    it "rejects unknown command"
    local err_output
    err_output=$("${bin}" foobar 2>&1 || true)
    assert_contains "${err_output}" "unknown command"
}

# ============================================================
# Run all tests
# ============================================================

main() {
    printf "\nclaude-bridge test suite\n"
    printf "========================\n"

    test_config
    test_crypto
    test_path_resolver
    test_manifest
    test_cli

    print_results
}

main "$@"
