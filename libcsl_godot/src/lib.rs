use cardano_serialization_lib::address::{Address, BaseAddress, NetworkInfo, StakeCredential};
use cardano_serialization_lib::crypto::{
    Bip32PrivateKey, ScriptHash, TransactionHash, Vkeywitness, Vkeywitnesses,
};
use cardano_serialization_lib::error::JsError;
use cardano_serialization_lib::fees::LinearFee;
use cardano_serialization_lib::output_builder::*;
use cardano_serialization_lib::tx_builder::*;
use cardano_serialization_lib::utils::*;
use cardano_serialization_lib::{
    AssetName, MultiAsset, Transaction, TransactionInput, TransactionOutput, TransactionWitnessSet,
};

use bip32::{Language, Mnemonic};

use godot::builtin::meta::GodotConvert;
use godot::prelude::*;

pub mod bigint;
pub mod gresult;

use bigint::BigInt;
use gresult::FailsWith;

use crate::gresult::GResult;

struct MyExtension;

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
    signature: Vkeywitness,
}

#[derive(GodotClass)]
#[class(base=RefCounted, rename=_Transaction)]
struct GTransaction {
    transaction: Transaction,
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
        )
    }
}

#[derive(GodotClass)]
#[class(base=Node, rename=_TxBuilder)]
struct TxBuilder {
    tx_builder_config: TransactionBuilderConfig,
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

impl FailsWith for TxBuilder {
    type E = TxBuilderError;
}

#[godot_api]
impl TxBuilder {
    /// It may fail with a BadProtocolParameters.
    fn create(params: &ProtocolParameters) -> Result<TxBuilder, TxBuilderError> {
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

        Ok(TxBuilder { tx_builder_config })
    }

    #[func]
    fn _create(params: Gd<ProtocolParameters>) -> Gd<GResult> {
        Self::to_gresult_class(Self::create(&params.bind()))
    }

    #[func]
    /// FIXME: This function should take validated parameters of the
    /// appropriate type instead of Strings.
    fn send_lovelace(
        &mut self,
        recipient_bech32: String,
        change_address_bech32: String,
        amount: Gd<BigInt>,
        gutxos: Array<Gd<Utxo>>,
    ) -> Gd<GTransaction> {
        let recipient =
            Address::from_bech32(&recipient_bech32).expect("Could not decode address bech32");
        let change_address =
            Address::from_bech32(&change_address_bech32).expect("Could not decode address bech32");

        let mut utxos: TransactionUnspentOutputs = TransactionUnspentOutputs::new();

        for gutxo in gutxos.iter_shared() {
            let utxo = gutxo.bind();
            let mut assets: MultiAsset = MultiAsset::new();
            for (unit, amount) in utxo.assets.iter_shared().typed::<GString, Gd<BigInt>>() {
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
            }

            utxos.add(&TransactionUnspentOutput::new(
                &TransactionInput::new(
                    &TransactionHash::from_hex(&utxo.tx_hash.to_string())
                        .expect("Could not decode transaction hash"),
                    utxo.output_index,
                ),
                &TransactionOutput::new(
                    &Address::from_bech32(&utxo.address.to_string())
                        .expect("Could not decode address bech32"),
                    &Value::new_with_assets(
                        &to_bignum(
                            utxo.coin
                                .bind()
                                .b
                                .as_u64()
                                .expect("UTxO Lovelace exceeds maximum")
                                .into(),
                        ),
                        &assets,
                    ),
                ),
            ));
        }
        let output_builder = TransactionOutputBuilder::new();
        let amount_builder = output_builder
            .with_address(&recipient)
            .next()
            .expect("Failed to build transaction output");
        let output = amount_builder
            .with_coin(
                &amount
                    .bind()
                    .b
                    .as_u64()
                    .expect("Output lovelace exceeds maximum"),
            )
            .build()
            .expect("Failed to build amount output");
        let mut tx_builder = TransactionBuilder::new(&self.tx_builder_config);
        tx_builder
            .add_inputs_from(&utxos, CoinSelectionStrategyCIP2::LargestFirstMultiAsset)
            .expect("Could not add inputs");
        tx_builder
            .add_output(&output)
            .expect("Could not add output");
        tx_builder
            .add_change_if_needed(&change_address)
            .expect("Could not set change address");
        let tx_body = tx_builder.build().expect("Could not build transaction");

        let mut witnesses = TransactionWitnessSet::new();
        let vkey_witnesses = Vkeywitnesses::new();
        witnesses.set_vkeys(&vkey_witnesses);

        return Gd::from_object(GTransaction {
            transaction: Transaction::new(&tx_body, &witnesses, None),
        });
    }
}

#[gdextension]
unsafe impl ExtensionLibrary for MyExtension {}
