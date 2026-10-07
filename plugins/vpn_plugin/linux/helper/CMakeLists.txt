# cattunnel-helper: the root part of CatTunnel for Linux (see ../HELPER.md).
# Standalone: cmake -S plugins/vpn_plugin/linux/helper -B build/helper -G Ninja
cmake_minimum_required(VERSION 3.16)
project(cattunnel_helper LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
add_compile_options(-Wall -Wextra -Werror -fstack-protector-strong)
# Distros set their own (Arch's makepkg: -D_FORTIFY_SOURCE=3 in CXXFLAGS);
# defining it twice is an error under -Werror.
if(NOT CMAKE_CXX_FLAGS MATCHES "_FORTIFY_SOURCE")
  add_compile_options(-D_FORTIFY_SOURCE=2)
endif()

file(READ "${CMAKE_CURRENT_SOURCE_DIR}/../../../../ENGINE_VERSION" ENGINE_VERSION)
string(STRIP "${ENGINE_VERSION}" ENGINE_VERSION)
add_compile_definitions(CATTUNNEL_ENGINE_VERSION="${ENGINE_VERSION}")

add_library(helper_core STATIC config_guard.cpp cli_runner.cpp physical_link.cpp system_dns.cpp)
target_include_directories(helper_core PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}" "${CMAKE_CURRENT_SOURCE_DIR}/../../common")
# The vendored headers aren't ours to keep warning-free.
target_include_directories(helper_core SYSTEM PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/third_party")

add_executable(cattunnel-helper main.cpp)
target_link_libraries(cattunnel-helper PRIVATE helper_core)
target_link_options(cattunnel-helper PRIVATE -Wl,-z,relro,-z,now -pie)
set_target_properties(cattunnel-helper PROPERTIES POSITION_INDEPENDENT_CODE ON)

option(HELPER_TESTS "Build the tests (fetches googletest)" ON)
if(HELPER_TESTS)
  include(FetchContent)
  FetchContent_Declare(googletest URL https://github.com/google/googletest/archive/refs/tags/v1.15.2.zip)
  set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)
  FetchContent_MakeAvailable(googletest)
  add_executable(helper_tests test/config_guard_test.cpp test/cli_runner_test.cpp test/system_dns_test.cpp ../../common/test/cli_output_test.cpp)
  target_link_libraries(helper_tests PRIVATE helper_core gtest_main)
  # The app's side of the protocol (../helper_client.cc), tested against a fake helper.
  add_executable(helper_client_tests ../test/helper_client_test.cc ../helper_client.cc)
  target_include_directories(helper_client_tests PRIVATE .. .)
  target_link_libraries(helper_client_tests PRIVATE gtest_main pthread)
  target_compile_definitions(helper_client_tests PRIVATE CATTUNNEL_HELPER_BIN="$<TARGET_FILE:cattunnel-helper>")
  add_dependencies(helper_client_tests cattunnel-helper)
  include(GoogleTest)
  gtest_discover_tests(helper_tests)
  gtest_discover_tests(helper_client_tests)
endif()
