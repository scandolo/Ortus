// Monochrome marks matching the app's BrandGlyph (Ortus/Views/BrandGlyph.swift).
// Static, trusted markup only; never interpolate page or policy data into it.
const svg = (body, mask = '') => `<svg viewBox="0 0 100 100" aria-hidden="true" fill="currentColor" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">${mask}${body}</svg>`;
const glyphs = {
  Gmail: svg('<rect x="8" y="20" width="84" height="62" rx="12" fill="none" stroke-width="9"/><path d="M14 28 50 56 86 28" fill="none" stroke-width="9"/>'),
  Slack: svg('<rect x="28" y="8" width="15" height="84" rx="7.5" stroke="none"/><rect x="57" y="8" width="15" height="84" rx="7.5" stroke="none"/><rect x="8" y="28" width="84" height="15" rx="7.5" stroke="none"/><rect x="8" y="57" width="84" height="15" rx="7.5" stroke="none"/>'),
  LinkedIn: svg('<rect x="6" y="6" width="88" height="88" rx="20" stroke="none" mask="url(#o-li)"/>',
    '<mask id="o-li"><rect width="100" height="100" fill="#fff"/><circle cx="30" cy="29" r="7.5" fill="#000" stroke="none"/><path d="M30 45v31M50 76V45M50 58q10-16 22 0v18" fill="none" stroke="#000" stroke-width="12"/></mask>'),
  X: svg('<path d="M16 12 84 88" stroke-width="16" fill="none"/><path d="M84 12 16 88" stroke-width="7" fill="none"/>'),
  Instagram: svg('<rect x="10" y="10" width="80" height="80" rx="24" fill="none" stroke-width="9"/><circle cx="50" cy="50" r="18" fill="none" stroke-width="9"/><circle cx="71" cy="29" r="5.5" stroke="none"/>'),
  Facebook: svg('<circle cx="50" cy="50" r="44" stroke="none" mask="url(#o-fb)"/>',
    '<mask id="o-fb"><rect width="100" height="100" fill="#fff"/><path d="M56 94V42q0-16 16-16M42 53h28" fill="none" stroke="#000" stroke-width="12"/></mask>'),
  Reddit: svg('<ellipse cx="50" cy="62" rx="40" ry="28" stroke="none" mask="url(#o-rd)"/><circle cx="76" cy="14" r="8" stroke="none"/><path d="M50 36 56 12 72 15" fill="none" stroke-width="6"/>',
    '<mask id="o-rd"><rect width="100" height="100" fill="#fff"/><circle cx="36" cy="58" r="7" fill="#000"/><circle cx="64" cy="58" r="7" fill="#000"/></mask>'),
  TikTok: svg('<circle cx="36" cy="72" r="18" stroke="none"/><path d="M53 72V10" stroke-width="13" fill="none"/><path d="M53 12q7 22 31 24" stroke-width="11" fill="none"/>'),
  WhatsApp: svg('<path d="M20 70A40 40 0 1 1 34 84L8 94Z" fill="none" stroke-width="8"/><path d="M38 32q0 28 28 30" fill="none" stroke-width="12"/>'),
};
export const glyph = name => glyphs[name] ?? '';
