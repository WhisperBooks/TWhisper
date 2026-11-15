# CLAUDE.md - working rules for this repository

Read README.md first, then this file. Keep both up to date with every change.
The rules follow TWhisper's and TFFMpegAPI's CLAUDE.md (same owner, same
conventions); where this file is silent, theirs apply.

## Project
EpubUnum (github.com/WhisperBooks/Epubunum, PRIVATE - WhisperBooks' own,
unlike the public TFFMpegAPI): EPUB reading and, next, writing for Delphi
FMX. Started 2026-11-15 at the owner's request, before the EPUB layer of
TWhisper: "having it's own component makes sense".

Product line (owner, 2026-11-15): the END-USER READER is the main
application most people will get - it shows the EPUB and plays the audio in
sync with the text highlighted. Variants for creators, publishers and
narrators build on it (TWhisper is "the big one"). Make-your-own books
(record stories for your children) is a promising market. So:
- The reader must not need TWhisper, whisper.cpp, models or a GPU: it uses
  EpubUnum (and possibly FFmpegAPI) only.
- Output is standard EPUB 3 media overlays, so books made here also play in
  other readers.
- Copy-protected books are refused with a message, never decrypted.

Rendering (owner, 2026-11-15): NATIVE WITH SKIA - "add Delphi's Skia into
things as it speeds up rendering". TEpubView (fmx/) draws the layout model
(lib/Epub.Layout) with Skia's paragraph engine. A web view is possible
later as a second renderer only; FMX has no web view on Linux and WebView2
under Proton is unproven. The layout model stays renderer-neutral.

DELPHI WITH SKIA, FPC WITHOUT (owner, 2026-11-15: "Epubunum can be Delphi
with Skia and FPC without - best of all worlds that way"; Skia "only matters
when rendering"). lib/ compiles with Delphi AND FPC (FPC is also the test
compiler here). Skia is only in fmx/ (TEpubView, Delphi). An FPC / Lazarus
renderer (LCL canvas or BGRABitmap) would draw the same layout model later.
Keep compiler differences in lib/ to small {$ifdef FPC} branches; names that
exist in only one compiler are bugs (zip 01: DefaultFormatSettings is FPC's
only - use FormatSettings, which both have).

The owner builds in the 32-bit IDE (the 64-bit one has no macOS / Linux
targets): packages build for Win32 too; design packages open on Win32.

## Skia (owner, 2026-11-15)
- EpubUnumFMX requires Skia.Package.RTL and Skia.Package.FMX (Delphi 13's
  names). TEpubView uses System.Skia and FMX.Skia, so the IDE adds both
  packages on the first compile if they are missing ("Skia was actually
  forced on me by the IDE when compiling the package" - push e8c3a23).
  gen_projects.py now writes them, with the SKIA define.
- Programs (EpubReader) still need Project > Enable Skia for sk4d.dll
  deployment; gen_projects.py writes those DeployFile entries.
- The IDE writes "GlobalUseSkia := True;" into a program's .dpr: NEVER
  keep it (TSteamAPI's rule; FmxSkiaCanvas decides under Proton).
- Skia API used by TEpubView was checked against the Skia4Delphi source
  (github.com/skia4delphi/skia4delphi): TSkCustomControl.Draw (strict
  protected virtual), DrawCacheKind, Redraw, ISkParagraphBuilder (PushStyle,
  AddText, Pop, Build), ISkParagraph (Layout, Paint, Height,
  GetRectsForRange -> TArray<TSkTextBox>, GetGlyphPositionAtCoordinate ->
  TSkPositionAffinity), TSkTextStyle, TSkFontStyle.Create(weight, width,
  slant), TSkImage.MakeFromEncoded, ISkCanvas.DrawImageRect / DrawRect /
  DrawLine / ClipRect / Save / Restore.

## Platform notes (from TSteamAPI, owner: "important notes in general")
github.com/G3DGames/TSteamAPI docs/: fmx-steamos-gtk3-bug-fix.md,
fmx-steamos-icu-bug-fix.md, fmx-menu-bug-fix.md, FmxWineCanvas /
FmxSkiaCanvas. EpubReader carries UNCHANGED copies of FmxLinuxGtkGlobal,
FmxWineCanvas, FmxSkiaCanvas and the ICU launcher (as EpubReader.sh; LF -
.gitattributes). Their headers still name TSteamAPI's copies and the
environment variable TSAPI_FMX_CANVAS: kept identical on purpose. No
TMainMenu in the reader (Linux GTK menu bar bug; SteamOS full screen); if a
menu is added, add FmxLinuxMenu. Start-up markers on stderr under POSIX and
the canvas in use logged, as SteamDemoPad. Gorilla3D / CGE notes in
TSteamAPI do not apply (no 3D).

## Reader sound and tool bar (zip 03, owner 2026-11-15)
- No TMediaPlayer: "(b) That's how MoviePlayerFMX does it" (SRDelphiFMX).
  The reader plays with TFFMpegAPI's TFFmpegAudioPlayer (FFmpegAPI-04:
  FFmpeg.AudioOut + FFmpeg.Player - streamed, WASAPI / PulseAudio / silent,
  Position = the sound being heard). EpubUnum's packages do NOT use FFmpeg;
  only the EpubReader demo does (TFFMpegAPI installed, like TWhisper).
  FFmpeg may be GPL or LGPL (owner): no policy forced; the licence is logged.
- Tool bar: no designed buttons; made in FormCreate the way Sprite3D's
  results view does it (github.com/peardox/Sprite3D, Sprite3DResultsView /
  Sprite3DHelpers: a TButton with a centred FMX TPath icon, SVG path data in
  a 24x24 box, Fill coloured from ResultingTextSettings.FontColor in
  OnApplyStyleLookup). Icons: open (folder), previous / next chapter
  (Sprite3D's FIRST / LAST), previous / next sentence (PREVIOUS / NEXT),
  play / pause.

## Layout rules
- `lib/` - framework-free units only. No FMX, VCL or LCL here, ever.
- `fmx/` - Epub.FMX (TEpubUnum), Epub.FMX.View (TEpubView), Epub.FMX.Reg.
  They include `..\lib\Epub.inc` by relative path.
- ONE WALKER: Epub.Layout's TEpubDocLayout produces the words AND the
  blocks; TEpubBook.Words comes from it (blocks off). Never split words
  anywhere else - word indexes from overlays, alignments and the view
  must agree.
- `demos/<Name>/` - `<Name>.dpr` + `<Name>.dproj` + `README.md`, other
  sources in `src/`. Demos list and search ONLY their own sources.
- GROUP ORDER (gen_projects.py GROUP_ORDER): EpubUnum, EpubUnumFMX,
  dclEpubUnumFMX, EpubConsole, EpubReader - plain runtime, FMX runtime,
  design, applications.

## Code rules
- ASCII-only sources; PasDoc on every declaration.
- Never `Low`, `High`, `TypeOf`, `AS` ... as identifiers (AS is reserved).
- No absolute paths, user names or machine names in tracked files.

## Deliveries
- Zips hold only the files changed since the previous zip, paths from the
  repo root, named EpubUnum-NN-topic.zip; the number is never reused; every
  delivery says what it goes on top of. Zip 01 is the whole repository.
- PACKAGE REBUILDS (owner, 2026-11-15: "Add rule"). Every delivery says
  one or the other. When a package must be rebuilt, the message carries,
  exactly, a blank line, the banner, a blank line, then the details:

      =====> PACKAGE REBUILD NEEDED <=====

  Details of the package rebuilds: which packages, in build order, why
  (which unit changed), and what to rebuild after them (programs, other
  repos' packages). Otherwise say "NO PACKAGE REBUILD", in capitals.
- Never commit or push, and don't offer to.
- Sync + check needs access: the repo is private (give this session access
  to WhisperBooks/Epubunum, or send a zip of the checkout).
- Before delivery: `python3 tools/pasdoc_check.py`,
  `python3 tools/project_check.py`, an FPC build of lib/ and EpubConsole
  run on the test books.

Last number used: 34.

## Review fixes (zip 08, on top of 68162a4 "A Claude push")
From a code review by reading (owner, 2026-11-15: "code review", then "y" to
a zip with the five fixes). NOT COMPILED OR RUN in that session (no FPC, no
Delphi, no Skia there; pasdoc_check and project_check: 0 problems): the
owner's Delphi build and an FPC build of lib/ with EpubConsole on the test
books are their test.
1. EpubReader, StartClip: the name of the extracted audio file was the
   overlay's audio path with '/' turned into '_'. A book chooses that path:
   backslashes with '..', or an absolute path (TPath.Combine returns an
   absolute second part as it is), wrote the book's bytes anywhere. Now the
   name is <BookSerial>-<first clip of that audio><extension>, the
   extension only a dot and ASCII letters / digits (SafeAudioExtension), so
   a second book with the same inner path no longer plays the first book's
   file either. The temp folder's name is a GUID (Random without Randomize
   gave the same folder every run; two readers shared and deleted it).
   Never build a file name on disk from a path inside a book.
2. TCustomEpub.BookSerial (Epub.Components): changes with every open and
   close. TEpubView keeps the serial its layout was made at
   (LayoutCurrent): ShowDocument makes the layout again when the book is
   another one even if the document number is the same - it showed the
   FIRST book's text for a second book starting at the same document - and
   Draw / WordAt / ScrollToWord / ShowFragment do nothing with a layout of
   the book before. TO TEST: open a book, then another, without leaving the
   first document.
3. Epub.Css, Parse: a statement without a block ('@charset "UTF-8";',
   '@namespace ...;', '@import ...;') ends at its ';'. It was scanned on to
   the next '{', became that rule's selector, started with '@' and the rule
   was skipped: the first rule of every style sheet starting that way. TO
   TEST: EpubConsole's rule counts / a book whose CSS starts with @charset.
4. TEpubView.LayoutItems: reading a picture is in try / except - a damaged
   entry (CRC, ZIP method, too large) gives no picture. The exception left
   Draw with FItems half made and the width marked as laid out, so the
   chapter stayed cut off.
5. Epub.Xml: Children no longer copies the array on every read (the node's
   own array, trimmed once). Children[I] in a loop over ChildCount
   (Epub.Layout's walk, the NCX reader) was quadratic. Callers must not
   change the array.
Found in the same review and NOT fixed: Epub.Zip trusts the sizes of the
directory (a small file can ask for 2 GB) [zip 11: data ranges checked,
Extract streams]; a descendant selector
('.poem p') is applied to every element matching its last part; style
sheets are parsed once per DOCUMENT, not per CSS file, and StyleOf scans
every rule and parses the declarations again for each element; ClipAt
returns a clip without clipEnd for every later time; the XML tree and the
layout walk recurse without a depth limit; ExtractAll skips every name with
'..' in it ('Wait....xhtml'); [fixed in zip 09: with FPC, UTF-16 text
is converted with string(W), not UTF8Encode]; Active := True fails silently without
OnOpenFailed; no LICENSE file.

## EPUB writing (zip 09, on top of ef2daff "Claude review push")
Owner, 2026-11-15: next work item 1, "EPUB writing: media overlays (SMIL),
word spans, package update - so TWhisper can write synced books".
Decisions (owner): "Matching is a TWhisper job. User can decide but default
to word level". So:
- lib/Epub.Writer, TEpubWriter: takes TIMED WORDS ONLY - (index into
  TEpubBook.Words, audio file, clipBegin, clipEnd). No text matching here.
  Level: eolWord (default; a span per timed word) or eolBlock (the
  paragraph / heading / list item gets an id, one clip per block run).
- Spans are INSERTED into the source text (never re-serialised): the
  parser now records source positions (TEpubXmlNode.SrcPos / SrcLen /
  SrcEnd / CData, TEpubXmlDoc.Source; EpubXmlRawIndex maps a decoded index
  back), and the ONE walker records where each word is
  (TEpubDocLayout.Create(..., AWithSources), Sources; TEpubBook.
  DocumentSources). A word split by markup ('<i>Moby</i>-Dick') gets its
  span on the first piece - the walker counts every word touching an
  element, so the id still holds exactly that word.
- Every tagged document is CHECKED before writing: laid out again it must
  give the same words, and each new id must hold exactly its word.
- A word alone in an element with an id keeps that id (Moby-Dick's
  c01w00001; writing a written book again adds 0 spans).
- Package: SMIL / audio / css / nav items, media-overlay, media:duration per
  overlay + total (kept overlays' values counted), media:active-class (when
  the book has none, plus epubunum-overlay.css linked from the tagged
  documents so other readers highlight), media:narrator, dcterms:modified.
  Edits are insertions / tag rewrites on the source, indented like the
  file. A manifest href with a space is written with %20.
- EPUB 2 -> EPUB 3 (overlays need it): version, nav from the NCX,
  opf:role / opf:file-as -> refines metas, other opf: attributes and
  extra dc:date dropped, HTML5 doctype + named entities as &#N; (the HTML5
  doctype declares none: &nbsp; was FATAL in epubcheck).
- Other files are copied RAW (TEpubZipWriter.AddRaw / TEpubZipReader.
  ReadRaw, size checked against the file); audio from disk is stored in
  pieces (AddFileStored), never loaded whole.
- EpubConsole: --words, --overlay TIMINGS OUT [--audio F | --book-audio P]
  [--block] [--narrator N], --clip-timings (test aid).
Also in zip 09 (found while testing):
- FPC UTF-8: EpubBytesText / EpubUtf8Bytes / CodeText converted through
  the system code page (UTF8Decode -> string): with no UTF-8 locale every
  non-ASCII character became '?' - in the words, and in written files.
  Now byte copies under FPC (strings are UTF-8 by design). The old build
  gave '?' for "Transcriber's" (curly quote) on Moby-Dick even with
  LANG=C.UTF-8. Delphi unchanged.
- Speed for word-level books (Moby-Dick with 212,881 clips): ReadOverlays
  grew FClips by one per clip and resolved two paths per par (now doubled
  capacity, paths cached per file); the walker grew FIds by one (now
  doubled); ClipWords scanned the ids (now a sorted index per document,
  first of a repeated id wins); ClipAt starts at the last clip found when
  the clips are ordered (FClipsOrdered); EpubClockValue used a TStringList
  and copied FormatSettings (~50 strings) per value (now split by hand,
  DotSettings set once - also in Epub.Css); StyleOf caches its answers
  (key: element, class, style, and the id only when a rule names it);
  TEpubXmlNode.LocalName is cached. Open + LoadText of that book: 3.1 s ->
  2.2 s (FPC -O2, Linux; most of it is parsing 46 MB of SMIL). The
  original Moby-Dick: 0.24 s -> 0.18 s.
TESTED here (FPC 3.0 from fpc-lambda, Linux x64, static link - no -k-ldl;
epubcheck 5.2.1 from its GitHub release; Moby-Dick from IDPF epub3-samples
20230704): word level for Moby-Dick's own two chapters (timings from its
clips), + chapter 3 new with a second audio file, block level, every word
of the book, a written book written again, a synthetic EPUB 2 (NCX,
opf:role, two dc:date, XHTML 1.1 doctype, &nbsp; / &mdash;, a word split
by <i>, a word across <a><sup>, ruby, pre, display:none, aside footnote,
a file name with a space). epubcheck: 0 errors / 0 warnings (the EPUB 2
sample only keeps its own fake cover PNG error). A test reader re-opened
every result: same words (text, role, document), each clip's words =
exactly its timed word, timings to the ms, ClipAt forwards and backwards.
Every tagged document = the original with only our markup inserted
(byte check). Old vs new library on Moby-Dick and the sample: same text,
layout and info apart from the '?' fix.
NOT RUN: Delphi build (owner), EpubReader on a written book. TO TEST:
build the packages (EpubUnum has a new unit), EpubConsole --overlay as in
its README on Moby-Dick, then open moby-words.epub in EpubReader: the
highlight must move word by word; the prev / next clip buttons now step
one WORD (a reader feature to decide: sentence stepping).
Known, not done: sentence level (a sentence can cross inline markup);
block level picks the innermost block, so a div's loose text after a p
gets a clip on the div (its highlight covers the p too); a word-level
book's SMIL parse dominates opening (a dedicated SMIL scanner would cut
it); non-core audio (wav, ogg, flac) is written with a warning only.

## Reader navigation and dark mode (zip 10, on top of zip 09)
Owner, 2026-11-15, after zip 09: "Chapter forwards / backwards that syncs
to the start of a chapter"; "next/prev ... non-sensical at word level.
This should be sentence / paragraph (selectable - a drop-down for now is
fine)"; "Dark mode would be good as well".
- Chapters = Toc entries in reading order (an entry at the place of the
  one before - a part and its first chapter - is merged; no Toc: the linear
  documents). Previous / next chapter and a contents click show the
  chapter AND move the audio to its first clip inside the chapter (a
  chapter without audio stops playing, nothing jumps to a later
  chapter's). Paused: FSeekClip - Play starts there instead of resuming.
  lbToc follows the clip being read (FSyncingToc: no jump).
- Steps by sentence / paragraph (cbStep, a TComboBox in the tool bar), on
  WORDS, not clips: a paragraph = a block of the walker's layout; a
  sentence ends at a block end or a word for which EpubEndsSentence
  (Epub.Layout, new; closing quotes stripped; Mr. / Dr. / St. ... and
  initials are not ends) is True. Then the first clip at or after that
  word. Checked with FPC on Moby-Dick: every one of its own sentence clips
  starts at a sentence start (its three word clips are the only others).
  Previous: start of the sentence being read; within BACK_GRACE (1.5 s of
  audio) of it - or paused at it - the one before.
- Dark mode (moon button, D): TEpubView's four colours, the form's Fill,
  lblStatus, the contents' item text and its style's 'background' shape
  (TocApplyStyle on OnApplyStyleLookup; light = the style re-applied).
  Zip 12 (owner: "Dark mode makes the sidebar unreadable" - light text on
  the style's white): dark sets lbToc.StyleLookup :=
  'transparentlistboxstyle' (FMX's own), so the form's dark Fill shows
  through; TocApplyStyle stays as a fallback (a 'background' shape made
  dark, another kind hidden). Light: StyleLookup ''.
  The tool bar's buttons and the combo box keep the platform style. Not
  remembered between runs (the reader keeps no settings yet).
NOT COMPILED (no Delphi here): uMain.pas changes are the owner's build.
TO TEST: chapter buttons while playing and paused; a contents click while
playing; sentence / paragraph steps on moby-dick-word-level.epub and the
original Moby-Dick; D on and off (the contents panel's background - if
the style names its background differently, it stays light).

## Streamed extraction (zip 11, on top of zip 10)
Owner, 2026-11-15: "Yes fix streaming" - the LibriVox Moby Dick m4b files
(Stuart Wills: 5 x 140 MB; Peter Dann: 3 x 225 MB) are copied out by
EpubReader before playing, and Extract read the whole entry into memory.
- TEpubZipReader.ReadTo(AIndex, AOut): stored or deflated, 1 MB pieces,
  CRC over the pieces, short data and the data range checked against the
  file. Extract uses it and deletes the file on any error. Tested (FPC): a
  300 MB entry, stored and deflated, byte-identical, peak 13 MB; the 9 MB
  deflated Moby-Dick mp4 = unzip's; a flipped byte -> "damaged (CRC)",
  no file left; ExtractAll of a written book = unzip's.
- ReadBytes checks the data range against the file too.
Still so: ReadBytes allocates the size the directory declares (a small
file can still ask for up to 2 GB when read whole; Extract does not).
NOTE: the IDPF Moby-Dick sample's audio is LibriVox's Stuart Wills
recording (chapters 1-2, the LibriVox intro before 24.5 s): TWhisper on
the Wills m4b files can be compared with that human-made sync (sentence
clips; offsets differ - find the median first).

## Shall we do this - and if so, how to do the UI
Ideas kept for later (owner, 2026-11-15): "keep them in a 'Shall we do
this and if so how to do UI' section". ORDER (owner): "once we've got the
reader at a satisfactory pausing point we can improve the other
contributing components / systems" - reader first, then TFFMpegAPI etc.
- LEARN TO READ: BUILT in zip 18 (see "Learn to read (zip 18)" below).
  Original notes kept:
- LEARN TO READ mode (owner's idea: "if the playing was paused and the
  user pressed fwd it could say the word ... people learning to read or
  learning to read a new language"; "a 'Learn To Read' switch ... owing to
  the differing use of the control(s)"). Proposal, not agreed in detail:
  a toolbar toggle (+ a key, e.g. L). In the mode: the step drop-down gets
  Word / Sentence / Paragraph (Word default); paused Next / Previous MOVE,
  THEN SAY the unit and stop (what is seen is what is heard); a "say
  again" key (Space or R) repeats the highlighted unit; a click on a word
  says just that word; Play still reads on. Next with nothing highlighted
  says the page's first word. Owner said "probably you want to read the
  currently highlighted word then move" - the say-again key covers that;
  confirm the order when it is built.
- NEEDS (other components, after the reader): TFFMpegAPI play range -
  TFFmpegAudioPlayer.PlayRange(Begin, End), the output stops feeding
  samples at End (the reader's 100 ms timer would let a ~300 ms word run
  into the next). Pad words 30-50 ms each side (consonants). Good word
  timings: TWhisper's DTW words, not clips shared out by length (the
  zip 09 test book's words are approximate - owner: "completely
  understandable").
- Speed change: DONE in zip 15 (slider 0.5x - 2x). 0.25x (owner: "down to
  0.25 or 0.5") needs TFFMpegAPI to chain two atempo filters (one goes
  down to 0.5): its MIN_SPEED, then SPEED_MIN here.
- AUDIO OUTSIDE THE BOOK (owner, 2026-11-15: "a strong case for (1+3)").
  (1) Timings file beside the ORIGINAL, untouched EPUB (small download,
  reads without audio); the reader finds the timings + audio and builds
  the overlays in memory. Only our reader plays it. (3) The complete
  EPUB with the audio inside (what --overlay makes now; works in every
  reader). (2) Remote audio URLs in the overlays - EPUB 3 allows it, few
  readers do. To decide: how the reader finds timings / audio (same
  folder + name, or picked), and an EDITION CHECK (word count / hash of
  the text) so timings made from another edition are refused.
  LIBRIVOX: their recordings and the Gutenberg texts are public domain;
  a timings file can name LibriVox's own download (archive.org URL +
  size / checksum) instead of a local path, so only book + timings are
  published and the reader fetches the audio. LibriVox readers mostly read
  a known Gutenberg edition: one timings file per recording + edition.
  Owner: "an interesting option to talk to them about". Volunteer GPU
  transcribers for this: TWhisper CLAUDE.md, plans.
- DROP UNUSED AUDIO: --overlay keeps the source book's audio even when no
  overlay plays it any more (moby-dick-mo.epub's
  mobydick_001_002_melville.mp4, 9 MB). Owner: "no big loss" for now.
- STEAM DECK (owner, 2026-11-15): the reader has TSteamAPI's platform fixes
  already (native Linux64 + EpubReader.sh, or Windows under Proton).
  Needs: Steam Input via TSteamAPI - proposed A play / pause, d-pad
  sentence, bumpers chapter, triggers speed, Y dark, B contents, stick /
  trackpad scroll, touch = click a word; a 1280x800 layout (bigger
  buttons, contents hidden); remembered settings; a test in Game mode.
  Needs TSteamAPI's current source in the session.
- TESTED (owner, 2026-11-15): the reader on a Lenovo Miix 520 tablet
  ("a hugely underpowered pile of junk") - "Worked perfectly and very low
  system usage". Deploy: EpubReader.exe, sk4d.dll, FFmpeg's avutil-60,
  swresample-6, avcodec-62, avformat-62 (+ swscale-9, avfilter-11 for
  the speed slider), the .epub (audio inside).
- Say a sentence, then step through its words.
- The current word shown large in a strip under the page.
- Remember reader settings between runs (dark mode, step unit, text
  size): the reader keeps none yet.

## Timings with their audio (zip 14, on top of 6ab27c4)
EpubConsole --overlay without --audio / --book-audio takes the files from
the timings' own "# audio N: path" lines (WhisperConsole --timings, TWhisper
zip 21, writes them; a relative path is relative to the timings file; a
missing file is an error). The sync pipeline (TWhisper and Epubunum stay
separate): EpubConsole --words -> WhisperConsole --align-words --timings ->
EpubConsole --overlay. Tested here: a synthetic transcript of Moby-Dick
ch 1-2 over two m4b files (the IDPF mp4 cut at 860 s) -> 3672 clips,
epubcheck 0 / 0, every clip = its timing.

## Words split at dashes (zip 15, on top of 26118e5 = zip 14 pushed)
Owner, Moby-Dick ch 135 in the reader: "calm-frozen" and "it!-it's" (em
dashes) lit as one word. The walker (TWalker.AppendText, DashAt) now ends
a word after a dash U+2012 - U+2015 that follows text: 'calm' + dash,
then 'frozen'. A dash starting a word stays on it (dash + 'GENESIS.');
a dash right after one that ended a word is a word of its own (doubled
dashes). The same dashes as TWhisper's WhisperSplitText, so the aligner's
split and EpubUnum's words now agree. WORD NUMBERS CHANGE: Moby-Dick
212881 -> 214492 words (1611 more); old timings files must be made again
(--words, then WhisperConsole --from-json --align-words --timings).
Tested here: the owner's moby.json realigned against the new list - same
aligner figures (TWhisper zip 23), 213544 timed words; --overlay (stand-in
audio) 213544 clips, 0 left out; epubcheck 5.2.1 0 / 0; checkover (every
word's clip = its timing) and onlyinserts (only markup inserted) clean.
Sentence steps in the reader: 'it!' + dash no longer ends a sentence
(EpubEndsSentence sees the dash) - right, it is mid-sentence.

Also in zip 15:
- PUNCTUATION NOT LIT (owner: "If a word has some punctuation after it
  the punctuation is highlighted as well"). EpubWordCore (Epub.Layout)
  narrows a word to its letters and digits (ASCII punctuation, U+2010 -
  U+205E, guillemets, inverted marks trimmed at both ends; inner ones
  kept: it's, sperm-whale). Used by TEpubView's highlight (first word's
  start, last word's end) and by TEpubWriter's spans: '<span>whales</span>,'
  and opening quotes outside the span. Reading the book back still ties
  every clip to its word (the walker's word ids are unchanged: checkover
  0 word differences, every clip = its timing), onlyinserts clean,
  epubcheck 0 / 0. The FMX view is NOT compiled here (no Delphi / Skia).
- SPEED SLIDER in the reader (owner: "slider will do ... Default 1"):
  TTrackBar 0.5 - 1.5 step 0.1 (zip 16: owner "0.5 to 1.5 (2.0 sounds
  silly)"; was 0.5 - 2). Zip 17: dragging made the window stop responding
  (owner) - every step set Speed, and each set restarts the player's feed
  (seek + new filter graph). Now the label follows at once and the player
  gets the speed when the slider has rested SPEED_SETTLE_MS (300 ms,
  tmSpeed): once per drag, once per run of [ / ] presses. + a '1.0x' label (click = 1x), keys [ and ];
  sets TFFmpegAudioPlayer.Speed (the feed restarts at the same place).
  Without avfilter / swscale the error goes to the status line and the
  slider returns to 1. NOT COMPILED here.
- ICON: demos/EpubReader/EpubReader_Icon.ico (16 - 256 px: an open book
  with an amber highlighted word and a play badge, drawn here with PIL).
  EpubReader.dproj: ONE line added, Icon_MainIcon in the Base_Win64
  group; nothing else in the .dproj touched. gen_projects.py does not
  write icons (it is never run on the existing .dproj). macOS (.icns) and
  Linux icons: not yet.
- FOUND, for TWhisper (not fixed): 375 words in the Moby timings have a
  10 ms time starting where the next word starts (DTW gave Whisper's
  'the' no length) - in 18 places the reader's ClipAt in the middle of
  such a clip finds the word before. Harmless to hear; TWhisper should
  give such a word part of the gap before it.

## Learn to read (zip 18, on top of 17)
Owner, 2026-11-15: "Learn To Read is also a good thing to have - may also
be useful for proof-reading books (re-labelled but same functionality)".
EpubReader (uMain only): btnLearn ('Abc', StaysPressed) + key L; cbStep
holds Word / Sentence / Paragraph in the mode (Word chosen on entry),
Sentence / Paragraph outside it (StepUnit maps the index: UNIT_WORD /
UNIT_SENTENCE / UNIT_PARAGRAPH; FillSteps refills keeping the unit).
In the mode Next / Previous (LearnStep): StopPlaying, the next / previous
unit (UnitStart / new UnitEnd; IsUnitStart is True for every word in
Word steps), SayWords: highlight + scroll + SyncToc, then
FPlayer.PlayRange(first clip's begin - 40 ms, last clip's end + 60 ms)
(SAY_PAD_BEFORE / AFTER) and stop. No clip (not read): lit, silent, the
previous sound cut. A unit across two audio files is said to the end of
the first file's part. Word steps pass over words with no clip and no
letter or digit. R: say again. Click a word: that word. Play reads on
from the unit (FSeekClip); with nothing said yet after a pause, Next
goes on from the paused sentence, Previous says it. Book open / chapter
jump reset the unit. OpenClipAudio split out of StartClip (the audio
extraction, unchanged). NOT COMPILED here (no Delphi / FMX / Skia).
Proof-reading: same mode, a second label later (owner).
Zip 19 (owner, first test): "The word level accuracy is noticeably bad
here. A single word frequently includes the end of previous word and the
start of the next - possibly reduce the padding to near zero. Sentence on
the other hand is frequently too much prose ... sections of the sentence
between punctuation". SAY_PAD_BEFORE / AFTER 40 / 60 ms -> 0. New unit
PHRASE (UNIT_WORD 0, UNIT_PHRASE 1, UNIT_SENTENCE 2, UNIT_PARAGRAPH 3;
outside the mode the list is Sentence / Paragraph = index + 2): a phrase
ends after a word whose last character (closing quotes stripped) is
, ; : . ! ? or a dash U+2012 - U+2015, or that closes a bracket
(EndsPhrase). Phrase is the mode's default. WORD TIMING: with no padding
any bleed left is the timings' own - DTW word boundaries; on the human
sync, sentence starts were within 0.21 s on average. If single words
still bleed, the fix is in TWhisper (word edges), not here.
Zip 20: owner "phrase works well, drop word as an option" (single words
still bled with no padding, on TWhisper-26 timings). Word steps removed
(UNIT_PHRASE 0, UNIT_SENTENCE 1, UNIT_PARAGRAPH 2; outside the mode the
list is Sentence / Paragraph = index + 1); a click still says one word.
Zip 21 (owner): "In Learn Mode the Play button should play the
highlighted text rather than the next text ... useful if someone had
problems with a specific word. Also Learn Mode should be much more
distinctive". btnPlayClick in the mode: SayWords(FLearnFirst, FLearnLast)
again (nothing said yet: the unit of CurrentWord) - never reads on; its
hint changes. Distinctive: recLearn (TRectangle, Align Contents, behind
layTop's buttons) green band LEARN_BAR / LEARN_BAR_DARK; highlight
LEARN_HIGHLIGHT / _DARK instead of amber (ApplyTheme); LEARN_TITLE
appended to the window title (kept across book opens); status line
prefixed "LEARN TO READ - ".
Zip 22 (owner: "Chapter 1 - clicked Call - that was it": the click said
one word and Play then repeated only that word). A click in the mode now
picks the unit the word is in (UnitStart .. UnitEnd, by cbStep) and says
it; single words are no longer said anywhere in the mode.
TWhisper idea for the bleed: move each word boundary to the quietest
point within ~80 ms of DTW's (loudness per frame, as the benchmark
stretch), at --from-json time - offered, not agreed.

## GUI book builder (zip 23: BUILT, NOT COMPILED - see "EpubBuilder (zip 23)")
"Epub on one side, Audio list on the other and a Create button to take
the parts, run the make steps and build the final ePub you can then open
with reader. Probably integrate Reader at some stage later but for now a
simple GUI." The steps it runs are today's files: EpubConsole --words ->
WhisperConsole (transcribe, --json) + --align-words --timings ->
EpubConsole --overlay. Linking both libraries in one app was always the
plan ("A GUI app linking both can come later", TWhisper zip 21 notes).
To decide: which repo it lives in (it needs TWhisper + EpubUnum +
TFFMpegAPI), progress / cancel for a 20 min transcription, keeping the
transcript JSON so a re-align needs no new transcription, the device /
model choice (TWhisperBenchmark).

## EpubBuilder (zip 23, on top of 22; needs TWhisper zip 27)
Owner: builder in EpubUnum's demos (chosen over TWhisper's demos / a new
repo), linking the libraries in-process (chosen over running the console
exes). demos/EpubBuilder: EpubBuilder.dpr, src/uBuilder.pas + .fmx (form
only; controls built in code), README.md, EpubBuilder.dproj made by
tools/gen_projects.py (new file only - no existing .dproj touched; the
generator gained the project and GROUP_ORDER the name). EpubUnum.groupproj
edited BY HAND: EpubBuilder after EpubReader in Projects, its three
targets, and in Build / Clean / Make (project_check: 0 problems).
Window: book (left: Choose..., title / words / existing overlays; a
protected book refused with the library's message), audio (right: Add
files... / Add folder... sorted by WhisperNaturalCompare, Remove, Up,
Down), below: model, device (TWhisperLib.SelectableDevices; Default),
output (default <book>-synced.epub; never the book itself), "Chapters of
a file are parts" (on), "Use a saved transcript" (on), Create / Cancel,
progress, log. TBuildThread: TEpubBook words without role nav ->
FFmpeg (PATH, else whisper.cpp's folder) -> TWhisperAudioSet -> the
transcript: <output>.transcript.json when its parts are the same files
and starts, else TWhisperRun part by part as WhisperConsole (DTW words,
WhisperCleanTranscription, FillGaps, WhisperAppendTranscription, the
first part's language kept) and saved -> WhisperSplitBookWords /
WhisperAlignText / WhisperJoinAligned -> WhisperWordFileTimes (TWhisper
zip 27) -> TEpubWriter.AddAudioFile + AddWord -> SaveToFile. Progress:
5 % book + audio, 85 % transcription by whisper.cpp's progress per part
weighted by length, then align / write. Cancel: Terminate + Run.Cancel.
NOT COMPILED here (no Delphi / FMX): the owner's build is its first.
Zip 24 (owner's first compile, dcc64): EEpubError is in Epub.Zip (added
to uses); WhisperTimeToStr(Round(SecondsBetween(..) * 100)) "incompatible
types" -> MilliSecondsBetween(..) div 10; TThread.ForceQueue(nil, anon)
"no overloaded version" -> the thread is FreeOnTerminate, BuildDone only
clears FBuild; FormClose of a running build sets FreeOnTerminate False,
cancels, WaitFor (OnTerminate has not run: it runs on the main thread),
frees.
Zip 25 (owner, first run on Aladdin: "More user feedback would be nice -
not sure if it's got stuck"; it was at 60 % in one 34 min part with no
log line since the model loaded): a "Now" status line - the step
(reading, opening audio, loading model, decoding part N, transcribing,
second pass, aligning, writing), during transcription each segment's
text and its time on the joined line (TWhisperRun.OnSegment), plus time
taken and time left (from the progress, once >= 7 %), refreshed every
second by tmStatus so the clock moves during a long part.
Zip 26. FIRST REAL BUILD (owner, Aladdin, 34:32 m4a, Gutenberg EPUB 2):
5212 exact, 29 similar, 15 interpolated, 3056 not spoken (Gutenberg
header + licence: the story from "There once lived" to "kings." is all
timed), 5256 clips, 0 left out; second Create from the saved transcript
in 0.4 s. OPEN: (1) 357.6 s to transcribe (5.8x) where WhisperConsole
did Aladdin at 116x - device "Default"? to test with Vulkan0 and the
saved transcript UNticked; (2) the builder's transcript is ALL lower case
with NO punctuation (150 segments) and starts at 0.00 with "there once
lived" - WhisperConsole's text has both; same params on paper. Both may
be one cause (a slow fallback path / another device). Fixed here:
- epubcheck on the result: 3 errors from the EPUB 2 -> 3 upgrade.
  dc:language xsi:type="dcterms:RFC4646" (xsi: attributes now dropped
  with opf: ones) and meta http-equiv="Content-Style-Type" in the
  documents (WithoutOldHttpEquiv in Html5Text: http-equiv values HTML5
  does not allow are removed). Tested: Aladdin's EPUB set back to 2.0 +
  --overlay -> epubcheck 0 / 0.
- RESULTS in the log after a build (owner: "Stats after completion would
  be nice with explanation"): each figure with what it means, a verdict
  (matched / timed: >= 98 very good, >= 93 good, >= 80 usable, else
  poor - wrong recording or file order?), front / back matter told apart
  from not-spoken text inside the book (a warning past 10 %), and the
  10 longest stretches of 3+ words with time and quote.
Zip 27 - CAUSE of the slow, lower-case transcripts (owner's Vulkan0 run:
still 16x and the same text): the builder used whisper.cpp's defaults -
previous text as context, no prompt. With DTW, flash attention is off,
and TWhisper's own notes (its CLAUDE.md, session 5) say turbo with flash
attention off and the previous text as context falls into loops and
lower-case run-on text; RECOMMENDED for books: --no-context
--carry-prompt + a punctuated prompt - what the owner's Moby-Dick run
used ("previous text as context False, initial prompt in every window",
81x). The builder now sets NoContext, MaxTextContext 0, InitialPrompt
BOOK_PROMPT ("Once upon a time, there was a story. It was read
aloud.") carried into every window, and cleans prompt echoes with it.
A saved transcript made before zip 27 should be made again (untick
"Use a saved transcript" once).
Zip 28 (owner: "persist model and device at least ... somewhere
OS-friendly"): EpubBuilder.ini (TMemIniFile, UTF-8) in %APPDATA%\EpubBuilder
(TPath.GetHomePath), ~/Library/Application Support/EpubBuilder (macOS),
$XDG_CONFIG_HOME or ~/.config /EpubBuilder (Linux): [Build] Model (dropped
when the file is gone), Device BY NAME (the list order can change),
Chapters, UseSavedTranscript; [Folders] Book, Audio (the dialogs open
there). Saved on choosing a model, on Create and on close.
Zip 29 (owner): choosing another book empties the audio list ("started
new book, still had old audio") and sets the output name afresh.
FOREIGN LANGUAGES (owner has Night Watch in German too; "I only want
transcribe, not translate"): Params.Translate := False explicitly;
Params.Language := the book's dc:language primary subtag when whisper.cpp
knows it (else auto); the carried prompt in that language (BOOK_PROMPTS:
en, de, fr, es, it, nl; accented letters as #$xx codes - ASCII source);
other languages: no prompt (NoContext + MaxTextContext 0 still - no
loops; maybe no capitals / punctuation, which the aligner ignores).
KNOWN LIMITS for other languages, in TWhisper's aligner: number words are
English (WhisperNumberWords: "4" -> "four", Roman "IV" -> "four"), so a
German "Kapitel IV" heard as "Kapitel vier" does not match (it is then
interpolated - a few words per chapter heading); letters / similarity
work on UTF-8 bytes (umlauts count as two). Worth a German number-word
table in TWhisper if the German run shows many heading misses.
Zip 30. NIGHT WATCH (owner, English, professional reader, 1 m4b, 75
chapter parts, 14:41:28; copyrighted - local only): 19:32 in all;
108371 exact (95.2 %), 1899 similar, 441 MOVED (the footnotes, read
where called - working: 101, 70, 56, 51 ... word stretches at their
call points), 2029 interpolated, 812 not spoken (mostly back matter:
about the author, copyright - not at the very end, so not counted as
edges), verdict 97.8 % good. Slow parts: opening credits 114 s audio in
85 s, chapters 10, 53, 73 (63-89 s) - music / credits or fallbacks.
- Word edges: TWhisper zip 28 WhisperTrimWordSilence called after
  FillGaps; a saved transcript without TRIMMED_MARK ("word_edges":
  "trimmed", written after the JSON's opening brace by SaveTranscript)
  is trimmed once from the audio (TrimSaved, part by part) and saved
  again - so Aladdin / Night Watch need no new transcription.
EpubReader: RegisterOpenWith at start-up (owner: "add Reader to Open
With association. Maybe later Always open with"): Windows HKCU\Software\
Classes - ProgID EpubUnum.EpubReader (open command, icon), .epub\
OpenWithProgids, Applications\EpubReader.exe\SupportedTypes, then
SHChangeNotify; Linux ~/.local/share/applications/epubreader.desktop
(MimeType application/epub+zip, Exec through EpubReader.sh when it is
there). Only written when missing or pointing elsewhere; the status line
says so until a book opens. "Always": Windows 10/11 let only the user
choose the default (the UserChoice key is hash-protected) - Open with >
Choose another app > EpubReader > Always. macOS: CFBundleDocumentTypes
in the Info.plist - later.
NOT COMPILED here (no Delphi). Open question to the owner: ask before
Create replaces an existing EPUB the last build of this book did not make?
IDEA, PARKED (owner: "didn't think it was practical anyway"): an English
sentence -> its German sentence and audio, from two synced EPUBs by
sentence alignment (lengths, names, numbers; Whisper's X -> English
translation as a bridge); phrase level needs a translation model.
Zip 31 - READER (owner, 2026-11-15 21:02): menu bar (TMainMenu, made in
code: File > Open... / Recently Opened / Exit; View > Dark mode / Learn
to read (checked) / Larger / Smaller text); the toolbar's Open button
gone. Settings in JSON (owner: "they will get more complex"):
EpubReader.json in %APPDATA%\EpubReader / ~/Library/Application
Support/EpubReader / $XDG_CONFIG_HOME or ~/.config/EpubReader -
"dark", "textSize", "speed", "recent": [{file, title, word}] (RECENT_MAX
10, latest first). Position = ReadingWord (Learn unit, else the clip
highlighted, else the document's first word), kept on close and when
another book is opened (RememberBook), restored in EpubUnum1Open
(RestoreWord: GoClip - lit, Play starts there). Matched BY FILE NAME
(owner: "tied to the epub name for now"). No book on the command line:
the last one read opens. A missing recent file: a message, taken off.
SMOOTH FOLLOWING (owner: "display is rather jerky ... the row the reader
is on is central"): TEpubView.ScrollToWord(AWord, ACenter) - with
ACenter the word's LINE (WordLine: Skia's rect of the word) goes to the
middle, by SmoothScrollTo (15 ms timer, 20 % of the way per tick; a jump
farther than 1.5 screens is instant; any other scroll stops it); every
ScrollToWord of the reader centres. NOT COMPILED here (no Delphi).
Settings menu: later (owner: "We will also eventually need").
Zip 32 - FOOTNOTES (owner: "I couldn't spot any. They should probably be
highlighted ... File -> Goto Footnote -> [list] ... disable" when none):
TEpubView.NoteColor (index 4; default $FFEDE6D6, a shade darker than the
paper; claNull = off) drawn behind blocks whose Role = ewrNote (the
walker's: aside, epub:type / role / class footnote, endnote, note,
rearnote); reader DARK_NOTE $FF2C2C34. File > Go to Footnote: runs of
note words per document (at most 300), item "N. <chapter>: <first 8
words> ...", click = RestoreWord (lit; Play from there - a footnote
read at its call point plays there). OPEN: if Night Watch's EPUB does
not mark its footnotes as notes (plain paragraphs, or only a noteref
link), the menu stays disabled - then the markup decides what to
detect (the owner can describe one footnote's tags; the book stays
local).
Zip 33 (owner: "Reader doesn't have a menu"): a TMainMenu made in code
reaches the window's (Windows' / macOS') own menu bar only after
RecreateOSMenu - now called at the end of BuildMenu, BuildRecentMenu,
BuildNotesMenu and after a tick changes. If it still does not show:
a TMenuBar (FMX-drawn, Align Top) is the fallback.
Zip 34 - FIND (owner: "We could just add a Search function :)" ... "we
want one anyway"): Edit > Find (Ctrl+F) / Find next (F3) / Find previous
(Shift+F3); a find bar under the tool bar (layFind: edFind, < >, "3 of
17", X; Enter / Shift+Enter / Esc). FindAll: the query split at spaces,
each word compared with the book's words without case and surrounding
punctuation (FindKey = EpubWordCore + LowerCase); whole words, the LAST
one may be a word's start ("Vim" finds "Vimes"); contents page (role
nav) skipped. FindStep: from the match shown, else from ReadingWord;
round the book. A match: shown lit (all its words), centred, its chapter
in the contents, FClip / FSeekClip so Play starts there. While the find
box has the focus FormKeyDown leaves typed keys alone (P, D, L, R, [ ]
would otherwise act). A new book clears the matches. Night Watch's
footnotes: still need their markup to be found as notes.
LATER (owner): go to the suspicious parts from the results - needs the
reader inside the builder (or the builder inside the reader).
To come: remember settings (model, device, folders), a summary of the
not-spoken stretches, open the result in EpubReader, integrate in the
reader later (owner).

## Pushes checked
- 7723030 ("Claude push", 2026-11-15 21:12) = zips 15 - 32: every file
  identical to the deliveries (CR LF / BOM aside) except
  demos/EpubBuilder/EpubBuilder.dproj, re-saved by the IDE (its platform
  blocks and TargetedPlatforms; MainSource and the uBuilder reference
  unchanged) - the pushed one is the one to keep. pasdoc_check,
  project_check: 0 problems. TWhisper at f47da6b (= its zip 28).
- 26118e5 = zip 14 (owner: applied and pushed; his Delphi EpubConsole
  --overlay of the full Moby-Dick from TWhisper timings: 211964 clips, 0
  left out).
- 6ab27c4 ("EPub view etc") = zips 09-13: every delivered file identical
  to a fresh clone (2026-11-15); pasdoc_check, project_check 0 problems;
  FPC build of lib + EpubConsole runs. Owner: "11-13 applied and tested"
  (dark sidebar fixed by the transparent list style).
- ef2daff = zip 08 (review fixes, on 68162a4 = zips 06 + 07): checked
  2026-11-15 by clone; pasdoc_check and project_check 0 problems.
- e8c3a23: zips 01-04 match. The IDE added the Skia requires (now in the
  generator, zip 05) and re-saved the .dproj files. The owner added
  test/README.md and test/.gitignore (*.epub - test books stay local).
  The console folder was pushed as demos/EPubConsole; the owner renamed it
  to demos/EpubConsole in cdcebf7 (checked). bed841b = zip 05 (checked).

## Test notes (zip 01, FPC 3.0, Linux x64)
- Seven EPUBs (local only, copyrighted - never committed or quoted):
  Aladdin, The Stars My Destination, The Hobbit (illustrated, EPUB 3),
  Silverthorn, Night Watch, The Moment of the Magician, Magician. All open;
  every ZIP entry reads with its CRC; every document parses (Hobbit: 16
  repairs).
- Layout invariants on all seven: every word's span spells the word, no
  word without a block, runs cover each block's text - 0 failures. Night
  Watch's 834 italic runs come from its CSS classes (Calibre). Magician's
  293,229 words load in about 0.4 s.
- Synthetic EPUBs: EPUB 3 with nav, nested ids, a SMIL overlay (clock
  values h:mm:ss, mm:ss, 1.5s, 3200ms, 0.15min), cover, active class,
  duration; font obfuscation opens; AES encryption.xml and Adobe rights.xml
  are refused.
- Hobbit aligned with EpubConsole --text --body-only against the earlier
  transcript: exact 93,955 (same), not spoken 10,188 -> 9,679, not heard
  5 -> 0 (captions and notes left out).
- Owner's first Delphi build of zip 01 (Win64): E2003 DefaultFormatSettings
  in Epub.Css (FPC-only name; also in Epub.Book) - fixed in zip 02.
- Owner (2026-11-15, Delphi 13, Windows): EpubUnumFMX and EpubReader build
  (the IDE added the Skia requires to EpubUnumFMX on the first compile).
  EpubReader with Moby-Dick (IDPF epub3-samples, CC-BY-SA, media overlays,
  one AAC mp4): "All tests ran perfectly" - the book shows, WASAPI sound,
  the highlight follows the audio, pause / resume, clip buttons, chapter 2.
- A Windows "ding" on the very first run, not seen in the debugger log
  (that log is only the File Open dialog's shell noise). Possibly Ctrl+O:
  FormKeyDown opens the dialog inside the key press, and the pending Ctrl+O
  character may reach the dialog's file-name box. Unconfirmed - change only
  if it comes back (fix: TThread.ForceQueue the open).
- Not yet run: Linux / SteamOS (PulseAudio), macOS, a paged view.
