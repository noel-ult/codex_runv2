# Codex Run — Hunters vs. Runner (Godot 4 Vertical Slice)

An open-world stealth heist set in a rain-soaked night city, built in **Godot 4** with strictly typed GDScript.
There are **no imported asset files**:
- **Surfaces:** every texture is a procedural shader (brick, concrete and glass facades with lit interiors and shop signs, wet asphalt, paving, painted steel, foliage, fabric with seams and glowing Codex veins).
- **Characters:** skinned body and clothing surfaces lofted from cross-sections, driven by a procedurally animated `Skeleton3D`.
- **Everything else:** UI, weather and minigames are all built in code.

## Running

1. Clone the repo and open `project.godot` in **Godot 4.7** (verified on 4.7.2). Forward+ falls back to OpenGL if Vulkan is unavailable.
2. Press **Play** (F5). The main scene is `res://scenes/main.tscn`.

> Opening the project in the editor once generates Godot's `.godot/` class cache, which the scripts' `class_name` types need.
> From the CLI: `godot --headless --path . --import`, then `godot --path .`.

## The mission

You carry the **Codex**. The only way to send it to safety is through the Hunters' own uplink:

1. **Copy and decode HunterNet.** Sneak up behind an *unaware* (green-visor) Hunter and hold **E** on its suit port to copy an encrypted packet. You can keep moving after copying. Carry it to **Storage 07** on the west edge and hold **E** at the indoor **HunterNet decoder** to start Signal Lock in shelter. Win to recover lab credentials and automatically save a checkpoint. Escape leaves the packet available for another attempt.
2. **Infiltrate Meridian Signal Labs** (the walled compound in the NE block) and authenticate at the **HunterNet core** door with the credentials.
3. **Breach the Main Hunter Database** in three retro layers on the CRT terminal: **Signal Lock**, then **Firewall Override**, then **Cipher Recovery**. Mistakes raise the **TRACE** meter. At 100% the HunterNet locates you (alarm) and locks the terminal for 20 s.
4. **Lockdown.** A successful breach reveals the one live uplink relay and its cipher. It also triggers a HunterNet lockdown: every Hunter converges, the relay guard doubles, and the Codex Release speeds up to every 20 s. Before starting the uplink, you can use the violet relay marker to send a false handshake and divert up to two Hunters for 24 seconds.
5. **Transmit.** Hold **E** at the live relay and survive **30 s** within 16 m while the uplink broadcasts your position.

Before decoding, capture sends you back to the packet-copy step. After decoding, capture returns you to Storage 07 with your lab credentials and resets core access, the database breach and uplink progress. Your gear, upgrades and credits survive capture. Storage 07 protects you from Hunter contact inside its sheltered room.

Relaunching resumes from the saved credential checkpoint with starting gear, starting credits and the decode salvage reward. The credential decode is the only save point. Press **R** during gameplay or confirm **Restart Run** in the pause menu to clear the checkpoint and begin again.

## Controls

| Key | Action |
| --- | --- |
| W A S D / Arrows | Move on foot; drive/reverse and steer in a vehicle |
| Mouse | Camera |
| Space | Jump. Press again in the air for a **Leap** (Super Jump); brake while driving |
| Q | Leap from the ground |
| Shift | **Dash** |
| F | Toggle **Full Form** |
| C / Ctrl | Toggle **crouch** |
| Z | Toggle **prone** (lie down and crawl) |
| E (hold) | Interact: suit ports, ID cloning, panels, doors, terminal, decoys, relay, vehicle doors, day jobs and supply counter |
| E (tap) | Leave a vehicle once stopped |
| Left mouse | Use the selected gadget |
| 1 / 2 / 3, mouse wheel | Select Jammer Dart / EMP Charge / Decoy Codex |
| Tab | Toggle the objective log |
| R | Restart Run (clears the credential checkpoint) |
| Esc | Pause or resume play. Disconnect from a terminal or leave the workbench when one is open |

Open **Esc → Controls** to check the current bindings for gameplay, terminal minigames, and the workbench. **Esc → Operators** lets you inspect the Runner, Hunter, Civilian, and Technician in 3D. Drag the model to rotate it, or use the left and right arrows while the preview has focus.

The pause menu’s **Graphics** selector saves your choice across runs. **Detail** uses full resolution and the complete lighting effects. **Performance** renders the 3D view at 80% scale and turns off screen space reflections, ambient occlusion, and volumetric fog. HUD text stays at full resolution.

Terminal minigames:
- **Signal Lock:** A/D tune frequency and W/S tune phase. Match the drifting carrier and hold the lock.
- **Firewall Override:** Follow three prompts by pressing the displayed number key (1, 2, or 3). A wrong key adds trace.
- **Cipher:** A/D select a slot, W/S change the glyph, Enter submits. Each submitted tile shows its own clue. Green means the glyph is in the right slot, amber means it belongs in another slot, and dim means it is unmatched. The secret uses distinct glyphs. Each secret glyph can match only one tile per guess, with exact matches scored first.

## Day, night and weather

- **Clock:** the city runs a 24 h day. Nights last longer (about 8 real minutes) than days (about 5 minutes).
- **At dawn:** the sun rises, the sky brightens, street lamps switch off and fewer windows stay lit. At dusk it all reverses.
- **Daylight is dangerous.** Codex Releases reach 50% further and come 30% sooner. Lie low in the **hideout**, the shielded `STORAGE 07` lock-up on the west edge (marked on the compass), or rest until dusk.
- **Morning work:** from dawn until 18:00, visit the marked courier depot on the southwest sidewalk. Hold E to collect a parcel, take it to the marked drop point, then hold E again to earn credits. Routes rotate after each delivery. An unfinished job expires at dusk or on capture. Use the cot at Storage 07 overnight to wait until 06:00.
- **Vehicles:** three labeled parked cars can be driven day or night, including during the heist. Hold E at the driver door to enter. Use W/S to drive and reverse, A/D to steer, Space to brake, and E to exit after stopping. Gadgets and on-foot interactions are unavailable while driving.
- **Weather** starts clear, then cycles between clear, overcast, light fog (favoured in the morning), drizzle and storm (favoured in the evening). It drives rain, fog, cloud, lightning and how wet the streets are. Even foggy days keep the city readable.
- **Weather changes stealth:**
  - Fog and storms shrink camera, turret, searchlight and drone ranges.
  - Storms ground the Seeker Drones.

## The hideout and prep station

Inside the hideout the Codex is masked. Use the **workbench** (E) to spend **salvage parts**. You get parts from salvage pickups around the city, from downed Seeker Drones (+2) and from the first successful packet decode in each run (+3).

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

## Credits and the supply counter

The Runner starts with **40 credits**. Morning courier deliveries pay more; credits and bought supplies survive capture, while restarting the run resets the wallet. Credits are separate from salvage parts used at the hideout workbench.

Field dispatch sits near the starting street and offers two jobs around the clock. **Case Recovery** pays 75 credits when you retrieve the marked data case and return it to dispatch. **Signal Survey** pays 90 credits when you scan both receivers. The first scan starts a 55-second timer. Case locations rotate and the survey route reverses on repeat jobs.

The marked **SUPPLIES** counter sits on the sidewalk beside Meridian Labs. Hold E on foot to browse, W/S or the arrows to select, E or Enter to buy, and Escape to leave. A purchase only goes through when the full pack fits in your inventory.

| Supply | Price |
| --- | ---: |
| Jammer darts ×3 | 18 credits |
| EMP charge ×1 | 25 credits |
| Resonance cells ×2 | 16 credits |
| Salvage parts ×2 | 20 credits |

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
| Top centre | Heading tape with objective bearings and distances |
| Top left | Current objective (Tab for the full log) |
| Top right | Threat state (UNDETECTED / SEARCHING / HUNTED), with a matching screen-edge vignette |
| Bottom left | Form, Resonance, Codex Release countdown, ability keys and status chips (stance, ignition, dead zone, disguise timer, lockdown) |
| Bottom right | Selected gadget, ammo, cells and decoys |
| Centre | World markers, jammer target lock, and interaction prompts with a hold bar |
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
├── MissionDirector (objective chain) · HackTerminal (CRT minigames) · PrepStationUI · HUD · PauseMenu
```

**Decoupling rules**

- `CodexSignalSystem` and `PlayerController` never reference Hunter AI. The Codex speaks only through signals: `codex_released`, `ignition_broadcast`, `echo_dropped`, `decoy_beacon_*`, and so on.
- Gadgets and hunter weapons affect the world through duck-typed **group contracts**:
  - `electronics` + `disable_for()`;
  - `emp_receivers` + `apply_emp()`;
  - the runner's `apply_tether()` / `apply_slow()` / `apply_disguise()`;
  - `decoy_emitters` + `hunter_disable()`.
- World and mission systems feed positions to the Hunters through `HunterAIDirector.report_signal()`, wired in `main.gd`.

**Characters**: `HumanoidRig` builds the torso, head, limbs, and clothing as skinned surfaces in an `ArrayMesh`. A 17-bone `Skeleton3D` drives the walk, run, jump, dash, crouch, crawl, and scan poses. Faces, hands, shoe soles, and outfit shapes are modeled in code. The Runner, Hunter, Civilian, and Technician each have their own clothing and gear, and `apply_style()` recreates the same seeded outfits for disguises.

**Physics layers**: 1 world, 2 runner, 3 hunters, 4 vehicles, 5 triggers, 6 doors, 7 electronics (dart hitboxes), 8 NPCs.

**Strict typing**: untyped declarations and Variant inference are compile **errors**, and the project produces zero warnings.

## Headless verification

```bash
godot --headless --path . --import
for f in $(find scripts -name '*.gd'); do godot --headless --path . --check-only --script "$f"; done
godot --headless --path . --quit-after 600         # runs main.tscn ~10 s, should print nothing
```

For the system map, shared-folder coordination rules and developer handoff, see [the project guide](docs/PROJECT_GUIDE.md).
