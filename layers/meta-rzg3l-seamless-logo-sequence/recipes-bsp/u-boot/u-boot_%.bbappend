# Keep the numeric order: 0003-0008 change the driver added by 0002.
# 0001-0004 are the same as in meta-rzg3l-seamless-logo-still, and 0008 is the
# same change as its 0005.
#
# Only for smarc-rzg3l: the driver uses the physical addresses of this board.
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append:smarc-rzg3l = " \
    file://0001-configs-smarc-rzg3l-add-CONFIG_VIDEO-y.patch \
    file://0002-add-Display-Drivers.patch \
    file://0003-video-rzg2l-load-the-boot-logo-from-the-rootfs-parti.patch \
    file://0004-video-rzg2l-wait-for-two-frames-instead-of-a-flat-se.patch \
    file://0005-video-rzg2l-play-a-multi-frame-intro-from-a-self-adv.patch \
    file://0006-video-rzg2l-pick-the-display-timing-from-the-logo-re.patch \
    file://0007-video-rzg2l-declare-the-hand-over-to-the-kernel-from.patch \
    file://0008-video-rzg2l-let-the-DU-recover-from-a-PBUF-underflow.patch \
"

# ":=" because THISDIR points to the recipe, not to this layer, when a task
# runs. The error messages below must name this layer.
RZG3L_LOGO_SEQUENCE_UBOOT_DIR := "${THISDIR}"

python () {
    import re

    res = d.getVar('RZG3L_LOGO_SEQUENCE_RESOLUTION') or ''
    m = re.fullmatch(r'([1-9][0-9]*)x([1-9][0-9]*)', res)
    if not m:
        bb.fatal("RZG3L_LOGO_SEQUENCE_RESOLUTION is '%s'; expected <width>x<height>, "
                 "for example 1920x1080." % res)
    d.setVar('RZG3L_LOGO_SEQUENCE_WIDTH', m.group(1))
    d.setVar('RZG3L_LOGO_SEQUENCE_HEIGHT', m.group(2))

    rate = d.getVar('RZG3L_LOGO_SEQUENCE_RATE_MS') or ''
    if not rate.isdigit() or int(rate) < 1:
        bb.fatal("RZG3L_LOGO_SEQUENCE_RATE_MS is '%s'; expected a positive number "
                 "of milliseconds." % rate)
}

# Passed in EXTRA_OEMAKE, so a change also changes the do_compile signature
# and U-Boot is rebuilt.
EXTRA_OEMAKE:append:smarc-rzg3l = ' KCFLAGS="-DRZG2L_LOGO_WIDTH=${RZG3L_LOGO_SEQUENCE_WIDTH} -DRZG2L_LOGO_HEIGHT=${RZG3L_LOGO_SEQUENCE_HEIGHT} -DRZG2L_LOGO_RATE_MS=${RZG3L_LOGO_SEQUENCE_RATE_MS}"'

# A patch can apply next to a moved line, and a BSP update can break the
# series. Check the patched source instead of trusting do_patch.
do_configure:prepend:smarc-rzg3l() {
    v="${S}/drivers/video/rzg2l/rzg2l_video.c"

    if [ ! -e "$v" ]; then
        bbfatal "$v does not exist after do_patch. The display driver from ${RZG3L_LOGO_SEQUENCE_UBOOT_DIR} did not land - re-check 0002-*.patch against this U-Boot revision."
    fi

    # Report a missing timing table here, by name, instead of as an #error in
    # do_compile.
    if ! grep -Eq "^#(el)?if \(RZG2L_LOGO_WIDTH == ${RZG3L_LOGO_SEQUENCE_WIDTH}\) && \(RZG2L_LOGO_HEIGHT == ${RZG3L_LOGO_SEQUENCE_HEIGHT}\)" "$v"; then
        bbfatal "the U-Boot display driver has no timing table for ${RZG3L_LOGO_SEQUENCE_RESOLUTION} (RZG3L_LOGO_SEQUENCE_RESOLUTION). Add a define_*.h and one #elif to drivers/video/rzg2l/rzg2l_video.c - see README section III of the layer in ${RZG3L_LOGO_SEQUENCE_UBOOT_DIR}/../.."
    fi

    # rzg3l-seamless-logo-sequence-frames installs the frames under this name.
    if ! grep -q '"boot/fastlogo_%ux%u_%02u.bin.gz"' "$v"; then
        bbfatal "U-Boot does not load boot/fastlogo_<W>x<H>_NN.bin.gz, which is where rzg3l-seamless-logo-sequence-frames installs the frames. Re-check 0006-*.patch in ${RZG3L_LOGO_SEQUENCE_UBOOT_DIR}."
    fi

    # The same image boots from eMMC or microSD. A fixed device number would
    # be wrong for one of them, without any error.
    if grep -Eq 'ext4load[[:space:]]+mmc[[:space:]]+[0-9]+:' "$v"; then
        bbfatal "the display driver has a hard-coded MMC device in its ext4load command. It must select the device at run time - see 0005-*.patch in ${RZG3L_LOGO_SEQUENCE_UBOOT_DIR}."
    fi

    # Without the declaration, the kernel resets the display at its first
    # modeset.
    if ! grep -q '^int ft_system_setup(void \*blob, struct bd_info \*bd)' "$v"; then
        bbfatal "the display driver does not declare the hand-over to the kernel. Re-check 0007-*.patch in ${RZG3L_LOGO_SEQUENCE_UBOOT_DIR}."
    fi

    # Without PB_AUTOCLR, one PBUF underflow leaves the screen magenta until
    # the next full modeset. The inherited CRTC never gets one.
    if ! grep -Eq '^[[:space:]]+\{0x10890040,[[:space:]]*0x00010000\}' "$v"; then
        bbfatal "the display driver does not program DU_MCR1.PB_AUTOCLR (0x10890040 = 0x00010000). Re-check 0011-*.patch in ${RZG3L_LOGO_SEQUENCE_UBOOT_DIR}."
    fi
}

# The driver does not build without CONFIG_OF_SYSTEM_SETUP. This check names
# the cause when a fragment from another layer turns it off, instead of an
# #error from the compiler.
do_configure:append:smarc-rzg3l() {
    found=0
    for c in ${B}/*/.config; do
        [ -e "$c" ] || continue
        found=1
        if ! grep -q '^CONFIG_OF_SYSTEM_SETUP=y$' "$c"; then
            bbfatal "$c does not have CONFIG_OF_SYSTEM_SETUP=y, so U-Boot would never declare the boot logo hand-over to the kernel. 0007-*.patch in ${RZG3L_LOGO_SEQUENCE_UBOOT_DIR} turns it on in smarc-rzg3l_defconfig; something later turned it off."
        fi
    done
    [ "$found" = 1 ] || bbfatal "no U-Boot .config under ${B} after do_configure; cannot check CONFIG_OF_SYSTEM_SETUP."
}
