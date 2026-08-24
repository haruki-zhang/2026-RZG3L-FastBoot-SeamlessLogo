# SPDX-License-Identifier: MIT
#
# Rootfs post-processing: mask systemd units that cannot be handled through
# SYSTEMD_AUTO_ENABLE. Masking means symlinking the unit to /dev/null.
#
# systemd-vconsole-setup.service ships inside the systemd recipe itself, so
# there is no separate recipe whose SYSTEMD_AUTO_ENABLE could be set - it can
# only be masked in the rootfs. It sets VT fonts and keymaps, and this board
# has no VT keyboard (~264 ms in the original boot log).
#
# serial-getty@ttyS0.service is belt and braces: SERIAL_CONSOLES only lists
# ttySC3, so the ttyS0 unit should already be absent.
#
# Hooked onto every image recipe through IMAGE_CLASSES in the distro conf.
# Override FASTBOOT_MASKED_UNITS from a conf file to add or remove units.

FASTBOOT_MASKED_UNITS ?= "systemd-vconsole-setup.service serial-getty@ttyS0.service"

fastboot_mask_units() {
    install -d ${IMAGE_ROOTFS}${sysconfdir}/systemd/system
    for u in ${FASTBOOT_MASKED_UNITS}; do
        ln -sf /dev/null ${IMAGE_ROOTFS}${sysconfdir}/systemd/system/$u
    done
}

ROOTFS_POSTPROCESS_COMMAND += "fastboot_mask_units"
