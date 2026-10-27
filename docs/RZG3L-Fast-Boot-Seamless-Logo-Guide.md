# RZ/G3L Fast Boot and Seamless Logo Solutions

## 1. Overview

This package provides two boot-experience solutions for the **RZ/G3L SMARC
Evaluation Board Kit** on top of the RZ/G3L Board Support Package (BSP) v1.0.0.
Both are delivered as Yocto layers that are added to the standard BSP build
environment.

### Objective

The boot sequence shapes the end user's first impression of a product. With
the standard BSP the display stays dark until Linux initialises it, flickers
when the mode is set, and the GUI appears about 22 s after power-on. This PoC
addresses these issues:

- **Immediate visual feedback.** A logo appears within 1 s of power-on and
  stays on screen, without a black screen or flicker, until the product GUI
  or application takes over.
- **Shorter time to GUI (Solution 1).** The boot time until the GUI is ready
  is reduced from about 22 s to about 6.8 s (about 70% shorter) (*).
- **Brand-specific boot animation (Solution 2).** Customers can replace the
  images and change the number of frames, the frame time and the resolution,
  and continue the animation in their own Linux application.
- **Easy adoption.** Both solutions are Yocto layers added to the standard
  BSP, without changes to the BSP itself. They also serve as a reference
  implementation for customer products.

(*) Measured on the RZ/G3L SMARC EVK, eMMC boot, until the GUI (Weston)
start-up is complete.

### Solutions at a Glance

| | **Solution 1: Fast Boot + Seamless Still Logo** | **Solution 2: Seamless Logo Sequence** |
|---|---|---|
| Components | `meta-rzg3l-fast-boot` + `meta-rzg3l-seamless-logo-still` | `meta-rzg3l-seamless-logo-sequence` + `rzg3l-seamless-logo-sequence-app` |
| Boot time reduction | Yes | No |
| Logo during boot | One still image, from U-Boot until Weston | A frame sequence in U-Boot, a second image sequence in Linux, last image held until Weston |
| Customization | Limited (fixed image file, compiled-in resolution) | Images, number of frames, frame time and resolution are configurable |
| Deployment | Yocto build only | Yocto build, plus manual installation of the sample application |
| Boot medium | Rootfs on eMMC | microSD or eMMC (detected at run time) |

In both solutions U-Boot brings up the MIPI DSI → ADV7535 → HDMI display path a
few hundred milliseconds after reset, and the Linux kernel inherits the running
display instead of re-initialising it. The picture stays on screen through the
whole boot, with no black screen and no HDMI re-sync.

> **Notice:**
> This guide assumes that the standard RZ/G3L BSP build environment has been
> prepared by following `r01us0858ej0100-rzg3l(Linux Start-up_Guide_RZG3L)_rc1.pdf`
> (hereinafter "Start-up Guide"). It describes only the steps that differ from
> the Start-up Guide.

---

## 2. Environment

### Hardware Environment

| **Component** | **Description** |
|---|---|
| **Board** | RZ/G3L SMARC Evaluation Board Kit (`smarc-rzg3l`) |
| **Display** | HDMI monitor supporting 1920x1080@60 (and 1280x720@60 for Solution 1) |
| **Power, serial console, microSD card** | As described in the Start-up Guide, chapter 4.1 |
| **Host Machine** | Linux host PC (Ubuntu 22.04) |

### Software Environment

| **Software** | **Version / Description** |
|---|---|
| **RZ/G3L BSP** | v1.0.0 (Yocto scarthgap, U-Boot 2024.07, Linux 6.12.46-cip8) |
| **Graphics package** | `meta-rz-features/meta-rz-graphics` (required for `core-image-weston`) |
| **Reference Guide** | `r01us0858ej0100-rzg3l(Linux Start-up_Guide_RZG3L)_rc1.pdf` |
| **Target Machine** | `smarc-rzg3l` |
| **Image** | `core-image-weston` |

### Common Preparation

For both solutions, first prepare the default BSP build environment by
following the Start-up Guide, chapter 2.2, steps (1) to (5). Enable the
Graphics package in steps (3) and (5).

The resulting workspace contains at least `build`, `poky`, `meta-openembedded`,
`meta-arm`, `meta-renesas` and `meta-rz-features`. Copy the layers of the
selected solution from this package into the top directory of that workspace.

---

## 3. Solution 1: Fast Boot + Seamless Still Logo

### 3.1 Key Modifications

- **`meta-rzg3l-fast-boot`**: shortens the boot.
  - **U-Boot**: no autoboot delay, no environment reset at every boot, and a
    quiet kernel command line for eMMC boot.
  - **Kernel**: unused peripherals (Ethernet, USB, PCIe, CAN, camera, audio,
    extra UARTs, RTC) are disabled in the device tree, and the matching
    kernel subsystems are removed.
  - **Distro `rz-vlp-fast`**: unused features and package groups removed, and
    systemd start-up optimised.
- **`meta-rzg3l-seamless-logo-still`**: shows a still logo image from U-Boot
  until Weston starts.
  - **U-Boot**: a display driver brings up the HDMI output and shows the image
    (1280x720 by default).
  - **Kernel**: the display drivers inherit the running display, and the
    framebuffer console and fbdev emulation are disabled.

The two layers are independent and can also be used separately.

### 3.2 Implementation Steps

#### Step 1. Add the Layers

Copy `layers/meta-rzg3l-fast-boot` and `layers/meta-rzg3l-seamless-logo-still`
into the top directory of the workspace, then add them in this order:

```sh
# pwd should be the build directory of the workspace

bitbake-layers add-layer ../meta-rzg3l-fast-boot
bitbake-layers add-layer ../meta-rzg3l-seamless-logo-still
```

> **Note:** Add `meta-rzg3l-fast-boot` first. Both layers patch the same
> device tree file, and the patches are applied in `bblayers.conf` order.

#### Step 2. Configure `local.conf`

Add the following line to `build/conf/local.conf`:

```sh
DISTRO = "rz-vlp-fast"
```

#### Step 3. Build the Image

```sh
MACHINE=smarc-rzg3l bitbake core-image-weston
```

The output files are generated in `build/tmp/deploy/images/smarc-rzg3l/`.

#### Step 4. Write the Board for eMMC Boot

The logo image is loaded from partition 2 of the eMMC, so the Solution 1 image
must be written to eMMC. It is written with `bmaptool` from a separate
"writer" Linux system, booted from a microSD card in QSPI boot mode.

> **Note:** Only the writer image must contain `bmaptool`. The Solution 1
> image that is written to eMMC does not need it.

1. **Build the writer image.** Use a standard BSP build without the layers of
   this package. Use a separate build directory, so that the Solution 1
   configuration is not affected:

   ```sh
   # pwd should be the top directory of the workspace

   TEMPLATECONF=$PWD/meta-renesas/meta-rz-distro/conf/templates/vlp-v5-conf/ \
       source poky/oe-init-build-env build-writer
   bitbake-layers add-layer ../meta-rz-features/meta-rz-graphics
   ```

   Add the following line to `build-writer/conf/local.conf`, then build:

   ```sh
   IMAGE_INSTALL:append = " bmaptool"
   ```

   ```sh
   MACHINE=smarc-rzg3l bitbake core-image-weston
   ```

2. **Prepare the writer microSD card and bootloader.** Write the WIC image of
   the writer build to a microSD card (Start-up Guide chapter 3). Write
   `bl2_bp_spi-smarc-rzg3l.srec` and `fip-smarc-rzg3l.srec` of the writer
   build to QSPI (Start-up Guide 4.3–4.5).

3. **Copy the Solution 1 image to the writer microSD card.** Copy the WIC
   image and its block map (not the `.tar.gz` files named in Start-up Guide
   8.2.2) to the second partition:

   ```sh
   # pwd should be the build directory of Solution 1
   # replace sdX with the actual microSD card device

   sudo mount /dev/sdX2 /mnt
   sudo cp tmp/deploy/images/smarc-rzg3l/core-image-weston-smarc-rzg3l.rootfs.wic.gz /mnt/root/
   sudo cp tmp/deploy/images/smarc-rzg3l/core-image-weston-smarc-rzg3l.rootfs.wic.bmap /mnt/root/
   sudo umount /mnt
   ```

4. **Write the Solution 1 bootloader to eMMC** (Start-up Guide 4.3 and
   8.2.1). Use these files of the Solution 1 build:

   ```text
   Flash_Writer_SCIF_RZG3L_SMARC_LPDDR4.mot
   bl2_bp_mmc-smarc-rzg3l.srec      (named bl2_bp_emmc-smarc-rzg3l.srec in the Start-up Guide)
   fip-smarc-rzg3l.srec
   ```

5. **Write the Solution 1 image to eMMC.** Insert the microSD card into the
   carrier board slot, boot Linux in QSPI boot mode (Start-up Guide 4.5 and
   5.1) and log in as `root`. Then run:

   ```sh
   bmaptool copy /root/core-image-weston-smarc-rzg3l.rootfs.wic.gz /dev/mmcblk0
   ```

   > **Note:** The eMMC and the microSD slot of the SMARC module are
   > exclusive. Keep the "SYS" DIP switch set to eMMC (Start-up Guide 4.1.3).

6. **Boot from eMMC.** Set the board to eMMC boot mode (Start-up Guide 8.2.3,
   Table 15) and remove the microSD card from the carrier board. U-Boot boots
   Linux from the microSD card whenever one is inserted.

7. **Reset the U-Boot environment** (Start-up Guide 8.2.4). The autoboot delay
   is now 0: to reach the U-Boot prompt, keep pressing a key on the serial
   console while you press the RESET button. Then run:

   ```sh
   => env default -a
   => saveenv
   => reset
   ```

> **Note:** The U-Boot side of both layers is in `bl2`/`fip`, not in the WIC
> image. Repeat item 4 after any change to the U-Boot patches.

### 3.3 Notes

- **Disabled peripherals.** Ethernet, USB, PCIe, CAN, camera, audio,
  i2c0/i2c1/i2c3, extra UARTs and RTC are disabled. To use any of them,
  re-enable the device-tree node and the matching kernel and userspace
  features (`meta-rzg3l-fast-boot/README` section V).
- **Kernel messages on the serial console.** For eMMC boot the kernel command
  line contains `quiet`. Kernel messages are still available with `dmesg` and
  `journalctl`.
- **Changing the logo image or resolution.** The image is a gzip-compressed
  raw frame buffer, and the resolution is compiled into U-Boot. See
  `meta-rzg3l-seamless-logo-still/README` section V. For easy customization,
  use Solution 2.

---

## 4. Solution 2: Seamless Logo Sequence

### 4.1 Key Components

- **`meta-rzg3l-seamless-logo-sequence`** (Yocto layer)
  - **U-Boot**: brings up the HDMI output, plays a sequence of frames (default
    `l1.bmp`–`l4.bmp`, 1 s each) and holds the last one.
  - **Kernel**: inherits the running display. The last U-Boot frame stays on
    screen until the first program in Linux draws.
  - **Frames**: kept as editable BMP files and converted at build time.
- **`rzg3l-seamless-logo-sequence-app`** (sample application)
  - Starts early in the Linux boot and shows a second image sequence (default
    `w1.bmp`–`w7.bmp`, 1 s each).
  - Keeps the last image on screen until Weston replaces it.
  - Installed and enabled manually by the user.

The layer and the sample application do not depend on each other: the layer
works without the application, and the application also runs on a stock BSP
image.

Default sequence on the display:

```text
reset → l1 → l2 → l3 → l4 (held during kernel boot) → w1 → … → w7 (held) → Weston desktop
        └──────── U-Boot ────────┘                    └─ sample app ─┘
```

### 4.2 Implementation Steps

#### Step 1. Add the Layer

Copy `layers/meta-rzg3l-seamless-logo-sequence` into the top directory of the
workspace, then add it:

```sh
# pwd should be the build directory of the workspace

bitbake-layers add-layer ../meta-rzg3l-seamless-logo-sequence
```

> **Note:** `meta-rzg3l-seamless-logo-sequence` cannot be combined with
> `meta-rzg3l-seamless-logo-still`. The build stops with an error if both are
> present.

#### Step 2. Build the Image

```sh
MACHINE=smarc-rzg3l bitbake core-image-weston
```

No `DISTRO` change is required. To customize the frames, frame time or
resolution, set the variables in chapter 5 in `local.conf` before building.

#### Step 3. Write the Board

Any boot mode of the Start-up Guide can be used. The frames are loaded from
partition 2 of the medium the board boots from.

| Boot mode | Procedure (Start-up Guide) | Note |
|---|---|---|
| **QSPI boot** (default) | Chapter 3 (microSD card), 4.3–4.5 (bootloader), 5 (boot) | Writing the WIC image does not update U-Boot. Write `bl2_bp_spi-smarc-rzg3l.srec` and `fip-smarc-rzg3l.srec` with Flash Writer. |
| **eSD boot** | 8.3 | The WIC image contains `bl2` and `fip`. Writing the WIC to the microSD card also updates U-Boot. |
| **eMMC boot** | 8.2 | Same procedure as Solution 1, Step 4, with the Solution 2 image. |

Without the sample application, the last U-Boot frame (`l4`) stays on screen
until the Weston desktop appears.

#### Step 4. Install the Sample Application

The package contains a prebuilt binary
(`apps/rzg3l-seamless-logo-sequence-app/prebuilt/logo_sample_app`). To build it
from source, see `apps/rzg3l-seamless-logo-sequence-app/README.md`.

Copy the files to the second partition of the boot medium. The example below
uses the microSD card on the host PC (see also Start-up Guide 7.1.2, Step 4):

```sh
# pwd should be apps/rzg3l-seamless-logo-sequence-app of this package
# replace sdX with the actual microSD card device

sudo mount /dev/sdX2 /mnt
sudo mkdir -p /mnt/home/root
sudo cp prebuilt/logo_sample_app run-app.sh images/w*.bmp /mnt/home/root/
sudo cp sample-app.service /mnt/lib/systemd/system/
sudo umount /mnt
```

After copying, the second partition contains the following files:

```plaintext
/home/root/
├── logo_sample_app          # application (executable)
├── run-app.sh               # start script (executable)
├── w1.bmp
├── w2.bmp
├── w3.bmp
├── w4.bmp
├── w5.bmp
├── w6.bmp
└── w7.bmp

/lib/systemd/system/
└── sample-app.service
```

Boot the board, log in as `root` and enable the service once:

```sh
systemctl enable sample-app.service
reboot
```

The application now runs at every boot. To stop using it, run
`systemctl disable sample-app.service`.

> **Note:** The image runs an SSH server and `root` has no password, so the
> files can also be copied with `scp`. See
> `apps/rzg3l-seamless-logo-sequence-app/README.md`.

---

## 5. Customizing Solution 2

### 5.1 Overview

| What to change | Where | Rebuild | Write to the board |
|---|---|---|---|
| U-Boot frames (images, number) | `RZG3L_LOGO_SEQUENCE_FRAMES` in `local.conf` | Image | WIC |
| U-Boot frame time | `RZG3L_LOGO_SEQUENCE_RATE_MS` in `local.conf` | Image | `bl2`/`fip` and WIC |
| U-Boot frame time, for trials | `logo_rate_ms` in the U-Boot environment | None | None |
| Resolution | `RZG3L_LOGO_SEQUENCE_RESOLUTION` in `local.conf`, plus new images | Image | `bl2`/`fip` and WIC |
| Linux images and interval | `run-app.sh` on the board | None | None |

For QSPI and eMMC boot, `bl2`/`fip` is written with Flash Writer. For eSD
boot, writing the WIC image also writes `bl2`/`fip` (see 4.2, Step 3).

### 5.2 Replacing the U-Boot Frames

**Image requirements**

- Uncompressed BMP, 24 or 32 bpp.
- Exactly the output resolution (default 1920x1080). The build checks this.
- Maximum 14 frames at 1920x1080, 31 frames at 1280x720.

**Setting the frames**

Place the BMP files in
`meta-rzg3l-seamless-logo-sequence/recipes-graphics/rzg3l-seamless-logo-sequence-frames/files/`,
then list them in playback order in `build/conf/local.conf`. The number of
frames is the number of entries:

```sh
# build/conf/local.conf
RZG3L_LOGO_SEQUENCE_FRAMES = "frame1.bmp frame2.bmp frame3.bmp"
```

An absolute path on the build host can also be used instead of a file name.

**Applying the change**

Rebuild the image and write the new WIC image. U-Boot does not change, so
`bl2`/`fip` does not need to be written again.

### 5.3 Changing the U-Boot Frame Time

Set the time each frame is held, in milliseconds (default 1000), in
`build/conf/local.conf`:

```sh
# build/conf/local.conf
RZG3L_LOGO_SEQUENCE_RATE_MS = "500"
```

The value is compiled into U-Boot and rounded down to whole display frames
(16.7 ms at 60 Hz). Rebuild, then write `bl2`/`fip` and the WIC image.

To try values without a rebuild, set U-Boot environment variables:

```sh
=> setenv logo_rate_ms 500      # frame time in ms
=> setenv logo_frames 3         # play at most this many frames
=> saveenv
=> reset
```

To return to the compiled-in values, delete the variables
(`setenv logo_rate_ms`, `setenv logo_frames`) and run `saveenv`.

> **Note:** The sequence plays in parallel with the boot and does not delay
> it.
> If the frames take longer than the boot to play, Linux takes over before
> the last frame is reached.

### 5.4 Changing the Resolution

1920x1080 (default) and 1280x720 are supported. Set the resolution and the
frames of that size in `build/conf/local.conf`:

```sh
# build/conf/local.conf
RZG3L_LOGO_SEQUENCE_RESOLUTION = "1280x720"
RZG3L_LOGO_SEQUENCE_FRAMES = "frame1_720p.bmp frame2_720p.bmp"
```

- All U-Boot frames must have the new size.
- The kernel needs no change. U-Boot passes the mode to the kernel at boot,
  and the HDMI connector then offers only this mode. Prepare the
  sample-application images at the same size (5.5).
- Rebuild, then write `bl2`/`fip` and the WIC image.

Other resolutions need a new timing table in the U-Boot display driver. See
`meta-rzg3l-seamless-logo-sequence/README` section IV. The maximum is
1920x1080@60 (ADV7535 limit).

### 5.5 Changing the Linux Images and Interval

Edit `/home/root/run-app.sh` on the board:

```sh
IMAGES="
/home/root/w1.bmp
/home/root/w2.bmp
/home/root/w3.bmp
"

INTERVAL_MS=1000
```

- Any number of images, shown in the order listed.
- Uncompressed BMP, 24 or 32 bpp. Use the resolution U-Boot drives (default
  1920x1080). An image of another size is centred, or scaled with
  `--fit=scale`.
- Copy new image files to the board and list them in `IMAGES`.
- The change takes effect at the next boot. No rebuild is required.

Other options can be added to the `exec` line of `run-app.sh`. Run
`logo_sample_app --help` or see
`apps/rzg3l-seamless-logo-sequence-app/README.md`.

> **Important:** Weston starts only after the last image has been shown. With
> N images and an interval of T ms, Weston starts about N × T ms later than
> without the application (7 s with the default images). Choose the number of
> images and the interval with this in mind.

---

## 6. Known Limitations

**Both solutions**

- The HDMI connector is fixed to the mode U-Boot drives: it is always reported
  as connected, EDID is not read, and hot-plug is not reported. A monitor that
  does not support the mode shows no picture.
- There is no framebuffer device (`/dev/fb0`) and no kernel console on HDMI.
  The serial console is not affected.
- The memory region `0x58000000`–`0x5fffffff` (128 MiB) stays reserved for the
  lifetime of the system.
- The BSP U-Boot environment has `loadaddr=0x58000000`, which is the logo frame
  buffer. Always give an explicit address to manual `ext4load` or `tftp`
  commands at the U-Boot prompt.
- Some monitors need time to lock onto the HDMI signal, so the first frame may
  not be visible.

**Solution 1**

- The rootfs must be on eMMC (the logo image is loaded from eMMC partition 2).
- The logo resolution is 1280x720 by default and is compiled into U-Boot.
- Disabled peripherals: see 3.3.

**Solution 2**

- The frames are loaded from partition 2 (ext4) of the MMC device the board
  boots from. Other boot media show a black frame.
- With the sample application, Weston starts after the image sequence (see 5.5).
- `meta-rzg3l-seamless-logo-sequence` combined with `meta-rzg3l-fast-boot` is
  expected to work but has not been tested.

---

## 7. Deliverables

```plaintext
rzg3l-fast-boot-seamless-logo/
├── README.md
├── docs/
│   ├── RZG3L-Fast-Boot-Seamless-Logo-Guide.md     # this guide (Markdown)
│   └── RZG3L-Fast-Boot-Seamless-Logo-Guide.pdf    # this guide (PDF)
│
├── layers/
│   ├── meta-rzg3l-fast-boot/                      # fast boot (Solution 1)
│   │   └── docs/fast-boot-method.md               # measurement and optimisation method
│   ├── meta-rzg3l-seamless-logo-still/            # still logo (Solution 1)
│   └── meta-rzg3l-seamless-logo-sequence/         # logo sequence (Solution 2)
│
├── apps/
│   └── rzg3l-seamless-logo-sequence-app/          # sample application (Solution 2)
│       ├── README.md
│       ├── main.c  Makefile  run-app.sh  sample-app.service
│       ├── prebuilt/logo_sample_app
│       └── images/w1.bmp … w7.bmp
│
├── image/                                         # prebuilt images (placeholder)
│   └── README.md
├── reference/                                     # RZ/G3L Linux Start-up Guide
└── tools/md2pdf.py                                # renders this guide as PDF
```

Each layer contains a `README` with the full configuration reference.

### Name Changes from v1.0

| v1.0 | Now |
|---|---|
| Solution 1: Fast Boot & Fast Logo | Solution 1: Fast Boot + Seamless Still Logo |
| Solution 2: Fast Logo Intro | Solution 2: Seamless Logo Sequence |
| `meta-rzg3l-fast-boot-base` | `meta-rzg3l-fast-boot` |
| `meta-rzg3l-fast-logo` | `meta-rzg3l-seamless-logo-still` |
| `meta-rzg3l-fast-logo-intro` | `meta-rzg3l-seamless-logo-sequence` |
| `rzg3l-fast-logo-sample-app` | `rzg3l-seamless-logo-sequence-app` |
| recipe `rzg3l-boot-logo` | `rzg3l-seamless-logo-still-image` |
| recipe `rzg3l-fastlogo-frames` | `rzg3l-seamless-logo-sequence-frames` |
| `RZG3L_BOOT_LOGO_PACKAGE` | `RZG3L_STILL_LOGO_PACKAGE` |
| `RZG3L_FASTLOGO_*` | `RZG3L_LOGO_SEQUENCE_*` |

Behaviour on the board is unchanged. U-Boot messages keep their `fast-logo:`
prefix, and the logo files in `/boot` keep their names.
