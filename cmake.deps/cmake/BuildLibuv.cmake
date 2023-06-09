get_sha(libuv ${DEPS_IGNORE_SHA})
ExternalProject_Add(libuv
  URL ${LIBUV_URL}
  DOWNLOAD_DIR ${DEPS_DOWNLOAD_DIR}/libuv
  CMAKE_ARGS ${DEPS_CMAKE_ARGS}
    -D CMAKE_INSTALL_LIBDIR=lib
    -D BUILD_TESTING=OFF
    -D LIBUV_BUILD_SHARED=OFF
    -D UV_LINT_W4=OFF
  CMAKE_CACHE_ARGS ${DEPS_CMAKE_CACHE_ARGS}
  ${EXTERNALPROJECT_OPTIONS})
