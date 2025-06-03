init:
    image erikari idle   = Image("erikari-movement/idle-front.spine")
    image erikari angry  = Image("erikari-emotes/angry.spine")
    image erikari laugh  = Image("erikari-emotes/laugh.spine")
    image erikari wave  = Image("erikari-emotes/wave.spine")

    image harri idle  = Image("harri-movement/idle-front.spine")
    image harri shrug = Image("harri-emotes/shrug.spine")
    image harri wave  = Image("harri-emotes/wave.spine")
    image harri laugh  = Image("harri-emotes/laugh.spine")

label start:
    $ erikari = Character("Erikari")
    $ harri = Character("Harri")

    # Clear scene but immediately show both characters
    scene
    show erikari wave at left
    show harri wave at right

    # Add a small pause to ensure characters are loaded
    pause 0.1

    erikari "Hi there! I'm Erikari – a Spine character with the *erikari* skin."
    harri "And I'm Harri, rocking the *harri* skin."
    show harri shrug at right

    erikari "Watch us switch animations at runtime!"

    show erikari angry at left
    erikari "Grrr… now I'm angry!"

    harri "Whoa, deep breaths…"

    show erikari laugh at left
    erikari "Haha, just kidding!"

    menu:
        "Ask Harri to wave":
            show harri wave at right
            harri "Hello there! 👋"
            pause 0.4
            show harri shrug at right
            harri "So… what now?"
        "End the demo":
            pass

    harri "That concludes the RenSpine showcase. Tap the restart button to watch it again!"
    return