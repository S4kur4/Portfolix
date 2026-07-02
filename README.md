# Portfolix

**Portfolix 是一款运行于 macOS 的投资组合管理工具，面向国内个人投资者，提供记录、追踪与智能分析功能。**

中文 | [English](#english)

## 简介

Portfolix 是一个原生 macOS 投资组合管理 App，面向希望自主记录资产、理解组合结构、跟踪收益变化，并通过 AI 获得辅助分析的个人投资者。

Portfolix 不连接券商账户，不要求输入任何第三方金融账户密码、Cookie 或交易 Session Token。用户的持仓、历史收益、资产价格快照和设置默认保存在本机，由用户自行记录、修改并跟踪。

## 功能

- 记录跟踪A股、B股、美股、港股、公墓基金、数字货币和现金类资产
- 维护每日组合快照和资产价格历史
- 查看组合价值、收益趋势、持仓占比、币种敞口和数据源状态
- 管理个人风险偏好，并评估组合与个人风险约束的匹配情况
- 使用自行配置的 LLM API 和 Search API 生成智能分析报告
- 将持仓明细、每日收益和资产每日价格导出为结构化数据包

## 构建与测试

运行测试：

```bash
swift test
```

构建本地开发 App：

```bash
./scripts/build-app.sh
open .build/Portfolix.app
```

## 行情数据

Portfolix 使用原生 Swift 行情适配器查询互联网上股票、基金和数字货币公开行情，无需额外配置 API Key。

## 许可证

Portfolix 源代码使用 Apache License 2.0 授权。详见 `LICENSE`。

Portfolix 名称、Logo、App Icon 和品牌资产不自动作为商标授权。详见 `TRADEMARK.md`。

---

# English

[中文](#portfolix) | English

**Portfolix is a local-first macOS app for personal portfolio records, tracking, and AI-assisted analysis.**

## Overview

Portfolix is a native macOS portfolio management app designed for individual investors who want to independently record their assets, understand portfolio structure, track performance changes, and leverage AI-assisted analysis.

Portfolix does not connect to brokerage accounts and does not require any third-party financial account credentials, cookies, or trading session tokens. Users’ holdings, historical performance, asset price snapshots, and settings are stored locally by default, and are fully managed, updated, and tracked by the user.

## Features

- Track and record A-shares, B-shares, US stocks, Hong Kong stocks, public mutual funds, digital currencies, and cash assets
- Maintain daily portfolio snapshots and asset price history
- View portfolio value, return trends, holding allocations, currency exposures, and data source status
- Manage personal risk tolerance and assess how well the portfolio matches personal risk constraints
- Generate intelligent analysis reports using self-configured LLM APIs and Search APIs
- Export holding details, daily returns, and daily asset prices as structured data packages

## Build & Test

Run tests:

```bash
swift test
```

Build the local development App:

```bash
./scripts/build-app.sh
open .build/Portfolix.app
```

## Market Data
Portfolix utilizes native Swift market data adapters to query public market data for stocks, funds, and digital currencies from the internet, requiring no additional API Key configuration.

## License
The Portfolix source code is licensed under the Apache License 2.0. See LICENSE for details.

The Portfolix name, logo, App Icon, and brand assets are not automatically licensed as trademarks. See TRADEMARK.md for details.
