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

// Modifiers helpers.
// Returns 1 if Shift is pressed for the given input event, otherwise 0.
uint32_t omni_ncinput_shift(const struct ncinput* ni);

// Visual/pixel helpers.
// Returns terminal cell pixel geometry (cdimy/cdimx) and maximum accepted bitmap size (maxpixely/maxpixelx).
// Returns 0 on success, -1 on failure.
int omni_notcurses_cellpix(struct notcurses* nc, unsigned* cdimy, unsigned* cdimx,
                           unsigned* maxpixely, unsigned* maxpixelx);
uint32_t omni_ncblit_pixel(void);
uint64_t omni_ncvisual_option_blend(void);
uint64_t omni_ncvisual_option_nodegrade(void);

// Terminal safety helpers.
// Install SIGINT/SIGTERM/SIGHUP/SIGQUIT handlers that request shutdown.
void omni_install_signal_handlers(void);
// Returns 0 if no signal received; otherwise returns the signal number.
int omni_signal_received(void);
// Best-effort restore terminal modes (show cursor, reset attributes, exit alt screen).
void omni_restore_terminal(void);
