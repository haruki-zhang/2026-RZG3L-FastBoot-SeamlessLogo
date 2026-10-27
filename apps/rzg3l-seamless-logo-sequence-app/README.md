# Boot logo sample application for RZ/G3L

A small DRM/KMS program that shows a sequence of BMP images on the display
early in the Linux boot, before the compositor starts, and keeps the last
image on screen until the compositor replaces it. It is a reference
implementation; replace it with your own application as needed.

It runs on a stock RZ/G3L BSP image and on an image built with
`meta-rzg3l-seamless-logo-sequence`, where U-Boot has already put a logo on the
display and the kernel keeps it there. The application and the layer do not
depend on each other.

Environment: RZ/G3L SMARC EVK, BSP v1.0.0 (Yocto scarthgap), HDMI display.

## Contents

    README.md
    main.c                  source
    Makefile
    run-app.sh              start script: image list and interval
    sample-app.service      systemd unit
    prebuilt/
        logo_sample_app     prebuilt binary (aarch64, BSP v1.0.0 SDK)
    images/
        w1.bmp .. w7.bmp    sample images, 1920x1080, 24 bpp

## Behaviour

1. The service starts early in the boot, before `weston.service`.
2. The application shows each image for the configured interval
   (default 1000 ms).
3. After the last image it releases DRM master and reports readiness to
   systemd. Weston then starts.
4. The last image stays on screen until Weston's first frame replaces it.
   There is no black screen in between.

Only one program can be DRM master, and only the master can set a mode, so
Weston waits for the image sequence. With seven images at one second each,
Weston starts about seven seconds later than without the application.

## Build

Use the prebuilt binary in `prebuilt/`, or build with the BSP SDK:

    $ bitbake core-image-weston -c populate_sdk
    $ sh tmp/deploy/sdk/rz-vlp-glibc-x86_64-core-image-weston-cortexa55-smarc-rzg3l-toolchain-5.0.14.sh
    $ source /opt/rz-vlp/5.0.14/environment-setup-cortexa55-poky-linux
    $ make

This produces `logo_sample_app`. The only library it needs is libdrm. The SDK
can come from an image with or without `meta-rzg3l-seamless-logo-sequence`.

## Install

| File | Destination on the board |
|---|---|
| `logo_sample_app` | `/home/root/` |
| `run-app.sh` | `/home/root/` (must be executable) |
| `images/w1.bmp` .. `images/w7.bmp` | `/home/root/` |
| `sample-app.service` | `/lib/systemd/system/` |

On RZ/G3L BSP v1.0.0 images `/home/root` does not exist. Create it once on
the board:

    # mkdir -p /home/root

To use another directory, change the paths in `run-app.sh` and
`sample-app.service`.

Copy the files over the network (the image runs an SSH server; root has no
password):

    $ scp prebuilt/logo_sample_app run-app.sh images/w*.bmp root@<board-ip>:/home/root/
    $ scp sample-app.service root@<board-ip>:/lib/systemd/system/

Alternatively, copy the files to partition 2 (ext4) of the microSD card on
the host PC.

Then enable the service once on the board:

    # systemctl enable sample-app.service

It runs at every boot from then on. To stop using it:

    # systemctl disable sample-app.service

## Changing the images

Edit `run-app.sh` on the board:

    IMAGES="
    /home/root/w1.bmp
    ...
    "
    INTERVAL_MS=1000

- Any number of images, shown in the order listed.
- Uncompressed BMP, 24 or 32 bpp.
- The display mode is chosen from the first image: if the display offers a
  mode of that size it is used, otherwise the display's preferred mode. An
  image that does not match the mode is shown 1:1 and centred (cropped if
  larger, black borders if smaller). `--fit=scale` scales it to fit,
  keeping its aspect ratio.
- With `meta-rzg3l-seamless-logo-sequence` the display offers only the mode
  U-Boot drives, so draw the images at that size (1920x1080 by default).

The change takes effect at the next boot.

All options (`logo_sample_app --help`):

    -i, --interval=MS      time each image stays on screen (default 1000)
    -t, --hold-max=MS      stop holding the last image after this long;
                           0 holds it until replaced (default 60000)
    -m, --mode=WxH         use this mode if the display offers it
                           (default: the size of the first image)
    -f, --fit=center|scale place images that do not match the mode
    -M, --module=NAME      DRM driver to use (default rzg2l-du)
    -d, --device-wait=MS   wait this long for the DRM device (default 3000)

## Behaviour with and without the layer

- **Stock BSP:** Linux brings up the display. The kernel console is visible
  until the application sets its mode.
- **With `meta-rzg3l-seamless-logo-sequence`:** the last U-Boot frame is on
  screen when the application starts. The first image replaces it without an
  HDMI re-sync.

In both cases the last image stays on screen until Weston draws.

## Writing your own application

The key points, all shown in `main.c`:

- **DRM master.** Start before the compositor and make the compositor wait
  (`Before=weston.service` with `Type=notify`). A program that is not DRM
  master gets `EACCES` from `drmModeSetCrtc()`.
- **Hand-over to the compositor.** Closing the DRM device removes your
  framebuffer from the display. To keep your last image on screen, drop DRM
  master with `drmDropMaster()` but keep the device open until the
  compositor has committed.
- **Aspect ratio.** Call `drmSetClientCap(fd, DRM_CLIENT_CAP_ASPECT_RATIO, 1)`
  before reading the connector's modes. Some kernels reject a modeset with
  `EINVAL` otherwise.
- **DRM/KMS, not fbdev.** With `meta-rzg3l-seamless-logo-sequence` there is no
  `/dev/fb0`.
- **Pitch.** Write the dumb buffer row by row at `create.pitch`. On this
  display unit it is rounded up to 64 bytes and is not always `width * 4`.
- **Opening the device.** Open `/dev/dri/card*` directly and check the driver
  name. `drmOpen()` run as root can leave stale `/dev/dri` nodes when it runs
  before the device has appeared.
- **Never block the boot.** Bound every wait, and report readiness to systemd
  on every exit path.
