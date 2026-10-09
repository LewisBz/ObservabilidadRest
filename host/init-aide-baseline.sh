#!/usr/bin/env bash
set -euo pipefail

# Builds the AIDE baseline. This scan is I/O heavy; run it once, off peak.

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

mkdir -p /var/lib/aide /var/log/aide

if command -v aideinit >/dev/null 2>&1; then
  aideinit -y -f
else
  aide --init
  if [[ -f /var/lib/aide/aide.db.new ]]; then
    cp -a /var/lib/aide/aide.db.new /var/lib/aide/aide.db
  elif [[ -f /var/lib/aide/aide.db.new.gz ]]; then
    cp -a /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
  fi
fi

echo "AIDE baseline stored under /var/lib/aide. Daily check writes /var/log/aide/aide-check.log."
