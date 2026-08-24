FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# Phase 1: disable unused product peripherals and trim the matching kernel
# subsystems while preserving the display, boot storage and thermal paths.
SRC_URI += "file://0001-arm64-dts-renesas-rzg3l-smarc-disable-unused-periphe.patch"
SRC_URI += "file://fastboot.cfg"

# rz-vlp-fast.conf pins linux-renesas to 6.12%. Keep the wildcard bbappend so a
# future incompatible recipe fails loudly instead of silently dropping these
# fast-boot changes.
