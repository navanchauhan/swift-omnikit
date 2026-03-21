// blink_shim.c — Embedded wrapper around blink's emulation engine.
//
// Strategy:
// - Platforms with host fork() available keep the existing child-process model.
// - Platforms without fork(), or tests that opt into it, run blink in-process
//   and unwind guest exit paths back to the embedder.

#include "include/CBlinkEmulator.h"
#include "omni_fdfs.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

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
#include "blink/syscall.h"
#include "blink/signal.h"
#include "blink/tunables.h"
#include "blink/x86.h"
#include "blink/util.h"
#include "blink/fds.h"

struct OmniNoForkContext {
    sigjmp_buf escape;
    pthread_mutex_t lock;
    pthread_cond_t cond;
    bool finished;
    bool timed_out;
    int exit_code;
    struct Machine *current_machine;
};

static _Thread_local struct OmniNoForkContext *g_nofork_context = NULL;

struct BlinkFatalSignalHandlers {
    struct sigaction sigbus;
    struct sigaction sigill;
    struct sigaction sigtrap;
    struct sigaction sigsegv;
    bool installed;
};

static void nofork_context_detach_current_machine(struct OmniNoForkContext *context,
                                                  struct Machine *machine);

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

// ── Stubs for blinkenlights symbols ──────────────────────────────────────────
// These are referenced by bios.c and other files but only meaningful in the
// TUI debugger (blinkenlights). We provide no-op stubs.

int ttyin = -1;
int vidya = -1;
bool tuimode = false;
struct Pty *pty = NULL;
struct Machine *m = NULL;
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
// Called when the guest does execve(). We re-load the program in the same
// child process.
static int ShimExec(char *execfn, char *prog, char **argv, char **envp) {
    int i;
    sigset_t oldmask;
    struct Machine *old = g_machine;
    if (old) KillOtherThreads(old->system);
    struct Machine *machine = NewMachine(NewSystem(XED_MACHINE_MODE_LONG), 0);
    if (!machine) _exit(127);
    g_machine = machine;
    m = machine;
    machine->system->exec = ShimExec;
    if (!old) {
        LoadProgram(machine, execfn, prog, argv, envp, NULL);
        SetupCod(machine);
        for (int i = 0; i < 10; ++i) {
            AddStdFd(&machine->system->fds, i);
        }
    } else {
#ifdef HAVE_JIT
        DisableJit(&old->system->jit);
#endif
        unassert(!machine->sysdepth);
        unassert(!machine->pagelocks.i);
        unassert(!FreeVirtual(old->system, -0x800000000000, 0x1000000000000));
        for (i = 1; i <= 64; ++i) {
            if (Read64(old->system->hands[i - 1].handler) == SIG_IGN_LINUX) {
                Write64(machine->system->hands[i - 1].handler, SIG_IGN_LINUX);
            }
        }
        memcpy(machine->system->rlim, old->system->rlim, sizeof(old->system->rlim));
        LoadProgram(machine, execfn, prog, argv, envp, NULL);
        machine->system->fds.list = old->system->fds.list;
        old->system->fds.list = 0;
        memcpy(&oldmask, &old->system->exec_sigmask, sizeof(oldmask));
        UNLOCK(&old->system->exec_lock);
        FreeMachine(old);
        unassert(!pthread_sigmask(SIG_SETMASK, &oldmask, 0));
    }
    Blink(machine);  // _Noreturn — guest will eventually call exit()
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
    return 0;
}

static void destroy_nofork_context(struct OmniNoForkContext *context) {
    pthread_cond_destroy(&context->cond);
    pthread_mutex_destroy(&context->lock);
}

static void nofork_context_set_current_machine(struct OmniNoForkContext *context,
                                               struct Machine *machine) {
    if (!context) return;
    pthread_mutex_lock(&context->lock);
    context->current_machine = machine;
    pthread_mutex_unlock(&context->lock);
}

static void nofork_context_detach_current_machine(struct OmniNoForkContext *context,
                                                  struct Machine *machine) {
    if (!context) return;
    pthread_mutex_lock(&context->lock);
    if (context->current_machine == machine) {
        context->current_machine = NULL;
    }
    pthread_mutex_unlock(&context->lock);
}

static void nofork_context_finish(struct OmniNoForkContext *context) {
    if (!context) return;
    pthread_mutex_lock(&context->lock);
    context->finished = true;
    context->current_machine = NULL;
    pthread_cond_broadcast(&context->cond);
    pthread_mutex_unlock(&context->lock);
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

static int host_runtime_setup(const blink_run_config_t *config, const flatvfs_t *vfs) {
    (void)vfs;

    if (reset_blink_vfs_state() != 0) return -1;

    WriteErrorInit();
    InitMap();
    FLAG_nolinear = true;

#ifndef DISABLE_VFS
    if (config->vfs_prefix) {
        if (init_isolated_host_prefix(config->vfs_prefix)) {
            return -1;
        }
        if (OmniInstallGuestFdMounts()) {
            return -1;
        }
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
#endif

    InitBus();
    return 0;
}

static _Noreturn void run_machine_nofork(struct Machine *machine) {
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
    }
}

// Called when the guest does execve(). In no-fork mode this replaces the
// currently running machine and continues execution in-process.
static int ShimExecNoFork(char *execfn, char *prog, char **argv, char **envp) {
    int i;
    sigset_t oldmask;
    struct Machine *old = g_machine;
    struct Machine *machine = NewMachine(NewSystem(XED_MACHINE_MODE_LONG), 0);

    if (old) KillOtherThreads(old->system);
    if (!machine) blink_host_exit(127);

    g_machine = machine;
    m = machine;
    nofork_context_set_current_machine(g_nofork_context, machine);

    machine->system->exec = ShimExecNoFork;
    machine->system->trapexit = true;

    if (!old) {
        LoadProgram(machine, execfn, prog, argv, envp, NULL);
        SetupCod(machine);
        for (i = 0; i < 10; ++i) {
            AddStdFd(&machine->system->fds, i);
        }
    } else {
#ifdef HAVE_JIT
        DisableJit(&old->system->jit);
#endif
        unassert(!machine->sysdepth);
        unassert(!machine->pagelocks.i);
        unassert(!FreeVirtual(old->system, -0x800000000000, 0x1000000000000));
        for (i = 1; i <= 64; ++i) {
            if (Read64(old->system->hands[i - 1].handler) == SIG_IGN_LINUX) {
                Write64(machine->system->hands[i - 1].handler, SIG_IGN_LINUX);
            }
        }
        memcpy(machine->system->rlim, old->system->rlim, sizeof(old->system->rlim));
        LoadProgram(machine, execfn, prog, argv, envp, NULL);
        machine->system->fds.list = old->system->fds.list;
        old->system->fds.list = 0;
        memcpy(&oldmask, &old->system->exec_sigmask, sizeof(oldmask));
        UNLOCK(&old->system->exec_lock);
        FreeMachine(old);
        unassert(!pthread_sigmask(SIG_SETMASK, &oldmask, 0));
    }

    run_machine_nofork(machine);
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
    struct BlinkFatalSignalHandlers fatal_handlers;
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
        if (install_blink_fatal_signal_handlers(&fatal_handlers) != 0) {
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
    restore_blink_fatal_signal_handlers(&fatal_handlers);
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
    struct BlinkFatalSignalHandlers fatal_handlers;
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
        if (install_blink_fatal_signal_handlers(&fatal_handlers) != 0) {
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
    restore_blink_fatal_signal_handlers(&fatal_handlers);

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
        struct BlinkFatalSignalHandlers fatal_handlers;
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

        FLAG_nolinear = true;  // Safe memory mode — no mmap tricks in child

#ifndef DISABLE_VFS
        if (config->vfs_prefix) {
            if (init_isolated_host_prefix(config->vfs_prefix)) {
                _exit(127);
            }
            if (OmniInstallGuestFdMounts()) {
                _exit(127);
            }
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
        if (install_blink_fatal_signal_handlers(&fatal_handlers) == -1) {
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
        struct BlinkFatalSignalHandlers fatal_handlers;
        WriteErrorInit();
        InitMap();

        FLAG_nolinear = true;

#ifndef DISABLE_VFS
        if (config->vfs_prefix) {
            if (init_isolated_host_prefix(config->vfs_prefix)) {
                _exit(127);
            }
            if (OmniInstallGuestFdMounts()) {
                _exit(127);
            }
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
        if (install_blink_fatal_signal_handlers(&fatal_handlers) == -1) {
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
