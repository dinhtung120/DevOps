#!/usr/bin/env bash
# =============================================================================
# Deploy Tooplate template 2098_health trên Apache - Tương thích CentOS Stream 9 / RHEL 9 / Rocky 9 / AlmaLinux 9 / Ubuntu
# Đã thêm: Tự động mở port 80 (http) trong firewalld nếu cần
# =============================================================================

set -euo pipefail

# ── Cấu hình ────────────────────────────────────────────────────────────────
readonly URL="https://www.tooplate.com/zip-templates/2098_health.zip"
readonly ART_NAME="2098_health"
readonly TEMPDIR="/tmp/webfiles-$(date +%s)-$$"
readonly WEB_ROOT="/var/www/html"

# ── Helper ───────────────────────────────────────────────────────────────────
err()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "INFO : $*"; }

# ── Phát hiện family + package manager ──────────────────────────────────────
if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
fi

if [[ "${ID:-}" == "ubuntu" || "${ID_LIKE:-}" =~ debian ]]; then
    OS_FAMILY="debian"
    PKG_MGR="apt-get"
    WEB_PKG="apache2"
    SVC="apache2"
    WEB_USER="www-data"
else
    OS_FAMILY="redhat"
    if command -v dnf >/dev/null 2>&1; then
        PKG_MGR="dnf"
    else
        PKG_MGR="yum"
    fi
    WEB_PKG="httpd"
    SVC="httpd"
    WEB_USER="apache"
fi

info "OS family detected : $OS_FAMILY"
info "Web server: $WEB_PKG / $SVC"

# ── Cài đặt gói ─────────────────────────────────────────────────────────────
info "Cài đặt gói cần thiết..."
if [[ $OS_FAMILY == "debian" ]]; then
    sudo $PKG_MGR update -qq
    sudo DEBIAN_FRONTEND=noninteractive $PKG_MGR install -yqq wget unzip "$WEB_PKG"
else
    sudo $PKG_MGR makecache -q
    sudo $PKG_MGR install -y -q wget unzip "$WEB_PKG" firewalld   # đảm bảo firewalld có sẵn
fi

# ── Khởi động & enable service ──────────────────────────────────────────────
info "Khởi động và enable $SVC..."
sudo systemctl enable --now "$SVC" || err "Không start được $SVC"

# ── Mở port 80 trong firewall (chỉ áp dụng cho redhat family) ───────────────
if [[ $OS_FAMILY == "redhat" ]] && command -v firewall-cmd >/dev/null 2>&1; then
    info "Kiểm tra và cấu hình firewall (firewalld)..."
    
    # Kiểm tra zone active và liệt kê services hiện tại
    sudo firewall-cmd --list-all
    
    # Kiểm tra xem http đã có trong services chưa
    if ! sudo firewall-cmd --list-services | grep -q http; then
        info "Không tìm thấy dịch vụ 'http' → đang thêm..."
        sudo firewall-cmd --permanent --zone=public --add-service=http || err "Không thêm được service http"
        sudo firewall-cmd --reload || err "Reload firewall thất bại"
        info "Đã mở port 80 (http) thành công!"
    else
        info "Dịch vụ 'http' đã có sẵn trong firewall."
    fi
    
    # In lại để kiểm tra (có thể comment nếu không muốn verbose)
    sudo firewall-cmd --list-all
fi

# ── Deploy website ──────────────────────────────────────────────────────────
info "Deploy website..."

mkdir -p "$TEMPDIR" || err "Tạo thư mục tạm thất bại"
cd "$TEMPDIR"       || err "cd $TEMPDIR thất bại"

wget -q "$URL" || err "Tải file zip thất bại"
unzip -q "${ART_NAME}.zip" || err "Giải nén thất bại"

sudo rm -rf "${WEB_ROOT:?}"/*
sudo cp -r "${ART_NAME}"/* "$WEB_ROOT/" || err "Copy file thất bại"

# Fix quyền & SELinux
sudo chown -R "$WEB_USER:$WEB_USER" "$WEB_ROOT"
sudo chmod -R 755 "$WEB_ROOT"

if command -v restorecon >/dev/null 2>&1; then
    sudo restorecon -R -v "$WEB_ROOT" || true
fi

# Restart
info "Restart $SVC..."
sudo systemctl restart "$SVC"

# ── Kiểm tra kết quả ────────────────────────────────────────────────────────
echo
info "Trạng thái $SVC:"
sudo systemctl status "$SVC" --no-pager -l | head -n 12

echo
info "Một số file trong $WEB_ROOT:"
ls -la --color=auto "$WEB_ROOT" | head -n 15

# ── Cleanup ─────────────────────────────────────────────────────────────────
info "Dọn dẹp..."
cd / || true
rm -rf "$TEMPDIR"

info "Truy cập website tại: http://$(hostname -I | awk '{print $1}')/"
info "Nếu từ máy khác vẫn không truy cập được, kiểm tra firewall hoặc mạng VM."