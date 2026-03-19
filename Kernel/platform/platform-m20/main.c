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

void pagemap_init(void)
{
	/* Linker provided end of kernel */
	extern uint8_t _end;
	uint32_t e = (uint32_t)&_end;

	/*
	 *	Allocate the rest of available RAM to userspace.
	 *	With 512 KB we have segments 0-7 mapped to physical RAM.
	 *	The kernel lives in the lower segments; user space gets the rest.
	 */
	/* TODO: determine actual RAM end from hardware/boot info */
	kmemaddblk((void *)e, 0x80000 - e);

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
