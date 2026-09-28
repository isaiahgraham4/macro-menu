// Export only the data and pure modifier functions from the existing web source.
const fs = require('fs');
const vm = require('vm');
const path = require('path');
const root = path.resolve(__dirname, '../..');
const source = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const between = (a,b) => source.slice(source.indexOf(a), source.indexOf(b, source.indexOf(a)));
const code = between('const CHAINS =', '/* ---------- helpers') + '\n' +
 between('const GYG_MODS =', '// A take-off and a swap') + '\n' +
 between('function extraFits(', 'function findMeals(') + '\n' +
 `JSON.stringify({chains:CHAINS, foods:BUILTIN.map(f=>({...f, modifiers:modsFor(f)}))})`;
const result = vm.runInNewContext(code, {}, {timeout: 5000});
const data = JSON.parse(result);
if (!data.foods.length || new Set(data.foods.map(f=>f.id)).size !== data.foods.length) throw Error('Invalid menu IDs');

// McDonald's lists each ingredient's energy (mcd-ingredients.json). Turn those into "take off" options.
// Energy is official; protein, carbs and fat are estimated from the ingredient type, so they're marked est.
const ingredients = require('./mcd-ingredients.json').items;
// Not removable: trace items, and the base liquid of a drink.
const SKIP = /^(WATER|ICE|COFFEE EXTRACT|SPRAY OIL|SEASONING|FULL CREAM MILK|OAT MILK|SPRITE|LEMONADE CONCENTRATE|MATCHA POWDER)$/;
// [pattern, protein, carbs, fat] as shares of the ingredient's energy. First match wins.
const SPLITS = [
  [/FUDGE|DRIZZLE|FLAKE|M&M|OREO|TIM TAM|BISCOTTI|CHOCOLATE POWDER|MATCHA/, 0.05, 0.60, 0.35],
  [/KETCHUP|BBQ|CHILLI JAM|SYRUP|TOPPING|LEMONADE|SPRITE|PEARLS/, 0.02, 0.95, 0.03],
  [/MUSTARD/, 0.20, 0.45, 0.35],
  [/SAUCE/, 0.02, 0.10, 0.88],
  [/CHEESE|MOZZARELLA/, 0.26, 0.04, 0.70],
  [/HASH BROWN|CRISPY ONIONS/, 0.04, 0.44, 0.52],
  [/BUN|MUFFIN|TORTILLA|SOURDOUGH|TOAST|CONE|HOTCAKES|BREAD/, 0.14, 0.72, 0.14],
  [/BEEF PATT/, 0.38, 0.01, 0.61],
  [/SAUSAGE/, 0.23, 0.02, 0.75],
  [/CHICKEN PATTY|FILET/, 0.22, 0.30, 0.48],
  [/BACON/, 0.30, 0.01, 0.69],
  [/HAM/, 0.60, 0.10, 0.30],
  [/EGG/, 0.35, 0.02, 0.63],
  [/LETTUCE|TOMATO|PICKLES|ONIONS|STRAWBERRY PIECES/, 0.12, 0.83, 0.05],
  [/WHIPPED CREAM|COLD FOAM|BUTTER/, 0.03, 0.10, 0.87],
  [/MILK/, 0.21, 0.29, 0.50],
];
// Title case to match GYG's options ("No Tomatillo Salsa").
const LABELS = {'SHREDDED LETTUCE':'Lettuce', 'SLICED TOMATO':'Tomato', 'SLICED CHEESE':'Cheese', 'WHITE CHEDDAR CHEESE':'Cheese',
  'SLIVERED ONIONS':'Onions', 'HOUSE GRILLED BBQ SAUCE':'BBQ Sauce', 'FILET-O-FISH PORTION':'Fish', "M&M'S MINIS":"M&M's",
  'OREO COOKIES PIECES':'Oreo Pieces', 'TIM TAM JATZ BISCUIT CRUMB':'Biscuit Crumb', 'SALTED TIM TAM SAUCE':'Tim Tam Sauce',
  'CADBURY FLAKE':'Flake', 'HOT CHOCOLATE POWDER':'Chocolate Powder', 'CHOCOLATE SHAKE SYRUP':'Chocolate Syrup'};
const label = raw => LABELS[raw] || (/BEEF PATT/.test(raw) ? 'Beef' : /CHICKEN PATTY/.test(raw) ? 'Chicken Patty'
  : /BUN$/.test(raw) ? 'Bun' : /TORTILLA/.test(raw) ? 'Tortilla'
  : raw.toLowerCase().replace(/\b\w/g, c => c.toUpperCase()).replace(/\bMc(\w)/g, (_, c) => 'Mc' + c.toUpperCase()));
const round = x => Math.round(x * 10) / 10;
let added = 0;
for (const food of data.foods) {
  const entry = ingredients[food.id];
  if (!entry) continue;
  const [, itemKj, parts] = entry;
  if (itemKj !== food.kj) console.warn(`${food.id}: menu has ${food.kj} kJ, McDonald's lists ${itemKj} kJ`);
  const missing = parts.filter(p => p[1] == null);
  const known = parts.reduce((sum, p) => sum + (p[1] ?? 0), 0);
  const keys = new Set((food.modifiers || []).map(m => m.key));
  for (const [raw, listed] of parts) {
    // One unlisted part (often the patty) is whatever energy the others don't account for.
    const kj = listed ?? (missing.length === 1 ? itemKj - known : null);
    if (kj == null || kj <= 0 || SKIP.test(raw) || kj > itemKj * 0.55) continue;
    const [, ps, cs, fs] = SPLITS.find(([re]) => re.test(raw)) || [null,
      ...(() => { const e = food.p * 4 + (food.c ?? 0) * 4 + (food.f ?? 0) * 9 || 1; return [food.p * 4 / e, (food.c ?? 0) * 4 / e, (food.f ?? 0) * 9 / e]; })()];
    const kcal = kj / 4.184, name = label(raw);
    let slug = name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, ''), key = `r:${slug}`;
    for (let n = 2; keys.has(key); n++) key = `r:${slug}-${n}`;
    keys.add(key);
    food.modifiers = [...(food.modifiers || []), {key, id: `no-${slug}`, kind: 'r', name: `No ${name}`,
      kj: -kj, p: -round(kcal * ps / 4), c: -round(kcal * cs / 4), f: -round(kcal * fs / 9), price: 0, est: true}];
    added++;
  }
}
console.log(`Added ${added} McDonald's ingredient removals.`);

// Subway lists every sub's standard build and each ingredient's nutrition per portion (subway-ingredients.json),
// so its "take off" options carry full nutrition. Breads and the main filling stay on.
const subway = require('./subway-ingredients.json');
const SUBWAY_LABELS = {'Old English Cheese': 'Cheese', 'Three Cheeses': 'Cheese'};
const pick = name => subway.subs[name] || subway.subs[name.replace(/ Brekkie$/, '')] || subway.subs[name + ' on Rye'];
function subwayBuild(name) {
  let m;
  if ((m = name.match(/^6" (.+)$/))) return {parts: pick(m[1]), scale: 1};
  if ((m = name.match(/^Footlong (.+)$/))) return {parts: pick(m[1]), scale: 2};
  if ((m = name.match(/^(.+) 6"$/))) return {parts: pick(m[1]), scale: 1};
  if ((m = name.match(/^(.+) Wrap$/))) {
    const parts = pick(m[1]);
    return {parts: parts && parts.map(part => /Bread$/.test(part) ? 'Flour Wrap' : part), scale: 1};
  }
  // Regular salads only list their cheese and dressing; the salad itself is a bigger serve than on a sub.
  if ((m = name.match(/^(.+) Salad \(regular\)$/))) return {parts: subway.salads[m[1]], scale: 1, toppingsOnly: true};
  return {};
}
let subwayAdded = 0, subwayItems = 0;
for (const food of data.foods.filter(f => f.chain === 'sub')) {
  const {parts, scale, toppingsOnly} = subwayBuild(food.name);
  if (!parts) continue;
  const missing = parts.filter(part => !subway.parts[part]);
  if (missing.length) throw Error(`${food.name}: unknown Subway parts ${missing}`);
  if (!toppingsOnly) {
    // The parts should add up to the published total; if not, the build is out of date, so skip it.
    const total = parts.reduce((sum, part) => sum + subway.parts[part][0], 0) * scale;
    if (Math.abs(total - food.kj) > food.kj * 0.03) { console.warn(`${food.name}: parts add to ${Math.round(total)} kJ, menu lists ${food.kj}`); continue; }
  }
  const keys = new Set((food.modifiers || []).map(mod => mod.key));
  let any = false;
  for (const part of parts) {
    if (subway.base.includes(part)) continue;
    const [kj, p, f, sat, c, sugar, fibre, sodium] = subway.parts[part].map(v => v * scale);
    if (kj > food.kj * 0.55) continue;
    const name = SUBWAY_LABELS[part] || part;
    const slug = name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
    if (keys.has(`r:${slug}`)) continue;
    keys.add(`r:${slug}`);
    food.modifiers = [...(food.modifiers || []), {key: `r:${slug}`, id: `no-${slug}`, kind: 'r', name: `No ${name}`,
      kj: -round(kj), p: -round(p), c: -round(c), f: -round(f),
      nut: {sat: -round(sat), sugar: -round(sugar), fibre: -round(fibre), sodium: -round(sodium)}, price: 0}];
    subwayAdded++; any = true;
  }
  if (any) subwayItems++;
}
console.log(`Added ${subwayAdded} Subway ingredient removals across ${subwayItems} items.`);

// Hungry Jack's doesn't list ingredient nutrition, but some burgers come with and without cheese.
// The difference between the two is exactly what the cheese adds.
const HJ_CHEESE = [['hj:whopper-with-cheese', 'hj:whopper'], ['hj:double-whopper-with-cheese', 'hj:double-whopper'],
  ['hj:cheeseburger', 'hj:hamburger'], ['hj:plant-based-whopper-with-cheese', 'hj:plant-based-whopper']];
const byId = Object.fromEntries(data.foods.map(f => [f.id, f]));
for (const [withId, withoutId] of HJ_CHEESE) {
  const withCheese = byId[withId], without = byId[withoutId];
  if (!withCheese || !without) { console.warn(`Missing ${withId} or ${withoutId}`); continue; }
  const diff = key => round((withCheese[key] ?? 0) - (without[key] ?? 0));
  if (diff('kj') <= 0 || diff('f') < 0 || diff('p') < 0) { console.warn(`${withId}: cheese difference doesn't add up`); continue; }
  const nut = Object.fromEntries(Object.keys(withCheese.nut || {}).filter(k => without.nut?.[k] != null)
    .map(k => [k, -round(withCheese.nut[k] - without.nut[k])]));
  withCheese.modifiers = [...(withCheese.modifiers || []), {key: 'r:cheese', id: 'no-cheese', kind: 'r', name: 'No Cheese',
    kj: -diff('kj'), p: -diff('p'), c: -diff('c'), f: -diff('f'), nut, price: 0}];
}
console.log(`Added Hungry Jack's cheese removals to ${HJ_CHEESE.length} burgers.`);
fs.writeFileSync(path.join(root, 'ios/MacroMenu/MenuData.json'), JSON.stringify(data));
console.log(`Exported ${data.foods.length} foods across ${data.chains.length-1} restaurants.`);
