# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "vpn_plugin")
project(${PROJECT_NAME} LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "vpn_plugin_plugin")

# Any new source files that you add to the plugin should be added here.
list(APPEND PLUGIN_SOURCES
  "background_worker.cpp"
  "background_worker.h"
  "../common/cli_output.h"
  "cli_process.cpp"
  "physical_net.cpp"
  "cli_process.h"
  "runner/platform_api.g.cpp"
  "runner/platform_api.g.h"
  "vpn_plugin.cpp"
  "vpn_plugin.h"
  "ui_thread_dispatcher.cpp"
  "ui_thread_dispatcher.h"
)

# Define the plugin library target. Its name must not be changed (see comment
# on PLUGIN_NAME above).
add_library(${PLUGIN_NAME} SHARED
  "include/vpn_plugin/vpn_plugin_c_api.h"
  "vpn_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
)

# Apply a standard set of build settings that are configured in the
# application-level CMakeLists.txt. This can be removed for plugins that want
# full control over build settings.
apply_standard_settings(${PLUGIN_NAME})

# Symbols are hidden by default to reduce the chance of accidental conflicts
# between plugins. This should not be removed; any symbols that should be
# exported should be explicitly exported with the FLUTTER_PLUGIN_EXPORT macro.
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

# Source include directories and library dependencies. Add any plugin-specific
# dependencies here.
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
# Code shared with the Linux plugin (CLI output parsing).
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/../common")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)
target_link_libraries(${PLUGIN_NAME} PRIVATE Shell32 Ole32 Ws2_32 Iphlpapi Bcrypt)

# === TrustTunnel CLI client (the VPN engine, run as a child process) ===
# Same engine version as Android: ENGINE_VERSION in the repo root, and the
# archive must match its sha256 in ENGINE_SHA256 (tools/update_engine.sh).
# The public GitHub release is used - no GitHub Packages token needed.
include(FetchContent)

# The plugin is reached through .plugin_symlinks, so resolve the real path
# before walking up to the repo root.
get_filename_component(_VPN_PLUGIN_REAL_DIR "${CMAKE_CURRENT_SOURCE_DIR}" REALPATH)
if(NOT DEFINED TRUSTTUNNEL_ENGINE_ROOT)
  get_filename_component(TRUSTTUNNEL_ENGINE_ROOT "${_VPN_PLUGIN_REAL_DIR}/../../.." ABSOLUTE)
endif()
file(READ "${TRUSTTUNNEL_ENGINE_ROOT}/ENGINE_VERSION" TRUSTTUNNEL_ENGINE_VERSION)
string(STRIP "${TRUSTTUNNEL_ENGINE_VERSION}" TRUSTTUNNEL_ENGINE_VERSION)

if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8 OR CMAKE_SYSTEM_PROCESSOR MATCHES "ARM|aarch64")
  message(FATAL_ERROR "CatTunnel for Windows is x86_64 only (the CLI has no other Windows build)")
endif()
set(_TT_ARCHIVE "trusttunnel_client-v${TRUSTTUNNEL_ENGINE_VERSION}-windows-x86_64.zip")

file(STRINGS "${TRUSTTUNNEL_ENGINE_ROOT}/ENGINE_SHA256" _TT_HASH_LINE REGEX " ${_TT_ARCHIVE}$")
if(NOT _TT_HASH_LINE)
  message(FATAL_ERROR "No sha256 for ${_TT_ARCHIVE} in ENGINE_SHA256 - run tools/update_engine.sh")
endif()
string(REGEX MATCH "^[0-9a-f]+" _TT_SHA256 "${_TT_HASH_LINE}")

FetchContent_Declare(
  TrustTunnelCli
  URL "https://github.com/TrustTunnel/TrustTunnelClient/releases/download/v${TRUSTTUNNEL_ENGINE_VERSION}/${_TT_ARCHIVE}"
  URL_HASH SHA256=${_TT_SHA256}
)
FetchContent_MakeAvailable(TrustTunnelCli)

# CATTUNNEL_ENGINE_EXE (environment): our own trusttunnel_client.exe
# (tools/engine_native: upstream tag + 0001-anti-dpi-desync) instead of the
# release one; wintun.dll and the licenses still come from the release zip.
set(_TT_EXE "${trusttunnelcli_SOURCE_DIR}/trusttunnel_client.exe")
if(DEFINED ENV{CATTUNNEL_ENGINE_EXE})
  file(TO_CMAKE_PATH "$ENV{CATTUNNEL_ENGINE_EXE}" _TT_EXE)
  message(STATUS "TrustTunnel CLI: own build ${_TT_EXE}")
endif()
set(_TT_FILES
  "${_TT_EXE}"
  "${trusttunnelcli_SOURCE_DIR}/wintun.dll"
  "${trusttunnelcli_SOURCE_DIR}/WINTUN_LICENSE.txt"
)
foreach(_file ${_TT_FILES})
  if(NOT EXISTS "${_file}")
    message(FATAL_ERROR "${_file} is missing from ${_TT_ARCHIVE}")
  endif()
endforeach()
message(STATUS "TrustTunnel CLI ${TRUSTTUNNEL_ENGINE_VERSION}: ${trusttunnelcli_SOURCE_DIR}")

# The app-level install step copies these next to CatTunnel.exe; the CLI
# license (Apache-2.0) goes along under its own name.
configure_file("${trusttunnelcli_SOURCE_DIR}/LICENSE.txt"
  "${CMAKE_CURRENT_BINARY_DIR}/TRUSTTUNNEL_CLIENT_LICENSE.txt" COPYONLY)
set(vpn_plugin_bundled_libraries
  ${_TT_FILES}
  "${CMAKE_CURRENT_BINARY_DIR}/TRUSTTUNNEL_CLIENT_LICENSE.txt"
  PARENT_SCOPE
)

# === Tests ===
# Parsing of the CLI output (cli_output.h). Build and run from Visual Studio
# or ctest after configuring with -Dinclude_vpn_plugin_tests=ON.
if (${include_${PROJECT_NAME}_tests})
set(TEST_RUNNER "${PROJECT_NAME}_test")
enable_testing()

FetchContent_Declare(
  googletest
  URL https://github.com/google/googletest/archive/refs/tags/v1.15.2.zip
)
# Prevent overriding the parent project's compiler/linker settings
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
set(INSTALL_GTEST OFF CACHE BOOL "Disable installation of googletest" FORCE)
FetchContent_MakeAvailable(googletest)

add_executable(${TEST_RUNNER} ../common/test/cli_output_test.cpp)
apply_standard_settings(${TEST_RUNNER})
target_include_directories(${TEST_RUNNER} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../common")
target_link_libraries(${TEST_RUNNER} PRIVATE gtest_main)

include(GoogleTest)
gtest_discover_tests(${TEST_RUNNER})
endif()
