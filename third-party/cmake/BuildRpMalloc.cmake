ExternalProject_Add(rpmalloc
  PREFIX ${DEPS_BUILD_DIR}
  URL ${RPMALLOC_URL}
  DOWNLOAD_DIR ${DEPS_DOWNLOAD_DIR}/rpmalloc
  DOWNLOAD_COMMAND ${CMAKE_COMMAND}
    -DPREFIX=${DEPS_BUILD_DIR}
    -DDOWNLOAD_DIR=${DEPS_DOWNLOAD_DIR}/rpmalloc
    -DURL=${RPMALLOC_URL}
    -DEXPECTED_SHA256=${RPMALLOC_SHA256}
    -DTARGET=rpmalloc
    -DUSE_EXISTING_SRC_DIR=${USE_EXISTING_SRC_DIR}
    -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/DownloadAndExtractFile.cmake
  PATCH_COMMAND sed -i "s|define ENABLE_UNLIMITED_CACHE    0|define ENABLE_UNLIMITED_CACHE    1|" ${DEPS_BUILD_DIR}/src/rpmalloc/rpmalloc/rpmalloc.c
  BUILD_IN_SOURCE 1
  CONFIGURE_COMMAND ${DEPS_BUILD_DIR}/src/rpmalloc/configure.py --toolchain clang --config release --arch x86-64
  BUILD_COMMAND sed -i "s| -Werror| -Werror -Wno-unused-macros -Wno-unguarded-availability-new -mmacosx-version-min=10.15|" build.ninja && ninja
  INSTALL_COMMAND mkdir -p ${DEPS_INSTALL_DIR}/include/rpmalloc &&
    cp ${DEPS_BUILD_DIR}/src/rpmalloc/rpmalloc/rpmalloc.h ${DEPS_INSTALL_DIR}/include/rpmalloc &&
    cp ${DEPS_BUILD_DIR}/src/rpmalloc/lib/macos/release/librpmallocwrap.a ${DEPS_INSTALL_DIR}/lib)

list(APPEND THIRD_PARTY_DEPS rpmalloc)
