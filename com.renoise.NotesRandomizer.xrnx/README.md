# Randomize Notes

Randomize Notes changes the notes in your pattern or phrase to new notes in a
scale and key. It can also shuffle the notes you already have. Use it to make
new variations of an existing melody, bass line or chord pattern.

Only the note changes. Instrument, volume, panning, delay and effects stay as
they are. Note-offs and empty notes are never touched.

## Opening it

- Choose *Tools > Randomize Notes...* in the main menu.
- Right-click in the Pattern Editor or the Phrase Editor and choose *Randomize Notes...*.
- Press one of the key bindings listed below.

The dialog stays open while you work. Each run is one undo step.

## The dialog

**Where** chooses which notes to change. The list follows the editor you are in.

- In the Pattern Editor, the choices are Selection in Pattern, Track in Pattern,
  Track in Song, Whole Pattern and Whole Song.
- In the Phrase Editor, the choices are Selection in Phrase and Whole Phrase.

Each editor remembers its own choice. Song scopes visit each pattern once,
even when it repeats in the sequence or appears as an alias.

**How** chooses what to do.

- *Shuffle* keeps the notes that are there and mixes up their order.
- *Chaos* picks from all 12 notes.
- *Custom* picks from the notes you choose. Click the piano keys to add or
  remove notes. A new Custom scale starts from the scale you had before.
- The other 35 entries are the scales of Renoise's own instrument Scale menu,
  from Natural Major to Nine-Tone Scale.

**Key** sets the root of the scale. You can also click a piano key to make it the root.

The **piano** shows the notes of the scale. A dot marks each scale note and a
ring marks the root. The line under it lists the notes, starting at the root.

**Options**

- *Nearest neighbour* moves each note to the next scale note up or down, instead
  of picking a random one. *Rand* chooses up or down at random for each note.
- *Preserve notes in scale* keeps notes that are already in the scale.
- *Preserve octaves* keeps each note in its octave. Turn it off to pick a random
  octave between the two values you set.
- *Ignore muted tracks and columns* skips muted tracks, muted note columns and
  muted phrase columns.

Options that do not apply to the current mode are greyed out.

Hidden note columns are never changed, even when they still hold notes.
Script phrases have no note lines, so the tool leaves them alone.

**Keys in the dialog:** Return runs, Esc closes, Up and Down change How, Left
and Right change Key.

## Key bindings

Find these in *Edit > Preferences > Keys*. They run with the dialog's last
settings, so you can use them without opening the dialog.

| Section | Binding | Changes |
|---|---|---|
| Pattern Editor | Block Operations: Randomize Notes | Selection in Pattern |
| Pattern Editor | Track Operations: Randomize Notes in Pattern | Track in Pattern |
| Pattern Editor | Track Operations: Randomize Notes in Song | Track in Song |
| Pattern Editor | Pattern Operations: Randomize Notes | Whole Pattern |
| Pattern Editor | Tools: Randomize Notes... | Opens the dialog |
| Phrase Editor | Block Operations: Randomize Notes | Selection in Phrase |
| Phrase Editor | Phrase Operations: Randomize Notes | Whole Phrase |
| Phrase Editor | Phrase Operations: Randomize Notes... | Opens the dialog |

## Install

Drag `com.renoise.NotesRandomizer.xrnx` onto Renoise. It replaces version 1.11
if you have it. Renoise 3.5 or newer is needed.

## Changes in 2.00

- The tool now works with Renoise 3.5 (API 6.2).
- It now works in the Phrase Editor, on a selection or on the whole phrase.
- A new piano shows the scale. You pick Custom notes on the piano.
- The scales are now Renoise's own 35 scales, with correct notes.
- The dialog has a new layout that keeps its size. Options are greyed out instead of hidden.
- Settings are saved between sessions.
- A status message says what changed, or why nothing did.
- The key bindings now run at once with the saved settings. In 1.11, the first
  press opened the dialog instead.
- These bugs are fixed:
  - Two scales could crash the tool.
  - Nearest neighbour picked the wrong note in keys other than C.
  - Notes at the top and bottom octave moved the wrong way.
  - Two runs within one second gave the same result.
  - Hidden note columns were changed.
  - Aliased tracks were changed twice in song scopes.
  - Running on a phrase switched off "Ignore muted" for good.
