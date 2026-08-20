#!/usr/bin/env bash
#
# Minimal FUTU OpenD entrypoint for the self-hosted image.
#
# This renders the real OpenD ``<futu_opend>`` XML config that the binary reads
# via ``-cfg_file=``. Only the listen address, account id, and ports are plain
# env vars; the login password MD5 and the RSA key come from the ``*_FILE``
# secret interface so they never appear in image layers, process listings, or
# ordinary environment variables:
#
#   FUTU_ACCOUNT_ID            account id to sign in (optional hint)
#   FUTU_ACCOUNT_PWD_MD5_FILE  path to a file holding the login password MD5
#   FUTU_RSA_KEY_FILE          path to the PEM RSA key for encrypted gateway
#   FUTU_OPEND_IP              bind address (default: the container hostname,
#                              which under compose resolves to the internal IP)
#   FUTU_OPEND_PORT            OpenD API port (default 11111)
#   FUTU_OPEND_TELNET_PORT     OpenD telnet/2FA port (default 22222)
#
# The rendered config is written to a mode-0600 file under /tmp and unlinked on
# exit. The password MD5 is joined into the config exactly as OpenD requires
# (``<login_pwd_md5>``), but is never printed to stdout/stderr or written to
# the shared state volume. The RSA key path is referenced, not copied.

set -euo pipefail

OPEND_HOME="${OPEND_HOME:-/opt/futu-opend}"
USER_HOME="${OPEND_USER_HOME:-/home/futu}"
STATE_DIR="$USER_HOME/.com.futunn.FutuOpenD"
# OpenD binds to a hostname/IP, not loopback. Under internal bridge networking
# the container hostname resolves to the container's internal IP, which is
# exactly what the app reaches as `futu-opend` on the broker-internal network.
BIND_IP="${FUTU_OPEND_IP:-$(cat /etc/hostname)}"
API_PORT="${FUTU_OPEND_PORT:-11111}"
TELNET_PORT="${FUTU_OPEND_TELNET_PORT:-22222}"

# Make sure the state volume is owned by the operator (first run on a fresh
# volume). Propagate failures: an unwritable state dir means OpenD cannot keep
# its login/device cache.
mkdir -p "$STATE_DIR"
if [ "$(id -u)" = "10002" ]; then
  chown futu:futu "$STATE_DIR" 2>/dev/null || true
fi

# Locate the OpenD binary under the unpacked archive. OpenD arranges a
# per-version subdir; search for a trailing `FutuOpenD` executable.
OPEND_BIN="$(find "$OPEND_HOME" -type f -name FutuOpenD -perm -u+x 2>/dev/null | head -n 1 || true)"
if [ -z "${OPEND_BIN:-}" ]; then
  echo "FutuOpenD binary not found under $OPEND_HOME" >&2
  exit 1
fi

# Validate the secret-file interface: a configured password file must exist
# and be non-empty (the caller mounts it as a 'ro' file); an RSA key must exist
# if configured. Fail fast rather than start half-configured.
PWD_MD5=""
if [ -n "${FUTU_ACCOUNT_PWD_MD5_FILE:-}" ]; then
  if [ ! -r "$FUTU_ACCOUNT_PWD_MD5_FILE" ] || [ ! -s "$FUTU_ACCOUNT_PWD_MD5_FILE" ]; then
    echo "FUTU_ACCOUNT_PWD_MD5_FILE is not a readable non-empty file: $FUTU_ACCOUNT_PWD_MD5_FILE" >&2
    exit 1
  fi
  PWD_MD5="$(tr -d '[:space:]' < "$FUTU_ACCOUNT_PWD_MD5_FILE")"
  PWD_MD5="${PWD_MD5#md5hash:}"
fi

RSA_FILE=""
if [ -n "${FUTU_RSA_KEY_FILE:-}" ]; then
  if [ ! -r "$FUTU_RSA_KEY_FILE" ]; then
    echo "FUTU_RSA_KEY_FILE is not a readable file: $FUTU_RSA_KEY_FILE" >&2
    exit 1
  fi
  RSA_FILE="$FUTU_RSA_KEY_FILE"
fi

# Render the real OpenD config under a mode-0600 temp file.
TMP_CONF="$(mktemp /tmp/FutuOpenD.XXXXXX.xml)"
trap 'rm -f "$TMP_CONF"' EXIT
chmod 0600 "$TMP_CONF"
{
  echo '<?xml version="1.0" encoding="utf-8"?>'
  echo '<futu_opend>'
  echo "  <ip>${BIND_IP}</ip>"
  echo "  <api_port>${API_PORT}</api_port>"
  echo "  <telnet_ip>${BIND_IP}</telnet_ip>"
  echo "  <telnet_port>${TELNET_PORT}</telnet_port>"
  if [ -n "${FUTU_ACCOUNT_ID:-}" ]; then
    echo "  <login_account>${FUTU_ACCOUNT_ID}</login_account>"
  fi
  if [ -n "$PWD_MD5" ]; then
    echo "  <login_pwd_md5>${PWD_MD5}</login_pwd_md5>"
  fi
  if [ -n "$RSA_FILE" ]; then
    echo "  <rsa_private_key>${RSA_FILE}</rsa_private_key>"
  fi
  echo '  <log_level>info</log_level>'
  echo '</futu_opend>'
} > "$TMP_CONF"

echo "Starting FutuOpenD on ${BIND_IP}:${API_PORT} (password $([ -n "$PWD_MD5" ] && echo configured || echo unset), rsa $([ -n "$RSA_FILE" ] && echo configured || echo unset))"

# exec so OpenD becomes PID 1 and receives signals directly.
exec "$OPEND_BIN" -cfg_file="$TMP_CONF"
