# Prebuilt images

> **Placeholder.** Prebuilt images are not included in this release yet.

When provided, this directory will contain the following files for each
solution. All files are built for `MACHINE = "smarc-rzg3l"`.

```plaintext
image/
├── fast-boot-seamless-logo-still/   # meta-rzg3l-fast-boot + meta-rzg3l-seamless-logo-still (eMMC boot)
│   ├── core-image-weston-smarc-rzg3l.rootfs.wic.gz
│   ├── core-image-weston-smarc-rzg3l.rootfs.wic.bmap
│   ├── bl2_bp_mmc-smarc-rzg3l.srec
│   ├── fip-smarc-rzg3l.srec
│   └── Flash_Writer_SCIF_RZG3L_SMARC_LPDDR4.mot
│
└── seamless-logo-sequence/          # meta-rzg3l-seamless-logo-sequence
    ├── core-image-weston-smarc-rzg3l.rootfs.wic.gz
    ├── core-image-weston-smarc-rzg3l.rootfs.wic.bmap
    ├── bl2_bp_spi-smarc-rzg3l.srec
    ├── fip-smarc-rzg3l.srec
    └── Flash_Writer_SCIF_RZG3L_SMARC_LPDDR4.mot
```

U-Boot (`bl2`/`fip`) is written with Flash Writer, separately from the WIC
image. See the main guide in `docs/`.
