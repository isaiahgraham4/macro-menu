// McDonald's US menu: every item on the full menu page plus its other sizes, read from McDonald's own itemDetails API.
// Run inside a browser tab on https://www.mcdonalds.com/us/en-us/full-menu.html (curl gets "Access Denied"), e.g. with
// Playwright's browser_evaluate and a filename, and save the result as ios/Scripts/us/mcd-us-source.json.
// One request every 250 ms: fetching ~250 pages at once got the AU site to block us.
async () => {
  const get = async id => {
    const r = await fetch(`/dnaapp/itemDetails?country=US&language=en&showLiveData=true&item=${id}`);
    if (!r.ok) return {id, err: r.status};
    const it = (await r.json()).item;
    const n = {};
    for (const x of [].concat(it.nutrient_facts?.nutrient || [])) n[x.nutrient_name_id] = x.value === '' ? null : +x.value;
    // Allergens are listed per component; the item-level text mixes in ingredient statements.
    const comps = [].concat(it.components?.component || []);
    const al = new Set(), may = new Set();
    const add = (s, set) => { if (typeof s === 'string') s.replace(/<[^>]+>/g, '').split(/[.,]/).map(x => x.trim())
      .filter(x => x && x.length < 30 && !/:/.test(x)).forEach(x => set.add(x.toLowerCase())); };
    comps.forEach(c => { add(c.product_allergen, al); add(c.product_additional_allergen, may); });
    if (!comps.length) { add(it.item_allergen, al); add(it.item_additional_allergen, may); }
    const sizes = [].concat(it.relation_types?.relation_type || []).filter(t => t.type === 'size')
      .flatMap(t => [].concat(t.related_items?.related_item || [])).map(x => ({id: String(x.id), label: x.label}));
    return {id: String(id), name: it.item_name, marketing: it.item_marketing_name,
      cats: [].concat(it.categories?.category || []).map(c => c.name), n, al: [...al], may: [...may], sizes};
  };
  const ids = [...new Set([...document.querySelectorAll('[data-product-id]')].map(e => e.dataset.productId))].filter(id => /^\d{6}$/.test(id));
  const out = {}, queue = [...ids], seen = new Set(ids);
  while (queue.length) {
    const id = queue.shift();
    try {
      const o = await get(id);
      // Meals and bundles carry no nutrition of their own.
      if (o.n && o.n.calories != null) out[id] = o;
      for (const s of o.sizes || []) if (!seen.has(s.id)) { seen.add(s.id); queue.push(s.id); }
    } catch (e) { out[id] = {id, err: String(e)}; }
    await new Promise(r => setTimeout(r, 250));
  }
  return {checked: new Date().toISOString().slice(0, 10), items: Object.values(out)};
}
