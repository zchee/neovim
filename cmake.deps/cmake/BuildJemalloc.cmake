if(WIN32)
  message(STATUS "Building mimalloc in Windows is not supported (skipping)")
  return()
endif()

ExternalProject_Add(jemalloc
  URL ${JEMALLOC_URL}
  DOWNLOAD_NO_PROGRESS TRUE
  DOWNLOAD_DIR ${DEPS_DOWNLOAD_DIR}/jemalloc
  BUILD_IN_SOURCE 1
  CONFIGURE_COMMAND ${DEPS_BUILD_DIR}/src/jemalloc/autogen.sh &&
    ${DEPS_BUILD_DIR}/src/jemalloc/configure CC=${DEPS_C_COMPILER} --prefix=${DEPS_INSTALL_DIR} --enable-static --enable-lazy-lock
  BUILD_COMMAND ""
  INSTALL_COMMAND ${MAKE_PRG} install_include install_lib_static)

list(APPEND THIRD_PARTY_DEPS jemalloc)
