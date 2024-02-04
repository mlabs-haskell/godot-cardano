use cardano_serialization_lib as CSL;
use CSL::crypto::{ScriptHash, TransactionHash, Vkeywitness, Vkeywitnesses};
use CSL::error::JsError;
use CSL::plutus::{ExUnits, PlutusData, RedeemerTag};
use CSL::tx_builder_constants::TxBuilderConstants;
use CSL::utils::*;
use CSL::{AssetName, MultiAsset, TransactionInput, TransactionOutput};

use uplc::tx::eval_phase_two_raw;

use godot::builtin::meta::GodotConvert;
use godot::prelude::*;

use crate::bigint::BigInt;
use crate::gresult::{FailsWith, GResult};

pub fn multiasset_from_dictionary(dict: &Dictionary) -> MultiAsset {
    let mut assets: MultiAsset = MultiAsset::new();
    dict.iter_shared()
        .typed()
        .for_each(|(unit, amount): (GString, Gd<BigInt>)| {
            assets.set_asset(
                &ScriptHash::from_hex(
                    &unit
                        .to_string()
                        .get(0..56)
                        .expect("Could not extract policy ID"),
                )
                .expect("Could not decode policy ID"),
                &AssetName::new(
                    hex::decode(
                        unit.to_string()
                            .get(56..)
                            .expect("Could not extract asset name"),
                    )
                    .unwrap()
                    .into(),
                )
                .expect("Could not decode asset name"),
                BigNum::from_str(&amount.bind().to_str()).unwrap(),
            );
        });
    return assets;
}

#[derive(GodotClass)]
#[class(base=RefCounted, rename=Signature)]
pub struct Signature {
    pub signature: Vkeywitness,
}

#[derive(GodotClass)]
#[class(base=Node, rename=_Address)]
pub struct Address {
    pub address: CSL::address::Address,
}

#[derive(Debug)]
pub enum AddressError {
    Bech32Error(JsError),
}

impl GodotConvert for AddressError {
    type Via = i64;
}

impl ToGodot for AddressError {
    fn to_godot(&self) -> Self::Via {
        use AddressError::*;
        match self {
            Bech32Error(_) => 1,
        }
    }
}

impl FailsWith for Address {
    type E = AddressError;
}

#[godot_api]
impl Address {
    #[func]
    pub fn from_bech32(address: String) -> Gd<Address> {
        return Gd::from_object(Self {
            address: CSL::address::Address::from_bech32(&address)
                .expect("Could not parse address bech32"),
        });
    }

    pub fn to_bech32(&self) -> Result<String, AddressError> {
        self.address
            .to_bech32(None)
            .map_err(|e| AddressError::Bech32Error(e))
    }

    #[func]
    pub fn _to_bech32(&self) -> Gd<GResult> {
        Self::to_gresult(self.to_bech32())
    }
}

#[derive(Debug)]
pub enum DatumValue {
    NoDatum,
    Hash(PackedByteArray),
    Inline(PackedByteArray),
}

#[derive(GodotClass, Debug)]
#[class(base=RefCounted, rename=Datum)]
pub struct Datum {
    pub datum: DatumValue,
}

#[godot_api]
impl Datum {
    #[func]
    pub fn none() -> Gd<Datum> {
        return Gd::from_object(Datum {
            datum: DatumValue::NoDatum,
        });
    }

    #[func]
    pub fn hash(bytes: PackedByteArray) -> Gd<Datum> {
        return Gd::from_object(Datum {
            datum: DatumValue::Hash(bytes),
        });
    }

    #[func]
    pub fn inline(bytes: PackedByteArray) -> Gd<Datum> {
        return Gd::from_object(Datum {
            datum: DatumValue::Inline(bytes),
        });
    }
}

#[derive(GodotClass, Debug)]
#[class(base=RefCounted, rename=Redeemer)]
pub struct Redeemer {
    pub redeemer: CSL::plutus::Redeemer,
}

#[godot_api]
impl Redeemer {
    #[func]
    fn create(
        tag: u64,
        index: u64,
        data: PackedByteArray,
        ex_units_mem: u64,
        ex_units_steps: u64,
    ) -> Gd<Redeemer> {
        let redeemer_tag: RedeemerTag = match tag {
            0 => RedeemerTag::new_spend(),
            1 => RedeemerTag::new_mint(),
            2 => RedeemerTag::new_cert(),
            3 => RedeemerTag::new_reward(),
            _ => RedeemerTag::new_mint(),
        };
        return Gd::from_object(Redeemer {
            redeemer: CSL::plutus::Redeemer::new(
                &redeemer_tag,
                &BigNum::from(index),
                &PlutusData::from_bytes(data.to_vec()).unwrap(),
                &ExUnits::new(&BigNum::from(ex_units_mem), &BigNum::from(ex_units_steps)),
            ),
        });
    }

    #[func]
    fn get_data(&self) -> PackedByteArray {
        let vec = self.redeemer.data().to_bytes();
        let bytes: &[u8] = vec.as_slice().into();
        PackedByteArray::from(bytes)
    }
}

#[derive(GodotClass, Debug)]
#[class(base=RefCounted, rename=PlutusScript)]
pub struct PlutusScript {
    pub script: CSL::plutus::PlutusScript,
}

#[godot_api]
impl PlutusScript {
    #[func]
    fn create(script: PackedByteArray) -> Gd<PlutusScript> {
        return Gd::from_object(PlutusScript {
            script: CSL::plutus::PlutusScript::new_v2(script.to_vec()),
        });
    }
}

#[derive(GodotClass, Debug)]
#[class(base=RefCounted, rename=_Utxo)]
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
    pub fn create(
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

    pub fn to_transaction_unspent_output(&self) -> TransactionUnspentOutput {
        TransactionUnspentOutput::new(
            &TransactionInput::new(
                &TransactionHash::from_hex(&self.tx_hash.to_string())
                    .expect("Could not decode transaction hash"),
                self.output_index,
            ),
            &TransactionOutput::new(
                &CSL::address::Address::from_bech32(&self.address.to_string())
                    .expect("Could not decode address bech32"),
                &Value::new_with_assets(
                    &to_bignum(
                        self.coin
                            .bind()
                            .b
                            .as_u64()
                            .expect("UTxO Lovelace exceeds maximum")
                            .into(),
                    ),
                    &multiasset_from_dictionary(&self.assets),
                ),
            ),
        )
    }
}

#[derive(GodotClass)]
#[class(base=RefCounted, rename=_Transaction)]
pub struct Transaction {
    pub transaction: CSL::Transaction,

    pub max_ex_units: (u64, u64),
    pub slot_config: (u64, u64, u32),
}

#[godot_api]
impl Transaction {
    #[func]
    fn bytes(&self) -> PackedByteArray {
        let bytes_vec = self.transaction.clone().to_bytes();
        let bytes: &[u8] = bytes_vec.as_slice().into();
        return PackedByteArray::from(bytes);
    }

    #[func]
    fn add_signature(&mut self, signature: Gd<Signature>) {
        // NOTE: destroys? transaction and replaces with a new one. might be better to add
        // signatures to the witness set before the transaction is actually built
        let mut witness_set = self.transaction.witness_set();
        let mut vkey_witnesses = witness_set.vkeys().unwrap_or(Vkeywitnesses::new());
        vkey_witnesses.add(&signature.bind().signature);
        witness_set.set_vkeys(&vkey_witnesses);
        self.transaction = CSL::Transaction::new(
            &self.transaction.body(),
            &witness_set,
            self.transaction.auxiliary_data(),
        );
    }

    #[func]
    fn evaluate(&mut self, gutxos: Array<Gd<Utxo>>) -> Array<Gd<Redeemer>> {
        let mut utxos: Vec<(Vec<u8>, Vec<u8>)> = Vec::new();
        gutxos.iter_shared().for_each(|gutxo| {
            let utxo = gutxo.bind().to_transaction_unspent_output();
            utxos.push((utxo.input().to_bytes(), utxo.output().to_bytes()))
        });

        let eval_result = eval_phase_two_raw(
            &self.transaction.to_bytes(),
            &utxos,
            &TxBuilderConstants::plutus_default_cost_models().to_bytes(),
            self.max_ex_units,
            self.slot_config,
            false,
            |_| {},
        );

        match eval_result {
            Ok(redeemers) => {
                let mut actual_redeemers: Array<Gd<Redeemer>> = Array::new();
                redeemers.iter().for_each(|redeemer| {
                    actual_redeemers.push(Gd::from_object(Redeemer {
                        redeemer: CSL::plutus::Redeemer::from_bytes(redeemer.to_vec()).unwrap(),
                    }))
                });
                actual_redeemers
            }
            Err(_err) => Array::new(),
        }
    }
}
