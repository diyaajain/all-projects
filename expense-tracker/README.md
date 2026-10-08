# Expense Tracker

A command-line app to log, filter, and summarize your spending. Data is stored locally in SQLite, so it needs no setup and no external libraries (matplotlib is optional, for charts).

## Features
- Add expenses with amount, category, note, and date
- List and filter by month or category
- Category summary with percentages and text bars
- Monthly bar chart (optional, needs matplotlib)
- Export everything to CSV
- Unit tests

## Setup
```bash
cd expense-tracker
pip install -r requirements.txt   # optional: only for charts and tests
```

## Usage
```bash
python3 expense_tracker.py add 250 food -n "lunch with friends"
python3 expense_tracker.py add 1200 transport -d 2026-10-03
python3 expense_tracker.py add 250 food -n "lunch with friends"
python3 expense_tracker.py list -m 2026-10 -c food
python3 expense_tracker.py summary -m 2026-10
python3 expense_tracker.py chart
python3 expense_tracker.py export my_expenses.csv
python3 expense_tracker.py delete 2
```

Example output:
```
Summary for 2026-10
===================
transport         1200.00   82.8%  #########################
food               250.00   17.2%  #####
TOTAL             1450.00
```

## Run the tests
```bash
pytest
```

## Ideas to extend it
- Monthly budgets per category with overspend warnings
- Recurring expenses (rent, subscriptions)
- A Streamlit or Flask web front end
- Import from a bank CSV statement
