import expense_tracker as et


def make_conn(tmp_path):
    return et.connect(tmp_path / "test.db")


def test_add_and_list(tmp_path):
    conn = make_conn(tmp_path)
    et.add_expense(conn, 120.5, "Food", "lunch", "2026-10-01")
    rows = et.list_expenses(conn)
    assert len(rows) == 1
    assert rows[0]["category"] == "food"
    assert rows[0]["amount"] == 120.5


def test_filter_by_month_and_category(tmp_path):
    conn = make_conn(tmp_path)
    et.add_expense(conn, 10, "food", on="2026-09-10")
    et.add_expense(conn, 20, "food", on="2026-10-10")
    et.add_expense(conn, 30, "rent", on="2026-10-11")
    assert len(et.list_expenses(conn, month="2026-10")) == 2
    assert len(et.list_expenses(conn, month="2026-10", category="rent")) == 1


def test_delete(tmp_path):
    conn = make_conn(tmp_path)
    new_id = et.add_expense(conn, 5, "other")
    assert et.delete_expense(conn, new_id) is True
    assert et.delete_expense(conn, new_id) is False


def test_totals(tmp_path):
    conn = make_conn(tmp_path)
    et.add_expense(conn, 10, "food", on="2026-09-10")
    et.add_expense(conn, 15, "food", on="2026-10-10")
    et.add_expense(conn, 50, "rent", on="2026-10-11")
    assert et.category_totals(et.list_expenses(conn)) == {"rent": 50, "food": 25}
    assert et.monthly_totals(conn) == {"2026-09": 10, "2026-10": 65}
