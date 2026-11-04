# BL2 starts the CM33 on whatever is at offset 0x270000 of the boot media. The
# BSP kickstart file puts nothing there, so it is replaced by one that adds the
# CM33 firmware. Images with their own kickstart file (lpdemo-image) keep it.
#
# IMAGE_CLASSES are inherited after the image recipe has set WKS_FILE, so only
# the BSP default is replaced.

FLA_BSP_WKS_FILE ?= "rz-image-bootpart-esd.wks"
FLA_WKS_FILE ?= "fla-bootpart-esd.wks.in"

python __anonymous () {
    if 'RZ_CM33_FIRMWARE_LOAD' not in (d.getVar('MACHINE_FEATURES') or '').split():
        bb.fatal("meta-rzg3l-seamless-logo-cm33-anim needs MACHINE_FEATURES RZ_CM33_FIRMWARE_LOAD "
                 "(meta-rz-multi-os/meta-rzg/meta-rzg3l): BL2 has to start the CM33 firmware")

    if d.getVar('WKS_FILE') == d.getVar('FLA_BSP_WKS_FILE'):
        d.setVar('WKS_FILE', d.getVar('FLA_WKS_FILE'))
}

do_image_wic[depends] += "${RZG3L_CM33_FW}:do_deploy"
