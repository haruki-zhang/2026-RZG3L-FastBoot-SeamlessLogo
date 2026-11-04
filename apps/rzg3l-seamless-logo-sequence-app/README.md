# rzg3l-seamless-logo-sequence-app

Sample DRM/KMS application for the RZ/G3L SMARC EVK. It shows a sequence of
BMP images early in the Linux boot and keeps the last image on screen until
Weston draws its first frame.

It works on a stock BSP image and on an image with
`meta-rzg3l-seamless-logo-sequence`. With the layer, the first image replaces
the last U-Boot frame without an HDMI re-sync.

Tested with RZ/G3L BSP v1.0.0, HDMI display.

## Contents

    main.c, Makefile        source
    run-app.sh              start script: image list and interval
    sample-app.service      systemd unit
    prebuilt/logo_sample_app
                            prebuilt binary (aarch64, BSP v1.0.0 SDK)
    images/w1.bmp .. w7.bmp sample images, 1920x1080, 24 bpp

## Build

Use the prebuilt binary, or build with the BSP SDK:

    $ bitbake core-image-weston -c populate_sdk
    $ sh tmp/deploy/sdk/rz-vlp-glibc-x86_64-core-image-weston-cortexa55-smarc-rzg3l-toolchain-5.0.14.sh
    $ source /opt/rz-vlp/5.0.14/environment-setup-cortexa55-poky-linux
    $ make

## Install

| File | Destination on the board |
|---|---|
| `logo_sample_app`, `run-app.sh`, `images/w*.bmp` | `/home/root/` |
| `sample-app.service` | `/lib/systemd/system/` |

`/home/root` does not exist on BSP v1.0.0 images. Create it first:

    # mkdir -p /home/root

Copy the files, for example over SSH (root has no password):

    $ scp prebuilt/logo_sample_app run-app.sh images/w*.bmp root@<board-ip>:/home/root/
    $ scp sample-app.service root@<board-ip>:/lib/systemd/system/

Enable the service:

    # systemctl enable sample-app.service

## Configuration

Edit `IMAGES` and `INTERVAL_MS` in `/home/root/run-app.sh`. The change takes
effect at the next boot.

- Uncompressed BMP, 24 or 32 bpp, any number of images.
- The first image selects the mode. An image that does not match the mode is
  centred, or scaled with `--fit=scale`.
- With `meta-rzg3l-seamless-logo-sequence`, the display offers only the
  U-Boot mode (1920x1080 by default).
- Weston starts after the last image: N images × interval later than without
  the application.

Options (`logo_sample_app --help`):

    -i, --interval=MS      time per image (default 1000)
    -t, --hold-max=MS      stop holding the last image after this time;
                           0: until replaced (default 60000)
    -m, --mode=WxH         use this mode if the display offers it
    -f, --fit=center|scale place images that do not match the mode
    -M, --module=NAME      DRM driver (default rzg2l-du)
    -d, --device-wait=MS   wait for the DRM device (default 3000)

## Notes for your own application

- Only one program can be DRM master. Start before Weston
  (`Before=weston.service`, `Type=notify`).
- To keep the last image on screen, call `drmDropMaster()` but keep the DRM
  device open until Weston has committed.
- Set `DRM_CLIENT_CAP_ASPECT_RATIO` before reading modes. Some drivers
  compare the aspect ratio and reject a mode handed back without it.
- Use DRM/KMS. There is no `/dev/fb0`.
- Write the dumb buffer at `create.pitch`. It is not always `width * 4`.
- Bound every wait and report readiness on every exit path, so the boot is
  never blocked.
