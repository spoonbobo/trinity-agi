#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "requests>=2.28.0",
# ]
# ///
"""
Execute and manage paper trades on Polymarket.

Simulates trades against live CLOB prices and tracks them in a local SQLite database.
Starting capital: $10,000 (configurable on first run).

Usage:
    # Open a paper trade
    uv run paper_trade.py --market "<question_or_slug>" --token-id <clob_token_id> \\
        --direction YES --amount 100 --strategy TAIL [--db path]

    # Close a paper trade
    uv run paper_trade.py --close <trade_id> [--db path]

    # List open trades
    uv run paper_trade.py --list [--db path]

    # Reset portfolio (delete all data)
    uv run paper_trade.py --reset [--db path]
"""

import argparse
import json
import os
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

import requests

CLOB_API = "https://clob.polymarket.com"
DEFAULT_DB = os.path.expanduser("~/.openclaw/workspace/polymarket-paper.db")
DEFAULT_CAPITAL = 10_000.0


def get_db(db_path: str) -> sqlite3.Connection:
    """Open (and initialise if needed) the paper trading database."""
    Path(db_path).parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS portfolio (
            id          INTEGER PRIMARY KEY CHECK (id = 1),
            starting_capital REAL NOT NULL,
            cash        REAL NOT NULL,
            created_at  TEXT NOT NULL,
            updated_at  TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS paper_trades (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            market_name  TEXT NOT NULL,
            token_id     TEXT NOT NULL,
            strategy     TEXT NOT NULL,
            direction    TEXT NOT NULL,
            quantity     REAL NOT NULL,
            entry_price  REAL NOT NULL,
            exit_price   REAL,
            pnl          REAL,
            status       TEXT NOT NULL DEFAULT 'open',
            opened_at    TEXT NOT NULL,
            closed_at    TEXT
        );
    """)
    conn.commit()
    return conn


def ensure_portfolio(conn: sqlite3.Connection, capital: float = DEFAULT_CAPITAL) -> dict:
    """Ensure the portfolio row exists, creating with starting capital if needed."""
    row = conn.execute("SELECT * FROM portfolio WHERE id = 1").fetchone()
    if row:
        return dict(row)
    now = datetime.now(timezone.utc).isoformat()
    conn.execute(
        "INSERT INTO portfolio (id, starting_capital, cash, created_at, updated_at) VALUES (1, ?, ?, ?, ?)",
        (capital, capital, now, now),
    )
    conn.commit()
    row = conn.execute("SELECT * FROM portfolio WHERE id = 1").fetchone()
    return dict(row)


def fetch_current_price(token_id: str) -> float:
    """Fetch the current midpoint price for a token from the CLOB API."""
    try:
        resp = requests.get(
            f"{CLOB_API}/midpoint", params={"token_id": token_id}, timeout=10
        )
        resp.raise_for_status()
        return float(resp.json().get("mid", 0))
    except (requests.RequestException, ValueError, KeyError) as e:
        print(f"Warning: Could not fetch price for {token_id}: {e}", file=sys.stderr)
        return 0.0


def open_trade(
    conn: sqlite3.Connection,
    market_name: str,
    token_id: str,
    direction: str,
    amount: float,
    strategy: str,
    capital: float,
) -> None:
    """Open a new paper trade at the current market price."""
    portfolio = ensure_portfolio(conn, capital)
    cash = portfolio["cash"]

    if amount > cash:
        print(f"Error: Insufficient cash. Available: ${cash:,.2f}, Requested: ${amount:,.2f}", file=sys.stderr)
        sys.exit(1)

    price = fetch_current_price(token_id)
    if price <= 0:
        print(f"Error: Could not fetch a valid price for token {token_id}.", file=sys.stderr)
        sys.exit(1)

    quantity = amount / price
    now = datetime.now(timezone.utc).isoformat()

    conn.execute(
        """INSERT INTO paper_trades
           (market_name, token_id, strategy, direction, quantity, entry_price, status, opened_at)
           VALUES (?, ?, ?, ?, ?, ?, 'open', ?)""",
        (market_name, token_id, strategy.upper(), direction.upper(), quantity, price, now),
    )

    new_cash = cash - amount
    conn.execute(
        "UPDATE portfolio SET cash = ?, updated_at = ? WHERE id = 1",
        (new_cash, now),
    )
    conn.commit()

    trade_id = conn.execute("SELECT last_insert_rowid()").fetchone()[0]

    print(f"Trade #{trade_id} OPENED")
    print(f"  Market:    {market_name}")
    print(f"  Direction: {direction.upper()}")
    print(f"  Strategy:  {strategy.upper()}")
    print(f"  Entry:     ${price:.4f}")
    print(f"  Quantity:  {quantity:,.2f} shares")
    print(f"  Cost:      ${amount:,.2f}")
    print(f"  Cash left: ${new_cash:,.2f}")


def close_trade(conn: sqlite3.Connection, trade_id: int, capital: float) -> None:
    """Close an open paper trade at the current market price."""
    ensure_portfolio(conn, capital)

    row = conn.execute(
        "SELECT * FROM paper_trades WHERE id = ? AND status = 'open'", (trade_id,)
    ).fetchone()

    if not row:
        print(f"Error: No open trade with ID #{trade_id}.", file=sys.stderr)
        sys.exit(1)

    trade = dict(row)
    price = fetch_current_price(trade["token_id"])
    if price <= 0:
        print(f"Error: Could not fetch current price for token {trade['token_id']}.", file=sys.stderr)
        sys.exit(1)

    entry_price = trade["entry_price"]
    quantity = trade["quantity"]
    direction = trade["direction"]

    # P&L calculation
    if direction == "YES":
        pnl = (price - entry_price) * quantity
    else:
        # NO direction: profit when price drops
        pnl = (entry_price - price) * quantity

    exit_value = quantity * price
    now = datetime.now(timezone.utc).isoformat()

    conn.execute(
        """UPDATE paper_trades
           SET exit_price = ?, pnl = ?, status = 'closed', closed_at = ?
           WHERE id = ?""",
        (price, pnl, now, trade_id),
    )

    portfolio = dict(conn.execute("SELECT * FROM portfolio WHERE id = 1").fetchone())
    new_cash = portfolio["cash"] + exit_value
    conn.execute(
        "UPDATE portfolio SET cash = ?, updated_at = ? WHERE id = 1",
        (new_cash, now),
    )
    conn.commit()

    result = "WIN" if pnl > 0 else "LOSS" if pnl < 0 else "FLAT"
    print(f"Trade #{trade_id} CLOSED -- {result}")
    print(f"  Market:    {trade['market_name']}")
    print(f"  Direction: {direction}")
    print(f"  Strategy:  {trade['strategy']}")
    print(f"  Entry:     ${entry_price:.4f}")
    print(f"  Exit:      ${price:.4f}")
    print(f"  Quantity:  {quantity:,.2f} shares")
    print(f"  P&L:       ${pnl:+,.2f}")
    print(f"  Cash now:  ${new_cash:,.2f}")


def list_open_trades(conn: sqlite3.Connection, capital: float) -> None:
    """List all open paper trades."""
    ensure_portfolio(conn, capital)
    rows = conn.execute(
        "SELECT * FROM paper_trades WHERE status = 'open' ORDER BY opened_at DESC"
    ).fetchall()

    if not rows:
        print("No open trades.")
        return

    print(f"{'ID':>4}  {'Direction':>9}  {'Strategy':>8}  {'Entry':>8}  {'Qty':>10}  {'Cost':>10}  Market")
    print("-" * 90)
    for r in rows:
        cost = r["entry_price"] * r["quantity"]
        print(
            f"  {r['id']:>2}  {r['direction']:>9}  {r['strategy']:>8}  "
            f"${r['entry_price']:.4f}  {r['quantity']:>10,.2f}  "
            f"${cost:>9,.2f}  {r['market_name'][:40]}"
        )


def reset_portfolio(conn: sqlite3.Connection) -> None:
    """Delete all trades and portfolio data."""
    conn.executescript("""
        DELETE FROM paper_trades;
        DELETE FROM portfolio;
    """)
    conn.commit()
    print("Portfolio reset. All trades deleted.")


def main():
    parser = argparse.ArgumentParser(description="Polymarket paper trading")
    parser.add_argument("--market", "-m", help="Market question or slug")
    parser.add_argument("--token-id", "-t", help="CLOB token ID for the outcome")
    parser.add_argument(
        "--direction", "-d", choices=["YES", "NO", "yes", "no"],
        help="Trade direction",
    )
    parser.add_argument("--amount", "-a", type=float, help="USD amount to paper-trade")
    parser.add_argument("--strategy", "-s", default="MANUAL", help="Strategy label (default: MANUAL)")
    parser.add_argument("--close", "-c", type=int, metavar="TRADE_ID", help="Close an open trade by ID")
    parser.add_argument("--list", action="store_true", help="List open trades")
    parser.add_argument("--reset", action="store_true", help="Reset portfolio (delete all data)")
    parser.add_argument("--db", default=DEFAULT_DB, help=f"SQLite database path (default: {DEFAULT_DB})")
    parser.add_argument("--capital", type=float, default=DEFAULT_CAPITAL, help=f"Starting capital (default: ${DEFAULT_CAPITAL:,.0f})")

    args = parser.parse_args()
    conn = get_db(args.db)

    try:
        if args.reset:
            reset_portfolio(conn)
        elif args.close is not None:
            close_trade(conn, args.close, args.capital)
        elif args.list:
            list_open_trades(conn, args.capital)
        elif args.market and args.token_id and args.direction and args.amount:
            open_trade(
                conn,
                market_name=args.market,
                token_id=args.token_id,
                direction=args.direction.upper(),
                amount=args.amount,
                strategy=args.strategy,
                capital=args.capital,
            )
        else:
            parser.print_help()
            print("\nExamples:", file=sys.stderr)
            print('  # Open a trade', file=sys.stderr)
            print('  uv run paper_trade.py -m "Will BTC hit 100k?" -t <token_id> -d YES -a 100 -s TAIL', file=sys.stderr)
            print('  # Close trade #1', file=sys.stderr)
            print('  uv run paper_trade.py --close 1', file=sys.stderr)
            print('  # List open trades', file=sys.stderr)
            print('  uv run paper_trade.py --list', file=sys.stderr)
            sys.exit(1)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
