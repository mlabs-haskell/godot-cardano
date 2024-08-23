use std::collections::{BTreeMap, BTreeSet};
use std::ops::Deref;

use cardano_serialization_lib as CSL;
use CSL::{
    AssetName, BigNum, CoinSelectionStrategyCIP2, Costmdls, ExUnits, Int, JsError, LinearFee,
    MintBuilder, MintWitness, PlutusData, PlutusWitness, RedeemerTag, TransactionBuilder,
    TransactionBuilderConfigBuilder, TransactionOutputBuilder, TransactionUnspentOutputs,
    TxBuilderConstants, TxInputsBuilder, UnitInterval, Value, Vkeywitnesses,
};

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
    PlutusScriptSource, PubKeyHash, Transaction, Utxo, UtxoDatumValue,
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
    ref_script_coins_per_byte: u64,
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
        ref_script_coins_per_byte: u64,
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
            ref_script_coins_per_byte,
        });
    }
}

#[derive(GodotClass)]
#[class(base=RefCounted, rename=_TxBuilder)]
struct GTxBuilder {
    tx_builder: TransactionBuilder,
    protocol_parameters: ProtocolParameters,
    inputs_builder: TxInputsBuilder,
    mint_builder: MintBuilder,
    uses_plutus_scripts: bool,
    max_ex_units: (u64, u64),
    slot_config: (u64, u64, u32),
    cost_models: Costmdls,
    minted_assets:
        BTreeMap<CSL::ScriptHash, (CSL::PlutusScriptSource, Dictionary, PackedByteArray)>,
    script_inputs_map: BTreeMap<CSL::TransactionInput, (CSL::PlutusScriptSource, CSL::Value)>,
    data: BTreeSet<PlutusData>,
    previous_build: Option<CSL::Transaction>,
}

#[derive(Debug)]
pub enum TxBuilderError {
    BadProtocolParameters(JsError),
    QuantityExceedsMaximum(),
    DeserializeError(CSL::DeserializeError),
    ByronAddressUnsupported(),
    CouldNotGetKeyHash(),
    UnknownRedeemerIndex(u64),
    UnexpectedCollateralAmount(),
    OtherError(JsError),
    MissingScriptForInput(u64),
    MissingWitnesses,
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
            MissingScriptForInput(_) => 9,
            MissingWitnesses => 10,
        }
    }
}

impl FailsWith for GTxBuilder {
    type E = TxBuilderError;
}

impl From<CSL::DeserializeError> for TxBuilderError {
    fn from(err: CSL::DeserializeError) -> TxBuilderError {
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
    let from_base_address = CSL::BaseAddress::from_address(address)
        .and_then(|addr| addr.payment_cred().to_keyhash())
        .ok_or(TxBuilderError::CouldNotGetKeyHash);
    let from_enterprise_address = CSL::EnterpriseAddress::from_address(address)
        .and_then(|addr| addr.payment_cred().to_keyhash())
        .ok_or(TxBuilderError::CouldNotGetKeyHash);
    // TODO: figure out how keys/signatures work with Byron addresses
    let from_byron_address = match CSL::ByronAddress::from_address(address) {
        None => Err(TxBuilderError::CouldNotGetKeyHash()),
        Some(_byron_address) => Err(TxBuilderError::ByronAddressUnsupported()),
    };
    inputs_builder.add_key_input(
        &from_base_address
            .or(from_enterprise_address)
            .or(from_byron_address)?,
        &CSL::TransactionInput::new(&utxo.tx_hash.bind().hash, utxo.output_index),
        &Value::new_with_assets(
            &utxo
                .coin
                .bind()
                .b
                .as_u64()
                .ok_or(TxBuilderError::QuantityExceedsMaximum())?
                .into(),
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
            .coins_per_utxo_byte(&params.coins_per_utxo_byte.into())
            .pool_deposit(&params.pool_deposit.into())
            .key_deposit(&params.key_deposit.into())
            .max_value_size(params.max_value_size)
            .max_tx_size(params.max_tx_size)
            .fee_algo(&LinearFee::new(
                &params.linear_fee_coefficient.into(),
                &params.linear_fee_constant.into(),
            ))
            .ex_unit_prices(&CSL::ExUnitPrices::new(
                &CSL::UnitInterval::new(
                    &params.price_mem_ten_millionths.into(),
                    &BigNum::from(10_000_000u64),
                ),
                &CSL::UnitInterval::new(
                    &params.price_step_ten_millionths.into(),
                    &BigNum::from(10_000_000u64),
                ),
            ))
            .ref_script_coins_per_byte(&UnitInterval::new(
                &BigNum::from(params.ref_script_coins_per_byte),
                &BigNum::from(1u64),
            ))
            .deduplicate_explicit_ref_inputs_with_regular_inputs(true)
            .build()
            .map_err(|e| TxBuilderError::BadProtocolParameters(e))?;
        let tx_builder = TransactionBuilder::new(&tx_builder_config);

        Ok(GTxBuilder {
            tx_builder,
            protocol_parameters: params.clone(),
            inputs_builder: TxInputsBuilder::new(),
            mint_builder: MintBuilder::new(),
            uses_plutus_scripts: false,
            max_ex_units: (params.max_cpu_units, params.max_mem_units),
            slot_config: (0, 0, 0),
            cost_models: TxBuilderConstants::plutus_default_cost_models(),

            minted_assets: BTreeMap::new(),
            script_inputs_map: BTreeMap::new(),
            data: BTreeSet::new(),
            previous_build: None,
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
        let source = script_source.bind();

        // Index and RedeemerTag are not necessary, they are automatically set
        // by get_plutus_inputs_scripts()
        let redeemer = CSL::Redeemer::new(
            &RedeemerTag::new_spend(),
            &BigNum::from(0u64),
            &PlutusData::from_bytes(redeemer_bytes.to_vec())?,
            &ExUnits::new(&BigNum::zero(), &BigNum::zero()), //
        );

        let witness = match datum {
            Some(UtxoDatumValue::Resolved(datum_hex)) => {
                let data = PlutusData::from_hex(datum_hex.to_string().as_str()).unwrap();
                self.data.insert(data.clone());
                PlutusWitness::new_with_ref(
                    &source.source,
                    &CSL::DatumSource::new(&data),
                    &redeemer,
                )
            }
            _ => PlutusWitness::new_with_ref_without_datum(&source.source, &redeemer),
        };

        self.script_inputs_map.insert(
            utxo.to_transaction_input(),
            (source.source.clone(), value.clone()),
        );
        self.uses_plutus_scripts = true;
        self.inputs_builder
            .add_plutus_script_input(&witness, &input, &value);

        match source.utxo.as_ref() {
            Some(gutxo) => {
                self.tx_builder
                    .add_script_reference_input(&gutxo.bind().to_transaction_input(), source.size);
            }
            None => (),
        }

        Ok(())
    }

    fn collect_from_script(
        &mut self,
        script_source: Gd<PlutusScriptSource>,
        gutxos: Array<Gd<Utxo>>,
        redeemer: PackedByteArray,
    ) -> Result<(), TxBuilderError> {
        let mut address: Option<Address> = None;
        let get_payment_cred_bytes = |address: &Address| -> Option<Vec<u8>> {
            address
                .payment_credential()
                .map(|c| c.bind().credential.to_bytes())
        };

        for gutxo in gutxos.iter_shared() {
            let utxo = gutxo.bind();
            let addr = utxo.get_address();
            match &address {
                Some(addr_) => {
                    if get_payment_cred_bytes(&addr.bind()) != get_payment_cred_bytes(addr_) {
                        godot_warn!("collect_from_script: Utxo was not added because its payment credential did not match previous inputs: {:?}", utxo);
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

    fn pay_to_address(
        &mut self,
        address: Gd<Address>,
        coin: Gd<BigInt>,
        assets: Gd<MultiAsset>,
        datum: Gd<Datum>,
        script_ref: Option<Gd<PlutusScript>>,
    ) -> Result<(), TxBuilderError> {
        let mut output_builder = match &datum.bind().deref().datum {
            // TODO: do this privately inside `Datum`?
            DatumValue::NoDatum => TransactionOutputBuilder::new(),
            DatumValue::Inline(bytes) => TransactionOutputBuilder::new()
                .with_plutus_data(&PlutusData::from_bytes(bytes.to_vec())?),
            DatumValue::Hash(bytes) => TransactionOutputBuilder::new()
                .with_data_hash(&CSL::DataHash::from_bytes(bytes.to_vec())?),
        };

        output_builder = match script_ref {
            Some(script) => output_builder
                .with_script_ref(&CSL::ScriptRef::new_plutus_script(&script.bind().script)),
            None => output_builder,
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
                    &CSL::DataCost::new_coins_per_byte(
                        &self.protocol_parameters.coins_per_utxo_byte.into(),
                    ),
                )?
                .build()?
        };

        self.tx_builder.add_output(&output)?;
        Ok(())
    }

    #[func]
    fn _pay_to_address(
        &mut self,
        address: Gd<Address>,
        coin: Gd<BigInt>,
        assets: Gd<MultiAsset>,
        datum: Option<Gd<Datum>>,
        script_ref: Option<Gd<PlutusScript>>,
    ) -> Gd<GResult> {
        Self::to_gresult(self.pay_to_address(
            address,
            coin,
            assets,
            datum.unwrap_or(Datum::none()),
            script_ref,
        ))
    }

    #[func]
    fn _add_reference_input(&mut self, input: Gd<Utxo>) {
        self.tx_builder
            .add_reference_input(&input.bind().deref().to_transaction_input());
    }

    #[func]
    fn valid_after(&mut self, slot: u64) {
        self.tx_builder
            .set_validity_start_interval_bignum(BigNum::from(slot))
    }

    #[func]
    fn valid_before(&mut self, slot: u64) {
        self.tx_builder.set_ttl_bignum(&BigNum::from(slot))
    }

    fn add_mint_asset(
        &mut self,
        script_source: &CSL::PlutusScriptSource,
        tokens: &Dictionary,
        redeemer: &CSL::Redeemer,
    ) -> Result<(), TxBuilderError> {
        for (asset_name, amount) in tokens.iter_shared().typed::<PackedByteArray, Gd<BigInt>>() {
            self.mint_builder.add_asset(
                &MintWitness::new_plutus_script(script_source, redeemer),
                &AssetName::new(asset_name.to_vec())?,
                &Int::from_str(&amount.bind().b.to_str())?,
            )?
        }
        Ok(())
    }

    fn mint_assets(
        &mut self,
        gscript: Gd<PlutusScriptSource>,
        tokens: &Dictionary,
        redeemer_bytes: PackedByteArray,
    ) -> Result<(), TxBuilderError> {
        let bound = gscript.bind();
        let script = bound.deref();
        let script_hash = &script.hash;

        let mut non_zero = false;
        // TODO: replace redeemer? error on mismatch?
        match self.minted_assets.get_mut(script_hash) {
            Some((_, previous_tokens, _)) => {
                for (asset_name, amount) in tokens.iter_shared() {
                    let previous_amount: Gd<BigInt> = match previous_tokens.get(asset_name.clone())
                    {
                        Some(amount) => amount.to(),
                        None => BigInt::zero(),
                    };
                    let new_amount = previous_amount.bind().add(amount.to());
                    if new_amount.bind().eq(BigInt::zero()) {
                        previous_tokens.remove(asset_name.clone());
                    } else {
                        previous_tokens.set(asset_name.clone(), new_amount);
                        non_zero = true;
                    }
                }
            }
            None => {
                self.minted_assets.insert(
                    script_hash.clone(),
                    (
                        script.source.clone(),
                        tokens.clone(),
                        redeemer_bytes.clone(),
                    ),
                );
                non_zero = true;
            }
        }
        if !non_zero {
            self.minted_assets.remove(&script_hash.clone());
        }

        Ok(())
    }

    #[func]
    fn _mint_assets(
        &mut self,
        script_source: Gd<PlutusScriptSource>,
        tokens: Dictionary,
        redeemer: PackedByteArray,
    ) -> Gd<GResult> {
        Self::to_gresult(self.mint_assets(script_source, &tokens, redeemer))
    }

    // adds redeemers for non-input scripts as needed
    fn add_dummy_redeemers(&mut self) -> Result<(), TxBuilderError> {
        self.mint_builder = MintBuilder::new();
        let minted_assets = self.minted_assets.clone();
        for (index, (_script_hash, (script_source, assets, redeemer_bytes))) in
            minted_assets.iter().enumerate()
        {
            let redeemer = CSL::Redeemer::new(
                &RedeemerTag::new_mint(),
                &BigNum::from(index),
                &PlutusData::from_bytes(redeemer_bytes.to_vec())?,
                &ExUnits::new(&BigNum::zero(), &BigNum::zero()),
            );
            self.add_mint_asset(&script_source.clone(), &assets, &redeemer)?;
            self.uses_plutus_scripts = true;
        }
        Ok(())
    }

    #[func]
    fn _add_dummy_redeemers(&mut self) -> Gd<GResult> {
        Self::to_gresult(self.add_dummy_redeemers())
    }

    #[func]
    fn _add_required_signer(&mut self, pub_key_hash: Gd<PubKeyHash>) {
        self.tx_builder
            .add_required_signer(&pub_key_hash.bind().hash);
    }

    fn balance_and_assemble(
        &mut self,
        gutxos: Array<Gd<Utxo>>,
        change_address: Gd<Address>,
    ) -> Result<Transaction, TxBuilderError> {
        let mut utxos: TransactionUnspentOutputs = TransactionUnspentOutputs::new();
        let mut tx_builder = self.tx_builder.clone();

        for gutxo in gutxos.iter_shared() {
            utxos.add(&gutxo.bind().to_transaction_unspent_output());
        }

        tx_builder.set_inputs(&self.inputs_builder.clone());

        tx_builder.set_mint_builder(&self.mint_builder.clone());

        let fee = match self.previous_build.as_ref().map(|tx| tx.body().fee()) {
            Some(fee) => fee.into(),
            // overestimate fee for preliminary passes and change calculation
            None => 2_000_000u64,
        };
        if self.uses_plutus_scripts {
            let min_collateral = fee * (self.protocol_parameters.collateral_percentage + 99) / 100;
            let collateral_amount = BigNum::from(min_collateral);
            let mut collateral_inputs_builder = TxInputsBuilder::new();
            for gutxo in gutxos.iter_shared() {
                let utxo = gutxo.bind();
                let output_builder = TransactionOutputBuilder::new();
                let utxo_coin = utxo
                    .coin
                    .bind()
                    .b
                    .as_u64()
                    .ok_or_else(|| TxBuilderError::QuantityExceedsMaximum())?;
                let collateral_output = output_builder
                    .with_address(&utxo.address.bind().address)
                    .next()?
                    .with_asset_and_min_required_coin_by_utxo_cost(
                        &utxo.assets.bind().assets,
                        &CSL::DataCost::new_coins_per_byte(
                            &self.protocol_parameters.coins_per_utxo_byte.into(),
                        ),
                    )?
                    .build()?;
                let output_min_utxo = collateral_output.amount().coin();
                // FIXME: we probably want to select more than a single input when needed
                if utxo_coin >= output_min_utxo.checked_add(&collateral_amount)? {
                    add_utxo_to_inputs_builder(utxo.deref(), &mut collateral_inputs_builder)?;
                    break;
                }
            }
            tx_builder.set_collateral(&collateral_inputs_builder);
            tx_builder.set_total_collateral_and_return(
                &BigNum::from(min_collateral),
                &change_address.bind().address,
            )?;
        }

        tx_builder.add_inputs_from(&utxos, CoinSelectionStrategyCIP2::RandomImproveMultiAsset)?;

        if self.uses_plutus_scripts {
            tx_builder.calc_script_data_hash(&self.cost_models)?;
        }

        tx_builder.add_change_if_needed(&change_address.bind().address)?;

        let tx = tx_builder.build_tx()?;

        let mut witnesses = tx.witness_set();
        let vkey_witnesses = Vkeywitnesses::new();
        witnesses.set_vkeys(&vkey_witnesses);
        let transaction = CSL::Transaction::new(&tx.body(), &witnesses, None);
        self.previous_build = Some(transaction.clone());
        Ok(Transaction {
            transaction,
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
        self.mint_builder = MintBuilder::new();
        let input_witnesses = self.inputs_builder.get_plutus_input_scripts();
        let mut script_input_index = 0;
        for redeemer in eval_result.bind().redeemers.iter_shared() {
            let bound = redeemer.bind().deref().redeemer.clone();
            let minted_assets = self.minted_assets.clone();
            match bound.tag().kind() {
                CSL::RedeemerTagKind::Mint => {
                    let index: u64 = bound.index().into();
                    let (_script_hash, (script_source, assets, _redeemer_bytes)) = minted_assets
                        .iter()
                        .nth(index.try_into().unwrap())
                        .ok_or(TxBuilderError::UnknownRedeemerIndex(index))?;
                    self.add_mint_asset(&script_source.clone(), &assets, &bound)?;
                }
                CSL::RedeemerTagKind::Spend => {
                    let index: u64 = bound.index().into();
                    let input = self.previous_build.clone().unwrap().body().inputs().get(
                        index
                            .try_into()
                            .map_err(|_| TxBuilderError::UnknownRedeemerIndex(index))?,
                    );
                    let witness = input_witnesses
                        .as_ref()
                        .ok_or(TxBuilderError::MissingWitnesses)?
                        .get(script_input_index);
                    let (script_source, value) = self
                        .script_inputs_map
                        .get(&input)
                        .ok_or(TxBuilderError::MissingScriptForInput(index))?;
                    script_input_index += 1;
                    match witness.datum() {
                        Some(datum) => {
                            self.inputs_builder.add_plutus_script_input(
                                &PlutusWitness::new_with_ref(
                                    &script_source,
                                    &CSL::DatumSource::new(&datum),
                                    &bound,
                                ),
                                &input,
                                &value,
                            );
                        }
                        None => {
                            self.inputs_builder.add_plutus_script_input(
                                &PlutusWitness::new_with_ref_without_datum(&script_source, &bound),
                                &input,
                                &value,
                            );
                        }
                    }
                }
                CSL::RedeemerTagKind::Cert => (),
                CSL::RedeemerTagKind::Reward => (),
                CSL::RedeemerTagKind::Vote => (),
                CSL::RedeemerTagKind::VotingProposal => (),
            }
        }
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
