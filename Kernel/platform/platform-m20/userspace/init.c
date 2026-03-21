/* Minimal FUZIX /init for Z8001
 * Writes a banner then loops echoing characters.
 * Uses the serial terminal (fd 0/1/2 opened by kernel).
 */

extern int open(const char *path, int flags);
extern int write(int fd, const void *buf, int count);
extern void _exit(int status);

static char banner[] = "[init]\n";
static char ttydev[] = "/dev/tty1";

int main(void)
{
	open(ttydev, 2);	/* fd 0 = stdin, O_RDWR */
	open(ttydev, 2);	/* fd 1 = stdout */
	open(ttydev, 2);	/* fd 2 = stderr */

	write(1, banner, 7);
	_exit(0);
	return 0;
}
