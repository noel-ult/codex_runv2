# Codex Run — Hunters vs. Runner (Godot 4 Vertical Slice)

An open-world stealth heist set in a rain-soaked night city, built in **Godot 4** with strictly typed GDScript.
There are **no imported asset files**:
- **Surfaces:** every texture is a procedural shader (brick, concrete and glass facades with lit interiors and shop signs, wet asphalt, paving, painted steel, foliage, fabric with seams and glowing Codex veins).
- **Characters:** one continuous skinned mesh lofted from cross-sections, driven by a procedurally animated `Skeleton3D`.
- **Everything else:** UI, weather and minigames are all built in code.

## Running

1. Clone the repo and open `project.godot` in **Godot 4.7** (verified on 4.7.2). Forward+ falls back to OpenGL if Vulkan is unavailable.
2. Press **Play** (F5). The main scene is `res://scenes/main.tscn`.

> Opening the project in the editor once generates Godot's `.godot/` class cache, which the scripts' `class_name` types need.
> From the CLI: `godot --headless --path . --import`, then `godot --path .`.

## The mission

You carry the **Codex**. The only way to send it to safety is through the Hunters' own uplink:

1. **Tap HunterNet.** Sneak up behind an *unaware* (green-visor) Hunter and hold **E** on its suit port. While you work the **Signal Lock** hack, the Hunter freezes. Win it and you steal HunterNet credentials; fail and it wakes up on you.
2. **Infiltrate Meridian Signal Labs** (the walled compound in the NE block) and authenticate at the **HunterNet core** door with the credentials.
3. **Breach the Main Hunter Database** in three retro layers on the CRT terminal: **Signal Lock**, then **Firewall Breaker**, then **Cipher Recovery**. Mistakes raise the **TRACE** meter. At 100% the HunterNet locates you (alarm) and locks the terminal for 20 s.
4. **Lockdown.** A successful breach reveals the one live uplink relay and its cipher. It also triggers a HunterNet lockdown: every Hunter converges, the relay guard doubles, and the Codex Release speeds up to every 20 s.
5. **Transmit.** Hold **E** at the live relay and survive **30 s** within 16 m while the uplink broadcasts your position.

## Controls

| Key | Action |
| --- | --- |
| W A S D / Arrows | Move |
| Mouse | Camera |
| Space | Jump. Press again in the air for a **Leap** (Super Jump) |
| Q | Leap from the ground |
| Shift | **Dash** |
| F | Toggle **Full Form** |
| C / Ctrl | Toggle **crouch** |
| Z | Toggle **prone** (lie down and crawl) |
| E (hold) | Interact: suit ports, ID cloning, panels, doors, terminal, decoys, relay |
| Left mouse | Use the selected gadget |
| 1 / 2 / 3, mouse wheel | Select Jammer Dart / EMP Charge / Decoy Codex |
| Tab | Toggle the objective log |
| R | Restart |
| Esc | Release the mouse / disconnect from a terminal |

Terminal minigames:
- **Signal Lock:** A/D tune frequency and W/S tune phase. Match the drifting carrier and hold the lock.
- **Firewall Breaker:** A/D move the paddle and Space launches the probe. Destroy every CORE node; each dropped probe adds trace.
- **Cipher:** A/D select a slot, W/S change the glyph, Enter submits. ● = right glyph in the right slot, ○ = right glyph in the wrong slot.

## Day, night and weather

- **Clock:** the city runs a 24 h day. Nights last longer (about 8 real minutes) than days (about 5 minutes).
- **At dawn:** the sun rises, the sky brightens, street lamps switch off and fewer windows stay lit. At dusk it all reverses.
- **Daylight is dangerous.** Codex Releases reach 50% further and come 30% sooner. Lie low in the **hideout**, the shielded `STORAGE 07` lock-up on the west edge (marked on the compass), or rest until dusk.
- **Weather** cycles between clear, overcast, fog (favoured in the morning), drizzle and storm (favoured in the evening). It drives rain, fog, cloud, lightning and how wet the streets are.
- **Weather changes stealth:**
  - Fog and storms shrink camera, turret, searchlight and drone ranges.
  - Storms ground the Seeker Drones.

## The hideout and prep station

Inside the hideout the Codex is masked. Use the **workbench** (E) to spend **salvage parts**. You get parts from salvage pickups around the city, from downed Seeker Drones (+2) and from hunter suit hacks (+3).

| Fabricate | Cost |
| --- | --- |
| Jammer darts ×3 | 2 |
| EMP charge | 3 |
| Resonance Cell | 2 |

| Upgrade (one-time) | Cost |
| --- | --- |
| Dart rack (+3 darts) | 5 |
| EMP capacitor (+1 EMP) | 5 |
| Decoy amplifier (+20 decoy charge) | 6 |
| ID forger (+60 s disguise) | 4 |
| Signature dampener (−15% Release radius) | 6 |

During the day, the station or the **cot** lets you **rest until dusk** (19:00).

## The Codex

- **Base Form**: slow and invisible to Hunters. They only know where you are from signals.
- **Codex Release**: every **30 s** the Codex vents a pulse that pings every Hunter within a radius that grows with Resonance. The countdown is bottom-left. Dead Zones absorb it, an armed decoy can take it for you, and a disguise shrinks its radius.
- **Micro-Fusions** (Dash, Leap) and **Full Form** (fast, high jumps) build **Resonance**. Reaching 100 triggers **Ignition**: your live position is broadcast and Residual Echoes drop behind you.
- **Dead Zones** (violet haze): the East Tunnel, the SW Warehouse and the Faraday-shielded HunterNet core. They mask broadcasts and Releases, and Resonance decays 3× faster inside.

## Runner gadgets

| Gadget | Effect |
| --- | --- |
| **Jammer Dart** | Silent hitscan from the crosshair, with aim assist that locks onto any device or Hunter within ~7° of the crosshair (generous hitboxes). Takes one camera, searchlight, laser grid, sentry turret or drone offline for 20 s, or scrambles a Hunter's visor (it freezes and loses you). |
| **EMP Charge** | Thrown. Shuts down every device within 13 m for 15 s and stuns Hunters. Loud: +15 Resonance. |
| **Decoy Codex** | Costs 2 **Resonance Cells** (glowing pickups in alleys, on rooftops and in Dead Zones). Place it, then hold E to **imprint** it with 30 of your own Resonance. An armed decoy takes the next Codex Release in your place and echoes your Ignition broadcast as a fake beacon. Hunters that reach it shoot it apart. Max 2 active. |

Supply caches restock darts and EMPs, and all pickups respawn.

## Hunters and their weapons

Visor/halo colour shows state: **green** PATROL, **amber** INVESTIGATE, **red** APEX PURSUIT, **violet** CHASE DECOY.

- **Tether Harpoon**: fired by pursuing Hunters with line of sight. Latches on, slows you and reels you in.
- **Sonar Grenade**: lobbed at suspected positions. Its pings reveal you within 11 m.
- **Seeker Drone**: launched when they lose you. Flies a search spiral over rooftops with a spotlight and reports you on sight.
- **Capture**: physical contact with an alerted (amber/red) Hunter.

## Meridian Signal Labs security

| Defence | Counter |
| --- | --- |
| Vehicle gate / loading-bay shutter (staff access only) | Slip in behind a Hunter or technician, wear a technician disguise, or hack the bay override (+20 Resonance) |
| West service door | Hack the keypad (+30 Resonance) |
| Roof (10 m) + hatch | Full Form jump + Leap, then pry the hatch |
| CCTV cameras, searchlight tower | Stay out of the cones, jam them, or walk calmly in disguise |
| Laser tripwire grids (one sweeps) | Jam an emitter post or EMP |
| Sentry turrets (stun bolts slow you) | Jam, EMP, or stay out of the arc |
| HunterNet core door | Stolen HunterNet credentials |

## Stances and staying low

| Stance | Speed | Effect on security (cameras, turrets, searchlight, drones) |
| --- | --- | --- |
| Standing | normal | full sensor range |
| **Crouched** (C) | 2.4 m/s | sensor range halved, detection fills ~2× slower |
| **Prone** (Z) | 1.1 m/s crawl | invisible to sensors beyond ~3 m; fits under the lowest laser beam (0.6 m) |

- **Getting up:** jumping, Full Form or Micro-Fusions stand you back up, and dashing is impossible while prone.
- **Headroom:** you can't stand up under a low ceiling.
- **Hunters:** stances only fool electronics. An alerted Hunter that bumps into you still catches you.

## NPCs and disguises

Civilians walk the sidewalks, and **lab technicians** commute between the SE bus stop and the lab. Walk up behind (or beside) one: a floating cue turns green when you're in position. Hold E for 1.2 s to **clone their ID**. The NPC stops while you work, and you take on their exact outfit.
- **Technician IDs** open the staff gate and loading-bay shutter.
- **While disguised and walking**, cameras, the searchlight, turrets and drones ignore you, and the Codex Release radius shrinks.
- **The disguise breaks** if you run, use Micro-Fusions or Full Form, fire a gadget, Ignite, enter the restricted server room, get inspected by an alerted Hunter, or after 2 minutes.

## HUD

| Area | Contents |
| --- | --- |
| Top centre | Compass with objective bearings and distances |
| Top left | Current objective (Tab for the full log) |
| Top right | Threat state (UNDETECTED / SEARCHING / HUNTED), with a matching screen-edge vignette |
| Bottom left | Form, Resonance, Codex Release countdown, ability keys and status chips (ignited, dead zone, disguise timer, lockdown) |
| Bottom right | Selected gadget, ammo, cells and decoys |
| Centre | Interaction prompts with a hold bar |
| Bottom centre | Radio subtitles |

## Architecture

```
Main (main.gd — composition root: the ONLY place systems are wired together)
├── WorldEnvironment (sky, volumetric fog, SSAO, SSR, glow) / Moon (+ Sun) / Rain
├── TimeOfDay (24 h clock, sun/moon/sky/lamps) · WeatherSystem (rain, fog, cloud, wetness, lightning)
├── NavigationRegion3D (navmesh baked at runtime from world-layer colliders)
│   └── City (greybox_city_builder.gd)
│        ├── BuildingFactory / PropFactory / VehicleModel   (procedural structures)
│        ├── MeridianSignalLabs (facility_compound.gd: AutoGate, SlidingDoor, SecurityCamera,
│        │                       SearchlightTower, LaserTripwire, SentryTurret, server room)
│        ├── 4× UplinkStation, Hideout, DeadZones, TrafficVehicles, Pickups, NpcWalkers
├── Player (CharacterBody3D + HumanoidRig + CodexSignalSystem + GadgetBelt + camera rig)
├── HunterAIDirector → 4× hunter.tscn (HunterAgent + HumanoidRig + weapons) + SeekerDrones
├── MissionDirector (objective chain) · HackTerminal (CRT minigames) · PrepStationUI · HUD
```

**Decoupling rules**

- `CodexSignalSystem` and `PlayerController` never reference Hunter AI. The Codex speaks only through signals: `codex_released`, `ignition_broadcast`, `echo_dropped`, `decoy_beacon_*`, and so on.
- Gadgets and hunter weapons affect the world through duck-typed **group contracts**:
  - `electronics` + `disable_for()`;
  - `emp_receivers` + `apply_emp()`;
  - the runner's `apply_tether()` / `apply_slow()` / `apply_disguise()`;
  - `decoy_emitters` + `hunter_disable()`.
- World and mission systems feed positions to the Hunters through `HunterAIDirector.report_signal()`, wired in `main.gd`.

**Characters**: `HumanoidRig` lofts torso, neck, head, arms, hands, legs and feet into one `ArrayMesh`, with 4-bone weights blended across every joint. It skins that mesh to a 17-bone `Skeleton3D` and adds gear (hood, armour, visor, backpack, badge) via `BoneAttachment3D`. Gait, jump, dash, crouch and scan poses are computed every frame. Outfits: Runner, Hunter, Civilian (seeded variety) and Technician; `apply_style()` swaps them at runtime for disguises.

**Physics layers**: 1 world, 2 runner, 3 hunters, 4 vehicles, 5 triggers, 6 doors, 7 electronics (dart hitboxes), 8 NPCs.

**Strict typing**: untyped declarations and Variant inference are compile **errors**, and the project produces zero warnings.

## Headless verification

```bash
godot --headless --path . --import
for f in $(find scripts -name '*.gd'); do godot --headless --path . --check-only --script "$f"; done
godot --headless --path . --quit-after 600         # runs main.tscn ~10 s, should print nothing
```
