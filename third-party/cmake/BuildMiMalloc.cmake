ExternalProject_Add(mimalloc
  PREFIX ${DEPS_BUILD_DIR}
  URL ${MIMALLOC_URL}
  DOWNLOAD_DIR ${DEPS_DOWNLOAD_DIR}/mimalloc
  DOWNLOAD_COMMAND ${CMAKE_COMMAND}
    -DPREFIX=${DEPS_BUILD_DIR}
    -DDOWNLOAD_DIR=${DEPS_DOWNLOAD_DIR}/mimalloc
    -DURL=${MIMALLOC_URL}
    -DEXPECTED_SHA256=${MIMALLOC_SHA256}
    -DTARGET=mimalloc
    -DUSE_EXISTING_SRC_DIR=${USE_EXISTING_SRC_DIR}
    -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/DownloadAndExtractFile.cmake
  # PATCH_COMMAND sed -i "s|list(APPEND mi_cflags -Wall -Wextra -Wno-unknown-pragmas -ftls-model=initial-exec)|list(APPEND mi_cflags -Wno-unknown-pragmas -ftls-model=initial-exec)|" ${DEPS_BUILD_DIR}/src/mimalloc/CMakeLists.txt
  BUILD_IN_SOURCE 1
  CONFIGURE_COMMAND ${CMAKE_COMMAND} ${DEPS_BUILD_DIR}/src/mimalloc
    -DMI_BUILD_OBJECT:BOOL=ON
    -DMI_BUILD_SHARED:BOOL=OFF
    -DMI_BUILD_STATIC:BOOL=OFF
    -DMI_BUILD_TESTS:BOOL=OFF
    -DMI_OVERRIDE=ON
    -DMI_INTERPOSE=ON
    -DMI_OSX_ZONE:BOOL=ON
    # -DMI_SEE_ASM:BOOL=OFF
    # -DMIMALLOC_SHOW_STATS=1
    # -DMIMALLOC_VERBOSE=1
    -DCMAKE_INSTALL_PREFIX=${DEPS_INSTALL_DIR}
    -DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}
    -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
    # "-DCMAKE_C_FLAGS:STRING=${CMAKE_C_COMPILER_ARG1} -fPIC -O3 -DNDEBUG -Wno-unused-function -Wno-unused-parameter -Wno-incompatible-pointer-types -Wno-implicit-function-declaration"
    -DCMAKE_GENERATOR=${CMAKE_GENERATOR}
  BUILD_COMMAND ${CMAKE_COMMAND} --build . --target all --config ${CMAKE_BUILD_TYPE}
  INSTALL_COMMAND ${CMAKE_COMMAND} --build . --target install --config ${CMAKE_BUILD_TYPE} &&
    cp ${DEPS_INSTALL_DIR}/lib/mimalloc-2.0/mimalloc.o ${DEPS_INSTALL_DIR}/lib/mimalloc.o)
    # cp ${DEPS_INSTALL_DIR}/lib/mimalloc-2.0/include/mimalloc.h ${DEPS_INSTALL_DIR}/include/mimalloc.h)
  # INSTALL_COMMAND ${CMAKE_COMMAND} --build . --target install --config ${CMAKE_BUILD_TYPE})

list(APPEND THIRD_PARTY_DEPS mimalloc)
