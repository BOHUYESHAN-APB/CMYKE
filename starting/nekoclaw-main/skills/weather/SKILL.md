# Weather Skill

获取当前天气信息（从 wttr.in 免费天气服务）。

## Usage

使用 `@shell` 工具调用 curl 获取天气信息:

```bash
@shell({"command": "curl -s wttr.in/Tokyo?format=3"})
```

## Example Queries

- "现在的天气怎么样？"
- "告诉我东京的天气"
- "Temperature in Tokyo"

## Parameters

- `location`: 城市名称（默认: Tokyo）
- `format`: 输出格式（默认: format=3，简洁格式）

## Advanced

完整格式:
```bash
curl -s wttr.in/Tokyo?format="%l:+%c+%t+%w"
```

## Notes

- 无需 API key
- 支持全球大多数城市
- 数据来自 wttr.in 服务
