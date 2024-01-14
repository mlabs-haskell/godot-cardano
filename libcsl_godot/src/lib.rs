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
    Bip32PrivateKey,
    ScriptHash,
    TransactionHash,
    Vkeywitness,
    Vkeywitnesses
};
use cardano_serialization_lib::utils::*;
use cardano_serialization_lib::output_builder::*;
use cardano_serialization_lib::tx_builder::*;
use cardano_serialization_lib::tx_builder::mint_builder::*;
use cardano_serialization_lib::fees::LinearFee;
use cardano_serialization_lib::{
    AssetName,
    MultiAsset,
    Transaction,
    TransactionInput,
    TransactionOutput,
    TransactionWitnessSet,
};
use cardano_serialization_lib::tx_builder::tx_inputs_builder::{
    PlutusScriptSource,
    TxInputsBuilder
};
use cardano_serialization_lib::plutus::{PlutusData, PlutusScript};
use cardano_serialization_lib::utils as CSL;

use bip32::{Mnemonic, Language};

use godot::prelude::*;

struct MyExtension;

#[derive(GodotClass, Eq, Hash, Ord, PartialEq, PartialOrd)]
#[class(init, base=RefCounted)]
struct BigInt {
    #[init(default = CSL::BigInt::from_str("0").unwrap())]
    #[doc(hidden)]
    b: CSL::BigInt
}

#[godot_api] 
impl BigInt {
    #[func]
    fn from_str(text: String) -> Gd<BigInt> {
        let b = CSL::BigInt::from_str(&text).expect("Could not parse BigInt");
        return Gd::from_object(Self { b });
    }

    #[func]
    fn to_str(&self) -> String {
        return self.b.to_str();
    }

    #[func]
    fn to_string(&self) -> String {
        return self.to_str();
    }

    #[func]
    fn from_int(n: i64) -> Gd<BigInt> {
        let b = CSL::BigInt::from_str(&n.to_string()).unwrap();
        return Gd::from_object(Self { b });
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
    fn zero() -> Gd<BigInt> {
        return Self::from_str("0".to_string());
    }

    #[func]
    fn one() -> Gd<BigInt> {
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

    #[func]
    fn from_bytes(bytes: PackedByteArray) -> Gd<BigInt> {
       return Gd::from_object(BigInt {
           b: CSL::BigInt::from_bytes(bytes.to_vec()).unwrap()
       });
    }

    #[func]
    fn to_bytes(&self) -> PackedByteArray {
        let vec = self.b.to_bytes();
        let bytes: &[u8] = vec.as_slice().into();
        return PackedByteArray::from(bytes);
    }
}

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
    #[func]
    fn create(constructor: Gd<BigInt>, fields: Array<Variant>) -> Gd<Constr> {
        return Gd::from_object(
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
                BigInt::from_str(
                    raw.unsigned_integer()
                       .unwrap()
                       .to_string()
                ).to_variant()
            },
            Ok(Type::NegativeInteger) => {
                BigInt::from_int(raw.negative_integer().unwrap()).to_variant()
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
                        BigInt::from_int(tag - 121),
                        Self::decode_array(raw)
                    ).to_variant()
                } else if tag >= 1280 && tag <= 1400 {
                    Constr::create(
                        BigInt::from_int(tag - 1280 + 7),
                        Self::decode_array(raw)
                    ).to_variant()
                } else if tag == 102 {
                    match raw.array() {
                        Ok(Len::Len(2)) => {
                            Constr::create(
                                BigInt::from_str(raw.unsigned_integer().unwrap().to_string()),
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
                            serializer.write_tag(tag.try_into().unwrap());
                            serializer.write_bytes(bytes);
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
                serializer.write_array(Len::Len(array.len().try_into().unwrap()));
                for item in array.iter_shared() {
                    Self::encode_variant(item, serializer)
                }
            },
            VariantType::Dictionary => {
                let dict: Dictionary = variant.to();
                serializer.write_map(Len::Len(dict.len().try_into().unwrap()));
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
                            serializer.write_tag(121 + constructor_int);
                        } else if constructor_int <= 127 {
                            serializer.write_tag(1280 + constructor_int);
                        } else {
                            serializer.write_array(Len::Len(2));
                            serializer.write_unsigned_integer(constructor_int);
                            Self::encode_variant(constr.fields.to_variant(), serializer);
                        }
                        Self::encode_variant(constr.fields.to_variant(), serializer);
                    },
                    "BigInt" => {
                        let gd_bigint: Gd<BigInt> = variant.to();
                        let b = &gd_bigint.bind();
                        serializer.write_raw_bytes(&b.b.to_bytes());
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
#[class(init, base=RefCounted)]
struct Utxo {
    #[var(get)] tx_hash: GString,
    #[var(get)] output_index: u32,
    #[var(get)] address: GString,
    #[var(get)] coin: Gd<BigInt>,
    #[var(get)] assets: Dictionary
}

#[godot_api]
impl Utxo {
    #[func]
    fn create(
        tx_hash: GString,
        output_index: u32,
        address: GString,
        coin: Gd<BigInt>,
        assets: Dictionary
    ) -> Gd<Utxo> {
        return Gd::from_object(
            Self {
                tx_hash,
                output_index,
                address,
                coin,
                assets
            }
        );
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
    ) -> Gd<ProtocolParameters> {
        return Gd::from_object(
            Self {
                coins_per_utxo_byte,
                pool_deposit,
                key_deposit,
                max_value_size,
                max_tx_size,
                linear_fee_constant,
                linear_fee_coefficient,
            }
        );
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
#[class(init, base=RefCounted)]
struct PrivateKeyAccount {
    #[var] account_index: u32,

    master_private_key: Option<Bip32PrivateKey>,
}

#[godot_api]
impl PrivateKeyAccount {
    #[func]
    fn from_mnemonic(phrase: String) -> Option<Gd<PrivateKeyAccount>> {
        let result = Mnemonic::new(
            phrase
                .to_lowercase()
                .split_whitespace()
                .collect::<Vec<_>>()
                .join(" "),
            Language::English
        );
        match result {
            Err(msg) => {
                godot_print!("{}", msg);
                return None
            }
            Ok(mnemonic) => {
                // TODO: find out if the wrapped key will be freed by Gd
                return Some(Gd::from_object(
                    Self {
                        master_private_key: Some(Bip32PrivateKey::from_bip39_entropy(mnemonic.entropy(), &[])),
                        account_index: 0
                    }
                ))
            }
        }
    }

    fn get_account_root(&self) -> Bip32PrivateKey {
        let priv_key = self.master_private_key.as_ref().expect("Private key not set");
        return priv_key
            .derive(harden(1852))
            .derive(harden(1815))
            .derive(harden(self.account_index));
    }

    #[func]
    fn get_address(&self) -> Gd<GAddress> {
        let account_root = self.get_account_root();
        let spend = account_root.derive(0).derive(0).to_public();
        let stake = account_root.derive(2).derive(0).to_public();
        let spend_cred = StakeCredential::from_keyhash(&spend.to_raw_key().hash());
        let stake_cred = StakeCredential::from_keyhash(&stake.to_raw_key().hash());
        let address =
            BaseAddress::new(
                NetworkInfo::testnet_preview().network_id(),
                &spend_cred,
                &stake_cred
            ).to_address();
        return Gd::from_object(GAddress { address: Some(address) });
    }

    #[func]
    fn get_address_bech32(&self) -> String {
        return self.get_address().bind().address.as_ref().unwrap().to_bech32(None).unwrap();
    }

    #[func]
    fn sign_transaction(&self, tx: Gd<GTransaction>) -> Gd<GSignature> {
        let account_root = self.get_account_root();
        let spend_key = account_root.derive(0).derive(0).to_raw_key();
        let tx_hash = hash_transaction(&tx.bind().transaction.as_ref().unwrap().body());

        return Gd::from_object(
            GSignature {
                signature: Some(make_vkey_witness(&tx_hash, &spend_key))
            }
        )
    }
}

// TODO: qualify all CSL types and skip renaming
#[derive(GodotClass)]
#[class(init, base=RefCounted, rename=Signature)]
struct GSignature {
    signature: Option<Vkeywitness>
}

#[derive(GodotClass)]
#[class(init, base=RefCounted, rename=Transaction)]
struct GTransaction {
    transaction: Option<Transaction>
}

#[godot_api]
impl GTransaction {
    #[func]
    fn bytes(&self) -> PackedByteArray {
        let bytes_vec = self.transaction.clone().unwrap().to_bytes();
        let bytes: &[u8] = bytes_vec.as_slice().into();
        return PackedByteArray::from(bytes);
    }

    #[func]
    fn add_signature(&mut self, signature: Gd<GSignature>) {
        // NOTE: destroys? transaction and replaces with a new one. might be better to add
        // signatures to the witness set before the transaction is actually built
        let transaction = self.transaction.as_ref().unwrap();
        let mut witness_set = transaction.witness_set();
        let mut vkey_witnesses = witness_set.vkeys().unwrap_or(Vkeywitnesses::new());
        vkey_witnesses.add(signature.bind().signature.as_ref().unwrap());
        witness_set.set_vkeys(&vkey_witnesses);
        self.transaction = Some(
            Transaction::new(
                &transaction.body(),
                &witness_set,
                transaction.auxiliary_data()
            )
        )
    }
}

#[derive(GodotClass)]
#[class(init, base=Node, rename=Address)]
struct GAddress {
    address: Option<Address>
}

#[godot_api]
impl GAddress {
    #[func]
    fn from_bech32(address: String) -> Gd<GAddress> {
        return Gd::from_object(
            Self {
                address: Some(Address::from_bech32(&address).expect("Could not parse address bech32"))
            }
        )
    }

    #[func]
    fn to_bech32(&self) -> String {
        return self.address.as_ref().unwrap().to_bech32(None).unwrap();
    }
}

#[derive(GodotClass)]
#[class(init, base=Node, rename=TxBuilder)]
struct GTxBuilder {
    tx_builder: Option<TransactionBuilder>,
    inputs_builder: Option<TxInputsBuilder>
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

//#[derive(GodotClass)]
//#[class(base=Node, rename=TxBuilder)]
//struct GPlutusScript {
//    script: PlutusScript
//}
//
//impl GPlutusScript {
//}

#[godot_api]
impl GTxBuilder {
    #[func]
    fn create(cardano: Gd<Cardano>) -> Gd<GTxBuilder> {
        let builder = TransactionBuilder::new(&cardano.bind().tx_builder_config.as_ref().unwrap());
        Gd::from_object(
            Self {
                tx_builder: Some(builder),
                inputs_builder: Some(TxInputsBuilder::new())
            }
        )
    }

    #[func]
    fn collect_from(&mut self, gutxos: Array<Gd<Utxo>>) {
        let inputs_builder = self.inputs_builder.as_mut().unwrap();
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
                .with_address(&address.bind().address.as_ref().unwrap())
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
            .as_mut()
            .unwrap()
            .add_output(&output)
            .expect("Could not add output");
    }

    //#[func]
    //fn mint_assets(
    //    script: Gd<GPlutusScript>,
    //    tokens: Dictionary,
    //    redeemer: Gd<GDatum>
    //) {
    //    //MintWitness::new_plutus_script(
    //    //    &PlutusScriptSource::new(&script.bind().script),
    //    //    &redeemer.
    //    //);
    //    //MintBuilder::new();
    //    //Asset
    //}

    #[func]
    fn complete(
        &mut self,
        gutxos: Array<Gd<Utxo>>,
        change_address: Gd<GAddress>
    ) -> Gd<GTransaction> {
        let mut utxos: TransactionUnspentOutputs = TransactionUnspentOutputs::new();
        gutxos.iter_shared().for_each(|gutxo| {
            let utxo = gutxo.bind();
            utxos.add(
                &TransactionUnspentOutput::new(
                    &TransactionInput::new(
                        &TransactionHash::from_hex(&utxo.tx_hash.to_string()).expect("Could not decode transaction hash"),
                        utxo.output_index
                    ),
                    &TransactionOutput::new(
                        &Address::from_bech32(&utxo.address.to_string()).expect("Could not decode address bech32"), 
                        &Value::new_with_assets(
                            &to_bignum(utxo.coin.bind().b.as_u64().expect("UTxO Lovelace exceeds maximum").into()),
                            &multiasset_from_dictionary(&utxo.assets)
                        )
                    )
                )
            );
        });
        let tx_builder = self.tx_builder.as_mut().unwrap();
        tx_builder.set_inputs(&self.inputs_builder.as_ref().unwrap());
        tx_builder.add_inputs_from(&utxos, CoinSelectionStrategyCIP2::LargestFirstMultiAsset).expect("Could not add inputs");
        tx_builder.add_change_if_needed(&change_address.bind().address.as_ref().unwrap()).expect("Could not set change address");
        let tx_body = tx_builder.build().expect("Could not build transaction");

        let mut witnesses = TransactionWitnessSet::new();
        let vkey_witnesses = Vkeywitnesses::new();
        witnesses.set_vkeys(&vkey_witnesses);

        return Gd::from_object(
            GTransaction {
                transaction: Some(Transaction::new(&tx_body, &witnesses, None))
            }
        )
    }
}

#[derive(GodotClass)]
#[class(init, base=Node, rename=_Cardano)]
struct Cardano {
    tx_builder_config: Option<TransactionBuilderConfig>,
}

#[godot_api]
impl Cardano {
    #[func]
    fn set_protocol_parameters(&mut self, parameters: Gd<ProtocolParameters>) {
        let params = parameters.bind();
        godot_print!("Setting parameters");
        self.tx_builder_config =
            Some(
                TransactionBuilderConfigBuilder::new()
                    .coins_per_utxo_byte(&to_bignum(params.coins_per_utxo_byte))
                    .pool_deposit(&to_bignum(params.pool_deposit))
                    .key_deposit(&to_bignum(params.key_deposit))
                    .max_value_size(params.max_value_size)
                    .max_tx_size(params.max_tx_size)
                    .fee_algo(
                        &LinearFee::new(
                            &to_bignum(params.linear_fee_coefficient),
                            &to_bignum(params.linear_fee_constant)
                        )
                    )
                    .build().expect("Failed to build transaction builder config")
            );
    }
}

#[gdextension]
unsafe impl ExtensionLibrary for MyExtension {}
