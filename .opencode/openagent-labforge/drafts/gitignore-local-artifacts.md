# Draft: Gitignore Local Artifacts

## Requirements (confirmed)
- 一次性把 git 忽略规则配置好
- `.opencode` 这类目录不要提交

## Technical Decisions
- 采用仓库根 `.gitignore` 统一管理本地目录忽略规则
- 保持已有规则不删改，只追加本地目录忽略项
- 本次忽略范围锁定为：`.opencode/`、`scripts/`、`starting/`

## Research Findings
- `.gitignore` 当前未忽略 `.opencode/`、`scripts/`、`starting/`
- `git status --short` 当前未跟踪目录为 `.opencode/`、`scripts/`、`starting/`
- `.opencode/openagent-labforge/` 下已有 checkpoint/bootstrap 文件，属于本地运行产物

## Open Questions
- 无

## Scope Boundaries
- INCLUDE: 更新根 `.gitignore` 的本地目录忽略规则、验证 `git status`
- EXCLUDE: 修改业务代码、删除现有文件、改动子目录内其他 `.gitignore`
