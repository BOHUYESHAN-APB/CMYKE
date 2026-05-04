# Git Ignore Local Artifact Directories

## TL;DR
> **Summary**: Configure repo-root ignore rules so local runtime/reference directories are never staged accidentally.
> **Deliverables**:
> - Root `.gitignore` updated with `/.opencode/`, `/scripts/`, `/starting/`
> - Verification evidence that ignore rules apply and `git status` no longer reports those three directories
> - Edge-case evidence for already-tracked files under these paths
> **Effort**: Quick
> **Parallel**: NO
> **Critical Path**: Task 1 → Task 2 → Task 3

## Context
### Original Request
- 用户要求一次性配置 git 忽略规则，明确指出 OpenCode 类目录不要提交。
- 用户已确认忽略范围为三者全部：`.opencode/`、`scripts/`、`starting/`。

### Interview Summary
- 目标是“防误提交流程产物/本地目录”，不是改业务代码。
- 范围锁定根 `.gitignore`，不改子目录 `.gitignore`、不改全局 git config。

### Metis Review (gaps addressed)
- Guardrail: 使用**根锚定目录规则**（`/path/`）避免误忽略同名子目录。
- Guardrail: 先验证是否已有 tracked 文件，避免错误承诺“全部消失”。
- Acceptance: 用 `git check-ignore -v` + `git status` 双重验证规则生效。

## Work Objectives
### Core Objective
将 `.opencode/`、`scripts/`、`starting/` 设为仓库根本地目录忽略项，阻止后续误提交。

### Deliverables
- 根 `.gitignore` 新增 3 条规则（追加，不破坏现有项）
- 命令行验证结果（规则来源、状态变化、tracked 边界）
- 证据文件路径记录

### Definition of Done (verifiable conditions with commands)
- `git check-ignore -v .opencode scripts starting` 显示命中根 `.gitignore` 的新增规则。
- `git status --short --untracked-files=all` 不再出现 `?? .opencode/`、`?? scripts/`、`?? starting/`。
- `git ls-files ".opencode" "scripts" "starting"` 结果为空；若非空，输出已记录并标记为后续清理议题（本计划不执行 rm --cached）。

### Must Have
- 只改根 `.gitignore`
- 规则采用根锚定目录写法：`/.opencode/`、`/scripts/`、`/starting/`
- 全部验证由 agent 命令执行，无人工判断步骤

### Must NOT Have (guardrails, AI slop patterns, scope boundaries)
- 不修改 `lib/`、`backend-rust/` 等业务代码
- 不编辑任何子目录 `.gitignore`
- 不执行 `git rm --cached`（除非后续用户单独要求）
- 不修改 git 全局配置

## Verification Strategy
> ZERO HUMAN INTERVENTION — all verification is agent-executed.
- Test decision: tests-after（Git commands, no framework)
- QA policy: 每个任务包含 happy path + failure/edge case
- Evidence: `.opencode/openagent-labforge/evidence/task-{N}-{slug}.txt`

## Execution Strategy
### Parallel Execution Waves
Wave 1: 规则写入与结构验证（Task 1）
Wave 2: 忽略行为验证（Task 2）
Wave 3: 状态收口与边界审计（Task 3）

### Dependency Matrix (full, all tasks)
- Task 1 blocks Task 2
- Task 2 blocks Task 3

### Agent Dispatch Summary (wave → task count → categories)
- Wave 1 → 1 task → quick
- Wave 2 → 1 task → quick
- Wave 3 → 1 task → quick

## TODOs

- [ ] 1. Append root-anchored ignore rules in root `.gitignore`

  **What to do**: 在根 `.gitignore` 文件末尾追加三行：`/.opencode/`、`/scripts/`、`/starting/`，保持现有内容不删除、不重排。
  **Must NOT do**: 不修改任何其他文件；不替换现有忽略规则。

  **Recommended Agent Profile**:
  - Category: `quick` — Reason: 单文件小改动
  - Skills: `[]` — 无额外技能依赖
  - Omitted: `[]` — 无

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [2, 3] | Blocked By: []

  **References**:
  - Pattern: `.gitignore:1-56` — 现有规则结构与注释风格
  - Pattern: `git status --short` 当前输出 — `?? .opencode/`, `?? scripts/`, `?? starting/`

  **Acceptance Criteria**:
  - [ ] `grep -n "^/\.opencode/$\|^/scripts/$\|^/starting/$" .gitignore` 返回三条命中
  - [ ] `.gitignore` 仅新增上述三条，不含其他变更

  **QA Scenarios**:
  ```
  Scenario: [Happy path - rules appended]
    Tool: Bash
    Steps: run git diff -- .gitignore
    Expected: diff only contains +/.opencode/, +/scripts/, +/starting/
    Evidence: .opencode/openagent-labforge/evidence/task-1-gitignore-rules.txt

  Scenario: [Failure/edge - accidental extra edits]
    Tool: Bash
    Steps: run git diff -- .gitignore and inspect added/removed lines count
    Expected: no removed lines from existing .gitignore content
    Evidence: .opencode/openagent-labforge/evidence/task-1-gitignore-rules-error.txt
  ```

  **Commit**: NO | Message: `chore(gitignore): ignore local artifact directories` | Files: [`.gitignore`]

- [ ] 2. Validate ignore-rule resolution and tracked-file edge case

  **What to do**: 使用 `git check-ignore -v` 验证三目录命中来源，使用 `git ls-files` 检查是否已有 tracked 文件。
  **Must NOT do**: 不执行 `git rm --cached`，不做索引清理动作。

  **Recommended Agent Profile**:
  - Category: `quick` — Reason: 只读验证命令
  - Skills: `[]` — 无
  - Omitted: `[]` — 无

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: [3] | Blocked By: [1]

  **References**:
  - API/Type: `git check-ignore -v` — 验证忽略规则命中来源
  - API/Type: `git ls-files` — 验证 tracked 边界

  **Acceptance Criteria**:
  - [ ] `git check-ignore -v .opencode scripts starting` 输出来源文件为根 `.gitignore`
  - [ ] `git ls-files ".opencode" "scripts" "starting"` 输出为空，或非空时输出被完整记录为边界风险

  **QA Scenarios**:
  ```
  Scenario: [Happy path - ignore source confirmed]
    Tool: Bash
    Steps: run git check-ignore -v .opencode scripts starting
    Expected: each path maps to root .gitignore newly added rules
    Evidence: .opencode/openagent-labforge/evidence/task-2-check-ignore.txt

  Scenario: [Failure/edge - tracked files exist]
    Tool: Bash
    Steps: run git ls-files ".opencode" "scripts" "starting"
    Expected: if output non-empty, mark boundary note "tracked files require separate cleanup task"
    Evidence: .opencode/openagent-labforge/evidence/task-2-tracked-edge.txt
  ```

  **Commit**: NO | Message: `n/a` | Files: []

- [ ] 3. Verify status cleanup for target directories only

  **What to do**: 运行最终状态核验，确认目标三目录不再出现在 untracked 列表；保留其他不相关状态。
  **Must NOT do**: 不要求仓库完全 clean；不处理无关目录。

  **Recommended Agent Profile**:
  - Category: `quick` — Reason: 单命令状态收口
  - Skills: `[]` — 无
  - Omitted: `[]` — 无

  **Parallelization**: Can Parallel: NO | Wave 3 | Blocks: [] | Blocked By: [2]

  **References**:
  - API/Type: `git status --short --untracked-files=all` — 目标目录可见性验证

  **Acceptance Criteria**:
  - [ ] `git status --short --untracked-files=all` 不含 `?? .opencode/`、`?? scripts/`、`?? starting/`
  - [ ] 输出中若仍有其他变更，标注为 out-of-scope，不做处理

  **QA Scenarios**:
  ```
  Scenario: [Happy path - target dirs hidden]
    Tool: Bash
    Steps: run git status --short --untracked-files=all
    Expected: target directories absent from output
    Evidence: .opencode/openagent-labforge/evidence/task-3-status.txt

  Scenario: [Failure/edge - target dirs still appear]
    Tool: Bash
    Steps: rerun git check-ignore -v .opencode scripts starting
    Expected: identify mismatch rule or tracked-file cause and record exact reason
    Evidence: .opencode/openagent-labforge/evidence/task-3-status-error.txt
  ```

  **Commit**: YES | Message: `chore(gitignore): ignore local artifact directories` | Files: [`.gitignore`]

## Final Verification Wave (4 parallel agents, ALL must APPROVE)
- [ ] F1. Plan Compliance Audit — oracle
- [ ] F2. Code Quality Review — unspecified-high
- [ ] F3. Real Manual QA — unspecified-high
- [ ] F4. Scope Fidelity Check — deep

## Commit Strategy
- 单提交策略：仅包含根 `.gitignore` 改动。
- 提交前确认 staged 文件仅 `.gitignore`。

## Success Criteria
- 本地目录 `.opencode/`、`scripts/`、`starting/` 不再被误加入提交候选。
- 忽略规则来源可追溯且可复验。
- 无业务代码受影响。
