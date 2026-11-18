#!/usr/bin/env bash
# Host packages Longhorn needs on framework (Ubuntu 24.04) so pods there can
# attach Longhorn volumes. framework holds no replicas; this is only for the
# engine side. The CachyOS nodes got the same by hand (longhorn-plan.md).
#
#   open-iscsi   longhorn-manager won't start without iscsiadm; volumes reach
#                the pod as iSCSI block devices.
#   nfs-common   RWX volumes and the NFS backup target.
#
# Run on framework:
#   sudo ./longhorn-prereqs.sh
# Then the crash-looping longhorn-manager pod on framework recovers on its own
# (or delete it to skip the backoff).

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

apt-get update
apt-get install -y open-iscsi nfs-common

echo iscsi_tcp >/etc/modules-load.d/iscsi_tcp.conf
modprobe iscsi_tcp
systemctl enable --now iscsid

# multipathd (Ubuntu Server ships it) claims Longhorn's block devices and
# breaks mounts. Keep it off them if it's installed.
if systemctl list-unit-files multipathd.service >/dev/null 2>&1 &&
  ! grep -qs 'devnode "\^sd\[a-z0-9\]+"' /etc/multipath.conf; then
  cat >>/etc/multipath.conf <<'EOF'
blacklist {
    devnode "^sd[a-z0-9]+"
}
EOF
  systemctl restart multipathd
fi

iscsiadm --version
echo "Done. Longhorn's manager on framework should go Ready shortly."
