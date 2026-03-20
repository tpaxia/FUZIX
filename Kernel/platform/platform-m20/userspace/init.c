/* Minimal FUZIX /init for Z8001
 * Writes a banner then loops echoing characters.
 * Uses the serial terminal (fd 0/1/2 opened by kernel).
 */

extern int write(int fd, const void *buf, int count);
extern int read(int fd, void *buf, int count);
extern void _exit(int status);

static char banner[] = "[init]\n# ";

int main(void)
{
	char c;

	write(1, banner, 10);

	for (;;) {
		if (read(0, &c, 1) == 1) {
			write(1, &c, 1);
			if (c == '\r')
				write(1, "\n# ", 3);
		}
	}
	return 0;
}
