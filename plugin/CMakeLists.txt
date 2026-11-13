cmake_minimum_required(VERSION 3.20)
# The plugin must be universal on macOS; this has to be set before project().
if(APPLE AND XPLANE_SDK AND NOT CMAKE_OSX_ARCHITECTURES)
  set(CMAKE_OSX_ARCHITECTURES "x86_64;arm64" CACHE STRING "")
endif()
project(flightsim_aide_plugin C CXX)

# The static libraries are linked into a shared .xpl; Linux needs -fPIC for that.
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Companion plugin. The build has two parts. The core is a static library with no
# XPLM dependency, its tests and core_test_server. The XPLM shell
# is added on top and needs -DXPLANE_SDK.
#
#   cmake -S plugin -B plugin/build -DBUILD_TESTS=ON
#   cmake --build plugin/build --config Release
#   ctest --test-dir plugin/build -C Release --output-on-failure

option(BUILD_TESTS "Build core_tests and core_test_server" ON)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

file(GLOB CORE_SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/src/core/*.cpp")
# CivetWeb: SSL, CGI and file serving off, WebSocket on (D-36).
add_library(civetweb STATIC third_party/civetweb/civetweb.c)
target_include_directories(civetweb PUBLIC third_party/civetweb)
target_compile_definitions(civetweb PUBLIC NO_SSL NO_CGI NO_FILES NO_CACHING USE_WEBSOCKET USE_IPV6=0)
if(WIN32)
  target_compile_definitions(civetweb PRIVATE _CRT_SECURE_NO_WARNINGS)
  target_link_libraries(civetweb PUBLIC ws2_32)
  if(MSVC)
    target_compile_options(civetweb PRIVATE /utf-8 /w)
  endif()
else()
  target_link_libraries(civetweb PUBLIC pthread)
  target_compile_options(civetweb PRIVATE -w)
endif()

add_library(flightsim_aide_core STATIC ${CORE_SOURCES})
target_link_libraries(flightsim_aide_core PUBLIC civetweb)
target_include_directories(flightsim_aide_core PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src/core")
if(MSVC)
  target_compile_options(flightsim_aide_core PRIVATE /W4 /utf-8)
else()
  target_compile_options(flightsim_aide_core PRIVATE -Wall -Wextra)
endif()

# File access lives outside core/ (the isolation test bans fopen there).
file(GLOB PLATFORM_SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/src/platform/*.cpp")
add_library(flightsim_aide_platform STATIC ${PLATFORM_SOURCES})
target_link_libraries(flightsim_aide_platform PUBLIC flightsim_aide_core)
target_include_directories(flightsim_aide_platform PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src/platform")
if(MSVC)
  target_compile_options(flightsim_aide_platform PRIVATE /W4 /utf-8)
else()
  target_compile_options(flightsim_aide_platform PRIVATE -Wall -Wextra)
endif()

if(BUILD_TESTS)
  enable_testing()
  file(GLOB TEST_SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/test/*.cpp")
  add_executable(core_tests ${TEST_SOURCES})
  target_link_libraries(core_tests PRIVATE flightsim_aide_core flightsim_aide_platform)
  target_include_directories(core_tests SYSTEM PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/third_party/doctest")
  # Golden fixtures are shared with the Dart tests.
  target_compile_definitions(core_tests PRIVATE
    FIXTURE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/../testing/fixtures/protocol")
  add_test(NAME core_tests COMMAND core_tests)

  # The core on its own with scripted data: contract runs, device tests.
  add_executable(core_test_server test_server/core_test_server.cpp)
  target_link_libraries(core_test_server PRIVATE flightsim_aide_core)
  target_compile_definitions(core_test_server PRIVATE
    FIXTURE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/../testing/fixtures/protocol")
  add_test(NAME core_isolation
    COMMAND ${CMAKE_COMMAND} -DCORE_DIR=${CMAKE_CURRENT_SOURCE_DIR}/src/core
            -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/check_core_isolation.cmake)
  add_test(NAME shared_server_start
    COMMAND ${CMAKE_COMMAND} -DSHELL=${CMAKE_CURRENT_SOURCE_DIR}/src/xplane/plugin.cpp
            -DTEST_SERVER=${CMAKE_CURRENT_SOURCE_DIR}/test_server/core_test_server.cpp
            -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/check_shared_start.cmake)
endif()

# The X-Plane shell: the only target that includes XPLM headers (src/xplane).
# Needs the SDK: -DXPLANE_SDK=<folder with CHeaders/ and Libraries/>.
#   cmake -S plugin -B plugin/build-xp -DXPLANE_SDK="external/XPSDK430/SDK"
set(XPLANE_SDK "" CACHE PATH "Folder containing CHeaders/ and Libraries/ (the unpacked X-Plane SDK)")
if(XPLANE_SDK)
  if(NOT EXISTS "${XPLANE_SDK}/CHeaders/XPLM/XPLMDefs.h")
    message(FATAL_ERROR "XPLANE_SDK must contain CHeaders/XPLM/XPLMDefs.h")
  endif()
  file(GLOB SHELL_SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/src/xplane/*.cpp")
  add_library(flightsim_aide SHARED ${SHELL_SOURCES})
  set_target_properties(flightsim_aide PROPERTIES PREFIX "" SUFFIX ".xpl")
  target_link_libraries(flightsim_aide PRIVATE flightsim_aide_core flightsim_aide_platform)
  target_include_directories(flightsim_aide PRIVATE
    "${XPLANE_SDK}/CHeaders/XPLM" "${CMAKE_CURRENT_SOURCE_DIR}/src/xplane")
  # XPLM200 to XPLM301 only, and the plugin is tested on X-Plane 12 only (D-46).
  target_compile_definitions(flightsim_aide PRIVATE XPLM200=1 XPLM210=1 XPLM300=1 XPLM301=1)
  if(WIN32)
    target_compile_definitions(flightsim_aide PRIVATE IBM=1 _CRT_SECURE_NO_WARNINGS)
    target_compile_options(flightsim_aide PRIVATE /W4 /utf-8)
    target_link_libraries(flightsim_aide PRIVATE "${XPLANE_SDK}/Libraries/Win/XPLM_64.lib")
  elseif(APPLE)
    target_compile_definitions(flightsim_aide PRIVATE APL=1)
    target_compile_options(flightsim_aide PRIVATE -Wall -Wextra)
    target_link_options(flightsim_aide PRIVATE -undefined dynamic_lookup)
  else()
    target_compile_definitions(flightsim_aide PRIVATE LIN=1)
    target_compile_options(flightsim_aide PRIVATE -Wall -Wextra -fvisibility=hidden)
  endif()

  # Optional install after the build: -DXPLANE_PLUGINS=<X-Plane>/Resources/plugins.
  # Layout A (confirmed on XP12): flightsim_aide/64/<win|mac|lin>.xpl.
  # Layout B: flightsim_aide/<win_x64|mac_x64|lin_x64>/flightsim_aide.xpl.
  set(XPLANE_PLUGINS "" CACHE PATH "X-Plane Resources/plugins folder to copy the plugin into (optional)")
  set(PLUGIN_LAYOUT "A" CACHE STRING "A or B")
  if(XPLANE_PLUGINS)
    if(WIN32)
      set(_os win)
    elseif(APPLE)
      set(_os mac)
    else()
      set(_os lin)
    endif()
    if(PLUGIN_LAYOUT STREQUAL "B")
      set(_dest "${XPLANE_PLUGINS}/flightsim_aide/${_os}_x64")
      set(_name "flightsim_aide.xpl")
    else()
      set(_dest "${XPLANE_PLUGINS}/flightsim_aide/64")
      set(_name "${_os}.xpl")
    endif()
    add_custom_command(TARGET flightsim_aide POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E make_directory "${_dest}"
      COMMAND ${CMAKE_COMMAND} -E copy "$<TARGET_FILE:flightsim_aide>" "${_dest}/${_name}"
      COMMENT "Installing to ${_dest}/${_name}")
  endif()
endif()
