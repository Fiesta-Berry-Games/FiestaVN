init:
    # Ali → erikari       Harp → harri
    image ali idle   = Image("erikari-movement/idle-front.spine")
    image ali angry  = Image("erikari-emotes/angry.spine")
    image ali laugh  = Image("erikari-emotes/laugh.spine")

    image harp idle  = Image("harri-movement/idle-front.spine")
    image harp shrug = Image("harri-emotes/shrug.spine")
    image harp wave  = Image("harri-emotes/wave.spine")

label start:
    $ ali = Character("Ali")
    $ hp  = Character("Harp")

    scene
    show ali idle  at left
    show harp idle at right

    ali "Hi there!  I'm Ali – a Spine character with the *erikari* skin."
    hp  "And I'm Harp, rocking the *harri* skin."

    ali "Watch us switch animations at runtime!"

    show ali angry               # no need to hide – just replace
    ali "Grrr… now I'm angry!"

    hp  "Whoa, deep breaths…"

    show ali laugh
    ali "Haha, just kidding!"

    menu:
        "Ask Harp to wave":
            show harp wave
            hp "Hello there! 👋"
            pause 0.4
            show harp shrug
            hp "So… what now?"
        "End the demo":
            pass

    hp "That concludes the RenSpine showcase. Tap the restart button to watch it again!"
    return
