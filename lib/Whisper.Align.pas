(* @abstract(Aligns the text of record (a book's words) with the words of a
  transcription, so every book word gets the time it is spoken - or is
  marked as not spoken: the core of syncing an EPUB to its audiobook and of
  proof-listening a recording against its text.)

  Framework-free (no FMX / VCL / LCL); compiles with Delphi and FPC. No
  file or EPUB handling here: the caller gives the book's words in reading
  order (@link(WhisperSplitText)) and the transcription's words
  (@code(TWhisperTranscription.Words)).

  @bold(The book is the text of record.) The transcript only supplies times;
  its spelling, punctuation and mistakes never reach the reader. Whisper
  misspells names ('Mustafa' for 'Mustapha'), mishears words ('begoaled'),
  drops or repeats a few, writes numbers as digits, and adds what the
  reader says that the book does not hold (a LibriVox preamble, "End of
  ..."). The book may hold what was not read (front matter, a licence, a
  table of contents, a paragraph of a different edition).

  @bold(Nothing relies on markup.) Where the reading starts and ends, and
  which stretches were not read, follows from the alignment itself:
  @orderedList(
    @item(Both sides are cut into tokens: lower case, letters and digits
      only (apostrophes, hyphens, soft hyphens, zero-width characters
      dropped; Latin accents folded, 'Renee' = 'Renee' with an accent;
      ligatures expanded). Numbers become words ('40' = 'forty', '1867' =
      'eighteen sixty seven', '3rd' = 'third'), so one word can give several
      tokens.)
    @item(Anchors: token trigrams that occur exactly once in the book AND
      once in the transcript; of them the longest chain that runs forward
      in both (longest increasing subsequence) is kept, so a repeated or
      misplaced phrase cannot pull the alignment out of order.)
    @item(Between anchors an edit-distance alignment pairs tokens: equal,
      similar (at least half the letters in common), or two against one
      when they spell the same ('on to' = 'onto', 'can not' = 'cannot').
      Dissimilar tokens are never paired.)
    @item(A paired book word takes the time of its transcript word(s).
      Unpaired book words between two timed ones share the time between
      them in proportion to their length - unless that would mean reading
      far faster than the reader does: such a run was NOT SPOKEN (a missing
      paragraph, front matter between a stray match and the text). Text
      before the first or after the last timed word is not spoken either.)
    @item(Where the transcript is silent for @link(WHISPER_ALIGN_SILENCE) or
      more, the book words it lacks go into that silence and are "not
      heard" (@code(wamNotHeard)): the recogniser may have dropped them,
      so they are neither interpolated as heard nor blamed on the
      reader.)
    @item(A small cluster of matches cut off on both sides by text that was
      not spoken - Project Gutenberg's header repeating the title the reader
      speaks - is a coincidence: it is taken out and the alignment run
      again, so the title is found where it is really read.)
  )

  Tested on Aladdin (Gutenberg #57, 5261 story words; owner's medium.en
  DTW words): see the README. A 166 000-word book aligns in about a
  second. *)
unit Whisper.Align;

{$I Whisper.inc}

interface

uses
  SysUtils, Classes,
  Whisper.Types;

const
  { A pause of the transcript this long (10 ms units: 3 s) or longer is a
    silence: book words that the transcript lacks go there at almost no
    cost, and are wamNotHeard rather than not spoken. Real pauses of a
    reader are shorter; this is where the recogniser dropped speech, or
    music, or a long silence. }
  WHISPER_ALIGN_SILENCE = 3 * WHISPER_TICKS_PER_SECOND;

type
  { Words of a text, in reading order. }
  TWhisperStringArray = array of string;

  { How a book word got its time. }
  TWhisperAlignMatch = (
    { No time: only punctuation, not a word. }
    wamNone,
    { Paired with the same word(s) of the transcript. }
    wamExact,
    { Paired with similar word(s) (a spelling or hearing difference). }
    wamSimilar,
    { Not heard in the transcript, but placed between its timed neighbours
      at a plausible speed (a word the transcript dropped or misheard
      beyond recognition). }
    wamInterpolated,
    { Not spoken: before the first or after the last timed word, or a run
      that could not have been read in the time between its neighbours. }
    wamNotSpoken,
    { Not heard: the transcript has no words at all for a while
      (@code(WHISPER_ALIGN_SILENCE) or more) where these words belong, so
      whether they were spoken is unknown - most often the recogniser
      dropped the rest of a 30 s window. Placed in that time, like
      interpolated words; @code(TWhisperRun.FillGaps) transcribes such
      gaps again. }
    wamNotHeard
  );

  { The time of one book word. }
  TWhisperAlignedWord = record
    { Start, 10 ms units (-1 = no time). }
    T0: Int64;
    { End, 10 ms units (-1 = no time). }
    T1: Int64;
    { How the time was found. }
    Match: TWhisperAlignMatch;
    { Index of the (first) transcript word it was paired with (-1 when not
      paired). }
    WordIndex: Integer;
  end;
  { Times of the book words, one per book word. }
  TWhisperAlignedWordArray = array of TWhisperAlignedWord;

  { Figures of an alignment. }
  TWhisperAlignStats = record
    { Book words given. }
    BookWords: Integer;
    { Transcript words given. }
    TranscriptWords: Integer;
    { Anchors (unique trigrams) in the kept chain of the last pass. }
    Anchors: Integer;
    { Book words paired with equal transcript words. }
    Exact: Integer;
    { Book words paired with similar transcript words. }
    Similar: Integer;
    { Book words placed between timed neighbours. }
    Interpolated: Integer;
    { Book words not spoken. }
    NotSpoken: Integer;
    { Book words in a gap of the transcript (wamNotHeard). }
    NotHeard: Integer;
    { Book words without a time for being punctuation only. }
    Punctuation: Integer;
    { Reading speed of the timed words, words per second. }
    WordsPerSecond: Double;
    { Small isolated clusters of matches taken out (coincidences). }
    Isolated: Integer;
    { Alignment passes made (1 + one per round of taking clusters out). }
    Passes: Integer;
    { Longest run of interpolated book words. }
    LongestRun: Integer;
    { Index of the first book word of that run (-1 when there is none). }
    LongestRunStart: Integer;
    { The recogniser's habits learned from this book and recording, as
      'book=heard (count)': a book word heard differently in at least half
      of its places (5 or more), each way it was heard at least twice, the
      heard form never a word of the book. The alignment was run again
      with these counting as equal. }
    Learned: TWhisperStringArray;
    { Book words paired through a learned habit (counted in Exact). }
    LearnedWords: Integer;
  end;

  { A stretch of book words of one kind, for reports. }
  TWhisperAlignRegion = record
    { First book word. }
    First: Integer;
    { Last book word. }
    Last: Integer;
    { wamInterpolated, wamNotSpoken or wamNotHeard. }
    Match: TWhisperAlignMatch;
    { Time where the stretch is, 10 ms units: its start for interpolated
      words and words not heard, the end of the timed word before it for
      words not spoken (-1 at the very start). }
    Time: Int64;
  end;
  { Stretches, in book order. }
  TWhisperAlignRegionArray = array of TWhisperAlignRegion;

{ A word as the aligner compares it, its tokens joined by spaces: lower
  case, letters and digits only, Latin accents folded, ligatures expanded,
  numbers as words ('1867' gives 'eighteen sixty seven'). '' for a word of
  punctuation only. }
function WhisperNormalizeWord(const AWord: string): string;

{ English words of a number ('forty', 'one hundred and five', 'eighteen
  sixty seven' for a year-like 1100..1999), space separated.
  @param(AOrdinal  'fortieth', 'third' instead.) }
function WhisperNumberWords(ANumber: Int64; AOrdinal: Boolean = False): string;

{ Splits a text into words at white space and dashes (em, en and figure
  dashes, which books use without spaces): what @link(WhisperAlignText)
  expects. Punctuation stays with its word. }
function WhisperSplitText(const AText: string): TWhisperStringArray;

{ Aligns ABookWords (the text of record, in reading order) with the
  transcript words AWords. See the unit description.
  @param(AStats  Receives the figures of the alignment.)
  @returns(One entry per book word.) }
function WhisperAlignText(const ABookWords: TWhisperStringArray; const AWords: TWhisperWordArray;
  out AStats: TWhisperAlignStats): TWhisperAlignedWordArray;

{ The stretches of interpolated, not-spoken and not-heard words, at least
  AMinWords long (punctuation-only words inside a stretch count with it). }
function WhisperAlignRegions(const AAligned: TWhisperAlignedWordArray; AMinWords: Integer): TWhisperAlignRegionArray;

{ Name of a match kind ('none', 'exact', 'similar', 'interpolated',
  'not spoken', 'not heard'). }
function WhisperAlignMatchName(AMatch: TWhisperAlignMatch): string;

implementation

const
  { Words per anchor. }
  ANCHOR_N = 3;
  { Largest gap table (book tokens x transcript tokens) aligned token by
    token; a bigger gap (a long stretch with no anchor) is left unpaired. }
  MAX_GAP_CELLS = 4000000;
  { Cost of leaving a token unpaired. }
  COST_GAP = 1.0;
  { Cost of pairing similar (not equal) tokens. }
  COST_SIMILAR = 0.5;
  { Cost of pairing two tokens with one that spells the same. }
  COST_JOIN = 0.1;
  { Least share of letters two tokens must have in common to be similar. }
  MIN_SIMILARITY = 0.5;
  { Trace: pair one with one. }
  STEP_PAIR = 1;
  { Trace: book token left unpaired. }
  STEP_BOOK = 2;
  { Trace: transcript token left unpaired. }
  STEP_TRANSCRIPT = 3;
  { Trace: two book tokens with one transcript token. }
  STEP_JOIN_BOOK = 4;
  { Trace: one book token with two transcript tokens. }
  STEP_JOIN_TRANSCRIPT = 5;
  { Shortest run of unpaired words the speed check applies to (shorter
    runs: contractions, a dropped word, often in no time at all). }
  RATE_MIN_RUN = 4;
  { A run is not spoken when it would need more than this many times the
    reader's own speed ... }
  RATE_FACTOR = 2.5;
  { ... and more than this many words per second in any case. }
  RATE_MIN_LIMIT = 6.0;
  { A cluster of at most this many paired words between text that was not
    spoken is a coincidence. }
  MAX_ISOLATED_PAIRS = 8;
  { At least one side of such a cluster must be this many words not spoken
    (or the start / end of the book). }
  MIN_ISOLATING_RUN = 20;
  { Most alignment passes. }
  MAX_PASSES = 10;
  { A book token is learned when it was paired at least this often ... }
  LEARN_MIN_PAIRED = 5;
  { ... and heard differently in at least this share of those places; ... }
  LEARN_MIN_SHARE = 0.5;
  { ... each way it was heard this often or more is learned. }
  LEARN_MIN_VARIANT = 2;
  { Cost of leaving a book token unpaired where the transcript is silent
    (WHISPER_ALIGN_SILENCE or more): book words that the transcript lacks
    belong in its silences, not somewhere a common word happens to pair. }
  COST_GAP_IN_SILENCE = 0.05;
  { Before the first and after the last anchor only this many book tokens
    per transcript token (plus EDGE_SLACK) next to the anchor can pair:
    text further out could not have been read in that time. }
  EDGE_TOKENS_PER_TOKEN = 3;
  { See EDGE_TOKENS_PER_TOKEN. }
  EDGE_SLACK = 20;
  { Names of the match kinds. }
  MATCH_NAMES: array[TWhisperAlignMatch] of string = ('none', 'exact', 'similar', 'interpolated',
    'not spoken', 'not heard');
  { Number words 0..19. }
  SMALL_NUMBERS: array[0..19] of string = ('zero', 'one', 'two', 'three', 'four', 'five', 'six',
    'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen',
    'seventeen', 'eighteen', 'nineteen');
  { Number words of the tens (index 2..9). }
  TENS: array[2..9] of string = ('twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty',
    'ninety');
  { Ordinals of the words whose ordinal is not word + 'th'. }
  ORDINAL_FROM: array[0..8] of string = ('one', 'two', 'three', 'five', 'eight', 'nine', 'twelve',
    'zero', 'ninety');
  { The ordinals of ORDINAL_FROM. }
  ORDINAL_TO: array[0..8] of string = ('first', 'second', 'third', 'fifth', 'eighth', 'ninth', 'twelfth',
    'zeroth', 'ninetieth');
  { Latin-1 letters U+00C0..U+00FF folded to ASCII ('' = not a letter). }
  LATIN1_FOLD: array[$C0..$FF] of string = ('a', 'a', 'a', 'a', 'a', 'a', 'ae', 'c', 'e', 'e', 'e', 'e',
    'i', 'i', 'i', 'i', 'd', 'n', 'o', 'o', 'o', 'o', 'o', '', 'o', 'u', 'u', 'u', 'u', 'y', 'th', 'ss',
    'a', 'a', 'a', 'a', 'a', 'a', 'ae', 'c', 'e', 'e', 'e', 'e', 'i', 'i', 'i', 'i', 'd', 'n', 'o', 'o',
    'o', 'o', 'o', '', 'o', 'u', 'u', 'u', 'u', 'y', 'th', 'y');
  { Ligatures U+FB00..U+FB06 expanded. }
  LIGATURES: array[$FB00..$FB06] of string = ('ff', 'fi', 'fl', 'ffi', 'ffl', 'st', 'st');

type
  { Tokens. }
  TNormArray = array of UTF8String;
  { Integer list. }
  TIntArray = array of Integer;
  { Flags. }
  TBoolArray = array of Boolean;

  { A trigram and where it starts. }
  TGram = record
    { The three tokens, space separated. }
    Key: UTF8String;
    { Index of its first token. }
    Pos: Integer;
  end;
  { Trigrams. }
  TGramArray = array of TGram;

  { A book token paired with a transcript token. }
  TPair = record
    { Book token. }
    B: Integer;
    { Transcript token. }
    T: Integer;
    { @true when the two are equal (or join to equal spellings). }
    Exact: Boolean;
  end;
  { Pairs in increasing order. }
  TPairArray = array of TPair;

  { Tokens of one side and the word each comes from. }
  TTokens = record
    { The tokens. }
    Norm: TNormArray;
    { Word index of each token. }
    Word: TIntArray;
    { Tokens used. }
    Count: Integer;
    { Transcript only: the token is the last of its word and the transcript
      is silent after it for WHISPER_ALIGN_SILENCE or more (nil for the
      book). }
    SilenceAfter: TBoolArray;
  end;

function WhisperAlignMatchName(AMatch: TWhisperAlignMatch): string;
begin
  Result := MATCH_NAMES[AMatch];
end;

{ Words below one thousand, appended to AResult. }
procedure AddHundreds(N: Integer; var AResult: string);

  procedure Add(const S: string);
  begin
    if AResult <> '' then
      AResult := AResult + ' ';
    AResult := AResult + S;
  end;

begin
  if N >= 100 then
  begin
    Add(SMALL_NUMBERS[N div 100]);
    Add('hundred');
    N := N mod 100;
    if N > 0 then
      Add('and');
  end;
  if N >= 20 then
  begin
    Add(TENS[N div 10]);
    if N mod 10 > 0 then
      Add(SMALL_NUMBERS[N mod 10]);
  end
  else if N > 0 then
    Add(SMALL_NUMBERS[N]);
end;

function WhisperNumberWords(ANumber: Int64; AOrdinal: Boolean): string;
const
  THOUSAND = 1000;
  MILLION = 1000000;
  BILLION = 1000000000;
  YEAR_FIRST = 1100;
  YEAR_LAST = 1999;
  CENTURY = 100;
var
  Last, Rest: string;
  P, I: Integer;
begin
  Result := '';
  if ANumber < 0 then
    ANumber := -ANumber;
  if ANumber = 0 then
    Result := SMALL_NUMBERS[0]
  else if (ANumber >= YEAR_FIRST) and (ANumber <= YEAR_LAST) and not AOrdinal then
  begin
    // read as a year: 1867 = eighteen sixty seven, 1800 = eighteen hundred
    AddHundreds(Integer(ANumber div CENTURY), Result);
    if ANumber mod CENTURY = 0 then
      Result := Result + ' hundred'
    else
    begin
      if ANumber mod CENTURY < 10 then
        Result := Result + ' oh';   // 1805 = eighteen oh five
      AddHundreds(Integer(ANumber mod CENTURY), Result);
    end;
  end
  else
  begin
    if ANumber >= BILLION then
    begin
      AddHundreds(Integer((ANumber div BILLION) mod THOUSAND), Result);
      Result := Result + ' billion';
    end;
    if (ANumber div MILLION) mod THOUSAND > 0 then
    begin
      AddHundreds(Integer((ANumber div MILLION) mod THOUSAND), Result);
      Result := Result + ' million';
    end;
    if (ANumber div THOUSAND) mod THOUSAND > 0 then
    begin
      AddHundreds(Integer((ANumber div THOUSAND) mod THOUSAND), Result);
      Result := Result + ' thousand';
    end;
    if (ANumber >= THOUSAND) and (ANumber mod THOUSAND > 0) and (ANumber mod THOUSAND < CENTURY) then
      Result := Result + ' and';
    AddHundreds(Integer(ANumber mod THOUSAND), Result);
  end;
  Result := Trim(Result);
  if AOrdinal then
  begin
    P := LastDelimiter(' ', Result);
    Last := Copy(Result, P + 1, MaxInt);
    Rest := Copy(Result, 1, P);
    for I := 0 to High(ORDINAL_FROM) do
      if Last = ORDINAL_FROM[I] then
      begin
        Result := Rest + ORDINAL_TO[I];
        Exit;
      end;
    if (Last <> '') and (Last[Length(Last)] = 'y') then
      Result := Rest + Copy(Last, 1, Length(Last) - 1) + 'ieth'
    else
      Result := Result + 'th';
  end;
end;

{ Decodes the UTF-8 sequence at S[I] (I advanced past it). }
function NextCodePoint(const S: UTF8String; var I: Integer): Cardinal;
var
  L, K, N: Integer;
  B: Byte;
begin
  N := Length(S);
  B := Ord(S[I]);
  if B < $80 then
    L := 1
  else if (B and $E0) = $C0 then
    L := 2
  else if (B and $F0) = $E0 then
    L := 3
  else if (B and $F8) = $F0 then
    L := 4
  else
    L := 1;
  if I + L - 1 > N then
    L := 1;
  if L = 1 then
    Result := B
  else
  begin
    if L = 2 then
      Result := B and $1F
    else if L = 3 then
      Result := B and $0F
    else
      Result := B and $07;
    for K := 1 to L - 1 do
      Result := (Result shl 6) or (Cardinal(Ord(S[I + K])) and $3F);
  end;
  Inc(I, L);
end;

{ Appends code point C to S as UTF-8. }
procedure AppendCodePoint(var S: UTF8String; C: Cardinal);
var
  U: UTF8String;
begin
  if C < $80 then
    U := AnsiChar(C)
  else if C < $800 then
    U := AnsiChar($C0 or (C shr 6)) + AnsiChar($80 or (C and $3F))
  else if C < $10000 then
    U := AnsiChar($E0 or (C shr 12)) + AnsiChar($80 or ((C shr 6) and $3F)) + AnsiChar($80 or (C and $3F))
  else
    U := AnsiChar($F0 or (C shr 18)) + AnsiChar($80 or ((C shr 12) and $3F)) +
      AnsiChar($80 or ((C shr 6) and $3F)) + AnsiChar($80 or (C and $3F));
  S := S + U;
end;

{ The letters and digits of a word, lower case, accents folded, ligatures
  expanded (one string, before numbers are turned into words). }
function Letters(const AWord: string): UTF8String;
var
  S: UTF8String;
  I: Integer;
  C: Cardinal;
begin
  Result := '';
  S := UTF8String(AWord);
  I := 1;
  while I <= Length(S) do
  begin
    C := NextCodePoint(S, I);
    if (C >= Ord('A')) and (C <= Ord('Z')) then
      AppendCodePoint(Result, C + (Ord('a') - Ord('A')))
    else if ((C >= Ord('a')) and (C <= Ord('z'))) or ((C >= Ord('0')) and (C <= Ord('9'))) then
      AppendCodePoint(Result, C)
    else if (C >= Low(LATIN1_FOLD)) and (C <= High(LATIN1_FOLD)) then
      Result := Result + UTF8String(LATIN1_FOLD[C])
    else if (C >= Low(LIGATURES)) and (C <= High(LIGATURES)) then
      Result := Result + UTF8String(LIGATURES[C])
    else if (C = $152) or (C = $153) then
      Result := Result + 'oe'
    else if (C = $141) or (C = $142) then
      Result := Result + 'l'
    else if (C > $FF) and not ((C >= $2000) and (C <= $2BFF)) and not ((C >= $3000) and (C <= $303F)) and
      not ((C >= $FE00) and (C <= $FE0F)) and (C <> $FEFF) and not ((C >= $FF00) and (C <= $FF0F)) then
      AppendCodePoint(Result, C);   // a letter of another script (punctuation blocks excluded)
  end;
end;

{ Appends the tokens of one word to ATokens (numbers as words). }
procedure AddTokens(const AWord: string; AWordIndex: Integer; var ATokens: TTokens);

  procedure Add(const S: UTF8String);
  begin
    if S = '' then
      Exit;
    if ATokens.Count >= Length(ATokens.Norm) then
    begin
      SetLength(ATokens.Norm, ATokens.Count * 2 + 64);
      SetLength(ATokens.Word, ATokens.Count * 2 + 64);
    end;
    ATokens.Norm[ATokens.Count] := S;
    ATokens.Word[ATokens.Count] := AWordIndex;
    Inc(ATokens.Count);
  end;

const
  { Longest digit string read as a number (beyond: kept as digits). }
  MAX_DIGITS = 12;
var
  L, Words: UTF8String;
  I, N: Integer;
  Ordinal: Boolean;
  Suffix: UTF8String;
  Value: Int64;
begin
  L := Letters(AWord);
  if L = '' then
    Exit;
  // digits, optionally an ordinal suffix: a number
  N := 0;
  while (N < Length(L)) and (L[N + 1] >= '0') and (L[N + 1] <= '9') do
    Inc(N);
  Suffix := Copy(L, N + 1, MaxInt);
  Ordinal := (Suffix = 'st') or (Suffix = 'nd') or (Suffix = 'rd') or (Suffix = 'th');
  if (N > 0) and (N <= MAX_DIGITS) and ((Suffix = '') or Ordinal) then
  begin
    Value := StrToInt64(string(Copy(L, 1, N)));
    Words := UTF8String(WhisperNumberWords(Value, Ordinal)) + ' ';
    I := 1;
    while I <= Length(Words) do
    begin
      N := I;
      while Words[I] <> ' ' do
        Inc(I);
      Add(Copy(Words, N, I - N));
      Inc(I);
    end;
  end
  else
    Add(L);
end;

function WhisperNormalizeWord(const AWord: string): string;
var
  T: TTokens;
  I: Integer;
begin
  T.Norm := nil;
  T.Word := nil;
  T.Count := 0;
  AddTokens(AWord, 0, T);
  Result := '';
  for I := 0 to T.Count - 1 do
  begin
    if I > 0 then
      Result := Result + ' ';
    Result := Result + string(T.Norm[I]);
  end;
end;

function WhisperSplitText(const AText: string): TWhisperStringArray;
var
  S, Cur: UTF8String;
  I, J, N: Integer;
  C: Cardinal;
  Sep: Boolean;

  procedure Flush;
  begin
    if Cur <> '' then
    begin
      if N >= Length(Result) then
        SetLength(Result, N * 2 + 64);
      Result[N] := string(Cur);
      Inc(N);
      Cur := '';
    end;
  end;

begin
  Result := nil;
  N := 0;
  Cur := '';
  S := UTF8String(AText);
  I := 1;
  while I <= Length(S) do
  begin
    J := I;
    C := NextCodePoint(S, I);
    // white space (ASCII, no-break, the U+2000 spaces) and dashes
    Sep := (C <= Ord(' ')) or (C = $A0) or ((C >= $2000) and (C <= $200A)) or (C = $2028) or
      (C = $2029) or (C = $202F) or (C = $205F) or (C = $3000) or ((C >= $2012) and (C <= $2015));
    if Sep then
      Flush
    else
      Cur := Cur + Copy(S, J, I - J);
  end;
  Flush;
  SetLength(Result, N);
  if N = 0 then
    Result := nil;
end;

{ Levenshtein distance of two (short) strings, by bytes. }
function Distance(const A, B: UTF8String): Integer;
var
  Prev, Cur: TIntArray;
  I, J, Cost: Integer;
begin
  Prev := nil;
  Cur := nil;
  SetLength(Prev, Length(B) + 1);
  SetLength(Cur, Length(B) + 1);
  for J := 0 to Length(B) do
    Prev[J] := J;
  for I := 1 to Length(A) do
  begin
    Cur[0] := I;
    for J := 1 to Length(B) do
    begin
      if A[I] = B[J] then
        Cost := 0
      else
        Cost := 1;
      Cur[J] := Prev[J - 1] + Cost;
      if Prev[J] + 1 < Cur[J] then
        Cur[J] := Prev[J] + 1;
      if Cur[J - 1] + 1 < Cur[J] then
        Cur[J] := Cur[J - 1] + 1;
    end;
    for J := 0 to Length(B) do
      Prev[J] := Cur[J];
  end;
  Result := Prev[Length(B)];
end;

{ @true when two tokens are similar enough to be the same word misspelt or
  misheard. }
function Similar(const A, B: UTF8String): Boolean;
var
  L: Integer;
begin
  L := Length(A);
  if Length(B) > L then
    L := Length(B);
  Result := (L > 0) and (1 - Distance(A, B) / L >= MIN_SIMILARITY);
end;

{ Sorts trigrams by key (quicksort). }
procedure SortGrams(var A: TGramArray; L, R: Integer);
var
  I, J: Integer;
  P: UTF8String;
  T: TGram;
begin
  while L < R do
  begin
    I := L;
    J := R;
    P := A[(L + R) div 2].Key;
    repeat
      while A[I].Key < P do
        Inc(I);
      while A[J].Key > P do
        Dec(J);
      if I <= J then
      begin
        T := A[I];
        A[I] := A[J];
        A[J] := T;
        Inc(I);
        Dec(J);
      end;
    until I > J;
    if J - L < R - I then
    begin
      SortGrams(A, L, J);
      L := I;
    end
    else
    begin
      SortGrams(A, I, R);
      R := J;
    end;
  end;
end;

{ Sorts pairs by book position (quicksort; positions are unique). }
procedure SortPairs(var A: TPairArray; L, R: Integer);
var
  I, J, P: Integer;
  T: TPair;
begin
  while L < R do
  begin
    I := L;
    J := R;
    P := A[(L + R) div 2].B;
    repeat
      while A[I].B < P do
        Inc(I);
      while A[J].B > P do
        Dec(J);
      if I <= J then
      begin
        T := A[I];
        A[I] := A[J];
        A[J] := T;
        Inc(I);
        Dec(J);
      end;
    until I > J;
    if J - L < R - I then
    begin
      SortPairs(A, L, J);
      L := I;
    end
    else
    begin
      SortPairs(A, I, R);
      R := J;
    end;
  end;
end;

{ The trigrams of the first ACount tokens that occur once only, sorted by
  key. }
function UniqueGrams(const ANorm: TNormArray; ACount: Integer): TGramArray;
var
  All: TGramArray;
  I, J, N: Integer;
begin
  Result := nil;
  All := nil;
  if ACount < ANCHOR_N then
    Exit;
  SetLength(All, ACount - ANCHOR_N + 1);
  for I := 0 to High(All) do
  begin
    All[I].Key := ANorm[I];
    for J := 1 to ANCHOR_N - 1 do
      All[I].Key := All[I].Key + ' ' + ANorm[I + J];
    All[I].Pos := I;
  end;
  SortGrams(All, 0, High(All));
  SetLength(Result, Length(All));
  N := 0;
  I := 0;
  while I <= High(All) do
  begin
    J := I;
    while (J < High(All)) and (All[J + 1].Key = All[I].Key) do
      Inc(J);
    if J = I then
    begin
      Result[N] := All[I];
      Inc(N);
    end;
    I := J + 1;
  end;
  SetLength(Result, N);
end;

{ The anchors: trigrams unique on both sides, the longest chain increasing
  in both, as token pairs (every token of each kept trigram). }
function FindAnchors(const AB, AT: TTokens; out AAnchorCount: Integer): TPairArray;
var
  GB, GT: TGramArray;
  Cand: TPairArray;
  I, J, N, Lo, Hi, Mid, Len, K, LastB, LastT: Integer;
  TailIdx, Prev, Chain: TIntArray;
begin
  Result := nil;
  AAnchorCount := 0;
  GB := UniqueGrams(AB.Norm, AB.Count);
  GT := UniqueGrams(AT.Norm, AT.Count);
  Cand := nil;
  SetLength(Cand, Length(GB));
  N := 0;
  I := 0;
  J := 0;
  while (I <= High(GB)) and (J <= High(GT)) do
    if GB[I].Key < GT[J].Key then
      Inc(I)
    else if GB[I].Key > GT[J].Key then
      Inc(J)
    else
    begin
      Cand[N].B := GB[I].Pos;
      Cand[N].T := GT[J].Pos;
      Cand[N].Exact := True;
      Inc(N);
      Inc(I);
      Inc(J);
    end;
  SetLength(Cand, N);
  if N = 0 then
    Exit;
  SortPairs(Cand, 0, N - 1);
  // longest increasing subsequence on T
  TailIdx := nil;
  Prev := nil;
  SetLength(TailIdx, N);
  SetLength(Prev, N);
  Len := 0;
  for I := 0 to N - 1 do
  begin
    Lo := 0;
    Hi := Len;
    while Lo < Hi do
    begin
      Mid := (Lo + Hi) div 2;
      if Cand[TailIdx[Mid]].T < Cand[I].T then
        Lo := Mid + 1
      else
        Hi := Mid;
    end;
    if Lo > 0 then
      Prev[I] := TailIdx[Lo - 1]
    else
      Prev[I] := -1;
    TailIdx[Lo] := I;
    if Lo = Len then
      Inc(Len);
  end;
  Chain := nil;
  SetLength(Chain, Len);
  K := TailIdx[Len - 1];
  for I := Len - 1 downto 0 do
  begin
    Chain[I] := K;
    K := Prev[K];
  end;
  AAnchorCount := Len;
  SetLength(Result, Len * ANCHOR_N);
  N := 0;
  LastB := -1;
  LastT := -1;
  for I := 0 to Len - 1 do
    for J := 0 to ANCHOR_N - 1 do
      if (Cand[Chain[I]].B + J > LastB) and (Cand[Chain[I]].T + J > LastT) then
      begin
        Result[N].B := Cand[Chain[I]].B + J;
        Result[N].T := Cand[Chain[I]].T + J;
        Result[N].Exact := True;
        LastB := Result[N].B;
        LastT := Result[N].T;
        Inc(N);
      end;
  SetLength(Result, N);
end;

{ Appends a pair to APairs. }
procedure AddPair(var APairs: TPairArray; var ACount: Integer; AB, AT: Integer; AExact: Boolean);
begin
  if ACount >= Length(APairs) then
    SetLength(APairs, ACount * 2 + 64);
  APairs[ACount].B := AB;
  APairs[ACount].T := AT;
  APairs[ACount].Exact := AExact;
  Inc(ACount);
end;

{ Pairs the tokens of one gap (book B0..B1, transcript T0..T1, inclusive;
  either may be empty) by edit distance, appending to APairs.
  @param(APreferLate  On a tie, pair the later book tokens (the gap before
    the first anchor: the title the reader speaks is the one next to the
    text, not a copy in front matter); else the earlier ones.) }
procedure AlignGap(const AB, AT: TTokens; B0, B1, T0, T1: Integer; APreferLate: Boolean;
  var APairs: TPairArray; var ACount: Integer);
var
  NB, NT, I, J, W, NTmp: Integer;
  Row2, Row1, Cur: array of Double;
  Trace: array of Byte;
  C, D: Double;
  Tmp: TPairArray;
  Step: Byte;
begin
  NB := B1 - B0 + 1;
  NT := T1 - T0 + 1;
  if (NB <= 0) or (NT <= 0) or (Int64(NB + 1) * (NT + 1) > MAX_GAP_CELLS) then
    Exit;
  W := NT + 1;
  Row2 := nil;
  Row1 := nil;
  Cur := nil;
  Trace := nil;
  SetLength(Row2, W);
  SetLength(Row1, W);
  SetLength(Cur, W);
  SetLength(Trace, (NB + 1) * W);
  for J := 0 to NT do
  begin
    Row1[J] := J * COST_GAP;
    Row2[J] := 0;
    Trace[J] := STEP_TRANSCRIPT;
  end;
  for I := 1 to NB do
  begin
    // book tokens before the gap's first transcript token: in a silence
    // when the token before the gap is followed by one
    if (T0 > 0) and (AT.SilenceAfter <> nil) and AT.SilenceAfter[T0 - 1] then
      Cur[0] := Row1[0] + COST_GAP_IN_SILENCE
    else
      Cur[0] := Row1[0] + COST_GAP;
    Trace[I * W] := STEP_BOOK;
    for J := 1 to NT do
    begin
      if (AT.SilenceAfter <> nil) and AT.SilenceAfter[T0 + J - 1] then
        C := Row1[J] + COST_GAP_IN_SILENCE
      else
        C := Row1[J] + COST_GAP;
      Step := STEP_BOOK;
      D := Cur[J - 1] + COST_GAP;
      if (D < C) or (APreferLate and (D = C)) then
      begin
        C := D;
        Step := STEP_TRANSCRIPT;
      end;
      // two book tokens spelling one transcript token ('on to' = 'onto')
      if (I >= 2) and (AB.Norm[B0 + I - 2] + AB.Norm[B0 + I - 1] = AT.Norm[T0 + J - 1]) then
      begin
        D := Row2[J - 1] + COST_JOIN;
        if D <= C then
        begin
          C := D;
          Step := STEP_JOIN_BOOK;
        end;
      end;
      // one book token spelt as two transcript tokens
      if (J >= 2) and (AB.Norm[B0 + I - 1] = AT.Norm[T0 + J - 2] + AT.Norm[T0 + J - 1]) then
      begin
        D := Row1[J - 2] + COST_JOIN;
        if D <= C then
        begin
          C := D;
          Step := STEP_JOIN_TRANSCRIPT;
        end;
      end;
      if AB.Norm[B0 + I - 1] = AT.Norm[T0 + J - 1] then
        D := Row1[J - 1]
      else if Similar(AB.Norm[B0 + I - 1], AT.Norm[T0 + J - 1]) then
        D := Row1[J - 1] + COST_SIMILAR
      else
        D := C + 1;
      if D <= C then
      begin
        C := D;
        Step := STEP_PAIR;
      end;
      Cur[J] := C;
      Trace[I * W + J] := Step;
    end;
    for J := 0 to NT do
    begin
      Row2[J] := Row1[J];
      Row1[J] := Cur[J];
    end;
  end;
  // backtrack (pairs come out last first)
  Tmp := nil;
  NTmp := 0;
  I := NB;
  J := NT;
  while (I > 0) and (J > 0) do
    case Trace[I * W + J] of
      STEP_PAIR:
        begin
          AddPair(Tmp, NTmp, B0 + I - 1, T0 + J - 1, AB.Norm[B0 + I - 1] = AT.Norm[T0 + J - 1]);
          Dec(I);
          Dec(J);
        end;
      STEP_JOIN_BOOK:
        begin
          AddPair(Tmp, NTmp, B0 + I - 1, T0 + J - 1, True);
          AddPair(Tmp, NTmp, B0 + I - 2, T0 + J - 1, True);
          Dec(I, 2);
          Dec(J);
        end;
      STEP_JOIN_TRANSCRIPT:
        begin
          AddPair(Tmp, NTmp, B0 + I - 1, T0 + J - 1, True);
          AddPair(Tmp, NTmp, B0 + I - 1, T0 + J - 2, True);
          Dec(I);
          Dec(J, 2);
        end;
      STEP_BOOK:
        Dec(I);
    else
      Dec(J);
    end;
  for I := NTmp - 1 downto 0 do
    AddPair(APairs, ACount, Tmp[I].B, Tmp[I].T, Tmp[I].Exact);
end;

{ The token pairs of one alignment pass: anchors, and the gaps before,
  between and after them. }
function PairTokens(const AB, AT: TTokens; out AAnchorCount: Integer): TPairArray;
var
  Anchors: TPairArray;
  N, I, PB, PT, Edge: Integer;
begin
  Anchors := FindAnchors(AB, AT, AAnchorCount);
  Result := nil;
  N := 0;
  PB := -1;
  PT := -1;
  for I := 0 to Length(Anchors) do
  begin
    if (I = 0) and (Length(Anchors) > 0) then
    begin
      // before the first anchor: only the book text just before it
      Edge := Anchors[0].B - (Anchors[0].T * EDGE_TOKENS_PER_TOKEN + EDGE_SLACK);
      if Edge < 0 then
        Edge := 0;
      AlignGap(AB, AT, Edge, Anchors[0].B - 1, 0, Anchors[0].T - 1, True, Result, N);
    end
    else if I < Length(Anchors) then
      AlignGap(AB, AT, PB + 1, Anchors[I].B - 1, PT + 1, Anchors[I].T - 1, False, Result, N)
    else if Length(Anchors) > 0 then
    begin
      // after the last anchor: only the book text just after it
      Edge := PB + (AT.Count - 1 - PT) * EDGE_TOKENS_PER_TOKEN + EDGE_SLACK;
      if Edge > AB.Count - 1 then
        Edge := AB.Count - 1;
      AlignGap(AB, AT, PB + 1, Edge, PT + 1, AT.Count - 1, False, Result, N);
    end
    else
      AlignGap(AB, AT, 0, AB.Count - 1, 0, AT.Count - 1, False, Result, N);
    if I < Length(Anchors) then
    begin
      AddPair(Result, N, Anchors[I].B, Anchors[I].T, True);
      PB := Anchors[I].B;
      PT := Anchors[I].T;
    end;
  end;
  SetLength(Result, N);
end;

{ Length used to share time among words: letters and digits plus one. }
function WordWeight(const AWord: string): Integer;
begin
  Result := Length(Letters(AWord)) + 1;
end;

{ One alignment pass over the book words not in AExcluded: fills AResult
  (every word) and returns the number of clusters it took out (marked in
  AExcluded for the next pass). }
function AlignPass(const ABookWords: TWhisperStringArray; const AWords: TWhisperWordArray;
  const ATrans: TTokens; var AExcluded: TBoolArray; var AResult: TWhisperAlignedWordArray;
  var AStats: TWhisperAlignStats; ACounts: TStringList): Integer;
var
  BT: TTokens;
  Pairs: TPairArray;
  I, J, K, TW, Left, Right, Run, Paired, LeftRun, RightRun, First, Last: Integer;
  AllExact: TBoolArray;
  Total, Acc, Span, Rate, Limit: Double;
  FirstTime, LastTime: Int64;
  Timed, Unheard, LeftIsolating, RightIsolating: Boolean;
begin
  Result := 0;
  for I := 0 to High(AResult) do
  begin
    AResult[I].T0 := -1;
    AResult[I].T1 := -1;
    AResult[I].Match := wamNone;
    AResult[I].WordIndex := -1;
  end;
  // book tokens of the words still in play
  BT.Norm := nil;
  BT.Word := nil;
  BT.Count := 0;
  BT.SilenceAfter := nil;
  for I := 0 to High(ABookWords) do
    if not AExcluded[I] then
      AddTokens(ABookWords[I], I, BT);
  Pairs := PairTokens(BT, ATrans, AStats.Anchors);
  // book token / heard token pairs, for learning the recogniser's habits
  if ACounts <> nil then
  begin
    ACounts.Clear;
    for I := 0 to High(Pairs) do
      if (not Pairs[I].Exact) or (BT.Norm[Pairs[I].B] = ATrans.Norm[Pairs[I].T]) then
      begin
        J := ACounts.IndexOf(string(BT.Norm[Pairs[I].B]) + #9 + string(ATrans.Norm[Pairs[I].T]));
        if J < 0 then
          ACounts.AddObject(string(BT.Norm[Pairs[I].B]) + #9 + string(ATrans.Norm[Pairs[I].T]), TObject(1))
        else
          ACounts.Objects[J] := TObject(NativeInt(ACounts.Objects[J]) + 1);
      end;
  end;

  // a paired word spans its transcript words
  AllExact := nil;
  SetLength(AllExact, Length(ABookWords));
  for I := 0 to High(AllExact) do
    AllExact[I] := True;
  for I := 0 to High(Pairs) do
  begin
    J := BT.Word[Pairs[I].B];
    TW := ATrans.Word[Pairs[I].T];
    if AResult[J].WordIndex < 0 then
    begin
      AResult[J].WordIndex := TW;
      AResult[J].T0 := AWords[TW].T0;
      AResult[J].T1 := AWords[TW].T1;
    end
    else
    begin
      if AWords[TW].T0 < AResult[J].T0 then
        AResult[J].T0 := AWords[TW].T0;
      if AWords[TW].T1 > AResult[J].T1 then
        AResult[J].T1 := AWords[TW].T1;
    end;
    if not Pairs[I].Exact then
      AllExact[J] := False;
  end;
  for I := 0 to High(AResult) do
    if AResult[I].WordIndex >= 0 then
    begin
      if AllExact[I] then
        AResult[I].Match := wamExact
      else
        AResult[I].Match := wamSimilar;
    end;
  // consecutive book words on one transcript word ('to night' on
  // 'tonight') share its time by length
  I := 0;
  while I <= High(AResult) do
  begin
    J := I;
    if AResult[I].WordIndex >= 0 then
      while (J < High(AResult)) and (AResult[J + 1].WordIndex = AResult[I].WordIndex) and
        (AResult[J + 1].T0 = AResult[I].T0) and (AResult[J + 1].T1 = AResult[I].T1) do
        Inc(J);
    if J > I then
    begin
      Total := 0;
      for K := I to J do
        Total := Total + WordWeight(ABookWords[K]);
      Acc := AResult[I].T0;
      Span := AResult[I].T1 - AResult[I].T0;
      for K := I to J do
      begin
        AResult[K].T0 := Round(Acc);
        Acc := Acc + Span * WordWeight(ABookWords[K]) / Total;
        AResult[K].T1 := Round(Acc);
      end;
    end;
    I := J + 1;
  end;

  // the reader's speed
  Paired := 0;
  FirstTime := -1;
  LastTime := -1;
  for I := 0 to High(AResult) do
    if AResult[I].WordIndex >= 0 then
    begin
      Inc(Paired);
      if FirstTime < 0 then
        FirstTime := AResult[I].T0;
      LastTime := AResult[I].T1;
    end;
  if (Paired > 1) and (LastTime > FirstTime) then
    AStats.WordsPerSecond := Paired * WHISPER_TICKS_PER_SECOND / (LastTime - FirstTime)
  else
    AStats.WordsPerSecond := 0;
  Limit := AStats.WordsPerSecond * RATE_FACTOR;
  if Limit < RATE_MIN_LIMIT then
    Limit := RATE_MIN_LIMIT;

  // unpaired runs: interpolated, or not spoken
  I := 0;
  while I <= High(AResult) do
  begin
    if AResult[I].WordIndex >= 0 then
    begin
      Inc(I);
      Continue;
    end;
    Left := I - 1;
    Right := I;
    while (Right <= High(AResult)) and (AResult[Right].WordIndex < 0) do
      Inc(Right);
    Timed := (Left >= 0) and (Right <= High(AResult));
    Unheard := False;
    if Timed then
    begin
      Run := Right - Left - 1;
      Span := AResult[Right].T0 - AResult[Left].T1;
      if Span < 0 then
        Span := 0;
      Rate := Run * WHISPER_TICKS_PER_SECOND / (Span + 1);
      Timed := (Run < RATE_MIN_RUN) or (Rate <= Limit);
      // the transcript is silent there: no word of it starts in between
      if Span >= WHISPER_ALIGN_SILENCE then
      begin
        Unheard := True;
        for K := AResult[Left].WordIndex + 1 to AResult[Right].WordIndex - 1 do
          if (AWords[K].T0 >= AResult[Left].T1) and (AWords[K].T0 < AResult[Right].T0) then
          begin
            Unheard := False;
            Break;
          end;
        if Unheard then
          Timed := True;
      end;
    end;
    if Timed then
    begin
      Total := 0;
      for K := Left + 1 to Right - 1 do
        Total := Total + WordWeight(ABookWords[K]);
      Acc := AResult[Left].T1;
      for K := Left + 1 to Right - 1 do
      begin
        AResult[K].T0 := Round(Acc);
        Acc := Acc + Span * WordWeight(ABookWords[K]) / Total;
        AResult[K].T1 := Round(Acc);
        if Letters(ABookWords[K]) = '' then
          AResult[K].Match := wamNone
        else if Unheard then
          AResult[K].Match := wamNotHeard
        else
          AResult[K].Match := wamInterpolated;
      end;
    end
    else
      for K := I to Right - 1 do
        AResult[K].Match := wamNotSpoken;
    I := Right;
  end;
  for I := 0 to High(AResult) do
    if AExcluded[I] then
    begin
      AResult[I].Match := wamNotSpoken;
      AResult[I].T0 := -1;
      AResult[I].T1 := -1;
      AResult[I].WordIndex := -1;
    end;

  // small clusters of matches cut off by text not spoken: coincidences
  I := 0;
  while I <= High(AResult) do
  begin
    if AResult[I].Match = wamNotSpoken then
    begin
      Inc(I);
      Continue;
    end;
    First := I;
    Last := I;
    Paired := 0;
    while (Last <= High(AResult)) and (AResult[Last].Match <> wamNotSpoken) do
    begin
      if AResult[Last].WordIndex >= 0 then
        Inc(Paired);
      Inc(Last);
    end;
    Dec(Last);
    LeftRun := 0;
    K := First - 1;
    while (K >= 0) and (AResult[K].Match = wamNotSpoken) do
    begin
      Inc(LeftRun);
      Dec(K);
    end;
    LeftIsolating := (First = 0) or (LeftRun > 0);
    if K < 0 then
      LeftRun := MaxInt;   // the start of the book
    RightRun := 0;
    K := Last + 1;
    while (K <= High(AResult)) and (AResult[K].Match = wamNotSpoken) do
    begin
      Inc(RightRun);
      Inc(K);
    end;
    RightIsolating := (Last = High(AResult)) or (RightRun > 0);
    if K > High(AResult) then
      RightRun := MaxInt;  // the end of the book
    if (Paired <= MAX_ISOLATED_PAIRS) and LeftIsolating and RightIsolating and
      ((LeftRun >= MIN_ISOLATING_RUN) or (RightRun >= MIN_ISOLATING_RUN)) and
      not ((LeftRun = MaxInt) and (RightRun = MaxInt)) then
    begin
      for K := First to Last do
        AExcluded[K] := True;
      Inc(Result);
    end;
    I := Last + 1;
  end;
end;

{ Adds AN to the count of AKey in the sorted list AList. }
procedure AddCount(AList: TStringList; const AKey: string; AN: Integer);
var
  J: Integer;
begin
  J := AList.IndexOf(AKey);
  if J < 0 then
    AList.AddObject(AKey, TObject(NativeInt(AN)))
  else
    AList.Objects[J] := TObject(NativeInt(AList.Objects[J]) + AN);
end;

{ Count of AKey in the sorted list AList (0 if absent). }
function CountOf(AList: TStringList; const AKey: string): Integer;
var
  J: Integer;
begin
  J := AList.IndexOf(AKey);
  if J < 0 then
    Result := 0
  else
    Result := Integer(NativeInt(AList.Objects[J]));
end;

{ From ACounts ('book' #9 'heard' with counts, the last pass's pairs)
  learns the recogniser's habits: a book token paired LEARN_MIN_PAIRED
  times or more and heard differently in at least LEARN_MIN_SHARE of them;
  each way it was heard LEARN_MIN_VARIANT times or more, unless that form
  is a token of the book itself (then the difference may be the reader's)
  or is heard for two book tokens. AMap (sorted) gets the heard forms, each
  with its book token in AMapBook at the index in Objects. }
procedure LearnHabits(const ABookWords: TWhisperStringArray; ACounts, AMap, AMapBook: TStringList;
  var AStats: TWhisperAlignStats);
var
  I, K, N, P: Integer;
  B, Heard: string;
  Toks: TTokens;
  BookSet, Paired, Other, Ambiguous, Shown: TStringList;
begin
  AMap.Clear;
  AMapBook.Clear;
  Toks.Norm := nil;
  Toks.Word := nil;
  Toks.Count := 0;
  Toks.SilenceAfter := nil;
  for I := 0 to High(ABookWords) do
    AddTokens(ABookWords[I], I, Toks);
  BookSet := TStringList.Create;
  Paired := TStringList.Create;
  Other := TStringList.Create;
  Ambiguous := TStringList.Create;
  Shown := TStringList.Create;
  try
    BookSet.Sorted := True;
    BookSet.Duplicates := dupIgnore;
    Paired.Sorted := True;
    Other.Sorted := True;
    Ambiguous.Sorted := True;
    Ambiguous.Duplicates := dupIgnore;
    for I := 0 to Toks.Count - 1 do
      BookSet.Add(string(Toks.Norm[I]));
    for I := 0 to ACounts.Count - 1 do
    begin
      P := Pos(#9, ACounts[I]);
      B := Copy(ACounts[I], 1, P - 1);
      Heard := Copy(ACounts[I], P + 1, MaxInt);
      N := Integer(NativeInt(ACounts.Objects[I]));
      AddCount(Paired, B, N);
      if Heard <> B then
        AddCount(Other, B, N);
    end;
    for I := 0 to ACounts.Count - 1 do
    begin
      P := Pos(#9, ACounts[I]);
      B := Copy(ACounts[I], 1, P - 1);
      Heard := Copy(ACounts[I], P + 1, MaxInt);
      N := Integer(NativeInt(ACounts.Objects[I]));
      if (Heard = B) or (N < LEARN_MIN_VARIANT) or (BookSet.IndexOf(Heard) >= 0) or
        (CountOf(Paired, B) < LEARN_MIN_PAIRED) or (CountOf(Other, B) < LEARN_MIN_SHARE * CountOf(Paired, B)) then
        Continue;
      K := AMap.IndexOf(Heard);
      if K >= 0 then
        Ambiguous.Add(Heard)
      else
      begin
        AMapBook.Add(B);
        AMap.AddObject(Heard, TObject(NativeInt(AMapBook.Count - 1)));
        Shown.Add(Format('%s=%s (%d)', [B, Heard, N]));
      end;
    end;
    for I := 0 to Ambiguous.Count - 1 do
    begin
      K := AMap.IndexOf(Ambiguous[I]);
      if K >= 0 then
        AMap.Delete(K);
    end;
    AStats.Learned := nil;
    for I := 0 to Shown.Count - 1 do
    begin
      P := Pos('=', Shown[I]);
      Heard := Copy(Shown[I], P + 1, Pos(' (', Shown[I]) - P - 1);
      if Ambiguous.IndexOf(Heard) < 0 then
      begin
        SetLength(AStats.Learned, Length(AStats.Learned) + 1);
        AStats.Learned[High(AStats.Learned)] := Shown[I];
      end;
    end;
  finally
    Shown.Free;
    Ambiguous.Free;
    Other.Free;
    Paired.Free;
    BookSet.Free;
  end;
end;

function WhisperAlignText(const ABookWords: TWhisperStringArray; const AWords: TWhisperWordArray;
  out AStats: TWhisperAlignStats): TWhisperAlignedWordArray;
var
  Trans: TTokens;
  Excluded: TBoolArray;
  I, W, Removed, Run, RunStart: Integer;
  Counts, Map, MapBook: TStringList;
  Learned: Boolean;
begin
  AStats := Default(TWhisperAlignStats);
  AStats.BookWords := Length(ABookWords);
  AStats.TranscriptWords := Length(AWords);
  AStats.LongestRunStart := -1;
  Result := nil;
  SetLength(Result, Length(ABookWords));
  Excluded := nil;
  SetLength(Excluded, Length(ABookWords));
  Trans.Norm := nil;
  Trans.Word := nil;
  Trans.Count := 0;
  Trans.SilenceAfter := nil;
  for I := 0 to High(AWords) do
    AddTokens(AWords[I].Text, I, Trans);
  SetLength(Trans.SilenceAfter, Trans.Count);
  for I := 0 to Trans.Count - 1 do
  begin
    W := Trans.Word[I];
    Trans.SilenceAfter[I] := (W < High(AWords)) and ((I = Trans.Count - 1) or (Trans.Word[I + 1] <> W)) and
      (AWords[W + 1].T0 - AWords[W].T1 >= WHISPER_ALIGN_SILENCE);
  end;
  Counts := TStringList.Create;
  Map := TStringList.Create;
  MapBook := TStringList.Create;
  try
    Counts.Sorted := True;
    Map.Sorted := True;
    repeat
      Inc(AStats.Passes);
      Removed := AlignPass(ABookWords, AWords, Trans, Excluded, Result, AStats, Counts);
      Inc(AStats.Isolated, Removed);
    until (Removed = 0) or (AStats.Passes >= MAX_PASSES);
    // the recogniser's habits: learn them, then align again with them
    LearnHabits(ABookWords, Counts, Map, MapBook, AStats);
    Learned := Map.Count > 0;
    if Learned then
    begin
      for I := 0 to Trans.Count - 1 do
      begin
        W := Map.IndexOf(string(Trans.Norm[I]));
        if W >= 0 then
          Trans.Norm[I] := UTF8String(MapBook[Integer(NativeInt(Map.Objects[W]))]);
      end;
      // the clusters already taken out stay out
      repeat
        Inc(AStats.Passes);
        Removed := AlignPass(ABookWords, AWords, Trans, Excluded, Result, AStats, Counts);
        Inc(AStats.Isolated, Removed);
      until (Removed = 0) or (AStats.Passes >= 2 * MAX_PASSES);
      // book words paired through a habit
      for I := 0 to High(Result) do
        if (Result[I].Match = wamExact) and (Result[I].WordIndex >= 0) and
          (Map.IndexOf(WhisperNormalizeWord(AWords[Result[I].WordIndex].Text)) >= 0) then
          Inc(AStats.LearnedWords);
    end;
  finally
    MapBook.Free;
    Map.Free;
    Counts.Free;
  end;

  Run := 0;
  RunStart := 0;
  for I := 0 to High(Result) do
  begin
    case Result[I].Match of
      wamExact: Inc(AStats.Exact);
      wamSimilar: Inc(AStats.Similar);
      wamInterpolated: Inc(AStats.Interpolated);
      wamNotSpoken: Inc(AStats.NotSpoken);
      wamNotHeard: Inc(AStats.NotHeard);
    else
      Inc(AStats.Punctuation);
    end;
    if Result[I].Match = wamInterpolated then
    begin
      if Run = 0 then
        RunStart := I;
      Inc(Run);
      if Run > AStats.LongestRun then
      begin
        AStats.LongestRun := Run;
        AStats.LongestRunStart := RunStart;
      end;
    end
    else if Result[I].Match <> wamNone then
      Run := 0;
  end;
end;

function WhisperAlignRegions(const AAligned: TWhisperAlignedWordArray; AMinWords: Integer): TWhisperAlignRegionArray;
var
  I, J, N, K: Integer;
  M: TWhisperAlignMatch;
begin
  Result := nil;
  N := 0;
  I := 0;
  while I <= High(AAligned) do
  begin
    M := AAligned[I].Match;
    if (M <> wamInterpolated) and (M <> wamNotSpoken) and (M <> wamNotHeard) then
    begin
      Inc(I);
      Continue;
    end;
    J := I;
    while (J < High(AAligned)) and ((AAligned[J + 1].Match = M) or (AAligned[J + 1].Match = wamNone)) do
      Inc(J);
    while (J > I) and (AAligned[J].Match = wamNone) do
      Dec(J);
    if J - I + 1 >= AMinWords then
    begin
      SetLength(Result, N + 1);
      Result[N].First := I;
      Result[N].Last := J;
      Result[N].Match := M;
      if M <> wamNotSpoken then
        Result[N].Time := AAligned[I].T0
      else
      begin
        Result[N].Time := -1;
        K := I - 1;
        while (K >= 0) and (AAligned[K].T1 < 0) do
          Dec(K);
        if K >= 0 then
          Result[N].Time := AAligned[K].T1;
      end;
      Inc(N);
    end;
    I := J + 1;
  end;
end;

end.
