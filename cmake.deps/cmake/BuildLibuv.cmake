if(USE_EXISTING_SRC_DIR)
  unset(LIBUV_URL)
endif()
ExternalProject_Add(libuv
  URL ${LIBUV_URL}
  DOWNLOAD_NO_PROGRESS TRUE
  CMAKE_ARGS
    -DCMAKE_INSTALL_PREFIX=${DEPS_INSTALL_DIR}
    -DCMAKE_INSTALL_LIBDIR=lib
    -DBUILD_TESTING=OFF
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    -DLIBUV_BUILD_SHARED=OFF
    ${BUILD_TYPE_STRING}
  CMAKE_CACHE_ARGS
    -DCMAKE_OSX_ARCHITECTURES:STRING=${CMAKE_OSX_ARCHITECTURES}
  DOWNLOAD_DIR ${DEPS_DOWNLOAD_DIR}/libuv)

list(APPEND THIRD_PARTY_DEPS libuv)
