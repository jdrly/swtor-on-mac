// setsid-exec [--daemon] PROGRAM [ARGS...]
//
// Runs PROGRAM in a new session, out of reach of signals to the SWTOR launcher's process
// group. (The wrapper's fallback for starting the engine's wineserver when hold-launcher
// --start-session can't.)
// A plain binary instead of `perl -e setsid`: macOS strips DYLD_* variables when it
// starts SIP-protected system binaries like /usr/bin/perl, and Wine needs them.
//
// default   setsid() + exec, with every fd but stdio closed first (a wineserver outlives its
//           caller and must not keep the launcher's or mac_wine's pipes and sockets open).
//           If setsid() fails (we are a process-group leader), fork: the child gets the
//           session and runs PROGRAM, we wait for it.
// --daemon  fully detach, like a daemon: fork, new session, fork again, so PROGRAM
//           ends up an orphan outside the launcher's process tree and group, with
//           stdin/stdout on /dev/null and stderr on $SWTOR_GAME_STDERR (or /dev/null).
//           This process keeps the launcher's stdio pipe open and stays until
//           PROGRAM exits or SWTOR_DETACH_WAIT seconds (default 45) pass: the
//           launcher only shuts down once that pipe closes (or after its own 30 s
//           timeout), and the game needs the launcher during startup (login handoff);
//           it quits within a second if the launcher is already gone.
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

// SWTOR_SETSID_LOG=path: append what happened (diagnostics only)
static void logf_(const char *fmt, ...)
{
    const char *path = getenv("SWTOR_SETSID_LOG");
    FILE *f = path ? fopen(path, "a") : NULL;
    if (!f) return;
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    fprintf(f, "%ld.%03ld pid=%d ppid=%d pgid=%d ", (long)ts.tv_sec, ts.tv_nsec / 1000000,
            getpid(), getppid(), getpgrp());
    va_list ap;
    va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);
    fputc('\n', f);
    fclose(f);
}

static int run(char **argv)
{
    execv(argv[0], argv);
    perror(argv[0]);
    return 127;
}

static int wait_status(pid_t pid)
{
    int status = 0;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR)
        ;
    return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
}

int main(int argc, char **argv)
{
    int daemon = argc > 1 && !strcmp(argv[1], "--daemon");
    char **prog = argv + 1 + daemon;
    if (!*prog) {
        fprintf(stderr, "usage: setsid-exec [--daemon] PROGRAM [ARGS...]\n");
        return 2;
    }
    logf_("start%s %s", daemon ? " --daemon" : "", prog[0]);

    if (daemon) {
        int fds[2];
        if (pipe(fds) < 0) { perror("pipe"); return run(prog); }
        pid_t child = fork();
        if (child < 0) { perror("fork"); return run(prog); }
        if (child > 0) {
            close(fds[1]);
            pid_t game = 0;
            if (read(fds[0], &game, sizeof(game)) != sizeof(game)) game = 0;
            close(fds[0]);
            int st = wait_status(child);  // the middle process exits immediately
            logf_("detached (middle %d exited %d, program pid %d)", child, st, game);
            const char *w = getenv("SWTOR_DETACH_WAIT");
            int limit = w ? atoi(w) : 45, waited = 0;
            while (game > 0 && waited < limit && (kill(game, 0) == 0 || errno == EPERM)) {
                sleep(1);
                waited++;
            }
            logf_("stopped waiting after %ds (program %s)", waited,
                  game > 0 && kill(game, 0) == 0 ? "still running" : "gone");
            return 0;
        }
        close(fds[0]);
        setsid();
        pid_t grandchild = fork();
        if (grandchild < 0) _exit(run(prog));
        if (grandchild > 0) {
            ssize_t n = write(fds[1], &grandchild, sizeof(grandchild));
            (void)n;
            _exit(0);
        }
        close(fds[1]);
        int devnull = open("/dev/null", O_RDWR);
        const char *errpath = getenv("SWTOR_GAME_STDERR");
        int errfd = errpath ? open(errpath, O_WRONLY | O_CREAT | O_TRUNC, 0644) : -1;
        if (devnull >= 0) { dup2(devnull, 0); dup2(devnull, 1); }
        dup2(errfd >= 0 ? errfd : devnull, 2);
        logf_("daemon running %s", prog[0]);
        _exit(run(prog));
    }

    for (int fd = 3; fd < 1024; fd++) close(fd);
    if (setsid() < 0) {
        logf_("setsid failed (group leader): forking");
        pid_t pid = fork();
        if (pid == 0) {
            setsid();
            _exit(run(prog));
        }
        if (pid > 0) {
            int st = wait_status(pid);
            logf_("child %d ended with %d", pid, st);
            return st;
        }
        perror("fork");  // fall through: run without a new session
    }
    return run(prog);
}
