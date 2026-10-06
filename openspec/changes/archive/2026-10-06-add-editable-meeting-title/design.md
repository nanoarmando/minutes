## Context

`NoteWriter` already builds file names from `fileNamePattern` (with collision suffixes) and replaces parts of a note
atomically (summary markers, tags in front matter). `NoteIndex` watches the folder and identifies notes by
`minutes_id`; sidecars and kept audio are named by that id, so a rename does not break them. `MeetingContext` reads
the title from the front matter first.

## Goals / Non-Goals

**Goals:**
- Edit the title in place from the detail header and keep the file name consistent with it.

**Non-Goals:**
- Regenerating the title with the model, or renaming from the list or the menu.
- Renaming kept audio or sidecars (they are keyed by id).
- Changing the calendar event stored in the sidecar.

## Decisions

- **Writer operation:** `NoteWriter.updateTitle(of:to:)` replaces the `title` scalar in the front matter and the
  first `# ` line of the body, writes atomically, then moves the file to the pattern-derived name using the existing
  name builder and collision logic, and returns the new URL. Reusing the existing name builder keeps one place that
  sanitizes titles for file names.
- **Selection:** selection is by meeting id, so the index refresh after the move keeps the meeting selected.
- **UI:** the large title becomes a `TextField` on click (`@FocusState`); `onSubmit` saves, `onExitCommand` and losing
  focus cancel. The field is disabled while the detail is busy.
- **Order:** content first, then move. A failed move leaves a correct note under its old name and shows the error.

## Risks / Trade-offs

- [The note is open in an external editor during the rename] → the editor may keep the old path; same as renaming
  in Finder.
- [Index briefly sees a removed and an added file] → it keys by id and refreshes once; the selection follows the id.
- [Characters invalid in file names] → handled by the existing file name builder.
