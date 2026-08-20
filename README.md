# Experiment17 Visuals — GitHub modular build

The whole project now lives in GitHub. Clients only need `Loader.lua`; it reads `manifest.json` and loads the enabled modules from `modules/`.

## Repository tree

```text
Experiment17_-Visuals-/
├── Loader.lua
├── manifest.json
├── README.md
├── sync_relay.py
└── modules/
    ├── Performance.lua
    ├── Visual.lua
    ├── Lighting.lua
    ├── ESP.lua                  # ESP router
    ├── World.lua
    ├── Player.lua
    ├── PlayerAnimations.lua
    ├── Trajectory.lua
    ├── Waypoints.lua
    ├── Sync.lua
    └── esp/
        ├── registry.json
        ├── Universal.lua
        └── games/
            └── GameESP_Template.lua
```

## One-line loader

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/GasterNoCopyAble/Experiment17_-Visuals-/main/Loader.lua"))()
```

## manifest.json

`manifest.json` is the top-level module list. The Loader reads it at startup, so new modules can be added without rebuilding the entire loader.

## Routed ESP

`modules/ESP.lua` is only a router. It reads `modules/esp/registry.json`, checks `game.PlaceId` first and then `game.GameId`, and redirects the Loader to the matching game-specific ESP. Unknown games fall back to `modules/esp/Universal.lua`.

Example entry:

```json
{
  "places": {
    "123456789": {
      "name": "My Game ESP",
      "url": "modules/esp/games/MyGame.lua"
    }
  }
}
```

Use `universes` instead of `places` when one ESP should cover every place in the same Roblox universe.

## Player animations

`modules/PlayerAnimations.lua` adds animation controls to the existing Player tab:

- custom Animation ID player
- speed, weight, loop, fade and priority
- freeze current pose
- current dominant AnimationTrack status
- idle/walk/run/jump/fall/climb/swim overrides
- original AnimationIds are restored on disable/unload

## Sync

`modules/Sync.lua` uses the E17SYNC1 WebSocket protocol. Connected clients can voluntarily share their locally rendered character pose and camera state. The receiver renders a local ghost and can interpolate the lower-rate network updates.

The reference relay is `sync_relay.py`:

```bash
pip install websockets
python sync_relay.py --host 0.0.0.0 --port 8765
```

For internet use, host the relay somewhere reachable by all clients and preferably expose it through `wss://`.

### VISUALS presence tag

`Sync -> Visuals Presence Tags -> Show VISUALS Tag` adds a local tag above the **real Roblox character** of a peer whose Experiment17 client is currently visible through the same Sync room.

Options include:

- Show VISUALS Tag
- Show Tag On Self
- custom Tag Text
- Tag Color
- Rainbow Tag
- RGB speed
- maximum render distance
- tag height

The default text is `E17 VISUALS`.

This is intentionally presence-based. Roblox does not normally let one LocalScript inspect another player's client or determine whether they executed Experiment17. A user is therefore marked only when their own Experiment17 instance voluntarily announces `visuals = true` through Sync.
