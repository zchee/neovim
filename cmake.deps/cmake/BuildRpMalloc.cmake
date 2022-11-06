if(WIN32)
  message(STATUS "Building rpmalloc in Windows is not supported (skipping)")
  return()
endif()

ExternalProject_Add(rpmalloc
  URL ${RPMALLOC_URL}
  DOWNLOAD_NO_PROGRESS TRUE
  DOWNLOAD_DIR ${DEPS_DOWNLOAD_DIR}/rpmalloc
  PATCH_COMMAND sed -i "s|define ENABLE_UNLIMITED_CACHE    0|define ENABLE_UNLIMITED_CACHE    1|" ${DEPS_BUILD_DIR}/src/rpmalloc/rpmalloc/rpmalloc.c
  BUILD_IN_SOURCE 1
  CONFIGURE_COMMAND ${DEPS_BUILD_DIR}/src/rpmalloc/configure.py --toolchain clang --config release --arch x86-64
  BUILD_COMMAND sed -i "s| -Werror| -Werror -Wno-unused-macros -Wno-unguarded-availability-new -mmacosx-version-min=10.15|" build.ninja && ninja
  INSTALL_COMMAND mkdir -p ${DEPS_INSTALL_DIR}/include/rpmalloc &&
    cp ${DEPS_BUILD_DIR}/src/rpmalloc/rpmalloc/rpmalloc.h ${DEPS_INSTALL_DIR}/include/rpmalloc &&
    cp ${DEPS_BUILD_DIR}/src/rpmalloc/lib/macos/release/librpmallocwrap.a ${DEPS_INSTALL_DIR}/lib)

list(APPEND THIRD_PARTY_DEPS rpmalloc)
