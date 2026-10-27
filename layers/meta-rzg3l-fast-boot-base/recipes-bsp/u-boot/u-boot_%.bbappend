# Bake the fast-boot U-Boot environment into the built-in defaults, so nothing
# has to be typed at the prompt on a freshly flashed board.
#
# The settings split across the two mechanisms U-Boot offers:
#
#   bootdelay                  Kconfig symbol -> fastboot.cfg
#   bootcmd, prodemmcbootargs  CONFIG_BOOTCOMMAND and CFG_EXTRA_ENV_SETTINGS in
#                              include/configs/smarc-rzg3l.h, which Kconfig
#                              cannot reach -> 0001-*.patch
#
# prodsdbootargs is left alone: only the eMMC product path is made quiet, the
# SD development path keeps the BSP's verbose console. See README section IV.
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += " \
    file://0001-configs-smarc-rzg3l-fast-boot-default-environment.patch \
    file://fastboot.cfg \
"

# Immediate assignment: by the time a task runs, THISDIR is the recipe's
# directory rather than this bbappend's, which would point anyone reading the
# error messages below at the wrong layer.
FASTBOOT_UBOOT_DIR := "${THISDIR}"

# ---------------------------------------------------------------------------
# Assert the result rather than assume it
# ---------------------------------------------------------------------------
# Both mechanisms can fail quietly: a fragment entry can be reverted by a
# "select" elsewhere, and a patch can still apply around a moved default.
# u-boot-initial-env is the compiled-in default environment dumped as text, so
# checking it covers the patch and the fragment together, at their result
# rather than at their inputs. do_compile is what generates it.
fastboot_uboot_expect_env() {
    if ! grep -Fqx "$2" "$1"; then
        bbfatal "U-Boot default environment has no '$2' (checked $1). The fast-boot environment changes in ${FASTBOOT_UBOOT_DIR} did not take effect - re-check 0001-*.patch and fastboot.cfg against this U-Boot revision."
    fi
}

fastboot_uboot_check_env() {
    # One call per entry: the values contain spaces, so a single
    # whitespace-separated list would not survive word splitting.
    #
    # Only what this layer sets is checked. Asserting prodsdbootargs, which we
    # do not own, would turn an ordinary BSP change into a build failure here.
    fastboot_uboot_expect_env "$1" 'bootdelay=0'
    fastboot_uboot_expect_env "$1" 'bootcmd=run bootcmd_check;run bootimage'
    fastboot_uboot_expect_env "$1" 'prodemmcbootargs=setenv bootargs rw rootwait root=/dev/mmcblk0p2 quiet systemd.show_status=false'
}

do_compile:append() {
    if [ -z "${UBOOT_INITIAL_ENV}" ]; then
        bbfatal "UBOOT_INITIAL_ENV is empty, so the fast-boot environment cannot be verified. Restore it, or drop this check in ${FASTBOOT_UBOOT_DIR}."
    fi

    # u-boot.inc writes ${B}/u-boot-initial-env without UBOOT_CONFIG and
    # ${B}/<defconfig>/u-boot-initial-env with it. smarc-rzg3l uses the latter.
    envfiles="${B}/u-boot-initial-env"
    for config in ${UBOOT_MACHINE}; do
        envfiles="$envfiles ${B}/$config/u-boot-initial-env"
    done

    checked=0
    for envfile in $envfiles; do
        if [ -e "$envfile" ]; then
            fastboot_uboot_check_env "$envfile"
            checked=$(expr $checked + 1)
        fi
    done

    if [ "$checked" -eq 0 ]; then
        bbfatal "do_compile produced no u-boot-initial-env under ${B}, so the fast-boot environment could not be verified."
    fi
}
