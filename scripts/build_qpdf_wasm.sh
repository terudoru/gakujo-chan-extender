#!/usr/bin/env bash
# Run in docker.io/emscripten/emsdk pinned to:
# sha256:11d144844086982d68260867ce1fc665667f4139b73326625033ed8d16533406
# Pass a writable output directory; verify and test the results before installing.
set -euo pipefail

output_dir="${1:?Pass a writable output directory}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
work_dir="$(mktemp -d)"
cd "$work_dir"

curl --fail --location --retry 2 --output qpdf.tar.gz \
  https://github.com/qpdf/qpdf/releases/download/v12.4.2/qpdf-12.4.2.tar.gz
printf '%s  %s\n' \
  8a58af5b6141319287c1883bec8bd1bd545b7567b7fc5e6ce5d25a1c85f36397 qpdf.tar.gz \
  | sha256sum -c -
tar --no-same-owner -xzf qpdf.tar.gz

# The pinned Emscripten ports verify their downloaded sources using SHA-512.
embuilder build zlib libjpeg
sysroot="$(em-config CACHE)/sysroot"
libdir="$sysroot/lib/wasm32-emscripten"
test -f "$libdir/libz.a"
test -f "$libdir/libjpeg.a"
common_flags="-fwasm-exceptions -O3"
link_flags="-fwasm-exceptions -O3 -sMODULARIZE=1 -sEXPORT_ES6=1 -sEXPORT_NAME=createQpdfModule"
link_flags+=" -sENVIRONMENT=web,worker,node -sALLOW_MEMORY_GROWTH=1 -sMAXIMUM_MEMORY=268435456"
link_flags+=" -sSTACK_SIZE=2097152 -sINVOKE_RUN=0 -sEXIT_RUNTIME=0 -sEXPORTED_RUNTIME_METHODS=FS,callMain"
emcmake cmake -S qpdf-12.4.2 -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON -DBUILD_DOC=OFF -DINSTALL_EXAMPLES=OFF \
  -DUSE_IMPLICIT_CRYPTO=OFF -DREQUIRE_CRYPTO_NATIVE=ON -DPKG_CONFIG_EXECUTABLE=/usr/bin/false \
  -DZLIB_H_PATH="$sysroot/include" -DZLIB_LIB_PATH="$libdir/libz.a" \
  -DLIBJPEG_H_PATH="$sysroot/include" -DLIBJPEG_LIB_PATH="$libdir/libjpeg.a" \
  -DCMAKE_C_FLAGS="$common_flags" -DCMAKE_CXX_FLAGS="$common_flags" \
  -DCMAKE_EXE_LINKER_FLAGS="$link_flags"
cmake --build build --target qpdf --parallel 2
cp build/qpdf/qpdf.js build/qpdf/qpdf.wasm "$output_dir/"
sha256sum "$output_dir/qpdf.js" "$output_dir/qpdf.wasm"
