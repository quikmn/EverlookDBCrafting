# EverlookDB Crafting

Level your professions the cheap and reliable way on WoW Forever. `/ecraft` (also `/eprof`).

- **Skill-Up planner.** Pick a profession and a target (default: the next rank's cap). Calculate gives the cheapest
  route at today's prices: each step is a recipe, its skill range, the crafts you can expect and the crafts for a 90%
  safety buffer. Cost tiles show the materials to buy, patterns, trainer fees and the total, plus what the crafts
  would sell for (shown, not counted). Rank trainings show where they fall, with a Map button to the nearest
  trainer for your side. The route is kept for your character, so the numbers don't jump after a /reload; it changes
  only when you change the target or a switch, or press Recalculate.
- **Every step reliably gives its skill-ups.** Only recipes you know, or can learn now for your faction (a trainer, a
  teacher outside a dungeon, a vendor pattern) are routed: the same rule as the professions guide on
  [everlookdb.com](https://everlookdb.com/professions.html). Dungeon, drop, quest, reputation and unknown recipes are
  never in the route. "Patterns from the auction house" adds drop recipes whose pattern is for sale right now.
- **Skill-Up guide.** A small movable checklist: the current step with a live skill bar and the chance of a skill-up
  now, what to buy at the auction house, what to buy from vendors (Map: the nearest vendor), what to make first, the
  materials still needed, and every step. Right-click a step to mark it done. "Show recipe" selects the step's recipe
  in your profession window; you craft with the game's own button.
- **Crafting list** (`/ecraft list`). Plan what to craft, account wide: each recipe with - and + for its count, and
  under it a material tree with what you have in bags, bank and on your other characters. Materials one of your
  characters can make break down into their own materials (Craft or Buy on each). Each craft takes one off. "Send
  missing to Auctions" puts the rest on a shopping list in EverlookDB Auctions; vendor goods have a Map button.
- **Recipe browser** (`/ecraft recipes [words]`). Every recipe of a profession, learned or not. Search by name or by a
  reagent ("silk cloth"); filters Known, Not known and Favourites. Each recipe shows its skill colours, your chance
  now, where every reagent comes from, how to learn it (trainer, vendor, drops, quests) and who of you knows it.
- **Merchant's Favor** (`/ecraft favor`). Every Waylaid Crate ranked by gold per Favor at today's prices: the crate on
  the auction house plus its cheapest bundle (bought, or crafted with a recipe one of your characters knows). Sort by
  gold per Favor or the cheapest total; filter by tier, your level, faction and "My bags free". Each crate has a Map
  button to the turn-in NPC and a Shopping list button for EverlookDB Auctions (minus what you have).
- **Item tooltips.** On a material: how many of your recipes use it and how many more your route needs. On something
  crafted: who of you can make it. On a recipe: which of your characters know it or can learn it. On a Waylaid Crate:
  its Favor and gold per Favor. Each part can be turned off.
- **Guild crafters.** Guild members who run this addon see which recipes each other's current character knows ("Guild
  can make this" in tooltips). Guild channel only, throttled, names kept in memory only. Off in /ecraft > Guild.
- **"Buy what the route needs"** under an open merchant that sells vendor materials your route still needs. The first
  click shows the price, the second buys, never more than needed.
- **Your materials on every character of your realm.** Bags (and the reagent bag) and, from your last visit, the bank
  and reagent bank of each character on your realm (or a connected one) count as owned; mail can't cross realms, so
  characters elsewhere don't. "Don't count my alts' materials" leaves the others out.
- **Prices** from EverlookDB Auctions' scans when it is installed, else Auctionator's. Vendor goods cost what a
  merchant last showed you, else what WoW Forever's vendors charge. A material with no price shows "?" and is never
  guessed in a total.
- **Profession window colours** (formerly the CraftColors addon). Each recipe name in its skill-up colour (your own
  shades if you like), and after it the chance that one craft raises your skill ("37%", yellow and green recipes) and
  how many your bags make ("(4)", or "(4 +5)" with your bank and other characters). Works in the older-style trade
  skill and craft windows too. Your CraftColors settings are carried over; with CraftColors still enabled only one of
  the two draws, and you can disable CraftColors.
- **Profession scanner.** Opening a profession window saves your skill and recipes. Someone else's (a linked or guild
  profession) is never saved as yours. Where the window shows other reagents than the game files (the server changed
  a recipe), the window's version is used everywhere.

## Commands

| Command | What it does |
|---|---|
| `/ecraft` | the settings window (planner, characters, prices, every setting); search finds any setting |
| `/ecraft plan [profession]` | the planner, e.g. `/ecraft plan tailoring` |
| `/ecraft guide` | open or close the guide |
| `/ecraft list [add <recipe> [count] \| clear]` | the Crafting list |
| `/ecraft recipes [words]` | the recipe browser, searching for a recipe or reagent |
| `/ecraft favor` | Merchant's Favor: Waylaid Crates ranked by gold per Favor |
| `/ecraft colors [on \| off]` | the profession window colours: their page, or switch them on or off |
| `/ecraft status` | what the addon knows: characters, professions, routes, price source |
| `/ecraft <setting> <value>` | change a setting, e.g. `/ecraft noalts on` |
| `/ecraft help` | all commands |

## Privacy

Character names and what they carry are kept only on your PC, in this addon's own saved variables
(`EverlookCraftDB`). Nothing is uploaded: the EverlookDB uploader does not read this addon's file.

## For other addons

`EverlookCraftAPI` (read-only): `recipe(spell)`, `chance(spell, skill)`, `stock(item)`, `knownBy(spell)`,
`guildKnows(spell)`, `professionColors()`, `favorBest(n)` (the best Waylaid Crates for Merchant's Favor), `openFavor()`. See `API.lua`.

## Data and credits

`Data.lua` is written by everlookdb.com's `tools/craft_addon_data.py`:

- recipes, skill colours and materials: the WoW Forever client data;
- trainers, vendors, rank fees and spawns: classic-db (CMaNGOS, GPL-3.0, https://github.com/cmangos/classic-db);
- what WoW Forever's vendors charge, server learn ranks and where its NPCs stand: Efficient Games' EG Link
  (https://github.com/JIVESCORP/eg-link-output-wowf), licensed under CC BY 4.0
  (https://creativecommons.org/licenses/by/4.0/); changed by EverlookDB (selected fields, merged with classic-db and
  the client data);
- recipe drops, Merchant's Favor vendors and per-crate Favor: AllTheThings (MIT), changed by EverlookDB;
- which recipes are reliably learnable: everlookdb.com's own rule (`web/learntier.js`).

The skill-up chance is the classic formula: orange always, yellow and green (gray - skill) / (gray - yellow), gray never.

## License

GPL-3.0-or-later (see LICENSE), because the data includes classic-db facts.

## Tests

`python -P tests/run.py` (lupa; the parity test needs node and the Quarry repo at D:\Dev\Quarry).
