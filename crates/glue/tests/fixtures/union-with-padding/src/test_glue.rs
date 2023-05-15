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
pub enum discriminant_NonRecursive {
    Bar = 0,
    Baz = 1,
    Blah = 2,
    Foo = 3,
}

impl core::fmt::Debug for discriminant_NonRecursive {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::Bar => f.write_str("discriminant_NonRecursive::Bar"),
            Self::Baz => f.write_str("discriminant_NonRecursive::Baz"),
            Self::Blah => f.write_str("discriminant_NonRecursive::Blah"),
            Self::Foo => f.write_str("discriminant_NonRecursive::Foo"),
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
#[repr(C)]
pub union NonRecursive {
    Bar: roc_std::U128,
    Blah: i32,
    Foo: core::mem::ManuallyDrop<roc_std::RocStr>,
    _sizer: [u8; 48],
}

impl NonRecursive {
    #[cfg(any(
        target_arch = "arm",
        target_arch = "wasm32",
        target_arch = "x86"
    ))]
    /// Returns which variant this tag union holds. Note that this never includes a payload!
    pub fn discriminant(&self) -> discriminant_NonRecursive {
        unsafe {
            let bytes = core::mem::transmute::<&Self, &[u8; core::mem::size_of::<Self>()]>(self);

            core::mem::transmute::<u8, discriminant_NonRecursive>(*bytes.as_ptr().add(16))
        }
    }

    #[cfg(any(
        target_arch = "arm",
        target_arch = "wasm32",
        target_arch = "x86"
    ))]
    /// Internal helper
    fn set_discriminant(&mut self, discriminant: discriminant_NonRecursive) {
        let discriminant_ptr: *mut discriminant_NonRecursive = (self as *mut NonRecursive).cast();

        unsafe {
            *(discriminant_ptr.add(16)) = discriminant;
        }
    }

    #[cfg(any(
        target_arch = "arm",
        target_arch = "aarch64",
        target_arch = "wasm32",
        target_arch = "x86",
        target_arch = "x86_64"
    ))]
    /// Construct a tag named `Bar`, with the appropriate payload
    pub fn Bar(arg: roc_std::U128) -> Self {
            let mut answer = Self {
                Bar: arg
            };

            answer.set_discriminant(discriminant_NonRecursive::Bar);

            answer
    }

    #[cfg(any(
        target_arch = "arm",
        target_arch = "aarch64",
        target_arch = "wasm32",
        target_arch = "x86",
        target_arch = "x86_64"
    ))]
    /// Unsafely assume this `NonRecursive` has a `.discriminant()` of `Bar` and convert it to `Bar`'s payload.
            /// (Always examine `.discriminant()` first to make sure this is the correct variant!)
            /// Panics in debug builds if the `.discriminant()` doesn't return `Bar`.
            pub unsafe fn into_Bar(self) -> roc_std::U128 {
                debug_assert_eq!(self.discriminant(), discriminant_NonRecursive::Bar);
        let payload = self.Bar;

        payload
    }

    #[cfg(any(
        target_arch = "arm",
        target_arch = "aarch64",
        target_arch = "wasm32",
        target_arch = "x86",
        target_arch = "x86_64"
    ))]
    /// Unsafely assume this `NonRecursive` has a `.discriminant()` of `Bar` and return its payload.
            /// (Always examine `.discriminant()` first to make sure this is the correct variant!)
            /// Panics in debug builds if the `.discriminant()` doesn't return `Bar`.
            pub unsafe fn as_Bar(&self) -> &roc_std::U128 {
                debug_assert_eq!(self.discriminant(), discriminant_NonRecursive::Bar);
        let payload = &self.Bar;

        &payload
    }

    #[cfg(any(
        target_arch = "arm",
        target_arch = "wasm32",
        target_arch = "x86"
    ))]
    /// A tag named Baz, which has no payload.
    pub const Baz: Self = unsafe {
        let mut bytes = [0; core::mem::size_of::<NonRecursive>()];

        bytes[16] = discriminant_NonRecursive::Baz as u8;

        core::mem::transmute::<[u8; core::mem::size_of::<NonRecursive>()], NonRecursive>(bytes)
    };

    #[cfg(any(
        target_arch = "arm",
        target_arch = "aarch64",
        target_arch = "wasm32",
        target_arch = "x86",
        target_arch = "x86_64"
    ))]
    /// Other `into_` methods return a payload, but since the Baz tag
    /// has no payload, this does nothing and is only here for completeness.
    pub fn into_Baz(self) {
        ()
    }

    #[cfg(any(
        target_arch = "arm",
        target_arch = "aarch64",
        target_arch = "wasm32",
        target_arch = "x86",
        target_arch = "x86_64"
    ))]
    /// Other `as` methods return a payload, but since the Baz tag
    /// has no payload, this does nothing and is only here for completeness.
    pub fn as_Baz(&self) {
        ()
    }

    #[cfg(any(
        target_arch = "arm",
        target_arch = "aarch64",
        target_arch = "wasm32",
        target_arch = "x86",
        target_arch = "x86_64"
    ))]
    /// Construct a tag named `Blah`, with the appropriate payload
    pub fn Blah(arg: i32) -> Self {
            let mut answer = Self {
                Blah: arg
            };

            answer.set_discriminant(discriminant_NonRecursive::Blah);

            answer
    }

    #[cfg(any(
        target_arch = "arm",
        target_arch = "aarch64",
        target_arch = "wasm32",
        target_arch = "x86",
        target_arch = "x86_64"
    ))]
    /// Unsafely assume this `NonRecursive` has a `.discriminant()` of `Blah` and convert it to `Blah`'s payload.
            /// (Always examine `.discriminant()` first to make sure this is the correct variant!)
            /// Panics in debug builds if the `.discriminant()` doesn't return `Blah`.
            pub unsafe fn into_Blah(self) -> i32 {
                debug_assert_eq!(self.discriminant(), discriminant_NonRecursive::Blah);
        let payload = self.Blah;

        payload
    }

    #[cfg(any(
        target_arch = "arm",
        target_arch = "aarch64",
        target_arch = "wasm32",
        target_arch = "x86",
        target_arch = "x86_64"
    ))]
    /// Unsafely assume this `NonRecursive` has a `.discriminant()` of `Blah` and return its payload.
            /// (Always examine `.discriminant()` first to make sure this is the correct variant!)
            /// Panics in debug builds if the `.discriminant()` doesn't return `Blah`.
            pub unsafe fn as_Blah(&self) -> &i32 {
                debug_assert_eq!(self.discriminant(), discriminant_NonRecursive::Blah);
        let payload = &self.Blah;

        &payload
    }

    #[cfg(any(
        target_arch = "arm",
        target_arch = "aarch64",
        target_arch = "wasm32",
        target_arch = "x86",
        target_arch = "x86_64"
    ))]
    /// Construct a tag named `Foo`, with the appropriate payload
    pub fn Foo(arg: roc_std::RocStr) -> Self {
            let mut answer = Self {
                Foo: core::mem::ManuallyDrop::new(arg)
            };

            answer.set_discriminant(discriminant_NonRecursive::Foo);

            answer
    }

    #[cfg(any(
        target_arch = "arm",
        target_arch = "aarch64",
        target_arch = "wasm32",
        target_arch = "x86",
        target_arch = "x86_64"
    ))]
    /// Unsafely assume this `NonRecursive` has a `.discriminant()` of `Foo` and convert it to `Foo`'s payload.
            /// (Always examine `.discriminant()` first to make sure this is the correct variant!)
            /// Panics in debug builds if the `.discriminant()` doesn't return `Foo`.
            pub unsafe fn into_Foo(mut self) -> roc_std::RocStr {
                debug_assert_eq!(self.discriminant(), discriminant_NonRecursive::Foo);
        let payload = {
            let mut uninitialized = core::mem::MaybeUninit::uninit();
            let swapped = unsafe {
                core::mem::replace(
                    &mut self.Foo,
                    core::mem::ManuallyDrop::new(uninitialized.assume_init()),
                )
            };

            core::mem::forget(self);

            core::mem::ManuallyDrop::into_inner(swapped)
        };

        payload
    }

    #[cfg(any(
        target_arch = "arm",
        target_arch = "aarch64",
        target_arch = "wasm32",
        target_arch = "x86",
        target_arch = "x86_64"
    ))]
    /// Unsafely assume this `NonRecursive` has a `.discriminant()` of `Foo` and return its payload.
            /// (Always examine `.discriminant()` first to make sure this is the correct variant!)
            /// Panics in debug builds if the `.discriminant()` doesn't return `Foo`.
            pub unsafe fn as_Foo(&self) -> &roc_std::RocStr {
                debug_assert_eq!(self.discriminant(), discriminant_NonRecursive::Foo);
        let payload = &self.Foo;

        &payload
    }

    #[cfg(any(
        target_arch = "aarch64",
        target_arch = "x86_64"
    ))]
    /// Returns which variant this tag union holds. Note that this never includes a payload!
    pub fn discriminant(&self) -> discriminant_NonRecursive {
        unsafe {
            let bytes = core::mem::transmute::<&Self, &[u8; core::mem::size_of::<Self>()]>(self);

            core::mem::transmute::<u8, discriminant_NonRecursive>(*bytes.as_ptr().add(32))
        }
    }

    #[cfg(any(
        target_arch = "aarch64",
        target_arch = "x86_64"
    ))]
    /// Internal helper
    fn set_discriminant(&mut self, discriminant: discriminant_NonRecursive) {
        let discriminant_ptr: *mut discriminant_NonRecursive = (self as *mut NonRecursive).cast();

        unsafe {
            *(discriminant_ptr.add(32)) = discriminant;
        }
    }

    #[cfg(any(
        target_arch = "aarch64",
        target_arch = "x86_64"
    ))]
    /// A tag named Baz, which has no payload.
    pub const Baz: Self = unsafe {
        let mut bytes = [0; core::mem::size_of::<NonRecursive>()];

        bytes[32] = discriminant_NonRecursive::Baz as u8;

        core::mem::transmute::<[u8; core::mem::size_of::<NonRecursive>()], NonRecursive>(bytes)
    };
}

impl Drop for NonRecursive {
    #[cfg(any(
        target_arch = "arm",
        target_arch = "aarch64",
        target_arch = "wasm32",
        target_arch = "x86",
        target_arch = "x86_64"
    ))]
    fn drop(&mut self) {
        // Drop the payloads
                    match self.discriminant() {
                discriminant_NonRecursive::Bar => {}
                discriminant_NonRecursive::Baz => {}
                discriminant_NonRecursive::Blah => {}
                discriminant_NonRecursive::Foo => unsafe { core::mem::ManuallyDrop::drop(&mut self.Foo) },
            }

    }
}

impl Eq for NonRecursive {}

impl PartialEq for NonRecursive {
    #[cfg(any(
        target_arch = "arm",
        target_arch = "aarch64",
        target_arch = "wasm32",
        target_arch = "x86",
        target_arch = "x86_64"
    ))]
    fn eq(&self, other: &Self) -> bool {
            if self.discriminant() != other.discriminant() {
                return false;
            }

            unsafe {
            match self.discriminant() {
                discriminant_NonRecursive::Bar => self.Bar == other.Bar,
                discriminant_NonRecursive::Baz => true,
                discriminant_NonRecursive::Blah => self.Blah == other.Blah,
                discriminant_NonRecursive::Foo => self.Foo == other.Foo,
            }
        }
    }
}

impl PartialOrd for NonRecursive {
    #[cfg(any(
        target_arch = "arm",
        target_arch = "aarch64",
        target_arch = "wasm32",
        target_arch = "x86",
        target_arch = "x86_64"
    ))]
    fn partial_cmp(&self, other: &Self) -> Option<core::cmp::Ordering> {
        match self.discriminant().partial_cmp(&other.discriminant()) {
            Some(core::cmp::Ordering::Equal) => {}
            not_eq => return not_eq,
        }

        unsafe {
            match self.discriminant() {
                discriminant_NonRecursive::Bar => self.Bar.partial_cmp(&other.Bar),
                discriminant_NonRecursive::Baz => Some(core::cmp::Ordering::Equal),
                discriminant_NonRecursive::Blah => self.Blah.partial_cmp(&other.Blah),
                discriminant_NonRecursive::Foo => self.Foo.partial_cmp(&other.Foo),
            }
        }
    }
}

impl Ord for NonRecursive {
    #[cfg(any(
        target_arch = "arm",
        target_arch = "aarch64",
        target_arch = "wasm32",
        target_arch = "x86",
        target_arch = "x86_64"
    ))]
    fn cmp(&self, other: &Self) -> core::cmp::Ordering {
            match self.discriminant().cmp(&other.discriminant()) {
                core::cmp::Ordering::Equal => {}
                not_eq => return not_eq,
            }

            unsafe {
            match self.discriminant() {
                discriminant_NonRecursive::Bar => self.Bar.cmp(&other.Bar),
                discriminant_NonRecursive::Baz => core::cmp::Ordering::Equal,
                discriminant_NonRecursive::Blah => self.Blah.cmp(&other.Blah),
                discriminant_NonRecursive::Foo => self.Foo.cmp(&other.Foo),
            }
        }
    }
}

impl Clone for NonRecursive {
    #[cfg(any(
        target_arch = "arm",
        target_arch = "aarch64",
        target_arch = "wasm32",
        target_arch = "x86",
        target_arch = "x86_64"
    ))]
    fn clone(&self) -> Self {
        let mut answer = unsafe {
            match self.discriminant() {
                discriminant_NonRecursive::Bar => Self {
                    Bar: self.Bar.clone(),
                },
                discriminant_NonRecursive::Baz => core::mem::transmute::<
                    core::mem::MaybeUninit<NonRecursive>,
                    NonRecursive,
                >(core::mem::MaybeUninit::uninit()),
                discriminant_NonRecursive::Blah => Self {
                    Blah: self.Blah.clone(),
                },
                discriminant_NonRecursive::Foo => Self {
                    Foo: self.Foo.clone(),
                },
            }

        };

        answer.set_discriminant(self.discriminant());

        answer
    }
}

impl core::hash::Hash for NonRecursive {
    #[cfg(any(
        target_arch = "arm",
        target_arch = "aarch64",
        target_arch = "wasm32",
        target_arch = "x86",
        target_arch = "x86_64"
    ))]
    fn hash<H: core::hash::Hasher>(&self, state: &mut H) {        match self.discriminant() {
            discriminant_NonRecursive::Bar => unsafe {
                    discriminant_NonRecursive::Bar.hash(state);
                    self.Bar.hash(state);
                },
            discriminant_NonRecursive::Baz => discriminant_NonRecursive::Baz.hash(state),
            discriminant_NonRecursive::Blah => unsafe {
                    discriminant_NonRecursive::Blah.hash(state);
                    self.Blah.hash(state);
                },
            discriminant_NonRecursive::Foo => unsafe {
                    discriminant_NonRecursive::Foo.hash(state);
                    self.Foo.hash(state);
                },
        }
    }
}

impl core::fmt::Debug for NonRecursive {
    #[cfg(any(
        target_arch = "arm",
        target_arch = "aarch64",
        target_arch = "wasm32",
        target_arch = "x86",
        target_arch = "x86_64"
    ))]
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.write_str("NonRecursive::")?;

        unsafe {
            match self.discriminant() {
                discriminant_NonRecursive::Bar => f.debug_tuple("Bar")
        .field(&self.Bar)
        .finish(),
                discriminant_NonRecursive::Baz => f.write_str("Baz"),
                discriminant_NonRecursive::Blah => f.debug_tuple("Blah")
        .field(&self.Blah)
        .finish(),
                discriminant_NonRecursive::Foo => f.debug_tuple("Foo")
        .field(&*self.Foo)
        .finish(),
            }
        }
    }
}