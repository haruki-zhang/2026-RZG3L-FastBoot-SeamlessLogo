#!/bin/sh
#
# Started by sample-app.service. Options: "logo_sample_app --help".

APP=/home/root/logo_sample_app

# Shown in this order. An image that does not match the mode is centred.
IMAGES="
/home/root/w1.bmp
/home/root/w2.bmp
/home/root/w3.bmp
/home/root/w4.bmp
/home/root/w5.bmp
/home/root/w6.bmp
/home/root/w7.bmp
"

INTERVAL_MS=1000

# exec: Type=notify accepts READY=1 only from the main process.
# shellcheck disable=SC2086
exec "$APP" --interval="$INTERVAL_MS" $IMAGES
