// hold-launcher GAME_PID
// hold-launcher --reap
// hold-launcher --paths
//
// Freezes the SWTOR launcher (SIGSTOP) while the game runs on another Wine engine
// (SWTOR_ENGINE) and lets it go on (SIGCONT) once the game has exited.
// Why: the launcher quits ~30 s after starting the game, and when it exits the
// engine's wineserver dies too (even in its own session), so the game hangs.
// A stopped launcher cannot quit; resumed after the game, it just finishes its
// shutdown.
//
// GAME_PID is the wrapper's own pid: the wrapper then execs the engine's wine, which becomes
// the game itself or `start.exe /exec swtor.exe` (the exec keeps the pid) and stays until the
// game process exits.
// The launcher is looked up among GAME_PID's ancestors (then its process-group
// leader) by executable path, so nothing else is ever stopped. Not found: log, exit.
//
// Run it in the foreground: it forks a detached child and returns once the launcher
// is stopped, so the game only starts after that. The child gets its own session
// (out of reach of group kills), stdin/stdout on /dev/null, stderr kept as the log,
// every other fd closed (it must not hold the launcher's pipes open). It waits in
// kevent() for the game's exit (EVFILT_PROC NOTE_EXIT): no polling, no CPU.
// It also resumes the launcher if it is told to quit (SIGTERM/SIGINT/SIGHUP/SIGQUIT)
// or kevent() fails, and does nothing if the launcher exited first (pid reuse).
// Once the launcher has quit (within 2 min of the game), it ends the engine's Wine session
// and whatever is left of it (see end_session_after_launcher, reap_leftovers).
//
// --reap: only end leftover Wine processes of SWTOR_ENGINE (processes of the engine while
// no wineserver of it runs), logging each to stderr. The wrapper runs it before it starts
// the engine's wineserver.
//
// --paths: "<pid> <executable>" for every process whose executable can be read (the real
// file, from proc_pidpath), for som.sh: Wine 11 rewrites argv[0], so ps shows C:\...\name.exe
// instead of the program for its processes.
//
// build: clang -O2 -arch x86_64 -arch arm64 -fobjc-arc -framework AppKit \
//          -o hold-launcher hold_launcher.c hide_app.m
#include <errno.h>
#include <fcntl.h>
#include <libproc.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/event.h>
#include <sys/proc.h>
#include <sys/proc_info.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

int hide_app(pid_t pid, double timeout);  // hide_app.m

// executable of the launcher's main process (its CEF helpers are "... Launcher Helper")
#define LAUNCHER_SUFFIX ".app/Contents/MacOS/Star Wars - The Old Republic Launcher"
// Broadsword's Wine helper (registry token, graphics config): its Wine calls go through the
// wrapper too, onto this engine. Only looked at, never signalled.
#define MAC_WINE_SUFFIX ".app/Contents/MacOS/mac_wine"
// after the launcher has quit: how long no wineserver may have come back, and the cap
#define QUIET_MS 3000
#define LINGER_MAX_MS 30000

// log lines go to stderr; the wrapper points it at ~/Library/Logs/SWTOR on Mac/hold.log
static void logf_(const char *fmt, ...)
{
    char ts[32];
    time_t now = time(NULL);
    strftime(ts, sizeof(ts), "%Y-%m-%d %H:%M:%S", localtime(&now));
    fprintf(stderr, "%s [%d] ", ts, getpid());
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
}

static int has_suffix(pid_t pid, const char *suffix)
{
    char path[PROC_PIDPATHINFO_MAXSIZE];
    if (proc_pidpath(pid, path, sizeof(path)) <= 0) return 0;
    size_t n = strlen(path), m = strlen(suffix);
    return n >= m && !strcmp(path + n - m, suffix);
}

static int is_launcher(pid_t pid) { return has_suffix(pid, LAUNCHER_SUFFIX); }

static int bsdinfo(pid_t pid, struct proc_bsdinfo *bi);

// Broadsword's mac_wine processes running now: *IDLE gets those without a Wine call in
// flight; returns those with one (a child that is not a zombie: the wine64 it started, which
// the wrapper turns into this engine's wine with the same pid). A mac_wine can stay long after
// the launcher, idle, with its finished call unreaped.
static int count_mac_wine(int *idle)
{
    *idle = 0;
    int n = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    pid_t *all = n > 0 ? malloc(n) : NULL;
    if (!all) return 0;
    n = proc_listpids(PROC_ALL_PIDS, 0, all, n) / (int)sizeof(pid_t);
    int busy = 0;
    for (int i = 0; i < n; i++) {
        if (all[i] <= 1 || !has_suffix(all[i], MAC_WINE_SUFFIX)) continue;
        pid_t kids[64];
        // (proc_listchildpids returns a count of pids, not bytes)
        int k = proc_listchildpids(all[i], kids, sizeof(kids)), live = 0;
        if (k > 64) k = 64;
        for (int j = 0; j < k && !live; j++) {
            struct proc_bsdinfo bi;
            live = bsdinfo(kids[j], &bi) && bi.pbi_status != SZOMB;
        }
        if (live) busy++; else (*idle)++;
    }
    free(all);
    return busy;
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

// The launcher spawns wine64 directly, but walk a few levels in case something sits
// in between; the game is in the launcher's process group, so try its leader last.
static pid_t find_launcher(pid_t game)
{
    struct proc_bsdinfo bi;
    if (!bsdinfo(game, &bi)) return 0;
    pid_t pgid = bi.pbi_pgid;
    for (int depth = 0; depth < 8 && bi.pbi_ppid > 1; depth++) {
        pid_t p = bi.pbi_ppid;
        if (is_launcher(p)) return p;
        if (!bsdinfo(p, &bi)) break;
    }
    return pgid > 1 && is_launcher(pgid) ? pgid : 0;
}

// Everything except stdio and KEEP: the launcher's pipes must not stay open here
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

// Before letting the launcher go: shut the engine's Wine session down cleanly
// (wineserver -k, with the WINEPREFIX the wrapper exported). Otherwise the launcher's
// exit kills the wineserver and leaves its winedevice.exe orphaned, ticking forever.
// (wineserver -k exits 0 once it has ended a server, 1 if none was running.)
static void stop_wine_session(void)
{
    const char *engine = getenv("SWTOR_ENGINE");
    if (!engine || !getenv("WINEPREFIX")) return;
    char path[1024];
    snprintf(path, sizeof(path), "%s/bin/wineserver", engine);
    pid_t pid = fork();
    if (pid == 0) {
        alarm(15);  // survives exec: a stuck wineserver -k must not keep the launcher stopped
        execl(path, "wineserver", "-k", (char *)NULL);
        _exit(127);
    }
    int st = 0;
    if (pid > 0)
        while (waitpid(pid, &st, 0) < 0 && errno == EINTR)
            ;
    if (pid < 0) logf_("wineserver -k: %s", strerror(errno));
    else if (WIFEXITED(st)) logf_("wineserver -k: exit %d%s", WEXITSTATUS(st), WEXITSTATUS(st) == 1 ? " (no server was running)" : "");
    else logf_("wineserver -k: timed out");
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

// Waits (at most SECONDS, looking once a second) until no wineserver of the engine runs;
// returns the one still running, or 0.
static pid_t wait_no_server(int seconds)
{
    pid_t server;
    for (int i = 0;; i++) {
        engine_procs(&server, NULL, 0);
        if (!server || i >= seconds) return server;
        sleep(1);
    }
}

// Leftovers: processes of the engine while no wineserver of it runs. Without a server there
// is no Wine session they could belong to (every Wine start brings up its server first, the
// wrapper before anything else), so they only tick on: Wine's system processes
// (winedevice.exe, services.exe, ...) of a session whose server is gone, waiting forever on
// msync, whatever their parent. All of them end (SIGKILL), each logged; with a server
// running, none. QUIET: no log line when there is nothing to do.
static void reap_leftovers(int quiet)
{
    pid_t server, pids[256];
    int n = engine_procs(&server, pids, 256);
    if (server) {
        if (!quiet) logf_("Wine session running (wineserver %d): leaving the engine's processes alone", server);
        return;
    }
    if (n == 0) {
        if (!quiet) logf_("no leftover Wine processes of the engine");
        return;
    }
    // once more right before: a new session (a game start) may have begun in between
    pid_t again;
    engine_procs(&again, NULL, 0);
    if (again) {
        if (!quiet) logf_("Wine session started (wineserver %d): leaving the engine's processes alone", again);
        return;
    }
    for (int i = 0; i < n; i++) {
        char name[2 * MAXCOMLEN + 1] = "?";
        struct proc_bsdinfo bi;
        int ppid = bsdinfo(pids[i], &bi) ? (int)bi.pbi_ppid : -1;
        proc_name(pids[i], name, sizeof(name));
        if (kill(pids[i], SIGKILL) == 0)
            logf_("ended leftover Wine process %d (%s, parent %d)", pids[i], name, ppid);
        else if (errno != ESRCH)
            logf_("could not end leftover Wine process %d (%s): %s", pids[i], name, strerror(errno));
    }
}

// After the launcher has quit. Its last Wine calls go through Broadsword's mac_wine, a
// separate process that can outlive it, and each of them brings the engine's wineserver up
// again (the wrapper starts it with -p 10, so it stays 10 s and keeps Wine's system processes
// alive): one -k is not enough. Every half second: while a mac_wine has a Wine call in flight,
// wait (it is never cut short, and mac_wine itself is never touched); else, if a wineserver
// of the engine runs, end the session (-k) again. Done once neither has been seen for
// QUIET_MS, or at LINGER_MAX_MS (then one last -k). Then the leftovers go, if no server is left.
static void end_session_after_launcher(void)
{
    long long start = now_ms(), quiet_from = start, t;
    int rounds = 0, waited_for_mac_wine = 0, logged_idle = 0, idle;
    pid_t server = 0;
    for (;;) {
        int mac_wine = count_mac_wine(&idle);
        engine_procs(&server, NULL, 0);
        t = now_ms();
        if (idle && !logged_idle) {
            logf_("mac_wine running without a Wine call (%d): not waiting for it", idle);
            logged_idle = 1;
        }
        if (mac_wine) {
            if (!waited_for_mac_wine)
                logf_("mac_wine running a Wine call (%d): waiting for it before ending the session", mac_wine);
            waited_for_mac_wine = 1;
            quiet_from = t;
        } else if (server) {
            if (rounds) logf_("wineserver %d came back %.1f s after the launcher quit", server, (t - start) / 1000.0);
            stop_wine_session();
            rounds++;
            // (it can take a moment to go)
            if ((server = wait_no_server(5)))
                logf_("wineserver %d still running 5 s after -k", server);
            quiet_from = now_ms();
        } else if (t - quiet_from >= QUIET_MS) {
            logf_("no wineserver for %.1f s (%.1f s after the launcher quit, %d time(s) -k)",
                  QUIET_MS / 1000.0, (t - start) / 1000.0, rounds);
            break;
        }
        if (t - start >= LINGER_MAX_MS) {
            logf_("still %s %d s after the launcher quit: ending the session once more",
                  mac_wine ? "a mac_wine Wine call running" : "a wineserver coming back", LINGER_MAX_MS / 1000);
            stop_wine_session();
            server = wait_no_server(5);
            break;
        }
        usleep(500000);
    }
    if (server) {
        logf_("wineserver %d still running: leaving the engine's processes alone", server);
        return;
    }
    sleep(1);  // let the session's clients exit on their own first
    reap_leftovers(0);
}

static void resume(pid_t launcher, const char *why)
{
    if (kill(launcher, SIGCONT) == 0)
        logf_("launcher %d resumed (%s)", launcher, why);
    else
        logf_("launcher %d: SIGCONT failed: %s (%s)", launcher, strerror(errno), why);
}

// The detached child. READY gets one byte once the launcher is stopped, or closes
// (we exit) if there is nothing to hold; either way the wrapper goes on.
static int hold(pid_t game, int ready)
{
    pid_t launcher = find_launcher(game);
    if (!launcher) {
        logf_("game %d: launcher not found among its ancestors, not holding", game);
        return 0;
    }

    static const int sigs[] = { SIGTERM, SIGINT, SIGHUP, SIGQUIT };
    struct kevent ch[2 + sizeof(sigs) / sizeof(*sigs)];
    int nch = 0;
    EV_SET(&ch[nch++], game, EVFILT_PROC, EV_ADD | EV_ONESHOT, NOTE_EXIT, 0, NULL);
    EV_SET(&ch[nch++], launcher, EVFILT_PROC, EV_ADD | EV_ONESHOT, NOTE_EXIT, 0, NULL);
    // signals arrive as events (kqueue sees them even when ignored): no handler races
    for (size_t i = 0; i < sizeof(sigs) / sizeof(*sigs); i++) {
        signal(sigs[i], SIG_IGN);
        EV_SET(&ch[nch++], sigs[i], EVFILT_SIGNAL, EV_ADD, 0, 0, NULL);
    }
    int kq = kqueue();
    if (kq < 0) {
        logf_("kqueue: %s, not holding", strerror(errno));
        return 1;
    }
    // registered one by one, so an exited pid (ESRCH) is attributed correctly
    for (int i = 0; i < nch; i++) {
        if (kevent(kq, &ch[i], 1, NULL, 0, NULL) == 0) continue;
        if (ch[i].filter == EVFILT_PROC)
            logf_("%s %d already gone (%s), not holding",
                  ch[i].ident == (uintptr_t)game ? "game" : "launcher",
                  (int)ch[i].ident, strerror(errno));
        else
            logf_("kevent signal %d: %s, not holding", (int)ch[i].ident, strerror(errno));
        return 1;
    }

    // Hide it first (the launcher only minimizes itself a while after starting the game,
    // too late once it is stopped, and its frozen window would cover the game)
    logf_("launcher %d %s", launcher, hide_app(launcher, 1.0) ? "hidden" : "not hidden (timed out)");

    if (kill(launcher, SIGSTOP) < 0) {
        logf_("launcher %d: SIGSTOP failed: %s, not holding", launcher, strerror(errno));
        return 1;
    }
    logf_("launcher %d stopped, waiting for game %d to exit", launcher, game);
    char one = 1;
    ssize_t w = write(ready, &one, 1);
    (void)w;
    close(ready);

    for (;;) {
        struct kevent ev[4];
        int n = kevent(kq, NULL, 0, ev, 4, NULL);
        if (n < 0 && errno == EINTR) continue;
        if (n < 0) {
            int e = errno;
            resume(launcher, strerror(e));
            return 1;
        }
        // a launcher exit wins over anything else in the batch: its pid may be reused
        for (int i = 0; i < n; i++)
            if (ev[i].filter == EVFILT_PROC && ev[i].ident == (uintptr_t)launcher) {
                logf_("launcher %d exited while held, nothing to resume", launcher);
                return 0;
            }
        for (int i = 0; i < n; i++) {
            if (ev[i].filter == EVFILT_PROC) {
                stop_wine_session();
                resume(launcher, "game exited");
                // wait (no polling) for the launcher to finish quitting, at most 2 min
                struct kevent t;
                EV_SET(&t, 1, EVFILT_TIMER, EV_ADD | EV_ONESHOT, NOTE_SECONDS, 120, NULL);
                kevent(kq, &t, 1, NULL, 0, NULL);
                struct kevent e;
                while (kevent(kq, NULL, 0, &e, 1, NULL) < 0 && errno == EINTR)
                    ;
                if (e.filter == EVFILT_PROC && e.ident == (uintptr_t)launcher) {
                    // The launcher's last Wine calls (on this engine too) may have left a
                    // session running, and more may come: end it until it stays gone.
                    logf_("launcher %d quit", launcher);
                    end_session_after_launcher();
                } else if (e.filter == EVFILT_TIMER) {
                    logf_("launcher %d still open 2 min after the game: leftover Wine processes "
                          "are ended at the next Wine start or by SWTOR on Mac", launcher);
                }
                return 0;
            }
            if (ev[i].filter == EVFILT_SIGNAL) {
                char why[32];
                snprintf(why, sizeof(why), "got signal %d", (int)ev[i].ident);
                resume(launcher, why);
                return 0;
            }
        }
    }
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
    // --reap: end leftover processes of the engine (none if its wineserver runs), at once
    if (argc == 2 && !strcmp(argv[1], "--reap")) {
        reap_leftovers(1);
        return 0;
    }
    if (argc == 2 && !strcmp(argv[1], "--paths")) {
        print_paths();
        return 0;
    }
    pid_t game = argc == 2 ? (pid_t)atoi(argv[1]) : 0;
    if (game <= 1) {
        fprintf(stderr, "usage: hold-launcher GAME_PID | hold-launcher --reap | hold-launcher --paths\n");
        return 2;
    }
    int fds[2];
    if (pipe(fds) < 0) {
        logf_("pipe: %s, not holding", strerror(errno));
        return 0;
    }
    pid_t child = fork();
    if (child < 0) {
        logf_("fork: %s, not holding", strerror(errno));
        return 0;
    }
    if (child > 0) {
        // return once the child has stopped the launcher (or given up: pipe closed)
        close(fds[1]);
        char c;
        while (read(fds[0], &c, 1) < 0 && errno == EINTR)
            ;
        return 0;
    }

    close(fds[0]);
    setsid();
    close_inherited_fds(fds[1]);
    int devnull = open("/dev/null", O_RDWR);
    if (devnull >= 0) {
        dup2(devnull, 0);
        dup2(devnull, 1);
        if (devnull > 2) close(devnull);
    }
    _exit(hold(game, fds[1]));
}
