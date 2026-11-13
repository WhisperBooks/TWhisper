(* Whisper.inc

  Shared compiler settings for every unit of the whisper.cpp binding.
  Include it right after the unit line of EVERY library unit:

  @longCode(#
  unit Whisper.Something;
  {$I Whisper.inc}
  interface
  #)

  It makes the same source compile with Delphi (FMX / VCL) and Free Pascal
  (FPC 3.2.2+, {$mode delphi}), and makes record and enum layout match
  whisper.h, which uses the platform's natural C layout (no #pragma pack):

  - Delphi: {$ALIGN 8} = natural alignment of every field (Int64 / Double /
    pointers on 8 bytes on 64-bit targets and on Win32 / ARM32, as MSVC and
    AAPCS do).
  - FPC: {$packrecords C}, which also covers i386 Linux, where the C ABI
    aligns Int64 on 4 bytes.
  - C enums are 32-bit ints, so Pascal enums must be at least 4 bytes.

  tools/verify_layout.py checks the result against clang for every target and
  writes Whisper.Layout.inc; WhisperCheckLayout (Whisper.API) compares it at
  run time with what the Pascal compiler produced.

  Defines produced here (use them instead of compiler-specific symbols):

  - WHISPER_WINDOWS, WHISPER_MACOS, WHISPER_LINUX, WHISPER_ANDROID
  - WHISPER_CPU64, WHISPER_CPUX64, WHISPER_CPUARM64, WHISPER_CPU386
  - WHISPER_UNSUPPORTED_PLATFORM  (iOS, WebAssembly, ...)
  - WHISPER_ANONYMOUS_METHODS     (compiler supports "reference to")
  - WHISPER_PARAMS_BY_POINTER     (C structs passed by value are passed as a
                                   pointer to a caller-made copy: Win64 and
                                   every ARM64 ABI)
  - WHISPER_SRET_AS_PARAM         (a C struct returned by value comes back
                                   through an ordinary first pointer
                                   parameter: x86-64 and Win32 MSVC)
*)

{ ---------------------------------------------------------------- compiler }
{$ifdef FPC}
  {$mode delphi}
  {$H+}
  {$macro on}
  {$packrecords C}
  {$packenum 4}
  {$scopedenums off}
  // FPC 3.3.1+ (trunk) supports function references / anonymous functions.
  // PasDoc cannot evaluate FPC_FULLVERSION; no compiler defines PASDOC.
  {$ifndef PASDOC}
  {$if FPC_FULLVERSION >= 30301}
    {$modeswitch functionreferences}
    {$modeswitch anonymousfunctions}
    {$define WHISPER_ANONYMOUS_METHODS}
  {$endif}
  {$endif}
{$else}
  {$ALIGN 8}
  {$MINENUMSIZE 4}
  {$SCOPEDENUMS OFF}
  {$define WHISPER_ANONYMOUS_METHODS}
{$endif}

{ ---------------------------------------------------------------- platform }
{ ANDROID is tested before LINUX because FPC's Android target is Linux-based. }
{$if defined(IOS) or defined(IPHONESIM) or defined(WASI) or defined(WASM)}
  {$define WHISPER_UNSUPPORTED_PLATFORM}
{$elseif defined(MSWINDOWS)}
  {$define WHISPER_WINDOWS}
{$elseif defined(ANDROID)}
  {$define WHISPER_ANDROID}
{$elseif defined(DARWIN) or defined(MACOS)}
  {$define WHISPER_MACOS}
{$elseif defined(LINUX)}
  {$define WHISPER_LINUX}
{$else}
  {$define WHISPER_UNSUPPORTED_PLATFORM}
{$endif}

{ ---------------------------------------------------------------- cpu }
{$if defined(CPU64) or defined(CPU64BITS) or defined(CPUX64)}
  {$define WHISPER_CPU64}
{$endif}
{$if defined(CPUX64) or defined(CPUX86_64) or defined(CPUAMD64)}
  {$define WHISPER_CPUX64}
{$endif}
{$if defined(CPUARM64) or defined(CPUAARCH64)}
  {$define WHISPER_CPUARM64}
{$endif}
{$if defined(CPU386) or defined(CPUI386) or defined(CPUX86)}
  {$define WHISPER_CPU386}
{$endif}

{ ---------------------------------------------------------------- C ABI }
{ Checked against clang's lowering for 9 targets by tools/verify_layout.py. }
{$if defined(WHISPER_CPUARM64) or (defined(MSWINDOWS) and defined(WHISPER_CPUX64))}
  {$define WHISPER_PARAMS_BY_POINTER}
{$endif}
{$if defined(WHISPER_CPUX64) or (defined(WHISPER_CPU386) and defined(MSWINDOWS))}
  {$define WHISPER_SRET_AS_PARAM}
{$endif}
