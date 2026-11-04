# SPDX-License-Identifier: MIT
#
# Build in the BSP SDK environment. CFLAGS and LDFLAGS are appended to, so the
# SDK's flags (sysroot, architecture) are kept.

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
