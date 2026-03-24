/* Minimal FUZIX /init for Z8001
 * Writes a banner then loops echoing characters.
 * Uses the serial terminal (fd 0/1/2 opened by kernel).
 */

extern int open(const char *path, int flags);
extern int write(int fd, const void *buf, int count);
extern int read(int fd, void *buf, int count);
extern int fork(void);
extern void _exit(int status);

static char banner[] = "[init]\n";
static char ttydev[] = "/dev/tty1";
static char parent_msg[] = "parent\n";
static char child_msg[] = "child\n";
static char nl[] = "\n# ";

int main(void)
{
	char c;
	int pid;

	open(ttydev, 2);	/* fd 0 = stdin, O_RDWR */
	open(ttydev, 2);	/* fd 1 = stdout */
	open(ttydev, 2);	/* fd 2 = stderr */

	write(1, banner, 7);

	pid = fork();
	if (pid) {
		write(1, parent_msg, 7);
	} else {
		write(1, child_msg, 6);
	}

	write(1, nl + 1, 2);	/* "# " */

	for (;;) {
		if (read(0, &c, 1) == 1) {
			if (c == '\n')
				write(1, nl, 3);
		}
	}
}
