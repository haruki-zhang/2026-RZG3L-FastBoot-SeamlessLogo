FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# Teach every driver on the DRAM -> VSPD -> DU -> MIPI DSI -> ADV7535 -> HDMI
# path to inherit the pipeline U-Boot left running instead of re-creating it.
#
# The series is meta-rzg3l-seamless-logo-still's, with the device tree
# declaration taken out:
#
#   0001       reserve the frame buffers and display lists U-Boot leaves the
#              VSPD fetching from, and move CMA out of the way
#   0002       not used. It wrote "renesas,seamless-boot-logo" into the board
#              .dts. Here U-Boot adds it at boot instead (U-Boot 0010), only
#              when it has actually started the pipeline, so the same kernel
#              brings the display up normally under any other bootloader
#   0003-0007  verbatim
#   0008       the driver half only; its .dts hunk set the pinned CEA VIC,
#              which U-Boot now adds together with the rest
#   0009       verbatim
#   0010       this layer's: corrects the comment in
#              rzg2l_du_crtc_atomic_flush() that claimed the first commit is
#              not flushed. It is - whoever commits first takes the screen -
#              which is what seamless-logo-sequence.cfg is about. No
#              functional change
#   0011       this layer's: the pinned connector accepts its mode without the
#              picture aspect ratio. Otherwise every DRM/KMS program that has
#              not set DRM_CLIENT_CAP_ASPECT_RATIO gets -EINVAL from its first
#              modeset; Weston sets it, plain libdrm programs usually do not
#   0012       this layer's: during the hand-over the VSP pipeline is started
#              on the first display list that has planes in it, from the first
#              atomic flush, instead of on an input-less one from the CRTC
#              enable - which put one black frame between the logo and the
#              first picture
#
# The drivers read the properties at probe, from the tree U-Boot hands over, so
# nothing in the kernel depends on the resolution.
#
# seamless-logo-sequence.cfg keeps every in-kernel client from committing
# before userspace: no framebuffer console, no kernel logo, no DRM fbdev
# emulation, no console on the virtual terminal. See the comments in the
# fragment.
#
# The patches form one linear series and do_patch applies SRC_URI entries in
# the order listed, so keep them in numeric order.
SRC_URI:append:smarc-rzg3l = " \
    file://0001-arm64-dts-renesas-rzg3l-smarc-reserve-the-U-Boot-boo.patch \
    file://0003-clk-renesas-r9a08g046-mark-the-MIPI-DSI-and-LCDC-clo.patch \
    file://0004-media-vsp1-take-over-a-pipeline-left-running-by-the-.patch \
    file://0005-drm-rz-du-inherit-a-CRTC-left-running-by-the-bootloa.patch \
    file://0006-drm-rz-du-rzg2l_mipi_dsi-inherit-a-link-left-streami.patch \
    file://0007-drm-bridge-adv7511-keep-an-HDMI-output-configured-by.patch \
    file://0008-drm-bridge-adv7511-pin-the-connector-to-the-bootload.patch \
    file://0009-drm-bridge-adv7511-stop-the-KMS-poll-from-tearing-th.patch \
    file://0010-drm-rz-du-correct-the-account-of-the-first-commit-in.patch \
    file://0011-drm-bridge-adv7511-accept-the-pinned-mode-without-it.patch \
    file://0012-media-vsp1-start-a-handed-over-pipeline-on-its-first.patch \
    file://seamless-logo-sequence.cfg \
"

RZG3L_LOGO_SEQUENCE_KERNEL_DIR := "${THISDIR}"

do_configure:prepend:smarc-rzg3l() {
    dts="${S}/arch/arm64/boot/dts/renesas/r9a08g046l48-smarc.dts"

    # U-Boot keeps scanning out of 0x58000000.. while the kernel boots; if the
    # region is handed to CMA, the first large allocation paints over the logo
    # and, worse, over the display lists the VSPD is walking.
    if ! grep -q 'framebuffer@58000000' "$dts"; then
        bbfatal "the board device tree does not reserve the U-Boot frame buffer area at 0x58000000. Re-check 0001-*.patch in ${RZG3L_LOGO_SEQUENCE_KERNEL_DIR}."
    fi

    # The declaration belongs to U-Boot. A static one - from another layer, or
    # a BSP update - would make the kernel skip its modeset even under a
    # bootloader that never lit the display.
    # A pinned mode compared with drm_mode_equal() rejects the same timing
    # without its aspect ratio, which is what a program that has not asked for
    # aspect-ratio-aware modes hands back.
    adv="${S}/drivers/gpu/drm/bridge/adv7511/adv7511_drv.c"
    if grep -q 'match = drm_mode_equal(pinned, mode);' "$adv"; then
        bbfatal "adv7511_bridge_mode_valid() compares the pinned mode including its aspect ratio, so plain DRM/KMS programs cannot set a mode. Re-check 0011-*.patch in ${RZG3L_LOGO_SEQUENCE_KERNEL_DIR}."
    fi

    # Without the deferred start the first commit shows a black frame.
    if ! grep -q 'boot_logo_start_pending' "${S}/drivers/media/platform/renesas/vsp1/vsp1_drm.c"; then
        bbfatal "vsp1 does not defer the pipeline start of a handed-over display, so taking it over shows a black frame. Re-check 0012-*.patch in ${RZG3L_LOGO_SEQUENCE_KERNEL_DIR}."
    fi

    if grep -q 'renesas,seamless-boot-logo' "$dts"; then
        bbfatal "the board device tree declares the boot logo hand-over statically. With this layer U-Boot adds it at boot, and only when it has started the pipeline. Remove the static declaration (is meta-rzg3l-seamless-logo-still also in the build?)."
    fi
}

# A fragment only states intent: another fragment, or a "select" somewhere, can
# turn a symbol back on, and the symptom would be a picture that goes black a
# few seconds into boot with nothing in the log. Check the configuration the
# kernel is actually built with.
do_configure:append:smarc-rzg3l() {
    c="${B}/.config"
    [ -e "$c" ] || bbfatal "no kernel .config at $c after do_configure; cannot check the boot logo configuration."

    for sym in CONFIG_FRAMEBUFFER_CONSOLE CONFIG_LOGO CONFIG_DRM_FBDEV_EMULATION CONFIG_VT_CONSOLE; do
        if grep -q "^$sym=[ym]" "$c"; then
            bbfatal "$sym is enabled in $c, but the boot logo needs it off - see the comments in seamless-logo-sequence.cfg in ${RZG3L_LOGO_SEQUENCE_KERNEL_DIR}, which turns it off. Something later turned it back on."
        fi
    done

    for sym in CONFIG_DRM_RZG2L_DU CONFIG_DRM_RZG2L_MIPI_DSI CONFIG_DRM_I2C_ADV7511 CONFIG_VIDEO_RENESAS_VSP1; do
        if ! grep -q "^$sym=y" "$c"; then
            bbfatal "$sym is not built in ($c). Every driver on the boot logo hand-over path has to probe before userspace starts; see seamless-logo-sequence.cfg in ${RZG3L_LOGO_SEQUENCE_KERNEL_DIR}."
        fi
    done
}
