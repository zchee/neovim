# This is not meant to be included by the top-level.
cmake_minimum_required (VERSION 3.10)
project(NVIM_DEPS C)

if(POLICY CMP0135)
  cmake_policy(SET CMP0135 NEW)
endif()

# Point CMake at any custom modules we may ship
list(APPEND CMAKE_MODULE_PATH "${PROJECT_SOURCE_DIR}/cmake" "${PROJECT_SOURCE_DIR}/../cmake")

include(CheckCCompilerFlag)
include(Util)

set(DEPS_CMAKE_ARGS
  -D CMAKE_C_COMPILER=${CMAKE_C_COMPILER}
  -D CMAKE_GENERATOR=${CMAKE_GENERATOR}
  -D CMAKE_GENERATOR_PLATFORM=${CMAKE_GENERATOR_PLATFORM}
  -D CMAKE_POSITION_INDEPENDENT_CODE=ON)

set(DEPS_CMAKE_CACHE_ARGS -DCMAKE_OSX_ARCHITECTURES:STRING=${CMAKE_OSX_ARCHITECTURES})

set_default_buildtype()

get_property(isMultiConfig GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(NOT isMultiConfig)
  list(APPEND DEPS_CMAKE_ARGS -D CMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE})
endif()

set(DEFAULT_MAKE_CFLAGS CFLAGS+=-g)

check_c_compiler_flag(-Og HAS_OG_FLAG)
if(HAS_OG_FLAG)
  set(DEFAULT_MAKE_CFLAGS CFLAGS+=-Og ${DEFAULT_MAKE_CFLAGS})
endif()

if(CMAKE_SYSTEM_NAME MATCHES "OpenBSD")
  # pkg-config 29.2 has a bug on OpenBSD which causes it to drop any paths that
  # *contain* system include paths. To avoid this, we prefix what would be
  # "/usr/include" as "/_usr/include".
  # This check is also performed in the root CMakeLists.txt
  # https://github.com/neovim/neovim/pull/14745#issuecomment-860201794
  set(DEPS_INSTALL_DIR "${CMAKE_BINARY_DIR}/_usr" CACHE PATH "Dependencies install directory.")
else()
  set(DEPS_INSTALL_DIR "${CMAKE_BINARY_DIR}/usr" CACHE PATH "Dependencies install directory.")
endif()

list(APPEND DEPS_CMAKE_ARGS -D CMAKE_INSTALL_PREFIX=${DEPS_INSTALL_DIR})

set(DEPS_BIN_DIR "${DEPS_INSTALL_DIR}/bin" CACHE PATH "Dependencies binary install directory.")
set(DEPS_LIB_DIR "${DEPS_INSTALL_DIR}/lib" CACHE PATH "Dependencies library install directory.")
set(DEPS_BUILD_DIR "${CMAKE_BINARY_DIR}/build" CACHE PATH "Dependencies build directory.")
set(DEPS_DOWNLOAD_DIR "${DEPS_BUILD_DIR}/downloads" CACHE PATH "Dependencies download directory.")

option(USE_BUNDLED "Use bundled dependencies." ON)

option(USE_BUNDLED_UNIBILIUM "Use the bundled unibilium." ${USE_BUNDLED})
option(USE_BUNDLED_LIBTERMKEY "Use the bundled libtermkey." ${USE_BUNDLED})
option(USE_BUNDLED_LIBVTERM "Use the bundled libvterm." ${USE_BUNDLED})
option(USE_BUNDLED_LIBUV "Use the bundled libuv." ${USE_BUNDLED})
option(USE_BUNDLED_MSGPACK "Use the bundled msgpack." ${USE_BUNDLED})
option(USE_BUNDLED_LUAJIT "Use the bundled version of luajit." ${USE_BUNDLED})
option(USE_BUNDLED_LUAROCKS "Use the bundled version of luarocks." ${USE_BUNDLED})
option(USE_BUNDLED_LUV "Use the bundled version of luv." ${USE_BUNDLED})
#XXX(tarruda): Lua is only used for debugging the functional test client, don't
# build it unless explicitly requested
option(USE_BUNDLED_LUA "Use the bundled version of lua." OFF)
option(USE_BUNDLED_TS_PARSERS "Use the bundled treesitter parsers." ${USE_BUNDLED})
option(USE_BUNDLED_TS "Use the bundled treesitter runtime." ${USE_BUNDLED})
option(USE_BUNDLED_JEMALLOC "Use the bundled jemalloc." ${USE_BUNDLED})

if(USE_BUNDLED AND MSVC)
  option(USE_BUNDLED_GETTEXT "Use the bundled version of gettext." ON)
  option(USE_BUNDLED_LIBICONV "Use the bundled version of libiconv." ON)
else()
  option(USE_BUNDLED_GETTEXT "Use the bundled version of gettext." OFF)
  option(USE_BUNDLED_LIBICONV "Use the bundled version of libiconv." OFF)
endif()

if(WIN32)
  option(USE_BUNDLED_NVIMQT "Bundle neovim-qt" ON)
endif()

option(USE_EXISTING_SRC_DIR "Skip download of deps sources in case of existing source directory." OFF)

find_package(Git)
if(NOT Git_FOUND)
  message(FATAL_ERROR "Git is required to apply patches.")
endif()

if(UNIX)
  find_program(MAKE_PRG NAMES gmake make)
  if(NOT MAKE_PRG)
    message(FATAL_ERROR "GNU Make is required to build the dependencies.")
  else()
    message(STATUS "Found GNU Make at ${MAKE_PRG}")
  endif()
endif()

# When using make, use the $(MAKE) variable to avoid warning about the job
# server.
if(CMAKE_GENERATOR MATCHES "Makefiles")
  set(MAKE_PRG "${MAKE}")
endif()

if(MINGW AND CMAKE_GENERATOR MATCHES "Ninja")
  find_program(MAKE_PRG NAMES mingw32-make)
  if(NOT MAKE_PRG)
    message(FATAL_ERROR "GNU Make for mingw32 is required to build the dependencies.")
  else()
    message(STATUS "Found GNU Make for mingw32: ${MAKE_PRG}")
  endif()
endif()

set(DEPS_C_COMPILER "${CMAKE_C_COMPILER}")

if(CMAKE_OSX_SYSROOT)
  set(DEPS_C_COMPILER "${DEPS_C_COMPILER} -isysroot${CMAKE_OSX_SYSROOT}")
endif()

if(CMAKE_OSX_ARCHITECTURES)
  # The LuaJIT build does not like being passed multiple `-arch` flags
  # so we handle a universal build the old-fashioned way.
  set(LUAJIT_C_COMPILER "${DEPS_C_COMPILER}")
  foreach(ARCH IN LISTS CMAKE_OSX_ARCHITECTURES)
    set(DEPS_C_COMPILER "${DEPS_C_COMPILER} -arch ${ARCH}")
  endforeach()
endif()

# If the macOS deployment target is not set manually (via $MACOSX_DEPLOYMENT_TARGET),
# fall back to local system version. Needs to be done here and in top-level CMakeLists.txt.
if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
  if(NOT CMAKE_OSX_DEPLOYMENT_TARGET)
    execute_process(COMMAND sw_vers -productVersion
                    OUTPUT_VARIABLE MACOS_VERSION
                    OUTPUT_STRIP_TRAILING_WHITESPACE)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "${MACOS_VERSION}")
  endif()
  message(STATUS "Using deployment target ${CMAKE_OSX_DEPLOYMENT_TARGET}")
endif()

include(ExternalProject)
set_directory_properties(PROPERTIES EP_PREFIX "${DEPS_BUILD_DIR}")

set(LIBUV_URL https://github.com/libuv/libuv/archive/v1.x.tar.gz)
set(LIBUV_SHA256 SKIP)

set(MSGPACK_URL https://github.com/msgpack/msgpack-c/archive/c_master.tar.gz)
set(MSGPACK_SHA256 SKIP)

# https://github.com/LuaJIT/LuaJIT/tree/v2.1
set(LUAJIT_URL https://github.com/LuaJIT/LuaJIT/archive/v2.1.tar.gz)
set(LUAJIT_SHA256 SKIP)

set(LUA_URL https://www.lua.org/ftp/lua-5.1.5.tar.gz)
set(LUA_SHA256 2640fc56a795f29d28ef15e13c34a47e223960b0240e8cb0a82d9b0738695333)

set(LUAROCKS_URL https://github.com/luarocks/luarocks/archive/master.tar.gz)
set(LUAROCKS_SHA256 SKIP)

set(UNIBILIUM_URL https://github.com/neovim/unibilium/archive/v2.1.1.tar.gz)
set(UNIBILIUM_SHA256 SKIP)

set(LIBTERMKEY_URL https://www.leonerd.org.uk/code/libtermkey/libtermkey-0.22.tar.gz)
set(LIBTERMKEY_SHA256 6945bd3c4aaa83da83d80a045c5563da4edd7d0374c62c0d35aec09eb3014600)

set(LIBVTERM_URL https://www.leonerd.org.uk/code/libvterm/libvterm-0.3.1.tar.gz)
set(LIBVTERM_SHA256 25a8ad9c15485368dfd0a8a9dca1aec8fea5c27da3fa74ec518d5d3787f0c397)

set(JEMALLOC_URL https://github.com/jemalloc/jemalloc/archive/dev.tar.gz)
set(JEMALLOC_SHA256 SKIP)

set(LUV_VERSION 1.44.2-1)
set(LUV_URL https://github.com/luvit/luv/archive/master.tar.gz)
set(LUV_SHA256 SKIP)

set(LUA_COMPAT53_URL https://github.com/keplerproject/lua-compat-5.3/archive/master.tar.gz)
set(LUA_COMPAT53_SHA256 SKIP)

# cat.exe curl.exe curl-ca-bundle.crt diff.exe tee.exe xxd.exe
set(WINTOOLS_URL https://github.com/neovim/deps/raw/c1e7dd8de9e1b18d11dcfa0a192cd029262e5303/opt/win32tools.zip)
set(WINTOOLS_SHA256 3c4c490a3d392ceeb1347cb77cc821a31900b688a2189276d3a1131a3f21daf1)

set(WINGUI_URL https://github.com/equalsraf/neovim-qt/releases/download/v0.2.17/neovim-qt.zip)
set(WINGUI_SHA256 502e386eef677c2c2e0c11d8cbb27f3e12b4d96818369417e8da4129c4580c25)

set(WIN32YANK_X86_64_URL https://github.com/equalsraf/win32yank/releases/download/v0.0.4/win32yank-x64.zip)
set(WIN32YANK_X86_64_SHA256 33a747a92da60fb65e668edbf7661d3d902411a2d545fe9dc08623cecd142a20)

set(GETTEXT_URL https://ftp.gnu.org/pub/gnu/gettext/gettext-0.21.1.tar.gz)
set(GETTEXT_SHA256 SKIP)

set(LIBICONV_URL https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.17.tar.gz)
set(LIBICONV_SHA256 ccf536620a45458d26ba83887a983b96827001e92a13847b45e4925cc8913178)

set(TREESITTER_C_URL https://github.com/tree-sitter/tree-sitter-c/archive/master.tar.gz)
set(TREESITTER_C_SHA256 SKIP)

set(TREESITTER_LUA_URL https://github.com/MunifTanjim/tree-sitter-lua/archive/main.tar.gz)
set(TREESITTER_LUA_SHA256 SKIP)

set(TREESITTER_VIM_URL https://github.com/vigoux/tree-sitter-viml/archive/master.tar.gz)
set(TREESITTER_VIM_SHA256 SKIP)

set(TREESITTER_HELP_URL https://github.com/neovim/tree-sitter-vimdoc/archive/master.tar.gz)
set(TREESITTER_HELP_SHA256 SKIP)

set(TREESITTER_URL https://github.com/tree-sitter/tree-sitter/archive/master.tar.gz)
set(TREESITTER_SHA256 SKIP)

if(USE_BUNDLED_UNIBILIUM)
  include(BuildUnibilium)
endif()

if(USE_BUNDLED_LIBTERMKEY)
  include(BuildLibtermkey)
  if(USE_BUNDLED_UNIBILIUM)
    add_dependencies(libtermkey unibilium)
  endif()
endif()

if(USE_BUNDLED_LIBVTERM)
  include(BuildLibvterm)
endif()

if(USE_BUNDLED_LIBUV)
  include(BuildLibuv)
endif()

if(USE_BUNDLED_MSGPACK)
  include(BuildMsgpack)
endif()

if(USE_BUNDLED_LUAJIT)
  include(BuildLuajit)
endif()

if(USE_BUNDLED_LUA)
  include(BuildLua)
endif()

if(USE_BUNDLED_LUAROCKS)
  include(BuildLuarocks)
endif()

if(USE_BUNDLED_JEMALLOC)
  include(BuildJeMalloc)
endif()

if(USE_BUNDLED_LUV)
  include(BuildLuv)
endif()

if(USE_BUNDLED_GETTEXT)
  include(BuildGettext)
endif()

if(USE_BUNDLED_LIBICONV)
  include(BuildLibiconv)
endif()

if(USE_BUNDLED_TS_PARSERS)
  include(BuildTreesitterParsers)
endif()

if(USE_BUNDLED_TS)
  include(BuildTreesitter)
endif()

if(WIN32)
  include(GetBinaryDeps)

  GetBinaryDep(TARGET wintools
    INSTALL_COMMAND ${CMAKE_COMMAND} -E copy_directory . ${DEPS_INSTALL_DIR}/bin)

  if(USE_BUNDLED_NVIMQT)
    GetBinaryDep(TARGET wingui
      INSTALL_COMMAND ${CMAKE_COMMAND} -E copy_directory bin ${DEPS_INSTALL_DIR}/bin
      COMMAND ${CMAKE_COMMAND} -E copy_directory share ${DEPS_INSTALL_DIR}/share)
  endif()

  GetBinaryDep(TARGET win32yank_X86_64
    INSTALL_COMMAND ${CMAKE_COMMAND} -E copy win32yank.exe ${DEPS_INSTALL_DIR}/bin)
endif()
