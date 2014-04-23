
. /etc/profile
. inc.config.sh

num_cores="`nproc`"

echo --- Configuring Portage

emerge-webrsync
emerge --sync

echo --- Choosing the Right Profile
if [ "$SYSTEM_PROFILE" != "" ]; then
	echo ------ Switching system profile to $SYSTEM_PROFILE
	eselect profile set "$SYSTEM_PROFILE" || exit 1
	eselect profile list
fi

echo --- Switching timezone to $TIMEZONE
echo "$TIMEZONE" > /etc/timezone
emerge --config sys-libs/timezone-data

echo --- Configure locales
# Nothing for now

echo --- Configuring the Kernel
if [ "$KERNEL_EBUILD" == "" ]; then
	KERNEL_EBUILD=gentoo-sources
fi
emerge $KERNEL_EBUILD
cd /usr/src/linux
make localconfig
make -j$((num_cores + 1))
make modules_install
cp arch/x86/boot/bzImage /boot/kernel-auto

echo --- Installing Necessary System Tools
# FixME: Do the stuff

rc-update add sshd default

# FixMe: auto-detect those
rootdev=/dev/sda
rootpart=/dev/sda3
rootgrub="(hd0,0)"

echo --- Configuring the Bootloader
case $BOOTLOADER in
    grub2)
        echo ------ Using GRUB2
        emerge sys-boot/grub
        grub2-install $rootdev
    ;;
    grub-legacy)
        echo ------ Using GRUB Legacy
        echo ">=sys-boot/grub-2" >> /etc/portage/package.mask
        emerge sys-boot/grub:0
        echo "default 0" > /boot/grub/grub.conf
        echo "timeout 5" >> /boot/grub/grub.conf
        echo >> /boot/grub/grub.conf
        echo "title Gentoo Linux (auto-installed default)" >> /boot/grub/grub.conf
        echo "root $rootgrub" >> /boot/grub/grub.conf
        echo "kernel /boot/kernel-auto root=$rootpart" >> /boot/grub/grub.conf
        grep -v rootfs /proc/mounts > /etc/mtab
        grub-install --no-floppy $rootdev
    ;;
    *)
        echo FATAL: Unknown bootloader: $BOOTLOADER
        exit 1
    ;;
esac

echo "-- All (not yet) DONE, reboot to finish."

