# Skills System 📚

NekoClaw 的动态技能加载系统喵！⚡

## 概述

Skills 是 NekoClaw 的插件系统，通过简单的 `SKILL.md` 文件就能定义新技能，无需修改 Rust 代码！

## 架构

```
nekoclaw/
└── skills/                    # Skills 目录
    ├── echo/                  # 示例技能 1
    │   └── SKILL.md          # 技能描述文件
    ├── weather/              # 示例技能 2
    │   └── SKILL.md
    └── ...                   # 你的自定义技能
```

## 工作流程

1. **定义技能**：在 `skills/` 目录下创建新目录和 `SKILL.md`
2. **AI 学习**：NekoClaw 启动时自动扫描并读取所有 `SKILL.md`
3. **注入 Prompt**：技能描述被注入到 AI 的 system prompt 中
4. **智能调用**：AI 根据需求自动选择并调用对应的技能

## 创建新技能

### 步骤 1：创建技能目录

```bash
mkdir -p skills/my-skill
```

### 步骤 2：编写 SKILL.md

```markdown
# My Skill Name

简短描述这个技能的作用和应用场景。

## Usage

详细说明如何使用这个技能，包括：
- 什么时候使用
- 输入参数说明
- 输出格式

## Examples

提供几个使用示例：
- 示例 1
- 示例 2

## Notes

其他注意事项：
- 限制或约束
- 最佳实践
- 相关资源链接
```

### 步骤 3：重启加载

```bash
cargo run -- agent --message "测试新技能"
```

## 示例技能

### Echo Skill

**文件**: `skills/echo/SKILL.md`

使用 `@shell` 工具执行 `echo` 命令，将消息回显到 stdout。

```bash
@shell({"command": "echo 'your message here'"})
```

### Weather Skill

**文件**: `skills/weather/SKILL.md`

获取当前天气信息（从 wttr.in 免费天气服务）。

```bash
@shell({"command": "curl -s wttr.io/Tokyo?format=3"})
```

## 技能格式规范

### 强制要求

- ✅ 目录下必须包含 `SKILL.md` 文件
- ✅ 使用 Markdown 格式
- ✅ 第一行是 `# 技能名称`
- ✅ 包含明确的描述和使用说明

### 可选内容

- 📝 `## Usage` - 使用说明
- 💡 `## Examples` - 示例
- ⚠️ `## Notes` - 注意事项
- 🔧 `## Parameters` - 参数说明

## AI 如何使用技能

AI 会读取 `SKILL.md` 的内容，理解技能的用途和使用方法。当用户请求与某个技能相关的任务时，AI 会：

1. 识别用户意图
2. 选择最合适的技能
3. 调用 `@shell` 工具执行相应命令
4. 处理输出结果并返回给用户

## 兼容性

Skills 系统兼容 OpenClaw 社区的 Skills 格式，这意味着你可以：

- 直接使用 OpenClaw 的社区资源
- 在 OpenClaw 和 NekoClaw 之间共享技能
- 贡献你的技能到社区

## 高级特性

### 热重载

- ✅ 支持：修改 `SKILL.md` 后重启生效
- ❌ 暂不支持：运行时热重载（需要重启）

### 参数提取

系统自动从 `SKILL.md` 中提取第一段非空文本作为技能描述，展示给 AI。

### 日志

启用详细日志查看技能加载细节：

```bash
RUST_LOG=nekoclaw::skills=debug cargo run -- agent
```

## 故障排除

### 技能没有加载？

- 检查 `skills/` 目录是否在项目根目录
- 确保 `SKILL.md` 文件存在且格式正确
- 查看日志确认加载状态

### AI 不使用技能？

- 检查 `SKILL.md` 描述是否清晰
- 确保技能用途符合用户请求
- 查看完整的 system prompt（调试模式）

## 安全考虑

⚠️ **重要提示**：

- Skills 系统通过 `@shell` 工具执行命令
- 所有命令都会经过 Shell 工具的安全检查
- 建议限制危险命令的执行权限
- 测试技能时注意安全边界

## 贡献

欢迎贡献新的技能！

1. `skills/your-skill/SKILL.md` - 技能描述
2. `skills/your-skill/scripts/` - 可选的脚本文件（如需要）
3. 提交 PR 或在 Discord 社区分享

---

**开发者**: 诺诺 (Nono) ⚡

**最后更新**: 2026-02-16
