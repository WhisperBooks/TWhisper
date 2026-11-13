#!/usr/bin/env python3
"""verify_layout.py - checks the Pascal binding's record layouts and by-value
lowering against whisper.h, using clang for every target platform.

Usage:
    python3 tools/verify_layout.py <whisper.cpp source folder> [--write]

What it does:
  1. Builds a C file that stores sizeof() / offsetof() of every field the
     Pascal records in lib/Whisper.Types.pas declare (the FIELDS table below
     must list them in the same order), compiles it with clang for each
     target and reads the numbers back from the LLVM IR.
  2. Groups targets with identical tables and (with --write) writes
     lib/Whisper.Layout.inc: the expected numbers per platform, which
     WhisperCheckLayout (Whisper.API) compares at run time with what the
     Pascal compiler produced.
  3. Checks clang's lowering of the by-value struct exports (whisper_full,
     whisper_full_with_state, whisper_init_from_file_with_params[_no_state],
     whisper_full_get_token_data) against the choice the Pascal binding
     makes for each target (ABI table below). A mismatch is an error.

Needs clang only (no target SDK): a stub stdio.h is supplied. Exit code 0 =
all checks passed.
"""
import os, re, subprocess, sys, tempfile, shutil

# (C struct, C field path, Pascal field name). Order = Pascal declaration order.
FIELDS = {
    'whisper_context_params': [
        ('use_gpu', 'use_gpu'), ('flash_attn', 'flash_attn'), ('gpu_device', 'gpu_device'),
        ('dtw_token_timestamps', 'dtw_token_timestamps'), ('dtw_aheads_preset', 'dtw_aheads_preset'),
        ('dtw_n_top', 'dtw_n_top'), ('dtw_aheads.n_heads', 'dtw_aheads_n_heads'),
        ('dtw_aheads.heads', 'dtw_aheads_heads'), ('dtw_mem_size', 'dtw_mem_size'),
    ],
    'whisper_token_data': [
        ('id', 'id'), ('tid', 'tid'), ('p', 'p'), ('plog', 'plog'), ('pt', 'pt'), ('ptsum', 'ptsum'),
        ('t0', 't0'), ('t1', 't1'), ('t_dtw', 't_dtw'), ('vlen', 'vlen'),
    ],
    'whisper_ahead': [('n_text_layer', 'n_text_layer'), ('n_head', 'n_head')],
    'whisper_grammar_element': [('type', 'type_'), ('value', 'value')],
    'whisper_vad_params': [
        ('threshold', 'threshold'), ('min_speech_duration_ms', 'min_speech_duration_ms'),
        ('min_silence_duration_ms', 'min_silence_duration_ms'),
        ('max_speech_duration_s', 'max_speech_duration_s'), ('speech_pad_ms', 'speech_pad_ms'),
        ('samples_overlap', 'samples_overlap'),
    ],
    'whisper_timings': [
        ('sample_ms', 'sample_ms'), ('encode_ms', 'encode_ms'), ('decode_ms', 'decode_ms'),
        ('batchd_ms', 'batchd_ms'), ('prompt_ms', 'prompt_ms'),
    ],
    'whisper_full_params': [(f, f.replace('.', '_')) for f in '''
        strategy n_threads n_max_text_ctx offset_ms duration_ms translate no_context
        no_timestamps single_segment print_special print_progress print_realtime
        print_timestamps token_timestamps thold_pt thold_ptsum max_len split_on_word
        max_tokens debug_mode audio_ctx tdrz_enable suppress_regex initial_prompt
        carry_initial_prompt prompt_tokens prompt_n_tokens language detect_language
        suppress_blank suppress_nst temperature max_initial_ts length_penalty
        temperature_inc entropy_thold logprob_thold no_speech_thold greedy.best_of
        beam_search.beam_size beam_search.patience new_segment_callback
        new_segment_callback_user_data progress_callback progress_callback_user_data
        encoder_begin_callback encoder_begin_callback_user_data abort_callback
        abort_callback_user_data logits_filter_callback logits_filter_callback_user_data
        grammar_rules n_grammar_rules i_start_rule grammar_penalty vad vad_model_path
        vad_params.threshold vad_params.min_speech_duration_ms
        vad_params.min_silence_duration_ms vad_params.max_speech_duration_s
        vad_params.speech_pad_ms vad_params.samples_overlap'''.split()],
}

# Pascal record type of each struct (for the generated include's comments).
PASCAL_TYPE = {
    'whisper_context_params': 'TWhisperContextParams', 'whisper_token_data': 'TWhisperTokenData',
    'whisper_ahead': 'TWhisperAhead', 'whisper_grammar_element': 'TWhisperGrammarElement',
    'whisper_vad_params': 'TWhisperVadParams', 'whisper_timings': 'TWhisperTimings',
    'whisper_full_params': 'TWhisperFullParams',
}

# target triple -> (layout group, Pascal condition of that group,
#                   params passed as explicit pointer?, token data result:
#                   'param' = explicit first result-pointer parameter,
#                   'record' = compiler's record return (not checkable here))
TARGETS = {
    'x86_64-pc-windows-msvc':    ('P64', True,  'param'),
    'aarch64-unknown-linux-gnu': ('P64', True,  'record'),
    'arm64-apple-macos':         ('P64', True,  'record'),
    'aarch64-linux-android':     ('P64', True,  'record'),
    'x86_64-unknown-linux-gnu':  ('P64', False, 'param'),
    'x86_64-apple-macos':        ('P64', False, 'param'),
    'i686-pc-windows-msvc':      ('P32', False, 'param'),
    'armv7a-linux-androideabi':  ('P32', False, 'record'),
    'i686-unknown-linux-gnu':    ('P32I386', False, 'record'),
}
GROUP_COND = {
    'P64': 'defined(WHISPER_CPU64)',
    'P32': 'not defined(WHISPER_CPU64) and not (defined(WHISPER_CPU386) and not defined(MSWINDOWS))',
    'P32I386': 'defined(WHISPER_CPU386) and not defined(MSWINDOWS)',
}

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def c_source():
    lines = ['#include <stddef.h>', '#include "whisper.h"', 'unsigned long long whisper_layout[] = {']
    for s, fl in FIELDS.items():
        tag = s if s in ('whisper_ahead', 'whisper_grammar_element', 'whisper_vad_params',
                         'whisper_token_data') else 'struct ' + s
        lines.append('  sizeof(%s), _Alignof(%s),' % (tag, tag))
        for c, _ in fl:
            lines.append('  offsetof(%s, %s),' % (tag, c))
    lines.append('};')
    lines.append('void *whisper_use[] = { (void*)whisper_full, (void*)whisper_full_with_state, '
                 '(void*)whisper_init_from_file_with_params, '
                 '(void*)whisper_init_from_file_with_params_no_state, '
                 '(void*)whisper_full_get_token_data };')
    return '\n'.join(lines) + '\n'


def compile_ir(src_dir, tmp, target):
    cmd = ['clang', '-target', target, '-ffreestanding', '-I', os.path.join(tmp, 'stub'),
           '-I', os.path.join(src_dir, 'include'), '-I', os.path.join(src_dir, 'ggml', 'include'),
           '-S', '-emit-llvm', '-o', '-', os.path.join(tmp, 'layout.c')]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit('clang failed for %s:\n%s' % (target, r.stderr))
    return r.stdout


def parse_layout(ir):
    m = re.search(r'@whisper_layout = [^\[]*\[\d+ x i64\] \[(.*?)\]', ir, re.S)
    if not m:
        sys.exit('layout array not found in IR')
    return [int(x) for x in re.findall(r'i64 (\d+)', m.group(1))]


def lowering(ir, fn):
    m = re.search(r'declare .*?@%s\((.*?)\)' % fn, ir)
    if not m:
        sys.exit('declaration of %s not found' % fn)
    return m.group(1)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    src_dir = sys.argv[1]
    write = '--write' in sys.argv
    if not os.path.isfile(os.path.join(src_dir, 'include', 'whisper.h')):
        sys.exit('include/whisper.h not found under ' + src_dir)
    tmp = tempfile.mkdtemp(prefix='whisper_layout_')
    errors = 0
    try:
        os.makedirs(os.path.join(tmp, 'stub'))
        with open(os.path.join(tmp, 'stub', 'stdio.h'), 'w') as f:
            f.write('typedef struct _FILE FILE;\n')
        with open(os.path.join(tmp, 'layout.c'), 'w') as f:
            f.write(c_source())
        tables = {}
        for t, (group, as_ptr, sret) in TARGETS.items():
            ir = compile_ir(src_dir, tmp, t)
            nums = parse_layout(ir)
            if group in tables and tables[group][1] != nums:
                print('ERROR: %s differs from %s (group %s)' % (t, tables[group][0], group))
                errors += 1
            tables.setdefault(group, (t, nums))
            # by-value parameters
            for fn in ('whisper_full', 'whisper_full_with_state',
                       'whisper_init_from_file_with_params',
                       'whisper_init_from_file_with_params_no_state'):
                low = lowering(ir, fn)
                is_byval = 'byval' in low or '[' in low  # [N x i32] = split in registers
                if as_ptr == is_byval:
                    print('ERROR: %s %s: clang lowers it as (%s), binding uses %s' %
                          (t, fn, low.strip(), 'a pointer' if as_ptr else 'a value record'))
                    errors += 1
            low = lowering(ir, 'whisper_full_get_token_data')
            if 'sret' not in low.split(',')[0]:
                print('ERROR: %s whisper_full_get_token_data is not sret: %s' % (t, low))
                errors += 1
            print('%-28s %-8s params=%-6s token_data=%s  OK' %
                  (t, group, 'ptr' if as_ptr else 'value', sret))
        # report
        for group, (t, nums) in tables.items():
            i = 0
            print('\n[%s] (%s)' % (group, t))
            for s, fl in FIELDS.items():
                print('  %-26s size %3d align %d' % (s, nums[i], nums[i + 1]))
                i += 2 + len(fl)
        if write:
            write_inc(tables)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print('\n%d error(s)' % errors)
    sys.exit(1 if errors else 0)


def write_inc(tables):
    out = ['(* Whisper.Layout.inc - GENERATED by tools/verify_layout.py from whisper.h',
           '  with clang. Do not edit by hand: change the generator and rerun it.',
           '',
           '  Expected C sizes and field offsets of every record in Whisper.Types,',
           '  per platform group. Included by Whisper.API (WhisperCheckLayout), which',
           '  compares them with what the Pascal compiler produced. Each struct is',
           '  "size, alignment, offsets of the fields in declaration order". *)',
           '']
    first = True
    for group, (t, nums) in tables.items():
        out.append('{$%s %s}' % ('if' if first else 'elseif', GROUP_COND[group]))
        out.append('  // %s (checked on %s)' % (group, ', '.join(
            k for k, v in TARGETS.items() if v[0] == group)))
        out.append('  WHISPER_C_LAYOUT: array[0..%d] of Integer = (' % (len(nums) - 1))
        i = 0
        rows = []
        for s, fl in FIELDS.items():
            n = 2 + len(fl)
            rows.append('    // %s = %s\n    %s' % (PASCAL_TYPE[s], s,
                        ', '.join(str(x) for x in nums[i:i + n])))
            i += n
        out.append(',\n'.join(rows))
        out.append('  );')
        first = False
    out.append('{$else}')
    out.append('  {$define WHISPER_NO_LAYOUT_TABLE}')
    out.append('{$endif}')
    path = os.path.join(ROOT, 'lib', 'Whisper.Layout.inc')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', newline='\r\n') as f:
        f.write('\n'.join(out) + '\n')
    print('wrote', path)


if __name__ == '__main__':
    main()
