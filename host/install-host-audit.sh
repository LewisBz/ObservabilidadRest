#!/usr/bin/env bash
set -euo pipefail

# Installs auditd, AIDE, snoopy and tlog on Ubuntu.
# Does not initialize the AIDE baseline (run init-aide-baseline.sh afterwards).
# Does not change the root shell. Does not install Cockpit.

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y auditd audispd-plugins aide snoopy tlog

install -m 640 "${SCRIPT_DIR}/auditd/auditd.conf" /etc/audit/auditd.conf
install -d -m 755 /etc/audit/rules.d
install -m 640 "${SCRIPT_DIR}/auditd/rules.d/99-observability.rules" /etc/audit/rules.d/99-observability.rules

if [[ -d /etc/aide/aide.conf.d ]]; then
  install -m 644 "${SCRIPT_DIR}/aide/99_observability" /etc/aide/aide.conf.d/99_observability
else
  echo "AIDE drop-in directory missing; append ${SCRIPT_DIR}/aide/99_observability to /etc/aide/aide.conf" >&2
fi
install -m 644 "${SCRIPT_DIR}/aide/cron.d" /etc/cron.d/aide-observability

if [[ -f /etc/snoopy.ini ]]; then
  install -m 644 "${SCRIPT_DIR}/snoopy/snoopy.ini" /etc/snoopy.ini
elif [[ -f /etc/snoopy/snoopy.ini ]]; then
  install -m 644 "${SCRIPT_DIR}/snoopy/snoopy.ini" /etc/snoopy/snoopy.ini
else
  install -m 644 "${SCRIPT_DIR}/snoopy/snoopy.ini" /etc/snoopy.ini
fi

if command -v snoopy-enable >/dev/null 2>&1; then
  snoopy-enable || true
fi

install -d -m 755 /etc/tlog
install -m 644 "${SCRIPT_DIR}/tlog/tlog-rec-session.conf" /etc/tlog/tlog-rec-session.conf

augenrules --load || true
systemctl enable --now auditd
systemctl restart auditd

echo
echo "Host audit packages are installed. Next steps:"
echo "  1. sudo ${SCRIPT_DIR}/init-aide-baseline.sh"
echo "  2. For selected admin users (never root):"
echo "       sudo usermod -s /usr/bin/tlog-rec-session USER"
echo "  3. After the audit rules look correct, append -e 2 and reload (requires reboot to unlock)."
echo "  4. Do not install Cockpit on the public VPS. If it is already present, bind it to 127.0.0.1."
echo "  5. Restart Alloy so it can tail /var/log/audit/audit.log:"
echo "       docker compose restart alloy"
