# required make.conf settings
# GENTOO_MIRROR is required to use FTP protocol for now
# Not all mirrors support FTP and sometimes distfiles.gentoo.org will resolve
# to ones that don't all the time. In that case go to
# https://gentoo.org/downloads/mirrors/ and manually change GENTOO_MIRROR
# variable to some mirror that is listed as supporting FTP.
GENTOO_MIRROR="ftp://distfiles.gentoo.org/pub/gentoo"
COMMON_FLAGS="-march=native -O2 -pipe"
#COMMON_FLAGS="-march=native -O2 -pipe -ggdb -fno-omit-frame-pointer"
#CFLAGS="\${COMMON_FLAGS}"
#CXXFLAGS="\${COMMON_FLAGS}"
USE="-bindist -X verify-sig vim-syntax"

# optional make.conf settings (leave blank for defaults)
http_proxy=""
FEATURES="preserve-libs"
#FEATURES="preserve-libs splitdebug installsources"
CPU_FLAGS_X86="mmx sse sse2"
INPUT_DEVICES=""
VIDEO_CARDS=""
LINGUAS=""
L10N=""
PORTAGE_ELOG_MAILURI=""

LIBREOFFICE_EXTENSIONS=""
NGINX_MODULES_HTTP=""
NGINX_MODULES_MAIL=""
QEMU_SOFTMMU_TARGETS=""
QEMU_USER_TARGETS=""

# Uncomment to auto-accept non-FREE licenses (old Gentoo default)
#ACCEPT_LICENSE="* -@EULA"

# I prefer old emerge autounmask behaviour and it is also used by the install
# script itself. Comment out this if you don't want it after install.
# See also https://bugs.gentoo.org/658648.
# Also I see --verbose-conflicts helpful
EMERGE_DEFAULT_OPTS="--autounmask --verbose-conflicts"

# System profile - leave blank to use installation CD default one
#SYSTEM_PROFILE=""

TIMEZONE="Europe/Riga"

LOCALES="
    en_US ISO-8859-1
    en_US.UTF-8 UTF-8
    lv_LV ISO-8859-13
    lv_LV.UTF-8 UTF-8
"
DEFAULT_LOCALE="POSIX"

# Environment
DEFAULT_EDITOR="/usr/bin/vi"

# Leave blank for default
KERNEL_EBUILD="gentoo-sources"
# You can specify kernel .config file name (absolute/relative path prior
# chrooting). If left blank, "make localyesconfig" is used.
USE_KERNEL_CONFIG=""
# Here you can specify additional kernel config's to enable or disable.
# Format is CONFIG_OPTION=<y|n|m>, separated by a newline.
ADDITIONAL_KERNEL_CONFIG="
    CONFIG_SYN_COOKIES=y
"
# Specify kernel binary blob ebuilds here, if needed.
KERNEL_EXTRA_FIRMWARE=""
# Optionally specify additional kernel command line arguments.
ADDITIONAL_KERNEL_ARGS=""
# Optional sysctl custom values
SYSCTL_CONF="
    net.ipv4.tcp_syncookies = 1
"

# Default to auto generated hostname, by applying MAC address to it.
# Might be useful when installing VM templates.
TARGET_HOSTNAME="tux-box-\`ifconfig -a | grep ether | head -n 1 | sed 's/\s\+/\t/g' | cut -f 3 | sed 's/://g'\`"
# Use the following instead for a simple static hostname.
#TARGET_HOSTNAME="tux-box"

# Optionally specify root password. Is not required if ordinary user has SUDO_WHEEL_ALL="1".
# Strings beginning with '$' will be treated as /etc/shadow hashes instead of plaintext passwords.
ROOT_PASSWORD=""

USER_LOGIN="larry"
USER_PASSWORD="somepass"
USER_GROUPS="users,wheel"

# Allow members of wheel group to execute any command using sudo. Change to "1" to enable.
SUDO_WHEEL_ALL=""

# Put anything you want to append to /etc/hosts here.
HOSTS_ADD="
"

# Additional overlays to add, format is layman arguments, multiple can be added. Example:
# LAYMAN_ADD="
#	-a mysql
#	-o https://raw.github.com/skyfms/portage-overlay/master/overlay.xml -L -a is-overlay
# "
# Will add app-portage/layman as a dependency, if not empty.
LAYMAN_ADD=""

# Necessary system tools to emerge
# Specific USE flag changes can be specified in square brackets
# Additionally, the following ones will be always emerged under certain
# circumstances:
#   * app-arch/cpio - always
#   * app-portage/layman - if LAYMAN_ADD (see above) is not empty
#   * net-misc/dhcpcd - if network configured via DHCP
#   * net-wireless/wpa_supplicant - if WPA WiFi detected
#   * net-wireless/wireless-tools - if WPA WiFi detected
#   * sys-apps/busybox[static] - always
#   * sys-fs/btrfs-progs - if Btrfs partition(s) detected
#   * sys-fs/dosfstools - if FAT partition(s) detected
#   * sys-fs/e2fsprogs - if ext2/ext3/ext4 partition(s) detected
#   * sys-fs/jfsutils - if JFS partition(s) detected
#   * sys-fs/mdadm - if active software RAID devices detected
#   * sys-fs/reiserfsprogs - if ReiserFS partition(s) detected
#   * sys-fs/xfsprogs - if XFS partition(s) detected
SYSTEM_TOOLS="
    app-admin/logrotate
    app-admin/sudo
    app-admin/syslog-ng
    app-editors/nano
    app-editors/vim
    app-misc/mc
    app-misc/tmux
    app-portage/gentoolkit
    dev-libs/libpcre2[jit]
    dev-vcs/git
    mail-client/mailx
    mail-mta/ssmtp
    net-firewall/iptables
    net-misc/ntp
    net-misc/telnet-bsd
    sys-apps/mlocate
    sys-block/parted
    sys-devel/gdb
    sys-process/cronie
    sys-process/lsof
"

# Supported bootloaders: grub2, grub-legacy, refind
BOOTLOADER="grub2"

# Scripts to add to /etc/local.d/, useful for post-install actions on a first boot.
RC_LOCAL_SCRIPTS=""

