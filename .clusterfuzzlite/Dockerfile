# ClusterFuzzLite build environment for the Zebra fuzz target suite.
#
# base-builder-rust ships the nightly toolchain + `cargo fuzz` pre-installed
# and in PATH (https://google.github.io/oss-fuzz/.../rust-lang/).
FROM gcr.io/oss-fuzz-base/base-builder-rust

# Extra system deps the Zebra workspace needs that are NOT in base-builder-rust:
#   - cmake / clang / libclang-dev : building the `zcash_script` C/C++ library
#     reached through the `zebra-script` FFI bridge (script_verify /
#     script_flag_matrix / script_struct targets).
#   - protobuf-compiler            : `zebra-rpc` pulls `tonic`, whose build
#     script invokes `protoc`.
# NOTE (unverified): this dep list is best-effort from the local build
# toolchain. The first Docker build run is the authority — adjust if the
# build fails on a missing dep.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        cmake clang libclang-dev protobuf-compiler && \
    rm -rf /var/lib/apt/lists/*

COPY . $SRC/zebra-fuzz-m2
WORKDIR $SRC/zebra-fuzz-m2
COPY ./.clusterfuzzlite/build.sh $SRC/
