//! The goal of this module is to introduce a class called `GResult`
//! which is a light wrapper over `Result`. The idea is to allow different
//! classes implemented in Rust to preserve type information about their methods'
//! returned types as well as the different errors they might produce; all while still
//! allowing GDScript access this information too.
//!
//! The challenge is that gdext's macros don't support generic types, so we
//! can't easily do the task at hand without a lot of repetition.

use godot::prelude::*;

/// Class used for communicating results to GDScript.
/// The class has no `init`, so it cannot be created from GDScript.
/// This is fine, our users should not need to create `GResult`s.
#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct GResult {
    #[doc(hidden)]
    result: Result<Variant, Variant>,
}

#[godot_api]
impl GResult {
    #[func]
    pub fn is_ok(&self) -> bool {
        self.result.is_ok()
    }
    #[func]
    pub fn is_err(&self) -> bool {
        self.result.is_err()
    }
    /// A user should call `get` on a `GResult` and match on the resulting
    /// dictionary to get the value they want.
    #[func]
    pub fn get(&self) -> Dictionary {
        match &self.result {
            Ok(val) => Dictionary::from([(&"value", val)]),
            Err(err) => Dictionary::from([(&"error", err)]),
        }
    }
}

/// Trait used for assuring that all types consistently use their own
/// pre-defined set of error codes.
pub trait FailsWith {
    type E: ToGodot + FromGodot;

    /// Return a failure
    fn failure(e: &Self::E) -> GResult {
        GResult {
            result: Result::Err(e.to_variant()),
        }
    }

    /// Get the `Result` inside. This is safe.
    fn unwrap(r: GResult) -> Result<Variant, Self::E> {
        match r.result {
            Ok(v) => Result::Ok(v),
            Err(e) => Result::Err(Self::E::from_variant(&e)),
        }
    }
}

pub fn success<V: ToGodot>(v: V) -> GResult {
    GResult {
        result: Result::Ok(v.to_variant()),
    }
}
