# Sylvie & Sylvie: a two-character staging demo using the bundled art.
# Green-dress Sylvie stands at left, blue-dress Sylvie at right, and the
# expression swaps show how `show ... at <position>` re-stages a sprite.

define sg = Character("Sylvie (green)", color="#c8ffc8")
define sb = Character("Sylvie (blue)", color="#c8c8ff")

# Sprites replace each other when they share a tag (the first word of the
# image name), so the two Sylvies each get their own tag backed by the
# bundled art. This is how one set of art plays two roles at once.
image sylvieg normal = "sylvie green normal.png"
image sylvieg smile = "sylvie green smile.png"
image sylvieg giggle = "sylvie green giggle.png"
image sylvieg surprised = "sylvie green surprised.png"
image sylvieb normal = "sylvie blue normal.png"
image sylvieb smile = "sylvie blue smile.png"
image sylvieb giggle = "sylvie blue giggle.png"
image sylvieb surprised = "sylvie blue surprised.png"

label start:
    play music "illurock.opus"
    scene bg meadow
    show sylvieg normal at left
    show sylvieb normal at right
    sg "Hey! You look exactly like me."
    sb "Funny — I was about to say the same thing about you."
    show sylvieg smile at left
    sg "I love your dress, though. Blue really suits you."
    show sylvieb giggle at right
    sb "Thanks! Green is very you, too."
    show sylvieg surprised at left
    sg "Wait. If you're me... who's writing this story?"
    show sylvieb surprised at right
    sb "Oh no. You're right. Someone is typing this right now."
    menu:
        "Wave at the writer":
            show sylvieg giggle at left
            show sylvieb smile at right
            sg "Hi, writer! Give us a happy ending, please."
            sb "And maybe a bigger meadow."
        "Pretend nothing happened":
            show sylvieg normal at left
            show sylvieb normal at right
            sg "Let's just enjoy the meadow and say no more about it."
            sb "Agreed. Lovely weather we're rendering today."
    show sylvieg smile at left
    show sylvieb smile at right
    sb "Either way, it's nice not to be out here alone."
    sg "It really is. See you in the next preview."
    return
