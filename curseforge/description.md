# EverlookDB Crafting

Level your professions the cheap and reliable way on WoW Forever. Type `/ecraft` (or `/eprof`).

- **Skill-up planner.** Say where you are and where you want to be (from your skill now, or any skill you set). You
  get the cheapest route at today's prices: each step's recipe and roughly how many crafts it takes ("~140, buy for
  155 to be safe"). A Map button shows the nearest trainer or vendor.
- **One shopping list.** Every material and pattern the route needs: how many you have on your characters, how many
  you need, what the rest costs and where to get it (auction house, the nearest vendor, or make it yourself). It
  ticks off as things land in your bags. Send it to an EverlookDB Auctions or Auctionator shopping list in one click,
  or buy the vendor part at an open merchant.
- **Every step gives its skill-ups.** Only recipes you know or can learn now for your faction are used: no dungeon,
  drop or quest recipes, and a reputation vendor's pattern only once you have the standing. Optionally add patterns
  that are for sale on the auction house right now.
- **Skill-up guide.** A small movable checklist: the current step with a live skill bar, the shopping list, what to
  have in your bags, and every step with rank training, tools and recipes to learn. Right-click a step to mark it done.
- **Skill-up cards.** "Hurray! Tailoring 151" at the top right whenever a profession rises: crafting, gathering,
  Fishing, Cooking, First Aid and the rest. A bar shows how far you are toward the rank's cap, and a hint says what's
  next: the rank to train when you hit the cap, or the next step of your route. Fireworks every 25 points. With
  EverlookDB Auctions the cards sit right under its loot cards. Move them with `/ecraft skillcards move`.
- **Crafting queue** (`/ecraft queue`). One list of everything you plan to craft, shared with EverlookDB Auctions'
  Crafting profit. Queue from the recipe browser, by right-clicking a recipe in your profession window, with "Queue
  next steps" in the skill-up guide, or with a click in Crafting profit. Each recipe shows its materials (have / need
  on all your characters, mail too), its profit and whether it's ready, needs materials, needs skill or is on cooldown.
  "Keep 20 in stock" refills the queue by itself when you have fewer, counting bags, bank, mail, alts and auctions.
- **Craft next.** One button under your profession window, like "Craft next: 5 Bolt of Silk Cloth". Each click crafts
  the next ready recipe of the queue, skips the ones without materials, and ticks them off as they're made.
- **Recipe browser** (`/ecraft recipes`). Every recipe of a profession, learned or not. Search by name or reagent
  ("silk cloth"), see where each reagent comes from, how to learn the recipe and which of your characters know it.
- **Merchant's Favor** (`/ecraft favor`). Every Waylaid Crate ranked by gold per Favor at today's prices, with a Map
  button to the turn-in NPC and a shopping list for EverlookDB Auctions.
- **Item tooltips.** How many of your recipes use a material, who of your characters can make an item or knows a
  recipe, and a Waylaid Crate's Favor. Each part can be turned off.
- **Guild crafters.** See which recipes your guild mates know, if they run the addon too. Can be turned off.
- **Buy what the route needs** from an open merchant in two clicks, never more than needed.
- **Your materials on every character** of your realm count as owned (bags and bank). You can turn this off, or
  plan as if you had nothing ("Buy everything for the route").
- **Prices** from EverlookDB Auctions, or Auctionator if you use that. A material with no price shows "?" and is
  never guessed.
- **Profession window colours.** Each recipe name in its skill-up colour, with your chance of a skill-up ("37%") and
  how many you can make ("(4)"). Replaces the CraftColors addon; your CraftColors settings carry over.

## Commands

| Command | What it does |
|---|---|
| `/ecraft` | the settings window; the search box finds any setting |
| `/ecraft plan [profession]` | the planner, e.g. `/ecraft plan tailoring` |
| `/ecraft guide` | open or close the guide |
| `/ecraft queue` | the crafting queue; also `queue add`, `queue keep`, `queue next`, `queue clear` (see `/ecraft help`) |
| `/ecraft recipes [words]` | the recipe browser |
| `/ecraft favor` | Merchant's Favor |
| `/ecraft colors [on \| off]` | the profession window colours |
| `/ecraft skillcards [on \| off \| move \| reset]` | the skill-up cards: switch them, move them, put them back |
| `/ecraft help` | all commands |

## Privacy

Your characters and what they carry stay on your PC. Nothing is uploaded.

## Credits

Data: WoW Forever client data, classic-db (CMaNGOS, GPL-3.0), Efficient Games' EG Link (CC BY 4.0, changed by
EverlookDB) and AllTheThings (MIT, changed by EverlookDB).

## License

GPL-3.0-or-later.
