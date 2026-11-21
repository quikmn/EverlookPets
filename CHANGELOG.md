# Changelog

## v0.5.1 (2026-11-21)
- Waypoints in the bestiary now lead to where WoW Forever players actually see a beast; older classic spawn data is only used when we have nothing else, and says so.

## v0.5.0 (2026-11-21)
- The addon is now called EverlookDB Pets (was Everlook Pets), like the rest of the EverlookDB family. Settings, commands and the folder stay the same.
- **Level-up card.** When your hunter levels up, a card near the top of the screen says what's new: "Level 40! Here's what's new for you and Shadowclaw". First, the new ranks your pet's family can learn at that level and your pet doesn't have: "New: Claw rank 6 for Shadowclaw. Tame a Silt Crawler (level 40-41, Swamp of Sorrows) to learn it", with a Pin button that puts a waypoint on that beast's nearest spawn spot (TomTom's when it's loaded, else the game's map pin). If you already know the rank, it says to teach it to your pet instead; if another of your pets knows it, it names that pet. Then the hunter trainer's new spells and ranks, with icons, what they cost in all and the nearest trainer of your faction, and the ranks to buy from a pet trainer (Growl, Great Stamina, the resistances...). "Pin nearest trainer" puts a waypoint on the hunter trainer; "Open in EverlookDB Pets" opens your pet's page.
- The card is calm: no sound, never in the middle of a fight (it waits until the fight ends), and nothing at all at a level where nothing is new. Drag it anywhere and it stays there; close it with its X or Escape. It never closes another window.
- `/epets levelup` shows the card for your level again. Settings: "Show the level-up card when I level up" and "Level up: one chat line instead of the card".

## v0.4.2 (2026-11-21)
- Petopia links removed: the Petopia button on Your pet, the Petopia line in a row's tooltip and the Petopia box on Data and links. A tame nobody has reported a beast for now points to EverlookDB's pet page.
- Bestiary: beasts whose level nobody has reported yet ("level ?", WoW Forever's new ones) now come last instead of first. Among beasts of the same level, the ones known to teach something come first.
- Bestiary data refreshed from EverlookDB: more spawn spots seen in WoW Forever, a few more levels, and rare beasts marked rare (Barnabus). A beast no longer lists a whole continent ("Eastern Kingdoms") as one of its zones.
- Settings: "Use the raid warning sound instead" is on the Settings page now, so the settings search finds it too.
- Tooltips no longer say "level 0" for a tameable beast whose level isn't known.
- Right after logging in or calling your pet, a pet the game hasn't named yet is no longer saved (or announced in chat) as "Unknown". The name is picked up as soon as it arrives, and a rename shows at once.
- The stable: your other pets are no longer forgotten when the game hands over only half the stable list, and on a non-English client a stabled pet keeps its family.
- Set waypoint: when the game refuses the waypoint, the beast page says so instead of claiming it was set.
- Bestiary and pet page cards: the second line no longer runs under the star or the Where? button, and a two-line "nothing here" text gets room.
- Clearer wording: the empty "What it teaches" on a beast page, and the tooltip setting mentions what a beast teaches.

## v0.4.1 (2026-11-21)
- The addon has its own icon in the addon list, in the EverlookDB style (the database stack with a paw).

## v0.4.0 (2026-11-20)
- Settings window: switches, buttons and sliders use a softer shade of the accent colour, an on switch has a dark knob so it stands out, and boxes have cleaner rounded edges.
- The window has a touch of colour: hunter green for the selected page, switches and sliders.
- Bestiary: WoW Forever's own beasts now show where they spawn and their level when players have seen them (EG Link, our Collector); e.g. Low Plains Buzzard in Riverglades.

- World map: on a continent or the world map, a small note next to the "Tameable beasts" switch says to open a zone's map, since the pins show on zone maps.
- Renaming your pet keeps what Everlook Pets knew about it (what it was told about, what's new) instead of leaving an old entry behind under the old name. Old entries for pets you no longer have are cleared when you open the stable.
- On characters that aren't hunters, Everlook Pets now stays idle: it no longer watches nameplates, targets and mouse-overs, and it puts no "Hunters only" plugin on your bars. The Bestiary (`/epets beasts`) still works on every character.
- Lighter in combat: your pet's happiness, the pet bar and spell updates no longer make Everlook Pets re-check everything during a fight; it checks once when combat ends, and the world map's pins update then too.
- Rare and wishlist alerts: the chat line has clickable [Waypoint] (to its nearest known spawn spot) and [Beast page] links instead of a "/tar Name" to retype. To target the beast, bind a key under Key Bindings > AddOns > Everlook Pets ("Target the beast from the last rare / wishlist alert"); the line then says which key. The sound is a soft ping now; the raid warning sound is a setting ("Use the raid warning sound instead").
- Setting a waypoint no longer prints a chat line each time; the beast page says where it went, right under its buttons.
- The minimap button is off by default when Everlook Bar is loaded, since its Everlook Pets plugin on the bar shows the same count. Turn it back on in Settings (or `/epets minimap on`); if you had switched it off, it stays off.
- The minimap button no longer jumps around when a button drawer (Everlook Bar's, for one) has collected it.

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
- Where the bestiary comes from: hunters' tames in WoW Forever (EG Link by Efficient Games, Forever Hunter Pets, BeastScout) and the classic 1.12 client's data (VMaNGOS) where nobody has reported a beast yet. Credits in the Data and links page and the README.

## v0.1.0 (2026-11-18)

- First version. `/epets` opens a window with your pet: name, family, level next to yours, loyalty, free training points, happiness and what it eats.
- Every ability your pet's family can learn, with the rank your pet has and what to do next: train it now (you know a better rank), buy it from a pet trainer, learn it from another of your pets, tame a beast that knows it (with a link to Petopia's list for that rank), or the pet level where it opens. Things to do come first.
- A chat line when something becomes actionable: a new rank opens as your pet levels, or you learned a rank your pet lacks. Once per change, never a wall of text.
- Says when your pet falls behind your level ("Your pet is 5 levels below you"); you pick from how many levels, or never.
- A minimap button and a data-broker plugin (Everlook Bar, Titan Panel...) with your pet's level and a count of what's new.
- Wild beasts you can tame say so on their tooltip: family, level, whether it's too high for you yet, and what the family learns.
- Every setting also works from chat (`/epets lag 5`, `/epets chat off`); `/epets check` lists what to do in chat; `/epets feedback` gives a link for bugs and ideas; `/epets help` lists the commands.
