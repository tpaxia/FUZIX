/* Minimal FUZIX /init for Z8001
 * Tests: open, write, read, fork, signal, fork+exec+waitpid
 */

extern int open(const char *path, int flags);
extern int write(int fd, const void *buf, int count);
extern int read(int fd, void *buf, int count);
extern int fork(void);
extern int getpid(void);
extern void *signal(int sig, void *handler);
extern int kill(int pid, int sig);
extern int execve(const char *path, char *argv[], char *envp[]);
extern int waitpid(int pid, int *status, int options);
extern void _exit(int status);

#define SIGUSR1 10
#define NULL ((void *)0)

static char ttydev[] = "/dev/tty1";
static char banner[] = "[init]\n";
static char nl[] = "\n# ";

int main(void)
{
	char c;
	int pid, status;
	static char hello_path[] = "/bin/hello";
	char *argv[2];
	char *envp[1];

	argv[0] = hello_path;
	argv[1] = 0;
	envp[0] = 0;

	open(ttydev, 2);	/* fd 0 */
	open(ttydev, 2);	/* fd 1 */
	open(ttydev, 2);	/* fd 2 */

	write(1, banner, 7);

	/* Test fork + exec */
	pid = fork();
	if (pid == 0) {
		/* Child: exec /bin/hello */
		int r = execve("/bin/hello", argv, envp);
		/* If exec fails, r is -1 */
		write(1, "EF\n", 3);
		_exit(1);
	}
	/* Parent: wait for child */
	write(1, "W\n", 2);
	waitpid(pid, &status, 0);
	write(1, "D\n", 2);

	write(1, nl + 1, 2);	/* "# " */

	for (;;) {
		if (read(0, &c, 1) == 1) {
			if (c == '\n')
				write(1, nl, 3);
		}
	}
}
