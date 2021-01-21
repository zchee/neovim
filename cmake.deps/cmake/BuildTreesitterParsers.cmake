function(BuildTSParser LANG TS_URL TS_CMAKE_FILE)
  set(NAME treesitter-${LANG})
  if(USE_EXISTING_SRC_DIR)
    unset(TS_URL)
  endif()
  ExternalProject_Add(${NAME}
    URL ${TS_URL}
    DOWNLOAD_NO_PROGRESS TRUE
    DOWNLOAD_DIR ${DEPS_DOWNLOAD_DIR}/${NAME}
    PATCH_COMMAND ${CMAKE_COMMAND} -E copy
      ${CMAKE_CURRENT_SOURCE_DIR}/cmake/${TS_CMAKE_FILE}
      ${DEPS_BUILD_DIR}/src/${NAME}/CMakeLists.txt
    CMAKE_ARGS ${DEPS_CMAKE_ARGS}
      -D PARSERLANG=${LANG}
    CMAKE_CACHE_ARGS ${DEPS_CMAKE_CACHE_ARGS})
endfunction()

BuildTSParser(c ${TREESITTER_C_URL} TreesitterParserCMakeLists.txt)
BuildTSParser(lua ${TREESITTER_LUA_URL} TreesitterParserCMakeLists.txt)
BuildTSParser(vim ${TREESITTER_VIM_URL} TreesitterParserCMakeLists.txt)
BuildTSParser(help ${TREESITTER_HELP_URL} TreesitterParserCMakeLists.txt)
