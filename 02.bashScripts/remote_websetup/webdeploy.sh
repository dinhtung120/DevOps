#!/usr/bin/env bash
# =============================================================================
# Tên script:     deploy-to-hosts.sh
# Mô tả:          Copy & chạy script multios_websetup.sh trên nhiều remote host
# Yêu cầu:        SSH key-based auth (không dùng password)
#                 User remote phải có quyền sudo không cần password cho script
#                 hoặc cho các lệnh bên trong multios_websetup.sh
# =============================================================================

set -euo pipefail          # Dừng ngay khi có lỗi, biến chưa định nghĩa, pipe fail

# ── Cấu hình ──────────────────────────────────────────────────────────────────
readonly SCRIPT_LOCAL="multios_websetup.sh"
readonly REMOTE_USER="devops"
readonly REMOTE_TMP="/tmp"
readonly HOSTS_FILE="remhosts"

# Kiểm tra file tồn tại trước khi chạy
if [[ ! -f "$SCRIPT_LOCAL" ]]; then
    echo "LỖI: Không tìm thấy file $SCRIPT_LOCAL" >&2
    exit 1
fi

if [[ ! -f "$HOSTS_FILE" ]]; then
    echo "LỖI: Không tìm thấy file danh sách host: $HOSTS_FILE" >&2
    exit 1
fi

# ── Hàm helper ────────────────────────────────────────────────────────────────
err() {
    echo "ERROR: $*" >&2
    exit 1
}

info() {
    echo "INFO : $*"
}

run_on_host() {
    local host="$1"

    echo
    echo "#########################################################"
    echo "Host: $host"
    echo "#########################################################"

    # Copy script
    info "Đang copy script lên $host..."
    scp -q "$SCRIPT_LOCAL" "${REMOTE_USER}@${host}:${REMOTE_TMP}/" || {
        echo " → SCP thất bại" >&2
        return 1
    }

    # Chạy script với sudo
    info "Đang thực thi script trên $host..."
    ssh -q "${REMOTE_USER}@${host}" \
        "sudo bash ${REMOTE_TMP}/${SCRIPT_LOCAL}" || {
        echo " → Thực thi thất bại" >&2
        return 1
    }

    # Dọn dẹp
    info "Dọn dẹp file tạm trên $host..."
    ssh -q "${REMOTE_USER}@${host}" "sudo rm -f ${REMOTE_TMP}/${SCRIPT_LOCAL}"

    echo " → Hoàn tất trên $host"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    local failed=0

    # Đọc danh sách host (bỏ dòng trống và comment #)
    mapfile -t hosts < <(grep -vE '^\s*(#|$)' "$HOSTS_FILE")

    if [[ ${#hosts[@]} -eq 0 ]]; then
        err "File $HOSTS_FILE không chứa host nào hợp lệ"
    fi

    info "Tổng số host cần triển khai: ${#hosts[@]}"

    for host in "${hosts[@]}"; do
        host="${host##*( )}"          # trim leading space
        host="${host%%*( )}"          # trim trailing space

        [[ -z "$host" ]] && continue

        if run_on_host "$host"; then
            echo " [ OK ]"
        else
            echo " [ FAIL ]" >&2
            ((failed++))
        fi
    done

    echo
    if (( failed == 0 )); then
        info "Hoàn tất thành công tất cả host!"
    else
        err "Có $failed host thất bại"
    fi
}

# ── Chạy ──────────────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi