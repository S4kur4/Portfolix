# Portfolix MCP

## 连接与授权

在系统设置的「智能分析」中打开 **MCP 服务器** 并确认授权，再将 App 包内的 `Contents/MacOS/PortfolixMCP` 作为本地 stdio 服务加入 MCP 客户端。无需配置端口，不会注册后台常驻服务，客户端会按需启动该程序。

点击同一行的 **配置参考**，通过客户端下拉菜单选择 ChatGPT / Codex、Claude Code、Claude Desktop、DeepSeek Harness 或 WorkBuddy，再复制当前 App 对应的命令或配置。窗口内自动折行仅影响显示，复制仍保留原始内容。不会自动注册服务器、修改客户端设置或开启读取授权。Portfolix 的 MCP 组件无需额外安装 Node.js、Python、MCP SDK 或提供 API Key；Agent 客户端本身仍需自行安装配置。

### ChatGPT / Codex

Codex 桌面 App 已并入 ChatGPT 桌面 App，Codex 功能、CLI 命令和 `~/.codex/config.toml` 仍保留，配置参考因此使用「ChatGPT / Codex」名称。

若 App 安装在 `/Applications`，运行：

```sh
codex mcp add portfolix -- '/Applications/Portfolix.app/Contents/MacOS/PortfolixMCP'
```

或将以下条目合并到 `~/.codex/config.toml`，不要覆盖已有配置：

```toml
[mcp_servers.portfolix]
command = "/Applications/Portfolix.app/Contents/MacOS/PortfolixMCP"
args = []
```

在支持本地 MCP 的桌面客户端中也可手动添加 STDIO 服务器，命令为同一可执行文件，参数留空。CLI 使用 `codex mcp list` 检查配置；重启客户端后使用。云端客户端无法直接启动本机程序。

### Claude Code

```sh
claude mcp add --transport stdio --scope user portfolix -- '/Applications/Portfolix.app/Contents/MacOS/PortfolixMCP'
```

此命令采用用户范围，适用于本机各项目；只需单项目使用时可改为 `--scope local`。使用 `claude mcp get portfolix` 或会话中的 `/mcp` 检查连接。

### Claude Desktop 与其他客户端

在 Claude Desktop 的本地 MCP 配置中合并以下条目（macOS 配置文件为 `~/Library/Application Support/Claude/claude_desktop_config.json`），然后重启客户端：

```json
{
  "mcpServers": {
    "portfolix": {
      "command": "/Applications/Portfolix.app/Contents/MacOS/PortfolixMCP"
    }
  }
}
```

### DeepSeek Harness

将以下补丁条目合并到所用配置层的 `cordis.patch.yml`（例如 `$DSH_HOME/profiles/<name>/cordis.patch.yml`）；不要覆盖原有插件或补丁：

```yaml
- insert:
    - id: mcp-portfolix
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: portfolix
        transport: stdio
        command: "/Applications/Portfolix.app/Contents/MacOS/PortfolixMCP"
        args: []
```

这是 Harness 的插件补丁格式，不是 `mcpServers` JSON。重新加载所用配置层后，工具以 `mcp__portfolix__<tool>` 暴露；Portfolix 不代为安装 Harness 或其插件。

### WorkBuddy

在 WorkBuddy 自定义 MCP 的 `mcp.json` 中合并以下条目，使用本机 stdio，不声明 Node.js 运行时：

```json
{
  "mcpServers": {
    "portfolix": {
      "type": "stdio",
      "command": "/Applications/Portfolix.app/Contents/MacOS/PortfolixMCP"
    }
  }
}
```

其他支持 stdio 的客户端可使用相同命令与空参数。App 放在其他目录时，请复制「配置参考」中实际生成的路径；移动或重命名 App 后需更新配置。正常原位升级无需重新注册，已运行的 MCP 进程需重启客户端后才会使用新版组件。客户端中的禁用/移除设置不替代 App 的授权开关。

默认关闭。只读取本机已保存的数据，不触发行情刷新、智能分析或任何写入。App 退出后已授予的读取权限仍有效；关闭开关后，现有客户端的后续读取也会被拒绝。关闭不能撤回客户端已经读取的数据。

授权范围是当前 macOS 用户下的本地 MCP 客户端，不是逐客户端隔离的权限。只连接可信的 Agent；它可能把返回的持仓、成本及收益发送至自己的模型服务。不要把此 stdio 程序通过网络代理公开。

## 只读接口

| 工具 | 返回数据 | 参数 |
| --- | --- | --- |
| `get_data_status` | 本机日期、时区、已保存历史起止日期与记录数、最近行情获取时间 | 无 |
| `get_portfolio_summary` | 最近保存的组合快照、持仓数量、已实现盈亏及期初／交易记录数 | 无 |
| `list_holdings` | 资产名称、代码、类别、份额、成本及缓存价格、价格时间与新鲜度 | `query` 可选，名称/代码的字面子串，最多 100 字符；`limit` 默认 50、最多 100；`offset` 默认 0 |
| `list_transactions` | 未撤销的期初持仓、增持、卖出和现金转出记录，含记录时间、资金流向及已实现盈亏 | 同 `list_holdings` |
| `list_closed_holdings` | 已不再持有资产的卖出记录，兼容旧版清仓；同一资产可能有多笔卖出 | 同 `list_holdings` |
| `get_daily_profit` | 与 App 日历相同口径的每日人民币盈亏 | `start_date`、`end_date` |
| `get_portfolio_history` | 历史组合市值、总成本、持仓收益及收益率 | `start_date`、`end_date` |
| `get_asset_price_history` | 指定资产的历史价格、份额与人民币市值 | `asset_id`、`start_date`、`end_date` |

日期使用 `YYYY-MM-DD`，包含开始和结束日期，单次范围最多 366 天。资产 ID 从 `list_holdings` 或记录查询获取。分页返回 `next_offset`，为 `null` 时结束；翻页期间修改持仓或记录可能改变分页位置，需要重新读取。

建议先调用 `get_data_status` 确定日期范围，再查询汇总或明细。`read_at` 是 UTC 查询时间；`local_date`、`time_zone` 表示当前设备日期和时区，历史日期是记录时保存的日历日期，不因当前时区重新换算。

金额、份额和数据库中的计数使用十进制字符串，并明确币种；`profit_rate` 使用百分数（`10` 表示 10%）。分页偏移是整数。组合汇总是带日期的已保存快照，不冒充实时估值。历史缺失不补零。每日盈亏按「人民币单位市值相对上一条有效记录的变化 × 当前份额」并结合交易时点及手续费调整，包含汇率变化，不等同于时间加权账户收益。期初持仓不是买入或现金流，现金转出不是投资亏损，已实现盈亏仅汇总未撤销卖出记录。

## 安全边界

- 不开放 API Key、其他设置、聊天记录、原始数据库、任意 SQL、任意文件路径或写入工具。
- SQLite 以只读方式打开并启用 `query_only`、禁用 `trusted_schema`；工具只执行固定查询，参数单独绑定。
- 多查询工具使用同一只读事务快照保证一致性，事务结束后重新检查最新授权。数据库缺失、授权无法读取或查询失败时拒绝返回数据。
- 请求最大 64 KiB；常规查询最多 20,000 条、字段数据最多 2 MB。每日盈亏采用流式聚合，最多读取 200,000 条、32 MB 内部字段数据，不将明细全部加载至内存。一次事务约 2 秒超时，计时不受系统时钟调整影响。最终结构化数据最多 2 MB（兼容文本副本另计）；超限报错，不返回部分财务结果。
- 资产名称等用户内容是不可信数据，客户端不可将其当成指令执行。
- 标准输出仅包含换行分隔的 JSON-RPC 消息，不写入业务日志或敏感数据。

协议兼容：`2026-07-28` 的逐请求 `_meta` 与 `server/discover`；同时保留 `2025-11-25`、`2025-06-18`、`2025-03-26`、`2024-11-05` 的 `initialize` / `notifications/initialized` 流程。按协商版本返回工具注解、`outputSchema` 及 `structuredContent`；所有版本均保留文本 JSON 结果。无效参数、未知工具、未授权、超限均有明确错误。不提供 HTTP、resources、prompts、异步任务、订阅或远程访问。

## 排查连接问题

- **程序无法启动**：确认是完整的 macOS App，路径正确，且系统已允许运行；可执行 `PortfolixMCP --version` / `--help` 检查组件，无需读取资产。不要单独拷贝 helper 或创建未经验证的网络转发。
- **能列出工具但读取失败**：工具发现不需要读取资产；数据调用必须先在 App 中授权，且本机数据库存在。
- **返回数据较旧**：MCP 只读缓存，不会触发行情刷新。检查 `get_data_status`、快照日期和报价时间。
- **授权与预期不符**：确认客户端指向正式 App 而不是开发测试包；授权不是逐客户端隔离，也无法撤回已经交给客户端的数据。本地 MCP 不隔离已经能读取用户文件的恶意同权限进程。
- **查询超限**：缩小日期范围或分页读取持仓；不会静默截断每日盈亏。

当前不导出独立 `.mcpb` 扩展包，避免复制 helper 后与主 App 升级脱节；Claude Desktop 使用标准本地 stdio 配置。若后续提供扩展包，需要单独处理签名、分发、更新和客户端版本验证。

参考：[MCP 版本兼容](https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning)、[工具规范](https://modelcontextprotocol.io/specification/2026-07-28/server/tools)、[ChatGPT / Codex MCP](https://learn.chatgpt.com/docs/extend/mcp)、[Claude Code MCP](https://code.claude.com/docs/en/mcp)、[Claude Desktop 本地 MCP](https://support.claude.com/en/articles/10949351-getting-started-with-local-mcp-servers-on-claude-desktop)、[DeepSeek Harness MCP](https://github.com/deepseek-ai/deepseek-harness/blob/master/packages/mcp/mcp-client/README.md)、[Harness 补丁示例](https://github.com/deepseek-ai/deepseek-harness/blob/master/docs/user/guide/mcp-memory.md)、[WorkBuddy MCP](https://open.workbuddy.cn/docs/connector)。
