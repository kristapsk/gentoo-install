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

MACHINE="`uname -m`"
case $MACHINE in
    i686) GENTOO_ARCH=x86 ;;
    x86_64) GENTOO_ARCH=amd64 ;;
    *)
        echo "Unknown / unsupported machine $MACHINE!"
        exit 1
    ;;
esac

echo === Installing Gentoo GNU/Linux for $GENTOO_ARCH

cd /mnt/gentoo
wget "$GENTOO_MIRROR/releases/$GENTOO_ARCH/current-iso/stage3-$GENTOO_ARCH-????????.tar.bz2" || exit 1
tar xvjpf stage3-*.tar.bz2

echo --- Configuring the compile options

make_conf="/mnt/gentoo/etc/portage/make.conf"
cp $make_conf ${make_conf}.dist
cat ${make_conf}.dist |
	sed "s/CFLAGS=.*/CFLAGS=\"$CFLAGS\"/" |
	sed "s/USE=.*/USE=\"$USE\"/" > $make_conf
num_cores="`nproc`"
echo "MAKEOPTS=\"-j$((num_cores + 1))\"" >> $make_conf
if [ "$SYNC" != "" ]; then
    echo "SYNC=\"$SYNC\"" >> $make_conf
fi

echo --- Chrooting

cp -L /etc/resolv.conf /mnt/gentoo/etc/

mount -t proc proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev

cd - > /dev/null
cp inc.config.sh /mnt/gentoo/
cp chroot-part.sh /mnt/gentoo/
chroot /mnt/gentoo /bin/bash /chroot-part.sh 

umount -l /mnt/gentoo/dev
umount -l /mnt/gentoo/proc


