#!/bin/busybox sh

cmdline() {
    local value
    value=" $(cat /proc/cmdline)"
    value="${value##* $1=}"
    value="${value%% *}"
    [ "$value" != "" ] && echo "$value"
}

rescue_shell() {
    echo "Something went wrong. Dropping to a shell."
    exec sh
}

# Mount pseudo filesystems.
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

# Assemble software RAIDs, if needed.
if [ -x /sbin/mdadm ]; then
    mdadm --examine --scan > /etc/mdadm.conf
    mdadm --assemble --scan
fi

# Mount the root filesystem.
mount -o ro $(findfs $(cmdline root)) /mnt/root || rescue_shell

# Check that init is executable.
if [ ! -x /mnt/root/sbin/init ]; then
    rescue_shell
fi

# Clean up.
umount /dev
umount /sys
umount /proc

# Boot the real thing.
exec switch_root /mnt/root /sbin/init

