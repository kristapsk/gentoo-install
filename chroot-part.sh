echo "This script is not supposed to be launched directly!"
echo "Check README.txt and use gentoo_install.sh instead."
exit

. /etc/profile
. /etc/inc.config.sh

num_cores="`nproc`"

# Be sure, we have directory versions, not single file.
mkdir /etc/portage/package.use
mkdir /etc/portage/package.mask

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
if [ "$KERNEL_EXTRA_FIRMWARE" != "" ]; then
    emerge $KERNEL_EXTRA_FIRMWARE
fi
cd /usr/src/linux
if [ -f /usr/src/use_kernel_config ]; then
    echo "------ Using prepared kernel configuration"
    cp /usr/src/use_kernel_config .config
    make olddefconfig
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
cp arch/x86/boot/bzImage /boot/kernel-$kernel_version-auto || exit 1

# Do we have XEN PVHVM xvd block device support in kernel?
if grep -qs "CONFIG_XEN_PVHVM=y" .config && grep -qs "CONFIG_XEN_BLKDEV_FRONTEND=y" .config; then
    XEN_BLKDEV="1"
else
    XEN_BLKDEV="0"
fi

echo --- Configuring Filesystems

# comment out all non-blank lines which are not yet commented out
sed -i 's/^[^#]/#&/g' /etc/fstab
# add our mounts at the end of the file
cat /mounts.txt | sed 's/\/mnt\/gentoo\s/\/ /g' | sed 's/\/mnt\/gentoo//g' >> /etc/fstab
# add swaps
swapon -s | tail -n -1 | cut -f 1 | while read swap_line; do
    echo -e "$swap_line\t\tnone\t\tswap\t\tsw\t\t0 0" >> /etc/fstab
done
# XEN block device name fix
if [ "$XEN_BLKDEV" != "1" ]; then
    sed -i 's/\/dev\/xvd/\/dev\/sd/g' /etc/fstab
fi

echo --- Configuring Networking

echo "hostname=\"$TARGET_HOSTNAME\"" > /etc/conf.d/hostname
emerge --noreplace netifrc
net_iface="`route -n | grep "^0.0.0.0" | sed 's/\s\+/\t/g' | cut -f 8`"

# If LiveCD has classic ethX network interface name, make sure that udev in
# installed system will not rename it.
if grep -qs "^eth" <<< "$net_iface"; then
    ADDITIONAL_KERNEL_ARGS="`echo "$ADDITIONAL_KERNEL_ARGS"` net.ifnames=0"
fi

if [ "`cat /use_dhcpcd.txt`" == "1" ]; then
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
# Resolve auto generated hostname for hosts file, if specified.
real_hostname="`eval echo "$TARGET_HOSTNAME"`"
sed -i "s/127\.0\.0\.1\s\+localhost/127\.0\.0\.1\t$real_hostname localhost/" /etc/hosts


echo --- Setting root password

echo -e "$ROOT_PASSWORD\n$ROOT_PASSWORD\n" | passwd


echo --- sysctl
echo "$SYSCTL_CONF" | while read sysctl_conf_line; do
    echo "$sysctl_conf_line" | sed -s 's/^[ \t]*//' >> /etc/sysctl.d/gentoo-install.conf
done

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
        tool_without_slot="`echo "$tool" | sed 's/:.*$//'`"
        if [ -d "/usr/portage/$tool_without_slot" ]; then
            if [ "$use_changes" != "" ]; then
                echo "$tool $use_changes" >> /etc/portage/package.use/gentoo-install
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

# 3) do some hacks

# Special hack to not pull in sys-fs/eudev, if sys-fs/udev is in emerge_list.
# Without that I got the following with auto-generated config from my workstation:
#
# * Error: The above package list contains packages which cannot be
# * installed at the same time on the same system.
#
#  (sys-fs/udev-215-r1::gentoo, installed) pulled in by
#    sys-fs/udev
#    >=sys-fs/udev-208-r1 required by (virtual/udev-215::gentoo, installed)
#    >=sys-fs/udev-208-r1:0/0[abi_x86_32(-)?,abi_x86_64(-)?,abi_x86_x32(-)?,abi_mips_n32(-)?,abi_mips_n64(-)?,abi_mips_o32(-)?,abi_ppc_32(-)?,abi_ppc_64(-)?,abi_s390_32(-)?,abi_s390_64(-)?,static-libs?] (>=sys-fs/udev-208-r1:0/0[abi_x86_64(-)]) required by (virtual/libudev-215-r1::gentoo, ebuild scheduled for merge)
#
#  (sys-fs/eudev-1.9-r2::gentoo, ebuild scheduled for merge) pulled in by
#    >=sys-fs/eudev-1.5.3-r1:0/0[abi_x86_32(-)?,abi_x86_64(-)?,abi_x86_x32(-)?,abi_mips_n32(-)?,abi_mips_n64(-)?,abi_mips_o32(-)?,abi_ppc_32(-)?,abi_ppc_64(-)?,abi_s390_32(-)?,abi_s390_64(-)?,gudev,introspection?,static-libs?] (>=sys-fs/eudev-1.5.3-r1:0/0[abi_x86_64(-),gudev,introspection]) required by (virtual/libgudev-215-r1::gentoo, ebuild scheduled for merge)
#
if [[ "$emerge_list" =~ "sys-fs/udev" ]]; then
    echo "------ Masking eudev, to not have conflicts with udev" 
    echo "sys-fs/eudev" >> /etc/portage/package.mask/gentoo-install
fi

# Special re-emerge hack for USE="-bindist", which can cause conflicts like:
#
#  (dev-libs/openssl-1.0.1j::gentoo, ebuild scheduled for merge) pulled in by
#    dev-libs/openssl:0[-bindist] required by (net-dns/bind-9.9.5-r3::gentoo, ebuild scheduled for merge)
#
#  (dev-libs/openssl-1.0.1j::gentoo, installed) pulled in by
#    >=dev-libs/openssl-0.9.6d:0[bindist=] required by (net-misc/openssh-6.6_p1-r1::gentoo, installed)
#
if [[ "$USE" =~ "-bindist" ]] || grep -qs '\-bindist' /etc/portage/package.use/*; then
    echo "------ Resolving bindist USE flag issues"
    emerge --unmerge openssl openssh && emerge openssl openssh
fi

# 4) emerge SYSTEM_TOOLS, with auto-unmasking, if necessary
emerge --autounmask-write --newuse --update $emerge_list 
if ls /etc/portage/._cfg* >/dev/null 2>&1; then
    etc-update --automode -5
    emerge --newuse --update $emerge_list || exit 1
fi

# FixMe: need some 100% check that emerge haven't failed here.

# 5) do specific things needed for each tool
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

echo --- Configuring the Environment

if [ "$DEFAULT_EDITOR" != "" ]; then
    eselect editor set "$DEFAULT_EDITOR"
    . /etc/profile
fi

echo --- Configuring the Bootloader

grep -v rootfs /proc/mounts > /etc/mtab
bootpart="`df /boot | tail -n 1 | sed 's/\s\+/\t/g' | cut -f 1`"
bootdev="/dev/`lsblk -is $bootpart -o NAME | tail -n+3 | perl -pe 's/^([^A-Za-z0-9_]+)/length($1)."\t"/ge' | sort -nsr | cut -f 2 | tr '\!' '/'`"


if [ "$BOOTLOADER" == "" ]; then
    BOOTLOADER=grub2
fi
case $BOOTLOADER in
    grub2)
        echo ------ Using GRUB2
        emerge sys-boot/grub
        grub2-install $bootdev
        grub2-mkconfig -o /boot/grub/grub.cfg
    ;;
    grub-legacy)
        echo ------ Using GRUB Legacy
        
        echo ">=sys-boot/grub-2" >> /etc/portage/package.mask/grub
        if [ "`uname -m`" == "x86_64" ]; then
            echo "sys-libs/ncurses abi_x86_32" >> /etc/portage/package.use/gentoo-install
        fi
        emerge sys-boot/grub:0 || exit 1

        rootgrub="`grep $bootdev < /boot/grub/device.map | cut -f 1`"
        rootpart="`grep "\s/mnt/gentoo\s" /mounts.txt | cut -d ' ' -f 1`"
        if [ "$XEN_BLKDEV" != "1" ]; then
            rootpart="`echo "$rootpart" | sed 's/\/dev\/xvd/\/dev\/sd/g'`"
        fi

        echo "default 0" > /boot/grub/grub.conf
        echo "timeout 5" >> /boot/grub/grub.conf
        echo >> /boot/grub/grub.conf
        echo "title Gentoo Linux $kernel_version (auto)" >> /boot/grub/grub.conf
        # FixMe: fix auto-detecting of /boot partition
        #echo "root $rootgrub" >> /boot/grub/grub.conf
        echo "root (hd0,0)" >> /boot/grub/grub.conf
        echo "kernel /boot/kernel-$kernel_version-auto root=$rootpart $ADDITIONAL_KERNEL_ARGS" >> /boot/grub/grub.conf

        # Work around "/dev/xvda does not have any corresponding BIOS drive" error.
        if [ "$bootdev" == "/dev/xvda" ]; then
            echo -e "device (hd0) /dev/xvda\nroot (hd0,0)\nsetup (hd0)\nquit" | grub
        else
            grub-install --no-floppy $bootdev
        fi
    ;;
    *)
        echo FATAL: Unknown bootloader: $BOOTLOADER
        exit 1
    ;;
esac

if [ "$USER_LOGIN" != "" ]; then
    echo "--- Adding user"
    if [ "$USER_GROUPS" == "" ]; then
        USER_GRUPS="users"
    fi
    useradd -m -G $USER_GROUPS -s /bin/bash $USER_LOGIN
    echo -e "$USER_PASSWORD\n$USER_PASSWORD\n" | passwd $USER_LOGIN
fi

if [ "$SUDO_WHEEL_ALL" != "" ]; then
    echo '%wheel ALL=(ALL) ALL' >> /etc/sudoers
fi

echo "--- Cleanup"
rm -f /stage3-*.tar.bz2 /chroot-part.sh /mounts.txt /use_dhcpcd.txt

echo "--- All DONE, reboot to finish."

