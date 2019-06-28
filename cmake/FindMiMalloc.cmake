# # - Try to find mimalloc
# # Once done this will define
# #  MIMALLOC_FOUND - System has mimalloc
# #  MIMALLOC_INCLUDE_DIRS - The mimalloc include directories
# #  MIMALLOC_LIBRARIES - The libraries needed to use mimalloc
# 
# find_path(MIMALLOC_INCLUDE_DIR mimalloc.h
#           PATHS ${PC_MIMALLOC_INCLUDEDIR} ${PC_MIMALLOC_INCLUDE_DIRS}
#           ${LIMIT_SEARCH})
# 
# list(APPEND MIMALLOC_NAMES mimalloc)
# 
# # find_library(MIMALLOC_LIBRARY NAMES ${MIMALLOC_NAMES}
# #   HINTS ${PC_MIMALLOC_LIBDIR} ${PC_MIMALLOC_LIBRARY_DIRS}
# #   ${LIMIT_SEARCH})
# # lib/mimalloc-1.7/
# find_library(MIMALLOC_LIBRARY NAMES mimalloc.o}
#   # Check each directory for all names to avoid using headers/libraries from
#   # different places.
#   NAMES_PER_DIR)
# 
# set(MIMALLOC_LIBRARIES ${MIMALLOC_LIBRARY})
# # set(MIMALLOC_INCLUDE_DIRS ${MIMALLOC_INCLUDE_DIR})
# 
# include(FindPackageHandleStandardArgs)
# # handle the QUIETLY and REQUIRED arguments and set MIMALLOC_FOUND to TRUE
# # if all listed variables are TRUE
# find_package_handle_standard_args(MiMalloc DEFAULT_MSG
#   MIMALLOC_LIBRARY)
# 
# mark_as_advanced(MIMALLOC_LIBRARY)
# 
# include(LibFindMacros)
# 
# libfind_pkg_detect(Mimalloc mimalloc FIND_PATH mimalloc.o FIND_LIBRARY mimalloc)
# libfind_process(Mimalloc)

# - Try to find mimalloc
# Once done this will define
#  MIMALLOC_FOUND - System has mimalloc
#  MIMALLOC_INCLUDE_DIRS - The mimalloc include directories
#  MIMALLOC_LIBRARIES - The libraries needed to use mimalloc

# if(NOT USE_BUNDLED_MIMALLOC)
#   find_package(PkgConfig)
#   if (PKG_CONFIG_FOUND)
#     pkg_check_modules(PC_MIMALLOC QUIET mimalloc)
#   endif()
# else()
#   set(PC_MIMALLOC_INCLUDEDIR)
#   set(PC_MIMALLOC_INCLUDE_DIRS)
#   set(PC_MIMALLOC_LIBDIR)
#   set(PC_MIMALLOC_LIBRARY_DIRS)
#   set(LIMIT_SEARCH NO_DEFAULT_PATH)
# endif()
# 
# set(MIMALLOC_DEFINITIONS ${PC_MIMALLOC_CFLAGS_OTHER})
# 
# find_path(MIMALLOC_INCLUDE_DIR mimalloc.h
#           PATHS ${PC_MIMALLOC_INCLUDEDIR} ${PC_MIMALLOC_INCLUDE_DIRS}
#           ${LIMIT_SEARCH})

# If we're asked to use static linkage, add libmimalloc.a as a preferred library name.
# if(MIMALLOC_USE_STATIC)
#   list(APPEND MIMALLOC_NAMES
#     "${CMAKE_STATIC_LIBRARY_PREFIX}mimalloc${CMAKE_STATIC_LIBRARY_SUFFIX}")
# elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
#   list(INSERT MIMALLOC_NAMES 0
#     "${CMAKE_STATIC_LIBRARY_PREFIX}mimalloc${CMAKE_STATIC_LIBRARY_SUFFIX}")
# endif()

# list(APPEND MIMALLOC_NAMES mimalloc)

# find_library(MIMALLOC_LIBRARY NAMES ${MIMALLOC_NAMES}
#   HINTS ${PC_MIMALLOC_LIBDIR} ${PC_MIMALLOC_LIBRARY_DIRS}
#   ${LIMIT_SEARCH})

# set(MIMALLOC_LIBRARIES ${MIMALLOC_LIBRARY})
# set(MIMALLOC_INCLUDE_DIRS ${MIMALLOC_INCLUDE_DIR})

# include(FindPackageHandleStandardArgs)
# handle the QUIETLY and REQUIRED arguments and set MIMALLOC_FOUND to TRUE
# if all listed variables are TRUE
# find_package_handle_standard_args(MiMalloc DEFAULT_MSG
#   MIMALLOC_LIBRARY MIMALLOC_INCLUDE_DIR)
# find_package_handle_standard_args(MiMalloc DEFAULT_MSG
#   MIMALLOC_INCLUDE_DIR)

# mark_as_advanced(MIMALLOC_INCLUDE_DIR)
