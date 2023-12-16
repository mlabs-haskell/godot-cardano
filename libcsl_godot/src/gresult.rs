//! The goal of this module is to introduce a class called `GResult`
//! which is a light wrapper over `Result`. The idea is to allow different
//! classes implemented in Rust to preserve type information about their methods'
//! returned types as well as the different errors they might produce; all while still
//! allowing GDScript access this information too.

use godot::obj::dom::UserDomain;
use godot::prelude::*;

/// Class used for communicating results to GDScript.
/// The class has no `init`, so it cannot be created from GDScript.
/// This is fine, our users should not need to create `GResult`s.
#[derive(GodotClass, Debug)]
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
    type E: ToGodot;

    /// Create a failed `GResult` from a previous `Result`.
    fn to_gresult<T>(result: Result<T, Self::E>) -> Gd<GResult>
    where
        T: ToGodot,
    {
        Gd::from_object(GResult {
            result: result
                .map(|val| val.to_variant())
                .map_err(|err| err.to_variant()),
        })
    }

    /// Like `to_gresult`, but wraps the returned class in a `Gd<C>`.
    fn to_gresult_class<C>(result: Result<C, Self::E>) -> Gd<GResult>
    where
        C: GodotClass<Declarer = UserDomain>,
    {
        Self::to_gresult(result.map(|c| Gd::from_object(c)))
    }
}
