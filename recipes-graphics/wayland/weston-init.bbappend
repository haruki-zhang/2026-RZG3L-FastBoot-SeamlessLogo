# Phase 2: let Weston start in parallel with the multi-user service chain.
# meta-rz-distro's weston-init bbappend adds "multi-user.target" to weston's
# After= line, which serialises the compositor behind the whole multi-user
# chain (network, connman, avahi, ...). Undo that.
#
# Phase 2b: run the compositor directly instead of inside a login session.
#
# Stock weston.service runs weston as User=weston with
# PAMName=weston-autologin. pam_systemd then asks logind to create a session,
# and logind brings up a complete per-user service manager for uid 998.
# Measured on the EVK by lining up `systemd-analyze blame`, `systemd-analyze
# plot` and the dmesg audit records (times are kernel-relative):
#
#   4.069s  systemd forks the weston executor, PAM starts
#   4.325s  user@998.service starts
#   6.153s  user@998.service ready                   (blame: 1.827s)
#   6.187s  loginuid set, PAM session established    (audit, comm="(weston)")
#   6.727s  weston active -> graphical.target
#
# 2118 ms of the 2658 ms weston.service spends starting is session setup. The
# compositor itself only needs 540 ms.
#
# What is safe to remove and why:
#
#   User= / Group= / PAMName=  The session is the only reason uid 998 needs a
#       login at all. Dropping PAMName removes the logind session and with it
#       user@998.service and user-runtime-dir@998.service.
#
#   Requires= / After=systemd-user-sessions.service  That unit exists to gate
#       logins. With no login there is nothing to gate, and weston still gets
#       After=basic.target from DefaultDependencies.
#
# What must NOT change:
#
#   weston.socket keeps SocketUser=weston / SocketGroup=wayland and keeps
#       listening on /run/wayland-0. weston inherits the descriptor, so the
#       socket path and its ownership are identical to before, and
#       /etc/profile.d/weston-socket.sh keeps pointing clients at that absolute
#       path. Nothing ever referenced /run/user/998.
#
#   The weston user and its input/video/render group memberships stay in place;
#       weston.socket still needs the user to exist.
#
# weston does still want XDG_RUNTIME_DIR, which used to come from
# user-runtime-dir@998. RuntimeDirectory= gives it a private /run/weston with
# mode 0700, created before ExecStart and removed when the service stops.
#
# Trade-off: the compositor now runs as root and uses weston's launcher-direct
# backend rather than the logind one. The capability actually lost is VT
# switching, which has no user on this board. Revert this hunk if a product
# cannot accept a root compositor - steps VII.1 and VII.2 are independent of
# it. See README VII.3.
#
# This is a no-op for images that do not install Weston.
do_install:append() {
    unit="${D}${systemd_system_unitdir}/weston.service"
    if [ ! -e "$unit" ]; then
        return 0
    fi

    # Phase 2
    sed -i -e 's/ multi-user\.target//g' "$unit"

    # Phase 2b. Assert first: if weston-init stops shipping what we strip, the
    # session plumbing would come back silently and cost 2.1 s again.
    for expected in \
            '^User=weston$' \
            '^Group=weston$' \
            '^PAMName=weston-autologin$' \
            '^Requires=systemd-user-sessions\.service$' \
            '^After=systemd-user-sessions\.service$' \
            '^\[Install\]$' ; do
        if ! grep -q "$expected" "$unit"; then
            bbfatal "weston.service no longer matches '$expected'; re-check the phase-2b fast-boot changes in ${THISDIR}"
        fi
    done

    sed -i \
        -e '/^User=weston$/d' \
        -e '/^Group=weston$/d' \
        -e '/^PAMName=weston-autologin$/d' \
        -e '/^Requires=systemd-user-sessions\.service$/d' \
        -e '/^After=systemd-user-sessions\.service$/d' \
        -e '/^# Make sure we are started after logins are permitted\.$/d' \
        -e '/^# The user to run Weston as\.$/d' \
        -e '/^# Set up a full user session for the user, required by Weston\.$/d' \
        -e '/^\[Install\]$/i # meta-rzg3l-fast-boot-base: replaces the XDG_RUNTIME_DIR that' \
        -e '/^\[Install\]$/i # user-runtime-dir@998.service used to provide.' \
        -e '/^\[Install\]$/i Environment=XDG_RUNTIME_DIR=/run/weston' \
        -e '/^\[Install\]$/i RuntimeDirectory=weston' \
        -e '/^\[Install\]$/i RuntimeDirectoryMode=0700' \
        -e '/^\[Install\]$/i \\' \
        "$unit"
}
