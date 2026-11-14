// The exception-ports fixture's probe (scripts/fixtures/exception-ports.sh), built twice:
//
//   probe start-dead -- PROGRAM [ARGS...]   (native) starts PROGRAM with task exception ports for
//       EXC_BAD_ACCESS, EXC_BAD_INSTRUCTION and EXC_BREAKPOINT that are dead from the start (the
//       receive right is destroyed right after the start), as a launcher's process that is gone
//       leaves them; exits as PROGRAM did (128 + signal for a signal)
//   probe fault <handler|default>           (x86_64, under Rosetta) one EXC_BAD_ACCESS on a second
//       thread: handler: a SIGSEGV handler skips the faulting instruction and "past the fault" is
//       printed (exit 0); default: no handler (the default action, SIGSEGV)
//   probe exec -- PROGRAM [ARGS...]         execs PROGRAM, keeping the exception ports (the
//       fixture's control: a translated process in hold-launcher's place that clears nothing)
//
// build: clang -O2 -arch arm64 -o start probe.c; clang -O0 -arch x86_64 -o fault probe.c
#include <mach/mach.h>
#include <pthread.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;
extern int posix_spawnattr_setexceptionports_np(posix_spawnattr_t *, exception_mask_t, mach_port_t,
                                                exception_behavior_t, thread_state_flavor_t);

static int start_dead(char **cmd)
{
    mach_port_t port;
    if (mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &port) ||
        mach_port_insert_right(mach_task_self(), port, port, MACH_MSG_TYPE_MAKE_SEND))
        return 2;
    posix_spawnattr_t a;
    posix_spawnattr_init(&a);
    if (posix_spawnattr_setexceptionports_np(&a, EXC_MASK_BAD_ACCESS | EXC_MASK_BAD_INSTRUCTION | EXC_MASK_BREAKPOINT,
                                             port, EXCEPTION_DEFAULT | MACH_EXCEPTION_CODES, THREAD_STATE_NONE))
        return 2;
    pid_t pid;
    int r = posix_spawn(&pid, cmd[0], NULL, &a, cmd, environ);
    posix_spawnattr_destroy(&a);
    if (r) { fprintf(stderr, "probe: cannot start %s: %s\n", cmd[0], strerror(r)); return 2; }
    mach_port_mod_refs(mach_task_self(), port, MACH_PORT_RIGHT_RECEIVE, -1);  // the port is dead now
    int st = 0;
    if (waitpid(pid, &st, 0) < 0) return 2;
    return WIFSIGNALED(st) ? 128 + WTERMSIG(st) : WEXITSTATUS(st);
}

#if defined(__x86_64__)
static void skip(int sig, siginfo_t *si, void *uc)
{
    (void)sig; (void)si;
    ((ucontext_t *)uc)->uc_mcontext->__ss.__rip += 2;  // movl %eax,(%rax)
}
static void *fault(void *arg)
{
    (void)arg;
    __asm__ volatile("xorq %%rax, %%rax\n\t.byte 0x89, 0x00" ::: "rax", "memory");
    printf("past the fault\n");
    return NULL;
}
#endif

int main(int argc, char **argv)
{
    if (argc >= 4 && !strcmp(argv[1], "start-dead") && !strcmp(argv[2], "--")) return start_dead(argv + 3);
    if (argc >= 4 && !strcmp(argv[1], "exec") && !strcmp(argv[2], "--")) { execv(argv[3], argv + 3); return 127; }
#if defined(__x86_64__)
    if (argc == 3 && !strcmp(argv[1], "fault")) {
        if (!strcmp(argv[2], "handler")) {
            struct sigaction sa;
            memset(&sa, 0, sizeof(sa));
            sa.sa_sigaction = skip;
            sa.sa_flags = SA_SIGINFO;
            sigaction(SIGSEGV, &sa, NULL);
        }
        setvbuf(stdout, NULL, _IONBF, 0);
        pthread_t t;
        pthread_create(&t, NULL, fault, NULL);
        pthread_join(t, NULL);
        return 0;
    }
#endif
    fprintf(stderr, "usage: probe start-dead -- PROGRAM [ARGS...] | probe exec -- PROGRAM [ARGS...] | probe fault <handler|default> (x86_64)\n");
    return 64;
}
