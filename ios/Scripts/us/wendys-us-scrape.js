// Wendy's US menu: nutrition and allergens from each item page of Wendy's national online menu (order.wendys.com).
// The pages render in the browser only, so this runs through Playwright (browser_run_code_unsafe with this file).
// It works through the list in ~100 s batches and keeps progress in the site's localStorage under __wres;
// run it again until it reports every item ok, then save localStorage.__wres as ios/Scripts/us/wendys-us-source.json.
// The national menu shows one size per item (Jr. fries, small drinks); other sizes only appear once a store is picked.
async (page) => {
  const L = {"hamburgers":["daves-single","daves-double","daves-triple","baconator","son-of-baconator","big-bacon-classic","big-bacon-classic-double","big-bacon-classic-triple","bacon-double-stack-tm","jr-bacon-cheeseburger","jr-cheeseburger-deluxe","jr-cheeseburger","double-stack-tm","jr-hamburger"],"chicken-nuggets-more":["nuggs-party-pack","10-pc-spicy-chicken-nuggets","6-pc-spicy-chicken-nuggets","4-pc-spicy-chicken-nuggets","classic-chicken-sandwich","spicy-chicken-sandwich","grilled-chicken-wrap","asiago-ranch-club-sandwich-classic","asiago-ranch-club-sandwich-spicy","crispy-chicken-blt","crispy-chicken-sandwich","10-pc-chicken-nuggets","6-pc-chicken-nuggets","4-pc-chicken-nuggets"],"tenders":["3-pc-tenders","4-pc-tenders"],"fresh-made-salads":["parmesan-caesar-salad","cobb-salad","apple-pecan-salad","taco-salad"],"fries-sides":["french-fries","baconator-fries","chili-cheese-fries","cheese-fries","chili","sour-cream-and-chive-baked-potato","plain-baked-potato","bacon-cheese-baked-potato","chili-cheese-baked-potato","cheese-baked-potato","apple-bites"],"coffee":["regular-hot-coffee","cold-brew","vanilla-cold-brew-with-cream","caramel-cold-brew-with-cream","chocolate-cold-brew-with-cream","cold-brew-with-cream-and-sugar"],"beverages":["watermelon-lemonade","pineapple-mango-lemonade","all-natural-lemonade","strawberry-lemonade","sprite-watermelon","watermelon-sparkling-energy","pineapple-citrus-sparkling-energy","coca-cola","coca-cola-zero-sugar","diet-coke","sprite","dr-pepper","diet-dr-pepper","barqs-root-beer","fanta-orange","minute-maid-light-lemonade","hi-c-flashin-fruit-punch","pure-life-bottled-water","milk","chocolate-milk","honest-kids-fruit-punch","simply-orange-juice"],"frosty":["classic-chocolate-frosty","vanilla-frosty","cookie-dough-frosty-fusion-vanilla","cookie-dough-frosty-fusion-chocolate","oreo-brownie-vanilla-frosty-fusion-tm","caramel-crunch-vanilla-frosty-fusion-tm","brownie-batter-vanilla-frosty-swirl-tm","strawberry-vanilla-frosty-swirl-tm","caramel-vanilla-frosty-swirl-tm","oreo-brownie-chocolate-frosty-fusion-tm","caramel-crunch-chocolate-frosty-fusion-tm","brownie-batter-chocolate-frosty-swirl-tm","strawberry-chocolate-frosty-swirl-tm","caramel-chocolate-frosty-swirl-tm"],"bakery":["cinnabon-pull-apart","chocolate-chunk-cookie","sugar-cookie"],"croissants":["maple-bacon-chicken-croissant","sausage-egg-swiss-croissant","bacon-egg-swiss-croissant"],"biscuits":["sausage-egg-cheese-biscuit","bacon-egg-cheese-biscuit","egg-cheese-biscuit","honey-buddy-chicken-biscuit","honey-butter-biscuit","sausage-gravy-biscuit","sausage-biscuit"],"classics":["breakfast-baconator","homestyle-french-toast-sticks-4-pc","homestyle-french-toast-sticks-6-pc"],"breakfast-burrito":["breakfast-burrito-bacon","breakfast-burrito-sausage"],"sides-and-sweets":["seasoned-potatoes"]};
  const all = Object.entries(L).flatMap(([c, a]) => a.map(s => [c, s]));
  const parse = () => {
    const t = document.body.innerText;
    const name = (document.querySelector('h1')?.innerText || '').trim();
    const num = lab => { const m = t.match(new RegExp('\\n' + lab + '\\n([\\d.]+)')); return m ? +m[1] : null; };
    let al = null;
    if (/\nNo Allergens\n/.test(t)) al = [];
    else { const m = t.match(/Allergens\*\n([\s\S]*?)\n\n[^\n]*We provide/); if (m) al = m[1].split('\n').map(x => x.trim()).filter(Boolean); }
    const desc = (t.match(/What's On It\n\n([^\n]+)/) || [])[1] || '';
    return {name, cal: num('Calories'), fat: num('Total fat'), sat: num('Saturated fat'), sodium: num('Sodium'), carbs: num('Total Carbohydrate'), fibre: num('Dietary Fiber'), sugar: num('Total Sugars'), protein: num('Protein'), al, desc};
  };
  await page.goto('https://order.wendys.com/us/en/national/menu?site=menu');
  let res = JSON.parse(await page.evaluate(() => localStorage.getItem('__wres') || '{}'));
  const t0 = Date.now();
  for (const [c, s] of all) {
    if (res[s] && !res[s].err) continue;
    if (Date.now() - t0 > 100000) break;
    await page.goto(`https://order.wendys.com/us/en/national/menu/${c}/${s}?site=menu`);
    try { await page.waitForFunction(() => { const t = document.body.innerText; return /Calories\n\d/.test(t) && (/No Allergens/.test(t) || /We provide known/.test(t)); }, null, {timeout: 15000}); await page.waitForTimeout(300); res[s] = {cat: c, ...(await page.evaluate(parse))}; }
    catch (e) { res[s] = {cat: c, err: String(e).slice(0, 80)}; }
    await page.evaluate(r => localStorage.setItem('__wres', JSON.stringify(r)), res);
  }
  return Object.values(res).filter(x => !x.err).length + ' ok, ' + Object.values(res).filter(x => x.err).length + ' err / ' + all.length;
}
