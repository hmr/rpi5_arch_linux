#!/usr/bin/env bash
# vim: set ft=sh syn=bash ts=4 sw=4 :

# Script to make Arch Linux installation media bootable on Raspberry Pi 6
# Derived from "https://kiljan.org/2023/11/24/arch-linux-arm-on-a-raspberry-pi-5-model-b/"

set -eu

##### Configuration
SDDEV=/dev/mmcblk0
SDPARTBOOT="${SDDEV}p1"
SDPARTROOT="${SDDEV}p2"
SDMOUNT=/mnt/sd
DOWNLOADDIR=/tmp/pi

##### Check privilege
if [[ $(id -u) -ne 0 ]]; then
	echo "Run this script as root"
	exit
fi

##### Check if the media is mounted
if mount | grep -q "${SDDEV}"; then
	echo "The target media is mounted"
	exit
fi

##### Confirmation
echo "====================================================================="
echo "[WARNING] All the data in ${SDDEV} will be deleted. Are you sure?"
echo "====================================================================="
read -r

##### Check installation
PKGS=("curl" "libarchive-tools" "fdisk" "dosfstools" "e2fsprogs" "grep") 
for PKG in "${PKGS[@]}"; do
	echo "Checking installation: ${PKG}"
	if ! apt show "${PKG}" 2>/dev/null | grep -q "APT-Manual-Installed"; then
		echo "Installing ${PKG}"
		apt install -y "${PKG}"
	fi
done

##### Latest Arch Linux distribution
DISTPKG="ArchLinuxARM-rpi-aarch64-latest.tar.gz"
DISTURL="http://os.archlinuxarm.org/os/${DISTPKG}"

##### Latest RPi kernel package
# RPIKPKG="$(curl -sL "http://mirror.archlinuxarm.org/aarch64/core/" | grep -oP "linux-rpi-16k-\d+\.\d+\.\d+-\d+-aarch64.pkg.tar.xz" | head -n 1)"
RPIKPKG="$(curl -sL "http://mirror.archlinuxarm.org/aarch64/core/" | grep -oP "linux-rpi-\d+\.\d+\.\d+-\d+-aarch64.pkg.tar.xz" | head -n 1)"
RPIKRNLURL="http://mirror.archlinuxarm.org/aarch64/core/${RPIKPKG}"

echo
echo "Arch Linux Image: ${DISTURL}"
echo "Rpi Kernel Pkg  : ${RPIKRNLURL}"
echo

##### Unmount SD card
set +e
umount -R "${SDMOUNT}" >& /dev/null
set -e

##### Download Arch Linux install image
mkdir -p $DOWNLOADDIR
if [[ ! -e ${DOWNLOADDIR}/${DISTPKG} ]]; then
	echo "Downloading Arch Linux distribution"
	(
	cd $DOWNLOADDIR && \
		curl -JLO $DISTURL
	)
	echo
fi

##### Make partitions
echo "Making partitions"
sfdisk --quiet --wipe always $SDDEV << EOF
,256M,0c,
,,,
EOF

##### Format boot partition
echo "Formatting ${SDPARTBOOT} as vfat"
mkfs.vfat -F 32 $SDPARTBOOT
echo

##### Format root partition
echo "Formatting ${SDPARTROOT} as ext4"
mkfs.ext4 -E lazy_itable_init=0,lazy_journal_init=0 -F $SDPARTROOT

##### Mount the partitions
echo "Mounting root partition as ${SDMOUNT}"
mkdir -p ${SDMOUNT}
mount ${SDPARTROOT} ${SDMOUNT}
echo "Mounting boot partition as ${SDMOUNT}/boot"
mkdir -p ${SDMOUNT}/boot
mount ${SDPARTBOOT} ${SDMOUNT}/boot

##### Untar the installation media into SD card
echo "Extracting distribution files into ${SDMOUNT}"
bsdtar -xpf "${DOWNLOADDIR}/${DISTPKG}" -C "${SDMOUNT}"

##### Delete all the boot partition files
echo "Deleting all the boot partition files"
rm -rf ${SDMOUNT:?}/boot/*
echo

##### Download Raspberry Pi Foundation's kernel package
mkdir -p ${DOWNLOADDIR}/linux-rpi
pushd ${DOWNLOADDIR}/linux-rpi >& /dev/null
if [[ ! -e ${RPIKPKG} ]]; then
	echo "Downloading RPi kernel package"
	curl -JLO "${RPIKRNLURL}"
	echo
fi

##### Untar the RPi kernel package
echo "Extracting RPi kernel package files into ${SDMOUNT}/boot"
tar xf "${RPIKPKG}"
cp -rf boot/* ${SDMOUNT}/boot/
popd >& /dev/null

sync && umount -R "${SDMOUNT}"

echo "Done!"
