# Family Feud — CCIS Edition

A host-driven Family Feud game for two departments (default **DCS vs DIT**), built in
**Godot 4**. The host runs the board with mouse clicks: click an answer when a team guesses
correctly, press **WRONG ANSWER** for a strike, reveal the leftovers one by one at the end
of the round, then carry the totals into the next round.

## Quick start

1. Open `project.godot` in Godot 4.x, or run:
   ```
   godot --path .
   ```
2. The **main menu** appears. Press **START A GAME**.
3. **GAME SETUP** opens: tick the questions you want, rename the teams if you like, then
   press **START GAME**. The show begins on the first ticked question.
4. Press **ESC** at any time to bring the setup panel back up over the live game.

The flow is always **Main Menu → Game Setup → Game → Results**, and every screen has a
button back to the menu.

## Playing a round

| Control | What it does |
| --- | --- |
| Click an answer card | The answering team guessed it correctly — points are awarded and the turn passes |
| `WRONG ANSWER ✖` | A strike. Costs a guess. On the 3rd strike the turn passes |
| `ANSWERING:` team buttons | Force whichever team answers next (also clears their strikes) |
| `END ROUND` | Close the round early, or dump the remaining reveals |
| `REVEAL ONE ▶` | Reveals **exactly one** hidden answer (guideline 6) |
| `NEXT QUESTION ▶` / `SEE RESULTS ▶` | On the between-boards panel: both teams and their totals, then continue |
| `⚙ SETUP (ESC)` | Brings up the setup panel over the board |

Press **ESC** whenever you like: it closes the question editor first, then the setup panel,
and from the board it opens setup. Nothing you change in setup is applied until you press
**START GAME**.

A round ends when the board is cleared **or** the guess limit is reached. The finished board
holds for a beat so the last reveal lands, then a calm score panel shows both teams and their
totals with a single **NEXT QUESTION** button, so the switch never feels crowded.
Totals accumulate
across every round; the highest total after the last board wins. If the totals are level and
a tie-breaker board exists, a sudden-death board decides it (guideline 11) — those points
decide the winner only and are **not** added to the totals.

## Game Setup

`START A GAME` on the menu — or `ESC` during a show — opens the setup screen. It is one
page that fits the window with no scrolling: the question bank on the left, teams and rules
on the right, and the two action buttons along the bottom.

### Question bank (left)

| Control | What it does |
| --- | --- |
| Tick box | Include that question in this show. Points carry over between the ticked boards |
| `✓ SELECT ALL` / `✕ SELECT NONE` | Tick or untick everything at once |
| `＋ NEW QUESTION` | Opens the editor for a brand new question |
| `✎ EDIT` | Edits the selected question |
| `⧉ COPY` | Duplicates the selected question (handy for variants) |
| `▲` / `▼` | Moves the selected question up or down the running order |
| `🗑 DELETE` | Deletes the selected question (asks for confirmation first) |

Click a question to **select** it — the line above the toolbar tells you which question the
buttons will act on, and the focused row gets a gold outline. Every row also shows
`8 answers · 100 pts`, so a broken board is obvious at a glance.

### Teams and rules (right)

Team names are free text. Like the rules, they are **remembered in `data/settings.json`**
for the next launch. The `First to answer` choices use the real names, so they read
`DCS first` / `DIT first` / `Alternate rounds`.

### Saving

- Question changes are written on **START GAME**.
- Team names and rules are written only when they actually change.
- Both go into `res://data/`, which is **read-only in an exported build** — run the game
  from the project (editor or `--path .`) to use the editor, or ship the JSON and edit it
  by hand.

### Editing one question

`＋ NEW QUESTION` and `✎ EDIT` open the same editor: a name for the scoreboard, the question
text, then one row per answer with its points. `+ ADD ANOTHER ANSWER` adds rows (up to 12),
`✖` removes one, and the counter on the right turns amber when the board does not total 100.

## Files

```
project.godot                 autoload + 1600x900 window + shared theme
data/settings.json            team names and default rules
data/questions.json           the questions, answers and points
scenes/Main.tscn              root: swaps between the four screens
scenes/MainMenu.tscn          title screen: start a game, how to play, quit
scenes/GameScreen.tscn        board, scoreboard, strikes, timer, controls
scenes/SetupScreen.tscn       question bank + teams and rules, one page
scenes/QuestionEditor.tscn    add/edit one question
scenes/ResultScreen.tscn      final scores and per-round breakdown
scenes/AnswerCard.tscn        one board slot
scenes/ui/theme.tres          colours and button styling
scripts/game_data.gd          autoload: loads, validates and saves the JSON
scripts/game_screen.gd        round flow, turns, strikes, scoring, tie-breaker
scripts/setup_screen.gd       question bank, team names, rules
scripts/question_editor.gd    answer rows
scripts/answer_card.gd        reveal animation
scripts/result_screen.gd      scoreboard
scripts/main_menu.gd          title screen
scripts/main.gd               screen navigation
tests/smoke_test.gd           headless full-game test
tests/save_test.gd            headless save/reload test (puts the files back)
tests/layout_test.gd          headless "does it still fit 1600x900?" test
```

## Settings

Edit `data/settings.json`, or change them in the setup screen — team names and rules set
there are written straight back to that file, so the next launch opens the same way.

| Key | Default | Meaning |
| --- | --- | --- |
| `teams` | `["DCS","DIT"]` | The two team names |
| `guesses_per_round` | `10` | Guesses before the round is forced to end (guideline 5) |
| `strikes_per_turn` | `3` | Wrong answers in a row before the turn passes |
| `seconds_per_guess` | `0` | Countdown per turn. `0` switches the timer off (guideline 9) |
| `tie_breaker_enabled` | `true` | Play a sudden-death board when totals are level |
| `first_round_starter` | `2` | `0` = team 1 always, `1` = team 2 always, `2` = alternate each round |
| `answer_columns` | `0` | `0` = automatic (2 columns up to 8 answers) |

## Question format

```json
{
  "name": "Round 1",
  "question": "Mga rason kung bakit hindi nag-ruruncode?",
  "answers": [
    { "text": "Syntax", "points": 30 },
    { "text": "Semicolon", "points": 24 }
  ]
}
```

Answers are sorted highest-first automatically, so the file order does not matter. Points
should add up to 100 like a real survey — the loader prints a note in the Output panel when
a board does not. Questions 1 and 2 currently total 100; question 3 totals 99 as supplied.

When the in-game editor saves, it writes the keys back in alphabetical order. That is
cosmetic, but it does mean a hand-edited file may look re-ordered after the first save from
inside the game.

## Tests

```
godot --headless --path . --script res://tests/smoke_test.gd
godot --headless --path . --script res://tests/save_test.gd
godot --headless --path . --script res://tests/layout_test.gd
```

- `smoke_test.gd` — **91 checks**. Plays three full games headlessly through the real flow
  (menu → setup → board), covering alternating turns, strikes, one-by-one reveals, totals
  carrying over between rounds, ticking a subset of questions, renaming a team, the question
  editor and the tie-breaker.
- `save_test.gd` — adds a question and renames the teams, reloads both files from disk to
  prove the round-trip, then **puts both JSON files back byte for byte**, so it is safe to
  run as often as you like.
- `layout_test.gd` — measures the real 1600x900 layout and fails if any screen would need
  scrolling or overflow the window.
