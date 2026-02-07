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

uint32_t omni_ncinput_shift(const struct ncinput* ni){
  if(ni == NULL){
    return 0;
  }
  return (ni->modifiers & NCKEY_MOD_SHIFT) ? 1u : 0u;
}

int omni_notcurses_cellpix(struct notcurses* nc, unsigned* cdimy, unsigned* cdimx,
                           unsigned* maxpixely, unsigned* maxpixelx){
  if(!nc || !cdimy || !cdimx || !maxpixely || !maxpixelx){
    return -1;
  }
  ncvgeom geom;
  if(ncvisual_geom(nc, NULL, NULL, &geom)){
    return -1;
  }
  *cdimy = geom.cdimy;
  *cdimx = geom.cdimx;
  *maxpixely = geom.maxpixely;
  *maxpixelx = geom.maxpixelx;
  return 0;
}

uint32_t omni_ncblit_pixel(void){ return (uint32_t)NCBLIT_PIXEL; }
uint64_t omni_ncvisual_option_blend(void){ return (uint64_t)NCVISUAL_OPTION_BLEND; }
uint64_t omni_ncvisual_option_nodegrade(void){ return (uint64_t)NCVISUAL_OPTION_NODEGRADE; }

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
  // Also try to clear any Kitty graphics protocol images (sprixel/kitty artifacts)
  // so they don't linger on crash/abort.
  const char* seq = "\x1b_Ga=d\x1b\\\x1b[0m\x1b[?25h\x1b[?1049l\x1b[?2004l";
  (void)write(STDOUT_FILENO, seq, strlen(seq));
}
