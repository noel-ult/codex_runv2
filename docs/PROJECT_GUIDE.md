# Codex Run project guide

Updated 21 November 2026. Read this with `AGENTS.md` and inspect the current checkout before editing. The project is a playable Godot 4.7.2 stealth heist vertical slice built from procedural assets and strictly typed GDScript.

## Shared folder coordination

Two terminal agents can work in the same checkout. File writes, uncommitted changes, the Godot import cache, and running game instances are shared immediately.

- Inspect `git status --short` and relevant diffs before starting. Existing uncommitted work belongs to the user or another agent until identified.
- Agree on file ownership before parallel edits. Route changes to shared composition files such as `scripts/main.gd`, `project.godot`, and `scenes/main.tscn` through one owner at a time.
- Make localized patches and reread files before editing. Preserve changes outside your assignment.
- Announce API changes to the other owner before updating callers. Record the final behavior and checks in the handoff.
- Stage explicit paths when committing. Avoid staging unrelated work, reverting another agent's edits, resetting the checkout, or cleaning untracked files.
- Identify the PID or session for a process you start. Coordinate desktop input and Godot cache imports so agents do not interrupt one another's tests.
- A handoff should include owned files, implemented APIs, behavior changes, commands and results, and any unfinished work. Verify the live checkout rather than relying on a handoff's intent.

## Running and verification

`project.godot` starts `scenes/main.tscn`. Godot is available as `godot`, linked to the installation on the T7 drive. Run the import once to register `class_name` types.

```sh
godot --headless --path . --import
for script in $(rg --files scripts -g '*.gd'); do
  godot --headless --path . --check-only --script "$script" || exit 1
done
godot --headless --fixed-fps 60 --path . --quit-after 1800
```

For mechanic checks, use a temporary `extends SceneTree` harness and instantiate the main scene on the first physics frame. Exercise real signals and interaction entry points. The terminal minigames can be driven by setting their private state for deterministic tests. When skipping a hold with `Interactable.complete(player)`, remember it bypasses range and requirement checks.

Render visual checks through a 1280×720 `SubViewport` sharing the main world's `World3D`. The tiling window manager changes the root window dimensions. Check compact layouts too. Scratch harnesses and captures may live in `/tmp`, and are not repository test dependencies.

## Current gameplay

The opening cinematic runs for 23 seconds in four shots. It follows the Runner into containment, shows the first contact with the Codex, and ends with the lab alarm. Space or Escape skips to gameplay.

1. Approach the rear suit port of an unaware, patrolling Hunter and hold E to copy an encrypted packet. Copying leaves movement available and starts no minigame.
2. Carry the packet to Storage 07 on the west edge. Follow the decoder marker and hold E at the HunterNet decoder inside the safehouse. Win Signal Lock to recover lab credentials and automatically save the credential checkpoint. Escape cancels decoding and retains the packet for another attempt.
3. Infiltrate Meridian Signal Labs in the northeast block and authenticate at the HunterNet core door. A technician disguise opens staff entrances, and the other infiltration routes remain available.
4. Breach the database through Signal Lock, Firewall Override, and Cipher Recovery. Firewall Override shows three number prompts to answer with keys 1–3. Wrong answers raise trace. Trace can abort the breach and temporarily lock the terminal. Success reveals the live relay and starts lockdown.
5. Activate the live relay and stay within 16 meters for 50 seconds of accumulated transmission time. Leaving the radius pauses progress.

Cipher Recovery gives a clue on each submitted tile. Green marks an exact match, amber marks a glyph that belongs in another slot, and dim marks an unmatched tile. The secret uses distinct glyphs, and repeated guesses of the same glyph can match it only once per row. Exact matches take priority.

After the database breach, an optional violet marker identifies a dormant relay. A false handshake there can divert up to two Hunters for 24 seconds. The opportunity closes when the real transmission starts and resets on capture.

Capture restores the latest saved objective and clears the active hack and any unfinished upload. Gear, credits, and prep upgrades stay with the Runner during capture. After decoding, the Runner respawns at Storage 07.

For a presentation, press Ctrl+Shift+F10 while on foot during gameplay. The shortcut moves the Runner to the live relay, runs a six-second upload with the standard beam and progress display, then shows the ending. The preview leaves the checkpoint intact.

Credential decode auto-saves. Ctrl+S saves the packet, core access, breach or completed transmission milestone. Relaunch restores objective state with starting inventory and credits, plus the decode salvage reward if earned. Restart Run clears the checkpoint.

Storage 07 protects the Runner from Hunter contact while inside its defined interior and masks Codex emissions. Entering shelter detaches an existing harpoon tether and rejects new tether effects. Other Dead Zones mask signals. The shelter bounds are checked directly in local space, including immediately after a teleport. Decoding requires reaching the actual indoor decoder. The world continues simulating while hacking, so a database hack outside the shelter can still be interrupted by capture.

Movement uses WASD or arrows, mouse look, Space jump/air leap, Q ground leap, Shift dash, F Full Form, C/Ctrl crouch and Z prone. Hold E interacts. Left click uses the selected gadget, 1/2/3 or the wheel selects it, Tab opens objectives, R restarts, and Escape opens Pause/Controls during gameplay or leaves the current terminal/workbench/shop. The pause guide reads the project's bindings, and Operators displays the same four procedural character kits used in gameplay.

Three parked vehicles are driveable at any hour: hold E at a driver door to enter, use W/S to drive or reverse, A/D to steer, Space to brake and E to exit once stopped. The Runner follows the vehicle for Codex and capture rules; on-foot actions are suppressed while driving. During dawn/daylight, a marked southwest courier depot offers parcel deliveries to rotating marked destinations. A completed route pays credits; dusk or capture cancels an unfinished parcel. The hideout cot can skip overnight to 06:00 to reach morning work quickly. Credits buy full packs of darts, EMPs, cells and salvage at the marked counter beside the lab. Capture preserves the wallet; a run restart resets it.

Field dispatch offers two replayable contracts at any hour. Recover a marked case and return it to dispatch, or scan two receivers before the 55-second window expires. The window starts at the first scan. Contract rewards use the same wallet as courier work. Capture clears the active contract.

## Composition and ownership

`scripts/main.gd` introduces the systems and connects their signals. `PlayerController` and `CodexSignalSystem` must never reference Hunter AI. Preserve that boundary.

| Path | Responsibility |
| --- | --- |
| `scenes/main.tscn` | World environment, city, player, Hunter director, mission, terminal and UI nodes |
| `scenes/player.tscn`, `scenes/hunter.tscn` | Character physics, camera/rig and Hunter navigation configuration |
| `scripts/player/player_controller.gd` | Movement, camera, stances, interaction holds, disguises, vehicle occupancy and respawn |
| `scripts/systems/codex_signal_system.gd` | Resonance, form, ignition, Releases, masking and decoy broadcasts |
| `scripts/systems/residual_echo.gd` | Visible fading position echoes |
| `scripts/mission/mission_director.gd` | Packet/decode state, mission checkpoints, lab access, breach, lockdown, transmission and capture reset |
| `scripts/mission/field_contracts.gd` | Field dispatch kiosks, case deliveries, timed receiver surveys and contract signals |
| `scripts/mission/uplink_station.gd` | Relay geometry, interaction, reveal/handshake/transmission visuals and reset |
| `scripts/interaction/interactable.gd` | World interaction range, requirements, holds and completion signals |
| `scripts/ai/hunter_ai_director.gd` | Hunter assignment, signals, patrol/sweeps, extraction eligibility, shelter predicate and alert reset |
| `scripts/ai/hunter_agent.gd`, `hunter_fx.gd` | Individual Hunter navigation, state, suit port, visuals and weapon orders |
| `scripts/ai/weapons/` | Seeker drone, sonar grenade and tether harpoon |
| `scripts/characters/humanoid_rig.gd` | Procedural skinned anatomy, four outfits, gear, animation and disguise kit rebuilding |
| `scripts/npc/npc_walker.gd` | Pedestrians, lab technicians, routes and ID copying |
| `scripts/gadgets/` | Gadget belt, jammer aim, EMPs, decoys, electronics contracts and pickups |
| `scripts/hacking/` | Terminal sessions and the three minigames, with shared retro drawing/input helpers |
| `scripts/ui/hud.gd` | Objectives, heading tape, projected markers, threat, resource display and transmission finale |
| `scripts/ui/intro_cutscene.gd` | Procedural containment set, four-shot camera sequence, caption timing and skip input |
| `scripts/ui/pause_menu.gd`, `operator_preview.gd` | Pause/controls, restart confirmation and isolated 3D character inspection |
| `scripts/ui/prep_station_ui.gd` | Salvage purchases, fabrication, upgrades and rest UI |
| `scripts/ui/supply_shop_ui.gd` | Credit shop catalog UI, keyboard/mouse selection and purchase feedback |
| `scripts/economy/runner_economy.gd`, `day_job_board.gd` | Credit wallet and atomic supply purchases; daytime courier routes and payouts |
| `scripts/facility/facility_compound.gd` | Lab geometry/security, entrance overrides, core door and database interactions |
| `scripts/facility/auto_gate.gd`, `sliding_door.gd` | Staff access gates and animated doors |
| `scripts/facility/` security scripts | Cameras, searchlights, lasers and turrets |
| `scripts/world/greybox_city_builder.gd` | City layout, navigation sources, spawn/patrol points, NPCs, relay and hideout placement |
| `scripts/world/geometry_kit.gd`, `material_library.gd` | Shared procedural mesh/collision primitives and materials |
| `scripts/world/static_mesh_batcher.gd` | Chunked rendering batches for compatible static city primitives |
| `scripts/world/building_factory.gd`, `prop_factory.gd`, `vehicle_model.gd` | Procedural buildings, props and vehicles |
| `scripts/world/traffic_vehicle.gd`, `driveable_vehicle.gd` | Moving road traffic and collision-aware cars controlled by the Runner |
| `scripts/world/supply_counter.gd` | Procedural sidewalk counter and on-foot shop interaction |
| `scripts/world/hideout.gd`, `dead_zone.gd` | Safehouse shell/interactions/decoder/shelter bounds and generic signal masking volumes |
| `scripts/world/time_of_day.gd` | Single writer of sun/moon/sky/ambient/fog/lamps and `night_factor` |
| `scripts/world/weather_system.gd`, `rain_weather.gd` | Weather cycling, wetness and camera-following rain |
| `scripts/world/world_conditions.gd` | Shared read-only gameplay visibility/daylight/weather conditions |
| `shaders/` | Procedural surfaces, suit fabric, CRT display and operator stage floor |
| `README.md` | Player-facing mission rules, controls and project overview |

GDScript resource UIDs live in neighboring `.uid` files. README captures live in `docs/screenshots/`. `.godot/` contains generated local editor/import cache. The drive uses exFAT and Git has `core.fileMode=false`.

## Important state transitions

- Main pauses the mission world during the intro. The cinematic runs in its own 3D viewport and emits `finished` on skip or natural completion. Main then restores player input and HUD visibility and starts the mission.
- `user://mission_checkpoint.cfg` stores the latest saved milestone and relay seed. Startup accepts the earlier credential-only save format. Restoring core access reopens the authenticated door. Restoring the database breach reveals the same relay and reapplies lockdown after navigation synchronizes. Restoring a completed upload shows the finale.
- The presentation shortcut uses the normal transmission progress and completion path with a six-second duration and suppresses capture for the preview. Checkpoint writes are disabled for that run.

- Hunter port extraction emits `suit_packet_copied()`. The mission sets `has_suit_packet`, disables further extraction, enables the decoder, changes objective text and exposes its waypoint.
- The hideout decoder is built disabled. `main.gd` supplies it to the mission with `bind_decoder()` and supplies `hideout.protects_runner.bind(player)` to the AI director and the player's generic `shelter_check` callable.
- The terminal's `opened_changed` signal controls player input and HUD visibility. Capture uses `reset_session()` to discard the old game and stage timer without an abort callback that belongs to the old mission state.
- Capture flows through the director to `PlayerController.on_caught()`, then through `captured` to director alert reset and mission progress reset. The mission emits `mission_reset` so HUD lockdown state clears, plus fresh objectives/markers/progress.
- Facility reset closes and re-arms one-shot doors and revokes the bay override. Relay reset clears reveal, handshake and beam while retaining which relay was selected for this run.
- Mission completion remains final within the active run. Capture resets heist state in place and retains gear and upgrades. An explicit restart clears the saved checkpoint before reloading the scene.
- `main.gd` owns wallet, shop, job and vehicle wiring. The job board emits payouts for the wallet to apply. The shop checks capacity and funds before publishing both changes. The main modal refresh handles terminal/workbench/shop locks so closing one UI does not enable movement while another remains open.
- Weather starts clear. `TimeOfDay` updates sky, ambient and fog at 10 Hz, with immediate updates for phase changes, time skips and lightning. It still publishes gameplay clock and visibility each frame. Asphalt uses the `night_factor` global to retain visible road texture after dark.
- Static render batching happens before navigation baking. It leaves collision bodies in place and skips animated props. Disable `GreyboxCityBuilder.batch_static_geometry` to compare identical camera views without batching.
- The pause menu saves the graphics preset in `user://graphics.cfg`. Performance reduces the 3D render scale and turns off three expensive lighting passes at runtime. HUD and physics operate at their normal resolution and rate.

## Procedural and GDScript constraints

Follow the concrete engine gotchas in `AGENTS.md`. Keep typed declarations and loop variables, identity rest bases, correct winding/caps and skin weights. Preserve seeded outfit matching and socket/accent APIs. No imported art assets are needed. `WorldConditions` is the gameplay view of weather, and only its owning environment systems write their shader globals.
