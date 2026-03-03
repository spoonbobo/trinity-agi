#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "requests>=2.28.0",
# ]
# ///
"""
Auto-resolve open paper trades by checking if their markets have settled.

Queries the Gamma API for market resolution status and automatically closes
paper trades at their final price ($1.00 for winners, $0.00 for losers).

Usage:
    uv run resolve.py [--db path] [--dry-run] [--json]
"""

import argparse
import json
import os
import sqlite3
import sys
import time
from datetime import datetime, timezone

import requests

GAMMA_API = "https://gamma-api.polymarket.com"
CLOB_API = "https://clob.polymarket.com"
DEFAULT_DB = os.path.expanduser("~/.openclaw/workspace/polymarket-paper.db")


def get_db(db_path: str) -> sqlite3.Connection:
    """Open the paper trading database."""
    if not os.path.exists(db_path):
        print(f"Error: Database not found at {db_path}", file=sys.stderr)
        sys.exit(1)
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


def get_open_trades(conn: sqlite3.Connection) -> list[dict]:
    """Get all open paper trades."""
    rows = conn.execute(
        "SELECT * FROM paper_trades WHERE status = 'open' ORDER BY opened_at"
    ).fetchall()
    return [dict(r) for r in rows]


def fetch_market_by_token(token_id: str) -> dict | None:
    """Look up a market by its CLOB token ID via the Gamma API."""
    try:
        resp = requests.get(
            f"{GAMMA_API}/markets",
            params={"clob_token_ids": token_id, "limit": 1},
            timeout=15,
        )
        resp.raise_for_status()
        markets = resp.json()
        if markets and len(markets) > 0:
            return markets[0]
    except requests.RequestException as e:
        print(f"  Warning: Could not fetch market for token {token_id[:20]}...: {e}", file=sys.stderr)
    return None


def is_market_resolved(market: dict) -> tuple[bool, str | None, float | None]:
    """
    Check if a market has resolved.
    Returns (is_resolved, winning_outcome, resolution_price_for_yes).
    """
    if not market:
        return False, None, None

    closed = market.get("closed", False)
    resolved = market.get("resolved", False)

    if not closed and not resolved:
        return False, None, None

    # Check for resolution source
    resolution_source = market.get("resolutionSource", "")
    outcome = market.get("outcome", "")

    # Polymarket resolves to outcome strings like "Yes", "No", or specific outcome text
    if outcome:
        outcome_lower = outcome.lower()
        if outcome_lower in ("yes", "1", "true"):
            return True, "YES", 1.0
        elif outcome_lower in ("no", "0", "false"):
            return True, "NO", 0.0

    # Try outcomePrices field (JSON string of final prices)
    outcome_prices_raw = market.get("outcomePrices")
    if outcome_prices_raw:
        try:
            if isinstance(outcome_prices_raw, str):
                prices = json.loads(outcome_prices_raw)
            else:
                prices = outcome_prices_raw

            if isinstance(prices, list) and len(prices) >= 2:
                yes_price = float(prices[0])
                no_price = float(prices[1])
                # If resolved, one should be ~1.0 and the other ~0.0
                if yes_price > 0.9:
                    return True, "YES", 1.0
                elif no_price > 0.9:
                    return True, "NO", 0.0
                elif yes_price < 0.1 and no_price < 0.1:
                    # Voided market
                    return True, "VOID", 0.5
        except (json.JSONDecodeError, ValueError, TypeError):
            pass

    # Market is closed but we can't determine the outcome clearly
    if closed:
        return True, "UNKNOWN", None

    return False, None, None


def resolve_trade(
    conn: sqlite3.Connection,
    trade: dict,
    winning_outcome: str,
    yes_resolution_price: float,
) -> dict:
    """Resolve a single paper trade and return the resolution details."""
    direction = trade["direction"]
    quantity = trade["quantity"]
    entry_price = trade["entry_price"]

    # Determine exit price based on direction and resolution
    if winning_outcome == "VOID":
        # Voided market: return at entry price (no P&L)
        exit_price = entry_price
    elif direction == "YES":
        exit_price = yes_resolution_price
    else:  # NO
        exit_price = 1.0 - yes_resolution_price

    # P&L calculation
    if direction == "YES":
        pnl = (exit_price - entry_price) * quantity
    else:
        pnl = (entry_price - (1.0 - exit_price)) * quantity
        # Simpler: for NO, profit = (exit_price_of_no - entry_price) * qty
        exit_price_no = 1.0 - yes_resolution_price
        pnl = (exit_price_no - entry_price) * quantity
        exit_price = exit_price_no

    now = datetime.now(timezone.utc).isoformat()

    conn.execute(
        """UPDATE paper_trades
           SET exit_price = ?, pnl = ?, status = 'closed', closed_at = ?
           WHERE id = ?""",
        (exit_price, pnl, now, trade["id"]),
    )

    # Return cash to portfolio
    exit_value = quantity * exit_price
    portfolio = conn.execute("SELECT * FROM portfolio WHERE id = 1").fetchone()
    if portfolio:
        new_cash = portfolio["cash"] + exit_value
        conn.execute(
            "UPDATE portfolio SET cash = ?, updated_at = ? WHERE id = 1",
            (new_cash, now),
        )

    conn.commit()

    return {
        "trade_id": trade["id"],
        "market": trade["market_name"],
        "direction": direction,
        "strategy": trade["strategy"],
        "entry_price": entry_price,
        "exit_price": exit_price,
        "quantity": quantity,
        "pnl": pnl,
        "outcome": winning_outcome,
        "result": "WIN" if pnl > 0 else "LOSS" if pnl < 0 else "FLAT",
    }


def main():
    parser = argparse.ArgumentParser(description="Auto-resolve settled Polymarket paper trades")
    parser.add_argument("--db", default=DEFAULT_DB, help=f"SQLite database path (default: {DEFAULT_DB})")
    parser.add_argument("--dry-run", action="store_true", help="Check resolutions but don't update the database")
    parser.add_argument("--json", action="store_true", dest="output_json", help="Output JSON")

    args = parser.parse_args()
    conn = get_db(args.db)

    try:
        open_trades = get_open_trades(conn)
        if not open_trades:
            print("No open trades to resolve.")
            return

        print(f"Checking {len(open_trades)} open trade(s) for resolution...", file=sys.stderr)

        # Deduplicate token IDs to avoid redundant API calls
        token_to_market: dict[str, dict | None] = {}
        unique_tokens = set(t["token_id"] for t in open_trades)

        for token_id in unique_tokens:
            if token_id not in token_to_market:
                token_to_market[token_id] = fetch_market_by_token(token_id)
                time.sleep(0.3)  # Rate limit

        resolutions: list[dict] = []
        still_open = 0

        for trade in open_trades:
            market = token_to_market.get(trade["token_id"])
            resolved, winning_outcome, yes_price = is_market_resolved(market)

            if not resolved or winning_outcome == "UNKNOWN" or yes_price is None:
                still_open += 1
                continue

            if args.dry_run:
                # Preview without updating
                direction = trade["direction"]
                if direction == "YES":
                    exit_price = yes_price
                else:
                    exit_price = 1.0 - yes_price
                pnl = (exit_price - trade["entry_price"]) * trade["quantity"]
                resolutions.append({
                    "trade_id": trade["id"],
                    "market": trade["market_name"],
                    "direction": direction,
                    "outcome": winning_outcome,
                    "pnl": pnl,
                    "dry_run": True,
                })
            else:
                result = resolve_trade(conn, trade, winning_outcome, yes_price)
                resolutions.append(result)

        if args.output_json:
            print(json.dumps({"resolved": resolutions, "still_open": still_open}, indent=2))
        else:
            if not resolutions:
                print(f"\nNo markets have resolved yet. {still_open} trade(s) still open.")
            else:
                tag = " (DRY RUN)" if args.dry_run else ""
                print(f"\n{'='*60}")
                print(f"  RESOLVED TRADES{tag}")
                print(f"{'='*60}")
                total_pnl = 0.0
                for r in resolutions:
                    pnl = r["pnl"]
                    total_pnl += pnl
                    result = r.get("result", "WIN" if pnl > 0 else "LOSS" if pnl < 0 else "FLAT")
                    print(f"\n  #{r['trade_id']}  {r['direction']} -> Outcome: {r['outcome']}  [{result}]")
                    print(f"    Market: {r['market'][:50]}")
                    if not args.dry_run:
                        print(f"    Entry: ${r['entry_price']:.4f}  Exit: ${r['exit_price']:.4f}")
                    print(f"    P&L: ${pnl:+,.2f}")

                print(f"\n  Total resolved: {len(resolutions)}  |  Still open: {still_open}")
                print(f"  Combined P&L: ${total_pnl:+,.2f}")
                print()

        print(f"Done. {len(resolutions)} resolved, {still_open} still open.", file=sys.stderr)

    finally:
        conn.close()


if __name__ == "__main__":
    main()
