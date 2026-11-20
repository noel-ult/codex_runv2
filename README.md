# Codex Run — Hunters vs. Runner (Godot 4 Vertical Slice)

An open-world stealth-chase heist set in a rain-slicked night city, built in **Godot 4** with strictly typed GDScript.
There are **no imported asset files**. Every surface texture comes from procedural shaders (brick, concrete, glass curtain walls with lit interiors, wet asphalt, paving, painted steel, foliage, worn road paint), and every model is assembled from primitives in code. The characters are jointed humanoid rigs animated procedurally.

## Running

1. Clone the repo and open `project.godot` in **Godot 4.7** (verified on 4.7.2; older 4.x releases are untested). Forward+ falls back to OpenGL automatically if Vulkan is unavailable.
2. Press **Play** (F5). The main scene is `res://scenes/main.tscn`.

> Opening the project in the editor once generates Godot's `.godot/` class cache, which the scripts' `class_name` types need.
> To run from the CLI without opening the editor, import first: `godot --headless --path . --import`, then `godot --path .`.

## The goal

You carry the **Codex**. To send it to safety you must:

1. **Find the live uplink relay.** Four identical dormant relay masts stand on the city's edge (N, E, S, W). Only the Hunters know which one is genuine, and every ~30 s one of them is ordered to **sweep** it (you'll hear a *RADIO INTERCEPT*). Shadow that Hunter and keep the relay in line of sight within 45 m while it scans. The relay blinks blue during the handshake, and after 2.5 s it is decoded and marked on your HUD. The genuine relay changes every run.
2. **Break into Meridian Signal Labs** (the walled compound in the north-east block) and steal the **Uplink Key** from its vault.
3. **Carry the Key to the live relay and transmit** (hold E). For 30 s the uplink broadcasts your position to every Hunter. Stay within 16 m of the mast until it completes.

If you're caught while carrying the Key, it goes back to the vault. Doors you've hacked stay open, and the relay stays known.

## Controls

| Key | Action |
| --- | --- |
| W A S D / Arrows | Move (camera-relative) |
| Mouse | Orbit the camera |
| Space | Jump. Press again in the air for a **Super Jump** (Micro-Fusion) |
| Q | Super Jump from the ground (Micro-Fusion) |
| Shift | **Micro Dash** (Micro-Fusion) |
| F | Toggle **Full Form** |
| E (hold) | Interact: hack panels, vault console, Uplink Key, roof hatch, relay |
| E (tap) | **Fracture the Codex** onto the vehicle under the crosshair (when nothing to interact with is nearby) |
| R | Restart |
| Esc / Click | Release / capture the mouse |

## Breaking into Meridian Signal Labs

| Route | How | Cost |
| --- | --- | --- |
| Vehicle gate (south) | Opens only for Hunters passing through. Slip in behind one | Timing. The yard has CCTV and a searchlight |
| Service door (west wall) | Hold E at the keypad for 3 s | +30 Resonance |
| Over the wall / roof | Full Form jump + mid-air Super Jump, then hold E at the roof hatch to drop straight into the vault | Very loud: Full Form + Micro-Fusion |
| Vault door (inside the hall) | Hold E at the vault console for 4 s | +25 Resonance |

**Security cameras** (sweeping cones) and the **searchlight tower** see you in any Form. A sustained sighting reports your position to the Hunters. Taking the Key trips a **4 s silent alarm**. While you carry the Key, Resonance decays 40% slower.

## The Codex risk–reward loop

- **Base Form**: slow (4.5 m/s) and invisible to Hunters. They only learn where you are from signals: Ignition, CCTV, the silent alarm, and the uplink.
- **Micro-Fusions**: Micro Dash (+20) and Super Jump (+26) spike **Resonance** (0–100). Below 100, Resonance decays by 8/s.
- **Full Form**: 12.5 m/s and high jumps, but builds Resonance at 27/s (net +19/s after decay).
- **Codex Ignition**: reaching 100 pins Resonance for 2.5 s. Until it drops below 60, your **live 3D coordinates** are broadcast at 20 Hz, and a decaying **Residual Echo** drops every 2.5 s.
- **Codex Fracturing (decoy)**: tap E while aiming at a moving vehicle. An ability detaches onto it and the vehicle becomes a **fake Codex beacon** that pulls Hunters away. Resonance drops by 45. The ability stays **LOCKED** until you physically touch that vehicle again.
- **Dead Zones** (violet haze): the **East Tunnel** on the ring road and the **SW Warehouse**. Inside, broadcasts are masked, echo drops stop, and Resonance decays 3× faster.
- **Capture**: physical contact with a Hunter that is **pursuing or searching** (red or amber visor) catches you. Patrolling Hunters (green) can't perceive you. You respawn with 0 Resonance.

## Hunter AI

Each Hunter runs an FSM. The state shows in its visor, chest lamp and halo:

| State | Colour | Trigger |
| --- | --- | --- |
| `PATROL` | Green | Wanders streets, alleys, the compound and the relays. Periodically **sweeps** the genuine relay (still `PATROL`, with the scanner arm raised) |
| `INVESTIGATE_ECHO` | Amber | Best Residual Echo in range, or the last known position once a live signal is lost |
| `APEX_PURSUIT` | Red | A live position report (Ignition, CCTV, alarm, uplink) is < 1 s old |
| `CHASE_DECOY` | Violet | Each active decoy pulls its 2 nearest Hunters, except Hunters already within 12 m of a live signal |

## Architecture

```
Main (main.gd — composition root: the ONLY place systems are connected)
├── WorldEnvironment (night sky, volumetric fog, SSAO, SSR, glow) / Moon
├── NavigationRegion3D            (navmesh baked at runtime from world-layer colliders)
│   └── City (greybox_city_builder.gd)
│        ├── BuildingFactory / PropFactory / VehicleModel (procedural structures)
│        ├── MeridianSignalLabs (facility_compound.gd: AutoGate, SlidingDoors, SecurityCameras,
│        │                       SearchlightTower, Interactables, vault + Uplink Key)
│        ├── 4× UplinkStation, 2× DeadZone, 3× Path3D/PathFollow3D/DecoyVehicle
├── Echoes                        (ResidualEcho container)
├── Player (player.tscn: CharacterBody3D + HumanoidRig + SpringArm camera + InteractionRay)
│   └── CodexSignalSystem
├── HunterAIDirector → 4× hunter.tscn (HunterAgent + HumanoidRig + flashlight + CatchArea)
├── MissionDirector (objective chain, sweep observation, transmission)
└── HUD (built in code)
```

**Decoupling rules**

- `CodexSignalSystem` and `PlayerController` hold **no references to Hunter AI**. Data flows Codex → signals → Director → Hunters.
- World systems never touch Hunters either. `FacilityCompound.intruder_spotted` and `MissionDirector.signal_reported` are wired by `main.gd` into `HunterAIDirector.report_signal()`.
- The Director tells the mission about sweeps only through signals (`site_sweep_dispatched`, `site_sweep_scanning`).
- Captures flow `HunterAgent.runner_touched` → `HunterAIDirector.runner_caught` → `PlayerController.on_caught` → `captured` → Director grace period and mission reset.

**Rendering**: one shared material per surface type. Per-building variety (colour, style, seed, lit-window ratio, storefronts) comes from shader **instance uniforms**. Window and sign glyph patterns are hashed, so the city is deterministic and costs only a handful of shaders.

**Physics layers**: 1 world, 2 runner, 3 hunters, 4 vehicles, 5 triggers, 6 doors. The navmesh parses layer 1 only. The vehicle gate sits on the door layer, so Hunters path through it and it opens for them.

**Strict typing**: `project.godot` treats untyped declarations and Variant inference as **errors**. The project produces zero warnings.

## Testing each piece in-game

1. **Stealth**: walk past a green-visor Hunter. It ignores you.
2. **Ignition / echoes**: hold Full Form (F) for about 5 s. The `CODEX IGNITED` banner appears, visors turn red, and orange echo rings drop.
3. **Dead Zone**: while ignited, enter the East Tunnel or the SW Warehouse. The banner switches to `BROADCAST MASKED`.
4. **Decoy**: aim at a passing car and tap E. A beam and ring appear on the car, and violet-visor Hunters chase it. Touch the car to re-absorb the ability.
5. **Find the relay**: wait for the *RADIO INTERCEPT*, follow the Hunter that peels off, and watch from cover until the decode bar fills.
6. **Heist**: use any route into Meridian Signal Labs, open the vault, and take the Key (watch the CCTV cones).
7. **Transmit**: hold E at the live relay and survive 30 s within 16 m. The `CODEX TRANSMITTED` screen appears.

## Headless verification

```bash
godot --headless --path . --import                 # builds the class cache, reports parse errors
for f in $(find scripts -name '*.gd'); do godot --headless --path . --check-only --script "$f"; done
godot --headless --path . --quit-after 600         # runs main.tscn ~10 s, should print nothing
```
