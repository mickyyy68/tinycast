# Notes

Notes is an unlimited local collection of plain Markdown files in one persistent floating editor. One
window edits one active note at a time; its title opens the compact searchable switcher, while Search
Notes opens the main palette as a wide list-and-preview browser.

The interaction reference remains Raycast's official [Notes overview](https://www.raycast.com/core-features/notes)
and [launch article](https://www.raycast.com/blog/raycast-notes), but Tinycast's storage is deliberately
direct: the files in its Notes folder are the complete library.

## Invariants

- **One regular, non-hidden `.md` file is one note.** Its filename without the extension is its title;
  the source contains no frontmatter, embedded ID, or title field, and there is no database or sidecar.
- **There is no note-count limit.** Search presents at most 200 ranked rows, but it examines the whole
  collection and creation never consults a product limit.
- **Only the active note can be dirty.** Switching, creating, renaming, and deleting first flush it, so
  collection navigation cannot abandon an in-memory draft.
- **A save never overwrites an unseen external edit.** `NotesRepository` coordinates the mutation and
  compares the byte revision immediately before atomic replacement, rename, or Trash.
- **Search and preview are on demand and unindexed.** An empty query reads metadata only; a nonempty
  query reads bodies sequentially off-main, and the browser retains only the selected preview source.
- **The editor never transforms canonical Markdown.** A Foundation-only parser and display projection
  map between literal UTF-16 source and the collapsed TextKit 2 buffer; only canonical source reaches
  `NotesStore`, search, conflicts, or disk.
- **Off means no entry point or Notes work.** The feature is off by default; its shortcuts no-op, its
  commands are absent, and enabling alone does not enumerate or create the Notes directory.
- **The top edge is the resize anchor.** `NotesWindowController` alone owns the frame while the active
  document grows downward, stays expanded when content is deleted, and scrolls after its screen-aware
  maximum.

## Storage and identity

The per-channel directory is:

```text
~/Library/Application Support/<bundle-id>/Notes/
```

`NoteID` is the relative filename. A rename therefore returns a new identity; there are no per-note
launcher items, hotkeys, favorites, or visibility settings that could retain the old one. Immediate
regular `.md` children are sorted by modification date, then localized title. Subdirectories, hidden
files, and symbolic links are ignored.

Create uses `Untitled.md`, then `Untitled 2.md`, and so on. The same collision rule applies to rename
with case- and diacritic-insensitive comparison. The earlier `Floating Note.md` is already a valid note
and appears through ordinary enumeration; there is no migration branch. The active relative filename
is local UI state in UserDefaults and does not ride settings backups.

`NotesRepository` owns list, create, load, save, rename, Trash, conflict-copy, and search reads. Every
URL is validated as an immediate child of the injected directory. It lives in `Service/` because it
performs filesystem effects; `NotesStore` drives its blocking work from detached tasks.

## Ownership and enablement

`AppCore` owns `NotesStore`, `NotesSearchSession`, and `NotesMenuBarController`, then lazily constructs
`NotesCoordinator`. `NotesView` receives only the coordinator through `@Environment`; it never receives
`AppCore` or mutates the store.

Settings > Notes owns `AppSettings.notesEnabled`, which is false when absent. The pane lists **Show
Notes**, **Create Note**, and **Search Notes** from `CommandCatalog`, so it can still render them while
`AppIndex` omits them. Every row shares its `VisibilityStore` checkbox and `HotKeyAction` recorder with
Settings > Commands. **Show Notes in Menu Bar** optionally installs a separate `text.page` status item
that opens the same editor with one click. Both Notes settings are included in settings backups because
they grant no permission and start no background work.

`AppCore` observes both switches. It calls `NotesCoordinator.applyEnabled()` for the feature and applies
the status-item presence only when Notes and its menu-bar setting are both on. The coordinator projects
all three commands into `AppIndex` and rechecks the setting on every public invocation. Disabling hides
the panel, removes the status item, cancels search, flushes the draft, stops monitoring, and removes the
commands. A failed flush retains the draft for retry and termination preservation without leaving
monitoring or debounce work running.

## Commands and window

- **Show Notes** selects the last active note and shows or focuses the panel. Calling it while visible
  never hides the panel.
- **Create Note** creates and selects one unique Untitled note, including when it is the first action
  in an empty channel.
- **Search Notes** opens the main palette in its wide Notes search mode.

The optional Notes menu-bar item is a direct entry point, not a second notes surface: clicking its
`text.page` symbol runs **Show Notes** and opens or focuses the same floating editor.

Command-N uses the create path and Command-P opens the compact switcher. Escape closes the switcher
first, then hides the panel; Command-W and the header close control hide it directly. Hiding restores
the prior external application or Tinycast window and flushes without delaying the order-out.

The existing 520-point editor surface remains. Its fixed header contains the note glyph, active-title
switcher button, drag region, save/conflict state, Format, Create, Reveal, and close controls. The
switcher replaces only the editor region, scrolls inside the current frame, and therefore never moves the
panel's top edge or changes its saved size.

During one open-note session the panel grows with content but never shrinks after deletions or
projection changes. Switching to a different note or explicitly hiding and reopening Notes fits the
panel to that document again. Temporarily suspending the editor for Search Notes preserves its current
height.

The compact switcher and palette browser share `NotesSearchSession`. An empty query lists metadata-only
summaries by recency. A nonempty query is split on whitespace, debounced for 120 milliseconds, and
searches titles and literal bodies in a cancellable detached worker. The active note uses its in-memory
draft; other notes come from disk. Fuzzy title hits rank above body-only hits, results are capped at 200,
and a generation check prevents a superseded search from publishing.

Return opens the selected note. Inline rename coordinates the file move. Command-Delete or the row
action confirms through `DialogController`, then moves the file through `FileManager.trashItem` after a
revision check. Deleting the last note creates a fresh Untitled note.

## Search palette

`PaletteMode.notesSearch` maps to `NotesSearchScreen`, following Clipboard History's 290-point list,
vertical hairline, and preview layout. An empty query groups the recency-ordered list by Today,
Yesterday, This Week, This Month, and Earlier. A typed query is flat and relevance-ranked so date groups
cannot bury a stronger match. Rows contain only the `text.page` glyph and title because the right pane
shows the complete content.

Click or arrows only change the highlighted preview; double-click or Return flushes the dirty active
note, selects the result, closes the palette, and opens the existing editor centered around its prior
placement. A non-active preview loads through `NotesRepository` off-main and only one source is
retained. `NotePreviewView` uses the same parser, projection, and `NoteTextStyler` as the editor, but its
TextKit 2 view is selectable and non-editable. Tasks and links are visual only, and images remain
literal Markdown.

Opening Search Notes while the editor is visible temporarily orders the editor out. Escape restores and
focuses it; click-away restores it without stealing focus. Back, bare Backspace, or Tab chooses to stay
in the palette and abandons restoration. `PaletteCoordinator` reports dismissal through its AppCore-
wired hook so Notes, rather than the palette, restores the displaced surface exactly once.

## Markdown editor

`NoteMarkdownParser` recognizes headings, emphasis, strikethrough, inline links, blockquotes, lists,
tasks, horizontal rules, inline code, and fenced code without importing AppKit. `NoteDisplayProjection`
turns inactive constructs into rendered-width text: markers are elided, links show their label, list
markers become bullets, and task markers reserve one checkbox anchor. Moving the caret into a construct
restores its complete literal source. Images remain styled source and never load local or remote data.

Headings retain six distinct levels and block spacing. Quotes use an inset leading rule, wrapped list
content uses a hanging indent, fenced code uses a padded surface, and horizontal rules draw as full-width
decorations rather than repeated text glyphs.

`NoteEditorView` owns canonical source separately from `NSTextView.string`. Every display selection and
edit maps through ordered identity, elision, and replacement segments before one canonical transaction
updates the store. Copy and Cut use source ranges. The editor epoch changes on note switches and clean
external reloads, clearing its custom native undo manager before a new source is installed; ordinary
view updates preserve undo. Marked-text composition freezes projection until commit.

The `textformat` header control opens a Tinycast-owned in-window formatting overlay. It supports Normal,
H1–H3, bold, italic, strikethrough, inline code, links, quotes, bullets, numbering, tasks, fenced code,
and horizontal rules. Command-B, Command-I, Command-K, Shift-Command-X, and Shift-Command-7/8/9 use the
same source-edit planner. Escape closes formatting, then the switcher, then the window.

Return continues bullets, numbered items, and tasks, with new tasks unchecked. Return on an empty item
or Backspace at its content boundary removes the list marker; Tab and Shift-Tab nest and outdent list
lines. Each interaction is one canonical source transaction and one undo step.

Inactive tasks use pooled native checkbox controls positioned from TextKit segments. Each activation
revalidates the current editor epoch and literal marker before toggling. Command-click resolves supported
web, mail, and file destinations in the pure model, then `NoteLinkLauncher` performs the `NSWorkspace`
effect; ordinary clicks only enter source editing.

## Autosave and external changes

Editor changes update the main-actor draft immediately and debounce save for 300 milliseconds. Only
the active source is retained. A successful save refreshes metadata ordering; switching waits for the
same flush before loading another source.

`NoteFileMonitor` watches both the directory and active file because atomic saves replace the file.
Directory events rescan summaries. A clean active-file edit reloads; a dirty revision mismatch pauses
autosave and offers **Save Copy & Reload**. Conflict copies retain the title, for example
`Project (Tinycast Conflict 2026-08-11 143012).md`, and are ordinary notes after reconciliation.

An external rename is intentionally a removal plus an addition because filenames are identity. If the
active clean file disappears, the store selects the most recently modified remaining note or creates
Untitled. A dirty disappearance enters conflict instead. Termination awaits the active save or writes
the same conflict copy before allowing the app to exit.

## Verification

`Tests/notes-test.swift` compiles the shipped Notes model and service sources with the real fuzzy
matcher. It covers channel-separated directories, discovery of `Floating Note.md`, unlimited
enumeration, unique titles, byte revisions, rename and Trash conflicts, search, selection, autosave,
external reconciliation, recovery, parser/projection source preservation, formatting plans, and
top-anchored layout. `Tests/notes-editor-test.swift` uses real AppKit text objects to cover collapsed
layout, one source delivery per transaction, undo/redo, and stale-undo removal across note switches.

The Notes manual sweep in `docs/testing.md` covers the panel, Settings projection, shortcuts, keyboard
navigation, focus restoration, Finder, Trash recovery, large-directory search, and visual states.
