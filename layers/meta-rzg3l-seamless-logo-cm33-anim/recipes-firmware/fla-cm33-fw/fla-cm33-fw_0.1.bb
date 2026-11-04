SUMMARY = "RZ/G3L CM33 fast logo animation - animation-only CM33 firmware (BL22)"
DESCRIPTION = "Bare-metal Cortex-M33 firmware loaded and started by BL2 \
(meta-rz-multi-os RZ_CM33_FIRMWARE_LOAD) that switches the Layer1 (RPF1) frames of the \
boot logo. Used when the project has no other CM33 firmware: with \
meta-rzg3l-lp-display-demo the animation is linked into lpdemo-cm33-fw instead \
(RZG3L_CM33_FW)."
LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/BSD-3-Clause;md5=550794465ba0ec5312d6919e203a55f9"

COMPATIBLE_MACHINE = "smarc-rzg3l"

inherit deploy

SRC_URI = " \
    file://fla-cm33-fw \
    file://fla-anim \
"
S = "${WORKDIR}/fla-cm33-fw"

DEPENDS = "gcc-arm-none-eabi-native"

# Runs on the CM33, so it needs no target libc.
INHIBIT_DEFAULT_DEPS = "1"
PACKAGE_ARCH = "${MACHINE_ARCH}"

do_configure[noexec] = "1"

# e.g. FLA_CM33_EXTRA_CFLAGS = "-DFOO" in local.conf
FLA_CM33_EXTRA_CFLAGS ??= ""

do_compile() {
	# The Makefile sets its own CC and flags; the CA55 ones do not apply.
	oe_runmake -C ${S} CROSS_COMPILE=arm-none-eabi- ANIM_DIR=${WORKDIR}/fla-anim \
		EXTRA_CFLAGS="${FLA_CM33_EXTRA_CFLAGS}"
}

# BL2 reads the firmware from the boot media, not from the rootfs
# (fla-bootpart-esd.wks.in; QSPI 0x270000, eMMC boot partition 1 sector 0x1380).
do_install[noexec] = "1"
ALLOW_EMPTY:${PN} = "1"

do_deploy() {
	install -d ${DEPLOYDIR}
	for f in bin srec elf map; do
		install -m 0644 ${S}/out/fla-cm33-fw.$f ${DEPLOYDIR}/fla-cm33-fw-${MACHINE}.$f
	done
}
addtask deploy after do_compile before do_build
