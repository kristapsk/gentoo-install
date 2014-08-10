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
wget "$GENTOO_MIRROR/releases/$GENTOO_ARCH/current-iso/stage3-$GENTOO_SUBARCH-????????.tar.bz2" || exit 1
tar xvjpf stage3-*.tar.bz2 || exit 1

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

chroot /mnt/gentoo /bin/bash /chroot-part.sh 

umount -l /mnt/gentoo/dev
umount -l /mnt/gentoo/sys
umount -l /mnt/gentoo/proc


