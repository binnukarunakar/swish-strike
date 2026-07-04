// heroArt.js
// ----------------------------------------------------------------------------
// Self-contained, crafted SVG hero art — one per game. No external/licensed
// images: every tile is drawn from gradients + primitives using the color-
// science palette in docs/04_DESIGN_SYSTEM.md. Mirrors the iOS HeroArtView keys
// so the same game shows comparable art on both platforms.
//
// heroSVG(heroId) -> a complete <svg> string on a 4:5 portrait viewBox (400x500),
// near-black base with a bottom scrim so a card title stays legible over it.
// ----------------------------------------------------------------------------

const BG = '#0A0B0E';
const W = 400, H = 500;

// Shared bottom scrim so card titles are always legible over the art.
function scrim() {
  return `<rect x="0" y="${H * 0.45}" width="${W}" height="${H * 0.55}" fill="url(#scrim)"/>`;
}
function defsCommon() {
  return `<linearGradient id="scrim" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${BG}" stop-opacity="0"/>
      <stop offset="1" stop-color="${BG}" stop-opacity="0.9"/>
    </linearGradient>`;
}

// Wrap a body in the standard svg shell with the game's ambient accent glow.
function shell(accent, defs, body) {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" role="img">
  <defs>
    ${defsCommon()}
    <radialGradient id="amb" cx="0.5" cy="0.36" r="0.75">
      <stop offset="0" stop-color="${accent}" stop-opacity="0.22"/>
      <stop offset="0.6" stop-color="${accent}" stop-opacity="0.05"/>
      <stop offset="1" stop-color="${BG}" stop-opacity="0"/>
    </radialGradient>
    ${defs}
  </defs>
  <rect width="${W}" height="${H}" fill="${BG}"/>
  <rect width="${W}" height="${H}" fill="url(#amb)"/>
  ${body}
  ${scrim()}
</svg>`;
}

const ART = {
  basketball(a) {
    const defs = `<radialGradient id="bb" cx="0.38" cy="0.34" r="0.75">
        <stop offset="0" stop-color="#FFB37A"/><stop offset="0.45" stop-color="${a}"/><stop offset="1" stop-color="#C2410C"/>
      </radialGradient>`;
    return shell(a, defs, `
      <path d="M70 360 Q150 120 250 150" fill="none" stroke="${a}" stroke-width="3" stroke-dasharray="7 9" opacity="0.45" stroke-linecap="round"/>
      <ellipse cx="262" cy="210" rx="58" ry="16" fill="#000" opacity="0.28"/>
      <circle cx="262" cy="150" r="62" fill="url(#bb)"/>
      <path d="M200 150 H324 M262 88 V212 M218 100 Q262 150 218 200 M306 100 Q262 150 306 200" fill="none" stroke="#0A0B0E" stroke-width="2.4" opacity="0.85"/>
      <circle cx="240" cy="128" r="14" fill="#fff" opacity="0.18"/>`);
  },
  soccer(a) {
    const defs = `<linearGradient id="pitch" x1="0" y1="1" x2="0" y2="0">
        <stop offset="0" stop-color="#16A34A" stop-opacity="0.5"/><stop offset="1" stop-color="#16A34A" stop-opacity="0"/>
      </linearGradient>`;
    return shell(a, defs, `
      <rect x="0" y="300" width="${W}" height="200" fill="url(#pitch)"/>
      <path d="M40 500 L150 320 M360 500 L250 320" stroke="${a}" stroke-width="2.5" opacity="0.55"/>
      <path d="M150 320 Q200 300 250 320" fill="none" stroke="${a}" stroke-width="2" opacity="0.5"/>
      <g transform="translate(150 150)">
        <circle r="58" fill="#F4F6FA"/>
        <polygon points="0,-26 25,-8 16,22 -16,22 -25,-8" fill="#0A0B0E"/>
        <path d="M0,-58 L0,-26 M55,-18 L25,-8 M34,49 L16,22 M-34,49 L-16,22 M-55,-18 L-25,-8" stroke="#0A0B0E" stroke-width="2.2" opacity="0.7"/>
        <circle r="22" fill="none" stroke="#fff" stroke-width="0"/>
        <circle cx="-18" cy="-20" r="12" fill="#fff" opacity="0.25"/>
      </g>`);
  },
  juggling(a) {
    const defs = `<radialGradient id="j1" cx="0.4" cy="0.35" r="0.8"><stop offset="0" stop-color="#E9D5FF"/><stop offset="1" stop-color="${a}"/></radialGradient>`;
    return shell(a, defs, `
      <path d="M120 300 C40 180 180 130 200 200 C220 270 360 220 280 100" fill="none" stroke="${a}" stroke-width="2.5" stroke-dasharray="5 8" opacity="0.4"/>
      <circle cx="120" cy="300" r="30" fill="#A855F7"/><circle cx="111" cy="291" r="8" fill="#fff" opacity="0.3"/>
      <circle cx="280" cy="100" r="38" fill="url(#j1)"/><circle cx="268" cy="88" r="10" fill="#fff" opacity="0.3"/>
      <circle cx="205" cy="205" r="24" fill="#C77DFF"/><circle cx="198" cy="198" r="7" fill="#fff" opacity="0.3"/>`);
  },
  tennis(a) {
    const defs = `<radialGradient id="tn" cx="0.4" cy="0.35" r="0.8"><stop offset="0" stop-color="#ECFF8A"/><stop offset="0.5" stop-color="${a}"/><stop offset="1" stop-color="#A3E635"/></radialGradient>
      <linearGradient id="streak" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${a}" stop-opacity="0"/><stop offset="1" stop-color="${a}" stop-opacity="0.5"/></linearGradient>`;
    return shell(a, defs, `
      <path d="M60 360 L150 420 M90 330 L180 390 M120 300 L210 360" stroke="${a}" stroke-width="2" opacity="0.22"/>
      <path d="M120 320 L250 165" stroke="url(#streak)" stroke-width="34" stroke-linecap="round" opacity="0.5"/>
      <circle cx="270" cy="150" r="52" fill="url(#tn)"/>
      <path d="M232 120 Q286 150 232 182 M308 120 Q254 150 308 182" fill="none" stroke="#F4F6FA" stroke-width="2.4" opacity="0.9"/>
      <circle cx="252" cy="132" r="13" fill="#fff" opacity="0.22"/>`);
  },
  cornhole(a) {
    const defs = `<linearGradient id="board" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFB52E"/><stop offset="1" stop-color="#D97706"/></linearGradient>`;
    return shell(a, defs, `
      <path d="M90 370 L170 150 L320 175 L270 400 Z" fill="url(#board)"/>
      <path d="M90 370 L170 150 L320 175 L270 400 Z" fill="none" stroke="#FDE68A" stroke-width="1.5" opacity="0.4"/>
      <ellipse cx="222" cy="205" rx="26" ry="16" fill="#0A0B0E"/>
      <ellipse cx="222" cy="203" rx="26" ry="16" fill="none" stroke="#D97706" stroke-width="3"/>
      <path d="M70 360 Q140 220 200 210" fill="none" stroke="${a}" stroke-width="3" stroke-dasharray="6 8" opacity="0.45"/>
      <rect x="58" y="338" width="34" height="34" rx="8" fill="#FDE68A" transform="rotate(-18 75 355)"/>`);
  },
  'ping-pong'(a) {
    const defs = `<radialGradient id="pad" cx="0.4" cy="0.4" r="0.8"><stop offset="0" stop-color="#7DD8FF"/><stop offset="0.6" stop-color="${a}"/><stop offset="1" stop-color="#0EA5E9"/></radialGradient>`;
    return shell(a, defs, `
      <path d="M90 370 L320 300" stroke="${a}" stroke-width="2" opacity="0.35"/>
      <path d="M205 250 L205 300" stroke="#F4F6FA" stroke-width="2" stroke-dasharray="3 5" opacity="0.5"/>
      <path d="M120 330 Q200 180 280 240" fill="none" stroke="${a}" stroke-width="3" stroke-dasharray="6 8" opacity="0.5"/>
      <g transform="translate(120 300) rotate(-32)">
        <circle r="54" fill="url(#pad)"/><rect x="-13" y="44" width="26" height="58" rx="10" fill="#0EA5E9"/>
        <circle cx="-16" cy="-16" r="14" fill="#fff" opacity="0.2"/>
      </g>
      <circle cx="282" cy="240" r="16" fill="#F4F6FA"/><circle cx="277" cy="235" r="5" fill="#fff" opacity="0.5"/>`);
  },
  'bottle-flip'(a) {
    const defs = `<linearGradient id="bot" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#7DA8FF"/><stop offset="0.4" stop-color="${a}"/><stop offset="1" stop-color="#1D4ED8"/></linearGradient>`;
    const bottle = (fill, op) => `<g opacity="${op}"><rect x="-22" y="-18" width="44" height="86" rx="16" fill="${fill}"/><rect x="-11" y="-44" width="22" height="30" rx="7" fill="${fill}"/><rect x="-9" y="-54" width="18" height="12" rx="4" fill="${fill}"/></g>`;
    return shell(a, defs, `
      <path d="M150 360 Q210 150 300 250" fill="none" stroke="${a}" stroke-width="2.5" stroke-dasharray="5 8" opacity="0.4"/>
      <line x1="60" y1="392" x2="340" y2="392" stroke="${a}" stroke-width="2" opacity="0.4"/>
      <g transform="translate(165 250) rotate(150)">${bottle('#2E7DFF', 0.18)}</g>
      <g transform="translate(230 200) rotate(95)">${bottle('#2E7DFF', 0.22)}</g>
      <g transform="translate(300 330) rotate(0)">${bottle('url(#bot)', 1)}<rect x="-19" y="20" width="38" height="44" rx="12" fill="#BFDBFE" opacity="0.35"/></g>`);
  },
  catch(a) {
    const defs = `<radialGradient id="cb" cx="0.4" cy="0.35" r="0.8"><stop offset="0" stop-color="#FBCFE8"/><stop offset="1" stop-color="${a}"/></radialGradient>`;
    const mitt = (x, y, s, r) => `<g transform="translate(${x} ${y}) scale(${s}) rotate(${r})"><path d="M0 0 q-30 -8 -30 22 q0 30 34 30 q40 0 40 -34 q0 -22 -22 -22 q-2 -18 -22 -18 z" fill="${a}"/><path d="M0 0 q-30 -8 -30 22" fill="none" stroke="#DB2777" stroke-width="3" opacity="0.5"/></g>`;
    return shell(a, defs, `
      <path d="M95 360 Q205 120 305 200" fill="none" stroke="${a}" stroke-width="3" stroke-dasharray="6 9" opacity="0.45"/>
      ${mitt(95, 330, 1.1, -10)}
      ${mitt(300, 175, 1.05, 165)}
      <circle cx="205" cy="172" r="26" fill="url(#cb)"/><circle cx="197" cy="164" r="8" fill="#fff" opacity="0.4"/>`);
  },
  'free-throw'(a) {
    const defs = `<radialGradient id="ft" cx="0.4" cy="0.35" r="0.8"><stop offset="0" stop-color="#FF8AA0"/><stop offset="0.5" stop-color="${a}"/><stop offset="1" stop-color="#E11D48"/></radialGradient>`;
    return shell(a, defs, `
      <rect x="225" y="95" width="120" height="84" rx="4" fill="none" stroke="#F4F6FA" stroke-width="2.5" opacity="0.35"/>
      <rect x="262" y="130" width="46" height="34" fill="none" stroke="#F4F6FA" stroke-width="2.5" opacity="0.35"/>
      <ellipse cx="262" cy="190" rx="44" ry="13" fill="none" stroke="${a}" stroke-width="4"/>
      <path d="M222 192 L238 250 M248 196 L256 256 M276 196 L268 256 M302 192 L286 250" stroke="${a}" stroke-width="2.4" opacity="0.7"/>
      <path d="M70 400 Q150 210 222 200" fill="none" stroke="${a}" stroke-width="3" stroke-dasharray="7 9" opacity="0.4"/>
      <circle cx="92" cy="372" r="30" fill="url(#ft)"/><circle cx="83" cy="363" r="9" fill="#fff" opacity="0.3"/>`);
  },
  dribble(a) {
    const defs = `<radialGradient id="db" cx="0.4" cy="0.35" r="0.8"><stop offset="0" stop-color="#99F6E4"/><stop offset="0.5" stop-color="${a}"/><stop offset="1" stop-color="#0D9488"/></radialGradient>`;
    return shell(a, defs, `
      <line x1="205" y1="120" x2="205" y2="360" stroke="${a}" stroke-width="2" stroke-dasharray="4 7" opacity="0.3"/>
      <circle cx="205" cy="150" r="22" fill="#19E6C3" opacity="0.12"/>
      <circle cx="205" cy="210" r="30" fill="#19E6C3" opacity="0.25"/>
      <circle cx="205" cy="285" r="40" fill="url(#db)"/>
      <circle cx="190" cy="270" r="11" fill="#fff" opacity="0.28"/>
      <ellipse cx="205" cy="372" rx="60" ry="14" fill="none" stroke="${a}" stroke-width="2.5" opacity="0.5"/>
      <ellipse cx="205" cy="372" rx="90" ry="22" fill="none" stroke="${a}" stroke-width="1.5" opacity="0.25"/>`);
  },
  golf(a) {
    const defs = `<linearGradient id="green" x1="0" y1="1" x2="0" y2="0"><stop offset="0" stop-color="#15803D" stop-opacity="0.55"/><stop offset="1" stop-color="#15803D" stop-opacity="0"/></linearGradient>
      <radialGradient id="gb" cx="0.4" cy="0.35" r="0.8"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#CBD5E1"/></radialGradient>`;
    return shell(a, defs, `
      <path d="M0 330 Q200 290 400 340 L400 500 L0 500 Z" fill="url(#green)"/>
      <ellipse cx="268" cy="352" rx="24" ry="9" fill="#0A0B0E"/>
      <ellipse cx="268" cy="350" rx="24" ry="9" fill="none" stroke="${a}" stroke-width="2.5" opacity="0.8"/>
      <line x1="268" y1="350" x2="268" y2="160" stroke="#E2E8F0" stroke-width="4"/>
      <path d="M268 160 L334 182 L268 204 Z" fill="${a}"/>
      <path d="M70 392 Q160 372 240 354" fill="none" stroke="${a}" stroke-width="3" stroke-dasharray="6 8" opacity="0.5"/>
      <circle cx="84" cy="390" r="19" fill="url(#gb)"/>
      <circle cx="78" cy="384" r="6" fill="#fff" opacity="0.7"/>`);
  },
  'cup-pong'(a) {
    const defs = `<linearGradient id="cup" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${a}"/><stop offset="1" stop-color="#C81E1E"/></linearGradient>`;
    const cup = (x, y, s = 1) => `<g transform="translate(${x} ${y}) scale(${s})">
        <path d="M-26 0 L26 0 L20 64 L-20 64 Z" fill="url(#cup)"/>
        <ellipse cx="0" cy="0" rx="26" ry="9" fill="#7F1D1D"/>
        <ellipse cx="0" cy="0" rx="26" ry="9" fill="none" stroke="#FCA5A5" stroke-width="2" opacity="0.7"/>
        <path d="M-24 14 L24 14" stroke="#FECACA" stroke-width="3" opacity="0.35"/></g>`;
    return shell(a, defs, `
      <path d="M70 130 Q190 80 262 196" fill="none" stroke="${a}" stroke-width="3" stroke-dasharray="6 8" opacity="0.5"/>
      <circle cx="86" cy="138" r="15" fill="#F4F6FA"/><circle cx="81" cy="133" r="5" fill="#fff" opacity="0.6"/>
      ${cup(150, 240, 0.92)} ${cup(266, 240, 0.92)}
      ${cup(208, 210, 0.96)}
      ${cup(208, 300, 1.06)}
      <ellipse cx="208" cy="392" rx="120" ry="14" fill="${a}" opacity="0.10"/>`);
  },
  volleyball(a) {
    const defs = `<radialGradient id="vb" cx="0.38" cy="0.34" r="0.8"><stop offset="0" stop-color="#FFF7C2"/><stop offset="0.55" stop-color="${a}"/><stop offset="1" stop-color="#D9B91F"/></radialGradient>`;
    return shell(a, defs, `
      <line x1="40" y1="120" x2="360" y2="120" stroke="#F4F6FA" stroke-width="2" opacity="0.25"/>
      <line x1="40" y1="128" x2="360" y2="128" stroke="#F4F6FA" stroke-width="1" opacity="0.15"/>
      <path d="M205 330 Q205 220 205 196" stroke="${a}" stroke-width="2.5" stroke-dasharray="5 8" opacity="0.45" fill="none"/>
      <g transform="translate(205 168)">
        <circle r="56" fill="url(#vb)"/>
        <path d="M-56 0 Q0 -28 56 0 M-50 -26 Q0 4 50 -26 M-34 44 Q0 8 34 44" fill="none" stroke="#1E3A8A" stroke-width="3" opacity="0.55"/>
        <circle cx="-18" cy="-20" r="13" fill="#fff" opacity="0.35"/>
      </g>
      <g transform="translate(205 352) rotate(-6)">
        <rect x="-78" y="-10" width="74" height="20" rx="10" fill="#E8B88A"/>
        <rect x="6" y="-10" width="74" height="20" rx="10" fill="#E8B88A" transform="rotate(12 6 0)"/>
      </g>`);
  },
  'hacky-sack'(a) {
    const defs = `<radialGradient id="hs" cx="0.4" cy="0.35" r="0.85"><stop offset="0" stop-color="#C4BBFF"/><stop offset="1" stop-color="${a}"/></radialGradient>`;
    return shell(a, defs, `
      <path d="M205 150 Q205 240 205 296" stroke="${a}" stroke-width="2.5" stroke-dasharray="4 7" opacity="0.45" fill="none"/>
      <g transform="translate(205 170)">
        <circle r="42" fill="url(#hs)"/>
        <path d="M-42 0 Q0 -20 42 0 M-42 0 Q0 20 42 0 M0 -42 Q-16 0 0 42 M0 -42 Q16 0 0 42" fill="none" stroke="#0A0B0E" stroke-width="2.4" opacity="0.5"/>
        <circle cx="-12" cy="-14" r="9" fill="#fff" opacity="0.3"/>
      </g>
      <g transform="translate(196 344) rotate(-14)">
        <path d="M-58 6 Q-58 -16 -28 -16 L34 -16 Q66 -16 66 4 L66 16 Q66 24 56 24 L-48 24 Q-58 24 -58 16 Z" fill="#F4F6FA" opacity="0.92"/>
        <path d="M-58 8 L66 8" stroke="#0A0B0E" stroke-width="3" opacity="0.25"/>
        <path d="M-20 -16 L-12 8 M6 -16 L12 8" stroke="#9BA3B0" stroke-width="2.5" opacity="0.6"/>
        <rect x="-58" y="20" width="124" height="8" rx="4" fill="#9BA3B0" opacity="0.8"/>
      </g>`);
  },
};

export function heroSVG(heroId) {
  const accents = {
    basketball: '#FF7A33', soccer: '#33E07A', juggling: '#C77DFF', tennis: '#D4FF3D',
    cornhole: '#FFB52E', 'ping-pong': '#2EC4FF', 'bottle-flip': '#2E7DFF', catch: '#FF4D8D',
    'free-throw': '#FF3B5C', dribble: '#19E6C3',
    golf: '#5BE049', 'cup-pong': '#FF5147', volleyball: '#FFE03D', 'hacky-sack': '#8B7DFF',
  };
  const fn = ART[heroId];
  if (!fn) return shell('#9BA3B0', '', `<circle cx="200" cy="160" r="50" fill="#9BA3B0" opacity="0.4"/>`);
  return fn(accents[heroId]);
}

export const HERO_IDS = Object.keys(ART);
export default { heroSVG, HERO_IDS };
