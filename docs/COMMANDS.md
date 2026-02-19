# Command Reference

This doc lists the current chat commands and shortcut tags supported by CMYKE.
Commands are only recognized when they appear at the start of the message.

## Slash Commands

- `/help` or `/commands` or `/?` show command help.
- `/tool <action> <query>` run a tool call through the gateway.
- `/tool help` show tool command usage.
- `/agent <goal>` create a new universal agent session.
- `/research <goal>` deep research (default report).
- `/summary <goal>` quick summary (shallow).
- `/persona` show the current persona prompt.
- `/motions` show available Live3D motions.
- `/play <id>` trigger a motion.
- `/stop` stop motion and return to idle.
- `/mcp` show MCP help.
- `/skills` show Skills help.
- `/agents` show Agents help.

## Hash Tags (Shortcuts)

- `#tool <query>` tool call (defaults to `code`).
- `#search <query>` web search.
- `#crawl <url>` crawl a web page.
- `#analyze <text>` analysis.
- `#summarize <text>` summary.
- `#image <prompt>` image generation (planned).
- `#vision <prompt>` image analysis (planned).
- `#agent <goal>` same as `/agent`.
- `#research <goal>` same as `/research`.
- `#help` or `#help <topic>` same as `/help`.

## Tool Actions

- `code` shell or scripting actions.
- `search` web search.
- `crawl` fetch a URL.
- `analyze` analysis.
- `summarize` summary.
- `image` image generation (planned).
- `vision` image analysis (planned).

## Gateway Requirements

- Enable the tool gateway in Settings.
- Set gateway base URL and pairing token.
- Tool execution uses the Rust gateway and OpenCode.
