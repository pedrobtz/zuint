# Builds tools/fuzz/driver: the fuzz harness over a plain main(), without
# libFuzzer, for a local run and for mutation testing (each source compiled
# on its own, as Mull needs). R's headers only: nothing here calls R.
#
#   make -C tools/fuzz driver            # then ./tools/fuzz/run-local
#   make -C tools/fuzz driver CC="$MULL_CC" CFLAGS=
CC ?= cc
CFLAGS ?= -g -O1 -fno-omit-frame-pointer -fsanitize=address,undefined
R_INCLUDE := $(shell R RHOME)/include
ZUFAST_INCLUDE ?= $(shell Rscript -e 'cat(system.file("include", package = "zufast"))')
CPPFLAGS += -I../../src -I$(R_INCLUDE) -I$(ZUFAST_INCLUDE)
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
