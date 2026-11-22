<!--
#!environment llm_provider opencode
#!environment llm_provider_model opencode-go/glm-5.3-flash
#!environment output_file minirogue.ollmed
#!environment release 3
-->

# Dependencies

* Use only the target language's standard library, including its standard terminal-control facilities (for raw key input, when available). No external packages.
* Text-mode terminal interface drawn with ANSI escape sequences (alternate screen, cursor positioning). No curses.
* Randomness: when the environment variable `SEED` is set, initialize the random generator with that exact value first, so identical runs produce identical maps and monsters.
* When stdin is not a terminal, skip raw-mode setup and read stdin without blocking: every pending byte is processed, in arrival order, as its own turn command — a sequence of characters sent together (for example a piped string of several commands) must apply every one of those commands in sequence, not just the first; on EOF the hero quits the dungeon gracefully.

# Dungeon map

* The dungeon has 3 levels, generated independently. Grid: 60 columns x 17 rows of cells.
* Each level is made of rectangular rooms (between 4 and 7 rooms, each at least 4x3 cells) connected by straight horizontal or vertical corridors carved into walls. `#` marks walls, `.` marks floor, `+` marks a door on the room wall where a corridor meets it.
* Every level except level 3 contains one down-stairs cell `>` placed inside a room floor. Level 3 contains one `A` cell (the Amulet of Hacker) inside a room floor.
* On every level place: one `$` gold pile on floor, one `!` potion on floor, and monsters from the 'Hero and monsters' table, spread on floor cells not occupied by anything else and never adjacent to the stairs.
* The hero `@` starts inside the first room of level 1. The exact placement may be any room floor cell and must respect the SEED initialization.

# Hero and monsters

* The hero `@` has hit points, level (starts 1) and experience (starts 0). Maximum hit points = 10 + 2 per level above 1.
* Monster table (glyph, name, max HP, melee damage when it hits the hero): `b` giant bat 3 1; `d` dog 6 2; `Z` zombie 10 3. Levels 1 and 2 spawn two dogs and two bats; level 3 spawns two zombies, one dog and one bat.
* A move into a monster's cell is a melee attack by the hero: the hero deals a random integer between 1 and 4 damage. If the monster's hit points drop to 0 it dies, the hero gains experience equal to the monster's max HP and gold equal to the monster's number, and the monster's glyph is removed.
* When a monster is adjacent (8 directions) to the hero it attacks the hero: damage is a random integer between 1 and its melee damage value, and the hero loses that many hit points. Otherwise the monster takes one step toward the hero when the Manhattan distance is at most 8, and one random step when farther away or blocked.
* When the hero's hit points reach 0 the game ends with the tombstone (see 'Rendering').
* Gaining a level: when experience reaches or exceeds 10 times the hero's level, level increases by 1 and max hit points increase by 2. This is checked after each hero attack.

# Items and progression

* Walking onto a `$` gold pile collects it: gold increases by a random integer between 1 and 5, the pile disappears, the score for that is kept in gold.
* Walking onto a `!` potion drinks it: current hit points increase by 4 up to the maximum, the potion disappears.
* Walking onto `>` descends to the next level: the hero is placed inside the first room of the new level and a new level map is generated honoring the 'Dungeon map' contract.
* Walking onto `A` wins the game: print the victory line and stop.

# Rendering

* Terminal setup: the first frame switches into the alternate screen buffer (ESC[?1049h) and hides the cursor (ESC[?25l); when the game ends the terminal is restored with the cursor shown (ESC[?25h) and the alternate screen left (ESC[?1049l).
* BETWEEN FRAMES NEVER CLEAR THE WHOLE SCREEN and never use ESC[2J: every frame starts by moving the cursor to the top-left (ESC[H) and drawing each line followed by ESC[K (erase to end of line), so there is no flicker and no residue.
* Every turn the whole screen is redrawn: a HUD line at the top containing exactly `Dungeon: N`, `HP: c/m`, `XP: x`, `Gold: g`, `@: (r,c)` where N is the level number, c current hit points, m maximum, and (r,c) the hero grid position; then the bordered dungeon grid; then a controls reminder line `hjkl move  . wait  q quit`.
* Movement keys: `h` left, `l` right, `j` down, `k` up, `y` up-left, `u` up-right, `b` down-left, `n` down-right, `.` wait (one tick passes), `q` quit gracefully.
* Every final message starts on a FRESH line: before printing it, move the cursor to the bottom of the frame and emit a newline, so the message is never appended to the controls line or any board output.
* In EVERY ending (quit, death, victory) the LAST actions are exactly: print a newline, write the cursor-show sequence ESC[?25h, then write the leave-alternate-screen sequence ESC[?1049l. Both sequences 25h and 1049l MUST be present in the output of every run; leaving the alternate screen without them is a defect.
* On death print a drawn tombstone: a box of dashes and pipes containing `R.I.P  Hero`, `Killed by a monster`, `Level N with G gold` and `XP x`. Then restore the terminal and exit 0.
* On victory print the line `You escaped with the Amulet of Hacker! Score: G` instead, restore the terminal and exit 0. On `q` quit print `Quit - Score: G` and restore.

# Entry point

* When executed directly ($PROGRAM_NAME == __FILE__ or the idiomatic equivalent), run the turn loop: read one command, apply it, monster turns, redraw, until death, victory or quit. The generated program must be COMPLETE and runnable: every context in this document implemented together with the entry point function; a response that omits any context or the entry point function is an invalid artifact, so before finishing re-check that each section exists exactly once in the output.
* Wrap execution: on StandardError print a line containing FAIL-FAST and the reason and exit 1. Exit 0 on the graceful endings.
