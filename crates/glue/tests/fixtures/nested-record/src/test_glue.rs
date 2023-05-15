// ⚠️ GENERATED CODE ⚠️ - this entire file was generated by the `roc glue` CLI command

#![allow(unused_unsafe)]
#![allow(unused_variables)]
#![allow(dead_code)]
#![allow(unused_mut)]
#![allow(non_snake_case)]
#![allow(non_camel_case_types)]
#![allow(non_upper_case_globals)]
#![allow(clippy::undocumented_unsafe_blocks)]
#![allow(clippy::redundant_static_lifetimes)]
#![allow(clippy::unused_unit)]
#![allow(clippy::missing_safety_doc)]
#![allow(clippy::let_and_return)]
#![allow(clippy::missing_safety_doc)]
#![allow(clippy::redundant_static_lifetimes)]
#![allow(clippy::needless_borrow)]
#![allow(clippy::clone_on_copy)]

type Op_StderrWrite = roc_std::RocStr;
type Op_StdoutWrite = roc_std::RocStr;
type TODO_roc_function_69 = roc_std::RocStr;
type TODO_roc_function_70 = roc_std::RocStr;

#[cfg(any(
    target_arch = "arm",
    target_arch = "wasm32",
    target_arch = "x86"
))]
#[derive(Clone, Debug, Default, PartialEq, PartialOrd)]
#[repr(C)]
pub struct Outer {
    pub x: Inner,
    pub y: roc_std::RocStr,
    pub z: roc_std::RocList<u8>,
}

#[cfg(any(
    target_arch = "arm",
    target_arch = "aarch64",
    target_arch = "wasm32",
    target_arch = "x86",
    target_arch = "x86_64"
))]
#[derive(Clone, Copy, Debug, Default, PartialEq, PartialOrd)]
#[repr(C)]
pub struct Inner {
    pub b: f32,
    pub a: u16,
}

#[cfg(any(
    target_arch = "aarch64",
    target_arch = "x86_64"
))]
#[derive(Clone, Debug, Default, PartialEq, PartialOrd)]
#[repr(C)]
pub struct Outer {
    pub y: roc_std::RocStr,
    pub z: roc_std::RocList<u8>,
    pub x: Inner,
}