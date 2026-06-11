# Fiesta rehearsal - the RenSpine Editor's Spine demo.
#
# Two Spine characters (skins of the bundled chibi-stickers skeleton) staged
# left and right, switching animations mid-dialogue. Spine sprite attributes
# follow the renpy_spine naming convention: an asset path
# "<skin>-<group>/<animation>.spine" selects the skeleton skin and the
# animation, e.g. "erikari-emotes/wave.spine" -> skin `erikari`, animation
# `emotes/wave`.

define e = Character("Erikari", color="#ff5c8a")
define h = Character("Harri", color="#56c8f5")

init:
    image erikari idle    = Image("erikari-movement/idle-front.spine")
    image erikari wave    = Image("erikari-emotes/wave.spine")
    image erikari excited = Image("erikari-emotes/excited.spine")
    image erikari laugh   = Image("erikari-emotes/laugh.spine")
    image erikari idea    = Image("erikari-emotes/idea.spine")
    image erikari hooray  = Image("erikari-emotes/hooray.spine")

    image harri idle     = Image("harri-movement/idle-front.spine")
    image harri wave     = Image("harri-emotes/wave.spine")
    image harri thinking = Image("harri-emotes/thinking.spine")
    image harri sweat    = Image("harri-emotes/sweat.spine")
    image harri laugh    = Image("harri-emotes/laugh.spine")
    image harri hooray   = Image("harri-emotes/hooray.spine")

    # Solid-color stage backdrop.
    image bg stage = Solid("#5d2a64")

label start:
    scene bg stage

    show erikari wave at left
    show harri wave at right

    e "Welcome to the RenSpine Editor! Harri and I are live Spine skeletons."
    h "Same rig, different skins. Wave at the nice author, me."

    show erikari excited at left
    e "Watch this: a single show statement swaps my animation in place."

    show harri thinking at right
    h "So show harri thinking just... cross-fades me into pondering?"

    show erikari laugh at left
    e "Exactly! No sprite sheets, no reloads. The skeleton stays warm."

    show harri sweat at right
    h "And I perspire on cue. Extremely dignified technology."

    show erikari idea at left
    e "Open the Characters gallery to drop more poses straight into the script."

    show erikari hooray at left
    show harri hooray at right
    h "Or tap L, C, R to stage us at left, center, or right. Curtain call!"

    "Fin."

    return
