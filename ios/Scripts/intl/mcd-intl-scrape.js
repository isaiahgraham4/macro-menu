// McDonald's in Canada, the UK and New Zealand: every item on the country's full menu page plus its other sizes, from McDonald's own
// itemDetails API (the same one the US and Australian menus use). Run inside a browser tab on the country's full menu page (curl gets
// "Access Denied"), e.g. with Playwright's browser_evaluate and a filename, after setting COUNTRY below; save as mcd-<cc>-source.json.
// One request every 250 ms: fetching ~250 pages at once got the AU site to block us.
async () => {
  const COUNTRY = 'CA';   // CA, UK or NZ
  const text = s => typeof s === 'string' ? s.replace(/<[^>]+>/g, '').trim() : '';
  const get = async id => {
    const r = await fetch(`/dnaapp/itemDetails?country=${COUNTRY}&language=en&showLiveData=true&item=${id}`);
    if (!r.ok) return {id, err: r.status};
    const it = (await r.json()).item;
    const n = {}, u = {};
    for (const x of [].concat(it.nutrient_facts?.nutrient || [])) { n[x.nutrient_name_id] = x.value === '' ? null : +x.value; u[x.nutrient_name_id] = x.uom; }
    const comps = [].concat(it.components?.component || []);
    const sizes = [].concat(it.relation_types?.relation_type || []).filter(t => t.type === 'size')
      .flatMap(t => [].concat(t.related_items?.related_item || [])).map(x => ({id: String(x.id), label: x.label}));
    return {id: String(id), name: it.item_name, marketing: it.item_marketing_name, cats: [].concat(it.categories?.category || []).map(c => c.name),
      n, u, item_al: text(it.item_allergen), item_may: text(it.item_additional_allergen),
      flags: [].concat(it.allergens?.allergen || []).filter(a => a.value && a.value !== 'N').map(a => [a.name, a.value]),
      comp_al: comps.map(c => text(c.product_allergen)), comp_may: comps.map(c => text(c.product_additional_allergen)),
      serve: it.serving_size_metric || '', sizes};
  };
  const ids = [...new Set([...document.querySelectorAll('[data-product-id]')].map(e => e.dataset.productId))].filter(id => /^\d{6}$/.test(id));
  const out = {}, queue = [...ids], seen = new Set(ids);
  while (queue.length) {
    const id = queue.shift();
    try {
      const o = await get(id);
      if (o.n && (o.n.calories != null || o.n.energy_kJ != null || o.n.energy_kcal != null)) out[id] = o;
      for (const s of o.sizes || []) if (!seen.has(s.id)) { seen.add(s.id); queue.push(s.id); }
    } catch (e) { out[id] = {id, err: String(e)}; }
    await new Promise(r => setTimeout(r, 250));
  }
  return {country: COUNTRY, checked: new Date().toISOString().slice(0, 10), items: Object.values(out)};
}
