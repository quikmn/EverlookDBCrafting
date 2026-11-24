# EverlookDB Crafting

## v0.7.0 (2026-11-24)
- EverlookDB Auctions can now show recipes you don't know yet in its Crafting profit list (Easy to get, All recipes), with how to learn each one, using this addon's recipe data.

## v0.6.3 (2026-11-24)
- Recipe data refreshed: over 200 more patterns (Blacksmithing, First Aid and others) now show where they drop, as seen by players.

## v0.6.2 (2026-11-22)
- Skill-up cards: no more "+43" and fireworks after logging in; a jump the addon didn't see happen counts as one point.

## v0.6.1 (2026-11-22)
- Skill-up cards: the new skill in green, and +1 (or +N) on every card.

## v0.6.0 (2026-11-22)
- Skill-up cards: "Hurray! Tailoring 151" at the top right whenever any profession or secondary skill rises (crafting, gathering, Fishing, Cooking, First Aid, Lockpicking, Poisons). A thin bar shows how far you are toward the rank's cap; a hint says the rank to train when you hit the cap, or the next step of your route ("next: Bolt of Silk Cloth x12"). Several skill-ups at once add up on one card (+3).
- Fireworks every 25 points, at a rank's cap and at 300.
- With EverlookDB Auctions the cards sit right under its loot cards, so they never cover each other.
- `/ecraft skillcards on | off | move | reset | test`, and a new "Skill-up cards" settings page: fireworks, an optional soft sound (off), and weapon and defense skills too (off).

## v0.5.0 (2026-11-22)
- Skill-up planner: one shopping list for the whole route. Every material and pattern with have / need on your characters, what the rest costs and where to get it (auction house, the nearest vendor, or make it yourself). It ticks off as you buy.
- "Send to auction house" puts what's left on a shopping list in EverlookDB Auctions, or Auctionator if you use that. The Crafting list can send to Auctionator now too.
- Plan from any skill: "From skill" starts at your skill now, or wherever you set it.
- The safety margin is smarter: enough crafts to reach your target 9 times out of 10 for the whole route, so you buy less. Steps read "~140 crafts, buy for 155 to be safe".
- Buy it or make it: click a material you'd craft (a bolt, a bar) to buy it ready-made instead, with both prices shown.
- New setting "Buy everything for the route": what you already have isn't planned in.
- When the auction house sells a vendor good for less, the cheaper price is used. Merchants with only a few in stock are never counted on.
- Patterns from reputation vendors are used once you have the standing.
- The guide shows the recipes to learn (with a Map button to the trainer or vendor), tools to make or buy, rank books and quests, the level a rank needs, and a Buy button at an open merchant.
- The planner shows how old the auction prices are.

## v0.4.0 (2026-11-22)
- More Merchant's Favor recipes now show where to buy them and are used in the leveling routes.
- EverlookDB Auctions' Crafting profit page can now include the recipes your alts know.

## v0.3.0 (2026-11-22)
- The whole Merchant's Favor list now also shows inside EverlookDB Auctions' main window, on its Merchant's Favor page.
- EverlookDB Auctions' new Merchant's Favor page shows your three best Waylaid Crates and opens the full window.
- Tooltips have a tidier look shared by every EverlookDB addon: recipes in their skill colour, your characters in class colours.
- New setting "Solid tooltip background" (on by default, Tooltips page).

## v0.2.1 (2026-11-21)
- Works again after today's WoW Forever client update: your characters, alts' materials and saved trainer and merchant prices are found again.

## v0.2.0 (2026-11-21)
- The CraftColors addon is now part of EverlookDB Crafting: recipe names in their skill-up colour, your chance of a skill-up and how many you can make. Your CraftColors settings carry over.
- Merchant's Favor (`/ecraft favor`): every Waylaid Crate ranked by gold per Favor at today's prices, with filters, a Map button to the turn-in NPC and a shopping list for EverlookDB Auctions.
- Materials on characters of the other faction or another realm no longer count as yours (mail can't reach them).
- Crafting list: "Send missing to Auctions" no longer fails while item names are loading.
- Smaller fixes: the merchant buy bar, bank sorting, chat links, cut-off labels and page icons.

## v0.1.1 (2026-11-20)
- The addon has its own icon in the addon list.

## v0.1.0 (2026-11-20)
- New addon. `/ecraft` (also `/eprof`) opens the window with a search box that finds any setting.
- Skill-up planner: the cheapest route to your target at today's prices, only through recipes you can reliably learn.
- Skill-up guide: a small movable checklist with a live skill bar and what to buy and make next.
- Crafting list (`/ecraft list`): plan crafts across your characters and send missing materials to EverlookDB Auctions.
- Recipe browser (`/ecraft recipes`): every recipe, where its reagents come from and how to learn it.
- Item tooltips, guild crafters, a "Buy what the route needs" bar at merchants, and recipe tools added to the route.
- Prices from EverlookDB Auctions or Auctionator; trainer fees and merchant prices you see are remembered.
