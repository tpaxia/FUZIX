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
 *
 *	Stack frame after saves (16 bytes + 4 byte return addr):
 *	  SP+0:  rr12
 *	  SP+4:  rr10
 *	  SP+8:  rr8
 *	  SP+12: rr0 (user NSP seg:off)
 *	  SP+16: return address (caller of plt_switchout)
 */
_plt_switchout:
	di	vi,nvi

	/* Save callee-saved registers and user SP on kernel stack */
	ldctl	r0, nspseg
	ldctl	r1, nspoff
	pushl	@rr14, rr0		! save user SP (seg:off)
	pushl	@rr14, rr8
	pushl	@rr14, rr10		! includes udata ptr RR10
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

	/* Swap user memory if needed (for fork copy-on-write) */
	clr	r4
	clr	r5			! death = 0
	pushl	@rr14, rr4		! arg 2: death
	pushl	@rr14, rr2		! arg 1: ptptr p
	call	_pagemap_switch
	addl	rr14, #8		! clean args

	/* Reload rr2 (p) and rr10 — pagemap_switch may have clobbered them */
	ldl	rr10, _udata_shadow
	ldl	rr2, rr10(#U_DATA__U_PTAB)

	/* Restore kernel SP */
	ldl	rr14, rr10(#U_DATA__U_SP)

	/* Mark process as running */
	ldb	(0x82000000+P_TAB__P_STATUS_OFFSET)(r3), #P_RUNNING

	/* Restore callee-saved registers */
	popl	rr12, @rr14
	popl	rr10, @rr14		! restores RR10 (udata ptr) from saved
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
 *	Strategy: save registers like switchout does, then copy
 *	the parent's entire udata+stack to the child. The child's
 *	stack is an exact copy of the parent's, including the
 *	switchout-style register save frame. When the child is
 *	later scheduled by switchin, it will restore the registers,
 *	return through the same call chain as the parent, and
 *	dofork returns 0 (because switchin always returns 0).
 *
 *	The parent gets the child PID from dofork's return value.
 *	The child gets 0 from switchin's return value.
 */
_dofork:
	/*
	 * Save callee-saved registers exactly like switchout does.
	 * This creates the frame that switchin will pop.
	 */
	ldctl	r0, nspseg
	ldctl	r1, nspoff
	pushl	@rr14, rr0		! user SP
	pushl	@rr14, rr8
	pushl	@rr14, rr10		! udata ptr
	pushl	@rr14, rr12

	/* Save this stack pointer in parent's udata */
	ldl	rr10(#U_DATA__U_SP), rr14

	/* Get child p_tab from original arg (adjusted for 4 pushes = +16) */
	ldl	rr2, rr14(#20)		! child p_tab

	/* Get child udata pointer */
	ldl	rr4, rr2(#P_TAB__P_UDATA_OFFSET)

	/*
	 * Copy parent udata block to child (UBLOCK_SIZE bytes).
	 * This copies everything: the u_data struct AND the kernel stack
	 * including the register save frame we just created.
	 * Source = rr10 (parent udata), dest = rr4 (child udata).
	 */
	pushl	@rr14, rr2		! save child p_tab
	ldl	rr8, rr10		! rr8 = source (parent udata)
	ldl	rr12, rr4		! rr12 = dest (child udata)
	ld	r2, #UBLOCK_SIZE
_copy_udata:
	ldb	rh0, @rr8
	ldb	@rr12, rh0
	inc	r9, #1
	inc	r13, #1
	dec	r2, #1
	jr	nz, _copy_udata

	/*
	 * The child's u_sp now points into the PARENT's stack (because
	 * we copied u_sp as-is). Fix it to point to the same offset
	 * within the CHILD's udata block.
	 *
	 * child_u_sp = child_udata + (parent_u_sp - parent_udata)
	 */
	popl	rr2, @rr14		! child p_tab
	pushl	@rr14, rr2		! save again
	ldl	rr4, rr2(#P_TAB__P_UDATA_OFFSET)	! child udata
	ldl	rr8, rr10(#U_DATA__U_SP)	! parent u_sp
	! offset = parent_u_sp - parent_udata (just the offset difference)
	ld	r0, r9			! parent SP offset
	sub	r0, r11			! minus parent udata offset = delta
	ld	r1, r5			! child udata offset
	add	r1, r0			! child udata offset + delta
	ld	r0, r4			! child udata segment
	! rr0 = child's u_sp
	ldl	rr4(#U_DATA__U_SP), rr0

	/*
	 * Patch the saved rr10 in the child's switchout frame.
	 * The frame has [rr12][rr10][rr8][rr0][retaddr] growing up.
	 * rr10 is at u_sp + 4. It currently has the parent's udata
	 * pointer; fix it to the child's.
	 */
	ldl	rr8, rr0		! rr8 = child u_sp
	ldl	rr8(#4), rr4		! store child udata ptr at u_sp+4

	/*
	 * Call makeproc(child_ptab, child_udata)
	 */
	popl	rr2, @rr14		! child p_tab
	pushl	@rr14, rr2		! save again
	ldl	rr4, rr2(#P_TAB__P_UDATA_OFFSET)
	pushl	@rr14, rr4		! arg 2: child udata
	pushl	@rr14, rr2		! arg 1: child p_tab
	call	_makeproc
	addl	rr14, #8		! clean args

	/* Reload parent udata pointer */
	ldl	rr10, _udata_shadow

	/* Get child PID */
	popl	rr2, @rr14		! child p_tab
	ld	r2, rr2(#P_TAB__P_PID_OFFSET)
	pushl	@rr14, rr2		! save PID

	/* Clear child's u_insys so it returns to user mode */
	! (child udata already has a copy, but clear it explicitly)

	/* Restore our saved registers (same as switchin does) */
	popl	rr2, @rr14		! get saved PID into r2
	popl	rr12, @rr14
	popl	rr10, @rr14
	popl	rr8, @rr14
	popl	rr0, @rr14		! user SP
	ldctl	nspseg, r0
	ldctl	nspoff, r1

	clr	_runticks
	! r2 = child PID (saved earlier)
	ret
