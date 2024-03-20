find_library2(HOARD_LIBRARY NAMES hoard)

find_package_handle_standard_args(Hoard
  REQUIRED_VARS HOARD_LIBRARY)

add_library(Hoard INTERFACE)
target_link_libraries(Hoard INTERFACE ${HOARD_LIBRARY})

mark_as_advanced(HOARD_LIBRARY)
