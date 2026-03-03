#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "requests>=2.28.0",
# ]
# ///
"""
Scan Polymarket for trading opportunities using configurable strategies.

Strategies:
  TAIL    -- Follow strong trends (probability > 0.60 or < 0.40) with high volume.
  BONDING -- Contrarian plays on overreactions (large bid-ask spread signals uncertainty).
  SPREAD  -- Arbitrage when YES + NO midpoints sum > 1.02.

Usage:
    uv run scan_markets.py [--strategy tail|bonding|spread|all] [--limit N]
                           [--min-volume N] [--min-liquidity N] [--json]
"""

import argparse
import json
import sys
import time
from typing import Any

import requests

GAMMA_API = "https://gamma-api.polymarket.com"
CLOB_API = "https://clob.polymarket.com"

# Strategy thresholds
TAIL_PROB_HIGH = 0.60
TAIL_PROB_LOW = 0.40
BONDING_SPREAD_THRESHOLD = 0.08  # 8% bid-ask spread signals overreaction
SPREAD_ARB_THRESHOLD = 1.02  # YES + NO > 1.02 = arbitrage


def fetch_active_markets(limit: int = 100, min_volume: float = 0, min_liquidity: float = 0) -> list[dict]:
    """Fetch active, open markets from the Gamma API."""
    markets: list[dict] = []
    offset = 0
    page_size = min(limit, 100)

    while len(markets) < limit:
        params: dict[str, Any] = {
            "active": "true",
            "closed": "false",
            "limit": page_size,
            "offset": offset,
        }
        if min_volume > 0:
            params["volume_num_min"] = min_volume
        if min_liquidity > 0:
            params["liquidity_num_min"] = min_liquidity

        try:
            resp = requests.get(f"{GAMMA_API}/markets", params=params, timeout=15)
            resp.raise_for_status()
            batch = resp.json()
        except requests.RequestException as e:
            print(f"Error fetching markets (offset={offset}): {e}", file=sys.stderr)
            break

        if not batch:
            break

        markets.extend(batch)
        offset += page_size

        if len(batch) < page_size:
            break

        # Be polite to the API
        time.sleep(0.2)

    return markets[:limit]


def fetch_clob_price(token_id: str) -> dict | None:
    """Fetch midpoint, best bid, and best ask for a token from the CLOB API."""
    try:
        mid_resp = requests.get(
            f"{CLOB_API}/midpoint", params={"token_id": token_id}, timeout=10
        )
        mid_resp.raise_for_status()
        midpoint = float(mid_resp.json().get("mid", 0))
    except (requests.RequestException, ValueError, KeyError):
        midpoint = 0.0

    try:
        buy_resp = requests.get(
            f"{CLOB_API}/price", params={"token_id": token_id, "side": "BUY"}, timeout=10
        )
        buy_resp.raise_for_status()
        best_bid = float(buy_resp.json().get("price", 0))
    except (requests.RequestException, ValueError, KeyError):
        best_bid = 0.0

    try:
        sell_resp = requests.get(
            f"{CLOB_API}/price", params={"token_id": token_id, "side": "SELL"}, timeout=10
        )
        sell_resp.raise_for_status()
        best_ask = float(sell_resp.json().get("price", 0))
    except (requests.RequestException, ValueError, KeyError):
        best_ask = 0.0

    if midpoint == 0 and best_bid == 0 and best_ask == 0:
        return None

    return {"midpoint": midpoint, "best_bid": best_bid, "best_ask": best_ask}


def parse_token_ids(market: dict) -> list[str]:
    """Extract CLOB token IDs from a Gamma market object."""
    raw = market.get("clobTokenIds")
    if not raw:
        return []
    if isinstance(raw, list):
        return raw
    if isinstance(raw, str):
        try:
            parsed = json.loads(raw)
            if isinstance(parsed, list):
                return parsed
        except (json.JSONDecodeError, TypeError):
            pass
    return []


def parse_outcomes(market: dict) -> list[str]:
    """Extract outcome labels from a Gamma market object."""
    raw = market.get("outcomes")
    if not raw:
        return ["YES", "NO"]
    if isinstance(raw, list):
        return raw
    if isinstance(raw, str):
        try:
            parsed = json.loads(raw)
            if isinstance(parsed, list):
                return parsed
        except (json.JSONDecodeError, TypeError):
            pass
    return ["YES", "NO"]


def analyse_market(market: dict) -> list[dict]:
    """Analyse a single market and return any detected opportunities."""
    token_ids = parse_token_ids(market)
    outcomes = parse_outcomes(market)

    if len(token_ids) < 2:
        return []

    # Fetch prices for YES (index 0) and NO (index 1) tokens
    yes_price = fetch_clob_price(token_ids[0])
    no_price = fetch_clob_price(token_ids[1]) if len(token_ids) > 1 else None

    if not yes_price:
        return []

    opportunities = []
    question = market.get("question", "Unknown")
    condition_id = market.get("conditionId", market.get("condition_id", ""))
    volume = float(market.get("volume", 0) or 0)
    liquidity = float(market.get("liquidity", 0) or 0)

    base_info = {
        "question": question,
        "condition_id": condition_id,
        "token_ids": token_ids,
        "outcomes": outcomes,
        "volume": volume,
        "liquidity": liquidity,
        "slug": market.get("slug", ""),
    }

    yes_mid = yes_price["midpoint"]
    yes_bid = yes_price["best_bid"]
    yes_ask = yes_price["best_ask"]

    no_mid = no_price["midpoint"] if no_price else 0.0
    no_bid = no_price["best_bid"] if no_price else 0.0
    no_ask = no_price["best_ask"] if no_price else 0.0

    # TAIL: Strong trend detection
    if yes_mid > TAIL_PROB_HIGH or yes_mid < TAIL_PROB_LOW:
        direction = "YES" if yes_mid > TAIL_PROB_HIGH else "NO"
        strength = abs(yes_mid - 0.5) * 2  # 0-1 scale
        opportunities.append({
            **base_info,
            "strategy": "TAIL",
            "signal": f"{'Strong YES' if direction == 'YES' else 'Strong NO'} momentum",
            "direction": direction,
            "strength": round(strength, 3),
            "yes_mid": yes_mid,
            "no_mid": no_mid,
            "yes_bid_ask": [yes_bid, yes_ask],
        })

    # BONDING: Overreaction / high uncertainty detection
    yes_spread = yes_ask - yes_bid if yes_ask > 0 and yes_bid > 0 else 0
    no_spread = no_ask - no_bid if no_ask > 0 and no_bid > 0 else 0
    max_spread = max(yes_spread, no_spread)

    if max_spread >= BONDING_SPREAD_THRESHOLD:
        # Wide spread = uncertainty = contrarian opportunity
        direction = "YES" if yes_mid < 0.5 else "NO"
        opportunities.append({
            **base_info,
            "strategy": "BONDING",
            "signal": f"Wide spread ({max_spread:.1%}) signals uncertainty",
            "direction": direction,
            "strength": round(min(max_spread / 0.20, 1.0), 3),
            "yes_mid": yes_mid,
            "no_mid": no_mid,
            "yes_spread": round(yes_spread, 4),
            "no_spread": round(no_spread, 4),
        })

    # SPREAD: Arbitrage detection
    if no_mid > 0:
        total = yes_mid + no_mid
        if total > SPREAD_ARB_THRESHOLD:
            excess = total - 1.0
            opportunities.append({
                **base_info,
                "strategy": "SPREAD",
                "signal": f"YES+NO = {total:.4f} (excess {excess:.4f})",
                "direction": "SELL_BOTH",
                "strength": round(min(excess / 0.05, 1.0), 3),
                "yes_mid": yes_mid,
                "no_mid": no_mid,
                "total": round(total, 4),
                "excess": round(excess, 4),
            })

    return opportunities


def main():
    parser = argparse.ArgumentParser(
        description="Scan Polymarket for paper trading opportunities"
    )
    parser.add_argument(
        "--strategy", "-s",
        choices=["tail", "bonding", "spread", "all"],
        default="all",
        help="Strategy filter (default: all)",
    )
    parser.add_argument(
        "--limit", "-l",
        type=int,
        default=50,
        help="Max markets to scan (default: 50)",
    )
    parser.add_argument(
        "--min-volume",
        type=float,
        default=0,
        help="Minimum market volume in USD",
    )
    parser.add_argument(
        "--min-liquidity",
        type=float,
        default=0,
        help="Minimum market liquidity in USD",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        dest="output_json",
        help="Output raw JSON (default: human-readable table)",
    )

    args = parser.parse_args()
    strategy_filter = args.strategy.upper() if args.strategy != "all" else None

    print(f"Scanning up to {args.limit} active Polymarket markets...", file=sys.stderr)
    markets = fetch_active_markets(
        limit=args.limit,
        min_volume=args.min_volume,
        min_liquidity=args.min_liquidity,
    )
    print(f"Fetched {len(markets)} markets. Analysing...", file=sys.stderr)

    all_opportunities: list[dict] = []
    for i, market in enumerate(markets):
        opps = analyse_market(market)
        if strategy_filter:
            opps = [o for o in opps if o["strategy"] == strategy_filter]
        all_opportunities.extend(opps)

        if (i + 1) % 10 == 0:
            print(f"  Processed {i + 1}/{len(markets)} markets, {len(all_opportunities)} opportunities found...", file=sys.stderr)
        # Rate limit: ~2 CLOB calls per market, stay under 10 req/s
        time.sleep(0.3)

    # Sort by signal strength descending
    all_opportunities.sort(key=lambda o: o.get("strength", 0), reverse=True)

    if args.output_json:
        print(json.dumps(all_opportunities, indent=2))
    else:
        if not all_opportunities:
            print("\nNo opportunities found matching criteria.")
        else:
            print(f"\n{'='*80}")
            print(f"  {len(all_opportunities)} OPPORTUNITIES FOUND")
            print(f"{'='*80}\n")
            for opp in all_opportunities:
                print(f"  [{opp['strategy']}] {opp['question']}")
                print(f"    Signal:    {opp['signal']}")
                print(f"    Direction: {opp['direction']}  |  Strength: {opp['strength']:.1%}")
                print(f"    YES mid: {opp.get('yes_mid', 0):.4f}  |  NO mid: {opp.get('no_mid', 0):.4f}")
                print(f"    Volume: ${opp['volume']:,.0f}  |  Liquidity: ${opp['liquidity']:,.0f}")
                print(f"    Slug: {opp['slug']}")
                print()

    print(f"\nScan complete. {len(all_opportunities)} opportunities across {len(markets)} markets.", file=sys.stderr)


if __name__ == "__main__":
    main()
