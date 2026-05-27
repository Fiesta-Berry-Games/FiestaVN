import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Tests for Python-3-style `super()` (single inheritance) and the inert
/// `Transform(...)` GUI builtin in renpy_python.dart.
///
/// `super()` is the #1 fidelity ceiling for LearnToCodeRPG, where class
/// constructors call `super().__init__(...)` and quiz/question lists are filled
/// via list comprehensions of constructed instances. `Transform(...)` appears
/// nested in `define`d GUI dicts and must evaluate inertly rather than skip.
void main() {
  const executor = RenPyPythonExecutor();
  const evaluator = RenPyPythonEvaluator();

  Map<String, Object?> run(String source, [Map<String, Object?>? store]) {
    final s = store ?? <String, Object?>{};
    executor.execute(
      source,
      RenPyMapScope(store: s, persistent: <String, Object?>{}),
    );
    return s;
  }

  Object? eval(String expression, [Map<String, Object?>? store]) {
    return evaluator.evaluate(
      expression,
      RenPyMapScope(
        store: store ?? <String, Object?>{},
        persistent: <String, Object?>{},
      ),
    );
  }

  List<RenPyDiagnostic> skippedFor(String source) {
    final script = RenPyParser().parse(source, 'super.rpy').script;
    final runner = RenPyRunner(script);
    final diagnostics = <RenPyDiagnostic>[];
    runner.onDiagnostic = diagnostics.add;
    runner.jumpToLabel('start');
    runner.run();
    return diagnostics
        .where((d) => d.code == RenPyDiagnosticCode.skippedDefinition)
        .toList();
  }

  group('super() single inheritance', () {
    test('a 3-level super().method() chain dispatches A->B->C each once', () {
      final store = run('''
order = []
class A(object):
    def step(self):
        order.append("A")
class B(A):
    def step(self):
        super().step()
        order.append("B")
class C(B):
    def step(self):
        super().step()
        order.append("C")
c = C()
c.step()
''');
      // C.step -> super (B.step) -> super (A.step): bodies run innermost-first,
      // each exactly once, with the defining class advancing C -> B -> A.
      expect(store['order'], ['A', 'B', 'C']);
    });

    test('super() walks past an intermediate class that does not override', () {
      final store = run('''
log = []
class A(object):
    def step(self):
        log.append("A")
class B(A):
    pass
class C(B):
    def step(self):
        super().step()
        log.append("C")
c = C()
c.step()
''');
      // C.step's super() starts at B, which has no `step`, so it resolves to
      // A.step (findMethodWithOwner reports the true declaring owner) - no loop.
      expect(store['log'], ['A', 'C']);
    });

    test('super().__init__ sets inherited and own fields', () {
      final store = run('''
class Base:
    def __init__(self, name):
        self.name = name
        self.kind = "base"
class Derived(Base):
    def __init__(self, name, level):
        super().__init__(name)
        self.level = level
d = Derived("Ami", 3)
n = d.name
k = d.kind
l = d.level
''');
      expect(store['n'], 'Ami');
      expect(store['k'], 'base');
      expect(store['l'], 3);
    });

    test('super().method() dispatches to the base implementation', () {
      final store = run('''
class Base:
    def __init__(self):
        self.tag = "x"
    def describe(self):
        return "base:" + self.tag
class Derived(Base):
    def describe(self):
        return super().describe() + ":derived"
d = Derived()
result = d.describe()
''');
      expect(store['result'], 'base:x:derived');
    });

    test('explicit super(ClassName, self) form is tolerated', () {
      final store = run('''
class Base:
    def __init__(self, name):
        self.name = name
class Derived(Base):
    def __init__(self, name):
        super(Derived, self).__init__(name)
        self.ready = True
d = Derived("Bo")
n = d.name
r = d.ready
''');
      expect(store['n'], 'Bo');
      expect(store['r'], true);
    });

    test('class built inside a list comprehension materializes instances', () {
      // The LearnToCodeRPG quiz-list shape: [QuizQuestion(q) for q in data].
      final store = run('''
class QuizQuestion:
    def __init__(self, prompt):
        self.prompt = prompt
        self.answered = False
data = ["a", "b", "c"]
questions = [QuizQuestion(q) for q in data]
count = len(questions)
first = questions[0].prompt
last = questions[2].prompt
flag = questions[1].answered
''');
      expect(store['count'], 3);
      expect(store['first'], 'a');
      expect(store['last'], 'c');
      expect(store['flag'], false);
    });

    test('subclass instance in a comprehension uses super().__init__', () {
      final store = run('''
class Base:
    def __init__(self, prompt):
        self.prompt = prompt
        self.score = 0
class QuizQuestion(Base):
    def __init__(self, prompt, points):
        super().__init__(prompt)
        self.points = points
data = [("q1", 5), ("q2", 10)]
questions = [QuizQuestion(p, pts) for (p, pts) in data]
p0 = questions[0].prompt
pts1 = questions[1].points
s0 = questions[0].score
''');
      expect(store['p0'], 'q1');
      expect(store['pts1'], 10);
      expect(store['s0'], 0);
    });

    test('super().__init__ with no base __init__ degrades gracefully', () {
      // No crash: the super().__init__(...) call is a no-op.
      final store = run('''
class Base:
    pass
class Derived(Base):
    def __init__(self):
        super().__init__()
        self.value = 42
d = Derived()
v = d.value
''');
      expect(store['v'], 42);
    });

    test('super() with no base class at all degrades gracefully', () {
      final store = run('''
class Solo:
    def __init__(self):
        super().__init__()
        self.value = 7
s = Solo()
v = s.value
''');
      expect(store['v'], 7);
    });
  });

  group('Transform inert GUI builtin', () {
    test('Transform("img", zoom=2) evaluates to a non-null value', () {
      expect(eval('Transform("img", zoom=2)'), isNotNull);
    });

    test('Transform with no arguments does not throw', () {
      expect(eval('Transform()'), isNotNull);
    });

    test('define x = Transform(...) emits no skippedDefinition', () {
      final skipped = skippedFor('''
define x = Transform("img", zoom=2)

label start:
    "Done."
''');
      expect(skipped, isEmpty);
    });

    test('Transform nested in a define dict emits no skippedDefinition', () {
      final skipped = skippedFor('''
define bubble.properties = {"thought": {"image": Transform("img", zoom=2)}}

label start:
    "Done."
''');
      expect(skipped, isEmpty);
    });
  });
}
