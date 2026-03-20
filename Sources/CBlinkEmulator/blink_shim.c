// blink_shim.c — Fork-based wrapper around blink's emulation engine.
//
// Strategy: We fork a child process that initializes the blink VM, loads the
// ELF binary, and runs it. The child's stdout/stderr are captured via pipes.
// When the guest program calls exit(), blink calls the host exit() — which is
// fine because we're in a forked child.

#include "include/CBlinkEmulator.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <limits.h>

// ── Blink library headers ────────────────────────────────────────────────────
// These are resolved via the -iquote flag pointing to the blink source root.
#include "blink/machine.h"
#include "blink/loader.h"
#include "blink/map.h"
#include "blink/bus.h"
#include "blink/web.h"
#include "blink/vfs.h"
#include "blink/log.h"
#include "blink/syscall.h"
#include "blink/signal.h"
#include "blink/tunables.h"
#include "blink/x86.h"
#include "blink/util.h"
#include "blink/fds.h"

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
// Called when the guest receives a fatal signal. In the forked child context,
// we just exit with the appropriate signal-based exit code.
void TerminateSignal(struct Machine *m, int sig, int code) {
    (void)code;
    FreeMachine(m);
    _exit(128 + sig);
}

// ── Exec callback ────────────────────────────────────────────────────────────
// Called when the guest does execve(). We re-load the program in the same
// child process.
static int ShimExec(char *execfn, char *prog, char **argv, char **envp) {
    struct Machine *old = g_machine;
    if (old) KillOtherThreads(old->system);
    struct Machine *m = NewMachine(NewSystem(XED_MACHINE_MODE_LONG), 0);
    if (!m) _exit(127);
    g_machine = m;
    m->system->exec = ShimExec;
    if (!old) {
        LoadProgram(m, execfn, prog, argv, envp, NULL);
        SetupCod(m);
        for (int i = 0; i < 10; ++i) {
            AddStdFd(&m->system->fds, i);
        }
    } else {
#ifdef HAVE_JIT
        DisableJit(&old->system->jit);
#endif
        LoadProgram(m, execfn, prog, argv, envp, NULL);
        m->system->fds.list = old->system->fds.list;
        old->system->fds.list = 0;
        FreeMachine(old);
    }
    Blink(m);  // _Noreturn — guest will eventually call exit()
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

// ── Main entry point ─────────────────────────────────────────────────────────

int blink_run(const blink_run_config_t *config,
              blink_run_result_t *result,
              int timeout_ms) {
    if (!config || !result || !config->program_path || !config->argv) {
        errno = EINVAL;
        return -1;
    }

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
            if (VfsInit(config->vfs_prefix)) {
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

    pid_t pid = fork();
    if (pid == -1) return -1;

    if (pid == 0) {
        // ── Child: stdin/stdout/stderr inherited from parent ────────────
        WriteErrorInit();
        InitMap();

        FLAG_nolinear = true;

#ifndef DISABLE_VFS
        if (config->vfs_prefix) {
            if (VfsInit(config->vfs_prefix)) {
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
}

// ── In-memory VFS child setup ───────────────────────────────────────────────

/// Common child setup for memvfs: init blink with in-memory VFS.
/// Uses OmniVfsInit to mount the flatvfs directly — no disk writes.
static void memvfs_child_setup(const blink_run_config_t *config,
                                const flatvfs_t *vfs) {
    (void)config;

    // Initialize blink subsystems.
    WriteErrorInit();
    InitMap();
    FLAG_nolinear = true;

#ifndef DISABLE_VFS
    if (OmniVfsInit(vfs)) {
        _exit(127);
    }
#endif

    InitBus();
}

// ── blink_run_memvfs — interactive mode with in-memory VFS ──────────────────

int blink_run_memvfs(const blink_run_config_t *config, const flatvfs_t *vfs) {
    if (!config || !vfs || !config->program_path || !config->argv) {
        errno = EINVAL;
        return -1;
    }

    // Flush stdio buffers before fork to avoid duplicate output.
    fflush(stdout);
    fflush(stderr);

    pid_t pid = fork();
    if (pid == -1) return -1;

    if (pid == 0) {
        // ── Child: init in-memory VFS + run ─────────────────────────────
        memvfs_child_setup(config, vfs);

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
        close(stdout_pipe[0]);
        close(stderr_pipe[0]);
        dup2(stdout_pipe[1], STDOUT_FILENO);
        dup2(stderr_pipe[1], STDERR_FILENO);
        close(stdout_pipe[1]);
        close(stderr_pipe[1]);

        memvfs_child_setup(config, vfs);

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
        ShimExec(pathbuf, pathbuf, child_argv, child_envp);
        _exit(127);
    }

    // ── Parent process ───────────────────────────────────────────────────
    close(stdout_pipe[1]);
    close(stderr_pipe[1]);

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
            kill(pid, SIGKILL);
            result->timed_out = 1;
            break;
        }

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

    int status = 0;
    waitpid(pid, &status, 0);

    if (WIFEXITED(status)) {
        result->exit_code = WEXITSTATUS(status);
    } else if (WIFSIGNALED(status)) {
        result->exit_code = 128 + WTERMSIG(status);
    } else {
        result->exit_code = -1;
    }

    out_buf = realloc(out_buf, out_len + 1);
    if (out_buf) out_buf[out_len] = '\0';
    err_buf = realloc(err_buf, err_len + 1);
    if (err_buf) err_buf[err_len] = '\0';

    result->stdout_buf = out_buf;
    result->stdout_len = out_len;
    result->stderr_buf = err_buf;
    result->stderr_len = err_len;

    return 0;
}
