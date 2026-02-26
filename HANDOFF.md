# HANDOFF: Xiaomi-Robotics-0 VLA Validation (VRM Sandbox, Local)

Last updated: 2026-02-26

Purpose: hand off the current **local** VLA validation sandbox so another model/agent can continue without re-discovering the project state.

Scope:
- This is an experiment under `Studying/` (gitignored). It is not product code yet, but is intended to feed product embodiment design.
- Model weights are expected under `local_models/` (gitignored).

Confidentiality / sync policy:
- This handoff is intended for local multi-agent continuity.
- Keep changes in local git history/branches unless explicitly approved for remote sync.

## Program Alignment (2026-02-26 Correction)

- This VLA track is active and should continue to be optimized.
- Local realtime voice work is also active and should continue in parallel (see `docs/HANDOFF.md`).
- Product intent for embodiment is proactive 3D livestream movement (Neuro-sama-like agency), not a heavily scripted condition-reaction tree.
- Keep hard rules for safety and fallback; keep motion intent as model-driven as practical.

## Audit Snapshot

Locations:
- Snapshot root (name contains `archived`, currently still the active workspace):
  - `Studying/embodiment__archived_2026-02-25/`
- Main sandbox (current active run path):
  - `Studying/embodiment__archived_2026-02-25/vrm_sandbox/` (~269KB excluding model weights)
- Standalone minimal experiment:
  - `Studying/embodiment__archived_2026-02-25/_local_experiments/xiaomi_robotics_0_minimal/`
- Xiaomi official reference repo clone:
  - `Studying/Xiaomi-Robotics-0/` (preferred)
  - `Studying/embodiment__archived_2026-02-25/Xiaomi-Robotics-0/` (older duplicate snapshot)
- Everywhere clone:
  - `Studying/Everywhere-main/`

Files (VRM Sandbox):
- `Studying/embodiment__archived_2026-02-25/vrm_sandbox/index.html`: UI shell + controls.
- `Studying/embodiment__archived_2026-02-25/vrm_sandbox/main.js`: 3D scene, collision, interaction, camera modes, VLA loop, debug/log panel.
- `Studying/embodiment__archived_2026-02-25/vrm_sandbox/server.py`: static server + `/api/vla/*` inference endpoint (loads Xiaomi model via transformers).
- `Studying/embodiment__archived_2026-02-25/vrm_sandbox/README.md`: run + troubleshooting.
- `Studying/embodiment__archived_2026-02-25/vrm_sandbox/README_LAYOUT.md`: current floor plan and key coordinates.

Git hygiene:
- `Studying/` and `local_models/` are ignored by `.gitignore`.

## How To Run

Start the local server (static + API):
```powershell
cd d:\-Users-\Documents\GitHub\CMYKE
python .\Studying\embodiment__archived_2026-02-25\vrm_sandbox\server.py
```

Open:
```
http://127.0.0.1:5173/Studying/embodiment__archived_2026-02-25/vrm_sandbox/index.html
```

Health check:
```
http://127.0.0.1:5173/api/vla/health
```

If you see `/api/vla/health 404` or `/api/vla/infer ERR_EMPTY_RESPONSE`, you are likely not running `server.py` (or you have multiple servers on port `5173`). See `Studying/embodiment__archived_2026-02-25/vrm_sandbox/README.md` for the PowerShell kill command.

Server env:
- `VRM_SANDBOX_HOST` default `127.0.0.1`
- `VRM_SANDBOX_PORT` default `5173`

## Model Path / Contract

Model weights location (expected):
- `local_models/modelscope/XiaomiRobotics/Xiaomi-Robotics-0-LIBERO`

API:
- `GET /api/vla/health`: reports torch/transformers versions and whether the model is loaded.
- `POST /api/vla/infer`: returns a 10-step plan decoded from `outputs.actions`.

`POST /api/vla/infer` request fields:
- `robot_type` (default `libero_all`)
- `seed` (default `42`)
- `language` (instruction, bilingual OK)
- `target` (string label; used only for logging right now)
- `base_image` (data URL PNG; selected vision mode)
- `wrist_image` (data URL PNG; ego camera)
- `state` (list[float], padded/truncated to 32)

`POST /api/vla/infer` response fields:
- `actions_7`: list of 10 steps, each `[dx, dy, dz, dRx, dRy, dRz, gripper]`
- `action_chunk_shape`, `action0`, `action0_7`

Note:
- `server.py` currently sets device to CPU explicitly. If you want `xpu/cuda`, update `VLA.__init__` to pick `torch.xpu` / `torch.cuda` (or reuse the logic in the minimal experiment below).

## VRM Sandbox Control Loop (Front-End)

Vision modes (UI):
- `User`: user-controlled orbit camera view.
- `Follow`: third-person follow camera (behind avatar, with orbit/zoom/height controls).
- `Ego`: head/face camera (with forward/up offsets to avoid self-occlusion).
- `Global`: top-down/global view.
- `Multi`: 2x2 composite of the above.

Inference payload:
- `base_image` uses the currently selected vision mode (including `Multi` composite).
- `wrist_image` always uses the `Ego` view.

Action mapping (JS, simplified for sandbox):
- LIBERO actions interpreted as `[dx, dy, dz, ..., dRz, gripper]`.
- Mapping in `Studying/embodiment__archived_2026-02-25/vrm_sandbox/main.js`:
  - `forward = deadzone(dx) * actionScale`
  - `right = deadzone(-dy) * actionScale`
  - `turn = deadzone(dRz) * turnScale`
  - `interact = (gripper < 0.0 || gripper > 0.6)` (heuristic)

Navigation gating:
- The sandbox uses a small phase machine (`approach` -> `align` -> `interact`) with hysteresis thresholds (e.g. `NAV_INTERACT_ENTER_DIST`, `NAV_INTERACT_EXIT_DIST`, bearing gates).
- Goal: prevent rapid toggling and stop “spam interact from far away”.

## Debugging / Logs

Browser:
- Log tags include: `VISION`, `TARGET`, `VLA`, `AI`, `INTERACT`, `CAM`, `STATE`.
- Debug panel supports “Copy log” and “Copy debug info” (clipboard).
- Abort-driven fetch cancellations are suppressed (do not treat as model failure).

Server:
- Prints `[vla] infer:start ...` and `[vla] infer:done ...` per request.
- Aborted client connections are handled (avoids WinError 10053 spam).

## Current Issues (Observed)

- “Too far” loops: repeated `INTERACT: too far` when VLA plan doesn’t reliably approach targets.
- Wall hugging / drifting: sometimes the plan pushes the avatar into walls or away from the door.
- Post-door behavior: door opens but the avatar may exit immediately (no “stay and finish” objective).
- Visual ambiguity: dark scenes and self-occlusion can degrade decision quality (especially ego view).

## Suggested Next Work (For The Next Model/Agent)

High leverage changes to try first:
1. Add a stronger navigation assist layer (room waypoints + obstacle avoidance) and treat VLA outputs as “local motion hints” instead of raw control.
2. Improve “close-to-target” behavior: face target, slow down, suppress lateral jitter, and only allow interact when distance+bearing gates are satisfied.
3. Tune `actionScale/turnScale/actionDeadzone/aiPlanInterval` and record metrics (success rate, interact-too-far count, unstuck triggers).
4. Expand/clarify state signals (target relative pose, LoS flag, door open state) and verify they meaningfully change actions.
5. Improve vision: increase brightness/contrast, adjust ego camera offsets, and optionally send two views (follow + ego) even when user selects `Multi` (keep payload semantics stable).
6. Reduce scripted reflexes: use finite-state/rule logic as safety constraints and recovery only, not as the primary behavior generator.
7. Add proactive-motion metrics: time-in-purposeful-motion, wall-contact count, manual override count, and end-goal completion rate.

## Standalone Minimal Experiment (Recommended for Model Sanity)

If you suspect model/runtime issues (not navigation), use:
- `Studying/embodiment__archived_2026-02-25/_local_experiments/xiaomi_robotics_0_minimal/`

It supports:
- ModelScope download helpers
- `infer_once.py` with `--device auto|cpu|xpu|cuda` and prints `actions` shape + decoded chunk

## References

- Model selection note: `docs/MODEL_SELECTION_VLA.md`
- Floor plan: `Studying/embodiment__archived_2026-02-25/vrm_sandbox/README_LAYOUT.md`
- Xiaomi official repo clone: `Studying/Xiaomi-Robotics-0/`
- Everywhere clone: `Studying/Everywhere-main/`
