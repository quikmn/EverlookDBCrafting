# EverlookDB Crafting

## Unreleased
- Skill-up planner: routes are more reliable. Orange recipes come first because they always give a point, then yellow ones. A green recipe is only used when nothing orange or yellow exists at that skill, and the step says so.
- Skill-up planner: the cheapest route now counts what a craft gets back for sure: its vendor price, or its auction price for potions, bolts, bars and other goods that sell every day. When two recipes cost about the same, the one whose product is worth more wins. The planner shows what the crafts get back.
- A recipe taught by a pattern is planned from the skill the pattern asks for, so no step sends you to a pattern you can't learn yet.
- Recipe data refreshed.

## v0.10.0 (2026-11-27)
- New: a "Skill-up plan" button under your profession window, beside Craft next. A click opens the skill-up planner for that profession, or your route's guide when you have one; right-click always opens the planner. Turn it off in /ecraft > Profession window.
- The first time you open a profession window, a one-time tip in chat says how /ecraft plan finds the cheapest way to level it.

## v0.9.3 (2026-11-26)
- Windows: whichever window you click comes to the front. Click the auction house (or bags, spellbook...) and it shows over this window; click this window to bring it back.

## v0.9.2 (2026-11-26)
- A recipe whose learn skill is only an estimate now reads like "learn at ~30 or 85" when the data gives two figures.
- Skill-up planner: shopping list rows without a Map, Buy or Make instead button use the whole row for their details, so fewer lines are cut off. Hover a row to read a cut-off line in full.
- Settings search: the sidebar lights the page of the top result while you search.

## v0.9.1 (2026-11-26)
- Crafting queue: the window opens wider, so each recipe's status, profit and stock line is no longer cut off. "makes 5" only shows when a craft makes more than one.

## v0.9.0 (2026-11-25)
- New: one crafting queue. The Crafting list is now the crafting queue, and EverlookDB Auctions' Crafting profit uses the same queue: queue a recipe there with a click and it shows up here, and the other way round.
- Queue from anywhere: "Add to queue" in the recipe browser, right-click a recipe in your profession window (queue 1, 5, 10 or all you can make), "Queue next steps" in the skill-up guide (this step and the next two, as many crafts as each still takes), or `/ecraft queue add <recipe> [count]`.
- Craft next: a button under your profession window says what comes next, like "Craft next: 5 Bolt of Silk Cloth". Each click crafts the first recipe in the queue that is ready (you know it and the materials are in your bags), skips the ones without materials, and ticks them off as they're made. It never crafts by itself, and waits while you're casting or in combat.
- Each recipe in the queue shows whether it's ready, needs materials, needs skill (and which of your characters knows it) or is on cooldown, and what one craft earns at the auction house.
- Keep in stock: type how many of an item to keep in a recipe's Keep box (or `/ecraft queue keep <recipe> <count>`). When you have fewer, counting your bags, bank, mail, alts and auctions, the queue refills itself.

## v0.8.0 (2026-11-24)
- With EverlookDB Auctions installed, your materials are counted in one place for both addons, and now include what waits in your mailbox and mail you sent to an alt that hasn't been picked up yet. Skill-up routes, the shopping list and the Crafting list take them off what to buy, and tooltips say "3 in the mail".
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
