//! The goal of this module is to introduce a class called `GResult`
//! which is a light wrapper over `Result`. The idea is to allow different
//! classes implemented in Rust to preserve type information about their methods'
//! returned types as well as the different errors they might produce; all while still
//! allowing GDScript access this information too.

use godot::obj::dom::UserDomain;
use godot::prelude::meta::GodotConvert;
use godot::prelude::*;
use std::fmt::Debug;

/// Class used for communicating results to GDScript.
/// The class has no `init`, so it cannot be created from GDScript.
/// This is fine, our users should not need to create `GResult`s.
#[derive(GodotClass, Debug)]
#[class(base=RefCounted, rename=_Result)]
pub struct GResult {
    #[doc(hidden)]
    result: Result<Variant, GString>,
    #[doc(hidden)]
    tag: i64,
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
    #[func]
    pub fn tag(&self) -> i64 {
        self.tag
    }
    #[func]
    pub fn unsafe_value(&self) -> Variant {
        self.result.clone().unwrap()
    }
    #[func]
    pub fn unsafe_error(&self) -> GString {
        self.result.clone().unwrap_err()
    }

    // #[func]
    // pub fn map(&mut self, Callable)
}

/// Trait used for assuring that all classes consistently use their own
/// set of error codes.
pub trait FailsWith {
    type E: ToGodot + Debug + GodotConvert<Via = i64>; // the error type

    /// Create a failed `GResult` from a previous `Result`.
    fn to_gresult<T>(result: Result<T, Self::E>) -> Gd<GResult>
    where
        T: ToGodot,
    {
        match result {
            Ok(val) => Gd::from_object(GResult {
                result: Ok(val.to_variant()),
                tag: 0, // zero represents success
            }),
            Err(err) => Gd::from_object(GResult {
                result: Err(format!("{:?}", err).to_godot()),
                tag: err.to_godot(),
            }),
        }
    }

    /// Like `to_gresult`, but wraps the returned class in a `Gd<C>`.
    fn to_gresult_class<C>(result: Result<C, Self::E>) -> Gd<GResult>
    where
        C: GodotClass<Declarer = UserDomain>,
    {
        Self::to_gresult(result.map(|c| Gd::from_object(c)))
    }
}
