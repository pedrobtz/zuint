# The fixed-point core's C test binary (design 2.2), built without R.
#
#   make -C tools/fixed                    ASan and UBSan
#   make -C tools/fixed SAN=thread         ThreadSanitizer, for `fixed threads`
#   make -C tools/fixed CPPFLAGS=-DZUF_NO_INT128
#                                          zufast's portable 128-bit fallback
#
# ZUFAST_INCLUDE is zufast's inst/include; by default the installed zufast's.

ZUFAST_INCLUDE ?= $(shell Rscript -e 'cat(system.file("include", package = "zufast"))' 2>/dev/null)
CC ?= cc
SAN ?= address,undefined
CFLAGS ?= -O1 -g -fno-omit-frame-pointer -fsanitize=$(SAN) -fno-sanitize-recover=all
WARN = -std=c99 -Wall -Wextra -Werror -pedantic -D_POSIX_C_SOURCE=200809L

ROOT = ../..
SRC = fixed.c $(ROOT)/src/zu_fixed.c $(ROOT)/src/zu_api.c

fixed: $(SRC) $(ROOT)/src/zu_fixed.h $(ROOT)/src/zu_api.h $(ROOT)/inst/include/zuint.h
	$(CC) $(WARN) $(CFLAGS) $(CPPFLAGS) -I$(ROOT)/src -I$(ROOT)/inst/include -I$(ZUFAST_INCLUDE) \
	  -o $@ $(SRC) -lm -lpthread

clean:
	rm -f fixed

.PHONY: clean
