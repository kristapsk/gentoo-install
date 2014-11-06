# required make.conf settings
# GENTOO_MIRROR is required to use FTP protocol for now
GENTOO_MIRROR="ftp://distfiles.gentoo.org"
CFLAGS="-march=native -O2 -pipe"
USE="bindist mmx sse sse2 -X vim-syntax"

# optional make.conf settings (leave blank for defaults)

SYNC=""

INPUT_DEVICES=""
VIDEO_CARDS=""
LINGUAS=""

LIBREOFFICE_EXTENSIONS=""
NGINX_MODULES_HTTP=""
NGINX_MODULES_MAIL=""
QEMU_SOFTMMU_TARGETS=""
QEMU_USER_TARGETS=""

# System profile - leave blank to use installation CD default one
SYSTEM_PROFILE="hardened/linux/amd64"

TIMEZONE="Europe/Riga"

LOCALES="
    en_US ISO-8859-1
    en_US.UTF-8 UTF-8
    lv_LV ISO-8859-13
    lv_LV.UTF-8 UTF-8
"
DEFAULT_LOCALE="lv_LV.UTF-8"

# Leave blank for default
KERNEL_EBUILD="hardened-sources"
# You can specify kernel .config file name (absolute/relative path prior
# chrooting). If left blank, "make localyesconfig" is used.
USE_KERNEL_CONFIG=""
# Specify kernel binary blob ebuilds here, if needed.
KERNEL_EXTRA_FIRMWARE=""
# Optionally specify additional kernel command line arguments.
ADDITIONAL_KERNEL_ARGS=""

TARGET_HOSTNAME="tux-box"

ROOT_PASSWORD="somepass"

# Necessary system tools to emerge
# Specific USE flag changes can be specified in square brackets
# Additionally, the following ones will be always emerged under certain
# circumstances:
#   * net-misc/dhcpcd - if network configured via DHCP
#   * sys-fs/jfsutils - if JFS partition(s) detected
#   * sys-fs/reiserfsprogs - if ReiserFS partition(s) detected
#   * sys-fs/xfsprogs - if XFS partition(s) detected
SYSTEM_TOOLS="
    app-admin/logcheck
    app-admin/logrotate
    app-admin/sudo
    app-admin/syslog-ng
    app-editors/vim
    app-misc/mc
    app-misc/tmux
    app-portage/gentoolkit
    app-portage/layman
    dev-vcs/git
    mail-client/mailx
    mail-mta/ssmtp
    net-firewall/iptables
    net-misc/ntp[openntpd]
    net-misc/telnet-bsd
    sys-apps/mlocate
    sys-block/parted
    sys-devel/gdb
    sys-process/cronie
    sys-process/lsof
"

# Supported bootloaders: grub2, grub-legacy
BOOTLOADER="grub2"

