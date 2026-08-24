# SPDX-License-Identifier: MIT
#
# Rootfs post-processing for systemd behaviour that cannot be reached through
# recipe variables, because the units involved ship inside the systemd recipe
# itself and so have no SYSTEMD_AUTO_ENABLE of their own:
#
#   fastboot_mask_units          symlink units to /dev/null
#   fastboot_random_seed_credit  drop-in for systemd-random-seed.service
#
# Both write into ${sysconfdir}/systemd/system, the admin override directory,
# so nothing here fights the packaged unit files.
#
# Hooked onto every image recipe through IMAGE_CLASSES in the distro conf.

# ---------------------------------------------------------------------------
# Masked units
# ---------------------------------------------------------------------------
# Phase 2
#
#   systemd-vconsole-setup.service
#       Sets VT fonts and keymaps. This board has no VT keyboard (~264 ms in
#       the original boot log).
#
#   serial-getty@ttyS0.service
#       Belt and braces: SERIAL_CONSOLES only lists ttySC3, so the ttyS0 unit
#       should already be absent.
#
# Phase 2b - the network and identity services (README VII.2)
#
#   The DT profile disables both GbE ports, so there is no interface to
#   configure, no NTP server to reach and no name to resolve. Measured on the
#   EVK: resolved 766 ms, networkd 739 ms, timesyncd 669 ms, userdbd 213 ms,
#   network-generator 123 ms.
#
#   resolved matters most because it is on the sysinit.target critical chain -
#   and it is wired oddly: the systemd recipe puts it in sysinit.target.wants
#   while the unit orders itself After=systemd-networkd.service, which lives in
#   multi-user. Nothing in this image asks it anything: /etc/nsswitch.conf uses
#   "hosts: files myhostname dns" with no nss-resolve, and /etc/resolv.conf is
#   a symlink to connman's copy.
#
#   userdbd is masked together with its socket so a varlink query cannot try to
#   activate a masked service. /etc/nsswitch.conf queries "compat" before
#   "systemd" and every account in this image - including weston, uid 998 - is
#   in /etc/passwd, so glibc never needs the user database.
#
#   networkd-wait-online is masked because network-online.target.wants still
#   references it; with networkd masked it could only ever fail.
#
# Restoring any of these means un-masking the unit *and* restoring the DT node
# and the DISTRO_FEATURES entry it belongs to. See section VI.
#
# Override FASTBOOT_MASKED_UNITS from a conf file to add or remove units.
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
# The service blocks 998 ms inside sysinit.target. It is not slow at what it
# does; it is waiting for the kernel CRNG. In `load` mode it writes the saved
# seed to /dev/urandom and then immediately generates a *fresh* seed to write
# back, and that generation blocks in getrandom() until the pool is
# initialised - "random: crng init done" lands at 2.590s on this board.
#
# Crediting fixes the first half of that: entropy from the seed file is
# accounted to the pool through RNDADDENTROPY, which initialises the CRNG on
# the spot, so the second half no longer blocks. It also brings crng init
# roughly a second forward for everything else in the boot.
#
# Why this is safe here:
#
#   * The image ships no seed file, only the empty /var/lib/systemd directory.
#     Every board therefore generates its own seed on its own first boot, so no
#     two devices ever credit the same bytes. That is the condition
#     systemd-random-seed(8) attaches to this option.
#
#   * "true" rather than "force": systemd refuses to credit a seed file shorter
#     than the kernel pool size or with permissive access modes, so a truncated
#     or tampered file degrades to today's behaviour instead of inflating the
#     entropy estimate.
#
#   * /var/lib is on the persistent rootfs, not on the volatile tmpfs -
#     var-volatile-lib.service is skipped by its own
#     ConditionPathIsReadWrite=!/var/lib on this rw-rootfs image - so the seed
#     survives across boots.
#
#   * The refreshed seed is written during `load`, not only by `save` at
#     shutdown, so hard power cycles still leave a valid seed behind.
#
# Consequence to be aware of: the very first boot after flashing has no seed to
# credit and still pays the wait. Removing that last case needs the bootloader
# to publish /chosen/rng-seed; fastboot.cfg already enables
# CONFIG_RANDOM_TRUST_BOOTLOADER, so only the U-Boot side is outstanding.
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
