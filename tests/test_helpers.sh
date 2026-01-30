#!/bin/bash
# =============================================================================
# Test Helpers - Common functions for E2E tests
# =============================================================================

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# -----------------------------------------------------------------------------
# Logging functions
# -----------------------------------------------------------------------------
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# -----------------------------------------------------------------------------
# Test helpers
# -----------------------------------------------------------------------------
log_test_start() {
    local test_name="$1"
    echo ""
    echo "----------------------------------------"
    echo "Starting test: ${test_name}"
    echo "----------------------------------------"
}

log_test_pass() {
    local test_name="$1"
    echo -e "${GREEN}----------------------------------------${NC}"
    echo -e "${GREEN}Test PASSED: ${test_name}${NC}"
    echo -e "${GREEN}----------------------------------------${NC}"
}

log_test_fail() {
    local test_name="$1"
    echo -e "${RED}----------------------------------------${NC}"
    echo -e "${RED}Test FAILED: ${test_name}${NC}"
    echo -e "${RED}----------------------------------------${NC}"
}

# -----------------------------------------------------------------------------
# Docker exec wrapper (handles Git Bash path conversion on Windows)
# -----------------------------------------------------------------------------
docker_exec() {
    local container="$1"
    shift
    MSYS_NO_PATHCONV=1 docker exec "${container}" "$@"
}

# -----------------------------------------------------------------------------
# Assertions
# -----------------------------------------------------------------------------
assert_container_running() {
    local container="$1"
    if [[ $(docker inspect -f '{{.State.Running}}' "${container}" 2>/dev/null) == "true" ]]; then
        log_info "Container '${container}' is running"
        return 0
    else
        log_error "Container '${container}' is not running"
        return 1
    fi
}

assert_process_running() {
    local container="$1"
    local process="$2"
    if MSYS_NO_PATHCONV=1 docker exec "${container}" pgrep -f "${process}" > /dev/null 2>&1; then
        log_info "Process '${process}' is running"
        return 0
    else
        log_error "Process '${process}' is not running"
        return 1
    fi
}

assert_file_exists() {
    local container="$1"
    local file_path="$2"
    if MSYS_NO_PATHCONV=1 docker exec "${container}" test -f "${file_path}" 2>/dev/null; then
        log_info "File exists: ${file_path}"
        return 0
    else
        log_error "File does not exist: ${file_path}"
        return 1
    fi
}

assert_directory_exists() {
    local container="$1"
    local dir_path="$2"
    if MSYS_NO_PATHCONV=1 docker exec "${container}" test -d "${dir_path}" 2>/dev/null; then
        log_info "Directory exists: ${dir_path}"
        return 0
    else
        log_error "Directory does not exist: ${dir_path}"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Wait Functions
# -----------------------------------------------------------------------------
wait_for_log() {
    local container="$1"
    local pattern="$2"
    local timeout="${3:-60}"
    local elapsed=0

    while [[ ${elapsed} -lt ${timeout} ]]; do
        # Check docker logs
        if docker logs "${container}" 2>&1 | grep -qi "${pattern}"; then
            return 0
        fi
        # Also check the rust server log file inside container
        if docker_exec "${container}" grep -qi "${pattern}" /var/log/rust/rust-server.log 2>/dev/null; then
            return 0
        fi
        # Check supervisor stdout log
        if docker_exec "${container}" grep -qi "${pattern}" /var/log/rust/supervisor-rust.log 2>/dev/null; then
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    return 1
}

wait_for_container_healthy() {
    local container="$1"
    local timeout="${2:-300}"
    local elapsed=0

    while [[ ${elapsed} -lt ${timeout} ]]; do
        local health
        health=$(docker inspect -f '{{.State.Health.Status}}' "${container}" 2>/dev/null || echo "unknown")
        if [[ "${health}" == "healthy" ]]; then
            return 0
        fi
        sleep 10
        elapsed=$((elapsed + 10))
    done

    return 1
}

wait_for_port() {
    local container="$1"
    local port="$2"
    local protocol="${3:-tcp}"
    local timeout="${4:-60}"
    local elapsed=0

    while [[ ${elapsed} -lt ${timeout} ]]; do
        if [[ "${protocol}" == "tcp" ]]; then
            if docker_exec "${container}" nc -z localhost "${port}" 2>/dev/null; then
                return 0
            fi
        else
            # For UDP, check /proc/net/udp
            local port_hex
            printf -v port_hex "%04X" "${port}"
            if docker_exec "${container}" cat /proc/net/udp 2>/dev/null | grep -qi ":${port_hex}"; then
                return 0
            fi
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    return 1
}

wait_for_process() {
    local container="$1"
    local process="$2"
    local timeout="${3:-60}"
    local elapsed=0

    while [[ ${elapsed} -lt ${timeout} ]]; do
        if MSYS_NO_PATHCONV=1 docker exec "${container}" pgrep -f "${process}" > /dev/null 2>&1; then
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    return 1
}
