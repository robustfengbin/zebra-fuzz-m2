# Zebra Coverage-Guided Fuzzing Suite

A suite of coverage-guided [libFuzzer](https://llvm.org/docs/LibFuzzer.html) harnesses for
[Zebra](https://github.com/ZcashFoundation/zebra), the Rust Zcash full-node implementation.
Twelve fuzz targets exercise block / transaction / P2P deserialization, JSON-RPC request
handling, transparent-script verification (via the `zcash_script` C++ library), transparent
and shielded address parsing, the note-commitment tree, and Equihash solution validation.
The suite is continuously fuzzed on GitHub Actions via
[ClusterFuzzLite](https://google.github.io/clusterfuzzlite/).

## Targets

The 12 harnesses live in [`zebra-fuzz/fuzz/fuzz_targets/`](zebra-fuzz/fuzz/fuzz_targets):

### Deserialization & networking
| Target | What it exercises |
| --- | --- |
| `block_deserialize`   | `Block` consensus deserialization from raw bytes |
| `block_deep_fuzz`     | Deeper block parsing paths (headers, commitments, transactions) |
| `p2p_message_parse`   | Network protocol `Codec` message decode |
| `p2p_deep_fuzz`       | Deeper `protocol::external` message paths |
| `addr_message_fuzz`   | `addr` / `addrv2` peer-address message decode |

### RPC, script & cryptography
| Target | What it exercises |
| --- | --- |
| `rpc_handler_fuzz`        | RPC method dispatch over mocked state/mempool services |
| `jsonrpsee_envelope_fuzz` | JSON-RPC request envelope parsing across the method surface |
| `script_verify_fuzz`      | Transparent script verification through the `zcash_script` FFI |
| `script_flag_matrix_fuzz` | Script verification across consensus flag combinations (FFI) |
| `address_fuzz`            | Transparent & shielded address string parsing |
| `note_commitment_tree_fuzz` | Sprout / Sapling / Orchard note-commitment tree operations |
| `equihash_fuzz`           | Equihash proof-of-work solution validation |

`script_verify_fuzz` and `script_flag_matrix_fuzz` reach C/C++ code through the
`zebra-script` FFI bridge; sanitizer-coverage does not instrument the C side, so these two
report no Rust region coverage — their value is crash detection on the parser/verifier path.

## Upstream base

The vendored crates are upstream Zebra **v5.0.0**, byte-identical to the published release
except for two fuzzing-only `cfg` gates that expose otherwise-private modules to the
harnesses:

- `zebra-consensus`: `#[cfg(feature = "fuzzing")] pub mod block;` (reaches
  `block::check::equihash_solution_is_valid`)
- `zebra-network`: `#[cfg(feature = "fuzzing")] pub mod protocol;` (reaches
  `protocol::external` `Codec` / `Message`)

Neither gate is enabled in production builds. To verify the vendored crates match upstream,
check out `v5.0.0` from the upstream repository and diff.

## Building

The cargo-fuzz harnesses live under `zebra-fuzz/fuzz/` (not at the workspace root), so
cargo-fuzz is run from the workspace root with `--fuzz-dir`:

```sh
cargo +nightly fuzz build --fuzz-dir zebra-fuzz/fuzz
```

Native dependencies: `cmake`, `clang`, `libclang-dev` (for `zcash_script`) and
`protobuf-compiler` (for `zebra-rpc`'s `tonic` build).

## Running a target

```sh
cargo +nightly fuzz run --fuzz-dir zebra-fuzz/fuzz <target> zebra-fuzz/fuzz/corpus/<target>
```

Reproduce a target's coverage locally (the same numbers the CI coverage report shows):

```sh
cargo +nightly fuzz coverage --fuzz-dir zebra-fuzz/fuzz <target>
```

## Corpus

Seed corpora under `zebra-fuzz/fuzz/corpus/<target>/` are mainnet-derived public bytes —
real blocks, transactions, headers and P2P messages dumped from a fully-synced Zcash
mainnet node across several epochs — plus a small set of hand-constructed protocol seeds
(e.g. `verack`, `ping`, malformed headers). libFuzzer mutates these real inputs to explore
parser and consensus paths.

## Continuous fuzzing (ClusterFuzzLite)

GitHub Actions workflows under [`.github/workflows/`](.github/workflows):

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `cflite_pr`    | pull request    | Short code-change fuzzing, crash detection (ASan), SARIF output |
| `cflite_batch` | every 6 h / manual | Batch fuzzing, accumulates corpus into the storage repo |
| `cflite_cron`  | daily / manual  | Coverage report (published to `gh-pages`) and corpus pruning |

Build configuration lives in [`.clusterfuzzlite/`](.clusterfuzzlite) (`project.yaml`,
`Dockerfile`, `build.sh`). Coverage is tracked and reported, never used to fail the build.

## Coverage

The `cflite_cron` workflow publishes a full, navigable llvm-cov HTML report to the
`gh-pages` branch of the corpus repository, rebuilt automatically on every scheduled run:

**📊 Live coverage dashboard:** <https://robustfengbin.github.io/zebra-fuzz-m2-corpus/>

### Reading the report: harness vs. subject-under-test

The report has a **`Directories` / `Files`** toggle at the top. Two different things are
measured, and they should not be confused:

- **Harness coverage** — the files under `fuzz_targets/` (`equihash_fuzz.rs`,
  `block_deserialize.rs`, …) are the fuzzing entry points in this repository. They run at
  high coverage (most 85–100%) simply because the harness glue executes fully on every
  input. This tells you *the probes run*, not *how deeply Zebra is tested* — so it is **not**
  the number to cite.
- **Subject-under-test (SUT) coverage** — the actual upstream Zebra source files (under the
  `zebra-*` crate directories) are what the fuzzers exercise. **These are the meaningful
  numbers.** To see them, switch to the **`Files`** view, or in `Directories` view drill into
  the `zebra-*` directories rather than `fuzz_targets/`.

Per-target SUT region coverage on the seed-corpus baseline (whole-crate and whole-report
totals are diluted by thousands of unrelated dependency files, so we report per-SUT-file
region %):

| Target | SUT file | region % |
| --- | --- | --- |
| `equihash_fuzz`            | `work/equihash.rs`            | 65 |
| `block_deserialize`        | `block/serialize.rs`          | 67 |
| `address_fuzz`             | `transparent/address.rs`      | 63 |
| `note_commitment_tree_fuzz`| `orchard/tree.rs`             | 54 |
| `p2p_message_parse` / `addr_message_fuzz` | `network/.../codec.rs` | 53 (union) |
| `rpc_handler_fuzz` / `jsonrpsee_envelope_fuzz` | `zebra-rpc/.../methods.rs` | 33 |

`script_verify_fuzz` / `script_flag_matrix_fuzz` reach C/C++ through the `zcash_script`
FFI; sanitizer-coverage does not instrument the C side, so they report no Rust region % —
their value is crash detection on the verifier path.

Numbers are a seed + short-run baseline and grow with sustained fuzzing. 90+ Zebra
source files are exercised at ≥5% region coverage. Reproduce any target's numbers locally
with `cargo +nightly fuzz coverage --fuzz-dir zebra-fuzz/fuzz <target>`.

## License

Licensed under the same terms as upstream Zebra: MIT OR Apache-2.0.
