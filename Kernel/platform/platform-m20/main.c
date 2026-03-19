#include <kernel.h>
#include <timer.h>
#include <kdata.h>
#include <printf.h>
#include <devtty.h>

uint16_t swap_dev = 0xFFFF;

void do_beep(void)
{
}

/*
 *	MMU initialize - nothing to do, mapping PROMs are fixed
 */
void map_init(void)
{
}

uaddr_t ramtop;
uint8_t need_resched;

uint8_t plt_param(char *p)
{
	return 0;
}

void plt_discard(void)
{
}

void memzero(void *p, usize_t len)
{
	memset(p, 0, len);
}

/*
 *	Construct a Z8001 segmented pointer from segment number and offset.
 *	The CPU register format is: 1SSSSSSS 00000000 OOOOOOOO OOOOOOOO
 */
#define SEG_PTR(seg, off) \
	((void *)(((uint32_t)(0x80 | (seg)) << 24) | (uint32_t)(off)))

void pagemap_init(void)
{
	extern uint8_t _end;

	/*
	 *	Register free memory for user processes.
	 *
	 *	Physical memory map (from mmap.inp, 512K B/W config):
	 *
	 *	Kernel uses:
	 *	  Seg 2: DRAM0 14000-1FFFF + DRAM1 00000  (kernel data/bss)
	 *	  Seg B: DRAM1 14000-1FFFF + DRAM2 00000  (kernel code)
	 *
	 *	Safe D=I user segments (no physical overlap with kernel
	 *	or each other):
	 *	  Seg A: DRAM0 08000-0FFFF + DRAM1 04000-0BFFF  (64 KB)
	 *	  Seg C: DRAM2 04000-13FFF                       (64 KB)
	 *	  Seg D: DRAM2 14000-1FFFF + DRAM3 00000         (64 KB)
	 *	  Seg E: DRAM3 04000-13FFF                       (64 KB)
	 *
	 *	Seg 2 remainder: _end to 0xBFFF (after kernel data/bss)
	 *
	 *	Not used (physical overlap):
	 *	  Seg 9: overlaps Seg 2 (DRAM0 18000-1FFFF)
	 *	  Seg 6: overlaps Seg A (DRAM0 08000-10000)
	 *	  Seg F: last 16K wraps to DRAM3 00000, overlaps Seg D
	 */

	/* Remainder of segment 2 after kernel */
	uint16_t end_off = (uint16_t)(uaddr_t)&_end;
	if (end_off < 0xC000)
		kmemaddblk((void *)&_end, 0xC000 - end_off);

	/* Full user segments — 64 KB each.
	   size_t is 16-bit so 0x10000 overflows; use two 32 KB blocks. */
	kmemaddblk(SEG_PTR(0xA, 0x0000), 0x8000);
	kmemaddblk(SEG_PTR(0xA, 0x8000), 0x8000);
	kmemaddblk(SEG_PTR(0xC, 0x0000), 0x8000);
	kmemaddblk(SEG_PTR(0xC, 0x8000), 0x8000);
	kmemaddblk(SEG_PTR(0xD, 0x0000), 0x8000);
	kmemaddblk(SEG_PTR(0xD, 0x8000), 0x8000);
	kmemaddblk(SEG_PTR(0xE, 0x0000), 0x8000);
	kmemaddblk(SEG_PTR(0xE, 0x8000), 0x8000);

	kputs("Olivetti M20 (Z8001 @ 4 MHz)\n");
}

/* Udata and kernel stacks */
u_block udata_block[PTABSIZE];

void install_vdso(void)
{
	extern uint8_t vdso[];
	memcpy((void *)udata.u_codebase, &vdso, 0x10);
}

uint8_t plt_udata_set(ptptr p)
{
	p->p_udata = &udata_block[p - ptab].u_d;
	return 0;
}
