# Dead Hours – 3D zombie survival (Three.js)

Run: `python3 -m http.server 8000` in this folder, then open http://localhost:8000 (no build step; Three.js r160 is vendored in `lib/`).

- **Lobby**: four doors, each holds 1–5 survivors. Walk to a door, `E`, pick squad size (keys 1–5 / ↑↓), `Enter` to start.
  Other lobby players and squad-mates are AI-simulated (no network server in this build).
- **World**: houses with roofs, openable doors (`E`), cupboards with open animation and loot (only ~55% of houses have loot),
  a motorbike on your right at spawn (`E` to ride, W/S/A/D), synthesised sound effects.
- **Time**: day = 2 min, night = 3 min; day counter floats above the player's head. Zombies hear much farther at night
  (gunshots, bike, running attract them). Zombies bash closed doors.
- Game runs until every survivor dies, then returns to the lobby (loop).
- Controls: WASD, Shift run, C sneak, mouse look, LMB shoot/swing, 1 pistol, 2 bat, H heal, M mute.
