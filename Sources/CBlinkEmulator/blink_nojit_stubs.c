#include <stdarg.h>

#include "blink/bus.h"
#include "blink/endian.h"
#include "blink/jit.h"
#include "blink/machine.h"

#ifndef HAVE_JIT

void Jitter(P, const char *fmt, ...) {
  (void)m;
  (void)rde;
  (void)disp;
  (void)uimm0;
  (void)fmt;
}

void FastCall(struct Machine *m, u64 disp) {
  u64 v = Get64(m->sp) - 8;
  Write64(ToHost(v), m->ip);
  Put64(m->sp, v);
  m->ip += disp;
}

void FastLeave(struct Machine *m) {
  u64 v = Get64(m->bp);
  Put64(m->sp, v + 8);
  Put64(m->bp, Read64(ToHost(v)));
}

bool CanJitForImmediateEffect(void) {
  return false;
}

int CommitJit_(struct Jit *jit, struct JitBlock *jb) {
  (void)jit;
  (void)jb;
  return 0;
}

void ReinsertJitBlock_(struct Jit *jit, struct JitBlock *jb) {
  (void)jit;
  (void)jb;
}

#endif
