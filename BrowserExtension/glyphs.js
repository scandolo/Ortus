// Monochrome marks matching the app's BrandGlyph (Ortus/Views/BrandGlyph.swift).
// Static, trusted markup only; never interpolate page or policy data into it.
const svg = (body, mask = '') => `<svg viewBox="0 0 100 100" aria-hidden="true" fill="currentColor" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round">${mask}${body}</svg>`;
const glyphs = {
  Gmail: svg('<rect x="8" y="20" width="84" height="62" rx="12" fill="none" stroke-width="9"/><path d="M14 28 50 56 86 28" fill="none" stroke-width="9"/>'),
  Slack: svg('<rect x="25" y="6" width="19" height="88" rx="9.5" stroke="none"/><rect x="56" y="6" width="19" height="88" rx="9.5" stroke="none"/><rect x="6" y="25" width="88" height="19" rx="9.5" stroke="none"/><rect x="6" y="56" width="88" height="19" rx="9.5" stroke="none"/>'),
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
  YouTube: svg('<rect x="6" y="20" width="88" height="60" rx="18" stroke="none" mask="url(#o-yt)"/>',
    '<mask id="o-yt"><rect width="100" height="100" fill="#fff"/><path d="M42 34 70 50 42 66Z" fill="#000" stroke="none"/></mask>'),
  Twitch: svg('<path d="M14 6H94V64L70 88H50L34 100V88H14Z" stroke="none" mask="url(#o-tw)"/><path d="M42 30h9.5v25H42ZM64 30h9.5v25H64Z" stroke="none"/>',
    '<mask id="o-tw"><rect width="100" height="100" fill="#fff"/><path d="M26 18H82V56L65 73H48L36 84V73H26Z" fill="#000" stroke="none"/></mask>'),
  Netflix: svg('<path d="M18 6h18v88H18ZM64 6h18v88H64ZM18 6H39L82 94H61Z" stroke="none"/>'),
  Spotify: svg('<circle cx="50" cy="50" r="44" stroke="none" mask="url(#o-sp)"/>',
    '<mask id="o-sp"><rect width="100" height="100" fill="#fff"/><path d="M25 36Q52 23 78 39" fill="none" stroke="#000" stroke-width="8"/><path d="M28 51Q50 40 74 54" fill="none" stroke="#000" stroke-width="7"/><path d="M31 65Q50 56 69 68" fill="none" stroke="#000" stroke-width="6"/></mask>'),
  Discord: svg('<path d="M29 19 41 16 44 22H56L59 16 71 19C82 37 90 59 90 75Q84 81 72 84L68 77H32L28 84Q16 81 10 75C10 59 18 37 29 19Z" stroke="none" mask="url(#o-dc)"/>',
    '<mask id="o-dc"><rect width="100" height="100" fill="#fff"/><circle cx="36" cy="52" r="7" fill="#000" stroke="none"/><circle cx="64" cy="52" r="7" fill="#000" stroke="none"/></mask>'),
  Telegram: svg('<circle cx="50" cy="50" r="44" stroke="none" mask="url(#o-tg)"/><path d="M41 53 69 33" fill="none" stroke-width="4"/>',
    '<mask id="o-tg"><rect width="100" height="100" fill="#fff"/><path d="M20 46 80 22 68 78 50 60 40 70V53Z" fill="#000" stroke="none"/></mask>'),
};
// Additional website aliases match the app; no policy data enters SVG markup.
const websiteNames = { 'youtube.com':'YouTube', 'youtu.be':'YouTube', 'twitch.tv':'Twitch', 'netflix.com':'Netflix',
  'spotify.com':'Spotify', 'discord.com':'Discord', 'discord.gg':'Discord', 'telegram.org':'Telegram', 't.me':'Telegram' };
export function glyph(name) {
  if (typeof name !== 'string') return '';
  if (Object.hasOwn(glyphs, name)) return glyphs[name];
  const host = name.toLowerCase().replace(/\.$/, '');
  const website = Object.keys(websiteNames).find(domain => host === domain || host.endsWith('.' + domain));
  return website ? glyphs[websiteNames[website]] : '';
}
