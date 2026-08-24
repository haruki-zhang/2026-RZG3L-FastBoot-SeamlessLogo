# Phase 2: let Weston start in parallel with the multi-user service chain.
# meta-rz-distro's weston-init bbappend adds "multi-user.target" to weston's
# After= line, which serialises the compositor behind the whole multi-user
# chain (network, connman, avahi, ...). Undo that.
#
# This is a no-op for images that do not install Weston.
do_install:append() {
    if [ -e ${D}${systemd_system_unitdir}/weston.service ]; then
        sed -i -e 's/ multi-user\.target//g' \
            ${D}${systemd_system_unitdir}/weston.service
    fi
}
