(* @abstract(Dynamic binding of the whisper.cpp C API: @link(TWhisperLib) loads
  the library at run time and holds every export in @link(TWhisperFlat).)

  Nothing is linked statically: the library (whisper.dll, libwhisper.so,
  libwhisper.dylib) and the ggml libraries it needs are loaded with
  @code(TWhisperDynLib) when @link(TWhisperLib.Load) is called, and every
  export is bound by name. Required exports (the ones the classes in
  Whisper.Core need) raise @link(EWhisperDynLibError) when missing; all others are
  optional: check them with @code(Assigned(Lib.Flat.xxx)) before calling.
  @link(TWhisperLib.MissingSymbols) lists the ones the library lacks.

  @bold(Library search.) With no explicit path, the folder of the
  executable is tried first (on macOS also the bundle's Contents/Frameworks),
  then the operating system's search path (on Windows: PATH). A library found
  through the search path is located afterwards (GetModuleFileNameW /
  dladdr) and its folder used for the backends, as ggml itself only looks in
  the executable's folder and the current directory. Before whisper itself, the ggml
  libraries found in the same folder (ggml-base, the backends, ggml) are
  loaded by full path: the dependencies of whisper are then already in the
  process, wherever its folder is (Linux / Android dlopen does not look next
  to a library, and Windows looks next to the executable, not next to a
  whisper.dll loaded from another folder).

  @bold(Backends.) whisper.cpp does not load ggml's backends itself. After
  loading the libraries, @link(TWhisperLib.Load) calls
  ggml_backend_load_all_from_path on the library folder: with a
  GGML_BACKEND_DL build that loads every backend DLL found there (the best
  CPU variant, CUDA, Vulkan, HIP, ...), skipping any whose runtime is
  missing; with a build that links its backends in, it finds nothing extra
  and changes nothing. On Windows the library folder is put on the DLL
  search path while that runs, so a backend's own runtime DLLs
  (cudart64_*.dll, hipblas.dll, ...) are found next to it.
  @link(TWhisperLib.Devices) lists the result; a device is chosen per model
  with @link(TWhisperLib.ContextParamsFor).

  @bold(C structs passed or returned by value.) whisper_full and
  whisper_init_from_file_with_params take a struct by value;
  whisper_full_get_token_data returns one. Their ABI differs per platform
  (Whisper.inc: WHISPER_PARAMS_BY_POINTER, WHISPER_SRET_AS_PARAM); call
  them through @link(TWhisperLib.Full), @link(TWhisperLib.InitFromFile) and
  @link(TWhisperLib.GetTokenData), which hide that.

  @bold(Floating point.) Delphi unmasks floating-point exceptions that
  ggml relies on being masked (it computes with NaN / infinity). The
  computing calls of TWhisperLib mask them on the calling thread for the
  duration of the call (@code(WhisperMaskFPU)); do the same around any
  other export you call that computes.

  Not bound on purpose: the deprecated init functions, the model-loader
  variants (struct of callbacks), whisper_full_default_params /
  whisper_context_default_params (struct returns; the _by_ref variants are
  used) and the stand-alone VAD API (small structs by value: VAD is
  available through @code(TWhisperFullParams.vad)).

  @longCode(#
  var
    Lib: TWhisperLib;
  begin
    Lib := TWhisperLib.Load;           // raises EWhisperError when missing
    WriteLn(Lib.Version, ' ', Lib.SystemInfo);
  end;
  #) *)
unit Whisper.API;

{$I Whisper.inc}

interface

uses
  SysUtils, Classes, SyncObjs, StrUtils,
  Whisper.Types, Whisper.DynLib;

type
  {$ifdef WHISPER_PARAMS_BY_POINTER}
  { whisper_init_from_file_with_params (and _no_state): the params struct is
    passed as a pointer to a copy (this platform's ABI). }
  TWhisperInitFromFileFunc = function(path_model: PAnsiChar;
    params: PWhisperContextParams): PWhisperContext; cdecl;
  { whisper_init_from_buffer_with_params (and _no_state). }
  TWhisperInitFromBufferFunc = function(buffer: Pointer; buffer_size: NativeUInt;
    params: PWhisperContextParams): PWhisperContext; cdecl;
  { whisper_full: the params struct is passed as a pointer to a copy, which
    the library may change. }
  TWhisperFullFunc = function(ctx: PWhisperContext; params: PWhisperFullParams;
    samples: PSingle; n_samples: Int32): Int32; cdecl;
  { whisper_full_with_state. }
  TWhisperFullWithStateFunc = function(ctx: PWhisperContext; state: PWhisperState;
    params: PWhisperFullParams; samples: PSingle; n_samples: Int32): Int32; cdecl;
  { whisper_full_parallel. }
  TWhisperFullParallelFunc = function(ctx: PWhisperContext; params: PWhisperFullParams;
    samples: PSingle; n_samples: Int32; n_processors: Int32): Int32; cdecl;
  {$else}
  { whisper_init_from_file_with_params (and _no_state): the params struct is
    passed by value (copied onto the stack / into registers). }
  TWhisperInitFromFileFunc = function(path_model: PAnsiChar;
    params: TWhisperContextParams): PWhisperContext; cdecl;
  { whisper_init_from_buffer_with_params (and _no_state). }
  TWhisperInitFromBufferFunc = function(buffer: Pointer; buffer_size: NativeUInt;
    params: TWhisperContextParams): PWhisperContext; cdecl;
  { whisper_full: the params struct is passed by value. }
  TWhisperFullFunc = function(ctx: PWhisperContext; params: TWhisperFullParams;
    samples: PSingle; n_samples: Int32): Int32; cdecl;
  { whisper_full_with_state. }
  TWhisperFullWithStateFunc = function(ctx: PWhisperContext; state: PWhisperState;
    params: TWhisperFullParams; samples: PSingle; n_samples: Int32): Int32; cdecl;
  { whisper_full_parallel. }
  TWhisperFullParallelFunc = function(ctx: PWhisperContext; params: TWhisperFullParams;
    samples: PSingle; n_samples: Int32; n_processors: Int32): Int32; cdecl;
  {$endif}

  {$ifdef WHISPER_SRET_AS_PARAM}
  { whisper_full_get_token_data: the returned struct is written through a
    hidden first pointer parameter, declared explicitly here. }
  TWhisperGetTokenDataFunc = procedure(out_result: PWhisperTokenData; ctx: PWhisperContext;
    i_segment, i_token: Int32); cdecl;
  { whisper_full_get_token_data_from_state. }
  TWhisperGetTokenDataFromStateFunc = procedure(out_result: PWhisperTokenData;
    state: PWhisperState; i_segment, i_token: Int32); cdecl;
  {$else}
  { whisper_full_get_token_data: the compiler's record return (X8 on ARM64). }
  TWhisperGetTokenDataFunc = function(ctx: PWhisperContext;
    i_segment, i_token: Int32): TWhisperTokenData; cdecl;
  { whisper_full_get_token_data_from_state. }
  TWhisperGetTokenDataFromStateFunc = function(state: PWhisperState;
    i_segment, i_token: Int32): TWhisperTokenData; cdecl;
  {$endif}

  { Every bound export of whisper.cpp, named as in whisper.h. Fields of
    optional exports are @nil when the library lacks them. Parameters are
    as in C: strings are UTF-8 PAnsiChar, times are 10 ms units. }
  TWhisperFlat = record
    { const char * whisper_version(void). Required. }
    whisper_version: function: PAnsiChar; cdecl;
    { const char * whisper_print_system_info(void): CPU / GPU features. }
    whisper_print_system_info: function: PAnsiChar; cdecl;

    { Model loading. Required. Use @link(TWhisperLib.InitFromFile). }
    whisper_init_from_file_with_params: TWhisperInitFromFileFunc;
    { Model loading without a default state. }
    whisper_init_from_file_with_params_no_state: TWhisperInitFromFileFunc;
    { Model loading from memory. Use @link(TWhisperLib.InitFromBuffer). }
    whisper_init_from_buffer_with_params: TWhisperInitFromBufferFunc;
    { Model loading from memory without a default state. }
    whisper_init_from_buffer_with_params_no_state: TWhisperInitFromBufferFunc;
    { Creates a state for whisper_full_with_state. }
    whisper_init_state: function(ctx: PWhisperContext): PWhisperState; cdecl;
    { Loads the OpenVINO encoder (OpenVINO builds only). }
    whisper_ctx_init_openvino_encoder: function(ctx: PWhisperContext;
      model_path, device, cache_dir: PAnsiChar): Int32; cdecl;
    { Frees a model. Required. }
    whisper_free: procedure(ctx: PWhisperContext); cdecl;
    { Frees a state. }
    whisper_free_state: procedure(state: PWhisperState); cdecl;
    { Frees params from whisper_full_default_params_by_ref. Required. }
    whisper_free_params: procedure(params: PWhisperFullParams); cdecl;
    { Frees params from whisper_context_default_params_by_ref. Required. }
    whisper_free_context_params: procedure(params: PWhisperContextParams); cdecl;
    { Default context params (heap copy; free it). Required. }
    whisper_context_default_params_by_ref: function: PWhisperContextParams; cdecl;
    { Default full params (heap copy; free it). Required. }
    whisper_full_default_params_by_ref: function(strategy: TWhisperSamplingStrategy): PWhisperFullParams; cdecl;

    { Computes the log mel spectrogram of the samples. }
    whisper_pcm_to_mel: function(ctx: PWhisperContext; samples: PSingle;
      n_samples, n_threads: Int32): Int32; cdecl;
    { Runs the encoder on the mel spectrogram from offset. }
    whisper_encode: function(ctx: PWhisperContext; offset, n_threads: Int32): Int32; cdecl;
    { Runs the decoder on tokens. }
    whisper_decode: function(ctx: PWhisperContext; tokens: PWhisperToken;
      n_tokens, n_past, n_threads: Int32): Int32; cdecl;
    { Converts text to tokens; returns the count, negative = -needed. }
    whisper_tokenize: function(ctx: PWhisperContext; text: PAnsiChar;
      tokens: PWhisperToken; n_max_tokens: Int32): Int32; cdecl;
    { Number of tokens text converts to. }
    whisper_token_count: function(ctx: PWhisperContext; text: PAnsiChar): Int32; cdecl;

    { Largest language id. }
    whisper_lang_max_id: function: Int32; cdecl;
    { Id of a language code ("en") or name ("english"); -1 if unknown. }
    whisper_lang_id: function(lang: PAnsiChar): Int32; cdecl;
    { Code of a language id ("en"). }
    whisper_lang_str: function(id: Int32): PAnsiChar; cdecl;
    { English name of a language id ("english"). }
    whisper_lang_str_full: function(id: Int32): PAnsiChar; cdecl;
    { Detects the language of the mel already computed; fills lang_probs
      (whisper_lang_max_id + 1 floats) and returns the most probable id. }
    whisper_lang_auto_detect: function(ctx: PWhisperContext; offset_ms, n_threads: Int32;
      lang_probs: PSingle): Int32; cdecl;

    { Mel length. }
    whisper_n_len: function(ctx: PWhisperContext): Int32; cdecl;
    { Vocabulary size. }
    whisper_n_vocab: function(ctx: PWhisperContext): Int32; cdecl;
    { Text context size. }
    whisper_n_text_ctx: function(ctx: PWhisperContext): Int32; cdecl;
    { Audio context size. }
    whisper_n_audio_ctx: function(ctx: PWhisperContext): Int32; cdecl;
    { Non-zero for a multilingual model. }
    whisper_is_multilingual: function(ctx: PWhisperContext): Int32; cdecl;
    { Model hyper-parameter n_vocab. }
    whisper_model_n_vocab: function(ctx: PWhisperContext): Int32; cdecl;
    { Model hyper-parameter n_audio_ctx. }
    whisper_model_n_audio_ctx: function(ctx: PWhisperContext): Int32; cdecl;
    { Model hyper-parameter n_audio_state. }
    whisper_model_n_audio_state: function(ctx: PWhisperContext): Int32; cdecl;
    { Model hyper-parameter n_audio_head. }
    whisper_model_n_audio_head: function(ctx: PWhisperContext): Int32; cdecl;
    { Model hyper-parameter n_audio_layer. }
    whisper_model_n_audio_layer: function(ctx: PWhisperContext): Int32; cdecl;
    { Model hyper-parameter n_text_ctx. }
    whisper_model_n_text_ctx: function(ctx: PWhisperContext): Int32; cdecl;
    { Model hyper-parameter n_text_state. }
    whisper_model_n_text_state: function(ctx: PWhisperContext): Int32; cdecl;
    { Model hyper-parameter n_text_head. }
    whisper_model_n_text_head: function(ctx: PWhisperContext): Int32; cdecl;
    { Model hyper-parameter n_text_layer. }
    whisper_model_n_text_layer: function(ctx: PWhisperContext): Int32; cdecl;
    { Model hyper-parameter n_mels. }
    whisper_model_n_mels: function(ctx: PWhisperContext): Int32; cdecl;
    { Weight type of the model (ggml ftype). }
    whisper_model_ftype: function(ctx: PWhisperContext): Int32; cdecl;
    { Model type (e_model). }
    whisper_model_type: function(ctx: PWhisperContext): Int32; cdecl;
    { Model type as text ("tiny", "base", ...). }
    whisper_model_type_readable: function(ctx: PWhisperContext): PAnsiChar; cdecl;

    { Logits of the last decode. }
    whisper_get_logits: function(ctx: PWhisperContext): PSingle; cdecl;
    { Text of a token. }
    whisper_token_to_str: function(ctx: PWhisperContext; token: TWhisperToken): PAnsiChar; cdecl;
    { Special token: end of transcript. }
    whisper_token_eot: function(ctx: PWhisperContext): TWhisperToken; cdecl;
    { Special token: start of transcript. }
    whisper_token_sot: function(ctx: PWhisperContext): TWhisperToken; cdecl;
    { Special token: start of LM. }
    whisper_token_solm: function(ctx: PWhisperContext): TWhisperToken; cdecl;
    { Special token: previous. }
    whisper_token_prev: function(ctx: PWhisperContext): TWhisperToken; cdecl;
    { Special token: no speech. }
    whisper_token_nosp: function(ctx: PWhisperContext): TWhisperToken; cdecl;
    { Special token: no time stamps. }
    whisper_token_not: function(ctx: PWhisperContext): TWhisperToken; cdecl;
    { Special token: first time stamp token (begin). }
    whisper_token_beg: function(ctx: PWhisperContext): TWhisperToken; cdecl;
    { Special token of a language id. }
    whisper_token_lang: function(ctx: PWhisperContext; lang_id: Int32): TWhisperToken; cdecl;
    { Task token: translate. }
    whisper_token_translate: function(ctx: PWhisperContext): TWhisperToken; cdecl;
    { Task token: transcribe. }
    whisper_token_transcribe: function(ctx: PWhisperContext): TWhisperToken; cdecl;

    { Timings of the last run. NOTE: returns a heap copy the library has no
      function to free (20 bytes leak per call), or nil without a state. }
    whisper_get_timings: function(ctx: PWhisperContext): PWhisperTimings; cdecl;
    { Prints the timings to the log. }
    whisper_print_timings: procedure(ctx: PWhisperContext); cdecl;
    { Resets the timings. }
    whisper_reset_timings: procedure(ctx: PWhisperContext); cdecl;

    { Full transcription. Required. Use @link(TWhisperLib.Full). }
    whisper_full: TWhisperFullFunc;
    { Full transcription with an explicit state. }
    whisper_full_with_state: TWhisperFullWithStateFunc;
    { Full transcription split over n_processors (lower quality at the joins). }
    whisper_full_parallel: TWhisperFullParallelFunc;

    { Number of segments of the last run. Required. }
    whisper_full_n_segments: function(ctx: PWhisperContext): Int32; cdecl;
    { Number of segments of a state. }
    whisper_full_n_segments_from_state: function(state: PWhisperState): Int32; cdecl;
    { Language id of the last run. }
    whisper_full_lang_id: function(ctx: PWhisperContext): Int32; cdecl;
    { Language id of a state. }
    whisper_full_lang_id_from_state: function(state: PWhisperState): Int32; cdecl;
    { Start of a segment, 10 ms units. Required. }
    whisper_full_get_segment_t0: function(ctx: PWhisperContext; i_segment: Int32): Int64; cdecl;
    { Start of a segment of a state. }
    whisper_full_get_segment_t0_from_state: function(state: PWhisperState; i_segment: Int32): Int64; cdecl;
    { End of a segment, 10 ms units. Required. }
    whisper_full_get_segment_t1: function(ctx: PWhisperContext; i_segment: Int32): Int64; cdecl;
    { End of a segment of a state. }
    whisper_full_get_segment_t1_from_state: function(state: PWhisperState; i_segment: Int32): Int64; cdecl;
    { [TDRZ] the next segment is another speaker. }
    whisper_full_get_segment_speaker_turn_next: function(ctx: PWhisperContext; i_segment: Int32): Boolean; cdecl;
    { [TDRZ] the same, from a state. }
    whisper_full_get_segment_speaker_turn_next_from_state: function(state: PWhisperState; i_segment: Int32): Boolean; cdecl;
    { Text of a segment (UTF-8). Required. }
    whisper_full_get_segment_text: function(ctx: PWhisperContext; i_segment: Int32): PAnsiChar; cdecl;
    { Text of a segment of a state. }
    whisper_full_get_segment_text_from_state: function(state: PWhisperState; i_segment: Int32): PAnsiChar; cdecl;
    { No-speech probability of a segment. }
    whisper_full_get_segment_no_speech_prob: function(ctx: PWhisperContext; i_segment: Int32): Single; cdecl;
    { No-speech probability of a segment of a state. }
    whisper_full_get_segment_no_speech_prob_from_state: function(state: PWhisperState; i_segment: Int32): Single; cdecl;
    { Number of tokens of a segment. }
    whisper_full_n_tokens: function(ctx: PWhisperContext; i_segment: Int32): Int32; cdecl;
    { Number of tokens of a segment of a state. }
    whisper_full_n_tokens_from_state: function(state: PWhisperState; i_segment: Int32): Int32; cdecl;
    { Text of a token (UTF-8, may hold part of a character). }
    whisper_full_get_token_text: function(ctx: PWhisperContext; i_segment, i_token: Int32): PAnsiChar; cdecl;
    { Text of a token of a state (takes ctx AND state). }
    whisper_full_get_token_text_from_state: function(ctx: PWhisperContext; state: PWhisperState;
      i_segment, i_token: Int32): PAnsiChar; cdecl;
    { Id of a token. }
    whisper_full_get_token_id: function(ctx: PWhisperContext; i_segment, i_token: Int32): TWhisperToken; cdecl;
    { Id of a token of a state. }
    whisper_full_get_token_id_from_state: function(state: PWhisperState; i_segment, i_token: Int32): TWhisperToken; cdecl;
    { Data of a token. Use @link(TWhisperLib.GetTokenData). }
    whisper_full_get_token_data: TWhisperGetTokenDataFunc;
    { Data of a token of a state. }
    whisper_full_get_token_data_from_state: TWhisperGetTokenDataFromStateFunc;
    { Start of a token, 10 ms units. }
    whisper_full_get_token_t0: function(ctx: PWhisperContext; i_segment, i_token: Int32): Int64; cdecl;
    { End of a token, 10 ms units. }
    whisper_full_get_token_t1: function(ctx: PWhisperContext; i_segment, i_token: Int32): Int64; cdecl;
    { Probability of a token. }
    whisper_full_get_token_p: function(ctx: PWhisperContext; i_segment, i_token: Int32): Single; cdecl;
    { Probability of a token of a state. }
    whisper_full_get_token_p_from_state: function(state: PWhisperState; i_segment, i_token: Int32): Single; cdecl;
    { Number of VAD segments of the last run (vad = true). }
    whisper_full_n_vad_segments: function(ctx: PWhisperContext): Int32; cdecl;
    { Start of a VAD segment, 10 ms units of the original audio. }
    whisper_full_get_vad_segment_t0: function(ctx: PWhisperContext; i: Int32): Int64; cdecl;
    { End of a VAD segment. }
    whisper_full_get_vad_segment_t1: function(ctx: PWhisperContext; i: Int32): Int64; cdecl;

    { Benchmark of memcpy; text result. }
    whisper_bench_memcpy_str: function(n_threads: Int32): PAnsiChar; cdecl;
    { Benchmark of ggml_mul_mat; text result. }
    whisper_bench_ggml_mul_mat_str: function(n_threads: Int32): PAnsiChar; cdecl;
    { Routes whisper.cpp and ggml log output (nil = default: stderr). Use
      @link(TWhisperLib.AddLogListener) instead of calling it directly. }
    whisper_log_set: procedure(log_callback: TGgmlLogCallback; user_data: Pointer); cdecl;
  end;
  { Pointer to @link(TWhisperFlat). }
  PWhisperFlat = ^TWhisperFlat;

  { The ggml backend / device exports the binding uses, named as in
    ggml-backend.h. They live in ggml (registry, loading) and ggml-base
    (device properties); each is bound from whichever library has it. All
    optional: @nil when not found. }
  TWhisperGgmlFlat = record
    { Loads every known backend found in dir_path (best variant each). }
    ggml_backend_load_all_from_path: procedure(dir_path: PAnsiChar); cdecl;
    { Loads one backend library and registers it. }
    ggml_backend_load: function(path: PAnsiChar): PGgmlBackendReg; cdecl;
    { Number of registered backends. }
    ggml_backend_reg_count: function: NativeUInt; cdecl;
    { A registered backend. }
    ggml_backend_reg_get: function(index: NativeUInt): PGgmlBackendReg; cdecl;
    { Name of a backend ('CPU', 'CUDA', 'Vulkan', ...). }
    ggml_backend_reg_name: function(reg: PGgmlBackendReg): PAnsiChar; cdecl;
    { Number of devices of all registered backends. }
    ggml_backend_dev_count: function: NativeUInt; cdecl;
    { A device, in registry order. }
    ggml_backend_dev_get: function(index: NativeUInt): PGgmlBackendDev; cdecl;
    { Device by name ('CUDA0'). }
    ggml_backend_dev_by_name: function(name: PAnsiChar): PGgmlBackendDev; cdecl;
    { Name of a device ('CUDA0'). }
    ggml_backend_dev_name: function(device: PGgmlBackendDev): PAnsiChar; cdecl;
    { Description of a device (e.g. the GPU model). }
    ggml_backend_dev_description: function(device: PGgmlBackendDev): PAnsiChar; cdecl;
    { Free and total memory of a device, bytes. }
    ggml_backend_dev_memory: procedure(device: PGgmlBackendDev; free, total: PNativeUInt); cdecl;
    { Type of a device. }
    ggml_backend_dev_type: function(device: PGgmlBackendDev): TWhisperDeviceType; cdecl;
    { Backend of a device. }
    ggml_backend_dev_backend_reg: function(device: PGgmlBackendDev): PGgmlBackendReg; cdecl;
  end;
  { Pointer to @link(TWhisperGgmlFlat). }
  PWhisperGgmlFlat = ^TWhisperGgmlFlat;

  { A log line of whisper.cpp / ggml, delivered on the thread that wrote it.
    AText has no trailing line break. }
  TWhisperLogEvent = procedure(Sender: TObject; ALevel: TWhisperLogLevel;
    const AText: string) of object;
  { List of log listeners. }
  TWhisperLogEventArray = array of TWhisperLogEvent;

  { The loaded whisper.cpp library. One per process: @link(Load) creates it,
    @link(Unload) or the end of the program frees it. }
  TWhisperLib = class
  private
    { The whisper library. }
    FLib: TWhisperDynLib;
    { ggml libraries loaded before it, in load order (freed in reverse). }
    FDeps: TList;
    { Every bound export. }
    FFlat: TWhisperFlat;
    { Backing field of @link(Version). }
    FVersion: string;
    { Log listeners. }
    FLogListeners: TWhisperLogEventArray;
    { Guards FLogListeners, FLogBuffer and FLogLevel. }
    FLogLock: TCriticalSection;
    { Log text received without its line break yet. }
    FLogBuffer: string;
    { Level of FLogBuffer. }
    FLogLevel: TWhisperLogLevel;
    { Models created and not yet freed (Unload refuses while > 0). }
    FModelCount: Integer;
    { Messages about the loading (dependencies, missing exports). }
    FLoadLog: TStringList;
    { The ggml library (registry), for the device exports; @nil if absent. }
    FGgmlLib: TWhisperDynLib;
    { The ggml-base library (device properties); @nil if absent. }
    FGgmlBaseLib: TWhisperDynLib;
    { The ggml device exports. }
    FGgmlFlat: TWhisperGgmlFlat;
    { ggml device exports none of the libraries has. }
    FGgmlMissing: TStringList;
    { Backing field of @link(LibraryFolder). }
    FLibraryFolder: string;
    { Backing field of @link(BackendsLoaded). }
    FBackendsLoaded: Boolean;
    { @true while Load runs: log lines (ggml reporting the backends it
      loads or skips) go to LoadLog instead of stderr. }
    FCapturing: Boolean;
    { Creates the object; Load does the work. }
    constructor CreateLib;
    { Loads the ggml libraries found in AFolder, in dependency order:
      ggml-base, then ggml; when ggml does not load (a build that links its
      backends in, whose backend libraries the OS does not find), the
      backend libraries present first, then ggml again. }
    procedure LoadDependencies(const AFolder: string);
    { Loads one library of AFolder by stem (first file name that exists).
      @returns(@true when it was loaded.) }
    function LoadDependency(const AFolder, AStem: string): Boolean;
    { Opens ggml and ggml-base (already in the process) and binds the
      device exports. }
    procedure BindGgml;
    { Calls ggml_backend_load_all_from_path(AFolder) once (AFolder = '': the
      executable's folder and the current directory). }
    procedure LoadBackends(const AFolder: string);
    { Binds every export. }
    procedure BindAll;
    { Hooks or unhooks whisper_log_set depending on the listeners. }
    procedure UpdateLogHook;
    { Called by the C log callback: assembles lines and fires listeners. }
    procedure HandleLog(ALevel: TWhisperLogLevel; AText: PAnsiChar);
    { Fires every listener with one line. }
    procedure EmitLog(ALevel: TWhisperLogLevel; const AText: string);
    { Getter of @link(Flat). }
    function GetFlat: PWhisperFlat;
    { Getter of @link(FileName). }
    function GetFileName: string;
    { Getter of @link(MissingSymbols). }
    function GetMissingSymbols: TStrings;
    { Getter of @link(GgmlFlat). }
    function GetGgmlFlat: PWhisperGgmlFlat;
    { Raises when ggml lists no device: whisper.cpp would then throw a C++
      exception out of the model loader and end the process. }
    procedure CheckDevices;
    { Reads one device from the registry. }
    function ReadDevice(AIndex: Integer; ADev: PGgmlBackendDev; var AGpuCount: Integer): TWhisperDevice;
  public
    { Use @link(Load). }
    constructor Create;
    { Unhooks the log, unbinds every export and unloads the libraries. }
    destructor Destroy; override;

    { File names tried for the whisper library on this platform, in order
      (no folder): e.g. whisper.dll, libwhisper.dll on Windows. }
    class function LibraryNames: TStringList; static;

    { Loads the library, or returns the one already loaded.
      @param(ALibraryPath  '' = default search; a folder = look there; a
        file = that file.)
      @returns(The library.)
      @raises(EWhisperError when it cannot be loaded or a required export
        is missing.) }
    class function Load(const ALibraryPath: string = ''): TWhisperLib; static;
    { Unloads the library. Raises EWhisperError while models are alive. }
    class procedure Unload; static;
    { @true when the library is loaded. }
    class function IsLoaded: Boolean; static;
    { The loaded library. @raises(EWhisperError when not loaded.) }
    class function Instance: TWhisperLib; static;

    { Compares the Pascal records with whisper.h as compiled for this
      platform (Whisper.Layout.inc) and the defaults the library returns
      with the values whisper.h documents (finds a library built from a
      different whisper.h).
      @param(AReport  Receives one line per check that failed, and a summary
        line; may be @nil.)
      @returns(@true when everything matches.) }
    function CheckLayout(AReport: TStrings): Boolean;

    { Library version, e.g. '1.9.5'. }
    function Version: string;
    { System info: CPU features and backends of the library. }
    function SystemInfo: string;
    { Number of languages (whisper_lang_max_id + 1). }
    function LanguageCount: Integer;
    { Code of a language id ('en'). }
    function LanguageCode(AId: Integer): string;
    { English name of a language id ('english'). }
    function LanguageName(AId: Integer): string;
    { Id of a language code or name; -1 if unknown. }
    function LanguageId(const ACodeOrName: string): Integer;

    { The library's default whisper_context_params. }
    function DefaultContextParams: TWhisperContextParams;
    { The library's default whisper_full_params for a strategy. }
    function DefaultFullParams(AStrategy: TWhisperSamplingStrategy): TWhisperFullParams;

    { Loads a model file (whisper_init_from_file_with_params, FPU masked).
      @returns(The context, @nil on failure (see the log).) }
    function InitFromFile(const AFileName: string; const AParams: TWhisperContextParams): PWhisperContext;
    { Loads a model from memory (whisper_init_from_buffer_with_params).
      @returns(The context, @nil on failure.) }
    function InitFromBuffer(ABuffer: Pointer; ASize: NativeUInt;
      const AParams: TWhisperContextParams): PWhisperContext;
    { Runs whisper_full (AState = @nil) or whisper_full_with_state on the
      calling thread, FPU masked. AParams is copied first: the library may
      change its copy.
      @returns(0 on success; see whisper.cpp for the error codes.) }
    function Full(ACtx: PWhisperContext; AState: PWhisperState; const AParams: TWhisperFullParams;
      ASamples: PSingle; ACount: Integer): Integer;
    { whisper_full_get_token_data (or _from_state when AState <> @nil). }
    function GetTokenData(ACtx: PWhisperContext; AState: PWhisperState;
      ISegment, IToken: Integer): TWhisperTokenData;

    { Every device of the loaded backends, in registry order (memory as of
      now). Empty when the library has no device exports (very old builds). }
    function Devices: TWhisperDeviceArray;
    { Finds a device by name ('CPU', 'CUDA0', 'Vulkan1', ...; not case
      sensitive).
      @returns(@true when found.) }
    function FindDevice(const AName: string; out ADevice: TWhisperDevice): Boolean;
    { Sets use_gpu / gpu_device of AParams so whisper.cpp uses the named
      device: WHISPER_DEVICE_CPU = CPU only; a GPU / IGPU name = that device;
      '' = leave AParams as it is (whisper.cpp's choice: the first GPU when
      use_gpu).
      @returns(@false when the name is not a usable device - AParams is
        then unchanged.) }
    function ContextParamsFor(const ADevice: string; var AParams: TWhisperContextParams): Boolean;
    { Devices whisper.cpp can be told to use, for a choice or a benchmark:
      the CPU device first, then every GPU and IGPU (ACCEL devices are always
      used anyway, META ones never). }
    function SelectableDevices: TWhisperDeviceArray;

    { Adds a log listener; the first one routes whisper.cpp's log here
      (otherwise it goes to stderr). Listeners run on the thread that logs. }
    procedure AddLogListener(const AListener: TWhisperLogEvent);
    { Removes a log listener; the last one restores the default log. }
    procedure RemoveLogListener(const AListener: TWhisperLogEvent);

    { Counts a model in (Whisper.Core). }
    procedure ModelCreated;
    { Counts a model out (Whisper.Core). }
    procedure ModelFreed;

    { Every export. }
    property Flat: PWhisperFlat read GetFlat;
    { File the whisper library was loaded from. }
    property FileName: string read GetFileName;
    { Optional exports the library does not have. }
    property MissingSymbols: TStrings read GetMissingSymbols;
    { The ggml device exports (each may be @nil). }
    property GgmlFlat: PWhisperGgmlFlat read GetGgmlFlat;
    { ggml device exports none of the libraries has. }
    property GgmlMissingSymbols: TStringList read FGgmlMissing;
    { Folder the whisper library was loaded from - also when it was found
      through the OS search path (located with GetModuleFileNameW / dladdr);
      '' only when the OS could not tell. Backends are loaded from here. }
    property LibraryFolder: string read FLibraryFolder;
    { @true once ggml_backend_load_all_from_path has run. }
    property BackendsLoaded: Boolean read FBackendsLoaded;
    { What happened while loading: libraries loaded, dependencies skipped,
      and ggml's own lines about the backends it loaded or skipped (CUDA /
      Vulkan devices found, ...). }
    property LoadLog: TStringList read FLoadLog;
  end;

{ One line describing a device, e.g. 'CUDA0 - NVIDIA GeForce RTX 4070
  (GPU, CUDA, 11.2 of 12.0 GB free)'. }
function WhisperDeviceText(const ADevice: TWhisperDevice): string;

implementation

const
  { Names of the device types, for WhisperDeviceText. }
  DEVICE_TYPE_NAMES: array[TWhisperDeviceType] of string = ('CPU', 'GPU', 'integrated GPU',
    'accelerator', 'meta');
  { Bytes per gigabyte, for WhisperDeviceText. }
  BYTES_PER_GB = 1024.0 * 1024.0 * 1024.0;
  { Structs compared by CheckLayout (rows of WHISPER_C_LAYOUT). }
  WHISPER_LAYOUT_STRUCTS = 7;
  {$I Whisper.Layout.inc}

  { ggml libraries loaded before whisper, in dependency order: base, the
    backends (any that are present), then ggml itself. Stems only. }
  GGML_DEPENDENCIES: array[0..14] of string = ('ggml-base', 'ggml-cpu', 'ggml-blas',
    'ggml-metal', 'ggml-cuda', 'ggml-hip', 'ggml-musa', 'ggml-vulkan', 'ggml-opencl',
    'ggml-sycl', 'ggml-cann', 'ggml-zdnn', 'ggml-webgpu', 'ggml-rpc', 'ggml');

var
  { The loaded library (nil when not loaded). }
  GWhisperLib: TWhisperLib = nil;

{ File names of a library stem on this platform, most specific first. }
function PlatformFileNames(const AStem, AVersion: string): TStringList;
begin
  Result := TStringList.Create;
  {$if defined(MSWINDOWS)}
  Result.Add(AStem + '.dll');
  Result.Add('lib' + AStem + '.dll');      // MinGW builds
  {$elseif defined(WHISPER_MACOS)}
  Result.Add('lib' + AStem + '.dylib');
  if AVersion <> '' then
    Result.Add('lib' + AStem + '.' + AVersion + '.dylib');
  {$else}
  Result.Add('lib' + AStem + '.so');
  if AVersion <> '' then
    Result.Add('lib' + AStem + '.so.' + AVersion);
  {$endif}
end;

{ Full path of the file ALib was loaded from, asked from the OS: needed when
  it was found through the search path (PATH, LD_LIBRARY_PATH). ASymbol is
  an export of ALib (POSIX: dladdr needs an address inside the library).
  Returns '' when the OS cannot tell. }
function LoadedModulePath(ALib: TWhisperDynLib; const ASymbol: string): string;
{$ifdef MSWINDOWS}
type
  TGetModuleFileNameW = function(hModule: NativeUInt; lpFilename: PWideChar; nSize: Cardinal): Cardinal; stdcall;
const
  MAX_LONG_PATH = 32768;
var
  Kernel: TWhisperDynLib;
  GetModuleFileNameW: TGetModuleFileNameW;
  Buf: UnicodeString;
  N: Cardinal;
begin
  Result := '';
  Kernel := TWhisperDynLib.Load('kernel32.dll', False);
  if Kernel = nil then
    Exit;
  try
    if not Kernel.Bind(GetModuleFileNameW, 'GetModuleFileNameW', False) then
      Exit;
    SetLength(Buf, MAX_LONG_PATH);
    N := GetModuleFileNameW(NativeUInt(ALib.Handle), PWideChar(Buf), MAX_LONG_PATH);
    if (N > 0) and (N < MAX_LONG_PATH) then
      Result := string(Copy(Buf, 1, N));
  finally
    Kernel.Free;
  end;
end;
{$else}
type
  { Dl_info of dlfcn.h. }
  TDlInfo = record
    { Path of the object containing the address. }
    dli_fname: PAnsiChar;
    { Base address of that object. }
    dli_fbase: Pointer;
    { Nearest symbol. }
    dli_sname: PAnsiChar;
    { Its address. }
    dli_saddr: Pointer;
  end;
  TDladdr = function(addr: Pointer; info: Pointer): Integer; cdecl;
var
  Libc: TWhisperDynLib;
  Dladdr: TDladdr;
  Info: TDlInfo;
  Addr: Pointer;
begin
  Result := '';
  Addr := nil;
  if not ALib.Bind(Addr, ASymbol, False) then
    Exit;
  {$ifdef WHISPER_MACOS}
  Libc := TWhisperDynLib.LoadFirst(['/usr/lib/libSystem.B.dylib', 'libSystem.B.dylib'], False);
  {$else}
  Libc := TWhisperDynLib.LoadFirst(['libc.so.6', 'libdl.so.2', 'libdl.so'], False);
  {$endif}
  if Libc = nil then
    Exit;
  try
    if not Libc.Bind(Dladdr, 'dladdr', False) then
      Exit;
    FillChar(Info, SizeOf(Info), 0);
    if (Dladdr(Addr, @Info) <> 0) and (Info.dli_fname <> nil) then
      Result := ExpandFileName(string(UTF8String(Info.dli_fname)));
  finally
    Libc.Free;
  end;
end;
{$endif}

{ The C log callback: forwards to the library object. }
procedure WhisperLogTrampoline(level: TWhisperLogLevel; text: PAnsiChar; user_data: Pointer); cdecl;
begin
  try
    // user_data is the library object (also while it is still loading and
    // GWhisperLib is not set yet)
    if user_data <> nil then
      TWhisperLib(user_data).HandleLog(level, text)
    else if GWhisperLib <> nil then
      GWhisperLib.HandleLog(level, text);
  except
    // never let an exception unwind through C frames
  end;
end;

{ TWhisperLib }

constructor TWhisperLib.Create;
begin
  raise EWhisperError.Create('Use TWhisperLib.Load to load the whisper.cpp library');
end;

constructor TWhisperLib.CreateLib;
begin
  inherited Create;
  FDeps := TList.Create;
  FLogLock := TCriticalSection.Create;
  FLoadLog := TStringList.Create;
  FGgmlMissing := TStringList.Create;
end;

destructor TWhisperLib.Destroy;
var
  I: Integer;
begin
  if (FLib <> nil) and Assigned(FFlat.whisper_log_set) then
    FFlat.whisper_log_set(nil, nil);
  FillChar(FFlat, SizeOf(FFlat), 0);   // no export may be called after this
  FillChar(FGgmlFlat, SizeOf(FGgmlFlat), 0);
  FreeAndNil(FLib);
  FreeAndNil(FGgmlLib);
  FreeAndNil(FGgmlBaseLib);
  if FDeps <> nil then
    for I := FDeps.Count - 1 downto 0 do
      TWhisperDynLib(FDeps[I]).Free;
  FreeAndNil(FDeps);
  FreeAndNil(FLoadLog);
  FreeAndNil(FGgmlMissing);
  FreeAndNil(FLogLock);
  inherited;
end;

class function TWhisperLib.LibraryNames: TStringList;
begin
  Result := PlatformFileNames('whisper', '1');
end;

function TWhisperLib.LoadDependency(const AFolder, AStem: string): Boolean;
var
  Names: TStringList;
  Path: string;
  J: Integer;
  Dep: TWhisperDynLib;
begin
  Result := False;
  Names := PlatformFileNames(AStem, '0');
  try
    for J := 0 to Names.Count - 1 do
    begin
      Path := IncludeTrailingPathDelimiter(AFolder) + Names[J];
      if not FileExists(Path) then
        Continue;
      try
        Dep := TWhisperDynLib.Load(Path, True);
        FDeps.Add(Dep);
        FLoadLog.Add('Loaded dependency ' + Path);
        Result := True;
      except
        on E: EWhisperDynLibError do
          // A backend whose own runtime is missing (e.g. CUDA) is skipped;
          // whisper may still load with the others.
          FLoadLog.Add('Skipped dependency ' + Path + ': ' + E.Message);
      end;
      Exit;
    end;
  finally
    Names.Free;
  end;
end;

procedure TWhisperLib.LoadDependencies(const AFolder: string);
var
  I: Integer;
begin
  // ggml-base, then ggml: all a GGML_BACKEND_DL build links against (its
  // backends are loaded later by ggml itself, see LoadBackends).
  LoadDependency(AFolder, GGML_DEPENDENCIES[Low(GGML_DEPENDENCIES)]);
  if LoadDependency(AFolder, GGML_DEPENDENCIES[High(GGML_DEPENDENCIES)]) then
    Exit;
  // ggml did not load (or is absent): a build that links its backends into
  // ggml, whose backend libraries the OS does not look for in AFolder. Load
  // the ones present, then ggml again.
  for I := Low(GGML_DEPENDENCIES) + 1 to High(GGML_DEPENDENCIES) - 1 do
    LoadDependency(AFolder, GGML_DEPENDENCIES[I]);
  LoadDependency(AFolder, GGML_DEPENDENCIES[High(GGML_DEPENDENCIES)]);
end;

procedure TWhisperLib.BindGgml;

  { Opens a ggml library: from the whisper library's folder when known,
    else by name (it is in the process already as a dependency). }
  function OpenLib(const AStem: string): TWhisperDynLib;
  var
    Names: TStringList;
    J: Integer;
  begin
    Result := nil;
    Names := PlatformFileNames(AStem, '0');
    try
      for J := 0 to Names.Count - 1 do
      begin
        if FLibraryFolder <> '' then
        begin
          if FileExists(IncludeTrailingPathDelimiter(FLibraryFolder) + Names[J]) then
            Result := TWhisperDynLib.Load(IncludeTrailingPathDelimiter(FLibraryFolder) + Names[J], False);
        end
        else
          Result := TWhisperDynLib.Load(Names[J], False);
        if Result <> nil then
          Exit;
      end;
    finally
      Names.Free;
    end;
  end;

  { Binds AName from whichever library has it. }
  procedure G(var AProc; const AName: string);
  begin
    Pointer(AProc) := nil;
    if (FGgmlLib <> nil) and FGgmlLib.HasSymbol(AName) then
      FGgmlLib.Bind(AProc, AName, False)
    else if (FGgmlBaseLib <> nil) and FGgmlBaseLib.HasSymbol(AName) then
      FGgmlBaseLib.Bind(AProc, AName, False)
    else if FLib.HasSymbol(AName) then        // ggml linked into whisper
      FLib.Bind(AProc, AName, False)
    else
      FGgmlMissing.Add(AName);
  end;

begin
  FGgmlLib := OpenLib(GGML_DEPENDENCIES[High(GGML_DEPENDENCIES)]);
  FGgmlBaseLib := OpenLib(GGML_DEPENDENCIES[Low(GGML_DEPENDENCIES)]);
  G(FGgmlFlat.ggml_backend_load_all_from_path, 'ggml_backend_load_all_from_path');
  G(FGgmlFlat.ggml_backend_load, 'ggml_backend_load');
  G(FGgmlFlat.ggml_backend_reg_count, 'ggml_backend_reg_count');
  G(FGgmlFlat.ggml_backend_reg_get, 'ggml_backend_reg_get');
  G(FGgmlFlat.ggml_backend_reg_name, 'ggml_backend_reg_name');
  G(FGgmlFlat.ggml_backend_dev_count, 'ggml_backend_dev_count');
  G(FGgmlFlat.ggml_backend_dev_get, 'ggml_backend_dev_get');
  G(FGgmlFlat.ggml_backend_dev_by_name, 'ggml_backend_dev_by_name');
  G(FGgmlFlat.ggml_backend_dev_name, 'ggml_backend_dev_name');
  G(FGgmlFlat.ggml_backend_dev_description, 'ggml_backend_dev_description');
  G(FGgmlFlat.ggml_backend_dev_memory, 'ggml_backend_dev_memory');
  G(FGgmlFlat.ggml_backend_dev_type, 'ggml_backend_dev_type');
  G(FGgmlFlat.ggml_backend_dev_backend_reg, 'ggml_backend_dev_backend_reg');
  if FGgmlMissing.Count > 0 then
    FLoadLog.Add(Format('%d ggml device export(s) missing: %s - device selection limited',
      [FGgmlMissing.Count, FGgmlMissing.CommaText]));
end;

procedure TWhisperLib.LoadBackends(const AFolder: string);
type
  TSetDllDirectoryW = function(lpPathName: PWideChar): LongBool; stdcall;
var
  M: TWhisperFPUMask;
  U: UTF8String;
  {$ifdef MSWINDOWS}
  Kernel: TWhisperDynLib;
  SetDllDirectoryW: TSetDllDirectoryW;
  W: UnicodeString;
  {$endif}
begin
  if FBackendsLoaded or not Assigned(FGgmlFlat.ggml_backend_load_all_from_path) then
    Exit;
  {$ifdef MSWINDOWS}
  // ggml loads each backend with LoadLibraryW(full path): its own runtime
  // DLLs (cudart64_*.dll, hipblas.dll, ...) are looked for on the normal
  // search path, which does not include the backend's folder. Add it while
  // the backends load.
  SetDllDirectoryW := nil;
  Kernel := nil;
  if AFolder <> '' then
  begin
    Kernel := TWhisperDynLib.Load('kernel32.dll', False);
    if Kernel <> nil then
      Kernel.Bind(SetDllDirectoryW, 'SetDllDirectoryW', False);
  end;
  {$endif}
  M := WhisperMaskFPU;
  try
    {$ifdef MSWINDOWS}
    if Assigned(SetDllDirectoryW) then
    begin
      W := UnicodeString(ExcludeTrailingPathDelimiter(AFolder));
      SetDllDirectoryW(PWideChar(W));
    end;
    try
    {$endif}
      if AFolder <> '' then
      begin
        U := UTF8String(ExcludeTrailingPathDelimiter(AFolder));
        FGgmlFlat.ggml_backend_load_all_from_path(PAnsiChar(U));
        FLoadLog.Add('Loaded backends from ' + AFolder);
      end
      else
      begin
        FGgmlFlat.ggml_backend_load_all_from_path(nil);
        FLoadLog.Add('Loaded backends from the executable folder and the current directory');
      end;
    {$ifdef MSWINDOWS}
    finally
      if Assigned(SetDllDirectoryW) then
        SetDllDirectoryW(nil);   // back to the default search path
    end;
    {$endif}
  finally
    WhisperRestoreFPU(M);
    {$ifdef MSWINDOWS}
    Kernel.Free;
    {$endif}
  end;
  FBackendsLoaded := True;
end;

function TWhisperLib.ReadDevice(AIndex: Integer; ADev: PGgmlBackendDev;
  var AGpuCount: Integer): TWhisperDevice;
var
  F, T: NativeUInt;
  Reg: PGgmlBackendReg;
begin
  Result.Index := AIndex;
  Result.Name := WhisperStr(FGgmlFlat.ggml_backend_dev_name(ADev));
  if Assigned(FGgmlFlat.ggml_backend_dev_description) then
    Result.Description := WhisperStr(FGgmlFlat.ggml_backend_dev_description(ADev))
  else
    Result.Description := '';
  Result.Backend := '';
  if Assigned(FGgmlFlat.ggml_backend_dev_backend_reg) and Assigned(FGgmlFlat.ggml_backend_reg_name) then
  begin
    Reg := FGgmlFlat.ggml_backend_dev_backend_reg(ADev);
    if Reg <> nil then
      Result.Backend := WhisperStr(FGgmlFlat.ggml_backend_reg_name(Reg));
  end;
  if Assigned(FGgmlFlat.ggml_backend_dev_type) then
    Result.DeviceType := FGgmlFlat.ggml_backend_dev_type(ADev)
  else
    Result.DeviceType := wdtGPU;
  F := 0;
  T := 0;
  if Assigned(FGgmlFlat.ggml_backend_dev_memory) then
    FGgmlFlat.ggml_backend_dev_memory(ADev, @F, @T);
  Result.MemoryFree := F;
  Result.MemoryTotal := T;
  // whisper_backend_init_gpu counts GPU and IGPU devices in registry order
  if Result.DeviceType in [wdtGPU, wdtIGPU] then
  begin
    Result.GpuIndex := AGpuCount;
    Inc(AGpuCount);
  end
  else
    Result.GpuIndex := -1;
end;

function TWhisperLib.Devices: TWhisperDeviceArray;
var
  I, N, GpuCount: Integer;
  Dev: PGgmlBackendDev;
begin
  Result := nil;
  if not Assigned(FGgmlFlat.ggml_backend_dev_count) or not Assigned(FGgmlFlat.ggml_backend_dev_get) or
    not Assigned(FGgmlFlat.ggml_backend_dev_name) then
    Exit;
  N := Integer(FGgmlFlat.ggml_backend_dev_count());
  SetLength(Result, N);
  GpuCount := 0;
  for I := 0 to N - 1 do
  begin
    Dev := FGgmlFlat.ggml_backend_dev_get(NativeUInt(I));
    Result[I] := ReadDevice(I, Dev, GpuCount);
  end;
end;

function TWhisperLib.FindDevice(const AName: string; out ADevice: TWhisperDevice): Boolean;
var
  All: TWhisperDeviceArray;
  I: Integer;
begin
  All := Devices;
  for I := 0 to High(All) do
    if SameText(All[I].Name, AName) then
    begin
      ADevice := All[I];
      Exit(True);
    end;
  Result := False;
end;

function TWhisperLib.ContextParamsFor(const ADevice: string; var AParams: TWhisperContextParams): Boolean;
var
  D: TWhisperDevice;
begin
  if ADevice = '' then
    Exit(True);
  if SameText(ADevice, WHISPER_DEVICE_CPU) then
  begin
    AParams.use_gpu := False;
    Exit(True);
  end;
  Result := FindDevice(ADevice, D) and (D.GpuIndex >= 0);
  if Result then
  begin
    AParams.use_gpu := True;
    AParams.gpu_device := D.GpuIndex;
  end
  else if FindDevice(ADevice, D) and (D.DeviceType = wdtCPU) then
  begin
    AParams.use_gpu := False;   // a CPU device under another name
    Result := True;
  end;
end;

function TWhisperLib.SelectableDevices: TWhisperDeviceArray;
var
  All: TWhisperDeviceArray;
  I, N: Integer;
begin
  All := Devices;
  Result := nil;
  SetLength(Result, Length(All));
  N := 0;
  // the CPU first: the reference every GPU is compared with
  for I := 0 to High(All) do
    if All[I].DeviceType = wdtCPU then
    begin
      Result[N] := All[I];
      Inc(N);
      Break;
    end;
  // then GPU / IGPU devices in registry order (= whisper's gpu_device order)
  for I := 0 to High(All) do
    if All[I].DeviceType in [wdtGPU, wdtIGPU] then
    begin
      Result[N] := All[I];
      Inc(N);
    end;
  SetLength(Result, N);
end;

function WhisperDeviceText(const ADevice: TWhisperDevice): string;
begin
  Result := ADevice.Name;
  if (ADevice.Description <> '') and not SameText(ADevice.Description, ADevice.Name) then
    Result := Result + ' - ' + ADevice.Description;
  Result := Result + ' (' + DEVICE_TYPE_NAMES[ADevice.DeviceType];
  if (ADevice.Backend <> '') and not SameText(ADevice.Backend, ADevice.Name) then
    Result := Result + ', ' + ADevice.Backend;
  if ADevice.MemoryTotal > 0 then
    Result := Result + Format(', %.1f of %.1f GB free', [ADevice.MemoryFree / BYTES_PER_GB,
      ADevice.MemoryTotal / BYTES_PER_GB]);
  Result := Result + ')';
end;

class function TWhisperLib.Load(const ALibraryPath: string): TWhisperLib;
var
  Lib: TWhisperLib;
  Names, Candidates: TStringList;
  ExeDir, Folder, Path, Tried: string;
  I, J: Integer;
  Devs: TWhisperDeviceArray;
begin
  if GWhisperLib <> nil then
    Exit(GWhisperLib);
  ExeDir := '';
  {$ifdef WHISPER_UNSUPPORTED_PLATFORM}
  raise EWhisperError.Create('whisper.cpp dynamic loading is not supported on this platform');
  {$endif}
  Lib := TWhisperLib.CreateLib;
  try
    Names := LibraryNames;
    Candidates := TStringList.Create;
    try
      // Folders to try: explicit, else the exe's (and the macOS bundle's
      // Frameworks); a bare name for the OS search path comes last.
      if (ALibraryPath <> '') and FileExists(ALibraryPath) then
        Candidates.Add(ExpandFileName(ALibraryPath))
      else
      begin
        if ALibraryPath <> '' then
          Folder := ExpandFileName(ALibraryPath)
        else
        begin
          ExeDir := ExpandFileName(ExtractFilePath(ParamStr(0)));
          Folder := ExeDir;
        end;
        for J := 0 to Names.Count - 1 do
          Candidates.Add(IncludeTrailingPathDelimiter(Folder) + Names[J]);
        {$ifdef WHISPER_MACOS}
        if ALibraryPath = '' then
          for J := 0 to Names.Count - 1 do
            Candidates.Add(ExpandFileName(IncludeTrailingPathDelimiter(ExeDir) + '..' + PathDelim +
              'Frameworks' + PathDelim + Names[J]));
        {$endif}
        if ALibraryPath = '' then
          for J := 0 to Names.Count - 1 do
            Candidates.Add(Names[J]);
      end;
      Tried := '';
      for I := 0 to Candidates.Count - 1 do
      begin
        Path := Candidates[I];
        if ExtractFilePath(Path) <> '' then
        begin
          if not FileExists(Path) then
          begin
            Tried := Tried + sLineBreak + '  ' + Path + ': not present';
            Continue;
          end;
          Lib.LoadDependencies(ExtractFilePath(Path));
        end;
        try
          Lib.FLib := TWhisperDynLib.Load(Path, True);
          Lib.FLoadLog.Add('Loaded ' + Path);
          Lib.FLibraryFolder := ExtractFilePath(Path);
          Break;
        except
          on E: EWhisperDynLibError do
            Tried := Tried + sLineBreak + '  ' + E.Message;
        end;
      end;
    finally
      Candidates.Free;
      Names.Free;
    end;
    if Lib.FLib = nil then
      raise EWhisperError.Create('Cannot load the whisper.cpp library. Tried:' + Tried);
    if Lib.FLibraryFolder = '' then
    begin
      // found through the search path: ggml must be told the real folder
      Path := LoadedModulePath(Lib.FLib, 'whisper_version');
      if Path <> '' then
      begin
        Lib.FLibraryFolder := ExtractFilePath(Path);
        Lib.FLoadLog.Add('Found through the search path: ' + Path);
      end
      else
        Lib.FLoadLog.Add('Found through the search path; its folder is unknown, so backends are ' +
          'only looked for next to the executable and in the current directory');
    end;
    Lib.BindAll;
    Lib.FVersion := WhisperStr(Lib.FFlat.whisper_version());
    Lib.BindGgml;
    // ggml reports each backend it loads (or why not) through the log:
    // keep those lines in LoadLog instead of letting them go to stderr
    Lib.FCapturing := True;
    try
      Lib.UpdateLogHook;
      Lib.LoadBackends(Lib.FLibraryFolder);
    finally
      Lib.FCapturing := False;
      Lib.UpdateLogHook;
    end;
    Devs := Lib.Devices;
    if Length(Devs) = 0 then
      Lib.FLoadLog.Add('No compute device listed (no ggml device exports, or no backend loaded)')
    else
      for I := 0 to High(Devs) do
        Lib.FLoadLog.Add('Device ' + WhisperDeviceText(Devs[I]));
  except
    Lib.Free;
    raise;
  end;
  GWhisperLib := Lib;
  Result := Lib;
end;

class procedure TWhisperLib.Unload;
begin
  if GWhisperLib = nil then
    Exit;
  if GWhisperLib.FModelCount > 0 then
    raise EWhisperError.CreateFmt('Cannot unload whisper.cpp: %d model(s) still loaded',
      [GWhisperLib.FModelCount]);
  FreeAndNil(GWhisperLib);
end;

class function TWhisperLib.IsLoaded: Boolean;
begin
  Result := GWhisperLib <> nil;
end;

class function TWhisperLib.Instance: TWhisperLib;
begin
  if GWhisperLib = nil then
    raise EWhisperError.Create('The whisper.cpp library is not loaded (call TWhisperLib.Load)');
  Result := GWhisperLib;
end;

procedure TWhisperLib.BindAll;

  procedure Req(var AProc; const AName: string);
  begin
    FLib.Bind(AProc, AName, True);
  end;

  procedure Opt(var AProc; const AName: string);
  begin
    FLib.Bind(AProc, AName, False);
  end;

begin
  FLib.SymbolErrorMode := semRaise;
  try
    Req(FFlat.whisper_version, 'whisper_version');
    Req(FFlat.whisper_init_from_file_with_params, 'whisper_init_from_file_with_params');
    Req(FFlat.whisper_free, 'whisper_free');
    Req(FFlat.whisper_free_params, 'whisper_free_params');
    Req(FFlat.whisper_free_context_params, 'whisper_free_context_params');
    Req(FFlat.whisper_context_default_params_by_ref, 'whisper_context_default_params_by_ref');
    Req(FFlat.whisper_full_default_params_by_ref, 'whisper_full_default_params_by_ref');
    Req(FFlat.whisper_full, 'whisper_full');
    Req(FFlat.whisper_full_n_segments, 'whisper_full_n_segments');
    Req(FFlat.whisper_full_get_segment_t0, 'whisper_full_get_segment_t0');
    Req(FFlat.whisper_full_get_segment_t1, 'whisper_full_get_segment_t1');
    Req(FFlat.whisper_full_get_segment_text, 'whisper_full_get_segment_text');
    Req(FFlat.whisper_lang_max_id, 'whisper_lang_max_id');
    Req(FFlat.whisper_lang_str, 'whisper_lang_str');
  except
    on E: EWhisperDynLibError do
      raise EWhisperError.Create('The whisper.cpp library is too old or not whisper.cpp: ' + E.Message);
  end;

  Opt(FFlat.whisper_print_system_info, 'whisper_print_system_info');
  Opt(FFlat.whisper_init_from_file_with_params_no_state, 'whisper_init_from_file_with_params_no_state');
  Opt(FFlat.whisper_init_from_buffer_with_params, 'whisper_init_from_buffer_with_params');
  Opt(FFlat.whisper_init_from_buffer_with_params_no_state, 'whisper_init_from_buffer_with_params_no_state');
  Opt(FFlat.whisper_init_state, 'whisper_init_state');
  Opt(FFlat.whisper_ctx_init_openvino_encoder, 'whisper_ctx_init_openvino_encoder');
  Opt(FFlat.whisper_free_state, 'whisper_free_state');
  Opt(FFlat.whisper_pcm_to_mel, 'whisper_pcm_to_mel');
  Opt(FFlat.whisper_encode, 'whisper_encode');
  Opt(FFlat.whisper_decode, 'whisper_decode');
  Opt(FFlat.whisper_tokenize, 'whisper_tokenize');
  Opt(FFlat.whisper_token_count, 'whisper_token_count');
  Opt(FFlat.whisper_lang_id, 'whisper_lang_id');
  Opt(FFlat.whisper_lang_str_full, 'whisper_lang_str_full');
  Opt(FFlat.whisper_lang_auto_detect, 'whisper_lang_auto_detect');
  Opt(FFlat.whisper_n_len, 'whisper_n_len');
  Opt(FFlat.whisper_n_vocab, 'whisper_n_vocab');
  Opt(FFlat.whisper_n_text_ctx, 'whisper_n_text_ctx');
  Opt(FFlat.whisper_n_audio_ctx, 'whisper_n_audio_ctx');
  Opt(FFlat.whisper_is_multilingual, 'whisper_is_multilingual');
  Opt(FFlat.whisper_model_n_vocab, 'whisper_model_n_vocab');
  Opt(FFlat.whisper_model_n_audio_ctx, 'whisper_model_n_audio_ctx');
  Opt(FFlat.whisper_model_n_audio_state, 'whisper_model_n_audio_state');
  Opt(FFlat.whisper_model_n_audio_head, 'whisper_model_n_audio_head');
  Opt(FFlat.whisper_model_n_audio_layer, 'whisper_model_n_audio_layer');
  Opt(FFlat.whisper_model_n_text_ctx, 'whisper_model_n_text_ctx');
  Opt(FFlat.whisper_model_n_text_state, 'whisper_model_n_text_state');
  Opt(FFlat.whisper_model_n_text_head, 'whisper_model_n_text_head');
  Opt(FFlat.whisper_model_n_text_layer, 'whisper_model_n_text_layer');
  Opt(FFlat.whisper_model_n_mels, 'whisper_model_n_mels');
  Opt(FFlat.whisper_model_ftype, 'whisper_model_ftype');
  Opt(FFlat.whisper_model_type, 'whisper_model_type');
  Opt(FFlat.whisper_model_type_readable, 'whisper_model_type_readable');
  Opt(FFlat.whisper_get_logits, 'whisper_get_logits');
  Opt(FFlat.whisper_token_to_str, 'whisper_token_to_str');
  Opt(FFlat.whisper_token_eot, 'whisper_token_eot');
  Opt(FFlat.whisper_token_sot, 'whisper_token_sot');
  Opt(FFlat.whisper_token_solm, 'whisper_token_solm');
  Opt(FFlat.whisper_token_prev, 'whisper_token_prev');
  Opt(FFlat.whisper_token_nosp, 'whisper_token_nosp');
  Opt(FFlat.whisper_token_not, 'whisper_token_not');
  Opt(FFlat.whisper_token_beg, 'whisper_token_beg');
  Opt(FFlat.whisper_token_lang, 'whisper_token_lang');
  Opt(FFlat.whisper_token_translate, 'whisper_token_translate');
  Opt(FFlat.whisper_token_transcribe, 'whisper_token_transcribe');
  Opt(FFlat.whisper_get_timings, 'whisper_get_timings');
  Opt(FFlat.whisper_print_timings, 'whisper_print_timings');
  Opt(FFlat.whisper_reset_timings, 'whisper_reset_timings');
  Opt(FFlat.whisper_full_with_state, 'whisper_full_with_state');
  Opt(FFlat.whisper_full_parallel, 'whisper_full_parallel');
  Opt(FFlat.whisper_full_n_segments_from_state, 'whisper_full_n_segments_from_state');
  Opt(FFlat.whisper_full_lang_id, 'whisper_full_lang_id');
  Opt(FFlat.whisper_full_lang_id_from_state, 'whisper_full_lang_id_from_state');
  Opt(FFlat.whisper_full_get_segment_t0_from_state, 'whisper_full_get_segment_t0_from_state');
  Opt(FFlat.whisper_full_get_segment_t1_from_state, 'whisper_full_get_segment_t1_from_state');
  Opt(FFlat.whisper_full_get_segment_speaker_turn_next, 'whisper_full_get_segment_speaker_turn_next');
  Opt(FFlat.whisper_full_get_segment_speaker_turn_next_from_state, 'whisper_full_get_segment_speaker_turn_next_from_state');
  Opt(FFlat.whisper_full_get_segment_text_from_state, 'whisper_full_get_segment_text_from_state');
  Opt(FFlat.whisper_full_get_segment_no_speech_prob, 'whisper_full_get_segment_no_speech_prob');
  Opt(FFlat.whisper_full_get_segment_no_speech_prob_from_state, 'whisper_full_get_segment_no_speech_prob_from_state');
  Opt(FFlat.whisper_full_n_tokens, 'whisper_full_n_tokens');
  Opt(FFlat.whisper_full_n_tokens_from_state, 'whisper_full_n_tokens_from_state');
  Opt(FFlat.whisper_full_get_token_text, 'whisper_full_get_token_text');
  Opt(FFlat.whisper_full_get_token_text_from_state, 'whisper_full_get_token_text_from_state');
  Opt(FFlat.whisper_full_get_token_id, 'whisper_full_get_token_id');
  Opt(FFlat.whisper_full_get_token_id_from_state, 'whisper_full_get_token_id_from_state');
  Opt(FFlat.whisper_full_get_token_data, 'whisper_full_get_token_data');
  Opt(FFlat.whisper_full_get_token_data_from_state, 'whisper_full_get_token_data_from_state');
  Opt(FFlat.whisper_full_get_token_t0, 'whisper_full_get_token_t0');
  Opt(FFlat.whisper_full_get_token_t1, 'whisper_full_get_token_t1');
  Opt(FFlat.whisper_full_get_token_p, 'whisper_full_get_token_p');
  Opt(FFlat.whisper_full_get_token_p_from_state, 'whisper_full_get_token_p_from_state');
  Opt(FFlat.whisper_full_n_vad_segments, 'whisper_full_n_vad_segments');
  Opt(FFlat.whisper_full_get_vad_segment_t0, 'whisper_full_get_vad_segment_t0');
  Opt(FFlat.whisper_full_get_vad_segment_t1, 'whisper_full_get_vad_segment_t1');
  Opt(FFlat.whisper_bench_memcpy_str, 'whisper_bench_memcpy_str');
  Opt(FFlat.whisper_bench_ggml_mul_mat_str, 'whisper_bench_ggml_mul_mat_str');
  Opt(FFlat.whisper_log_set, 'whisper_log_set');
  if FLib.MissingSymbols.Count > 0 then
    FLoadLog.Add(Format('%d optional export(s) missing: %s',
      [FLib.MissingSymbols.Count, FLib.MissingSymbols.CommaText]));
end;

function TWhisperLib.GetFlat: PWhisperFlat;
begin
  Result := @FFlat;
end;

function TWhisperLib.GetGgmlFlat: PWhisperGgmlFlat;
begin
  Result := @FGgmlFlat;
end;

function TWhisperLib.GetFileName: string;
begin
  if FLib = nil then
    Result := ''
  else
    Result := FLib.FileName;
end;

function TWhisperLib.GetMissingSymbols: TStrings;
begin
  Result := FLib.MissingSymbols;
end;

function TWhisperLib.Version: string;
begin
  Result := FVersion;
end;

function TWhisperLib.SystemInfo: string;
begin
  if Assigned(FFlat.whisper_print_system_info) then
    Result := Trim(WhisperStr(FFlat.whisper_print_system_info()))
  else
    Result := '';
end;

function TWhisperLib.LanguageCount: Integer;
begin
  Result := FFlat.whisper_lang_max_id() + 1;
end;

function TWhisperLib.LanguageCode(AId: Integer): string;
begin
  Result := WhisperStr(FFlat.whisper_lang_str(AId));
end;

function TWhisperLib.LanguageName(AId: Integer): string;
begin
  if Assigned(FFlat.whisper_lang_str_full) then
    Result := WhisperStr(FFlat.whisper_lang_str_full(AId))
  else
    Result := LanguageCode(AId);
end;

function TWhisperLib.LanguageId(const ACodeOrName: string): Integer;
var
  I: Integer;
begin
  // whisper_lang_id logs an error for unknown names ("auto" included), so
  // the table is searched here instead.
  for I := 0 to LanguageCount - 1 do
    if SameText(LanguageCode(I), ACodeOrName) or SameText(LanguageName(I), ACodeOrName) then
      Exit(I);
  Result := -1;
end;

function TWhisperLib.DefaultContextParams: TWhisperContextParams;
var
  P: PWhisperContextParams;
begin
  P := FFlat.whisper_context_default_params_by_ref();
  if P = nil then
    raise EWhisperError.Create('whisper_context_default_params_by_ref returned nil');
  Result := P^;
  FFlat.whisper_free_context_params(P);
end;

function TWhisperLib.DefaultFullParams(AStrategy: TWhisperSamplingStrategy): TWhisperFullParams;
var
  P: PWhisperFullParams;
begin
  P := FFlat.whisper_full_default_params_by_ref(AStrategy);
  if P = nil then
    raise EWhisperError.Create('whisper_full_default_params_by_ref returned nil');
  Result := P^;
  FFlat.whisper_free_params(P);
end;

procedure TWhisperLib.CheckDevices;
begin
  if Assigned(FGgmlFlat.ggml_backend_dev_count) and (FGgmlFlat.ggml_backend_dev_count() = 0) then
    raise EWhisperError.CreateFmt('No ggml compute backend is loaded, so no model can be loaded. A ' +
      'GGML_BACKEND_DL build needs its backend libraries (at least one ggml-cpu-*) in %s',
      [IfThen(LibraryFolder = '', 'the executable folder', LibraryFolder)]);
end;

function TWhisperLib.InitFromFile(const AFileName: string;
  const AParams: TWhisperContextParams): PWhisperContext;
var
  U: UTF8String;
  P: TWhisperContextParams;
  M: TWhisperFPUMask;
begin
  CheckDevices;
  U := UTF8String(AFileName);   // whisper.cpp converts UTF-8 to wide on Windows
  P := AParams;
  M := WhisperMaskFPU;
  try
    {$ifdef WHISPER_PARAMS_BY_POINTER}
    Result := FFlat.whisper_init_from_file_with_params(PAnsiChar(U), @P);
    {$else}
    Result := FFlat.whisper_init_from_file_with_params(PAnsiChar(U), P);
    {$endif}
  finally
    WhisperRestoreFPU(M);
  end;
end;

function TWhisperLib.InitFromBuffer(ABuffer: Pointer; ASize: NativeUInt;
  const AParams: TWhisperContextParams): PWhisperContext;
var
  P: TWhisperContextParams;
  M: TWhisperFPUMask;
begin
  if not Assigned(FFlat.whisper_init_from_buffer_with_params) then
    raise EWhisperError.Create('The library has no whisper_init_from_buffer_with_params');
  CheckDevices;
  P := AParams;
  M := WhisperMaskFPU;
  try
    {$ifdef WHISPER_PARAMS_BY_POINTER}
    Result := FFlat.whisper_init_from_buffer_with_params(ABuffer, ASize, @P);
    {$else}
    Result := FFlat.whisper_init_from_buffer_with_params(ABuffer, ASize, P);
    {$endif}
  finally
    WhisperRestoreFPU(M);
  end;
end;

function TWhisperLib.Full(ACtx: PWhisperContext; AState: PWhisperState;
  const AParams: TWhisperFullParams; ASamples: PSingle; ACount: Integer): Integer;
var
  P: TWhisperFullParams;
  M: TWhisperFPUMask;
begin
  if (AState <> nil) and not Assigned(FFlat.whisper_full_with_state) then
    raise EWhisperError.Create('The library has no whisper_full_with_state');
  P := AParams;   // a fresh copy per call: with the pointer ABI the callee owns it
  M := WhisperMaskFPU;
  try
    {$ifdef WHISPER_PARAMS_BY_POINTER}
    if AState = nil then
      Result := FFlat.whisper_full(ACtx, @P, ASamples, ACount)
    else
      Result := FFlat.whisper_full_with_state(ACtx, AState, @P, ASamples, ACount);
    {$else}
    if AState = nil then
      Result := FFlat.whisper_full(ACtx, P, ASamples, ACount)
    else
      Result := FFlat.whisper_full_with_state(ACtx, AState, P, ASamples, ACount);
    {$endif}
  finally
    WhisperRestoreFPU(M);
  end;
end;

function TWhisperLib.GetTokenData(ACtx: PWhisperContext; AState: PWhisperState;
  ISegment, IToken: Integer): TWhisperTokenData;
begin
  FillChar(Result, SizeOf(Result), 0);
  if AState = nil then
  begin
    if not Assigned(FFlat.whisper_full_get_token_data) then
      raise EWhisperError.Create('The library has no whisper_full_get_token_data');
    {$ifdef WHISPER_SRET_AS_PARAM}
    FFlat.whisper_full_get_token_data(@Result, ACtx, ISegment, IToken);
    {$else}
    Result := FFlat.whisper_full_get_token_data(ACtx, ISegment, IToken);
    {$endif}
  end
  else
  begin
    if not Assigned(FFlat.whisper_full_get_token_data_from_state) then
      raise EWhisperError.Create('The library has no whisper_full_get_token_data_from_state');
    {$ifdef WHISPER_SRET_AS_PARAM}
    FFlat.whisper_full_get_token_data_from_state(@Result, AState, ISegment, IToken);
    {$else}
    Result := FFlat.whisper_full_get_token_data_from_state(AState, ISegment, IToken);
    {$endif}
  end;
end;

procedure TWhisperLib.AddLogListener(const AListener: TWhisperLogEvent);
var
  N: Integer;
begin
  if not Assigned(AListener) then
    Exit;
  FLogLock.Acquire;
  try
    N := Length(FLogListeners);
    SetLength(FLogListeners, N + 1);
    FLogListeners[N] := AListener;
  finally
    FLogLock.Release;
  end;
  UpdateLogHook;
end;

procedure TWhisperLib.RemoveLogListener(const AListener: TWhisperLogEvent);
var
  I, J: Integer;
begin
  FLogLock.Acquire;
  try
    for I := High(FLogListeners) downto 0 do
      if (TMethod(FLogListeners[I]).Code = TMethod(AListener).Code) and
        (TMethod(FLogListeners[I]).Data = TMethod(AListener).Data) then
      begin
        for J := I to High(FLogListeners) - 1 do
          FLogListeners[J] := FLogListeners[J + 1];
        SetLength(FLogListeners, Length(FLogListeners) - 1);
        Break;
      end;
  finally
    FLogLock.Release;
  end;
  UpdateLogHook;
end;

procedure TWhisperLib.UpdateLogHook;
var
  Hook: Boolean;
begin
  if not Assigned(FFlat.whisper_log_set) then
    Exit;
  FLogLock.Acquire;
  try
    Hook := (Length(FLogListeners) > 0) or FCapturing;
  finally
    FLogLock.Release;
  end;
  if Hook then
    FFlat.whisper_log_set(WhisperLogTrampoline, Self)
  else
    FFlat.whisper_log_set(nil, nil);
end;

procedure TWhisperLib.HandleLog(ALevel: TWhisperLogLevel; AText: PAnsiChar);
var
  Line: string;
  Level: TWhisperLogLevel;
  Ready: Boolean;
begin
  Ready := False;
  Level := ALevel;
  FLogLock.Acquire;
  try
    if ALevel = wllCont then
      FLogBuffer := FLogBuffer + WhisperStr(AText)
    else
    begin
      if FLogBuffer <> '' then
      begin
        // the previous message never got its line break: emit it as it is
        Line := FLogBuffer;
        Level := FLogLevel;
        FLogBuffer := '';
        FLogLock.Release;
        try
          EmitLog(Level, TrimRight(Line));
        finally
          FLogLock.Acquire;
        end;
      end;
      FLogBuffer := WhisperStr(AText);
      FLogLevel := ALevel;
    end;
    if (FLogBuffer <> '') and CharInSet(FLogBuffer[Length(FLogBuffer)], [#10, #13]) then
    begin
      Line := TrimRight(FLogBuffer);
      Level := FLogLevel;
      FLogBuffer := '';
      Ready := True;
    end;
  finally
    FLogLock.Release;
  end;
  if Ready then
    EmitLog(Level, Line);
end;

procedure TWhisperLib.EmitLog(ALevel: TWhisperLogLevel; const AText: string);
const
  LEVEL_TAGS: array[TWhisperLogLevel] of string = ('', 'debug: ', '', 'warning: ', 'ERROR: ', '');
var
  Listeners: TWhisperLogEventArray;
  I: Integer;
begin
  FLogLock.Acquire;
  try
    if FCapturing then
      FLoadLog.Add(LEVEL_TAGS[ALevel] + AText);
    Listeners := Copy(FLogListeners, 0, Length(FLogListeners));
  finally
    FLogLock.Release;
  end;
  for I := 0 to High(Listeners) do
    try
      Listeners[I](Self, ALevel, AText);
    except
      // a listener must not break the library's logging
    end;
end;

procedure TWhisperLib.ModelCreated;
begin
  Inc(FModelCount);
end;

procedure TWhisperLib.ModelFreed;
begin
  Dec(FModelCount);
end;

function TWhisperLib.CheckLayout(AReport: TStrings): Boolean;
var
  Names: array of string;
  Values: array of Integer;
  Count, Errors: Integer;

  procedure Add(const AName: string; AValue: NativeInt);
  begin
    if Count >= Length(Values) then
    begin
      SetLength(Values, Count + 32);
      SetLength(Names, Count + 32);
    end;
    Names[Count] := AName;
    Values[Count] := Integer(AValue);
    Inc(Count);
  end;

  function Off(AField, ABase: Pointer): NativeInt;
  begin
    Result := NativeInt(NativeUInt(AField) - NativeUInt(ABase));
  end;

  procedure Fail(const AMessage: string);
  begin
    Inc(Errors);
    if AReport <> nil then
      AReport.Add(AMessage);
  end;

  procedure Expect(const AName: string; AOk: Boolean; const AGot: string);
  begin
    if not AOk then
      Fail(Format('Library default %s = %s, not the value whisper.h %s documents - the ' +
        'library was built from a different whisper.h', [AName, AGot, WHISPER_BINDING_VERSION]));
  end;

type
  // Alignment probes: the offset of R is the record's alignment.
  TAlignContext = record B: Byte; R: TWhisperContextParams; end;
  TAlignToken = record B: Byte; R: TWhisperTokenData; end;
  TAlignAhead = record B: Byte; R: TWhisperAhead; end;
  TAlignGrammar = record B: Byte; R: TWhisperGrammarElement; end;
  TAlignVad = record B: Byte; R: TWhisperVadParams; end;
  TAlignTimings = record B: Byte; R: TWhisperTimings; end;
  TAlignFull = record B: Byte; R: TWhisperFullParams; end;
var
  C: TWhisperContextParams;
  T: TWhisperTokenData;
  A: TWhisperAhead;
  G: TWhisperGrammarElement;
  V: TWhisperVadParams;
  Ti: TWhisperTimings;
  F, FB: TWhisperFullParams;
  AC: TAlignContext;
  AT: TAlignToken;
  AA: TAlignAhead;
  AG: TAlignGrammar;
  AV: TAlignVad;
  ATi: TAlignTimings;
  AF: TAlignFull;
  I: Integer;
begin
  Count := 0;
  Errors := 0;
  Values := nil;
  Names := nil;
  // Same order as FIELDS in tools/verify_layout.py.
  Add('TWhisperContextParams size', SizeOf(C));
  Add('TWhisperContextParams alignment', Off(@AC.R, @AC));
  Add('TWhisperContextParams.use_gpu', Off(@C.use_gpu, @C));
  Add('TWhisperContextParams.flash_attn', Off(@C.flash_attn, @C));
  Add('TWhisperContextParams.gpu_device', Off(@C.gpu_device, @C));
  Add('TWhisperContextParams.dtw_token_timestamps', Off(@C.dtw_token_timestamps, @C));
  Add('TWhisperContextParams.dtw_aheads_preset', Off(@C.dtw_aheads_preset, @C));
  Add('TWhisperContextParams.dtw_n_top', Off(@C.dtw_n_top, @C));
  Add('TWhisperContextParams.dtw_aheads_n_heads', Off(@C.dtw_aheads_n_heads, @C));
  Add('TWhisperContextParams.dtw_aheads_heads', Off(@C.dtw_aheads_heads, @C));
  Add('TWhisperContextParams.dtw_mem_size', Off(@C.dtw_mem_size, @C));

  Add('TWhisperTokenData size', SizeOf(T));
  Add('TWhisperTokenData alignment', Off(@AT.R, @AT));
  Add('TWhisperTokenData.id', Off(@T.id, @T));
  Add('TWhisperTokenData.tid', Off(@T.tid, @T));
  Add('TWhisperTokenData.p', Off(@T.p, @T));
  Add('TWhisperTokenData.plog', Off(@T.plog, @T));
  Add('TWhisperTokenData.pt', Off(@T.pt, @T));
  Add('TWhisperTokenData.ptsum', Off(@T.ptsum, @T));
  Add('TWhisperTokenData.t0', Off(@T.t0, @T));
  Add('TWhisperTokenData.t1', Off(@T.t1, @T));
  Add('TWhisperTokenData.t_dtw', Off(@T.t_dtw, @T));
  Add('TWhisperTokenData.vlen', Off(@T.vlen, @T));

  Add('TWhisperAhead size', SizeOf(A));
  Add('TWhisperAhead alignment', Off(@AA.R, @AA));
  Add('TWhisperAhead.n_text_layer', Off(@A.n_text_layer, @A));
  Add('TWhisperAhead.n_head', Off(@A.n_head, @A));

  Add('TWhisperGrammarElement size', SizeOf(G));
  Add('TWhisperGrammarElement alignment', Off(@AG.R, @AG));
  Add('TWhisperGrammarElement.type_', Off(@G.type_, @G));
  Add('TWhisperGrammarElement.value', Off(@G.value, @G));

  Add('TWhisperVadParams size', SizeOf(V));
  Add('TWhisperVadParams alignment', Off(@AV.R, @AV));
  Add('TWhisperVadParams.threshold', Off(@V.threshold, @V));
  Add('TWhisperVadParams.min_speech_duration_ms', Off(@V.min_speech_duration_ms, @V));
  Add('TWhisperVadParams.min_silence_duration_ms', Off(@V.min_silence_duration_ms, @V));
  Add('TWhisperVadParams.max_speech_duration_s', Off(@V.max_speech_duration_s, @V));
  Add('TWhisperVadParams.speech_pad_ms', Off(@V.speech_pad_ms, @V));
  Add('TWhisperVadParams.samples_overlap', Off(@V.samples_overlap, @V));

  Add('TWhisperTimings size', SizeOf(Ti));
  Add('TWhisperTimings alignment', Off(@ATi.R, @ATi));
  Add('TWhisperTimings.sample_ms', Off(@Ti.sample_ms, @Ti));
  Add('TWhisperTimings.encode_ms', Off(@Ti.encode_ms, @Ti));
  Add('TWhisperTimings.decode_ms', Off(@Ti.decode_ms, @Ti));
  Add('TWhisperTimings.batchd_ms', Off(@Ti.batchd_ms, @Ti));
  Add('TWhisperTimings.prompt_ms', Off(@Ti.prompt_ms, @Ti));

  Add('TWhisperFullParams size', SizeOf(F));
  Add('TWhisperFullParams alignment', Off(@AF.R, @AF));
  Add('TWhisperFullParams.strategy', Off(@F.strategy, @F));
  Add('TWhisperFullParams.n_threads', Off(@F.n_threads, @F));
  Add('TWhisperFullParams.n_max_text_ctx', Off(@F.n_max_text_ctx, @F));
  Add('TWhisperFullParams.offset_ms', Off(@F.offset_ms, @F));
  Add('TWhisperFullParams.duration_ms', Off(@F.duration_ms, @F));
  Add('TWhisperFullParams.translate', Off(@F.translate, @F));
  Add('TWhisperFullParams.no_context', Off(@F.no_context, @F));
  Add('TWhisperFullParams.no_timestamps', Off(@F.no_timestamps, @F));
  Add('TWhisperFullParams.single_segment', Off(@F.single_segment, @F));
  Add('TWhisperFullParams.print_special', Off(@F.print_special, @F));
  Add('TWhisperFullParams.print_progress', Off(@F.print_progress, @F));
  Add('TWhisperFullParams.print_realtime', Off(@F.print_realtime, @F));
  Add('TWhisperFullParams.print_timestamps', Off(@F.print_timestamps, @F));
  Add('TWhisperFullParams.token_timestamps', Off(@F.token_timestamps, @F));
  Add('TWhisperFullParams.thold_pt', Off(@F.thold_pt, @F));
  Add('TWhisperFullParams.thold_ptsum', Off(@F.thold_ptsum, @F));
  Add('TWhisperFullParams.max_len', Off(@F.max_len, @F));
  Add('TWhisperFullParams.split_on_word', Off(@F.split_on_word, @F));
  Add('TWhisperFullParams.max_tokens', Off(@F.max_tokens, @F));
  Add('TWhisperFullParams.debug_mode', Off(@F.debug_mode, @F));
  Add('TWhisperFullParams.audio_ctx', Off(@F.audio_ctx, @F));
  Add('TWhisperFullParams.tdrz_enable', Off(@F.tdrz_enable, @F));
  Add('TWhisperFullParams.suppress_regex', Off(@F.suppress_regex, @F));
  Add('TWhisperFullParams.initial_prompt', Off(@F.initial_prompt, @F));
  Add('TWhisperFullParams.carry_initial_prompt', Off(@F.carry_initial_prompt, @F));
  Add('TWhisperFullParams.prompt_tokens', Off(@F.prompt_tokens, @F));
  Add('TWhisperFullParams.prompt_n_tokens', Off(@F.prompt_n_tokens, @F));
  Add('TWhisperFullParams.language', Off(@F.language, @F));
  Add('TWhisperFullParams.detect_language', Off(@F.detect_language, @F));
  Add('TWhisperFullParams.suppress_blank', Off(@F.suppress_blank, @F));
  Add('TWhisperFullParams.suppress_nst', Off(@F.suppress_nst, @F));
  Add('TWhisperFullParams.temperature', Off(@F.temperature, @F));
  Add('TWhisperFullParams.max_initial_ts', Off(@F.max_initial_ts, @F));
  Add('TWhisperFullParams.length_penalty', Off(@F.length_penalty, @F));
  Add('TWhisperFullParams.temperature_inc', Off(@F.temperature_inc, @F));
  Add('TWhisperFullParams.entropy_thold', Off(@F.entropy_thold, @F));
  Add('TWhisperFullParams.logprob_thold', Off(@F.logprob_thold, @F));
  Add('TWhisperFullParams.no_speech_thold', Off(@F.no_speech_thold, @F));
  Add('TWhisperFullParams.greedy_best_of', Off(@F.greedy_best_of, @F));
  Add('TWhisperFullParams.beam_search_beam_size', Off(@F.beam_search_beam_size, @F));
  Add('TWhisperFullParams.beam_search_patience', Off(@F.beam_search_patience, @F));
  Add('TWhisperFullParams.new_segment_callback', Off(@@F.new_segment_callback, @F));
  Add('TWhisperFullParams.new_segment_callback_user_data', Off(@F.new_segment_callback_user_data, @F));
  Add('TWhisperFullParams.progress_callback', Off(@@F.progress_callback, @F));
  Add('TWhisperFullParams.progress_callback_user_data', Off(@F.progress_callback_user_data, @F));
  Add('TWhisperFullParams.encoder_begin_callback', Off(@@F.encoder_begin_callback, @F));
  Add('TWhisperFullParams.encoder_begin_callback_user_data', Off(@F.encoder_begin_callback_user_data, @F));
  Add('TWhisperFullParams.abort_callback', Off(@@F.abort_callback, @F));
  Add('TWhisperFullParams.abort_callback_user_data', Off(@F.abort_callback_user_data, @F));
  Add('TWhisperFullParams.logits_filter_callback', Off(@@F.logits_filter_callback, @F));
  Add('TWhisperFullParams.logits_filter_callback_user_data', Off(@F.logits_filter_callback_user_data, @F));
  Add('TWhisperFullParams.grammar_rules', Off(@F.grammar_rules, @F));
  Add('TWhisperFullParams.n_grammar_rules', Off(@F.n_grammar_rules, @F));
  Add('TWhisperFullParams.i_start_rule', Off(@F.i_start_rule, @F));
  Add('TWhisperFullParams.grammar_penalty', Off(@F.grammar_penalty, @F));
  Add('TWhisperFullParams.vad', Off(@F.vad, @F));
  Add('TWhisperFullParams.vad_model_path', Off(@F.vad_model_path, @F));
  Add('TWhisperFullParams.vad_params_threshold', Off(@F.vad_params_threshold, @F));
  Add('TWhisperFullParams.vad_params_min_speech_duration_ms', Off(@F.vad_params_min_speech_duration_ms, @F));
  Add('TWhisperFullParams.vad_params_min_silence_duration_ms', Off(@F.vad_params_min_silence_duration_ms, @F));
  Add('TWhisperFullParams.vad_params_max_speech_duration_s', Off(@F.vad_params_max_speech_duration_s, @F));
  Add('TWhisperFullParams.vad_params_speech_pad_ms', Off(@F.vad_params_speech_pad_ms, @F));
  Add('TWhisperFullParams.vad_params_samples_overlap', Off(@F.vad_params_samples_overlap, @F));

  {$ifdef WHISPER_NO_LAYOUT_TABLE}
  if AReport <> nil then
    AReport.Add(Format('No C layout table for this platform: %d record values NOT checked', [Count]));
  {$else}
  if Count <> Length(WHISPER_C_LAYOUT) then
    Fail(Format('Layout table has %d values, the Pascal records %d - regenerate ' +
      'Whisper.Layout.inc with tools/verify_layout.py', [Length(WHISPER_C_LAYOUT), Count]))
  else
    for I := 0 to Count - 1 do
      if Values[I] <> WHISPER_C_LAYOUT[I] then
        Fail(Format('%s: Pascal %d, C %d', [Names[I], Values[I], WHISPER_C_LAYOUT[I]]));
  {$endif}

  // Defaults of whisper_full_default_params (src/whisper.cpp) that have not
  // changed for many releases: a field moved in the library's own
  // whisper.h shows up here.
  F := DefaultFullParams(wssGreedy);
  FB := DefaultFullParams(wssBeamSearch);
  Expect('strategy (greedy)', F.strategy = wssGreedy, IntToStr(Ord(F.strategy)));
  Expect('strategy (beam search)', FB.strategy = wssBeamSearch, IntToStr(Ord(FB.strategy)));
  Expect('n_max_text_ctx', F.n_max_text_ctx = 16384, IntToStr(F.n_max_text_ctx));
  Expect('thold_pt', Abs(F.thold_pt - 0.01) < 1e-6, FloatToStr(F.thold_pt));
  Expect('entropy_thold', Abs(F.entropy_thold - 2.4) < 1e-6, FloatToStr(F.entropy_thold));
  Expect('no_speech_thold', Abs(F.no_speech_thold - 0.6) < 1e-6, FloatToStr(F.no_speech_thold));
  Expect('greedy.best_of (greedy)', F.greedy_best_of = 5, IntToStr(F.greedy_best_of));
  Expect('beam_search.beam_size (beam search)', FB.beam_search_beam_size = 5,
    IntToStr(FB.beam_search_beam_size));
  Expect('grammar_penalty', Abs(F.grammar_penalty - 100) < 1e-6, FloatToStr(F.grammar_penalty));
  Expect('vad_params.threshold', Abs(F.vad_params_threshold - 0.5) < 1e-6,
    FloatToStr(F.vad_params_threshold));
  Expect('vad_params.min_speech_duration_ms', F.vad_params_min_speech_duration_ms = 250,
    IntToStr(F.vad_params_min_speech_duration_ms));
  Expect('vad_params.speech_pad_ms', F.vad_params_speech_pad_ms = 30,
    IntToStr(F.vad_params_speech_pad_ms));

  Result := Errors = 0;
  if AReport <> nil then
    if Result then
      AReport.Add(Format('Layout check passed: %d record values and the library defaults match ' +
        'whisper.h %s (library %s)', [Count, WHISPER_BINDING_VERSION, FVersion]))
    else
      AReport.Add(Format('Layout check FAILED: %d problem(s) (binding %s, library %s); do not ' +
        'call whisper_full with this library', [Errors, WHISPER_BINDING_VERSION, FVersion]));
end;

initialization

finalization
  FreeAndNil(GWhisperLib);

end.
