set(UNIBILIUM_CMAKE_ARGS
  -D BUILD_MAN_PAGES=OFF
  -D BUILD_TESTS=OFF
  -D BUILD_TOOLS=OFF)

# unibilium bakes its terminfo search path in at build time, taking whatever
# `ncurses*-config --terminfo-dirs` reports and trusting it. That answer can
# name a directory that does not exist -- Homebrew's ncurses-head reports a
# vendored portable-ruby path -- and then unibilium has nowhere to look once
# $TERMINFO and $TERMINFO_DIRS are absent, so nvim falls back to its built-in
# entry and decides TERM=screen is a 256-colour terminal.
#
# Ask the same question unibilium would, then append the standard locations
# after the answer. unibilium walks the list and skips entries that are not
# there, so the first one that exists wins: a bogus leading entry becomes
# harmless, and a system whose ncurses answers sanely is unaffected.
if(NOT WIN32)
  execute_process(COMMAND sh -c "ncursesw6-config --terminfo-dirs 2>/dev/null || \
      ncurses6-config  --terminfo-dirs 2>/dev/null || \
      ncursesw5-config --terminfo-dirs 2>/dev/null || \
      ncurses5-config  --terminfo-dirs 2>/dev/null"
    OUTPUT_VARIABLE UNIBILIUM_TERMINFO_DIRS
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET)
  # Same list unibilium falls back to when it finds no ncurses to ask.
  set(UNIBILIUM_TERMINFO_FALLBACK
    "/etc/terminfo:/lib/terminfo:/usr/share/terminfo:/usr/lib/terminfo:/usr/local/share/terminfo:/usr/local/lib/terminfo")
  if(UNIBILIUM_TERMINFO_DIRS)
    string(APPEND UNIBILIUM_TERMINFO_DIRS ":${UNIBILIUM_TERMINFO_FALLBACK}")
  else()
    set(UNIBILIUM_TERMINFO_DIRS "${UNIBILIUM_TERMINFO_FALLBACK}")
  endif()
  list(APPEND UNIBILIUM_CMAKE_ARGS -D TERMINFO_DIRS=${UNIBILIUM_TERMINFO_DIRS})
endif()

get_externalproject_options(unibilium ${DEPS_IGNORE_SHA})
ExternalProject_Add(unibilium
  DOWNLOAD_DIR ${DEPS_DOWNLOAD_DIR}/unibilium
  CMAKE_ARGS ${DEPS_CMAKE_ARGS} ${UNIBILIUM_CMAKE_ARGS}
  ${EXTERNALPROJECT_OPTIONS})
