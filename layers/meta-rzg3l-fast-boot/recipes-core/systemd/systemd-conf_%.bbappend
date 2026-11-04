# Writing the journal to eMMC/SD and copying it to the serial console both
# slow the boot. Keep it in RAM and store warnings only.
#
# MaxLevelStore=warning also drops info-level application output. Raise it
# to info when a measurement reads timestamps from the journal.
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
