# whisper-dev

Builds the [whisper.cpp](https://github.com/ggml-org/whisper.cpp) shared
libraries that [TWhisper](https://github.com/WhisperBooks/TWhisper) loads at
run time, with every backend as its own library (`GGML_BACKEND_DL`), and
collects them in **`dlls/`** at the root of this repository (Debug builds:
`dlls/debug/`). Only `dlls/README.md` and `dlls/.gitignore` are tracked.

- **CPU:** built in every variant the platform supports. ggml picks the best
  one for the machine at run time.
- **GPU:** CUDA and Vulkan (required on Windows), plus AMD HIP when the HIP SDK
  is installed. A machine without a given GPU simply skips that backend.
- **Choosing a device:** TWhisper lists the devices, selects one by name and
  benchmarks them (`TWhisper.Device`, `TWhisperBenchmark`).

## Setup

```
git clone --recurse-submodules https://github.com/WhisperBooks/whisper-dev
```

or, in an existing clone: `git submodule update --init --recursive`.
The `whisper.cpp` submodule is pinned to a commit: `--remote` would move it
to the branch head, and TWhisper's layout check is tied to the whisper.h it was
generated from.

## Prerequisites

| | Windows | Linux | macOS |
|---|---|---|---|
| Compiler | Visual Studio 2022 / 2026 with C++ | gcc / clang | Xcode command line tools |
| CMake | 3.21+ | 3.21+ | 3.21+ |
| CUDA | CUDA Toolkit (`CUDA_PATH`), required | used when `nvcc` is found | - |
| Vulkan | Vulkan SDK (`VULKAN_SDK`), required | Vulkan SDK, or the distribution's packages (Ubuntu: `libvulkan-dev glslc spirv-headers`) | (Metal is built in) |
| AMD HIP | HIP SDK (`HIP_PATH`) + Ninja, optional | ROCm (`ROCM_PATH`), optional | - |

On Windows `build.bat` works from any prompt: it sets up the x64 Visual
Studio environment itself and builds with **Ninja Multi-Config** (Ninja comes
with Visual Studio's "C++ CMake tools"), as whisper.cpp's own release builds
do. The Visual Studio generator is not used because it compiles CUDA through
NVIDIA's MSBuild integration, which may be missing for the installed Visual
Studio ("No CUDA toolset found").

## Build

```
build.bat                       Windows
./build.sh                      Linux / macOS
```

which is, on Windows (in an x64 Visual Studio environment)

```
cmake -B build -G "Ninja Multi-Config"
cmake --build build --config Release
```

`build.sh` builds with one job per CPU (`JOBS=n ./build.sh` to change it):
`cmake --build -j` without a number means unlimited jobs with make, which can
run a machine out of memory. `build.bat` uses Ninja's default (CPUs + 2);
`set JOBS=n` first to limit it - CUDA compiles need a lot of memory each.

Extra arguments to `build.bat` / `build.sh` go to the configure step:

| Option | Default | |
|---|---|---|
| `WHISPER_DEV_CUDA` | Windows ON, Linux if `nvcc` found | CUDA backend |
| `WHISPER_DEV_VULKAN` | Windows ON, Linux if `VULKAN_SDK` is set or `glslc` is found | Vulkan backend |
| `WHISPER_DEV_HIP` | ON if `HIP_PATH` / `ROCM_PATH` set | AMD HIP backend |
| `WHISPER_DEV_HIP_TARGETS` | `gfx1030;gfx1100;gfx1101;gfx1102;gfx1200;gfx1201` | AMD GPU architectures |
| `CUDA_ALL` | OFF | CUDA archs `50;75;86;89;120` instead of ggml's default list |
| `WHISPER_DEV_BLAS` | OFF | OpenBLAS backend (whisper.cpp always uses one that is present, so it takes the choice away) |
| `WHISPER_DEV_OPENVINO` | OFF | OpenVINO encoder (links into whisper, which then needs OpenVINO everywhere) |

A required SDK that is missing stops the configure step with a message; pass
`-DWHISPER_DEV_<X>=OFF` to build without that backend.

## What lands in `dlls/` (Windows)

| File | |
|---|---|
| `whisper.dll`, `ggml.dll`, `ggml-base.dll` | the libraries TWhisper loads |
| `ggml-cpu-*.dll` | CPU variants (`x64`, `sse42`, `haswell`, `skylakex`, `zen4`, ...) |
| `ggml-cuda.dll` + `cudart64_*`, `cublas64_*`, `cublasLt64_*` | CUDA backend and its runtime |
| `ggml-vulkan.dll` | Vulkan backend (`vulkan-1.dll` comes with the GPU driver) |
| `ggml-hip.dll` + `hipblas`, `rocblas`, `rocblas/library` | HIP backend (with `WHISPER_DEV_HIP`) |
| `msvcp140.dll`, `vcruntime140*.dll`, `vcomp140.dll` | MSVC + OpenMP runtime, app-local |

On Linux / macOS the same set as `lib*.so` / `lib*.dylib` (with their
soname copies, e.g. `libggml.so.0`).

On Windows, HIP is built in a second tree (`build/hip`) with the HIP SDK's own
clang, because that compiler cannot share a tree with MSVC, which CUDA needs.
Only `ggml-hip.dll` is taken from that tree. Both trees come from the same
checkout, so the backend API version matches.

## Using them

Copy `dlls/` next to the executable, or set `TWhisper.LibraryPath` to it, then:

```
WhisperConsole --check                          library, layout check, device list
WhisperConsole --bench ggml-base.en.bin jfk.wav time every device
```

## Benchmarks

`scripts/` and the `bench-*.bat` files run whisper.cpp's own `whisper-bench`
/ `whisper-cli` from `build/bin/Release` (examples are still built). Note that
`whisper-bench` times the encoder only; TWhisper's benchmark times real
transcription per device.
