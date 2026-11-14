# AMD HIP (ROCm) support - findings and plan

Status: 2026-11-14. Written so a new session can pick up AMD GPU work
without the chat history. Read CLAUDE.md first for the project rules
(delivery by zip, no commits / pushes, etc.).

## Why HIP at all

TWhisper loads whisper.cpp's ggml backends as separate libraries
(GGML_BACKEND_DL) and lets the user's own benchmark (TWhisperBenchmark: a
real transcription per model x device) pick the fastest device. HIP is
ggml's AMD-native GPU backend. Vulkan already works on every AMD GPU, so
HIP only matters where it is faster - and on the one AMD GPU tested so far
it is (see "Results").

Owner's rule (2026-11-14): support a backend only once it can be tested on
real hardware. Vulkan covers AMD until then.

## Where the build lives

whisper-dev (github.com/WhisperBooks/whisper-dev): CMake superproject,
whisper.cpp as a submodule (pinned 5922450 = whisper.cpp 1.9.5-dev),
output collected in dlls/.

- Windows: HIP is built in a SECOND tree (ExternalProject) with the HIP
  SDK's clang + Ninja, because the HIP SDK's clang cannot share a tree
  with MSVC (needed for CUDA). Needs HIP_PATH. Options
  WHISPER_DEV_HIP / WHISPER_DEV_HIP_TARGETS.
- Linux: HIP is built in the main tree (GGML_HIP=ON). Needs ROCm's
  clang: export HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)"
  before configuring.
- Runtime libraries: on Windows the HIP runtime (amdhip64_7.dll,
  amd_comgr_3.dll) comes with the user's AMD graphics driver; whisper-dev
  copies hipBLAS / rocBLAS (+ rocblas/library kernels) next to
  ggml-hip.dll. On Linux NOTHING is copied yet: libggml-hip.so needs
  libamdhip64, hipBLAS and rocBLAS from /opt/rocm - shipping Linux HIP
  means bundling those (large).
- If the runtime is missing or too old, ggml-hip simply fails to load and
  TWhisper carries on with the other backends (Vulkan remains). No crash.

## HIP SDK for Windows 7.x - facts

- Use 7.x (7.2 current at the time of writing; AMD's download page may
  still list 7.1.1). Windows 11 ONLY. 6.4.2 was the last release that
  also covered Windows 10.
- 7.x is not backwards compatible with 6.x; runtime DLLs renamed:
  amdhip64_7.dll (was amdhip64.dll), amd_comgr_3.dll (was amd_comgr.dll).
  Users need a 7.x-era AMD driver.
- Official supported list (AMD "System requirements for Windows",
  docs-7.2) - anything not listed is unsupported:

  | gfx target | Hardware |
  |---|---|
  | gfx1201 | RX 9070 XT / 9070 / 9070 GRE, Radeon AI PRO R9700 (RDNA4) |
  | gfx1200 | RX 9060 XT / 9060 (RDNA4) |
  | gfx1100 | RX 7900 XTX / XT, PRO W7900 / W7800 (RDNA3) |
  | gfx1101 | RX 7800 XT / 7700 XT, PRO W7700 (RDNA3) |
  | gfx1102 | RX 7650 GRE / 7600 XT / 7600 (RDNA3) |
  | gfx1150 | Ryzen AI 300 series, Ryzen AI 9 400 series (RDNA3.5 APUs) |
  | gfx1151 | Ryzen AI Max / Max+ 380-395 (incl. Pro), MAX+ 492 / 495, MAX PRO 490 |

  UNSUPPORTED in 7.2: all RDNA2 (RX 6000, PRO W6600 / W6800,
  gfx1030-1032), RDNA1, GCN (e.g. PRO VII, Vega iGPUs).
  The page states no minimum driver version.

### Laptops
- Listed: only the APUs (Ryzen AI 300 / 400 = gfx1150, Ryzen AI Max =
  gfx1151).
- Not listed but same silicon as listed desktop parts, so a build for that
  target will probably run: RX 7600M / 7600M XT / 7600S / 7700S (gfx1102),
  RX 7800M (gfx1101).
- No HIP: RX 6000M / 6000S (RDNA2), Ryzen 7040 / 8040 with 780M / 760M
  (gfx1103 - also the ROG Ally Z1), Ryzen 6000 with 680M, older Vega APUs,
  Steam Deck (gfx1033).
- Laptop catch: OEM graphics drivers lag; without AMD's own Adrenalin
  driver the 7.x runtime may be missing -> no HIP device, Vulkan instead.
- In practice most AMD laptop users will end up on Vulkan.

## whisper-dev changes still to make (not done yet)

1. WHISPER_DEV_HIP_TARGETS default: currently
   "gfx1030;gfx1100;gfx1101;gfx1102;gfx1200;gfx1201". gfx1030 is RDNA2 =
   unsupported in 7.2. New default:
   gfx1100;gfx1101;gfx1102;gfx1150;gfx1151;gfx1200;gfx1201
2. Check the library names whisper-dev copies on Windows against a real
   7.x install (hipblas.dll, hipblaslt.dll, rocblas.dll + rocblas/library,
   hipblaslt/library).
3. README: HIP needs Windows 11 and a 7.x-era AMD driver.
4. Linux: decide whether to bundle libamdhip64 / hipBLAS / rocBLAS (size!)
   or require ROCm installed.
5. Try ROCm's generic target gfx11-generic (rocminfo on the Steam Machine
   lists it next to gfx1102): one build for every RDNA3 chip, which would
   include gfx1103 (Z1 / 780M) that AMD's lists leave out. Needs checking
   that ggml and rocBLAS accept it (rocBLAS kernels are per target).
6. Already delivered (whisper-dev-vulkan.zip): on Linux the Vulkan SDK is
   optional - distribution packages are enough (Ubuntu: libvulkan-dev
   glslc spirv-headers); Vulkan switches on when glslc is found.

## Test machines

| Machine | GPU | HIP? |
|---|---|---|
| Owner's Steam Machine (2026) | semi-custom RDNA3, 28 CU, 8 GB GDDR6 = Navi 33, gfx1102 | YES - tested on Linux (below) |
| Owner's ROG Ally Z1 | RDNA3 iGPU gfx1103 | not on AMD's list; maybe via gfx11-generic |
| Owner's Steam Deck | RDNA2 iGPU gfx1033 | no - Vulkan |
| German tester's Beelink SER5 (Ryzen 5 5560U, Win 11 24H2, 16 GB shared) | Radeon Vega 6 iGPU, gfx90c | no - Vulkan + CPU only; useful as a low-end Windows / AMD Zen 3 CPU test box |
| Owner's laptops (RTX 5090 + Intel iGPU; IdeaPad GTX 1650 mobile) | NVIDIA / Intel | no AMD |

Windows HIP is still untested. Candidates: Windows 11 on the Steam
Machine (gfx1102 is on the 7.2 list, so it should work - installing
Windows there is awkward), or a tester with an RX 7000 / 9000 card or a
Ryzen AI laptop.

## Linux HIP test on the Steam Machine (how it was done)

SteamOS's root filesystem is read-only, so ROCm runs in a Distrobox
container (Distrobox shares the home folder with SteamOS - files copied to
the home folder over sftp are visible inside).

1. Desktop Mode, Konsole: `ls /dev/kfd` must exist (it does on SteamOS:
   the kernel supports ROCm).
2. Stop the machine suspending during long builds (System Settings ->
   Power Management, or in a host tab:
   `systemd-inhibit --what=idle:sleep --why="build" sleep infinity`).
3. ```
   distrobox create --name rocm --image docker.io/rocm/dev-ubuntu-24.04:latest --additional-flags "--device=/dev/kfd --device=/dev/dri --group-add keep-groups"
   distrobox enter rocm
   rocminfo | grep -i gfx        # -> gfx1102 and gfx11-generic
   ```
4. In the container:
   ```
   sudo apt update
   sudo apt install -y git cmake ninja-build libvulkan-dev glslc spirv-headers mesa-vulkan-drivers
   git clone --recursive https://github.com/WhisperBooks/whisper-dev
   cd whisper-dev
   export HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)"
   ./build.sh -DWHISPER_DEV_HIP=ON -DWHISPER_DEV_HIP_TARGETS=gfx1102 -DWHISPER_DEV_VULKAN=ON -DWHISPER_DEV_CUDA=OFF
   ```
   (Before the whisper-dev Vulkan fix: prefix `VULKAN_SDK=/usr`. If
   build.sh is not executable - it was pushed from Windows - use
   `sh build.sh` or `chmod +x`; fix in git with
   `git update-index --chmod=+x build.sh`.)
   Result: libggml-hip.so (76 MB), libggml-vulkan.so (33 MB), all CPU
   variants (zen4 picked on this CPU).
5. Device order with HIP + Vulkan: ROCm0 = device 0, Vulkan0 = device 1
   (ggml registers hip before vulkan).
6. If rocBLAS ever reports no kernels for the chip, the usual unofficial
   workaround is `HSA_OVERRIDE_GFX_VERSION=11.0.0` (pretend gfx1100). Not
   needed for gfx1102 here.

## Results

whisper-cli (whisper.cpp's own CLI - no Linux TWhisper build yet),
ggml-large-v3-turbo, LibriVox "Aladdin" (2106.6 s, 8 kHz mono WAV), the
CLI's DEFAULTS: beam search 5 / best of 5, 4 threads.

| Steam Machine | Total | Speed | Encode | Batch decode | Sampling (CPU) |
|---|---|---|---|---|---|
| HIP (ROCm0) | 74.9 s | 28.1x | 25.2 s (89 x 283 ms) | 30.9 s | 13.8 s |
| Vulkan0 (RADV) | 92.8 s | 22.7x | 42.3 s (97 x 436 ms) | 30.7 s | 13.8 s |

- HIP wins on this GPU, entirely in encoding (1.5x faster); decoding and
  sampling are the same. This is the OPPOSITE of the owner's RTX 5090
  laptop, where Vulkan beat CUDA - the reason the benchmark decides per
  machine.
- RADV on Navi 33 reports warp size 64, int dot 0, bf16 0, matrix cores
  KHR_coopmat; HIP runs native wave32.
- Both transcripts complete and good; wording and segment breaks differ a
  little between backends (different GPU code, different rounding), each
  with its own errors ("Ones the stranger" vs "On this the stranger").

### Against the RTX 5090 laptop

| Whole Aladdin, large-v3-turbo | Total | Speed | Encode |
|---|---|---|---|
| 5090 laptop, Vulkan0 (WhisperConsole, greedy) | 18.1 s | 116x | 3.2 s |
| 5090 laptop, CUDA0 (WhisperConsole, greedy) | ~18.6 s | 114x | - |
| Steam Machine, HIP (whisper-cli, beam 5, 4 threads) | 74.9 s | 28x | 25.2 s |
| Steam Machine, Vulkan (whisper-cli, beam 5, 4 threads) | 92.8 s | 23x | 42.3 s |

NOT like for like: about 44 s of the Steam Machine's time is beam-search
decoding / CPU sampling. Encode is the fairer GPU comparison: ~8x in the
5090's favour (a top laptop GPU vs an RX 7600-class chip). Still to run
for a fair figure:

```
./build/bin/whisper-cli -m ~/whisper/ggml-large-v3-turbo.bin -f ~/audio/aladdin.wav -dev 0 -bs 1 -bo 1 -t 12 -np
```

(and -dev 1 for Vulkan), or better WhisperConsole --bench once the Linux
build exists.

## Open questions / next steps

1. Greedy, 12-thread rerun on the Steam Machine (HIP and Vulkan).
2. gfx11-generic build: does one binary run on gfx1102 AND gfx1103 (Z1)?
3. Windows HIP: test on Windows 11 (Steam Machine or a tester's RX 7000 /
   9000 / Ryzen AI machine); verify the copied DLL names for 7.x.
4. Linux packaging: bundle ROCm's libraries or require ROCm; Steam Linux
   Runtime 3.0 (sniper) does not ship ROCm - see CLAUDE.md's FMX-on-Linux
   notes for the runtime itself.
5. TWhisper side needs no changes for HIP: devices come from ggml's
   registry (ROCm0 shows up like CUDA0 / Vulkan0) and the benchmark picks.

## Sources

- AMD HIP SDK for Windows 7.2 system requirements:
  https://rocm.docs.amd.com/projects/install-on-windows/en/docs-7.2/reference/system-requirements.html
- AMD HIP SDK for Windows 7.2 release notes:
  https://rocm.docs.amd.com/projects/install-on-windows/en/docs-7.2/about/releasenotes.html
- AMD HIP SDK 7.1.1 release notes (DLL renames):
  https://rocm.docs.amd.com/projects/install-on-windows/en/latest/about/releasenotes.html
- AMD HIP SDK download page: https://www.amd.com/en/developer/resources/rocm-hub/hip-sdk.html
- Steam Machine GPU (Navi 33 / gfx1102, per owner): https://www.techpowerup.com/gpu-specs/steam-machine-gpu.c4373
