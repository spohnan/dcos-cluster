#!/usr/bin/env bash
#
# Configure the instance EBS data disk as the docker storage volume using the OverlayFS driver
#

set -e

# If this has already been created assume we've run before and exit
if [ -e /dev/docker/docker ]; then
  exit
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

systemctl stop docker
yum -y install lvm2
echo "overlay" >> /etc/modules-load.d/overlay.conf
modprobe overlay
mkdir -p /etc/systemd/system/docker.service.d
echo "[Service]
ExecStart=
ExecStart=/bin/docker daemon --storage-driver=overlay -H fd://" >> /etc/systemd/system/docker.service.d/override.conf
systemctl daemon-reload

# Lists all block devices and skips the first two lines containing a column label and /dev/sda boot volume
DATA_VOLUMES=$(lsblk -d | awk '{ print $1 }' | grep -v "loop" | tail -n+3)

for v in $DATA_VOLUMES; do
  parted -s -- /dev/$v mklabel gpt
  parted -s -- /dev/$v mkpart primary ext4 2048s 100%
  parted -s -- /dev/$v set 1 lvm on
  sleep 2
  pvcreate /dev/${v}1
  vgcreate docker /dev/${v}1
  lvcreate --name docker --extents 100%FREE docker
  mkfs.xfs /dev/docker/docker
  sleep 2
  if [ ! -d /var/lib/docker ]; then
     mkdir /var/lib/docker
  fi
  echo "/dev/docker/docker      /var/lib/docker                 xfs     defaults        0 0" >> /etc/fstab
  mount -a
  break
done

# pick up the new systemd config files and restart docker
systemctl start docker
echo "# Do not delete" > $SCRIPT_DIR/docker-data-volume.done
