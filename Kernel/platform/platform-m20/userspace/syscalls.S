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
!
! Syscall numbers from Kernel/include/syscall_name.h:
!   0 = _exit, 1 = open, 2 = close, 7 = read, 8 = write

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

! int open(const char *path, int flags)
	.global	_open
_open:
	ld	r1, #1			! syscall 1 = open
	ldl	rr2, rr14(#4)		! path (32-bit segmented ptr → rr2)
	clr	r4
	ld	r5, rr14(#8)		! flags (16-bit → rr4 = 0:flags)
	clr	r6
	clr	r7			! mode = 0
	sc	#0
	ret

! int read(int fd, void *buf, int count)
	.global	_read
_read:
	ld	r1, #7			! syscall 7 = read
	clr	r2
	ld	r3, rr14(#4)		! fd
	ldl	rr4, rr14(#6)		! buf
	clr	r6
	ld	r7, rr14(#10)		! count
	sc	#0
	ret

! int fork(void)
	.global	_fork
_fork:
	ld	r1, #32			! syscall 32 = _fork
	sc	#0
	ret

! int write(int fd, const void *buf, int count)
	.global	_write
_write:
	ld	r1, #8			! syscall 8 = write
	clr	r2
	ld	r3, rr14(#4)		! fd (16-bit → rr2 = 0:fd)
	ldl	rr4, rr14(#6)		! buf (32-bit segmented ptr → rr4)
	clr	r6
	ld	r7, rr14(#10)		! count (16-bit → rr6 = 0:count)
	sc	#0
	ret
