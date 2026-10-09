# Daily AIDE check at 03:30. I/O is high during the scan; keep it off peak.
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

30 3 * * * root mkdir -p /var/log/aide && /usr/bin/aide --check > /var/log/aide/aide-check.log 2>&1
