# Changelog

## 0.2.0
* Route mode: pickups, objectives and turn-ins in the current zone are ordered
  into one path (nearest-neighbour + 2-opt); the arrow steps through it and the
  quest list shows numbered stops. Right-click or `/fxp skip` to skip a stop.
* Optional Questie integration: nearby available quests become pickup stops,
  and completed quests get turn-in locations when the client gives none.
* New advisor suggestion for pickups on your route; route summary in the
  "keep questing" suggestion.
* Options: route mode, Questie pickups, pickups per route, pickup level slack.
* Commands: `/fxp route`, `/fxp skip`, `/fxp questie`.

## 0.1.0
* First release for World of Warcraft: Forever (Interface 16001).
* Advisor panel, direction arrow and zone quest list overlays.
* Route database for all classic 1-60 zones and dungeons plus Zephras Isle,
  Riverglades, Shen'dralas, Mount Hyjal, Blackmaw Hold and Shaper's Terrace.
* Gear scoring, activity classification, rested-XP aware suggestions.
* Headless test-suite and CI packaging.
