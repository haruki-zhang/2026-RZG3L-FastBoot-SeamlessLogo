# Let Weston start in parallel with the multi-user service chain.
#
# meta-rz-distro's weston-init bbappend adds "multi-user.target" to weston's
# After= line, which serialises the compositor behind network, connman, avahi
# and everything else in that chain. Undo it.
#
# This bbappend also *asserts* that weston keeps its logind session. An earlier
# revision stripped User=/Group=/PAMName= to skip session setup, which saved
# 2118 ms and deadlocked suspend to RAM: without a session weston takes the VT
# over itself and never answers the release hand-shake, so pm_prepare_console()
# blocks before a single task is frozen. See README section VI.
#
# No-op for images that do not install Weston.
do_install:append() {
    unit="${D}${systemd_system_unitdir}/weston.service"
    if [ ! -e "$unit" ]; then
        return 0
    fi

    sed -i -e 's/ multi-user\.target//g' "$unit"

    for expected in \
            '^User=weston$' \
            '^Group=weston$' \
            '^PAMName=weston-autologin$' ; do
        if ! grep -q "$expected" "$unit"; then
            bbfatal "weston.service no longer has '$expected'. Weston would fall back to launcher-direct, take the VT over and deadlock suspend to RAM. Re-check ${THISDIR}"
        fi
    done
}
