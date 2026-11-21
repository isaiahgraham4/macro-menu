# Normalised chain source files (`<chain-id>-source.json`)

Read by `generic()` in `build-intl-menu.py`. One file per chain, written by that chain's `<chain-id>-fetch.py`.

```json
{
  "chain": "us-dunkin",            // country prefix + short name: us-, uk-, ca-, nz-, sg-, za-, in-
  "name": "Dunkin'",
  "how": "Official nutrition guide",   // a few words: what kind of source
  "url": "https://...",                // the page a person would open
  "src": "Dunkin' Nutrition Guide, US edition (dated ...). <anything left out and why>",
  "checked": "2026-11-22",
  "energy": "cal",                     // which figure the chain publishes: "cal" or "kj"
  "halal": false,                      // true where ham/bacon/sausage are chicken or beef
  "items": [
    {
      "name": "Glazed Donut",          // as a person would say it; size in brackets: "Iced Latte (medium)"
      "cat": "sweet",                  // main | side | drink | sweet | breakfast | extra (sauces, dips, add-ons)
      "serve": "1 donut (80 g)",       // or "medium (16 oz)", "1 serving"
      "cal": 240, "kj": null,          // whatever is published; the other may be null
      "p": 4, "c": 33, "f": 11,        // grams, as published
      "sat": 5, "sugar": 13, "fibre": 1,
      "sodium": 270,                   // mg; or give "salt" in g instead (UK) and leave sodium null
      "salt": null,
      "contains": ["gluten", "wheat", "milk", "egg", "soy"],   // null when the chain gives no allergens
      "may": ["treenut"],              // may-contain / shared equipment; null when not given
      "vg": null,                      // "vegan" or "vegetarian" only where the chain marks it
      "meat": null                     // optional list when the name doesn't say: ["chicken"], ["beef"], ["pork"], ["fish"], ["seafood"], ["lamb"], ["turkey"]
    }
  ]
}
```

Allergen keys: gluten, wheat, milk, egg, soy, sesame, peanut, treenut, fish, shellfish, lupin, sulphites.
Only list allergens when the chain's list covers the major ones (incl. sesame); otherwise set contains/may to null for every item.
