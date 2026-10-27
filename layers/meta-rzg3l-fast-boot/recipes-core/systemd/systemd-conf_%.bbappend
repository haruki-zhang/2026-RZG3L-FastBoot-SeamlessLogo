# journald tuning for fast boot:
#   Storage=volatile   keep the journal in RAM, never write to eMMC/SD
#   ForwardTo*=no      do not re-emit records to the serial console or kmsg
#   MaxLevel*=warning  drop info-level noise
#
# Note when measuring: MaxLevelStore=warning also drops an application's
# info-level stderr, so temporarily raise it to info before reading
# time-to-first-frame out of the journal.
do_install:append() {
    install -d ${D}${systemd_unitdir}/journald.conf.d
    cat > ${D}${systemd_unitdir}/journald.conf.d/99-fastboot.conf <<'EOF'
[Journal]
Storage=volatile
RuntimeMaxUse=4M

ForwardToConsole=no
ForwardToSyslog=no
ForwardToKMsg=no

MaxLevelStore=warning
MaxLevelConsole=warning
EOF
    chmod 0644 ${D}${systemd_unitdir}/journald.conf.d/99-fastboot.conf
}
