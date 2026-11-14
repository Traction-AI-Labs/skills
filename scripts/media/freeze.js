// Render-only init script: a fixed clock, so two renders of the same inputs give the same pixels.
(() => {
  const T = Date.parse("2026-11-17T09:50:00+11:00");
  const R = Date;
  class F extends R { constructor(...a) { super(...(a.length ? a : [T])); } static now() { return T; } }
  F.parse = R.parse; F.UTC = R.UTC;
  window.Date = F;
  try { localStorage.clear(); sessionStorage.clear(); } catch (e) {}
})();
