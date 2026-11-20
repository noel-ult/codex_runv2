# Agent notes

- Godot 4 project (verified on 4.7.2). On this machine Godot lives on the T7 drive at `/run/media/noel/T7/Godot/` (self-contained mode), symlinked as `~/.local/bin/godot`.
- Strict typing is enforced: `debug/gdscript/warnings/untyped_declaration=2` (error) in `project.godot`. Type every variable, parameter, return and `for` loop variable.
- `class_name` types need the `.godot` class cache: run `godot --headless --path . --import` before any CLI run on a fresh clone.
- Verification:
  - `godot --headless --path . --import`
  - `godot --headless --path . --check-only --script <file.gd>` for each script
  - `godot --headless --fixed-fps 60 --path . --quit-after 600` (runs main.tscn and should print nothing)
  - For mechanics, run a temporary `extends SceneTree` script with `--script`. Instance `main.tscn` on the first `_physics_process` frame, not in `_initialize` (the root isn't in the tree yet there).
- Architecture rule: `CodexSignalSystem` and `PlayerController` must never reference Hunter AI. All cross-system wiring lives in `scripts/main.gd`.
- Repo lives on an exFAT drive (`core.fileMode=false`).
- No imported asset files: textures are shaders in `shaders/` (shared `common.gdshaderinc`), models are built in code via `GeometryKit`, `BuildingFactory`, `PropFactory`, `VehicleModel`, `HumanoidRig`. Per-object variation uses shader instance uniforms.
- Visual checks: render through a `SubViewport` (1280x720) with `world_3d = root.get_world_3d()` from a temporary `extends SceneTree` script run windowed (`godot --path . --script <file>`). The tiling WM resizes the root window, so don't rely on `--resolution`.
- GDScript gotcha: don't assign to a property of a call result (`f().rotation = x`); store the node in a variable first.
- Characters are skinned procedural meshes (`scripts/characters/humanoid_rig.gd`): `SurfaceTool.set_skin_weight_count()` must be called BEFORE `begin()`; vertices are in skeleton rest space; bones have identity rest bases so pose rotations are plain eulers.
- Avoid `Array.filter()` with typed lambda params on arrays that may hold freed nodes (errors "Cannot convert argument 1 from Object to Object"); iterate with a `Variant` loop and `is_instance_valid` instead.
- `ShaderMaterial.get_shader_parameter()` returns null until the parameter is set; track animated values in script vars.
- Mission e2e testing: drive minigames by setting their private state via `set()` (e.g. SignalLock `_freq/_phase`, Breaker `_brick_kind`, Cipher `_guess` + push an Enter key event) and call `Interactable.complete(player)` to skip holds.
