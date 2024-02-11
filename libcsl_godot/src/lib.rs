use std::ops::Deref;

use cardano_serialization_lib as CSL;
use cardano_serialization_lib::address::BaseAddress;
use cardano_serialization_lib::crypto::{TransactionHash, Vkeywitnesses};
use cardano_serialization_lib::error::JsError;
use cardano_serialization_lib::fees::LinearFee;
use cardano_serialization_lib::output_builder::*;
use cardano_serialization_lib::plutus::PlutusData;
use cardano_serialization_lib::tx_builder::tx_inputs_builder::TxInputsBuilder;
use cardano_serialization_lib::tx_builder::*;
use cardano_serialization_lib::utils::*;
use cardano_serialization_lib::{TransactionInput, TransactionWitnessSet};

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
    multiasset_from_dictionary, Address, Datum, DatumValue, Transaction, Utxo,
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
        return Gd::from_object(Self {
            coins_per_utxo_byte,
            pool_deposit,
            key_deposit,
            max_value_size,
            max_tx_size,
            linear_fee_constant,
            linear_fee_coefficient,
        });
    }
}

#[derive(GodotClass)]
#[class(base=Node, rename=_TxBuilder)]
struct GTxBuilder {
    tx_builder: TransactionBuilder,
    inputs_builder: TxInputsBuilder,
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
            tx_builder,
            inputs_builder: TxInputsBuilder::new(),
        })
    }

    #[func]
    fn _create(params: Gd<ProtocolParameters>) -> Gd<GResult> {
        Self::to_gresult_class(Self::create(&params.bind()))
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
            DatumValue::Hash(bytes) => TransactionOutputBuilder::new()
                .with_data_hash(&CSL::crypto::DataHash::from_bytes(bytes.to_vec()).unwrap()),
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
        let tx_body = tx_builder.build().expect("Could not build transaction");

        let mut witnesses = TransactionWitnessSet::new();
        let vkey_witnesses = Vkeywitnesses::new();
        witnesses.set_vkeys(&vkey_witnesses);
        return Gd::from_object(Transaction {
            transaction: CSL::Transaction::new(&tx_body, &witnesses, None),
        });
    }

    #[func]
    fn complete(
        &mut self,
        gutxos: Array<Gd<Utxo>>,
        change_address: Gd<Address>,
    ) -> Gd<Transaction> {
        return self.balance_and_assemble(gutxos, change_address);
    }
}

#[gdextension]
unsafe impl ExtensionLibrary for MyExtension {}
