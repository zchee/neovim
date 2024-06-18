find_path2(MIMALLOC_INCLUDE_DIR mimalloc.h
          PATH_SUFFIXES mimalloc)

list(APPEND MIMALLOC_NAMES mimalloc)

find_library2(MIMALLOC_LIBRARY NAMES ${MIMALLOC_NAMES})

find_package_handle_standard_args(Mimalloc DEFAULT_MSG
                                  MIMALLOC_LIBRARY MIMALLOC_INCLUDE_DIR)

mark_as_advanced(MIMALLOC_INCLUDE_DIR MIMALLOC_LIBRARY)
