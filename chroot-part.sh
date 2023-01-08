echo "This script is not supposed to be launched directly!"
echo "Check README.txt and use gentoo_install.sh instead."
exit

. /etc/profile
. /etc/inc.config.sh

MACHINE="`uname -m`"
num_cores="`nproc`"

# Be sure, we have directory versions, not single file.
mkdir -p /etc/portage/package.use
mkdir -p /etc/portage/package.mask

# ldconfig resolves error "grep: error while loading shared libraries:
# libpcre.so.1: cannot open shared object file: No such file or directory"
# after chrooting from other linux than life CD
ldconfig

function emerge_with_autounmask()
{
    emerge --autounmask=y --autounmask-write $@
    if ls /etc/portage/._cfg* > /dev/null 2>&1 || ls /etc/portage/package.*/._cfg* > /dev/null 2>&1; then
        etc-update --automode -5 /etc/portage
        emerge $@ || kill $$
    fi
}

function kernel_config_set()
{
    configfile="$1"
    configparamarr=(${2//=/ })
    configparam=${configparamarr[0]}
    configvalue="${configparamarr[1]}"
    if grep -qsE "$configparam(=| is not set)" $configfile; then
        if [[ $configvalue =~ y|m ]]; then
            configline="$configparam=$configvalue"
        elif [[ $configvalue == n ]]; then
            configline="# $configparam is not set"
        else
            configline="$configparam=\"$configvalue\""
        fi
        sed -i -E "s/(# )?$configparam(=.+| is not set)/$configline/" $configfile
    else
        echo "WARNING: No $configparam in $configfile"
        return 1
    fi
}

echo --- Configuring Portage

#emerge-webrsync
emerge --sync


echo --- Choosing the Right Profile

if [ "$SYSTEM_PROFILE" != "" ]; then
	echo ------ Switching system profile to $SYSTEM_PROFILE
	eselect profile set "$SYSTEM_PROFILE" || exit 1
	eselect profile list
fi


echo --- Updating the @world set
emerge_with_autounmask --update --deep --newuse @world


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
        env-update && . /etc/profile && export PS1="(chroot) $PS1"
    fi
fi

if [[ "$FEATURES" =~ "installsources" ]]; then
	echo --- Installing debugedit
	emerge_with_autounmask dev-util/debugedit
fi

echo --- Configuring the Kernel

if [ "$KERNEL_EBUILD" == "" ]; then
	KERNEL_EBUILD=gentoo-sources
fi
emerge_with_autounmask $KERNEL_EBUILD
if [ "$KERNEL_EXTRA_FIRMWARE" != "" ]; then
    emerge_with_autounmask $KERNEL_EXTRA_FIRMWARE
fi
cd /usr/src/linux
if [ -f /usr/src/use_kernel_config ]; then
    echo "------ Using prepared kernel configuration"
    cp /usr/src/use_kernel_config .config
    make olddefconfig
else
    echo "------ Automatically generate configuration from live environment"
    if [ "$MACHINE" == "i686" ]; then
        kernel_config_set .config CONFIG_64BIT=n
    fi
    make olddefconfig
    make localyesconfig
fi
if grep -qs "HVM domU" /system-product-name.txt; then
    # https://wiki.xenproject.org/wiki/Mainline_Linux_Kernel_Configs#Configuring_the_Kernel_for_domU_Support
    kernel_config_set .config CONFIG_HYPERVISOR_GUEST=y
    make olddefconfig
    kernel_config_set .config CONFIG_PARAVIRT=y
    make olddefconfig
    kernel_config_set .config CONFIG_XEN=y
    kernel_config_set .config CONFIG_PARAVIRT_GUEST=y
    kernel_config_set .config CONFIG_PARAVIRT_SPINLOCKS=y
    make olddefconfig
    kernel_config_set .config CONFIG_HVC_DRIVER=y
    kernel_config_set .config CONFIG_HVC_XEN=y
    kernel_config_set .config CONFIG_XEN_FBDEV_FRONTEND=y
    kernel_config_set .config CONFIG_XEN_BLKDEV_FRONTEND=y
    kernel_config_set .config CONFIG_XEN_NETDEV_FRONTEND=y
    kernel_config_set .config CONFIG_XEN_PCIDEV_FRONTEND=y
    kernel_config_set .config CONFIG_INPUT_XEN_KBDDEV_FRONTEND=y
    kernel_config_set .config CONFIG_XEN_FBDEV_FRONTEND=y
    kernel_config_set .config CONFIG_XEN_XENBUS_FRONTEND=y
    kernel_config_set .config CONFIG_XEN_SAVE_RESTORE=y
fi
if [[ "$(wc -l < /has-virtio.txt)" != "0" ]]; then
    # https://wiki.gentoo.org/wiki/QEMU/Linux_guest#Kernel
    kernel_config_set .config CONFIG_HYPERVISOR_GUEST=y
    make olddefconfig
    kernel_config_set .config CONFIG_PARAVIRT=y
    make olddefconfig
    kernel_config_set .config CONFIG_KVM_GUEST=y
    kernel_config_set .config CONFIG_VIRTIO_MENU=y
    make olddefconfig
    kernel_config_set .config CONFIG_VIRTIO_PCI=y
    make olddefconfig
    kernel_config_set .config CONFIG_VIRTIO_BLK=y
    kernel_config_set .config CONFIG_VIRTIO_NET=y
    kernel_config_set .config CONFIG_SCSI_LOWLEVEL=y
    make olddefconfig
    kernel_config_set .config CONFIG_SCSI_VIRTIO=y
fi
echo "$ADDITIONAL_KERNEL_CONFIG" | while read kernel_config; do
    # remove whitespaces
    kernel_config="`xargs <<< "$kernel_config"`"
    if [ "$kernel_config" != "" ]; then
        kernel_config_set .config "$kernel_config"
    fi
done
# Some required kernel config (for initrd)
kernel_config_set .config CONFIG_BLK_DEV_INITRD=y
kernel_config_set .config CONFIG_DEVTMPFS=y
# Software RAID
if grep -qs "active" /proc/mdstat; then
    kernel_config_set .config CONFIG_MD_AUTODETECT=y
    if grep -qs " : .*linear " /proc/mdstat; then
        kernel_config_set .config CONFIG_MD_LINEAR=y
    fi
    if grep -qs " : .*raid0 " /proc/mdstat; then
        kernel_config_set .config CONFIG_MD_RAID0=y
    fi
    if grep -qs " : .*raid1 " /proc/mdstat; then
        kernel_config_set .config CONFIG_MD_RAID1=y
    fi
    if grep -qs " : .*raid10 " /proc/mdstat; then
        kernel_config_set .config CONFIG_MD_RAID10=y
    fi
    if grep -qs " : .*\(raid4\|raid5\|raid6\) " /proc/mdstat; then
        kernel_config_set .config CONFIG_MD_RAID456=y
    fi
    if grep -qs " : .*multipath " /proc/mdstat; then
        kernel_config_set .config CONFIG_MD_MULTIPATH=y
    fi
fi
# May be required to enable dependencies of ADDITIONAL_KERNEL_CONFIG
make olddefconfig
kernel_version="`make kernelversion`"
make -j$num_cores
make modules_install
cp arch/x86/boot/bzImage /boot/kernel-$kernel_version-auto || exit 1

# May be needed :(
emerge_with_autounmask sys-kernel/linux-firmware

echo --- Configuring Filesystems

# comment out all non-blank lines which are not yet commented out
sed -i 's/^[^#]/#&/g' /etc/fstab
# add our mounts at the end of the file
fstab_format="%s\t%-22s\t%-7s\t%-50s\t%s"
cat /mounts.txt | while read fs mountpoint type opts dump pass; do
    if [ "$mountpoint" == "/mnt/gentoo" ]; then
        mountpoint="/"
    else
        mountpoint="`sed 's/\/mnt\/gentoo//g' <<< "$mountpoint"`"
    fi
    if [ "$mountpoint" == "/boot" ]; then
        opts="noauto,$opts"
        dump="1"
        pass="2"
    elif [ "$mountpoint" == "/" ]; then
        dump="0"
        pass="1"
    else
        dump="0"
        pass="0"
    fi
    # Remove generic defaults
    opts="`echo "$opts" | sed -r 's/rw,?//'`"
    # Remove filesystem specific defaults
    if [ "$type" == "ext4" ]; then
        opts="`echo "$opts" | sed -r 's/data=ordered,?//'`"
    fi
    # Remove trailing comma, if present
    opts=${opts%,}
    printf "$fstab_format\n" "UUID=`lsblk -no UUID $fs`" "$mountpoint" "$type" "$opts" "$dump $pass" >> /etc/fstab
done
# add swaps
swapon -s | tail -n -1 | cut -f 1 | while read swap_line; do
    printf "$fstab_format\n" "UUID=`lsblk -no UUID $swap_line`" "none" "swap" "sw" "0 0" >> /etc/fstab
done
# CD-ROM
mkdir /mnt/cdrom
printf "$fstab_format\n" "/dev/sr0" "/mnt/cdrom" "auto" "noauto,ro" "0 0" >> /etc/fstab

echo --- Configuring Networking

echo "hostname=\"$TARGET_HOSTNAME\"" > /etc/conf.d/hostname
emerge_with_autounmask --noreplace netifrc
net_iface="`route -n | grep "^0.0.0.0" | sed 's/\s\+/\t/g' | cut -f 8`"

# If LiveCD has classic ethX network interface name, make sure that udev in
# installed system will not rename it.
if grep -qs "^eth" <<< "$net_iface"; then
    ADDITIONAL_KERNEL_ARGS="`echo "$ADDITIONAL_KERNEL_ARGS"` net.ifnames=0"
fi

if [ "$(cat /use_dhcpcd.txt)" == "1" ]; then
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
if [ "$(cat /use_wpa.txt)" == "1" ]; then
    needs_wpa=1
fi
cd /etc/init.d
ln -s net.lo net.$net_iface
rc-update add net.$net_iface default
cd - > /dev/null
# Resolve auto generated hostname for hosts file, if specified.
real_hostname="`eval echo "$TARGET_HOSTNAME"`"
sed -i "s/127\.0\.0\.1\s\+localhost/127\.0\.0\.1\t$real_hostname localhost/" /etc/hosts
# Add additional /etc/hosts entries, if needed
echo "$HOSTS_ADD" >> /etc/hosts

if [ "$(xargs <<< "$LAYMAN_ADD")" != "" ]; then
    echo --- Configuring additional portage overlays
    emerge_with_autounmask app-portage/layman

    echo "$LAYMAN_ADD" | while read layman_cmd; do
        if [ "$layman_cmd" != "" ]; then
            echo y | layman $layman_cmd
        fi
    done
fi

if [ "$ROOT_PASSWORD" != "" ]; then
    echo --- Setting root password
    if [[ ${ROOT_PASSWORD:0:1} == "$" ]]; then
        usermod -p "$ROOT_PASSWORD" root
    else
        echo -e "$ROOT_PASSWORD\n$ROOT_PASSWORD\n" | passwd
    fi
fi

echo --- sysctl
echo "$SYSCTL_CONF" | while read sysctl_conf_line; do
    if [ "$sysctl_conf_line" != "" ]; then
        echo "$sysctl_conf_line" | sed -s 's/^[ \t]*//' >> /etc/sysctl.d/local.conf
    fi
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
        if emerge -p $tool_without_slot > /dev/null; then
            # initramfs tools must be static linked
            if [ "$tool" == "sys-apps/busybox" ] || [ "$tool" == "sys-fs/mdadm" ]; then
                if grep -qs -- "-static" <<< "$use_changes"; then
                    use_changes="`echo "$use_changes" | sed 's/-static//'`"
                fi
                if ! grep -qs "static" <<< "$use_changes"; then
                    use_changes="$use_changes static"
                fi
            fi
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
if ! grep -qs "app-arch/cpio" <<< "$emerge_list"; then
    emerge_list="$emerge_list app-arch/cpio"
fi
if ! grep -qs "net-misc/dhcpcd" <<< "$emerge_list"; then
    if [ "$needs_dhcpcd" == "1" ]; then
        emerge_list="$emerge_list net-misc/dhcpcd"
    fi
fi
if ! grep -qs "net-wireless/wireless-tools" <<< "$emerge_list"; then
    if [ "$needs_wpa" == "1" ]; then
        emerge_list="$emerge_list net-wireless/wireless-tools"
    fi
fi
if ! grep -qs "net-wireless/wpa_supplicant" <<< "$emerge_list"; then
    if [ "$needs_wpa" == "1" ]; then
        emerge_list="$emerge_list net-wireless/wpa_supplicant"
    fi
fi
if ! grep -qs "sys-apps/busybox" <<< "$emerge_list"; then
    emerge_list="$emerge_list sys-apps/busybox"
    echo "sys-apps/busybox static" >> /etc/portage/package.use/gentoo-install
fi
if ! grep -qs "sys-fs/btrfs-progs" <<< "$emerge_list"; then
    if grep -qs "btrfs" < /proc/mounts; then
        emerge_list="$emerge_list sys-fs/btrfs-progs"
    fi
fi
if ! grep -qs "sys-fs/dosfstools" <<< "$emerge_list"; then
    if grep -qs "fat" < /proc/mounts; then
        emerge_list="$emerge_list sys-fs/dosfstools"
    fi
fi
if ! grep -qs "sys-fs/e2fsprogs" <<< "$emerge_list"; then
    if grep -qs "ext" < /proc/mounts; then
        emerge_list="$emerge_list sys-fs/e2fsprogs"
    fi
fi
if ! grep -qs "sys-fs/jfsutils" <<< "$emerge_list"; then
    if grep -qs "jfs" < /proc/mounts; then
        emerge_list="$emerge_list sys-fs/jfsutils"
    fi
fi
if ! grep -qs "sys-fs/mdadm" <<< "$emerge_list"; then
    if grep -qs "active" < /proc/mdstat; then
        emerge_list="$emerge_list sys-fs/mdadm"
        echo "sys-fs/mdadm static" >> /etc/portage/package.use/gentoo-install
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
    emerge --unmerge openssl openssh && emerge_with_autounmask openssl openssh
fi

# 4) emerge SYSTEM_TOOLS, with auto-unmasking, if necessary
emerge_with_autounmask --newuse --update $emerge_list


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

if grep -qs "sys-fs/mdadm" <<< "$emerge_list"; then
    rc-update add mdraid boot
fi

rc-update add sshd default

# 6) copy necessary stuff to initrd
cp -a /bin/busybox /usr/src/initramfs/bin/busybox
if [ -x /sbin/mdadm ]; then
    cp -a /sbin/mdadm /usr/src/initramfs/sbin/mdadm
fi

echo --- Configuring the Environment

if [ "$DEFAULT_EDITOR" != "" ]; then
    eselect editor set "$DEFAULT_EDITOR"
    . /etc/profile
fi

echo --- Creating custom initramfs
cd /usr/src/initramfs
find . -print0 | cpio --null -ov --format=newc | gzip -9 > /boot/initramfs-gentoo-install.img
cd - > /dev/null

echo --- Configuring the Bootloader

bootpart="`df /boot | tail -n 1 | sed 's/\s\+/\t/g' | cut -f 1`"
bootdevs="`lsblk -is $bootpart -o NAME | tail -n+2`"
while grep -qs "^[^A-Za-z0-9_]" <<< "$bootdevs"; do
    bootdevs="`grep "^[^a-zA-Z0-9_]" <<< "$bootdevs" | cut -c 2-`"
done

if [ "$BOOTLOADER" == "" ]; then
    BOOTLOADER=grub2
fi
case $BOOTLOADER in
    grub2)
        echo ------ Using GRUB2
        emerge_with_autounmask sys-boot/grub:2

        # Some versions of XenServer has problems with graphical GRUB menu
        # https://serverfault.com/questions/598668/vms-grub-menu-invisible-with-xenserver-6-0-2
        sed -i "s/.*GRUB_TERMINAL=.*/GRUB_TERMINAL=console/g" /etc/default/grub

        while read -u 3 bootdev; do
            disklabel_type="$(fdisk -l /dev/$bootdev | grep "Disklabel type" | cut -d ' ' -f 3)"
            if [ "$disklabel_type" == "gpt" ] && [ -d /sys/firmware/efi ]; then
                mount -o remount,rw /sys/firmware/efi/efivars
                grub-install --target=x86_64-efi --efi-directory=/boot
            else
                grub-install /dev/$bootdev
            fi
        done 3<<< "$bootdevs"
        grub-mkconfig -o /boot/grub/grub.cfg
    ;;
    grub-legacy)
        echo ------ Using GRUB Legacy
        
        echo ">=sys-boot/grub-2" >> /etc/portage/package.mask/grub
        if [ "$MACHINE" == "x86_64" ]; then
            echo "sys-libs/ncurses abi_x86_32" >> /etc/portage/package.use/gentoo-install
        fi
        emerge_with_autounmask sys-boot/grub-static

        rootpart="`grep "\s/\s" /etc/fstab | grep -v "^#" | cut -f 1`"

        echo "default 0" > /boot/grub/grub.conf
        echo "timeout 5" >> /boot/grub/grub.conf
        echo >> /boot/grub/grub.conf
        echo "title Gentoo Linux $kernel_version (auto)" >> /boot/grub/grub.conf
        # FixMe: fix auto-detecting of /boot partition
        #echo "root $rootgrub" >> /boot/grub/grub.conf
        echo "root (hd0,0)" >> /boot/grub/grub.conf
        echo "kernel /boot/kernel-$kernel_version-auto root=$rootpart $ADDITIONAL_KERNEL_ARGS" >> /boot/grub/grub.conf
        echo "initrd /boot/initramfs-gentoo-install.img" >> /boot/grub/grub.conf

        echo "$bootdevs" | while read bootdev; do
            echo -e "device (hd0) /dev/$bootdev\nroot (hd0,0)\nsetup (hd0)\nquit" | grub
        done
    ;;
    refind)
        echo ------ Using rEFInd

        refind_use=""
        for fs in btrfs ext2 ext4 hfs iso9660 ntfs reiserfs; do
            if grep -qs "$fs" < /proc/mounts; then
                refind_use="$refind_use$fs "
            fi
        done
        if [[ "$refind_use" != "" ]]; then
            echo "sys-boot/refind $refind_use" >> /etc/portage/package.use/gentoo-install
        fi
        emerge_with_autounmask sys-boot/efibootmgr sys-boot/refind

        mount -o remount,rw -t efivarfs efivarfs /sys/firmware/efi/efivars
        refind-install

        mkdir -p /boot/EFI/BOOT
        cp /boot/EFI/refind/refind_x64.efi /boot/EFI/BOOT/bootx64.efi

        rootpart="`grep "\s/\s" /etc/fstab | grep -v "^#" | cut -f 1`"
        cmdline="root=$rootpart $ADDITIONAL_KERNEL_ARGS initrd=initramfs-gentoo-install.img"
        echo -e "\"Boot with standard options\"\t\"BOOT_IMAGE=/boot/kernel-$kernel_version-auto $cmdline\"" > /boot/refind_linux.conf
        echo -e "\"Boot to single-user mode\"\t\"BOOT_IMAGE=/boot/kernel-$kernel_version-auto $cmdline single\"" >> /boot/refind_linux.conf
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
    if [[ ${USER_PASSWORD:0:1} == "$" ]]; then
        useradd -m -G $USER_GROUPS -s /bin/bash -p "$USER_PASSWORD" $USER_LOGIN
    else
        useradd -m -G $USER_GROUPS -s /bin/bash $USER_LOGIN
        echo -e "$USER_PASSWORD\n$USER_PASSWORD\n" | passwd $USER_LOGIN
    fi
fi

if [ "$SUDO_WHEEL_ALL" != "" ]; then
    echo '%wheel ALL=(ALL) ALL' >> /etc/sudoers
fi

echo "--- Cleanup"
rm -f /stage3-*Z.tar* /chroot-part.sh /mounts.txt /use_dhcpcd.txt /use_wpa.txt /system-product-name.txt /has-virtio.txt
sed -i 's/ROOT_PASSWORD=.*/#ROOT_PASSWORD=""/' /etc/inc.config.sh
sed -i 's/USER_PASSWORD=.*/#USER_PASSWORD=""/' /etc/inc.config.sh
chmod 600 /etc/inc.config.sh

echo "--- All DONE, reboot to finish."

