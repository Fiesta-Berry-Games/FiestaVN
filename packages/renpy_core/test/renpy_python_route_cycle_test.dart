// Tests for deepcopy depth-guard: constructing Route-like objects with
// nested _PythonInstance trees must not stack-overflow.
import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  const executor = RenPyPythonExecutor();

  RenPyMapScope newScope() => RenPyMapScope(
    store: <String, Object?>{},
    persistent: <String, Object?>{},
  );

  test('deepcopy of flat list succeeds', () {
    final scope = newScope();
    executor.execute('from copy import deepcopy', scope);
    executor.execute('''
class Item():
    def __init__(self, name):
        self.name = name
items = [Item("a"), Item("b"), Item("c")]
copied = deepcopy(items)
''', scope);
    final items = scope.read('items') as List;
    final copied = scope.read('copied') as List;
    expect(copied.length, items.length);
  });

  test('deepcopy of nested instances does not stack-overflow', () {
    final scope = newScope();
    executor.execute('from copy import deepcopy', scope);
    executor.execute('''
class Node():
    def __init__(self, val):
        self.val = val
        self.children = []
''', scope);
    // Build a deeply nested structure
    executor.execute('''
root = Node(0)
root.children = [Node(1), Node(2)]
root.children[0].children = [Node(3), Node(4)]
root.children[0].children[0].children = [Node(5)]
root.children[0].children[0].children[0].children = [Node(6)]
copied = deepcopy(root)
''', scope);
    final copied = scope.read('copied');
    expect(copied, isNotNull);
  });

  test('Route-like class constructed with deepcopy succeeds', () {
    final scope = newScope();
    executor.execute('from copy import deepcopy', scope);

    // Minimal RouteDay and Route mirroring the Mysterious Messenger classes
    executor.execute('''
class RouteDay():
    def __init__(self, day, archive_list=None):
        self.day = day
        self.archive_list = archive_list or []
''', scope);

    executor.execute('''
class Route():
    def __init__(self, default_branch, branch_list=None,
                route_history_title="Common",
                has_end_title="unset"):
        if has_end_title == "unset":
            if branch_list is not None:
                has_end_title = True
            else:
                has_end_title = False
        self.default_branch = default_branch
        if branch_list is None:
            branch_list = []
        self.ending_labels = []
        self.route = deepcopy(default_branch)
        self.route_history_title = route_history_title
        self.seen_all_endings = False
''', scope);

    executor.execute('''
good_end = ["Good End", RouteDay("2nd"), RouteDay("3rd"), RouteDay("Final")]
bad_end = ["Bad End", RouteDay("5th")]
route = Route(
    default_branch=good_end,
    branch_list=[bad_end],
    route_history_title="Casual",
    has_end_title=False
)
''', scope);

    final route = scope.read('route');
    expect(route, isNotNull);
  });

  test('Route-like class with deeper nesting does not stack-overflow', () {
    final scope = newScope();
    executor.execute('from copy import deepcopy', scope);

    executor.execute('''
class ChatRoom():
    def __init__(self, title, participants):
        self.title = title
        self.participants = participants
        self.available = False
        self.played = False
        self.choices = []

class RouteDay():
    def __init__(self, day, archive_list=None):
        self.day = day
        self.archive_list = archive_list or []

class Route():
    def __init__(self, default_branch, branch_list=None,
                route_history_title="Common"):
        self.default_branch = default_branch
        self.route = deepcopy(default_branch)
        self.route_history_title = route_history_title
''', scope);

    // Construct nested objects similar to the real game
    executor.execute('''
participants = ["ja", "ju", "s", "y", "z"]
days = [
    RouteDay("2nd", [
        ChatRoom("Morning", participants),
        ChatRoom("Afternoon", participants),
        ChatRoom("Evening", participants),
    ]),
    RouteDay("3rd", [
        ChatRoom("Chat1", participants),
        ChatRoom("Chat2", participants),
    ]),
    RouteDay("Final"),
]
route = Route(default_branch=days, route_history_title="Test")
ok = True
''', scope);

    expect(scope.read('ok'), isTrue);
  });
}
