# Restaurant data: sources and permission requests

Leanr's restaurant figures are facts (energy, protein, carbs, fat, serve size) re-entered from each chain's own
published nutrition information. No descriptions, photos or logos are copied. Each chain's source, collection method
and the menu snapshot date are in `Scripts/menu-source.js` (`src`, `how`, `url`) and show on every food's page under
Source. Items a chain publishes no figures for are left out; third-party databases such as CalorieKing aren't used.

A written "yes" from a chain removes any question about using its figures. Send each one the request below through the
contact or feedback form on its Australian website (or its media / marketing contact), then record the answer here.

## Request template

Subject: Permission to show [Chain]'s published nutrition information in a free app

Hi [Chain] team,

I'm Isaiah Graham, an independent developer in Victoria. I make Leanr, a free iPhone app that helps people find and log
fast-food orders that fit their calorie and protein targets.

Leanr shows the energy, protein, carbohydrate, fat and serve size that [Chain] publishes in its nutrition information,
unchanged and credited to [Chain] with a link to your nutrition page. It doesn't use your logos, photos or menu
descriptions, and it says clearly that Leanr isn't affiliated with [Chain].

Could you confirm you're happy for Leanr to show these figures? If you'd prefer a different source (for example a
nutrition file you update), or would like anything changed or removed, I'll act on it straight away.

Thanks,
Isaiah Graham
[contact email]

## Tracker

| Chain | Source used | Asked | Answer |
|---|---|---|---|
| McDonald's | Official website item pages | | |
| KFC | Official nutrition and allergen guide | | |
| Hungry Jack's | Official website item pages and nutrition guide PDFs | | |
| Subway | Official nutrition guide | | |
| Guzman y Gomez | Official nutrition guide | | |
| Nando's | Official website nutrition information | | |
| Oporto | Official website menu nutrition panels | | |
| Red Rooster | Official website menu nutrition panels | | |
| Domino's | Official website nutritional information | | |
| Spud Bar | In-store menu board (photo) and official website | | |
| Zambrero | Official nutrition information sheet | | |
| Boost Juice | Official allergen and nutrition information | | |

## Prices

Prices are switched off for now and aren't shipped in the app (`SHOW_PRICES` in `Scripts/export-menu.cjs`). If they
return, only take them from public menus or in-store boards, not from inside an ordering app whose terms forbid copying.

## If a chain asks for removal

Delete its rows in `Scripts/menu-source.js`, run `node Scripts/export-menu.cjs`, update the catalogue count in
`Tests/AppChecks.swift`, and ship a build. Logged meals keep their own copies, so users' history isn't affected.
