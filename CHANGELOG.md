# Changelog

## v0.6.0 (2026-11-21)
- New: `/epets recent` (or Recent in the window) lists everything the addon told you, with buttons to show the card or set the waypoint again.
- The level-up card shows new pet ranks only by default; trainer ranks and new spells can be switched on in the settings.
- The level-up card can cover your current pet's family, families you pick, or all families. It keeps to four rows, then "and N more".
- Tooltips get the EverlookDB look, with a new "Solid tooltip background" setting (on by default).

## v0.5.1 (2026-11-21)
- Bestiary waypoints now lead to where WoW Forever players actually see a beast; older classic spawn data is only used when there's nothing else, and says so.

## v0.5.0 (2026-11-21)
- The addon is now called EverlookDB Pets (was Everlook Pets). Settings, commands and the folder stay the same.
- New level-up card: when you level up, it shows the new ranks your pet can learn and where to tame them, the hunter trainer's new spells and the ranks to buy from a pet trainer, with Pin buttons for waypoints.
- The card never plays a sound, waits until a fight ends, and stays quiet when nothing is new. Drag it anywhere; close it with X or Escape.
- `/epets levelup` shows the card again. Settings turn it off or give one chat line instead.

## v0.4.2 (2026-11-21)
- A tame nobody has reported a beast for now points to EverlookDB's pet page.
- Bestiary: beasts with an unknown level come last; among equal levels, beasts known to teach something come first.
- Bestiary data refreshed: more spawn spots, more levels, rare beasts marked rare, and no more whole continents listed as a zone.
- Tooltips no longer say "level 0" for a beast whose level isn't known.
- Fixed: a pet showing up as "Unknown" right after login, stabled pets being forgotten, and stabled pets losing their family on non-English clients.
- Set waypoint says so when the game refuses the waypoint.
- Layout and wording fixes on cards, the beast page and settings.

## v0.4.1 (2026-11-21)
- The addon has its own icon in the addon list.

## v0.4.0 (2026-11-20)
- Softer, cleaner settings window with a touch of hunter green.
- Bestiary: WoW Forever's own beasts now show where they spawn and their level once players have seen them.
- World map: a note next to the "Tameable beasts" switch says pins show on zone maps.
- Renaming your pet keeps what the addon knew about it.
- On non-hunters the addon stays idle; the Bestiary (`/epets beasts`) still works.
- Lighter in combat: updates wait until the fight ends.
- Rare and wishlist alerts have clickable [Waypoint] and [Beast page] links, and a key binding targets the beast. The sound is a soft ping now (raid warning sound is a setting).
- Setting a waypoint no longer prints a chat line.
- The minimap button is off by default when EverlookDB Bar is loaded, since the bar shows the same count, and no longer jumps around in button drawers.

## v0.3.0 (2026-11-19)

- **Bestiary**, a new page in `/epets`: every tameable beast as a card with its family, levels, zones, attack speed and a chip for each rank it teaches (gold when your pet would gain it; the edge says confirmed, seen in WoW Forever or classic data). Search "bite 6", "cat", "stranglethorn" or "rare" in the box at the top, and filter by family, zone, near your level, rare, fast attack, untamed by you or your wishlist. `/epets beasts bite 6` opens it with that search.
- Click a beast for its page: its 3D model, levels, attack speed, what it eats, where it lives and spawns, each rank it teaches with what it costs in training points, and **Set waypoint** (TomTom's waypoint when TomTom is loaded, else the game's own map pin and arrow). A link to its EverlookDB page too.
- A star puts a beast on your wishlist (per character; `/epets wishlist` lists them). You get one chat line and a sound when a rare tameable beast or one from your wishlist is near: on a nameplate, as your target or under your mouse. Once in 5 minutes per beast; each part can be turned off in Settings.
- The addon remembers the beasts you tamed, so cards, beast pages and tooltips say "tamed by you", and the Bestiary can hide them.
- Your pet's page starts with **Still to learn**: what's most worth it first (what you can do right now, the biggest jump in rank, the fewest training points), what each rank costs in training points, how many you have free, and for a tame the 3 nearest beasts you can tame at your level. Click a beast for its page.
- The world map shows **Tameable beasts**: pins where beasts spawn that teach a rank your pet lacks and that you can tame at your level. Hover a pin for what it teaches, click it for its page. Switch them off on the map or in Settings.

## v0.2.0 (2026-11-18)

- Settings: an AI help button copies a description of every setting for an AI assistant, and `/epets apply` runs the commands it gives back.
- **Where?** now lists the beasts that teach the rank, from EverlookDB's bestiary: ones you can tame at your level first, confirmed before seen before classic data, in your zone and then your continent first, with their levels and zones and a link to the first one's EverlookDB page. It links the site's pet page only when no beast is known.
- Wild beasts' tooltips say what they teach when tamed: "Teaches: Bite 2 · Claw 3", marked confirmed, seen in WoW Forever or classic data.
- Abilities new in WoW Forever (Dismember, Pinch, Swipe...) become a normal "tame" to do once players have seen a beast teach them.
- The bestiary comes from hunters' tames in WoW Forever, with classic data where nobody has reported a beast yet. Credits are on the Data and links page.

## v0.1.0 (2026-11-18)

- First version. `/epets` opens a window with your pet: name, family, level next to yours, loyalty, free training points, happiness and what it eats.
- Every ability your pet's family can learn, with the rank your pet has and what to do next: train it now (you know a better rank), buy it from a pet trainer, learn it from another of your pets, tame a beast that knows it (with a link to Petopia's list for that rank), or the pet level where it opens. Things to do come first.
- A chat line when something becomes actionable: a new rank opens as your pet levels, or you learned a rank your pet lacks. Once per change, never a wall of text.
- Says when your pet falls behind your level ("Your pet is 5 levels below you"); you pick from how many levels, or never.
- A minimap button and a data-broker plugin (Everlook Bar, Titan Panel...) with your pet's level and a count of what's new.
- Wild beasts you can tame say so on their tooltip: family, level, whether it's too high for you yet, and what the family learns.
- Every setting also works from chat (`/epets lag 5`, `/epets chat off`); `/epets check` lists what to do in chat; `/epets feedback` gives a link for bugs and ideas; `/epets help` lists the commands.
