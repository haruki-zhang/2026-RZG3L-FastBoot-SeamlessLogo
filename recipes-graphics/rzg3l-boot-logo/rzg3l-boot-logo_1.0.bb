# SPDX-License-Identifier: MIT
#
# Boot logo payload for the RZ/G3L seamless boot logo.
#
# The U-Boot fast-logo driver runs before the main loop and does
#
#   ext4load mmc 0:2 0x48000000 boot/boot_img_720p.bin.gz
#   unzip    0x48000000 0x58000000
#
# so the images must sit in /boot on the rootfs partition under exactly these
# names. Partition 1 of the BSP layout is vfat and ext4load cannot read it;
# partition 2 is also where the BSP environment keeps Image and the device
# tree, so U-Boot only ever mounts one filesystem.
#
# Payload format: raw ARGB8888 frame buffer, gzip compressed.
#   boot_img_720p.bin.gz    1280x720x4  = 3686400 bytes uncompressed
#   boot_img_1080p.bin.gz   1920x1080x4 = 8294400 bytes uncompressed
#
# The uncompressed size must match, byte for byte, the resolution selected by
# DISPLAY_MODE in drivers/video/rzg2l/rzg2l_video.c - the driver gunzips
# straight into the reserved frame buffer and never checks the geometry.
#
# To ship your own artwork, bbappend this recipe from your own layer with
# FILESEXTRAPATHS:prepend and drop in files of the same names.

SUMMARY = "U-Boot boot logo images for the RZ/G3L seamless boot logo"
DESCRIPTION = "Installs the gzip-compressed raw frame buffer images that the \
U-Boot fast-logo driver loads from /boot on the rootfs partition and scans out \
before the kernel starts."
HOMEPAGE = "https://github.com/renesas-rz"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# unpack=0 matters: the fetcher would gunzip a .gz in SRC_URI during do_unpack,
# and U-Boot wants the compressed file - it runs "unzip" on it itself.
SRC_URI = " \
	file://boot_img_720p.bin.gz;unpack=0 \
	file://boot_img_1080p.bin.gz;unpack=0 \
"

S = "${WORKDIR}"

# Nothing to build, and no toolchain needed to install two blobs.
INHIBIT_DEFAULT_DEPS = "1"
do_configure[noexec] = "1"
do_compile[noexec] = "1"

# The artwork is tied to this machine's display configuration, not just to its
# architecture.
PACKAGE_ARCH = "${MACHINE_ARCH}"

RZG3L_BOOT_LOGO_DIR ?= "/boot"

do_install() {
	install -d ${D}${RZG3L_BOOT_LOGO_DIR}
	install -m 0644 ${WORKDIR}/boot_img_720p.bin.gz  ${D}${RZG3L_BOOT_LOGO_DIR}/
	install -m 0644 ${WORKDIR}/boot_img_1080p.bin.gz ${D}${RZG3L_BOOT_LOGO_DIR}/
}

FILES:${PN} = "${RZG3L_BOOT_LOGO_DIR}"

# Read straight off the block device by U-Boot, so there is nothing to strip,
# debug-split or check for dependencies.
INHIBIT_PACKAGE_STRIP = "1"
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
INHIBIT_SYSROOT_STRIP = "1"
EXCLUDE_FROM_SHLIBS = "1"
