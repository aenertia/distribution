# SPDX-License-Identifier: GPL-2.0
# Cross-compile Makefile: CC, CFLAGS, LDFLAGS set by ROCKNIX build system

CC      ?= gcc
CFLAGS  ?= -O2
LDFLAGS ?=

EXTRA_CFLAGS  = -Wall -Wextra -Wpedantic -std=gnu11
EXTRA_LDFLAGS =

TARGET  = ssc-iio-bridge
SOURCES = main.c
OBJECTS = $(SOURCES:.c=.o)

DESTDIR ?=

all: $(TARGET)

$(TARGET): $(OBJECTS)
	$(CC) $(CFLAGS) $(EXTRA_CFLAGS) -o $@ $^ $(LDFLAGS) $(EXTRA_LDFLAGS)

%.o: %.c
	$(CC) $(CFLAGS) $(EXTRA_CFLAGS) -c -o $@ $<

install: $(TARGET)
	install -Dm0755 $(TARGET) $(DESTDIR)/usr/bin/$(TARGET)
	install -Dm0644 ssc-iio-bridge.service $(DESTDIR)/usr/lib/systemd/system/ssc-iio-bridge.service

clean:
	rm -f $(OBJECTS) $(TARGET)

.PHONY: all install clean
