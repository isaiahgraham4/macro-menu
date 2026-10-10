// Builds ios/MacroMenu/MenuData.json from menu-source.js (the menus and the rules for customising orders).
const fs = require('fs');
const vm = require('vm');
const path = require('path');
const root = path.resolve(__dirname, '../..');
const code = fs.readFileSync(path.join(__dirname, 'menu-source.js'), 'utf8') + '\n' +
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
const byId = Object.fromEntries(data.foods.map(f => [f.id, f]));
// Parts McDonald's also sells on their own, with full nutrition: scale that to the part's energy instead of estimating.
const SOLD_ALONE = [[/^MCCHICKEN SAUCE$/, 'mcd:dipping-sauce-mcchicken'], [/^BIG MAC SAUCE$/, 'mcd:dipping-sauce-big-mac'],
  [/^TARTAR SAUCE$/, 'mcd:dipping-sauce-tartare'], [/^KETCHUP$/, 'mcd:dipping-sauce-ketchup'],
  [/^TOMATO CHILLI JAM$/, 'mcd:dipping-sauce-tomato-chilli-jam'], [/^HASH BROWN$/, 'mcd:hash-brown']];
/** Protein, carbs and fat for `kj` of a McDonald's part, with `est` when they're worked out from the ingredient type. */
function partNutrition(raw, kj, food) {
  const alone = SOLD_ALONE.find(([re]) => re.test(raw));
  const source = alone && byId[alone[1]];
  if (source) {
    const k = kj / source.kj;
    const nut = Object.fromEntries(Object.entries(source.nut || {}).map(([key, v]) => [key, round(v * k)]));
    return {p: round(source.p * k), c: round((source.c ?? 0) * k), f: round((source.f ?? 0) * k), nut, est: false};
  }
  const [, ps, cs, fs] = SPLITS.find(([re]) => re.test(raw)) || [null,
    ...(() => { const e = food.p * 4 + (food.c ?? 0) * 4 + (food.f ?? 0) * 9 || 1; return [food.p * 4 / e, (food.c ?? 0) * 4 / e, (food.f ?? 0) * 9 / e]; })()];
  const kcal = kj / 4.184;
  return {p: round(kcal * ps / 4), c: round(kcal * cs / 4), f: round(kcal * fs / 9), est: true};
}
const negate = n => ({p: -n.p, c: -n.c, f: -n.f, ...(n.nut ? {nut: Object.fromEntries(Object.entries(n.nut).map(([k, v]) => [k, -v]))} : {}), ...(n.est ? {est: true} : {})});
const slugOf = name => name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
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
    const name = label(raw), slug = slugOf(name);
    let key = `r:${slug}`;
    for (let n = 2; keys.has(key); n++) key = `r:${slug}-${n}`;
    keys.add(key);
    food.modifiers = [...(food.modifiers || []), {key, id: `no-${slug}`, kind: 'r', name: `No ${name}`,
      kj: -kj, ...negate(partNutrition(raw, kj, food)), price: 0}];
    added++;
  }
}
console.log(`Added ${added} McDonald's ingredient removals.`);

// What McDonald's will add to a burger, McMuffin or wrap: another patty, slice, rasher or egg, more of its sauce or salad,
// or bacon and cheese where it has none. Energy is McDonald's own figure for that ingredient.
// One patty, slice or rasher, as it comes in the single versions (Cheeseburger, Quarter Pounder, McChicken…).
const UNITS = [
  [/^10:1 BEEF PATT/, 'Beef Patty', 'f', 446], [/^4:1 BEEF PATT/, 'Quarter Pounder Patty', 'f', 1050],
  [/^MCCHICKEN PATTY/, 'McChicken Patty', 'f', 767], [/^MCCRISPY CHICKEN PATTY/, 'McCrispy Chicken', 'f', 1250],
  [/^MCSPICY CHICKEN PATTY/, 'McSpicy Chicken', 'f', 1280], [/^FILET-O-FISH PORTION/, 'Fish', 'f', 524],
  [/^BEEF SAUSAGE/, 'Sausage', 'f', 471], [/^EGG$/, 'Egg', 'f', 295], [/^HASH BROWN$/, 'Hash Brown', 'a', 600],
  [/^BACON$/, 'Bacon', 'a', 116], [/^SLICED CHEESE$|^WHITE CHEDDAR CHEESE$/, 'Cheese', 'a', 202],
];
// Sauces and salad go on again at the item's own portion.
const AGAIN = /SAUCE|KETCHUP|MUSTARD|CHILLI JAM|PICKLES|ONIONS|LETTUCE|TOMATO|SLAW/;
const BUILT = /BUN$|MUFFIN$|TORTILLA$/;
let extras = 0;
for (const food of data.foods) {
  const entry = ingredients[food.id];
  if (!entry || !entry[2].some(([raw]) => BUILT.test(raw))) continue;
  const mods = [], seen = new Set();
  const add = (raw, name, kind, kj) => {
    const slug = slugOf(name);
    if (seen.has(slug) || !(kj > 0)) return;
    seen.add(slug);
    mods.push({key: `${kind}:${slug}`, id: `extra-${slug}`, kind, name, kj, ...partNutrition(raw, kj, food), price: null});
  };
  for (const [raw, listed] of entry[2]) {
    const unit = UNITS.find(([re]) => re.test(raw));
    if (unit) add(raw, `Extra ${unit[1]}`, unit[2], unit[3]);
    else if (AGAIN.test(raw) && listed > 0) add(raw, `Extra ${label(raw)}`, 'a', listed);
  }
  if (!seen.has('extra-bacon')) add('BACON', 'Add Bacon', 'a', 116);
  if (!seen.has('extra-cheese')) add('SLICED CHEESE', 'Add Cheese', 'a', 202);
  // Estimated extras keep the item's other nutrients as listed, like the removals.
  for (const mod of mods) { if (!mod.est) delete mod.est; if (mod.price == null) delete mod.price; }
  food.modifiers = [...(food.modifiers || []), ...mods];
  extras += mods.length;
}
console.log(`Added ${extras} McDonald's extras.`);

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

// Hungry Jack's, KFC, Oporto and Red Rooster don't list what an extra adds, but sell some items with and without it.
// The difference between the two published items is exactly what that extra adds, so it can go on or come off.
// [what, without, with, items it can be added to, items it can be taken off, kind, name to add, name to take off]
// The names are for differences that aren't a single ingredient, such as a Grill Masters double or a Red Rooster triple.
const PAIRS = [
  ['Cheese', 'hj:whopper', 'hj:whopper-with-cheese', ['hj:whopper'], ['hj:whopper-with-cheese'], 'a'],
  ['Cheese', 'hj:double-whopper', 'hj:double-whopper-with-cheese', ['hj:double-whopper'], ['hj:double-whopper-with-cheese'], 'a'],
  ['Cheese', 'hj:hamburger', 'hj:cheeseburger', ['hj:hamburger'], ['hj:cheeseburger'], 'a'],
  ['Cheese', 'hj:plant-based-whopper', 'hj:plant-based-whopper-with-cheese', ['hj:plant-based-whopper'], ['hj:plant-based-whopper-with-cheese'], 'a'],
  ['Whopper Patty', 'hj:whopper', 'hj:double-whopper', ['hj:whopper', 'hj:whopper-with-cheese', 'hj:double-whopper', 'hj:double-whopper-with-cheese',
    'hj:triple-whopper-with-cheese', 'hj:angry-whopper', 'hj:cowboy-whopper', 'hj:double-cowboy-whopper', 'hj:ultimate-double-whopper'], [], 'f'],
  ['Patty & Cheese', 'hj:cheeseburger', 'hj:double-cheeseburger', ['hj:cheeseburger', 'hj:double-cheeseburger', 'hj:triple-cheeseburger', 'hj:bbq-cheeseburger'], [], 'f'],
  ['Bacon & Cheese', 'hj:grilled-chicken-burger', 'hj:grilled-chicken-with-bacon-cheese', ['hj:grilled-chicken-burger', 'hj:spicy-grilled-chicken-burger'],
    ['hj:grilled-chicken-with-bacon-cheese'], 'a'],
  ['Bacon & Cheese', 'hj:classic-jack-s-fried-chicken', 'hj:cheesy-bacon-classic-jack-s-fried-chicken', ['hj:classic-jack-s-fried-chicken'],
    ['hj:cheesy-bacon-classic-jack-s-fried-chicken'], 'a'],
  ['Bacon & Cheese', 'hj:spicy-jack-s-fried-chicken', 'hj:cheesy-bacon-spicy-jack-s-fried-chicken', ['hj:spicy-jack-s-fried-chicken'],
    ['hj:cheesy-bacon-spicy-jack-s-fried-chicken'], 'a'],
  ['Bacon & Cheese', 'kfc:original-crispy-burger', 'kfc:original-crispy-bacon-cheese-burger', ['kfc:original-crispy-burger'], ['kfc:original-crispy-bacon-cheese-burger'], 'a'],
  ['Bacon & Cheese', 'kfc:zinger-burger', 'kfc:zinger-bacon-cheese-burger', ['kfc:zinger-burger'], ['kfc:zinger-bacon-cheese-burger'], 'a'],
  ['Cheese', 'hj:whopper-junior', 'hj:whopper-junior-with-cheese', ['hj:whopper-junior'], ['hj:whopper-junior-with-cheese'], 'a'],
  // Grill Masters Chicago is left out: its single and double are published only 315 kJ apart, which looks like an error.
  ...['bbq-smokehouse', 'spicy-chipotle', 'smoky-chipotle', 'cowboy'].map(kind =>
    ['Double', `hj:grill-masters-${kind}-angus`, `hj:grill-masters-double-${kind}-angus`, [`hj:grill-masters-${kind}-angus`],
      [`hj:grill-masters-double-${kind}-angus`], 'f', 'Make it a Double', 'Make it a Single']),
  ['Double', 'hj:grill-masters-angus-bacon-cheese', 'hj:grill-masters-double-angus-bacon-cheese', ['hj:grill-masters-angus-bacon-cheese'],
    ['hj:grill-masters-double-angus-bacon-cheese'], 'f', 'Make it a Double', 'Make it a Single'],
  ['Chicken Fillet', 'oporto:bacon-egg-burger', 'oporto:chicken-bacon-egg-burger', ['oporto:bacon-egg-burger'],
    ['oporto:chicken-bacon-egg-burger'], 'f', 'Add Chicken Fillet', 'No Chicken Fillet'],
  ['Bacon', 'oporto:chicken-egg-burger', 'oporto:chicken-bacon-egg-burger', ['oporto:chicken-egg-burger'], ['oporto:chicken-bacon-egg-burger'], 'a'],
  ...['flayva-wrap', 'rippa-roll', 'honey-bbq-rippa-roll', 'reds-burger', 'bbq-bacon-burger', 'spicy-burger', 'picklebird-burger'].map(item =>
    ['Triple', `rr:${item}`, `rr:triple-${item}`, [`rr:${item}`], [`rr:triple-${item}`], 'f', 'Make it a Triple', 'Make it a Regular']),
];
let paired = 0;
for (const [what, withoutId, withId, addTo, takeOff, kind, addName, removeName] of PAIRS) {
  const withIt = byId[withId], without = byId[withoutId];
  if (!withIt || !without) throw Error(`Missing ${withId} or ${withoutId}`);
  const diff = key => round((withIt[key] ?? 0) - (without[key] ?? 0));
  if (diff('kj') <= 0 || diff('f') < 0 || diff('p') < 0) throw Error(`${withId}: ${what} difference doesn't add up`);
  const nut = Object.fromEntries(Object.keys(withIt.nut || {}).filter(k => without.nut?.[k] != null)
    .map(k => [k, Math.max(0, round(withIt.nut[k] - without.nut[k]))]));
  const amounts = {kj: diff('kj'), p: diff('p'), c: diff('c'), f: diff('f'), nut};
  const slug = slugOf(what), name = addName || (kind === 'f' ? `Extra ${what}` : `Add ${what}`);
  for (const id of addTo) {
    const food = byId[id];
    if (!food) throw Error(`Missing ${id}`);
    food.modifiers = [...(food.modifiers || []), {key: `${kind}:${slug}`, id: `extra-${slug}`, kind, name, ...amounts, price: null}]
      .map(m => { if (m.price == null) delete m.price; return m; });
    paired++;
  }
  for (const id of takeOff) {
    const food = byId[id];
    if (!food) throw Error(`Missing ${id}`);
    food.modifiers = [...(food.modifiers || []), {key: `r:${slug}`, id: `no-${slug}`, kind: 'r', name: removeName || `No ${what}`,
      kj: -amounts.kj, p: -amounts.p, c: -amounts.c, f: -amounts.f, nut: Object.fromEntries(Object.entries(nut).map(([k, v]) => [k, -v])), price: 0}];
    paired++;
  }
}
console.log(`Added ${paired} extras and removals worked out from pairs of items sold with and without them.`);

// KFC sells its fillets on their own, so a burger can take another one at that item's published nutrition.
const SOLD_SEPARATELY = [
  ['kfc:zinger-fillet-piece', 'Add a Zinger Fillet',
    ['kfc:zinger-burger', 'kfc:zinger-bacon-cheese-burger', 'kfc:zinger-stacker-burger', 'kfc:zinger-crunch-burger']],
  ['kfc:original-crispy-fillet-piece', 'Add an Original Crispy Fillet',
    ['kfc:original-crispy-burger', 'kfc:original-crispy-bacon-cheese-burger', 'kfc:original-crispy-bbq-bacon-stacker-burger']],
];
let separate = 0;
for (const [itemId, name, addTo] of SOLD_SEPARATELY) {
  const item = byId[itemId];
  if (!item) throw Error(`Missing ${itemId}`);
  for (const id of addTo) {
    const food = byId[id];
    if (!food) throw Error(`Missing ${id}`);
    food.modifiers = [...(food.modifiers || []), {key: `item:${itemId}`, id: itemId, kind: 'f', name,
      kj: item.kj, p: item.p, c: item.c, f: item.f, ...(item.nut ? {nut: item.nut} : {})}];
    separate++;
  }
}
console.log(`Added ${separate} extras that are sold on their own.`);
// format: the app only accepts formats it understands. revision: a fingerprint of the menu.
// published: when this revision was first exported; unchanged menus keep their date, so a re-export isn't "newer".
// Prices are switched off for now: they vary too much between stores. menu-source.js keeps them for later;
// set SHOW_PRICES to true to ship them again.
const SHOW_PRICES = false;
if (!SHOW_PRICES) {
  for (const food of data.foods) { delete food.price; delete food.pf; for (const mod of food.modifiers || []) delete mod.price; }
  for (const chain of data.chains) delete chain.psrc;
}
const crypto = require('crypto');
const bundledPath = path.join(root, 'ios/MacroMenu/MenuData.json');
const revision = crypto.createHash('sha256').update(JSON.stringify({chains: data.chains, foods: data.foods})).digest('hex').slice(0, 16);
let published = new Date().toISOString();
try { const previous = JSON.parse(fs.readFileSync(bundledPath, 'utf8')); if (previous.revision === revision && previous.published) published = previous.published; } catch {}
const menu = JSON.stringify({format: 1, revision, published, chains: data.chains, foods: data.foods});
fs.writeFileSync(bundledPath, menu);
console.log(`Exported ${data.foods.length} foods across ${data.chains.length-1} restaurants.`);
