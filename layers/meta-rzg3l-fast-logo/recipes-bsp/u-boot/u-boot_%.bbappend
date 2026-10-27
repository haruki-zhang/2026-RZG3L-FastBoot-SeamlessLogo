FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# do_patch applies SRC_URI entries in the order listed here and 0003/0004 edit
# the driver added by 0002, so keep them in numeric order.
SRC_URI += " \
	file://0001-configs-smarc-rzg3l-add-CONFIG_VIDEO-y.patch \
	file://0002-add-Display-Drivers.patch \
	file://0003-video-rzg2l-load-the-boot-logo-from-the-rootfs-parti.patch \
	file://0004-video-rzg2l-wait-for-two-frames-instead-of-a-flat-se.patch \
"

# 0003 reads the splash from /boot on the rootfs partition, which is where
# rzg3l-boot-logo installs it. Building U-Boot on its own is fine; the image
# just will not have the file until that recipe has been installed too.
