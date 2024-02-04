use std::io::Cursor;
use std::num::TryFromIntError;

use cbor_event::{de::Deserializer, se::Serializer, Len, Type};

use cardano_serialization_lib::error::DeserializeError;
use cardano_serialization_lib::utils as CSL;

use godot::builtin::meta::GodotConvert;
use godot::prelude::*;

use crate::bigint::BigInt;
use crate::gresult::{GResult, FailsWith};

#[derive(GodotClass)]
#[class(base=RefCounted, rename=_Constr)]
struct Constr {
    #[var(get)]
    constructor: Gd<BigInt>,
    #[var(get)]
    fields: Array<Variant>,
}

#[godot_api]
impl Constr {
    fn create(constructor: BigInt, fields: Array<Variant>) -> Gd<Constr> {
        Gd::from_object(Self {
            constructor: Gd::from_object(constructor),
            fields,
        })
    }

    #[func]
    fn _create(constructor: Gd<BigInt>, fields: Array<Variant>) -> Gd<Constr> {
        Gd::from_object(Self {
            constructor,
            fields,
        })
    }
}

#[derive(GodotClass)]
#[class(base=RefCounted, rename=_Bytes)]
struct Bytes {
    #[var]
    bytes: PackedByteArray
}

#[derive(GodotClass)]
#[class(base=RefCounted, rename=_PlutusData)]
struct PlutusData {
    data: Variant
}

#[godot_api]
impl PlutusData {
    #[func]
    fn get_data(&mut self) -> Variant {
        self.data.clone()
    }
}

#[derive(GodotClass, Eq, Hash, Ord, PartialEq, PartialOrd)]
#[class(init, base=RefCounted, rename=_Cbor)]
struct Cbor {}

#[derive(Debug)]
enum CborError {
    DecodeIntError,
    DecodeBytesError,
    DecodeConstrError,
    DecodeTagError,
    DecodeTypeError,
    EncodeTagError,
    EncodeUnknownObjectError,
    EncodeUnsupportedTypeError,
    CborEventError(cbor_event::Error),
}

use CborError::*;

impl From<TryFromIntError> for CborError {
    fn from(_err: TryFromIntError) -> Self {
        DecodeIntError
    }
}

impl From<cbor_event::Error> for CborError {
    fn from(err: cbor_event::Error) -> Self {
        CborEventError(err)
    }
}

impl From<DeserializeError> for CborError {
    fn from(_err: DeserializeError) -> Self {
        DecodeBytesError
    }
}

impl GodotConvert for CborError {
    type Via = i64;
}

impl ToGodot for CborError {
    fn to_godot(&self) -> Self::Via {
        match self {
            DecodeIntError => 1,
            DecodeBytesError => 2,
            DecodeConstrError => 3,
            DecodeTagError => 4,
            DecodeTypeError => 5,
            EncodeTagError => 6,
            EncodeUnknownObjectError => 7,
            EncodeUnsupportedTypeError => 8,
            CborEventError(_) => 9,
        }
    }
}

impl FailsWith for Cbor {
    type E = CborError;
}

#[godot_api]
impl Cbor {
    fn decode_len<F>(
        raw: &mut Deserializer<Cursor<Vec<u8>>>,
        len: Len,
        mut next: F,
    ) -> Result<(), CborError>
    where
        F: FnMut(&mut Deserializer<Cursor<Vec<u8>>>) -> Result<(), CborError>,
    {
        match len {
            Len::Len(len) => {
                let mut i = 0;
                while i < len {
                    next(raw)?;
                    i += 1;
                }
                Ok(())
            }
            Len::Indefinite => {
                while !raw.special_break()? {
                    next(raw)?;
                }
                Ok(())
            }
        }
    }

    fn decode_array(
        raw: &mut Deserializer<Cursor<Vec<u8>>>,
    ) -> Result<Array<Variant>, CborError> {
        let mut array: Array<Variant> = Array::new();
        let len = raw.array()?;
        Self::decode_len(raw, len, |raw| {
            array.push(Self::decode_variant(raw)?);
            Ok(())
        })?;
        Ok(array)
    }

    fn decode_tagged(
        raw: &mut Deserializer<Cursor<Vec<u8>>>,
        tag: i64,
    ) -> Result<Variant, CborError> {
        if tag >= 121 && tag <= 127 {
            let fields = Self::decode_array(raw)?;
            Ok(Constr::create(BigInt::from_int(tag - 121), fields).to_variant())
        } else if tag >= 1280 && tag <= 1400 {
            let fields = Self::decode_array(raw)?;
            Ok(Constr::create(BigInt::from_int(tag - 1280 + 7), fields).to_variant())
        } else if tag == 102 {
            match raw.array()? {
                Len::Len(2) => {
                    let i = raw.unsigned_integer()?.try_into()?;
                    let constructor = BigInt::from_int(i);
                    let fields = Self::decode_array(raw)?;
                    Ok(Constr::create(constructor, fields).to_variant())
                }
                _ => Err(DecodeConstrError),
            }
        } else if tag == 2 || tag == 3 {
            let bytes = raw.bytes()?;
            // TODO: find a nicer way
            let mut serializer = Serializer::new_vec();
            serializer.write_tag(tag.try_into()?)?;
            serializer.write_bytes(bytes)?;
            let bound = serializer.finalize();
            let b = CSL::BigInt::from_bytes(bound)?;
            Ok(Gd::from_object(BigInt { b }).to_variant())
        } else {
            Err(DecodeTagError)
        }
    }

    fn decode_variant(raw: &mut Deserializer<Cursor<Vec<u8>>>) -> Result<Variant, CborError> {
        match raw.cbor_type()? {
            Type::UnsignedInteger => {
                let i = raw.unsigned_integer()?.try_into()?;
                let b = BigInt::from_int(i);
                Ok(Gd::from_object(b).to_variant())
            }
            Type::NegativeInteger => {
                let i = raw.negative_integer()?;
                let b = BigInt::from_int(i);
                Ok(Gd::from_object(b).to_variant())
            }
            Type::Bytes => {
                let b = raw.bytes()?;
                let bytes: &[u8] = b.as_slice().into();
                Ok(PackedByteArray::from(bytes).to_variant())
            }
            Type::Text => {
                let t = raw.text()?;
                Ok(t.to_variant())
            }
            Type::Array => {
                let a = Self::decode_array(raw)?;
                Ok(a.to_variant())
            }
            Type::Map => {
                let mut dict: Dictionary = Dictionary::new();
                let len = raw.map()?;
                Self::decode_len(raw, len, |raw| {
                    dict.set(Self::decode_variant(raw)?, Self::decode_variant(raw)?);
                    Ok(())
                })?;
                Ok(dict.to_variant())
            }
            Type::Tag => {
                let tag = raw.tag()?.try_into()?;
                Self::decode_tagged(raw, tag)
            }
            _ => Err(DecodeTypeError),
        }
    }

    fn to_variant(bytes: PackedByteArray) -> Result<PlutusData, CborError> {
        let vec = bytes.to_vec();
        let mut raw = Deserializer::from(Cursor::new(vec));
        Ok(PlutusData { data: Self::decode_variant(&mut raw)? })
    }

    #[func]
    fn _to_variant(bytes: PackedByteArray) -> Gd<GResult> {
        Self::to_gresult_class(Self::to_variant(bytes))
    }

    fn encode_variant(
        variant: Variant,
        serializer: &mut Serializer<Vec<u8>>,
    ) -> Result<(), CborError> {
        match variant.get_type() {
            VariantType::Array => {
                let array: Array<Variant> = variant.to();
                serializer.write_array(Len::Len(array.len().try_into().unwrap()))?;
                for item in array.iter_shared() {
                    Self::encode_variant(item, serializer)?;
                }
            }
            VariantType::Dictionary => {
                let dict: Dictionary = variant.to();
                serializer.write_map(Len::Len(dict.len().try_into().unwrap()))?;
                for (key, value) in dict.iter_shared() {
                    Self::encode_variant(key, serializer)?;
                    Self::encode_variant(value, serializer)?;
                }
            }
            VariantType::PackedByteArray => {
                let bytes: PackedByteArray = variant.to();
                let vec = bytes.to_vec();
                serializer.write_bytes(vec)?;
            }
            VariantType::Object => {
                let class: String = variant.call("get_class", &[]).to();
                match class.as_str() {
                    "_Constr" => {
                        let gd_constr: Gd<Constr> = variant.to();
                        let constr = gd_constr.bind();
                        let constructor_int: u64 = constr
                            .constructor
                            .bind()
                            .b
                            .as_u64()
                            .ok_or(EncodeTagError)?
                            .into();

                        if constructor_int <= 7 {
                            serializer.write_tag(121 + constructor_int)?;
                        } else if constructor_int <= 127 {
                            serializer.write_tag(1280 + constructor_int)?;
                        } else {
                            serializer.write_array(Len::Len(2))?;
                            serializer.write_unsigned_integer(constructor_int)?;
                            Self::encode_variant(constr.fields.to_variant(), serializer)?;
                        }
                        Self::encode_variant(constr.fields.to_variant(), serializer)?;
                    }
                    "_BigInt" => {
                        let gd_bigint: Gd<BigInt> = variant.to();
                        let b = &gd_bigint.bind();
                        serializer.write_raw_bytes(&b.b.to_bytes()).unwrap();
                    }
                    _ => Err(EncodeUnknownObjectError)?,
                }
            }
            _ => Err(EncodeUnsupportedTypeError)?
        }
        Ok(())
    }

    fn from_variant(variant: Variant) -> Result<Bytes, CborError> {
        let mut serializer = Serializer::new_vec();
        Self::encode_variant(variant, &mut serializer)?;
        let bound = serializer.finalize();
        let bytes: &[u8] = bound.as_slice().into();
        Ok(Bytes { bytes: PackedByteArray::from(bytes) })
    }

    #[func]
    fn _from_variant(variant: Variant) -> Gd<GResult> {
        Self::to_gresult_class(Self::from_variant(variant))
    }
}
