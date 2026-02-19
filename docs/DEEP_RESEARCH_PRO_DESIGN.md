# Deep Research Pro (Design Draft)

Goal: make CMYKE's deep research outputs "report-ready" (accurate, verifiable, and visually polished), similar to the professional deliverables seen in Claude Cowork / Claude Research and modern deep-research products.

This doc is a design draft to align:
- product UX (workspace, artifacts, exports),
- runtime (agents/skills/tools/MCP),
- and packaging (Rust sidecar + polyglot tool servers).

## Implementation Snapshot (2026-02-19)

This document mixes target design and current implementation. Current state:

- Desktop Flutter has a working Deep Research screen with:
  - questionnaire rounds (with timeout auto-fill),
  - questionnaire as the single source of truth for deliverable/depth constraints (no duplicated bottom presets),
  - deep-research specific prompt policy (separate from normal chat persona policy),
  - real execution via `UniversalAgent.runResearch(...)` (not fake progress),
  - tool-gateway delegated **multi-query** web search (fanout) with trace IDs; Deep Research supports multi-round search refinement (best-effort, model-assisted planning),
  - per-run workspace outputs: exports are written under `workspace/<session_id>/outputs/deep_research/runs/<run_id>/` with a `manifest.json` (no overwrite; old artifacts are kept),
  - artifact export pipeline and local file open action.
- Current export path can generate HTML and attempts DOCX/PDF/PPTX/XLSX via existing exporter behavior; converter/runtime availability still affects final format fidelity.
- Mobile/Gateway/OpenCode-delegated Deep Research remains a target architecture and is not fully wired end-to-end yet.
- Citation hard-enforcement policy in this doc is still a target; current run path does not block export on uncited claims yet.

## Non-Goals (for now)

- No "auto-run everything" without user control. Deep research must be opt-in and user-steerable.
- No mandatory sandbox dependency on a single platform technology (e.g. WSL2-only). Sandbox backends are pluggable.
- No unvetted community skills marketplace until we have a hard security model (allowlists, permission prompts, signing).

## Inspiration (Observed Patterns)

1) "Research mode" is agentic: multi-step search, iterative refinement, citations.
2) "Workspace" is separate from chat: document viewer/editor, table of contents, sources panel.
3) "Professional deliverables" are real files: docx/pptx/xlsx/pdf with charts, formulas, consistent layout.
4) "Long-running tasks" run out-of-band: can keep working while user is away; show progress and let user steer.
5) Execution is isolated: tools and code run in a VM/container/sandbox; file access is scoped.

## CMYKE Product Requirements

### A. Outputs (professional + beautiful)
- Report (PDF/Word): headings, ToC, tables, callouts, footnotes/citations, consistent typography.
- Slides (PPTX): narrative structure, charts, summary slide, appendix, speaker notes optional.
- Spreadsheet (XLSX): working formulas, assumptions tab, scenario table, charts where relevant.
- Optional: "audio summary" as a separate artifact.

### A4. Expert Mode (multi-model debate, future)

To improve rigor (at the cost of tokens), Deep Research should support an optional "Expert Mode":

- Use 2+ different models/providers (e.g. different vendors, different strengths).
- Have them discuss the same evidence, challenge each other's weak claims, and converge on a final report.
- Ensure all experts share the same tool pipeline: web search, crawl, analyze, summarize, and (optionally) code execution, with unified traceability (`trace_id`, sources, manifests).


### A2. Client Support

- **Mobile Lite:** can start/view Deep Research jobs, but heavy tools run in the gateway.
- **Desktop Full:** full Deep Research creation, editing, and export.

### A3. Remote Execution

- Mobile Lite can connect to a remote gateway (desktop host).
- Deep Research runs remotely; mobile receives streaming progress + artifacts.
- Pairing supports both LAN and WAN modes (see `docs/CHANNEL_GATEWAY_DESIGN.md`).

### A1. Default Deliverable Rules (user-specified)

- Default output: **DOCX + PDF**.
- If the user mentions "汇报/演示/路演/汇报给领导" -> add **PPTX** automatically.
- If the request implies structured numeric output (e.g. "预算/测算/对比/模型/ROI/成本/表格") -> add **XLSX**.
- Defaults should be confirmed via questionnaire only; avoid duplicate preset controls in the bottom input bar.

### A0. User Controls (questionnaire-first)

In Deep Research workspace, the user should explicitly pick deliverables and constraints through questionnaire rounds:

- Deliverables: `DOCX` `PPTX` `XLSX` `PDF` (mapped from questionnaire answers)
- Visual style pack (theme): e.g. "Minimal", "Corp", "Academic", "Pitch", "China-Report"
- Evidence policy:
  - citations required: `[x]` (forced by default)
  - allow uncited claims: `[ ]` (off by default; hidden unless "advanced" mode)
- Interaction policy:
  - ask clarifying questions when ambiguous: `[ ]` (default on)
  - auto-fill unanswered questions after timeout: `[ ]` (default on, 90s)
- Execution policy:
  - allow sandbox code execution: `[ ]` (default on, but requires runtime available)
  - allow browser automation: `[ ]` (default off, needs extra consent)

### B. Correctness (research-grade)
- Every non-trivial claim should be traceable to a citation (web/doc/internal).
- Numbers must be reproducible: either computed by a tool (code sandbox) or quoted with citation.
- Sources panel must be easy to audit: consistent IDs, clickable references, and deduping.

### B2. Web Search Fanout (multi-round + concurrency)

To reach "research-grade" outputs, a single user request should be allowed to trigger **multiple searches**:

- **Fanout (parallel):** run 3+ web searches concurrently with different queries (e.g. official docs, evaluation/comparison, community practice, papers).
- **Multi-round (iterative):** after round-1 results, generate follow-up queries and run a second round to fill gaps or verify key claims.
- **Traceability:** every search must carry a `trace_id` and be stored as a `Source` entry (future work: normalized sources panel).

Practical policy defaults:
- Standard chat: at most 1 round (low-latency).
- Deep Research: 2 rounds (quality first), with strict caps on total queries and injected context length.

### B3. AI-Driven Retrieval Loop (100+ rounds design)

The "100+ rounds" capability is not "just run search many times". It requires a **retrieval loop** with budgets, caching, and stopping criteria.

Core loop:
- Plan queries (fanout) -> Run searches concurrently -> Fetch/Read key pages -> Extract facts & citations -> Evaluate gaps -> Repeat.

Key constraints (must-have):
- **Budget control:** hard caps on total rounds, total tool calls, total injected context length, and total wall-clock time.
- **Stop criteria:** stop when information gain stalls, evidence coverage is sufficient for deliverable, or budget is hit.
- **Cache & dedupe:** avoid re-searching the same query and re-reading the same URLs; reuse prior evidence.
- **Traceability:** every tool call has `trace_id`; every URL/PDF/image becomes a `Source` with stable ID.

Suggested stopping heuristics (hybrid):
- Rule-based: 2 consecutive rounds with no new unique sources/facts.
- Model-based: an "evidence sufficiency judge" returns `{stop:boolean, reasons:string[], missing:string[]}`.

Why we need a judge:
- Deep retrieval without a judge turns into wasteful loops.
- The judge is also what enables skills to be deterministic ("verify pass" can fail the job if judge says evidence missing).

Connector strategy (advanced network environments):
- Treat "paper DBs / enterprise DBs" as **retrieval providers** behind the same tool contract.
- Examples: Crossref/OpenAlex/arXiv, institutional SCI(E) gateways, internal knowledge bases.
- UI must show: which providers were used, and which require credentials/consent.

UI implications:
- Show live counters: `rounds`, `fanout`, `tool_calls`, `unique_sources`, `budget_remaining`.
- Allow user to "raise budget", "pause", "force stop", and "pin sources".

### B1. Citation Enforcement (hard policy)

- If a claim has no citation, the system must:
  - either auto-collect a source and attach it,
  - or explicitly mark the statement as "uncited".
- Export rules:
  - DOCX/PDF export is blocked if "uncited" remains and citations are forced.
  - User can override only in "advanced" mode (explicit consent).

### C. UX (workspace + iteration)
- Deep research runs as a job with:
  - Plan (editable + approve),
  - Progress (streamed steps),
  - Evidence set (sources),
  - Draft artifact(s),
  - Export.
- "Artifacts" are first-class: each deliverable is an artifact with revisions.
- Global/folder instructions: style preferences and domain defaults apply automatically per workspace.

## Architecture (Target)

### 1) Layers

- Flutter (UI):
  - Deep Research workspace (job list, plan editor, report viewer, sources panel).
  - Artifact preview/edit (Markdown + WYSIWYG-ish for key structures).
  - Export/download UI, templates selection.

- Rust sidecar backend (local, bundled):
  - Tool Gateway ("SAP"): tool registry, permissions, audit log, execution routing.
  - Skill Engine: deterministic pipelines for report/deck/sheet generation.
  - Agent Orchestrator: planner + workers; schedules and supervises long jobs.
  - Sandbox Manager: Docker/WSL2/microVM execution, scoped filesystem mounts.

- Tool servers (polyglot, via MCP):
  - Node servers: PPTX generation (e.g., PptxGenJS), browser automation, some connectors.
  - Python servers: data analysis, chart render, docx/xlsx generation, PDF post-processing.
  - Each server exposes tools over MCP (stdio or HTTP/SSE transport).

### 2) Data Model (minimum)

- `ResearchJob`
  - `job_id`, `session_id`, `trace_id`
  - `state`: planned/running/review/exported/failed
  - `plan` (editable)
  - `sources[]` (normalized)
  - `artifacts[]` (report/deck/sheet)

- `Artifact`
  - `artifact_id`, `type`: report|deck|sheet|notes
  - `format`: md|html|pdf|docx|pptx|xlsx
  - `content` (or file path)
  - `render_config` (template/theme)
  - `citations_map` (ref -> source_id)

## Skills (High-Value Set)

Skills are *deterministic pipelines* that call tools and enforce formatting + QA:

1) `deep_research.report_pro`
- Inputs: topic, audience, length, tone, template, constraints
- Steps:
  - plan -> gather sources -> synthesize outline -> draft -> citation pass -> QA pass -> layout render -> export

2) `deep_research.deck_pro`
- Generates PPTX with:
  - narrative (problem, market, solution, recommendation),
  - charts,
  - appendix with sources.

3) `deep_research.model_xlsx`
- Builds XLSX with:
  - assumptions sheet,
  - calculations sheet,
  - output sheet + charts.

4) `deep_research.polish_pass`
- Enforces house style:
  - typography, spacing rules, heading hierarchy,
  - table formatting and alignment,
  - figure captions and numbering,
  - citation style (footnotes/endnotes).

5) `deep_research.verify_pass`
- Runs:
  - citation completeness check,
  - numeric sanity check (recompute if possible),
  - contradiction scan (two sources disagree -> mark uncertainty).

## Clarification Questionnaire (N-T-AI-style, refined)

When user requirements are underspecified, Deep Research should switch into a "Questionnaire" step.

### Behavior

- The agent generates a short structured questionnaire (5-10 items max).
- Each question is multiple-choice when possible (reduces ambiguity), with an optional free-text field.
- Each question has:
  - `why_this_matters`
  - `default_choice` (what the AI will pick if user does not respond)
  - `timeout_seconds` (default 90s)
- If user doesn't answer before timeout:
  - AI auto-fills using `default_choice`, marks it as `auto_filled=true`.
  - Job continues, but the UI shows a banner: "Some choices were auto-filled; click to revise."
- Clarification can run **up to 3 rounds**, no more.
  - Round 1: major deliverables + audience + scope
  - Round 2: depth + data policy + chart preferences
  - Round 3: style + length + export formats
  - If still ambiguous after round 3: proceed with safe defaults.

### Example questions

- Audience: exec / technical / mixed
- Deliverable: docx / pptx / both
- Citation style: IEEE / APA / GB/T / footnote numeric
- Data policy: include estimates? yes/no
- Charts: include? yes/no; prefer bar/line/table-first
- Length: short (1-2 pages) / normal (3-6) / long (10+)

## Tooling Strategy (Charts + Layout)

### Report rendering
Preferred: Markdown -> HTML (template) -> PDF.
- Reason: best control of design aesthetics with CSS.
- PDF engine: headless Chromium or a dedicated HTML->PDF renderer.

### DOCX-first (recommended initial milestone)

We should ship DOCX as the first "professional" artifact because it's the most useful in real work reporting.

Docx pipeline options:

Option A (pragmatic): Markdown -> DOCX (Pandoc) with `reference.docx` styles and optional OpenXML template.
- Pros: mature ecosystem, citations support, consistent styles via reference doc.
- Cons: some edge-cases on list/table styling; needs careful template governance.

Option B (layout-first): HTML -> DOCX conversion.
- Pros: reuse HTML design system.
- Cons: style mapping is often lossy; harder to guarantee "Word-native" structure.

Decision (user preference):
- **Default to HTML -> DOCX** to preserve typography, spacing, and layout.
- Keep Markdown -> DOCX as a fallback for "simple text reports" or when HTML conversion fails.
- Keep HTML->PDF pipeline for "beautiful PDF" as a parallel track.

Implementation notes:
- We should build a **single HTML layout system** that drives both DOCX and PDF.
- Use "layout blocks" (title, summary, table, chart, callout, appendix) so conversion can be controlled.
- Candidate converters (evaluate by fidelity + size):
  - `@turbodocx/html-to-docx`
  - `html-docx-js`

## DOCX + PDF Production Pipeline (Design + QA)

This section focuses on the **DOCX+PDF artifact pipeline** and its verification, with an HTML-driven layout system as the single source of truth.

### 1) HTML -> DOCX Evaluation Plan (fonts, sizes, tables, headings, pagination)

Objective: quantify and compare HTML->DOCX conversion fidelity across candidate converters and templates, and define acceptance thresholds.

**Metrics (per fixture set)**
1. **Font fidelity**: % of text runs using the expected font family (including CJK fallback mapping). Target >= 98%.
2. **Font size fidelity**: % of text runs within +/- 0.5pt of expected size. Target >= 98%.
3. **Table fidelity**: % of tables matching expected column widths, borders, header row style, and cell padding within tolerance. Target >= 95%.
4. **Heading hierarchy**: all headings mapped to correct Word styles (`Heading 1/2/3`) with correct numbering rules. Target 100%.
5. **Pagination**: page break placements match `break-before/after` directives, and no orphan headings or split tables beyond allowed rules. Target >= 95%.

**Fixture set (controlled HTML inputs)**
- Minimal doc with H1/H2/H3, body, lists, and citations.
- Dense table doc: fixed widths, mixed alignment, header row, multi-line cells.
- Long narrative doc: forced page breaks, multi-page sections, footnotes.
- Mixed language doc: Latin + CJK + symbols to test font fallback.
- Visual blocks: callouts, figure captions, chart images, and appendix.

**Automation approach**
1. Convert each HTML fixture to DOCX using candidate converters and a fixed `reference.docx`.
2. Parse DOCX with a deterministic inspector (e.g., Python `python-docx` or OpenXML SDK) to extract fonts, sizes, headings, table structure, and page breaks.
3. Render DOCX to PDF via Word/LibreOffice for visual validation and compare against HTML->PDF baseline using image diff (pixel or structural diff).
4. Produce a summary report with per-metric scores and pass/fail flags.

**Acceptance rule**
- All five metrics must meet targets, and no visual regressions in the PDF comparison. Otherwise the converter is rejected or requires mapping rules/post-processing.

### 2) Production Pipeline Steps (HTML -> DOCX + HTML -> PDF)

**Shared steps (HTML as single source of truth)**
1. Generate a **layout-block JSON** from the research draft (sections, tables, figures, citations).
2. Render **HTML** via a controlled template engine using layout blocks and theme variables.
3. Run **layout QA** on HTML (heading order, table widths, citation links, page-break markers).

**HTML -> DOCX**
1. Convert HTML to DOCX with a selected converter and a locked `reference.docx` for styles.
2. Apply a **DOCX post-process pass** to fix known gaps (page breaks, heading numbering, table widths, footnote placement).
3. Run **DOCX QA** (style mapping, fonts/sizes, table checks, pagination checks).
4. Export finalized DOCX to `workspace/<session_id>/outputs/`.

**HTML -> PDF**
1. Render HTML to PDF using headless Chromium with print CSS.
2. Apply **print-only CSS** for page headers/footers, page numbers, and table header repetition.
3. Run **PDF QA** (font embedding, pagination, figure placement, link/citation integrity).
4. Export finalized PDF to `workspace/<session_id>/outputs/`.

### 3) Template Structure (Layout Blocks)

The HTML template should be built from reusable blocks that map cleanly to DOCX styles.

**Core blocks**
- Title page
- Table of contents
- Executive summary
- Section header (H1/H2/H3)
- Body paragraph
- Callout (info/warning/key takeaway)
- Figure with caption
- Table (with header row)
- Chart (image or SVG with caption)
- Quote block
- Footnotes/citations
- Appendix

**Block rules**
- Each block has a unique `data-block` identifier for conversion and QA.
- CSS classes map 1:1 to Word styles in `reference.docx`.
- Tables and figures declare width intent (`full`, `wide`, `content`) to stabilize layout across DOCX/PDF.
- Page breaks are authored as explicit blocks, not implicit CSS hacks.

### Images in documents (user creative requests)

We should support "image assets" in reports and decks.

Sources:
- Local ComfyUI server (user-managed)
- Cloud image providers (OpenAI/Gemini/others)

Design:
- Add an `image_generation` capability in the Tool Gateway.
- If user has local ComfyUI:
  - Use workflow JSON to parameterize prompts and return image files.
  - Keep a cache + metadata for reproducibility.
- If no local provider:
  - fall back to cloud image APIs (with explicit consent).

### Image Input Pipeline (user uploads in chat)

When the user sends an image in the chat:

1) **Ingest**
   - Store in a per-session sandbox workspace:
     - `workspace/<session_id>/inputs/`
   - Normalize name: `img_<timestamp>_<hash>.png` (or keep original name as metadata).
2) **Routing**
   - If the active **main model supports vision**, call the main model first.
   - Otherwise call the **vision agent**.
   - The vision result is stored as a structured note:
     - `{image_id, caption, tags, objects, text_ocr?, source_model}`
3) **Index & Trace**
   - Create a `source` entry for the image with a stable ID so it can be cited.
   - Add a short tag list (e.g. `scene`, `objects`, `style`) for retrieval.
4) **Document Binding**
   - If the user request implies a report/deck:
     - link the image into the artifact manifest
     - optionally include the vision caption in a "figure caption"

This ensures the image is always usable by tools and can be referenced in reports.

## Sandbox Workspace (temp files, code, artifacts)

We need a **per-session sandbox workspace** where tools can read/write without touching the user's main filesystem.

Proposed layout:

```
workspace/
  <session_id>/
    inputs/        # user uploads (images, docs)
    scratch/       # temp files, code, intermediate artifacts
    outputs/       # final artifacts (docx/pdf/pptx/xlsx)
    logs/          # tool/audit logs (optional)
```

Rules:
- Tools may only read/write under `workspace/<session_id>`.
- Absolute paths are rejected unless mapped to the workspace root.
- Session cleanup policy is configurable (e.g. keep 7 days).

## Tool: Code / CLI execution

If we add a code executor (e.g. "OpenCode CLI"), it should run inside the sandbox:

- Inputs: `{language, code, files[], args[], cwd}`.
- CWD default: `workspace/<session_id>/scratch/`.
- Outputs: `{stdout, stderr, exit_code, created_files[]}`.

This keeps "code execution" aligned with our tool permission model.

## OpenCode CLI Integration (local OS)

We can use OpenCode CLI as a **code/agent tool** that runs locally inside the
workspace sandbox. The Tool Gateway should:

- set `cwd` within `workspace/<session_id>/` (default: `scratch/`)
- set `OPENCODE_CONFIG` + `OPENCODE_CONFIG_DIR` to a workspace-shared location so skills can be reused
  across sessions (CMYKE uses `workspace/_shared/opencode/`)
- pass the user's prompt or the agent's instruction
- capture `stdout/stderr/exit_code`
- parse JSON output when available

**Hard policy:** OpenCode execution is **sandbox-only**.
- All task file IO (inputs/outputs/scratch) is scoped to `workspace/<session_id>/`.
- Shared config/skills are stored under `workspace/_shared/opencode/` (still under the workspace root).

Minimal invocation plan:

- interactive: `opencode` (TUI) for user-driven sessions
- non-interactive: `opencode run <message...> --format json` for tool execution
- optional warm server: `opencode serve` + `opencode run --attach http://localhost:4096 ...`
- MCP server management can be done via `opencode mcp add/list/auth` if we choose
  to delegate MCP connectivity to OpenCode for specific tools.

This allows the agent to call PowerShell/bash through OpenCode's tool layer
while keeping our main policy gate in Rust.

### Routing decision (user requirement)

- Deep Research: **MCP is delegated to OpenCode**.
  - Rust Tool Gateway only calls OpenCode.
- Realtime / standard chat: can call OpenCode as a tool, but only when needed.
- Built-in MCP + skills remain available for "normal" tools.

## Attribution & Updates (OpenCode)

We are embedding OpenCode and adapting its code. Requirements:

- Add an "About" entry for OpenCode in our app (name, license, link).
- Keep a scheduled update path (pull/refresh OpenCode source periodically).

### Charts
Define a single chart spec format (recommend Vega-Lite-like JSON).
- chart tool: input data + spec -> output SVG/PNG
- embed into HTML/PDF + PPTX.

### Slides
Generate native PPTX (not screenshot slides).
- ensures editable decks and crisp charts.

## Sandbox / "MANUS-like" execution

We need a workspace + executor for:
- browser automation / scraping,
- code interpreter (Python, node),
- file conversions.

Phased approach:
1) **Local OS first** (no mandatory Linux VM):
   - Windows: PowerShell + native tools
   - macOS/Linux: bash/zsh + native tools
2) Optional Linux sandbox later (Docker/WSL2/remote) for risky or heavy tasks.

Hard constraints:
- sandbox FS mounts are explicit (workspace folder only)
- network egress can be toggled per job
- all tool calls are logged with `trace_id`

### Cross-platform sandbox abstraction

Define a `SandboxBackend` interface and select at runtime:

- Windows:
  - `native_restricted` backend (fallback)
  - `wsl2` backend (optional)
  - `docker` backend (optional)
- macOS:
  - `native_restricted` backend (fallback)
  - `docker` backend (optional)
  - `lima/colima` backend (optional)
- Linux:
  - `native_restricted` backend (fallback)
  - `docker/podman` backend (optional)

Backend selection is always visible to the user in Deep Research settings.

## MCP / Tooling Research (external references)

These references inform design choices; they are not CMYKE dependencies yet.

- Manus skills emphasize sandboxed execution and structured SKILL workflows.
- AI Manus (open-source) provides a docker-based sandbox, toolset (terminal/browser/files), and SSE event streaming.
- ComfyUI supports API-driven workflows with JSON graphs, making local image generation reproducible.
- ComfyUI has an official OpenAI GPT-Image-1 node example, indicating a plugin-friendly model integration path.

## Reference Learnings from Cloned Projects (local)

From the repos you requested we cloned into `Studying/deep_research`:

- **free-OKC (OKCVM)**: ships a canonical system prompt + tool spec + Python tool implementations + FastAPI UI.
  - This supports our idea of a **"tool contract" spec** and a **server-managed tool registry**.
  - The VM enforces **per-session workspace mounts** and rejects paths outside the sandbox.
- **openclaw**: gateway + onboarding wizard + channel integrations.
  - Reinforces the need for a **runtime daemon** (SAP tool gateway) and strong onboarding.
- **openclaw-skills**: skills are standalone artifacts.
  - Suggests we keep skills versioned and separate from the core runtime.
  - Common structure: `SKILL.md` + `_meta.json` + optional `scripts/` and `references/`.
- **zeroclaw**: agent prompt patterns + tool-loop behaviors.
  - Useful as a reference when we harden Deep Research's "multi-turn tool calling" policies and persona separation.
- **coze-studio**: full agent-dev platform with workflow, plugins, knowledge, and models.
  - Useful for thinking about modular resources and UI composition.

### License & Attribution Snapshot (learning/referenced repos)

For compliance, we explicitly mark these references and their local paths.
They are primarily used for architecture research and migration analysis.

| ID | Project | Local path | Usage boundary | License |
|---|---|---|---|---|
| TP-REF-001 | free-OKC | `Studying/deep_research/free-OKC` | Tool contract + VM sandbox reference | MIT |
| TP-REF-002 | openclaw | `Studying/deep_research/openclaw` | Gateway daemon, onboarding, channel adapter reference | MIT |
| TP-REF-003 | openclaw-skills | `Studying/deep_research/openclaw-skills` | SKILL artifact structure reference | MIT |
| TP-REF-004 | nanobot-cn | `Studying/deep_research/nanobot-cn` | Agent orchestration reference | MIT |
| TP-REF-005 | coze-studio | `Studying/deep_research/coze-studio` | Platform composition reference | Apache-2.0 |
| TP-REF-006 | zeroclaw | `Studying/deep_research/zeroclaw` | Prompt/tool-loop organization reference | MIT |
| TP-REF-007 | OpenManus | `Studying/universal-agent/openmanus/OpenManus-main` | Manus-like sandbox/flow reference | MIT |
| TP-REF-008 | OpenCowork | `Studying/universal-agent/opencowork/opencowork-main` | Deep research orchestration reference | MIT |
| TP-REF-009 | DeepResearchAgent | `Studying/universal-agent/deepresearchagent/DeepResearchAgent-main` | Toolset/process reference | Public Domain / The Unlicense |
| TP-REF-010 | Skywork Super Agents | `Studying/universal-agent/skywork-super-agents/Skywork-Super-Agents-main` | Multi-agent orchestration reference | MIT |

OpenCode note:
- OpenCode is integrated as an external tool runner in our gateway path.
- License is tracked as MIT via `opencode-ai` npm metadata.
- Attribution details should stay aligned with `docs/THIRD_PARTY_ATTRIBUTIONS.md`.

## Roadmap (pragmatic)

M0 (now): freeze schemas + UX skeleton
- finalize `ResearchJob/Artifact/Source/Citation` models and UI panels
- define the skill YAML schema and ToolCall/ToolResult envelope

M1: "Professional Report" first
- report generator: Markdown -> HTML template -> PDF
- sources panel + ToC + export
- citations enforcement + verify pass
 - DOCX generator: Markdown -> DOCX with reference style pack (ship at least 2 themes)

M2: charts
- implement chart tool (SVG/PNG)
- embed into report + export

M3: PPTX/XLSX
- add tool servers for PPTX/XLSX generation (MCP)
- add deck/sheet skills

M4: sandbox
- add Docker/WSL2 manager and "code interpreter" tool
- enforce permissions, audit, workspace scoping

M5: connector ecosystem
- MCP connectors for common apps (drive/email/calendar/notes) behind policy gates
