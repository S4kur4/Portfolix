# Portfolix MCP

## 连接与授权

在系统设置的「智能分析」中打开 **MCP Server**，确认授权后点击复制图标，将生成的配置加入支持本地 stdio 的 MCP 客户端。无需配置端口，不会注册后台常驻服务。客户端按需启动 App 包内的 `Contents/MacOS/PortfolixMCP`。

默认关闭。只读取本机已保存的数据，不触发行情刷新、智能分析或任何写入。App 退出后已授予的读取权限仍有效；关闭开关后，现有客户端的后续读取也会被拒绝。关闭不能撤回客户端已经读取的数据。

授权范围是当前 macOS 用户下的本地 MCP 客户端，不是逐客户端隔离的权限。只连接可信的 Agent；它可能把返回的持仓、成本及收益发送至自己的模型服务。不要把此 stdio 程序通过网络代理公开。

## 只读接口

| 工具 | 返回数据 | 参数 |
| --- | --- | --- |
| `get_portfolio_summary` | 最近保存的组合快照、持仓数量 | 无 |
| `list_holdings` | 资产名称、代码、类别、份额、成本及缓存价格、价格时间与新鲜度 | `limit` 默认 50、最多 100；`offset` 默认 0 |
| `get_daily_profit` | 与 App 日历相同口径的每日人民币盈亏 | `start_date`、`end_date` |
| `get_portfolio_history` | 历史组合市值、总成本、持仓收益及收益率 | `start_date`、`end_date` |
| `get_asset_price_history` | 指定资产的历史价格、份额与人民币市值 | `asset_id`、`start_date`、`end_date` |

日期使用 `YYYY-MM-DD`，包含开始和结束日期，单次范围最多 366 天。资产 ID 从 `list_holdings` 获取。分页返回 `next_offset`，为 `null` 时结束；翻页期间修改持仓可能改变分页位置，需要重新读取。

金额和份额使用十进制字符串，并明确币种。组合汇总是带日期的已保存快照，不冒充实时估值。历史缺失不补零。每日盈亏按「人民币单位市值相对上一条有效记录的变化 × 当前份额」汇总，包含汇率变化，不等同于经过出入金调整的账户实际收益。

## 安全边界

- 不开放 API Key、其他设置、聊天记录、原始数据库、任意 SQL、任意文件路径或写入工具。
- SQLite 以只读方式打开并启用 `query_only`；工具只执行固定查询，参数单独绑定。
- 每次读取前后检查授权；数据库缺失、授权无法读取或查询失败时拒绝返回数据。
- 请求最大 64 KiB；单次查询最多 20,000 条内部记录，数据库字段数据最多 2 MB，查询执行约 2 秒超时。超限报错，不返回可能误导的部分计算结果。
- 资产名称等用户内容是不可信数据，客户端不可将其当成指令执行。
- 标准输出仅包含换行分隔的 JSON-RPC 消息，不写入业务日志或敏感数据。

协议版本：`2025-11-25`。支持 `initialize`、`notifications/initialized`、`ping`、`tools/list`、`tools/call`。不提供 HTTP、resources、prompts、订阅或远程访问。

参考：[MCP stdio 规范](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)、[工具规范](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)。
