use cardano_serialization_lib as CSL;
use CSL::crypto::{ScriptHash, Vkeywitness, Vkeywitnesses};
use CSL::error::JsError;
use CSL::plutus::{ExUnits, PlutusData, RedeemerTag};
use CSL::utils::*;
use CSL::{AssetName, TransactionInput, TransactionOutput};

use uplc::tx::error::Error as UplcError;
use uplc::tx::eval_phase_two_raw;

use godot::builtin::meta::GodotConvert;
use godot::prelude::*;

use crate::bigint::BigInt;
use crate::gresult::{FailsWith, GResult};

#[derive(GodotClass)]
#[class(base=RefCounted, rename=_MultiAsset)]
pub struct MultiAsset {
    pub assets: CSL::MultiAsset,
}

#[derive(Debug)]
pub enum MultiAssetError {
    CouldNotExtractPolicyId(String),
    CouldNotExtractAssetName(String),
    CouldNotDecodeHex(String),
    InvalidAssetName(String),
    OtherError(JsError),
}

impl GodotConvert for MultiAssetError {
    type Via = i64;
}

impl ToGodot for MultiAssetError {
    fn to_godot(&self) -> Self::Via {
        use MultiAssetError::*;
        match self {
            CouldNotExtractPolicyId(_) => 1,
            CouldNotExtractAssetName(_) => 2,
            CouldNotDecodeHex(_) => 3,
            InvalidAssetName(_) => 4,
            OtherError(_) => 5,
        }
    }
}

impl FailsWith for MultiAsset {
    type E = MultiAssetError;
}

impl From<JsError> for MultiAssetError {
    fn from(error: JsError) -> MultiAssetError {
        MultiAssetError::OtherError(error)
    }
}

#[godot_api]
impl MultiAsset {
    pub fn from_dictionary(dict: &Dictionary) -> Result<Self, MultiAssetError> {
        let mut assets: CSL::MultiAsset = CSL::MultiAsset::new();
        for (unit, amount) in dict.iter_shared().typed::<GString, Gd<BigInt>>() {
            assets.set_asset(
                &ScriptHash::from_hex(
                    &unit
                        .to_string()
                        .get(0..56)
                        .ok_or(MultiAssetError::CouldNotExtractPolicyId(unit.to_string()))?,
                )
                .map_err(|_| MultiAssetError::CouldNotDecodeHex(unit.to_string()))?,
                &AssetName::new(
                    hex::decode(
                        unit.to_string()
                            .get(56..)
                            .ok_or(MultiAssetError::CouldNotExtractAssetName(unit.to_string()))?,
                    )
                    .map_err(|_| MultiAssetError::CouldNotDecodeHex(unit.to_string()))?
                    .into(),
                )
                .map_err(|_| MultiAssetError::InvalidAssetName(unit.to_string()))?,
                BigNum::from_str(&amount.bind().to_str())?,
            );
        }
        return Ok(MultiAsset { assets });
    }

    #[func]
    pub fn _from_dictionary(dict: Dictionary) -> Gd<GResult> {
        Self::to_gresult_class(Self::from_dictionary(&dict))
    }

    #[func]
    pub fn empty() -> Gd<MultiAsset> {
        Gd::from_object(MultiAsset {
            assets: CSL::MultiAsset::new(),
        })
    }
}

#[derive(GodotClass)]
#[class(base=RefCounted, rename=_TransactionHash)]
pub struct TransactionHash {
    pub hash: CSL::crypto::TransactionHash,
}

#[derive(Debug)]
pub enum TransactionHashError {
    InvalidHash(JsError),
}

impl GodotConvert for TransactionHashError {
    type Via = i64;
}

impl ToGodot for TransactionHashError {
    fn to_godot(&self) -> Self::Via {
        use TransactionHashError::*;
        match self {
            InvalidHash(_) => 1,
        }
    }
}

impl FailsWith for TransactionHash {
    type E = TransactionHashError;
}

impl From<JsError> for TransactionHashError {
    fn from(error: JsError) -> TransactionHashError {
        TransactionHashError::InvalidHash(error)
    }
}

#[godot_api]
impl TransactionHash {
    fn from_hex(hash: GString) -> Result<Self, TransactionHashError> {
        Ok(Self {
            hash: CSL::crypto::TransactionHash::from_hex(&hash.to_string())?,
        })
    }

    #[func]
    fn _from_hex(hash: GString) -> Gd<GResult> {
        Self::to_gresult_class(Self::from_hex(hash))
    }

    #[func]
    fn to_hex(&self) -> GString {
        self.hash.to_hex().into()
    }
}

#[derive(GodotClass)]
#[class(base=RefCounted, rename=Signature)]
pub struct Signature {
    pub signature: Vkeywitness,
}

#[derive(GodotClass)]
#[class(base=RefCounted, rename=_Address)]
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
    pub fn from_bech32(address: String) -> Result<Address, AddressError> {
        Ok(Self {
            address: CSL::address::Address::from_bech32(&address)
                .map_err(|e| AddressError::Bech32Error(e))?,
        })
    }

    #[func]
    pub fn _from_bech32(address: String) -> Gd<GResult> {
        Self::to_gresult_class(Self::from_bech32(address))
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

#[derive(Debug)]
pub enum RedeemerError {
    DecodeRedeemerError(CSL::error::DeserializeError),
    UnknownRedeemerTag(u64),
}

impl GodotConvert for RedeemerError {
    type Via = i64;
}

impl ToGodot for RedeemerError {
    fn to_godot(&self) -> Self::Via {
        use RedeemerError::*;
        match self {
            DecodeRedeemerError(_) => 1,
            UnknownRedeemerTag(_) => 2,
        }
    }
}

impl FailsWith for Redeemer {
    type E = RedeemerError;
}

impl From<CSL::error::DeserializeError> for RedeemerError {
    fn from(error: CSL::error::DeserializeError) -> RedeemerError {
        RedeemerError::DecodeRedeemerError(error)
    }
}

#[godot_api]
impl Redeemer {
    fn create(
        tag: u64,
        index: u64,
        data: PackedByteArray,
        ex_units_mem: u64,
        ex_units_steps: u64,
    ) -> Result<Redeemer, RedeemerError> {
        let redeemer_tag: RedeemerTag = match tag {
            0 => Ok(RedeemerTag::new_spend()),
            1 => Ok(RedeemerTag::new_mint()),
            2 => Ok(RedeemerTag::new_cert()),
            3 => Ok(RedeemerTag::new_reward()),
            _ => Err(RedeemerError::UnknownRedeemerTag(tag)),
        }?;
        let data = &PlutusData::from_bytes(data.to_vec())?;
        Ok(Redeemer {
            redeemer: CSL::plutus::Redeemer::new(
                &redeemer_tag,
                &BigNum::from(index),
                data,
                &ExUnits::new(&BigNum::from(ex_units_mem), &BigNum::from(ex_units_steps)),
            ),
        })
    }

    #[func]
    fn _create(
        tag: u64,
        index: u64,
        data: PackedByteArray,
        ex_units_mem: u64,
        ex_units_steps: u64,
    ) -> Gd<GResult> {
        return Self::to_gresult_class(Self::create(
            tag,
            index,
            data,
            ex_units_mem,
            ex_units_steps,
        ));
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

    #[func]
    fn hash(&self) -> PackedByteArray {
        let hash = self.script.hash();
        let bound = hash.to_bytes();
        let bytes: &[u8] = bound.as_slice().into();
        PackedByteArray::from(bytes)
    }
}

#[derive(GodotClass, Debug)]
#[class(base=RefCounted, rename=_PubKeyHash)]
pub struct PubKeyHash {
    pub hash: CSL::crypto::Ed25519KeyHash
}

#[derive(Debug)]
pub enum PubKeyHashError {
    FromHexError(JsError),
}

impl GodotConvert for PubKeyHashError {
    type Via = i64;
}

impl ToGodot for PubKeyHashError {
    fn to_godot(&self) -> Self::Via {
        use PubKeyHashError::*;
        match self {
            FromHexError(_) => 1,
        }
    }
}

impl FailsWith for PubKeyHash {
    type E = PubKeyHashError;
}

#[godot_api]
impl PubKeyHash {
    pub fn from_hex(hex: String) -> Result<PubKeyHash, PubKeyHashError> {
        let hash = CSL::crypto::Ed25519KeyHash::from_hex(hex.as_str()).map_err(PubKeyHashError::FromHexError)?;
        Ok(PubKeyHash { hash })
    }

    #[func]
    pub fn _from_hex(hex: GString) -> Gd<GResult> {
        Self::to_gresult_class(Self::from_hex(hex.to_string()))
    }
}


#[derive(GodotClass, Debug)]
#[class(base=RefCounted, rename=_Utxo)]
pub struct Utxo {
    #[var(get)]
    pub tx_hash: Gd<TransactionHash>,
    #[var(get)]
    pub output_index: u32,
    #[var(get)]
    pub address: Gd<Address>,
    #[var(get)]
    pub coin: Gd<BigInt>,
    #[var(get)]
    pub assets: Gd<MultiAsset>,
}

#[godot_api]
impl Utxo {
    #[func]
    pub fn create(
        tx_hash: Gd<TransactionHash>,
        output_index: u32,
        address: Gd<Address>,
        coin: Gd<BigInt>,
        assets: Gd<MultiAsset>,
    ) -> Gd<Utxo> {
        Gd::from_object(Self {
            tx_hash,
            output_index,
            address,
            coin,
            assets,
        })
    }

    pub fn to_transaction_unspent_output(&self) -> TransactionUnspentOutput {
        TransactionUnspentOutput::new(
            &TransactionInput::new(&self.tx_hash.bind().hash, self.output_index),
            &TransactionOutput::new(
                &self.address.bind().address,
                &Value::new_with_assets(
                    &to_bignum(
                        self.coin
                            .bind()
                            .b
                            .as_u64()
                            .or(Some(BigNum::from(std::u64::MAX)))
                            .unwrap()
                            .into(),
                    ),
                    &self.assets.bind().assets,
                ),
            ),
        )
    }
}

#[derive(GodotClass)]
#[class(base=RefCounted, rename=_CostModels)]
pub struct CostModels {
    pub cost_models: CSL::plutus::Costmdls,
}

#[godot_api]
impl CostModels {
    #[func]
    pub fn create() -> Gd<CostModels> {
        Gd::from_object(CostModels {
            cost_models: CSL::plutus::Costmdls::new(),
        })
    }

    fn build_model(ops: Array<u64>) -> CSL::plutus::CostModel {
        let mut model = CSL::plutus::CostModel::new();
        for (i, op) in ops.iter_shared().enumerate() {
            // NOTE: `model.set` never seems to actually fail?
            model.set(i, &Int::new(&BigNum::from(op))).unwrap();
        }
        model
    }

    #[func]
    pub fn set_plutus_v1_model(&mut self, ops: Array<u64>) {
        self.cost_models.insert(
            &CSL::plutus::Language::new_plutus_v1(),
            &Self::build_model(ops),
        );
    }

    #[func]
    pub fn set_plutus_v2_model(&mut self, ops: Array<u64>) {
        self.cost_models.insert(
            &CSL::plutus::Language::new_plutus_v2(),
            &Self::build_model(ops),
        );
    }
}

#[derive(GodotClass, Debug)]
#[class(base=RefCounted, rename=_EvaluationResult)]
pub struct EvaluationResult {
    pub redeemers: Array<Gd<Redeemer>>,
    pub fee: u64,
}

#[godot_api]
impl EvaluationResult {}

#[derive(GodotClass)]
#[class(base=RefCounted, rename=_Transaction)]
pub struct Transaction {
    pub transaction: CSL::Transaction,

    pub max_ex_units: (u64, u64),
    pub slot_config: (u64, u64, u32),
    pub cost_models: CSL::plutus::Costmdls,
}

#[derive(Debug)]
pub enum TransactionError {
    EvaluationError(UplcError),
    DeserializeError(CSL::error::DeserializeError),
}

impl GodotConvert for TransactionError {
    type Via = i64;
}

impl ToGodot for TransactionError {
    fn to_godot(&self) -> Self::Via {
        use TransactionError::*;
        match self {
            EvaluationError(_) => 1,
            DeserializeError(_) => 2,
        }
    }
}

impl FailsWith for Transaction {
    type E = TransactionError;
}

impl From<UplcError> for TransactionError {
    fn from(error: UplcError) -> TransactionError {
        TransactionError::EvaluationError(error)
    }
}

impl From<CSL::error::DeserializeError> for TransactionError {
    fn from(error: CSL::error::DeserializeError) -> TransactionError {
        TransactionError::DeserializeError(error)
    }
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
    fn hash(&self) -> Gd<TransactionHash> {
        Gd::from_object(TransactionHash {
            hash: hash_transaction(&self.transaction.body()),
        })
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

    fn evaluate(&mut self, gutxos: Array<Gd<Utxo>>) -> Result<EvaluationResult, TransactionError> {
        let mut utxos: Vec<(Vec<u8>, Vec<u8>)> = Vec::new();
        for gutxo in gutxos.iter_shared() {
            let utxo = gutxo.bind().to_transaction_unspent_output();
            utxos.push((utxo.input().to_bytes(), utxo.output().to_bytes()))
        }

        let redeemers = eval_phase_two_raw(
            &self.transaction.to_bytes(),
            &utxos,
            &self.cost_models.to_bytes(),
            self.max_ex_units,
            self.slot_config,
            false,
            |_| {},
        )?;

        let mut actual_redeemers: Array<Gd<Redeemer>> = Array::new();
        for redeemer in redeemers.iter() {
            actual_redeemers.push(Gd::from_object(Redeemer {
                redeemer: CSL::plutus::Redeemer::from_bytes(redeemer.to_vec())?,
            }))
        }
        Ok(EvaluationResult {
            redeemers: actual_redeemers,
            fee: self.transaction.body().fee().into(),
        })
    }

    #[func]
    fn _evaluate(&mut self, gutxos: Array<Gd<Utxo>>) -> Gd<GResult> {
        Self::to_gresult_class(self.evaluate(gutxos))
    }
}
