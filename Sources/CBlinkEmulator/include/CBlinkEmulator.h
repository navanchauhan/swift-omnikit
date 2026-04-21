// CBlinkEmulator — thin C wrapper around the blink x86-64 emulator library.
// Provides a fork-safe API that runs an ELF binary using blink's emulation
// engine. Hosts with fork() keep child-process isolation; no-fork platforms
// fall back to an in-process runtime.

#ifndef CBLINK_EMULATOR_H
#define CBLINK_EMULATOR_H

#include <stdint.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Additional host directory mount to graft into the guest VFS.
typedef struct {
    /// Host directory path to expose.
    const char *host_path;
    /// Absolute guest mount path (for example "/workspace").
    const char *guest_path;
} blink_host_mount_t;

/// Configuration for a blink emulation run.
typedef struct {
    /// Path to the ELF binary to execute (host path).
    const char *program_path;
    /// Null-terminated argument vector (argv[0] should be the program name).
    const char *const *argv;
    /// Number of arguments (including argv[0]).
    int argc;
    /// Null-terminated environment variable array ("KEY=VALUE" strings).
    /// Pass NULL to inherit no environment.
    const char *const *envp;
    /// Number of environment variables.
    int envc;
    /// VFS prefix path (sets BLINK_PREFIX for blink's VFS layer).
    /// If NULL, no VFS prefix is configured.
    const char *vfs_prefix;
    /// Additional hostfs mounts to install inside the guest after the root VFS.
    /// Only directory mounts are supported.
    const blink_host_mount_t *host_mounts;
    /// Number of entries in host_mounts.
    int host_mount_count;
} blink_run_config_t;

/// Result of a blink emulation run.
typedef struct {
    /// Exit code from the emulated process.
    int exit_code;
    /// 1 if the process was killed due to timeout, 0 otherwise.
    int timed_out;
    /// Captured stdout (heap-allocated, caller must free).
    char *stdout_buf;
    /// Length of captured stdout in bytes.
    size_t stdout_len;
    /// Captured stderr (heap-allocated, caller must free).
    char *stderr_buf;
    /// Length of captured stderr in bytes.
    size_t stderr_len;
} blink_run_result_t;

typedef struct {
    void *opaque;
} blink_pty_session_t;

/// Run an x86-64 ELF binary under blink emulation.
///
/// This function forks a child process, sets up the blink emulator with the
/// given configuration, and captures stdout/stderr. The parent process waits
/// for the child to complete (or kills it on timeout).
///
/// @param config  Emulation configuration (must not be NULL).
/// @param result  Output result structure (must not be NULL).
///                On success, caller must free result->stdout_buf and
///                result->stderr_buf.
/// @param timeout_ms  Maximum execution time in milliseconds. 0 means no timeout.
/// @return 0 on success, -1 on error (check errno).
int blink_run(const blink_run_config_t *config,
              blink_run_result_t *result,
              int timeout_ms);

/// Free the buffers inside a blink_run_result_t.
/// Safe to call with NULL buffers.
void blink_result_free(blink_run_result_t *result);

/// Run an x86-64 ELF binary interactively with the user's terminal.
///
/// Unlike blink_run(), this function does NOT capture stdout/stderr.
/// The child process inherits stdin/stdout/stderr directly, providing
/// a fully interactive terminal experience (shell, apk, editors, etc.).
///
/// @param config  Emulation configuration (must not be NULL).
/// @return Exit code from the emulated process, or -1 on error.
int blink_run_interactive(const blink_run_config_t *config);

// ── Flat in-memory VFS ──────────────────────────────────────────────────────

/// Entry types for the flat in-memory VFS.
#define FLATVFS_FILE     0
#define FLATVFS_DIR      1
#define FLATVFS_SYMLINK  2

/// A single entry in the flat VFS.
typedef struct {
    const char *path;           // Relative path (e.g. "bin/busybox")
    uint8_t type;               // FLATVFS_FILE, FLATVFS_DIR, or FLATVFS_SYMLINK
    uint16_t mode;              // POSIX permission bits
    const uint8_t *data;        // File contents (NULL for dirs/symlinks)
    size_t data_size;           // Size of data
    const char *symlink_target; // Symlink target (NULL for files/dirs)
} flatvfs_entry_t;

/// The flat in-memory VFS.
typedef struct {
    const flatvfs_entry_t *entries;
    int entry_count;
} flatvfs_t;

/// Start an interactive PTY-backed blink session using a flat VFS snapshot.
///
/// The returned PTY master file descriptor is owned by the caller. The session
/// handle must be destroyed with blink_pty_session_destroy() after waiting for
/// exit or requesting termination.
int blink_pty_session_start_memvfs(const blink_run_config_t *config,
                                   const flatvfs_t *vfs,
                                   int rows,
                                   int cols,
                                   blink_pty_session_t **out_session,
                                   int *out_master_fd);

/// Request termination of a PTY-backed interactive session.
int blink_pty_session_terminate(blink_pty_session_t *session);

/// Update the PTY-backed session window size.
int blink_pty_session_resize(blink_pty_session_t *session, int rows, int cols);

/// Wait for a PTY-backed interactive session to finish.
int blink_pty_session_wait(blink_pty_session_t *session, int *out_exit_code);

/// Destroy a PTY-backed interactive session handle.
void blink_pty_session_destroy(blink_pty_session_t *session);

/// Run blink with a flat VFS snapshot as the guest root filesystem.
///
/// On platforms without host fork(), or when explicitly forced into no-fork
/// mode, the custom memvfs backend is mounted directly in-process. On
/// fork-capable hosts, the shim may materialize the snapshot into an isolated
/// temporary root so guest fork()/exec flows share a consistent writable view.
///
/// @param config  Emulation configuration (must not be NULL).
///                config->program_path should be the guest path (e.g. "/bin/sh").
///                config->vfs_prefix is ignored (the flatvfs IS the filesystem).
/// @param vfs     The flat in-memory VFS (must not be NULL).
/// @return Exit code from the emulated process, or -1 on error.
int blink_run_memvfs(const blink_run_config_t *config, const flatvfs_t *vfs);

/// Run blink with captured output and a flat VFS snapshot as the guest root.
///
/// Like blink_run() but uses the provided flat snapshot instead of an existing
/// host directory. The runtime chooses between direct memvfs mounting and an
/// isolated temporary host root using the same rules as blink_run_memvfs().
///
/// @param config     Emulation configuration (must not be NULL).
/// @param result     Output result structure (must not be NULL).
/// @param timeout_ms Maximum execution time in milliseconds. 0 means no timeout.
/// @param vfs        The flat in-memory VFS (must not be NULL).
/// @return 0 on success, -1 on error.
int blink_run_captured_memvfs(const blink_run_config_t *config,
                              blink_run_result_t *result,
                              int timeout_ms,
                              const flatvfs_t *vfs);

/// Initialize blink's VFS with a pure in-memory filesystem.
///
/// Replaces VfsInit() — mounts the flatvfs as the root filesystem via a
/// custom blink VfsSystem ("memfs"), with devfs at /dev and procfs at /proc.
/// No disk writes occur; mutations go to an in-memory overlay.
///
/// Used by the in-process runtime path before ShimExec.
///
/// @param vfs  The flat in-memory VFS (must not be NULL).
/// @return 0 on success, non-zero on error.
int OmniVfsInit(const flatvfs_t *vfs);

#ifdef __cplusplus
}
#endif

#endif /* CBLINK_EMULATOR_H */
