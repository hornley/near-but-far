# Snow bridge build

The bridge pins Snow 0.10.0 and exports only the private C interface in `include/`.
It uses the Rust Apple targets for arm64 and x86_64 macOS, arm64 iOS devices, and
arm64/x86_64 iOS simulators.

Prerequisites: Xcode command line tools, `rustup`, and network access the first
time Cargo dependencies or Rust targets are installed. From the repository root,
run:

```sh
Rust/NearButFarSession/build-xcframework.sh
```

The script installs missing Rust targets, builds the release static libraries,
and writes `Rust/NearButFarSession/build/NearButFarSession.xcframework`. Build
products and Cargo's `target/` directory are ignored.

Snow 0.10.0 contains eight remediations Trail of Bits validated against its
reviewed source. The exact 0.10.0 release was not fully audited; the two
informational findings about pre-message ephemeral mixing and ephemeral memory
clearing were not validated as fixed. Snow does not guarantee that every key
copy is zeroized.
