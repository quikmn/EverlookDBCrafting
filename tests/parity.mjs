// The site's own route for a few professions, for the parity test (tests/run.py): everlookdb.com's route rule
// (web/route.js, imported) and the functions of web/professions.js (prepare, source, analyse), cut out of the file as
// they are and run on web/data/guides.json. Prices are the site's effort weights (source(id).e), through the site's gold-route
// path (a price function, a score of the material cost, the tier factors of web/learntier.js).
//   node tests/parity.mjs <Quarry dir> <side a|h> <skill> [<skill> ...]  ->  JSON { skill: [[from, to, spell], ...] }
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const [quarry, side, ...skills] = process.argv.slice(2);
const { learnWays, obtainTier, MAIN_TIER, tierFactor } = await import(pathToFileURL(join(quarry, 'web/learntier.js')).href);
const { chanceAt, buildGuide, routePool, cheapestRoute } = await import(pathToFileURL(join(quarry, 'web/route.js')).href);
const src = readFileSync(join(quarry, 'web/professions.js'), 'utf8');
const fn = (name) => { const i = src.indexOf(`function ${name}(`); if (i < 0) throw new Error(`no ${name}`); return src.slice(i, src.indexOf('\n}\n', i) + 3); };
const line = (start) => { const i = src.indexOf(start); if (i < 0) throw new Error(`no ${start}`); return src.slice(i, src.indexOf('\n', i) + 1); };
const region = src.slice(src.indexOf('const QI ='), src.indexOf('// ------------------------------------------------------------------ data prep'));
const G = JSON.parse(readFileSync(join(quarry, 'web/data/guides.json'), 'utf8'));
const code = ['const CAP =', 'const STRETCH =', 'const TIERS =', 'const INTERNAL ='].map(line).join('') + region
  + fn('prepare') + fn('analyse') + `
  const item = (id) => G.items[id];
  const state = { side: SIDE };
  const tierOf = (r, s = state.side) => (r.tiers ??= {})[s] ??= obtainTier(G, r.ways, s);
  const openRecipe = (r) => tierOf(r, 'both').t <= MAIN_TIER;   // prepare's start fix uses the default side
  const inDefault = (r) => tierOf(r).t <= MAIN_TIER && !r.mats.some(([i]) => source(i).cd);
  indexMakers();
  const out = {};
  const base = (id) => { const e = source(id).e; return { e, gold: e }; };
  for (const id of SKILLS) {
    const p = prepare(G.professions.find((x) => String(x.id) === String(id)));
    const pool = p.recipes.filter(inDefault);
    const m = analyse(pool, base, (r, c) => c.e, state.side);
    out[id] = m.guide.steps.map((st) => [st.from, st.to, st.r.spell, st.n]);
    out[id + ':stall'] = m.guide.stall ?? null;
  }
  return out;`;
const run = new Function('G', 'learnWays', 'obtainTier', 'MAIN_TIER', 'tierFactor', 'chanceAt', 'buildGuide', 'routePool', 'cheapestRoute', 'SIDE', 'SKILLS', code);
process.stdout.write(JSON.stringify(run(G, learnWays, obtainTier, MAIN_TIER, tierFactor, chanceAt, buildGuide, routePool, cheapestRoute, side, skills)));
