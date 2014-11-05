#! /bin/bash

. inc.config.sh

if [ "`whoami`" != "root" ]; then
    echo Must be run as root!
    exit 1
fi


if ! grep -qs /mnt/gentoo /proc/mounts; then
    echo "Target /mnt/gentoo not mounted!"
    exit 1
fi

# Some configuration checks
if [ "$USE_KERNEL_CONFIG" != "" ] && [ ! -f "$USE_KERNEL_CONFIG" ]; then
    echo "Kernel configuration file $USE_KERNEL_CONFIG not found!"
    exit 1
fi

if [ "$TARGET_HOSTNAME" == "" ]; then
    echo "Hostname in configuration blank, cannot continue!"
    exit 1
fi

if [ "$ROOT_PASSWORD" == "" ]; then
    echo "root password in configuration blank, cannot continue!"
    exit 1
fi

if [ "`dmesg | grep Xen`" != "" ] && [ "$BOOTLOADER" != "grub-legacy" ]; then
    echo "XenServer only supports GRUB legacy (grub-legacy) as BOOTLOADER for PV guests."
    exit 1
fi


MACHINE="`uname -m`"
case $MACHINE in
    i686) GENTOO_ARCH=x86 ; GENTOO_SUBARCH=i686 ;;
    x86_64) GENTOO_ARCH=amd64 ; GENTOO_SUBARCH=amd64 ;;
    *)
        echo "Unknown / unsupported machine type $MACHINE!"
        exit 1
    ;;
esac

echo === Installing Gentoo GNU/Linux for $GENTOO_ARCH

cd /mnt/gentoo
rm -f stage3-*.tar.bz2
wget "$GENTOO_MIRROR/releases/$GENTOO_ARCH/current-iso/stage3-$GENTOO_SUBARCH-????????.tar.bz2" || exit 1
tar xvjpf stage3-*.tar.bz2 || exit 1

if dmesg | grep -qs Xen; then
    echo --- Creating Xen device nodes
    mknod -m 600 /mnt/gentoo/dev/hvc0 c 229 0
    # Create xvd* device nodes for all /dev/[sh]d[ab] devices, others not supported yet
    mknod -m 660 /mnt/gentoo/dev/xvda b 202 0
    mknod -m 660 /mnt/gentoo/dev/xvdb b 202 16
    for i in `seq 1 15`; do
        mknod -m 660 /mnt/gentoo/dev/xvda$i b 202 $i
        mknod -m 660 /mnt/gentoo/dev/xvdb$i b 202 $((i + 16))
    done
fi

echo --- Configuring the compile options

make_conf="/mnt/gentoo/etc/portage/make.conf"
cp $make_conf ${make_conf}.dist
sed -i "s/CFLAGS=.*/CFLAGS=\"$CFLAGS\"/" $make_conf
sed -i "s/USE=.*/USE=\"$USE\"/" $make_conf
num_cores="`nproc`"
echo "MAKEOPTS=\"-j$((num_cores + 1))\"" >> $make_conf
if [ "$SYNC" != "" ]; then
    echo "SYNC=\"$SYNC\"" >> $make_conf
fi
if [ "$INPUT_DEVICES" != "" ]; then
    echo "INPUT_DEVICES=\"$INPUT_DEVICES\"" >> $make_conf
fi
if [ "$VIDEO_CARDS" != "" ]; then
    echo "VIDEO_CARDS=\"$VIDEO_CARDS\"" >> $make_conf
fi
if [ "$LINGUAS" != "" ]; then
    echo "LINGUAS=\"$LINGUAS\"" >> $make_conf
fi

# Package specific make.conf options

if [ "$LIBREOFFICE_EXTENSIONS" != "" ]; then
    echo "LIBREOFFICE_EXTENSIONS=\"$LIBREOFFICE_EXTENSIONS\"" >> $make_conf
fi
if [ "$NGINX_MODULES_HTTP" != "" ]; then
    echo "NGINX_MODULES_HTTP=\"$NGINX_MODULES_HTTP\"" >> $make_conf
fi
if [ "$NGINX_MODULES_MAIL" != "" ]; then
    echo "NGINX_MODULES_MAIL=\"$NGINX_MODULES_MAIL\"" >> $make_conf
fi
if [ "$QEMU_SOFTMMU_TARGETS" != "" ]; then
    echo "QEMU_SOFTMMU_TARGETS=\"$QEMU_SOFTMMU_TARGETS\"" >> $make_conf
fi
if [ "$QEMU_USER_TARGETS" != "" ]; then
    echo "QEMU_USER_TARGETS=\"$QEMU_USER_TARGETS\"" >> $make_conf
fi

echo --- Checking for DHCP

touch /mnt/gentoo/use_dhcpcd.txt
if pgrep dhcpcd > /dev/null; then
    echo "1" > /mnt/gentoo/use_dhcpcd.txt
fi

echo --- Chrooting

cp -L /etc/resolv.conf /mnt/gentoo/etc/

cd - > /dev/null
cp inc.config.sh /mnt/gentoo/
# we remove first three lines which contains error message and exit, as guard
# against direct launching of chroot-part script.
tail -n+4 chroot-part.sh > /mnt/gentoo/chroot-part.sh
if [ "$USE_KERNEL_CONFIG" != "" ]; then
    cp "$USE_KERNEL_CONFIG" /mnt/gentoo/usr/src/use_kernel_config || exit 1
fi
grep "\s/mnt/gentoo" /proc/mounts > /mnt/gentoo/mounts.txt

mount -t proc proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev

# Be sure to always umount, if user presses Ctrl+C.
# Two traps are needed to guard against executing commands twice.
trap "umount -l /mnt/gentoo/dev; umount -l /mnt/gentoo/sys; umount -l /mnt/gentoo/proc" EXIT
trap "exit 1" SIGINT SIGTERM

chroot /mnt/gentoo /bin/bash /chroot-part.sh

