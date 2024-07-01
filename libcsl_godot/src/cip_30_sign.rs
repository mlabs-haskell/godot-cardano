use cardano_message_signing::utils::ToBytes;

use godot::prelude::*;

use crate::cip_8_sign::DataSignatureCOSE1;

#[derive(GodotClass)]
#[class(base=RefCounted, rename=DataSignature)]
pub struct DataSignature {
    pub cose_key: PackedByteArray,
    pub cose_sig1: PackedByteArray,
}

#[godot_api]
impl DataSignature {
    pub fn cose_key_hex(&self) -> String {
        hex::encode(self.cose_key.to_vec())
    }

    #[func]
    pub fn _cose_key_hex(&self) -> String {
        Self::cose_key_hex(&self)
    }

    pub fn cose_sig1_hex(&self) -> String {
        hex::encode(self.cose_sig1.to_vec())
    }

    #[func]
    pub fn _cose_sig1_hex(&self) -> String {
        Self::cose_sig1_hex(&self)
    }
}

impl From<DataSignatureCOSE1> for DataSignature {
    fn from(ds: DataSignatureCOSE1) -> Self {
        DataSignature {
            cose_key: ds.cose_key.to_bytes().as_slice().into(),
            cose_sig1: ds.cose_sig1.to_bytes().as_slice().into(),
        }
    }
}
