use crate::bigint::BigInt;
use cardano_serialization_lib as CSL;
use godot::prelude::*;
use CSL::crypto::{Vkeywitness, Vkeywitnesses};

#[derive(GodotClass)]
#[class(init, base=RefCounted, rename=Signature)]
pub struct Signature {
    pub signature: Option<Vkeywitness>,
}

#[derive(GodotClass, Debug)]
#[class(init, base=RefCounted)]
pub struct Utxo {
    #[var(get)]
    pub tx_hash: GString,
    #[var(get)]
    pub output_index: u32,
    #[var(get)]
    pub address: GString,
    #[var(get)]
    pub coin: Gd<BigInt>,
    #[var(get)]
    pub assets: Dictionary,
}

#[godot_api]
impl Utxo {
    #[func]
    fn create(
        tx_hash: GString,
        output_index: u32,
        address: GString,
        coin: Gd<BigInt>,
        assets: Dictionary,
    ) -> Gd<Utxo> {
        return Gd::from_object(Self {
            tx_hash,
            output_index,
            address,
            coin,
            assets,
        });
    }
}

#[derive(GodotClass)]
#[class(init, base=RefCounted, rename=Transaction)]
pub struct Transaction {
    pub transaction: Option<CSL::Transaction>,
}

#[godot_api]
impl Transaction {
    #[func]
    fn bytes(&self) -> PackedByteArray {
        let bytes_vec = self.transaction.clone().unwrap().to_bytes();
        let bytes: &[u8] = bytes_vec.as_slice().into();
        return PackedByteArray::from(bytes);
    }

    #[func]
    fn add_signature(&mut self, signature: Gd<Signature>) {
        // NOTE: destroys? transaction and replaces with a new one. might be better to add
        // signatures to the witness set before the transaction is actually built
        let transaction = self.transaction.as_ref().unwrap();
        let mut witness_set = transaction.witness_set();
        let mut vkey_witnesses = witness_set.vkeys().unwrap_or(Vkeywitnesses::new());
        vkey_witnesses.add(signature.bind().signature.as_ref().unwrap());
        witness_set.set_vkeys(&vkey_witnesses);
        self.transaction = Some(CSL::Transaction::new(
            &transaction.body(),
            &witness_set,
            transaction.auxiliary_data(),
        ))
    }
}
