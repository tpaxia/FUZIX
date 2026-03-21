/*
 *	Context switching for Z8001 flat memory model
 *
 *	Adapted for Z8001 segmented addressing.
 *	Stack pointer is RR14 (R14=segment, R15=offset).
 *	All push/pop use @rr14.
 *	All indirect memory access uses register pairs (rr2, rr4...).
 *	R0 cannot be used as a base register.
 *
 *	GCC z8k-coff: args on stack, return in r2/rr2.
 */

#include "../../cpu-z8000/kernel-z8000.def"

	.segm

	.globl	_plt_switchout
	.globl	_switchin
	.globl	_dofork
	.globl	_udata_shadow

	.text

/*
 *	Switchout saves the current process state and calls getproc
 *	to find a new process to run, then calls switchin.
 */
_plt_switchout:
	di	vi,nvi

	/* Save callee-saved registers and user SP on kernel stack */
	ldctl	r0, nspseg
	ldctl	r1, nspoff
	pushl	@rr14, rr0		! save user SP (seg:off)
	pushl	@rr14, rr8
	pushl	@rr14, rr10		! includes udata ptr R10
	pushl	@rr14, rr12

	/* Save kernel SP in udata */
	ldl	rr10(#U_DATA__U_SP), rr14

	/* Find another process to run */
	call	_getproc

	/* switchin(p) - getproc returns ptptr in rr2 */
	pushl	@rr14, rr2		! push arg for switchin
	call	_switchin

	/* Should never return */
	jp	_plt_monitor

/*
 *	switchin(ptptr p)
 *	Switch to process p. Argument (32-bit ptr) at rr14(#4).
 */
_switchin:
	di	vi,nvi

	ldl	rr2, rr14(#4)		! get process pointer from stack

	/* Get the udata pointer for this process */
	ldl	rr10, rr2(#P_TAB__P_UDATA_OFFSET)

	/* Verify u_ptab matches */
	ldl	rr6, rr10(#U_DATA__U_PTAB)
	cpl	rr6, rr2
	jr	nz, switchinfail

	/* Update shadow */
	ldl	_udata_shadow, rr10

	/* Restore kernel SP */
	ldl	rr14, rr10(#U_DATA__U_SP)

	/* Mark process as running */
	ldb	(0x82000000+P_TAB__P_STATUS_OFFSET)(r3), #P_RUNNING

	/* Restore callee-saved registers */
	popl	rr12, @rr14
	popl	rr10, @rr14		! restores R10 (udata ptr) from saved
	popl	rr8, @rr14
	popl	rr0, @rr14		! user SP (seg:off)
	ldctl	nspseg, r0
	ldctl	nspoff, r1

	/* Clear runticks */
	clr	_runticks

	testb	(0x82000000+U_DATA__U_ININTERRUPT)(r11)
	jr	nz, keepoff

	ei	vi,nvi

keepoff:
	clr	r2			! return 0
	ret

switchinfail:
	call	_plt_monitor

/*
 *	dofork(ptptr child)
 *	child (32-bit ptr) at rr14(#4)
 *
 *	TODO: Proper implementation for segmented mode.
 *	For now this is a stub that will need to be completed.
 */
_dofork:
	clr	r2			! return 0 = failure
	ret
