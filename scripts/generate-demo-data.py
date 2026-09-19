#!/usr/bin/env python3
"""Generate a deterministic, privacy-safe Portfolix demo data package."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import random
import tempfile
import uuid
import zipfile
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal, ROUND_HALF_UP, getcontext
from pathlib import Path


getcontext().prec = 28

FORMAT_IDENTIFIER = "app.portfolix.data-export.archive"
SCHEMA_VERSION = 3
SEED = 20260919
NAMESPACE = uuid.UUID("1c1783be-cf54-44e8-91f0-72e748f65bb4")
DATA_FILENAMES = (
    "holdings.json",
    "daily_returns.json",
    "daily_asset_prices.json",
    "risk_profile.json",
)
RATES_FROM_CNY = {
    "CNY": Decimal("1"),
    "HKD": Decimal("1.153431425"),
    "USD": Decimal("0.147215543"),
    "USDT": Decimal("0.147289188"),
}


@dataclass(frozen=True)
class DemoAsset:
    name: str
    symbol: str
    category: str
    currency: str
    quantity: Decimal
    average_cost: Decimal
    final_price: Decimal
    month_return: Decimal
    volatility: Decimal
    source: str
    freshness: str = "已更新"

    @property
    def asset_id(self) -> str:
        return str(uuid.uuid5(NAMESPACE, f"{self.category}|{self.symbol}"))

    @property
    def trades_on_weekends(self) -> bool:
        return self.category in {"数字货币", "现金"}


ASSETS = (
    DemoAsset("贵州茅台", "600519", "A 股", "CNY", Decimal("110"), Decimal("1450"), Decimal("1588"), Decimal("0.035"), Decimal("0.012"), "东方财富"),
    DemoAsset("宁德时代", "300750", "A 股", "CNY", Decimal("520"), Decimal("205"), Decimal("218"), Decimal("-0.028"), Decimal("0.020"), "东方财富"),
    DemoAsset("招商银行", "600036", "A 股", "CNY", Decimal("3500"), Decimal("39.5"), Decimal("42.8"), Decimal("0.015"), Decimal("0.010"), "东方财富"),
    DemoAsset("腾讯控股", "00700", "港股", "HKD", Decimal("700"), Decimal("365"), Decimal("420"), Decimal("0.050"), Decimal("0.018"), "东方财富"),
    DemoAsset("Apple", "AAPL", "美股", "USD", Decimal("150"), Decimal("210"), Decimal("238"), Decimal("0.032"), Decimal("0.014"), "东方财富"),
    DemoAsset("NVIDIA", "NVDA", "美股", "USD", Decimal("180"), Decimal("148"), Decimal("176"), Decimal("0.061"), Decimal("0.026"), "东方财富"),
    DemoAsset("Microsoft", "MSFT", "美股", "USD", Decimal("70"), Decimal("475"), Decimal("510"), Decimal("-0.012"), Decimal("0.012"), "东方财富"),
    DemoAsset("华夏纳斯达克100 ETF联接A", "015299", "公募基金", "CNY", Decimal("140000"), Decimal("1.61"), Decimal("1.78"), Decimal("0.044"), Decimal("0.009"), "东方财富"),
    DemoAsset("易方达黄金主题", "161116", "公募基金", "CNY", Decimal("90000"), Decimal("1.82"), Decimal("2.06"), Decimal("0.027"), Decimal("0.008"), "东方财富"),
    DemoAsset("中欧医疗健康混合A", "003095", "公募基金", "CNY", Decimal("120000"), Decimal("1.72"), Decimal("1.49"), Decimal("-0.055"), Decimal("0.012"), "东方财富"),
    DemoAsset("易方达中概互联50 ETF联接A", "006327", "公募基金", "CNY", Decimal("100000"), Decimal("1.15"), Decimal("1.06"), Decimal("-0.038"), Decimal("0.011"), "东方财富"),
    DemoAsset("Bitcoin", "BTC-USDT", "数字货币", "USDT", Decimal("0.38"), Decimal("78000"), Decimal("92000"), Decimal("0.082"), Decimal("0.032"), "OKX"),
    DemoAsset("现金人民币", "CNY", "现金", "CNY", Decimal("160000"), Decimal("1"), Decimal("1"), Decimal("0"), Decimal("0"), "手工价格", "手工价格"),
    DemoAsset("现金美元", "USD", "现金", "USD", Decimal("12000"), Decimal("1"), Decimal("1"), Decimal("0"), Decimal("0"), "手工价格", "手工价格"),
)


def parse_arguments() -> argparse.Namespace:
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=root / "DemoData" / "Portfolix-Demo-Portfolio-30D.zip",
        help="Destination ZIP path.",
    )
    parser.add_argument(
        "--end-date",
        type=date.fromisoformat,
        default=date.today(),
        help="Last snapshot day in YYYY-MM-DD format (default: today).",
    )
    parser.add_argument(
        "--days",
        type=int,
        default=30,
        help="Number of visible portfolio history days (default: 30).",
    )
    return parser.parse_args()


def decimal_text(value: Decimal, places: int = 8) -> str:
    quantum = Decimal(1).scaleb(-places)
    normalized = value.quantize(quantum, rounding=ROUND_HALF_UP)
    text = format(normalized, "f").rstrip("0").rstrip(".")
    return text if text and text != "-0" else "0"


def timestamp(day: date, hour: int = 8) -> str:
    moment = datetime(day.year, day.month, day.day, hour, tzinfo=timezone.utc)
    return moment.isoformat().replace("+00:00", "Z")


def market_value_cny(asset: DemoAsset, price: Decimal) -> Decimal:
    return asset.quantity * price / RATES_FROM_CNY[asset.currency]


def price_series(asset: DemoAsset, days: list[date], index: int) -> list[Decimal]:
    if asset.month_return == 0:
        return [asset.final_price for _ in days]

    trading_indexes = [
        offset
        for offset, day in enumerate(days)
        if asset.trades_on_weekends or day.weekday() < 5
    ]
    start_price = asset.final_price / (Decimal("1") + asset.month_return)
    rng = random.Random(SEED + index * 7919)
    phase = rng.uniform(0, math.tau)
    secondary_phase = rng.uniform(0, math.tau)
    prices: list[Decimal] = []
    active_step = 0
    last_price = start_price
    denominator = max(1, len(trading_indexes) - 1)

    for offset, day in enumerate(days):
        is_trading_day = asset.trades_on_weekends or day.weekday() < 5
        if is_trading_day:
            progress = Decimal(active_step) / Decimal(denominator)
            progress_float = float(progress)
            bridge = math.sin(math.pi * progress_float)
            wave = (
                math.sin(progress_float * math.tau * 2.2 + phase)
                + 0.45 * math.sin(progress_float * math.tau * 4.7 + secondary_phase)
            )
            baseline = start_price + (asset.final_price - start_price) * progress
            variation = asset.final_price * asset.volatility * Decimal(str(bridge * wave))
            last_price = max(Decimal("0.00000001"), baseline + variation)
            active_step += 1
        prices.append(last_price)

    prices[-1] = asset.final_price
    return prices


def json_bytes(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")


def build_package(end_date: date, visible_days: int) -> dict[str, bytes]:
    if not 7 <= visible_days <= 365:
        raise ValueError("--days must be between 7 and 365")

    # One seed day is included so the first visible day has a daily P&L value.
    dates = [end_date - timedelta(days=visible_days - offset) for offset in range(visible_days + 1)]
    series_by_symbol = {
        asset.symbol: price_series(asset, dates, index)
        for index, asset in enumerate(ASSETS)
    }
    created_at = timestamp(dates[0])
    updated_at = timestamp(end_date)
    holdings: list[dict[str, object]] = []
    asset_snapshots: list[dict[str, object]] = []
    total_cost_cny = sum(
        (market_value_cny(asset, asset.average_cost) for asset in ASSETS),
        Decimal("0"),
    )

    for asset in ASSETS:
        prices = series_by_symbol[asset.symbol]
        latest_price = prices[-1]
        total_cost = asset.quantity * asset.average_cost
        latest_market_value = market_value_cny(asset, latest_price)
        profit_rate = (
            (latest_price - asset.average_cost) / asset.average_cost * Decimal("100")
            if asset.average_cost != 0
            else Decimal("0")
        )
        holdings.append(
            {
                "averageCost": decimal_text(asset.average_cost),
                "category": asset.category,
                "createdAt": created_at,
                "fetchedAt": updated_at,
                "freshness": asset.freshness,
                "id": asset.asset_id,
                "latestPrice": decimal_text(latest_price),
                "marketValueCNY": decimal_text(latest_market_value, 2),
                "name": asset.name,
                "profitRate": decimal_text(profit_rate, 4),
                "quantity": decimal_text(asset.quantity),
                "quoteCurrency": asset.currency,
                "quoteTime": updated_at,
                "source": asset.source,
                "symbol": asset.symbol,
                "totalCost": decimal_text(total_cost, 2),
                "updatedAt": updated_at,
                "weeklyTrend": [float(decimal_text(price, 6)) for price in prices[-7:]],
            }
        )

        for snapshot_day, price in zip(dates, prices):
            snapshot_time = timestamp(snapshot_day)
            asset_snapshots.append(
                {
                    "assetID": asset.asset_id,
                    "averageCost": decimal_text(asset.average_cost),
                    "category": asset.category,
                    "date": snapshot_day.isoformat(),
                    "freshness": asset.freshness,
                    "latestPrice": decimal_text(price),
                    "marketValueCNY": decimal_text(market_value_cny(asset, price), 2),
                    "name": asset.name,
                    "quantity": decimal_text(asset.quantity),
                    "quoteCurrency": asset.currency,
                    "quoteTime": snapshot_time,
                    "source": asset.source,
                    "symbol": asset.symbol,
                    "updatedAt": snapshot_time,
                }
            )

    portfolio_snapshots: list[dict[str, str]] = []
    for date_index, snapshot_day in enumerate(dates[1:], start=1):
        total_value = sum(
            (
                market_value_cny(asset, series_by_symbol[asset.symbol][date_index])
                for asset in ASSETS
            ),
            Decimal("0"),
        )
        total_profit = total_value - total_cost_cny
        profit_rate = total_profit / total_cost_cny * Decimal("100")
        portfolio_snapshots.append(
            {
                "date": snapshot_day.isoformat(),
                "profitRate": decimal_text(profit_rate, 4),
                "totalCostCNY": decimal_text(total_cost_cny, 2),
                "totalProfitCNY": decimal_text(total_profit, 2),
                "totalValueCNY": decimal_text(total_value, 2),
                "updatedAt": timestamp(snapshot_day),
            }
        )

    risk_profile = {
        "configured": True,
        "cryptoLimit": "12",
        "foreignCurrencyLimit": "55",
        "level": "稳健平衡",
        "liquidityMinimum": "10",
        "positionLimit": "25",
        "updatedAt": updated_at,
        "version": 1,
    }
    payloads = {
        "holdings.json": json_bytes(holdings),
        "daily_returns.json": json_bytes(portfolio_snapshots),
        "daily_asset_prices.json": json_bytes(asset_snapshots),
        "risk_profile.json": json_bytes(risk_profile),
    }
    record_counts = {
        "assetPriceSnapshots": len(asset_snapshots),
        "holdings": len(holdings),
        "portfolioSnapshots": len(portfolio_snapshots),
        "riskProfiles": 1,
    }
    manifest = {
        "appVersion": "demo-data-generator",
        "excludedData": [
            "smart analysis data",
            "API credentials and device-specific app settings",
        ],
        "exportedAt": updated_at,
        "files": [
            {
                "name": filename,
                "recordCount": record_counts[
                    {
                        "holdings.json": "holdings",
                        "daily_returns.json": "portfolioSnapshots",
                        "daily_asset_prices.json": "assetPriceSnapshots",
                        "risk_profile.json": "riskProfiles",
                    }[filename]
                ],
                "sha256": hashlib.sha256(payloads[filename]).hexdigest(),
            }
            for filename in DATA_FILENAMES
        ],
        "formatIdentifier": FORMAT_IDENTIFIER,
        "integrityAlgorithm": "SHA-256",
        "recordCounts": record_counts,
        "schemaVersion": SCHEMA_VERSION,
    }
    return {"manifest.json": json_bytes(manifest), **payloads}


def write_archive(files: dict[str, bytes], destination: Path, end_date: date) -> None:
    destination = destination.expanduser().resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        prefix="portfolix-demo-",
        suffix=".zip",
        dir=destination.parent,
        delete=False,
    ) as temporary_file:
        temporary_path = Path(temporary_file.name)

    try:
        with zipfile.ZipFile(
            temporary_path,
            mode="w",
            compression=zipfile.ZIP_DEFLATED,
            compresslevel=9,
        ) as archive:
            for filename in ("manifest.json", *DATA_FILENAMES):
                info = zipfile.ZipInfo(filename)
                info.date_time = (end_date.year, end_date.month, end_date.day, 8, 0, 0)
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o600 << 16
                archive.writestr(info, files[filename])
        os.chmod(temporary_path, 0o600)
        os.replace(temporary_path, destination)
    finally:
        temporary_path.unlink(missing_ok=True)


def main() -> None:
    arguments = parse_arguments()
    files = build_package(arguments.end_date, arguments.days)
    write_archive(files, arguments.output, arguments.end_date)
    print(arguments.output.expanduser().resolve())


if __name__ == "__main__":
    main()
