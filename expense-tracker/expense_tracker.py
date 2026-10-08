#!/usr/bin/env python3
"""Expense Tracker: a small command-line app to log and summarize spending.

Data is stored in a local SQLite database (expenses.db by default).
Run `python expense_tracker.py --help` for usage.
"""
import argparse
import csv
import sqlite3
import sys
from collections import defaultdict
from datetime import date, datetime
from pathlib import Path

DB_PATH = Path(__file__).with_name("expenses.db")
CATEGORIES = ["food", "transport", "rent", "bills", "shopping",
              "entertainment", "health", "education", "other"]


def connect(db_path=DB_PATH):
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    conn.execute(
        """CREATE TABLE IF NOT EXISTS expenses (
               id INTEGER PRIMARY KEY AUTOINCREMENT,
               date TEXT NOT NULL,
               amount REAL NOT NULL CHECK (amount > 0),
               category TEXT NOT NULL,
               note TEXT DEFAULT ''
           )"""
    )
    return conn


def parse_date(value):
    try:
        return datetime.strptime(value, "%Y-%m-%d").date().isoformat()
    except ValueError:
        raise argparse.ArgumentTypeError(f"'{value}' is not a valid date (use YYYY-MM-DD)")


def positive_amount(value):
    try:
        amount = float(value)
    except ValueError:
        raise argparse.ArgumentTypeError(f"'{value}' is not a number")
    if amount <= 0:
        raise argparse.ArgumentTypeError("amount must be greater than 0")
    return round(amount, 2)


# ---------- core operations ----------

def add_expense(conn, amount, category, note="", on=None):
    on = on or date.today().isoformat()
    cur = conn.execute(
        "INSERT INTO expenses (date, amount, category, note) VALUES (?, ?, ?, ?)",
        (on, amount, category.lower(), note),
    )
    conn.commit()
    return cur.lastrowid


def list_expenses(conn, month=None, category=None):
    query, params = "SELECT * FROM expenses WHERE 1=1", []
    if month:
        query += " AND substr(date, 1, 7) = ?"
        params.append(month)
    if category:
        query += " AND category = ?"
        params.append(category.lower())
    return conn.execute(query + " ORDER BY date DESC, id DESC", params).fetchall()


def delete_expense(conn, expense_id):
    cur = conn.execute("DELETE FROM expenses WHERE id = ?", (expense_id,))
    conn.commit()
    return cur.rowcount > 0


def category_totals(rows):
    totals = defaultdict(float)
    for r in rows:
        totals[r["category"]] += r["amount"]
    return dict(sorted(totals.items(), key=lambda kv: kv[1], reverse=True))


def monthly_totals(conn):
    rows = conn.execute(
        "SELECT substr(date, 1, 7) AS month, SUM(amount) AS total "
        "FROM expenses GROUP BY month ORDER BY month"
    ).fetchall()
    return {r["month"]: r["total"] for r in rows}


# ---------- display helpers ----------

def print_table(rows):
    if not rows:
        print("No expenses found.")
        return
    print(f"{'ID':>4}  {'Date':<10}  {'Category':<14}  {'Amount':>10}  Note")
    print("-" * 60)
    for r in rows:
        print(f"{r['id']:>4}  {r['date']:<10}  {r['category']:<14}  {r['amount']:>10.2f}  {r['note']}")
    print("-" * 60)
    print(f"{'Total':>32}  {sum(r['amount'] for r in rows):>10.2f}")


def print_summary(rows, title):
    if not rows:
        print("No expenses found.")
        return
    totals = category_totals(rows)
    grand = sum(totals.values())
    print(f"\n{title}")
    print("=" * len(title))
    for cat, amt in totals.items():
        bar = "#" * max(1, round(amt / grand * 30))
        print(f"{cat:<14} {amt:>10.2f}  {amt / grand * 100:>5.1f}%  {bar}")
    print(f"{'TOTAL':<14} {grand:>10.2f}")


def show_chart(conn):
    try:
        import matplotlib.pyplot as plt
    except ImportError:
        sys.exit("matplotlib is required for charts: pip install matplotlib")
    data = monthly_totals(conn)
    if not data:
        sys.exit("No expenses to chart yet.")
    plt.bar(list(data.keys()), list(data.values()), color="#4C78A8")
    plt.title("Monthly spending")
    plt.xlabel("Month")
    plt.ylabel("Total")
    plt.xticks(rotation=45)
    plt.tight_layout()
    plt.show()


def export_csv(rows, path):
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "date", "amount", "category", "note"])
        for r in rows:
            writer.writerow([r["id"], r["date"], r["amount"], r["category"], r["note"]])


# ---------- CLI ----------

def build_parser():
    p = argparse.ArgumentParser(description="Track and summarize your expenses.")
    sub = p.add_subparsers(dest="command", required=True)

    a = sub.add_parser("add", help="add an expense")
    a.add_argument("amount", type=positive_amount)
    a.add_argument("category", help=f"e.g. {', '.join(CATEGORIES)}")
    a.add_argument("-n", "--note", default="")
    a.add_argument("-d", "--date", type=parse_date, help="YYYY-MM-DD (default: today)")

    l = sub.add_parser("list", help="list expenses")
    l.add_argument("-m", "--month", help="filter by month, YYYY-MM")
    l.add_argument("-c", "--category")

    d = sub.add_parser("delete", help="delete an expense by id")
    d.add_argument("id", type=int)

    s = sub.add_parser("summary", help="spending by category")
    s.add_argument("-m", "--month", help="filter by month, YYYY-MM")

    sub.add_parser("chart", help="bar chart of monthly totals (needs matplotlib)")

    e = sub.add_parser("export", help="export all expenses to CSV")
    e.add_argument("path", nargs="?", default="expenses.csv")
    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    conn = connect()
    if args.command == "add":
        new_id = add_expense(conn, args.amount, args.category, args.note, args.date)
        print(f"Added expense #{new_id}: {args.amount:.2f} on {args.category}")
    elif args.command == "list":
        print_table(list_expenses(conn, args.month, args.category))
    elif args.command == "delete":
        print("Deleted." if delete_expense(conn, args.id) else f"No expense with id {args.id}.")
    elif args.command == "summary":
        rows = list_expenses(conn, args.month)
        print_summary(rows, f"Summary for {args.month or 'all time'}")
    elif args.command == "chart":
        show_chart(conn)
    elif args.command == "export":
        export_csv(list_expenses(conn), args.path)
        print(f"Exported to {args.path}")


if __name__ == "__main__":
    main()
