Z8K_GCC = /Users/paxia/Projects/gcc-z8k/build-z8k-coff/gcc
XGCC = $(Z8K_GCC)/xgcc -B$(Z8K_GCC)/
AS = z8k-coff-as
LD = z8k-coff-ld
OBJCOPY = z8k-coff-objcopy

CFLAGS = -Os -msegmented -ffreestanding -nostdlib -fno-builtin -Wall

all: init.bin

crt0.o: crt0.S
	$(AS) -z8001 -o $@ $<

syscalls.o: syscalls.S
	$(AS) -z8001 -o $@ $<

init.o: init.c
	$(XGCC) $(CFLAGS) -c -o $@ $<

init.coff: crt0.o init.o syscalls.o
	$(LD) -m z8001 -T user.ld -o $@ crt0.o init.o syscalls.o

init.bin: init.coff fixhdr.py
	$(OBJCOPY) -O binary $< $@
	python3 fixhdr.py $@

clean:
	rm -f *.o *.coff *.bin
