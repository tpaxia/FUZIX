! Z8001 FUZIX user-space crt0
!
! Binary layout (a.out flat):
!   File: [64-byte header] [text section]
!   Memory after exec: [VDSO 0x00-0x0F] [gap 0x10-0x1F] [text @ 0x20+]
!
! The exec loader reads a_text - 0x20 bytes from the file and
! places them at u_codebase + 0x20. Code at text[0] ends up at
! u_codebase + 0x20. So a_entry = 0x20 for entry at text[0].
!
! Stack is set up by the kernel. On entry, the stack contains:
!   SP+0: argc (word)
!   SP+2: argv pointer (long)
!   SP+6: envp pointer (long)

	.segm
	.text
	.global	_start
	.global	___main

! Entry point — code starts at text[0], loaded at u_codebase + 0x20
_start:
	! Get argc, argv, envp from stack
	ld	r2, @rr14		! argc
	ldl	rr4, rr14(#2)		! argv
	! Call main(argc, argv)
	! Push args on stack (right to left)
	pushl	@rr14, rr4		! argv
	push	@rr14, r2		! argc
	call	_main
	! Clean stack
	addl	rr14, #6

	! main returned — _exit(retval)
	! retval in r2
	ld	r3, r2			! status = main return
	ld	r1, #0			! syscall 0 = _exit
	sc	#0
	halt

! GCC constructor stub
___main:
	ret
