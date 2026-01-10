# Handoff Notes (CMYKE)

Last updated: 2026-01-10

## Scope
- This repo is a Flutter app with a local model workspace under `local_models/`.
- The user wants a realtime "phone-like" speech-to-speech demo with barge-in.
- Dual-mode runtime: standard LLM workflows + realtime voice model.

## Stage Goals (Current)
- Finish dual-mode routing with Control/Planner agent for tool calls.
- Add Avatar Stage placeholder (Live2D/Live3D) + expression event wiring.
- Design MCP client + skill registry and implement initial stubs.
- Prepare deep search/research scaffolding (retrieval + document output).
- Refine multi-platform UI layout for desktop and mobile.

## Environment
- OS: Windows (PowerShell).
- Conda envs:
  - `FunAudioChat` (CPU).
  - `FunAudioChatXPU` (XPU-enabled PyTorch 2.9.1+xpu).
- GPU: Intel Arc 130T (XPU available).
- User preference: respond in Chinese.

## Nested Git Repos
- Nested `.git` directories and files under `local_models/Fun-Audio-Chat/**` were removed.
- `git status -sb` is clean at repo root.

## Key Local Changes (gitignored under `local_models/`)
These are not tracked by the top-level repo, but are important for the demo:

### Server (realtime, streaming)
File: `local_models/Fun-Audio-Chat/web_demo/server/server.py`
- Added device selection to support XPU and non-CUDA TTS.
- TTS can run in a thread when CUDA is not available.
- Added `/api/{worker}` route to match the front-end `?worker_addr=simplex`.
- Input audio saving uses `soundfile` (avoids `torchcodec`/FFmpeg DLL issues).
- Enforced `local_files_only=True` on model/processor loading to avoid HF network.

### Client (official web demo)
Files:
- `local_models/Fun-Audio-Chat/web_demo/client/vite.config.ts`
  - HTTPS is optional (falls back to http:5173 if no cert).
  - Default proxy target set to `http://127.0.0.1:11235`.
- `local_models/Fun-Audio-Chat/web_demo/client/.env.local`
  - `VITE_SIMPLEX_TARGET=http://127.0.0.1:11235`.
- `local_models/Fun-Audio-Chat/web_demo/client/src/pages/Queue/Queue.tsx`
  - AudioWorklet loading fixed: use `audio-processor.ts?url` and call `addModule` first.
- `local_models/Fun-Audio-Chat/web_demo/client/src/pages/Conversation/components/UserAudio/UserAudio.tsx`
  - Added microphone device dropdown + refresh.
- `local_models/Fun-Audio-Chat/web_demo/client/src/pages/Conversation/hooks/useUserAudio.ts`
  - Updated dependencies to avoid stale constraints.

### Other local tweaks
Files:
- `local_models/Fun-Audio-Chat/utils/cosyvoice_detokenizer.py` (ruamel.yaml loader compat).
- `local_models/Fun-Audio-Chat/utils/device_utils.py` (FA_DTYPE override).
- `local_models/Fun-Audio-Chat/examples/infer_s2s.py` (save wav via soundfile).
- `local_models/Fun-Audio-Chat/web_demo/minimal_gui.py` (custom minimal gradio UI).

## Known Runtime Notes
- TTS on CPU causes audible gaps; XPU helps but still limited by hardware.
- Any call to `torchaudio.save` on XPU env triggers `torchcodec` FFmpeg DLL errors. Use `soundfile`.
- Offline mode can break model loading if config/tokenizer files are missing from the local model dir.

## Current “Happy Path” Run
Backend (XPU):
```
cd local_models/Fun-Audio-Chat
$env:PYTHONPATH = (Get-Location)
$env:FA_DEVICE = "xpu:0"
$env:FA_TTS_DEVICE = "xpu:0"   # or "cpu" if needed
& C:/Users/BoHuYeShan/.conda/envs/FunAudioChatXPU/python.exe web_demo/server/server.py --host 127.0.0.1 --port 11235 --model-path pretrained_models/Fun-Audio-Chat-8B
```

Frontend:
```
cd local_models/Fun-Audio-Chat/web_demo/client
npm run dev
```
Open: `http://localhost:5173/?worker_addr=simplex`

## Deferred / Abandoned
- CPU INT8 dynamic quantization was tested but blocked by offline loading and missing config/tokenizer files in the int8 dir.
- A temporary scripts folder was created and then removed.
