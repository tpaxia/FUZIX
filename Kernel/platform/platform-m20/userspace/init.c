/* Minimal FUZIX /init for Z8001
 * Tests: open, write, read, fork, signal delivery
 */

extern int open(const char *path, int flags);
extern int write(int fd, const void *buf, int count);
extern int read(int fd, void *buf, int count);
extern int fork(void);
extern int getpid(void);
extern void *signal(int sig, void *handler);
extern int kill(int pid, int sig);
extern void _exit(int status);

#define SIGUSR1 10

static char ttydev[] = "/dev/tty1";
static char banner[] = "[init]\n";
static char sig_msg[] = "SIG!\n";
static char ok_msg[] = "ok\n";
static char nl[] = "\n# ";

static volatile int got_sig;

void sighandler(int sig)
{
	got_sig = sig;
	write(1, sig_msg, 5);
}

int main(void)
{
	char c;
	int pid;

	open(ttydev, 2);	/* fd 0 */
	open(ttydev, 2);	/* fd 1 */
	open(ttydev, 2);	/* fd 2 */

	write(1, banner, 7);

	/* Test signal delivery */
	if (signal(SIGUSR1, (void *)sighandler) == (void *)-1)
		write(1, "SE\n", 3);
	else
		write(1, "SO\n", 3);
	pid = getpid();
	if (pid <= 0)
		write(1, "PE\n", 3);
	else
		write(1, "PO\n", 3);
	kill(pid, SIGUSR1);
	write(1, "K\n", 2);

	/* If we get here, signal was delivered and handler returned */
	if (got_sig == SIGUSR1)
		write(1, ok_msg, 3);

	write(1, nl + 1, 2);	/* "# " */

	for (;;) {
		if (read(0, &c, 1) == 1) {
			if (c == '\n')
				write(1, nl, 3);
		}
	}
}
