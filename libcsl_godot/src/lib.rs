use std::ops::Deref;
use std::collections::BTreeSet;

use cardano_serialization_lib as CSL;
use CSL::address::{BaseAddress, NetworkInfo, StakeCredential};
use CSL::crypto::{Bip32PrivateKey, Vkeywitnesses};
use CSL::error::JsError;
use CSL::fees::LinearFee;
use CSL::output_builder::*;
use CSL::plutus::{
    ExUnits, PlutusData, PlutusScripts, RedeemerTag, Redeemers, Costmdls
};
use CSL::tx_builder::mint_builder::*;
use CSL::tx_builder::tx_inputs_builder::{
    PlutusScriptSource, TxInputsBuilder,
};
use CSL::tx_builder_constants::TxBuilderConstants;
use CSL::tx_builder::*;
use CSL::utils::*;
use CSL::{AssetName, TransactionWitnessSet};

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
    multiasset_from_dictionary, Address, CostModels, Datum, DatumValue, PlutusScript, Signature,
    Transaction, Utxo, EvaluationResult
};

struct MyExtension;

#[derive(GodotClass, Clone)]
#[class(init, base=RefCounted)]
struct ProtocolParameters {
    coins_per_utxo_byte: u64,
    pool_deposit: u64,
    key_deposit: u64,
    max_value_size: u32,
    max_tx_size: u32,
    linear_fee_constant: u64,
    linear_fee_coefficient: u64,
    price_mem_ten_millionths: u64,
    price_step_ten_millionths: u64,
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
        price_mem_ten_millionths: u64,
        price_step_ten_millionths: u64,
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
            price_mem_ten_millionths,
            price_step_ten_millionths,
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
    tx_builder: TransactionBuilder,
    protocol_parameters: ProtocolParameters,
    inputs_builder: TxInputsBuilder,
    mint_builder: MintBuilder,
    plutus_scripts: PlutusScripts,
    redeemers: Redeemers,
    max_ex_units: (u64, u64),
    slot_config: (u64, u64, u32),
    cost_models: Costmdls,
    fee: u64,
    used_langs: BTreeSet<CSL::plutus::Language>,
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
            .ex_unit_prices(
                &CSL::plutus::ExUnitPrices::new(
                    &CSL::UnitInterval::new(
                        &to_bignum(params.price_mem_ten_millionths),
                        &to_bignum(10_000_000)
                    ),
                    &CSL::UnitInterval::new(
                        &to_bignum(params.price_step_ten_millionths),
                        &to_bignum(10_000_000)
                    ),
                )
            )
            .build()
            .map_err(|e| TxBuilderError::BadProtocolParameters(e))?;
        let tx_builder = TransactionBuilder::new(&tx_builder_config);

        Ok(GTxBuilder {
            tx_builder,
            protocol_parameters: params.clone(),
            inputs_builder: TxInputsBuilder::new(),
            mint_builder: MintBuilder::new(),
            plutus_scripts: PlutusScripts::new(),
            redeemers: Redeemers::new(),
            fee: 0,
            max_ex_units: (params.max_cpu_units, params.max_mem_units),
            slot_config: (0, 0, 0),
            cost_models: TxBuilderConstants::plutus_default_cost_models(),
            used_langs: BTreeSet::new()
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
    fn set_cost_models(&mut self, cost_models: Gd<CostModels>) {
        self.cost_models = cost_models.bind().cost_models.clone();
    }

    #[func]
    fn collect_from(&mut self, gutxos: Array<Gd<Utxo>>) {
        let inputs_builder = &mut self.inputs_builder;
        gutxos.iter_shared().for_each(|gutxo| {
            gutxo.bind().add_to_inputs_builder(inputs_builder);
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
            DatumValue::Hash(bytes) => TransactionOutputBuilder::new()
                .with_data_hash(&CSL::crypto::DataHash::from_bytes(bytes.to_vec()).unwrap()),
        };

        let amount_builder = output_builder
            .with_address(&address.bind().address)
            .next()
            .expect("Failed to build transaction output");
        let output = 
            if coin.bind().gt(BigInt::zero()) {
                amount_builder
                    .with_coin_and_asset(
                        &coin
                            .bind()
                            .b
                            .as_u64()
                            .expect("Output lovelace exceeds maximum"),
                        &multiasset_from_dictionary(&assets),
                    )
                    .build()
                    .expect("Failed to build amount output")
            } else {
                amount_builder
                    .with_asset_and_min_required_coin_by_utxo_cost(
                        &multiasset_from_dictionary(&assets),
                        &CSL::DataCost::new_coins_per_byte(&to_bignum(self.protocol_parameters.coins_per_utxo_byte))
                    )
                    .expect("Failed to build minUTxO output")
                    .build()
                    .expect("Failed to build amount output")
            };

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
        let mut index: u32 = 0;
        let num_scripts: u32 = self.plutus_scripts.len() as u32;
        while index < num_scripts {
            if self.plutus_scripts.get(index as usize).hash() == script.hash() {
                break;
            }
            index += 1;
        }
        let redeemer = &CSL::plutus::Redeemer::new(
            &RedeemerTag::new_mint(),
            &to_bignum(index as u64),
            &PlutusData::from_bytes(redeemer.to_vec()).unwrap(),
            &ExUnits::new(&BigNum::zero(), &BigNum::zero()),
        );
        tokens.iter_shared().typed().for_each(
            |(asset_name, amount): (PackedByteArray, Gd<BigInt>)| {
                self.mint_builder.add_asset(
                    &MintWitness::new_plutus_script(&PlutusScriptSource::new(script), redeemer),
                    &AssetName::new(asset_name.to_vec()).unwrap(),
                    &Int::from_str(&amount.bind().b.to_str()).unwrap(),
                )
            },
        );
        if index >= num_scripts {
            self.plutus_scripts.add(script);
            self.redeemers.add(redeemer);
            self.used_langs.insert(script.language_version());
        }
    }

    pub fn calc_script_data_hash(&mut self) -> CSL::crypto::ScriptDataHash {
        let mut retained_cost_models = Costmdls::new();

        for lang in &self.used_langs {
            match self.cost_models.get(&lang) {
                Some(cost) => {
                    retained_cost_models.insert(&lang, &cost);
                }
                _ => { }
            }
        }

        return hash_script_data(
            &self.redeemers,
            &retained_cost_models,
            None,
        );
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
        tx_builder.set_inputs(&self.inputs_builder.clone());
        tx_builder
            .add_inputs_from(&utxos, CoinSelectionStrategyCIP2::LargestFirstMultiAsset)
            .expect("Could not add inputs");

        tx_builder.set_mint_builder(&self.mint_builder.clone());
        if self.redeemers.len() > 0 {
            let min_collateral = self.fee * 150 / 100 + 1;
            let collateral_amount = Gd::from_object(
                BigInt::from_int(min_collateral.try_into().unwrap())
            );
            for gutxo in gutxos.iter_shared() {
                let utxo = gutxo.bind();
                if utxo.coin.bind().gt(collateral_amount.clone()) {
                    let mut inputs_builder = TxInputsBuilder::new();
                    utxo.add_to_inputs_builder(&mut inputs_builder);
                    tx_builder.set_collateral(&inputs_builder);
                    tx_builder.set_total_collateral_and_return(
                        &BigNum::from(min_collateral),
                        &change_address.bind().address
                    ).unwrap();
                    break;
                }
            }
        }
        tx_builder.set_script_data_hash(&self.calc_script_data_hash());
        tx_builder
            .add_change_if_needed(&change_address.bind().address)
            .expect("Could not set change address");
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
            cost_models: self.cost_models.clone()
        });
    }

    #[func]
    fn complete(
        &mut self,
        gutxos: Array<Gd<Utxo>>,
        change_address: Gd<Address>,
        eval_result: Gd<EvaluationResult>
    ) -> Gd<Transaction> {
        self.redeemers = Redeemers::new();
        for redeemer in eval_result.bind().redeemers.iter_shared() {
            self.redeemers.add(&redeemer.bind().redeemer)
        }
        self.fee = eval_result.bind().fee;
        return self.balance_and_assemble(gutxos, change_address);
    }
}

#[gdextension]
unsafe impl ExtensionLibrary for MyExtension {}
