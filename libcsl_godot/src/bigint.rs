use std::ops::Deref;

use crate::gresult::{FailsWith, GResult};
use cardano_serialization_lib::error::JsError;
use cardano_serialization_lib::utils as CSL;
use godot::builtin::meta::GodotConvert;
use godot::prelude::*;

#[derive(GodotClass, Eq, Hash, Ord, PartialEq, PartialOrd)]
#[class(init, base=RefCounted)]
pub struct BigInt {
    #[init(default = CSL::BigInt::from_str("0").unwrap())]
    #[doc(hidden)]
    pub b: CSL::BigInt,
}

#[derive(Debug)]
pub enum BigIntError {
    CouldNotParseBigInt(JsError),
    CouldNotConvertFromInt(JsError),
}

impl GodotConvert for BigIntError {
    type Via = GString;
}

// TODO: Improve error strings
impl ToGodot for BigIntError {
    fn to_godot(&self) -> Self::Via {
        GString::from(format!("{:?}", self))
    }
}

impl FailsWith for BigInt {
    type E = BigIntError;
}

#[godot_api]
impl BigInt {
    pub fn from_str_(text: String) -> Result<BigInt, BigIntError> {
        CSL::BigInt::from_str(&text).map_or_else(
            |e| Result::Err(BigIntError::CouldNotParseBigInt(e)),
            |b| Result::Ok(Self { b }),
        )
    }

    #[func]
    pub fn from_str(text: String) -> Gd<GResult> {
        Self::to_gresult_class(Self::from_str_(text))
    }

    #[func]
    pub fn to_str(&self) -> String {
        return self.b.to_str();
    }

    #[func]
    pub fn to_string(&self) -> String {
        return self.to_str();
    }

    pub fn from_int_(n: i64) -> Result<BigInt, BigIntError> {
        CSL::BigInt::from_str(&n.to_string()).map_or_else(
            |e| Result::Err(BigIntError::CouldNotConvertFromInt(e)),
            |b| Result::Ok(Self { b }),
        )
    }

    #[func]
    pub fn from_int(n: i64) -> Gd<GResult> {
        Self::to_gresult_class(Self::from_int_(n))
    }

    #[func]
    fn add(&self, other: Gd<BigInt>) -> Gd<BigInt> {
        let b = self.b.add(&other.bind().deref().b);
        return Gd::from_object(Self { b });
    }

    #[func]
    fn mul(&self, other: Gd<BigInt>) -> Gd<BigInt> {
        let b = self.b.mul(&other.bind().deref().b);
        return Gd::from_object(Self { b });
    }

    #[func]
    fn zero() -> Gd<GResult> {
        return Self::from_str("0".to_string());
    }

    #[func]
    fn one() -> Gd<GResult> {
        return Self::from_str("1".to_string());
    }

    #[func]
    fn eq(&self, other: Gd<BigInt>) -> bool {
        return self.b == other.bind().b;
    }

    #[func]
    fn gt(&self, other: Gd<BigInt>) -> bool {
        return self > &other.bind();
    }

    #[func]
    fn lt(&self, other: Gd<BigInt>) -> bool {
        return self < &other.bind();
    }
}
