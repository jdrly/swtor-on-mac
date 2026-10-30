// hold-launcher --start-session WINESERVER_LOG
// hold-launcher --run-game HOLD_LOG NOTE PROGRAM [ARGS...]
// hold-launcher --reap
// hold-launcher --paths
// hold-launcher GAME_PID   (0.1.1's wrappers: nothing to do any more)
//
// The Wine session helper of the wrapper (src/wine-wrapper.sh), next to Broadsword's real
// preloaders in bin-real. (The name is 0.1.1's, when it held the launcher: SIGSTOP while the
// game ran, because the launcher's exit seemed to take the engine's wineserver with it. It
// doesn't: the launcher quits ~30 s after starting the game, as with Broadsword's own Wine, and
// macOS spares the game and the Wine processes then. See launcher-lifecycle/REPORT.md.)
//
// Environment, from the wrapper: SWTOR_ENGINE (SWTOR on Mac's Wine engine), WINEPREFIX (its
// prefix), and whatever Wine reads (WINEMSYNC, WINEDEBUG, DYLD_FALLBACK_LIBRARY_PATH, ...).
//
// A Wine session of a prefix is its wineserver and Wine's system processes (services.exe,
// winedevice.exe, plugplay.exe, svchost.exe, rpcss.exe), which the session's first Wine
// process starts through `wineboot --init`. They inherit that process's stdout and stderr: when
// it is a `reg` call of Broadsword's mac_wine, mac_wine's pipe stays open for as long as the
// session lives, and mac_wine (Rust's Command::output, which reads to EOF) waits for that.
//
// --start-session: makes sure a session of WINEPREFIX runs, started so that it holds nothing
// of the caller's: under a lock per prefix (concurrent Wine starts wait for each other), first
// --reap, then the engine's wineserver -p10 (it ends 10 s after the last Wine process; "-p 10",
// with a space, would make it persistent forever: Wine's getopt takes the value only attached)
// in its own session with stdin/stdout on /dev/null, stderr appended to WINESERVER_LOG and every
// other fd closed. If that started a new server (exit 0; 2 = one already runs), a bootstrap Wine
// call (reg query, stdio on /dev/null, own session, nothing else open) brings up Wine's system
// processes, so they inherit nothing either. Logs one line to stderr. Exit 0, 3 if it ended
// leftover Wine processes first (the wrapper then looks for why: macOS may have ended the last
// session when the launcher quit, see som.sh btm-check), or 1 if no wineserver could be started
// (the wrapper then starts one itself).
//
// --run-game: runs the game, PROGRAM ARGS (the engine's wine with the launcher's command), as
// this process's child with everything of this process (its stdio and other fds, its process
// group, its environment) and keeps none of those fds itself (stdio on /dev/null, the rest
// closed: what the game closes is closed), passes TERM, INT, HUP and QUIT on to it, and when it ends appends
// one line to HOLD_LOG: how long it ran and how it ended (exit code or signal), with NOTE (the
// game's language). Then this process ends as the game did (its exit code; TERM, INT, HUP and
// KILL raised again, other signals as exit 128 + signal: no crash report of its own), so the
// launcher sees what it would have seen. It ends with the game: nothing of it stays. The
// wrapper execs it in its own place, so the launcher's child is this process for the session.
//
// --reap: ends leftover Wine processes of WINEPREFIX's session: processes of SWTOR_ENGINE that
// belong to it (they map files from its server directory /tmp/.wine-<uid>/server-<dev>-<ino>,
// or their working directory is in the prefix's drive_c) while no wineserver of it runs (none
// holds the lock in that directory), each logged to stderr. Other prefixes' Wine processes
// are never touched. Without WINEPREFIX: 0.1.1's rule (any process of the engine while no
// wineserver of the engine runs).
//
// --paths: "<pid> <executable>" for every process whose executable can be read (the real
// file, from proc_pidpath), for som.sh: Wine 11 rewrites argv[0], so ps shows C:\...\name.exe
// instead of the program for its processes.
//
// No AppKit: a process with an NSApplication counts for macOS as an app of the launcher that
// started it, and the Dock's Quit on the launcher kills those (0.1.1's hold-launcher, cut off
// mid-cleanup).
//
// build: clang -O2 -arch x86_64 -arch arm64 -o hold-launcher hold_launcher.c
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <libproc.h>
#include <limits.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/proc_info.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static void vlogf_(FILE *f, const char *fmt, va_list ap)
{
    char ts[32];
    time_t now = time(NULL);
    strftime(ts, sizeof(ts), "%Y-%m-%d %H:%M:%S", localtime(&now));
    fprintf(f, "%s [%d] ", ts, getpid());
    vfprintf(f, fmt, ap);
    fputc('\n', f);
}

// log lines go to stderr; the wrapper points it at ~/Library/Logs/SWTOR on Mac/hold.log
static void logf_(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    vlogf_(stderr, fmt, ap);
    va_end(ap);
}

static void logf_to(FILE *f, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    vlogf_(f, fmt, ap);
    va_end(ap);
}

static long long now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000LL + ts.tv_nsec / 1000000;
}

static int bsdinfo(pid_t pid, struct proc_bsdinfo *bi)
{
    return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, bi, sizeof(*bi)) == sizeof(*bi);
}

// Everything except stdio and KEEP: nothing of the caller's (the launcher's or mac_wine's
// pipes and sockets) may stay open in a process that outlives it
static void close_inherited_fds(int keep)
{
    int size = proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, NULL, 0);
    struct proc_fdinfo *fds = size > 0 ? malloc(size) : NULL;
    if (fds) size = proc_pidinfo(getpid(), PROC_PIDLISTFDS, 0, fds, size);
    if (!fds || size <= 0) {
        for (int fd = 3; fd < 1024; fd++)
            if (fd != keep) close(fd);
        free(fds);
        return;
    }
    for (int i = 0; i < size / (int)sizeof(*fds); i++)
        if (fds[i].proc_fd > 2 && fds[i].proc_fd != keep) close(fds[i].proc_fd);
    free(fds);
}

// The engine's processes at this moment. Sets *SERVER to a live wineserver of the engine (0:
// none) and puts up to MAX of the others into PIDS; returns how many. Wine runs them from the
// engine's loader or from hard links of it (CrossOver's winetemp-<inode>-.../<name>.exe), so
// they are matched by that file: its path, or the same inode. The loader is
// lib/wine/x86_64-unix/wine (CrossOver 26), or bin/wine-preloader where there is one (the
// CrossOver 24 engine of SWTOR on Mac 0.0.x). Nothing else matches (the game's Game Mode copy
// in SWTOR.app is an APFS clone, another inode; this process neither).
static int engine_procs(pid_t *server, pid_t *pids, int max)
{
    *server = 0;
    const char *engine = getenv("SWTOR_ENGINE");
    if (!engine || !*engine) return 0;
    char pre[1024], srv[1024], srv2[1024];
    snprintf(pre, sizeof(pre), "%s/bin/wine-preloader", engine);
    snprintf(srv, sizeof(srv), "%s/bin/wineserver", engine);
    // (a wineserver Wine starts itself runs from <engine>/lib/wine/../../bin/wineserver)
    snprintf(srv2, sizeof(srv2), "%s/lib/wine/../../bin/wineserver", engine);
    struct stat ps;
    int have_ino = stat(pre, &ps) == 0;
    if (!have_ino) {
        snprintf(pre, sizeof(pre), "%s/lib/wine/x86_64-unix/wine", engine);
        have_ino = stat(pre, &ps) == 0;
    }
    int n = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    pid_t *all = n > 0 ? malloc(n) : NULL;
    if (!all) return 0;
    n = proc_listpids(PROC_ALL_PIDS, 0, all, n) / (int)sizeof(pid_t);
    int found = 0;
    for (int i = 0; i < n; i++) {
        char path[PROC_PIDPATHINFO_MAXSIZE];
        struct stat st;
        if (all[i] <= 1 || all[i] == getpid() || proc_pidpath(all[i], path, sizeof(path)) <= 0) continue;
        if (!strcmp(path, srv) || !strcmp(path, srv2)) {
            *server = all[i];
            continue;
        }
        // (only winetemp paths are looked at: no stat() of other programs' files)
        if (strcmp(path, pre) &&
            !(have_ino && strstr(path, "/winetemp-") && stat(path, &st) == 0 &&
              st.st_dev == ps.st_dev && st.st_ino == ps.st_ino))
            continue;
        if (found < max) pids[found] = all[i];
        found++;
    }
    free(all);
    return found < max ? found : max;
}

// The prefix's session, as Wine names it: its server directory /tmp/.wine-<uid>/server-<dev>-<ino>
// (server/request.c), KEY the part to look for in paths ("/.wine-<uid>/server-<dev>-<ino>/":
// macOS shows /private/tmp), DRIVE_C the prefix's drive_c with a trailing slash (real path).
struct session {
    char dir[PATH_MAX], key[128], drive_c[PATH_MAX];
    dev_t dev;
    ino_t ino;
};

static int session_of(const char *prefix, struct session *s)
{
    struct stat st;
    char real[PATH_MAX];
    if (!prefix || !*prefix || stat(prefix, &st) != 0 || !realpath(prefix, real)) return 0;
    s->dev = st.st_dev;
    s->ino = st.st_ino;
    snprintf(s->key, sizeof(s->key), "/.wine-%u/server-%llx-%llx/", getuid(),
             (unsigned long long)st.st_dev, (unsigned long long)st.st_ino);
    snprintf(s->dir, sizeof(s->dir), "/tmp%.*s", (int)strlen(s->key) - 1, s->key);
    snprintf(s->drive_c, sizeof(s->drive_c), "%s/drive_c/", real);
    return 1;
}

// The pid of the session's wineserver (it holds the lock in the server directory), or 0
static pid_t session_server(const struct session *s)
{
    char lock[PATH_MAX + 8];
    snprintf(lock, sizeof(lock), "%s/lock", s->dir);
    int fd = open(lock, O_RDONLY);
    if (fd < 0) return 0;
    struct flock fl = { .l_type = F_WRLCK, .l_whence = SEEK_SET, .l_start = 0, .l_len = 1 };
    pid_t holder = fcntl(fd, F_GETLK, &fl) == 0 && fl.l_type != F_UNLCK ? fl.l_pid : 0;
    close(fd);
    return holder;
}

// Does PID belong to the session: its working directory in the prefix's drive_c (Wine's
// system processes: C:\windows), or a file of the server directory mapped (every Wine process
// of the session maps its tmpmap-* files)?
static int in_session(pid_t pid, const struct session *s)
{
    struct proc_vnodepathinfo vpi;
    if (proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vpi, sizeof(vpi)) == sizeof(vpi) &&
        !strncmp(vpi.pvi_cdir.vip_path, s->drive_c, strlen(s->drive_c)))
        return 1;
    struct proc_regionwithpathinfo rp;
    uint64_t addr = 0;
    for (int i = 0; i < 100000; i++) {
#ifdef PROC_PIDREGIONPATHINFO2
        int r = proc_pidinfo(pid, PROC_PIDREGIONPATHINFO2, addr, &rp, sizeof(rp));  // file-backed only
#else
        int r = proc_pidinfo(pid, PROC_PIDREGIONPATHINFO, addr, &rp, sizeof(rp));
#endif
        if (r != sizeof(rp)) break;
        if (rp.prp_vip.vip_path[0] && strstr(rp.prp_vip.vip_path, s->key)) return 1;
        uint64_t next = rp.prp_prinfo.pri_address + rp.prp_prinfo.pri_size;
        if (next <= addr) break;
        addr = next;
    }
    return 0;
}

// 1 if it ended PID
static int end_leftover(pid_t pid)
{
    char name[2 * MAXCOMLEN + 1] = "?";
    struct proc_bsdinfo bi;
    int ppid = bsdinfo(pid, &bi) ? (int)bi.pbi_ppid : -1;
    proc_name(pid, name, sizeof(name));
    if (kill(pid, SIGKILL) == 0) {
        logf_("ended leftover Wine process %d (%s, parent %d)", pid, name, ppid);
        return 1;
    }
    if (errno != ESRCH)
        logf_("could not end leftover Wine process %d (%s): %s", pid, name, strerror(errno));
    return 0;
}

// 0.1.1's rule, without a prefix: processes of the engine while no wineserver of it runs.
// Returns how many it ended.
static int reap_engine(int quiet)
{
    pid_t server, again, pids[256];
    int n = engine_procs(&server, pids, 256);
    if (server) {
        if (!quiet) logf_("Wine session running (wineserver %d): leaving the engine's processes alone", server);
        return 0;
    }
    if (n == 0) {
        if (!quiet) logf_("no leftover Wine processes of the engine");
        return 0;
    }
    // once more right before: a new session (a game start) may have begun in between
    engine_procs(&again, NULL, 0);
    if (again) return 0;
    int ended = 0;
    for (int i = 0; i < n; i++) ended += end_leftover(pids[i]);
    return ended;
}

// Leftovers of the prefix's session: its Wine processes while no wineserver of it runs.
// Without a server there is no session they could belong to (every Wine start brings up its
// server first), so they only tick on: e.g. system processes that wait (msync) forever after
// their server was killed. All of them end (SIGKILL), each logged; with a server running, none.
// QUIET: no log line when there is nothing to do. Returns how many it ended.
static int reap(int quiet)
{
    struct session s;
    const char *prefix = getenv("WINEPREFIX");
    if (!prefix || !*prefix) return reap_engine(quiet);
    if (!session_of(prefix, &s)) {
        if (!quiet) logf_("no prefix at %s: nothing to end", prefix);
        return 0;
    }
    pid_t server = session_server(&s), dummy, pids[256], mine[256];
    if (server) {
        if (!quiet) logf_("Wine session running (wineserver %d): leaving its processes alone", server);
        return 0;
    }
    int n = engine_procs(&dummy, pids, 256), m = 0;
    for (int i = 0; i < n; i++)
        if (in_session(pids[i], &s)) mine[m++] = pids[i];
    if (m == 0) {
        if (!quiet) logf_("no leftover Wine processes of the prefix");
        return 0;
    }
    // once more right before: a new session (a game start) may have begun in between
    if (session_server(&s)) return 0;
    int ended = 0;
    for (int i = 0; i < m; i++) ended += end_leftover(mine[i]);
    return ended;
}

// Runs PATH (ARGV) in its own session with stdin/stdout on /dev/null, stderr on ERRPATH
// (appended; NULL: /dev/null) and nothing else open; TIMEOUT s at most (SIGKILL, survives exec).
// Returns its wait status, or -1.
static int run_detached(const char *path, char *const argv[], const char *errpath, int timeout)
{
    pid_t pid = fork();
    if (pid == 0) {
        setsid();
        close_inherited_fds(-1);
        int null = open("/dev/null", O_RDWR);
        int err = errpath ? open(errpath, O_WRONLY | O_CREAT | O_APPEND, 0644) : -1;
        dup2(null, 0);
        dup2(null, 1);
        dup2(err >= 0 ? err : null, 2);
        if (null > 2) close(null);
        if (err > 2) close(err);
        // (a stuck call must not keep the Wine start waiting: SIGALRM ends it)
        if (timeout > 0) alarm(timeout);
        execv(path, argv);
        _exit(127);
    }
    if (pid < 0) return -1;
    int st = 0;
    while (waitpid(pid, &st, 0) < 0)
        if (errno != EINTR) return -1;
    return st;
}

static void on_alarm(int sig) { (void)sig; }

static int start_session(const char *wslog)
{
    const char *engine = getenv("SWTOR_ENGINE");
    const char *prefix = getenv("WINEPREFIX");
    struct session s;
    if (!engine || !*engine || !session_of(prefix, &s)) {
        logf_("start-session: no engine or prefix (SWTOR_ENGINE, WINEPREFIX)");
        return 1;
    }
    // One start at a time per prefix: mac_wine starts two Wine calls at once, and only one may
    // bring the session up (the other would be its first Wine process, with mac_wine's pipe).
    // Next to the server directory, not in the prefix; at most 150 s.
    char lockdir[PATH_MAX], lock[PATH_MAX + 64];
    snprintf(lockdir, sizeof(lockdir), "/tmp/.wine-%u", getuid());
    mkdir(lockdir, 0700);
    snprintf(lock, sizeof(lock), "%s/swtor-on-mac-%llx-%llx.lock", lockdir,
             (unsigned long long)s.dev, (unsigned long long)s.ino);
    int lfd = open(lock, O_RDWR | O_CREAT, 0600);
    if (lfd >= 0) {
        struct sigaction sa = { .sa_handler = on_alarm };  // (no SA_RESTART: flock returns EINTR)
        sigaction(SIGALRM, &sa, NULL);
        alarm(150);
        if (flock(lfd, LOCK_EX) != 0) logf_("start-session: lock: %s, going on without it", strerror(errno));
        alarm(0);
    }

    int reaped = reap(1);
    char server[PATH_MAX], wine[PATH_MAX];
    snprintf(server, sizeof(server), "%s/bin/wineserver", engine);
    snprintf(wine, sizeof(wine), "%s/bin/wine", engine);
    char *sargv[] = { "wineserver", "-p10", NULL };
    int st = run_detached(server, sargv, wslog, 30);
    int code = st >= 0 && WIFEXITED(st) ? WEXITSTATUS(st) : -1;
    int ret = 0;
    if (code == 0) {
        // a new server: its system processes come up now, from a call that holds nothing
        long long t0 = now_ms();
        char *bargv[] = { "wine", "reg", "query", "HKCU\\Software\\Wine", "/v", "SWTORonMacSession", NULL };
        int bst = run_detached(wine, bargv, NULL, 120);
        logf_("Wine session started (wineserver %d, -p10); system processes up in %.1f s (%s)",
              session_server(&s), (now_ms() - t0) / 1000.0,
              bst >= 0 && WIFSIGNALED(bst) ? "bootstrap timed out" : "bootstrap done");
    } else if (code != 2) {
        logf_("start-session: wineserver -p10 failed (%s %d)", code < 0 ? "signal" : "exit",
              code < 0 && st >= 0 && WIFSIGNALED(st) ? WTERMSIG(st) : code);
        ret = 1;
    }
    if (lfd >= 0) close(lfd);  // (releases the lock)
    return ret == 0 && reaped ? 3 : ret;
}

static const int game_signals[] = { SIGTERM, SIGINT, SIGHUP, SIGQUIT };
static volatile pid_t game_pid;

static void pass_on(int sig)
{
    if (game_pid > 0) kill(game_pid, sig);
}

static int run_game(const char *holdlog, const char *note, char **argv)
{
    sigset_t block, old;
    sigemptyset(&block);
    for (size_t i = 0; i < sizeof(game_signals) / sizeof(*game_signals); i++) sigaddset(&block, game_signals[i]);
    // (blocked until the handlers know the game's pid: none is lost in between)
    sigprocmask(SIG_BLOCK, &block, &old);
    long long t0 = now_ms();
    pid_t pid = fork();
    if (pid == 0) {
        sigprocmask(SIG_SETMASK, &old, NULL);
        execv(argv[0], argv);
        _exit(127);
    }
    if (pid < 0) {
        // (no child: the game in this process, as the wrapper ran it before, without the line)
        sigprocmask(SIG_SETMASK, &old, NULL);
        execv(argv[0], argv);
        return 127;
    }
    game_pid = pid;
    // While it waits, this process holds nothing of the caller's: a pipe or socket the game
    // closes ends for its other side as if the game were the launcher's child itself.
    close_inherited_fds(-1);
    int null = open("/dev/null", O_RDWR);
    for (int fd = 0; fd <= 2 && null >= 0; fd++) dup2(null, fd);
    if (null > 2) close(null);
    struct sigaction sa = { .sa_handler = pass_on, .sa_flags = SA_RESTART };
    sigemptyset(&sa.sa_mask);
    for (size_t i = 0; i < sizeof(game_signals) / sizeof(*game_signals); i++) sigaction(game_signals[i], &sa, NULL);
    sigprocmask(SIG_SETMASK, &old, NULL);
    int st = 0;
    while (waitpid(pid, &st, 0) < 0)
        if (errno != EINTR) { st = -1; break; }
    long long s = (now_ms() - t0) / 1000;
    char how[64], name[16] = "?";
    if (st == -1) snprintf(how, sizeof(how), "end unknown (%s)", strerror(errno));
    else if (WIFSIGNALED(st)) {
        // (sys_signame is lower case: "term")
        if (WTERMSIG(st) < NSIG)
            for (int i = 0; sys_signame[WTERMSIG(st)][i] && i < (int)sizeof(name) - 1; i++)
                name[i] = (char)toupper((unsigned char)sys_signame[WTERMSIG(st)][i]), name[i + 1] = 0;
        snprintf(how, sizeof(how), "signal %d (SIG%s)%s", WTERMSIG(st), name, WCOREDUMP(st) ? ", core dumped" : "");
    } else snprintf(how, sizeof(how), "exit code %d", WEXITSTATUS(st));
    FILE *f = fopen(holdlog, "a");
    if (f) {
        logf_to(f, "game ended after %lld:%02lld:%02lld (%s): %s", s / 3600, s / 60 % 60, s % 60, note, how);
        fclose(f);
    }
    if (st != -1 && WIFSIGNALED(st)) {
        int sig = WTERMSIG(st);
        if (sig == SIGTERM || sig == SIGINT || sig == SIGHUP || sig == SIGKILL) {
            signal(sig, SIG_DFL);
            sigset_t one;
            sigemptyset(&one);
            sigaddset(&one, sig);
            sigprocmask(SIG_UNBLOCK, &one, NULL);
            raise(sig);
        }
        return 128 + sig;
    }
    return st == -1 ? 1 : WEXITSTATUS(st);
}

// --paths: every process's real executable, "<pid> <path>" lines
static void print_paths(void)
{
    int n = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    pid_t *all = n > 0 ? malloc(n) : NULL;
    if (!all) return;
    n = proc_listpids(PROC_ALL_PIDS, 0, all, n) / (int)sizeof(pid_t);
    for (int i = 0; i < n; i++) {
        char path[PROC_PIDPATHINFO_MAXSIZE];
        if (all[i] > 0 && proc_pidpath(all[i], path, sizeof(path)) > 0)
            printf("%d %s\n", (int)all[i], path);
    }
    free(all);
}

int main(int argc, char **argv)
{
    if (argc == 3 && !strcmp(argv[1], "--start-session")) return start_session(argv[2]);
    if (argc >= 5 && !strcmp(argv[1], "--run-game")) return run_game(argv[2], argv[3], argv + 4);
    // --reap: end leftover processes of the prefix's session (none if its wineserver runs), at once
    if (argc == 2 && !strcmp(argv[1], "--reap")) {
        reap(1);
        return 0;
    }
    if (argc == 2 && !strcmp(argv[1], "--paths")) {
        print_paths();
        return 0;
    }
    if (argc == 2 && atoi(argv[1]) > 1) {
        logf_("game %s: not holding the launcher (no longer needed)", argv[1]);
        return 0;
    }
    fprintf(stderr, "usage: hold-launcher --start-session WINESERVER_LOG | --run-game HOLD_LOG NOTE PROGRAM [ARGS...] | --reap | --paths\n");
    return 2;
}
