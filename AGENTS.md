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
