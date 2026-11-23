# LiteSwitcher for Windows (x64 and ARM64). The macOS app is built by macos/build.sh.
#   cmake -S . -B build -A x64      (or -A ARM64)
#   cmake --build build --config Release
cmake_minimum_required(VERSION 3.21)
project(LiteSwitcher VERSION 2.1.0 LANGUAGES C CXX)

if(NOT WIN32)
  message(FATAL_ERROR "This CMake project builds the Windows app; on macOS run macos/build.sh")
endif()

# Static CRT: LiteSwitcher.exe needs nothing installed.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

add_executable(LiteSwitcher WIN32
  windows/main.cpp
  windows/LS.rc
  windows/LS.manifest
  core/ls_core.c)
target_include_directories(LiteSwitcher PRIVATE core windows)
target_compile_features(LiteSwitcher PRIVATE cxx_std_17 c_std_11)
target_compile_definitions(LiteSwitcher PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(LiteSwitcher PRIVATE /utf-8 /W4 /permissive- $<$<CONFIG:Release>:/O1 /GL>)
target_link_options(LiteSwitcher PRIVATE $<$<CONFIG:Release>:/LTCG /OPT:REF /OPT:ICF>)
target_link_libraries(LiteSwitcher PRIVATE user32 shell32 comctl32 advapi32 ole32)

# Detector self-test as a console tool (also run in CI).
add_executable(coretest core/coretest.c core/ls_core.c)
target_compile_options(coretest PRIVATE /utf-8 /W4)
