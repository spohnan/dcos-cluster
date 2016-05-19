#!/usr/bin/env bash
#
# Configure the instance EBS data disk as the docker storage volume using the OverlayFS driver
#

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

systemctl stop docker
yum -y install lvm2
echo "overlay" >> /etc/modules-load.d/overlay.conf
modprobe overlay
mkdir -p /etc/systemd/system/docker.service.d
rm -rf /var/lib/docker/*
echo "[Service]
ExecStart=
ExecStart=/bin/docker daemon --storage-driver=overlay -H fd://" >> /etc/systemd/system/docker.service.d/override.conf

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
  echo "/dev/docker/docker      /var/lib/docker                 xfs     defaults        0 0" >> /etc/fstab
  mount -a
  break
done

systemctl start docker
echo "# Do not delete" > $SCRIPT_DIR/docker-data-volume.done
