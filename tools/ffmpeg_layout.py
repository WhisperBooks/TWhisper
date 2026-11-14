#!/usr/bin/env python3
"""ffmpeg_layout.py - field offsets of the FFmpeg structs that
lib/Whisper.FFmpeg.pas reads, for every target platform, from FFmpeg's own
headers with clang.

Usage:
    python3 tools/ffmpeg_layout.py <FFmpeg include folder> [--write]

The include folder is the one holding libavformat/avformat.h and
libavutil/avconfig.h (an installed "include" folder, or a configured
source tree).

What it does:
  1. Builds a C file storing the major versions of the four libraries,
     offsetof() of every field Whisper.FFmpeg reads from the large structs
     (AVFormatContext, AVStream, AVCodecParameters, AVFrame, AVPacket - the
     OFFSETS table) and sizeof / offsetof of the small structs it declares
     as Pascal records (the RECORDS table, in Pascal declaration order),
     compiles it with clang for each target and reads the numbers back from
     the LLVM IR.
  2. Groups targets with identical tables (the same groups as
     verify_layout.py) and, with --write, writes lib/Whisper.FFmpegLayout.inc:
     the library major versions, the offsets as constants per platform
     group, and the expected record layouts, which WhisperFFmpegCheckLayout
     (Whisper.FFmpeg) compares at run time with the Pascal compiler's.

Needs clang only (no target SDK): stub C library headers are supplied.
Exit code 0 = all targets of a group agree.
"""
import os, re, subprocess, sys, tempfile, shutil

# (C struct, C field, Pascal constant). Large structs: only offsets.
OFFSETS = [
    ('AVFormatContext', 'nb_streams', 'FMT_NB_STREAMS'),
    ('AVFormatContext', 'streams', 'FMT_STREAMS'),
    ('AVFormatContext', 'nb_chapters', 'FMT_NB_CHAPTERS'),
    ('AVFormatContext', 'chapters', 'FMT_CHAPTERS'),
    ('AVFormatContext', 'start_time', 'FMT_START_TIME'),
    ('AVFormatContext', 'duration', 'FMT_DURATION'),
    ('AVFormatContext', 'metadata', 'FMT_METADATA'),
    ('AVStream', 'index', 'STREAM_INDEX'),
    ('AVStream', 'codecpar', 'STREAM_CODECPAR'),
    ('AVStream', 'time_base', 'STREAM_TIME_BASE'),
    ('AVStream', 'start_time', 'STREAM_START_TIME'),
    ('AVStream', 'duration', 'STREAM_DURATION'),
    ('AVCodecParameters', 'codec_type', 'PAR_CODEC_TYPE'),
    ('AVCodecParameters', 'codec_id', 'PAR_CODEC_ID'),
    ('AVCodecParameters', 'ch_layout', 'PAR_CH_LAYOUT'),
    ('AVCodecParameters', 'sample_rate', 'PAR_SAMPLE_RATE'),
    ('AVFrame', 'extended_data', 'FRAME_EXTENDED_DATA'),
    ('AVFrame', 'nb_samples', 'FRAME_NB_SAMPLES'),
    ('AVFrame', 'format', 'FRAME_FORMAT'),
    ('AVFrame', 'pts', 'FRAME_PTS'),
    ('AVFrame', 'sample_rate', 'FRAME_SAMPLE_RATE'),
    ('AVFrame', 'ch_layout', 'FRAME_CH_LAYOUT'),
    ('AVPacket', 'stream_index', 'PACKET_STREAM_INDEX'),
]

# Small structs declared as Pascal records: (C struct, Pascal type, fields).
RECORDS = [
    ('AVRational', 'TAVRational', ['num', 'den']),
    ('AVChannelLayout', 'TAVChannelLayout', ['order', 'nb_channels', 'u', 'opaque']),
    ('AVChapter', 'TAVChapter', ['id', 'time_base', 'start', 'end', 'metadata']),
    ('AVDictionaryEntry', 'TAVDictionaryEntry', ['key', 'value']),
]

VERSIONS = [('LIBAVUTIL_VERSION_MAJOR', 'FFMPEG_AVUTIL_MAJOR'),
            ('LIBAVCODEC_VERSION_MAJOR', 'FFMPEG_AVCODEC_MAJOR'),
            ('LIBAVFORMAT_VERSION_MAJOR', 'FFMPEG_AVFORMAT_MAJOR'),
            ('LIBSWRESAMPLE_VERSION_MAJOR', 'FFMPEG_SWRESAMPLE_MAJOR')]

# Same targets and groups as verify_layout.py.
TARGETS = {
    'x86_64-pc-windows-msvc': 'P64', 'aarch64-unknown-linux-gnu': 'P64',
    'arm64-apple-macos': 'P64', 'aarch64-linux-android': 'P64',
    'x86_64-unknown-linux-gnu': 'P64', 'x86_64-apple-macos': 'P64',
    'i686-pc-windows-msvc': 'P32', 'armv7a-linux-androideabi': 'P32',
    'i686-unknown-linux-gnu': 'P32I386',
}
GROUP_COND = {
    'P64': 'defined(WHISPER_CPU64)',
    'P32': 'not defined(WHISPER_CPU64) and not (defined(WHISPER_CPU386) and not defined(MSWINDOWS))',
    'P32I386': 'defined(WHISPER_CPU386) and not defined(MSWINDOWS)',
}

# The few C library headers FFmpeg's public headers include, as stubs.
STUBS = {
    'errno.h': '#define EAGAIN 11\n#define EINVAL 22\n#define ENOMEM 12\n#define ENOSYS 38\n'
               '#define EDOM 33\n#define ERANGE 34\n',
    'stdio.h': 'typedef struct _FILE FILE;\n#define SEEK_SET 0\n#define SEEK_CUR 1\n#define SEEK_END 2\n',
    'inttypes.h': '#include <stdint.h>\n',
    'math.h': '', 'stdlib.h': '', 'string.h': '', 'time.h': '',
}

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def c_source():
    lines = ['#include <stddef.h>', '#include <libavformat/avformat.h>',
             '#include <libavcodec/avcodec.h>', '#include <libavutil/frame.h>',
             '#include <libswresample/swresample.h>',
             'unsigned long long ffmpeg_layout[] = {']
    for c, _ in VERSIONS:
        lines.append('  %s,' % c)
    for s, f, _ in OFFSETS:
        lines.append('  offsetof(%s, %s),' % (s, f))
    for s, _, fl in RECORDS:
        lines.append('  sizeof(%s), _Alignof(%s),' % (s, s))
        for f in fl:
            lines.append('  offsetof(%s, %s),' % (s, f))
    lines.append('};')
    return '\n'.join(lines) + '\n'


def compile_ir(inc, tmp, target):
    resdir = subprocess.run(['clang', '-print-resource-dir'], capture_output=True,
                            text=True).stdout.strip()
    cmd = ['clang', '-target', target, '-nostdinc', '-isystem', os.path.join(resdir, 'include'),
           '-isystem', os.path.join(tmp, 'stub'), '-I', inc, '-Wno-everything',
           '-S', '-emit-llvm', '-o', '-', os.path.join(tmp, 'layout.c')]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit('clang failed for %s:\n%s' % (target, r.stderr))
    m = re.search(r'@ffmpeg_layout = [^\[]*\[\d+ x i64\] \[(.*?)\]', r.stdout, re.S)
    if not m:
        sys.exit('layout array not found in IR for ' + target)
    return [int(x) for x in re.findall(r'i64 (\d+)', m.group(1))]


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    inc = sys.argv[1]
    write = '--write' in sys.argv
    for h in ('libavformat/avformat.h', 'libavutil/avconfig.h', 'libswresample/swresample.h'):
        if not os.path.isfile(os.path.join(inc, h)):
            sys.exit('%s not found under %s' % (h, inc))
    tmp = tempfile.mkdtemp(prefix='ffmpeg_layout_')
    errors = 0
    try:
        os.makedirs(os.path.join(tmp, 'stub'))
        for name, text in STUBS.items():
            with open(os.path.join(tmp, 'stub', name), 'w') as f:
                f.write(text)
        with open(os.path.join(tmp, 'layout.c'), 'w') as f:
            f.write(c_source())
        tables = {}
        for t, group in TARGETS.items():
            nums = compile_ir(inc, tmp, t)
            if group in tables and tables[group][1] != nums:
                print('ERROR: %s differs from %s (group %s)' % (t, tables[group][0], group))
                errors += 1
            tables.setdefault(group, (t, nums))
            print('%-28s %-8s OK' % (t, group))
        _, nums = next(iter(tables.values()))
        print('\nlibrary majors: ' + ', '.join('%s %d' % (p, nums[i])
                                              for i, (_, p) in enumerate(VERSIONS)))
        for group, (t, nums) in tables.items():
            print('\n[%s] (%s)' % (group, t))
            for i, (s, f, _) in enumerate(OFFSETS):
                print('  %-18s %-14s %4d' % (s, f, nums[len(VERSIONS) + i]))
        if write:
            write_inc(tables)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print('\n%d error(s)' % errors)
    sys.exit(1 if errors else 0)


def write_inc(tables):
    _, first_nums = next(iter(tables.values()))
    out = ['(* Whisper.FFmpegLayout.inc - GENERATED by tools/ffmpeg_layout.py from',
           '  FFmpeg\'s headers with clang. Do not edit by hand: change the generator',
           '  and rerun it.',
           '',
           '  The FFmpeg major versions the offsets belong to, the offsets of the',
           '  fields Whisper.FFmpeg reads from FFmpeg\'s large structs, and the',
           '  expected C layout of its small Pascal records ("size, alignment,',
           '  offsets of the fields in declaration order"), per platform group.',
           '  Included by Whisper.FFmpeg in a const section. *)',
           '']
    for i, (_, p) in enumerate(VERSIONS):
        out.append('  %s = %d;' % (p, first_nums[i]))
    out.append('')
    first = True
    nv = len(VERSIONS)
    for group, (t, nums) in tables.items():
        out.append('{$%s %s}' % ('if' if first else 'elseif', GROUP_COND[group]))
        out.append('  // %s (checked on %s)' % (group, ', '.join(
            k for k, v in TARGETS.items() if v == group)))
        for i, (s, f, p) in enumerate(OFFSETS):
            out.append('  FFOFS_%s = %d;   // %s.%s' % (p, nums[nv + i], s, f))
        rec = nums[nv + len(OFFSETS):]
        out.append('  FFMPEG_C_LAYOUT: array[0..%d] of Integer = (' % (len(rec) - 1))
        rows = []
        i = 0
        for s, p, fl in RECORDS:
            n = 2 + len(fl)
            rows.append('    // %s = %s\n    %s' % (p, s, ', '.join(str(x) for x in rec[i:i + n])))
            i += n
        out.append(',\n'.join(rows))
        out.append('  );')
        first = False
    out.append('{$else}')
    out.append('  {$define WHISPER_NO_FFMPEG_LAYOUT}')
    out.append('{$endif}')
    path = os.path.join(ROOT, 'lib', 'Whisper.FFmpegLayout.inc')
    with open(path, 'w', newline='\r\n') as f:
        f.write('\n'.join(out) + '\n')
    print('wrote', path)


if __name__ == '__main__':
    main()
