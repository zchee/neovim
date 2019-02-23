# - Try to find tcmalloc
# Once done this will define
#  TCMALLOC_FOUND - System has tcmalloc
#  TCMALLOC_INCLUDE_DIRS - The tcmalloc include directories
#  TCMALLOC_LIBRARIES - The libraries needed to use tcmalloc

if(NOT TCMALLOC_USE_BUNDLED)
  find_package(PkgConfig)
  if (PKG_CONFIG_FOUND)
    pkg_check_modules(PC_TCMALLOC QUIET tcmalloc)
  endif()
else()
  set(PC_TCMALLOC_INCLUDEDIR)
  set(PC_TCMALLOC_INCLUDE_DIRS)
  set(PC_TCMALLOC_LIBDIR)
  set(PC_TCMALLOC_LIBRARY_DIRS)
  set(LIMIT_SEARCH NO_DEFAULT_PATH)
endif()

set(TCMALLOC_DEFINITIONS ${PC_TCMALLOC_CFLAGS_OTHER})

find_path(TCMALLOC_INCLUDE_DIR gperftools/tcmalloc.h
          PATHS ${PC_TCMALLOC_INCLUDEDIR} ${PC_TCMALLOC_INCLUDE_DIRS}
          ${LIMIT_SEARCH})

# If we're asked to use static linkage, add libtcmalloc.a as a preferred library name.
if(TCMALLOC_USE_STATIC)
  list(APPEND TCMALLOC_NAMES
    "${CMAKE_STATIC_LIBRARY_PREFIX}tcmalloc_minimal${CMAKE_STATIC_LIBRARY_SUFFIX} -lc++")
endif()

list(APPEND TCMALLOC_NAMES tcmalloc_minimal)

find_library(TCMALLOC_LIBRARY NAMES ${TCMALLOC_NAMES}
  HINTS ${PC_TCMALLOC_LIBDIR} ${PC_TCMALLOC_LIBRARY_DIRS}
  ${LIMIT_SEARCH})

set(TCMALLOC_LIBRARIES ${TCMALLOC_LIBRARY})
set(TCMALLOC_INCLUDE_DIRS ${TCMALLOC_INCLUDE_DIR})

include(FindPackageHandleStandardArgs)
# handle the QUIETLY and REQUIRED arguments and set TCMALLOC_FOUND to TRUE
# if all listed variables are TRUE
find_package_handle_standard_args(TcMalloc DEFAULT_MSG
  TCMALLOC_LIBRARY TCMALLOC_INCLUDE_DIR)

mark_as_advanced(TCMALLOC_INCLUDE_DIR TCMALLOC_LIBRARY)
