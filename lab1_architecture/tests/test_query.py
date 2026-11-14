from pathlib import Path

def test_sql_has_lecture_filter_and_sort():
    app = Path(__file__).parents[1] / 'lab1' / 'app.py'
    src = app.read_text()
    assert "l.lesson_type = 'lecture'" in src
    assert 'ORDER BY attendance_percent ASC' in src
    assert 'LIMIT 10' in src
    assert 'week_start_date' in src

def test_gateway_checks_jwt():
    app = Path(__file__).parents[1] / 'gateway' / 'app.py'
    src = app.read_text()
    assert 'jwt.decode' in src
    assert "@app.get('/api/lab1/low-attendance')" in src
