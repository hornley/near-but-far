use std::{env, path::PathBuf};

fn main() {
    let root = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    let config = cbindgen::Config::from_file(root.join("cbindgen.toml")).unwrap();
    let generated = cbindgen::Builder::new()
        .with_crate(root.clone())
        .with_config(config)
        .generate()
        .expect("generate private C header");
    let header = root.join("include/NearButFarSession.h");
    let rendered_path = PathBuf::from(env::var("OUT_DIR").unwrap()).join("NearButFarSession.h");
    generated.write_to_file(&rendered_path);
    let rendered = std::fs::read_to_string(rendered_path).unwrap();
    if header.exists() {
        assert_eq!(
            std::fs::read_to_string(&header).unwrap(),
            rendered,
            "committed C header is stale; regenerate it with the build script"
        );
    } else {
        std::fs::write(header, rendered).unwrap();
    }
}
