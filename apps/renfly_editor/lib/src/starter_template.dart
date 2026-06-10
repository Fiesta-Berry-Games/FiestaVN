/// The self-contained starter story loaded on launch and by "New".
///
/// It previews with zero assets: `black`, `red`, and `white` are Ren'Py
/// built-in solid-color images, so missing-asset fallbacks never trigger.
const String starterTemplate = '''
define e = Character("Eileen")

label start:
    scene black with dissolve
    "Welcome to RenFly Editor."
    show red at center
    e "Edit the script on the left, then press Run."
    menu:
        "Try a choice":
            e "Choices work too."
        "Skip":
            pass
    scene white
    e "That's the whole tour. Make something wonderful."
    return
''';
