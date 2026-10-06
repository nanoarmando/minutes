## Why

A meeting's title comes from the calendar event, from the model, or is "Meeting <date> <time>". When it is wrong or
too generic, the only way to change it is to edit the front matter in another editor, and the file keeps its old
name.

## What Changes

- Clicking the title in the meeting detail turns it into a text field; Enter saves, Escape cancels, an empty title is
  not accepted.
- Saving updates the `title` front matter and the `# Title` heading of the note, and renames the file with the
  file name pattern (collisions get " 2", " 3"…).
- Later summaries, corrections and re-tags use the new title as meeting context.

## Capabilities

### New Capabilities
None.

### Modified Capabilities
- `meetings-window`: the title can be edited from the detail view.
- `meeting-notes`: title edits update the note in place and rename the file.

## Impact

- Code: the detail header, a note writer operation for the title and the rename.
- The note format does not change. The notes dictionary refreshes through the existing index update.
- No new setting, permission, dependency or network request.
