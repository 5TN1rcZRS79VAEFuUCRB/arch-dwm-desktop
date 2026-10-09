# Show only Again (1) and Good (3); ignore Hard (2) and Easy (4), including their keys.
from aqt import gui_hooks


def only_again_good(buttons, reviewer, card):
    return tuple(b for b in buttons if b[0] in (1, 3))


def block_hard_easy(ease_tuple, reviewer, card):
    proceed, ease = ease_tuple
    return (proceed and ease in (1, 3), ease)


gui_hooks.reviewer_will_init_answer_buttons.append(only_again_good)
gui_hooks.reviewer_will_answer_card.append(block_hard_easy)
