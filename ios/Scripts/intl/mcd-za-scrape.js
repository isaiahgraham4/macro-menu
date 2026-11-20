// McDonald's South Africa: mcdonalds.co.za is its own site (not the dnaapp API the other countries use). Every item page under
// index.php?p=menu/<slug> carries its allergens, a nutrition summary, and one button per size with the figures in data attributes.
// Run inside a browser tab on https://www.mcdonalds.co.za/ (curl gets 403), e.g. with Playwright's browser_evaluate and a
// filename; save as mcd-za-source.json. One request every 300 ms.
async () => {
  const CATS = ['all-day-breakfast', 'chicken-sandwiches', 'beef', 'vegetarian', 'salads', 'mccaf%C3%A9', 'beverages', 'desserts-shakes',
                'snacks-sides', 'sharebox', 'limited-offers', 'happy-meal', 'combo-meals'];
  const SKIP = new Set([...CATS, 'happy-meal', 'combo-meals']);
  const page = async slug => {
    const r = await fetch('/index.php?p=menu/' + slug);
    return r.ok ? new DOMParser().parseFromString(await r.text(), 'text/html') : null;
  };
  const wait = () => new Promise(r => setTimeout(r, 300));
  const where = {};
  for (const cat of CATS) {
    const d = await page(cat);
    await wait();
    if (!d) continue;
    for (const a of d.querySelectorAll('a[href*="p=menu/"]')) {
      const slug = a.getAttribute('href').split('p=menu/')[1].split(/[#&]/)[0];
      if (!SKIP.has(slug) && !CATS.includes(slug)) (where[slug] ||= new Set()).add(decodeURIComponent(cat));
    }
  }
  const items = [];
  for (const slug of Object.keys(where)) {
    try {
      const d = await page(slug);
      await wait();
      if (!d) { items.push({slug, err: 'not found'}); continue; }
      const text = sel => d.querySelector(sel)?.textContent.trim() ?? null;
      const sizes = [...d.querySelectorAll('button[data-product-cals]')].map(b => ({label: b.textContent.trim(), ...Object.fromEntries(
        [...b.attributes].filter(a => a.name.startsWith('data-')).map(a => [a.name.replace(/^data-(product|table)-/, '$1_'), a.value]))}));
      items.push({slug, cats: [...where[slug]], name: text('h1'),
        allergens: [...d.querySelectorAll('#IngredientsCollapse .card-body p')].map(p => p.textContent.trim()).filter(Boolean),
        hasAllergenCard: !!d.querySelector('#IngredientsCollapse'),
        n: {cal: text('.tablecals'), fat: text('.changeFats'), carbs: text('.changeCarbs'), protein: text('.changeProtein'), sat: text('.tablesf'),
            sodium: text('.tableSod'), fibre: text('.tableFiber'), sugar: text('.tableSugar')},
        sizes});
    } catch (e) { items.push({slug, err: String(e)}); }
  }
  return {country: 'ZA', checked: new Date().toISOString().slice(0, 10), items};
}
