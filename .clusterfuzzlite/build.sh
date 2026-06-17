#!/bin/bash -eu
#
# ClusterFuzzLite build script for the Zebra fuzz target suite.
# Runs inside the base-builder-rust container; $OUT / $SRC / $CC / $CXX /
# $LIB_FUZZING_ENGINE are provided by the build environment.

# Non-standard layout: the cargo-fuzz harnesses live at zebra-fuzz/fuzz/, NOT at
# the workspace root. cargo-fuzz must run from the workspace root WITH
# --fuzz-dir; otherwise it resolves the manifest to the (non-existent)
# workspace-root fuzz/ and dies with "could not read manifest .../fuzz/Cargo.toml".
cd "$SRC/zebra-fuzz-m2"

# The OSS-Fuzz coverage build's cargo wrapper hard-codes `cd fuzz` (verified by
# reading /usr/local/bin/cargo in the image: `cd fuzz || true; cargo build --bins`),
# ignoring --fuzz-dir. Symlink fuzz -> zebra-fuzz/fuzz BEFORE the build so the
# wrapper's `cd fuzz` resolves to the 12 bin targets instead of editing nothing
# at the workspace root. The address/default build uses --fuzz-dir, unaffected.
ln -sfn zebra-fuzz/fuzz fuzz

# -O builds the fuzzers in release mode (the OSS-Fuzz Rust convention).
# The fuzz crate enables zebra-chain/proptest-impl and zebra-state/proptest-impl
# as default dependency features; the Arbitrary-based harnesses
# (address_fuzz / note_commitment_tree_fuzz) need the derived `Arbitrary` impls.
cargo fuzz build -O --fuzz-dir zebra-fuzz/fuzz

FUZZ_OUT="zebra-fuzz/fuzz/target/x86_64-unknown-linux-gnu/release"

# Explicit white-list — only the 12 shipped targets (M1 5 + M2 7) are copied
# to $OUT. We do NOT glob fuzz/fuzz_targets/*.rs so no held-back / out-of-scope
# target can leak into the published fuzzer set.
WHITELIST=(
    # M2 (7)
    rpc_handler_fuzz
    jsonrpsee_envelope_fuzz
    script_verify_fuzz
    script_flag_matrix_fuzz
    address_fuzz
    note_commitment_tree_fuzz
    equihash_fuzz
    # M1 (5)
    block_deserialize
    block_deep_fuzz
    p2p_message_parse
    p2p_deep_fuzz
    addr_message_fuzz
)

for t in "${WHITELIST[@]}"; do
    cp "$FUZZ_OUT/$t" "$OUT/"
    # Ship a seed corpus alongside each target if one was staged under
    # fuzz/corpus/<target>/ (mainnet-derived public bytes; safe to publish).
    if [ -d "zebra-fuzz/fuzz/corpus/$t" ]; then
        (cd "zebra-fuzz/fuzz/corpus/$t" && zip -q -r "$OUT/${t}_seed_corpus.zip" .)
    fi
    # Ship a dictionary if one exists under zebra-fuzz/fuzz/dicts/<target>.dict.
    if [ -f "zebra-fuzz/fuzz/dicts/${t}.dict" ]; then
        cp "zebra-fuzz/fuzz/dicts/${t}.dict" "$OUT/${t}.dict"
    fi
done
