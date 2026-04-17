define config.screen_width = 1280
define config.screen_height = 960

define openfade = Fade(1.5, 2.0, 2.0, color="#fff")
define longfade = Fade(1.0, 0.5, 1.0)
define flash = Fade(0.1, 0.0, 0.4, color="#fff")
define longdissolve = Dissolve(1.0)
define longerdissolve = Dissolve(2.5)
define doorfade = ImageDissolve("masks/door.png", 1.0, ramplen = 32)
define quickgradientwiperight = ImageDissolve("masks/right.png", 1.5, ramplen = 16)
define quickgradientcirclefade = ImageDissolve("masks/circle.png", 0.5, ramplen = 16, reverse = True)
define gradientcirclefade = ImageDissolve("masks/circle.png", 1.0, ramplen = 16)

image archive bg = Image("images/bg/archive.jpg")
image lecture bg = Image("images/bg/lecturehall.jpg")
image door bg = Image("images/bg/door.jpg")
image letter bg = Image("images/bg/letter.jpg")
image flashback bg = im.Grayscale("images/bg/archive.jpg")
image redcard = Solid((255, 0, 0, 255))
image eri normal = Image("images/characters/eri/eri normal.png")
image enj smile = Image("images/characters/enj/enj smile.png")
image sha normal = Image("images/characters/sha/sha normal.png")

define narrator = Character(None)

label start:
    stop music
    $ renpy.pause()
    play sound "/SE/Z1.opus"

    scene black
    with openfade

    play music "/music/She End.opus" fadein 1.0 noloop
    scene archive bg
    show eri normal at Position(xpos = 0.2)
    show enj smile at Position(xpos = 0.8)
    with longerdissolve

    "Reference Game 4 begins.{w} It compresses Confession coverage."

    nvl clear
    "NVL context reset."
    extend " Extended clause."

    show text "{size=72}{color=#ffffff}Reference Game 4{/color}{/size}" as title at truecenter behind enj
    with longdissolve

    menu:
        "Which Confession feature bucket?"
        "Transitions and staging.":
            "We sample the route RenPy scripts use for named transitions and positioned sprites."
        "Audio and text.":
            "The default route should not choose this branch."

    hide title
    show sha normal at Position(xpos = 0.5) behind enj
    with quickgradientwiperight

    play ME "/ME/rain_2.opus" fadein 0.5 loop
    scene flashback bg
    show eri normal at Position(xpos = 0.15)
    show enj smile at Position(xpos = 0.85)
    with quickgradientcirclefade

    "Grayscale flashbacks, multiple characters, and layered placement are active."

    play sound "/se/ZS4.opus"
    with vpunch
    "A one-shot sound should fire only on its own statement."

    scene door bg
    with doorfade
    "Image dissolves can use named mask files."

    scene red
    with flash
    "Solid color scenes stand in for full-screen RenPy effects."

    scene white
    with gradientcirclefade
    "Reverse and forward gradient fades both resolve."

    stop sound fadeout 0.25
    stop ME fadeout 0.5
    scene lecture bg
    show eri normal at Position(xpos = 0.25)
    show enj smile at Position(xpos = 0.75)
    with longfade

    "Characters return to separate positions after full scene replacement."

    scene letter bg
    with longdissolve
    stop music fadeout 0.5

    "{b}Reference Game 4 Complete{/b}."
    return
