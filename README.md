# EverlookDB Pets

Hunter pets for WoW Forever: your pet's abilities, the best rank its level allows, how
to get the next one, and a bestiary of every tameable beast: what it teaches, where it spawns, a wishlist and map pins. From the makers of [EverlookDB.com](https://everlookdb.com); the addon's page is
[everlookdb.com/everlook-pets.html](https://everlookdb.com/everlook-pets.html).

## What it does

**Your pet.** Name, family, level next to yours, loyalty, free training points, happiness and what it eats. When your
pet falls behind your level it says so ("Your pet is 5 levels below you"; from how many levels is a setting).

**Abilities.** Every ability your pet's family can learn, as a row with its icon, the rank your pet has and what to
do next. Things to do come first:

- **Train now: you know rank 7, your pet has 6.** Teach it with Beast Training.
- **Buy rank 4 from a pet trainer.** Growl, Cower, Great Stamina, Natural Armor and the resistances.
- **Fang knows rank 7: learn it from that pet.** Another of your pets (active or stabled) has it.
- **Tame a beast that knows rank 7.** With a "Where?" button: the best beasts for that rank, ones you can tame at
  your level first, confirmed before seen before classic data, in your zone and then your continent first, with
  their levels and zones and a link to the first one's EverlookDB page. The site's pet page when no beast is known.
- **Rank 3: new in WoW Forever.** Abilities Forever added (Dismember, Pinch, Swipe...) that nobody has reported a
  beast for yet point to EverlookDB; once players have, they become a tame like any other.
- **Trained: rank 6 · rank 7 at pet level 48**, or **Opens at pet level 30**.

Hover a row for the longer explanation and the links.

**Still to learn.** Above the full list, what your pet can still learn, most worth it first: what you can do right
now (train, learn from another pet, buy), then the biggest jump in rank, then the fewest training points. Each row
says what the rank costs in training points (and what it costs your pet, which gets back what its lower rank cost),
and the line on top says how many points are free and what the next rank costs. For a tame, the 3 nearest beasts you
can tame at your level are listed under it (your zone first, then your continent; confirmed first among equals);
click one for its page, or the row for every beast that teaches the rank.

**Bestiary.** Every tameable beast in one list, as cards: family icon, name, levels, rare or elite, zones, attack
speed, and a chip for each rank it teaches. A chip's text is gold when your pet would gain that rank and grey when it
has it; its edge is green when the rank is confirmed, white when seen in WoW Forever, grey for classic data. The
search box at the top finds "bite 6" (who teaches it), "dash" (any rank), "cat", "stranglethorn", "rare", "fast",
"elite", a level ("32") or part of a name; every word must match. Chips under it filter by family, zone (this zone,
this continent, or one zone), near your level, rare, fast attack, untamed by you and your wishlist.

**A beast's page.** Click a card: its 3D model (drag to turn it; models can be turned off), levels (too high for you
yet?), attack speed, what it eats, where it lives, whether you tamed one, and each rank it teaches with how sure that
is, what it means for your pet and its training-point cost. Where it spawns, with a Waypoint button per spot. **Set
waypoint** puts a waypoint on the nearest spot where WoW Forever players saw the beast (your map first, then your
continent; a lone sighting gives way to a spot seen more often); older classic spawn data only when players haven't
seen it there, and the line says so. It is TomTom's waypoint when TomTom is loaded,
else the game's own map pin and arrow. The beast's EverlookDB page is a click away.

**Wishlist and near alerts.** The star on a card puts a beast on your wishlist (per character). When a rare
tameable beast or a wishlisted one shows up on a nameplate (turn on enemy nameplates), as your target or under your
mouse, you get one chat line with a sound, at most once in 5 minutes per beast: "Broken Tooth (rare Cat, level 37) is
near. /tar Broken Tooth". Both alerts and the sound are settings.

**Tamed by you.** The addon remembers which beasts you tamed: Tame Beast on a beast followed by a new pet, and the
beast every pet you have came from. Cards, beast pages and tooltips say so, and the Bestiary can leave them out.

**World map.** "Tameable beasts" pins on a zone's map where beasts spawn that teach a rank your pet lacks (one its
level allows, not sold by trainers) and that you can tame at your level. The pin is the family icon with the same
green, white or grey edge; hover it for what it teaches, click it for its page. A switch at the bottom left of the
map (and a setting) turns them off.

**Alerts, once per change.** A chat line when a new rank opens as your pet levels, or when you learn a rank your pet
lacks. A pet seen for the first time, or a level that opens many ranks at once, gets one summary line instead. The
minimap button and the data-broker plugin (shown by EverlookDB Bar, Titan Panel, ChocolateBar...) carry a count of
what's new until you open the window.

**Level-up card.** When you level up, a card near the top of the screen says what's new at that level: the ranks your
pet's family can now learn that your pet lacks ("New: Claw rank 6 for Shadowclaw. Tame a Silt Crawler (level 40-41,
Swamp of Sorrows) to learn it", or "teach it now" when you know it already), the hunter trainer's new spells and
ranks, and the ranks to buy from a pet trainer. A Pin button puts a waypoint on the beast's nearest spawn spot or the
nearest trainer of your faction (TomTom's when TomTom is loaded). No sound, it waits for the end of a fight, it shows
nothing when nothing is new, and you can drag it anywhere; Escape or its X closes it. `/epets levelup` shows it again;
a setting turns it off or gives one chat line instead.

**Tameable beasts.** Hovering a wild beast shows "Tameable", its family and level, whether it's too high for you yet,
and what its family learns.

## Install

WowUp: pick **World of Warcraft: Forever**, then Get Addons → Install from URL, and paste `https://github.com/quikmn/EverlookPets`.

By hand: download the latest zip from Releases (`EverlookPets.zip`) and unzip it into
`World of Warcraft\_forever_\Interface\AddOns`.

Bugs and ideas: [Issues](https://github.com/quikmn/EverlookPets/issues), or `/epets feedback` in game.

## Using it

- `/epets` opens the window (also under Settings > AddOns). `/everlookpets` works too.
- `/epets check` lists what to do now in chat.
- `/epets levelup` shows the level-up card for your level (what's new for you and your pet).
- `/epets recent` opens the Recent page: everything the addon told you (level-up cards, beasts near you, your pet), newest first, with buttons to show the card or set the waypoint again. Right-click the minimap button or the bar plugin for the same.
- `/epets levelcard off`, `/epets levelchat on`: no level-up card, or one chat line instead of it.
- `/epets chat off`, `/epets lag 5`, `/epets minimap off`, `/epets tooltip off`, `/epets locked off`: settings from
  chat (`/epets get` lists them all).
- `/epets beasts <words>` opens the Bestiary with that search (`/epets beasts bite 6`); `/epets wishlist` lists your
  starred beasts in chat.
- `/epets rare off`, `/epets wish off`, `/epets sound off`, `/epets models off`, `/epets map off`: the new settings.
- `/epets search <words>`, `/epets status`, `/epets version`, `/epets reset` (asks first), `/epets feedback`, `/epets help`.

## Where the data comes from

The bestiary comes from EverlookDB: what hunters tamed in WoW Forever and where players saw each beast, with older
classic data where nobody has reported a beast yet. Every rank says how sure it is: **confirmed**, **seen** in WoW
Forever, or **classic data** (WoW Forever may differ). Spell, zone and family names are in your game's language;
beast names are English.

## Credits and license

GPL-3.0-or-later (see LICENSE). Data from classic-db (CMaNGOS, GPL-3.0), EG Link (Efficient Games, CC BY 4.0),
Forever Hunter Pets (MIT), BeastScout (GPL-3.0) and VMaNGOS (GPL-2.0-or-later); game data © Blizzard Entertainment.
Not affiliated with Blizzard Entertainment.
