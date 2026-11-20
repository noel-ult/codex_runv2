# Codex Run — Hunters vs. Runner (Godot 4 Vertical Slice)

An open-world stealth-chase vertical slice built in **Godot 4** with strictly typed GDScript.
Every visual (city, vehicles, characters, effects, HUD) is built from primitives at runtime, so there are **zero external assets**.

## Running

1. Clone the repo and open `project.godot` in **Godot 4.7** (verified on 4.7.2; older 4.x releases are untested). The Forward+ renderer falls back to OpenGL automatically if Vulkan is unavailable.
2. Press **Play** (F5). The main scene is `res://scenes/main.tscn`.

> Opening the project in the editor once generates Godot's `.godot/` class cache, which the scripts' `class_name` types need.
> To run from the CLI without opening the editor, import first: `godot --headless --path . --import`.

## Controls

| Key | Action |
| --- | --- |
| W A S D / Arrows | Move (camera-relative) |
| Mouse | Orbit the camera |
| Space | Jump. Press it again in the air for a **Super Jump** (Micro-Fusion) |
| Q | Super Jump from the ground (Micro-Fusion) |
| Shift | **Micro Dash** (Micro-Fusion) |
| F | Toggle **Full Form** |
| E | **Fracture Codex** onto the vehicle under the crosshair |
| R | Restart the slice |
| Esc / Click | Release / capture the mouse |

## The Codex risk–reward loop

- **Base Form**: slow (4.5 m/s) and invisible to Hunters. They only ever learn where you are from Codex signals.
- **Micro-Fusions**: Micro Dash (+20) and Super Jump (+26) spike **Resonance** (0–100). Below 100, Resonance decays by 8/s.
- **Full Form**: 12.5 m/s and much higher jumps, but builds Resonance at 27/s (net +19/s after decay).
- **Codex Ignition**: reaching 100 pins Resonance for 2.5 s, then it may decay. Until it falls below 60, your **live 3D coordinates** are broadcast to the Hunter AI at 20 Hz, and a decaying **Residual Echo** (orange ring) drops every 2.5 s.
- **Codex Fracturing (decoy)**: aim at a moving vehicle and press **E**. An ability detaches onto it (Full Form if it's active, otherwise your last-used Micro-Fusion), and the vehicle becomes a pulsing **fake Codex beacon**. Resonance drops by 45, which usually ends an Ignition. That ability stays **LOCKED** until you physically touch the vehicle again (after a 2 s grace period).
- **Dead Zones** (purple volumes): the **East Tunnel** over the ring road and the **Warehouse** interior in the south-west block. Inside, broadcasts are masked, echo drops stop, and Resonance decays 3× faster.
- **Capture**: a Hunter in Apex Pursuit that reaches a fresh broadcast position catches you. You respawn with 0 Resonance. Fractured abilities stay on their vehicles.

## Hunter AI

Each Hunter runs an FSM, and the state is shown by the ring above its head:

| State | Colour | Trigger |
| --- | --- | --- |
| `PATROL` | Green | Default: wanders random street/alley waypoints |
| `INVESTIGATE_ECHO` | Amber | Best-scoring Residual Echo in range (fresh + close), or the last known position once the live signal is lost |
| `APEX_PURSUIT` | Red | Live Ignition coordinates are fresh (< 1 s old) |
| `CHASE_DECOY` | Violet | Each active decoy beacon pulls its 2 nearest Hunters. A Hunter within 12 m of a live signal ignores decoys |

## Architecture

```
Main (main.gd — composition root: the ONLY place systems are connected)
├── WorldEnvironment / DirectionalLight3D
├── NavigationRegion3D            (NavigationMesh baked at runtime from static colliders, layer 1)
│   └── City (greybox_city_builder.gd)  → buildings, alleys, rooftops, 2 DeadZones, 3 Path3D routes
│        └── Route_*/PathFollow3D/DecoyVehicle (decoy_vehicle.gd)
├── Echoes                        (container for ResidualEcho nodes)
├── Player (player.tscn: CharacterBody3D + SpringArm camera + InteractionRay)
│   └── CodexSignalSystem (codex_signal_system.gd)
├── HunterAIDirector (hunter_ai_director.gd) → spawns 4× hunter.tscn (hunter_agent.gd)
└── HUD (hud.gd, CanvasLayer built in code)
```

**Decoupling rules**

- `CodexSignalSystem` owns all Codex rules and talks outward **only through signals**: `resonance_changed`, `form_changed`, `codex_ignited`, `ignition_broadcast`, `echo_dropped`, `decoy_beacon_activated/deactivated`, `ability_lock_changed`, `dead_zone_changed`, and so on.
- `CodexSignalSystem` and `PlayerController` hold **no references to Hunter AI**. Data flows one way: Codex → signals → Director → Hunters.
- Capture flows back through signals too: `HunterAIDirector.runner_caught` → `PlayerController.on_caught` → `PlayerController.captured` → `HunterAIDirector.on_runner_respawned`. `main.gd` wires all of these.
- Decoys implement a small "fracture beacon" contract (`attach_fractured_ability`, `release_fractured_ability`, `is_beacon_active`, signal `runner_contact`), so the Codex system doesn't depend on any concrete world class.
- `DeadZone` areas only emit `runner_entered/exited`, and `main.gd` connects those to the Codex.

**Physics layers**: 1 world, 2 runner, 3 hunters, 4 vehicles, 5 triggers. The navmesh parses layer 1 only, so moving vehicles never cut holes in it. Its baking AABB is capped at 3 m height, so Hunters stay on the streets and rooftops are a refuge.

**Strict typing**: `project.godot` treats untyped declarations and Variant inference as **errors**, and unsafe access/casts as warnings. The project produces zero warnings.

## Testing each mechanic in-game

1. **Stealth / Base Form**: walk past a green-ring Hunter. It ignores you.
2. **Micro-Fusions**: tap Shift (dash) and Q or double Space (super jump). Watch the Resonance bar spike and then decay.
3. **Ignition**: hold Full Form (F) for about 5 s. The red `CODEX IGNITED` banner appears, Hunter rings turn red, orange echoes drop every 2.5 s, and the HUD census shows `APEX PURSUIT`.
4. **Echo trail**: after Ignition ends (Resonance < 60), Hunters turn amber and follow the freshest echoes or your last known position.
5. **Dead Zone**: while ignited, run into the East Tunnel (ring road, east side) or the Warehouse (south-west block, doors on the west and east walls). The `DEAD ZONE` badge appears, the banner switches to `BROADCAST MASKED`, echoes stop, and Resonance drains 3× faster.
6. **Fracture decoy**: aim the crosshair at a passing vehicle until the `[E] FRACTURE CODEX ONTO …` prompt shows, then press E. A coloured beam appears on the vehicle, Resonance drops by 45, the ability shows `FRACTURED -> <VEHICLE> (LOCKED)`, and violet-ring Hunters chase the vehicle.
7. **Re-absorb**: catch up to that vehicle and touch it. The ability unlocks and the beam disappears.
8. **Capture**: stay ignited near red Hunters. `CAUGHT BY HUNTERS` flashes, you respawn, and the capture counter goes up.

## Headless verification

```bash
godot --headless --path . --import                 # builds the class cache, reports parse errors
for f in $(find scripts -name '*.gd'); do godot --headless --path . --check-only --script "$f"; done
godot --headless --path . --quit-after 600         # runs main.tscn ~10 s, should print nothing
```
