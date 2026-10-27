# Bring the MIPI DSI -> ADV7535 -> HDMI pipeline up in U-Boot, play the boot
# logo frames once through a self-advancing VSPD display list chain and park on
# the last one, then tell the kernel it has a running pipeline to inherit.
#
#   0001-0004  imported verbatim from meta-rzg3l-seamless-logo-still:
#              CONFIG_VIDEO, the drivers/video/rzg2l display driver run from
#              init_sequence_r, the frames loaded from /boot on the rootfs
#              partition, and a two-frame wait instead of a flat second
#   0005-0007  1080p, the self-advancing display list chain that plays once
#              and parks, and run-time detection of the boot medium
#   0008       the timing table is picked from RZG2L_LOGO_WIDTH/HEIGHT, and
#              the frame files carry the geometry in their names
#   0009       play however many frames are installed; frame 0 gets its full
#              time on screen
#   0010       declare the hand-over to the kernel in the device tree at boot,
#              from ft_system_setup() (CONFIG_OF_SYSTEM_SETUP, turned on in
#              smarc-rzg3l_defconfig), and only for a pipeline that actually
#              started
#
# do_patch applies SRC_URI entries in the order listed and 0003 onwards all edit
# the driver added by 0002, so keep them in numeric order.
#
# Everything is restricted to smarc-rzg3l: the driver programs that board's
# display path by physical address.
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append:smarc-rzg3l = " \
    file://0001-configs-smarc-rzg3l-add-CONFIG_VIDEO-y.patch \
    file://0002-add-Display-Drivers.patch \
    file://0003-video-rzg2l-load-the-boot-logo-from-the-rootfs-parti.patch \
    file://0004-video-rzg2l-wait-for-two-frames-instead-of-a-flat-se.patch \
    file://0005-video-rzg2l-select-the-1080p-display-mode.patch \
    file://0006-video-rzg2l-play-a-multi-frame-intro-from-a-self-adv.patch \
    file://0007-video-rzg2l-find-the-intro-on-whichever-medium-the-b.patch \
    file://0008-video-rzg2l-pick-the-display-timing-from-the-logo-re.patch \
    file://0009-video-rzg2l-play-however-many-frames-are-installed.patch \
    file://0010-video-rzg2l-declare-the-hand-over-to-the-kernel-from.patch \
"

# Immediate assignment: by the time a task runs THISDIR is the recipe's
# directory rather than this bbappend's, which would point anyone reading the
# error messages below at the wrong layer.
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

# The display driver takes its resolution and default pace from these macros.
# Changing any of them changes the do_compile signature, so U-Boot is rebuilt.
EXTRA_OEMAKE:append:smarc-rzg3l = ' KCFLAGS="-DRZG2L_LOGO_WIDTH=${RZG3L_LOGO_SEQUENCE_WIDTH} -DRZG2L_LOGO_HEIGHT=${RZG3L_LOGO_SEQUENCE_HEIGHT} -DRZG2L_LOGO_RATE_MS=${RZG3L_LOGO_SEQUENCE_RATE_MS}"'

# Assert the result rather than assume it. A patch can apply around a moved
# line, and a BSP update can move the driver out from under the whole series,
# so check the patched source instead of trusting do_patch.
do_configure:prepend:smarc-rzg3l() {
    v="${S}/drivers/video/rzg2l/rzg2l_video.c"

    if [ ! -e "$v" ]; then
        bbfatal "$v does not exist after do_patch. The display driver from ${RZG3L_LOGO_SEQUENCE_UBOOT_DIR} did not land - re-check 0002-*.patch against this U-Boot revision."
    fi

    # The list of resolutions lives in one place, the driver. Report a missing
    # timing table here, by name, rather than as an #error deep in do_compile.
    if ! grep -Eq "^#(el)?if \(RZG2L_LOGO_WIDTH == ${RZG3L_LOGO_SEQUENCE_WIDTH}\) && \(RZG2L_LOGO_HEIGHT == ${RZG3L_LOGO_SEQUENCE_HEIGHT}\)" "$v"; then
        bbfatal "the U-Boot display driver has no timing table for ${RZG3L_LOGO_SEQUENCE_RESOLUTION} (RZG3L_LOGO_SEQUENCE_RESOLUTION). Add a define_*.h and one #elif to drivers/video/rzg2l/rzg2l_video.c - see README section IV of the layer in ${RZG3L_LOGO_SEQUENCE_UBOOT_DIR}/../.."
    fi

    # rzg3l-seamless-logo-sequence-frames installs the frames under exactly
    # this name.
    if ! grep -q '"boot/fastlogo_%ux%u_%02u.bin.gz"' "$v"; then
        bbfatal "U-Boot does not load boot/fastlogo_<W>x<H>_NN.bin.gz, which is where rzg3l-seamless-logo-sequence-frames installs the frames. Re-check 0008-*.patch in ${RZG3L_LOGO_SEQUENCE_UBOOT_DIR}."
    fi

    # The boot medium is a run-time decision. The same image boots from eMMC
    # or from microSD, and a device number compiled into the load command is
    # silently right on one and silently wrong on the other.
    if grep -Eq 'ext4load[[:space:]]+mmc[[:space:]]+[0-9]+:' "$v"; then
        bbfatal "the display driver has a hard-coded MMC device in its ext4load command. It must select the device at run time - see 0007-*.patch in ${RZG3L_LOGO_SEQUENCE_UBOOT_DIR}."
    fi

    # Without this the kernel is never told to inherit the pipeline, and
    # re-initialises the display at its first modeset.
    if ! grep -q '^int ft_system_setup(void \*blob, struct bd_info \*bd)' "$v"; then
        bbfatal "the display driver does not declare the hand-over to the kernel. Re-check 0010-*.patch in ${RZG3L_LOGO_SEQUENCE_UBOOT_DIR}."
    fi
}

# ft_system_setup() is only called with CONFIG_OF_SYSTEM_SETUP, and the driver
# refuses to build without it. Check the generated configuration anyway, so a
# config fragment from another layer that turns it off is reported by name
# rather than as an #error from the compiler.
do_configure:append:smarc-rzg3l() {
    found=0
    for c in ${B}/*/.config; do
        [ -e "$c" ] || continue
        found=1
        if ! grep -q '^CONFIG_OF_SYSTEM_SETUP=y$' "$c"; then
            bbfatal "$c does not have CONFIG_OF_SYSTEM_SETUP=y, so U-Boot would never declare the boot logo hand-over to the kernel. 0010-*.patch in ${RZG3L_LOGO_SEQUENCE_UBOOT_DIR} turns it on in smarc-rzg3l_defconfig; something later turned it off."
        fi
    done
    [ "$found" = 1 ] || bbfatal "no U-Boot .config under ${B} after do_configure; cannot check CONFIG_OF_SYSTEM_SETUP."
}
