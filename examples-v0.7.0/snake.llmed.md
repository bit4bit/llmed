<!--
#!environment llm_provider opencode
#!environment llm_provider_model opencode-go/glm-5.3-flash
#!environment output_file snake.ollmed
#!environment release 1
-->

# Dependencies

* Use only the target language's standard library, including its standard terminal-control facilities (for raw key input, when available). No external packages.
* Draw exclusively with ANSI escape sequences (alternate screen buffer, cursor hide/show, explicit cursor positioning).
* The game must also work when stdin is NOT a terminal (piped or closed input): in that case skip raw-mode setup, never block on input, and treat EOF as simply having no key presses.

# Game state

* Board: fixed grid of 24 columns x 12 rows of cells surrounded by a border drawn with ASCII or box-drawing characters.
* The snake starts 3 cells long, horizontally centered on the middle row, moving right. Exactly one food item sits at a random free cell.
* Every tick (150 milliseconds) the snake moves one cell in its current direction.
* Eating the food makes the snake one cell longer, respawns the food at a new random free cell, and increases the score by 1. Score starts at 0.
* Moving into the border or into the snake's own body ends the game (game over).

# Rendering and controls

* Every tick the whole board is redrawn: one top line showing exactly `Score: N` (N = current score), then the bordered grid with the snake head drawn as `O`, the snake body as `o`, and the food as `*`.
* Controls: direction keys `h`, `j`, `k`, `l` and the arrow keys; `q` quits the game immediately.
* Input reading never blocks the game loop. Pressing a key that reverses direction into the snake's own neck (e.g. moving `l` while currently moving `h`) is ignored.
* On game over or quit, restore the terminal (show cursor, leave the alternate screen) and print one final line containing `GAME OVER` and the final score, in the shape `GAME OVER - Score: N`.
* Exit status 0 for both normal endings; the 'Entry point' context owns the main loop and the guard.

# Entry point

* When executed directly ($PROGRAM_NAME == __FILE__ or the target language's idiomatic equivalent), run the game: initialize state, loop tick/render/input until game over or quit, print the final line, restore the terminal.
* Wrap execution: on StandardError print a line containing FAIL-FAST and the reason and exit 1. Exit 0 on normal endings.
