/*
 *	Olivetti M20 TTY driver
 *
 *	TTY 1: Serial port (i8251A at 0x00C1/0x00C3)
 *
 *	Baud rate set via i8253 PIT counter 0.
 */

#include <kernel.h>
#include <kdata.h>
#include <printf.h>
#include <tty.h>
#include <devtty.h>

/* i8251A port addresses */
#define TTY_DATA	0x00C1
#define TTY_CTRL	0x00C3

/* i8251A status bits */
#define USART_TXRDY	0x01
#define USART_RXRDY	0x02
#define USART_TXEMPTY	0x04

static uint8_t tbuf1[TTYSIZ];
static uint8_t tbuf2[TTYSIZ];

struct s_queue ttyinq[NUM_DEV_TTY + 1] = {
	{ NULL, NULL, NULL, 0, 0, 0 },		/* ttyinq[0] unused */
	{ tbuf1, tbuf1, tbuf1, TTYSIZ, 0, TTYSIZ / 2 },	/* TTY 1: serial */
};

tcflag_t termios_mask[NUM_DEV_TTY + 1] = {
	0,
	_CSYS,
};

/* Output a character to the given TTY */
void tty_putc(uint_fast8_t minor, uint_fast8_t c)
{
	/* Wait for TX ready */
	while (!(in(TTY_CTRL) & USART_TXEMPTY))
		;
	out(TTY_DATA, c);
}

void tty_sleeping(uint_fast8_t minor)
{
}

ttyready_t tty_writeready(uint_fast8_t minor)
{
	if (in(TTY_CTRL) & USART_TXEMPTY)
		return TTY_READY_NOW;
	return TTY_READY_SOON;
}

void tty_data_consumed(uint_fast8_t minor)
{
}

int tty_carrier(uint_fast8_t minor)
{
	return 1;
}

void tty_setup(uint_fast8_t minor, uint_fast8_t flags)
{
	/* TODO: configure baud rate via i8253 counter 0 */
}

/*
 *	Poll for incoming serial data.
 *	Called from the timer interrupt.
 */
void tty_interrupt(void)
{
	uint8_t st;

	st = in(TTY_CTRL);
	if (st & USART_RXRDY)
		tty_inproc(1, in(TTY_DATA));
}
