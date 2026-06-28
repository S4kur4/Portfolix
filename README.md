# Portfolix

**Portfolix 是一款运行于 macOS 的投资组合管理工具，面向国内个人投资者，提供记录、追踪与智能分析功能。**

中文 | [English](#english)

## 简介

Portfolix 是一个原生 macOS 投资组合管理 App，面向希望自主记录资产、理解组合结构、跟踪收益变化，并通过 AI 获得辅助分析的个人投资者。

Portfolix 不连接券商账户，不要求输入任何第三方金融账户密码、Cookie 或交易 Session Token。用户的持仓、历史收益、资产价格快照和设置默认保存在本机，由用户自行记录、修改并跟踪。

## 功能

- 记录股票、基金、数字货币和现金类资产
- 维护每日组合快照和资产价格历史
- 查看组合价值、收益趋势、持仓占比、币种敞口和数据源状态
- 管理风险偏好，并评估组合与个人风险约束的匹配情况
- 使用用户自行配置的 LLM 和 Search API 生成智能分析报告
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

## AKShare Helper

Portfolix 包含一个最小化 JSON-lines Python Bridge，用于通过 [AKShare](https://github.com/akfamily/akshare) 查询部分市场数据。开发环境可创建隔离运行时：

```bash
python3 -m venv .build/akshare-runtime
.build/akshare-runtime/bin/python3 -m pip install --requirement Helpers/requirements-akshare-dev.txt
```

正式发布时，如果随 App 打包 AKShare 和 Python 依赖，需要同时保留 AKShare 及其传递依赖的许可证声明。详见 `THIRD_PARTY_NOTICES.md` 和 `RELEASING.md`。

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

- Record stocks, funds, cryptocurrencies, and cash assets
- Maintain daily portfolio snapshots and historical asset prices
- View portfolio value, performance trends, allocation breakdown, currency exposure, and data source status
- Manage risk preferences and evaluate how the portfolio aligns with personal risk constraints
- Generate analytical reports using user-configured LLM and search APIs
- Export holdings, daily performance, and asset price data as structured datasets

## Build and Test

Run tests:

```bash
swift test
```

Build the app for local development:

```bash
./scripts/build-app.sh
open .build/Portfolix.app
```

## AKShare Helper

Portfolix includes a minimal JSON-lines Python bridge for querying selected market data via [AKShare](https://github.com/akfamily/akshare). For development, you can create an isolated runtime environment:

```bash
python3 -m venv .build/akshare-runtime
.build/akshare-runtime/bin/python3 -m pip install --requirement Helpers/requirements-akshare-dev.txt
```

For production releases, if AKShare and its Python dependencies are bundled with the app, you must also include the corresponding licenses of AKShare and its transitive dependencies. See `THIRD_PARTY_NOTICES.md` and `RELEASING.md` for details.

## License

The Portfolix source code is licensed under the Apache License 2.0. See `LICENSE` for details.

The name "Portfolix", logo, app icon, and brand assets are not automatically granted for trademark use. See `TRADEMARK.md` for details.
