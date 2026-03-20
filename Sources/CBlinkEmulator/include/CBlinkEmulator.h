// CBlinkEmulator — thin C wrapper around the blink x86-64 emulator library.
// Provides a fork-safe API that runs an ELF binary in a child process using
// blink's emulation engine and captures stdout/stderr via pipes.

#ifndef CBLINK_EMULATOR_H
#define CBLINK_EMULATOR_H

#include <stdint.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

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

/// Run blink with an in-memory VFS (no disk I/O).
///
/// This function materializes the VFS into blink's VFS layer by writing
/// entries to a tmpfs-backed directory structure. The key difference from
/// blink_run_interactive is that it uses memfd/pipes for file data instead
/// of writing to the real filesystem.
///
/// @param config  Emulation configuration (must not be NULL).
///                config->program_path should be the guest path (e.g. "/bin/sh").
///                config->vfs_prefix is ignored (the flatvfs IS the filesystem).
/// @param vfs     The flat in-memory VFS (must not be NULL).
/// @return Exit code from the emulated process, or -1 on error.
int blink_run_memvfs(const blink_run_config_t *config, const flatvfs_t *vfs);

/// Run blink with captured output and an in-memory VFS (no disk I/O).
///
/// Like blink_run() but uses the flat in-memory VFS instead of a host directory.
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
/// Must be called from the forked child process before ShimExec.
///
/// @param vfs  The flat in-memory VFS (must not be NULL).
/// @return 0 on success, non-zero on error.
int OmniVfsInit(const flatvfs_t *vfs);

#ifdef __cplusplus
}
#endif

#endif /* CBLINK_EMULATOR_H */
