/*
 *	Olivetti M20 platform-specific assembly
 *
 *	Z8001 segmented mode
 */

#include "../../cpu-z8000/kernel-z8000.def"

	.segm

	.globl	_plt_reboot
	.globl	_init_early
	.globl	_init_hardware
	.globl	_program_vectors
	.globl	_plt_interrupt
	.globl	_plt_idle
	.globl	_outchar
	.globl	_plt_monitor

	.globl	_trap_monitor

/*
 *	M20 I/O port addresses
 */
#define	TTY_DATA	0x00C1		/* i8251A serial data */
#define	TTY_CTRL	0x00C3		/* i8251A serial control/status */
#define	PIT_C0		0x0121		/* i8253 counter 0 (TTY baud) */
#define	PIT_C2		0x0125		/* i8253 counter 2 (system timer) */
#define	PIT_CTRL	0x0127		/* i8253 control */
#define	PIC_CMD		0x0041		/* i8259A command */
#define	PIC_DATA	0x0043		/* i8259A data/mask */

	.text

_plt_monitor:
_trap_monitor:
_plt_reboot:
	di	vi,nvi
	jr	_plt_reboot

_init_early:
	/*
	 * Set up udata pointer in R10 and shadow.
	 * udata_block is in segment 2 (.bss).
	 */
	lda	rr10, _udata_block	! R10 = offset, R11 = unused
	! For now R10 holds just the offset within seg 2
	! TODO: proper segmented udata management
	ldl	_udata_shadow, rr10
	ret

_plt_idle:
	ei	vi,nvi
	halt
	ret

_init_hardware:
	/*
	 *	Initialize i8251A TTY USART
	 *	Must reset and configure before use — BIOS state
	 *	may not survive the boot process.
	 */
	ldb	rl0, #0x00
	outb	#TTY_CTRL, rl0		! sync byte 1
	outb	#TTY_CTRL, rl0		! sync byte 2
	outb	#TTY_CTRL, rl0		! sync byte 3
	ldb	rl0, #0x40		! internal reset
	outb	#TTY_CTRL, rl0
	ldb	rl0, #0xCE		! mode: async, 8N1, x16 clock
	outb	#TTY_CTRL, rl0
	ldb	rl0, #0x37		! command: RTS, DTR, error reset, RxEN, TxEN
	outb	#TTY_CTRL, rl0
	inb	rl0, #TTY_DATA		! flush pending data

	/*
	 *	Set up PIT counter 0 for TTY serial baud rate
	 *	Baud = 1230782 / (16 * divisor)
	 *	For 9600: divisor = 8 (gives 9609 baud, close enough)
	 */
	ldb	rl0, #0x36		! Counter 0, LSB then MSB, mode 3
	outb	#PIT_CTRL, rl0
	ldb	rl0, #0x08		! LSB of divisor 8
	outb	#PIT_C0, rl0
	ldb	rl0, #0x00		! MSB of divisor 8
	outb	#PIT_C0, rl0

	/*
	 *	Set up PIT counter 2 for system timer (NVI)
	 *	~50 Hz: divisor = 1230782 / 50 = 24616 = 0x6028
	 */
	ldb	rl0, #0xB4		! Counter 2, LSB then MSB, mode 2
	outb	#PIT_CTRL, rl0
	ldb	rl0, #0x28		! LSB of 0x6028
	outb	#PIT_C2, rl0
	ldb	rl0, #0x60		! MSB of 0x6028
	outb	#PIT_C2, rl0

	/*
	 *	Initialize i8259A PIC
	 */
	ldb	rl0, #0x13		! ICW1: single, edge, ICW4 needed
	outb	#PIC_CMD, rl0
	ldb	rl0, #0x00		! ICW2: vector offset 0
	outb	#PIC_DATA, rl0
	ldb	rl0, #0x01		! ICW4: 8086 mode
	outb	#PIC_DATA, rl0
	ldb	rl0, #0xFF		! Mask all interrupts for now
	outb	#PIC_DATA, rl0

	/*
	 *	Set up PSAP to point to our vector table at <<2>>:0100
	 *	Must be done with interrupts disabled (they already are)
	 */
	ld	r0, #0x8200		! segment 2
	ldctl	psapseg, r0
	ld	r0, #0x0100		! offset 0x100 (256-byte aligned)
	ldctl	psapoff, r0

	/*
	 * TODO: fill PSAP entries with our handlers
	 * For now leave them zeroed (BSS) — any trap/interrupt
	 * before we set them up will jump to 0 and crash,
	 * but interrupts are masked so that's OK until we enable them.
	 */

	/* Set memory size */
	ld	_ramsize, #512		! 512 KB
	ld	_procmem, #384		! rough estimate for user space

	ret

/*
 *	Interrupt dispatcher
 */
_plt_interrupt:
	call	_timer_interrupt
	call	_tty_interrupt
	ret

/*
 *	Program exception vectors
 */
_program_vectors:
	ret

/*
 *	No banking - all stubs are no-ops
 */
	.globl	_map_process_always
	.globl	_map_process
	.globl	_map_kernel
	.globl	_map_restore
	.globl	_map_save

_map_process_always:
_map_process:
_map_kernel:
_map_restore:
_map_save:
	ret

/*
 *	Debug character output via serial port (i8251A at 0x00C1)
 *	Called from C: void outchar(uint_fast8_t c)
 *	Argument on stack (stack calling convention)
 */
_outchar:
	push	@rr14, r1
	ldb	rl0, rr14(#7)		! load char arg from stack
_outchar_wait:
	inb	rl1, #TTY_CTRL		! read status
	bitb	rl1, #2			! TxEMPTY? (not gated by CTS)
	jr	z, _outchar_wait
	outb	#TTY_DATA, rl0
	pop	r1, @rr14
	ret

