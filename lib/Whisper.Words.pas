(* @abstract(Word-level timings: the DTW set-up of a model
  (@link(WhisperEnableDtw)), tokens joined into words with start and end
  times (@link(WhisperBuildWords)), and word export (JSON, Audacity
  labels).)

  Framework-free (no FMX / VCL / LCL); compiles with Delphi and FPC.

  @bold(Why words.) whisper.cpp's segments are far too coarse to sync text
  to audio (the first segment of an audiobook can span 26 s). Words need
  one time per token, and the accurate source of those is dynamic time
  warping (DTW) over the cross-attention of the model's alignment heads -
  OpenAI's word_timestamps method, which whisper.cpp implements as
  "dtw_token_timestamps". It is chosen when the MODEL is loaded:
  @link(WhisperEnableDtw) picks the alignment heads of the model from its
  file header and turns flash attention off (whisper.cpp silently disables
  DTW with flash attention, its default). Without DTW, whisper.cpp's token
  time stamps (a heuristic) are the fallback.

  @bold(What a DTW time means.) whisper.cpp stores, per text token, the
  moment the alignment path ENTERS the next token's row - in OpenAI's terms
  the END of the token (OpenAI's own start of token k is the entry into row
  k, whose input is the token before it). So a token's start is the
  previous token's time, and the first token of a run starts at 0; the
  segment-boundary rules below then pull starts after pauses back to the
  segment's own start.

  @bold(How tokens become words) (a port of OpenAI's whisper/timing.py and
  tokenizer.py):
  @orderedList(
    @item(Text tokens are joined until they form whole UTF-8 characters.)
    @item(Languages with spaces: a piece starting with a space, or
      consisting of punctuation, starts a new word; others are appended.
      Chinese, Japanese, Thai, Lao, Burmese and Cantonese: every whole
      character piece is a word.)
    @item(The median word duration (at most 0.7 s) bounds words at
      sentence ends.)
    @item(Opening punctuation is moved to the following word, closing
      punctuation to the previous one (keeping that word's times). Unlike
      OpenAI, a token made only of such marks ('!"', '."', '),') moves
      too: OpenAI tests for a single mark and leaves those as words of
      their own, which books full of dialogue would be littered with.)
    @item(Words are handed to the segments by token count; the first word
      after a pause and the first and last word of a segment are bounded
      by the segment's own start and end.)
  )

  @bold(Limits.) With voice activity detection whisper.cpp maps only
  segment times back to the original audio, not token times, so
  @code(TWhisperRun) refuses words together with Vad. DTW needs the full
  audio context (AudioContext = 0): whisper.cpp asserts otherwise. *)
unit Whisper.Words;

{$I Whisper.inc}

interface

uses
  SysUtils, Classes,
  Whisper.Types;

type
  { The hyperparameters at the start of a ggml model file (whisper.cpp's
    whisper_hparams, in file order, after the magic number). }
  TWhisperModelHeader = record
    { Vocabulary size (51864 English only, 51865 multilingual, 51866 for
      large-v3 and its turbo). }
    NVocab: Int32;
    { Audio context: encoder positions (1500 = 30 s). }
    NAudioCtx: Int32;
    { Encoder width. }
    NAudioState: Int32;
    { Encoder attention heads. }
    NAudioHead: Int32;
    { Encoder layers. }
    NAudioLayer: Int32;
    { Text context: decoder positions (448). }
    NTextCtx: Int32;
    { Decoder width. }
    NTextState: Int32;
    { Decoder attention heads. }
    NTextHead: Int32;
    { Decoder layers. }
    NTextLayer: Int32;
    { Mel bands (80; 128 for large-v3 and its turbo). }
    NMels: Int32;
    { Weight type (plus the quantisation version times 1000). }
    FType: Int32;
  end;

{ Reads the header of a ggml model file.
  @returns(@false when the file cannot be read or is not a ggml model.) }
function WhisperReadModelHeader(const AFileName: string; out AHeader: TWhisperModelHeader): Boolean;

{ The alignment-heads preset of a model, from its header: tiny ... large-v3
  and large-v3-turbo (quantised files too). large-v1 and large-v2 have the
  same header; a file name containing 'v1' means large-v1. A model that is
  none of these (distil-whisper, fine-tunes with other shapes) gets
  @code(wahNTopMost). }
function WhisperDtwPreset(const AHeader: TWhisperModelHeader; const AFileName: string): TWhisperAlignmentHeadsPreset;

{ Name of a preset for logs ('large-v3-turbo', 'top layers', ...). }
function WhisperDtwPresetName(APreset: TWhisperAlignmentHeadsPreset): string;

{ Sets AParams up for DTW token times (word timings) with the model
  AModelFile: dtw_token_timestamps on, the alignment heads, flash attention
  OFF (whisper.cpp disables DTW with flash attention), dtw_n_top for
  @code(wahNTopMost) (half the decoder layers, as OpenAI's default heads)
  and dtw_mem_size large enough for the heads.
  @param(APreset  wahNone = choose from the model's header
    (@link(WhisperDtwPreset)); wahCustom = keep the heads already in
    AParams.)
  @returns(@false - AParams unchanged - when the heads must come from the
    header and the file cannot be read.) }
function WhisperEnableDtw(const AModelFile: string; var AParams: TWhisperContextParams;
  APreset: TWhisperAlignmentHeadsPreset = wahNone): Boolean;

{ Joins the text tokens of ASegments into words with times (see the unit
  description). The segments need their tokens (TWhisperRun.IncludeWords
  or IncludeTokens).
  @param(ALanguage  Language code of the run ('en', 'zh', ...): decides
    whether words are separated by spaces.)
  @param(ATiming  wwtDtw: the tokens' DTW times; wwtTokenTimestamps: their
    t0 / t1.)
  @returns(The words in spoken order; @nil for wwtNone or no text.) }
function WhisperBuildWords(const ASegments: TWhisperSegmentArray; const ALanguage: string;
  ATiming: TWhisperWordTiming): TWhisperWordArray;

{ Name of a timing source ('dtw', 'token_timestamps', 'none'). }
function WhisperWordTimingName(ATiming: TWhisperWordTiming): string;

{ The words as an Audacity label track: one line per word, start TAB end
  TAB word, seconds with a '.' decimal point. Import it in Audacity (File,
  Import, Labels) over the audio to check the timings by ear. Save as
  UTF-8 without a byte order mark (@code(WhisperSaveTextFile)). }
function WhisperWordsToLabels(const AWords: TWhisperWordArray): string;

{ The result as JSON: language, word timing source, audio length, and the
  segments with their words (word, start, end, probability; seconds). Pure
  ASCII (other characters as \u escapes), so any file encoding keeps it
  intact. }
function WhisperWordsToJson(const AResult: TWhisperTranscription): string;

implementation

const
  { First four bytes of a ggml model file ('ggml' read as a little-endian
    32-bit value). }
  GGML_FILE_MAGIC = $67676D6C;
  { Vocabulary size from which a model is multilingual. }
  MULTILINGUAL_VOCAB = 51865;
  { Mel bands of large-v3 and large-v3-turbo. }
  LARGE_V3_MELS = 128;
  { Decoder width of tiny. }
  TINY_STATE = 384;
  { Decoder width of base. }
  BASE_STATE = 512;
  { Decoder width of small. }
  SMALL_STATE = 768;
  { Decoder width of medium. }
  MEDIUM_STATE = 1024;
  { Decoder width of large (every version). }
  LARGE_STATE = 1280;
  { Decoder layers of tiny. }
  TINY_LAYERS = 4;
  { Decoder layers of base. }
  BASE_LAYERS = 6;
  { Decoder layers of small. }
  SMALL_LAYERS = 12;
  { Decoder layers of medium. }
  MEDIUM_LAYERS = 24;
  { Decoder (and encoder) layers of large. }
  LARGE_LAYERS = 32;
  { Decoder layers of large-v3-turbo. }
  TURBO_LAYERS = 4;

  { Alignment heads of each preset (whisper.cpp's g_aheads tables); 0 for
    the presets without a fixed table. }
  PRESET_HEADS: array[TWhisperAlignmentHeadsPreset] of Integer = (0, 0, 0, 8, 6, 5, 8, 19, 10, 18,
    6, 9, 23, 10, 6);
  { Names of the presets. }
  PRESET_NAMES: array[TWhisperAlignmentHeadsPreset] of string = ('none', 'top layers', 'custom',
    'tiny.en', 'tiny', 'base.en', 'base', 'small.en', 'small', 'medium.en', 'medium', 'large-v1',
    'large-v2', 'large-v3', 'large-v3-turbo');
  { Names of the timing sources. }
  TIMING_NAMES: array[TWhisperWordTiming] of string = ('none', 'dtw', 'token_timestamps');

  { Copies of the attention weights whisper.cpp holds at once during DTW
    (the weights, normalised, median-filtered). }
  DTW_MEM_COPIES = 3;
  { Decoder rows beyond half the text context (the sampled tokens): start
    of transcript, language, no-timestamps, end of text, slack. }
  DTW_EXTRA_ROWS = 8;
  { Bytes added to the estimate: graph, cost and trace matrices. }
  DTW_MEM_MARGIN = 32 * 1024 * 1024;

  { Longest median word duration used, 10 ms units (OpenAI: 0.7 s). }
  MAX_MEDIAN_TICKS = 70;
  { Margin of the segment-boundary rules, 10 ms units (OpenAI: 0.5 s). }
  SEGMENT_MARGIN_TICKS = 50;
  { The first word after a pause: a pause is longer than this many median
    word durations (OpenAI). }
  PAUSE_MEDIANS = 4;

  { Python's string.punctuation (ASCII), as code points. }
  ASCII_PUNCTUATION: array[0..31] of Cardinal = ($21, $22, $23, $24, $25, $26, $27, $28, $29, $2A,
    $2B, $2C, $2D, $2E, $2F, $3A, $3B, $3C, $3D, $3E, $3F, $40, $5B, $5C, $5D, $5E, $5F, $60, $7B,
    $7C, $7D, $7E);
  { OpenAI's prepend_punctuations: double quote, apostrophe, left double
    quotation mark, inverted question mark, opening parenthesis, bracket and
    brace, hyphen. }
  PREPEND_PUNCTUATION: array[0..7] of Cardinal = ($22, $27, $201C, $BF, $28, $5B, $7B, $2D);
  { OpenAI's append_punctuations: double quote, apostrophe, full stop,
    ideographic full stop, comma, fullwidth comma, exclamation mark and its
    fullwidth form, question mark and its fullwidth form, colon and its
    fullwidth form, right double quotation mark, closing parenthesis,
    bracket and brace, ideographic comma. }
  APPEND_PUNCTUATION: array[0..16] of Cardinal = ($22, $27, $2E, $3002, $2C, $FF0C, $21, $FF01, $3F,
    $FF1F, $3A, $FF1A, $201D, $29, $5D, $7D, $3001);
  { OpenAI's sentence_end_marks: '.', ideographic full stop, '!', fullwidth
    '!', '?', fullwidth '?'. }
  SENTENCE_END: array[0..5] of Cardinal = ($2E, $3002, $21, $FF01, $3F, $FF1F);
  { Languages written without spaces between words (OpenAI's list): every
    whole character is a word. }
  NO_SPACE_LANGUAGES: array[0..5] of string = ('zh', 'ja', 'th', 'lo', 'my', 'yue');

  { First code point of a UTF-16 surrogate pair's range above the BMP. }
  UNICODE_SUPPLEMENTARY = $10000;
  { High surrogate base. }
  HIGH_SURROGATE = $D800;
  { Low surrogate base. }
  LOW_SURROGATE = $DC00;
  { Code point of the replacement character. }
  REPLACEMENT_CHAR = $FFFD;

type
  { Code points of a piece of text. }
  TCodePoints = array of Cardinal;

  { One text token of the run with its time span (10 ms units). }
  TFlatToken = record
    { The token's UTF-8 bytes. }
    Bytes: UTF8String;
    { Probability. }
    P: Single;
    { Start. }
    T0: Double;
    { End. }
    T1: Double;
  end;
  { The text tokens of a run, in order. }
  TFlatTokenArray = array of TFlatToken;

  { A word while it is built. }
  TWordWork = record
    { UTF-8 bytes, with OpenAI's spaces (a leading space marks a new word). }
    Bytes: UTF8String;
    { Tokens the word holds (moves with merged punctuation). }
    TokenCount: Integer;
    { Start, 10 ms units. }
    T0: Double;
    { End, 10 ms units. }
    T1: Double;
    { Mean token probability. }
    Probability: Double;
    { Segment index (set when handed to a segment). }
    Segment: Integer;
  end;
  { Words while they are built. }
  TWordWorkArray = array of TWordWork;

  { Durations, for the median. }
  TDoubleArray = array of Double;
  { Text tokens per segment. }
  TIntegerArray = array of Integer;

{ The larger of two values. }
function MaxD(A, B: Double): Double;
begin
  if A > B then
    Result := A
  else
    Result := B;
end;

{ The smaller of two values. }
function MinD(A, B: Double): Double;
begin
  if A < B then
    Result := A
  else
    Result := B;
end;

{ Length of the UTF-8 sequence that starts with byte B (1 for a byte that
  cannot start one: it then stands alone). }
function Utf8SeqLen(B: Byte): Integer;
begin
  if B < $80 then
    Result := 1
  else if (B and $E0) = $C0 then
    Result := 2
  else if (B and $F0) = $E0 then
    Result := 3
  else if (B and $F8) = $F0 then
    Result := 4
  else
    Result := 1;
end;

{ @true when S does not end inside a UTF-8 sequence. }
function Utf8Complete(const S: UTF8String): Boolean;
var
  I, N: Integer;
begin
  N := Length(S);
  I := 1;
  while I <= N do
    I := I + Utf8SeqLen(Ord(S[I]));
  Result := I = N + 1;
end;

{ Decodes UTF-8 to code points (a cut or invalid byte gives the
  replacement character). }
function CodePoints(const S: UTF8String): TCodePoints;
var
  I, K, L, N, Count: Integer;
  C: Cardinal;
begin
  Result := nil;
  N := Length(S);
  if N = 0 then
    Exit;
  SetLength(Result, N);
  Count := 0;
  I := 1;
  while I <= N do
  begin
    L := Utf8SeqLen(Ord(S[I]));
    if I + L - 1 > N then
      L := 1;
    if L = 1 then
    begin
      C := Ord(S[I]);
      if C >= $80 then
        C := REPLACEMENT_CHAR;
    end
    else
    begin
      if L = 2 then
        C := Ord(S[I]) and $1F
      else if L = 3 then
        C := Ord(S[I]) and $0F
      else
        C := Ord(S[I]) and $07;
      for K := 1 to L - 1 do
        C := (C shl 6) or (Cardinal(Ord(S[I + K])) and $3F);
    end;
    Result[Count] := C;
    Inc(Count);
    Inc(I, L);
  end;
  SetLength(Result, Count);
end;

{ Python's "AText in ASet" for two strings: AText is empty or occurs in
  ASet as a run of code points. }
function IsIn(const AText: TCodePoints; const ASet: array of Cardinal): Boolean;
var
  I, J: Integer;
begin
  Result := Length(AText) = 0;
  I := 0;
  while not Result and (I <= Length(ASet) - Length(AText)) do
  begin
    J := 0;
    while (J < Length(AText)) and (AText[J] = ASet[I + J]) do
      Inc(J);
    Result := J = Length(AText);
    Inc(I);
  end;
end;

{ @true when AText is not empty and every code point of it is in ASet. }
function AllIn(const AText: TCodePoints; const ASet: array of Cardinal): Boolean;
var
  I, J: Integer;
  Found: Boolean;
begin
  Result := Length(AText) > 0;
  for I := 0 to High(AText) do
  begin
    Found := False;
    for J := 0 to High(ASet) do
      if AText[I] = ASet[J] then
        Found := True;
    if not Found then
      Result := False;
  end;
end;

{ OpenAI's punctuation test ("AText in ASet"), widened to runs made only of
  set members, so that '!"', '."' and '),' (one token each, common in
  books) join their word too. }
function IsPunctuationOf(const AText: TCodePoints; const ASet: array of Cardinal): Boolean;
begin
  Result := IsIn(AText, ASet) or AllIn(AText, ASet);
end;

{ S without leading and trailing spaces and control characters. }
function StripSpaces(const S: UTF8String): UTF8String;
var
  A, B: Integer;
begin
  A := 1;
  B := Length(S);
  while (A <= B) and (Ord(S[A]) <= Ord(' ')) do
    Inc(A);
  while (B >= A) and (Ord(S[B]) <= Ord(' ')) do
    Dec(B);
  Result := Copy(S, A, B - A + 1);
end;

{ @true when S starts with a space. }
function StartsWithSpace(const S: UTF8String): Boolean;
begin
  Result := (S <> '') and (S[1] = ' ');
end;

{ @true when S ends with a space. }
function EndsWithSpace(const S: UTF8String): Boolean;
begin
  Result := (S <> '') and (S[Length(S)] = ' ');
end;

{ @true for a language written without spaces between words. }
function IsNoSpaceLanguage(const ALanguage: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(NO_SPACE_LANGUAGES) do
    if SameText(ALanguage, NO_SPACE_LANGUAGES[I]) then
      Result := True;
end;

{ Seconds of a time in 10 ms units, as text with a '.' decimal point
  (independent of the locale). }
function TicksText(ATicks: Int64): string;
begin
  if ATicks < 0 then
    ATicks := 0;
  Result := Format('%d.%.2d', [ATicks div WHISPER_TICKS_PER_SECOND, ATicks mod WHISPER_TICKS_PER_SECOND]);
end;

{ A probability 0..1 with three decimals and a '.' decimal point. }
function ProbabilityText(AValue: Double): string;
const
  SCALE = 1000;
var
  N: Int64;
begin
  if AValue < 0 then
    AValue := 0;
  N := Round(AValue * SCALE);
  Result := Format('%d.%.3d', [N div SCALE, N mod SCALE]);
end;

{ S as a JSON string literal, quotes included; pure ASCII. }
function JsonString(const S: string): string;
var
  CP: TCodePoints;
  I: Integer;
  C: Cardinal;
  SB: TStringBuilder;
begin
  CP := CodePoints(UTF8String(S));
  SB := TStringBuilder.Create;
  try
    SB.Append('"');
    for I := 0 to High(CP) do
    begin
      C := CP[I];
      if C = Ord('"') then
        SB.Append('\"')
      else if C = Ord('\') then
        SB.Append('\\')
      else if (C >= $20) and (C < $80) then
        SB.Append(Char(Byte(C)))
      else if C < UNICODE_SUPPLEMENTARY then
        SB.Append(Format('\u%.4x', [C]))
      else
      begin
        C := C - UNICODE_SUPPLEMENTARY;
        SB.Append(Format('\u%.4x\u%.4x', [HIGH_SURROGATE + (C shr 10), LOW_SURROGATE + (C and $3FF)]));
      end;
    end;
    SB.Append('"');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ Sorts A ascending (Shell sort: no recursion, fast enough for a book's
  words). }
procedure SortDoubles(var A: TDoubleArray);
var
  Gap, I, J: Integer;
  Tmp: Double;
begin
  Gap := Length(A) div 2;
  while Gap > 0 do
  begin
    for I := Gap to High(A) do
    begin
      Tmp := A[I];
      J := I;
      while (J >= Gap) and (A[J - Gap] > Tmp) do
      begin
        A[J] := A[J - Gap];
        Dec(J, Gap);
      end;
      A[J] := Tmp;
    end;
    Gap := Gap div 2;
  end;
end;

{ The text tokens of every segment with their time spans, and the number of
  text tokens per segment (ACounts). }
function FlattenTokens(const ASegments: TWhisperSegmentArray; ATiming: TWhisperWordTiming;
  out ACounts: TIntegerArray): TFlatTokenArray;
var
  S, K, N: Integer;
  Prev, B, E: Double;
  Tok: TWhisperTokenInfo;
begin
  Result := nil;
  ACounts := nil;
  SetLength(ACounts, Length(ASegments));
  N := 0;
  for S := 0 to High(ASegments) do
    Inc(N, Length(ASegments[S].Tokens));
  SetLength(Result, N);
  N := 0;
  Prev := 0;
  for S := 0 to High(ASegments) do
  begin
    ACounts[S] := 0;
    for K := 0 to High(ASegments[S].Tokens) do
    begin
      Tok := ASegments[S].Tokens[K];
      if Tok.Special then
        Continue;
      if ATiming = wwtDtw then
      begin
        // t_dtw is the token's END; it starts where the previous one ended
        E := Tok.TDtw;
        if E < 0 then
          E := Tok.T1;
        if E < 0 then
          E := ASegments[S].T1;
        B := Prev;
        E := MaxD(E, B);
      end
      else
      begin
        B := Tok.T0;
        if B < 0 then
          B := ASegments[S].T0;
        E := Tok.T1;
        if E < 0 then
          E := ASegments[S].T1;
        E := MaxD(E, B);
      end;
      Result[N].Bytes := Tok.Utf8;
      Result[N].P := Tok.Probability;
      Result[N].T0 := B;
      Result[N].T1 := E;
      Prev := E;
      Inc(N);
      Inc(ACounts[S]);
    end;
  end;
  SetLength(Result, N);
  if N = 0 then
    Result := nil;
end;

{ Splits the tokens into words (OpenAI's split_tokens_on_unicode and
  split_tokens_on_spaces) and gives each its times and probability. }
function SplitWords(const ATokens: TFlatTokenArray; ASpaces: Boolean): TWordWorkArray;
var
  Count, I, First, Tok, K: Integer;
  Piece: UTF8String;
  NewWord: Boolean;
  Sum: Double;
begin
  Result := nil;
  if Length(ATokens) = 0 then
    Exit;
  SetLength(Result, Length(ATokens));
  Count := 0;
  Piece := '';
  First := 0;
  for I := 0 to High(ATokens) do
  begin
    Piece := Piece + ATokens[I].Bytes;
    if not Utf8Complete(Piece) and (I < High(ATokens)) then
      Continue;   // a character continues in the next token
    if ASpaces then
      NewWord := (Count = 0) or StartsWithSpace(Piece) or
        IsIn(CodePoints(StripSpaces(Piece)), ASCII_PUNCTUATION)
    else
      NewWord := True;
    if NewWord then
    begin
      Result[Count].Bytes := Piece;
      Result[Count].TokenCount := I - First + 1;
      Result[Count].Segment := -1;
      Inc(Count);
    end
    else
    begin
      Result[Count - 1].Bytes := Result[Count - 1].Bytes + Piece;
      Inc(Result[Count - 1].TokenCount, I - First + 1);
    end;
    Piece := '';
    First := I + 1;
  end;
  SetLength(Result, Count);
  // times and probability from the tokens (words are contiguous)
  Tok := 0;
  for I := 0 to Count - 1 do
  begin
    Result[I].T0 := ATokens[Tok].T0;
    Result[I].T1 := ATokens[Tok + Result[I].TokenCount - 1].T1;
    Sum := 0;
    for K := Tok to Tok + Result[I].TokenCount - 1 do
      Sum := Sum + ATokens[K].P;
    Result[I].Probability := Sum / Result[I].TokenCount;
    Inc(Tok, Result[I].TokenCount);
  end;
end;

{ The median word duration (at most 0.7 s; 0 when every word has zero
  length), as OpenAI's add_word_timestamps computes it. }
function MedianDuration(const AWords: TWordWorkArray): Double;
var
  D: TDoubleArray;
  I, N: Integer;
begin
  Result := 0;
  D := nil;
  SetLength(D, Length(AWords));
  N := 0;
  for I := 0 to High(AWords) do
    if AWords[I].T1 - AWords[I].T0 <> 0 then
    begin
      D[N] := AWords[I].T1 - AWords[I].T0;
      Inc(N);
    end;
  SetLength(D, N);
  if N = 0 then
    Exit;
  SortDoubles(D);
  if Odd(N) then
    Result := D[N div 2]
  else
    Result := (D[N div 2 - 1] + D[N div 2]) / 2;
  Result := MinD(MAX_MEDIAN_TICKS, Result);
end;

{ OpenAI's merge_punctuations: opening punctuation joins the following
  word, closing punctuation the previous one; the emptied words keep their
  place with no text and no tokens. }
procedure MergePunctuations(var AWords: TWordWorkArray);
var
  I, J: Integer;
begin
  // opening punctuation, from the end
  I := Length(AWords) - 2;
  J := Length(AWords) - 1;
  while I >= 0 do
  begin
    if StartsWithSpace(AWords[I].Bytes) and
      IsPunctuationOf(CodePoints(StripSpaces(AWords[I].Bytes)), PREPEND_PUNCTUATION) then
    begin
      AWords[J].Bytes := AWords[I].Bytes + AWords[J].Bytes;
      Inc(AWords[J].TokenCount, AWords[I].TokenCount);
      AWords[I].Bytes := '';
      AWords[I].TokenCount := 0;
    end
    else
      J := I;
    Dec(I);
  end;
  // closing punctuation, from the start
  I := 0;
  J := 1;
  while J < Length(AWords) do
  begin
    if not EndsWithSpace(AWords[I].Bytes) and IsPunctuationOf(CodePoints(AWords[J].Bytes), APPEND_PUNCTUATION) then
    begin
      AWords[I].Bytes := AWords[I].Bytes + AWords[J].Bytes;
      Inc(AWords[I].TokenCount, AWords[J].TokenCount);
      AWords[J].Bytes := '';
      AWords[J].TokenCount := 0;
    end
    else
      I := J;
    Inc(J);
  end;
end;

function WhisperReadModelHeader(const AFileName: string; out AHeader: TWhisperModelHeader): Boolean;
var
  S: TFileStream;
  Magic: UInt32;
begin
  Result := False;
  FillChar(AHeader, SizeOf(AHeader), 0);
  if (AFileName = '') or not FileExists(AFileName) then
    Exit;
  try
    S := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
    try
      Magic := 0;
      S.ReadBuffer(Magic, SizeOf(Magic));
      if Magic = GGML_FILE_MAGIC then
      begin
        S.ReadBuffer(AHeader, SizeOf(AHeader));
        Result := (AHeader.NTextLayer > 0) and (AHeader.NTextHead > 0) and (AHeader.NTextCtx > 0) and
          (AHeader.NAudioCtx > 0);
      end;
    finally
      S.Free;
    end;
  except
    // unreadable or too short: not a model we can inspect
    Result := False;
  end;
end;

function WhisperDtwPreset(const AHeader: TWhisperModelHeader; const AFileName: string): TWhisperAlignmentHeadsPreset;
var
  En: Boolean;
begin
  En := AHeader.NVocab < MULTILINGUAL_VOCAB;
  Result := wahNTopMost;
  if AHeader.NMels = LARGE_V3_MELS then
  begin
    if (AHeader.NTextState = LARGE_STATE) and (AHeader.NTextLayer = LARGE_LAYERS) then
      Result := wahLargeV3
    else if (AHeader.NTextState = LARGE_STATE) and (AHeader.NTextLayer = TURBO_LAYERS) and
      (AHeader.NAudioLayer = LARGE_LAYERS) then
      Result := wahLargeV3Turbo;
  end
  else if (AHeader.NTextState = TINY_STATE) and (AHeader.NTextLayer = TINY_LAYERS) then
  begin
    if En then
      Result := wahTinyEn
    else
      Result := wahTiny;
  end
  else if (AHeader.NTextState = BASE_STATE) and (AHeader.NTextLayer = BASE_LAYERS) then
  begin
    if En then
      Result := wahBaseEn
    else
      Result := wahBase;
  end
  else if (AHeader.NTextState = SMALL_STATE) and (AHeader.NTextLayer = SMALL_LAYERS) then
  begin
    if En then
      Result := wahSmallEn
    else
      Result := wahSmall;
  end
  else if (AHeader.NTextState = MEDIUM_STATE) and (AHeader.NTextLayer = MEDIUM_LAYERS) then
  begin
    if En then
      Result := wahMediumEn
    else
      Result := wahMedium;
  end
  else if (AHeader.NTextState = LARGE_STATE) and (AHeader.NTextLayer = LARGE_LAYERS) and not En then
  begin
    if Pos('v1', LowerCase(ExtractFileName(AFileName))) > 0 then
      Result := wahLargeV1
    else
      Result := wahLargeV2;
  end;
end;

function WhisperDtwPresetName(APreset: TWhisperAlignmentHeadsPreset): string;
begin
  Result := PRESET_NAMES[APreset];
end;

function WhisperEnableDtw(const AModelFile: string; var AParams: TWhisperContextParams;
  APreset: TWhisperAlignmentHeadsPreset): Boolean;
var
  H: TWhisperModelHeader;
  HaveHeader: Boolean;
  Heads: Int64;
  Mem: Int64;
begin
  Result := False;
  HaveHeader := WhisperReadModelHeader(AModelFile, H);
  if APreset = wahNone then
  begin
    if not HaveHeader then
      Exit;
    APreset := WhisperDtwPreset(H, AModelFile);
  end;
  if APreset = wahNTopMost then
  begin
    if HaveHeader and ((AParams.dtw_n_top <= 0) or (AParams.dtw_n_top > H.NTextLayer)) then
    begin
      AParams.dtw_n_top := H.NTextLayer div 2;
      if AParams.dtw_n_top < 1 then
        AParams.dtw_n_top := 1;
    end;
    if AParams.dtw_n_top <= 0 then
      Exit;   // no header to choose the layers from
  end;
  AParams.dtw_token_timestamps := True;
  AParams.dtw_aheads_preset := APreset;
  AParams.flash_attn := False;   // whisper.cpp turns DTW off with flash attention
  if APreset = wahNTopMost then
    Heads := Int64(AParams.dtw_n_top) * H.NTextHead
  else if APreset = wahCustom then
    Heads := AParams.dtw_aheads_n_heads
  else
    Heads := PRESET_HEADS[APreset];
  if HaveHeader and (Heads > 0) then
  begin
    Mem := DTW_MEM_COPIES * Heads * (H.NTextCtx div 2 + DTW_EXTRA_ROWS) * H.NAudioCtx * SizeOf(Single) +
      DTW_MEM_MARGIN;
    if Mem > Int64(AParams.dtw_mem_size) then
      AParams.dtw_mem_size := NativeUInt(Mem);
  end;
  Result := True;
end;

function WhisperBuildWords(const ASegments: TWhisperSegmentArray; const ALanguage: string;
  ATiming: TWhisperWordTiming): TWhisperWordArray;
var
  Tokens: TFlatTokenArray;
  Counts: TIntegerArray;
  W, Outs: TWordWorkArray;
  Median, MaxDur, LastSpeech, SegStart, SegEnd, Boundary: Double;
  I, S, WI, Saved, NOut, F, L, N: Integer;
  Text: string;
begin
  Result := nil;
  if ATiming = wwtNone then
    Exit;
  Tokens := FlattenTokens(ASegments, ATiming, Counts);
  W := SplitWords(Tokens, not IsNoSpaceLanguage(ALanguage));
  if Length(W) = 0 then
    Exit;
  Median := MedianDuration(W);
  MaxDur := Median * 2;

  // truncate long words at sentence boundaries
  if Median > 0 then
    for I := 1 to High(W) do
      if W[I].T1 - W[I].T0 > MaxDur then
      begin
        if IsIn(CodePoints(W[I].Bytes), SENTENCE_END) then
          W[I].T1 := W[I].T0 + MaxDur
        else if IsIn(CodePoints(W[I - 1].Bytes), SENTENCE_END) then
          W[I].T0 := W[I].T1 - MaxDur;
      end;

  MergePunctuations(W);

  // hand the words to the segments by token count; bound them by the segments
  Outs := nil;
  SetLength(Outs, Length(W));
  NOut := 0;
  WI := 0;
  LastSpeech := 0;
  for S := 0 to High(ASegments) do
  begin
    Saved := 0;
    F := NOut;
    while (WI < Length(W)) and ((Saved < Counts[S]) or (S = High(ASegments))) do
    begin
      if W[WI].Bytes <> '' then
      begin
        Outs[NOut] := W[WI];
        Outs[NOut].Segment := S;
        Inc(NOut);
      end;
      Inc(Saved, W[WI].TokenCount);
      Inc(WI);
    end;
    if NOut = F then
      Continue;
    L := NOut - 1;
    // the first (and second) word after a pause: at most twice the median
    if (Outs[F].T1 - LastSpeech > Median * PAUSE_MEDIANS) and ((Outs[F].T1 - Outs[F].T0 > MaxDur) or
      ((L > F) and (Outs[F + 1].T1 - Outs[F].T0 > MaxDur * 2))) then
    begin
      if (L > F) and (Outs[F + 1].T1 - Outs[F + 1].T0 > MaxDur) then
      begin
        Boundary := MaxD(Outs[F + 1].T1 / 2, Outs[F + 1].T1 - MaxDur);
        Outs[F].T1 := Boundary;
        Outs[F + 1].T0 := Boundary;
      end;
      Outs[F].T0 := MaxD(0, Outs[F].T1 - MaxDur);
    end;
    // prefer the segment's start when the first word is too long
    SegStart := ASegments[S].T0;
    if (SegStart < Outs[F].T1) and (SegStart - SEGMENT_MARGIN_TICKS > Outs[F].T0) then
      Outs[F].T0 := MaxD(0, MinD(Outs[F].T1 - Median, SegStart));
    // prefer the segment's end when the last word is too long
    SegEnd := ASegments[S].T1;
    if (SegEnd > Outs[L].T0) and (SegEnd + SEGMENT_MARGIN_TICKS < Outs[L].T1) then
      Outs[L].T1 := MaxD(Outs[L].T0 + Median, SegEnd)
    else
      SegEnd := Outs[L].T1;
    LastSpeech := SegEnd;
  end;

  SetLength(Result, NOut);
  N := 0;
  for I := 0 to NOut - 1 do
  begin
    Text := Trim(WhisperStr(PAnsiChar(Outs[I].Bytes)));
    if Text = '' then
      Continue;
    Result[N].Text := Text;
    Result[N].T0 := Round(Outs[I].T0);
    Result[N].T1 := Round(Outs[I].T1);
    if Result[N].T1 < Result[N].T0 then
      Result[N].T1 := Result[N].T0;
    Result[N].Probability := Outs[I].Probability;
    Result[N].Segment := Outs[I].Segment;
    Inc(N);
  end;
  SetLength(Result, N);
  if N = 0 then
    Result := nil;
end;

function WhisperWordTimingName(ATiming: TWhisperWordTiming): string;
begin
  Result := TIMING_NAMES[ATiming];
end;

function WhisperWordsToLabels(const AWords: TWhisperWordArray): string;
var
  SB: TStringBuilder;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    for I := 0 to High(AWords) do
      SB.Append(TicksText(AWords[I].T0)).Append(#9).Append(TicksText(AWords[I].T1)).Append(#9)
        .Append(AWords[I].Text).Append(sLineBreak);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function WhisperWordsToJson(const AResult: TWhisperTranscription): string;
var
  SB: TStringBuilder;
  S, WI: Integer;
  First: Boolean;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('{').Append(sLineBreak);
    SB.Append('  "language": ').Append(JsonString(AResult.LanguageCode)).Append(',').Append(sLineBreak);
    SB.Append('  "word_timing": ').Append(JsonString(WhisperWordTimingName(AResult.WordTiming))).Append(',')
      .Append(sLineBreak);
    SB.Append('  "audio_seconds": ').Append(TicksText(Round(AResult.AudioSeconds * WHISPER_TICKS_PER_SECOND)))
      .Append(',').Append(sLineBreak);
    SB.Append('  "segments": [');
    WI := 0;
    for S := 0 to High(AResult.Segments) do
    begin
      if S > 0 then
        SB.Append(',');
      SB.Append(sLineBreak).Append('    {"id": ').Append(IntToStr(S))
        .Append(', "start": ').Append(TicksText(AResult.Segments[S].T0))
        .Append(', "end": ').Append(TicksText(AResult.Segments[S].T1))
        .Append(', "text": ').Append(JsonString(Trim(AResult.Segments[S].Text)))
        .Append(', "words": [');
      while (WI < Length(AResult.Words)) and (AResult.Words[WI].Segment < S) do
        Inc(WI);
      First := True;
      while (WI < Length(AResult.Words)) and (AResult.Words[WI].Segment = S) do
      begin
        if not First then
          SB.Append(',');
        First := False;
        SB.Append(sLineBreak).Append('      {"word": ').Append(JsonString(AResult.Words[WI].Text))
          .Append(', "start": ').Append(TicksText(AResult.Words[WI].T0))
          .Append(', "end": ').Append(TicksText(AResult.Words[WI].T1))
          .Append(', "probability": ').Append(ProbabilityText(AResult.Words[WI].Probability)).Append('}');
        Inc(WI);
      end;
      if not First then
        SB.Append(sLineBreak).Append('    ');
      SB.Append(']}');
    end;
    SB.Append(sLineBreak).Append('  ]').Append(sLineBreak).Append('}').Append(sLineBreak);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

end.
