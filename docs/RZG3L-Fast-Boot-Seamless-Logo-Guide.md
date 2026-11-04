# RZ/G3L Fast Boot and Seamless Logo Solutions

## 1. Overview

This package provides three boot-experience solutions for the **RZ/G3L SMARC
Evaluation Board Kit**, based on the RZ/G3L BSP v1.0.0. Each solution is a set
of Yocto layers added to the standard BSP build.

### Objective

With the standard BSP, the display stays dark until Linux starts it, and
Weston appears about 22 s after power-on. The solutions provide:

- **A logo within 1 s of power-on.** It stays on screen until Weston, with no
  black screen and no flicker.
- **Shorter boot (Solution 1).** Time to Weston drops from about 22 s to about
  6.8 s (eMMC boot).
- **A custom logo sequence (Solution 2).** Images, frame count, frame time and
  resolution are configurable. A Linux application can continue the sequence.
- **An animation without CPU load (Solution 3).** The Cortex-M33 plays an
  animation over the still logo: by default a spinner with a simulated
  percentage. The Cortex-A55 boots Linux undisturbed.
- **No changes to the BSP.** All solutions are added as Yocto layers.

### Solutions at a Glance

| | **Solution 1: Fast Boot + Seamless Still Logo** | **Solution 2: Seamless Logo Sequence** | **Solution 3: Seamless Logo CM33 Animation** |
|---|---|---|---|
| Components | `meta-rzg3l-fast-boot` + `meta-rzg3l-seamless-logo-still` | `meta-rzg3l-seamless-logo-sequence` + `rzg3l-seamless-logo-sequence-app` | `meta-rzg3l-seamless-logo-cm33-anim` + `meta-rzg3l-seamless-logo-still` + RZ/G3L Multi-OS package |
| Shorter boot | Yes | No | No (can be combined with `meta-rzg3l-fast-boot`) |
| Logo during boot | One still image | A frame sequence in U-Boot, then an image sequence in Linux | The still image with an animation over it (default: a spinner with a percentage) |
| Customization | Limited | Images, frame count, frame time, resolution | Time from 1 % to 99 %, own frames, size, position, frame time |
| Deployment | Yocto build | Yocto build, plus manual installation of the sample application | Yocto build |
| Boot medium | eMMC | Any | Any, eSD used as an example |

In all solutions, U-Boot starts the HDMI output shortly after power-on. The
kernel takes over the running display instead of resetting it.

> **Notice:** This guide assumes the standard BSP build environment of
> `r01us0858ej0100-rzg3l(Linux Start-up_Guide_RZG3L)_rc1.pdf` (the "Start-up
> Guide"). It describes only the additional steps.

---

## 2. Environment

### Hardware Environment

| **Component** | **Description** |
|---|---|
| **Board** | RZ/G3L SMARC Evaluation Board Kit (`smarc-rzg3l`) |
| **Display** | HDMI monitor with 1920x1080@60 (and 1280x720@60 for Solutions 1 and 3) |
| **Power, serial console, microSD card** | Start-up Guide, 4.1 |
| **Host Machine** | Linux PC (Ubuntu 22.04) |

### Software Environment

| **Software** | **Version / Description** |
|---|---|
| **RZ/G3L BSP** | v1.0.0 (Yocto scarthgap, U-Boot 2024.07, Linux 6.12.46-cip8) |
| **Graphics package** | `meta-rz-features/meta-rz-graphics` (required for `core-image-weston`) |
| **Multi-OS package** | `meta-rz-features/meta-rz-multi-os` v4.2.0 for RZ/G3L (Solution 3 only) |
| **Reference Guide** | `r01us0858ej0100-rzg3l(Linux Start-up_Guide_RZG3L)_rc1.pdf` |
| **Target Machine** | `smarc-rzg3l` |
| **Image** | `core-image-weston` |

### Common Preparation

1. Prepare the BSP build environment: Start-up Guide 2.2, steps (1) to (5),
   with the Graphics package.
2. Copy the layers of the selected solution into the top directory of the
   workspace.

Solution 3 also needs the Multi-OS package (5.2, Step 1).

---

## 3. Solution 1: Fast Boot + Seamless Still Logo

### 3.1 Key Modifications

- **`meta-rzg3l-fast-boot`**: shortens the boot.
  - **U-Boot**: no boot delay, no environment reset at every boot, quiet
    kernel command line for eMMC boot.
  - **Kernel**: unused peripherals are disabled in the device tree, and their
    drivers are removed.
  - **Distro `rz-vlp-fast`**: unused features and package groups removed,
    systemd start-up optimised.
- **`meta-rzg3l-seamless-logo-still`**: shows a still logo (the Renesas
  wordmark) from U-Boot until Weston.
  - **U-Boot**: a display driver starts the HDMI output and shows the logo
    (1280x720).
  - **Kernel**: the display drivers take over the running display.

The two layers can also be used separately.

### 3.2 Implementation Steps

#### Step 1. Add the Layers

```sh
# pwd should be the build directory of the workspace

bitbake-layers add-layer ../meta-rzg3l-fast-boot
bitbake-layers add-layer ../meta-rzg3l-seamless-logo-still
```

> **Note:** Add `meta-rzg3l-fast-boot` first. Both layers patch the same
> device tree file, in `bblayers.conf` order.

#### Step 2. Configure `local.conf`

Add to `build/conf/local.conf`:

```sh
DISTRO = "rz-vlp-fast"
```

#### Step 3. Build the Image

```sh
MACHINE=smarc-rzg3l bitbake core-image-weston
```

The output is in `build/tmp/deploy/images/smarc-rzg3l/`.

#### Step 4. Write the Board for eMMC Boot

The logo is loaded from eMMC partition 2, so the image must be on eMMC. It is
written with `bmaptool` from a "writer" Linux on a microSD card, booted in
QSPI boot mode.

1. **Build the writer image.** Use a standard BSP build in a separate build
   directory:

   ```sh
   # pwd should be the top directory of the workspace

   TEMPLATECONF=$PWD/meta-renesas/meta-rz-distro/conf/templates/vlp-v5-conf/ \
       source poky/oe-init-build-env build-writer
   bitbake-layers add-layer ../meta-rz-features/meta-rz-graphics
   ```

   Add to `build-writer/conf/local.conf`, then build:

   ```sh
   IMAGE_INSTALL:append = " bmaptool"
   ```

   ```sh
   MACHINE=smarc-rzg3l bitbake core-image-weston
   ```

2. **Prepare the writer.** Write the writer WIC image to a microSD card
   (Start-up Guide 3). Write its `bl2_bp_spi-smarc-rzg3l.srec` and
   `fip-smarc-rzg3l.srec` to QSPI (Start-up Guide 4.3–4.5).

3. **Copy the Solution 1 image to the writer microSD card:**

   ```sh
   # pwd should be the build directory of Solution 1
   # replace sdX with the actual microSD card device

   sudo mount /dev/sdX2 /mnt
   sudo cp tmp/deploy/images/smarc-rzg3l/core-image-weston-smarc-rzg3l.rootfs.wic.gz /mnt/root/
   sudo cp tmp/deploy/images/smarc-rzg3l/core-image-weston-smarc-rzg3l.rootfs.wic.bmap /mnt/root/
   sudo umount /mnt
   ```

4. **Write the Solution 1 bootloader to eMMC** (Start-up Guide 4.3 and
   8.2.1), with these files of the Solution 1 build:

   ```text
   Flash_Writer_SCIF_RZG3L_SMARC_LPDDR4.mot
   bl2_bp_mmc-smarc-rzg3l.srec      (bl2_bp_emmc-smarc-rzg3l.srec in the Start-up Guide)
   fip-smarc-rzg3l.srec
   ```

5. **Write the Solution 1 image to eMMC.** Insert the microSD card into the
   carrier board slot. Boot in QSPI boot mode (Start-up Guide 4.5 and 5.1),
   log in as `root` and run:

   ```sh
   bmaptool copy /root/core-image-weston-smarc-rzg3l.rootfs.wic.gz /dev/mmcblk0
   ```

   > **Note:** Keep the "SYS" DIP switch set to eMMC (Start-up Guide 4.1.3).

6. **Boot from eMMC.** Set eMMC boot mode (Start-up Guide 8.2.3, Table 15)
   and remove the microSD card. U-Boot boots from the microSD card whenever
   one is inserted.

7. **Reset the U-Boot environment** (Start-up Guide 8.2.4). The boot delay is
   0, so keep pressing a key on the serial console while pressing RESET. Then
   run:

   ```sh
   => env default -a
   => saveenv
   => reset
   ```

> **Note:** U-Boot is in `bl2`/`fip`, not in the WIC image. After a change to
> U-Boot, repeat item 4.

### 3.3 Notes

- **Disabled peripherals:** Ethernet, USB, PCIe, CAN, camera, audio,
  i2c0/i2c1/i2c3, extra UARTs and RTC. To use one, re-enable its device tree
  node and the matching kernel and userspace features.
- **Kernel messages:** not shown on the serial console for eMMC boot
  (`quiet`). Use `dmesg` or `journalctl`.
- **Changing the logo or the resolution:** see
  `meta-rzg3l-seamless-logo-still/README`, section III. For easy
  customization, use Solution 2.

---

## 4. Solution 2: Seamless Logo Sequence

### 4.1 Key Components

- **`meta-rzg3l-seamless-logo-sequence`** (Yocto layer)
  - **U-Boot**: starts the HDMI output, plays a frame sequence (default
    `l1.bmp`–`l4.bmp`, 1 s each) and holds the last frame.
  - **Kernel**: takes over the running display. The last frame stays on
    screen until the first program in Linux draws.
  - **Frames**: BMP files, converted at build time.
- **`rzg3l-seamless-logo-sequence-app`** (sample application)
  - Starts early in the Linux boot and shows a second image sequence (default
    `w1.bmp`–`w7.bmp`, 1 s each).
  - Holds the last image until Weston replaces it.
  - Installed manually.

The layer and the application do not depend on each other.

Default sequence:

```text
reset → l1 → l2 → l3 → l4 (held during kernel boot) → w1 → … → w7 (held) → Weston desktop
        └──────── U-Boot ────────┘                    └─ sample app ─┘
```

### 4.2 Implementation Steps

#### Step 1. Add the Layer

```sh
# pwd should be the build directory of the workspace

bitbake-layers add-layer ../meta-rzg3l-seamless-logo-sequence
```

> **Note:** Cannot be combined with `meta-rzg3l-seamless-logo-still`. The
> build stops with an error.

#### Step 2. Build the Image

```sh
MACHINE=smarc-rzg3l bitbake core-image-weston
```

To customize the sequence, set the variables of 4.3 in `local.conf` first.

#### Step 3. Write the Board

The frames are loaded from partition 2 of the boot medium.

| Boot mode | Procedure (Start-up Guide) | Note |
|---|---|---|
| **QSPI boot** (default) | 3 (microSD card), 4.3–4.5 (bootloader), 5 (boot) | The WIC image does not contain U-Boot. Write `bl2_bp_spi-smarc-rzg3l.srec` and `fip-smarc-rzg3l.srec` with Flash Writer. |
| **eSD boot** | 8.3 | The WIC image contains `bl2` and `fip`. |
| **eMMC boot** | 8.2 | As Solution 1, Step 4, with the Solution 2 image. |

Without the sample application, `l4` stays on screen until Weston.

#### Step 4. Install the Sample Application

Use the prebuilt binary `apps/rzg3l-seamless-logo-sequence-app/prebuilt/logo_sample_app`.
To build it, see `apps/rzg3l-seamless-logo-sequence-app/README.md`.

Copy the files to partition 2 of the microSD card on the host PC:

```sh
# pwd should be apps/rzg3l-seamless-logo-sequence-app of this package
# replace sdX with the actual microSD card device

sudo mount /dev/sdX2 /mnt
sudo mkdir -p /mnt/home/root
sudo cp prebuilt/logo_sample_app run-app.sh images/w*.bmp /mnt/home/root/
sudo cp sample-app.service /mnt/lib/systemd/system/
sudo umount /mnt
```

Boot the board, log in as `root` and enable the service:

```sh
systemctl enable sample-app.service
reboot
```

To stop using it: `systemctl disable sample-app.service`.

> **Note:** The files can also be copied with `scp`. `root` has no password.

### 4.3 Customization

| What to change | Where | Write to the board |
|---|---|---|
| U-Boot frames | `RZG3L_LOGO_SEQUENCE_FRAMES` in `local.conf` | WIC |
| U-Boot frame time | `RZG3L_LOGO_SEQUENCE_RATE_MS` in `local.conf` | `bl2`/`fip` and WIC |
| U-Boot frame time, for trials | `logo_rate_ms` in the U-Boot environment | None |
| Resolution | `RZG3L_LOGO_SEQUENCE_RESOLUTION` in `local.conf`, plus new frames | `bl2`/`fip` and WIC |
| Linux images and interval | `run-app.sh` on the board | None |

Changes in `local.conf` need a rebuild. With eSD boot, the WIC image also
contains `bl2`/`fip`.

#### U-Boot Frames

- Uncompressed BMP, 24 or 32 bpp.
- Exactly the output resolution (default 1920x1080). The build checks this.
- At most 14 frames at 1920x1080, 31 at 1280x720.

Put the files in
`meta-rzg3l-seamless-logo-sequence/recipes-graphics/rzg3l-seamless-logo-sequence-frames/files/`
and list them in playback order. Absolute paths on the build host also work.

```sh
# build/conf/local.conf
RZG3L_LOGO_SEQUENCE_FRAMES = "frame1.bmp frame2.bmp frame3.bmp"
```

#### U-Boot Frame Time

Time per frame in ms (default 1000), rounded down to whole display frames
(16.7 ms at 60 Hz):

```sh
# build/conf/local.conf
RZG3L_LOGO_SEQUENCE_RATE_MS = "500"
```

For trials without a rebuild:

```sh
=> setenv logo_rate_ms 500      # frame time in ms
=> setenv logo_frames 3         # play at most this many frames
=> saveenv
=> reset
```

To return to the built-in values, delete the variables and run `saveenv`.

> **Note:** The sequence plays in parallel with the boot. If it is longer than
> the boot, Linux takes over before the last frame.

#### Resolution

1920x1080 (default) and 1280x720 are supported:

```sh
# build/conf/local.conf
RZG3L_LOGO_SEQUENCE_RESOLUTION = "1280x720"
RZG3L_LOGO_SEQUENCE_FRAMES = "frame1_720p.bmp frame2_720p.bmp"
```

- All frames must have the new size.
- The kernel needs no change. The HDMI output then offers only this mode, so
  use the same size for the sample application images.

Other resolutions need a new timing table in U-Boot. See
`meta-rzg3l-seamless-logo-sequence/README`, section III. The maximum is
1920x1080@60.

#### Linux Images and Interval

Edit `/home/root/run-app.sh` on the board:

```sh
IMAGES="
/home/root/w1.bmp
/home/root/w2.bmp
/home/root/w3.bmp
"

INTERVAL_MS=1000
```

- Any number of images, shown in this order.
- Uncompressed BMP, 24 or 32 bpp, at the U-Boot resolution. Other sizes are
  centred, or scaled with `--fit=scale`.
- Takes effect at the next boot.

For other options, run `logo_sample_app --help`.

> **Important:** Weston starts after the last image. With N images and an
> interval of T ms, Weston starts about N × T ms later (7 s by default).

---

## 5. Solution 3: Seamless Logo CM33 Animation

### 5.1 Key Components

- **`meta-rzg3l-seamless-logo-still`**: the still logo and its display, as
  in Solution 1 (Layer0).
- **`meta-rzg3l-seamless-logo-cm33-anim`**: an animation on a second layer
  (Layer1), blended over the still logo.
  - **U-Boot**: sets up Layer1, loads the frames and passes them to the
    CM33.
  - **CM33 firmware**: started by BL2. It switches the frames until the first
    Weston frame.
  - **Frames**: made at build time. Default: a 12-dot spinner, 192x192, below
    the wordmark, with a percentage inside. The bright dot steps clockwise,
    one dot per 125 ms (one turn in 1.5 s). The percentage is simulated: it
    counts from 1 % to 99 % in 20 s, fast first, then slower. It then stays
    at 99 % and the spinner keeps turning until the first Weston frame.
- **RZ/G3L Multi-OS package**: its BL2 loads and starts the CM33 firmware.

The CM33 only changes two values in a display list in SRAM. The display reads
the list at every frame start, so a switch never tears. The Cortex-A55 is not
involved after U-Boot. U-Boot loads the frames after the logo is on screen:
about 0.27 s with the default animation, before the kernel starts (5.3).

Default sequence:

```text
reset → still logo + spinner 1 % … 99 % (then 99 %, looped) ────→ Weston desktop
        └─ U-Boot ─┘└──────── kernel, systemd (CM33 animates) ───┘
```

### 5.2 Implementation Steps

#### Step 1. Add the Layers

Download the RZ/G3L Multi-OS package v4.2.0 and extract it in the top
directory of the workspace. Then add the layers:

```sh
# pwd should be the build directory of the workspace

bitbake-layers add-layer ../meta-rz-features/meta-rz-multi-os/meta-rzg/meta-rzg3l
bitbake-layers add-layer ../meta-rzg3l-seamless-logo-still
bitbake-layers add-layer ../meta-rzg3l-seamless-logo-cm33-anim
```

> **Note:** Cannot be combined with `meta-rzg3l-seamless-logo-sequence`. Can
> be combined with `meta-rzg3l-fast-boot`: add it first and set
> `DISTRO = "rz-vlp-fast"` (3.2).

#### Step 2. Configure `local.conf`

Add to `build/conf/local.conf`:

```sh
USE_OPENAMP = "0"
```

Otherwise the Multi-OS package installs its own CM33 firmware. BL2 loads only
one.

#### Step 3. Build the Image

```sh
MACHINE=smarc-rzg3l bitbake core-image-weston
```

The WIC image in `build/tmp/deploy/images/smarc-rzg3l/` contains `bl2`,
`fip`, the CM33 firmware and the frames.

#### Step 4. Write the Board for eSD Boot

1. **Write the WIC image to a microSD card** (Start-up Guide 3):

   ```sh
   # pwd should be the build directory of the workspace
   # replace sdX with the actual microSD card device

   sudo bmaptool copy tmp/deploy/images/smarc-rzg3l/core-image-weston-smarc-rzg3l.rootfs.wic.gz /dev/sdX
   ```

2. **Set eSD boot mode** (Start-up Guide 8.3.2, Table 17). Set the "SYS" DIP
   switch to the SMARC module microSD slot (`SW_SD0_DEV_SEL`, Start-up Guide
   4.1.3).

3. **Insert the card into the SMARC module slot** and power on (Start-up
   Guide 8.3.3).

> **Note:** Always use `bl2`, `fip` and the CM33 firmware of the same build.
> The WIC image keeps them together.

### 5.3 Customization

All settings go in `build/conf/local.conf` and need a rebuild. With eSD boot,
writing the WIC image updates everything.

| What to change | Variable | Default |
|---|---|---|
| Time from 1 % to 99 % (s) | `FLA_ANIM_PROGRESS_S` | `20` |
| Own frames instead of the spinner | `FLA_ANIM_FRAMES` | `""` (the spinner) |
| Frame size | `FLA_ANIM_SIZE` | `192x192` |
| Time per frame (ms) | `FLA_ANIM_PERIOD_MS` | `125` |
| Loop (1) or play once and hold (0) | `FLA_ANIM_LOOP` | `1` |
| Own frames: first frame of the loop | `FLA_ANIM_LOOP_FROM` | `0` |
| Vertical centre (per mille of the screen height) | `FLA_ANIM_Y` | `800` |
| Time limit (ms, 0: none) | `FLA_TIMEOUT_MS` | `60000` |
| Frame package (`""`: still logo only) | `FLA_ANIM_PACKAGE` | `rzg3l-seamless-logo-cm33-anim-frames` |

For the still logo, see 3.3.

#### Time from 1 % to 99 %

The percentage does not measure the boot. It follows a fixed curve over
`FLA_ANIM_PROGRESS_S` seconds after the animation starts (once U-Boot has
loaded the frames, about 0.3 s after the logo appears):

| Time | 0 | 25 % | 50 % | 75 % | 100 % | after that |
|---|---|---|---|---|---|---|
| Shown | 1 % | 43 % | 74 % | 92 % | 99 % | 99 %, until the first Weston frame |

If Weston starts earlier, the desktop replaces the animation at a lower
percentage. If it starts later, 99 % stays on screen longer. Set the time a
little shorter than the time to the Weston desktop of your image, for example:

```sh
# build/conf/local.conf
FLA_ANIM_PROGRESS_S = "12"      # 99 % after 12 s, e.g. with meta-rzg3l-fast-boot
```

Whole or decimal seconds (`"12.5"`) are accepted. Rebuild the image and
write the WIC image (5.2, Step 4).

Every frame is stored, so the time sets the number of frames and the time
U-Boot needs to load them:

| `FLA_ANIM_PROGRESS_S` | Frames | Frame data | U-Boot `ready in` |
|---|---|---|---|
| `12` | 108 | 16 MB | about 0.17 s (estimated) |
| `20` (default) | 172 | 25 MB | 0.265 s (measured) |
| `30` | 252 | 37 MB | about 0.39 s (estimated) |

- Frames = `FLA_ANIM_PROGRESS_S` × 1000 / `FLA_ANIM_PERIOD_MS`, plus 12 for
  the spinner turn at 99 %. A frame is 192 × 192 × 4 bytes.
- U-Boot loads them after the logo is on screen, so the logo is not delayed,
  but the kernel starts later by that time.
- The frames must fit in 80 MiB: with the default size and frame time, up to
  about 69 s. The build stops with an error above that.
- `FLA_ANIM_PERIOD_MS` also sets the spinner speed (one dot per frame), and
  `FLA_ANIM_SIZE` the size of the spinner and of the digits. The frame must be
  square.

Check on the serial console (one line):

```text
fla: anim: Layer1 192x192 at (544,480), 172 frame(s) every 125 ms loop from 160,
           timeout 60000 ms, ready in 265 ms: CM33 state 1
```

`loop from 160`: frames 0 to 159 show 1 % to 98 %, then frames 160 to 171
(one spinner turn at 99 %) loop.

#### Own Frames

- PNG, 8-bit RGB or RGBA, not interlaced, alpha not premultiplied.
  Transparent pixels show the still logo.
- Exactly `FLA_ANIM_SIZE`. Width × height must be a multiple of 64.
- At most 80 MiB in total (width × height × 4 bytes per frame).
- With `FLA_ANIM_LOOP = "1"`, the frames before `FLA_ANIM_LOOP_FROM` are
  played once, the rest loops.
- `FLA_ANIM_PROGRESS_S` is not used. Set `FLA_ANIM_PERIOD_MS` for your frames
  (default 125).

The build checks these limits.

```sh
# build/conf/local.conf
FLA_ANIM_FRAMES = "/home/user/anim/f00.png /home/user/anim/f01.png /home/user/anim/f02.png"
FLA_ANIM_SIZE = "256x256"
FLA_ANIM_PERIOD_MS = "50"
```

Plain file names refer to
`meta-rzg3l-seamless-logo-cm33-anim/recipes-graphics/rzg3l-seamless-logo-cm33-anim-frames/files/`.

> **Note:** Keep the animation clear of the parts of the still logo that must
> stay visible. The default spinner sits below the wordmark.

#### Frame Time and Position

```sh
# build/conf/local.conf
FLA_ANIM_PERIOD_MS = "100"     # spinner: one turn in 1.2 s
FLA_ANIM_LOOP = "0"
FLA_ANIM_Y = "500"              # centre of the screen
```

- The spinner steps one dot per frame: `FLA_ANIM_PERIOD_MS` sets its speed.
  The percentage still reaches 99 % after `FLA_ANIM_PROGRESS_S`.
- `FLA_ANIM_LOOP = "0"`: the animation stops on its last frame (99 %, the
  spinner stands still).
- A frame switch is shown at the next display frame (16.7 ms at 60 Hz). Use
  17 ms or more.
- Layer1 is centred horizontally. `FLA_ANIM_Y` works for 1280x720 and
  1920x1080.

#### U-Boot Environment

For trials, saved with `saveenv`:

| Variable | Effect |
|---|---|
| `fla_off=1` | No animation |
| `fla_period_ms` | Time per frame in ms |
| `fla_timeout_ms` | Time limit in ms |

> **Note:** With eSD boot, U-Boot uses its default environment at every boot
> (Start-up Guide 8.3.3). Use the `local.conf` variables instead.

---

## 6. Known Limitations

**All solutions**

- The HDMI output is fixed to the U-Boot mode. EDID and hot-plug are not
  used. A monitor without that mode shows no picture.
- No `/dev/fb0` and no kernel console on HDMI. The serial console works.
- `0x58000000`–`0x5fffffff` (128 MiB) stays reserved.
- The BSP U-Boot environment has `loadaddr=0x58000000`, the logo frame
  buffer. Give an explicit address to manual `ext4load` or `tftp` commands.
- Some monitors lock onto the HDMI signal late and miss the first frame.

**Solution 1**

- The rootfs must be on eMMC.
- The logo resolution (1280x720) is compiled into U-Boot.

**Solution 2**

- The frames are loaded from partition 2 of the boot MMC device. Other boot
  media show a black frame.
- With the sample application, Weston starts after the image sequence.
- Not tested together with `meta-rzg3l-fast-boot`.

**Solution 3**

- Tested with eSD boot only. The frames are loaded from partition 2 of
  `mmc 0` (SMARC module microSD slot or eMMC).
- OpenAMP / RPMsg cannot be used on the CM33 at the same time.
- BL2 loads the CM33 firmware first, so the logo appears about 0.2 s later
  than without the Multi-OS package (estimated).
- Loading the frames delays the kernel start: about 0.27 s with the default
  animation (5.3, Time from 1 % to 99 %).
- The percentage is simulated. It does not follow the boot progress.
- The animation ends at the first Weston frame. A Linux application cannot
  continue it.

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
│   ├── meta-rzg3l-seamless-logo-still/            # still logo (Solutions 1 and 3)
│   ├── meta-rzg3l-seamless-logo-sequence/         # logo sequence (Solution 2)
│   └── meta-rzg3l-seamless-logo-cm33-anim/        # CM33 animation (Solution 3)
│
├── apps/
│   └── rzg3l-seamless-logo-sequence-app/          # sample application (Solution 2)
│       ├── README.md
│       ├── main.c  Makefile  run-app.sh  sample-app.service
│       ├── prebuilt/logo_sample_app
│       └── images/w1.bmp … w7.bmp
│
├── image/                                         # prebuilt WIC images
│   ├── README.md
│   ├── fast-boot-seamless-logo-still/             # Solution 1
│   ├── seamless-logo-sequence/                    # Solution 2
│   └── seamless-logo-cm33-anim/                   # Solution 3
└── reference/                                     # RZ/G3L Linux Start-up Guide
```
