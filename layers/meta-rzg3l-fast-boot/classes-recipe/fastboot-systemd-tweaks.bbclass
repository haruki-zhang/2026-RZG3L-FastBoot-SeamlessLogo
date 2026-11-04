# SPDX-License-Identifier: MIT
#
# These units ship inside the systemd recipe, so SYSTEMD_AUTO_ENABLE cannot
# reach them. Both helpers write to ${sysconfdir}/systemd/system, the admin
# override directory, so the packaged unit files stay unchanged.

# vconsole-setup       the board has no VT keyboard.
# serial-getty@ttyS0   the console is ttySC3.
# network services     the device tree disables both Ethernet ports. Together
#                      they take 2.5 s, and resolved is on the sysinit.target
#                      critical chain.
#
# userdbd.socket is masked too, so a query cannot start the masked service.
# All accounts are in /etc/passwd. networkd-wait-online is still wanted by
# network-online.target and can only fail.
#
# To restore a unit, also re-enable its device-tree node and DISTRO_FEATURES
# entry.
FASTBOOT_MASKED_UNITS ?= "\
    systemd-vconsole-setup.service \
    serial-getty@ttyS0.service \
    systemd-resolved.service \
    systemd-timesyncd.service \
    systemd-networkd.service \
    systemd-networkd.socket \
    systemd-networkd-wait-online.service \
    systemd-network-generator.service \
    systemd-userdbd.service \
    systemd-userdbd.socket \
"

fastboot_mask_units() {
    install -d ${IMAGE_ROOTFS}${sysconfdir}/systemd/system
    for u in ${FASTBOOT_MASKED_UNITS}; do
        ln -sf /dev/null ${IMAGE_ROOTFS}${sysconfdir}/systemd/system/$u
    done
}

# systemd-random-seed waits about 1 s in sysinit.target: it blocks in
# getrandom() until the CRNG is ready. Crediting the saved seed makes the CRNG
# ready at once.
#
# This is safe because:
#   - the image ships no seed, so each board creates its own;
#   - "true", not "force": systemd still rejects a short or unsafe seed file;
#   - the seed is on the persistent rootfs and is renewed at every boot, so
#     a power cut still leaves a valid seed.
#
# The first boot after writing the board has no seed and still waits.
fastboot_random_seed_credit() {
    seeddir=${IMAGE_ROOTFS}${sysconfdir}/systemd/system/systemd-random-seed.service.d
    install -d $seeddir
    cat > $seeddir/99-fastboot.conf <<'EOF'
[Service]
Environment=SYSTEMD_RANDOM_SEED_CREDIT=true
EOF
    chmod 0644 $seeddir/99-fastboot.conf
}

ROOTFS_POSTPROCESS_COMMAND += "fastboot_mask_units"
ROOTFS_POSTPROCESS_COMMAND += "fastboot_random_seed_credit"
