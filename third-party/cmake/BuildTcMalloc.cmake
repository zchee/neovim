ExternalProject_Add(tcmalloc
  PREFIX ${DEPS_BUILD_DIR}
  URL ${TCMALLOC_URL}
  DOWNLOAD_DIR ${DEPS_DOWNLOAD_DIR}/tcmalloc
  DOWNLOAD_COMMAND ${CMAKE_COMMAND}
    -DPREFIX=${DEPS_BUILD_DIR}
    -DDOWNLOAD_DIR=${DEPS_DOWNLOAD_DIR}/tcmalloc
    -DURL=${TCMALLOC_URL}
    -DEXPECTED_SHA256=${TCMALLOC_SHA256}
    -DTARGET=tcmalloc
    -DUSE_EXISTING_SRC_DIR=${USE_EXISTING_SRC_DIR}
    -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/DownloadAndExtractFile.cmake
  BUILD_IN_SOURCE 1
  CONFIGURE_COMMAND ${DEPS_BUILD_DIR}/src/tcmalloc/autogen.sh &&
     ${DEPS_BUILD_DIR}/src/tcmalloc/configure
     CC=${DEPS_C_COMPILER} CXX=${DEPS_CXX_COMPILER}
     CFLAGS=${CMAKE_C_FLAGS} CXXFLAGS=${CMAKE_C_FLAGS}
     --enable-dynamic-sized-delete-support --enable-emergency-malloc
     --enable-frame-pointers --enable-libunwind --enable-sized-delete
     --enable-stacktrace-via-backtrace
     --with-tcmalloc-alignment=16 --with-tcmalloc-pagesize=64K
     --disable-cpu-profiler --disable-heap-profiler --disable-heap-checker
     --disable-debugalloc --disable-dependency-tracking
     --prefix=${DEPS_INSTALL_DIR}
  BUILD_COMMAND ""
  INSTALL_COMMAND ${MAKE_PRG} install-libLTLIBRARIES install-perftoolsincludeHEADERS)

list(APPEND THIRD_PARTY_DEPS tcmalloc)
