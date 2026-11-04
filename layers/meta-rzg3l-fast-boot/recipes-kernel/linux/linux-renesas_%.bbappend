FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# Unused peripherals cost probe time and udev events at boot.
SRC_URI += " \
	file://0001-arm64-dts-renesas-rzg3l-smarc-disable-unused-periphe.patch \
	file://fastboot.cfg \
"

# "%" instead of 6.12: with a new kernel version the patch fails to apply,
# instead of the changes being dropped silently.
