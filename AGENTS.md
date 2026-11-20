# Agent notes

- Godot 4 project (verified on 4.7.2). Godot is not installed system-wide; a portable binary can be fetched from the official `godotengine/godot` GitHub releases into `/tmp`.
- Strict typing is enforced: `debug/gdscript/warnings/untyped_declaration=2` (error) in `project.godot`. Type every variable, parameter, return and `for` loop variable.
- `class_name` types need the `.godot` class cache: run `godot --headless --path . --import` before any CLI run on a fresh clone.
- Verification:
  - `godot --headless --path . --import`
  - `godot --headless --path . --check-only --script <file.gd>` for each script
  - `godot --headless --fixed-fps 60 --path . --quit-after 600` (runs main.tscn and should print nothing)
  - For mechanics, run a temporary `extends SceneTree` script with `--script`. Instance `main.tscn` on the first `_physics_process` frame, not in `_initialize` (the root isn't in the tree yet there).
- Architecture rule: `CodexSignalSystem` and `PlayerController` must never reference Hunter AI. All cross-system wiring lives in `scripts/main.gd`.
- Repo lives on an exFAT drive (`core.fileMode=false`).
