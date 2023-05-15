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
    target_arch = "aarch64",
    target_arch = "wasm32",
    target_arch = "x86",
    target_arch = "x86_64"
))]
#[derive(Clone, Copy, Eq, Hash, Ord, PartialEq, PartialOrd)]
#[repr(u8)]
pub enum discriminant_StrConsList {
    Cons = 0,
    Nil = 1,
}

impl core::fmt::Debug for discriminant_StrConsList {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::Cons => f.write_str("discriminant_StrConsList::Cons"),
            Self::Nil => f.write_str("discriminant_StrConsList::Nil"),
        }
    }
}

#[cfg(any(
    target_arch = "arm",
    target_arch = "aarch64",
    target_arch = "wasm32",
    target_arch = "x86",
    target_arch = "x86_64"
))]
#[repr(transparent)]
#[derive(PartialEq, PartialOrd, Eq, Ord, Hash)]
pub struct StrConsList {
    pointer: *mut core::mem::ManuallyDrop<StrConsList_Cons>,
}

#[cfg(any(
    target_arch = "arm",
    target_arch = "aarch64",
    target_arch = "wasm32",
    target_arch = "x86",
    target_arch = "x86_64"
))]
#[derive(Clone, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
#[repr(C)]
struct StrConsList_Cons {
    pub f0: roc_std::RocStr,
    pub f1: StrConsList,
}

impl StrConsList {
    #[cfg(any(
        target_arch = "arm",
        target_arch = "aarch64",
        target_arch = "wasm32",
        target_arch = "x86",
        target_arch = "x86_64"
    ))]
    #[inline(always)]
    fn storage(&self) -> Option<&core::cell::Cell<roc_std::Storage>> {
        let mask = match std::mem::size_of::<usize>() {
            4 => 0b11,
            8 => 0b111,
            _ => unreachable!(),
        };

        // NOTE: pointer provenance is probably lost here
        let unmasked_address = (self.pointer as usize) & !mask;
        let untagged = unmasked_address as *const core::cell::Cell<roc_std::Storage>;

        if untagged.is_null() {
            None
        } else {
            unsafe {
                Some(&*untagged.sub(1))
            }
        }
    }

    #[cfg(any(
        target_arch = "arm",
        target_arch = "aarch64",
        target_arch = "wasm32",
        target_arch = "x86",
        target_arch = "x86_64"
    ))]
    /// Returns which variant this tag union holds. Note that this never includes a payload!
    pub fn discriminant(&self) -> discriminant_StrConsList {
        if self.pointer.is_null() {
            discriminant_StrConsList::Nil
        } else {
            discriminant_StrConsList::Cons
        }
    }

    #[cfg(any(
        target_arch = "arm",
        target_arch = "aarch64",
        target_arch = "wasm32",
        target_arch = "x86",
        target_arch = "x86_64"
    ))]
    /// Construct a tag named `Cons`, with the appropriate payload
    pub fn Cons(arg0: roc_std::RocStr, arg1: StrConsList) -> Self {
        let payload_align = core::mem::align_of::<StrConsList_Cons>();
        let self_align = core::mem::align_of::<Self>();
        let size = self_align + core::mem::size_of::<StrConsList_Cons>();
        let payload = core::mem::ManuallyDrop::new(StrConsList_Cons {
                    f0: arg0,
                    f1: arg1,
                });

        unsafe {
            // Store the payload at `self_align` bytes after the allocation,
            // to leave room for the refcount.
            let alloc_ptr = crate::roc_alloc(size, payload_align as u32);
            let payload_ptr = alloc_ptr.cast::<u8>().add(self_align).cast::<core::mem::ManuallyDrop<StrConsList_Cons>>();

            *payload_ptr = payload;

            // The reference count is stored immediately before the payload,
            // which isn't necessarily the same as alloc_ptr - e.g. when alloc_ptr
            // needs an alignment of 16.
            let storage_ptr = payload_ptr.cast::<roc_std::Storage>().sub(1);
            storage_ptr.write(roc_std::Storage::new_reference_counted());

            Self { pointer: payload_ptr }
        }
    }

    #[cfg(any(
        target_arch = "arm",
        target_arch = "aarch64",
        target_arch = "wasm32",
        target_arch = "x86",
        target_arch = "x86_64"
    ))]
    /// Unsafely assume this `StrConsList` has a `.discriminant()` of `Cons` and convert it to `Cons`'s payload.
    /// (Always examine `.discriminant()` first to make sure this is the correct variant!)
    /// Panics in debug builds if the `.discriminant()` doesn't return Cons.
    pub unsafe fn into_Cons(self) -> (roc_std::RocStr, StrConsList) {
        debug_assert_eq!(self.discriminant(), discriminant_StrConsList::Cons);

        let payload = {{
            let mut uninitialized = core::mem::MaybeUninit::uninit();
            let swapped = unsafe {{
                core::mem::replace(
                    &mut *self.pointer,
                    core::mem::ManuallyDrop::new(uninitialized.assume_init()),
                )
            }};

            core::mem::forget(self);

            core::mem::ManuallyDrop::into_inner(swapped)
        }};

        (
            payload.f0, 
            payload.f1
        )
    }

    #[cfg(any(
        target_arch = "arm",
        target_arch = "aarch64",
        target_arch = "wasm32",
        target_arch = "x86",
        target_arch = "x86_64"
    ))]
    /// Unsafely assume this `StrConsList` has a `.discriminant()` of `Cons` and return its payload.
    /// (Always examine `.discriminant()` first to make sure this is the correct variant!)
    /// Panics in debug builds if the `.discriminant()` doesn't return `Cons`.
    pub unsafe fn as_Cons(&self) -> (&roc_std::RocStr, &StrConsList) {
        debug_assert_eq!(self.discriminant(), discriminant_StrConsList::Cons);

        let payload = &*self.pointer;

        (
            &payload.f0, 
            &payload.f1
        )
    }

    #[cfg(any(
        target_arch = "arm",
        target_arch = "aarch64",
        target_arch = "wasm32",
        target_arch = "x86",
        target_arch = "x86_64"
    ))]
    /// A tag named Nil, which has no payload.
    pub const Nil: Self = Self {
        pointer: core::ptr::null_mut(),
    };

    #[cfg(any(
        target_arch = "arm",
        target_arch = "aarch64",
        target_arch = "wasm32",
        target_arch = "x86",
        target_arch = "x86_64"
    ))]
    /// Other `into_` methods return a payload, but since the Nil tag
    /// has no payload, this does nothing and is only here for completeness.
    pub fn into_Nil(self) {
        ()
    }

    #[cfg(any(
        target_arch = "arm",
        target_arch = "aarch64",
        target_arch = "wasm32",
        target_arch = "x86",
        target_arch = "x86_64"
    ))]
    /// Other `as` methods return a payload, but since the Nil tag
    /// has no payload, this does nothing and is only here for completeness.
    pub fn as_Nil(&self) {
        ()
    }
}

impl Clone for StrConsList {
    #[cfg(any(
        target_arch = "arm",
        target_arch = "aarch64",
        target_arch = "wasm32",
        target_arch = "x86",
        target_arch = "x86_64"
    ))]
    fn clone(&self) -> Self {
        if let Some(storage) = self.storage() {
            let mut new_storage = storage.get();
            if !new_storage.is_readonly() {
                new_storage.increment_reference_count();
                storage.set(new_storage);
            }
        }

        Self {
            pointer: self.pointer
        }
    }
}

impl Drop for StrConsList {
    #[cfg(any(
        target_arch = "arm",
        target_arch = "aarch64",
        target_arch = "wasm32",
        target_arch = "x86",
        target_arch = "x86_64"
    ))]
    fn drop(&mut self) {{
        // We only need to do any work if there's actually a heap-allocated payload.
        if let Some(storage) = self.storage() {{
            let mut new_storage = storage.get();

            // Decrement the refcount
            let needs_dealloc = !new_storage.is_readonly() && new_storage.decrease();

            if needs_dealloc {{
                // Drop the payload first.
                unsafe {{
                    core::mem::ManuallyDrop::drop(&mut core::ptr::read(self.pointer));
                }}

                // Dealloc the pointer
                let alignment = core::mem::align_of::<Self>().max(core::mem::align_of::<roc_std::Storage>());

                unsafe {{
                    crate::roc_dealloc(storage.as_ptr().cast(), alignment as u32);
                }}
            }} else {{
                // Write the storage back.
                storage.set(new_storage);
            }}
        }}
    }}
}

impl core::fmt::Debug for StrConsList {
    #[cfg(any(
        target_arch = "arm",
        target_arch = "aarch64",
        target_arch = "wasm32",
        target_arch = "x86",
        target_arch = "x86_64"
    ))]
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        if self.pointer.is_null() {
            f.write_str("StrConsList::Nil")
        } else {
            f.write_str("StrConsList::")?;

            unsafe {
                f.debug_tuple("Cons")
                    .field(&(&**self.pointer).f0)
                    .field(&(&**self.pointer).f1)
                    .finish()
            }
        }
    }
}