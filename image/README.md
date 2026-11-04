# Prebuilt images

Prebuilt `core-image-weston` images for `MACHINE = "smarc-rzg3l"`, one per
solution, built from the layers in this package:

```plaintext
image/
├── fast-boot-seamless-logo-still/   # Solution 1: meta-rzg3l-fast-boot + meta-rzg3l-seamless-logo-still
│   ├── core-image-weston-smarc-rzg3l.rootfs.wic.gz
│   └── core-image-weston-smarc-rzg3l.rootfs.wic.bmap
│
├── seamless-logo-sequence/          # Solution 2: meta-rzg3l-seamless-logo-sequence
│   ├── core-image-weston-smarc-rzg3l.rootfs.wic.gz
│   └── core-image-weston-smarc-rzg3l.rootfs.wic.bmap
│
└── seamless-logo-cm33-anim/         # Solution 3: meta-rzg3l-seamless-logo-still + meta-rzg3l-seamless-logo-cm33-anim
    │                                #             (+ meta-rz-multi-os, USE_OPENAMP = "0")
    ├── core-image-weston-smarc-rzg3l.rootfs.wic.gz
    └── core-image-weston-smarc-rzg3l.rootfs.wic.bmap
```

Only the WIC image and its block map are provided. For QSPI and eMMC boot,
the bootloader (`bl2`, `fip`) is written separately with Flash Writer, and
neither is included here: build them from the same layers (guide, Solution 1
Step 3, Solution 2 Step 2 or Solution 3 Step 3) and write them as the guide
describes. The logo
is shown by U-Boot, so with a stock `bl2`/`fip` the board boots these images
but shows no logo. For eSD boot the WIC image already contains `bl2` and
`fip`; the Solution 3 image also contains the CM33 firmware, so it is
complete for eSD boot.

| Image | Boot medium | How to write (guide) |
|---|---|---|
| `fast-boot-seamless-logo-still` | eMMC only | Solution 1, Step 4 |
| `seamless-logo-sequence` | microSD or eMMC | Solution 2, Step 3 |
| `seamless-logo-cm33-anim` | eSD (microSD card in the SMARC module slot) | Solution 3, Step 4 |

To write a WIC image to a microSD card on the host PC:

```sh
# replace sdX with the actual microSD card device
sudo bmaptool copy core-image-weston-smarc-rzg3l.rootfs.wic.gz /dev/sdX
```

The sample application of Solution 2 is not in the image. Install it as
described in the guide, Solution 2 Step 4.
