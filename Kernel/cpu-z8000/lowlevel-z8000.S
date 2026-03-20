/*
 *	Z8001 (segmented) low-level support for FUZIX
 *
 *	The Z8001 uses segmented addressing with 7-bit segment + 16-bit offset.
 *	Pointers are 32-bit: high word = segment, low word = offset.
 *	The SC (System Call) instruction is used for syscall entry.
 *	PSAP points to exception/interrupt vector table.
 *	System stack uses RR14 (R14=segment, R15=offset).
 *	Normal stack also uses RR14/R15 in normal mode.
 *
 *	Register conventions:
 *	  R10 = udata pointer (register global, preserved across calls)
 *	  RR14 = stack pointer (system or normal mode)
 *
 *	GCC z8k-coff calling convention (segmented, no -mregparms):
 *	  Arguments: passed on the stack, right-to-left
 *	  Return value: r2 (16-bit), rr2 (32-bit)
 *	  R0-R7: caller-saved
 *	  R8-R13: callee-saved
 *	  RR14: stack pointer (segmented pair)
 *
 *	After a segmented CALL, the stack contains:
 *	  rr14(#0): PC offset (2 bytes)
 *	  rr14(#2): PC segment (2 bytes)
 *	  rr14(#4): first argument
 *	  rr14(#6): second argument ...
 */

#include "kernel-z8000.def"

	.segm

	.globl	___hard_di
	.globl	___hard_ei
	.globl	___hard_irqrestore
	.globl	_doexec
	.globl	_get_usp
	.globl	_set_usp
	.globl	_outstring
	.globl	_outcharhex
	.globl	_vdso
	.globl	_udata_shadow
	.globl	_kernel_flag
	.globl	_copy_blocks
	.globl	_swap_blocks
	.globl	_sys_cpu
	.globl	_sys_cpu_feat
	.globl	_inb
	.globl	_outb
	.globl	_inw
	.globl	_outw
	.globl	_e_syscall
	.globl	_e_nvi
	.globl	_e_vi
	.globl	_e_nmi
	.globl	_e_ext_instr
	.globl	_e_priv_instr
	.globl	_e_segv
	.globl	_need_resched

	.text

/*
 *	I/O port access (Z8001 has separate I/O space)
 *	uint8_t inb(uint16_t port)
 *	port at rr14(#4), return in r2
 */
_inb:
	ld	r1, rr14(#4)		! port from stack
	inb	rl2, @r1
	subb	rh2, rh2		! zero extend
	ret

/*
 *	void outb(uint16_t port, uint8_t val)
 *	port at rr14(#4), val byte at rr14(#7)
 */
_outb:
	ld	r1, rr14(#4)		! port from stack
	ldb	rl0, rr14(#7)		! val byte from stack
	outb	@r1, rl0
	ret

/*
 *	uint16_t inw(uint16_t port)
 *	port at rr14(#4), return in r2
 */
_inw:
	ld	r1, rr14(#4)
	in	r2, @r1
	ret

/*
 *	void outw(uint16_t port, uint16_t val)
 *	port at rr14(#4), val at rr14(#6)
 */
_outw:
	ld	r1, rr14(#4)		! port
	ld	r0, rr14(#6)		! value
	out	@r1, r0
	ret

/*
 *	Interrupt control
 *
 *	irqflags_t ___hard_di(void)
 *	Returns previous FCW interrupt bits in r2
 *
 *	Z8001 FCW bit layout:
 *	  Bit 15: SEG (segmented mode, read-only on Z8001)
 *	  Bit 14: S/N (System/Normal mode)
 *	  Bit 13: EPA (Extended Processing Architecture enable)
 *	  Bit 12: VIE (Vectored Interrupt Enable)
 *	  Bit 11: NVIE (Non-Vectored Interrupt Enable)
 *	  Bits 10-0: flags (C, Z, S, P/V, DA, H)
 */
___hard_di:
	ldctl	r2, fcw
	ld	r1, r2
	and	r1, #0xE7FF		! clear VIE (bit 12) and NVIE (bit 11)
	ldctl	fcw, r1
	and	r2, #0x1800		! return only VIE+NVIE bits
	ret

/*
 *	void ___hard_ei(void)
 */
___hard_ei:
	ei	vi,nvi
	ret

/*
 *	void ___hard_irqrestore(irqflags_t flags)
 *	flags at rr14(#4)
 */
___hard_irqrestore:
	ld	r1, rr14(#4)		! flags from stack (VIE+NVIE bits)
	ldctl	r0, fcw
	and	r0, #0xE7FF		! clear VIE (bit 12) and NVIE (bit 11)
	or	r0, r1			! restore saved VIE+NVIE
	ldctl	fcw, r0
	ret

/*
 *	Get/set user stack pointer (normal mode SP)
 *	The Z8001 LDCTL can access the normal stack pointer from system mode.
 */
_get_usp:
	ldctl	r2, nspseg
	ldctl	r3, nspoff
	ret				! returns seg:off in rr2

/*
 *	void set_usp(uint32_t sp)
 *	sp (seg:off) at rr14(#4)
 */
_set_usp:
	ld	r0, rr14(#4)		! segment
	ld	r1, rr14(#6)		! offset
	ldctl	nspseg, r0
	ldctl	nspoff, r1
	ret

/*
 *	System call entry point
 *
 *	On Z8001, the SC instruction pushes on the system stack:
 *	  +0: SC instruction word (identifier, contains SC #n)
 *	  +2: FCW (saved)
 *	  +4: PC segment
 *	  +6: PC offset
 *
 *	User passes syscall number in R1, args as 32-bit pairs:
 *	  RR2 (R2:R3) = argn
 *	  RR4 (R4:R5) = argn1
 *	  RR6 (R6:R7) = argn2
 *	For 16-bit args, user sets high word to 0 (e.g. clr r2; ld r3, #fd).
 *	Return value in RR2 (to match C convention).
 */
_e_syscall:
	/* Save R10 (udata pointer register) - must be first for fork */
	push	@rr14, r10
	ld	r10, _udata_shadow

	ldb	U_DATA__U_CALLNO(r10), rl1	! syscall number
	ldb	U_DATA__U_INSYS(r10), #1

	/* Save 32-bit arguments.
	   arg_t is 32-bit, stored as two 16-bit words (big-endian).
	   U_DATA__U_ARGN is the offset of the high word. */
	ld	U_DATA__U_ARGN(r10), r2
	ld	U_DATA__U_ARGN+2(r10), r3
	ld	U_DATA__U_ARGN1(r10), r4
	ld	U_DATA__U_ARGN1+2(r10), r5
	ld	U_DATA__U_ARGN2(r10), r6
	ld	U_DATA__U_ARGN2+2(r10), r7

	/* Save user stack pointer */
	ldctl	r0, nspseg
	ldctl	r1, nspoff
	ldl	U_DATA__U_SYSCALL_SP(r10), rr0

	ldb	_kernel_flag, #1
	ei	vi,nvi			! enable interrupts for syscall

	call	_unix_syscall

	di	vi,nvi

	ldb	U_DATA__U_INSYS(r10), #0
	ldb	_kernel_flag, #0

	/* Check for errors */
	ld	r1, U_DATA__U_ERROR(r10)
	test	r1
	jr	nz, sysc_err

	ldl	rr2, U_DATA__U_RETVAL(r10)
	jr	sysc_sig

sysc_err:
	ld	r2, #-1
	ld	r3, #-1

sysc_sig:
	testb	U_DATA__U_CURSIG(r10)
	jr	nz, return_via_signal

	/* Normal return - pop R10 and do IRET */
	pop	r10, @rr14
	iret

return_via_signal:
	/* TODO: signal delivery */
	pop	r10, @rr14
	iret

/*
 *	Execute a user process
 *
 *	doexec(uaddr_t addr)
 *	addr (seg:off) at rr14(#4)
 */
_doexec:
	ldl	rr2, rr14(#4)		! entry point from stack

	/* Reset supervisor stack to top of udata block */
	ldl	rr14, _udata_ptr_seg		! load segmented SP
	add	r15, #UBLOCK_SIZE

	ldb	_kernel_flag, #0
	ldb	U_DATA__U_INSYS(r10), #0

	/* Set user stack pointer */
	ldl	rr0, U_DATA__U_ISP(r10)
	ldctl	nspseg, r0
	ldctl	nspoff, r1

	/* Build an IRET frame on system stack:
	 *   The IRET frame (bottom to top of stack):
	 *     PC offset  (lowest address)
	 *     PC segment
	 *     FCW
	 *     Identifier (highest address, popped first)
	 */
	push	@rr14, r3		! PC offset
	push	@rr14, r2		! PC segment
	ld	r0, #0x9800		! FCW: SEG=1, S/N=0(normal), VIE=1, NVIE=1
	push	@rr14, r0
	clr	r0			! identifier
	push	@rr14, r0

	/* Clear user-visible registers */
	clr	r0
	clr	r1
	clr	r2
	clr	r3
	clr	r4
	clr	r5
	clr	r6
	clr	r7
	clr	r8
	clr	r9
	/* R10 = udata, leave it for now - will be cleared in user VDSO */
	clr	r11
	clr	r12
	clr	r13

	iret			! jump to user space

/*
 *	VDSO - copied into the base of each user executable
 *	Provides the syscall entry point and signal return stub
 */
_vdso:
	sc	#0			! system call trap
	ret
	/* signal unwind */
	/* TODO: signal frame unwinding */
	ret

/*
 *	Exception handlers
 */
_e_ext_instr:
	/* Extended/unimplemented instruction trap */
	call	_trap_monitor
	iret

_e_priv_instr:
	/* Privileged instruction in normal mode */
	call	_trap_monitor
	iret

_e_segv:
	/* Segment violation */
	call	_trap_monitor
	iret

/*
 *	NVI handler (timer interrupt on M20)
 */
_e_nvi:
	pushl	@rr14, rr0
	pushl	@rr14, rr2
	pushl	@rr14, rr4
	pushl	@rr14, rr6
	push	@rr14, r10

	ld	r10, _udata_shadow
	ldb	U_DATA__U_ININTERRUPT(r10), #1

	call	_plt_interrupt

	ldb	U_DATA__U_ININTERRUPT(r10), #0

	testb	U_DATA__U_INSYS(r10)
	jr	nz, nvi_no_preempt

	testb	_need_resched
	jr	z, nvi_no_preempt

	/* Preemption */
	ldl	rr2, U_DATA__U_PTAB(r10)
	ldb	rl0, P_TAB__P_STATUS_OFFSET(r2)
	cpb	rl0, #P_RUNNING
	jr	nz, nvi_no_ready
	ldb	P_TAB__P_STATUS_OFFSET(r2), #P_READY
	ldb	rl0, P_TAB__P_FLAGS_OFFSET(r2)
	orb	rl0, #PFL_BATCH
	ldb	P_TAB__P_FLAGS_OFFSET(r2), rl0
nvi_no_ready:
	call	_switchout

nvi_no_preempt:
	testb	U_DATA__U_CURSIG(r10)
	jr	nz, nvi_signal

	pop	r10, @rr14
	popl	rr6, @rr14
	popl	rr4, @rr14
	popl	rr2, @rr14
	popl	rr0, @rr14
	iret

nvi_signal:
	/* TODO: deliver signal on return from interrupt */
	pop	r10, @rr14
	popl	rr6, @rr14
	popl	rr4, @rr14
	popl	rr2, @rr14
	popl	rr0, @rr14
	iret

/*
 *	VI handler (vectored interrupts via i8259A)
 */
_e_vi:
	pushl	@rr14, rr0
	pushl	@rr14, rr2
	pushl	@rr14, rr4
	pushl	@rr14, rr6
	push	@rr14, r10

	ld	r10, _udata_shadow
	ldb	U_DATA__U_ININTERRUPT(r10), #1

	call	_plt_interrupt

	ldb	U_DATA__U_ININTERRUPT(r10), #0

	pop	r10, @rr14
	popl	rr6, @rr14
	popl	rr4, @rr14
	popl	rr2, @rr14
	popl	rr0, @rr14
	iret

/*
 *	NMI handler
 */
_e_nmi:
	iret

/*
 *	Debug output helpers
 *	These call _outchar which expects its arg on the stack.
 */
_outstring:
	/* rr2 = pointer to string (segmented), at rr14(#4) */
	ldl	rr2, rr14(#4)
_outstring_loop:
	ldb	rl0, @rr2
	testb	rl0
	ret	z
	push	@rr14, r0		! push char as word arg
	call	_outchar
	pop	r0, @rr14		! clean stack
	inc	r3, #1
	jr	_outstring_loop

_outcharhex:
	/* print byte at rr14(#5) as hex */
	push	@rr14, r7		! save caller-saved we use
	ldb	rl7, rr14(#7)		! load byte arg (4 ret + 2 push + 1)
	ldb	rl0, rl7
	srlb	rl0, #4			! high nibble
	subb	rh0, rh0
	call	_hexnibble_out
	ldb	rl0, rl7
	andb	rl0, #0x0F		! low nibble
	subb	rh0, rh0
	call	_hexnibble_out
	pop	r7, @rr14
	ret

_hexnibble_out:
	addb	rl0, #0x30
	cpb	rl0, #0x3A
	jr	lt, _hexnib_ok
	addb	rl0, #7
_hexnib_ok:
	push	@rr14, r0		! push char arg for outchar
	call	_outchar
	pop	r0, @rr14		! clean stack
	ret

/*
 *	Block copy/swap helpers
 *	copy_blocks(void *dst, void *src, unsigned int count)
 *	dst(32-bit) at rr14(#4), src(32-bit) at rr14(#8), count at rr14(#12)
 */
_copy_blocks:
	pushl	@rr14, rr8		! save callee-saved
	ldl	rr2, rr14(#8)		! dst (adjusted for pushed rr8)
	ldl	rr4, rr14(#12)		! src
	ld	r6, rr14(#16)		! count
	test	r6
	jr	z, _copy_done
_copy_loop:
	ld	r8, #256		! 256 words = 512 bytes
_copy_word:
	ld	r0, @rr4
	ld	@rr2, r0
	inc	r3, #2
	inc	r5, #2
	djnz	r8, _copy_word
	djnz	r6, _copy_loop
_copy_done:
	popl	rr8, @rr14
	ret

/*
 *	swap_blocks(void *ptr1, void *ptr2, unsigned int count)
 *	ptr1(32-bit) at rr14(#4), ptr2(32-bit) at rr14(#8), count at rr14(#12)
 */
_swap_blocks:
	pushl	@rr14, rr8		! save callee-saved
	ldl	rr2, rr14(#8)		! ptr1 (adjusted for pushed rr8)
	ldl	rr4, rr14(#12)		! ptr2
	ld	r6, rr14(#16)		! count
	test	r6
	jr	z, _swap_done
_swap_loop:
	ld	r8, #256
_swap_word:
	ld	r0, @rr2
	ld	r1, @rr4
	ld	@rr2, r1
	ld	@rr4, r0
	inc	r3, #2
	inc	r5, #2
	djnz	r8, _swap_word
	djnz	r6, _swap_loop
_swap_done:
	popl	rr8, @rr14
	ret

	.data

_udata_shadow:
	.long	0			! segmented pointer to current udata
	.globl	_udata_ptr_seg
_udata_ptr_seg:
	.long	0			! segmented base for stack reset
_kernel_flag:
	.byte	0
! need_resched is defined in main.c
_sys_cpu:
	.byte	0
_sys_cpu_feat:
	.byte	0
