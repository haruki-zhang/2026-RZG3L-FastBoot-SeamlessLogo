# Boot logo sample application for RZ/G3L

A small DRM/KMS program that shows a sequence of BMP images on the display
early in Linux boot, before the compositor starts. It is a reference for an
application that continues a boot logo in Linux, and is meant to be replaced by
your own.

It works on a stock RZ/G3L BSP image, and on an image built with the
`meta-rzg3l-fast-logo-intro` layer, where U-Boot has already put a logo on the
display and the kernel keeps it there. It does not depend on that layer, and
the layer does not depend on it.

Environment: RZ/G3L SMARC EVK, BSP v1.0.0 (Yocto scarthgap), HDMI display.

## Contents

    README.md
    w1.bmp .. w7.bmp        sample images, 1920x1080, 24 bpp
    exit/                   variant (a): show the images, then exit
        main.c Makefile run-app.sh sample-app.service
    hold/                   variant (b): show the images, then keep the last
        main.c Makefile     one on screen until the compositor replaces it
        run-app.sh sample-app.service

Pick one variant. Both build a program called `logo_sample_app` and use the
same file names, so only one can be installed at a time.

| | exit | hold |
|---|---|---|
| After the last image | waits one interval, then exits | drops DRM master and keeps the last image on screen |
| Between the app and the compositor | the screen is dark until the compositor draws (about 2-3 s on a stock image) | no gap: the compositor's first frame replaces the last image |
| systemd | `Type=oneshot`, `Before=weston.service` | `Type=notify`, `Before=weston.service` |
| Compositor starts | when the program exits | when the program reports readiness, right after the last image |

In both cases the compositor waits for the images: only one program can be DRM
master, and only the master can set modes. With seven images at one second
each, weston starts about seven seconds later than it would without the
application.

## Build

Build the SDK for the image you run, install it, and build with it:

    $ bitbake core-image-weston -c populate_sdk
    $ sh tmp/deploy/sdk/rz-vlp-glibc-x86_64-core-image-weston-cortexa55-smarc-rzg3l-toolchain-5.0.14.sh
    $ source /opt/rz-vlp/5.0.14/environment-setup-cortexa55-poky-linux
    $ cd exit        # or hold
    $ make

(The installer's default directory is `/opt/rz-vlp/5.0.14`; `-d <dir>` installs
elsewhere.) The SDK does not have to come from an image with
`meta-rzg3l-fast-logo-intro`: that layer changes nothing the application is
built against.

This produces `logo_sample_app`. The only library it needs is libdrm, which
every image with a graphical stack has.

## Install

| File | To (on the board) |
|---|---|
| `logo_sample_app` | `/home/root/` |
| `run-app.sh` | `/home/root/` (keep it executable) |
| `w1.bmp` .. `w7.bmp` | `/home/root/` |
| `sample-app.service` | `/lib/systemd/system/` |

`/home/root/` is where the RZ/G2L PoC kept them. On RZ/G3L BSP v1.0.0 images
root's home directory is `/root` and `/home/root` does not exist, so create it
once on the board first:

    # mkdir -p /home/root

(Or keep the files elsewhere and change the paths in `run-app.sh` and
`sample-app.service` to match.)

To copy over the network - the image runs an SSH server and root has no
password:

    $ scp exit/logo_sample_app exit/run-app.sh w*.bmp root@<board-ip>:/home/root/
    $ scp exit/sample-app.service root@<board-ip>:/lib/systemd/system/

Alternatively, write the files onto partition 2 (ext4) of the microSD card
from the PC.

Then, once, on the board:

    # systemctl enable sample-app.service

It runs at every boot from then on. To stop using it:

    # systemctl disable sample-app.service

To switch variants, replace `logo_sample_app` and `sample-app.service` with
the other variant's, then run `systemctl daemon-reload`.

## Changing the images

Edit `run-app.sh` on the board:

    IMAGES="
    /home/root/w1.bmp
    ...
    "
    INTERVAL_MS=1000

- Any number of images, shown in the order listed.
- Uncompressed BMP, 24 or 32 bpp, any size.
- The display mode is chosen from the first image: if the display offers a
  mode of that size it is used, otherwise the display's preferred mode. An image
  that does not match the mode is shown 1:1 and centred - cropped if it is
  larger, with black borders if it is smaller. `--fit=scale` scales it to fit
  instead, keeping its aspect ratio.
- With `meta-rzg3l-fast-logo-intro` the display offers exactly one mode, the
  one U-Boot drives, so draw the images at that size (1920x1080 by default).

All options (`logo_sample_app --help`):

    -i, --interval=MS      time each image stays on screen (default 1000)
    -w, --wait=MS          exit: keep the last image this much longer (default 0)
    -t, --hold-max=MS      hold: stop holding the last image after this long;
                           0 holds it until replaced (default 60000)
    -m, --mode=WxH         use this mode if the display offers it
                           (default: the size of the first image)
    -f, --fit=center|scale place images that do not match the mode
    -M, --module=NAME      DRM driver to use (default rzg2l-du)
    -d, --device-wait=MS   wait this long for the DRM device (default 3000)

## Behaviour with and without the layer

Without the layer (stock BSP): the display comes up in Linux; the kernel
console is visible until the program sets its mode. The `exit` variant hands
the display back to the kernel console when it exits, until the compositor
starts.

With `meta-rzg3l-fast-logo-intro`: U-Boot's last frame is on screen when the
program starts. Its first image replaces it without the display re-syncing.
With the `exit` variant the screen goes dark when it exits, until the
compositor draws; with `hold` it goes straight from the last image to the
compositor.

## Writing your own application

The points that matter, all shown in `main.c`:

- **DRM master.** Start before the compositor and make the compositor wait
  (`Before=weston.service`, with `Type=oneshot` or `Type=notify`). A program
  that is not master gets `EACCES` from `drmModeSetCrtc()`.
- **Hand the display over.** Closing the DRM device takes your framebuffer off
  the display. To leave your last picture up, drop DRM master with
  `drmDropMaster()` but keep the device open until the compositor has
  committed (see `hold/main.c`).
- **Aspect ratio.** Call `drmSetClientCap(fd, DRM_CLIENT_CAP_ASPECT_RATIO, 1)`
  before reading the connector's modes. Without it the kernel strips the
  picture aspect ratio from CEA modes and a driver that pins the connector to
  one such mode may reject your modeset with `EINVAL`.
  (`meta-rzg3l-fast-logo-intro` accepts both since its kernel patch 0011, but
  other kernels may not.)
- **DRM/KMS, not fbdev.** With `meta-rzg3l-fast-logo-intro` there is no
  `/dev/fb0`: the layer turns DRM fbdev emulation off, because fbdev would
  commit its own blank framebuffer over the boot logo.
- **Pitch.** Write the dumb buffer row by row at `create.pitch`; on this DU it
  is rounded up to 64 bytes and is not always `width * 4`.
- **Opening the device.** Open `/dev/dri/card*` directly and check the driver
  name. `drmOpen()` run as root creates missing `/dev/dri` nodes itself, which
  leaves stale nodes behind when it runs before the device has appeared.
- **Never block the boot.** Bound every wait, and report readiness on every
  exit path when using `Type=notify`.

## Differences from the RZ/G2L PoC application

This is based on the libdrm sample of the RZ/G2L FastLogo PoC (v0.8). Changes:
the driver name (`rzg2l-du`), aspect-ratio-aware modes, mode selection and image placement for any
resolution, BMP row padding and 32 bpp support, pitch-correct drawing, flips on
a fixed schedule that wait for completion, the first image shown once instead
of twice, image list and interval as options, a systemd unit ordered before
weston that actually reports readiness (`hold`) or uses `Type=oneshot`
(`exit`), and the `hold` variant.
