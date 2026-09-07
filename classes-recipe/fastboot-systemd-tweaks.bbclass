# SPDX-License-Identifier: MIT
#
# systemd behaviour that recipe variables cannot reach, because the units
# involved ship inside the systemd recipe itself and so have no
# SYSTEMD_AUTO_ENABLE of their own. Both helpers write into
# ${sysconfdir}/systemd/system, the admin override directory, so nothing here
# fights the packaged unit files.
#
# Hooked onto every image recipe through IMAGE_CLASSES in rz-vlp-fast.conf.

# ---------------------------------------------------------------------------
# Masked units
# ---------------------------------------------------------------------------
# vconsole-setup   sets VT fonts and keymaps; this board has no VT keyboard
# serial-getty@ttyS0  belt and braces, SERIAL_CONSOLES only lists ttySC3
# resolved/networkd/timesyncd/userdbd/network-generator
#                  the DT profile disables both GbE ports, so there is no
#                  interface to configure, no NTP server to reach and no name
#                  to resolve. Together 2.51 service-seconds, and resolved sits
#                  on the sysinit.target critical chain.
#
# userdbd is masked with its socket so a varlink query cannot activate a masked
# service; every account in this image is in /etc/passwd, so glibc never needs
# it. networkd-wait-online is masked because network-online.target.wants still
# references it and it could only ever fail.
#
# Restoring any of these means un-masking the unit *and* restoring the DT node
# and the DISTRO_FEATURES entry it belongs to. See README section V.
#
# Override from a conf file to add or remove units.
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

# ---------------------------------------------------------------------------
# systemd-random-seed.service: credit the saved seed
# ---------------------------------------------------------------------------
# The service blocks ~1 s inside sysinit.target. It is not slow, it is waiting:
# after writing the saved seed to /dev/urandom it generates a fresh one to write
# back, and that blocks in getrandom() until the CRNG initialises. Crediting the
# seed initialises the CRNG on the spot, so the second half stops blocking.
#
# Safe here because:
#   - the image ships no seed file, so every board generates its own on its own
#     first boot and no two devices credit the same bytes;
#   - "true" rather than "force", so systemd still refuses a seed that is too
#     short or has permissive modes, degrading to today's behaviour;
#   - /var/lib is on the persistent rootfs, so the seed survives reboots;
#   - the refreshed seed is written during load, not only by save at shutdown,
#     so a hard power cycle still leaves a valid seed behind.
#
# The first boot after flashing has no seed to credit and still pays the wait.
# Removing that case needs U-Boot to publish /chosen/rng-seed; 6.12 already
# credits a bootloader seed unconditionally.
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
