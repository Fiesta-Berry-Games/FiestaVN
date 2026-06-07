import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  const executor = RenPyPythonExecutor();

  RenPyMapScope scope() => RenPyMapScope(
        store: <String, Object?>{},
        persistent: <String, Object?>{},
      );

  test('DIAG 1: minimal class with @property', () {
    final s = scope();
    try {
      executor.execute('''
class Foo():
    def __init__(self, name):
        self.name = name
    @property
    def display_name(self):
        return self.name
f = Foo("test")
result = f.display_name
''', s);
      print('DIAG 1 SUCCESS: result=${s.read("result")}');
    } catch (e) {
      print('DIAG 1 FAILED: $e');
    }
  });

  test('DIAG 2: class with @property and @xxx.setter', () {
    final s = scope();
    try {
      executor.execute('''
class Foo():
    def __init__(self, name):
        self._name = name
    @property
    def name(self):
        return self._name
    @name.setter
    def name(self, value):
        self._name = value
f = Foo("test")
result = f.name
''', s);
      print('DIAG 2 SUCCESS: result=${s.read("result")}');
    } catch (e) {
      print('DIAG 2 FAILED: $e');
    }
  });

  test('DIAG 3: class with try/except inside method', () {
    final s = scope();
    try {
      executor.execute('''
class Foo():
    def __init__(self, name):
        self.name = name
    def safe_get(self):
        try:
            return self.name
        except:
            return "fallback"
f = Foo("test")
result = f.safe_get()
''', s);
      print('DIAG 3 SUCCESS: result=${s.read("result")}');
    } catch (e) {
      print('DIAG 3 FAILED: $e');
    }
  });

  test('DIAG 4: class with try/except Exception as e', () {
    final s = scope();
    try {
      executor.execute('''
class Foo():
    def __init__(self, name):
        self.name = name
    def safe_get(self):
        try:
            return self.name
        except Exception as e:
            return "fallback"
f = Foo("test")
result = f.safe_get()
''', s);
      print('DIAG 4 SUCCESS: result=${s.read("result")}');
    } catch (e) {
      print('DIAG 4 FAILED: $e');
    }
  });

  test('DIAG 5: class with self._field = value', () {
    final s = scope();
    try {
      executor.execute('''
class Foo():
    def __init__(self, name):
        self._name = name
        self._count = 0
f = Foo("test")
result = f._name
count = f._count
''', s);
      print('DIAG 5 SUCCESS: result=${s.read("result")}, count=${s.read("count")}');
    } catch (e) {
      print('DIAG 5 FAILED: $e');
    }
  });

  test('DIAG 6: class with docstring', () {
    final s = scope();
    try {
      executor.execute('''
class Foo():
    """A test class."""
    def __init__(self, name):
        self.name = name
f = Foo("test")
result = f.name
''', s);
      print('DIAG 6 SUCCESS: result=${s.read("result")}');
    } catch (e) {
      print('DIAG 6 FAILED: $e');
    }
  });

  test('DIAG 7: class with docstring AND @property AND @setter', () {
    final s = scope();
    try {
      executor.execute('''
class Foo():
    """A test class."""
    def __init__(self, name):
        self._name = name
    @property
    def name(self):
        return self._name
    @name.setter
    def name(self, value):
        self._name = value
f = Foo("test")
result = f.name
''', s);
      print('DIAG 7 SUCCESS: result=${s.read("result")}');
    } catch (e) {
      print('DIAG 7 FAILED: $e');
    }
  });

  test('DIAG 8: class with **kwargs in __init__', () {
    final s = scope();
    try {
      executor.execute('''
class Foo():
    def __init__(self, name, **properties):
        self.name = name
        self.props = properties
f = Foo("test", color="#fff")
result = f.name
''', s);
      print('DIAG 8 SUCCESS: result=${s.read("result")}');
    } catch (e) {
      print('DIAG 8 FAILED: $e');
    }
  });

  test('DIAG 9: class with method that accesses store.xxx', () {
    final s = scope();
    try {
      executor.execute('''
class Foo():
    def __init__(self, name):
        self.name = name
    def check_store(self):
        try:
            if self not in store.all_items:
                store.all_items.append(self)
        except AttributeError:
            return
f = Foo("test")
''', s);
      print('DIAG 9 SUCCESS');
    } catch (e) {
      print('DIAG 9 FAILED: $e');
    }
  });

  test('DIAG 10: class with isinstance check', () {
    final s = scope();
    try {
      executor.execute('''
class Foo():
    def __init__(self, name):
        self.name = name

class Bar(Foo):
    def __init__(self, name, x):
        self.name = name
        self.x = x

b = Bar("test", 42)
result = isinstance(b, Foo)
''', s);
      print('DIAG 10 SUCCESS: result=${s.read("result")}');
    } catch (e) {
      print('DIAG 10 FAILED: $e');
    }
  });

  test('DIAG 11: ChatCharacter-like minimal', () {
    final s = scope();
    try {
      executor.execute('''
class ChatCharacter():
    """
    Class that stores ChatCharacters along with relevant information.
    """

    def __init__(self, name, file_id=False,
                prof_pic=False, heart_color='#000000',
                right_msgr=False, **properties):
        """Creates a ChatCharacter object."""
        self.name = name
        self.file_id = file_id
        self._prof_pic = False
        self.prof_pic = prof_pic
        self.heart_color = heart_color
        self.right_msgr = right_msgr

    @property
    def prof_pic(self):
        """Return this character's profile picture."""
        try:
            return self._prof_pic
        except:
            return 'default.webp'

    @prof_pic.setter
    def prof_pic(self, new_img):
        """Set this character's profile picture."""
        self._prof_pic = new_img

c = ChatCharacter("Test", file_id='t')
result = c.name
pic = c.prof_pic
''', s);
      print('DIAG 11 SUCCESS: result=${s.read("result")}, pic=${s.read("pic")}');
    } catch (e) {
      print('DIAG 11 FAILED: $e');
    }
  });

  test('DIAG 12: @property.setter decorator parse check', () {
    final s = scope();
    try {
      // This test isolates whether @xxx.setter breaks parsing
      executor.execute('''
class Simple():
    def __init__(self):
        self._val = 0
    @property
    def val(self):
        return self._val
    @val.setter
    def val(self, x):
        self._val = x
s = Simple()
s.val = 42
result = s.val
''', s);
      print('DIAG 12 SUCCESS: result=${s.read("result")}');
    } catch (e) {
      print('DIAG 12 FAILED: $e');
    }
  });

  test('DIAG 13: property getter with method having same name shadows it', () {
    final s = scope();
    try {
      // Does the setter def overwrite the property descriptor?
      executor.execute('''
class Simple():
    def __init__(self):
        self._val = 0
    @property
    def val(self):
        return self._val
    def set_val(self, x):
        self._val = x
s = Simple()
result = s.val
''', s);
      print('DIAG 13 SUCCESS: result=${s.read("result")}');
    } catch (e) {
      print('DIAG 13 FAILED: $e');
    }
  });

  test('DIAG 14: multiple @property defs work', () {
    final s = scope();
    try {
      executor.execute('''
class Multi():
    def __init__(self):
        self._a = 1
        self._b = 2
    @property
    def a(self):
        return self._a
    @property
    def b(self):
        return self._b
m = Multi()
ra = m.a
rb = m.b
''', s);
      print('DIAG 14 SUCCESS: a=${s.read("ra")}, b=${s.read("rb")}');
    } catch (e) {
      print('DIAG 14 FAILED: $e');
    }
  });

  test('DIAG 15: bare except with colon only', () {
    final s = scope();
    try {
      executor.execute('''
class Foo():
    def __init__(self):
        self._val = 0
    @property
    def val(self):
        try:
            return self._val
        except:
            return -1
f = Foo()
result = f.val
''', s);
      print('DIAG 15 SUCCESS: result=${s.read("result")}');
    } catch (e) {
      print('DIAG 15 FAILED: $e');
    }
  });

  test('DIAG 16: methods.get() inside __init__', () {
    final s = scope();
    try {
      executor.execute('''
class Foo():
    def __init__(self, name, **properties):
        self.name = name
        self.color = properties.get('who_color', False)
f = Foo("test", who_color="#fff")
result = f.color
''', s);
      print('DIAG 16 SUCCESS: result=${s.read("result")}');
    } catch (e) {
      print('DIAG 16 FAILED: $e');
    }
  });

  test('DIAG 17: GalleryImage-like class', () {
    final s = scope();
    try {
      executor.execute('''
class GalleryImage():
    """A gallery image."""
    def __init__(self, name, img=None, thumbnail=None,
            locked_img="CGs/album_unlock.webp",
            condition=None, width=750, height=1334):
        self.name = name
        if img is None:
            self.img = name
        else:
            self.img = img
        self.locked_img = locked_img
        self.condition = condition or "True"
        self.width = width
        self.height = height

    @property
    def locked(self):
        return True

    @property
    def unlocked(self):
        return not self.locked

    def __eq__(self, other):
        try:
            return self.name == other.name
        except:
            return False

    def __ne__(self, other):
        try:
            return self.name != other.name
        except:
            return False

g = GalleryImage("cg r_1")
result = g.name
img = g.img
''', s);
      print('DIAG 17 SUCCESS: result=${s.read("result")}, img=${s.read("img")}');
    } catch (e) {
      print('DIAG 17 FAILED: $e');
    }
  });

  test('DIAG 18: GalleryAlbum-like with for loop in method', () {
    final s = scope();
    try {
      executor.execute('''
class GalleryAlbum():
    def __init__(self, images):
        self.images = images
        self.process_images()

    def process_images(self):
        result = []
        for image in self.images:
            result.append(image)
        self.processed = result

    def __iter__(self):
        return iter(self.images)

a = GalleryAlbum([1, 2, 3])
result = a.processed
''', s);
      print('DIAG 18 SUCCESS: result=${s.read("result")}');
    } catch (e) {
      print('DIAG 18 FAILED: $e');
    }
  });

  test('DIAG 20: class def with multiple @xxx.setter - does it parse?', () {
    final s = scope();
    try {
      executor.execute('''
class ChatCharacter():
    """
    Class that stores ChatCharacters.
    """

    def __init__(self, name, file_id=False):
        self.name = name
        self.file_id = file_id
        self._heart_points = 0
        self._good_heart = 0
        self._prof_pic = False

    def private_to_public(self):
        try:
            self._prof_pic = self.__prof_pic
        except Exception as e:
            pass

    @property
    def vn_name(self):
        return self.name

    @vn_name.setter
    def vn_name(self, new_name):
        self.name = new_name

    @property
    def reg_bubble_img(self):
        return "bubble.webp"

    @property
    def glow_bubble_img(self):
        return "glow.webp"

    @property
    def voicemail(self):
        return "voicemail"

    @voicemail.setter
    def voicemail(self, new_label):
        pass

    @property
    def heart_points(self):
        try:
            return self._heart_points
        except:
            return 0

    @heart_points.setter
    def heart_points(self, points):
        self._heart_points = points

    @property
    def good_heart(self):
        try:
            return self._good_heart
        except:
            return 0

    @good_heart.setter
    def good_heart(self, points):
        self._good_heart = points

    @property
    def prof_pic(self):
        try:
            return self._prof_pic
        except:
            return 'default.webp'

    @prof_pic.setter
    def prof_pic(self, new_img):
        self._prof_pic = new_img

    def get_pfp(self, the_size):
        return self.prof_pic

    def reset_pfp(self):
        self.prof_pic = False

    @property
    def seen_updates(self):
        return False

    @seen_updates.setter
    def seen_updates(self, value):
        pass

    @property
    def bonus_pfp(self):
        try:
            return self._bonus_pfp
        except:
            return False

    @bonus_pfp.setter
    def bonus_pfp(self, new_img):
        try:
            self._bonus_pfp = new_img
        except:
            return

    @property
    def name(self):
        try:
            return self._name
        except:
            return "Unknown"

    @name.setter
    def name(self, value):
        self._name = value

    @property
    def cover_pic(self):
        try:
            return self._cover_pic
        except:
            return False

    @cover_pic.setter
    def cover_pic(self, value):
        self._cover_pic = value

    @property
    def status(self):
        try:
            return self._status
        except:
            return ""

    @status.setter
    def status(self, value):
        self._status = value
''', s);
      print('DIAG 20 SUCCESS: ChatCharacter class registered');
      // Try to instantiate
      executor.execute('''
c = ChatCharacter("Test", file_id="t01")
''', s);
      print('DIAG 20 INSTANTIATION SUCCESS');
      print('DIAG 20 c.name = ${s.read("c")}');
    } catch (e) {
      print('DIAG 20 FAILED: $e');
    }
  });

  test('DIAG 21: default param with renpy.character.NotSet', () {
    final s = scope();
    try {
      executor.execute('''
class Foo():
    def __init__(self, name, vn_name=renpy.character.NotSet):
        self.name = name
        if vn_name is renpy.character.NotSet:
            self.vn_name = self.name
        else:
            self.vn_name = vn_name
f = Foo("test")
result = f.vn_name
''', s);
      print('DIAG 21 SUCCESS: result=${s.read("result")}');
    } catch (e) {
      print('DIAG 21 FAILED: $e');
    }
  });

  test('DIAG 22: non-default arg after default (multiline params)', () {
    final s = scope();
    try {
      // This mimics the ChatCharacter __init__ signature:
      // def __init__(self, name, file_id=False, ..., **properties)
      // where all params have defaults except self and name
      executor.execute('''
class Foo():
    def __init__(self, name, file_id=False,
                prof_pic=False, heart_color='#000000',
                right_msgr=False, voice_tag='other_voice',
                vn_name=False, **properties):
        self.name = name
        self.file_id = file_id
f = Foo("test", file_id="t01")
result = f.name
''', s);
      print('DIAG 22 SUCCESS: result=${s.read("result")}');
    } catch (e) {
      print('DIAG 22 FAILED: $e');
    }
  });

  test('DIAG 23: real ChatCharacter __init__ signature', () {
    final s = scope();
    try {
      executor.execute('''
class ChatCharacter():
    def __init__(self, name, file_id=False, prof_pic=False,
            participant_pic=False, heart_color='#000000',
            cover_pic=False, status=False, bubble_color=False,
            glow_color=False, emote_list=False, voicemail=False,
            right_msgr=False, homepage_pic=False,
            phone_char=False, vn_char=False,
            pronunciation_help=False, voice_tag='other_voice',
            vn_name=False, **properties
            ):
        self.name = name
        self.file_id = file_id
c = ChatCharacter("Test")
result = c.name
''', s);
      print('DIAG 23 SUCCESS: result=${s.read("result")}');
    } catch (e) {
      print('DIAG 23 FAILED: $e');
    }
  });

  test('DIAG 24: bare raise inside except', () {
    final s = scope();
    try {
      executor.execute('''
class Foo():
    def __init__(self, x):
        self.x = x
    def check(self):
        try:
            if not self.x:
                raise
        except:
            return "caught"
        return "ok"
f = Foo(False)
result = f.check()
''', s);
      print('DIAG 24 SUCCESS: result=${s.read("result")}');
    } catch (e) {
      print('DIAG 24 FAILED: $e');
    }
  });

  test('DIAG 25: getattr builtin', () {
    final s = scope();
    try {
      executor.execute('''
class Foo():
    def __init__(self):
        self.x = 42
f = Foo()
result = getattr(f, 'x', None)
missing = getattr(f, 'y', 'default')
''', s);
      print('DIAG 25 SUCCESS: result=${s.read("result")}, missing=${s.read("missing")}');
    } catch (e) {
      print('DIAG 25 FAILED: $e');
    }
  });

  test('DIAG 26: multiline string continuation in def params', () {
    final s = scope();
    try {
      // The real ChatCharacter has params spread across 4 lines
      executor.execute('''
class Foo():
    def method(self, a, b=False,
            c=False, d='#000',
            e=False,
            **kwargs):
        self.a = a
f = Foo()
f.method("test")
result = f.a
''', s);
      print('DIAG 26 SUCCESS: result=${s.read("result")}');
    } catch (e) {
      print('DIAG 26 FAILED: $e');
    }
  });

  test('DIAG 27: bare raise outside class', () {
    final s = scope();
    try {
      executor.execute('''
def check(x):
    try:
        if not x:
            raise
    except:
        return "caught"
    return "ok"
result = check(False)
''', s);
      print('DIAG 27 SUCCESS: result=${s.read("result")}');
    } catch (e) {
      print('DIAG 27 FAILED: $e');
    }
  });

  test('DIAG 28: bare raise in try/except without class', () {
    final s = scope();
    try {
      executor.execute('''
try:
    raise
except:
    result = "caught"
''', s);
      print('DIAG 28 SUCCESS: result=${s.read("result")}');
    } catch (e) {
      print('DIAG 28 FAILED: $e');
    }
  });

  test('DIAG 29: bare raise in class method - class survives?', () {
    final s = scope();
    try {
      executor.execute('''
class Foo():
    def check(self):
        try:
            raise
        except:
            return "caught"
        return "ok"
''', s);
      print('DIAG 29 SUCCESS: class registered');
      // The class should parse without running the method body
      executor.execute('''
f = Foo()
result = f.check()
''', s);
      print('DIAG 29 INVOCATION: result=${s.read("result")}');
    } catch (e) {
      print('DIAG 29 FAILED: $e');
    }
  });

  test('DIAG 30: raise in if-not-x pattern in class', () {
    final s = scope();
    try {
      executor.execute('''
class Foo():
    def __init__(self, x):
        self.x = x
    @property
    def filename(self):
        try:
            if not self.x:
                raise
            else:
                return self.x
        except:
            return False
''', s);
      print('DIAG 30 SUCCESS: class registered');
      executor.execute('''
f = Foo("test.webp")
result = f.filename
''', s);
      print('DIAG 30 result=${s.read("result")}');
    } catch (e) {
      print('DIAG 30 FAILED: $e');
    }
  });

  test('DIAG 31: raise in GalleryImage filename pattern', () {
    final s = scope();
    try {
      executor.execute('''
class GalleryImage():
    def __init__(self, name, img=None):
        self.name = name
        if img is None:
            self.img = name
        else:
            self.img = img
    @property
    def filename(self):
        try:
            if '.' in self.img:
                return self.img
        except:
            pass
        try:
            if True:
                raise
            else:
                return False
        except:
            return False
''', s);
      print('DIAG 31 SUCCESS: class registered');
    } catch (e) {
      print('DIAG 31 FAILED: $e');
    }
  });

  test('DIAG 19: @seen_in_album.setter style (property + setter)', () {
    final s = scope();
    try {
      executor.execute('''
class Img():
    def __init__(self):
        self._seen = False
    @property
    def seen_in_album(self):
        return self._seen
    @seen_in_album.setter
    def seen_in_album(self, new_bool):
        self._seen = new_bool
i = Img()
result_before = i.seen_in_album
i.seen_in_album = True
result_after = i.seen_in_album
''', s);
      print('DIAG 19 SUCCESS: before=${s.read("result_before")}, after=${s.read("result_after")}');
    } catch (e) {
      print('DIAG 19 FAILED: $e');
    }
  });
}
