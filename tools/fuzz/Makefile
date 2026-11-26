# Builds tools/fuzz/driver: the fuzz harness over a plain main(), without
# libFuzzer, for a local run and for mutation testing (each source compiled
# on its own, as Mull needs). R's headers only: nothing here calls R.
#
#   make -C tools/fuzz driver            # then tools/fuzz/driver tools/fuzz/corpus/*
#   make -C tools/fuzz driver CC="$MULL_CC" CFLAGS=
CC ?= cc
CFLAGS ?= -g -O1 -fno-omit-frame-pointer -fsanitize=address,undefined
# R CMD config, not R RHOME: Debian's R keeps R.h in /usr/share/R/include.
R_CPPFLAGS := $(shell R CMD config --cppflags)
ZUFAST_INCLUDE ?= $(shell Rscript -e 'cat(system.file("include", package = "zufast"))')
CPPFLAGS += -I../../src $(R_CPPFLAGS) -I$(ZUFAST_INCLUDE)
OBJS := harness.o driver.o zu_parse.o zu_metadata.o zu_fixed.o

driver: $(OBJS)
	$(CC) $(CFLAGS) $(OBJS) -o $@ -lm

harness.o: harness.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -c harness.c -o $@
driver.o: driver.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -c driver.c -o $@
zu_parse.o: ../../src/zu_parse.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -c ../../src/zu_parse.c -o $@
zu_metadata.o: ../../src/zu_metadata.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -c ../../src/zu_metadata.c -o $@
zu_fixed.o: ../../src/zu_fixed.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -c ../../src/zu_fixed.c -o $@

clean:
	rm -f driver $(OBJS)

.PHONY: clean
