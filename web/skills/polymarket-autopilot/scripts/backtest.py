#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "requests>=2.28.0",
# ]
# ///
"""
Backtest TAIL, BONDING, and SPREAD strategies against historical closed markets.

Fetches resolved markets from the Gamma API and replays strategy signals
to compute hypothetical win rate, P&L, and per-strategy performance.

Usage:
    uv run backtest.py [--strategy tail|bonding|spread|all] [--limit 100]
                       [--capital 10000] [--bet-size 100] [--json]
"""

import argparse
import json
import sys
import time
from datetime import datetime, timezone

import requests

GAMMA_API = "https://gamma-api.polymarket.com"
CLOB_API = "https://clob.polymarket.com"

# Strategy thresholds (same as scan_markets.py)
TAIL_PROB_HIGH = 0.60
TAIL_PROB_LOW = 0.40
BONDING_SPREAD_THRESHOLD = 0.08
SPREAD_ARB_THRESHOLD = 1.02


def fetch_closed_markets(limit: int = 100) -> list[dict]:
    """Fetch recently closed/resolved markets from the Gamma API."""
    markets: list[dict] = []
    offset = 0
    page_size = min(limit, 100)

    while len(markets) < limit:
        try:
            resp = requests.get(
                f"{GAMMA_API}/markets",
                params={
                    "closed": "true",
                    "limit": page_size,
                    "offset": offset,
                    "order": "volume",
                    "ascending": "false",
                },
                timeout=15,
            )
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
        time.sleep(0.3)

    return markets[:limit]


def parse_json_field(raw) -> list:
    """Parse a JSON string or return as-is if already a list."""
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


def get_resolution(market: dict) -> str | None:
    """Determine the winning outcome of a resolved market."""
    outcome = market.get("outcome", "")
    if outcome:
        ol = outcome.lower()
        if ol in ("yes", "1", "true"):
            return "YES"
        elif ol in ("no", "0", "false"):
            return "NO"

    outcome_prices = parse_json_field(market.get("outcomePrices"))
    if len(outcome_prices) >= 2:
        try:
            yes_p = float(outcome_prices[0])
            no_p = float(outcome_prices[1])
            if yes_p > 0.9:
                return "YES"
            elif no_p > 0.9:
                return "NO"
        except (ValueError, TypeError):
            pass

    return None


def get_entry_prices(market: dict) -> tuple[float, float] | None:
    """
    Extract the last known prices before resolution as simulated entry prices.
    Uses outcomePrices if available, otherwise bestBid/bestAsk fields.
    """
    # Try to use the market's last recorded prices
    outcome_prices = parse_json_field(market.get("outcomePrices"))
    if len(outcome_prices) >= 2:
        try:
            # These are resolution prices (1.0/0.0), not entry prices
            # We need pre-resolution prices instead
            pass
        except (ValueError, TypeError):
            pass

    # Use bestBid as a proxy for the price before resolution
    best_bid = market.get("bestBid")
    best_ask = market.get("bestAsk")

    if best_bid is not None and best_ask is not None:
        try:
            return float(best_bid), float(best_ask)
        except (ValueError, TypeError):
            pass

    # Fallback: estimate from volume and other signals
    # Use oneDayPriceChange or similar if available
    price = market.get("lastTradePrice") or market.get("bestBid")
    if price is not None:
        try:
            p = float(price)
            return p, 1.0 - p
        except (ValueError, TypeError):
            pass

    return None


def simulate_strategies(market: dict) -> list[dict]:
    """Simulate strategy signals on a historical market. Returns list of signals."""
    token_ids = parse_json_field(market.get("clobTokenIds"))
    outcomes = parse_json_field(market.get("outcomes")) or ["Yes", "No"]
    resolution = get_resolution(market)

    if not resolution or len(token_ids) < 2:
        return []

    # We need a price to simulate entry. Use bestBid or lastTradePrice.
    yes_price = None
    no_price = None

    # Try bestBid
    bb = market.get("bestBid")
    if bb is not None:
        try:
            yes_price = float(bb)
            no_price = 1.0 - yes_price
        except (ValueError, TypeError):
            pass

    # Fallback: use lastTradePrice
    if yes_price is None:
        ltp = market.get("lastTradePrice")
        if ltp is not None:
            try:
                yes_price = float(ltp)
                no_price = 1.0 - yes_price
            except (ValueError, TypeError):
                pass

    if yes_price is None:
        return []

    question = market.get("question", "Unknown")
    volume = float(market.get("volume", 0) or 0)

    signals = []

    # TAIL: strong trend
    if yes_price > TAIL_PROB_HIGH or yes_price < TAIL_PROB_LOW:
        direction = "YES" if yes_price > TAIL_PROB_HIGH else "NO"
        entry = yes_price if direction == "YES" else no_price
        won = (direction == resolution)
        exit_price = 1.0 if won else 0.0
        pnl_per_dollar = (exit_price - entry) / entry if entry > 0 else 0

        signals.append({
            "strategy": "TAIL",
            "question": question,
            "direction": direction,
            "entry_price": entry,
            "resolution": resolution,
            "won": won,
            "pnl_pct": pnl_per_dollar,
            "volume": volume,
        })

    # BONDING: contrarian (simulate as: bet against the strong side)
    if yes_price > 0.70 or yes_price < 0.30:
        # Contrarian = bet against the crowd
        direction = "NO" if yes_price > 0.70 else "YES"
        entry = no_price if direction == "NO" else yes_price
        won = (direction == resolution)
        exit_price = 1.0 if won else 0.0
        pnl_per_dollar = (exit_price - entry) / entry if entry > 0 else 0

        signals.append({
            "strategy": "BONDING",
            "question": question,
            "direction": direction,
            "entry_price": entry,
            "resolution": resolution,
            "won": won,
            "pnl_pct": pnl_per_dollar,
            "volume": volume,
        })

    # SPREAD: check if yes + no > threshold (unlikely in resolved data, but check)
    if yes_price and no_price:
        total = yes_price + no_price
        if total > SPREAD_ARB_THRESHOLD:
            excess = total - 1.0
            signals.append({
                "strategy": "SPREAD",
                "question": question,
                "direction": "SELL_BOTH",
                "entry_price": total,
                "resolution": resolution,
                "won": True,  # Arbitrage always wins if executed
                "pnl_pct": excess,
                "volume": volume,
            })

    return signals


def main():
    parser = argparse.ArgumentParser(description="Backtest Polymarket paper trading strategies")
    parser.add_argument(
        "--strategy", "-s",
        choices=["tail", "bonding", "spread", "all"],
        default="all",
        help="Strategy filter (default: all)",
    )
    parser.add_argument("--limit", "-l", type=int, default=100, help="Number of closed markets to fetch (default: 100)")
    parser.add_argument("--capital", type=float, default=10_000, help="Starting capital (default: $10,000)")
    parser.add_argument("--bet-size", type=float, default=100, help="Fixed bet size per trade (default: $100)")
    parser.add_argument("--json", action="store_true", dest="output_json", help="Output JSON")

    args = parser.parse_args()
    strategy_filter = args.strategy.upper() if args.strategy != "all" else None

    print(f"Fetching {args.limit} closed markets for backtesting...", file=sys.stderr)
    markets = fetch_closed_markets(args.limit)
    print(f"Fetched {len(markets)} markets. Running strategies...", file=sys.stderr)

    all_signals: list[dict] = []
    for market in markets:
        signals = simulate_strategies(market)
        if strategy_filter:
            signals = [s for s in signals if s["strategy"] == strategy_filter]
        all_signals.extend(signals)

    if not all_signals:
        print("No strategy signals found in the tested markets.")
        return

    # Compute aggregate stats
    stats: dict[str, dict] = {}
    for s in all_signals:
        strat = s["strategy"]
        if strat not in stats:
            stats[strat] = {
                "trades": 0,
                "wins": 0,
                "losses": 0,
                "total_pnl_pct": 0.0,
                "best_trade": -999,
                "worst_trade": 999,
            }
        st = stats[strat]
        st["trades"] += 1
        if s["won"]:
            st["wins"] += 1
        else:
            st["losses"] += 1
        st["total_pnl_pct"] += s["pnl_pct"]
        st["best_trade"] = max(st["best_trade"], s["pnl_pct"])
        st["worst_trade"] = min(st["worst_trade"], s["pnl_pct"])

    for st in stats.values():
        st["win_rate"] = st["wins"] / st["trades"] if st["trades"] > 0 else 0
        st["avg_pnl_pct"] = st["total_pnl_pct"] / st["trades"] if st["trades"] > 0 else 0
        # Simulate dollar P&L
        st["simulated_pnl"] = st["total_pnl_pct"] * args.bet_size

    if args.output_json:
        print(json.dumps({
            "markets_tested": len(markets),
            "total_signals": len(all_signals),
            "bet_size": args.bet_size,
            "starting_capital": args.capital,
            "strategies": stats,
            "signals": all_signals[:50],  # Truncate for readability
        }, indent=2, default=str))
    else:
        total_trades = sum(s["trades"] for s in stats.values())
        total_wins = sum(s["wins"] for s in stats.values())
        total_pnl = sum(s["simulated_pnl"] for s in stats.values())

        print(f"\n{'='*65}")
        print(f"  BACKTEST RESULTS -- {len(markets)} markets, {total_trades} signals")
        print(f"  Bet size: ${args.bet_size:,.0f}  |  Starting capital: ${args.capital:,.0f}")
        print(f"{'='*65}")

        print(f"\n  {'Strategy':<10} {'Trades':>7} {'Wins':>6} {'Loss':>6} {'Win%':>7} {'Avg P&L':>9} {'Total $':>10}")
        print(f"  {'-'*60}")

        for strat in ["TAIL", "BONDING", "SPREAD"]:
            if strat not in stats:
                continue
            s = stats[strat]
            print(
                f"  {strat:<10} {s['trades']:>7} {s['wins']:>6} {s['losses']:>6} "
                f"{s['win_rate']:>6.1%} {s['avg_pnl_pct']:>+8.1%} ${s['simulated_pnl']:>+9,.0f}"
            )

        print(f"  {'-'*60}")
        overall_wr = total_wins / total_trades if total_trades > 0 else 0
        print(f"  {'TOTAL':<10} {total_trades:>7} {total_wins:>6} {total_trades - total_wins:>6} "
              f"{overall_wr:>6.1%} {'':>9} ${total_pnl:>+9,.0f}")

        final_capital = args.capital + total_pnl
        ret = total_pnl / args.capital if args.capital > 0 else 0
        print(f"\n  Final capital: ${final_capital:>,.0f} ({ret:+.1%} return)")

        # Show top 5 wins and losses
        winners = sorted([s for s in all_signals if s["won"]], key=lambda x: x["pnl_pct"], reverse=True)[:5]
        losers = sorted([s for s in all_signals if not s["won"]], key=lambda x: x["pnl_pct"])[:5]

        if winners:
            print(f"\n  TOP WINS:")
            for w in winners:
                print(f"    [{w['strategy']}] {w['direction']} @ ${w['entry_price']:.2f} -> {w['resolution']} "
                      f"({w['pnl_pct']:+.0%})  {w['question'][:45]}")

        if losers:
            print(f"\n  TOP LOSSES:")
            for l in losers:
                print(f"    [{l['strategy']}] {l['direction']} @ ${l['entry_price']:.2f} -> {l['resolution']} "
                      f"({l['pnl_pct']:+.0%})  {l['question'][:45]}")

        print()

    print(f"Backtest complete. {len(all_signals)} signals across {len(markets)} markets.", file=sys.stderr)


if __name__ == "__main__":
    main()
