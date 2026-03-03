#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "requests>=2.28.0",
# ]
# ///
"""
Display Polymarket paper trading portfolio: balances, positions, P&L, and strategy stats.

Usage:
    uv run portfolio.py [--db path] [--resolve] [--format table|json] [--history]
"""

import argparse
import json
import os
import sqlite3
import sys
from datetime import datetime, timezone

import requests

CLOB_API = "https://clob.polymarket.com"
DEFAULT_DB = os.path.expanduser("~/.openclaw/workspace/polymarket-paper.db")


def get_db(db_path: str) -> sqlite3.Connection:
    """Open the paper trading database (read-only)."""
    if not os.path.exists(db_path):
        print(f"Error: Database not found at {db_path}", file=sys.stderr)
        print("Run paper_trade.py first to create the database.", file=sys.stderr)
        sys.exit(1)
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


def fetch_current_price(token_id: str) -> float:
    """Fetch the current midpoint price for a token from the CLOB API."""
    try:
        resp = requests.get(
            f"{CLOB_API}/midpoint", params={"token_id": token_id}, timeout=10
        )
        resp.raise_for_status()
        return float(resp.json().get("mid", 0))
    except (requests.RequestException, ValueError, KeyError):
        return 0.0


def build_portfolio_report(conn: sqlite3.Connection, resolve: bool = False) -> dict:
    """Build a complete portfolio report."""
    portfolio_row = conn.execute("SELECT * FROM portfolio WHERE id = 1").fetchone()
    if not portfolio_row:
        return {"error": "No portfolio found. Run paper_trade.py first."}

    portfolio = dict(portfolio_row)
    cash = portfolio["cash"]
    starting_capital = portfolio["starting_capital"]

    # Open positions
    open_trades = [
        dict(r)
        for r in conn.execute(
            "SELECT * FROM paper_trades WHERE status = 'open' ORDER BY opened_at DESC"
        ).fetchall()
    ]

    # Closed trades
    closed_trades = [
        dict(r)
        for r in conn.execute(
            "SELECT * FROM paper_trades WHERE status = 'closed' ORDER BY closed_at DESC"
        ).fetchall()
    ]

    # Resolve current prices for open positions
    positions_value = 0.0
    for trade in open_trades:
        cost = trade["entry_price"] * trade["quantity"]
        trade["cost"] = cost

        if resolve:
            current = fetch_current_price(trade["token_id"])
            trade["current_price"] = current
            current_value = current * trade["quantity"]
            trade["current_value"] = current_value

            if trade["direction"] == "YES":
                trade["unrealised_pnl"] = (current - trade["entry_price"]) * trade["quantity"]
            else:
                trade["unrealised_pnl"] = (trade["entry_price"] - current) * trade["quantity"]

            positions_value += current_value
        else:
            trade["current_price"] = None
            trade["current_value"] = cost
            trade["unrealised_pnl"] = 0.0
            positions_value += cost

    # Strategy stats from closed trades
    strategy_stats: dict[str, dict] = {}
    total_pnl = 0.0
    wins = 0
    losses = 0

    for trade in closed_trades:
        pnl = trade["pnl"] or 0.0
        total_pnl += pnl
        strat = trade["strategy"]

        if strat not in strategy_stats:
            strategy_stats[strat] = {
                "trades": 0,
                "wins": 0,
                "losses": 0,
                "total_pnl": 0.0,
            }

        strategy_stats[strat]["trades"] += 1
        strategy_stats[strat]["total_pnl"] += pnl
        if pnl > 0:
            wins += 1
            strategy_stats[strat]["wins"] += 1
        elif pnl < 0:
            losses += 1
            strategy_stats[strat]["losses"] += 1

    for stat in strategy_stats.values():
        stat["win_rate"] = (
            stat["wins"] / stat["trades"] if stat["trades"] > 0 else 0.0
        )

    total_value = cash + positions_value
    overall_pnl = total_value - starting_capital
    win_rate = wins / len(closed_trades) if closed_trades else 0.0

    return {
        "portfolio": {
            "starting_capital": starting_capital,
            "cash": cash,
            "positions_value": positions_value,
            "total_value": total_value,
            "overall_pnl": overall_pnl,
            "overall_return": overall_pnl / starting_capital if starting_capital else 0,
            "prices_resolved": resolve,
        },
        "open_positions": open_trades,
        "closed_trades_count": len(closed_trades),
        "realised_pnl": total_pnl,
        "win_rate": win_rate,
        "wins": wins,
        "losses": losses,
        "strategy_stats": strategy_stats,
        "closed_trades": closed_trades,
        "updated_at": portfolio["updated_at"],
    }


def print_table(report: dict, show_history: bool = False) -> None:
    """Print a human-readable portfolio summary."""
    if "error" in report:
        print(report["error"])
        return

    p = report["portfolio"]
    resolved_tag = " (live prices)" if p["prices_resolved"] else " (at cost)"

    print(f"\n{'='*60}")
    print(f"  POLYMARKET PAPER PORTFOLIO")
    print(f"{'='*60}")
    print(f"  Starting Capital:  ${p['starting_capital']:>12,.2f}")
    print(f"  Cash:              ${p['cash']:>12,.2f}")
    print(f"  Positions Value:   ${p['positions_value']:>12,.2f}{resolved_tag}")
    print(f"  Total Value:       ${p['total_value']:>12,.2f}")
    print(f"  Overall P&L:       ${p['overall_pnl']:>+12,.2f} ({p['overall_return']:+.2%})")
    print(f"{'='*60}")

    # Open positions
    open_pos = report["open_positions"]
    if open_pos:
        print(f"\n  OPEN POSITIONS ({len(open_pos)})")
        print(f"  {'-'*56}")
        for t in open_pos:
            pnl_str = f"  P&L: ${t['unrealised_pnl']:+,.2f}" if p["prices_resolved"] else ""
            current_str = f" -> ${t['current_price']:.4f}" if t["current_price"] else ""
            print(f"  #{t['id']}  {t['direction']:>3} {t['strategy']:<8}  "
                  f"${t['entry_price']:.4f}{current_str}  "
                  f"{t['quantity']:,.1f} shares  "
                  f"${t['cost']:,.2f}{pnl_str}")
            print(f"       {t['market_name'][:50]}")
    else:
        print("\n  No open positions.")

    # Stats
    print(f"\n  PERFORMANCE")
    print(f"  {'-'*56}")
    print(f"  Closed Trades: {report['closed_trades_count']}")
    print(f"  Realised P&L:  ${report['realised_pnl']:+,.2f}")
    print(f"  Win Rate:      {report['win_rate']:.1%} ({report['wins']}W / {report['losses']}L)")

    # Strategy breakdown
    if report["strategy_stats"]:
        print(f"\n  STRATEGY BREAKDOWN")
        print(f"  {'-'*56}")
        print(f"  {'Strategy':<10} {'Trades':>6} {'Wins':>5} {'Losses':>6} {'Win%':>6} {'P&L':>10}")
        for strat, s in sorted(report["strategy_stats"].items()):
            print(
                f"  {strat:<10} {s['trades']:>6} {s['wins']:>5} {s['losses']:>6} "
                f"{s['win_rate']:>5.0%} ${s['total_pnl']:>+9,.2f}"
            )

    # Trade history
    if show_history and report["closed_trades"]:
        print(f"\n  RECENT CLOSED TRADES (last 20)")
        print(f"  {'-'*56}")
        for t in report["closed_trades"][:20]:
            result = "WIN" if (t["pnl"] or 0) > 0 else "LOSS" if (t["pnl"] or 0) < 0 else "FLAT"
            print(f"  #{t['id']}  {t['direction']:>3} {t['strategy']:<8}  "
                  f"${t['entry_price']:.4f} -> ${t['exit_price']:.4f}  "
                  f"P&L: ${t['pnl']:+,.2f}  {result}")
            print(f"       {t['market_name'][:50]}")

    print()


def main():
    parser = argparse.ArgumentParser(description="Polymarket paper trading portfolio viewer")
    parser.add_argument("--db", default=DEFAULT_DB, help=f"SQLite database path (default: {DEFAULT_DB})")
    parser.add_argument(
        "--resolve", "-r",
        action="store_true",
        help="Fetch live prices from CLOB API for unrealised P&L",
    )
    parser.add_argument(
        "--format", "-f",
        choices=["table", "json"],
        default="table",
        help="Output format (default: table)",
    )
    parser.add_argument(
        "--history",
        action="store_true",
        help="Show recent closed trade history",
    )

    args = parser.parse_args()
    conn = get_db(args.db)

    try:
        report = build_portfolio_report(conn, resolve=args.resolve)

        if args.format == "json":
            print(json.dumps(report, indent=2, default=str))
        else:
            print_table(report, show_history=args.history)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
