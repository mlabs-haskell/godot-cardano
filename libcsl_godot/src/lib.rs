use std::collections::HashMap;
use std::ops::Deref;

use cardano_serialization_lib as CSL;
use CSL::crypto::Vkeywitnesses;
use CSL::error::JsError;
use CSL::fees::LinearFee;
use CSL::output_builder::*;
use CSL::plutus::{Costmdls, ExUnits, PlutusData, PlutusScripts, RedeemerTag, Redeemers};
use CSL::tx_builder::mint_builder::*;
use CSL::tx_builder::tx_inputs_builder::TxInputsBuilder;
use CSL::tx_builder::*;
use CSL::tx_builder_constants::TxBuilderConstants;
use CSL::utils::*;
use CSL::{AssetName, TransactionWitnessSet};

use godot::builtin::meta::GodotConvert;
use godot::prelude::*;

pub mod bigint;
pub mod gresult;
pub mod plutus;
pub mod wallet;
pub mod ledger {
    pub mod transaction;
}

use crate::bigint::BigInt;
use crate::gresult::{FailsWith, GResult};
use crate::ledger::transaction::{
    Address, CostModels, Datum, DatumValue, EvaluationResult, MultiAsset, PlutusScript,
    PlutusScriptSource, Transaction, Utxo,
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
    collateral_percentage: u64,
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
        collateral_percentage: u64,
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
            collateral_percentage,
            max_cpu_units,
            max_mem_units,
        });
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
    fee: Option<u64>,
    minted_assets: HashMap<u32, (CSL::plutus::PlutusScript, Dictionary)>,
}

#[derive(Debug)]
pub enum TxBuilderError {
    BadProtocolParameters(JsError),
    QuantityExceedsMaximum(),
    DeserializeError(CSL::error::DeserializeError),
    ByronAddressUnsupported(),
    CouldNotGetKeyHash(),
    UnknownRedeemerIndex(CSL::plutus::Redeemer),
    UnexpectedCollateralAmount(),
    OtherError(JsError),
}

impl GodotConvert for TxBuilderError {
    type Via = i64;
}

impl ToGodot for TxBuilderError {
    fn to_godot(&self) -> Self::Via {
        use TxBuilderError::*;
        match self {
            BadProtocolParameters(_) => 1,
            QuantityExceedsMaximum() => 2,
            DeserializeError(_) => 3,
            ByronAddressUnsupported() => 4,
            CouldNotGetKeyHash() => 5,
            UnknownRedeemerIndex(_) => 6,
            UnexpectedCollateralAmount() => 7,
            OtherError(_) => 8,
        }
    }
}

impl FailsWith for GTxBuilder {
    type E = TxBuilderError;
}

impl From<CSL::error::DeserializeError> for TxBuilderError {
    fn from(err: CSL::error::DeserializeError) -> TxBuilderError {
        return TxBuilderError::DeserializeError(err);
    }
}

impl From<JsError> for TxBuilderError {
    fn from(err: JsError) -> TxBuilderError {
        return TxBuilderError::OtherError(err);
    }
}

fn add_utxo_to_inputs_builder(
    utxo: &Utxo,
    inputs_builder: &mut TxInputsBuilder,
) -> Result<(), TxBuilderError> {
    let address = &utxo.address.bind().address;
    let from_base_address = CSL::address::BaseAddress::from_address(address)
        .and_then(|addr| addr.payment_cred().to_keyhash())
        .ok_or(TxBuilderError::CouldNotGetKeyHash);
    let from_enterprise_address = CSL::address::EnterpriseAddress::from_address(address)
        .and_then(|addr| addr.payment_cred().to_keyhash())
        .ok_or(TxBuilderError::CouldNotGetKeyHash);
    // TODO: figure out how keys/signatures work with Byron addresses
    let from_byron_address = match CSL::address::ByronAddress::from_address(address) {
        None => Err(TxBuilderError::CouldNotGetKeyHash()),
        Some(_byron_address) => Err(TxBuilderError::ByronAddressUnsupported()),
    };
    inputs_builder.add_key_input(
        &from_base_address
            .or(from_enterprise_address)
            .or(from_byron_address)?,
        &CSL::TransactionInput::new(&utxo.tx_hash.bind().hash, utxo.output_index),
        &Value::new_with_assets(
            &to_bignum(
                utxo.coin
                    .bind()
                    .b
                    .as_u64()
                    .ok_or(TxBuilderError::QuantityExceedsMaximum())?
                    .into(),
            ),
            &utxo.assets.bind().assets,
        ),
    );
    Ok(())
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
            .ex_unit_prices(&CSL::plutus::ExUnitPrices::new(
                &CSL::UnitInterval::new(
                    &to_bignum(params.price_mem_ten_millionths),
                    &to_bignum(10_000_000),
                ),
                &CSL::UnitInterval::new(
                    &to_bignum(params.price_step_ten_millionths),
                    &to_bignum(10_000_000),
                ),
            ))
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
            fee: None,
            max_ex_units: (params.max_cpu_units, params.max_mem_units),
            slot_config: (0, 0, 0),
            cost_models: TxBuilderConstants::plutus_default_cost_models(),

            minted_assets: HashMap::new(),
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

    fn collect_from(&mut self, gutxos: Array<Gd<Utxo>>) -> Result<(), TxBuilderError> {
        let inputs_builder = &mut self.inputs_builder;
        for gutxo in gutxos.iter_shared() {
            add_utxo_to_inputs_builder(gutxo.bind().deref(), inputs_builder)?;
        }
        Ok(())
    }

    #[func]
    fn _collect_from(&mut self, gutxos: Array<Gd<Utxo>>) -> Gd<GResult> {
        Self::to_gresult(self.collect_from(gutxos))
    }

    fn add_plutus_script_input(
        &mut self,
        script_source: Gd<PlutusScriptSource>,
        utxo: &Utxo,
        redeemer_bytes: PackedByteArray,
    ) -> Result<(), TxBuilderError> {
        let input = utxo.to_transaction_input();
        let datum = utxo.to_datum();
        let value = utxo.to_value();

        // set the maximum ex units to overestimate the fee on first balance pass
        let max_mem = self.protocol_parameters.max_mem_units / 4;
        let max_steps = self.protocol_parameters.max_cpu_units / 4;

        // Index and RedeemerTag are not necessary, they are automatically set
        // by get_plutus_inputs_scripts()
        let redeemer = CSL::plutus::Redeemer::new(
            &RedeemerTag::new_spend(),
            &to_bignum(0u64),
            &PlutusData::from_bytes(redeemer_bytes.to_vec())?,
            &ExUnits::new(&BigNum::from(max_mem), &BigNum::from(max_steps)), //
        );

        self.redeemers.add(&redeemer);

        // FIXME: script hash fails to match if we add the datum here?
        let witness = match None {
            None => CSL::tx_builder::tx_inputs_builder::PlutusWitness::new_with_ref_without_datum(
                &script_source.bind().source,
                &redeemer,
            ),
            Some(d) => CSL::tx_builder::tx_inputs_builder::PlutusWitness::new_with_ref(
                &script_source.bind().source,
                &d,
                &redeemer,
            ),
        };

        // FIXME: resolve reference scripts
        let script = witness.script().unwrap();
        self.plutus_scripts.add(&script);

        self.inputs_builder
            .add_plutus_script_input(&witness, &input, &value);

        Ok(())
    }

    fn collect_from_script(
        &mut self,
        script_source: Gd<PlutusScriptSource>,
        gutxos: Array<Gd<Utxo>>,
        redeemer: PackedByteArray,
    ) -> Result<(), TxBuilderError> {
        let mut address: Option<Address> = None;
        for gutxo in gutxos.iter_shared() {
            let utxo = gutxo.bind();
            let addr = utxo.get_address();
            println!(
                "(collect_from_script) utxo address: {:?}",
                addr.bind().to_bech32().expect("could not get address")
            );
            match &address {
                Some(addr_) => {
                    if addr.bind().address.to_bytes() != addr_.address.to_bytes() {
                        godot_warn!("collect_from_script: Utxo was not added because its address did not match previous inputs: {:?}", utxo);
                    } else {
                        self.add_plutus_script_input(
                            script_source.clone(),
                            &utxo,
                            redeemer.clone(),
                        )?
                    }
                }
                None => {
                    address = Some(Address {
                        address: utxo.address.bind().address.clone(),
                    });
                    self.add_plutus_script_input(script_source.clone(), &utxo, redeemer.clone())?
                }
            }
        }
        Ok(())
    }

    #[func]
    fn _collect_from_script(
        &mut self,
        script_source: Gd<PlutusScriptSource>,
        gutxos: Array<Gd<Utxo>>,
        redeemer: PackedByteArray,
    ) -> Gd<GResult> {
        Self::to_gresult(self.collect_from_script(script_source, gutxos, redeemer))
    }

    #[func]
    fn pay_to_address(
        &mut self,
        address: Gd<Address>,
        coin: Gd<BigInt>,
        assets: Gd<MultiAsset>,
    ) -> Gd<GResult> {
        self._pay_to_address_with_datum(address, coin, assets, Datum::none())
    }

    fn pay_to_address_with_datum(
        &mut self,
        address: Gd<Address>,
        coin: Gd<BigInt>,
        assets: Gd<MultiAsset>,
        datum: Gd<Datum>,
    ) -> Result<(), TxBuilderError> {
        let output_builder = match &datum.bind().deref().datum {
            // TODO: do this privately inside `Datum`?
            DatumValue::NoDatum => TransactionOutputBuilder::new(),
            DatumValue::Inline(bytes) => TransactionOutputBuilder::new()
                .with_plutus_data(&PlutusData::from_bytes(bytes.to_vec())?),
            DatumValue::Hash(bytes) => TransactionOutputBuilder::new()
                .with_data_hash(&CSL::crypto::DataHash::from_bytes(bytes.to_vec())?),
        };

        let amount_builder = output_builder
            .with_address(&address.bind().address)
            .next()?;
        let output = if coin.bind().gt(BigInt::zero()) {
            amount_builder
                .with_coin_and_asset(
                    &coin
                        .bind()
                        .b
                        .as_u64()
                        .ok_or(TxBuilderError::QuantityExceedsMaximum())?,
                    &assets.bind().assets,
                )
                .build()?
        } else {
            amount_builder
                .with_asset_and_min_required_coin_by_utxo_cost(
                    &assets.bind().assets,
                    &CSL::DataCost::new_coins_per_byte(&to_bignum(
                        self.protocol_parameters.coins_per_utxo_byte,
                    )),
                )?
                .build()?
        };

        self.tx_builder.add_output(&output)?;
        Ok(())
    }

    #[func]
    fn _pay_to_address_with_datum(
        &mut self,
        address: Gd<Address>,
        coin: Gd<BigInt>,
        assets: Gd<MultiAsset>,
        datum: Gd<Datum>,
    ) -> Gd<GResult> {
        Self::to_gresult(self.pay_to_address_with_datum(address, coin, assets, datum))
    }

    fn add_mint_asset(
        &mut self,
        script: &PlutusScript,
        tokens: &Dictionary,
        redeemer: &CSL::plutus::Redeemer,
    ) -> Result<(), TxBuilderError> {
        use cardano_serialization_lib::tx_builder::tx_inputs_builder::PlutusScriptSource;
        for (asset_name, amount) in tokens.iter_shared().typed::<PackedByteArray, Gd<BigInt>>() {
            self.mint_builder.add_asset(
                &MintWitness::new_plutus_script(&PlutusScriptSource::new(&script.script), redeemer),
                &AssetName::new(asset_name.to_vec())?,
                &Int::from_str(&amount.bind().b.to_str())?,
            )
        }
        Ok(())
    }

    fn mint_assets(
        &mut self,
        gscript: Gd<PlutusScript>,
        tokens: &Dictionary,
        redeemer_bytes: PackedByteArray,
    ) -> Result<(), TxBuilderError> {
        let bound = gscript.bind();
        let script = bound.deref();
        let mut index: u32 = 0;
        let num_scripts: u32 = self.plutus_scripts.len() as u32;
        while index < num_scripts {
            if self.plutus_scripts.get(index as usize).hash() == script.script.hash() {
                break;
            }
            index += 1;
        }
        let redeemer = CSL::plutus::Redeemer::new(
            &RedeemerTag::new_mint(),
            &to_bignum(index as u64),
            &PlutusData::from_bytes(redeemer_bytes.to_vec())?,
            &ExUnits::new(&BigNum::zero(), &BigNum::zero()),
        );
        if index >= num_scripts {
            self.plutus_scripts.add(&script.script);
            self.redeemers.add(&redeemer);
        }
        self.minted_assets
            .insert(index, (script.script.clone(), tokens.clone()));
        self.add_mint_asset(&script, &tokens, &redeemer)
    }

    #[func]
    fn _mint_assets(
        &mut self,
        script: Gd<PlutusScript>,
        tokens: Dictionary,
        redeemer: PackedByteArray,
    ) -> Gd<GResult> {
        Self::to_gresult(self.mint_assets(script, &tokens, redeemer))
    }

    fn balance_and_assemble(
        &mut self,
        gutxos: Array<Gd<Utxo>>,
        change_address: Gd<Address>,
    ) -> Result<Transaction, TxBuilderError> {
        let mut utxos: TransactionUnspentOutputs = TransactionUnspentOutputs::new();
        let mut tx_builder = self.tx_builder.clone();
        let uses_plutus_scripts = self.redeemers.len() > 0;

        for gutxo in gutxos.iter_shared() {
            utxos.add(&gutxo.bind().to_transaction_unspent_output());
        }

        tx_builder.set_inputs(&self.inputs_builder.clone());
        tx_builder.add_inputs_from(&utxos, CoinSelectionStrategyCIP2::LargestFirstMultiAsset)?;

        tx_builder.set_mint_builder(&self.mint_builder.clone());
        if uses_plutus_scripts {
            let fee = match self.fee {
                Some(set_fee) => set_fee,
                None => match self.tx_builder.min_fee() {
                    Ok(fee) => fee.into(),
                    Err(_) => 0,
                },
            };
            let min_collateral = fee * (self.protocol_parameters.collateral_percentage + 99) / 100;
            // NOTE: look for at least enough ADA to return a change output
            //       this may still fail if tokens on the output require more ADA
            let collateral_amount = Gd::from_object(BigInt::from_int(
                (min_collateral * 3)
                    .try_into()
                    .map_err(|_| TxBuilderError::UnexpectedCollateralAmount())?,
            ));
            for gutxo in gutxos.iter_shared() {
                let utxo = gutxo.bind();
                if utxo.coin.bind().gt(collateral_amount.clone()) {
                    let mut inputs_builder = TxInputsBuilder::new();
                    add_utxo_to_inputs_builder(utxo.deref(), &mut inputs_builder)?;
                    tx_builder.set_collateral(&inputs_builder);
                    tx_builder.set_total_collateral_and_return(
                        &BigNum::from(min_collateral),
                        &change_address.bind().address,
                    )?;
                    break;
                }
            }
            tx_builder.calc_script_data_hash(&self.cost_models)?;
        }
        tx_builder.add_change_if_needed(&change_address.bind().address)?;
        self.fee = Some(tx_builder.get_fee_if_set().unwrap().into());
        let tx = tx_builder.build_tx()?;
        println!("(balanceAndAssemble) tx body: {:?}", tx.body());

        let mut witnesses = tx.witness_set();
        let vkey_witnesses = Vkeywitnesses::new();
        witnesses.set_vkeys(&vkey_witnesses);
        //if uses_plutus_scripts {
        //    witnesses.set_plutus_scripts(&self.plutus_scripts);
        //    witnesses.set_redeemers(&self.redeemers);
        //}
        Ok(Transaction {
            transaction: CSL::Transaction::new(&tx.body(), &witnesses, None),
            max_ex_units: self.max_ex_units,
            slot_config: self.slot_config,
            cost_models: self.cost_models.clone(),
        })
    }

    #[func]
    fn _balance_and_assemble(
        &mut self,
        gutxos: Array<Gd<Utxo>>,
        change_address: Gd<Address>,
    ) -> Gd<GResult> {
        Self::to_gresult_class(self.balance_and_assemble(gutxos, change_address))
    }

    fn complete(
        &mut self,
        gutxos: Array<Gd<Utxo>>,
        change_address: Gd<Address>,
        eval_result: Gd<EvaluationResult>,
    ) -> Result<Transaction, TxBuilderError> {
        // Why are redeemers and builders recreated when they can be overwritten?
        //self.redeemers = Redeemers::new();
        self.mint_builder = MintBuilder::new();
        for redeemer in eval_result.bind().redeemers.iter_shared() {
            let bound = redeemer.bind().deref().redeemer.clone();
            match bound.tag().kind() {
                CSL::plutus::RedeemerTagKind::Mint => {
                    let (script, assets) = self
                        .minted_assets
                        .get(&bound.index().try_into()?)
                        .ok_or(TxBuilderError::UnknownRedeemerIndex(
                            redeemer.bind().deref().redeemer.clone(),
                        ))?
                        .to_owned();
                    self.add_mint_asset(&PlutusScript { script }, &assets, &bound)?;
                }
                CSL::plutus::RedeemerTagKind::Spend => (),
                CSL::plutus::RedeemerTagKind::Cert => (),
                CSL::plutus::RedeemerTagKind::Reward => (),
            }
            self.redeemers.add(&bound);
        }
        self.fee = Some(eval_result.bind().fee);
        self.balance_and_assemble(gutxos, change_address)
    }

    #[func]
    fn _complete(
        &mut self,
        gutxos: Array<Gd<Utxo>>,
        change_address: Gd<Address>,
        eval_result: Gd<EvaluationResult>,
    ) -> Gd<GResult> {
        Self::to_gresult_class(self.complete(gutxos, change_address, eval_result))
    }
}

#[gdextension]
unsafe impl ExtensionLibrary for MyExtension {}
