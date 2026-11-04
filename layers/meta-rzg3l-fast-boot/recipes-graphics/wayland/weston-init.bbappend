# meta-rz-graphics adds multi-user.target to weston's After=, so Weston waits
# for network, connman, avahi and the rest. Remove it.
#
# Weston must keep its logind session (User=, Group=, PAMName=). Without it,
# Weston takes over the VT itself and suspend to RAM hangs. Removing the
# session saves about 2 s, so the check below stops anyone from trying.
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
