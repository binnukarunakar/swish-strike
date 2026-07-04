// Emits one standalone .svg per game into ../../assets/heroes/ from heroArt.js,
// so the repo ships crafted, license-clean hero art as real files too.
import { writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { heroSVG, HERO_IDS } from '../js/heroArt.js';

const here = dirname(fileURLToPath(import.meta.url));
const out = resolve(here, '../../assets/heroes');
mkdirSync(out, { recursive: true });
for (const id of HERO_IDS) {
  writeFileSync(resolve(out, `${id}.svg`), heroSVG(id));
  console.log(`wrote ${id}.svg`);
}
console.log(`\n${HERO_IDS.length} hero SVGs written to assets/heroes/`);
