# - Try to find rpmalloc
# Once done this will define
#  RPMALLOC_FOUND - System has rpmalloc
#  RPMALLOC_INCLUDE_DIRS - The rpmalloc include directories
#  RPMALLOC_LIBRARIES - The libraries needed to use rpmalloc

if(NOT USE_BUNDLED_RPMALLOC)
  find_package(PkgConfig)
  if (PKG_CONFIG_FOUND)
    pkg_check_modules(PC_RPMALLOC QUIET rpmalloc)
  endif()
else()
  set(PC_RPMALLOC_INCLUDEDIR)
  set(PC_RPMALLOC_INCLUDE_DIRS)
  set(PC_RPMALLOC_LIBDIR)
  set(PC_RPMALLOC_LIBRARY_DIRS)
  set(LIMIT_SEARCH NO_DEFAULT_PATH)
endif()

set(RPMALLOC_DEFINITIONS ${PC_RPMALLOC_CFLAGS_OTHER})

find_path(RPMALLOC_INCLUDE_DIR rpmalloc/rpmalloc.h
          PATHS ${PC_RPMALLOC_INCLUDEDIR} ${PC_RPMALLOC_INCLUDE_DIRS}
          ${LIMIT_SEARCH})

# If we're asked to use static linkage, add librpmalloc.a as a preferred library name.
if(RPMALLOC_USE_STATIC)
  list(APPEND RPMALLOC_NAMES
    "${CMAKE_STATIC_LIBRARY_PREFIX}rpmallocwrap${CMAKE_STATIC_LIBRARY_SUFFIX}")
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
  list(INSERT RPMALLOC_NAMES 0
    "${CMAKE_STATIC_LIBRARY_PREFIX}rpmallocwrap${CMAKE_STATIC_LIBRARY_SUFFIX}")
endif()

list(APPEND RPMALLOC_NAMES rpmalloc)

find_library(RPMALLOC_LIBRARY NAMES ${RPMALLOC_NAMES}
  HINTS ${PC_RPMALLOC_LIBDIR} ${PC_RPMALLOC_LIBRARY_DIRS}
  ${LIMIT_SEARCH})

set(RPMALLOC_LIBRARIES ${RPMALLOC_LIBRARY})
set(RPMALLOC_INCLUDE_DIRS ${RPMALLOC_INCLUDE_DIR})

include(FindPackageHandleStandardArgs)
# handle the QUIETLY and REQUIRED arguments and set RPMALLOC_FOUND to TRUE
# if all listed variables are TRUE
find_package_handle_standard_args(RpMalloc DEFAULT_MSG
  RPMALLOC_LIBRARY RPMALLOC_INCLUDE_DIR)
find_package_handle_standard_args(RpMalloc DEFAULT_MSG
  RPMALLOC_INCLUDE_DIR)

mark_as_advanced(RPMALLOC_INCLUDE_DIR)
