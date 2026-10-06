## ADDED Requirements

### Requirement: Title edits
Saving a new title SHALL replace only the `title` front matter value and the note's first-level heading (when it is
still present), leaving the rest of the file unchanged, with an atomic write. The file SHALL then be renamed with
the current file name pattern and the new title, in the same folder, appending " 2", " 3"… on a collision with
another file; it SHALL NOT be renamed when the resulting name is the same. The sidecar and kept audio SHALL stay
linked to the meeting. If the rename fails, the title change SHALL be kept and the error SHALL be shown.

#### Scenario: Title and file name updated
- **WHEN** the note "2026-10-06 1133 Jose Ricardo TVP.md" is renamed to "TVP tracking scope"
- **THEN** its front matter title and heading are "TVP tracking scope", the file is "2026-10-06 1133 TVP tracking scope.md", and the summary, transcript and sidecar are unchanged

#### Scenario: Name collision
- **WHEN** the new file name already belongs to another note
- **THEN** the renamed file gets " 2" appended and the other note is untouched

#### Scenario: Heading removed by the user
- **WHEN** the user had deleted the "# Title" heading in an editor and then renames the meeting
- **THEN** only the front matter title changes and no heading is added
