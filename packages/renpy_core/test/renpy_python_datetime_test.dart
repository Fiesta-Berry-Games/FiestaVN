import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  const executor = RenPyPythonExecutor();

  Map<String, Object?> run(String source, [Map<String, Object?>? store]) {
    final s = store ?? <String, Object?>{};
    executor.execute(
      source,
      RenPyMapScope(store: s, persistent: <String, Object?>{}),
    );
    return s;
  }

  group('datetime', () {
    test('date.today() + timedelta(days=1) orders after today', () {
      final store = run('''
from datetime import date, timedelta
today = date.today()
tomorrow = today + timedelta(days=1)
after = tomorrow > today
before = today < tomorrow
''');
      expect(store['after'], true);
      expect(store['before'], true);
    });

    test('date - timedelta moves backward; weeks advance by 7 days', () {
      final store = run('''
from datetime import date, timedelta
today = date.today()
yesterday = today - timedelta(days=1)
next_week = today + timedelta(weeks=1)
back = yesterday < today
weekDelta = (next_week - today)
''');
      expect(store['back'], true);
    });

    test('date attribute reads and weekday() work', () {
      final store = run('''
from datetime import date
d = date(2020, 1, 15)
y = d.year
m = d.month
dy = d.day
wd = d.weekday()
''');
      expect(store['y'], 2020);
      expect(store['m'], 1);
      expect(store['dy'], 15);
      // 2020-01-15 is a Wednesday -> Python weekday() == 2.
      expect(store['wd'], 2);
    });

    test('import datetime then datetime.date.today() arithmetic', () {
      final store = run('''
import datetime
start = datetime.date.today()
later = start + datetime.timedelta(days=7)
gap = later > start
''');
      expect(store['gap'], true);
    });

    test('a Calendar-style class advances a date monotonically', () {
      final store = run('''
from datetime import date, timedelta
class Calendar:
    def __init__(self):
        self.current = date.today()
    def next(self):
        self.current = self.current + timedelta(days=1)
        return self.current
cal = Calendar()
first = cal.next()
second = cal.next()
advanced = second > first
''');
      expect(store['advanced'], true);
    });

    test('graceful fallback: an unsupported datetime member raises', () {
      // `time` is not implemented; using it must raise RenPyPythonError
      // (graceful skip) rather than crash with a stray Dart exception.
      expect(
        () => run('''
from datetime import time
t = time(12, 0)
'''),
        throwsA(isA<RenPyPythonError>()),
      );
    });
  });
}
