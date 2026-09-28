# Restaurant app links

Leanr calls `UIApplication.open` with `universalLinksOnly: true`. It opens the App Store only when iOS reports that the installed app cannot handle the link. No installed-app inventory or guessed URL schemes are used.

Additional associations checked against Apple's AASA CDN on 27 September 2026:

| App | Host and supported path | App identifier |
| --- | --- | --- |
| MyMacca's | `mcdonaldsau.smart.link/` (`/*`) | `F338RQS4M9.com.mcdonalds.gma.au` |
| KFC | `www.kfc.com.au/` (`*`) | `E3ZYR9A7BS.com.ncr.hsr.KFCXpress` |
| Oporto | `oporto.onelink.me/wCf9/` (`/wCf9/*`) | `KU284HK33Z.com.oporto.rewards` |
| Red Rooster | `redrooster-prd.onelink.me/nA6U/paid-appy` (`/nA6U/*`) | `75K827J4Q6.au.com.redrooster.royalty` |
| Domino's | `order.dominos.com.au/` (`/`) | `3E9U6978QT.au.com.dominos.Dominos`, `R3ATCV7K4H.com.dominos.arizona.AU` |

Association records: `https://app-site-association.cdn-apple.com/a/v1/<host>`.
Red Rooster also publishes the exact link on `https://www.redrooster.com.au/appy-deals/`.

Hungry Jack's, GYG and Nando's retain their existing configured links. Subway Australia and Spudbar currently show explicit App Store buttons because no verified app-launch link was found. The global Subway domain claims a different app identifier from Australia's `au.com.subcard.app`, so it is not used.

Manual acceptance check: with each Australian restaurant app installed, tap its Open button and confirm that app comes forward. Without it installed, confirm the AU App Store listing opens. Association-file validation alone cannot prove that every installed app version claims and handles a domain; device testing is still required.
