#!/bin/sh
# Hysteria 2 installer for Alpine Linux with OpenRC.
#
# This script is intentionally POSIX-sh compatible: Alpine may only provide
# BusyBox ash and does not support the official systemd installer.

set -eu

BIN="/usr/local/bin/hysteria"
CONFIG_DIR="/etc/hysteria"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"
SERVICE="/etc/init.d/hysteria"
LOG_FILE="/var/log/hysteria.log"
ERROR_LOG_FILE="/var/log/hysteria.err"
RUN_USER="${HY2_RUN_USER:-hysteria}"
RUN_GROUP="root"
PORT="${HY2_PORT:-443}"
PASSWORD="${HY2_PASSWORD:-}"
DOMAIN="${HY2_DOMAIN:-}"
EMAIL="${HY2_EMAIL:-}"
HOST="${HY2_HOST:-}"
SNI="${HY2_SNI:-}"
MASQ_URL="${HY2_MASQ_URL:-https://www.bing.com/}"
OBFS_TYPE="${HY2_OBFS_TYPE:-}"
OBFS_PASSWORD="${HY2_OBFS_PASSWORD:-}"
VERSION="${HY2_VERSION:-latest}"
ARCH="${HY2_ARCH:-}"
NO_START="${HY2_NO_START:-0}"
REMOVE_USER="${HY2_REMOVE_USER:-0}"

DOWNLOAD_TMP=""
CONFIG_TMP=""
SERVICE_TMP=""

cleanup() {
    [ -z "$DOWNLOAD_TMP" ] || rm -f "$DOWNLOAD_TMP"
    [ -z "$CONFIG_TMP" ] || rm -f "$CONFIG_TMP"
    [ -z "$SERVICE_TMP" ] || rm -f "$SERVICE_TMP"
}
trap cleanup EXIT

die() {
    printf '%s\n' "[error] $*" >&2
    exit 1
}

info() {
    printf '%s\n' "[info] $*"
}

warn() {
    printf '%s\n' "[warn] $*" >&2
}

usage() {
    cat <<'EOF'
Hysteria 2 Alpine/OpenRC installer

Usage:
  sh hysteria2-alpine.sh              Install or upgrade and start the service
  sh hysteria2-alpine.sh --status     Show OpenRC status and binary version
  sh hysteria2-alpine.sh --print-node Print the generated node URI
  sh hysteria2-alpine.sh --remove     Stop and remove the service and files

Common environment variables:
  HY2_PORT=443                         UDP listen port
  HY2_PASSWORD=...                     Password; safe URI characters only
  HY2_HOST=example.com                 Host/IP used in the generated URI
  HY2_SNI=bing.com                     TLS SNI used by clients
  HY2_DOMAIN=example.com               Use ACME instead of a self-signed cert
  HY2_EMAIL=admin@example.com          Required with HY2_DOMAIN
  HY2_MASQ_URL=https://www.bing.com/   HTTP/3 masquerade target
  HY2_OBFS_TYPE=salamander             Optional: salamander or gecko
  HY2_OBFS_PASSWORD=...                Required only when obfuscation is enabled
  HY2_VERSION=latest                   latest or a release such as v2.9.2
  HY2_ARCH=amd64                       Override automatic architecture detection
  HY2_RUN_USER=hysteria                Service account; root is also supported
  HY2_NO_START=1                       Install files without starting OpenRC

The generated files are stored under /etc/hysteria/:
  config.yaml, client.yaml, node-uri.txt, and self-signed certificates if used.
EOF
}

require_root() {
    [ "$(id -u)" -eq 0 ] || die "run this script as root"
}

require_alpine() {
    [ -r /etc/os-release ] || die "/etc/os-release not found"
    # shellcheck disable=SC1091
    . /etc/os-release
    [ "${ID:-}" = "alpine" ] || die "this script targets Alpine Linux (detected: ${ID:-unknown})"
}

require_openrc() {
    command -v apk >/dev/null 2>&1 || die "apk not found"
    command -v rc-service >/dev/null 2>&1 || die "OpenRC rc-service not found"
    command -v rc-update >/dev/null 2>&1 || die "OpenRC rc-update not found"
}

contains_control_chars() {
    LC_ALL=C printf '%s' "$1" | LC_ALL=C grep -q '[[:cntrl:]]'
}

validate_password() {
    value="$1"
    label="$2"
    case "$value" in
        ''|*[!A-Za-z0-9._~-]*)
            die "$label may contain only A-Z a-z 0-9 . _ ~ - so it can be embedded safely in a URI"
            ;;
    esac
}

validate_port() {
    case "$PORT" in
        ''|*[!0-9]*) die "HY2_PORT must be a number: $PORT" ;;
    esac
    if [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        die "HY2_PORT must be between 1 and 65535"
    fi
}

validate_inputs() {
    validate_port

    case "$RUN_USER" in
        root|hysteria) ;;
        *) die "HY2_RUN_USER must be root or hysteria" ;;
    esac

    case "$OBFS_TYPE" in
        ''|salamander|gecko) ;;
        *) die "HY2_OBFS_TYPE must be salamander or gecko" ;;
    esac

    case "$DOMAIN" in
        *[!A-Za-z0-9.-]*) die "HY2_DOMAIN must be a plain DNS name" ;;
    esac

    case "$SNI" in
        *[!A-Za-z0-9._:-]*) die "HY2_SNI contains unsupported URI characters" ;;
    esac

    case "$HOST" in
        *[!A-Za-z0-9._:\[\]-]*) die "HY2_HOST contains unsupported URI characters" ;;
    esac

    case "$VERSION" in
        *[!A-Za-z0-9._/-]*) die "HY2_VERSION contains unsupported characters" ;;
    esac

    if contains_control_chars "$EMAIL" || contains_control_chars "$MASQ_URL"; then
        die "HY2_EMAIL and HY2_MASQ_URL must not contain control characters"
    fi

    if [ -n "$DOMAIN" ] && [ -n "${HY2_CERT_FILE:-}" ]; then
        die "do not combine HY2_DOMAIN with custom certificate files"
    fi

    if [ -n "${HY2_CERT_FILE:-}" ] || [ -n "${HY2_KEY_FILE:-}" ]; then
        if [ -z "${HY2_CERT_FILE:-}" ] || [ -z "${HY2_KEY_FILE:-}" ]; then
            die "set both HY2_CERT_FILE and HY2_KEY_FILE"
        fi
        [ -r "$HY2_CERT_FILE" ] || die "certificate is not readable: $HY2_CERT_FILE"
        [ -r "$HY2_KEY_FILE" ] || die "private key is not readable: $HY2_KEY_FILE"
    fi
}

yaml_quote() {
    # Single-quoted YAML strings escape a literal apostrophe by doubling it.
    printf '%s' "$1" | sed "s/'/''/g"
}

detect_arch() {
    if [ -n "$ARCH" ]; then
        case "$ARCH" in
            386|amd64|amd64-avx|arm|arm64|armv5|mipsle|mipsle-sf|riscv64|s390x) return ;;
            *) die "unsupported HY2_ARCH: $ARCH" ;;
        esac
    fi

    case "$(uname -m)" in
        x86_64|amd64) ARCH="amd64" ;;
        i386|i686|x86) ARCH="386" ;;
        aarch64|arm64) ARCH="arm64" ;;
        armv7*|armv6*|armv5*) ARCH="arm" ;;
        riscv64) ARCH="riscv64" ;;
        s390x) ARCH="s390x" ;;
        mipsel|mipsle) ARCH="mipsle" ;;
        *) die "unsupported architecture: $(uname -m)" ;;
    esac
}

extract_existing_password() {
    [ -f "$CONFIG_FILE" ] || return 0
    awk '
        /^auth:[[:space:]]*$/ { in_auth = 1; next }
        in_auth && /^[^[:space:]]/ { exit }
        in_auth && /^[[:space:]]+password:/ {
            sub(/^[[:space:]]+password:[[:space:]]*/, "")
            print
            exit
        }
    ' "$CONFIG_FILE" 2>/dev/null | sed "s/^['\"]//; s/['\"]$//" || true
}

make_password() {
    openssl rand -hex 16
}

ensure_dependencies() {
    info "Installing Alpine dependencies..."
    apk add --no-cache ca-certificates curl openssl >/dev/null
    if [ "$RUN_USER" != "root" ] && [ "$PORT" -lt 1024 ]; then
        apk add --no-cache libcap >/dev/null
    fi
    update-ca-certificates >/dev/null 2>&1 || true
}

ensure_service_user() {
    if [ "$RUN_USER" = "root" ]; then
        RUN_GROUP="root"
        return
    fi
    if ! id hysteria >/dev/null 2>&1; then
        adduser -S -D -H -s /sbin/nologin hysteria
    fi
    RUN_GROUP="$(id -gn hysteria)"
}

download_binary() {
    if [ "$VERSION" = "latest" ]; then
        DOWNLOAD_URL="https://download.hysteria.network/app/latest/hysteria-linux-${ARCH}"
    else
        case "$VERSION" in
            app/*) RELEASE_VERSION="${VERSION#app/}" ;;
            v*) RELEASE_VERSION="$VERSION" ;;
            *) RELEASE_VERSION="v$VERSION" ;;
        esac
        DOWNLOAD_URL="https://github.com/apernet/hysteria/releases/download/app/${RELEASE_VERSION}/hysteria-linux-${ARCH}"
    fi

    DOWNLOAD_TMP="${BIN}.download.$$"
    info "Downloading Hysteria 2 (${ARCH}, ${VERSION})..."
    curl -fsSL --retry 3 --connect-timeout 10 --max-time 300 -o "$DOWNLOAD_TMP" "$DOWNLOAD_URL" || die "download failed: $DOWNLOAD_URL"
    chmod 0755 "$DOWNLOAD_TMP"
    "$DOWNLOAD_TMP" version >/dev/null 2>&1 || die "downloaded file is not a valid Hysteria binary"
    mv -f "$DOWNLOAD_TMP" "$BIN"
    DOWNLOAD_TMP=""

    if [ "$RUN_USER" != "root" ] && [ "$PORT" -lt 1024 ]; then
        command -v setcap >/dev/null 2>&1 || die "setcap is unavailable; use HY2_RUN_USER=root or install libcap"
        setcap cap_net_bind_service=+ep "$BIN" || die "could not grant cap_net_bind_service to $BIN"
    fi
}

prepare_tls() {
    TLS_MODE="self-signed"
    CERT_PATH="${CONFIG_DIR}/server.crt"
    KEY_PATH="${CONFIG_DIR}/server.key"

    if [ -n "$DOMAIN" ]; then
        [ -n "$EMAIL" ] || die "HY2_EMAIL is required when HY2_DOMAIN is set"
        TLS_MODE="acme"
        return
    fi

    if [ -n "${HY2_CERT_FILE:-}" ]; then
        TLS_MODE="custom"
        cp -f "$HY2_CERT_FILE" "$CERT_PATH"
        cp -f "$HY2_KEY_FILE" "$KEY_PATH"
        return
    fi

    if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
        info "Generating a self-signed certificate (clients will use insecure=1)..."
        openssl req -x509 -newkey rsa:2048 -nodes \
            -keyout "$KEY_PATH" \
            -out "$CERT_PATH" \
            -days 3650 \
            -subj "/CN=${SNI:-hysteria}" >/dev/null 2>&1
    fi
}

write_config() {
    CONFIG_TMP="${CONFIG_FILE}.tmp.$$"
    {
        printf 'listen: :%s\n\n' "$PORT"
        case "$TLS_MODE" in
            acme)
                printf 'acme:\n'
                printf '  domains:\n'
                printf "    - '%s'\n" "$(yaml_quote "$DOMAIN")"
                printf "  email: '%s'\n\n" "$(yaml_quote "$EMAIL")"
                ;;
            custom|self-signed)
                printf 'tls:\n'
                printf "  cert: '%s'\n" "$(yaml_quote "$CERT_PATH")"
                printf "  key: '%s'\n" "$(yaml_quote "$KEY_PATH")"
                if [ "$TLS_MODE" = "self-signed" ]; then
                    printf '  sniGuard: disable\n'
                fi
                printf '\n'
                ;;
        esac

        printf 'auth:\n'
        printf '  type: password\n'
        printf "  password: '%s'\n" "$(yaml_quote "$PASSWORD")"

        if [ -n "$OBFS_TYPE" ]; then
            printf '\nobfs:\n'
            printf '  type: %s\n' "$OBFS_TYPE"
            printf '  %s:\n' "$OBFS_TYPE"
            printf "    password: '%s'\n" "$(yaml_quote "$OBFS_PASSWORD")"
        fi

        printf '\nmasquerade:\n'
        printf '  type: proxy\n'
        printf '  proxy:\n'
        printf "    url: '%s'\n" "$(yaml_quote "$MASQ_URL")"
        printf '    rewriteHost: true\n'
    } > "$CONFIG_TMP"
    chmod 0640 "$CONFIG_TMP"
    mv -f "$CONFIG_TMP" "$CONFIG_FILE"
    CONFIG_TMP=""
}

write_service() {
    SERVICE_TMP="${SERVICE}.tmp.$$"
    {
        printf '%s\n' '#!/sbin/openrc-run'
        printf '%s\n' '# Generated by hysteria2-alpine.sh; edit the environment and rerun the installer.'
        printf 'name="hysteria"\n'
        printf 'description="Hysteria 2 proxy server"\n'
        printf 'command="%s"\n' "$BIN"
        printf 'command_args="server -c %s"\n' "$CONFIG_FILE"
        printf 'command_user="%s:%s"\n' "$RUN_USER" "$RUN_GROUP"
        printf 'command_background=true\n'
        # shellcheck disable=SC2016
        printf 'pidfile="/run/$RC_SVCNAME.pid"\n'
        printf 'output_log="%s"\n' "$LOG_FILE"
        printf 'error_log="%s"\n' "$ERROR_LOG_FILE"
        printf '\n'
        printf '%s\n' 'depend() {'
        printf '%s\n' '    need net'
        printf '%s\n' '    after firewall'
        printf '%s\n' '}'
        printf '\n'
        printf '%s\n' 'start_pre() {'
        printf '    [ -x "%s" ] || return 1\n' "$BIN"
        printf '    [ -r "%s" ] || return 1\n' "$CONFIG_FILE"
        printf '}\n'
    } > "$SERVICE_TMP"
    chmod 0755 "$SERVICE_TMP"
    mv -f "$SERVICE_TMP" "$SERVICE"
    SERVICE_TMP=""
}

format_uri_host() {
    case "$HOST" in
        \[*\]) printf '%s' "$HOST" ;;
        *:*) printf '[%s]' "$HOST" ;;
        *) printf '%s' "$HOST" ;;
    esac
}

write_client_files() {
    URI_HOST="$(format_uri_host)"
    QUERY="sni=${SNI}"
    if [ "$TLS_MODE" = "self-signed" ]; then
        QUERY="${QUERY}&insecure=1"
    fi
    if [ -n "$OBFS_TYPE" ]; then
        QUERY="${QUERY}&obfs=${OBFS_TYPE}&obfs-password=${OBFS_PASSWORD}"
    fi

    NODE_URI="hysteria2://${PASSWORD}@${URI_HOST}:${PORT}/?${QUERY}#Alpine-Hysteria2"
    NODE_URI_FILE="${CONFIG_DIR}/node-uri.txt"
    CLIENT_FILE="${CONFIG_DIR}/client.yaml"

    umask 077
    printf '%s\n' "$NODE_URI" > "$NODE_URI_FILE"
    {
        printf 'server: %s:%s\n' "$URI_HOST" "$PORT"
        printf 'auth: %s\n' "$PASSWORD"
        printf 'tls:\n'
        printf '  sni: %s\n' "$SNI"
        if [ "$TLS_MODE" = "self-signed" ]; then
            printf '  insecure: true\n'
        fi
        if [ -n "$OBFS_TYPE" ]; then
            printf 'obfs:\n'
            printf '  type: %s\n' "$OBFS_TYPE"
            printf '  %s:\n' "$OBFS_TYPE"
            printf '    password: %s\n' "$OBFS_PASSWORD"
        fi
        printf 'socks5:\n'
        printf '  listen: 127.0.0.1:1080\n'
    } > "$CLIENT_FILE"

    chmod 0600 "$NODE_URI_FILE" "$CLIENT_FILE"
}

detect_host() {
    if [ -n "$HOST" ]; then
        return
    fi
    if [ -n "$DOMAIN" ]; then
        HOST="$DOMAIN"
        return
    fi

    for endpoint in \
        https://api.ipify.org \
        https://ifconfig.me/ip \
        https://ipinfo.io/ip; do
        HOST="$(curl -fsSL --max-time 5 "$endpoint" 2>/dev/null || true)"
        [ -n "$HOST" ] && return
    done
    HOST="YOUR_SERVER_IP"
    warn "could not detect the public IP; set HY2_HOST and rerun to regenerate a usable URI"
}

install_or_upgrade() {
    require_root
    require_alpine
    require_openrc
    validate_inputs
    ensure_dependencies

    if [ -z "$PASSWORD" ] && [ -f "$CONFIG_FILE" ]; then
        PASSWORD="$(extract_existing_password)"
    fi
    [ -n "$PASSWORD" ] || PASSWORD="$(make_password)"
    validate_password "$PASSWORD" "HY2_PASSWORD"

    if [ -n "$OBFS_TYPE" ]; then
        [ -n "$OBFS_PASSWORD" ] || OBFS_PASSWORD="$(make_password)"
        validate_password "$OBFS_PASSWORD" "HY2_OBFS_PASSWORD"
    fi

    detect_arch
    ensure_service_user
    mkdir -p "$CONFIG_DIR"
    detect_host
    [ -n "$SNI" ] || SNI="${DOMAIN:-bing.com}"
    validate_inputs
    prepare_tls

    if [ -f "$CONFIG_FILE" ]; then
        BACKUP_FILE="${CONFIG_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
        cp -p "$CONFIG_FILE" "$BACKUP_FILE"
        chmod 0600 "$BACKUP_FILE"
        info "Existing config backed up to $BACKUP_FILE"
    fi

    download_binary
    write_config
    write_service

    if [ "$RUN_USER" = "root" ]; then
        chown -R root:root "$CONFIG_DIR"
        chmod 0700 "$CONFIG_DIR"
    else
        chown -R "$RUN_USER:$RUN_GROUP" "$CONFIG_DIR"
        chmod 0750 "$CONFIG_DIR"
    fi
    chmod 0640 "$CONFIG_FILE"
    [ "$TLS_MODE" = "acme" ] || chmod 0600 "${CONFIG_DIR}/server.key"

    touch "$LOG_FILE" "$ERROR_LOG_FILE"
    chown "$RUN_USER:$RUN_GROUP" "$LOG_FILE" "$ERROR_LOG_FILE"
    chmod 0640 "$LOG_FILE" "$ERROR_LOG_FILE"
    write_client_files
    chown "$RUN_USER:$RUN_GROUP" "${CONFIG_DIR}/node-uri.txt" "${CONFIG_DIR}/client.yaml"
    chmod 0600 "${CONFIG_DIR}/node-uri.txt" "${CONFIG_DIR}/client.yaml"

    rc-update add hysteria default >/dev/null
    if [ "$NO_START" = "1" ]; then
        warn "HY2_NO_START=1 set; files installed but service was not started"
    else
        rc-service hysteria stop >/dev/null 2>&1 || true
        if ! rc-service hysteria start; then
            warn "service failed to start; recent logs:"
            tail -30 "$LOG_FILE" "$ERROR_LOG_FILE" 2>/dev/null || true
            die "Hysteria 2 did not start"
        fi
        sleep 1
        if ! rc-service hysteria status >/dev/null 2>&1; then
            tail -30 "$LOG_FILE" "$ERROR_LOG_FILE" 2>/dev/null || true
            die "OpenRC did not report hysteria as started"
        fi
    fi

    printf '\n%s\n' 'Hysteria 2 installation completed.'
    printf '%s\n' "  Binary:  $BIN"
    printf '%s\n' "  Config:  $CONFIG_FILE"
    printf '%s\n' "  Service: hysteria (OpenRC, default runlevel)"
    printf '%s\n' "  Listen:  UDP $PORT"
    printf '%s\n' "  User:    $RUN_USER"
    printf '%s\n' "  Node URI:"
    printf '%s\n' "    $NODE_URI"
    printf '%s\n' "  Saved URI: ${CONFIG_DIR}/node-uri.txt"
    printf '%s\n' "  Client config: ${CONFIG_DIR}/client.yaml"
    printf '%s\n' "  Check:   sh $0 --status"
    printf '%s\n' "  Firewall: allow UDP $PORT$(if [ "$TLS_MODE" = "acme" ]; then printf ' and TCP 80 for ACME'; fi)"
}

status() {
    require_root
    require_openrc
    rc-service hysteria status
    if [ -x "$BIN" ]; then
        "$BIN" version 2>/dev/null || true
    fi
    if [ -f "$CONFIG_DIR/node-uri.txt" ]; then
        printf '%s\n' "Node URI file: $CONFIG_DIR/node-uri.txt"
    fi
}

print_node() {
    require_root
    [ -f "$CONFIG_DIR/node-uri.txt" ] || die "node URI not found: $CONFIG_DIR/node-uri.txt"
    cat "$CONFIG_DIR/node-uri.txt"
}

remove_installation() {
    require_root
    require_alpine
    require_openrc

    rc-service hysteria stop >/dev/null 2>&1 || true
    rc-update del hysteria default >/dev/null 2>&1 || true
    rm -f "$SERVICE" "$BIN"
    rm -rf "$CONFIG_DIR"
    rm -f "$LOG_FILE" "$ERROR_LOG_FILE"

    if [ "$REMOVE_USER" = "1" ] && id hysteria >/dev/null 2>&1; then
        deluser hysteria >/dev/null 2>&1 || true
    fi
    info "Hysteria 2 and its OpenRC service were removed"
}

ACTION="install"
case "${1:-}" in
    ''|install|upgrade) ACTION="install" ;;
    --help|-h|help) usage; exit 0 ;;
    --status|status) ACTION="status" ;;
    --print-node|print-node) ACTION="print-node" ;;
    --remove|remove) ACTION="remove" ;;
    *) usage >&2; die "unknown argument: $1" ;;
esac

case "$ACTION" in
    install) install_or_upgrade ;;
    status) status ;;
    print-node) print_node ;;
    remove) remove_installation ;;
esac
