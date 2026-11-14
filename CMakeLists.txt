# whisper-dev - builds the whisper.cpp shared libraries TWhisper loads, with
# every backend as its own library (GGML_BACKEND_DL), and collects them in
# <repo>/dlls (Debug builds: <repo>/dlls/debug).
#
#   build.bat     Windows: sets up the x64 Visual Studio environment itself and
#                 uses the Ninja Multi-Config generator (as whisper.cpp's own
#                 release builds do: the Visual Studio generator needs NVIDIA's
#                 MSBuild integration for CUDA, which may be missing for the
#                 installed Visual Studio - "No CUDA toolset found")
#   ./build.sh    Linux / macOS
# Options (cmake -D...):
#   WHISPER_DEV_CUDA      CUDA backend          Windows: ON (required), else: ON if nvcc found
#   WHISPER_DEV_VULKAN    Vulkan backend        Windows: ON (required), else: ON if VULKAN_SDK set
#   WHISPER_DEV_HIP       AMD HIP backend       ON if HIP_PATH (Windows) / ROCM_PATH (Linux) is set
#   WHISPER_DEV_HIP_TARGETS  AMD GPU architectures, e.g. "gfx1100;gfx1201"
#   WHISPER_DEV_BLAS      OpenBLAS backend      OFF (see below)
#   WHISPER_DEV_OPENVINO  OpenVINO encoder      OFF (see below)
#   CUDA_ALL              CUDA archs 50;75;86;89;120 instead of ggml's default list
#
# The CPU backend is always built in every variant the platform supports
# (GGML_CPU_ALL_VARIANTS); ggml picks the best one for the machine at run
# time. GPU backends whose runtime is missing on a machine are skipped there.
# Missing SDKs for a required backend stop the configure step with a message
# instead of silently building less.
#
# BLAS is off by default: whisper.cpp ALWAYS uses an accelerator backend
# that is present, so a ggml-blas library in the folder would take the
# choice away from the program. OpenVINO is off by default: it links into
# whisper itself, which then does not load at all where OpenVINO is missing.

cmake_minimum_required(VERSION 3.21)
project(whisper-dev C CXX)

if (POLICY CMP0077)
    cmake_policy(SET CMP0077 NEW)   # option() honours normal variables set here
endif()
# whisper.cpp starts with cmake_minimum_required(VERSION 3.5), which resets
# CMP0077 to OLD in its scope: its option() calls would then DISCARD the values
# set below (BUILD_SHARED_LIBS, WHISPER_BUILD_EXAMPLES, ...) and use their own
# defaults. Make NEW the default for policies the subproject leaves unset.
set(CMAKE_POLICY_DEFAULT_CMP0077 NEW)

set(WHISPER_SRC ${CMAKE_CURRENT_SOURCE_DIR}/whisper.cpp)
if (NOT EXISTS ${WHISPER_SRC}/include/whisper.h)
    message(FATAL_ERROR "whisper.cpp submodule missing: git submodule update --init --recursive")
endif()

set(DLL_DIR ${CMAKE_CURRENT_SOURCE_DIR}/dlls)

message(STATUS "whisper-dev: ${CMAKE_SYSTEM_NAME} ${CMAKE_SYSTEM_PROCESSOR}, output ${DLL_DIR}")

# ---------------------------------------------------------------- defaults
set(_cuda_default OFF)
set(_vulkan_default OFF)
set(_hip_default OFF)
if (WIN32)
    set(_cuda_default ON)
    set(_vulkan_default ON)
    if (DEFINED ENV{HIP_PATH})
        set(_hip_default ON)
    endif()
elseif (CMAKE_SYSTEM_NAME MATCHES "Linux")
    find_program(_nvcc nvcc HINTS /usr/local/cuda/bin)
    if (_nvcc)
        set(_cuda_default ON)
        set(CMAKE_CUDA_COMPILER ${_nvcc})
    endif()
    find_program(_glslc glslc)
    if (DEFINED ENV{VULKAN_SDK} OR _glslc)
        set(_vulkan_default ON)
    endif()
    if (DEFINED ENV{ROCM_PATH})
        set(_hip_default ON)
    endif()
endif()

option(WHISPER_DEV_CUDA     "Build the CUDA backend"   ${_cuda_default})
option(WHISPER_DEV_VULKAN   "Build the Vulkan backend" ${_vulkan_default})
option(WHISPER_DEV_HIP      "Build the AMD HIP backend" ${_hip_default})
option(WHISPER_DEV_BLAS     "Build the OpenBLAS backend (always used when present)" OFF)
option(WHISPER_DEV_OPENVINO "Build whisper with the OpenVINO encoder (needs OpenVINO at run time)" OFF)
option(CUDA_ALL             "CUDA architectures 50;75;86;89;120 instead of ggml's default" OFF)
set(WHISPER_DEV_HIP_TARGETS "gfx1030;gfx1100;gfx1101;gfx1102;gfx1200;gfx1201" CACHE STRING
    "AMD GPU architectures for HIP (only ones the HIP SDK has rocBLAS kernels for)")

# ---------------------------------------------------------------- SDK checks
if (WHISPER_DEV_CUDA AND WIN32 AND NOT DEFINED ENV{CUDA_PATH})
    message(FATAL_ERROR "CUDA_PATH is not set: install the CUDA Toolkit or configure with -DWHISPER_DEV_CUDA=OFF")
endif()
if (WHISPER_DEV_VULKAN AND WIN32 AND NOT DEFINED ENV{VULKAN_SDK})
    message(FATAL_ERROR "VULKAN_SDK is not set: install the Vulkan SDK or configure with -DWHISPER_DEV_VULKAN=OFF")
endif()
# Linux: the Vulkan SDK is optional - the distribution's packages do
# (Ubuntu / Debian: libvulkan-dev glslc spirv-headers;
#  Arch: vulkan-headers vulkan-icd-loader shaderc spirv-headers)
if (WHISPER_DEV_VULKAN AND NOT WIN32 AND NOT APPLE AND NOT DEFINED ENV{VULKAN_SDK})
    find_package(Vulkan)
    find_package(SPIRV-Headers CONFIG QUIET)
    if (NOT Vulkan_FOUND OR NOT Vulkan_GLSLC_EXECUTABLE OR NOT SPIRV-Headers_FOUND)
        message(FATAL_ERROR "Vulkan headers / glslc / SPIRV-Headers not found: install the Vulkan SDK or your distribution's packages (Ubuntu: libvulkan-dev glslc spirv-headers), or configure with -DWHISPER_DEV_VULKAN=OFF")
    endif()
endif()

# ---------------------------------------------------------------- whisper.cpp
set(BUILD_SHARED_LIBS        ON)
set(GGML_BACKEND_DL          ON)
set(GGML_NATIVE              OFF)    # portable: runs on any CPU of the architecture
set(WHISPER_BUILD_TESTS      OFF)
set(WHISPER_BUILD_EXAMPLES   ON)     # whisper-cli / whisper-bench for the bench scripts
set(WHISPER_SDL2             OFF)
set(GGML_CUDA   ${WHISPER_DEV_CUDA})
set(GGML_VULKAN ${WHISPER_DEV_VULKAN})
set(GGML_BLAS   ${WHISPER_DEV_BLAS})
set(WHISPER_OPENVINO ${WHISPER_DEV_OPENVINO})
if (WHISPER_DEV_BLAS AND NOT GGML_BLAS_VENDOR)
    set(GGML_BLAS_VENDOR "OpenBLAS")
endif()

# every CPU variant where ggml supports it (x86 everywhere; ARM on Linux,
# Android and macOS - not Windows on ARM)
if (CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|AMD64|amd64|i.86)$" OR
    (CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64)$" AND NOT WIN32))
    set(GGML_CPU_ALL_VARIANTS ON)
else()
    set(GGML_CPU_ALL_VARIANTS OFF)
endif()

if (WHISPER_DEV_CUDA)
    # nvcc refuses host compilers newer than the CUDA release knows (Visual
    # Studio 2026 = MSVC 19.50+ with an older toolkit); this only skips that
    # version check.
    if (MSVC AND MSVC_VERSION GREATER_EQUAL 1950 AND NOT CMAKE_CUDA_FLAGS MATCHES "allow-unsupported-compiler")
        set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} -allow-unsupported-compiler")
        message(STATUS "whisper-dev: MSVC ${MSVC_VERSION} - passing -allow-unsupported-compiler to nvcc")
    endif()
    if (CUDA_ALL)
        set(CMAKE_CUDA_ARCHITECTURES "50;75;86;89;120")
    elseif (CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64" AND NOT DEFINED CMAKE_CUDA_ARCHITECTURES)
        set(CMAKE_CUDA_ARCHITECTURES "87")   # Jetson Orin
    endif()
endif()

# HIP: on Linux in this tree; on Windows in a separate clang tree (below),
# because the HIP SDK's clang cannot share a tree with MSVC (needed by CUDA).
if (WHISPER_DEV_HIP AND NOT WIN32)
    set(GGML_HIP ON)
    set(AMDGPU_TARGETS ${WHISPER_DEV_HIP_TARGETS})
    set(GPU_TARGETS ${WHISPER_DEV_HIP_TARGETS})
endif()

add_subdirectory(${WHISPER_SRC} whisper.cpp)

# ---------------------------------------------------------------- collect
# whisper.cpp writes its libraries to <build>/bin whatever a parent sets, so
# the 'dlls' target copies them (and the runtimes they need) to DLL_DIR.
set(_dest "$<IF:$<CONFIG:Debug>,${DLL_DIR}/debug,${DLL_DIR}>")
set(_copy_cmds COMMAND ${CMAKE_COMMAND} -E make_directory ${_dest})
set(_copy_deps)

# shared libraries: the file, plus on Linux / macOS the soname and the plain
# name (libggml.so.0 is what the others NEED; libggml.so is what TWhisper
# looks for first)
foreach (_t whisper ggml ggml-base)
    if (TARGET ${_t})
        list(APPEND _copy_deps ${_t})
        list(APPEND _copy_cmds COMMAND ${CMAKE_COMMAND} -E copy_if_different $<TARGET_FILE:${_t}> ${_dest})
        if (NOT WIN32)
            list(APPEND _copy_cmds
                COMMAND ${CMAKE_COMMAND} -E copy_if_different $<TARGET_FILE:${_t}> ${_dest}/$<TARGET_SONAME_FILE_NAME:${_t}>
                COMMAND ${CMAKE_COMMAND} -E copy_if_different $<TARGET_FILE:${_t}> ${_dest}/$<TARGET_LINKER_FILE_NAME:${_t}>)
        endif()
    endif()
endforeach()

# backend modules (every CPU variant, CUDA, Vulkan, Metal, HIP, BLAS, ...)
foreach (_t ${GGML_AVAILABLE_BACKENDS})
    if (TARGET ${_t})
        list(APPEND _copy_deps ${_t})
        list(APPEND _copy_cmds COMMAND ${CMAKE_COMMAND} -E copy_if_different $<TARGET_FILE:${_t}> ${_dest})
    endif()
endforeach()

if (WIN32)
    # CUDA runtime next to ggml-cuda.dll (CUDA 13 keeps it in bin\x64)
    if (WHISPER_DEV_CUDA)
        file(GLOB _cuda_dlls
            "$ENV{CUDA_PATH}/bin/cudart64_*.dll" "$ENV{CUDA_PATH}/bin/cublas64_*.dll" "$ENV{CUDA_PATH}/bin/cublasLt64_*.dll"
            "$ENV{CUDA_PATH}/bin/x64/cudart64_*.dll" "$ENV{CUDA_PATH}/bin/x64/cublas64_*.dll" "$ENV{CUDA_PATH}/bin/x64/cublasLt64_*.dll")
        if (NOT _cuda_dlls)
            message(FATAL_ERROR "No cudart64_*.dll / cublas64_*.dll under $ENV{CUDA_PATH}/bin")
        endif()
        list(APPEND _copy_cmds COMMAND ${CMAKE_COMMAND} -E copy_if_different ${_cuda_dlls} ${_dest})
    endif()
    # MSVC runtime + OpenMP (vcomp140.dll, used by ggml-cpu): app-local, so
    # the folder works where the VC++ redistributable is not installed
    set(CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS_SKIP ON)
    set(CMAKE_INSTALL_OPENMP_LIBRARIES ON)
    set(CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS_NO_WARNINGS ON)
    include(InstallRequiredSystemLibraries)
    if (CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS)
        list(APPEND _copy_cmds COMMAND ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS} ${_dest})
    endif()
    # OpenBLAS from vcpkg
    if (WHISPER_DEV_BLAS AND DEFINED VCPKG_INSTALLED_DIR)
        file(GLOB _blas_dlls "${VCPKG_INSTALLED_DIR}/${VCPKG_TARGET_TRIPLET}/bin/*.dll")
        if (_blas_dlls)
            list(APPEND _copy_cmds COMMAND ${CMAKE_COMMAND} -E copy_if_different ${_blas_dlls} ${_dest})
        endif()
    endif()
endif()

add_custom_target(dlls ALL ${_copy_cmds}
    COMMENT "Collecting the whisper.cpp libraries in ${DLL_DIR}"
    VERBATIM)
add_dependencies(dlls ${_copy_deps})

# ---------------------------------------------------------------- HIP (Windows)
if (WHISPER_DEV_HIP AND WIN32)
    if (NOT DEFINED ENV{HIP_PATH})
        message(FATAL_ERROR "HIP_PATH is not set: install the AMD HIP SDK or configure with -DWHISPER_DEV_HIP=OFF")
    endif()
    file(TO_CMAKE_PATH "$ENV{HIP_PATH}" _hip)
    find_program(_ninja ninja)
    if (NOT _ninja)
        message(FATAL_ERROR "ninja is not on PATH (needed to build the HIP backend)")
    endif()
    find_program(_hip_clang clang PATHS ${_hip}/bin ${_hip}/lib/llvm/bin NO_DEFAULT_PATH)
    find_program(_hip_clangxx clang++ PATHS ${_hip}/bin ${_hip}/lib/llvm/bin NO_DEFAULT_PATH)
    if (NOT _hip_clang OR NOT _hip_clangxx)
        message(FATAL_ERROR "clang / clang++ not found in the HIP SDK at ${_hip}")
    endif()
    string(REPLACE ";" "|" _hip_targets "${WHISPER_DEV_HIP_TARGETS}")
    include(ExternalProject)
    # Same checkout, its own tree, only ggml-hip is built; at run time it uses
    # the MSVC-built ggml-base.dll of the main tree (same backend API version).
    ExternalProject_Add(ggml-hip-windows
        SOURCE_DIR ${WHISPER_SRC}
        BINARY_DIR ${CMAKE_BINARY_DIR}/hip
        CMAKE_GENERATOR Ninja
        LIST_SEPARATOR |
        CMAKE_ARGS
            -DCMAKE_MAKE_PROGRAM=${_ninja}
            -DCMAKE_C_COMPILER=${_hip_clang}
            -DCMAKE_CXX_COMPILER=${_hip_clangxx}
            -DCMAKE_BUILD_TYPE=Release
            -DBUILD_SHARED_LIBS=ON -DGGML_BACKEND_DL=ON -DGGML_NATIVE=OFF -DGGML_CPU=OFF
            -DGGML_HIP=ON -DAMDGPU_TARGETS=${_hip_targets} -DGPU_TARGETS=${_hip_targets}
            -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_TESTS=OFF -DWHISPER_SDL2=OFF
        BUILD_COMMAND ${CMAKE_COMMAND} --build <BINARY_DIR> --target ggml-hip
        BUILD_ALWAYS ON
        INSTALL_COMMAND "")
    # ggml-hip.dll + hipBLAS / rocBLAS and their kernel libraries
    # (amdhip64_*.dll comes with the AMD driver and is not copied)
    file(GLOB _hip_dlls "${_hip}/bin/hipblas.dll" "${_hip}/bin/hipblaslt.dll" "${_hip}/bin/rocblas.dll")
    set(_hip_cmds
        COMMAND ${CMAKE_COMMAND} -E make_directory ${DLL_DIR}
        COMMAND ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_BINARY_DIR}/hip/bin/ggml-hip.dll ${DLL_DIR})
    if (_hip_dlls)
        list(APPEND _hip_cmds COMMAND ${CMAKE_COMMAND} -E copy_if_different ${_hip_dlls} ${DLL_DIR})
    endif()
    foreach (_lib rocblas hipblaslt)
        if (EXISTS ${_hip}/bin/${_lib}/library)
            list(APPEND _hip_cmds COMMAND ${CMAKE_COMMAND} -E copy_directory
                ${_hip}/bin/${_lib}/library ${DLL_DIR}/${_lib}/library)
        endif()
    endforeach()
    add_custom_target(dlls-hip ALL ${_hip_cmds}
        COMMENT "Collecting the HIP backend in ${DLL_DIR}"
        VERBATIM)
    add_dependencies(dlls-hip ggml-hip-windows dlls)
endif()

# ---------------------------------------------------------------- summary
message(STATUS "whisper-dev backends: CPU (all variants: ${GGML_CPU_ALL_VARIANTS}), CUDA ${WHISPER_DEV_CUDA}, "
               "Vulkan ${WHISPER_DEV_VULKAN}, HIP ${WHISPER_DEV_HIP}, BLAS ${WHISPER_DEV_BLAS}, "
               "OpenVINO ${WHISPER_DEV_OPENVINO}")
