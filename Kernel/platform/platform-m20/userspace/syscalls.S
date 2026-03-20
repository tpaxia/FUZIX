! Z8001 FUZIX syscall wrappers
!
! Kernel SC convention (with 32-bit arg_t):
!   R1       = syscall number (low byte)
!   RR2      = argn (32-bit: R2=high, R3=low)
!   RR4      = argn1 (32-bit: R4=high, R5=low)
!   RR6      = argn2 (32-bit: R6=high, R7=low)
!   Return in RR2 (R2:R3)
!
! C calling convention (stack-based, no -mregparms):
!   Args on stack at rr14(#4), rr14(#6/8), etc.
!   Return in r2 (16-bit) or rr2 (32-bit)

	.segm
	.text

! void _exit(int status)
	.global	__exit
__exit:
	ld	r1, #0			! syscall 0 = _exit
	clr	r2
	ld	r3, rr14(#4)		! status (16-bit → rr2 = 0:status)
	sc	#0
	halt

! int write(int fd, const void *buf, int count)
	.global	_write
_write:
	ld	r1, #4			! syscall 4 = write
	clr	r2
	ld	r3, rr14(#4)		! fd (16-bit → rr2 = 0:fd)
	ldl	rr4, rr14(#6)		! buf (32-bit segmented ptr → rr4)
	clr	r6
	ld	r7, rr14(#10)		! count (16-bit → rr6 = 0:count)
	sc	#0
	ret

! int read(int fd, void *buf, int count)
	.global	_read
_read:
	ld	r1, #3			! syscall 3 = read
	clr	r2
	ld	r3, rr14(#4)		! fd
	ldl	rr4, rr14(#6)		! buf
	clr	r6
	ld	r7, rr14(#10)		! count
	sc	#0
	ret
