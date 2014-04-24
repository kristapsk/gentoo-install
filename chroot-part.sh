
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

# 1) check package names and set use flags if needed
emerge_list=""
while read tool_line; do
    if grep -qs "\[" <<< "$tool_line"; then
        tool="`echo "$tool_line" | sed "s/\[.*//"`"
        use_changes="`echo "$tool_line" | sed "s/.*\[//" | sed "s/\].*//" | tr ',' ' '`"
    else
        tool="$tool_line"
        use_changes=""
    fi
    if [ -d "/usr/portage/$tool" ]; then
        if [ "$use_changes" != "" ]; then
            echo "$tool $use_changes" >> /etc/portage/package.use
        fi
    else
        echo "Unknown / non-existing required package: $tool, aborting."
        if ! grep -qs "/" <<< "$tool"; then
            echo "Full package names must be specified, e.g. 'app-admin/syslog-ng', not 'syslog-ng'." 
        fi
        exit 1
    fi
done <<< "$SYSTEM_TOOLS"

# 2) emerge
emerge $emerge_list || exit 1

# 3) do specific things needed for each tool
# FixMe: hardcoded currently, may make this nicer in future

rc-update add sshd default

if grep -qs "app-admin/syslog-ng" <<< "$emerge_list"; then
    rc-update add syslog-ng default
elif grep -qs "app-admin/sysklogd" <<< "$emerge_list"; then
    rc-update add sysklogd default
elif grep -qs "app-admin/metalog" <<< "$emerge_list"; then
    rc-update add metalog default
fi

if grep -qs "sys-process/cronie" <<< "$emerge_list"; then
    rc-update add cronie default
fi

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

