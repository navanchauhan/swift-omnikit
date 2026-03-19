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

#ifdef __cplusplus
}
#endif

#endif /* CBLINK_EMULATOR_H */
