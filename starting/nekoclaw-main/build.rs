//!
//! # Build Script
//!
//! Generate version information at compile time using vergen with gitcl mode.
//! The gitcl feature in Cargo.toml makes git methods use command line git automatically.

fn main() {
    // Tell Cargo to rerun if build.rs changes
    println!("cargo:rerun-if-changed=build.rs");

    // Emit build info using vergen
    // gitcl feature in Cargo.toml makes git_* methods use command line git
    vergen::EmitBuilder::builder()
        .build_timestamp() // VERGEN_BUILD_TIMESTAMP
        .cargo_features() // VERGEN_CARGO_FEATURES
        .git_sha(true) // VERGEN_GIT_SHA (short)
        .git_commit_date() // VERGEN_GIT_COMMIT_DATE
        .rustc_semver() // VERGEN_RUSTC_SEMVER
        .emit()
        .expect("Failed to emit vergen instructions");
}
