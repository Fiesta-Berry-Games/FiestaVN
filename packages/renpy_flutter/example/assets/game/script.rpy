# Minimal Ren'Py script bundled with the renpy_flutter example.
# It exists only to show the package rendering something out of the box.
# Use "Open game folder" in the app to load a real Ren'Py game instead.

define e = Character("Eileen")

label start:
    scene black

    "Welcome to the renpy_flutter example."

    e "Hi! I'm Eileen, running inside a Flutter app."

    menu:
        "Show me another line.":
            e "renpy_flutter renders Ren'Py script with renpy_core underneath."
        "That's enough.":
            pass

    e "To play a real game, go back and choose \"Open game folder\"."

    return
