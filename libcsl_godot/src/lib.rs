use std::ops::Deref;
use std::io::Cursor;

use cbor_event::{de::Deserializer, se::{Serializer}, Len, Type};

use cardano_serialization_lib::address::{
    Address,
    BaseAddress,
    NetworkInfo,
    StakeCredential
};
use cardano_serialization_lib::crypto::{
    Bip32PrivateKey, ScriptHash, TransactionHash, Vkeywitness, Vkeywitnesses,
};
use cardano_serialization_lib::error::JsError;
use cardano_serialization_lib::fees::LinearFee;
use cardano_serialization_lib::output_builder::*;
use cardano_serialization_lib::tx_builder::*;
use cardano_serialization_lib::tx_builder::mint_builder::*;
use cardano_serialization_lib::tx_builder_constants::TxBuilderConstants;
use cardano_serialization_lib::utils::*;
use cardano_serialization_lib::{
    AssetName, MultiAsset, Transaction, TransactionInput, TransactionOutput, TransactionWitnessSet,
};
use cardano_serialization_lib::tx_builder::tx_inputs_builder::{
    PlutusScriptSource,
    TxInputsBuilder
};
use cardano_serialization_lib::plutus::{
    ExUnits,
    PlutusData,
    PlutusScript,
    PlutusScripts,
    Redeemer,
    Redeemers,
    RedeemerTag,
};
use cardano_serialization_lib::utils as CSL;

use bip32::{Language, Mnemonic};

use godot::builtin::meta::GodotConvert;
use godot::prelude::*;

use uplc::tx::eval_phase_two_raw;

pub mod bigint;
pub mod gresult;

use bigint::BigInt;
use gresult::FailsWith;

use crate::gresult::GResult;

struct MyExtension;

#[derive(GodotClass)]
#[class(base=Object)]
struct Constr {
    #[var(get)]
    constructor: Gd<BigInt>,
    #[var(get)]
    fields: Array<Variant>
}

#[godot_api]
impl Constr {
    fn create(constructor: BigInt, fields: Array<Variant>) -> Gd<Constr> {
        Gd::from_object(
            Self {
                constructor: Gd::from_object(constructor),
                fields
            }
        )
    }

    #[func]
    fn _create(constructor: Gd<BigInt>, fields: Array<Variant>) -> Gd<Constr> {
        Gd::from_object(
            Self {
                constructor,
                fields
            }
        )
    }
}

#[derive(GodotClass, Eq, Hash, Ord, PartialEq, PartialOrd)]
#[class(init, base=RefCounted)]
struct Cbor {
}

#[godot_api] 
impl Cbor {
    fn decode_array(raw: &mut Deserializer<Cursor<Vec<u8>>>) -> Array<Variant> {
        let mut array: Array<Variant> = Array::new();
        let result = raw.array_with(|item| {
            array.push(Self::decode_variant(item));
            return Ok(());
        });
        match result {
            Ok(_) => (),
            Err(err) => godot_print!("got error: {}", err)
        }
        array
    }

    fn decode_variant(raw: &mut Deserializer<Cursor<Vec<u8>>>) -> Variant {
        return match raw.cbor_type() {
            Err(err) => { 
                godot_print!("error: {}", err);
                Variant::nil()
            },
            Ok(Type::UnsignedInteger) => {
                Gd::from_object(
                    BigInt::from_str(
                        raw.unsigned_integer()
                           .unwrap()
                           .to_string()
                    ).unwrap()
                ).to_variant()
            },
            Ok(Type::NegativeInteger) => {
                Gd::from_object(
                    BigInt::from_int(raw.negative_integer().unwrap()).unwrap()
                ).to_variant()
            },
            Ok(Type::Bytes) => {
                let bound = raw.bytes().unwrap();
                let bytes: &[u8] = bound.as_slice().into();
                PackedByteArray::from(bytes).to_variant()
            },
            Ok(Type::Text) => {
                raw.text().unwrap().to_variant()
            },
            Ok(Type::Array) => {
                Self::decode_array(raw).to_variant()
            },
            Ok(Type::Map) => {
                let mut dict: Dictionary = Dictionary::new();
                let result = raw.map_with(|item| {
                    let key = Self::decode_variant(item);
                    let value = Self::decode_variant(item);
                    dict.insert(key, value);
                    return Ok(());
                });
                match result {
                    Ok(_) => (),
                    Err(err) => godot_print!("got error: {}", err)
                }
                dict.to_variant()
            },
            Ok(Type::Tag) => {
                let tag: i64 = raw.tag().unwrap().try_into().unwrap();
                if tag >= 121 && tag <= 127 {
                    Constr::create(
                        BigInt::from_int(tag - 121).unwrap(),
                        Self::decode_array(raw)
                    ).to_variant()
                } else if tag >= 1280 && tag <= 1400 {
                    Constr::create(
                        BigInt::from_int(tag - 1280 + 7).unwrap(),
                        Self::decode_array(raw)
                    ).to_variant()
                } else if tag == 102 {
                    match raw.array() {
                        Ok(Len::Len(2)) => {
                            Constr::create(
                                BigInt::from_str(raw.unsigned_integer().unwrap().to_string()).unwrap(),
                                Self::decode_array(raw)
                            ).to_variant()
                        },
                        _ => {
                            godot_print!("invalid constr data");
                            Variant::nil()
                        }
                    }
                } else if tag == 2 || tag == 3 {
                    match raw.bytes() {
                        Ok(bytes) => {
                            // TODO: find a nicer way
                            let mut serializer = Serializer::new_vec();
                            serializer.write_tag(tag.try_into().unwrap()).unwrap();
                            serializer.write_bytes(bytes).unwrap();
                            let bound = serializer.finalize();
                            Gd::from_object(BigInt {
                                b: CSL::BigInt::from_bytes(bound).unwrap()
                            }).to_variant()
                        },
                        _ => {
                            godot_print!("invalid bigint data");
                            Variant::nil()
                        }
                    }
                } else {
                    Variant::nil()
                }
            },
            Ok(_) => {
                godot_print!("Got item");
                Variant::nil()
            },
        };
    }

    #[func]
    fn to_variant(bytes: PackedByteArray) -> Variant {
        let vec = bytes.to_vec();
        let mut raw = Deserializer::from(Cursor::new(vec));
        return Self::decode_variant(&mut raw);
    }

    fn encode_variant(variant: Variant, serializer: &mut Serializer<Vec<u8>>) {
        match variant.get_type() {
            VariantType::Array => {
                let array: Array<Variant> = variant.to();
                serializer.write_array(Len::Len(array.len().try_into().unwrap())).unwrap();
                for item in array.iter_shared() {
                    Self::encode_variant(item, serializer)
                }
            },
            VariantType::Dictionary => {
                let dict: Dictionary = variant.to();
                serializer.write_map(Len::Len(dict.len().try_into().unwrap())).unwrap();
                for (key, value) in dict.iter_shared() {
                    Self::encode_variant(key, serializer);
                    Self::encode_variant(value, serializer);
                }
            },
            VariantType::PackedByteArray => {
                let bytes: PackedByteArray = variant.to();
                let vec = bytes.to_vec();
                serializer.write_bytes(vec).unwrap();
            },
            VariantType::Object => {
                let class: String = variant.call("get_class", &[]).to();
                match class.as_str() {
                    "Constr" => {
                        let gd_constr: Gd<Constr> = variant.to();
                        let constr = gd_constr.bind();
                        let constructor_int: u64 = constr.constructor.bind().b.as_u64().unwrap().into();

                        if constructor_int <= 7 {
                            serializer.write_tag(121 + constructor_int).unwrap();
                        } else if constructor_int <= 127 {
                            serializer.write_tag(1280 + constructor_int).unwrap();
                        } else {
                            serializer.write_array(Len::Len(2)).unwrap();
                            serializer.write_unsigned_integer(constructor_int).unwrap();
                            Self::encode_variant(constr.fields.to_variant(), serializer);
                        }
                        Self::encode_variant(constr.fields.to_variant(), serializer);
                    },
                    "BigInt" => {
                        let gd_bigint: Gd<BigInt> = variant.to();
                        let b = &gd_bigint.bind();
                        serializer.write_raw_bytes(&b.b.to_bytes()).unwrap();
                    },
                    _ => () // todo: handle unknown objects
                }
            }
            _ => godot_error!("Don't know how to encode type"),
        };
    }

    #[func]
    fn from_variant(variant: Variant) -> PackedByteArray {
        let mut serializer = Serializer::new_vec();
        Self::encode_variant(variant, &mut serializer);
        let bound = serializer.finalize();
        let bytes: &[u8] = bound.as_slice().into();
        return PackedByteArray::from(bytes);
    }
}

////////////////////////////////////////////////////////////////////////////////
/// Cardano types

#[derive(GodotClass, Debug)]
#[class(init, base=RefCounted, rename=_Utxo)]
struct Utxo {
    #[var(get)]
    tx_hash: GString,
    #[var(get)]
    output_index: u32,
    #[var(get)]
    address: GString,
    #[var(get)]
    coin: Gd<BigInt>,
    #[var(get)]
    assets: Dictionary,
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

    fn to_transaction_unspent_output(&self) -> TransactionUnspentOutput {
        TransactionUnspentOutput::new(
            &TransactionInput::new(
                &TransactionHash::from_hex(&self.tx_hash.to_string()).expect("Could not decode transaction hash"),
                self.output_index
            ),
            &TransactionOutput::new(
                &Address::from_bech32(&self.address.to_string()).expect("Could not decode address bech32"), 
                &Value::new_with_assets(
                    &to_bignum(self.coin.bind().b.as_u64().expect("UTxO Lovelace exceeds maximum").into()),
                    &multiasset_from_dictionary(&self.assets)
                )
            )
        )
    }
}

#[derive(GodotClass)]
#[class(init, base=RefCounted)]
struct ProtocolParameters {
    coins_per_utxo_byte: u64,
    pool_deposit: u64,
    key_deposit: u64,
    max_value_size: u32,
    max_tx_size: u32,
    linear_fee_constant: u64,
    linear_fee_coefficient: u64,
    max_cpu_units: u64,
    max_mem_units: u64,
}

#[godot_api]
impl ProtocolParameters {
    #[func]
    fn create(
        coins_per_utxo_byte: u64,
        pool_deposit: u64,
        key_deposit: u64,
        max_value_size: u32,
        max_tx_size: u32,
        linear_fee_constant: u64,
        linear_fee_coefficient: u64,
        max_cpu_units: u64,
        max_mem_units: u64,
    ) -> Gd<ProtocolParameters> {
        return Gd::from_object(Self {
            coins_per_utxo_byte,
            pool_deposit,
            key_deposit,
            max_value_size,
            max_tx_size,
            linear_fee_constant,
            linear_fee_coefficient,
            max_cpu_units,
            max_mem_units
        });
    }
}

fn harden(index: u32) -> u32 {
    return index | 0x80000000;
}

fn multiasset_from_dictionary(dict: &Dictionary) -> MultiAsset {
    let mut assets: MultiAsset = MultiAsset::new();
    dict.iter_shared().typed().for_each(|(unit, amount): (GString, Gd<BigInt>)| {
        assets.set_asset(
            &ScriptHash::from_hex(&unit.to_string().get(0..56).expect("Could not extract policy ID")).expect("Could not decode policy ID"),
            &AssetName::new(hex::decode(unit.to_string().get(56..).expect("Could not extract asset name")).unwrap().into()).expect("Could not decode asset name"),
            BigNum::from_str(&amount.bind().to_str()).unwrap()
        );
    });
    return assets;
}

#[derive(GodotClass)]
#[class(base=RefCounted, rename=_PrivateKeyAccount)]
struct PrivateKeyAccount {
    #[var]
    account_index: u32,
    master_private_key: Bip32PrivateKey,
}

#[derive(Debug)]
pub enum PrivateKeyAccountError {
    BadPhrase(bip32::Error),
    Bech32Error(JsError),
}

impl GodotConvert for PrivateKeyAccountError {
    type Via = i64;
}

impl ToGodot for PrivateKeyAccountError {
    fn to_godot(&self) -> Self::Via {
        use PrivateKeyAccountError::*;
        match self {
            BadPhrase(_) => 1,
            Bech32Error(_) => 2,
        }
    }
}

impl FailsWith for PrivateKeyAccount {
    type E = PrivateKeyAccountError;
}

#[godot_api]
impl PrivateKeyAccount {
    fn from_mnemonic(phrase: String) -> Result<PrivateKeyAccount, PrivateKeyAccountError> {
        let mnemonic = Mnemonic::new(
            phrase
                .to_lowercase()
                .split_whitespace()
                .collect::<Vec<_>>()
                .join(" "),
            Language::English,
        )
        .map_err(|e| PrivateKeyAccountError::BadPhrase(e))?;

        Ok(Self {
            master_private_key: Bip32PrivateKey::from_bip39_entropy(mnemonic.entropy(), &[]),
            account_index: 0,
        })
    }

    #[func]
    fn _from_mnemonic(phrase: String) -> Gd<GResult> {
        Self::to_gresult_class(Self::from_mnemonic(phrase))
    }

    fn get_account_root(&self) -> Bip32PrivateKey {
        self.master_private_key
            .derive(harden(1852))
            .derive(harden(1815))
            .derive(harden(self.account_index))
    }

    fn get_address(&self) -> Address {
        let account_root = self.get_account_root();
        let spend = account_root.derive(0).derive(0).to_public();
        let stake = account_root.derive(2).derive(0).to_public();
        let spend_cred = StakeCredential::from_keyhash(&spend.to_raw_key().hash());
        let stake_cred = StakeCredential::from_keyhash(&stake.to_raw_key().hash());

        BaseAddress::new(
            NetworkInfo::testnet_preview().network_id(),
            &spend_cred,
            &stake_cred,
        )
        .to_address()
    }
    
    #[func]
    fn _get_address(&self) -> Gd<GAddress> {
        Gd::from_object(GAddress { address: self.get_address() })
    }

    /// It may fail due to a conversion error to Bech32.
    // FIXME: We should be using a prefix that depends on the network we are connecting to.
    fn get_address_bech32(&self) -> Result<String, PrivateKeyAccountError> {
        let addr = self.get_address();
        addr.to_bech32(None)
            .map_err(|e| PrivateKeyAccountError::Bech32Error(e))
    }

    #[func]
    fn _get_address_bech32(&self) -> Gd<GResult> {
        Self::to_gresult(self.get_address_bech32())
    }

    fn sign_transaction(&self, gtx: &GTransaction) -> GSignature {
        let account_root = self.get_account_root();
        let spend_key = account_root.derive(0).derive(0).to_raw_key();
        let tx_hash = hash_transaction(&gtx.transaction.body());
        GSignature {
            signature: make_vkey_witness(&tx_hash, &spend_key),
        }
    }

    #[func]
    fn _sign_transaction(&self, gtx: Gd<GTransaction>) -> Gd<GSignature> {
        Gd::from_object(self.sign_transaction(&gtx.bind()))
    }
}

// TODO: qualify all CSL types and skip renaming
#[derive(GodotClass)]
#[class(base=RefCounted, rename=Signature)]
struct GSignature {
    signature: Vkeywitness
}

#[derive(GodotClass)]
#[class(base=RefCounted, rename=_Transaction)]
struct GTransaction {
    transaction: Transaction,

    max_ex_units: (u64, u64),
    slot_config: (u64, u64, u32),
}

#[godot_api]
impl GTransaction {
    #[func]
    fn bytes(&self) -> PackedByteArray {
        let bytes_vec = self.transaction.clone().to_bytes();
        let bytes: &[u8] = bytes_vec.as_slice().into();
        return PackedByteArray::from(bytes);
    }

    #[func]
    fn add_signature(&mut self, signature: Gd<GSignature>) {
        // NOTE: destroys? transaction and replaces with a new one. might be better to add
        // signatures to the witness set before the transaction is actually built
        let mut witness_set = self.transaction.witness_set();
        let mut vkey_witnesses = witness_set.vkeys().unwrap_or(Vkeywitnesses::new());
        vkey_witnesses.add(&signature.bind().signature);
        witness_set.set_vkeys(&vkey_witnesses);
        self.transaction = Transaction::new(
            &self.transaction.body(),
            &witness_set,
            self.transaction.auxiliary_data(),
        );
    }

    #[func]
    fn evaluate(
        &mut self,
        gutxos: Array<Gd<Utxo>>,
    ) -> Array<Gd<GRedeemer>> {
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
            |_| {}
        );

        match eval_result {
            Ok(redeemers) => {
                let mut actual_redeemers: Array<Gd<GRedeemer>> = Array::new();
                redeemers.iter().for_each(|redeemer| {
                    actual_redeemers.push(
                        Gd::from_object(GRedeemer {
                            redeemer: Redeemer::from_bytes(redeemer.to_vec()).unwrap()
                        })
                    )
                });
                actual_redeemers
            },
            Err(_err) => { 
                Array::new()
            }
        }
    }
}

#[derive(GodotClass)]
#[class(base=Node, rename=_Address)]
struct GAddress {
    address: Address
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


impl FailsWith for GAddress  {
    type E = AddressError;
}

#[godot_api]
impl GAddress {
    #[func]
    fn from_bech32(address: String) -> Gd<GAddress> {
        return Gd::from_object(
            Self {
                address: Address::from_bech32(&address).expect("Could not parse address bech32")
            }
        )
    }

    fn to_bech32(&self) -> Result<String, AddressError> {
        self.address
            .to_bech32(None)
            .map_err(|e| AddressError::Bech32Error(e))
    }

    #[func]
    fn _to_bech32(&self) -> Gd<GResult> {
        Self::to_gresult(self.to_bech32())
    }
}

#[derive(Debug)]
enum Datum {
    NoDatum,
    Hash(PackedByteArray),
    Inline(PackedByteArray),
}

#[derive(GodotClass, Debug)]
#[class(base=RefCounted, rename=Datum)]
struct GDatum {
    datum: Datum
}

#[godot_api]
impl GDatum {
    #[func]
    fn none() -> Gd<GDatum> {
        return Gd::from_object(GDatum { datum: Datum::NoDatum })
    }

    #[func]
    fn hash(bytes: PackedByteArray) -> Gd<GDatum> {
        return Gd::from_object(GDatum { datum: Datum::Hash(bytes) })
    }

    #[func]
    fn inline(bytes: PackedByteArray) -> Gd<GDatum> {
        return Gd::from_object(GDatum { datum: Datum::Inline(bytes) })
    }
}

#[derive(GodotClass, Debug)]
#[class(base=RefCounted, rename=Redeemer)]
struct GRedeemer {
    redeemer: Redeemer
}

#[godot_api]
impl GRedeemer {
    #[func]
    fn create(
        tag: u64,
        index: u64,
        data: PackedByteArray,
        ex_units_mem: u64,
        ex_units_steps: u64,
    ) -> Gd<GRedeemer> {
        let redeemer_tag: RedeemerTag =
            match tag {
                0 => RedeemerTag::new_spend(),
                1 => RedeemerTag::new_mint(),
                2 => RedeemerTag::new_cert(),
                3 => RedeemerTag::new_reward(),
                _ => RedeemerTag::new_mint()
            };
        return Gd::from_object(GRedeemer {
            redeemer: Redeemer::new(
                &redeemer_tag,
                &BigNum::from(index),
                &PlutusData::from_bytes(data.to_vec()).unwrap(),
                &ExUnits::new(
                    &BigNum::from(ex_units_mem),
                    &BigNum::from(ex_units_steps)
                )
            )
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
struct GPlutusScript {
    script: PlutusScript
}

#[godot_api]
impl GPlutusScript {
    #[func]
    fn create(script: PackedByteArray) -> Gd<GPlutusScript> {
        return Gd::from_object(GPlutusScript { script: PlutusScript::new_v2(script.to_vec()) })
    }
}

#[derive(GodotClass)]
#[class(base=Node, rename=_TxBuilder)]
struct GTxBuilder {
    tx_builder_config: TransactionBuilderConfig,
    tx_builder: TransactionBuilder,
    inputs_builder: TxInputsBuilder,
    mint_builder: MintBuilder,
    plutus_scripts: PlutusScripts,
    redeemers: Redeemers,
    max_ex_units: (u64, u64),
    slot_config: (u64, u64, u32),

    spend_redeemer_index: BigNum,
    mint_redeemer_index: BigNum
}

#[derive(Debug)]
pub enum TxBuilderError {
    BadProtocolParameters(JsError),
}

impl GodotConvert for TxBuilderError {
    type Via = i64;
}

impl ToGodot for TxBuilderError {
    fn to_godot(&self) -> Self::Via {
        use TxBuilderError::*;
        match self {
            BadProtocolParameters(_) => 0,
        }
    }
}

impl FailsWith for GTxBuilder {
    type E = TxBuilderError;
}

#[godot_api]
impl GTxBuilder {
    /// It may fail with a BadProtocolParameters.
    fn create(
        params: &ProtocolParameters,
    ) -> Result<GTxBuilder, TxBuilderError> {
        let tx_builder_config = TransactionBuilderConfigBuilder::new()
            .coins_per_utxo_byte(&to_bignum(params.coins_per_utxo_byte))
            .pool_deposit(&to_bignum(params.pool_deposit))
            .key_deposit(&to_bignum(params.key_deposit))
            .max_value_size(params.max_value_size)
            .max_tx_size(params.max_tx_size)
            .fee_algo(&LinearFee::new(
                &to_bignum(params.linear_fee_coefficient),
                &to_bignum(params.linear_fee_constant),
            ))
            .build()
            .map_err(|e| TxBuilderError::BadProtocolParameters(e))?;
        let tx_builder = TransactionBuilder::new(&tx_builder_config);

        Ok(GTxBuilder {
            tx_builder_config,
            tx_builder,
            inputs_builder: TxInputsBuilder::new(),
            mint_builder: MintBuilder::new(),
            plutus_scripts: PlutusScripts::new(),
            redeemers: Redeemers::new(),
            max_ex_units: (params.max_cpu_units, params.max_mem_units),
            slot_config: (0, 0, 0),

            spend_redeemer_index: BigNum::zero(),
            mint_redeemer_index: BigNum::zero(),
        })
    }

    #[func]
    fn _create(
        params: Gd<ProtocolParameters>,
    ) -> Gd<GResult> {
        Self::to_gresult_class(
            Self::create(&params.bind())
        )
    }

    #[func]
    fn set_slot_config(&mut self, start_time: u64, start_slot: u64, slot_length: u32) {
        self.slot_config = (start_time, start_slot, slot_length);
    }

    #[func]
    fn collect_from(&mut self, gutxos: Array<Gd<Utxo>>) {
        let inputs_builder = &mut self.inputs_builder;
        gutxos.iter_shared().for_each(|gutxo| {
            let utxo = gutxo.bind();
            inputs_builder
                .add_key_input(
                    &BaseAddress::from_address(
                        &Address::from_bech32(&utxo.address.to_string()).unwrap()
                    ).unwrap().stake_cred().to_keyhash().unwrap(),
                    &TransactionInput::new(
                        &TransactionHash::from_hex(&utxo.tx_hash.to_string()).expect("Could not decode transaction hash"),
                        utxo.output_index
                    ),
                    &Value::new_with_assets(
                        &to_bignum(utxo.coin.bind().b.as_u64().expect("UTxO Lovelace exceeds maximum").into()),
                        &multiasset_from_dictionary(&utxo.assets)
                    )
                );
        });
    }

    #[func]
    fn pay_to_address(
        &mut self,
        address: Gd<GAddress>,
        coin: Gd<BigInt>,
        assets: Dictionary
    ) {
        self.pay_to_address_with_datum(
            address,
            coin,
            assets,
            Gd::from_object(GDatum { datum: Datum::NoDatum }));
    }

    #[func]
    fn pay_to_address_with_datum(
        &mut self,
        address: Gd<GAddress>,
        coin: Gd<BigInt>,
        assets: Dictionary,
        datum: Gd<GDatum>
    ) {
        let output_builder = 
            match &datum.bind().deref().datum {
                Datum::NoDatum => TransactionOutputBuilder::new(),
                Datum::Inline(bytes) => {
                    TransactionOutputBuilder::new()
                        .with_plutus_data(
                            &PlutusData::from_bytes(bytes.to_vec()).unwrap()
                        )
                },
                Datum::Hash(bytes) =>
                    // TODO:
                    TransactionOutputBuilder::new(),
            };

        let amount_builder =
            output_builder
                .with_address(&address.bind().address)
                .next()
                .expect("Failed to build transaction output");
        let output =
            amount_builder
                .with_coin_and_asset(
                    &coin
                        .bind()
                        .b
                        .as_u64()
                        .expect("Output lovelace exceeds maximum"),
                    &multiasset_from_dictionary(&assets)
                )
                .build()
                .expect("Failed to build amount output");
        self.tx_builder
            .add_output(&output)
            .expect("Could not add output");
    }

    #[func]
    fn mint_assets(
        &mut self,
        script: Gd<GPlutusScript>,
        tokens: Dictionary,
        redeemer: PackedByteArray
    ) {
        let bound = script.bind();
        let script = &bound.deref().script;
        let redeemer =
            &Redeemer::new(
                &RedeemerTag::new_mint(),
                &self.mint_redeemer_index,
                &PlutusData::from_bytes(redeemer.to_vec()).unwrap(),
                &ExUnits::new(&BigNum::zero(), &BigNum::zero())
            );
        tokens.iter_shared().typed().for_each(|(asset_name, amount): (PackedByteArray, Gd<BigInt>)| {
            self.mint_builder.add_asset(
                &MintWitness::new_plutus_script(
                    &PlutusScriptSource::new(script),
                    redeemer
                ), 
                &AssetName::new(asset_name.to_vec()).unwrap(),
                &Int::new(&BigNum::from_str(&amount.bind().b.to_str()).unwrap())
            )
        });
        self.mint_redeemer_index = self.mint_redeemer_index.checked_add(&BigNum::one()).unwrap();
        self.plutus_scripts.add(script);
        self.redeemers.add(redeemer);
    }

    #[func]
    fn balance_and_assemble(
        &mut self,
        gutxos: Array<Gd<Utxo>>,
        change_address: Gd<GAddress>
    ) -> Gd<GTransaction> {
        let mut utxos: TransactionUnspentOutputs = TransactionUnspentOutputs::new();
        gutxos.iter_shared().for_each(|gutxo| {
            utxos.add(&gutxo.bind().to_transaction_unspent_output());
        });
        let mut tx_builder = self.tx_builder.clone();
        tx_builder.set_inputs(&self.inputs_builder);
        tx_builder.add_inputs_from(&utxos, CoinSelectionStrategyCIP2::LargestFirstMultiAsset).expect("Could not add inputs");
        tx_builder.add_change_if_needed(&change_address.bind().address).expect("Could not set change address");
        tx_builder.set_mint_builder(&self.mint_builder);
        let tx_body = tx_builder.build().expect("Could not build transaction");

        let mut witnesses = TransactionWitnessSet::new();
        let vkey_witnesses = Vkeywitnesses::new();
        witnesses.set_vkeys(&vkey_witnesses);
        witnesses.set_plutus_scripts(&self.plutus_scripts);
        witnesses.set_redeemers(&self.redeemers);
        return Gd::from_object(
            GTransaction {
                transaction: Transaction::new(&tx_body, &witnesses, None),
                max_ex_units: self.max_ex_units,
                slot_config: self.slot_config
            }
        )
    }

    #[func]
    fn complete(
        &mut self,
        gutxos: Array<Gd<Utxo>>,
        change_address: Gd<GAddress>,
        gredeemers: Array<Gd<GRedeemer>>
    ) -> Gd<GTransaction> {
        self.redeemers = Redeemers::new();
        for redeemer in gredeemers.iter_shared() {
            self.redeemers.add(&redeemer.bind().redeemer)
        };
        return self.balance_and_assemble(gutxos, change_address);
    }
}

#[gdextension]
unsafe impl ExtensionLibrary for MyExtension {}
