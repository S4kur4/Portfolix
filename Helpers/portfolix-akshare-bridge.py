#!/usr/bin/env python3
"""Minimal JSON-lines bridge between Portfolix and AKShare."""

from __future__ import annotations

import json
import math
import os
import re
import statistics
import sys
import time
import unicodedata
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date, timedelta
from pathlib import Path
from typing import Any

PROTOCOL_VERSION = "akshare-bridge.v1"
MAX_REQUEST_BYTES = 8192
MAX_RESULTS = 12
CACHE_TTL_SECONDS = 7 * 24 * 60 * 60
CACHE_PATH = Path.home() / "Library" / "Caches" / "Portfolix" / "akshare-assets-v5.json"
FUND_DAILY_CACHE_TTL_SECONDS = 10 * 60
FUND_DAILY_CACHE_PATH = Path.home() / "Library" / "Caches" / "Portfolix" / "akshare-fund-daily-v1.json"
MARKET_CACHE_TTL_SECONDS = 5 * 60
MAX_ANALYSIS_ASSETS = 8
ANALYSIS_CACHE_TTL_SECONDS = 6 * 60 * 60
ANALYSIS_CACHE_PATH = Path.home() / "Library" / "Caches" / "Portfolix" / "akshare-analysis-v1.json"
US_STOCK_NAME_ALIASES = [
    ("apple", "AAPL", "Apple"),
    ("苹果", "AAPL", "Apple"),
    ("microsoft", "MSFT", "Microsoft"),
    ("微软", "MSFT", "Microsoft"),
    ("nvidia", "NVDA", "Nvidia"),
    ("英伟达", "NVDA", "Nvidia"),
    ("tesla", "TSLA", "Tesla"),
    ("特斯拉", "TSLA", "Tesla"),
    ("amazon", "AMZN", "Amazon"),
    ("亚马逊", "AMZN", "Amazon"),
    ("google", "GOOGL", "Alphabet"),
    ("alphabet", "GOOGL", "Alphabet"),
    ("谷歌", "GOOGL", "Alphabet"),
    ("meta", "META", "Meta"),
    ("facebook", "META", "Meta"),
]


class BridgeError(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


def decimal_text(value: Any) -> str | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(number) or number <= 0:
        return None
    return format(number, ".10g")


def quote_time_text(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    if not text or text.lower() in {"nan", "nat", "none"}:
        return None
    return text[:32]


def row_quote_time(row: Any) -> str | None:
    for key in ("净值日期", "数据日期", "更新时间", "日期时间", "日期", "date", "datetime", "时间"):
        try:
            value = row.get(key)
        except Exception:
            value = None
        text = quote_time_text(value)
        if text:
            return text
    return quote_time_text(getattr(row, "name", None))


def json_safe_value(value: Any) -> Any:
    if value is None:
        return None
    if isinstance(value, dict):
        return {str(key): json_safe_value(item) for key, item in value.items()}
    if isinstance(value, list):
        return [json_safe_value(item) for item in value]
    if isinstance(value, tuple):
        return [json_safe_value(item) for item in value]
    if isinstance(value, (str, int, bool)):
        return value
    if isinstance(value, float):
        return value if math.isfinite(value) else None
    if hasattr(value, "item"):
        try:
            return json_safe_value(value.item())
        except Exception:
            pass
    if hasattr(value, "isoformat"):
        try:
            return value.isoformat()
        except Exception:
            pass
    return str(value)


def normalized_hk_symbol(value: Any) -> str:
    digits = str(value).strip().split(".")[0].lstrip("0") or "0"
    return f"{digits.zfill(4)}.HK"


def normalized_us_symbol(value: Any) -> str:
    symbol = str(value).strip().upper()
    return symbol.split(".", 1)[-1] if "." in symbol else symbol


def normalized_search_text(value: Any) -> str:
    return unicodedata.normalize("NFKC", str(value)).strip().casefold()


def is_exchange_traded_fund_symbol(value: Any) -> bool:
    symbol = str(value).strip()
    return bool(re.fullmatch(r"(159|510|511|512|513|515|516|517|518|520|560|561|562|563|564|588|589)\d{3}", symbol))


def b_share_currency(symbol: Any) -> str:
    text = str(symbol).strip()
    return "USD" if text.startswith("900") else "HKD"


def candidate(
    *,
    name: Any,
    symbol: Any,
    category: str,
    currency: str,
    price: Any = None,
    source: str = "eastmoney",
    quote_time: Any = None,
) -> dict[str, Any]:
    return {
        "name": str(name).strip(),
        "symbol": str(symbol).strip().upper(),
        "category": category,
        "currency": currency,
        "latest_price": decimal_text(price),
        "upstream_source": source,
        "quote_time": quote_time_text(quote_time),
    }


def import_akshare():
    try:
        import akshare as ak  # type: ignore
    except ImportError as error:
        raise BridgeError(
            "dependency_unavailable",
            "本地行情组件运行时尚未安装，请先配置内置 Helper。",
        ) from error
    return ak


def fetch_catalog() -> list[dict[str, Any]]:
    ak = import_akshare()
    assets: list[dict[str, Any]] = []

    try:
        for _, row in ak.stock_info_a_code_name().iterrows():
            assets.append(
                candidate(
                    name=row.get("name", row.get("名称", "")),
                    symbol=row.get("code", row.get("代码", "")),
                    category="A 股",
                    currency="CNY",
                )
            )
    except Exception:
        pass

    try:
        for _, row in ak.stock_info_bj_name_code().iterrows():
            assets.append(
                candidate(
                    name=row.get("证券简称", ""),
                    symbol=row.get("证券代码", ""),
                    category="A 股",
                    currency="CNY",
                )
            )
    except Exception:
        pass

    try:
        for _, row in ak.stock_zh_b_spot_em().iterrows():
            symbol = str(row.get("代码", "")).strip()
            assets.append(
                candidate(
                    name=row.get("名称", ""),
                    symbol=symbol,
                    category="B 股",
                    currency=b_share_currency(symbol),
                    source="eastmoney",
                )
            )
    except Exception:
        pass

    try:
        for _, row in ak.fund_name_em().iterrows():
            symbol = str(row.get("基金代码", "")).strip()
            category = "A 股" if is_exchange_traded_fund_symbol(symbol) else "公募基金"
            assets.append(
                candidate(
                    name=row.get("基金简称", ""),
                    symbol=symbol,
                    category=category,
                    currency="CNY",
                )
            )
    except Exception:
        pass

    filtered_assets = [asset for asset in assets if asset["name"] and asset["symbol"]]
    if not filtered_assets:
        raise BridgeError("upstream_error", "本地行情组件暂时无法返回资产目录。")
    return filtered_assets


def load_catalog() -> list[dict[str, Any]]:
    try:
        if CACHE_PATH.exists():
            return json.loads(CACHE_PATH.read_text(encoding="utf-8"))
    except (OSError, ValueError, json.JSONDecodeError):
        pass

    assets = fetch_catalog()
    try:
        CACHE_PATH.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        CACHE_PATH.write_text(json.dumps(assets, ensure_ascii=False), encoding="utf-8")
        os.chmod(CACHE_PATH, 0o600)
    except OSError:
        pass
    return assets


def load_fund_daily_rows() -> list[dict[str, Any]]:
    try:
        if FUND_DAILY_CACHE_PATH.exists() and time.time() - FUND_DAILY_CACHE_PATH.stat().st_mtime < FUND_DAILY_CACHE_TTL_SECONDS:
            return json.loads(FUND_DAILY_CACHE_PATH.read_text(encoding="utf-8"))
    except (OSError, ValueError, json.JSONDecodeError):
        pass

    ak = import_akshare()
    rows = json_safe_value(ak.fund_open_fund_daily_em().to_dict(orient="records"))
    try:
        FUND_DAILY_CACHE_PATH.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        FUND_DAILY_CACHE_PATH.write_text(json.dumps(rows, ensure_ascii=False), encoding="utf-8")
        os.chmod(FUND_DAILY_CACHE_PATH, 0o600)
    except OSError:
        pass
    return rows


def load_market_rows(cache_name: str, fetcher: Any) -> list[dict[str, Any]]:
    cache_path = market_cache_path(cache_name)
    cached = cached_market_rows(cache_name, max_age=MARKET_CACHE_TTL_SECONDS)
    if cached is not None:
        return cached
    stale_cached = cached_market_rows(cache_name)

    try:
        rows = json_safe_value(fetcher().to_dict(orient="records"))
    except Exception:
        if stale_cached is not None:
            return stale_cached
        raise
    try:
        cache_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        cache_path.write_text(json.dumps(rows, ensure_ascii=False), encoding="utf-8")
        os.chmod(cache_path, 0o600)
    except OSError:
        pass
    return rows


def market_cache_path(cache_name: str) -> Path:
    return Path.home() / "Library" / "Caches" / "Portfolix" / f"{cache_name}.json"


def cached_market_rows(cache_name: str, max_age: int | None = None) -> list[dict[str, Any]] | None:
    cache_path = market_cache_path(cache_name)
    try:
        if not cache_path.exists():
            return None
        if max_age is not None and time.time() - cache_path.stat().st_mtime >= max_age:
            return None
        return json.loads(cache_path.read_text(encoding="utf-8"))
    except (OSError, ValueError, json.JSONDecodeError):
        return None


def first_value(row: dict[str, Any], *keys: str) -> Any:
    for key in keys:
        value = row.get(key)
        if value is not None and str(value).strip():
            return value
    return None


def row_symbol(row: dict[str, Any]) -> str:
    return str(first_value(row, "代码", "code", "证券代码", "基金代码") or "").strip().upper()


def row_name(row: dict[str, Any]) -> str:
    return str(first_value(row, "名称", "中文名称", "证券简称", "基金简称", "name") or "").strip()


def a_stock_name(symbol: str) -> str:
    rows = cached_market_rows("akshare-a-name-code-v1") or []
    if not rows:
        ak = import_akshare()
        rows = safe_market_rows("akshare-a-name-code-v1", ak.stock_info_a_code_name)
    for row in rows:
        if row_symbol(row) == symbol.strip().upper():
            return row_name(row)
    return ""


def cached_symbol_name(cache_name: str, symbol: str, *, normalize: Any | None = None) -> str:
    expected = normalize(symbol) if normalize else symbol.strip().upper()
    for row in cached_market_rows(cache_name) or []:
        current = row_symbol(row)
        current = normalize(current) if normalize else current
        if current == expected:
            return row_name(row)
    return ""


def hk_stock_name(symbol: str) -> str:
    return cached_symbol_name(
        "akshare-sina-hk-spot-v1",
        symbol,
        normalize=lambda value: str(value).strip().upper().removesuffix(".HK").lstrip("0") or "0",
    )


def b_stock_name(symbol: str) -> str:
    return cached_symbol_name("akshare-eastmoney-b-spot-v1", symbol)


def etf_name(symbol: str) -> str:
    return cached_symbol_name("akshare-eastmoney-etf-spot-v1", symbol)


def us_stock_alias_name(symbol: str) -> str:
    normalized = normalized_us_symbol(symbol)
    for _, alias_symbol, name in US_STOCK_NAME_ALIASES:
        if alias_symbol == normalized:
            return name
    return ""


def market_quote_candidate(symbol: str, category: str, fallback_name: str = "") -> dict[str, Any] | None:
    ak = import_akshare()
    normalized = symbol.strip().upper()
    if category == "A 股":
        rows = safe_market_rows("akshare-eastmoney-a-spot-v1", ak.stock_zh_a_spot_em)
        expected_symbol = normalized
        currency = "CNY"
    elif category == "港股":
        rows = safe_market_rows("akshare-eastmoney-hk-spot-v1", ak.stock_hk_spot_em)
        expected_symbol = normalized.removesuffix(".HK").lstrip("0") or "0"
        currency = "HKD"
    elif category == "美股":
        rows = safe_market_rows("akshare-eastmoney-us-spot-v1", ak.stock_us_spot_em)
        expected_symbol = normalized_us_symbol(normalized)
        currency = "USD"
    elif category == "B 股":
        rows = safe_market_rows("akshare-eastmoney-b-spot-v1", ak.stock_zh_b_spot_em)
        expected_symbol = normalized
        currency = b_share_currency(normalized)
    else:
        return None

    for row in rows:
        current_symbol = row_symbol(row)
        if category == "港股":
            current_symbol = current_symbol.removesuffix(".HK").lstrip("0") or "0"
        else:
            current_symbol = normalized_us_symbol(current_symbol) if category == "美股" else current_symbol
        if current_symbol != expected_symbol:
            continue
        price = decimal_text(first_value(row, "最新价", "价格", "收盘", "close"))
        if not price:
            return None
        display_symbol = normalized_hk_symbol(expected_symbol) if category == "港股" else expected_symbol
        return candidate(
            name=row_name(row) or fallback_name or display_symbol,
            symbol=display_symbol,
            category=category,
            currency=currency,
            price=price,
            source="eastmoney",
            quote_time=row_quote_time(row),
        )
    return None


def eastmoney_bj_stock_candidate(symbol: str, fallback_name: str = "") -> dict[str, Any] | None:
    ak = import_akshare()
    normalized = symbol.strip().upper()
    if not re.fullmatch(r"9\d{5}", normalized):
        return None
    rows = safe_market_rows("akshare-eastmoney-bj-a-spot-v1", ak.stock_bj_a_spot_em)
    for row in rows:
        if row_symbol(row) != normalized:
            continue
        price = decimal_text(first_value(row, "最新价", "价格", "收盘", "close"))
        if not price:
            return None
        return candidate(
            name=row_name(row) or fallback_name or normalized,
            symbol=normalized,
            category="A 股",
            currency="CNY",
            price=price,
            source="eastmoney",
            quote_time=row_quote_time(row),
        )
    return None


def eastmoney_etf_spot_candidate(symbol: str, fallback_name: str = "") -> dict[str, Any] | None:
    ak = import_akshare()
    normalized = symbol.strip().upper()
    if not is_exchange_traded_fund_symbol(normalized):
        return None
    rows = safe_market_rows("akshare-eastmoney-etf-spot-v1", ak.fund_etf_spot_em)
    for row in rows:
        current_symbol = row_symbol(row)
        if current_symbol != normalized:
            continue
        price = decimal_text(first_value(row, "最新价", "价格", "收盘", "close"))
        if not price:
            return None
        return candidate(
            name=row_name(row) or fallback_name or normalized,
            symbol=normalized,
            category="A 股",
            currency="CNY",
            price=price,
            source="eastmoney",
            quote_time=row_quote_time(row),
        )
    return None


def safe_market_rows(cache_name: str, fetcher: Any) -> list[dict[str, Any]]:
    try:
        return load_market_rows(cache_name, fetcher)
    except Exception:
        return []


def sina_a_daily_candidate(symbol: str, fallback_name: str = "") -> dict[str, Any] | None:
    ak = import_akshare()
    market_symbol = f"{'sh' if symbol.startswith('6') else 'sz'}{symbol}"
    try:
        rows = ak.stock_zh_a_daily(symbol=market_symbol)
    except Exception:
        return None
    if rows.empty:
        return None
    row = rows.iloc[-1]
    return candidate(
        name=fallback_name or symbol,
        symbol=symbol,
        category="A 股",
        currency="CNY",
        price=row.get("close"),
        source="sina",
        quote_time=row_quote_time(row),
    )


def sina_hk_spot_candidate(symbol: str, fallback_name: str = "") -> dict[str, Any] | None:
    ak = import_akshare()
    expected_symbol = symbol.strip().upper().removesuffix(".HK").lstrip("0") or "0"
    rows = safe_market_rows("akshare-sina-hk-spot-v1", ak.stock_hk_spot)
    for row in rows:
        current_symbol = row_symbol(row).lstrip("0") or "0"
        if current_symbol != expected_symbol:
            continue
        display_symbol = normalized_hk_symbol(expected_symbol)
        return candidate(
            name=row_name(row) or fallback_name or display_symbol,
            symbol=display_symbol,
            category="港股",
            currency="HKD",
            price=first_value(row, "最新价", "价格", "收盘", "close"),
            source="sina",
            quote_time=row_quote_time(row),
        )
    return None


def sina_hk_daily_candidate(symbol: str, fallback_name: str = "") -> dict[str, Any] | None:
    ak = import_akshare()
    expected_symbol = symbol.strip().upper().removesuffix(".HK").zfill(5)
    try:
        rows = ak.stock_hk_daily(symbol=expected_symbol)
    except Exception:
        return None
    if rows.empty:
        return None
    row = rows.iloc[-1]
    display_symbol = normalized_hk_symbol(expected_symbol)
    return candidate(
        name=fallback_name or display_symbol,
        symbol=display_symbol,
        category="港股",
        currency="HKD",
        price=row.get("close"),
        source="sina",
        quote_time=row_quote_time(row),
    )


def sina_us_daily_candidate(symbol: str, fallback_name: str = "") -> dict[str, Any] | None:
    ak = import_akshare()
    expected_symbol = normalized_us_symbol(symbol)
    try:
        rows = ak.stock_us_daily(symbol=expected_symbol)
    except Exception:
        return None
    if rows.empty:
        return None
    row = rows.iloc[-1]
    return candidate(
        name=fallback_name or expected_symbol,
        symbol=expected_symbol,
        category="美股",
        currency="USD",
        price=row.get("close"),
        source="sina",
        quote_time=row_quote_time(row),
    )


def stock_quote_candidate(symbol: str, category: str, fallback_name: str = "") -> dict[str, Any] | None:
    if category == "A 股":
        if re.fullmatch(r"9\d{5}", symbol.strip().upper()):
            return eastmoney_bj_stock_candidate(symbol, fallback_name) or market_quote_candidate(symbol, category, fallback_name)
        if is_exchange_traded_fund_symbol(symbol):
            return eastmoney_etf_spot_candidate(symbol, fallback_name) or market_quote_candidate(symbol, category, fallback_name)
        fallback_name = fallback_name or a_stock_name(symbol)
        return (
            sina_a_daily_candidate(symbol, fallback_name)
            or eastmoney_etf_spot_candidate(symbol, fallback_name)
            or market_quote_candidate(symbol, category, fallback_name)
        )
    if category == "港股":
        return (
            sina_hk_spot_candidate(symbol, fallback_name)
            or sina_hk_daily_candidate(symbol, fallback_name)
            or market_quote_candidate(symbol, category, fallback_name)
        )
    if category == "美股":
        return sina_us_daily_candidate(symbol, fallback_name) or market_quote_candidate(symbol, category, fallback_name)
    if category == "B 股":
        return market_quote_candidate(symbol, category, fallback_name)
    return None


def latest_fund_daily_candidate(symbol: str, fallback_name: str) -> dict[str, Any] | None:
    for row in load_fund_daily_rows():
        if str(row.get("基金代码", "")).strip() != symbol:
            continue

        dated_value_columns = []
        for key in row.keys():
            match = re.fullmatch(r"(\d{4}-\d{2}-\d{2})-单位净值", str(key))
            if match:
                dated_value_columns.append((match.group(1), key))
        dated_value_columns.sort(reverse=True)

        for quote_date, key in dated_value_columns:
            price = decimal_text(row.get(key))
            if price:
                return candidate(
                    name=row.get("基金简称", fallback_name),
                    symbol=symbol,
                    category="公募基金",
                    currency="CNY",
                    price=price,
                    source="eastmoney",
                    quote_time=quote_date,
                )
    return None


def ths_fund_candidate(symbol: str, fallback_name: str) -> dict[str, Any] | None:
    ak = import_akshare()
    try:
        rows = ak.fund_info_ths(symbol=symbol).to_dict(orient="records")
    except Exception:
        return None

    name = fallback_name
    price: Any = None
    quote_time: Any = None
    for row in rows:
        field = str(row.get("字段", "")).strip()
        value = row.get("值")
        if field in {"基金简称", "基金全称"} and value:
            name = str(value).strip()
        if field in {"最新净值", "单位净值", "基金净值", "净值"}:
            price = value
        if field in {"净值日期", "更新日期", "日期"}:
            quote_time = value
    if not decimal_text(price):
        return None
    return candidate(
        name=name or symbol,
        symbol=symbol,
        category="公募基金",
        currency="CNY",
        price=price,
        source="ths",
        quote_time=quote_time,
    )


def fund_quote_candidate(symbol: str, fallback_name: str) -> dict[str, Any] | None:
    return latest_fund_daily_candidate(symbol, fallback_name) or ths_fund_candidate(symbol, fallback_name)


def search_assets(params: dict[str, Any]) -> dict[str, Any]:
    keyword = str(params.get("keyword", "")).strip()
    if not 1 <= len(keyword) <= 64:
        raise BridgeError("invalid_keyword", "搜索关键字长度无效。")

    folded = normalized_search_text(keyword)
    catalog_matches = [
        asset
        for asset in load_catalog()
        if asset.get("category") != "数字货币"
        and (folded in normalized_search_text(asset["name"]) or folded in normalized_search_text(asset["symbol"]))
    ]
    matches = list(catalog_matches)
    if not catalog_matches:
        matches.extend(direct_name_candidates(keyword))
        matches.extend(direct_symbol_candidates(keyword))
    elif should_include_us_alias_candidate(keyword):
        matches.extend(direct_name_candidates(keyword))
    matches = merged_candidates(matches)
    matches.sort(
        key=lambda asset: (
            not asset["symbol"].casefold().startswith(folded),
            not normalized_search_text(asset["name"]).startswith(folded),
            asset["category"],
            asset["symbol"],
        )
    )
    return {"candidates": matches[:MAX_RESULTS]}


def should_include_us_alias_candidate(keyword: str) -> bool:
    folded = normalized_search_text(keyword)
    return any(folded in alias or alias in folded for alias, _, _ in US_STOCK_NAME_ALIASES)


def direct_name_candidates(keyword: str) -> list[dict[str, Any]]:
    folded = normalized_search_text(keyword)
    if len(folded) < 2:
        return []

    matches: list[dict[str, Any]] = []

    def rows_for(cache_name: str, fetcher_name: str) -> list[dict[str, Any]]:
        rows = cached_market_rows(cache_name) or []
        if rows:
            return rows
        ak = import_akshare()
        return safe_market_rows(cache_name, getattr(ak, fetcher_name))

    def append_stock_matches(rows: list[dict[str, Any]], category: str, limit: int = 4) -> None:
        added = 0
        for row in rows:
            name = row_name(row)
            symbol = row_symbol(row)
            if not name or not symbol:
                continue
            if folded not in normalized_search_text(name) and folded not in normalized_search_text(symbol):
                continue
            currency = "CNY"
            display_symbol = symbol
            if category == "B 股":
                currency = b_share_currency(symbol)
            elif category == "港股":
                currency = "HKD"
                display_symbol = normalized_hk_symbol(symbol)
            matches.append(
                candidate(
                    name=name,
                    symbol=display_symbol,
                    category=category,
                    currency=currency,
                    source=primary_source_for_category(category),
                )
            )
            added += 1
            if added >= limit:
                break

    append_stock_matches(rows_for("akshare-a-name-code-v1", "stock_info_a_code_name"), "A 股")
    append_stock_matches(rows_for("akshare-eastmoney-bj-name-code-v1", "stock_info_bj_name_code"), "A 股")
    append_stock_matches(rows_for("akshare-eastmoney-b-spot-v1", "stock_zh_b_spot_em"), "B 股")
    append_stock_matches(rows_for("akshare-sina-hk-spot-v1", "stock_hk_spot"), "港股")
    for alias, symbol, name in US_STOCK_NAME_ALIASES:
        if folded in alias or alias in folded:
            matches.append(
                candidate(
                    name=name,
                    symbol=symbol,
                    category="美股",
                    currency="USD",
                    source="sina",
                )
            )

    return matches


def primary_source_for_category(category: str) -> str:
    if category in {"A 股", "港股", "美股"}:
        return "sina"
    return "eastmoney"


def merged_candidates(candidates: list[dict[str, Any]]) -> list[dict[str, Any]]:
    merged: dict[tuple[str, str], dict[str, Any]] = {}
    for asset in candidates:
        key = (asset["category"], asset["symbol"])
        current = merged.get(key)
        if not current:
            merged[key] = asset
            continue
        combined = dict(current)
        if combined.get("name") == combined.get("symbol") and asset.get("name") and asset.get("name") != asset.get("symbol"):
            combined["name"] = asset["name"]
        if asset.get("latest_price"):
            combined["latest_price"] = asset.get("latest_price")
            combined["upstream_source"] = asset.get("upstream_source")
            combined["quote_time"] = asset.get("quote_time")
        merged[key] = combined
    return list(merged.values())


def direct_symbol_candidates(keyword: str) -> list[dict[str, Any]]:
    matches: list[dict[str, Any]] = []
    normalized = unicodedata.normalize("NFKC", keyword).strip().upper()

    if re.fullmatch(r"\d{1,5}\.HK", normalized):
        display_symbol = normalized_hk_symbol(normalized)
        matches.append(
            candidate(
                name=hk_stock_name(display_symbol) or display_symbol,
                symbol=display_symbol,
                category="港股",
                currency="HKD",
                source="sina",
            )
        )

    if re.fullmatch(r"920\d{3}", normalized):
        matches.append(
            candidate(
                name=normalized,
                symbol=normalized,
                category="A 股",
                currency="CNY",
                source="eastmoney",
            )
        )

    if re.fullmatch(r"(900|200)\d{3}", normalized):
        matches.append(
            candidate(
                name=b_stock_name(normalized) or normalized,
                symbol=normalized,
                category="B 股",
                currency=b_share_currency(normalized),
                source="eastmoney",
            )
        )

    if re.fullmatch(r"\d{6}", normalized) and is_exchange_traded_fund_symbol(normalized):
        matches.append(
            candidate(
                name=etf_name(normalized) or normalized,
                symbol=normalized,
                category="A 股",
                currency="CNY",
                source="eastmoney",
            )
        )

    if re.fullmatch(r"[036]\d{5}", normalized):
        matches.append(
            candidate(
                name=a_stock_name(normalized) or normalized,
                symbol=normalized,
                category="A 股",
                currency="CNY",
                source="sina",
            )
        )

    if keyword.strip() == normalized and re.fullmatch(r"[A-Z][A-Z0-9.-]{0,11}", normalized):
        matches.append(
            candidate(
                name=us_stock_alias_name(normalized) or normalized,
                symbol=normalized_us_symbol(normalized),
                category="美股",
                currency="USD",
                source="sina",
            )
        )

    return matches


def resolve_asset(params: dict[str, Any]) -> dict[str, Any]:
    symbol = str(params.get("symbol", "")).strip().upper()
    category = str(params.get("category", "")).strip()
    fallback_name = str(params.get("name", "")).strip()
    if not symbol or category not in {"A 股", "B 股", "港股", "美股", "公募基金"}:
        raise BridgeError("invalid_asset", "资产代码或类别无效。")

    if category in {"A 股", "B 股", "港股", "美股"}:
        resolved = stock_quote_candidate(symbol, category, fallback_name)
        if resolved:
            return {"candidate": resolved}

    for asset in load_catalog():
        if asset["category"] == category and asset["symbol"] == symbol:
            if category == "A 股" and (asset.get("latest_price") is None or asset.get("quote_time") is None):
                resolved = stock_quote_candidate(symbol, category, asset.get("name", ""))
                if resolved:
                    asset = resolved
            elif category == "公募基金" and (asset.get("latest_price") is None or asset.get("quote_time") is None):
                resolved = fund_quote_candidate(symbol, asset.get("name", ""))
                if resolved:
                    asset = resolved
            return {"candidate": asset}
    raise BridgeError("asset_not_found", "未找到对应资产。")


def bounded_text(value: Any, limit: int = 120) -> str | None:
    if value is None:
        return None
    text = unicodedata.normalize("NFKC", str(value)).strip()
    if not text or text.casefold() in {"nan", "nat", "none", "--", "-"}:
        return None
    return text[:limit]


def finite_number(value: Any) -> float | None:
    if value is None:
        return None
    text = str(value).replace(",", "").replace("%", "").strip()
    try:
        number = float(text)
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) else None


def matching_column(columns: list[Any], candidates: tuple[str, ...]) -> Any | None:
    for column in columns:
        folded = str(column).strip().casefold()
        if any(candidate.casefold() == folded for candidate in candidates):
            return column
    for column in columns:
        folded = str(column).strip().casefold()
        if any(candidate.casefold() in folded for candidate in candidates):
            return column
    return None


def frame_as_of(frame: Any) -> str | None:
    if frame is None or getattr(frame, "empty", True):
        return None
    row = frame.iloc[-1]
    return row_quote_time(row)


def history_metrics(frame: Any) -> tuple[list[dict[str, Any]], str | None]:
    if frame is None or getattr(frame, "empty", True):
        return [], None
    columns = list(frame.columns)
    close_column = matching_column(columns, ("收盘", "close", "单位净值", "累计净值"))
    if close_column is None:
        return [], frame_as_of(frame)
    closes = [finite_number(value) for value in frame[close_column].tolist()]
    closes = [value for value in closes if value is not None and value > 0]
    if len(closes) < 2:
        return [], frame_as_of(frame)
    as_of = frame_as_of(frame)
    metrics: list[dict[str, Any]] = []

    def append_metric(code: str, value: float, unit: str) -> None:
        if math.isfinite(value):
            metrics.append({"code": code, "value": round(value, 6), "unit": unit, "as_of": as_of})

    append_metric("latest_close", closes[-1], "quote_currency")
    for days in (20, 60, 120, 252):
        if len(closes) > days:
            append_metric(f"return_{days}d_pct", (closes[-1] / closes[-days - 1] - 1) * 100, "percent")
    recent = closes[-61:]
    if len(recent) >= 21:
        log_returns = [math.log(recent[index] / recent[index - 1]) for index in range(1, len(recent))]
        if len(log_returns) > 1:
            append_metric("annualized_volatility_60d_pct", statistics.stdev(log_returns) * math.sqrt(252) * 100, "percent")
    drawdown_prices = closes[-252:]
    peak = drawdown_prices[0]
    max_drawdown = 0.0
    for price in drawdown_prices:
        peak = max(peak, price)
        max_drawdown = min(max_drawdown, price / peak - 1)
    append_metric("max_drawdown_252d_pct", max_drawdown * 100, "percent")
    return metrics[:10], as_of


def selected_row_facts(
    frame: Any,
    endpoint: str,
    keywords: tuple[str, ...],
    *,
    newest_first: bool = True,
    limit: int = 10,
) -> list[dict[str, Any]]:
    if frame is None or getattr(frame, "empty", True):
        return []
    row = frame.iloc[0] if newest_first else frame.iloc[-1]
    as_of = row_quote_time(row)
    facts: list[dict[str, Any]] = []
    for column in frame.columns:
        label = bounded_text(column, 64)
        value = bounded_text(row.get(column), 120)
        if not label or not value or not any(keyword in label for keyword in keywords):
            continue
        facts.append(
            {
                "code": f"{endpoint}_{len(facts) + 1}",
                "label": label,
                "value": value,
                "as_of": as_of,
                "endpoint": endpoint,
            }
        )
        if len(facts) >= limit:
            break
    return facts


def financial_row_facts(frame: Any, endpoint: str, limit: int = 12) -> list[dict[str, Any]]:
    if frame is None or getattr(frame, "empty", True):
        return []
    labels = {
        "REPORT_DATE": "报告期",
        "OPERATE_INCOME": "营业收入（原币）",
        "OPERATE_INCOME_YOY": "营业收入同比",
        "PARENT_HOLDER_NETPROFIT": "归母净利润（原币）",
        "PARENT_HOLDER_NETPROFIT_YOY": "归母净利润同比",
        "BASIC_EPS": "基本每股收益",
        "GROSS_PROFIT_RATIO": "毛利率",
        "NET_PROFIT_RATIO": "净利率",
        "ROE_AVG": "平均净资产收益率",
        "ROA": "总资产收益率",
        "DEBT_ASSET_RATIO": "资产负债率",
        "CURRENT_RATIO": "流动比率",
        "CURRENCY_ABBR": "财报币种",
    }
    percent_columns = {
        "OPERATE_INCOME_YOY", "PARENT_HOLDER_NETPROFIT_YOY", "GROSS_PROFIT_RATIO",
        "NET_PROFIT_RATIO", "ROE_AVG", "ROA", "DEBT_ASSET_RATIO",
    }
    row = frame.iloc[0]
    as_of_value = bounded_text(row.get("REPORT_DATE"), 32)
    as_of = as_of_value[:10] if as_of_value else row_quote_time(row)
    facts: list[dict[str, Any]] = []
    for column, label in labels.items():
        if column not in frame.columns:
            continue
        raw_value = row.get(column)
        number = finite_number(raw_value)
        value = format(number, ".6g") if number is not None else bounded_text(raw_value, 80)
        if not value:
            continue
        if column in percent_columns:
            value = f"{value}%"
        facts.append(
            {
                "code": f"{endpoint}_{column.casefold()}",
                "label": label,
                "value": value,
                "as_of": as_of,
                "endpoint": endpoint,
            }
        )
        if len(facts) >= limit:
            break
    return facts


def key_value_facts(
    frame: Any,
    endpoint: str,
    keywords: tuple[str, ...],
    *,
    limit: int = 10,
) -> list[dict[str, Any]]:
    if frame is None or getattr(frame, "empty", True) or len(frame.columns) < 2:
        return []
    columns = list(frame.columns)
    label_column = matching_column(columns, ("item", "项目", "指标", "资料类型")) or columns[0]
    value_column = matching_column(columns, ("value", "值", "内容", "资料值")) or columns[1]
    facts: list[dict[str, Any]] = []
    for _, row in frame.iterrows():
        label = bounded_text(row.get(label_column), 64)
        value = bounded_text(row.get(value_column), 120)
        if not label or not value or not any(keyword in label for keyword in keywords):
            continue
        facts.append(
            {
                "code": f"{endpoint}_{len(facts) + 1}",
                "label": label,
                "value": value,
                "as_of": None,
                "endpoint": endpoint,
            }
        )
        if len(facts) >= limit:
            break
    return facts


def fund_holdings(frame: Any, asset_type: str, limit: int = 6) -> list[dict[str, Any]]:
    if frame is None or getattr(frame, "empty", True):
        return []
    columns = list(frame.columns)
    name_column = matching_column(columns, ("股票名称", "债券名称", "名称"))
    symbol_column = matching_column(columns, ("股票代码", "债券代码", "代码"))
    weight_column = matching_column(columns, ("占净值比例", "占净值比", "持仓占比"))
    if name_column is None:
        return []
    holdings: list[dict[str, Any]] = []
    for _, row in frame.head(limit).iterrows():
        name = bounded_text(row.get(name_column), 80)
        if not name:
            continue
        holdings.append(
            {
                "asset_type": asset_type,
                "name": name,
                "symbol": bounded_text(row.get(symbol_column), 32) if symbol_column is not None else None,
                "weight_pct": finite_number(row.get(weight_column)) if weight_column is not None else None,
                "as_of": row_quote_time(row),
            }
        )
    return holdings


def safe_analysis_call(ak: Any, endpoint: str, limitations: list[str], **kwargs: Any) -> Any | None:
    function = getattr(ak, endpoint, None)
    if function is None:
        limitations.append(f"{endpoint} 在当前 AKShare 版本不可用")
        return None
    try:
        return function(**kwargs)
    except Exception:
        limitations.append(f"{endpoint} 查询失败")
        return None


def a_share_market_symbol(symbol: str) -> str:
    if symbol.startswith(("6", "9")):
        return f"{symbol}.SH"
    if symbol.startswith(("4", "8", "92")):
        return f"{symbol}.BJ"
    return f"{symbol}.SZ"


def enrich_asset(asset: dict[str, str]) -> dict[str, Any]:
    ak = import_akshare()
    symbol = asset["symbol"]
    category = asset["category"]
    endpoints: list[str] = []
    limitations: list[str] = []
    metrics: list[dict[str, Any]] = []
    facts: list[dict[str, Any]] = []
    holdings: list[dict[str, Any]] = []
    as_of: str | None = None

    def call(endpoint: str, **kwargs: Any) -> Any | None:
        frame = safe_analysis_call(ak, endpoint, limitations, **kwargs)
        if frame is not None and not getattr(frame, "empty", True):
            endpoints.append(endpoint)
        return frame

    financial_keywords = (
        "报告期", "净资产收益率", "总资产报酬率", "营业收入", "营业总收入", "净利润",
        "资产负债率", "基本每股收益", "每股经营现金流", "市盈率", "市净率", "股息率",
    )
    profile_keywords = (
        "行业", "上市时间", "总市值", "流通市值", "主营", "基金类型", "基金规模",
        "成立", "基金经理", "管理人", "跟踪标的", "业绩比较基准", "投资目标",
    )

    if category == "A 股":
        history = call("stock_zh_a_hist", symbol=symbol, period="daily", start_date="20240101", adjust="qfq", timeout=8)
        metrics, as_of = history_metrics(history)
        profile = call("stock_individual_info_em", symbol=symbol, timeout=8)
        facts.extend(key_value_facts(profile, "stock_individual_info_em", profile_keywords))
        financial = call("stock_financial_analysis_indicator_em", symbol=a_share_market_symbol(symbol), indicator="按报告期")
        financial_facts = financial_row_facts(financial, "stock_financial_analysis_indicator_em")
        if not financial_facts:
            financial_facts = selected_row_facts(financial, "stock_financial_analysis_indicator_em", financial_keywords)
        facts.extend(financial_facts)
    elif category == "B 股":
        market_symbol = ("sh" if symbol.startswith("9") else "sz") + symbol
        history = call("stock_zh_b_daily", symbol=market_symbol, start_date="20240101", adjust="qfq")
        metrics, as_of = history_metrics(history)
    elif category == "港股":
        hk_symbol = symbol.split(".", 1)[0].zfill(5)
        history = call("stock_hk_daily", symbol=hk_symbol, adjust="qfq")
        metrics, as_of = history_metrics(history)
        financial = call("stock_hk_financial_indicator_em", symbol=hk_symbol)
        facts.extend(financial_row_facts(financial, "stock_hk_financial_indicator_em"))
        facts.extend(selected_row_facts(financial, "stock_hk_financial_indicator_em", financial_keywords, limit=6))
        dividend = call("stock_hk_dividend_payout_em", symbol=hk_symbol)
        facts.extend(selected_row_facts(dividend, "stock_hk_dividend_payout_em", ("财政年度", "除净日", "派息", "股息"), limit=5))
    elif category == "美股":
        us_symbol = normalized_us_symbol(symbol)
        history = call("stock_us_daily", symbol=us_symbol, adjust="qfq")
        metrics, as_of = history_metrics(history)
        financial = call("stock_financial_us_analysis_indicator_em", symbol=us_symbol, indicator="年报")
        facts.extend(financial_row_facts(financial, "stock_financial_us_analysis_indicator_em"))
    elif category == "公募基金":
        history = call("fund_open_fund_info_em", symbol=symbol, indicator="单位净值走势", period="成立来")
        metrics, as_of = history_metrics(history)
        overview = call("fund_overview_em", symbol=symbol)
        overview_facts = key_value_facts(overview, "fund_overview_em", profile_keywords, limit=12)
        facts.extend(overview_facts)
        fund_type = " ".join(
            fact["value"] for fact in overview_facts if "类型" in fact["label"] or "投资目标" in fact["label"]
        )
        year = str(date.today().year)
        if "债" in fund_type:
            bond_hold = call("fund_portfolio_bond_hold_em", symbol=symbol, date=year)
            holdings.extend(fund_holdings(bond_hold, "bond", limit=8))
        else:
            stock_hold = call("fund_portfolio_hold_em", symbol=symbol, date=year)
            holdings.extend(fund_holdings(stock_hold, "stock", limit=8))
    facts = facts[:20]
    holdings = holdings[:10]
    has_evidence = bool(metrics or facts or holdings)
    status = "complete" if has_evidence and not limitations else "partial" if has_evidence else "unavailable"
    return {
        "position_ref": asset["position_ref"],
        "symbol": symbol,
        "category": category,
        "status": status,
        "as_of": as_of,
        "endpoints": endpoints[:12],
        "metrics": metrics[:16],
        "facts": facts,
        "holdings": holdings,
        "limitations": limitations[:12],
    }


def market_context_facts(categories: set[str]) -> tuple[list[dict[str, Any]], list[str]]:
    ak = import_akshare()
    facts: list[dict[str, Any]] = []
    limitations: list[str] = []

    def latest_facts(endpoint: str, keywords: tuple[str, ...], **kwargs: Any) -> None:
        frame = safe_analysis_call(ak, endpoint, limitations, **kwargs)
        if frame is None:
            return
        facts.extend(selected_row_facts(frame, endpoint, keywords, newest_first=False, limit=4))

    if categories.intersection({"A 股", "B 股", "港股", "公募基金"}):
        latest_facts("macro_china_lpr", ("日期", "LPR", "1Y", "5Y", "利率"))
    if "美股" in categories:
        latest_facts("macro_bank_usa_interest_rate", ("日期", "今值", "预测值", "前值", "利率"))
    if categories.intersection({"港股", "美股"}):
        latest_facts("forex_hist_em", ("日期", "收盘", "最新价"), symbol="USDCNH")
    return facts[:16], limitations[:8]


def load_analysis_cache() -> dict[str, Any]:
    try:
        payload = json.loads(ANALYSIS_CACHE_PATH.read_text(encoding="utf-8"))
        return payload if isinstance(payload, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def save_analysis_cache(cache: dict[str, Any]) -> None:
    try:
        ANALYSIS_CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
        ANALYSIS_CACHE_PATH.write_text(json.dumps(cache, ensure_ascii=False), encoding="utf-8")
    except OSError:
        pass


def enrich_assets(params: dict[str, Any]) -> dict[str, Any]:
    raw_assets = params.get("assets_json")
    if not isinstance(raw_assets, str) or len(raw_assets) > 7000:
        raise BridgeError("invalid_assets", "市场数据请求无效。")
    try:
        requested_assets = json.loads(raw_assets)
    except json.JSONDecodeError as error:
        raise BridgeError("invalid_assets", "市场数据请求无效。") from error
    if not isinstance(requested_assets, list) or not 1 <= len(requested_assets) <= MAX_ANALYSIS_ASSETS:
        raise BridgeError("invalid_assets", "市场数据请求数量无效。")

    allowed_categories = {"A 股", "B 股", "港股", "美股", "公募基金"}
    assets: list[dict[str, str]] = []
    for item in requested_assets:
        if not isinstance(item, dict):
            raise BridgeError("invalid_assets", "市场数据请求无效。")
        position_ref = str(item.get("position_ref", ""))
        symbol = str(item.get("symbol", "")).strip().upper()
        category = str(item.get("category", ""))
        if (
            not re.fullmatch(r"position_[0-9A-Fa-f-]{36}", position_ref)
            or not re.fullmatch(r"[A-Z0-9./:_-]{1,32}", symbol)
            or category not in allowed_categories
        ):
            raise BridgeError("invalid_assets", "市场数据请求包含无效资产。")
        assets.append({"position_ref": position_ref, "symbol": symbol, "category": category})

    cache = load_analysis_cache()
    now = time.time()
    category_set = {asset["category"] for asset in assets}
    context_key = "_market_context:" + ",".join(sorted(category_set))
    cached_context = cache.get(context_key)
    cached_market_facts: list[dict[str, Any]] | None = None
    cached_market_limitations: list[str] | None = None
    if isinstance(cached_context, dict) and now - float(cached_context.get("cached_at", 0)) < ANALYSIS_CACHE_TTL_SECONDS:
        if isinstance(cached_context.get("facts"), list) and isinstance(cached_context.get("limitations"), list):
            cached_market_facts = cached_context["facts"]
            cached_market_limitations = cached_context["limitations"]
    results: dict[str, dict[str, Any]] = {}
    pending: list[dict[str, str]] = []
    for asset in assets:
        key = f"{asset['category']}:{asset['symbol']}"
        cached = cache.get(key)
        if isinstance(cached, dict) and now - float(cached.get("cached_at", 0)) < ANALYSIS_CACHE_TTL_SECONDS:
            evidence = cached.get("evidence")
            if isinstance(evidence, dict):
                evidence = dict(evidence)
                evidence["position_ref"] = asset["position_ref"]
                results[asset["position_ref"]] = evidence
                continue
        pending.append(asset)

    context_task_count = 0 if cached_market_facts is not None else 1
    with ThreadPoolExecutor(max_workers=min(6, max(1, len(pending) + context_task_count))) as executor:
        future_assets = {executor.submit(enrich_asset, asset): asset for asset in pending}
        context_future = executor.submit(market_context_facts, category_set) if cached_market_facts is None else None
        for future in as_completed(future_assets):
            asset = future_assets[future]
            try:
                evidence = future.result()
            except Exception:
                evidence = {
                    "position_ref": asset["position_ref"],
                    "symbol": asset["symbol"],
                    "category": asset["category"],
                    "status": "unavailable",
                    "as_of": None,
                    "endpoints": [],
                    "metrics": [],
                    "facts": [],
                    "holdings": [],
                    "limitations": ["该资产的 AKShare 市场数据查询失败"],
                }
            results[asset["position_ref"]] = evidence
            key = f"{asset['category']}:{asset['symbol']}"
            if evidence["status"] in {"complete", "partial"}:
                cache[key] = {"cached_at": now, "evidence": {**evidence, "position_ref": ""}}
        if context_future is None:
            market_facts = cached_market_facts or []
            market_limitations = cached_market_limitations or []
        else:
            try:
                market_facts, market_limitations = context_future.result()
                if market_facts:
                    cache[context_key] = {
                        "cached_at": now,
                        "facts": market_facts,
                        "limitations": market_limitations,
                    }
            except Exception:
                market_facts, market_limitations = [], ["AKShare 宏观与汇率上下文查询失败"]

    save_analysis_cache(cache)
    ordered = [results[asset["position_ref"]] for asset in assets]
    available_count = sum(item["status"] in {"complete", "partial"} for item in ordered)
    all_assets_complete = all(item["status"] == "complete" for item in ordered)
    status = "complete" if all_assets_complete and not market_limitations else "partial" if available_count else "unavailable"
    return {
        "market_evidence": {
            "provider": "AKShare",
            "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "status": status,
            "assets": ordered,
            "market_facts": market_facts,
            "limitations": market_limitations,
        }
    }


OPERATIONS = {
    "search_assets": search_assets,
    "resolve_asset": resolve_asset,
    "enrich_assets": enrich_assets,
}


def response(request_id: str, *, data: Any = None, error: BridgeError | None = None) -> None:
    payload: dict[str, Any] = {
        "protocol_version": PROTOCOL_VERSION,
        "request_id": request_id,
        "status": "error" if error else "ok",
    }
    if error:
        payload["error"] = {"code": error.code, "message": error.message}
    else:
        payload["data"] = data
    sys.__stdout__.write(json.dumps(payload, ensure_ascii=False) + "\n")
    sys.__stdout__.flush()


def main() -> None:
    # Keep third-party provider logs away from the JSON protocol channel.
    sys.stdout = sys.stderr
    raw = sys.stdin.buffer.readline(MAX_REQUEST_BYTES + 1)
    if len(raw) > MAX_REQUEST_BYTES:
        response("", error=BridgeError("request_too_large", "请求过大。"))
        return

    request_id = ""
    try:
        request = json.loads(raw.decode("utf-8"))
        request_id = str(request.get("request_id", ""))[:64]
        if request.get("protocol_version") != PROTOCOL_VERSION:
            raise BridgeError("unsupported_protocol", "Helper 协议版本不受支持。")
        operation = request.get("operation")
        if operation not in OPERATIONS:
            raise BridgeError("unsupported_operation", "Helper 操作不受支持。")
        params = request.get("params")
        if not isinstance(params, dict):
            raise BridgeError("invalid_params", "Helper 参数无效。")
        response(request_id, data=OPERATIONS[operation](params))
    except BridgeError as error:
        response(request_id, error=error)
    except (UnicodeDecodeError, json.JSONDecodeError, TypeError, ValueError):
        response(request_id, error=BridgeError("invalid_request", "Helper 请求格式无效。"))
    except Exception:
        response(request_id, error=BridgeError("upstream_error", "本地行情组件查询失败，请稍后重试。"))


if __name__ == "__main__":
    main()
