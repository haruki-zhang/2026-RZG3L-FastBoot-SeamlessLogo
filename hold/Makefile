# SPDX-License-Identifier: MIT
#
# Build with the BSP's SDK:
#
#   $ source /opt/poky/<version>/environment-setup-cortexa55-poky-linux
#   $ make
#
# The SDK environment provides CC (with --sysroot), CFLAGS, LDFLAGS and a
# pkg-config that looks inside the SDK sysroot. CFLAGS and LDFLAGS are appended
# to, not replaced, so the SDK's flags survive.

BIN ?= logo_sample_app
PKG_CONFIG ?= pkg-config

CFLAGS += -Wall -Wextra $(shell $(PKG_CONFIG) --cflags libdrm)
LDLIBS += $(shell $(PKG_CONFIG) --libs libdrm)

.PHONY: all clean

all: $(BIN)

$(BIN): main.o
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^ $(LDLIBS)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(BIN) main.o
