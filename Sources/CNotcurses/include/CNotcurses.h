#pragma once

#include <notcurses/notcurses.h>
#include <notcurses/nckeys.h>

// Expose a few macro-defined constants to Swift. (Some notcurses macros are not imported directly.)
uint32_t omni_nckey_button1(void);
uint32_t omni_nckey_scroll_up(void);
uint32_t omni_nckey_scroll_down(void);
uint32_t omni_nckey_esc(void);
uint32_t omni_nckey_backspace(void);
uint32_t omni_nckey_enter(void);
uint32_t omni_nckey_up(void);
uint32_t omni_nckey_down(void);

unsigned omni_ncmice_all_events(void);

// Terminal safety helpers.
// Install SIGINT/SIGTERM/SIGHUP/SIGQUIT handlers that request shutdown.
void omni_install_signal_handlers(void);
// Returns 0 if no signal received; otherwise returns the signal number.
int omni_signal_received(void);
// Best-effort restore terminal modes (show cursor, reset attributes, exit alt screen).
void omni_restore_terminal(void);
