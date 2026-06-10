# Sourced from: https://www.reddit.com/r/RenPy/comments/uld9bu/comment/i7uqepm/

label start:
    menu:
        "Stay for a peek":
            Thoughts "I'm not gonna get caught... ;)"
            scene S2 with dissolve
            Thoughts "I'd better stay quiet."

            show S3 with dissolve
            $ MasterClock.AddTime(0, 0, 1)
            Thoughts "Oop, nevermind. Right apartment."
            show S4 with dissolve
            Thoughts "But I guess she hasn't turned around yet."
            show S5 with dissolve
            Thoughts "Though if she does turn around, I'm probably fucked."
            menu:
                "Keep looking":
                    show S6 with dissolve
                    Thoughts "Ahh!"
                    Thoughts "I'd better go fast."
                    show S7
                    Riley "Huh?{p=0.3}{nw}"
                    $ AyyNoticed1 = True
                    $ AyyInfo.L += 1
                "Go back and wait in the living room":
                    Thoughts "Nope, fuck this."
        "Nope, nothing said, better head back and wait.":
            scene LR5
