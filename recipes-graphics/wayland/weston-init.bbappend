# Phase 2: let Weston start in parallel with the multi-user service chain.
# meta-rz-distro's weston-init bbappend adds "multi-user.target" to weston's
# After= line, which serialises the compositor behind the whole multi-user
# chain (network, connman, avahi, ...). Undo that.
#
# ---------------------------------------------------------------------------
# Phase 2b (run the compositor outside a login session) has been REMOVED
# ---------------------------------------------------------------------------
#
# This bbappend used to also strip User=, Group=, PAMName= and the
# systemd-user-sessions.service dependency, so that the compositor ran as root
# with no logind session. That saved 2118 ms of the 2658 ms weston.service
# spends starting - and it broke suspend to RAM outright.
#
# Without a logind session weston falls back to its launcher-direct backend,
# which takes the VT over itself: KDSETMODE(KD_GRAPHICS) plus
# VT_SETMODE(VT_PROCESS) on the tty systemd hands it through TTYPath=/dev/tty7.
# From then on weston is the process the kernel has to hand-shake with before
# any VT switch can complete, and it never answers the release signal.
#
# pm_prepare_console() moves the console to SUSPEND_CONSOLE before a single
# task is frozen, so "echo mem > /sys/power/state" ends up in
#
#   __vt_event_wait <- vt_waitactive <- vt_move_to_console
#                   <- pm_prepare_console <- pm_suspend <- state_store
#
# and stays there. Observed on the EVK: the compositor stays on screen, the
# module board keeps AWO and ALL_ON lit with DDR_RET dark, SLEEP_BTN does
# nothing because ATF is never entered and the GreenPAK is never told to cut
# the rails, and only a power cycle recovers. SysRq over a serial break still
# answers, which is how the stack above was captured.
#
# With the session restored the VT is owned by systemd-logind, which answers
# the release hand-shake, the switch completes and the suspend proceeds. That
# is also the configuration the stock rz-vlp image uses, and the one suspend
# to RAM is known to work in on this board.
#
# Two things that look like they should fix this instead, and do not:
#
#   * Voting the VT switch away by re-enabling DRM_FBDEV_EMULATION, so that
#     register_framebuffer() calls pm_vt_switch_required(dev, false). It does
#     silence pm_prepare_console(), but only while console suspend is enabled,
#     and fbdev emulation destroys the meta-rzg3l-fast-logo boot logo:
#     drm_fb_helper_hotplug_event() calls drm_fb_helper_set_par() on every
#     connector hotplug event after the initial config, which commits the
#     all-black fbdev framebuffer over the picture. Tried on hardware, the
#     logo survived a few hundred milliseconds. Do not go back to it.
#
#   * Leaving console suspend alone. pm_vt_switch() discards every vote when
#     console suspend is off, so the switch - and with it the deadlock - comes
#     back the moment anyone runs
#     "echo 0 > /sys/module/printk/parameters/console_suspend" or boots with
#     no_console_suspend. Only fixing the VT owner covers that case.
#
# Cost of this revert: weston.service is back to ~2.66 s and the boot time
# regresses by roughly 2.1 s. VII.1 and VII.2 are independent and still apply.
# If that 2.1 s has to come back, the direction is to keep the session but stop
# weston from having to arbitrate VT switches at all - not to re-enable fbdev
# emulation. See README VII.3.
#
# This is a no-op for images that do not install Weston.
do_install:append() {
    unit="${D}${systemd_system_unitdir}/weston.service"
    if [ ! -e "$unit" ]; then
        return 0
    fi

    # Phase 2
    sed -i -e 's/ multi-user\.target//g' "$unit"

    # Assert that the login session this layer relies on is still there. It is
    # what makes systemd-logind, rather than weston itself, the owner of the
    # VT, and suspend to RAM deadlocks in pm_prepare_console() without it.
    for expected in \
            '^User=weston$' \
            '^Group=weston$' \
            '^PAMName=weston-autologin$' ; do
        if ! grep -q "$expected" "$unit"; then
            bbfatal "weston.service no longer has '$expected'; weston would fall back to launcher-direct and take the VT over, which deadlocks suspend to RAM. Re-check ${THISDIR}"
        fi
    done
}
