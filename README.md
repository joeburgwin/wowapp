# ForeverXP – XP route advisor for World of Warcraft: Forever

ForeverXP is an addon for **World of Warcraft: Forever** (Blizzard's permanent
Classic+, patch 1.60.x, `## Interface: 16001`). It watches your level, zone,
gear, quest log, rested XP and what you have been doing for the last few
minutes, then shows a short ranked list of *what to do next for the most XP* in
gentle, translucent overlays.

It never touches combat: Forever restricts what addons may read in combat and
there is no combat log, so ForeverXP only uses XP, quest, map and item APIs.

## What it shows

| Overlay | What it does |
| --- | --- |
| **Advisor panel** | Top 1-5 suggestions with a one-line reason, plus a status line (level, XP/hour, time to level, rested %, gear rating, current activity). Click a suggestion to track its quest and set a map waypoint. |
| **Direction arrow** | A small arrow that rotates toward the quest the advisor thinks is most valuable (or the suggestion you clicked), with distance in yards. Right-click to go back to automatic mode. |
| **Route** | With route mode on, the quest list becomes a numbered walking order: quest pickups (from Questie), objectives and turn-ins in your zone, ordered into one efficient path from where you stand. The arrow steps through it. Left-click a step to point the arrow at it, right-click to skip it. |
| **Zone quest list** | With route mode off, a compact, colour-coded list of the quests in your current zone: completed first, then by XP, with objective progress. Click to track. |
| **Toast** | A faded-in line at the top of the screen whenever the top suggestion changes (optional). |

All three overlays are drag-to-move, scalable and semi-transparent. Lock them
with `/fxp lock`.

## Quest routing and Questie

The game only tells addons about quests already in your log, so on its own
ForeverXP can order your current objectives and turn-ins but cannot know which
quest givers you have not visited yet. Install **Questie** (the official
Forever build: both `Questie` and `QuestieDB` from the same release) and
ForeverXP reads its database to add nearby *available* quests to the route:

* Pickups are limited to quests you can accept now, at most a couple of levels
  above you (configurable), never gray, never repeatable, and only those whose
  giver stands on your current map.
* Turn-in locations for completed quests come from Questie when the client
  does not expose a waypoint.
* The route is planned as a path from your position: nearest-neighbour order
  with a 2-opt pass, with turn-ins nudged slightly earlier so you drop them off
  on the way. It is rebuilt whenever the quest log changes, so accepting a
  quest turns its pickup stop into an objective stop automatically.
* Reaching a quest giver or right-clicking a step suppresses that stop for a
  few minutes so the arrow doesn't bounce back.

`/fxp questie` reports whether Questie was detected and how many pickups are
on your map. Without Questie everything else still works.

## How it decides

Each tick the advisor builds a context and scores candidate actions:

* **Turn-ins first.** Completed quests are instant XP. Nearby turn-ins and a
  nearly full quest log push this higher.
* **Zone fit.** Every zone in the route database has a level range. Above the
  range it suggests the best next zone (with travel hint and quest hub); below it
  warns and points to a safer zone. In range it tells you to keep questing (and
  which quest to do next) or to fill your log at the hub.
* **Dungeons.** In a group of three or more it suggests the best-fit dungeon.
  Inside one, it reminds you that in Forever dungeon *quest* XP and rewards were
  increased while trash XP was reduced, so finish every dungeon quest.
* **Gear.** Equipped item level is compared with what a character of your level
  should wear (roughly level + 3). Weak or poor gear produces a suggestion with
  the concrete fix: outdated weapon, empty slots, which dungeon loot to chase,
  and whether to stay in the lower half of your zone range.
* **Activity and rested XP.** It classifies what you are doing (questing,
  grinding, dungeon, traveling, resting, idle) from XP events, quest progress
  and movement. Grinding with no rested XP gets flagged against the questing
  rate expected at your level; grinding *with* rested XP is steered onto quest
  mobs, because rested XP doubles kill XP but not quest XP.
* **Pickups.** With Questie, "pick up N quests on your route" appears with the
  nearest giver, boosted when your log is thin for the zone.
* **Housekeeping.** Gray quests (10% XP) are listed for turn-in or abandon.

The route database covers every original 1-60 zone and dungeon, plus the new
Forever content: Zephras Isle, Riverglades, Shen'dralas, Mount Hyjal, Blackmaw
Hold and Shaper's Terrace. Blizzard has not published level ranges for the new
zones, so those entries are marked as estimates (shown with `*`); you can fix a
range in-game with `/fxp zone <min> <max>` while standing in it. The addon also
learns each zone's real map ID the first time you enter it.

## Install

1. Download `ForeverXP-<version>.zip` from the CI artifacts (or run
   `./scripts/package.sh`), or copy the `ForeverXP` folder directly.
2. Unzip into your Forever AddOns folder, e.g.
   `World of Warcraft/_forever_/Interface/AddOns/ForeverXP/`
   (the folder must contain `ForeverXP.toc`).
3. Enable it on the character select AddOns screen and log in.

If the client marks it out of date, update `## Interface:` in `ForeverXP.toc`
to the number `/dump select(4, GetBuildInfo())` prints in-game.

## Commands

```
/fxp                 open the options panel
/fxp toggle          enable / disable
/fxp panel|arrow|quests   toggle an overlay
/fxp lock            lock / unlock overlay positions
/fxp scale 1.2       overlay scale (0.6-1.6)
/fxp alpha 0.8       overlay opacity (0.3-1)
/fxp reset           reset overlay positions
/fxp status          print everything the advisor currently sees
/fxp refresh         rescan quests, gear and zone now
/fxp zones [level]   list best-fit zones and dungeons for a level
/fxp zone 35 45      set the level range of the zone you are standing in
/fxp learn Riverglades   bind the current map to a route zone by name
/fxp route [on|off]  toggle route mode, or print the current route
/fxp skip            skip the current route stop
/fxp questie         check whether Questie pickups are available
```

## Caveats

* Forever's addon API is still settling between builds. Every game call goes
  through `Compat.lua`, which prefers the `C_*` namespaces, falls back to older
  globals, and returns nil instead of erroring. If something is unavailable on
  your build the related feature degrades (for example the arrow shows `?` when
  the client withholds your position inside instances).
* Quest XP comes from the client when it exposes it; otherwise it is estimated
  from the quest level (shown with `~`).
* Dungeon XP changes and new-zone level ranges are based on community reporting
  from the beta, not Blizzard documentation.

## Development

```
./scripts/test.sh      # syntax-checks every file and runs the headless suite
./scripts/package.sh   # builds dist/ForeverXP-<version>.zip
```

`tests/mock_wow.lua` is a tiny stand-in for the WoW UI environment that loads
the addon in TOC order and lets the tests drive the pure logic (zone matching,
gear scoring, activity classification, advisor ranking, arrow math, route
planning, the Questie bridge against a mocked Questie, slash commands). Lua 5.4 is used for the tests; the addon itself is written for the
client's Lua 5.1.

Layout:

```
ForeverXP/
  ForeverXP.toc     Interface 16001, load order
  Core.lua          namespace, saved variables, event + message bus, timers
  Compat.lua        API shim (all game calls go through here)
  Data/Zones.lua    zone route database (ranges, hubs, travel hints)
  Data/Dungeons.lua dungeon database
  Tracker.lua       XP samples, XP/hour, activity classification
  Gear.lua          equipped gear scoring
  Quests.lua        quest log scan, XP estimates, difficulty, waypoints
  Questie.lua       optional Questie bridge (available quests, turn-in spots)
  Route.lua         route planner (nearest-neighbour + 2-opt) and step tracking
  Advisor.lua       pure suggestion builder + live context
  UI/Panel.lua      advisor overlay + toast
  UI/Arrow.lua      direction arrow
  UI/QuestList.lua  zone quest list
  UI/Options.lua    Settings panel
  Commands.lua      /fxp
```

## License

MIT
