// blink_shim.c — Embedded wrapper around blink's emulation engine.
//
// Strategy:
// - Platforms with host fork() available keep the existing child-process model.
// - Platforms without fork(), or tests that opt into it, run blink in-process
//   and unwind guest exit paths back to the embedder.

#include "include/CBlinkEmulator.h"
#include "omni_fdfs.h"

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <limits.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>
#if defined(__APPLE__) || defined(__FreeBSD__) || defined(__NetBSD__) || \
    defined(__OpenBSD__)
#include <util.h>
#else
#include <pty.h>
#endif

// ── Blink library headers ────────────────────────────────────────────────────
// These are resolved via the -iquote flag pointing to the blink source root.
#include "blink/machine.h"
#include "blink/loader.h"
#include "blink/map.h"
#include "blink/bus.h"
#include "blink/web.h"
#include "blink/vfs.h"
#include "blink/hostfs.h"
#include "blink/log.h"
#include "blink/linux.h"
#include "blink/syscall.h"
#include "blink/signal.h"
#include "blink/tunables.h"
#include "blink/x86.h"
#include "blink/util.h"
#include "blink/fds.h"
#include "blink/flag.h"
#include "blink/flags.h"

struct OmniNoForkProcess;

struct OmniNoForkContext {
    sigjmp_buf escape;
    pthread_mutex_t lock;
    pthread_cond_t cond;
    bool finished;
    bool timed_out;
    int exit_code;
    int root_pid;
    int next_pid;
    int tty_sid;
    int tty_pgrp;
    struct winsize tty_winsize;
    struct termios tty_termios;
    bool has_tty;
    struct Machine *current_machine;
    struct OmniNoForkProcess *processes;
};

static _Thread_local struct OmniNoForkContext *g_nofork_context = NULL;
struct Machine *m = NULL;

struct BlinkExecRequest {
    char *execfn;
    char *prog;
    char **argv;
    char **envp;
    bool pending;
};

static _Thread_local struct BlinkExecRequest g_exec_request;

struct OmniNoForkProcess {
    int pid;
    int ppid;
    int tgid;
    int pgid;
    int sid;
    int tracer_pid;
    int wait_status;
    int final_wait_status;
    int stop_signal;
    int requested_exit_code;
    pthread_t thread;
    bool thread_started;
    bool finished;
    bool waited;
    bool parent_released;
    bool has_pending_wait_status;
    bool has_final_wait_status;
    bool is_root;
    bool is_thread;
    bool is_vfork;
    bool stopped;
    bool continued_pending;
    bool exit_requested;
    bool group_exit_requested;
    struct Machine *machine;
    struct OmniNoForkContext *context;
    struct OmniNoForkProcess *next;
};

struct user_regs_struct_linux_marshaled {
    u8 r15[8];
    u8 r14[8];
    u8 r13[8];
    u8 r12[8];
    u8 rbp[8];
    u8 rbx[8];
    u8 r11[8];
    u8 r10[8];
    u8 r9[8];
    u8 r8[8];
    u8 rax[8];
    u8 rcx[8];
    u8 rdx[8];
    u8 rsi[8];
    u8 rdi[8];
    u8 orig_rax[8];
    u8 rip[8];
    u8 cs[8];
    u8 eflags[8];
    u8 rsp[8];
    u8 ss[8];
    u8 fs_base[8];
    u8 gs_base[8];
    u8 ds[8];
    u8 es[8];
    u8 fs[8];
    u8 gs[8];
};

struct blink_pty_session_impl {
    blink_run_config_t config;
    char *tempdir;
    pthread_t thread;
    bool thread_started;
    bool joined;
    int wait_errno;
    int exit_code;
    int slave_fd;
    int initial_rows;
    int initial_cols;
    struct OmniNoForkContext context;
    bool context_initialized;
    atomic_bool terminate_requested;
};

static struct blink_pty_session_impl *pty_session_impl(
    blink_pty_session_t *session) {
    if (!session || !session->opaque) return NULL;
    return (struct blink_pty_session_impl *)session->opaque;
}

struct BlinkFatalSignalHandlers {
    struct sigaction sigbus;
    struct sigaction sigill;
    struct sigaction sigtrap;
    struct sigaction sigsegv;
    bool installed;
};

struct BlinkRuntimeSignalHandlers {
#ifdef HAVE_THREADS
    struct sigaction sigsys;
    bool have_sigsys;
#endif
    struct sigaction sigint;
    bool have_sigint;
    struct sigaction sigquit;
    bool have_sigquit;
    struct sigaction sighup;
    bool have_sighup;
    struct sigaction sigterm;
    bool have_sigterm;
    struct sigaction sigxcpu;
    bool have_sigxcpu;
    struct sigaction sigxfsz;
    bool have_sigxfsz;
    struct BlinkFatalSignalHandlers fatal;
};

static void nofork_context_detach_current_machine(struct OmniNoForkContext *context,
                                                  struct Machine *machine);
static void restore_blink_runtime_signal_handlers(
    const struct BlinkRuntimeSignalHandlers *saved);
static struct OmniNoForkProcess *nofork_find_process_by_pid_locked(
    struct OmniNoForkContext *context, int pid);
static struct OmniNoForkProcess *nofork_find_process_by_machine_locked(
    struct OmniNoForkContext *context, struct Machine *machine);
static struct OmniNoForkProcess *nofork_register_process_locked(
    struct OmniNoForkContext *context, struct Machine *machine, int pid, int ppid,
    int tgid, bool is_root, bool is_thread);
static int nofork_find_foreground_pgrp_locked(struct OmniNoForkContext *context);
static void nofork_set_initial_group_state_locked(struct OmniNoForkContext *context,
                                                  struct OmniNoForkProcess *process);
static struct OmniNoForkProcess *nofork_find_process_in_group_locked(
    struct OmniNoForkContext *context, int sid, int pgid);
static void nofork_deliver_signal_to_process_locked(
    struct OmniNoForkProcess *process, int sig);
static void nofork_wake_process_locked(struct OmniNoForkProcess *process);
static void nofork_notify_parent_sigchld_locked(
    struct OmniNoForkProcess *process);

static void dump_guest_bytes(const char *label, struct Machine *machine, i64 addr) {
    u8 *code;
    int i;

    if (!machine || !addr) return;
    code = SpyAddress(machine, addr);
    if (!code) {
        fprintf(stderr, "[terminate] %s_bytes=<unmapped>\n", label);
        return;
    }

    fprintf(stderr, "[terminate] %s_bytes=", label);
    for (i = 0; i < 16; ++i) {
        fprintf(stderr, "%s%02x", i ? " " : "", code[i]);
    }
    fprintf(stderr, "\n");
}

static void free_cstring_list(char **list) {
    if (!list) return;
    for (size_t i = 0; list[i]; ++i) {
        free(list[i]);
    }
    free(list);
}

static void clear_exec_request(void) {
    free(g_exec_request.execfn);
    free(g_exec_request.prog);
    free_cstring_list(g_exec_request.argv);
    free_cstring_list(g_exec_request.envp);
    memset(&g_exec_request, 0, sizeof(g_exec_request));
}

static char **dup_cstring_list(char **list) {
    size_t count = 0;
    char **copy;

    if (!list) return NULL;
    while (list[count]) {
        ++count;
    }
    copy = calloc(count + 1, sizeof(*copy));
    if (!copy) return NULL;
    for (size_t i = 0; i < count; ++i) {
        copy[i] = strdup(list[i]);
        if (!copy[i]) {
            free_cstring_list(copy);
            return NULL;
        }
    }
    copy[count] = NULL;
    return copy;
}

static char **dup_const_cstring_list(const char *const *list, int count) {
    char **copy;

    if (!list || count <= 0) return NULL;
    copy = calloc((size_t)(count + 1), sizeof(*copy));
    if (!copy) return NULL;
    for (int i = 0; i < count; ++i) {
        copy[i] = list[i] ? strdup(list[i]) : NULL;
        if (list[i] && !copy[i]) {
            free_cstring_list(copy);
            return NULL;
        }
    }
    copy[count] = NULL;
    return copy;
}

static void free_host_mounts_copy(blink_host_mount_t *mounts, int count) {
    if (!mounts) return;
    for (int i = 0; i < count; ++i) {
        free((char *)mounts[i].host_path);
        free((char *)mounts[i].guest_path);
    }
    free(mounts);
}

static int copy_run_config(const blink_run_config_t *src, blink_run_config_t *dst,
                           const char *override_vfs_prefix) {
    blink_host_mount_t *host_mounts = NULL;
    char **argv = NULL;
    char **envp = NULL;

    memset(dst, 0, sizeof(*dst));
    dst->argc = src->argc;
    dst->envc = src->envc;
    dst->host_mount_count = src->host_mount_count;

    dst->program_path = src->program_path ? strdup(src->program_path) : NULL;
    if (src->program_path && !dst->program_path) goto fail;

    argv = dup_const_cstring_list(src->argv, src->argc);
    if (src->argc > 0 && !argv) goto fail;
    dst->argv = (const char *const *)argv;

    envp = dup_const_cstring_list(src->envp, src->envc);
    if (src->envc > 0 && !envp) goto fail;
    dst->envp = (const char *const *)envp;

    if (override_vfs_prefix) {
        dst->vfs_prefix = strdup(override_vfs_prefix);
        if (!dst->vfs_prefix) goto fail;
    } else if (src->vfs_prefix) {
        dst->vfs_prefix = strdup(src->vfs_prefix);
        if (!dst->vfs_prefix) goto fail;
    }

    if (src->host_mount_count > 0) {
        host_mounts = calloc((size_t)src->host_mount_count, sizeof(*host_mounts));
        if (!host_mounts) goto fail;
        for (int i = 0; i < src->host_mount_count; ++i) {
            host_mounts[i].host_path =
                src->host_mounts[i].host_path ? strdup(src->host_mounts[i].host_path) : NULL;
            host_mounts[i].guest_path =
                src->host_mounts[i].guest_path ? strdup(src->host_mounts[i].guest_path) : NULL;
            if ((src->host_mounts[i].host_path && !host_mounts[i].host_path) ||
                (src->host_mounts[i].guest_path && !host_mounts[i].guest_path)) {
                free_host_mounts_copy(host_mounts, src->host_mount_count);
                host_mounts = NULL;
                goto fail;
            }
        }
        dst->host_mounts = host_mounts;
    }

    return 0;

fail:
    free((char *)dst->program_path);
    free_cstring_list(argv);
    free_cstring_list(envp);
    free((char *)dst->vfs_prefix);
    free_host_mounts_copy(host_mounts, src->host_mount_count);
    memset(dst, 0, sizeof(*dst));
    return -1;
}

static void free_run_config(blink_run_config_t *config) {
    if (!config) return;
    free((char *)config->program_path);
    free_cstring_list((char **)config->argv);
    free_cstring_list((char **)config->envp);
    free((char *)config->vfs_prefix);
    free_host_mounts_copy((blink_host_mount_t *)config->host_mounts,
                          config->host_mount_count);
    memset(config, 0, sizeof(*config));
}

static void fail_exec_request_setup(void) {
    clear_exec_request();
    if (g_nofork_context) {
        blink_host_exit(127);
    }
    _exit(127);
}

static void stash_exec_request(char *execfn, char *prog, char **argv, char **envp) {
    clear_exec_request();
    g_exec_request.execfn = execfn ? strdup(execfn) : NULL;
    g_exec_request.prog = prog ? strdup(prog) : NULL;
    g_exec_request.argv = dup_cstring_list(argv);
    g_exec_request.envp = dup_cstring_list(envp);
    if ((execfn && !g_exec_request.execfn) || (prog && !g_exec_request.prog) ||
        (argv && !g_exec_request.argv) || (envp && !g_exec_request.envp)) {
        fail_exec_request_setup();
    }
    g_exec_request.pending = true;
}

static int queue_exec_request(char *execfn, char *prog, char **argv, char **envp) {
    struct Machine *machine = g_machine;

    unassert(machine);
    stash_exec_request(execfn, prog, argv, envp);
#ifdef HAVE_JIT
    DisableJit(&machine->system->jit);
#endif
    HaltMachine(machine, kMachineExecTrap);
}

static void configure_exec_machine(struct Machine *machine) {
    g_machine = machine;
    m = machine;
    if (machine && machine->system) {
        VfsSetCurrentProcess(machine->system->vfs);
    }
    if (getenv("OMNIKIT_BLINK_STRACE")) {
        FLAG_strace = 1;
    }
    machine->system->trapexit = true;
    machine->system->embedded_exit_fastpath = (g_nofork_context == NULL);
    machine->system->exec = queue_exec_request;
}

static bool should_canonicalize_node_argv0(const char *prog, char **argv) {
#if defined(__APPLE__) && (defined(__aarch64__) || defined(__arm64__))
    const char *base;

    if (!prog || !argv || !argv[0] || strchr(argv[0], '/')) {
        return false;
    }

    base = strrchr(prog, '/');
    base = base ? base + 1 : prog;
    return (!strcmp(base, "node") || !strcmp(base, "nodejs")) &&
           !strcmp(argv[0], base);
#else
    (void)prog;
    (void)argv;
    return false;
#endif
}

static bool is_node_binary_name(const char *prog) {
    const char *base;

    if (!prog) {
        return false;
    }

    base = strrchr(prog, '/');
    base = base ? base + 1 : prog;
    return !strcmp(base, "node") || !strcmp(base, "nodejs");
}

static bool is_env_node_program(const char *prog, char **argv) {
#if defined(__APPLE__) && (defined(__aarch64__) || defined(__arm64__))
    const char *base;
    const char *subprogram;

    if (!prog) {
        return false;
    }

    base = strrchr(prog, '/');
    base = base ? base + 1 : prog;
    if (!strcmp(base, "env") && argv && argv[1]) {
        subprogram = strrchr(argv[1], '/');
        subprogram = subprogram ? subprogram + 1 : argv[1];
        return is_node_binary_name(subprogram);
    }
    return false;
#else
    (void)prog;
    (void)argv;
    return false;
#endif
}

static bool is_node_program(const char *prog, char **argv) {
    return is_node_binary_name(prog) || is_env_node_program(prog, argv);
}

static bool should_disable_host_jit_for_program(const char *prog, char **argv) {
#if defined(__APPLE__) && (defined(__aarch64__) || defined(__arm64__))
    static int disable_node_host_jit = -1;

    if (disable_node_host_jit == -1) {
        disable_node_host_jit =
            getenv("OMNIKIT_BLINK_DISABLE_NODE_HOST_JIT") != NULL;
    }
    return disable_node_host_jit && is_node_program(prog, argv);
#else
    (void)prog;
    (void)argv;
    return false;
#endif
}

static void copy_exec_inherited_state(struct System *dst, const struct System *src) {
    int sig;

    if (!dst || !src) {
        return;
    }
    for (sig = 1; sig <= 64; ++sig) {
        if (Read64(src->hands[sig - 1].handler) == SIG_IGN_LINUX) {
            Write64(dst->hands[sig - 1].handler, SIG_IGN_LINUX);
        }
    }
    memcpy(dst->rlim, src->rlim, sizeof(dst->rlim));
}

static void transfer_exec_fd_state(struct System *dst, struct System *src) {
    if (!dst || !src) {
        return;
    }
    LOCK(&src->fds.lock);
    dst->fds.list = src->fds.list;
    src->fds.list = NULL;
    UNLOCK(&src->fds.lock);
}

static void transfer_exec_vfs_process(struct System *dst, struct System *src) {
    if (!dst || !src || !src->vfs) {
        return;
    }
    if (dst->vfs) {
        VfsFreeProcess(dst->vfs);
    }
    dst->vfs = src->vfs;
    src->vfs = NULL;
}

static void load_exec_program(struct Machine *machine, char *execfn,
                              char *prog, char **argv, char **envp,
                              bool bootstrap_stdio) {
    bool debug = getenv("OMNIKIT_DEBUG_EXEC_LOOP") != NULL;

    if (debug) {
        fprintf(stderr, "[exec-loop] load_exec_program prog=%s argv0=%s\n",
                prog ? prog : "<null>",
                (argv && argv[0]) ? argv[0] : "<null>");
        fflush(stderr);
    }
#ifdef HAVE_JIT
    if (getenv("OMNIKIT_BLINK_NOJIT")) {
        DisableJit(&machine->system->jit);
    }
#endif

    // macOS/arm64 still hits a Blink JIT bug on Node/V8 startup when the
    // interpreter is launched with argv[0]="node" via /usr/bin/env.
    // Canonicalizing argv[0] to the resolved program path keeps Linux hosts
    // unchanged while making JS CLI stubs usable on Apple hosts.
    if (should_canonicalize_node_argv0(prog, argv)) {
        if (argv == g_exec_request.argv) {
            char *canonical_argv0 = strdup(prog);
            if (!canonical_argv0) {
                _exit(127);
            }
            free(argv[0]);
            argv[0] = canonical_argv0;
        } else {
            argv[0] = prog;
        }
    }

#ifdef HAVE_JIT
    // Node/V8 remains unstable under the host-side Blink JIT on Apple arm64,
    // even after fixing guest anonymous-exec handling. Keep Blink JIT for
    // general workloads, but run the Node interpreter via the stable
    // interpreter path so JS CLIs like npm/Codex can actually execute.
    if (should_disable_host_jit_for_program(prog, argv)) {
        DisableJit(&machine->system->jit);
    }
#endif
    LoadProgram(machine, execfn, prog, argv, envp, NULL);
    SetupCod(machine);
    if (bootstrap_stdio) {
        for (int i = 0; i < 10; ++i) {
            AddStdFd(&machine->system->fds, i);
        }
    }
    if (debug) {
        fprintf(stderr, "[exec-loop] load_exec_program complete ip=%#" PRIx64 "\n",
                machine->ip);
        fflush(stderr);
    }
}

static void prepare_exec_machine(struct Machine *machine, struct Machine *old,
                                 char *execfn, char *prog, char **argv,
                                 char **envp) {
    configure_exec_machine(machine);
    if (old) {
        copy_exec_inherited_state(machine->system, old->system);
    }
    load_exec_program(machine, execfn, prog, argv, envp, old == NULL);
    if (old) {
        transfer_exec_fd_state(machine->system, old->system);
        transfer_exec_vfs_process(machine->system, old->system);
        VfsSetCurrentProcess(machine->system->vfs);
    }
}

static void teardown_exec_source(struct Machine *old) {
    sigset_t oldmask;
    bool debug = getenv("OMNIKIT_DEBUG_EXEC_LOOP") != NULL;

    if (debug) {
        fprintf(stderr, "[exec-loop] tearing down old=%p\n", (void *)old);
        fflush(stderr);
    }
    if (old->threaded) {
        KillOtherThreads(old->system);
    }
    if (debug) {
        fprintf(stderr, "[exec-loop] after KillOtherThreads\n");
        fflush(stderr);
    }
#ifdef HAVE_JIT
    DisableJit(&old->system->jit);
#endif
    if (debug) {
        fprintf(stderr, "[exec-loop] after old jit disable\n");
        fflush(stderr);
    }
    memcpy(&oldmask, &old->system->exec_sigmask, sizeof(oldmask));
    UNLOCK(&old->system->exec_lock);
    FreeMachine(old);
#ifdef HAVE_JIT
    ShutdownJit();
#endif
    unassert(!pthread_sigmask(SIG_SETMASK, &oldmask, 0));
    if (debug) {
        fprintf(stderr, "[exec-loop] old teardown complete\n");
        fflush(stderr);
    }
}

#if !defined(__SANITIZE_THREAD__) && !defined(__SANITIZE_ADDRESS__) && \
    !defined(__FILC__)
static void OmniOnFatalSystemSignal(int sig, siginfo_t *si, void *ptr) {
    struct Machine *machine = g_machine;

    (void)ptr;

#ifdef __APPLE__
    sig = FixXnuSignal(machine, sig, si);
#elif defined(__powerpc__) && CAN_64BIT
    sig = FixPpcSignal(machine, sig, si);
#endif

#ifndef DISABLE_JIT
    if (g_exec_request.pending && sig == SIGTRAP) {
        return;
    }
    if (getenv("OMNIKIT_DEBUG_FATAL_SIG")) {
        fprintf(stderr,
                "[fatal-handler] sig=%d code=%d addr=%p ip=%#" PRIx64
                " pending_exec=%d\n",
                sig, si ? si->si_code : 0, si ? si->si_addr : NULL,
                machine ? machine->ip : 0, g_exec_request.pending ? 1 : 0);
        fflush(stderr);
    }
    if (machine && IsSelfModifyingCodeSegfault(machine, si)) {
        return;
    }
#endif

    g_siginfo = *si;
    unassert(machine);
    unassert(machine->canhalt);
    siglongjmp(machine->onhalt, kMachineFatalSystemSignal);
}

static int install_blink_fatal_signal_handlers(struct BlinkFatalSignalHandlers *saved) {
    struct sigaction sa;

    memset(saved, 0, sizeof(*saved));
    sigfillset(&sa.sa_mask);
    sa.sa_flags = SA_SIGINFO;
    sa.sa_sigaction = OmniOnFatalSystemSignal;

    if (sigaction(SIGBUS, &sa, &saved->sigbus) == -1) return -1;
    if (sigaction(SIGILL, &sa, &saved->sigill) == -1) goto fail_sigill;
    if (sigaction(SIGTRAP, &sa, &saved->sigtrap) == -1) goto fail_sigtrap;
    if (sigaction(SIGSEGV, &sa, &saved->sigsegv) == -1) goto fail_sigsegv;
    saved->installed = true;
    return 0;

fail_sigsegv:
    sigaction(SIGTRAP, &saved->sigtrap, NULL);
fail_sigtrap:
    sigaction(SIGILL, &saved->sigill, NULL);
fail_sigill:
    sigaction(SIGBUS, &saved->sigbus, NULL);
    return -1;
}

static void restore_blink_fatal_signal_handlers(
    const struct BlinkFatalSignalHandlers *saved) {
    if (!saved->installed) return;
    sigaction(SIGSEGV, &saved->sigsegv, NULL);
    sigaction(SIGTRAP, &saved->sigtrap, NULL);
    sigaction(SIGILL, &saved->sigill, NULL);
    sigaction(SIGBUS, &saved->sigbus, NULL);
}
#else
static int install_blink_fatal_signal_handlers(struct BlinkFatalSignalHandlers *saved) {
    memset(saved, 0, sizeof(*saved));
    return 0;
}

static void restore_blink_fatal_signal_handlers(
    const struct BlinkFatalSignalHandlers *saved) {
    (void)saved;
}
#endif

static bool should_install_blink_fatal_signal_handlers(void) {
    return getenv("OMNIKIT_BLINK_DISABLE_FATAL_HANDLERS") == NULL;
}

static void OmniOnSigSys(int sig) {
    (void)sig;
}

static int install_blink_runtime_signal_handlers(
    struct BlinkRuntimeSignalHandlers *saved) {
    struct sigaction sa;

    memset(saved, 0, sizeof(*saved));

#ifdef HAVE_THREADS
    sigfillset(&sa.sa_mask);
    sa.sa_flags = 0;
    sa.sa_handler = OmniOnSigSys;
    if (sigaction(SIGSYS, &sa, &saved->sigsys) == -1) {
        return -1;
    }
    saved->have_sigsys = true;
#endif

    sigfillset(&sa.sa_mask);
    sa.sa_flags = SA_SIGINFO;
    sa.sa_sigaction = OnSignal;
    if (sigaction(SIGINT, &sa, &saved->sigint) == -1) {
        goto fail;
    }
    saved->have_sigint = true;
    if (sigaction(SIGQUIT, &sa, &saved->sigquit) == -1) {
        goto fail;
    }
    saved->have_sigquit = true;
    if (sigaction(SIGHUP, &sa, &saved->sighup) == -1) {
        goto fail;
    }
    saved->have_sighup = true;
    if (sigaction(SIGTERM, &sa, &saved->sigterm) == -1) {
        goto fail;
    }
    saved->have_sigterm = true;
    if (sigaction(SIGXCPU, &sa, &saved->sigxcpu) == -1) {
        goto fail;
    }
    saved->have_sigxcpu = true;
    if (sigaction(SIGXFSZ, &sa, &saved->sigxfsz) == -1) {
        goto fail;
    }
    saved->have_sigxfsz = true;

    if (should_install_blink_fatal_signal_handlers() &&
        install_blink_fatal_signal_handlers(&saved->fatal) == -1) {
        goto fail;
    }

    return 0;

fail:
    restore_blink_runtime_signal_handlers(saved);
    return -1;
}

static void restore_blink_runtime_signal_handlers(
    const struct BlinkRuntimeSignalHandlers *saved) {
    restore_blink_fatal_signal_handlers(&saved->fatal);
    if (saved->have_sigxfsz) {
        sigaction(SIGXFSZ, &saved->sigxfsz, NULL);
    }
    if (saved->have_sigxcpu) {
        sigaction(SIGXCPU, &saved->sigxcpu, NULL);
    }
    if (saved->have_sigterm) {
        sigaction(SIGTERM, &saved->sigterm, NULL);
    }
    if (saved->have_sighup) {
        sigaction(SIGHUP, &saved->sighup, NULL);
    }
    if (saved->have_sigquit) {
        sigaction(SIGQUIT, &saved->sigquit, NULL);
    }
    if (saved->have_sigint) {
        sigaction(SIGINT, &saved->sigint, NULL);
    }
#ifdef HAVE_THREADS
    if (saved->have_sigsys) {
        sigaction(SIGSYS, &saved->sigsys, NULL);
    }
#endif
}

// ── Stubs for blinkenlights symbols ──────────────────────────────────────────
// These are referenced by bios.c and other files but only meaningful in the
// TUI debugger (blinkenlights). We provide no-op stubs.

int ttyin = -1;
int vidya = -1;
bool tuimode = false;
struct Pty *pty = NULL;
bool ptyisenabled = false;

void SetCarry(bool cf) { (void)cf; }
void ReactiveDraw(void) {}
void Redraw(bool force) { (void)force; }
void DrawDisplayOnly(void) {}
bool HasPendingKeyboard(void) { return false; }
void HandleAppReadInterrupt(bool errflag) { (void)errflag; }
ssize_t ReadAnsi(int fd, char *p, size_t n) {
    return read(fd, p, n);
}

// ── TerminateSignal ──────────────────────────────────────────────────────────
// Called when the guest receives a fatal signal.
void TerminateSignal(struct Machine *machine, int sig, int code) {
    struct OmniNoForkContext *context = g_nofork_context;
    struct FileMap *rip_map = NULL;
    struct FileMap *fault_map = NULL;
    u64 rip_entry = 0;
    u64 fault_entry = 0;
    i64 rip_offset = -1;
    i64 fault_offset = -1;

    if (machine) {
        rip_map = GetFileMap(machine->system, machine->ip);
        fault_map = GetFileMap(machine->system, machine->faultaddr);
        rip_entry = FindPageTableEntry(machine, machine->ip & -4096);
        fault_entry = FindPageTableEntry(machine, machine->faultaddr & -4096);
        if (rip_map) {
            rip_offset = machine->ip - rip_map->virt + rip_map->offset;
        }
        if (fault_map) {
            fault_offset = machine->faultaddr - fault_map->virt + fault_map->offset;
        }
    }

    fprintf(stderr,
            "[terminate] sig=%d code=%d rip=%#" PRIx64 " faultaddr=%#" PRIx64
            "\n",
            sig, code, machine ? machine->ip : 0, machine ? machine->faultaddr : 0);
    if (rip_entry) {
        fprintf(stderr, "[terminate] rip_pte=%#" PRIx64 "\n", rip_entry);
    }
    if (fault_entry && fault_entry != rip_entry) {
        fprintf(stderr, "[terminate] fault_pte=%#" PRIx64 "\n", fault_entry);
    }
    if (rip_map) {
        fprintf(stderr,
                "[terminate] rip_map path=%s virt=%#" PRIx64 " size=%#" PRIx64
                " off=%#" PRIx64 "\n",
                rip_map->path ? rip_map->path : "<null>", rip_map->virt,
                rip_map->size, rip_offset);
    }
    dump_guest_bytes("rip", machine, machine ? machine->ip : 0);
    if (fault_map) {
        fprintf(stderr,
                "[terminate] fault_map path=%s virt=%#" PRIx64 " size=%#" PRIx64
                " off=%#" PRIx64 "\n",
                fault_map->path ? fault_map->path : "<null>", fault_map->virt,
                fault_map->size, fault_offset);
    }
    if (machine && machine->faultaddr && machine->faultaddr != machine->ip) {
        dump_guest_bytes("fault", machine, machine->faultaddr);
    }
    if (machine) {
        fprintf(stderr, "[terminate] guest_backtrace:\n%s\n", GetBacktrace(machine));
    }
    fflush(stderr);

    if (context) {
        nofork_context_detach_current_machine(context, machine);
        FreeMachine(machine);
#ifdef HAVE_JIT
        ShutdownJit();
#endif
        g_machine = NULL;
        m = NULL;
        context->exit_code = 128 + sig;
        siglongjmp(context->escape, 1);
    }

    FreeMachine(machine);
    _exit(128 + sig);
}

// ── Exec callback ────────────────────────────────────────────────────────────
// Called for the initial guest image load. Guest execve() requests are trapped
// back to this loop so the replacement program starts from a clean host stack.
static int ShimExec(char *execfn, char *prog, char **argv, char **envp) {
    int rc;
    struct Machine *old = NULL;
    bool debug = getenv("OMNIKIT_DEBUG_EXEC_LOOP") != NULL;

    for (;;) {
        if (old) {
            teardown_exec_source(old);
            old = NULL;
        }
        if (debug) {
            fprintf(stderr, "[exec-loop] creating replacement machine for %s\n",
                    prog ? prog : "<null>");
            fflush(stderr);
        }
        struct Machine *machine = NewMachine(NewSystem(XED_MACHINE_MODE_LONG), 0);
        if (!machine) _exit(127);

        if (debug) {
            fprintf(stderr, "[exec-loop] machine=%p configured\n", (void *)machine);
            fflush(stderr);
        }
        prepare_exec_machine(machine, old, execfn, prog, argv, envp);

        clear_exec_request();
        if (debug) {
            fprintf(stderr, "[exec-loop] entering execute loop machine=%p\n",
                    (void *)machine);
            fflush(stderr);
        }
        for (;;) {
            if (!(rc = sigsetjmp(machine->onhalt, 1))) {
                machine->canhalt = true;
                Actor(machine);
            }

            machine->sysdepth = 0;
            machine->sigdepth = 0;
            machine->canhalt = false;
            machine->nofault = false;
            machine->insyscall = false;
            CollectPageLocks(machine);
            CollectGarbage(machine, 0);
            if (IsMakingPath(machine)) {
                AbandonPath(machine);
            }

            if (rc == kMachineFatalSystemSignal) {
                HandleFatalSystemSignal(machine, &g_siginfo);
                continue;
            }

            if (rc == kMachineExitTrap && machine->system->exited) {
                int exit_code = machine->system->exitcode;

                if (debug) {
                    fprintf(stderr,
                            "[exec-loop] guest exit trap machine=%p exit_code=%d\n",
                            (void *)machine, exit_code);
                    fflush(stderr);
                }
                FreeMachine(machine);
#ifdef HAVE_JIT
                ShutdownJit();
#endif
                _exit(exit_code);
            }

            if (rc == kMachineExecTrap && g_exec_request.pending) {
                old = machine;
                execfn = g_exec_request.execfn;
                prog = g_exec_request.prog;
                argv = g_exec_request.argv;
                envp = g_exec_request.envp;
                break;
            }
        }
    }
}

// ── Pipe helpers ─────────────────────────────────────────────────────────────

static int set_nonblocking(int fd) {
    int flags = fcntl(fd, F_GETFL);
    if (flags == -1) return -1;
    return fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

/// Read all data from a file descriptor into a dynamically grown buffer.
/// Returns 0 on success, -1 on error.
static int read_all(int fd, char **out_buf, size_t *out_len) {
    size_t capacity = 4096;
    size_t len = 0;
    char *buf = malloc(capacity);
    if (!buf) return -1;

    for (;;) {
        if (len + 1024 > capacity) {
            capacity *= 2;
            char *newbuf = realloc(buf, capacity);
            if (!newbuf) { free(buf); return -1; }
            buf = newbuf;
        }
        ssize_t n = read(fd, buf + len, capacity - len);
        if (n > 0) {
            len += (size_t)n;
        } else if (n == 0) {
            break;  // EOF
        } else if (errno == EINTR) {
            continue;
        } else {
            break;  // error or EAGAIN
        }
    }

    // Null-terminate for convenience
    char *final = realloc(buf, len + 1);
    if (!final) final = buf;
    final[len] = '\0';
    *out_buf = final;
    *out_len = len;
    return 0;
}

static char *join_paths(const char *base, const char *path) {
    size_t base_len;
    size_t path_len;
    char *joined;

    if (!base || !path) {
        errno = EINVAL;
        return NULL;
    }

    while (path[0] == '/') {
        ++path;
    }

    base_len = strlen(base);
    path_len = strlen(path);
    joined = malloc(base_len + (path_len ? 1 : 0) + path_len + 1);
    if (!joined) {
        return NULL;
    }

    memcpy(joined, base, base_len);
    if (path_len) {
        joined[base_len] = '/';
        memcpy(joined + base_len + 1, path, path_len);
        joined[base_len + path_len + 1] = '\0';
    } else {
        joined[base_len] = '\0';
    }
    return joined;
}

static char *parent_path_copy(const char *path) {
    const char *slash;
    char *parent;
    size_t parent_len;

    if (!path || !path[0]) {
        return strdup("");
    }

    slash = strrchr(path, '/');
    if (!slash) {
        return strdup("");
    }

    parent_len = (size_t)(slash - path);
    parent = malloc(parent_len + 1);
    if (!parent) {
        return NULL;
    }

    memcpy(parent, path, parent_len);
    parent[parent_len] = '\0';
    return parent;
}

static int ensure_directory_path(const char *root, const char *relative_path,
                                 mode_t mode) {
    char *path;
    char *cursor;
    size_t root_len;

    if (!relative_path || !relative_path[0]) {
        return 0;
    }

    path = join_paths(root, relative_path);
    if (!path) {
        return -1;
    }

    root_len = strlen(root);
    for (cursor = path + root_len + 1; *cursor; ++cursor) {
        if (*cursor != '/') {
            continue;
        }
        *cursor = '\0';
        if (mkdir(path, mode) == -1 && errno != EEXIST) {
            int saved_errno = errno;
            free(path);
            errno = saved_errno;
            return -1;
        }
        *cursor = '/';
    }

    if (mkdir(path, mode) == -1 && errno != EEXIST) {
        int saved_errno = errno;
        free(path);
        errno = saved_errno;
        return -1;
    }

    free(path);
    return 0;
}

static int write_all_bytes(int fd, const uint8_t *data, size_t size) {
    size_t written = 0;

    while (written < size) {
        ssize_t rc = write(fd, data + written, size - written);
        if (rc == -1) {
            if (errno == EINTR) {
                continue;
            }
            return -1;
        }
        written += (size_t)rc;
    }

    return 0;
}

static int remove_tree(const char *path) {
    struct stat st;

    if (lstat(path, &st) == -1) {
        if (errno == ENOENT) {
            return 0;
        }
        return -1;
    }

    if (S_ISDIR(st.st_mode)) {
        DIR *dir;
        struct dirent *entry;
        int rc = 0;

        dir = opendir(path);
        if (!dir) {
            return -1;
        }

        while ((entry = readdir(dir)) != NULL) {
            char *child_path;

            if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) {
                continue;
            }

            child_path = join_paths(path, entry->d_name);
            if (!child_path) {
                rc = -1;
                break;
            }
            if (remove_tree(child_path) == -1) {
                int saved_errno = errno;
                free(child_path);
                closedir(dir);
                errno = saved_errno;
                return -1;
            }
            free(child_path);
        }

        if (closedir(dir) == -1 && rc == 0) {
            rc = -1;
        }
        if (rc == -1) {
            return -1;
        }
        return rmdir(path);
    }

    return unlink(path);
}

static int remove_existing_path(const char *path) {
    struct stat st;

    if (lstat(path, &st) == -1) {
        if (errno == ENOENT) {
            return 0;
        }
        return -1;
    }

    return remove_tree(path);
}

static int materialize_flatvfs_to_tempdir(const flatvfs_t *vfs, char *tempdir,
                                          size_t tempdir_size) {
    int i;
    int saved_errno = 0;

    if (!vfs || !tempdir || tempdir_size < sizeof("/tmp/omnikit-blink-host-XXXXXX")) {
        errno = EINVAL;
        return -1;
    }

    strncpy(tempdir, "/tmp/omnikit-blink-host-XXXXXX", tempdir_size);
    tempdir[tempdir_size - 1] = '\0';
    if (!mkdtemp(tempdir)) {
        return -1;
    }

    for (i = 0; i < vfs->entry_count; ++i) {
        const flatvfs_entry_t *entry = &vfs->entries[i];
        const char *relative_path = entry->path ? entry->path : "";
        char *parent = NULL;
        char *host_path = NULL;
        mode_t mode = (mode_t)(entry->mode ? entry->mode : 0644);

        if (!relative_path[0]) {
            continue;
        }

        parent = parent_path_copy(relative_path);
        if (!parent) {
            saved_errno = errno;
            goto fail;
        }
        if (ensure_directory_path(tempdir, parent, 0755) == -1) {
            saved_errno = errno;
            goto fail;
        }

        host_path = join_paths(tempdir, relative_path);
        if (!host_path) {
            saved_errno = errno;
            goto fail;
        }

        switch (entry->type) {
        case FLATVFS_DIR:
            mode = (mode_t)(entry->mode ? entry->mode : 0755);
            {
                struct stat st;
                if (lstat(host_path, &st) == 0) {
                    if (!S_ISDIR(st.st_mode)) {
                        if (remove_tree(host_path) == -1) {
                            saved_errno = errno;
                            goto fail;
                        }
                        if (mkdir(host_path, mode) == -1) {
                            saved_errno = errno;
                            goto fail;
                        }
                    }
                } else if (errno == ENOENT) {
                    if (mkdir(host_path, mode) == -1) {
                        saved_errno = errno;
                        goto fail;
                    }
                } else {
                    saved_errno = errno;
                    goto fail;
                }
            }
            if (chmod(host_path, mode) == -1) {
                saved_errno = errno;
                goto fail;
            }
            break;
        case FLATVFS_SYMLINK:
            if (!entry->symlink_target) {
                saved_errno = EINVAL;
                goto fail;
            }
            if (remove_existing_path(host_path) == -1) {
                saved_errno = errno;
                goto fail;
            }
            if (symlink(entry->symlink_target, host_path) == -1) {
                saved_errno = errno;
                goto fail;
            }
            break;
        case FLATVFS_FILE: {
            int fd;
            if (remove_existing_path(host_path) == -1) {
                saved_errno = errno;
                goto fail;
            }
            fd = open(host_path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC,
                      mode);
            if (fd == -1) {
                saved_errno = errno;
                goto fail;
            }
            if (entry->data_size &&
                write_all_bytes(fd, entry->data, entry->data_size) == -1) {
                saved_errno = errno;
                close(fd);
                goto fail;
            }
            if (close(fd) == -1) {
                saved_errno = errno;
                goto fail;
            }
            if (chmod(host_path, mode) == -1) {
                saved_errno = errno;
                goto fail;
            }
            break;
        }
        default:
            saved_errno = EINVAL;
            goto fail;
        }

        free(parent);
        free(host_path);
        continue;

fail:
        free(parent);
        free(host_path);
        remove_tree(tempdir);
        errno = saved_errno ? saved_errno : EIO;
        return -1;
    }

    return 0;
}

static pthread_mutex_t g_nofork_runtime_lock = PTHREAD_MUTEX_INITIALIZER;

struct NoForkTimeoutThreadArgs {
    struct OmniNoForkContext *context;
    int timeout_ms;
};

static bool should_use_nofork_runtime(void) {
#if !defined(HAVE_FORK)
    return true;
#else
    const char *force = getenv("OMNIKIT_BLINK_FORCE_NOFORK");
    return force && force[0] && strcmp(force, "0") != 0;
#endif
}

static void init_default_tty_termios(struct termios *termios_state) {
    memset(termios_state, 0, sizeof(*termios_state));
    if (tcgetattr(STDIN_FILENO, termios_state) == 0) {
        return;
    }
    termios_state->c_iflag = BRKINT | ICRNL | IXON;
#ifdef IMAXBEL
    termios_state->c_iflag |= IMAXBEL;
#endif
    termios_state->c_oflag = OPOST | ONLCR;
    termios_state->c_cflag = CREAD | CS8 | HUPCL;
    termios_state->c_lflag = ISIG | ICANON | ECHO | ECHOE | ECHOK | IEXTEN;
#ifdef ECHOCTL
    termios_state->c_lflag |= ECHOCTL;
#endif
#ifdef ECHOKE
    termios_state->c_lflag |= ECHOKE;
#endif
    termios_state->c_cc[VINTR] = 3;
    termios_state->c_cc[VQUIT] = 28;
    termios_state->c_cc[VERASE] = 127;
    termios_state->c_cc[VKILL] = 21;
    termios_state->c_cc[VEOF] = 4;
    termios_state->c_cc[VTIME] = 0;
    termios_state->c_cc[VMIN] = 1;
#ifdef VSTART
    termios_state->c_cc[VSTART] = 17;
#endif
#ifdef VSTOP
    termios_state->c_cc[VSTOP] = 19;
#endif
#ifdef VSUSP
    termios_state->c_cc[VSUSP] = 26;
#endif
}

static void init_default_tty_winsize(struct winsize *winsize_state, int rows,
                                     int cols) {
    memset(winsize_state, 0, sizeof(*winsize_state));
    if (ioctl(STDIN_FILENO, TIOCGWINSZ, winsize_state) == 0 &&
        winsize_state->ws_row > 0 && winsize_state->ws_col > 0) {
        return;
    }
    winsize_state->ws_row = (unsigned short)(rows > 0 ? rows : 24);
    winsize_state->ws_col = (unsigned short)(cols > 0 ? cols : 80);
}

static void configure_nofork_tty_defaults(struct OmniNoForkContext *context,
                                          int rows, int cols) {
    if (!context) return;
    init_default_tty_termios(&context->tty_termios);
    init_default_tty_winsize(&context->tty_winsize, rows, cols);
}

static int init_nofork_context(struct OmniNoForkContext *context) {
    int err;

    memset(context, 0, sizeof(*context));
    if ((err = pthread_mutex_init(&context->lock, NULL)) != 0) {
        errno = err;
        return -1;
    }
    if ((err = pthread_cond_init(&context->cond, NULL)) != 0) {
        pthread_mutex_destroy(&context->lock);
        errno = err;
        return -1;
    }

    context->exit_code = -1;
    context->has_tty = false;
    configure_nofork_tty_defaults(context, 24, 80);
    return 0;
}

static void destroy_nofork_context(struct OmniNoForkContext *context) {
    pthread_cond_destroy(&context->cond);
    pthread_mutex_destroy(&context->lock);
}

static void nofork_note_root_pid_locked(struct OmniNoForkContext *context,
                                        struct Machine *machine) {
    if (!context || context->root_pid || !machine) {
        return;
    }
    context->root_pid = machine->system->pid;
    context->next_pid = context->root_pid >= 400000 ? context->root_pid + 1 : 400000;
}

static void nofork_context_set_current_machine(struct OmniNoForkContext *context,
                                               struct Machine *machine) {
    struct OmniNoForkProcess *process = NULL;

    if (!context) return;
    pthread_mutex_lock(&context->lock);
    nofork_note_root_pid_locked(context, machine);
    if (machine && machine->system) {
        process = nofork_find_process_by_machine_locked(context, machine);
        if (!process && machine->tid != machine->system->pid) {
            process = nofork_find_process_by_pid_locked(context, machine->tid);
        }
        if (!process) {
            process = nofork_find_process_by_pid_locked(context, machine->system->pid);
        }
        if (!process) {
            process = nofork_register_process_locked(
                context, machine, machine->system->pid,
                machine->system->pid == context->root_pid ? getppid()
                                                          : machine->system->pid,
                machine->system->pid, machine->system->pid == context->root_pid, false);
            if (process) {
                nofork_set_initial_group_state_locked(context, process);
            }
        } else {
            process->machine = machine;
        }
        if (process) {
            process->thread = pthread_self();
            process->thread_started = true;
            if (!process->tgid) {
                process->tgid = machine->system->pid;
            }
            if (!process->sid || !process->pgid) {
                nofork_set_initial_group_state_locked(context, process);
            }
        }
    }
    if (!machine || !process || !process->is_thread) {
        context->current_machine = machine;
    }
    pthread_mutex_unlock(&context->lock);
    if (machine && machine->system) {
        VfsSetCurrentProcess(machine->system->vfs);
    }
}

static void nofork_context_detach_current_machine(struct OmniNoForkContext *context,
                                                  struct Machine *machine) {
    if (!context) return;
    pthread_mutex_lock(&context->lock);
    if (context->current_machine == machine) {
        context->current_machine = NULL;
    }
    pthread_mutex_unlock(&context->lock);
    if (g_machine == machine) {
        VfsSetCurrentProcess(NULL);
    }
}

static void nofork_context_finish(struct OmniNoForkContext *context) {
    struct OmniNoForkProcess *process;
    struct OmniNoForkProcess *next;

    if (!context) return;
    pthread_mutex_lock(&context->lock);
    context->finished = true;
    context->current_machine = NULL;
    pthread_cond_broadcast(&context->cond);
    pthread_mutex_unlock(&context->lock);
    for (process = context->processes; process; process = next) {
        next = process->next;
        if (process->thread_started && !pthread_equal(process->thread, pthread_self())) {
            pthread_join(process->thread, NULL);
        }
        free(process);
    }
    context->processes = NULL;
}

static struct OmniNoForkProcess *nofork_find_process_by_pid_locked(
    struct OmniNoForkContext *context, int pid) {
    struct OmniNoForkProcess *process;

    for (process = context->processes; process; process = process->next) {
        if (process->pid == pid) {
            return process;
        }
    }
    return NULL;
}

static struct OmniNoForkProcess *nofork_find_process_by_machine_locked(
    struct OmniNoForkContext *context, struct Machine *machine) {
    struct OmniNoForkProcess *process;

    for (process = context->processes; process; process = process->next) {
        if (process->machine == machine) {
            return process;
        }
    }
    return NULL;
}

static struct OmniNoForkProcess *nofork_register_process_locked(
    struct OmniNoForkContext *context, struct Machine *machine, int pid, int ppid,
    int tgid, bool is_root, bool is_thread) {
    struct OmniNoForkProcess *process;

    process = nofork_find_process_by_pid_locked(context, pid);
    if (process) {
        process->machine = machine;
        process->ppid = ppid;
        process->tgid = tgid ? tgid : pid;
        process->is_root = is_root;
        process->is_thread = is_thread;
        return process;
    }
    process = calloc(1, sizeof(*process));
    if (!process) {
        return NULL;
    }
    process->pid = pid;
    process->ppid = ppid;
    process->tgid = tgid ? tgid : pid;
    process->machine = machine;
    process->context = context;
    process->is_root = is_root;
    process->is_thread = is_thread;
    process->next = context->processes;
    context->processes = process;
    return process;
}

static void nofork_set_initial_group_state_locked(struct OmniNoForkContext *context,
                                                  struct OmniNoForkProcess *process) {
    if (!context || !process) return;
    if (!process->sid) {
        process->sid = process->pid;
    }
    if (!process->pgid) {
        process->pgid = process->pid;
    }
    if (context->has_tty && !context->tty_sid) {
        context->tty_sid = process->sid;
    }
    if (context->has_tty && !context->tty_pgrp) {
        context->tty_pgrp = process->pgid;
    }
}

static struct OmniNoForkProcess *nofork_find_process_in_group_locked(
    struct OmniNoForkContext *context, int sid, int pgid) {
    struct OmniNoForkProcess *process;

    for (process = context->processes; process; process = process->next) {
        if (!process->finished && process->sid == sid && process->pgid == pgid) {
            return process;
        }
    }
    return NULL;
}

static int nofork_find_foreground_pgrp_locked(struct OmniNoForkContext *context) {
    if (!context) return 0;
    return context->tty_pgrp;
}

static int nofork_make_stopped_wait_status(int sig) {
    return ((sig & 255) << 8) | 0x7f;
}

static int nofork_make_continued_wait_status(void) {
    return 0xffff;
}

static bool nofork_wait_status_is_stopped(int wait_status) {
#ifdef WIFSTOPPED
    return WIFSTOPPED(wait_status);
#else
    return (wait_status & 0xff) == 0x7f;
#endif
}

static bool nofork_wait_status_is_continued(int wait_status) {
#ifdef WIFCONTINUED
    return WIFCONTINUED(wait_status);
#else
    return wait_status == 0xffff;
#endif
}

static void nofork_wake_process_locked(struct OmniNoForkProcess *process) {
    struct Machine *machine;

    if (!process) return;
    machine = process->machine;
    if (machine) {
        atomic_store_explicit(&machine->attention, true, memory_order_release);
    }
    pthread_cond_broadcast(&process->context->cond);
    if (process->thread_started && !pthread_equal(process->thread, pthread_self())) {
        pthread_kill(process->thread, SIGSYS);
    }
}

static void nofork_notify_parent_sigchld_locked(
    struct OmniNoForkProcess *process) {
    struct OmniNoForkProcess *parent;

    if (!process || process->is_thread) return;
    parent = nofork_find_process_by_pid_locked(process->context, process->ppid);
    if (parent && parent->machine && !parent->finished) {
        nofork_deliver_signal_to_process_locked(parent, SIGCHLD_LINUX);
    }
}

static int nofork_signal_handler_locked(struct OmniNoForkProcess *process, int sig) {
    if (!process || !process->machine || sig < 1 || sig > 64) {
        return SIG_DFL_LINUX;
    }
    return Read64(process->machine->system->hands[sig - 1].handler);
}

static void nofork_record_stopped_status_locked(struct OmniNoForkProcess *process,
                                                int sig) {
    if (!process || process->finished || process->stopped) return;
    process->stopped = true;
    process->stop_signal = sig;
    if (!process->has_pending_wait_status) {
        process->wait_status = nofork_make_stopped_wait_status(sig);
        process->has_pending_wait_status = true;
    }
    nofork_notify_parent_sigchld_locked(process);
    nofork_wake_process_locked(process);
}

static void nofork_resume_process_locked(struct OmniNoForkProcess *process) {
    if (!process || process->finished || !process->stopped) return;
    process->stopped = false;
    process->stop_signal = 0;
    if (process->has_pending_wait_status) {
        process->continued_pending = true;
    } else {
        process->wait_status = nofork_make_continued_wait_status();
        process->has_pending_wait_status = true;
    }
    nofork_notify_parent_sigchld_locked(process);
    nofork_wake_process_locked(process);
}

static bool nofork_process_matches_wait_target_locked(
    struct OmniNoForkProcess *process, struct OmniNoForkProcess *caller, int pid) {
    if (!process || !caller || process->is_root || process->is_thread ||
        process->ppid != caller->pid) {
        return false;
    }
    if (pid == -1) return true;
    if (pid > 0) return process->pid == pid;
    if (pid == 0) return process->pgid == caller->pgid;
    return process->pgid == -pid;
}

static bool nofork_process_next_wait_status_locked(struct OmniNoForkProcess *process,
                                                   int options,
                                                   int *wait_status) {
    if (!process) return false;
    if (process->has_pending_wait_status) {
        if (nofork_wait_status_is_stopped(process->wait_status) &&
            !(options & WUNTRACED)) {
            return false;
        }
        if (nofork_wait_status_is_continued(process->wait_status) &&
            !(options & WCONTINUED)) {
            return false;
        }
        if (wait_status) *wait_status = process->wait_status;
        return true;
    }
    if (process->finished && process->has_final_wait_status) {
        if (wait_status) *wait_status = process->final_wait_status;
        return true;
    }
    return false;
}

static void nofork_consume_wait_status_locked(struct OmniNoForkProcess *process) {
    if (!process || !process->has_pending_wait_status) return;
    process->has_pending_wait_status = false;
    if (process->continued_pending) {
        process->continued_pending = false;
        process->wait_status = nofork_make_continued_wait_status();
        process->has_pending_wait_status = true;
    }
}

static void nofork_deliver_signal_to_process_locked(
    struct OmniNoForkProcess *process, int sig) {
    struct Machine *machine;

    if (!process || !process->machine || !sig) return;
    machine = process->machine;
    EnqueueSignal(machine, sig);
    nofork_wake_process_locked(process);
}

static void nofork_unregister_process_locked(struct OmniNoForkContext *context,
                                             struct OmniNoForkProcess *target) {
    struct OmniNoForkProcess **it;

    for (it = &context->processes; *it; it = &(*it)->next) {
        if (*it == target) {
            *it = target->next;
            free(target);
            return;
        }
    }
}

static struct OmniNoForkProcess *nofork_ensure_root_process(
    struct OmniNoForkContext *context, struct Machine *machine) {
    struct OmniNoForkProcess *process;

    if (!context || !machine || !machine->system) {
        return NULL;
    }
    pthread_mutex_lock(&context->lock);
    nofork_note_root_pid_locked(context, machine);
    process = nofork_register_process_locked(context, machine, machine->system->pid,
                                             getppid(), machine->system->pid, true,
                                             false);
    nofork_set_initial_group_state_locked(context, process);
    pthread_mutex_unlock(&context->lock);
    return process;
}

static void add_timeout_to_timespec(struct timespec *deadline, int timeout_ms) {
    deadline->tv_sec += timeout_ms / 1000;
    deadline->tv_nsec += (long)(timeout_ms % 1000) * 1000000L;
    if (deadline->tv_nsec >= 1000000000L) {
        deadline->tv_sec += deadline->tv_nsec / 1000000000L;
        deadline->tv_nsec %= 1000000000L;
    }
}

static void *nofork_timeout_thread_main(void *arg) {
    struct NoForkTimeoutThreadArgs *state = (struct NoForkTimeoutThreadArgs *)arg;
    struct timespec deadline;

    if (clock_gettime(CLOCK_REALTIME, &deadline) != 0) {
        return NULL;
    }
    add_timeout_to_timespec(&deadline, state->timeout_ms);

    pthread_mutex_lock(&state->context->lock);
    while (!state->context->finished) {
        int rc = pthread_cond_timedwait(&state->context->cond, &state->context->lock,
                                        &deadline);
        if (state->context->finished) {
            break;
        }
        if (rc == ETIMEDOUT) {
            struct Machine *machine = state->context->current_machine;
            state->context->timed_out = true;
            if (machine) {
                atomic_store_explicit(&machine->killed, true, memory_order_release);
                atomic_store_explicit(&machine->attention, true, memory_order_release);
            }
            break;
        }
        if (rc != 0) {
            break;
        }
    }
    pthread_mutex_unlock(&state->context->lock);
    return NULL;
}

struct CapturePipeState {
    int fd;
    char *buf;
    size_t len;
    int error;
};

static void *capture_pipe_reader_main(void *arg) {
    struct CapturePipeState *state = (struct CapturePipeState *)arg;

    if (read_all(state->fd, &state->buf, &state->len) != 0) {
        state->error = errno ? errno : EIO;
    }
    close(state->fd);
    state->fd = -1;
    return NULL;
}

static int redirect_guest_fd(int guest_fd, int host_fd) {
    struct VfsInfo *info;

    if (HostfsWrapFd(host_fd, true, &info) == -1) {
        return -1;
    }
    if (VfsSetFd(guest_fd, info) == -1) {
        int saved_errno = errno;
        unassert(!VfsFreeInfo(info));
        errno = saved_errno;
        return -1;
    }
    return 0;
}

_Noreturn void blink_host_exit(int status) {
    struct OmniNoForkContext *context = g_nofork_context;

    if (context) {
        struct Machine *machine = g_machine;

        pthread_mutex_lock(&context->lock);
        if (context->current_machine == machine) {
            context->current_machine = NULL;
        }
        pthread_mutex_unlock(&context->lock);

        if (machine) {
            FreeMachine(machine);
#ifdef HAVE_JIT
            ShutdownJit();
#endif
        }

        g_machine = NULL;
        m = NULL;
        VfsSetCurrentProcess(NULL);
        context->exit_code = (status & 255);
        siglongjmp(context->escape, 1);
    }

    _Exit(status & 255);
}

static int reset_blink_vfs_state(void) {
    VfsCloseAll();
    VfsResetForReuse();
    return 0;
}

static int init_isolated_host_prefix(const char *prefix) {
    char *resolved_prefix;
    struct stat st;
    int rc;

    if (!prefix) {
        errno = EINVAL;
        return -1;
    }

    resolved_prefix = realpath(prefix, NULL);
    if (!resolved_prefix) {
        return -1;
    }
    if (stat(resolved_prefix, &st) == -1) {
        int saved_errno = errno;
        free(resolved_prefix);
        errno = saved_errno;
        return -1;
    }
    if (!S_ISDIR(st.st_mode)) {
        free(resolved_prefix);
        errno = ENOTDIR;
        return -1;
    }

    rc = VfsInitRootMount(resolved_prefix, "hostfs", 0, NULL, false, false, "/");
    free(resolved_prefix);
    return rc;
}

static int ensure_guest_mountpoint(const char *guest_path) {
    char pathbuf[PATH_MAX];
    size_t pathlen;
    char *cursor;
    struct stat st;

    if (!guest_path || guest_path[0] != '/') {
        errno = EINVAL;
        return -1;
    }
    if (!strcmp(guest_path, "/")) {
        return 0;
    }

    pathlen = strlen(guest_path);
    if (pathlen >= sizeof(pathbuf)) {
        errno = ENAMETOOLONG;
        return -1;
    }

    memcpy(pathbuf, guest_path, pathlen + 1);
    for (cursor = pathbuf + 1; *cursor; ++cursor) {
        if (*cursor != '/') continue;
        *cursor = '\0';
        if (VfsMkdir(AT_FDCWD, pathbuf, 0755) == -1 && errno != EEXIST) {
            return -1;
        }
        *cursor = '/';
    }

    if (VfsMkdir(AT_FDCWD, pathbuf, 0755) == -1 && errno != EEXIST) {
        return -1;
    }
    if (VfsStat(AT_FDCWD, pathbuf, &st, 0) == -1) {
        return -1;
    }
    if (!S_ISDIR(st.st_mode)) {
        errno = ENOTDIR;
        return -1;
    }
    return 0;
}

static int install_extra_host_mounts(const blink_run_config_t *config) {
    int i;

    if (!config || !config->host_mounts || config->host_mount_count <= 0) {
        return 0;
    }

    for (i = 0; i < config->host_mount_count; ++i) {
        const blink_host_mount_t *mount = &config->host_mounts[i];

        if (!mount->host_path || !mount->guest_path) {
            errno = EINVAL;
            return -1;
        }
        if (mount->guest_path[0] != '/') {
            errno = EINVAL;
            return -1;
        }
        if (!strcmp(mount->guest_path, "/")) {
            errno = EBUSY;
            return -1;
        }
        if (ensure_guest_mountpoint(mount->guest_path) == -1) {
            return -1;
        }
        if (VfsMount(mount->host_path, mount->guest_path, "hostfs", 0, NULL) == -1) {
            return -1;
        }
    }

    return 0;
}

static bool should_force_nolinear_host_runtime(void) {
    static int cached = -1;

    if (cached == -1) {
        cached = (FLAG_pagesize != 4096) || getenv("OMNIKIT_BLINK_FORCE_NOLINEAR") != NULL;
    }
    return cached;
}

static int host_runtime_setup(const blink_run_config_t *config, const flatvfs_t *vfs) {
    (void)vfs;

    if (reset_blink_vfs_state() != 0) return -1;

    WriteErrorInit();
    InitMap();
    FLAG_nolinear = should_force_nolinear_host_runtime();

#ifndef DISABLE_VFS
    if (config->host_mount_count > 0 && !config->vfs_prefix) {
        errno = EINVAL;
        return -1;
    }
    if (config->vfs_prefix) {
        if (init_isolated_host_prefix(config->vfs_prefix)) {
            return -1;
        }
        if (OmniInstallGuestFdMounts()) {
            return -1;
        }
    }
    if (install_extra_host_mounts(config)) {
        return -1;
    }
#endif

    InitBus();
    return 0;
}

static int memvfs_runtime_setup(const blink_run_config_t *config, const flatvfs_t *vfs) {
    (void)config;

    if (reset_blink_vfs_state() != 0) return -1;

    WriteErrorInit();
    InitMap();
    FLAG_nolinear = true;

#ifndef DISABLE_VFS
    if (OmniVfsInit(vfs)) {
        return -1;
    }
    if (OmniInstallGuestFdMounts()) {
        return -1;
    }
    if (install_extra_host_mounts(config)) {
        return -1;
    }
#endif

    InitBus();
    return 0;
}

static char *dup_nullable_cstring(const char *value) {
    return value ? strdup(value) : NULL;
}

static int clone_system_elf_state(struct System *dst, const struct System *src) {
    dst->elf.prog = dup_nullable_cstring(src->elf.prog);
    if (src->elf.prog && !dst->elf.prog) return -1;
    dst->elf.execfn = dup_nullable_cstring(src->elf.execfn);
    if (src->elf.execfn && !dst->elf.execfn) return -1;
    dst->elf.interpreter = dup_nullable_cstring(src->elf.interpreter);
    if (src->elf.interpreter && !dst->elf.interpreter) return -1;
    dst->elf.base = src->elf.base;
    dst->elf.aslr = src->elf.aslr;
    memcpy(dst->elf.rng, src->elf.rng, sizeof(dst->elf.rng));
    dst->elf.at_base = src->elf.at_base;
    dst->elf.at_phdr = src->elf.at_phdr;
    dst->elf.at_phent = src->elf.at_phent;
    dst->elf.at_entry = src->elf.at_entry;
    dst->elf.at_phnum = src->elf.at_phnum;
    return 0;
}

static int clone_system_fd_state(struct System *dst, const struct System *src) {
    struct Dll *e;
    struct Fd *fd;

    LOCK(&((struct System *)src)->fds.lock);
    for (e = dll_first(src->fds.list); e; e = dll_next(src->fds.list, e)) {
        fd = FD_CONTAINER(e);
        if (!ForkFd(&dst->fds, fd, fd->fildes, fd->oflags)) {
            UNLOCK(&((struct System *)src)->fds.lock);
            errno = ENOMEM;
            return -1;
        }
    }
    UNLOCK(&((struct System *)src)->fds.lock);
    return 0;
}

static int clone_system_filemaps(struct System *dst, const struct System *src) {
    struct Dll *e;
    struct FileMap *fm;
    struct FileMap *copy;
    size_t words;

    for (e = dll_first(src->filemaps); e; e = dll_next(src->filemaps, e)) {
        fm = FILEMAP_CONTAINER(e);
        copy = calloc(1, sizeof(*copy));
        if (!copy) return -1;
        copy->virt = fm->virt;
        copy->size = fm->size;
        copy->pages = fm->pages;
        copy->offset = fm->offset;
        copy->path = dup_nullable_cstring(fm->path);
        if (fm->path && !copy->path) {
            free(copy);
            return -1;
        }
        words = ROUNDUP(ROUNDUP(fm->size, 4096) / 4096, 64) / 64;
        if (words) {
            copy->present = malloc(words * sizeof(*copy->present));
            if (!copy->present) {
                free(copy->path);
                free(copy);
                return -1;
            }
            memcpy(copy->present, fm->present, words * sizeof(*copy->present));
        }
        dll_init(&copy->elem);
        dll_make_last(&dst->filemaps, &copy->elem);
    }
    return 0;
}

static u64 reserve_flags_from_pte(u64 entry) {
    return entry & (PAGE_U | PAGE_RW | PAGE_XD | PAGE_GROW);
}

static int prot_from_pte(u64 entry) {
    int prot = PROT_READ;

    if (entry & PAGE_RW) prot |= PROT_WRITE;
    if (!(entry & PAGE_XD)) prot |= PROT_EXEC;
    return prot;
}

static int clone_single_guest_page(struct Machine *parent, struct Machine *child,
                                   i64 virt, u64 entry) {
    u64 flags;
    u8 page[4096];

    flags = reserve_flags_from_pte(entry);
    if (ReserveVirtual(child->system, virt, 4096, flags | PAGE_RW, -1, 0, false,
                       false) == -1) {
        return -1;
    }
    if (!(entry & PAGE_RSRV)) {
        if (CopyFromUserRead(parent, page, virt, sizeof(page)) == -1) {
            return -1;
        }
        if (CopyToUserWrite(child, virt, page, sizeof(page)) == -1) {
            return -1;
        }
    }
    if (~entry & PAGE_RW) {
        if (ProtectVirtual(child->system, virt, 4096, prot_from_pte(entry), false) ==
            -1) {
            return -1;
        }
    }
    return 0;
}

static int clone_guest_page_range(struct Machine *parent, struct Machine *child,
                                  i64 virt, u64 entry, long level) {
    i64 size;
    i64 offset;

    size = (i64)1 << level;
    for (offset = 0; offset < size; offset += 4096) {
        if (clone_single_guest_page(parent, child, virt + offset, entry) == -1) {
            return -1;
        }
    }
    return 0;
}

static int clone_guest_page_table_level(struct Machine *parent,
                                        struct Machine *child, u64 table,
                                        long level, i64 base) {
    u8 *mi;
    u64 entry;
    i64 next_base;
    unsigned index;

    mi = GetPageAddress(parent->system, table, level == 39);
    if (!mi) return 0;
    for (index = 0; index < 512; ++index) {
        entry = LoadPte(mi + index * 8);
        if (!(entry & PAGE_V)) continue;
        next_base = base | ((i64)index << level);
        if (level == 39 && (next_base & ((i64)1 << 47))) {
            next_base |= ~(((i64)1 << 48) - 1);
        }
        if ((entry & PAGE_PS) && level > 12) {
            if (clone_guest_page_range(parent, child, next_base, entry, level) == -1) {
                return -1;
            }
            continue;
        }
        if (level == 12) {
            if (clone_single_guest_page(parent, child, next_base, entry) == -1) {
                return -1;
            }
            continue;
        }
        if (clone_guest_page_table_level(parent, child, entry, level - 9, next_base) ==
            -1) {
            return -1;
        }
    }
    return 0;
}

static int clone_guest_address_space(struct Machine *parent, struct Machine *child) {
    if (!parent->system->cr3) return 0;
    return clone_guest_page_table_level(parent, child, parent->system->cr3, 39, 0);
}

static int clone_system_state(struct Machine *parent, struct Machine *child,
                              int child_pid) {
    struct System *src = parent->system;
    struct System *dst = child->system;

    dst->dlab = src->dlab;
    dst->isfork = true;
    dst->loaded = src->loaded;
    dst->iscosmo = src->iscosmo;
    dst->trapexit = src->trapexit;
    dst->embedded_exit_fastpath = src->embedded_exit_fastpath;
    dst->brkchanged = src->brkchanged;
    dst->gdt_limit = src->gdt_limit;
    dst->idt_limit = src->idt_limit;
    dst->efer = src->efer;
    dst->pid = child_pid;
    dst->next_tid = child_pid;
    dst->gdt_base = src->gdt_base;
    dst->idt_base = src->idt_base;
    dst->cr0 = src->cr0;
    dst->cr2 = src->cr2;
    dst->cr4 = src->cr4;
    dst->brk = src->brk;
    dst->automap = src->automap;
    dst->memchurn = src->memchurn;
    dst->codestart = src->codestart;
    dst->codesize = src->codesize;
    dst->blinksigs = src->blinksigs;
    memcpy(&dst->exec_sigmask, &src->exec_sigmask, sizeof(dst->exec_sigmask));
    memcpy(dst->hands, src->hands, sizeof(dst->hands));
    memcpy(dst->rlim, src->rlim, sizeof(dst->rlim));
    if (clone_system_elf_state(dst, src) == -1) {
        return -1;
    }
    if (clone_system_fd_state(dst, src) == -1) {
        return -1;
    }
    if (clone_guest_address_space(parent, child) == -1) {
        return -1;
    }
    if (clone_system_filemaps(dst, src) == -1) {
        return -1;
    }
    return 0;
}

static void clone_machine_state(struct Machine *dst, struct Machine *src,
                                int child_pid, u64 stack) {
    struct System *system = dst->system;

    memcpy(dst, src, sizeof(*dst));
    dst->system = system;
    dst->thread = pthread_self();
    dst->tid = child_pid;
    dst->ctid = 0;
    memset(&dst->path, 0, sizeof(dst->path));
    memset(&dst->freelist, 0, sizeof(dst->freelist));
    memset(&dst->pagelocks, 0, sizeof(dst->pagelocks));
    ResetInstructionCache(dst);
    dst->insyscall = false;
    dst->nofault = false;
    dst->sysdepth = 0;
    dst->sigdepth = 0;
    dst->signals = 0;
    dst->threaded = false;
    dst->killed = false;
    dst->attention = false;
    dst->invalidated = false;
    dll_init(&dst->elem);
    if (stack) {
        Put64(dst->sp, stack);
    }
    Put64(dst->ax, 0);
}

static int run_machine_nofork(struct Machine *machine) {
    int rc;
    struct OmniNoForkContext *context = g_nofork_context;

    unassert(context);
    machine->system->trapexit = true;

    for (g_machine = machine, m = machine;;) {
        nofork_context_set_current_machine(context, machine);

        if (!(rc = sigsetjmp(machine->onhalt, 1))) {
            machine->canhalt = true;
            Actor(machine);
        }

        machine->sysdepth = 0;
        machine->sigdepth = 0;
        machine->canhalt = false;
        machine->nofault = false;
        machine->insyscall = false;
        CollectPageLocks(machine);
        CollectGarbage(machine, 0);
        if (IsMakingPath(machine)) {
            AbandonPath(machine);
        }

        if (rc == kMachineFatalSystemSignal) {
            HandleFatalSystemSignal(machine, &g_siginfo);
            continue;
        }

        if (rc == kMachineExitTrap && machine->system->exited) {
            int exit_code = machine->system->exitcode;

            nofork_context_detach_current_machine(context, machine);
            FreeMachine(machine);
#ifdef HAVE_JIT
            ShutdownJit();
#endif
            g_machine = NULL;
            m = NULL;

            if (context->timed_out) {
                exit_code = 128 + SIGKILL;
            }
            context->exit_code = exit_code;
            siglongjmp(context->escape, 1);
        }

        if (rc == kMachineExecTrap && g_exec_request.pending) {
            return rc;
        }
    }
}

static void nofork_finish_process(struct OmniNoForkProcess *process, int exit_code) {
    struct OmniNoForkContext *context;

    if (!process) return;
    context = process->context;
    pthread_mutex_lock(&context->lock);
    process->finished = true;
    process->stopped = false;
    process->continued_pending = false;
    process->stop_signal = 0;
    if (!process->has_final_wait_status) {
        process->final_wait_status = (exit_code & 255) << 8;
        process->has_final_wait_status = true;
    }
    process->machine = NULL;
    process->parent_released = true;
    if (!process->is_thread) {
        nofork_notify_parent_sigchld_locked(process);
    }
    pthread_cond_broadcast(&context->cond);
    pthread_mutex_unlock(&context->lock);
}

static void nofork_finish_thread_task(struct OmniNoForkProcess *process, int exit_code) {
    struct OmniNoForkContext *context;

    if (!process) return;
    context = process->context;
    pthread_mutex_lock(&context->lock);
    process->finished = true;
    process->stopped = false;
    process->continued_pending = false;
    process->stop_signal = 0;
    process->requested_exit_code = exit_code & 255;
    process->exit_requested = false;
    process->group_exit_requested = false;
    process->machine = NULL;
    process->parent_released = true;
    pthread_cond_broadcast(&context->cond);
    pthread_mutex_unlock(&context->lock);
}

static void nofork_process_wait_if_stopped(struct OmniNoForkProcess *process) {
    struct OmniNoForkContext *context;

    if (!process) return;
    context = process->context;
    pthread_mutex_lock(&context->lock);
    while (process->stopped && !process->finished && !context->finished &&
           !atomic_load_explicit(&process->machine->killed, memory_order_acquire)) {
        pthread_cond_wait(&context->cond, &context->lock);
    }
    pthread_mutex_unlock(&context->lock);
}

static int run_machine_nofork_pseudo_process(struct OmniNoForkProcess *process) {
    int rc;
    int exit_code;
    struct Machine *machine;
    struct OmniNoForkContext *context;

    context = process->context;
    machine = process->machine;
    unassert(context);
    unassert(machine);
    machine->system->trapexit = true;

    for (g_machine = machine, m = machine;;) {
        nofork_context_set_current_machine(context, machine);
        nofork_process_wait_if_stopped(process);

        if (!(rc = sigsetjmp(machine->onhalt, 1))) {
            machine->canhalt = true;
            Actor(machine);
        }

        machine->sysdepth = 0;
        machine->sigdepth = 0;
        machine->canhalt = false;
        machine->nofault = false;
        machine->insyscall = false;
        CollectPageLocks(machine);
        CollectGarbage(machine, 0);
        if (IsMakingPath(machine)) {
            AbandonPath(machine);
        }

        if (rc == kMachineFatalSystemSignal) {
            HandleFatalSystemSignal(machine, &g_siginfo);
            continue;
        }

        if (rc == kMachineExitTrap && machine->system->exited) {
            exit_code = machine->system->exitcode;
            nofork_context_detach_current_machine(context, machine);
            FreeMachine(machine);
#ifdef HAVE_JIT
            ShutdownJit();
#endif
            g_machine = NULL;
            m = NULL;
            VfsSetCurrentProcess(NULL);
            nofork_finish_process(process, exit_code);
            return kMachineExitTrap;
        }

        if (rc == kMachineExecTrap && g_exec_request.pending) {
            return rc;
        }
    }
}

static int run_machine_nofork_thread_task(struct OmniNoForkProcess *process) {
    int rc;
    int exit_code;
    bool should_finish;
    struct Machine *machine;
    struct OmniNoForkContext *context;

    context = process->context;
    machine = process->machine;
    unassert(context);
    unassert(machine);
    machine->system->trapexit = true;

    for (g_machine = machine, m = machine;;) {
        nofork_context_set_current_machine(context, machine);
        nofork_process_wait_if_stopped(process);

        if (!(rc = sigsetjmp(machine->onhalt, 1))) {
            machine->canhalt = true;
            unassert(!pthread_sigmask(SIG_SETMASK, &machine->spawn_sigmask, 0));
            Actor(machine);
        }

        machine->sysdepth = 0;
        machine->sigdepth = 0;
        machine->canhalt = false;
        machine->nofault = false;
        machine->insyscall = false;
        CollectPageLocks(machine);
        CollectGarbage(machine, 0);
        if (IsMakingPath(machine)) {
            AbandonPath(machine);
        }

        if (rc == kMachineFatalSystemSignal) {
            HandleFatalSystemSignal(machine, &g_siginfo);
            continue;
        }

        if (rc == kMachineExitTrap) {
            pthread_mutex_lock(&context->lock);
            should_finish = process->exit_requested || machine->system->exited;
            exit_code = process->exit_requested ? process->requested_exit_code
                                               : machine->system->exitcode;
            pthread_mutex_unlock(&context->lock);
            if (should_finish) {
                nofork_context_detach_current_machine(context, machine);
                FreeMachine(machine);
#ifdef HAVE_JIT
                ShutdownJit();
#endif
                g_machine = NULL;
                m = NULL;
                VfsSetCurrentProcess(NULL);
                nofork_finish_thread_task(process, exit_code);
                return kMachineExitTrap;
            }
        }
    }
}

static int nofork_replace_process_machine(struct OmniNoForkProcess *process) {
    struct Machine *old;
    struct Machine *machine;

    old = process->machine;
    machine = NewMachine(NewSystem(XED_MACHINE_MODE_LONG), 0);
    if (!machine) {
        return -1;
    }
    process->machine = machine;
    prepare_exec_machine(machine, old, g_exec_request.execfn, g_exec_request.prog,
                         g_exec_request.argv, g_exec_request.envp);
    clear_exec_request();
    pthread_mutex_lock(&process->context->lock);
    process->parent_released = true;
    pthread_cond_broadcast(&process->context->cond);
    pthread_mutex_unlock(&process->context->lock);
    teardown_exec_source(old);
    return 0;
}

static void *nofork_process_thread_main(void *arg) {
    struct OmniNoForkProcess *process = (struct OmniNoForkProcess *)arg;
    int rc;

    g_nofork_context = process->context;
    for (;;) {
        rc = run_machine_nofork_pseudo_process(process);
        if (rc == kMachineExecTrap && g_exec_request.pending) {
            if (nofork_replace_process_machine(process) == -1) {
                clear_exec_request();
                nofork_finish_process(process, 127);
                return NULL;
            }
            continue;
        }
        break;
    }
    return NULL;
}

static void *nofork_thread_task_main(void *arg) {
    struct OmniNoForkProcess *process = (struct OmniNoForkProcess *)arg;

    g_nofork_context = process->context;
    run_machine_nofork_thread_task(process);
    return NULL;
}

// Called when the guest does execve(). In no-fork mode this replaces the
// currently running machine and continues execution in-process.
static int ShimExecNoFork(char *execfn, char *prog, char **argv, char **envp) {
    struct Machine *old = NULL;
    bool debug = getenv("OMNIKIT_DEBUG_EXEC_LOOP") != NULL;

    for (;;) {
        if (old) {
            teardown_exec_source(old);
            old = NULL;
        }
        if (debug) {
            fprintf(stderr, "[exec-loop] nofork creating replacement machine for %s\n",
                    prog ? prog : "<null>");
            fflush(stderr);
        }
        struct Machine *machine = NewMachine(NewSystem(XED_MACHINE_MODE_LONG), 0);
        if (!machine) blink_host_exit(127);

        machine->system->trapexit = true;
        nofork_context_set_current_machine(g_nofork_context, machine);

        prepare_exec_machine(machine, old, execfn, prog, argv, envp);

        clear_exec_request();
        if (debug) {
            fprintf(stderr, "[exec-loop] nofork entering execute loop machine=%p\n",
                    (void *)machine);
            fflush(stderr);
        }
        if (run_machine_nofork(machine) == kMachineExecTrap && g_exec_request.pending) {
            old = machine;
            execfn = g_exec_request.execfn;
            prog = g_exec_request.prog;
            argv = g_exec_request.argv;
            envp = g_exec_request.envp;
            continue;
        }
    }
}

typedef int (*blink_runtime_setup_fn)(const blink_run_config_t *, const flatvfs_t *);

static int blink_run_nofork_interactive_impl(const blink_run_config_t *config,
                                             const flatvfs_t *vfs,
                                             blink_runtime_setup_fn setup_fn,
                                             int timeout_ms,
                                             int *timed_out) {
    int rc = -1;
    int saved_errno = 0;
    bool timeout_thread_started = false;
    pthread_t timeout_thread;
    struct OmniNoForkContext context;
    struct NoForkTimeoutThreadArgs timeout_args;
    struct BlinkRuntimeSignalHandlers signal_handlers = {0};
    void (*old_sigpipe)(int);
    char pathbuf[PATH_MAX];
    char *empty_envp[] = {NULL};

    if (init_nofork_context(&context) != 0) {
        return -1;
    }

    pthread_mutex_lock(&g_nofork_runtime_lock);
    g_nofork_context = &context;
    old_sigpipe = signal(SIGPIPE, SIG_IGN);

    if (!sigsetjmp(context.escape, 1)) {
        if (install_blink_runtime_signal_handlers(&signal_handlers) != 0) {
            saved_errno = errno;
            goto nofork_interactive_cleanup;
        }
        if (setup_fn(config, vfs) != 0) {
            saved_errno = errno;
            goto nofork_interactive_cleanup;
        }

        if (timeout_ms > 0) {
            int err;
            timeout_args.context = &context;
            timeout_args.timeout_ms = timeout_ms;
            if ((err = pthread_create(&timeout_thread, NULL,
                                      nofork_timeout_thread_main, &timeout_args)) != 0) {
                saved_errno = err;
                goto nofork_interactive_cleanup;
            }
            timeout_thread_started = true;
        }

        strncpy(pathbuf, config->program_path, sizeof(pathbuf) - 1);
        pathbuf[sizeof(pathbuf) - 1] = '\0';

        ShimExecNoFork(pathbuf, pathbuf, (char **)config->argv,
                       config->envp ? (char **)config->envp : empty_envp);
    }

    rc = context.exit_code;

nofork_interactive_cleanup:
    VfsCloseAll();
    nofork_context_finish(&context);
    if (timeout_thread_started) {
        pthread_join(timeout_thread, NULL);
    }
    restore_blink_runtime_signal_handlers(&signal_handlers);
    if (old_sigpipe != SIG_ERR) {
        signal(SIGPIPE, old_sigpipe);
    }
    g_nofork_context = NULL;
    pthread_mutex_unlock(&g_nofork_runtime_lock);

    if (timed_out) {
        *timed_out = context.timed_out ? 1 : 0;
    }
    destroy_nofork_context(&context);

    if (saved_errno) {
        errno = saved_errno;
        return -1;
    }
    return rc;
}

static void *blink_pty_session_thread_main(void *arg) {
    struct blink_pty_session_impl *session =
        (struct blink_pty_session_impl *)arg;
    struct BlinkRuntimeSignalHandlers signal_handlers = {0};
    void (*old_sigpipe)(int) = SIG_ERR;
    char pathbuf[PATH_MAX];
    char *empty_envp[] = {NULL};
    int saved_errno = 0;

    session->exit_code = -1;
    session->wait_errno = 0;

    if (init_nofork_context(&session->context) != 0) {
        session->wait_errno = errno;
        return NULL;
    }
    session->context_initialized = true;
    session->context.has_tty = true;
    configure_nofork_tty_defaults(&session->context, session->initial_rows,
                                  session->initial_cols);

    pthread_mutex_lock(&g_nofork_runtime_lock);
    g_nofork_context = &session->context;
    old_sigpipe = signal(SIGPIPE, SIG_IGN);

    if (!sigsetjmp(session->context.escape, 1)) {
        if (install_blink_runtime_signal_handlers(&signal_handlers) != 0) {
            saved_errno = errno;
            goto session_cleanup;
        }
        if (host_runtime_setup(&session->config, NULL) != 0) {
            saved_errno = errno;
            goto session_cleanup;
        }
        if (redirect_guest_fd(STDIN_FILENO, session->slave_fd) == -1 ||
            redirect_guest_fd(STDOUT_FILENO, session->slave_fd) == -1 ||
            redirect_guest_fd(STDERR_FILENO, session->slave_fd) == -1) {
            saved_errno = errno;
            goto session_cleanup;
        }
        if (atomic_load_explicit(&session->terminate_requested, memory_order_acquire)) {
            session->context.exit_code = 130;
            goto session_cleanup;
        }

        strncpy(pathbuf, session->config.program_path, sizeof(pathbuf) - 1);
        pathbuf[sizeof(pathbuf) - 1] = '\0';

        ShimExecNoFork(pathbuf, pathbuf, (char **)session->config.argv,
                       session->config.envp ? (char **)session->config.envp : empty_envp);
    }

session_cleanup:
    if (session->slave_fd != -1) {
        close(session->slave_fd);
        session->slave_fd = -1;
    }
    VfsCloseAll();
    nofork_context_finish(&session->context);
    restore_blink_runtime_signal_handlers(&signal_handlers);
    if (old_sigpipe != SIG_ERR) {
        signal(SIGPIPE, old_sigpipe);
    }
    g_nofork_context = NULL;
    pthread_mutex_unlock(&g_nofork_runtime_lock);

    session->exit_code = session->context.exit_code;
    if (saved_errno) {
        session->wait_errno = saved_errno;
    }
    if (session->context_initialized) {
        destroy_nofork_context(&session->context);
        session->context_initialized = false;
    }
    if (session->tempdir) {
        if (remove_tree(session->tempdir) == -1 && !session->wait_errno) {
            session->wait_errno = errno;
        }
        free(session->tempdir);
        session->tempdir = NULL;
    }
    return NULL;
}

static int pty_session_request_terminate(struct blink_pty_session_impl *session) {
    struct Machine *machine = NULL;

    if (!session) {
        errno = EINVAL;
        return -1;
    }

    atomic_store_explicit(&session->terminate_requested, true, memory_order_release);
    if (!session->context_initialized) {
        return 0;
    }

    pthread_mutex_lock(&session->context.lock);
    machine = session->context.current_machine;
    if (machine) {
        atomic_store_explicit(&machine->killed, true, memory_order_release);
        atomic_store_explicit(&machine->attention, true, memory_order_release);
    }
    pthread_cond_broadcast(&session->context.cond);
    pthread_mutex_unlock(&session->context.lock);
    return 0;
}

static int blink_run_nofork_captured_impl(const blink_run_config_t *config,
                                          blink_run_result_t *result,
                                          int timeout_ms,
                                          const flatvfs_t *vfs,
                                          blink_runtime_setup_fn setup_fn) {
    int err;
    int rc = -1;
    int saved_errno = 0;
    int stdout_pipe[2] = {-1, -1};
    int stderr_pipe[2] = {-1, -1};
    bool timeout_thread_started = false;
    bool stdout_reader_started = false;
    bool stderr_reader_started = false;
    pthread_t timeout_thread;
    pthread_t stdout_reader_thread;
    pthread_t stderr_reader_thread;
    struct OmniNoForkContext context;
    struct NoForkTimeoutThreadArgs timeout_args;
    struct CapturePipeState stdout_state = {.fd = -1, .buf = NULL, .len = 0, .error = 0};
    struct CapturePipeState stderr_state = {.fd = -1, .buf = NULL, .len = 0, .error = 0};
    struct BlinkRuntimeSignalHandlers signal_handlers = {0};
    void (*old_sigpipe)(int);
    char pathbuf[PATH_MAX];
    char *empty_envp[] = {NULL};

    memset(result, 0, sizeof(*result));

    if (init_nofork_context(&context) != 0) {
        return -1;
    }

    pthread_mutex_lock(&g_nofork_runtime_lock);
    g_nofork_context = &context;
    old_sigpipe = signal(SIGPIPE, SIG_IGN);

    if (!sigsetjmp(context.escape, 1)) {
        if (install_blink_runtime_signal_handlers(&signal_handlers) != 0) {
            saved_errno = errno;
            goto nofork_captured_cleanup_locked;
        }
        if (setup_fn(config, vfs) != 0) {
            saved_errno = errno;
            goto nofork_captured_cleanup_locked;
        }

        if (pipe(stdout_pipe) == -1 || pipe(stderr_pipe) == -1) {
            saved_errno = errno;
            goto nofork_captured_cleanup_locked;
        }

        stdout_state.fd = stdout_pipe[0];
        stderr_state.fd = stderr_pipe[0];
        if ((err = pthread_create(&stdout_reader_thread, NULL, capture_pipe_reader_main,
                                  &stdout_state)) != 0) {
            saved_errno = err;
            goto nofork_captured_cleanup_locked;
        }
        stdout_reader_started = true;
        if ((err = pthread_create(&stderr_reader_thread, NULL, capture_pipe_reader_main,
                                  &stderr_state)) != 0) {
            saved_errno = err;
            goto nofork_captured_cleanup_locked;
        }
        stderr_reader_started = true;

        if (redirect_guest_fd(STDOUT_FILENO, stdout_pipe[1]) == -1 ||
            redirect_guest_fd(STDERR_FILENO, stderr_pipe[1]) == -1) {
            saved_errno = errno;
            goto nofork_captured_cleanup_locked;
        }
        close(stdout_pipe[1]);
        stdout_pipe[1] = -1;
        close(stderr_pipe[1]);
        stderr_pipe[1] = -1;

        if (timeout_ms > 0) {
            int err;
            timeout_args.context = &context;
            timeout_args.timeout_ms = timeout_ms;
            if ((err = pthread_create(&timeout_thread, NULL,
                                      nofork_timeout_thread_main, &timeout_args)) != 0) {
                saved_errno = err;
                goto nofork_captured_cleanup_locked;
            }
            timeout_thread_started = true;
        }

        strncpy(pathbuf, config->program_path, sizeof(pathbuf) - 1);
        pathbuf[sizeof(pathbuf) - 1] = '\0';

        ShimExecNoFork(pathbuf, pathbuf, (char **)config->argv,
                       config->envp ? (char **)config->envp : empty_envp);
    }

    rc = saved_errno ? -1 : 0;

nofork_captured_cleanup_locked:
    if (stdout_pipe[1] != -1) {
        close(stdout_pipe[1]);
        stdout_pipe[1] = -1;
    }
    if (stderr_pipe[1] != -1) {
        close(stderr_pipe[1]);
        stderr_pipe[1] = -1;
    }
    VfsCloseAll();
    nofork_context_finish(&context);
    if (timeout_thread_started) {
        pthread_join(timeout_thread, NULL);
    }
    if (old_sigpipe != SIG_ERR) {
        signal(SIGPIPE, old_sigpipe);
    }
    g_nofork_context = NULL;
    pthread_mutex_unlock(&g_nofork_runtime_lock);

    if (stdout_pipe[0] != -1 && !stdout_reader_started) {
        close(stdout_pipe[0]);
        stdout_pipe[0] = -1;
    }
    if (stderr_pipe[0] != -1 && !stderr_reader_started) {
        close(stderr_pipe[0]);
        stderr_pipe[0] = -1;
    }
    if (stdout_reader_started) {
        pthread_join(stdout_reader_thread, NULL);
    }
    if (stderr_reader_started) {
        pthread_join(stderr_reader_thread, NULL);
    }
    restore_blink_runtime_signal_handlers(&signal_handlers);

    if (!saved_errno && stdout_state.error) {
        saved_errno = stdout_state.error;
    }
    if (!saved_errno && stderr_state.error) {
        saved_errno = stderr_state.error;
    }

    if (rc == 0 && !saved_errno) {
        result->exit_code = context.exit_code;
        result->timed_out = context.timed_out ? 1 : 0;
        result->stdout_buf = stdout_state.buf;
        result->stdout_len = stdout_state.len;
        result->stderr_buf = stderr_state.buf;
        result->stderr_len = stderr_state.len;
    } else {
        free(stdout_state.buf);
        free(stderr_state.buf);
    }

    destroy_nofork_context(&context);

    if (saved_errno) {
        errno = saved_errno;
        return -1;
    }
    return rc;
}

static int nofork_create_child_machine(struct Machine *parent, u64 flags, u64 stack,
                                       u64 ctid, int child_pid,
                                       struct Machine **out_machine) {
    struct Machine *child;
    _Atomic(i32) *ctid_ptr;

    child = NewMachine(NewSystem(XED_MACHINE_MODE_LONG), 0);
    if (!child) {
        errno = ENOMEM;
        return -1;
    }
    if (clone_system_state(parent, child, child_pid) == -1) {
        FreeMachine(child);
        return -1;
    }
    clone_machine_state(child, parent, child_pid, stack);
    if ((flags & (CLONE_CHILD_SETTID_LINUX | CLONE_CHILD_CLEARTID_LINUX)) &&
        !(ctid & (sizeof(i32) - 1)) &&
        (ctid_ptr = (_Atomic(i32) *)LookupAddress(child, ctid))) {
        if (flags & CLONE_CHILD_SETTID_LINUX) {
            atomic_store_explicit(ctid_ptr, Little32(child_pid), memory_order_release);
        }
        if (flags & CLONE_CHILD_CLEARTID_LINUX) {
            child->ctid = ctid;
        }
    }
    *out_machine = child;
    return 0;
}

bool OmniNoForkProcessHooksEnabled(void) {
    return g_nofork_context != NULL;
}

bool OmniNoForkIsPseudoProcess(struct Machine *machine) {
    struct OmniNoForkProcess *process;
    struct OmniNoForkContext *context = g_nofork_context;

    if (!context || !machine) return false;
    pthread_mutex_lock(&context->lock);
    process = nofork_find_process_by_machine_locked(context, machine);
    pthread_mutex_unlock(&context->lock);
    return process && !process->is_root && !process->is_thread;
}

bool OmniNoForkIsManagedThread(struct Machine *machine) {
    struct OmniNoForkProcess *process;
    struct OmniNoForkContext *context = g_nofork_context;

    if (!context || !machine) return false;
    pthread_mutex_lock(&context->lock);
    process = nofork_find_process_by_machine_locked(context, machine);
    pthread_mutex_unlock(&context->lock);
    return process && process->is_thread;
}

int OmniNoForkFork(struct Machine *machine, u64 flags, u64 stack, u64 ctid) {
    int err;
    int child_pid;
    struct OmniNoForkContext *context;
    struct OmniNoForkProcess *child_process;
    struct Machine *child_machine;
    bool is_vfork;

    context = g_nofork_context;
    if (!context || !machine || !machine->system) {
        errno = ENOSYS;
        return -1;
    }
    nofork_ensure_root_process(context, machine);
    pthread_mutex_lock(&context->lock);
    child_pid = context->next_pid++;
    pthread_mutex_unlock(&context->lock);

    child_machine = NULL;
    if (nofork_create_child_machine(machine, flags, stack, ctid, child_pid,
                                    &child_machine) == -1) {
        return -1;
    }

    is_vfork = (flags & CLONE_VFORK_LINUX) != 0;
    pthread_mutex_lock(&context->lock);
    {
        struct OmniNoForkProcess *parent_process =
            nofork_find_process_by_pid_locked(context, machine->system->pid);
        child_process =
            nofork_register_process_locked(context, child_machine, child_pid,
                                           machine->system->pid, child_pid, false,
                                           false);
        if (!child_process) {
            pthread_mutex_unlock(&context->lock);
            FreeMachine(child_machine);
            errno = ENOMEM;
            return -1;
        }
        if (parent_process) {
            child_process->sid = parent_process->sid;
            child_process->pgid = parent_process->pgid;
        } else {
            child_process->sid = machine->system->pid;
            child_process->pgid = machine->system->pid;
        }
    }
    if (!child_process) {
        pthread_mutex_unlock(&context->lock);
        FreeMachine(child_machine);
        errno = ENOMEM;
        return -1;
    }
    child_process->is_vfork = is_vfork;
    child_process->parent_released = !is_vfork;
    pthread_mutex_unlock(&context->lock);

    if ((err = pthread_create(&child_process->thread, NULL, nofork_process_thread_main,
                              child_process)) != 0) {
        pthread_mutex_lock(&context->lock);
        nofork_unregister_process_locked(context, child_process);
        pthread_mutex_unlock(&context->lock);
        FreeMachine(child_machine);
        errno = err;
        return -1;
    }
    child_process->thread_started = true;

    if (is_vfork) {
        pthread_mutex_lock(&context->lock);
        while (!child_process->finished && !child_process->parent_released) {
            pthread_cond_wait(&context->cond, &context->lock);
        }
        pthread_mutex_unlock(&context->lock);
    }

    return child_pid;
}

int OmniNoForkSpawnThread(struct Machine *machine, u64 flags, u64 stack, u64 ptid,
                          u64 ctid, u64 tls) {
    int err;
    int tid;
    sigset_t ss, oldss;
    _Atomic(int) *ptid_ptr = NULL;
    _Atomic(int) *ctid_ptr = NULL;
    struct Machine *child_machine;
    struct OmniNoForkContext *context;
    struct OmniNoForkProcess *parent_process;
    struct OmniNoForkProcess *thread_process;

    context = g_nofork_context;
    if (!context || !machine || !machine->system) {
        return -2;
    }
    if ((flags & CLONE_PARENT_SETTID_LINUX) &&
        ((ptid & (sizeof(int) - 1)) ||
         !IsValidMemory(machine, ptid, 4, PROT_READ | PROT_WRITE) ||
         !(ptid_ptr = (_Atomic(int) *)LookupAddress(machine, ptid)))) {
        errno = EFAULT;
        return -1;
    }
    if ((flags & CLONE_CHILD_SETTID_LINUX) &&
        ((ctid & (sizeof(int) - 1)) ||
         !IsValidMemory(machine, ctid, 4, PROT_READ | PROT_WRITE) ||
         !(ctid_ptr = (_Atomic(int) *)LookupAddress(machine, ctid)))) {
        errno = EFAULT;
        return -1;
    }

    nofork_ensure_root_process(context, machine);
    machine->threaded = true;
    machine->system->jit.threaded = true;
    if (!(child_machine = NewMachine(machine->system, machine))) {
        errno = EAGAIN;
        return -1;
    }

    sigfillset(&ss);
    unassert(!pthread_sigmask(SIG_SETMASK, &ss, &oldss));
    tid = child_machine->tid;
    if (flags & CLONE_SETTLS_LINUX) {
        child_machine->fs.base = tls;
    }
    if (flags & CLONE_CHILD_CLEARTID_LINUX) {
        child_machine->ctid = ctid;
    }
    if (flags & CLONE_CHILD_SETTID_LINUX) {
        atomic_store_explicit(ctid_ptr, Little32(tid), memory_order_release);
    }
    Put64(child_machine->ax, 0);
    Put64(child_machine->sp, stack);
    child_machine->spawn_sigmask = oldss;

    pthread_mutex_lock(&context->lock);
    parent_process = nofork_find_process_by_machine_locked(context, machine);
    thread_process = nofork_register_process_locked(
        context, child_machine, tid, parent_process ? parent_process->ppid : getppid(),
        machine->system->pid, false, true);
    if (thread_process) {
        thread_process->sid = parent_process ? parent_process->sid : machine->system->pid;
        thread_process->pgid = parent_process ? parent_process->pgid : machine->system->pid;
        thread_process->parent_released = true;
    }
    pthread_mutex_unlock(&context->lock);

    if (!thread_process) {
        FreeMachine(child_machine);
        unassert(!pthread_sigmask(SIG_SETMASK, &oldss, 0));
        errno = ENOMEM;
        return -1;
    }

    if ((err = pthread_create(&thread_process->thread, NULL, nofork_thread_task_main,
                              thread_process)) != 0) {
        pthread_mutex_lock(&context->lock);
        nofork_unregister_process_locked(context, thread_process);
        pthread_mutex_unlock(&context->lock);
        FreeMachine(child_machine);
        unassert(!pthread_sigmask(SIG_SETMASK, &oldss, 0));
        errno = err;
        return -1;
    }
    thread_process->thread_started = true;
    if (flags & CLONE_PARENT_SETTID_LINUX) {
        atomic_store_explicit(ptid_ptr, Little32(tid), memory_order_release);
    }
    unassert(!pthread_sigmask(SIG_SETMASK, &oldss, 0));
    return tid;
}

int OmniNoForkWait4(struct Machine *machine, int pid, int options,
                    int *out_pid, int *out_wstatus) {
    struct OmniNoForkContext *context;
    struct OmniNoForkProcess *process;
    struct OmniNoForkProcess *caller;
    int rc = -2;
    int wait_status = 0;
    bool should_join = false;

    context = g_nofork_context;
    if (!context || !machine || !machine->system) {
        return -2;
    }

    pthread_mutex_lock(&context->lock);
    caller = nofork_find_process_by_machine_locked(context, machine);
    if (!caller) {
        pthread_mutex_unlock(&context->lock);
        errno = ESRCH;
        return -1;
    }
    for (;;) {
        struct OmniNoForkProcess *candidate = NULL;
        bool matched_child = false;

        for (process = context->processes; process; process = process->next) {
            if (process->waited) continue;
            if (!nofork_process_matches_wait_target_locked(process, caller, pid)) {
                continue;
            }
            matched_child = true;
            if (nofork_process_next_wait_status_locked(process, options, &wait_status)) {
                candidate = process;
                break;
            }
        }

        if (!matched_child) {
            errno = ECHILD;
            rc = -1;
            break;
        }

        if (candidate) {
            process = candidate;
            if (out_pid) *out_pid = process->pid;
            if (out_wstatus) *out_wstatus = wait_status;
            if (process->has_pending_wait_status) {
                nofork_consume_wait_status_locked(process);
            } else {
                process->waited = true;
                should_join = process->thread_started;
            }
            rc = process->pid;
            break;
        }
        if (options & WNOHANG) {
            if (out_pid) *out_pid = 0;
            rc = 0;
            break;
        }
        pthread_cond_wait(&context->cond, &context->lock);
    }
    pthread_mutex_unlock(&context->lock);

    if (rc > 0 && process && should_join) {
        pthread_join(process->thread, NULL);
        pthread_mutex_lock(&context->lock);
        nofork_unregister_process_locked(context, process);
        pthread_mutex_unlock(&context->lock);
    }
    return rc;
}

int OmniNoForkGetpid(struct Machine *machine) {
    if (!machine || !machine->system) return -1;
    return machine->system->pid;
}

static struct OmniNoForkProcess *nofork_find_task_locked(struct OmniNoForkContext *context,
                                                         int tid) {
    return nofork_find_process_by_pid_locked(context, tid);
}

void OmniNoForkPollState(struct Machine *machine) {
    struct OmniNoForkContext *context;
    struct OmniNoForkProcess *process;

    context = g_nofork_context;
    if (!context || !machine || !machine->system) return;

    pthread_mutex_lock(&context->lock);
    process = nofork_find_process_by_machine_locked(context, machine);
    while (process && process->stopped && !process->finished && !context->finished &&
           !atomic_load_explicit(&machine->killed, memory_order_acquire)) {
        pthread_cond_wait(&context->cond, &context->lock);
        process = nofork_find_process_by_machine_locked(context, machine);
    }
    pthread_mutex_unlock(&context->lock);
}

int OmniNoForkGetppid(struct Machine *machine) {
    struct OmniNoForkProcess *process;
    struct OmniNoForkContext *context = g_nofork_context;

    if (!context || !machine) return -1;
    pthread_mutex_lock(&context->lock);
    process = nofork_find_process_by_machine_locked(context, machine);
    pthread_mutex_unlock(&context->lock);
    return process ? process->ppid : -1;
}

int OmniNoForkKill(struct Machine *machine, int pid, int sig) {
    struct OmniNoForkContext *context;
    struct OmniNoForkProcess *process;
    struct OmniNoForkProcess *caller;
    int handler;
    int matched = 0;

    context = g_nofork_context;
    if (!context || !machine || !machine->system) {
        return -2;
    }
    if (pid == INT_MIN || sig < 0 || sig > 64) {
        errno = EINVAL;
        return -1;
    }

    nofork_ensure_root_process(context, machine);
    pthread_mutex_lock(&context->lock);
    caller = nofork_find_process_by_machine_locked(context, machine);
    if (!caller) {
        pthread_mutex_unlock(&context->lock);
        errno = ESRCH;
        return -1;
    }

    for (process = context->processes; process; process = process->next) {
        bool match = false;
        if (process->finished) continue;
        if (pid > 0) {
            match = process->tgid == pid;
        } else if (pid == 0) {
            match = process->pgid == caller->pgid;
        } else if (pid == -1) {
            match = true;
        } else {
            match = process->pgid == -pid;
        }
        if (!match) continue;
        ++matched;
        if (!sig) continue;

        if (sig == SIGCONT_LINUX) {
            nofork_resume_process_locked(process);
            handler = nofork_signal_handler_locked(process, sig);
            if (handler != SIG_DFL_LINUX && handler != SIG_IGN_LINUX) {
                nofork_deliver_signal_to_process_locked(process, sig);
            }
            continue;
        }

        if (sig == SIGKILL_LINUX && process->stopped) {
            process->stopped = false;
            process->stop_signal = 0;
            nofork_wake_process_locked(process);
        }

        if (sig == SIGSTOP_LINUX) {
            nofork_record_stopped_status_locked(process, sig);
            continue;
        }

        if (sig == SIGTSTP_LINUX || sig == SIGTTIN_LINUX || sig == SIGTTOU_LINUX) {
            handler = nofork_signal_handler_locked(process, sig);
            if (handler == SIG_DFL_LINUX) {
                nofork_record_stopped_status_locked(process, sig);
                continue;
            }
            if (handler == SIG_IGN_LINUX) {
                continue;
            }
        }

        nofork_deliver_signal_to_process_locked(process, sig);
    }
    pthread_mutex_unlock(&context->lock);

    if (!matched) {
        errno = ESRCH;
        return -1;
    }
    return 0;
}

int OmniNoForkTkill(struct Machine *machine, int tid, int sig) {
    struct OmniNoForkContext *context;
    struct OmniNoForkProcess *process;

    context = g_nofork_context;
    if (!context || !machine || !machine->system) {
        return -2;
    }
    if (tid < 1 || sig < 0 || sig > 64) {
        errno = EINVAL;
        return -1;
    }

    pthread_mutex_lock(&context->lock);
    process = nofork_find_task_locked(context, tid);
    if (!process || process->finished) {
        pthread_mutex_unlock(&context->lock);
        errno = ESRCH;
        return -1;
    }
    if (sig) {
        if (sig == SIGSTOP_LINUX) {
            nofork_record_stopped_status_locked(process, sig);
        } else if (sig == SIGCONT_LINUX) {
            nofork_resume_process_locked(process);
        } else {
            nofork_deliver_signal_to_process_locked(process, sig);
        }
    }
    pthread_mutex_unlock(&context->lock);
    return 0;
}

int OmniNoForkTgkill(struct Machine *machine, int pid, int tid, int sig) {
    struct OmniNoForkContext *context;
    struct OmniNoForkProcess *process;

    context = g_nofork_context;
    if (!context || !machine || !machine->system) {
        return -2;
    }
    if (pid < 1 || tid < 1 || sig < 0 || sig > 64) {
        errno = EINVAL;
        return -1;
    }

    pthread_mutex_lock(&context->lock);
    process = nofork_find_task_locked(context, tid);
    if (!process || process->finished || process->tgid != pid) {
        pthread_mutex_unlock(&context->lock);
        errno = ESRCH;
        return -1;
    }
    if (sig) {
        if (sig == SIGSTOP_LINUX) {
            nofork_record_stopped_status_locked(process, sig);
        } else if (sig == SIGCONT_LINUX) {
            nofork_resume_process_locked(process);
        } else {
            nofork_deliver_signal_to_process_locked(process, sig);
        }
    }
    pthread_mutex_unlock(&context->lock);
    return 0;
}

int OmniNoForkSetsid(struct Machine *machine) {
    struct OmniNoForkContext *context;
    struct OmniNoForkProcess *process;
    int sid;

    context = g_nofork_context;
    if (!context || !machine || !machine->system) {
        return -2;
    }
    nofork_ensure_root_process(context, machine);
    pthread_mutex_lock(&context->lock);
    process = nofork_find_process_by_machine_locked(context, machine);
    if (!process) {
        pthread_mutex_unlock(&context->lock);
        errno = ESRCH;
        return -1;
    }
    if (process->pgid == process->pid) {
        pthread_mutex_unlock(&context->lock);
        errno = EPERM;
        return -1;
    }
    process->sid = process->pid;
    process->pgid = process->pid;
    sid = process->sid;
    pthread_mutex_unlock(&context->lock);
    return sid;
}

int OmniNoForkGetsid(struct Machine *machine, int pid) {
    struct OmniNoForkContext *context;
    struct OmniNoForkProcess *process;

    context = g_nofork_context;
    if (!context || !machine || !machine->system) {
        return -2;
    }
    nofork_ensure_root_process(context, machine);
    pthread_mutex_lock(&context->lock);
    if (pid == 0) pid = machine->system->pid;
    process = nofork_find_process_by_pid_locked(context, pid);
    pthread_mutex_unlock(&context->lock);
    if (!process || process->finished) {
        errno = ESRCH;
        return -1;
    }
    return process->sid;
}

int OmniNoForkGetpgid(struct Machine *machine, int pid) {
    struct OmniNoForkContext *context;
    struct OmniNoForkProcess *process;

    context = g_nofork_context;
    if (!context || !machine || !machine->system) {
        return -2;
    }
    nofork_ensure_root_process(context, machine);
    pthread_mutex_lock(&context->lock);
    if (pid == 0) pid = machine->system->pid;
    process = nofork_find_process_by_pid_locked(context, pid);
    pthread_mutex_unlock(&context->lock);
    if (!process || process->finished) {
        errno = ESRCH;
        return -1;
    }
    return process->pgid;
}

int OmniNoForkGetpgrp(struct Machine *machine) {
    return OmniNoForkGetpgid(machine, 0);
}

int OmniNoForkSetpgid(struct Machine *machine, int pid, int gid) {
    struct OmniNoForkContext *context;
    struct OmniNoForkProcess *caller;
    struct OmniNoForkProcess *target;

    context = g_nofork_context;
    if (!context || !machine || !machine->system) {
        return -2;
    }
    if (gid < 0) {
        errno = EINVAL;
        return -1;
    }
    nofork_ensure_root_process(context, machine);
    pthread_mutex_lock(&context->lock);
    caller = nofork_find_process_by_machine_locked(context, machine);
    if (!caller) {
        pthread_mutex_unlock(&context->lock);
        errno = ESRCH;
        return -1;
    }
    if (pid == 0) pid = caller->pid;
    target = nofork_find_process_by_pid_locked(context, pid);
    if (!target || target->finished) {
        pthread_mutex_unlock(&context->lock);
        errno = ESRCH;
        return -1;
    }
    if (gid == 0) gid = target->pid;
    if (target != caller && target->ppid != caller->pid) {
        pthread_mutex_unlock(&context->lock);
        errno = EPERM;
        return -1;
    }
    if (target->sid != caller->sid || target->pid == target->sid) {
        pthread_mutex_unlock(&context->lock);
        errno = EPERM;
        return -1;
    }
    if (gid != target->pid &&
        !nofork_find_process_in_group_locked(context, caller->sid, gid)) {
        pthread_mutex_unlock(&context->lock);
        errno = EPERM;
        return -1;
    }
    target->pgid = gid;
    pthread_mutex_unlock(&context->lock);
    return 0;
}

int OmniNoForkTcgets(struct Machine *machine, int fd, struct termios *termios_state) {
    struct OmniNoForkContext *context = g_nofork_context;
    (void)fd;
    if (!context || !machine || !machine->system) {
        return -2;
    }
    if (!termios_state) {
        errno = EINVAL;
        return -1;
    }
    pthread_mutex_lock(&context->lock);
    if (!context->has_tty) {
        pthread_mutex_unlock(&context->lock);
        errno = ENOTTY;
        return -1;
    }
    *termios_state = context->tty_termios;
    pthread_mutex_unlock(&context->lock);
    return 0;
}

int OmniNoForkTcsets(struct Machine *machine, int fd, int request,
                     const struct termios *termios_state) {
    struct OmniNoForkContext *context = g_nofork_context;
    (void)fd;
    (void)request;
    if (!context || !machine || !machine->system) {
        return -2;
    }
    if (!termios_state) {
        errno = EINVAL;
        return -1;
    }
    pthread_mutex_lock(&context->lock);
    if (!context->has_tty) {
        pthread_mutex_unlock(&context->lock);
        errno = ENOTTY;
        return -1;
    }
    context->tty_termios = *termios_state;
    pthread_mutex_unlock(&context->lock);
    return 0;
}

int OmniNoForkTcgetwinsize(struct Machine *machine, int fd,
                           struct winsize *winsize_state) {
    struct OmniNoForkContext *context = g_nofork_context;
    (void)fd;
    if (!context || !machine || !machine->system) {
        return -2;
    }
    if (!winsize_state) {
        errno = EINVAL;
        return -1;
    }
    pthread_mutex_lock(&context->lock);
    if (!context->has_tty) {
        pthread_mutex_unlock(&context->lock);
        errno = ENOTTY;
        return -1;
    }
    *winsize_state = context->tty_winsize;
    pthread_mutex_unlock(&context->lock);
    return 0;
}

int OmniNoForkTcsetwinsize(struct Machine *machine, int fd,
                           const struct winsize *winsize_state) {
    struct OmniNoForkContext *context = g_nofork_context;
    struct OmniNoForkProcess *process;
    (void)fd;
    if (!context || !machine || !machine->system) {
        return -2;
    }
    if (!winsize_state) {
        errno = EINVAL;
        return -1;
    }
    pthread_mutex_lock(&context->lock);
    if (!context->has_tty) {
        pthread_mutex_unlock(&context->lock);
        errno = ENOTTY;
        return -1;
    }
    context->tty_winsize = *winsize_state;
    if (!context->tty_winsize.ws_row) context->tty_winsize.ws_row = 24;
    if (!context->tty_winsize.ws_col) context->tty_winsize.ws_col = 80;
    for (process = context->processes; process; process = process->next) {
        if (!process->finished && process->sid == context->tty_sid &&
            process->pgid == context->tty_pgrp) {
            nofork_deliver_signal_to_process_locked(process, SIGWINCH_LINUX);
        }
    }
    pthread_mutex_unlock(&context->lock);
    return 0;
}

int OmniNoForkTcgetsid(struct Machine *machine, int fd) {
    struct OmniNoForkContext *context = g_nofork_context;
    (void)fd;
    if (!context || !machine || !machine->system) {
        return -2;
    }
    pthread_mutex_lock(&context->lock);
    if (!context->has_tty || !context->tty_sid) {
        pthread_mutex_unlock(&context->lock);
        errno = ENOTTY;
        return -1;
    }
    fd = context->tty_sid;
    pthread_mutex_unlock(&context->lock);
    return fd;
}

int OmniNoForkTcgetpgrp(struct Machine *machine, int fd) {
    struct OmniNoForkContext *context = g_nofork_context;
    int pgrp;
    (void)fd;
    if (!context || !machine || !machine->system) {
        return -2;
    }
    pthread_mutex_lock(&context->lock);
    if (!context->has_tty) {
        pthread_mutex_unlock(&context->lock);
        errno = ENOTTY;
        return -1;
    }
    pgrp = nofork_find_foreground_pgrp_locked(context);
    pthread_mutex_unlock(&context->lock);
    if (!pgrp) {
        errno = ENOTTY;
        return -1;
    }
    return pgrp;
}

int OmniNoForkTcsetpgrp(struct Machine *machine, int fd, int pgrp) {
    struct OmniNoForkContext *context;
    struct OmniNoForkProcess *caller;
    (void)fd;

    context = g_nofork_context;
    if (!context || !machine || !machine->system) {
        return -2;
    }
    if (pgrp <= 0) {
        errno = EINVAL;
        return -1;
    }
    nofork_ensure_root_process(context, machine);
    pthread_mutex_lock(&context->lock);
    caller = nofork_find_process_by_machine_locked(context, machine);
    if (!caller) {
        pthread_mutex_unlock(&context->lock);
        errno = ESRCH;
        return -1;
    }
    if (!context->has_tty || !context->tty_sid || caller->sid != context->tty_sid) {
        pthread_mutex_unlock(&context->lock);
        errno = ENOTTY;
        return -1;
    }
    if (!nofork_find_process_in_group_locked(context, caller->sid, pgrp)) {
        pthread_mutex_unlock(&context->lock);
        errno = ESRCH;
        return -1;
    }
    context->tty_pgrp = pgrp;
    pthread_mutex_unlock(&context->lock);
    return 0;
}

static void nofork_fill_user_regs_locked(
    struct Machine *machine, struct user_regs_struct_linux_marshaled *regs) {
    memset(regs, 0, sizeof(*regs));
    Write64(regs->r15, Get64(machine->r15));
    Write64(regs->r14, Get64(machine->r14));
    Write64(regs->r13, Get64(machine->r13));
    Write64(regs->r12, Get64(machine->r12));
    Write64(regs->rbp, Get64(machine->bp));
    Write64(regs->rbx, Get64(machine->bx));
    Write64(regs->r11, Get64(machine->r11));
    Write64(regs->r10, Get64(machine->r10));
    Write64(regs->r9, Get64(machine->r9));
    Write64(regs->r8, Get64(machine->r8));
    Write64(regs->rax, Get64(machine->ax));
    Write64(regs->rcx, Get64(machine->cx));
    Write64(regs->rdx, Get64(machine->dx));
    Write64(regs->rsi, Get64(machine->si));
    Write64(regs->rdi, Get64(machine->di));
    Write64(regs->orig_rax, Get64(machine->ax));
    Write64(regs->rip, machine->ip);
    Write64(regs->cs, machine->cs.sel ? machine->cs.sel : USER_CS_LINUX);
    Write64(regs->eflags, ExportFlags(machine->flags));
    Write64(regs->rsp, Get64(machine->sp));
    Write64(regs->ss, machine->ss.sel ? machine->ss.sel : USER_DS_LINUX);
    Write64(regs->fs_base, machine->fs.base);
    Write64(regs->gs_base, machine->gs.base);
    Write64(regs->ds, machine->ds.sel ? machine->ds.sel : USER_DS_LINUX);
    Write64(regs->es, machine->es.sel ? machine->es.sel : USER_DS_LINUX);
    Write64(regs->fs, machine->fs.sel ? machine->fs.sel : USER_DS_LINUX);
    Write64(regs->gs, machine->gs.sel ? machine->gs.sel : USER_DS_LINUX);
}

static int nofork_load_user_regs_locked(
    struct Machine *machine, const struct user_regs_struct_linux_marshaled *regs) {
    Put64(machine->r15, Read64(regs->r15));
    Put64(machine->r14, Read64(regs->r14));
    Put64(machine->r13, Read64(regs->r13));
    Put64(machine->r12, Read64(regs->r12));
    Put64(machine->bp, Read64(regs->rbp));
    Put64(machine->bx, Read64(regs->rbx));
    Put64(machine->r11, Read64(regs->r11));
    Put64(machine->r10, Read64(regs->r10));
    Put64(machine->r9, Read64(regs->r9));
    Put64(machine->r8, Read64(regs->r8));
    Put64(machine->ax, Read64(regs->rax));
    Put64(machine->cx, Read64(regs->rcx));
    Put64(machine->dx, Read64(regs->rdx));
    Put64(machine->si, Read64(regs->rsi));
    Put64(machine->di, Read64(regs->rdi));
    machine->ip = Read64(regs->rip);
    ImportFlags(machine, Read64(regs->eflags));
    Put64(machine->sp, Read64(regs->rsp));
    machine->fs.base = Read64(regs->fs_base);
    machine->gs.base = Read64(regs->gs_base);
    return 0;
}

i64 OmniNoForkPtrace(struct Machine *machine, int request, int pid, i64 addr, i64 data) {
    struct OmniNoForkContext *context;
    struct OmniNoForkProcess *caller;
    struct OmniNoForkProcess *target;
    struct user_regs_struct_linux_marshaled regs;
    u64 word;

    context = g_nofork_context;
    if (!context || !machine || !machine->system) {
        return -2;
    }

    nofork_ensure_root_process(context, machine);
    pthread_mutex_lock(&context->lock);
    caller = nofork_find_process_by_machine_locked(context, machine);
    if (!caller) {
        pthread_mutex_unlock(&context->lock);
        errno = ESRCH;
        return -1;
    }

    if (request == PTRACE_TRACEME_LINUX) {
        if (caller->tracer_pid && caller->tracer_pid != caller->ppid) {
            pthread_mutex_unlock(&context->lock);
            errno = EPERM;
            return -1;
        }
        caller->tracer_pid = caller->ppid;
        pthread_mutex_unlock(&context->lock);
        return 0;
    }

    target = nofork_find_process_by_pid_locked(context, pid);
    if (!target || !target->machine) {
        pthread_mutex_unlock(&context->lock);
        errno = ESRCH;
        return -1;
    }

    switch (request) {
        case PTRACE_ATTACH_LINUX:
            if (target == caller || target->tracer_pid) {
                pthread_mutex_unlock(&context->lock);
                errno = EPERM;
                return -1;
            }
            target->tracer_pid = caller->pid;
            nofork_record_stopped_status_locked(target, SIGSTOP_LINUX);
            pthread_mutex_unlock(&context->lock);
            return 0;

        case PTRACE_DETACH_LINUX:
            if (target->tracer_pid != caller->pid) {
                pthread_mutex_unlock(&context->lock);
                errno = EPERM;
                return -1;
            }
            target->tracer_pid = 0;
            if (data > 0) {
                nofork_deliver_signal_to_process_locked(target, (int)data);
            }
            nofork_resume_process_locked(target);
            pthread_mutex_unlock(&context->lock);
            return 0;

        case PTRACE_CONT_LINUX:
            if (target->tracer_pid != caller->pid) {
                pthread_mutex_unlock(&context->lock);
                errno = EPERM;
                return -1;
            }
            if (data > 0) {
                nofork_deliver_signal_to_process_locked(target, (int)data);
            }
            nofork_resume_process_locked(target);
            pthread_mutex_unlock(&context->lock);
            return 0;

        case PTRACE_KILL_LINUX:
            if (target->tracer_pid != caller->pid) {
                pthread_mutex_unlock(&context->lock);
                errno = EPERM;
                return -1;
            }
            target->tracer_pid = 0;
            nofork_deliver_signal_to_process_locked(target, SIGKILL_LINUX);
            pthread_mutex_unlock(&context->lock);
            return 0;

        case PTRACE_GETREGS_LINUX:
            if (target->tracer_pid != caller->pid || !target->stopped) {
                pthread_mutex_unlock(&context->lock);
                errno = EPERM;
                return -1;
            }
            nofork_fill_user_regs_locked(target->machine, &regs);
            pthread_mutex_unlock(&context->lock);
            if (!IsValidMemory(machine, data, sizeof(regs), PROT_WRITE) ||
                CopyToUserWrite(machine, data, &regs, sizeof(regs)) == -1) {
                return -1;
            }
            return 0;

        case PTRACE_SETREGS_LINUX:
            if (target->tracer_pid != caller->pid || !target->stopped) {
                pthread_mutex_unlock(&context->lock);
                errno = EPERM;
                return -1;
            }
            pthread_mutex_unlock(&context->lock);
            if (!IsValidMemory(machine, data, sizeof(regs), PROT_READ) ||
                CopyFromUserRead(machine, &regs, data, sizeof(regs)) == -1) {
                return -1;
            }
            pthread_mutex_lock(&context->lock);
            target = nofork_find_process_by_pid_locked(context, pid);
            if (!target || !target->machine || target->tracer_pid != caller->pid ||
                !target->stopped) {
                pthread_mutex_unlock(&context->lock);
                errno = ESRCH;
                return -1;
            }
            nofork_load_user_regs_locked(target->machine, &regs);
            pthread_mutex_unlock(&context->lock);
            return 0;

        case PTRACE_PEEKDATA_LINUX:
        case PTRACE_PEEKTEXT_LINUX:
            if (target->tracer_pid != caller->pid || !target->stopped ||
                (addr & (sizeof(word) - 1)) ||
                !IsValidMemory(target->machine, addr, sizeof(word), PROT_READ)) {
                pthread_mutex_unlock(&context->lock);
                errno = EPERM;
                return -1;
            }
            word = Read64(LookupAddress(target->machine, addr));
            pthread_mutex_unlock(&context->lock);
            errno = 0;
            return (i64)word;

        case PTRACE_POKEDATA_LINUX:
        case PTRACE_POKETEXT_LINUX:
            if (target->tracer_pid != caller->pid || !target->stopped ||
                (addr & (sizeof(word) - 1)) ||
                !IsValidMemory(target->machine, addr, sizeof(word),
                               PROT_READ | PROT_WRITE)) {
                pthread_mutex_unlock(&context->lock);
                errno = EPERM;
                return -1;
            }
            Write64(LookupAddress(target->machine, addr), (u64)data);
            pthread_mutex_unlock(&context->lock);
            return 0;

        default:
            pthread_mutex_unlock(&context->lock);
            errno = EINVAL;
            return -1;
    }
}

_Noreturn void OmniNoForkExitSignal(struct Machine *machine, int sig) {
    struct OmniNoForkContext *context;
    struct OmniNoForkProcess *process;

    context = g_nofork_context;
    if (!context || !machine || !machine->system) {
        _Exit((128 + sig) & 255);
    }
    pthread_mutex_lock(&context->lock);
    process = nofork_find_process_by_machine_locked(context, machine);
    if (process) {
        process->stopped = false;
        process->stop_signal = 0;
        process->continued_pending = false;
        process->final_wait_status = sig & 127;
        process->has_final_wait_status = true;
    }
    pthread_mutex_unlock(&context->lock);
    machine->system->exitcode = (128 + sig) & 255;
    machine->system->exited = true;
    HaltMachine(machine, kMachineExitTrap);
    __builtin_unreachable();
}

_Noreturn void OmniNoForkExitThread(struct Machine *machine, int rc) {
    struct OmniNoForkContext *context;
    struct OmniNoForkProcess *process;

    context = g_nofork_context;
    if (!context || !machine || !machine->system) {
        _Exit(rc & 255);
    }
    pthread_mutex_lock(&context->lock);
    process = nofork_find_process_by_machine_locked(context, machine);
    if (process) {
        process->requested_exit_code = rc & 255;
        process->exit_requested = true;
        process->group_exit_requested = false;
    }
    pthread_mutex_unlock(&context->lock);
    HaltMachine(machine, kMachineExitTrap);
    __builtin_unreachable();
}

_Noreturn void OmniNoForkExitThreadGroup(struct Machine *machine, int rc) {
    struct OmniNoForkContext *context;
    struct OmniNoForkProcess *process;
    struct OmniNoForkProcess *caller;
    int tgid;

    context = g_nofork_context;
    if (!context || !machine || !machine->system) {
        _Exit(rc & 255);
    }
    pthread_mutex_lock(&context->lock);
    caller = nofork_find_process_by_machine_locked(context, machine);
    tgid = caller ? caller->tgid : machine->system->pid;
    machine->system->exitcode = rc & 255;
    machine->system->exited = true;
    for (process = context->processes; process; process = process->next) {
        if (process->finished || process->tgid != tgid) continue;
        process->requested_exit_code = rc & 255;
        process->group_exit_requested = true;
        if (process != caller && process->machine) {
            process->machine->system->exitcode = rc & 255;
            process->machine->system->exited = true;
            nofork_deliver_signal_to_process_locked(process, SIGKILL_LINUX);
        }
    }
    if (caller) {
        caller->exit_requested = true;
        caller->group_exit_requested = true;
    }
    pthread_mutex_unlock(&context->lock);
    HaltMachine(machine, kMachineExitTrap);
    __builtin_unreachable();
}

_Noreturn void OmniNoForkExitGroup(struct Machine *machine, int rc) {
    if (!machine || !machine->system) {
        _Exit(rc & 255);
    }
    machine->system->exitcode = rc & 255;
    machine->system->exited = true;
    HaltMachine(machine, kMachineExitTrap);
}

// ── Main entry point ─────────────────────────────────────────────────────────

int blink_run(const blink_run_config_t *config,
              blink_run_result_t *result,
              int timeout_ms) {
    if (!config || !result || !config->program_path || !config->argv) {
        errno = EINVAL;
        return -1;
    }

    if (should_use_nofork_runtime()) {
        return blink_run_nofork_captured_impl(config, result, timeout_ms, NULL,
                                              host_runtime_setup);
    }

#if defined(HAVE_FORK)

    memset(result, 0, sizeof(*result));

    // Create pipes for stdout and stderr capture.
    int stdout_pipe[2] = {-1, -1};
    int stderr_pipe[2] = {-1, -1};
    if (pipe(stdout_pipe) == -1) return -1;
    if (pipe(stderr_pipe) == -1) {
        close(stdout_pipe[0]);
        close(stdout_pipe[1]);
        return -1;
    }

    pid_t pid = fork();
    if (pid == -1) {
        int saved = errno;
        close(stdout_pipe[0]); close(stdout_pipe[1]);
        close(stderr_pipe[0]); close(stderr_pipe[1]);
        errno = saved;
        return -1;
    }

    if (pid == 0) {
        // ── Child process ────────────────────────────────────────────────
        struct BlinkRuntimeSignalHandlers signal_handlers;
        close(stdout_pipe[0]);  // close read ends
        close(stderr_pipe[0]);

        // Redirect stdout/stderr to pipe write ends.
        dup2(stdout_pipe[1], STDOUT_FILENO);
        dup2(stderr_pipe[1], STDERR_FILENO);
        close(stdout_pipe[1]);
        close(stderr_pipe[1]);

        // Initialize blink subsystems.
        WriteErrorInit();
        InitMap();

        FLAG_nolinear = should_force_nolinear_host_runtime();

#ifndef DISABLE_VFS
        if (config->host_mount_count > 0 && !config->vfs_prefix) {
            _exit(127);
        }
        if (config->vfs_prefix) {
            if (init_isolated_host_prefix(config->vfs_prefix)) {
                _exit(127);
            }
            if (OmniInstallGuestFdMounts()) {
                _exit(127);
            }
        }
        if (install_extra_host_mounts(config)) {
            _exit(127);
        }
#endif

        InitBus();

        // Build argv for blink. We pass the program path as the command.
        char pathbuf[PATH_MAX];
        strncpy(pathbuf, config->program_path, sizeof(pathbuf) - 1);
        pathbuf[sizeof(pathbuf) - 1] = '\0';

        // Build argv array: program path + user args
        int total_argc = config->argc;
        char **child_argv = calloc((size_t)(total_argc + 1), sizeof(char *));
        if (!child_argv) _exit(127);
        for (int i = 0; i < total_argc; i++) {
            child_argv[i] = (char *)config->argv[i];
        }
        child_argv[total_argc] = NULL;

        // Build envp
        char **child_envp;
        if (config->envp && config->envc > 0) {
            child_envp = calloc((size_t)(config->envc + 1), sizeof(char *));
            if (!child_envp) _exit(127);
            for (int i = 0; i < config->envc; i++) {
                child_envp[i] = (char *)config->envp[i];
            }
            child_envp[config->envc] = NULL;
        } else {
            child_envp = calloc(1, sizeof(char *));
            if (!child_envp) _exit(127);
            child_envp[0] = NULL;
        }

        // Reset signal handlers in the child.
        signal(SIGPIPE, SIG_IGN);
        if (install_blink_runtime_signal_handlers(&signal_handlers) == -1) {
            _exit(127);
        }

        // Use ShimExec which mirrors blink.c's Exec() logic.
        // ShimExec calls Blink() which is _Noreturn.
        // When the guest exits, SysExitGroup calls exit().
        ShimExec(pathbuf, pathbuf, child_argv, child_envp);

        // Should never reach here.
        _exit(127);
    }

    // ── Parent process ───────────────────────────────────────────────────
    close(stdout_pipe[1]);  // close write ends
    close(stderr_pipe[1]);

    // Set up timeout if requested.
    if (timeout_ms > 0) {
        // We use a simple alarm-based approach.
        // For more precision, a real implementation would use poll/select
        // with timeout on the pipes plus a timer.
        // For now, we set an alarm and handle SIGALRM.
        // Actually, let's just read with a timer thread approach.
        // Simplest: read everything, then check if we need to kill.
    }

    // Read stdout and stderr from pipes.
    // We need to read both simultaneously to avoid deadlocks.
    // Use a second fork or thread... simplest: read in sequence since
    // blink child will typically produce moderate output.
    //
    // For robustness: read stdout first (child writes to pipe, kernel buffers).
    // If child blocks writing stderr because pipe is full, we'd deadlock.
    // To avoid this, set non-blocking and use select/poll.

    // Simple approach: read both via alternating non-blocking reads.
    set_nonblocking(stdout_pipe[0]);
    set_nonblocking(stderr_pipe[0]);

    size_t out_cap = 4096, err_cap = 4096;
    size_t out_len = 0, err_len = 0;
    char *out_buf = malloc(out_cap);
    char *err_buf = malloc(err_cap);
    if (!out_buf || !err_buf) {
        free(out_buf);
        free(err_buf);
        kill(pid, SIGKILL);
        waitpid(pid, NULL, 0);
        close(stdout_pipe[0]);
        close(stderr_pipe[0]);
        errno = ENOMEM;
        return -1;
    }

    int stdout_eof = 0, stderr_eof = 0;

    while (!stdout_eof || !stderr_eof) {
        fd_set rfds;
        FD_ZERO(&rfds);
        int maxfd = -1;
        if (!stdout_eof) {
            FD_SET(stdout_pipe[0], &rfds);
            if (stdout_pipe[0] > maxfd) maxfd = stdout_pipe[0];
        }
        if (!stderr_eof) {
            FD_SET(stderr_pipe[0], &rfds);
            if (stderr_pipe[0] > maxfd) maxfd = stderr_pipe[0];
        }

        struct timeval tv;
        tv.tv_sec = (timeout_ms > 0) ? (timeout_ms / 1000) : 5;
        tv.tv_usec = (timeout_ms > 0) ? ((timeout_ms % 1000) * 1000) : 0;

        int ret = select(maxfd + 1, &rfds, NULL, NULL, &tv);
        if (ret == -1) {
            if (errno == EINTR) continue;
            break;
        }
        if (ret == 0 && timeout_ms > 0) {
            // Timeout — kill the child.
            kill(pid, SIGKILL);
            result->timed_out = 1;
            break;
        }

        // Read stdout
        if (!stdout_eof && FD_ISSET(stdout_pipe[0], &rfds)) {
            if (out_len + 1024 > out_cap) {
                out_cap *= 2;
                char *tmp = realloc(out_buf, out_cap);
                if (tmp) out_buf = tmp;
            }
            ssize_t n = read(stdout_pipe[0], out_buf + out_len, out_cap - out_len);
            if (n > 0) out_len += (size_t)n;
            else if (n == 0) stdout_eof = 1;
            else if (errno != EAGAIN && errno != EINTR) stdout_eof = 1;
        }

        // Read stderr
        if (!stderr_eof && FD_ISSET(stderr_pipe[0], &rfds)) {
            if (err_len + 1024 > err_cap) {
                err_cap *= 2;
                char *tmp = realloc(err_buf, err_cap);
                if (tmp) err_buf = tmp;
            }
            ssize_t n = read(stderr_pipe[0], err_buf + err_len, err_cap - err_len);
            if (n > 0) err_len += (size_t)n;
            else if (n == 0) stderr_eof = 1;
            else if (errno != EAGAIN && errno != EINTR) stderr_eof = 1;
        }
    }

    close(stdout_pipe[0]);
    close(stderr_pipe[0]);

    // Wait for child.
    int status = 0;
    waitpid(pid, &status, 0);

    if (WIFEXITED(status)) {
        result->exit_code = WEXITSTATUS(status);
    } else if (WIFSIGNALED(status)) {
        result->exit_code = 128 + WTERMSIG(status);
    } else {
        result->exit_code = -1;
    }

    // Null-terminate output buffers.
    out_buf = realloc(out_buf, out_len + 1);
    if (out_buf) out_buf[out_len] = '\0';
    err_buf = realloc(err_buf, err_len + 1);
    if (err_buf) err_buf[err_len] = '\0';

    result->stdout_buf = out_buf;
    result->stdout_len = out_len;
    result->stderr_buf = err_buf;
    result->stderr_len = err_len;

    return 0;
#else
    errno = ENOTSUP;
    return -1;
#endif
}

void blink_result_free(blink_run_result_t *result) {
    if (!result) return;
    free(result->stdout_buf);
    result->stdout_buf = NULL;
    result->stdout_len = 0;
    free(result->stderr_buf);
    result->stderr_buf = NULL;
    result->stderr_len = 0;
}

// ── Interactive mode ────────────────────────────────────────────────────────
// Child inherits stdin/stdout/stderr directly — no pipes, no capture.
// Provides a fully interactive terminal experience.

int blink_run_interactive(const blink_run_config_t *config) {
    if (!config || !config->program_path || !config->argv) {
        errno = EINVAL;
        return -1;
    }

    if (should_use_nofork_runtime()) {
        return blink_run_nofork_interactive_impl(config, NULL, host_runtime_setup,
                                                 0, NULL);
    }

#if defined(HAVE_FORK)
    pid_t pid = fork();
    if (pid == -1) return -1;

    if (pid == 0) {
        // ── Child: stdin/stdout/stderr inherited from parent ────────────
        struct BlinkRuntimeSignalHandlers signal_handlers;
        WriteErrorInit();
        InitMap();

        FLAG_nolinear = should_force_nolinear_host_runtime();

#ifndef DISABLE_VFS
        if (config->host_mount_count > 0 && !config->vfs_prefix) {
            _exit(127);
        }
        if (config->vfs_prefix) {
            if (init_isolated_host_prefix(config->vfs_prefix)) {
                _exit(127);
            }
            if (OmniInstallGuestFdMounts()) {
                _exit(127);
            }
        }
        if (install_extra_host_mounts(config)) {
            _exit(127);
        }
#endif

        InitBus();

        char pathbuf[PATH_MAX];
        strncpy(pathbuf, config->program_path, sizeof(pathbuf) - 1);
        pathbuf[sizeof(pathbuf) - 1] = '\0';

        int total_argc = config->argc;
        char **child_argv = calloc((size_t)(total_argc + 1), sizeof(char *));
        if (!child_argv) _exit(127);
        for (int i = 0; i < total_argc; i++) {
            child_argv[i] = (char *)config->argv[i];
        }
        child_argv[total_argc] = NULL;

        char **child_envp;
        if (config->envp && config->envc > 0) {
            child_envp = calloc((size_t)(config->envc + 1), sizeof(char *));
            if (!child_envp) _exit(127);
            for (int i = 0; i < config->envc; i++) {
                child_envp[i] = (char *)config->envp[i];
            }
            child_envp[config->envc] = NULL;
        } else {
            child_envp = calloc(1, sizeof(char *));
            if (!child_envp) _exit(127);
            child_envp[0] = NULL;
        }

        signal(SIGPIPE, SIG_IGN);
        if (install_blink_runtime_signal_handlers(&signal_handlers) == -1) {
            _exit(127);
        }
        ShimExec(pathbuf, pathbuf, child_argv, child_envp);
        _exit(127);
    }

    // ── Parent: wait for child to exit ──────────────────────────────────
    int status = 0;
    while (waitpid(pid, &status, 0) == -1) {
        if (errno != EINTR) return -1;
    }

    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
    return -1;
#else
    errno = ENOTSUP;
    return -1;
#endif
}

int blink_pty_session_start_memvfs(const blink_run_config_t *config,
                                   const flatvfs_t *vfs,
                                   int rows,
                                   int cols,
                                   blink_pty_session_t **out_session,
                                   int *out_master_fd) {
    blink_pty_session_t *handle = NULL;
    struct blink_pty_session_impl *session = NULL;
    struct winsize size;
    char tempdir[PATH_MAX];
    int transport[2] = {-1, -1};
    int master_fd = -1;
    int slave_fd = -1;
    int err;

    if (!config || !vfs || !out_session || !out_master_fd || !config->program_path ||
        !config->argv) {
        errno = EINVAL;
        return -1;
    }

    memset(&size, 0, sizeof(size));
    size.ws_row = (unsigned short)(rows > 0 ? rows : 24);
    size.ws_col = (unsigned short)(cols > 0 ? cols : 80);

    if (materialize_flatvfs_to_tempdir(vfs, tempdir, sizeof(tempdir)) == -1) {
        return -1;
    }

    if (should_use_nofork_runtime()) {
        if (socketpair(AF_UNIX, SOCK_STREAM, 0, transport) == -1) {
            int saved_errno = errno;
            remove_tree(tempdir);
            errno = saved_errno;
            return -1;
        }
        master_fd = transport[0];
        slave_fd = transport[1];
    } else if (openpty(&master_fd, &slave_fd, NULL, NULL, &size) == -1) {
        int saved_errno = errno;
        remove_tree(tempdir);
        errno = saved_errno;
        return -1;
    }

    handle = calloc(1, sizeof(*handle));
    session = calloc(1, sizeof(*session));
    if (!handle || !session) {
        int saved_errno = errno;
        close(master_fd);
        close(slave_fd);
        remove_tree(tempdir);
        free(handle);
        errno = saved_errno;
        return -1;
    }

    session->tempdir = strdup(tempdir);
    if (!session->tempdir) {
        int saved_errno = errno;
        close(master_fd);
        close(slave_fd);
        remove_tree(tempdir);
        free(handle);
        free(session);
        errno = saved_errno;
        return -1;
    }
    session->slave_fd = slave_fd;
    session->exit_code = -1;
    session->initial_rows = rows > 0 ? rows : 24;
    session->initial_cols = cols > 0 ? cols : 80;
    atomic_init(&session->terminate_requested, false);

    if (copy_run_config(config, &session->config, tempdir) != 0) {
        int saved_errno = errno ? errno : ENOMEM;
        close(master_fd);
        close(slave_fd);
        remove_tree(tempdir);
        free(session->tempdir);
        free(session);
        errno = saved_errno;
        return -1;
    }

    if ((err = pthread_create(&session->thread, NULL, blink_pty_session_thread_main,
                              session)) != 0) {
        int saved_errno = err;
        close(master_fd);
        close(slave_fd);
        remove_tree(tempdir);
        free(handle);
        free_run_config(&session->config);
        free(session->tempdir);
        free(session);
        errno = saved_errno;
        return -1;
    }

    session->thread_started = true;
    handle->opaque = session;
    *out_session = handle;
    *out_master_fd = master_fd;
    return 0;
}

int blink_pty_session_terminate(blink_pty_session_t *session) {
    return pty_session_request_terminate(pty_session_impl(session));
}

int blink_pty_session_resize(blink_pty_session_t *session, int rows, int cols) {
    struct blink_pty_session_impl *impl = pty_session_impl(session);

    if (!impl) {
        errno = EINVAL;
        return -1;
    }

    if (!impl->context_initialized) {
        if (rows > 0) impl->initial_rows = rows;
        if (cols > 0) impl->initial_cols = cols;
        return 0;
    }

    pthread_mutex_lock(&impl->context.lock);
    impl->context.has_tty = true;
    if (rows > 0) {
        impl->context.tty_winsize.ws_row = (unsigned short)rows;
    }
    if (cols > 0) {
        impl->context.tty_winsize.ws_col = (unsigned short)cols;
    }
    if (!impl->context.tty_winsize.ws_row) {
        impl->context.tty_winsize.ws_row = 24;
    }
    if (!impl->context.tty_winsize.ws_col) {
        impl->context.tty_winsize.ws_col = 80;
    }
    for (struct OmniNoForkProcess *process = impl->context.processes; process;
         process = process->next) {
        if (!process->finished && process->sid == impl->context.tty_sid &&
            process->pgid == impl->context.tty_pgrp) {
            nofork_deliver_signal_to_process_locked(process, SIGWINCH_LINUX);
        }
    }
    pthread_mutex_unlock(&impl->context.lock);
    return 0;
}

int blink_pty_session_wait(blink_pty_session_t *session, int *out_exit_code) {
    int err;
    struct blink_pty_session_impl *impl = pty_session_impl(session);

    if (!impl) {
        errno = EINVAL;
        return -1;
    }

    if (impl->thread_started && !impl->joined) {
        if ((err = pthread_join(impl->thread, NULL)) != 0) {
            errno = err;
            return -1;
        }
        impl->joined = true;
    }

    if (impl->wait_errno) {
        errno = impl->wait_errno;
        return -1;
    }
    if (out_exit_code) {
        *out_exit_code = impl->exit_code;
    }
    return 0;
}

void blink_pty_session_destroy(blink_pty_session_t *session) {
    struct blink_pty_session_impl *impl = pty_session_impl(session);

    if (!session || !impl) return;
    if (impl->thread_started && !impl->joined) {
        pty_session_request_terminate(impl);
        pthread_join(impl->thread, NULL);
        impl->joined = true;
    }
    if (impl->slave_fd != -1) {
        close(impl->slave_fd);
        impl->slave_fd = -1;
    }
    if (impl->tempdir) {
        remove_tree(impl->tempdir);
        free(impl->tempdir);
    }
    free_run_config(&impl->config);
    free(impl);
    session->opaque = NULL;
    free(session);
}

static int run_interactive_memvfs_via_hostfs(const blink_run_config_t *config,
                                             const flatvfs_t *vfs) {
    blink_run_config_t host_config;
    char tempdir[PATH_MAX];
    int rc;
    int saved_errno = 0;

    if (materialize_flatvfs_to_tempdir(vfs, tempdir, sizeof(tempdir)) == -1) {
        return -1;
    }

    host_config = *config;
    host_config.vfs_prefix = tempdir;
    rc = blink_run_interactive(&host_config);
    if (rc == -1) {
        saved_errno = errno;
    }

    if (remove_tree(tempdir) == -1 && rc == -1 && !saved_errno) {
        saved_errno = errno;
    }
    if (rc == -1 && saved_errno) {
        errno = saved_errno;
    }
    return rc;
}

static int run_captured_memvfs_via_hostfs(const blink_run_config_t *config,
                                          blink_run_result_t *result,
                                          int timeout_ms,
                                          const flatvfs_t *vfs) {
    blink_run_config_t host_config;
    char tempdir[PATH_MAX];
    int rc;
    int saved_errno = 0;

    if (materialize_flatvfs_to_tempdir(vfs, tempdir, sizeof(tempdir)) == -1) {
        return -1;
    }

    host_config = *config;
    host_config.vfs_prefix = tempdir;
    rc = blink_run(&host_config, result, timeout_ms);
    if (rc == -1) {
        saved_errno = errno;
    }

    if (remove_tree(tempdir) == -1 && rc == -1 && !saved_errno) {
        saved_errno = errno;
    }
    if (rc == -1 && saved_errno) {
        errno = saved_errno;
    }
    return rc;
}

// ── blink_run_memvfs — interactive mode with in-memory VFS ──────────────────

int blink_run_memvfs(const blink_run_config_t *config, const flatvfs_t *vfs) {
    if (!config || !vfs || !config->program_path || !config->argv) {
        errno = EINVAL;
        return -1;
    }

    if (should_use_nofork_runtime()) {
        return blink_run_nofork_interactive_impl(config, vfs, memvfs_runtime_setup,
                                                 0, NULL);
    }

#if defined(HAVE_FORK)
    return run_interactive_memvfs_via_hostfs(config, vfs);
#else
    errno = ENOTSUP;
    return -1;
#endif
}

// ── blink_run_captured_memvfs — captured mode with in-memory VFS ────────────

int blink_run_captured_memvfs(const blink_run_config_t *config,
                              blink_run_result_t *result,
                              int timeout_ms,
                              const flatvfs_t *vfs) {
    if (!config || !result || !vfs || !config->program_path || !config->argv) {
        errno = EINVAL;
        return -1;
    }

    if (should_use_nofork_runtime()) {
        return blink_run_nofork_captured_impl(config, result, timeout_ms, vfs,
                                              memvfs_runtime_setup);
    }

#if defined(HAVE_FORK)
    memset(result, 0, sizeof(*result));
    return run_captured_memvfs_via_hostfs(config, result, timeout_ms, vfs);
#else
    errno = ENOTSUP;
    return -1;
#endif
}
