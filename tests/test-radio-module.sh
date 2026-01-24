#!/bin/bash
#=============================================================================
# InfraStack Radio Module - Test Script
# Tests the radio module integration without deploying actual containers
#=============================================================================

set -euo pipefail

# Get script directory and InfraStack root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRASTACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

#=============================================================================
# TEST UTILITIES
#=============================================================================

log_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
    ((TESTS_SKIPPED++))
}

assert_file_exists() {
    local file="$1"
    local description="${2:-$file exists}"

    if [[ -f "$file" ]]; then
        log_pass "$description"
        return 0
    else
        log_fail "$description - file not found: $file"
        return 1
    fi
}

assert_dir_exists() {
    local dir="$1"
    local description="${2:-$dir exists}"

    if [[ -d "$dir" ]]; then
        log_pass "$description"
        return 0
    else
        log_fail "$description - directory not found: $dir"
        return 1
    fi
}

assert_executable() {
    local file="$1"
    local description="${2:-$file is executable}"

    if [[ -x "$file" ]]; then
        log_pass "$description"
        return 0
    else
        log_fail "$description - not executable: $file"
        return 1
    fi
}

assert_contains() {
    local file="$1"
    local pattern="$2"
    local description="${3:-$file contains $pattern}"

    if grep -q "$pattern" "$file" 2>/dev/null; then
        log_pass "$description"
        return 0
    else
        log_fail "$description - pattern not found"
        return 1
    fi
}

assert_source_works() {
    local file="$1"
    local description="${2:-$file can be sourced}"

    if bash -n "$file" 2>/dev/null; then
        log_pass "$description"
        return 0
    else
        log_fail "$description - syntax error in $file"
        return 1
    fi
}

#=============================================================================
# TEST GROUPS
#=============================================================================

test_directory_structure() {
    echo ""
    echo "===== Directory Structure Tests ====="

    log_test "Checking radio module directories..."
    assert_dir_exists "$INFRASTACK_ROOT/scripts/radio" "Radio module directory"
    assert_dir_exists "$INFRASTACK_ROOT/scripts/radio/platforms" "Platforms directory"
    assert_dir_exists "$INFRASTACK_ROOT/scripts/radio/tools" "Tools directory"
    assert_dir_exists "$INFRASTACK_ROOT/scripts/lib" "Library directory"
    assert_dir_exists "$INFRASTACK_ROOT/docs/radio" "Radio documentation directory"
}

test_library_files() {
    echo ""
    echo "===== Library Files Tests ====="

    log_test "Checking library files..."
    assert_file_exists "$INFRASTACK_ROOT/scripts/lib/common.sh" "common.sh exists"
    assert_file_exists "$INFRASTACK_ROOT/scripts/lib/container.sh" "container.sh exists"
    assert_file_exists "$INFRASTACK_ROOT/scripts/lib/storage.sh" "storage.sh exists"
    assert_file_exists "$INFRASTACK_ROOT/scripts/lib/inventory.sh" "inventory.sh exists"

    log_test "Checking library syntax..."
    assert_source_works "$INFRASTACK_ROOT/scripts/lib/common.sh" "common.sh syntax valid"
    assert_source_works "$INFRASTACK_ROOT/scripts/lib/container.sh" "container.sh syntax valid"
    assert_source_works "$INFRASTACK_ROOT/scripts/lib/storage.sh" "storage.sh syntax valid"
    assert_source_works "$INFRASTACK_ROOT/scripts/lib/inventory.sh" "inventory.sh syntax valid"
}

test_platform_scripts() {
    echo ""
    echo "===== Platform Scripts Tests ====="

    log_test "Checking platform scripts..."
    assert_file_exists "$INFRASTACK_ROOT/scripts/radio/platforms/azuracast.sh" "azuracast.sh exists"
    assert_file_exists "$INFRASTACK_ROOT/scripts/radio/platforms/libretime.sh" "libretime.sh exists"
    assert_file_exists "$INFRASTACK_ROOT/scripts/radio/platforms/deploy.sh" "deploy.sh exists"

    log_test "Checking platform scripts are executable..."
    assert_executable "$INFRASTACK_ROOT/scripts/radio/platforms/azuracast.sh" "azuracast.sh executable"
    assert_executable "$INFRASTACK_ROOT/scripts/radio/platforms/libretime.sh" "libretime.sh executable"
    assert_executable "$INFRASTACK_ROOT/scripts/radio/platforms/deploy.sh" "deploy.sh executable"

    log_test "Checking platform scripts syntax..."
    assert_source_works "$INFRASTACK_ROOT/scripts/radio/platforms/deploy.sh" "deploy.sh syntax valid"
}

test_tool_scripts() {
    echo ""
    echo "===== Tool Scripts Tests ====="

    local tools=("status" "update" "backup" "remove" "logs" "info")

    for tool in "${tools[@]}"; do
        log_test "Checking ${tool}.sh..."
        assert_file_exists "$INFRASTACK_ROOT/scripts/radio/tools/${tool}.sh" "${tool}.sh exists"
        assert_executable "$INFRASTACK_ROOT/scripts/radio/tools/${tool}.sh" "${tool}.sh executable"
        assert_source_works "$INFRASTACK_ROOT/scripts/radio/tools/${tool}.sh" "${tool}.sh syntax valid"
    done
}

test_main_cli() {
    echo ""
    echo "===== Main CLI Tests ====="

    log_test "Checking infrastack.sh..."
    assert_file_exists "$INFRASTACK_ROOT/infrastack.sh" "infrastack.sh exists"
    assert_executable "$INFRASTACK_ROOT/infrastack.sh" "infrastack.sh executable"
    assert_source_works "$INFRASTACK_ROOT/infrastack.sh" "infrastack.sh syntax valid"

    log_test "Checking CLI contains radio commands..."
    assert_contains "$INFRASTACK_ROOT/infrastack.sh" "radio)" "CLI has radio category"
    assert_contains "$INFRASTACK_ROOT/infrastack.sh" "deploy)" "CLI has deploy command"
    assert_contains "$INFRASTACK_ROOT/infrastack.sh" "status)" "CLI has status command"
    assert_contains "$INFRASTACK_ROOT/infrastack.sh" "backup)" "CLI has backup command"

    log_test "Checking CLI version..."
    assert_contains "$INFRASTACK_ROOT/infrastack.sh" 'VERSION="2.0.0"' "CLI version is 2.0.0"
}

test_documentation() {
    echo ""
    echo "===== Documentation Tests ====="

    log_test "Checking documentation files..."
    assert_file_exists "$INFRASTACK_ROOT/docs/radio/getting-started.md" "getting-started.md exists"
    assert_file_exists "$INFRASTACK_ROOT/docs/radio/libretime.md" "libretime.md exists"
    assert_file_exists "$INFRASTACK_ROOT/docs/radio/storage-configuration.md" "storage-configuration.md exists"
    assert_file_exists "$INFRASTACK_ROOT/docs/radio/quick-reference.md" "quick-reference.md exists"
    assert_file_exists "$INFRASTACK_ROOT/scripts/radio/README.md" "Radio README.md exists"
    assert_file_exists "$INFRASTACK_ROOT/MIGRATION.md" "MIGRATION.md exists"

    log_test "Checking documentation references InfraStack..."
    assert_contains "$INFRASTACK_ROOT/docs/radio/getting-started.md" "infrastack radio" "Docs use infrastack command"
    assert_contains "$INFRASTACK_ROOT/MIGRATION.md" "infrastack radio" "Migration guide has new commands"
}

test_imports() {
    echo ""
    echo "===== Import Path Tests ====="

    log_test "Checking scripts use INFRASTACK_ROOT..."
    assert_contains "$INFRASTACK_ROOT/scripts/radio/platforms/deploy.sh" "INFRASTACK_ROOT" "deploy.sh uses INFRASTACK_ROOT"
    assert_contains "$INFRASTACK_ROOT/scripts/radio/tools/status.sh" "INFRASTACK_ROOT" "status.sh uses INFRASTACK_ROOT"
    assert_contains "$INFRASTACK_ROOT/scripts/lib/container.sh" "INFRASTACK_ROOT" "container.sh uses INFRASTACK_ROOT"

    log_test "Checking scripts source from scripts/lib/..."
    assert_contains "$INFRASTACK_ROOT/scripts/radio/tools/status.sh" 'source.*scripts/lib/common.sh' "status.sh sources common.sh"
}

test_cli_help() {
    echo ""
    echo "===== CLI Help Tests ====="

    log_test "Testing CLI help output..."

    if "$INFRASTACK_ROOT/infrastack.sh" help 2>&1 | grep -q "radio"; then
        log_pass "CLI help shows radio category"
    else
        log_fail "CLI help missing radio category"
    fi

    if "$INFRASTACK_ROOT/infrastack.sh" radio help 2>&1 | grep -q "deploy"; then
        log_pass "Radio help shows deploy command"
    else
        log_fail "Radio help missing deploy command"
    fi

    if "$INFRASTACK_ROOT/infrastack.sh" version 2>&1 | grep -q "2.0.0"; then
        log_pass "CLI version shows 2.0.0"
    else
        log_fail "CLI version incorrect"
    fi
}

#=============================================================================
# MAIN EXECUTION
#=============================================================================

main() {
    echo "============================================="
    echo "InfraStack Radio Module - Integration Tests"
    echo "============================================="
    echo ""
    echo "InfraStack Root: $INFRASTACK_ROOT"
    echo "Date: $(date)"
    echo ""

    # Run all test groups
    test_directory_structure
    test_library_files
    test_platform_scripts
    test_tool_scripts
    test_main_cli
    test_documentation
    test_imports
    test_cli_help

    # Summary
    echo ""
    echo "============================================="
    echo "Test Summary"
    echo "============================================="
    echo -e "${GREEN}Passed:${NC}  $TESTS_PASSED"
    echo -e "${RED}Failed:${NC}  $TESTS_FAILED"
    echo -e "${YELLOW}Skipped:${NC} $TESTS_SKIPPED"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        echo ""
        echo "The radio module is correctly integrated into InfraStack."
        echo ""
        echo "Next steps:"
        echo "  1. Test actual deployment (requires Proxmox)"
        echo "  2. Run: sudo infrastack radio deploy azuracast -i 999 -n test"
        echo "  3. Clean up: sudo infrastack radio remove --ctid 999 --data"
        exit 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        echo ""
        echo "Please review the failures above and fix the issues."
        exit 1
    fi
}

main "$@"
