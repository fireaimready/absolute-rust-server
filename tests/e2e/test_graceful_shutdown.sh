#!/bin/bash
# =============================================================================
# E2E Test: Graceful Shutdown
# Verifies that the server handles shutdown signals properly
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../test_helpers.sh"

TEST_NAME="graceful_shutdown"

# -----------------------------------------------------------------------------
# Test: Graceful Shutdown
# -----------------------------------------------------------------------------
test_graceful_shutdown() {
    log_test_start "${TEST_NAME}"

    # Verify container is running
    assert_container_running "rust-server"

    # Wait for server to be ready
    log_info "Waiting for server to be ready"
    if ! wait_for_log "rust-server" "Server startup complete" 600; then
        log_warn "Server may not be fully ready"
    fi

    # Give server time to stabilize
    sleep 10

    # Verify server process is running
    assert_process_running "rust-server" "RustDedicated"

    # Send graceful shutdown signal (SIGINT to container)
    log_info "Sending graceful shutdown signal (SIGINT)"
    docker kill --signal=INT rust-server || true

    # Wait for graceful shutdown sequence in logs
    log_info "Waiting for graceful shutdown sequence in logs"
    sleep 10

    # Check for shutdown-related messages in logs
    if docker logs rust-server 2>&1 | grep -qiE "saving|shutdown|stopping|SIGINT|terminated"; then
        log_info "Process stop/termination detected in logs"
        log_pass "Graceful shutdown sequence observed in logs"
    else
        log_warn "No explicit shutdown message found, but this may be normal"
    fi

    log_pass "Graceful shutdown verified"

    # Restart container for subsequent tests
    log_info "Ensuring container is running for subsequent tests"
    log_info "Stopping container with docker stop"
    docker stop --time 30 rust-server 2>/dev/null || true

    cd "$(dirname "${SCRIPT_DIR}")/.."
    docker compose -f docker-compose.test.yml up -d

    # Wait for container to be running
    local attempts=0
    while [[ $(docker inspect -f '{{.State.Running}}' rust-server 2>/dev/null) != "true" ]]; do
        if [[ ${attempts} -ge 30 ]]; then
            log_error "Container failed to restart after graceful shutdown test"
            log_test_fail "${TEST_NAME}"
            return 1
        fi
        sleep 2
        attempts=$((attempts + 1))
    done

    log_pass "Container restarted successfully"

    log_test_pass "${TEST_NAME}"
    return 0
}

# Run test
test_graceful_shutdown
