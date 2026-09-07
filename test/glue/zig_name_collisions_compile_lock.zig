//! Compile lock for generated Zig glue names.
//!
//! `roc glue` writes Zig source, so a generated name that Zig will not accept
//! is a broken build for the platform author and not something any layout
//! assertion can catch. This root imports the glue generated for
//! `test/glue/zig-name-collisions` and does nothing else: importing it is the
//! test, because an unparseable or undeclared name fails the compile.

const abi = @import("glue_abi");

comptime {
    _ = abi;
}
