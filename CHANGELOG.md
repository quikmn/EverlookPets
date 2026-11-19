# Changelog

## Unreleased

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
