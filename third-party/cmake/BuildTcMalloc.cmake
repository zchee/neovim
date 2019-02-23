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
  CONFIGURE_COMMAND autoreconf -fiv &&
     ${DEPS_BUILD_DIR}/src/tcmalloc/configure
     CC=${DEPS_C_COMPILER} CXX=${DEPS_CXX_COMPILER}
     "CFLAGS=${CMAKE_C_FLAGS} -march=native -Ofast -fno-omit-frame-pointer -Wno-unused-command-line-argument"
     "CXXFLAGS=${CMAKE_C_FLAGS} -march=native -Ofast -std=c++17 -stdlib=libc++ -fno-omit-frame-pointer -Wno-deprecated-declarations -Wno-unused-command-line-argument -Wno-mismatched-new-delete -Wno-unused-private-field -Wno-unused-function"
     --disable-cpu-profiler --disable-heap-profiler --disable-heap-checker --disable-debugalloc
     --enable-minimal --disable-shared --disable-deprecated-pprof
     --enable-frame-pointers
     --with-tcmalloc-pagesize=256 --with-tcmalloc-alignment=8
     --enable-aggressive-decommit-by-default
     --enable-dynamic-sized-delete-support
     --prefix=${DEPS_INSTALL_DIR}
  BUILD_COMMAND ""
  INSTALL_COMMAND ${MAKE_PRG} install-libLTLIBRARIES install-data)

list(APPEND THIRD_PARTY_DEPS tcmalloc)
