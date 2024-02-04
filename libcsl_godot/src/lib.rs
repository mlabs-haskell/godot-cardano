use std::ops::Deref;

use cardano_serialization_lib as CSL;
use cardano_serialization_lib::address::{BaseAddress, NetworkInfo, StakeCredential};
use cardano_serialization_lib::crypto::{Bip32PrivateKey, TransactionHash, Vkeywitnesses};
use cardano_serialization_lib::error::JsError;
use cardano_serialization_lib::fees::LinearFee;
use cardano_serialization_lib::output_builder::*;
<<<<<<< HEAD
use cardano_serialization_lib::plutus::{
    ExUnits, PlutusData, PlutusScripts, RedeemerTag, Redeemers,
};
use cardano_serialization_lib::tx_builder::mint_builder::*;
use cardano_serialization_lib::tx_builder::tx_inputs_builder::{
    PlutusScriptSource, TxInputsBuilder,
};
use cardano_serialization_lib::tx_builder::*;
use cardano_serialization_lib::utils::*;
use cardano_serialization_lib::{AssetName, TransactionInput, TransactionWitnessSet};

use bip32::{Language, Mnemonic};

use godot::builtin::meta::GodotConvert;
use godot::prelude::*;

pub mod bigint;
pub mod gresult;
pub mod plutus;
pub mod ledger {
    pub mod transaction;
}

use crate::bigint::BigInt;
use crate::gresult::{FailsWith, GResult};
use crate::ledger::transaction::{
    multiasset_from_dictionary, Address, Datum, DatumValue, PlutusScript, Redeemer, Signature,
    Transaction, Utxo,
};

struct MyExtension;

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
            max_mem_units,
        });
    }
}

fn harden(index: u32) -> u32 {
    return index | 0x80000000;
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

    fn get_address(&self) -> CSL::address::Address {
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
    fn _get_address(&self) -> Gd<Address> {
        Gd::from_object(Address {
            address: self.get_address(),
        })
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

    fn sign_transaction(&self, gtx: &Transaction) -> Signature {
        let account_root = self.get_account_root();
        let spend_key = account_root.derive(0).derive(0).to_raw_key();
        let tx_hash = hash_transaction(&gtx.transaction.body());
        Signature {
            signature: make_vkey_witness(&tx_hash, &spend_key),
        }
    }

    #[func]
    fn _sign_transaction(&self, gtx: Gd<Transaction>) -> Gd<Signature> {
        Gd::from_object(self.sign_transaction(&gtx.bind()))
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
    mint_redeemer_index: BigNum,
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
    fn create(params: &ProtocolParameters) -> Result<GTxBuilder, TxBuilderError> {
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
    fn _create(params: Gd<ProtocolParameters>) -> Gd<GResult> {
        Self::to_gresult_class(Self::create(&params.bind()))
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
            inputs_builder.add_key_input(
                &BaseAddress::from_address(
                    &CSL::address::Address::from_bech32(&utxo.address.to_string()).unwrap(),
                )
                .unwrap()
                .stake_cred()
                .to_keyhash()
                .unwrap(),
                &TransactionInput::new(
                    &TransactionHash::from_hex(&utxo.tx_hash.to_string())
                        .expect("Could not decode transaction hash"),
                    utxo.output_index,
                ),
                &Value::new_with_assets(
                    &to_bignum(
                        utxo.coin
                            .bind()
                            .b
                            .as_u64()
                            .expect("UTxO Lovelace exceeds maximum")
                            .into(),
                    ),
                    &multiasset_from_dictionary(&utxo.assets),
                ),
            );
        });
    }

    #[func]
    fn pay_to_address(&mut self, address: Gd<Address>, coin: Gd<BigInt>, assets: Dictionary) {
        self.pay_to_address_with_datum(address, coin, assets, Datum::none());
    }

    #[func]
    fn pay_to_address_with_datum(
        &mut self,
        address: Gd<Address>,
        coin: Gd<BigInt>,
        assets: Dictionary,
        datum: Gd<Datum>,
    ) {
        let output_builder = match &datum.bind().deref().datum {
            // TODO: do this privately inside `Datum`?
            DatumValue::NoDatum => TransactionOutputBuilder::new(),
            DatumValue::Inline(bytes) => TransactionOutputBuilder::new()
                .with_plutus_data(&PlutusData::from_bytes(bytes.to_vec()).unwrap()),
            DatumValue::Hash(bytes) =>
            // TODO: datum hashes
            {
                TransactionOutputBuilder::new()
            }
        };

        let amount_builder = output_builder
            .with_address(&address.bind().address)
            .next()
            .expect("Error to build transaction output");
        let output = amount_builder
            .with_coin_and_asset(
                &coin
                    .bind()
                    .b
                    .as_u64()
                    .expect("Output lovelace exceeds maximum"),
                &multiasset_from_dictionary(&assets),
            )
            .build()
            .expect("Error to build amount output");
        self.tx_builder
            .add_output(&output)
            .expect("Could not add output");
    }

    #[func]
    fn mint_assets(
        &mut self,
        script: Gd<PlutusScript>,
        tokens: Dictionary,
        redeemer: PackedByteArray,
    ) {
        let bound = script.bind();
        let script = &bound.deref().script;
        let redeemer = &CSL::plutus::Redeemer::new(
            &RedeemerTag::new_mint(),
            &self.mint_redeemer_index,
            &PlutusData::from_bytes(redeemer.to_vec()).unwrap(),
            &ExUnits::new(&BigNum::zero(), &BigNum::zero()),
        );
        tokens.iter_shared().typed().for_each(
            |(asset_name, amount): (PackedByteArray, Gd<BigInt>)| {
                self.mint_builder.add_asset(
                    &MintWitness::new_plutus_script(&PlutusScriptSource::new(script), redeemer),
                    &AssetName::new(asset_name.to_vec()).unwrap(),
                    &Int::new(&BigNum::from_str(&amount.bind().b.to_str()).unwrap()),
                )
            },
        );
        self.mint_redeemer_index = self
            .mint_redeemer_index
            .checked_add(&BigNum::one())
            .unwrap();
        self.plutus_scripts.add(script);
        self.redeemers.add(redeemer);
    }

    #[func]
    fn balance_and_assemble(
        &mut self,
        gutxos: Array<Gd<Utxo>>,
        change_address: Gd<Address>,
    ) -> Gd<Transaction> {
        let mut utxos: TransactionUnspentOutputs = TransactionUnspentOutputs::new();
        gutxos.iter_shared().for_each(|gutxo| {
            utxos.add(&gutxo.bind().to_transaction_unspent_output());
        });
        let mut tx_builder = self.tx_builder.clone();
        tx_builder.set_inputs(&self.inputs_builder);
        tx_builder
            .add_inputs_from(&utxos, CoinSelectionStrategyCIP2::LargestFirstMultiAsset)
            .expect("Could not add inputs");
        tx_builder
            .add_change_if_needed(&change_address.bind().address)
            .expect("Could not set change address");
        tx_builder.set_mint_builder(&self.mint_builder);
        let tx_body = tx_builder.build().expect("Could not build transaction");

        let mut witnesses = TransactionWitnessSet::new();
        let vkey_witnesses = Vkeywitnesses::new();
        witnesses.set_vkeys(&vkey_witnesses);
        witnesses.set_plutus_scripts(&self.plutus_scripts);
        witnesses.set_redeemers(&self.redeemers);
        return Gd::from_object(Transaction {
            transaction: CSL::Transaction::new(&tx_body, &witnesses, None),
            max_ex_units: self.max_ex_units,
            slot_config: self.slot_config,
        });
    }

    #[func]
    fn complete(
        &mut self,
        gutxos: Array<Gd<Utxo>>,
        change_address: Gd<Address>,
        gredeemers: Array<Gd<Redeemer>>,
    ) -> Gd<Transaction> {
        self.redeemers = Redeemers::new();
        for redeemer in gredeemers.iter_shared() {
            self.redeemers.add(&redeemer.bind().redeemer)
        }
        return self.balance_and_assemble(gutxos, change_address);
    }
}

#[gdextension]
unsafe impl ExtensionLibrary for MyExtension {}
