find_path2(MIMALLOC_INCLUDE_DIR mimalloc.h)
find_library2(MIMALLOC_LIBRARY NAMES mimalloc)

find_package_handle_standard_args(Mimalloc DEFAULT_MSG
  MIMALLOC_LIBRARY MIMALLOC_INCLUDE_DIR)
mark_as_advanced(MIMALLOC_LIBRARY MIMALLOC_INCLUDE_DIR)

add_library(mimalloc INTERFACE)
target_include_directories(mimalloc SYSTEM BEFORE INTERFACE ${MIMALLOC_INCLUDE_DIR})
target_link_libraries(mimalloc INTERFACE ${MIMALLOC_LIBRARY})
