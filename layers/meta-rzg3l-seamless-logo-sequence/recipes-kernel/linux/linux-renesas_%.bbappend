FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# The series of meta-rzg3l-seamless-logo-still, without the static device
# tree declaration:
#
#   0002       not used. U-Boot adds the declaration at boot (U-Boot 0007),
#              only after it has started the display. The same kernel then
#              also works with a bootloader that shows no logo.
#   0008       driver part only. U-Boot also adds the CEA VIC.
#
# The drivers read the declaration at probe, so the kernel does not depend on
# the resolution.
#
# Keep the list in numeric order. do_patch applies it in this order, and each
# patch builds on the ones before it.
SRC_URI:append:smarc-rzg3l = " \
    file://0001-arm64-dts-renesas-rzg3l-smarc-reserve-the-U-Boot-boo.patch \
    file://0003-clk-renesas-r9a08g046-mark-the-MIPI-DSI-and-LCDC-clo.patch \
    file://0004-media-vsp1-take-over-a-pipeline-left-running-by-the-.patch \
    file://0005-drm-rz-du-inherit-a-CRTC-left-running-by-the-bootloa.patch \
    file://0006-drm-rz-du-rzg2l_mipi_dsi-inherit-a-link-left-streami.patch \
    file://0007-drm-bridge-adv7511-keep-an-HDMI-output-configured-by.patch \
    file://0008-drm-bridge-adv7511-pin-the-connector-to-the-bootload.patch \
    file://seamless-logo-sequence.cfg \
"

RZG3L_LOGO_SEQUENCE_KERNEL_DIR := "${THISDIR}"

do_configure:prepend:smarc-rzg3l() {
    dts="${S}/arch/arm64/boot/dts/renesas/r9a08g046l48-smarc.dts"

    # The VSPD keeps reading 0x58000000.. while the kernel boots. In CMA, the
    # first large allocation would overwrite the logo and the display lists.
    if ! grep -q 'framebuffer@58000000' "$dts"; then
        bbfatal "the board device tree does not reserve the U-Boot frame buffer area at 0x58000000. Re-check 0001-*.patch in ${RZG3L_LOGO_SEQUENCE_KERNEL_DIR}."
    fi

    # drm_mode_equal() also compares the aspect ratio. A program without
    # DRM_CLIENT_CAP_ASPECT_RATIO passes the mode without it and is rejected.
    adv="${S}/drivers/gpu/drm/bridge/adv7511/adv7511_drv.c"
    if grep -q 'match = drm_mode_equal(pinned, mode);' "$adv"; then
        bbfatal "adv7511_bridge_mode_valid() compares the pinned mode including its aspect ratio, so plain DRM/KMS programs cannot set a mode. Re-check 0008-*.patch in ${RZG3L_LOGO_SEQUENCE_KERNEL_DIR}."
    fi

    # Starting the pipeline at CRTC enable shows one black frame.
    if ! grep -q 'boot_logo_start_pending' "${S}/drivers/media/platform/renesas/vsp1/vsp1_drm.c"; then
        bbfatal "vsp1 does not defer the pipeline start of a handed-over display, so taking it over shows a black frame. Re-check 0004-*.patch in ${RZG3L_LOGO_SEQUENCE_KERNEL_DIR}."
    fi

    # Only U-Boot may declare the hand-over. A static declaration (another
    # layer, a BSP update) makes the kernel skip its modeset even when no
    # bootloader started the display.
    if grep -q 'renesas,seamless-boot-logo' "$dts"; then
        bbfatal "the board device tree declares the boot logo hand-over statically. With this layer U-Boot adds it at boot, and only when it has started the pipeline. Remove the static declaration (is meta-rzg3l-seamless-logo-still also in the build?)."
    fi
}

# Another fragment or a "select" can turn a symbol back on. The logo then goes
# black a few seconds into boot, with nothing in the log. Check the final
# .config.
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
