import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

List<RenPyAtlNode> _atlOf(String source) {
  final script = RenPyParser().parse(source, 'atl.rpy').script;
  for (final statement in script.statements) {
    if (statement is RenPyTransformStatement) return statement.atl;
    if (statement is RenPyInitStatement) {
      for (final inner in statement.block) {
        if (inner is RenPyTransformStatement) return inner.atl;
      }
    }
  }
  fail('no transform statement parsed from:\n$source');
}

RenPyAtlProgram _compile(String source) =>
    RenPyAtlProgram.compile(_atlOf(source));

void main() {
  group('warpers', () {
    test('linear is the identity', () {
      expect(warp('linear', 0), 0);
      expect(warp('linear', 0.5), closeTo(0.5, 1e-9));
      expect(warp('linear', 1), 1);
    });

    test('ease is symmetric around the midpoint', () {
      expect(warp('ease', 0), closeTo(0, 1e-9));
      expect(warp('ease', 0.5), closeTo(0.5, 1e-9));
      expect(warp('ease', 1), closeTo(1, 1e-9));
    });

    test('easein starts slow', () {
      expect(warp('easein', 0.5), lessThan(0.5));
    });

    test('easeout starts fast', () {
      expect(warp('easeout', 0.5), greaterThan(0.5));
    });

    test('unknown warper falls back to linear', () {
      expect(warp('nope', 0.25), closeTo(0.25, 1e-9));
    });
  });

  group('linear interpolation', () {
    final program = _compile('''
transform slide:
    xpos 0.0
    linear 1.0 xpos 1.0
''');

    test('value at t=0 is the start', () {
      expect(program.transformAt(0).xpos, closeTo(0, 1e-9));
    });

    test('value at the midpoint is halfway', () {
      expect(program.transformAt(0.5).xpos, closeTo(0.5, 1e-9));
    });

    test('value at the end is the target', () {
      expect(program.transformAt(1.0).xpos, closeTo(1, 1e-9));
    });

    test('duration is the sum of the steps', () {
      expect(program.duration, closeTo(1.0, 1e-9));
      expect(program.isComplete(0.5), isFalse);
      expect(program.isComplete(1.0), isTrue);
    });
  });

  group('ease interpolation', () {
    final program = _compile('''
transform fade:
    alpha 0.0
    ease 2.0 alpha 1.0
''');

    test('midpoint uses the ease curve', () {
      // ease at the time midpoint resolves to the curve midpoint (0.5).
      expect(program.transformAt(1.0).alpha, closeTo(0.5, 1e-9));
    });

    test('endpoints match the start and target', () {
      expect(program.transformAt(0).alpha, closeTo(0, 1e-9));
      expect(program.transformAt(2.0).alpha, closeTo(1, 1e-9));
    });
  });

  group('pause', () {
    final program = _compile('''
transform held:
    xpos 0.0
    linear 1.0 xpos 1.0
    pause 0.5
    linear 1.0 xpos 0.0
''');

    test('holds the value during the pause', () {
      expect(program.transformAt(1.0).xpos, closeTo(1, 1e-9));
      expect(program.transformAt(1.25).xpos, closeTo(1, 1e-9));
      expect(program.transformAt(1.5).xpos, closeTo(1, 1e-9));
    });

    test('resumes after the pause', () {
      expect(program.transformAt(2.0).xpos, closeTo(0.5, 1e-9));
      expect(program.transformAt(2.5).xpos, closeTo(0, 1e-9));
    });

    test('total duration includes the pause', () {
      expect(program.duration, closeTo(2.5, 1e-9));
    });
  });

  group('repeat', () {
    test('bounded repeat replays the body and is finite', () {
      final program = _compile('''
transform pulse:
    block:
        alpha 0.0
        linear 1.0 alpha 1.0
        repeat 2
''');
      expect(program.duration, closeTo(2.0, 1e-9));
      expect(program.transformAt(0.5).alpha, closeTo(0.5, 1e-9));
      // Second cycle restarts from the snapped start.
      expect(program.transformAt(1.0).alpha, closeTo(0, 1e-9));
      expect(program.transformAt(1.5).alpha, closeTo(0.5, 1e-9));
    });

    test('unbounded repeat never completes', () {
      final program = _compile('''
transform forever:
    block:
        xpos 0.0
        linear 1.0 xpos 1.0
        repeat
''');
      expect(program.duration, isNull);
      expect(program.isComplete(100), isFalse);
      expect(program.transformAt(0.5).xpos, closeTo(0.5, 1e-9));
    });
  });

  group('multi-step timeline', () {
    final program = _compile('''
transform path:
    xpos 0.0
    linear 1.0 xpos 0.5
    linear 1.0 xpos 0.5 ypos 1.0
''');

    test('first leg moves x', () {
      expect(program.transformAt(0.5).xpos, closeTo(0.25, 1e-9));
    });

    test('second leg holds x and moves y', () {
      final state = program.transformAt(1.5);
      expect(state.xpos, closeTo(0.5, 1e-9));
      expect(state.ypos, closeTo(0.5, 1e-9));
    });
  });

  group('parallel', () {
    final program = _compile('''
transform combo:
    parallel:
        xpos 0.0
        linear 2.0 xpos 1.0
    parallel:
        alpha 0.0
        linear 1.0 alpha 1.0
''');

    test('tracks advance on independent clocks', () {
      final state = program.transformAt(1.0);
      expect(state.xpos, closeTo(0.5, 1e-9));
      expect(state.alpha, closeTo(1.0, 1e-9));
    });

    test('duration is the longest branch', () {
      expect(program.duration, closeTo(2.0, 1e-9));
    });
  });

  group('aliases', () {
    test('align expands to xalign and yalign', () {
      final program = _compile('''
transform a:
    align (0.5, 1.0)
''');
      final state = program.transformAt(0);
      expect(state.xalign, closeTo(0.5, 1e-9));
      expect(state.yalign, closeTo(1.0, 1e-9));
    });

    test('rotate and zoom interpolate', () {
      final program = _compile('''
transform spin:
    rotate 0.0
    zoom 1.0
    linear 1.0 rotate 90.0 zoom 2.0
''');
      final state = program.transformAt(0.5);
      expect(state.rotate, closeTo(45, 1e-9));
      expect(state.zoom, closeTo(1.5, 1e-9));
    });
  });

  test('non-animatable transform reports no work', () {
    final nodes = _atlOf('''
transform still:
    xpos 0.5
    yalign 1.0
''');
    expect(RenPyAtlProgram.isAnimatable(nodes), isFalse);
    final program = RenPyAtlProgram.compile(nodes);
    expect(program.duration, closeTo(0, 1e-9));
    expect(program.transformAt(0).xpos, closeTo(0.5, 1e-9));
  });

  test('animatable transform is detected', () {
    final nodes = _atlOf('''
transform mover:
    linear 1.0 xpos 1.0
''');
    expect(RenPyAtlProgram.isAnimatable(nodes), isTrue);
  });
}
