# Makefile for JioFiber SIP Proxy (b2bua)
CC ?= gcc
CFLAGS ?= -O2 -Wall
PJ_CFLAGS := $(shell pkg-config --cflags libpjproject 2>/dev/null || echo "-I/usr/include/pjproject")
PJ_LIBS := $(shell pkg-config --libs libpjproject 2>/dev/null || echo "-lpjsua -lpjsip-ua -lpjsip-simple -lpjsip -pjmedia-codec -lpjmedia -lpjmedia-videodev -lpjmedia-audiodev -lpjcore -lresample -lssllocal -lsrtp -lpjnath -lpjlib-util -lpj -lssl -lcrypto -lstdc++ -lpthread -lm")

TARGET = b2bua

all: $(TARGET)

$(TARGET): b2bua.c
	$(CC) $(CFLAGS) $(PJ_CFLAGS) -o $@ b2bua.c $(PJ_LIBS)

clean:
	rm -f $(TARGET) *.o

.PHONY: all clean
