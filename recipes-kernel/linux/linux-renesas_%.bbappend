FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# The patches form one linear series and do_patch applies SRC_URI entries in
# the order listed here, so keep them in numeric order: 0002 and 0008 extend
# the smarc dts nodes added by their predecessors, 0008 extends the adv7511
# state added by 0007, and 0009 edits all three of the hunks 0007 and 0008
# introduced. "devtool finish" emits this list unordered - re-sort it by hand
# after every regeneration.
SRC_URI += " \
	file://0001-arm64-dts-renesas-rzg3l-smarc-reserve-the-U-Boot-boo.patch \
	file://0002-arm64-dts-renesas-rzg3l-smarc-declare-the-boot-logo-.patch \
	file://0003-clk-renesas-r9a08g046-mark-the-MIPI-DSI-and-LCDC-clo.patch \
	file://0004-media-vsp1-take-over-a-pipeline-left-running-by-the-.patch \
	file://0005-drm-rz-du-inherit-a-CRTC-left-running-by-the-bootloa.patch \
	file://0006-drm-rz-du-rzg2l_mipi_dsi-inherit-a-link-left-streami.patch \
	file://0007-drm-bridge-adv7511-keep-an-HDMI-output-configured-by.patch \
	file://0008-drm-bridge-adv7511-pin-the-connector-to-the-bootload.patch \
	file://0009-drm-bridge-adv7511-stop-the-KMS-poll-from-tearing-th.patch \
	file://fast-logo.cfg \
"
