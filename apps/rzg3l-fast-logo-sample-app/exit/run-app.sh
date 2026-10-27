#!/bin/sh
#
# Started by sample-app.service. Edit the settings below to change what is
# shown; see README.md for all options (or run "logo_sample_app --help").

APP=/home/root/logo_sample_app

# Images, in the order they are shown. Any number, any size - an image that
# does not match the display mode is centred (or scaled, with --fit=scale).
IMAGES="
/home/root/w1.bmp
/home/root/w2.bmp
/home/root/w3.bmp
/home/root/w4.bmp
/home/root/w5.bmp
/home/root/w6.bmp
/home/root/w7.bmp
"

# Time each image stays on screen, in milliseconds.
INTERVAL_MS=1000

# exec, so that systemd sees the application itself as the service.
# shellcheck disable=SC2086
exec "$APP" --interval="$INTERVAL_MS" $IMAGES
