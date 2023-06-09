# wasmtime is a chungus -- optimize _extra hard_ to keep nvim svelte
get_externalproject_options(wasmtime ${DEPS_IGNORE_SHA})
ExternalProject_Add(wasmtime
  DOWNLOAD_DIR ${DEPS_DOWNLOAD_DIR}/wasmtime
  SOURCE_SUBDIR crates/c-api
  # The fastest-runtime profile strips debuginfo from every build unit,
  # including the host proc-macro dylibs that rustc must dlopen at compile time.
  # On recent Apple toolchains stripping a proc-macro dylib mis-aligns its
  # __LINKEDIT segment, so dyld refuses to load it and the build fails with a
  # misleading `error[E0463]: can't find crate for ...`. Drop a cargo config
  # into the source tree that disables stripping for build-time units only.
  PATCH_COMMAND ${CMAKE_COMMAND} -E copy
    ${CMAKE_CURRENT_SOURCE_DIR}/cmake/WasmtimeCargoConfig.toml
    ${DEPS_BUILD_DIR}/src/wasmtime/.cargo/config.toml
  CMAKE_ARGS ${DEPS_CMAKE_ARGS}
    -D WASMTIME_FASTEST_RUNTIME=ON       # build with full LTO
    -D WASMTIME_DISABLE_ALL_FEATURES=ON  # don't need all that crap...
    -D WASMTIME_FEATURE_CRANELIFT=ON     # ...except this one (compiles wasm to platform code)
    -D WASMTIME_FEATURE_GC=ON            # ...and this one (needed by ts to create engines)
    -D WASMTIME_FEATURE_GC_NULL=ON       # ...and this one (reasons)
  USES_TERMINAL_BUILD TRUE
  ${EXTERNALPROJECT_OPTIONS})
