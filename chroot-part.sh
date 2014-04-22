
. /etc/profile
. inc.config.sh

echo --- Configuring Portage

emerge-webrsync
emerge --sync

echo --- Choosing the Right Profile
if [ "$SYSTEM_PROFILE" != "" ]; then
	echo ------ Switching system profile to $SYSTEM_PROFILE
	eselect profile set "$SYSTEM_PROFILE" || exit 1
	eselect profile list
fi

echo --- Switching timezone to $TIMEZONE
echo "$TIMEZONE" > /etc/timezone
emerge --config sys-libs/timezone-data

echo --- Configure locales
# Nothing for now

echo --- Configuring the Kernel
if [ "$KERNEL_EBUILD" == "" ]; then
	KERNEL_EBUILD=gentoo-sources
fi
emerge $KERNEL_EBUILD

