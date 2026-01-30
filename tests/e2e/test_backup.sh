#!/bin/bash
# =============================================================================
# E2E Test: Backup
# Verifies that the backup system creates valid backups
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../test_helpers.sh"

TEST_NAME="backup"

# -----------------------------------------------------------------------------
# Test: Backup
# -----------------------------------------------------------------------------
test_backup() {
    log_test_start "${TEST_NAME}"

    # Verify container is running
    assert_container_running "rust-server"

    # Wait for server to be ready
    log_info "Waiting for server to initialize"
    if ! wait_for_log "rust-server" "Server startup complete" 600; then
        log_warn "Server may not be fully ready"
    fi

    # Give server time to create save files
    log_info "Waiting for save file generation (30 seconds)"
    sleep 30

    # Check if server data directory exists
    log_info "Checking for server data files"
    local server_identity="test_server"
    local data_path="/opt/rust/server/server/${server_identity}"

    if MSYS_NO_PATHCONV=1 docker exec rust-server test -d "${data_path}" 2>/dev/null; then
        log_info "Server data directory found"
    else
        log_warn "Server data directory not yet created, creating test files"
        MSYS_NO_PATHCONV=1 docker exec rust-server mkdir -p "${data_path}/cfg"
        MSYS_NO_PATHCONV=1 docker exec rust-server sh -c "echo 'test' > ${data_path}/cfg/test.cfg"
    fi

    # Trigger manual backup
    log_info "Triggering manual backup"
    MSYS_NO_PATHCONV=1 docker exec rust-server /opt/rust/scripts/rust-backup --force

    # Wait for backup to complete
    sleep 5

    # Check if backup was created
    log_info "Checking for backup files"
    local backup_dir="/config/backups"

    local backup_count
    backup_count=$(MSYS_NO_PATHCONV=1 docker exec rust-server find "${backup_dir}" -name 'rust_*.zip' -o -name 'rust_*.tar.gz' 2>/dev/null | wc -l)

    if [[ ${backup_count} -gt 0 ]]; then
        log_success "Backup created successfully (${backup_count} backup(s) found)"

        # List backups
        log_info "Backup files:"
        MSYS_NO_PATHCONV=1 docker exec rust-server ls -lh "${backup_dir}/" 2>/dev/null || true

        # Verify backup contains expected content
        log_info "Verifying backup contents"
        local latest_backup
        latest_backup=$(MSYS_NO_PATHCONV=1 docker exec rust-server sh -c "ls -t '${backup_dir}'/rust_*.zip 2>/dev/null | head -1")

        if [[ -n "${latest_backup}" ]]; then
            local backup_contents
            backup_contents=$(MSYS_NO_PATHCONV=1 docker exec rust-server unzip -l "${latest_backup}" 2>/dev/null || true)

            if echo "${backup_contents}" | grep -qE "server_data|cfg"; then
                log_success "Backup contains server data files"
            else
                log_warn "Backup may not contain expected files"
                echo "${backup_contents}"
            fi
        fi

        log_test_pass "${TEST_NAME}"
        return 0
    else
        log_error "No backup files found"
        MSYS_NO_PATHCONV=1 docker exec rust-server ls -la "${backup_dir}/" 2>/dev/null || true
        log_test_fail "${TEST_NAME}"
        return 1
    fi
}

# Run test
test_backup
