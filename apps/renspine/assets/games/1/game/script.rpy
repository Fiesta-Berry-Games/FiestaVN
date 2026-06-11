# Fiesta Skit - the RenSpine showcase story.
#
# A short branching skit that exercises the renpy_spine bridge end to end:
#   - two (sometimes three) Spine characters on stage at once, with a stable
#     skin identity per tag (erikari / harri / misaki),
#   - mid-dialogue animation switching via `show <tag> <emote>`,
#   - scene changes (built-in solid colors and Solid() image definitions,
#     which also clear the sprite stage),
#   - two branching menus with jumps, labels, and a final return,
#   - a looping music track with fade-in and a fade-out stop.
#
# Music: "illurock" from Ren'Py's "The Question" demo game
# (https://www.renpy.org), copied from
# apps/renfly_player/assets/games/the_question/game/illurock.opus
# for showcase purposes.

define e = Character("Erikari", color="#ff5c8a")
define h = Character("Harri", color="#56c8f5")
define m = Character("Misaki", color="#ffd166")

init:
    # Spine sprite attributes follow the renpy_spine naming convention:
    # "<skin>-<group>/<animation>.spine" selects the skeleton skin and the
    # animation, e.g. "erikari-emotes/wave.spine" -> skin `erikari`,
    # animation `emotes/wave`.
    image erikari idle       = Image("erikari-movement/idle-front.spine")
    image erikari wave       = Image("erikari-emotes/wave.spine")
    image erikari determined = Image("erikari-emotes/determined.spine")
    image erikari idea       = Image("erikari-emotes/idea.spine")
    image erikari dramatic   = Image("erikari-emotes/dramatic-stare.spine")
    image erikari excited    = Image("erikari-emotes/excited.spine")
    image erikari laugh      = Image("erikari-emotes/laugh.spine")
    image erikari love       = Image("erikari-emotes/love.spine")
    image erikari flushed    = Image("erikari-emotes/flushed.spine")
    image erikari hooray     = Image("erikari-emotes/hooray.spine")

    image harri idle     = Image("harri-movement/idle-front.spine")
    image harri wave     = Image("harri-emotes/wave.spine")
    image harri scared   = Image("harri-emotes/scared.spine")
    image harri thinking = Image("harri-emotes/thinking.spine")
    image harri confused = Image("harri-emotes/confused.spine")
    image harri sweat    = Image("harri-emotes/sweat.spine")
    image harri laugh    = Image("harri-emotes/laugh.spine")
    image harri hooray   = Image("harri-emotes/hooray.spine")
    image harri fawning  = Image("harri-emotes/fawning.spine")
    image harri sulk     = Image("harri-emotes/sulk.spine")
    image harri seeno    = Image("harri-emotes/see-no-evil.spine")
    image harri idea     = Image("harri-emotes/idea.spine")

    image misaki wave    = Image("misaki-emotes/wave.spine")
    image misaki excited = Image("misaki-emotes/excited.spine")
    image misaki perfect = Image("misaki-emotes/just-right.spine")

    # Solid-color stage backdrops.
    image bg plaza  = Solid("#5d2a64")
    image bg sunset = Solid("#b3543a")
    image bg night  = Solid("#1a1035")

label start:
    scene black
    play music "audio/illurock.opus" fadein 1.0

    show erikari wave at left
    show harri wave at right

    e "Psst! Harri! Wake up! The FiestaBerry anniversary is TONIGHT."
    h "Tonight?! I thought we had at least another week!"

    show harri scared at right
    h "We have no decorations, no music, no churros... we have NOTHING."

    show erikari determined at left
    e "Then we throw the greatest last-minute fiesta this plaza has ever seen."

    scene bg plaza
    show erikari idea at left
    show harri thinking at right

    e "First things first: every great fiesta needs a theme!"
    h "Hmm. A theme. Right. Themes are... definitely a thing I know about."

    menu:
        e "What kind of fiesta should it be?"

        "Grand and dramatic!":
            jump theme_dramatic

        "Cozy and sweet.":
            jump theme_cozy

label theme_dramatic:
    show erikari dramatic at left
    e "Picture it: a hundred lanterns. A confetti cannon. A LLAMA."

    show harri confused at right
    h "Where would we even get a llama by sunset?"

    show erikari excited at left
    e "Details, details! The plaza will GLOW, Harri. People will weep."

    show harri sweat at right
    h "My entire budget is three coins and a shiny button."

    show erikari laugh at left
    e "Then the button shall be our guest of honor!"

    show harri laugh at right
    h "Okay, fine, that did make me laugh. Dramatic it is."

    jump music_problem

label theme_cozy:
    show erikari love at left
    e "Little paper lanterns. Warm churros. Everyone gets a blanket."

    show harri hooray at right
    h "A blanket fiesta! Now THAT is within budget."

    e "And hot chocolate so thick the spoon stands up on its own."

    show harri fawning at right
    h "You had me at churros, honestly."

    show erikari laugh at left
    e "Cozy it is. Tonight the plaza will feel like one big hug."

    jump music_problem

label music_problem:
    scene bg sunset
    show erikari idle at left
    show harri idle at right

    h "Decorations: sorted. But Erikari... I just got word."

    show harri sulk at right
    h "The band cancelled. No band. No music. A silent fiesta."

    show erikari flushed at left
    e "A silent fiesta is just a meeting with snacks!"

    menu:
        h "So... who is going to save the music?"

        "Erikari improvises a one-woman band.":
            jump diy_band

        "Call DJ Misaki!":
            jump call_misaki

label diy_band:
    show erikari determined at left
    e "Hand me two pot lids and a kazoo. I have a vision."

    show harri seeno at right
    h "I can't watch. I also, somehow, cannot look away."

    show erikari hooray at left
    e "Ta-da! I call it 'Symphony for Cookware in D Minor'."

    show harri laugh at right
    h "It's terrible! It's perfect! The crowd is going to love it!"

    jump finale

label call_misaki:
    show harri idea at right
    h "Wait. Misaki still owes me a favor from the karaoke incident."

    show misaki wave at center
    m "Somebody said 'fiesta emergency'?"

    show erikari excited at left
    e "Misaki! You came! And you brought the speakers!"

    show misaki excited at center
    m "I brought ALL the speakers."

    show harri hooray at right
    h "The karaoke incident is hereby officially forgiven."

    show misaki perfect at center
    m "Then let's turn this plaza up to eleven."

    jump finale

label finale:
    scene bg night
    show erikari hooray at left
    show harri hooray at right

    "Lanterns flicker on, one by one, as the first guests drift into the plaza."

    e "We actually pulled it off."
    h "WE pulled it off. Team fiesta."

    show erikari wave at left
    show harri wave at right

    e "Happy anniversary, FiestaBerry!"
    h "And thanks for watching the RenSpine showcase - tap restart to pick a different path!"

    stop music fadeout 2.0

    "Fin."

    return
