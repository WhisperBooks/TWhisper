(* @abstract(Types of the whisper.cpp binding: constants, enums, the C records
  of whisper.h and the Pascal result records.)

  The C records keep the C field names, so whisper.h and its comments map
  one to one. Their layout matches whisper.h on every supported platform
  (see Whisper.inc and tools/verify_layout.py). Two deviations, both
  layout-neutral:

  @unorderedList(
    @item(Anonymous and nested structs are flattened: C
      @code(params.greedy.best_of) is @code(greedy_best_of),
      @code(params.vad_params.threshold) is @code(vad_params_threshold),
      @code(cparams.dtw_aheads.n_heads) is @code(dtw_aheads_n_heads). Every
      member of those structs has 4-byte (or pointer) alignment, so the
      offsets are the same; flattening avoids the compilers' differing rules
      for aligning a record inside a record.)
    @item(C @code(type) (a Pascal keyword) is @code(type_).)
  )

  Records seen by C contain no managed fields (string, dynamic array,
  interface). The Pascal result records (@link(TWhisperSegment), ...) are
  never passed to C. *)
unit Whisper.Types;

{$I Whisper.inc}

interface

uses
  SysUtils, Math;

const
  { Sample rate whisper.cpp works at; audio must be mono float at this rate. }
  WHISPER_SAMPLE_RATE = 16000;
  { FFT size of the mel spectrogram. }
  WHISPER_N_FFT = 400;
  { Hop length of the mel spectrogram. }
  WHISPER_HOP_LENGTH = 160;
  { Length in seconds of the audio window the encoder sees at once. }
  WHISPER_CHUNK_SIZE = 30;
  { whisper.cpp version whose whisper.h this binding was checked against
    (tools/verify_layout.py). Other versions work while the checked records
    are unchanged; @code(TWhisperLib.CheckLayout) tells. }
  WHISPER_BINDING_VERSION = '1.9.5';
  { Value of @code(TWhisperParams.Language) that asks whisper.cpp to detect
    the spoken language. }
  WHISPER_LANGUAGE_AUTO = 'auto';
  { Time stamps of whisper.cpp count in units of 10 ms: this many per second. }
  WHISPER_TICKS_PER_SECOND = 100;
  { Device name that selects the CPU (no GPU) in @code(TCustomWhisper.Device)
    and @code(TWhisperLib.ContextParamsFor); the same name ggml gives its
    CPU device. }
  WHISPER_DEVICE_CPU = 'CPU';

type
  { Raised for every failure of the binding. }
  EWhisperError = class(Exception);

  { Opaque C struct behind @link(PWhisperContext). }
  TWhisperContextOpaque = record
  end;
  { struct whisper_context * - a loaded model. }
  PWhisperContext = ^TWhisperContextOpaque;

  { Opaque C struct behind @link(PWhisperState). }
  TWhisperStateOpaque = record
  end;
  { struct whisper_state * - the working state of one transcription. }
  PWhisperState = ^TWhisperStateOpaque;

  { whisper_token (int32_t). }
  TWhisperToken = Int32;
  { Pointer to @link(TWhisperToken). }
  PWhisperToken = ^TWhisperToken;

  { enum whisper_sampling_strategy. }
  TWhisperSamplingStrategy = (
    { WHISPER_SAMPLING_GREEDY, like OpenAI's GreedyDecoder. }
    wssGreedy,
    { WHISPER_SAMPLING_BEAM_SEARCH, like OpenAI's BeamSearchDecoder. }
    wssBeamSearch
  );

  { enum whisper_alignment_heads_preset: attention heads used for DTW token
    time stamps; pick the one of the model in use. }
  TWhisperAlignmentHeadsPreset = (
    { WHISPER_AHEADS_NONE: DTW off. }
    wahNone,
    { WHISPER_AHEADS_N_TOP_MOST: all heads of the dtw_n_top top text layers. }
    wahNTopMost,
    { WHISPER_AHEADS_CUSTOM: the heads in dtw_aheads. }
    wahCustom,
    { WHISPER_AHEADS_TINY_EN. }
    wahTinyEn,
    { WHISPER_AHEADS_TINY. }
    wahTiny,
    { WHISPER_AHEADS_BASE_EN. }
    wahBaseEn,
    { WHISPER_AHEADS_BASE. }
    wahBase,
    { WHISPER_AHEADS_SMALL_EN. }
    wahSmallEn,
    { WHISPER_AHEADS_SMALL. }
    wahSmall,
    { WHISPER_AHEADS_MEDIUM_EN. }
    wahMediumEn,
    { WHISPER_AHEADS_MEDIUM. }
    wahMedium,
    { WHISPER_AHEADS_LARGE_V1. }
    wahLargeV1,
    { WHISPER_AHEADS_LARGE_V2. }
    wahLargeV2,
    { WHISPER_AHEADS_LARGE_V3. }
    wahLargeV3,
    { WHISPER_AHEADS_LARGE_V3_TURBO. }
    wahLargeV3Turbo
  );

  { enum whisper_gretype: grammar element types. }
  TWhisperGreType = (
    { WHISPER_GRETYPE_END: end of rule definition. }
    wgtEnd,
    { WHISPER_GRETYPE_ALT: start of alternate definition for rule. }
    wgtAlt,
    { WHISPER_GRETYPE_RULE_REF: non-terminal element, reference to rule. }
    wgtRuleRef,
    { WHISPER_GRETYPE_CHAR: terminal element, character (code point). }
    wgtChar,
    { WHISPER_GRETYPE_CHAR_NOT: inverse char(s) ([^a], [^a-b] [^abc]). }
    wgtCharNot,
    { WHISPER_GRETYPE_CHAR_RNG_UPPER: upper end of a character range. }
    wgtCharRngUpper,
    { WHISPER_GRETYPE_CHAR_ALT: another character of a character set. }
    wgtCharAlt
  );

  { enum ggml_log_level (ggml.h): level of a log message. }
  TWhisperLogLevel = (
    { GGML_LOG_LEVEL_NONE. }
    wllNone,
    { GGML_LOG_LEVEL_DEBUG. }
    wllDebug,
    { GGML_LOG_LEVEL_INFO. }
    wllInfo,
    { GGML_LOG_LEVEL_WARN. }
    wllWarn,
    { GGML_LOG_LEVEL_ERROR. }
    wllError,
    { GGML_LOG_LEVEL_CONT: continues the previous message. }
    wllCont
  );

  { struct whisper_ahead: one attention head (custom DTW heads). }
  TWhisperAhead = record
    { Text layer of the head. }
    n_text_layer: Int32;
    { Head within the layer. }
    n_head: Int32;
  end;
  { Pointer to @link(TWhisperAhead). }
  PWhisperAhead = ^TWhisperAhead;

  { struct whisper_context_params: how a model is loaded. }
  TWhisperContextParams = record
    { Use the GPU backend (if the library was built with one). }
    use_gpu: Boolean;
    { Use flash attention. }
    flash_attn: Boolean;
    { GPU device index (CUDA, Vulkan, ...). }
    gpu_device: Int32;
    { [EXPERIMENTAL] token-level time stamps with DTW. }
    dtw_token_timestamps: Boolean;
    { Alignment heads used for DTW. }
    dtw_aheads_preset: TWhisperAlignmentHeadsPreset;
    { Number of top text layers for @link(wahNTopMost). }
    dtw_n_top: Int32;
    { dtw_aheads.n_heads: number of custom heads (@link(wahCustom)). }
    dtw_aheads_n_heads: NativeUInt;
    { dtw_aheads.heads: the custom heads. }
    dtw_aheads_heads: PWhisperAhead;
    { DTW working memory in bytes (deprecated upstream). }
    dtw_mem_size: NativeUInt;
  end;
  { Pointer to @link(TWhisperContextParams). }
  PWhisperContextParams = ^TWhisperContextParams;

  { struct whisper_token_data: one decoded token. Time stamps in 10 ms units. }
  TWhisperTokenData = record
    { Token id. }
    id: TWhisperToken;
    { Forced time stamp token id. }
    tid: TWhisperToken;
    { Probability of the token. }
    p: Single;
    { Log probability of the token. }
    plog: Single;
    { Probability of the time stamp token. }
    pt: Single;
    { Sum of the probabilities of all time stamp tokens. }
    ptsum: Single;
    { Start of the token (token-level time stamps only, else -1). }
    t0: Int64;
    { End of the token. }
    t1: Int64;
    { DTW time stamp of the token (DTW only, else -1). }
    t_dtw: Int64;
    { Voice length of the token. }
    vlen: Single;
  end;
  { Pointer to @link(TWhisperTokenData). }
  PWhisperTokenData = ^TWhisperTokenData;

  { struct whisper_grammar_element. }
  TWhisperGrammarElement = record
    { Element type. }
    type_: TWhisperGreType;
    { Unicode code point or rule id. }
    value: UInt32;
  end;
  { Pointer to @link(TWhisperGrammarElement). }
  PWhisperGrammarElement = ^TWhisperGrammarElement;
  { Pointer to @link(PWhisperGrammarElement): the rule array of
    @link(TWhisperFullParams.grammar_rules). }
  PPWhisperGrammarElement = ^PWhisperGrammarElement;

  { struct whisper_vad_params: voice activity detection settings (the same
    fields are flattened into @link(TWhisperFullParams) as vad_params_*). }
  TWhisperVadParams = record
    { Probability threshold to consider as speech. }
    threshold: Single;
    { Minimum duration of a valid speech segment, ms. }
    min_speech_duration_ms: Int32;
    { Minimum silence that ends speech, ms. }
    min_silence_duration_ms: Int32;
    { Maximum duration of a speech segment before forcing a new one, s. }
    max_speech_duration_s: Single;
    { Padding added before and after speech segments, ms. }
    speech_pad_ms: Int32;
    { Overlap in seconds when copying audio samples from a speech segment. }
    samples_overlap: Single;
  end;
  { Pointer to @link(TWhisperVadParams). }
  PWhisperVadParams = ^TWhisperVadParams;

  { struct whisper_timings: average times of the last run, ms. }
  TWhisperTimings = record
    { Sampling time per token. }
    sample_ms: Single;
    { Encoder time per run. }
    encode_ms: Single;
    { Decoder time per token. }
    decode_ms: Single;
    { Batch decoder time per token. }
    batchd_ms: Single;
    { Prompt processing time per token. }
    prompt_ms: Single;
  end;
  { Pointer to @link(TWhisperTimings). }
  PWhisperTimings = ^TWhisperTimings;

  { whisper_new_segment_callback: n_new segments were added. Runs on the
    thread that called whisper_full. }
  TWhisperNewSegmentCallback = procedure(ctx: PWhisperContext; state: PWhisperState;
    n_new: Int32; user_data: Pointer); cdecl;
  { whisper_progress_callback: progress 0..100. }
  TWhisperProgressCallback = procedure(ctx: PWhisperContext; state: PWhisperState;
    progress: Int32; user_data: Pointer); cdecl;
  { whisper_encoder_begin_callback: return @false to stop before the next
    encoder run (whisper_full then returns the segments so far). }
  TWhisperEncoderBeginCallback = function(ctx: PWhisperContext; state: PWhisperState;
    user_data: Pointer): Boolean; cdecl;
  { ggml_abort_callback: return @true to abort the computation in progress. }
  TGgmlAbortCallback = function(data: Pointer): Boolean; cdecl;
  { whisper_logits_filter_callback: may change the logits before sampling. }
  TWhisperLogitsFilterCallback = procedure(ctx: PWhisperContext; state: PWhisperState;
    tokens: PWhisperTokenData; n_tokens: Int32; logits: PSingle; user_data: Pointer); cdecl;
  { ggml_log_callback: one log message (or a piece of one, see
    @link(wllCont)). May run on any thread. }
  TGgmlLogCallback = procedure(level: TWhisperLogLevel; text: PAnsiChar; user_data: Pointer); cdecl;

  { struct whisper_full_params: everything whisper_full does. Get it from
    @code(TWhisperLib.DefaultFullParams) (never fill it from zero) or use the
    @code(TWhisperParams) class, which also keeps the strings alive. }
  TWhisperFullParams = record
    { Decoding strategy. }
    strategy: TWhisperSamplingStrategy;
    { Number of CPU threads. }
    n_threads: Int32;
    { Max tokens to use from past text as prompt for the decoder. }
    n_max_text_ctx: Int32;
    { Start offset in ms. }
    offset_ms: Int32;
    { Audio duration to process in ms (0 = all). }
    duration_ms: Int32;
    { Translate to English. }
    translate: Boolean;
    { Do not use past transcription (if any) as initial prompt for the decoder. }
    no_context: Boolean;
    { Do not generate time stamps. }
    no_timestamps: Boolean;
    { Force single segment output (useful for streaming). }
    single_segment: Boolean;
    { Print special tokens (stdout). }
    print_special: Boolean;
    { Print progress information (stdout). }
    print_progress: Boolean;
    { Print results from within whisper.cpp (stdout). }
    print_realtime: Boolean;
    { Print time stamps of each segment when printing realtime. }
    print_timestamps: Boolean;
    { [EXPERIMENTAL] token-level time stamps. }
    token_timestamps: Boolean;
    { Time stamp token probability threshold (~0.01). }
    thold_pt: Single;
    { Time stamp token sum probability threshold (~0.01). }
    thold_ptsum: Single;
    { Max segment length in characters (0 = no limit). }
    max_len: Int32;
    { Split on word rather than on token (with max_len). }
    split_on_word: Boolean;
    { Max tokens per segment (0 = no limit). }
    max_tokens: Int32;
    { Extra debug output (e.g. dump of the log mel). }
    debug_mode: Boolean;
    { Overwrite the audio context size (0 = model default). }
    audio_ctx: Int32;
    { [TDRZ] tinydiarize speaker turn detection (needs a tdrz model). }
    tdrz_enable: Boolean;
    { Regular expression of tokens to suppress (UTF-8, may be nil). }
    suppress_regex: PAnsiChar;
    { Initial prompt (UTF-8, may be nil). }
    initial_prompt: PAnsiChar;
    { Prepend initial_prompt to every decode window. }
    carry_initial_prompt: Boolean;
    { Prompt tokens (used instead of initial_prompt when set). }
    prompt_tokens: PWhisperToken;
    { Number of prompt_tokens. }
    prompt_n_tokens: Int32;
    { Language code ("en", ...); nil, "" or "auto" = detect. }
    language: PAnsiChar;
    { Only detect the language, do not transcribe. }
    detect_language: Boolean;
    { Suppress blank outputs at the start of sampling. }
    suppress_blank: Boolean;
    { Suppress non-speech tokens. }
    suppress_nst: Boolean;
    { Initial decoding temperature. }
    temperature: Single;
    { Maximum initial time stamp. }
    max_initial_ts: Single;
    { Length penalty. }
    length_penalty: Single;
    { Temperature increment of the fallback. }
    temperature_inc: Single;
    { Entropy threshold of the fallback (like OpenAI's compression ratio). }
    entropy_thold: Single;
    { Average log probability threshold of the fallback. }
    logprob_thold: Single;
    { No-speech probability threshold. }
    no_speech_thold: Single;
    { greedy.best_of: candidates sampled with non-zero temperature. }
    greedy_best_of: Int32;
    { beam_search.beam_size: beams. }
    beam_search_beam_size: Int32;
    { beam_search.patience (not implemented upstream). }
    beam_search_patience: Single;
    { Called for every new segment. }
    new_segment_callback: TWhisperNewSegmentCallback;
    { user_data of new_segment_callback. }
    new_segment_callback_user_data: Pointer;
    { Called with the progress. }
    progress_callback: TWhisperProgressCallback;
    { user_data of progress_callback. }
    progress_callback_user_data: Pointer;
    { Called before every encoder run. }
    encoder_begin_callback: TWhisperEncoderBeginCallback;
    { user_data of encoder_begin_callback. }
    encoder_begin_callback_user_data: Pointer;
    { Polled during the computation; @true aborts. }
    abort_callback: TGgmlAbortCallback;
    { data of abort_callback. }
    abort_callback_user_data: Pointer;
    { Called to filter the logits before sampling. }
    logits_filter_callback: TWhisperLogitsFilterCallback;
    { user_data of logits_filter_callback. }
    logits_filter_callback_user_data: Pointer;
    { Grammar rules (array of rule pointers). }
    grammar_rules: PPWhisperGrammarElement;
    { Number of grammar_rules. }
    n_grammar_rules: NativeUInt;
    { Index of the start rule. }
    i_start_rule: NativeUInt;
    { Penalty of non-grammar tokens. }
    grammar_penalty: Single;
    { Enable voice activity detection (needs vad_model_path). }
    vad: Boolean;
    { Path of the VAD model (UTF-8). }
    vad_model_path: PAnsiChar;
    { vad_params.threshold. }
    vad_params_threshold: Single;
    { vad_params.min_speech_duration_ms. }
    vad_params_min_speech_duration_ms: Int32;
    { vad_params.min_silence_duration_ms. }
    vad_params_min_silence_duration_ms: Int32;
    { vad_params.max_speech_duration_s. }
    vad_params_max_speech_duration_s: Single;
    { vad_params.speech_pad_ms. }
    vad_params_speech_pad_ms: Int32;
    { vad_params.samples_overlap. }
    vad_params_samples_overlap: Single;
  end;
  { Pointer to @link(TWhisperFullParams). }
  PWhisperFullParams = ^TWhisperFullParams;

  { Audio for whisper.cpp: mono, @link(WHISPER_SAMPLE_RATE) Hz, -1..1. }
  TWhisperSamples = array of Single;

  { One token of a segment (Pascal side, never passed to C). }
  TWhisperTokenInfo = record
    { Token id. }
    Id: TWhisperToken;
    { Token text. A token can hold part of a multi-byte UTF-8 character;
      such a piece decodes to a replacement character - use the segment
      text for display. }
    Text: string;
    { Probability 0..1. }
    Probability: Single;
    { Start, 10 ms units (-1 without token time stamps). }
    T0: Int64;
    { End, 10 ms units (-1 without token time stamps). }
    T1: Int64;
    { DTW time stamp, 10 ms units (-1 without DTW). }
    TDtw: Int64;
    { @true for special tokens (time stamps, [_BEG_], ...). }
    Special: Boolean;
  end;
  { Tokens of a segment. }
  TWhisperTokenInfoArray = array of TWhisperTokenInfo;

  { One transcribed segment (Pascal side, never passed to C). }
  TWhisperSegment = record
    { Index of the segment in the run, from 0. }
    Index: Integer;
    { Start, 10 ms units. }
    T0: Int64;
    { End, 10 ms units. }
    T1: Int64;
    { Text (decoded from UTF-8). }
    Text: string;
    { Probability that the segment holds no speech. }
    NoSpeechProb: Single;
    { [TDRZ] the next segment is spoken by someone else. }
    SpeakerTurnNext: Boolean;
    { Tokens; filled only when tokens were asked for. }
    Tokens: TWhisperTokenInfoArray;
  end;
  { Segments of a run. }
  TWhisperSegmentArray = array of TWhisperSegment;

  { Summary of a finished transcription. }
  TWhisperTranscription = record
    { Every segment, in order. }
    Segments: TWhisperSegmentArray;
    { Code of the spoken (or forced) language, e.g. 'en'. }
    LanguageCode: string;
    { English name of that language. }
    LanguageName: string;
    { Return value of whisper_full: 0 = success. }
    ResultCode: Integer;
    { @true when the run was cancelled (the segments so far are kept). }
    Cancelled: Boolean;
    { Length of the audio, seconds. }
    AudioSeconds: Double;
    { Wall-clock time of the run, ms. }
    ElapsedMs: Int64;
    { Error message when the run failed (ResultCode <> 0 or an exception). }
    ErrorMessage: string;
  end;

  { Opaque C struct behind @link(PGgmlBackendDev). }
  TGgmlBackendDevOpaque = record
  end;
  { ggml_backend_dev_t - a compute device (CPU, a GPU through CUDA, Vulkan,
    HIP, ...). Owned by ggml; valid while the library is loaded. }
  PGgmlBackendDev = ^TGgmlBackendDevOpaque;

  { Opaque C struct behind @link(PGgmlBackendReg). }
  TGgmlBackendRegOpaque = record
  end;
  { ggml_backend_reg_t - a backend (CPU, CUDA, Vulkan, HIP, ...). }
  PGgmlBackendReg = ^TGgmlBackendRegOpaque;

  { enum ggml_backend_dev_type. }
  TWhisperDeviceType = (
    { GGML_BACKEND_DEVICE_TYPE_CPU: CPU, system memory. }
    wdtCPU,
    { GGML_BACKEND_DEVICE_TYPE_GPU: GPU with dedicated memory. }
    wdtGPU,
    { GGML_BACKEND_DEVICE_TYPE_IGPU: integrated GPU using host memory. }
    wdtIGPU,
    { GGML_BACKEND_DEVICE_TYPE_ACCEL: accelerator used together with the CPU
      (BLAS, AMX); whisper.cpp always adds these itself. }
    wdtAccel,
    { GGML_BACKEND_DEVICE_TYPE_META: wrapper of several devices (tensor
      parallelism); not used by whisper.cpp. }
    wdtMeta
  );

  { One compute device of the loaded backends (Pascal side). }
  TWhisperDevice = record
    { Index in ggml's device registry (ggml_backend_dev_get). }
    Index: Integer;
    { Device name, unique per process: 'CPU', 'CUDA0', 'Vulkan1', 'ROCm0',
      ... (the name the backend gives it). Use it for
      @code(TCustomWhisper.Device). }
    Name: string;
    { Human-readable description, e.g. the GPU model. }
    Description: string;
    { Backend that provides the device: 'CPU', 'CUDA', 'Vulkan', 'ROCm' /
      'HIP', ... }
    Backend: string;
    { Kind of device. }
    DeviceType: TWhisperDeviceType;
    { Free memory in bytes when listed (0 if the backend does not say). }
    MemoryFree: UInt64;
    { Total memory in bytes (0 if the backend does not say). }
    MemoryTotal: UInt64;
    { Value of whisper_context_params.gpu_device that selects this device
      (its position among GPU and IGPU devices); -1 for every other type. }
    GpuIndex: Integer;
  end;
  { Devices of the loaded backends. }
  TWhisperDeviceArray = array of TWhisperDevice;

  { Result of timing one model on one device (@code(TWhisperBenchmark)). }
  TWhisperBenchmarkResult = record
    { The model file. }
    ModelFile: string;
    { The device. }
    Device: TWhisperDevice;
    { @true when the model loaded and both runs succeeded on it. }
    Ok: Boolean;
    { Why it failed (Ok = @false). }
    ErrorMessage: string;
    { Time to load the model onto the device, ms. }
    LoadMs: Int64;
    { First (warm-up) run, ms: includes one-time costs such as shader /
      kernel compilation. }
    WarmupMs: Int64;
    { Timed run, ms: the figure the choice is based on. }
    RunMs: Int64;
    { Audio of the timed run, seconds. }
    AudioSeconds: Double;
    { Audio seconds per wall-clock second of the timed run (higher is faster). }
    Speed: Double;
    { Text of the timed run (to see that the device computes correctly). }
    Text: string;
  end;
  { Results of a benchmark, one per device. }
  TWhisperBenchmarkArray = array of TWhisperBenchmarkResult;

  { FPU exception mask type of the compiler's Math unit. }
  TWhisperFPUMask = {$ifdef FPC}TFPUExceptionMask{$else}TArithmeticExceptionMask{$endif};

const
  { Every floating-point exception: masked while C code runs (ggml computes
    with NaN / infinity on purpose; Delphi unmasks several exceptions by
    default and would raise them inside the library). }
  WHISPER_FPU_MASK_ALL: TWhisperFPUMask = [exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision];

{ Masks every floating-point exception on the calling thread.
  @returns(The previous mask, for @link(WhisperRestoreFPU).) }
function WhisperMaskFPU: TWhisperFPUMask;

{ Restores a mask saved by @link(WhisperMaskFPU). }
procedure WhisperRestoreFPU(const AMask: TWhisperFPUMask);

{ Converts a UTF-8 C string to a string (@nil gives ''). }
function WhisperStr(P: PAnsiChar): string;

{ Converts a whisper.cpp time (10 ms units) to seconds. }
function WhisperTimeToSeconds(ATime: Int64): Double;

{ Formats a whisper.cpp time (10 ms units) as hh:mm:ss.zzz.
  @param(ATime Time in 10 ms units.)
  @param(ACommaDecimal Use ',' before the milliseconds (SubRip) instead of '.'.) }
function WhisperTimeToStr(ATime: Int64; ACommaDecimal: Boolean = False): string;

implementation

function WhisperMaskFPU: TWhisperFPUMask;
begin
  Result := GetExceptionMask;
  SetExceptionMask(WHISPER_FPU_MASK_ALL);
end;

procedure WhisperRestoreFPU(const AMask: TWhisperFPUMask);
begin
  SetExceptionMask(AMask);
end;

function WhisperStr(P: PAnsiChar): string;
begin
  if P = nil then
    Result := ''
  else
    Result := string(UTF8String(P));
end;

function WhisperTimeToSeconds(ATime: Int64): Double;
begin
  Result := ATime / WHISPER_TICKS_PER_SECOND;
end;

function WhisperTimeToStr(ATime: Int64; ACommaDecimal: Boolean): string;
const
  MS_PER_TICK = 1000 div WHISPER_TICKS_PER_SECOND;
var
  Ms: Int64;
  Sep: Char;
begin
  if ATime < 0 then
    ATime := 0;
  Ms := ATime * MS_PER_TICK;
  if ACommaDecimal then
    Sep := ','
  else
    Sep := '.';
  Result := Format('%.2d:%.2d:%.2d%s%.3d', [Ms div 3600000, (Ms div 60000) mod 60,
    (Ms div 1000) mod 60, Sep, Ms mod 1000]);
end;

end.
