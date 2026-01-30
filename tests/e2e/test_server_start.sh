#!/bin/bash
# =============================================================================
# E2E Test: Server Start
# Verifies that the server starts correctly and becomes ready
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../test_helpers.sh"

TEST_NAME="server_start"

# -----------------------------------------------------------------------------
# Test: Server Start
# -----------------------------------------------------------------------------
test_server_start() {
    log_test_start "${TEST_NAME}"

    # Verify container is running
    assert_container_running "rust-server"

    # Check that steamcmd update ran
    log_info "Checking for SteamCMD update execution"
    if wait_for_log "rust-server" "Starting Rust server update" 120; then
        log_info "SteamCMD update started"
    else
        log_warn "SteamCMD update log not found (may have used cached files)"
    fi

    # Wait for server binary to be present
    log_info "Checking for server binary"
    local attempts=0
    local max_attempts=60

    while [[ ${attempts} -lt ${max_attempts} ]]; do
        # First check if container is still running
        if [[ $(docker inspect -f '{{.State.Running}}' rust-server 2>/dev/null) != "true" ]]; then
            log_error "Container stopped unexpectedly during startup"
            log_error "=== Container Logs ==="
            docker logs rust-server 2>&1 || true
            log_error "=== End Container Logs ==="
            return 1
        fi

        # Check for server binary
        if MSYS_NO_PATHCONV=1 docker exec rust-server test -f /opt/rust/server/RustDedicated 2>/dev/null; then
            log_info "Server binary found"
            break
        fi
        sleep 5
        attempts=$((attempts + 1))
    done

    if [[ ${attempts} -ge ${max_attempts} ]]; then
        log_error "Server binary not found after ${max_attempts} attempts"
        log_error "=== Container Logs ==="
        docker logs rust-server 2>&1 || true
        log_error "=== End Container Logs ==="
        return 1
    fi

    # Wait for server to start (look for startup complete message or other success indicators)
    log_info "Waiting for server to initialize (this may take several minutes)"
    log_info "Looking for 'Server startup complete' or 'SteamServer' in logs..."

    # First try the standard message
    if wait_for_log "rust-server" "Server startup complete" 600; then
        log_success "Server initialized successfully (startup complete message found)"
    else
        # Try alternative success indicators
        log_info "Standard startup message not found, checking alternative indicators..."

        if wait_for_log "rust-server" "SteamServer" 60; then
            log_success "Server initialized (SteamServer message found)"
        else
            # Check if server process is at least running
            if MSYS_NO_PATHCONV=1 docker exec rust-server pgrep -f RustDedicated > /dev/null 2>&1; then
                log_warn "Server process is running but startup messages not found"
                log_info "=== Recent container logs ==="
                docker logs rust-server --tail 30 2>&1 || true
                log_info "=== End recent logs ==="
                log_warn "Proceeding - server process is active"
            else
                log_error "Server process is not running"
                log_error "=== Container logs ==="
                docker logs rust-server --tail 100 2>&1 || true
                log_error "=== End container logs ==="

                # Show running processes for debugging
                log_info "=== Running processes ==="
                MSYS_NO_PATHCONV=1 docker exec rust-server ps aux 2>&1 || true
                log_info "=== End processes ==="
                return 1
            fi
        fi
    fi

    # Verify server process is running
    log_info "Verifying server process"
    assert_process_running "rust-server" "RustDedicated"

    log_test_pass "${TEST_NAME}"
    return 0
}

# Run test
test_server_start
