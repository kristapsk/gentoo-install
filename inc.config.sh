# required make.conf settings
# GENTOO_MIRROR is required to use FTP protocol for now
GENTOO_MIRROR="ftp://distfiles.gentoo.org"
CFLAGS="-march=native -O2 -pipe"
USE="-bindist mmx sse sse2 -X vim-syntax"
# optional make.conf settings (leave blank for defaults)
SYNC=""

# System profile - leave blank to use installation CD default one
SYSTEM_PROFILE="hardened/linux/amd64"

TIMEZONE="Europe/Riga"

# Leave blank for default
KERNEL_EBUILD="hardened-sources"

# Necessary system tools to emerge
# Specific USE flag changes can be specified in square brackets
# Additionally, the following ones will be always emerged under certain
# circumstances:
#   * net-misc/dhcpcd - if network configured via DHCP
SYSTEM_TOOLS="
    app-admin/logcheck
    app-admin/logrotate
    app-admin/sudo
    app-admin/syslog-ng
    app-editors/vim
    app-misc/mc
    app-misc/tmux
    app-portage/layman
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

