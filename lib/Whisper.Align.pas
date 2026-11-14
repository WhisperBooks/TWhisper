(* @abstract(Aligns the text of record (a book's words) with the words of a
  transcription, so every book word gets the time it is spoken: the core of
  syncing an EPUB to its audiobook.)

  Framework-free (no FMX / VCL / LCL); compiles with Delphi and FPC. No
  file or EPUB handling here: the caller gives the book's words in reading
  order and the transcription's words (@code(TWhisperTranscription.Words)).

  @bold(The book is the text of record.) The transcript only supplies times;
  its spelling, punctuation and mistakes never reach the reader. Whisper
  misspells names ('Mustafa' for 'Mustapha'), mishears words ('begoaled'),
  drops or repeats a few, and adds what the reader says that the book does
  not hold (a LibriVox preamble, "End of ...").

  @bold(How.) For a whole book (100 000 words and more) a full alignment
  table is far too big, so:
  @orderedList(
    @item(Both sides are normalised (lower case, letters and digits only;
      apostrophes and hyphens dropped, so "to-night" = "tonight").)
    @item(Anchors: word trigrams that occur exactly once in the book AND
      once in the transcript.)
    @item(Of the anchors, the longest chain that runs forward in both texts
      (longest increasing subsequence) is kept: a repeated or misplaced
      phrase cannot pull the alignment out of order.)
    @item(Between two anchors an edit-distance alignment pairs the words:
      equal words, or similar ones (at least half the letters in common by
      Levenshtein distance); two dissimilar words are never paired.)
    @item(A paired book word takes its transcript word's time. Unpaired
      book words share the time between their paired neighbours, in
      proportion to their length. Book text before the first or after the
      last paired word gets no time (-1): it was not spoken (licence text,
      front matter).)
  )
  @bold(Give it only spoken text.) Leave out what the reader does not say
  - Project Gutenberg's header and licence above all: they repeat the title
  ("The Project Gutenberg eBook of Aladdin and the Magic Lamp", "END OF THE
  PROJECT GUTENBERG EBOOK ALADDIN ...") and would take the times of the
  title the reader speaks. Tested on Aladdin (medium.en DTW words): of 5261
  story words 5202 paired exactly, 46 similar, 13 interpolated (none in
  a run), no time out of order; with a transcript broken over 25 minutes
  (dropped phrases) still 92 % exact, the longest interpolated run 58
  words.

  A long run of unpaired words (@link(TWhisperAlignStats.LongestRun)) marks
  a place where the transcript went wrong or the book differs: report it,
  or transcribe that stretch again. *)
unit Whisper.Align;

{$I Whisper.inc}

interface

uses
  SysUtils,
  Whisper.Types;

type
  { Words of a text, in reading order. }
  TWhisperStringArray = array of string;

  { How a book word got its time. }
  TWhisperAlignMatch = (
    { No time: before the first or after the last paired word, or not a
      word (only punctuation). }
    wamNone,
    { Paired with the same word of the transcript. }
    wamExact,
    { Paired with a similar word (a spelling or hearing difference). }
    wamSimilar,
    { Not in the transcript: placed between its paired neighbours. }
    wamInterpolated
  );

  { The time of one book word. }
  TWhisperAlignedWord = record
    { Start, 10 ms units (-1 = no time). }
    T0: Int64;
    { End, 10 ms units (-1 = no time). }
    T1: Int64;
    { How the time was found. }
    Match: TWhisperAlignMatch;
    { Index of the transcript word it was paired with (-1 when not paired). }
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
    { Anchors (unique trigrams) in the kept chain. }
    Anchors: Integer;
    { Book words paired with an equal transcript word. }
    Exact: Integer;
    { Book words paired with a similar transcript word. }
    Similar: Integer;
    { Book words placed between paired neighbours. }
    Interpolated: Integer;
    { Book words without a time. }
    Unplaced: Integer;
    { Longest run of interpolated book words. }
    LongestRun: Integer;
    { Index of the first book word of that run (-1 when there is none). }
    LongestRunStart: Integer;
  end;

{ A word as the aligner compares it: lower case, letters and digits only
  (apostrophes, hyphens and other punctuation dropped; letters beyond ASCII
  kept as they are). '' for a word of punctuation only. }
function WhisperNormalizeWord(const AWord: string): string;

{ Aligns ABookWords (the text of record, in reading order, split at white
  space) with the transcript words AWords. See the unit description.
  @param(AStats  Receives the figures of the alignment.)
  @returns(One entry per book word.) }
function WhisperAlignText(const ABookWords: TWhisperStringArray; const AWords: TWhisperWordArray;
  out AStats: TWhisperAlignStats): TWhisperAlignedWordArray;

{ Name of a match kind ('none', 'exact', 'similar', 'interpolated'). }
function WhisperAlignMatchName(AMatch: TWhisperAlignMatch): string;

implementation

const
  { Words per anchor. }
  ANCHOR_N = 3;
  { Largest gap table (book words x transcript words) aligned word by word;
    a bigger gap (a long stretch with no anchor) is interpolated. }
  MAX_GAP_CELLS = 4000000;
  { Cost of leaving a word unpaired. }
  COST_GAP = 1.0;
  { Cost of pairing similar (not equal) words. }
  COST_SIMILAR = 0.5;
  { Least share of letters two words must have in common to be similar. }
  MIN_SIMILARITY = 0.5;
  { Trace steps of the gap table. }
  STEP_PAIR = 1;
  { Trace: book word left unpaired. }
  STEP_BOOK = 2;
  { Trace: transcript word left unpaired. }
  STEP_TRANSCRIPT = 3;
  { Names of the match kinds. }
  MATCH_NAMES: array[TWhisperAlignMatch] of string = ('none', 'exact', 'similar', 'interpolated');

type
  { Normalised words. }
  TNormArray = array of UTF8String;
  { Integer list. }
  TIntArray = array of Integer;

  { A trigram and where it starts. }
  TGram = record
    { The three normalised words, space separated. }
    Key: UTF8String;
    { Index of its first word. }
    Pos: Integer;
  end;
  { Trigrams. }
  TGramArray = array of TGram;

  { A book word paired with a transcript word (normalised indexes). }
  TPair = record
    { Book word. }
    B: Integer;
    { Transcript word. }
    T: Integer;
  end;
  { Pairs in increasing order. }
  TPairArray = array of TPair;

function WhisperAlignMatchName(AMatch: TWhisperAlignMatch): string;
begin
  Result := MATCH_NAMES[AMatch];
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

{ The normalised form of a word, as UTF-8. }
function NormalizeU8(const AWord: string): UTF8String;
var
  S: UTF8String;
  I, L, K, N: Integer;
  C: Cardinal;
  B: Byte;
begin
  Result := '';
  S := UTF8String(AWord);
  N := Length(S);
  I := 1;
  while I <= N do
  begin
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
      C := B
    else
    begin
      if L = 2 then
        C := B and $1F
      else if L = 3 then
        C := B and $0F
      else
        C := B and $07;
      for K := 1 to L - 1 do
        C := (C shl 6) or (Cardinal(Ord(S[I + K])) and $3F);
    end;
    Inc(I, L);
    if (C >= Ord('A')) and (C <= Ord('Z')) then
      AppendCodePoint(Result, C + (Ord('a') - Ord('A')))
    else if ((C >= Ord('a')) and (C <= Ord('z'))) or ((C >= Ord('0')) and (C <= Ord('9'))) then
      AppendCodePoint(Result, C)
    else if (C >= $C0) and not ((C >= $2000) and (C <= $2BFF)) and not ((C >= $3000) and (C <= $303F)) and
      not ((C >= $FF00) and (C <= $FF0F)) and (C <> $D7) and (C <> $F7) then
      AppendCodePoint(Result, C);   // a letter beyond ASCII (punctuation blocks excluded)
  end;
end;

function WhisperNormalizeWord(const AWord: string): string;
begin
  Result := string(NormalizeU8(AWord));
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

{ @true when two normalised words are similar enough to be the same word
  misspelt or misheard. }
function Similar(const A, B: UTF8String): Boolean;
var
  L: Integer;
begin
  L := Length(A);
  if Length(B) > L then
    L := Length(B);
  Result := (L > 0) and (1 - Distance(A, B) / L >= MIN_SIMILARITY);
end;

{ Sorts trigrams by key (quicksort; ties keep no particular order). }
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

{ The trigrams of AWords that occur once only, sorted by key. }
function UniqueGrams(const AWords: TNormArray): TGramArray;
var
  All: TGramArray;
  I, J, N: Integer;
begin
  Result := nil;
  All := nil;
  if Length(AWords) < ANCHOR_N then
    Exit;
  SetLength(All, Length(AWords) - ANCHOR_N + 1);
  for I := 0 to High(All) do
  begin
    All[I].Key := AWords[I];
    for J := 1 to ANCHOR_N - 1 do
      All[I].Key := All[I].Key + ' ' + AWords[I + J];
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
  in both, as word pairs (every word of each kept trigram). }
function FindAnchors(const AB, AT: TNormArray; out AAnchorCount: Integer): TPairArray;
var
  GB, GT: TGramArray;
  Cand: TPairArray;
  I, J, N, Lo, Hi, Mid, Len, K, LastB, LastT: Integer;
  TailIdx, Prev, Chain: TIntArray;
begin
  Result := nil;
  AAnchorCount := 0;
  GB := UniqueGrams(AB);
  GT := UniqueGrams(AT);
  // keys in both (merge of the two sorted lists)
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
      Inc(N);
      Inc(I);
      Inc(J);
    end;
  SetLength(Cand, N);
  if N = 0 then
    Exit;
  // by book position (the merge left them in key order)
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
  // every word of every kept trigram, strictly increasing on both sides
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
        LastB := Result[N].B;
        LastT := Result[N].T;
        Inc(N);
      end;
  SetLength(Result, N);
end;

{ Pairs the words of one gap (book B0..B1, transcript T0..T1, inclusive;
  either may be empty) by edit distance, appending to APairs. }
procedure AlignGap(const AB, AT: TNormArray; B0, B1, T0, T1: Integer; var APairs: TPairArray;
  var ACount: Integer);
var
  NB, NT, I, J, W: Integer;
  PrevRow, CurRow: array of Double;
  Trace: array of Byte;
  C, D: Double;
  Tmp: TPairArray;
  NTmp: Integer;
begin
  NB := B1 - B0 + 1;
  NT := T1 - T0 + 1;
  if (NB <= 0) or (NT <= 0) or (Int64(NB + 1) * (NT + 1) > MAX_GAP_CELLS) then
    Exit;
  W := NT + 1;
  PrevRow := nil;
  CurRow := nil;
  Trace := nil;
  SetLength(PrevRow, W);
  SetLength(CurRow, W);
  SetLength(Trace, (NB + 1) * W);
  for J := 0 to NT do
  begin
    PrevRow[J] := J * COST_GAP;
    Trace[J] := STEP_TRANSCRIPT;
  end;
  for I := 1 to NB do
  begin
    CurRow[0] := I * COST_GAP;
    Trace[I * W] := STEP_BOOK;
    for J := 1 to NT do
    begin
      // leave the book word unpaired
      C := PrevRow[J] + COST_GAP;
      Trace[I * W + J] := STEP_BOOK;
      // leave the transcript word unpaired
      D := CurRow[J - 1] + COST_GAP;
      if D < C then
      begin
        C := D;
        Trace[I * W + J] := STEP_TRANSCRIPT;
      end;
      // pair them (equal or similar only)
      if AB[B0 + I - 1] = AT[T0 + J - 1] then
        D := PrevRow[J - 1]
      else if Similar(AB[B0 + I - 1], AT[T0 + J - 1]) then
        D := PrevRow[J - 1] + COST_SIMILAR
      else
        D := C + 1;
      if D <= C then
      begin
        C := D;
        Trace[I * W + J] := STEP_PAIR;
      end;
      CurRow[J] := C;
    end;
    for J := 0 to NT do
      PrevRow[J] := CurRow[J];
  end;
  // backtrack (pairs come out last first)
  Tmp := nil;
  SetLength(Tmp, NB);
  NTmp := 0;
  I := NB;
  J := NT;
  while (I > 0) and (J > 0) do
    case Trace[I * W + J] of
      STEP_PAIR:
        begin
          Tmp[NTmp].B := B0 + I - 1;
          Tmp[NTmp].T := T0 + J - 1;
          Inc(NTmp);
          Dec(I);
          Dec(J);
        end;
      STEP_BOOK:
        Dec(I);
    else
      Dec(J);
    end;
  for I := NTmp - 1 downto 0 do
  begin
    if ACount >= Length(APairs) then
      SetLength(APairs, ACount * 2 + 16);
    APairs[ACount] := Tmp[I];
    Inc(ACount);
  end;
end;

function WhisperAlignText(const ABookWords: TWhisperStringArray; const AWords: TWhisperWordArray;
  out AStats: TWhisperAlignStats): TWhisperAlignedWordArray;
var
  BNorm, TNorm: TNormArray;
  BMap: TIntArray;          // normalised book index -> book word index
  TMap: TIntArray;          // normalised transcript index -> transcript word index
  Anchors, Pairs: TPairArray;
  NPairs, I, J, K, PB, PT, Run, RunStart, Left, Right: Integer;
  Total, Acc: Double;
  Lens: TIntArray;
  Span: Double;
  W: UTF8String;
begin
  FillChar(AStats, SizeOf(AStats), 0);
  AStats.BookWords := Length(ABookWords);
  AStats.TranscriptWords := Length(AWords);
  AStats.LongestRunStart := -1;
  Result := nil;
  SetLength(Result, Length(ABookWords));
  for I := 0 to High(Result) do
  begin
    Result[I].T0 := -1;
    Result[I].T1 := -1;
    Result[I].Match := wamNone;
    Result[I].WordIndex := -1;
  end;
  // normalised words (punctuation-only words left out)
  BNorm := nil;
  BMap := nil;
  SetLength(BNorm, Length(ABookWords));
  SetLength(BMap, Length(ABookWords));
  K := 0;
  for I := 0 to High(ABookWords) do
  begin
    W := NormalizeU8(ABookWords[I]);
    if W <> '' then
    begin
      BNorm[K] := W;
      BMap[K] := I;
      Inc(K);
    end;
  end;
  SetLength(BNorm, K);
  TNorm := nil;
  TMap := nil;
  SetLength(TNorm, Length(AWords));
  SetLength(TMap, Length(AWords));
  K := 0;
  for I := 0 to High(AWords) do
  begin
    W := NormalizeU8(AWords[I].Text);
    if W <> '' then
    begin
      TNorm[K] := W;
      TMap[K] := I;
      Inc(K);
    end;
  end;
  SetLength(TNorm, K);

  // anchors, then the gaps before, between and after them
  Anchors := FindAnchors(BNorm, TNorm, AStats.Anchors);
  Pairs := nil;
  NPairs := 0;
  PB := -1;
  PT := -1;
  for I := 0 to Length(Anchors) do
  begin
    if I < Length(Anchors) then
      AlignGap(BNorm, TNorm, PB + 1, Anchors[I].B - 1, PT + 1, Anchors[I].T - 1, Pairs, NPairs)
    else
      AlignGap(BNorm, TNorm, PB + 1, High(BNorm), PT + 1, High(TNorm), Pairs, NPairs);
    if I < Length(Anchors) then
    begin
      if NPairs >= Length(Pairs) then
        SetLength(Pairs, NPairs * 2 + 16);
      Pairs[NPairs] := Anchors[I];
      Inc(NPairs);
      PB := Anchors[I].B;
      PT := Anchors[I].T;
    end;
  end;

  // paired words take their transcript word's time
  for I := 0 to NPairs - 1 do
  begin
    J := BMap[Pairs[I].B];
    K := TMap[Pairs[I].T];
    Result[J].T0 := AWords[K].T0;
    Result[J].T1 := AWords[K].T1;
    Result[J].WordIndex := K;
    if BNorm[Pairs[I].B] = TNorm[Pairs[I].T] then
      Result[J].Match := wamExact
    else
      Result[J].Match := wamSimilar;
  end;

  // unpaired words between two paired ones share the time between them
  Lens := nil;
  I := 0;
  while I <= High(Result) do
  begin
    if Result[I].Match <> wamNone then
    begin
      Inc(I);
      Continue;
    end;
    Left := I - 1;
    Right := I;
    while (Right <= High(Result)) and (Result[Right].Match = wamNone) do
      Inc(Right);
    if (Left >= 0) and (Right <= High(Result)) then
    begin
      Run := Right - Left - 1;
      SetLength(Lens, Run);
      Total := 0;
      for K := 0 to Run - 1 do
      begin
        Lens[K] := Length(NormalizeU8(ABookWords[Left + 1 + K])) + 1;
        Total := Total + Lens[K];
      end;
      Span := Result[Right].T0 - Result[Left].T1;
      if Span < 0 then
        Span := 0;
      Acc := Result[Left].T1;
      for K := 0 to Run - 1 do
      begin
        Result[Left + 1 + K].T0 := Round(Acc);
        Acc := Acc + Span * Lens[K] / Total;
        Result[Left + 1 + K].T1 := Round(Acc);
        Result[Left + 1 + K].Match := wamInterpolated;
      end;
      if Run > AStats.LongestRun then
      begin
        AStats.LongestRun := Run;
        AStats.LongestRunStart := Left + 1;
      end;
    end;
    I := Right;
  end;
  // a run that was not placed stays wamNone; mark interpolated ones only
  RunStart := 0;
  for I := 0 to High(Result) do
    case Result[I].Match of
      wamExact: Inc(AStats.Exact);
      wamSimilar: Inc(AStats.Similar);
      wamInterpolated: Inc(AStats.Interpolated);
    else
      Inc(RunStart);
    end;
  AStats.Unplaced := RunStart;
end;

end.
