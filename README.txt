
Fast HOWTO:
* Boot into LiveCD (best into recent one)
* Configure network
* Make partitions, format, mount them as /mnt/gentoo
* Check configuration inc.config.sh
* Run gentoo-install.sh

Known issues:
* No IPv6 support
* No LILO support (I will not implement it, do it yourself, if you need)
* Only amd64 / x86 supported for now (feel free to implement others)
* Missing configuration of /etc/rc.conf, /etc/conf.d/keymaps,
/etc/conf.d/hwclock, /etc/inittab, ...
* PPPoE client (net-dialup/ppp) is not detected and installed automatically
* If using GRUB Legacy, boot partition must be "(hd0,0)"
* Systemd is not supported

