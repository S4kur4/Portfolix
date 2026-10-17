<div align="center"><img src="/Portfolix.png" alt="Portfolix" width="96" height="96"/>

# Portfolix

中文 | [English](#english)
</div>

## 简介

Portfolix 是一个原生 macOS 投资组合管理 App，面向希望自主记录资产、理解组合结构、跟踪收益变化，并通过 AI 获得辅助分析的个人投资者。

<div align="center">
  <img src="/Resources/Screenshot-1.png?raw=true" alt="Overview" width="600">
</div>

Portfolix 不连接券商账户，不要求输入任何第三方金融账户密码、Cookie 或交易 Session Token。持仓、历史收益、资产价格快照和设置默认保存在本机，由你自行记录、修改并跟踪。

## 功能

- 目前支持记录和跟踪A股、B股、美股、港股、公募基金、数字货币和现金类资产
- 维护每日组合快照和资产成本价格，并可批量或通过本机语音更新持仓份额与成本
- 查看组合价值、盈亏日历、持仓收益趋势和持仓占比
- 通过投资云图查看今日盈亏和 AI 穿透分析的投资领域分布；未开启 AI 时按资产类别展示投资分布
- 使用自行配置的 DeepSeek API 生成智能分析报告，并可按需启用免密钥的 Parallel Search、复用 DeepSeek API Key 的 DeepSeek Search，或配置 Tavily、博查提供联网搜索
- 可将持仓明细、每日收益、资产每日价格和风险偏好导出为结构化数据包，或通过只读 MCP 供本机 AI 工具按授权访问

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

Portfolix does not connect to brokerage accounts and does not require you to enter any third-party financial account passwords, cookies, or session tokens. Your holdings, historical returns, asset price snapshots, and settings are saved locally by default, allowing you to record, modify, and track them independently.

## Features

- Multi-Asset Tracking: Currently supports recording and tracking A-shares, B-shares, US stocks, Hong Kong stocks, public funds, digital currencies, and cash assets.
- Snapshot Management: Maintains daily portfolio snapshots and asset cost bases, with batch or on-device voice updates for holding quantities and costs.
- Visual Analytics: View portfolio value, the P&L calendar, holding return trends, and holding allocations.
- Investment Map: Explore today's P&L and AI-assisted underlying investment-sector distributions, with asset-category distributions when AI is disabled.
- AI-Powered Analysis: Generate intelligent reports with your own DeepSeek API key and optionally enable keyless Parallel Search, reuse your DeepSeek API key for DeepSeek Search, or configure Tavily and Bocha for web research.
- Data Access: Export holding details, daily returns, daily asset prices, and risk preferences as structured data packages, or grant authorized local AI tools read-only MCP access.

## Market Data
Portfolix utilizes native Swift market data adapters to query public market data for stocks, funds, and digital currencies from the internet, requiring no additional API Key configuration.

## License
The Portfolix source code is licensed under the Apache License 2.0. See LICENSE for details.

The Portfolix name, logo, App Icon, and brand assets are not automatically licensed as trademarks. See TRADEMARK.md for details.
