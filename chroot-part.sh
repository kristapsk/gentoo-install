echo "This script is not supposed to be launched directly!"
echo "Check README.txt and use gentoo_install.sh instead."
exit

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


if [ "$LOCALES" != "" ]; then
    echo --- Configuring locale
    while read locale_line; do
        if [ "$locale_line" != "" ]; then
            echo "$locale_line" >> /etc/locale.gen
        fi
    done <<< "$LOCALES";
    locale-gen
    if [ "$DEFAULT_LOCALE" != "" ]; then
        eselect locale set $DEFAULT_LOCALE
        env-update && . /etc/profile
    fi
fi


echo --- Configuring the Kernel

if [ "$KERNEL_EBUILD" == "" ]; then
	KERNEL_EBUILD=gentoo-sources
fi
emerge $KERNEL_EBUILD
cd /usr/src/linux
if [ -f /usr/src/use_kernel_config ]; then
    cp /usr/src/use_kernel_config .config
#    newconf_count=$((`make listnewconfig|wc -l`-1))
#    if (( "$newconf_count" > "0" )); then
#        seq 1 $newconf_count | while read line; do echo -en "\n"; done | make oldconfig
#    fi
else
#    newconf_count=$((`make listnewconfig|wc -l`-1))
#    if (( "$newconf_count" > "0" )); then
#        # Just hit Enter for each new config parameter and use default values.
#        seq 1 $((`make listnewconfig|wc -l`-1)) | while read line; do echo -en "\n"; done | make localyesconfig
#    else
        make localyesconfig
#    fi
fi
kernel_version="`make kernelversion`"
make -j$((num_cores + 1))
make modules_install
cp arch/x86/boot/bzImage /boot/kernel-$kernel_version-auto


echo --- Configuring Filesystems

# comment out all non-blank lines which are not yet commented out
sed -i 's/^[^#]/#&/g' /etc/fstab
# add our mounts at the end of the file
cat /mounts.txt | sed 's/\/mnt\/gentoo\s/\/ /g' | sed 's/\/mnt\/gentoo//g' >> /etc/fstab


echo --- Configuring Networking

echo "hostname=\"$TARGET_HOSTNAME\"" > /etc/conf.d/hostname
emerge --noreplace netifrc
net_iface="`route -n | grep "^0.0.0.0" | sed 's/\s\+/\t/g' | cut -f 8`"
if pgrep dhcpcd > /dev/null; then
    echo "config_$net_iface=\"dhcp\"" >> /etc/conf.d/net
    needs_dhcpcd=1
else
    current_net_config_raw="`ifconfig $net_iface | awk 'NR==2' | sed 's/\s\+/\t/g'`"
    current_net_config_addr="`echo "$current_net_config_raw" | cut -f 3`"
    current_net_config_mask="`echo "$current_net_config_raw" | cut -f 5`"
    current_net_config_brd="`echo "$current_net_config_raw" | cut -f 7`"
    echo "config_$net_iface=\"$current_net_config_addr netmask $current_net_config_mask brd $current_net_config_brd\"" >> /etc/conf.d/net
    echo "routes_$net_iface=\"default via `route -n | grep "^0.0.0.0" | sed 's/\s\+/\t/g' | cut -f 2`\"" >> /etc/conf.d/net
fi
cd /etc/init.d
ln -s net.lo net.$net_iface
rc-update add net.$net_iface default
cd - > /dev/null
sed -i "s/127\.0\.0\.1\s\+localhost/127\.0\.0\.1\t$TARGET_HOSTNAME localhost/" /etc/hosts


echo --- Setting root password

echo -e "$ROOT_PASSWORD\n$ROOT_PASSWORD\n" | passwd


echo --- Installing Necessary System Tools

# 1) check package names and set use flags if needed
emerge_list=""
while read tool_line; do
    if [ "$tool_line" != "" ]; then
        if grep -qs "\[" <<< "$tool_line"; then
            tool="`echo "$tool_line" | sed "s/\[.*//"`"
            use_changes="`echo "$tool_line" | sed "s/.*\[//" | sed "s/\].*//" | tr ',' ' '`"
        else
            tool="$tool_line"
            use_changes=""
        fi
        emerge_list="$emerge_list $tool"
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
    fi
done <<< "$SYSTEM_TOOLS"

# 2) add more tools to list, if needed
# adding after previous step, and checking isn't it already on list, so user
# is free to add custom USE flags to each of it.
if ! grep -qs "net-misc/dhcpcd" <<< "$emerge_list"; then
    if [ "$needs_dhcpcd" == "1" ]; then
        emerge_list="$emerge_list net-misc/dhcpcd"
    fi
fi
if ! grep -qs "sys-fs/jfsutils" <<< "$emerge_list"; then
    if grep -qs "jfs" < /proc/mounts; then
        emerge_list="$emerge_list sys-fs/jfsutils"
    fi
fi
if ! grep -qs "sys-fs/reiserfsprogs" <<< "$emerge_list"; then
    if grep -qs "reiserfs" < /proc/mounts; then
        emerge_list="$emerge_list sys-fs/reiserfsprogs"
    fi
fi
if ! grep -qs "sys-fs/xfsprogs" <<< "$emerge_list"; then
    if grep -qs "xfs" < /proc/mounts; then
        emerge_list="$emerge_list sys-fs/xfsprogs"
    fi
fi

# 3) emerge
emerge $emerge_list || exit 1

# 4) do specific things needed for each tool
# FixMe: hardcoded currently, may make this nicer in future

if grep -qs "app-admin/syslog-ng" <<< "$emerge_list"; then
    rc-update add syslog-ng default
    if grep -qs "app-admin/logcheck" <<< "$emerge_list"; then
        sed -i '/options /a\\towner(root);\n\n\t## (Make log files group-readable by logcheck)\n\tgroup(logcheck);\n\tperm(0640);\n' /etc/syslog-ng/syslog-ng.conf
    fi
elif grep -qs "app-admin/sysklogd" <<< "$emerge_list"; then
    rc-update add sysklogd default
elif grep -qs "app-admin/metalog" <<< "$emerge_list"; then
    rc-update add metalog default
fi

if grep -qs "sys-process/cronie" <<< "$emerge_list"; then
    rc-update add cronie default
elif grep -qs "sys-process/bcron" <<< "$emerge_list"; then
    rc-update add bcron default
elif grep -qs "sys-process/dcron" <<< "$emerge_list"; then
    rc-update add dcron default
    crontab /etc/crontab
elif grep -qs "sys-process/fcron" <<< "$emerge_list"; then
    rc-update add fcron default
    crontab /etc/crontab
fi

if grep -qs "net-misc/ntp" <<< "$emerge_list"; then
    rc-update add ntpd default
fi

rc-update add sshd default

if grep -qs "app-portage/layman" <<< "$emerge_list"; then
    echo "source /var/lib/layman/make.conf" >> /etc/portage/make.conf
fi

echo --- Configuring the Bootloader

grep -v rootfs /proc/mounts > /etc/mtab
bootpart="`df /boot | tail -n 1 | sed 's/\s\+/\t/g' | cut -f 1`"
bootdev="/dev/`lsblk -is $bootpart -o NAME | tail -n+3 | perl -pe 's/^([^A-Za-z0-9_]+)/length($1)."\t"/ge' | sort -nsr | cut -f 2`"


if [ "$BOOTLOADER" == "" ]; then
    BOOTLOADER=grub2
fi
case $BOOTLOADER in
    grub2)
        echo ------ Using GRUB2
        emerge sys-boot/grub
        grub2-install $bootdev
    ;;
    grub-legacy)
        echo ------ Using GRUB Legacy
        
        echo ">=sys-boot/grub-2" >> /etc/portage/package.mask
        emerge sys-boot/grub:0

        rootgrub="`grep $bootdev < /boot/grub/device.map | cut -f 1`"
        rootpart="`grep "\s/mnt/gentoo\s" /mounts.txt | cut -d ' ' -f 1`"

        echo "default 0" > /boot/grub/grub.conf
        echo "timeout 5" >> /boot/grub/grub.conf
        echo >> /boot/grub/grub.conf
        echo "title Gentoo Linux $kernel_version (auto)" >> /boot/grub/grub.conf
        # FixMe: fix auto-detecting of /boot partition
        #echo "root $rootgrub" >> /boot/grub/grub.conf
        echo "root (hd0,0)" >> /boot/grub/grub.conf
        echo "kernel /boot/kernel-$kernel_version-auto root=$rootpart" >> /boot/grub/grub.conf
        
        grub-install --no-floppy $bootdev
    ;;
    *)
        echo FATAL: Unknown bootloader: $BOOTLOADER
        exit 1
    ;;
esac

echo "-- All DONE, reboot to finish."

