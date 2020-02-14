#! /bin/bash

CONFIG_FILE="inc.config.sh"

if [ "`whoami`" != "root" ]; then
    echo Must be run as root!
    exit 1
fi


if ! grep -qs /mnt/gentoo /proc/mounts; then
    echo "Target /mnt/gentoo not mounted!"
    exit 1
fi

no_gpg_validation=""
if [ "$1" == "--no-gpg-validation" ]; then
    no_gpg_validation="1"
    shift
fi

if [ "$1" != "" ]; then
    CONFIG_FILE="$1"
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Configuration file $CONFIG_FILE does not exist!"
    exit 1
fi

. "$CONFIG_FILE"

# Some configuration checks
if [ "$USE_KERNEL_CONFIG" != "" ] && [ ! -f "$USE_KERNEL_CONFIG" ]; then
    echo "Kernel configuration file $USE_KERNEL_CONFIG not found!"
    exit 1
fi

if [ "$TARGET_HOSTNAME" == "" ]; then
    echo "Hostname in configuration blank, cannot continue!"
    exit 1
fi

if [ "$ROOT_PASSWORD" == "" ] && [ "$SUDO_WHEEL_ALL" != "1" ]; then
    echo "Either root password or SUDO_WHEEL_ALL=1 must be specified!"
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

echo -- Setting the date and time
ntpd -q -g

cd /mnt/gentoo
rm -f stage3-*.tar*
if [ "$LOCAL_STAGE3" != "" ] && [ -f "$LOCAL_STAGE3" ]; then
    echo --- Using local stage3 copy
    cp "$LOCAL_STAGE3" /mnt/gentoo/
else
    echo --- Downloading stage3
    while true; do
        # Specify 10 sec. timeout to faster things up, not all Gentoo mirrors host an FTP server.
        wget --connect-timeout=10 "$GENTOO_MIRROR/releases/$GENTOO_ARCH/autobuilds/current-stage3-$GENTOO_SUBARCH/stage3-$GENTOO_SUBARCH-????????T??????Z.tar*" && break
    done
    if [ ! -f stage3-$GENTOO_SUBARCH-????????T??????Z.tar.bz2 ] && [ ! -f stage3-$GENTOO_SUBARCH-????????T??????Z.tar.xz ]; then
        echo "Download failed"
        exit 1
    fi
    if [ "$no_gpg_validation" != "1" ]; then
        echo --- Verifying and validating
        wget -q -O - https://www.gentoo.org/downloads/signatures/ | grep "[A-Z0-9]\{40\}" | sed 's/<[^>]*>//g' | sed 's/(.\+)//g' | while read key; do
            gpg --keyserver hkps.pool.sks-keyservers.net --recv-keys $key
        done
        gpg --verify stage3-$GENTOO_SUBARCH-????????T??????Z.tar*.DIGESTS.asc || exit 1
    fi
    for hashalgo in sha512 whirlpool; do
        if ! grep -qs $(openssl dgst -$hashalgo stage3-$GENTOO_SUBARCH-????????T??????Z.tar.{bz2,xz} 2> /dev/null | grep -Eo "[0-9a-z]{128,}") stage3-$GENTOO_SUBARCH-????????T??????Z.tar*.DIGESTS.asc; then
            echo "stage3 $hashalgo checksum mismatch"
            exit 1
        fi
    done
fi
echo --- Unpacking the stage tarball
if [ -f stage3-*.tar.xz ]; then
    tar xpf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner || exit 1
elif [ -f stage3-*.tar.bz2 ]; then
    tar xpf stage3-*.tar.bz2 --xattrs-include='*.*' --numeric-owner || exit 1
else
    echo "FATAL: Unknown stage3 tarball filename!"
    exit 1
fi

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
if [ "$COMMON_FLAGS" != "" ]; then
    sed -i "s/COMMON_FLAGS=.*/COMMON_FLAGS=\"$COMMON_FLAGS\"/" $make_conf
fi
if [ "$CFLAGS" != "" ]; then
    sed -i "s/CFLAGS=.*/CFLAGS=\"$CFLAGS\"/" $make_conf
fi
if [ "$CXXFLAGS" != "" ]; then
    sed -i "s/CXXFLAGS=.*/CXXFLAGS=\"$CXXFLAGS\"/" $make_conf
fi
if grep -qs "USE=.*" $make_conf; then
    sed -i "s/USE=.*/USE=\"$USE\"/" $make_conf
else
    echo -e "\nUSE=\"$USE\"" >> $make_conf
fi

if [ "$GENTOO_ARCH" == "amd64" ] || [ "$GENTOO_ARCH" == "x86" ]; then
    if [ "$CPU_FLAGS_X86" != "" ]; then
        echo "CPU_FLAGS_X86=\"$CPU_FLAGS_X86\"" >> $make_conf
    fi
fi

num_cores="`nproc`"
mem_gigs="$(( `grep MemTotal /proc/meminfo | sed 's/\s\+/\t/g' | cut -f 2` / 1024 / 1024 ))"
if [ "$mem_gigs" == "0" ]; then
    echo "MAKEOPTS=\"-j1\"" >> $make_conf
elif [ "$num_cores" -lt "$mem_gigs" ]; then
    echo "MAKEOPTS=\"-j$num_cores\"" >> $make_conf
else
    echo "MAKEOPTS=\"-j$mem_gigs\"" >> $make_conf
fi

if [ "$http_proxy" != "" ]; then
    echo "http_proxy=\"$http_proxy\"" >> $make_conf
fi

if [ "$FEATURES" != "" ]; then
    echo "FEATURES=\"$FEATURES\"" >> $make_conf
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
if [ "$L10N" != "" ]; then
    echo "L10N=\"$L10N\"" >> $make_conf
fi
if [ "$ACCEPT_LICENSE" != "" ]; then
    echo "ACCEPT_LICENSE=\"$ACCEPT_LICENSE\"" >> $make_conf
fi
if [ "$EMERGE_DEFAULT_OPTS" != "" ]; then
    echo "EMERGE_DEFAULT_OPTS=\"$EMERGE_DEFAULT_OPTS\"" >> $make_conf
fi
if [ "$PORTAGE_ELOG_MAILURI" != "" ]; then
    echo "PORTAGE_ELOG_MAILURI=\"$PORTAGE_ELOG_MAILURI\"" >> $make_conf
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

echo --- Checking for WPA

touch /mnt/gentoo/use_wpa.txt
if pgrep wpa_supplicant > /dev/null; then
    echo "1" > /mnt/gentoo/use_wpa.txt
    mkdir -p /mnt/gentoo/etc/wpa_supplicant/
    cp -L /etc/wpa_supplicant/wpa_supplicant.conf /mnt/gentoo/etc/wpa_supplicant/wpa_supplicant.conf
fi

echo --- Checking for system type
dmidecode -s system-product-name > /mnt/gentoo/system-product-name.txt

if [ "$RC_LOCAL_SCRIPTS" != "" ]; then
    echo --- Copying local.d scripts
    while read locald_script; do
        if [ "$locald_script" != "" ]; then
            echo "------ $locald_script"
            cp "$locald_script" /mnt/gentoo/etc/local.d/
        fi
    done <<< "$RC_LOCAL_SCRIPTS"
    chmod +x /mnt/gentoo/etc/local.d/*.start
    chmod +x /mnt/gentoo/etc/local.d/*.stop
    echo "rc_verbose=yes" > /mnt/gentoo/etc/conf.d/local
fi

echo --- Chrooting

mkdir -p /mnt/gentoo/etc/portage/repos.conf
cp /mnt/gentoo/usr/share/portage/config/repos.conf /mnt/gentoo/etc/portage/repos.conf/gentoo.conf

cp -L /etc/resolv.conf /mnt/gentoo/etc/

cd - > /dev/null
cp "$CONFIG_FILE" /mnt/gentoo/etc/inc.config.sh
# we remove first three lines which contains error message and exit, as guard
# against direct launching of chroot-part script.
tail -n+4 chroot-part.sh > /mnt/gentoo/chroot-part.sh
if [ "$USE_KERNEL_CONFIG" != "" ]; then
    cp "$USE_KERNEL_CONFIG" /mnt/gentoo/usr/src/use_kernel_config || exit 1
fi
grep "\s/mnt/gentoo" /proc/mounts > /mnt/gentoo/mounts.txt

mkdir -p /mnt/gentoo/usr/src/initramfs/{bin,dev,etc,lib,lib64,mnt/root,proc,root,sbin,sys}
cp initramfs-init.sh /mnt/gentoo/usr/src/initramfs/init

mount -t proc proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev

# Be sure to always umount, if user presses Ctrl+C.
# Two traps are needed to guard against executing commands twice.
trap "umount -l /mnt/gentoo/dev; umount -l /mnt/gentoo/sys; umount -l /mnt/gentoo/proc" EXIT
trap "exit 1" SIGINT SIGTERM

chroot /mnt/gentoo /bin/bash /chroot-part.sh

