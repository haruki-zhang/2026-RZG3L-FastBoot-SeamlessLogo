# Built into the default environment, so a newly written board needs no setenv.
#
#   bootdelay                  Kconfig -> fastboot.cfg
#   bootcmd, prodemmcbootargs  include/configs/smarc-rzg3l.h, not reachable
#                              from Kconfig -> 0001-*.patch
#
# prodsdbootargs is not changed: SD boot is for development and keeps the
# verbose console.
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += " \
    file://0001-configs-smarc-rzg3l-fast-boot-default-environment.patch \
    file://fastboot.cfg \
"

# ":=" because THISDIR points to the recipe, not to this layer, when a task
# runs. The error messages below must name this layer.
FASTBOOT_UBOOT_DIR := "${THISDIR}"

# Both changes can fail silently: a "select" can revert a fragment entry, and
# a patch can apply next to a moved default. u-boot-initial-env is the built
# default environment, so checking it covers both. do_compile generates it.
fastboot_uboot_expect_env() {
    if ! grep -Fqx "$2" "$1"; then
        bbfatal "U-Boot default environment has no '$2' (checked $1). The fast-boot environment changes in ${FASTBOOT_UBOOT_DIR} did not take effect - re-check 0001-*.patch and fastboot.cfg against this U-Boot revision."
    fi
}

fastboot_uboot_check_env() {
    # One call per entry, because the values contain spaces.
    # Only values set by this layer are checked, so BSP changes to other
    # variables do not break the build.
    fastboot_uboot_expect_env "$1" 'bootdelay=0'
    fastboot_uboot_expect_env "$1" 'bootcmd=run bootcmd_check;run bootimage'
    fastboot_uboot_expect_env "$1" 'prodemmcbootargs=setenv bootargs rw rootwait root=/dev/mmcblk0p2 quiet systemd.show_status=false'
}

do_compile:append() {
    if [ -z "${UBOOT_INITIAL_ENV}" ]; then
        bbfatal "UBOOT_INITIAL_ENV is empty, so the fast-boot environment cannot be verified. Restore it, or drop this check in ${FASTBOOT_UBOOT_DIR}."
    fi

    # u-boot.inc writes ${B}/<defconfig>/u-boot-initial-env with UBOOT_CONFIG
    # (smarc-rzg3l), and ${B}/u-boot-initial-env without it.
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
