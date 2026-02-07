// This target exists to provide a stable Clang module for notcurses, and to surface
// some macro-defined constants that are not directly importable into Swift.

#include "CNotcurses.h"

#include <signal.h>
#include <string.h>
#include <unistd.h>

uint32_t omni_nckey_button1(void) { return (uint32_t)NCKEY_BUTTON1; }
uint32_t omni_nckey_scroll_up(void) { return (uint32_t)NCKEY_SCROLL_UP; }
uint32_t omni_nckey_scroll_down(void) { return (uint32_t)NCKEY_SCROLL_DOWN; }
uint32_t omni_nckey_esc(void) { return (uint32_t)NCKEY_ESC; }
uint32_t omni_nckey_backspace(void) { return (uint32_t)NCKEY_BACKSPACE; }
uint32_t omni_nckey_enter(void) { return (uint32_t)NCKEY_ENTER; }
uint32_t omni_nckey_up(void) { return (uint32_t)NCKEY_UP; }
uint32_t omni_nckey_down(void) { return (uint32_t)NCKEY_DOWN; }

unsigned omni_ncmice_all_events(void) { return (unsigned)NCMICE_ALL_EVENTS; }

static volatile sig_atomic_t g_omni_signal = 0;

static void
omni_signal_handler(int signo){
  g_omni_signal = signo;
}

void omni_install_signal_handlers(void){
  signal(SIGINT, omni_signal_handler);
  signal(SIGTERM, omni_signal_handler);
  signal(SIGHUP, omni_signal_handler);
  signal(SIGQUIT, omni_signal_handler);
}

int omni_signal_received(void){
  return (int)g_omni_signal;
}

void omni_restore_terminal(void){
  // Best-effort cleanup: reset attrs, show cursor, leave alt screen, disable bracketed paste.
  // This is safe to emit even if the terminal doesn't support some sequences.
  const char* seq = "\x1b[0m\x1b[?25h\x1b[?1049l\x1b[?2004l";
  (void)write(STDOUT_FILENO, seq, strlen(seq));
}
