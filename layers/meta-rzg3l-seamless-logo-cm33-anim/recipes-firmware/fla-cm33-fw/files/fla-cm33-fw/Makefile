# Animation-only CM33 firmware, bare metal.
#
#   make CROSS_COMPILE=arm-none-eabi- ANIM_DIR=<fla-anim directory>
#
#   .bin   raw image. BL2 copies it from offset 0x270000 to SRAM 0x20000.
#   .srec  the same image at address 0, for Flash Writer.

CROSS_COMPILE	?= arm-none-eabi-
CC		:= $(CROSS_COMPILE)gcc
OBJCOPY		:= $(CROSS_COMPILE)objcopy
SIZE		:= $(CROSS_COMPILE)size

# Shared with the lpdemo-cm33-fw bbappend.
ANIM_DIR	?= ../fla-anim

OUT		:= out
TARGET		:= $(OUT)/fla-cm33-fw

# BL2 reads only RZG3L_M33_FW_SIZE (192 KiB).
IMAGE_MAX	:= 196608

SRCS := \
	src/startup.c \
	src/main.c

ANIM_SRCS := \
	$(ANIM_DIR)/fla_anim.c

INCLUDES := -Isrc -I$(ANIM_DIR)

CFLAGS := -mcpu=cortex-m33 -mthumb -mfloat-abi=soft -Os -g \
	-ffreestanding -fno-builtin -fno-pie -ffunction-sections -fdata-sections -std=gnu11 \
	-Wall -Wextra -Wno-unused-parameter -Werror $(EXTRA_CFLAGS)

LDFLAGS := -nostdlib -nostartfiles -static -T fla_cm33.ld \
	-Wl,--build-id=none -Wl,--gc-sections -Wl,--no-warn-rwx-segments -Wl,-Map=$(TARGET).map

OBJS := $(patsubst %.c,$(OUT)/obj/%.o,$(notdir $(SRCS)))
ANIM_OBJS := $(patsubst %.c,$(OUT)/obj/anim/%.o,$(notdir $(ANIM_SRCS)))
HDRS := $(wildcard src/*.h $(ANIM_DIR)/*.h)

.PHONY: all clean check-anim
all: check-anim $(TARGET).bin $(TARGET).srec

check-anim:
	@test -f $(ANIM_DIR)/fla_anim.c || \
		{ echo "ERROR: animation module not found, set ANIM_DIR (now $(ANIM_DIR))"; exit 1; }

$(OUT)/obj/%.o: src/%.c $(HDRS)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

$(OUT)/obj/anim/%.o: $(ANIM_DIR)/%.c $(HDRS)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

$(TARGET).elf: $(OBJS) $(ANIM_OBJS) fla_cm33.ld
	$(CC) $(CFLAGS) $(LDFLAGS) $(OBJS) $(ANIM_OBJS) -lgcc -o $@
	$(SIZE) $@

$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O binary $< $@
	@size=$$(stat -c %s $@); \
	 if [ $$size -gt $(IMAGE_MAX) ]; then \
		echo "ERROR: $@ is $$size bytes, BL2 loads only $(IMAGE_MAX)"; exit 1; fi; \
	 printf "%s: %d bytes\n" $@ $$size

$(TARGET).srec: $(TARGET).bin
	$(OBJCOPY) -I binary -O srec --srec-forceS3 --adjust-vma=0 $< $@

clean:
	rm -rf $(OUT)
