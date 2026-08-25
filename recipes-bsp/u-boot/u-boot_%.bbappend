# Phase 0: bake the fast-boot U-Boot environment into the built-in defaults.
#
# The three settings that used to be applied by hand at the U-Boot prompt:
#
#   setenv bootdelay 0
#   setenv prodemmcbootargs 'setenv bootargs rw rootwait root=/dev/mmcblk0p2 quiet systemd.show_status=false'
#   setenv bootcmd 'run bootcmd_check;run bootimage'
#
# They are split across the two mechanisms U-Boot actually offers:
#
#   bootdelay      is a Kconfig symbol (CONFIG_BOOTDELAY) that env_default.h
#                  turns into an environment variable, so it belongs in a
#                  defconfig fragment -> fastboot.cfg
#
#   bootcmd and prodemmcbootargs live in CONFIG_BOOTCOMMAND and
#                  CFG_EXTRA_ENV_SETTINGS in include/configs/smarc-rzg3l.h,
#                  which Kconfig cannot reach -> 0001-*.patch
#
# prodsdbootargs is left alone. Only the eMMC command line is made quiet; the
# SD path is the development boot loop and keeps the BSP's verbose console.
#
# Do not move bootdelay into the header as well: env_default.h already emits a
# "bootdelay=" entry from CONFIG_BOOTDELAY, and a second one out of
# CFG_EXTRA_ENV_SETTINGS would leave two entries for one key in the default
# environment blob.
#
# These are the compiled-in *defaults*. A board whose eMMC already holds a
# saved environment keeps using that one - see README section V for the
# one-time "env default -a; saveenv" that switches such a board over.
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += " \
    file://0001-configs-smarc-rzg3l-fast-boot-default-environment.patch \
    file://fastboot.cfg \
"

# Immediate assignment: by the time a task runs, THISDIR is the directory of
# the recipe rather than of this bbappend, which would send anyone reading the
# error messages below to the wrong layer.
FASTBOOT_UBOOT_DIR := "${THISDIR}"

# ---------------------------------------------------------------------------
# Assert the result rather than assume it
# ---------------------------------------------------------------------------
# Both mechanisms can fail quietly. A defconfig fragment can be reverted by a
# "select" from another symbol or name a symbol that no longer exists (README
# VII.1 has a kernel-side example of exactly that), and a rebased BSP could
# move the header defaults somewhere the patch still applies around.
#
# u-boot-initial-env is the compiled-in default environment dumped as text, so
# checking it covers the patch and the fragment together, at their end result
# rather than at their inputs. do_compile generates it, which is why the check
# hangs off do_compile and not do_configure.
fastboot_uboot_expect_env() {
    if ! grep -Fqx "$2" "$1"; then
        bbfatal "U-Boot default environment has no '$2' (checked $1). The fast-boot environment changes in ${FASTBOOT_UBOOT_DIR} did not take effect - re-check 0001-*.patch and fastboot.cfg against this U-Boot revision."
    fi
}

fastboot_uboot_check_env() {
    # One call per entry: the values contain spaces, so a single
    # whitespace-separated list would not survive word splitting.
    #
    # Only what this layer sets is checked. prodsdbootargs is intentionally
    # absent: asserting a value we do not own would turn an ordinary BSP
    # command-line change on the SD path into a build failure here.
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
