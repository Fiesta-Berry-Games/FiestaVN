# Sourced from: https://www.renpy.org/dl/4.1/tutorial.html

init:
    image whitehouse = Image("whitehouse.jpg")
    image eileen happy = Image("eileen_happy.png")
    image eileen upset = Image("eileen_upset.png")

label start:
    $ e = Character('Eileen')

    scene whitehouse
    show eileen happy

    e "I'm standing in front of the White House."

    show eileen upset

    e "I once wanted to go on a tour of the West Wing, but you have to
       know somebody to get in."

    "For some reason, she really seems upset about this."

    e "I considered sneaking in, but that probably isn't a good idea."
