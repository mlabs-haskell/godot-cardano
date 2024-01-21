use bip32::secp256k1::sha2::Sha256;
use cardano_serialization_lib::address::{Address, BaseAddress, NetworkInfo, StakeCredential};
use cardano_serialization_lib::crypto::{
    Bip32PrivateKey, Bip32PublicKey, ScriptHash, TransactionHash, Vkeywitness, Vkeywitnesses,
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
use godot::engine::{Crypto, CryptoKey};
use godot::prelude::*;

pub mod bigint;
pub mod gresult;

use bigint::BigInt;
use gresult::FailsWith;
use pbkdf2::pbkdf2_hmac;

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

/// A single address key account is essentially a Cardano single-address
/// wallet. The wallet can be imported by inputting a seed phrase together
/// with a password (as explained in the BIP39 standard).
///
/// However, the wallet is serialised to disk as the specific account's
/// private key. We are not interested in other possible accounts (since
/// this is a single-address wallet after all). For safety, the private key
/// is stored encrypted with PBKDF2_HMAC.
///
/// For convenience, the account public key is also stored. Considering that
/// this is a single address wallet, not much privacy is lost by simply storing
/// the public key, as it is equivalent to storing the only address that will
/// be in use.
#[derive(GodotClass)]
#[class(base=Resource, rename=_SingleAddressKeyAccount)]
struct SingleAddressKeyAccount {
    #[var]
    account_index: u32,
    #[var]
    encrypted_account_private_key: PackedByteArray,
    #[var]
    account_public_key: PackedByteArray,
    #[var]
    salt: PackedByteArray,
}

#[derive(Debug)]
pub enum SingleAddressKeyAccountError {
    BadPhrase(bip32::Error),
    Bech32Error(JsError),
}

impl GodotConvert for SingleAddressKeyAccountError {
    type Via = i64;
}

impl ToGodot for SingleAddressKeyAccountError {
    fn to_godot(&self) -> Self::Via {
        use SingleAddressKeyAccountError::*;
        match self {
            BadPhrase(_) => 1,
            Bech32Error(_) => 2,
        }
    }
}

impl FailsWith for SingleAddressKeyAccount {
    type E = SingleAddressKeyAccountError;
}

#[godot_api]
impl SingleAddressKeyAccount {
    fn import(
        phrase: String,
        mnemonic_password: String,
        account_password: String,
    ) -> Result<SingleAddressKeyAccount, SingleAddressKeyAccountError> {
        // we obtain the master private key with the mnemonic and the user
        // password
        let mnemonic = Mnemonic::new(
            phrase
                .to_lowercase()
                .split_whitespace()
                .collect::<Vec<_>>()
                .join(" "),
            Language::English,
        )
        .map_err(|e| SingleAddressKeyAccountError::BadPhrase(e))?;

        // we store the account private key, encrypted with a password using PBKDF2
        let account_index: u32 = 0;

        let master_private_key =
            Bip32PrivateKey::from_bip39_entropy(mnemonic.entropy(), mnemonic_password.as_bytes());

        let account_private_key = master_private_key
            .derive(harden(1852))
            .derive(harden(1815))
            .derive(harden(account_index));

        let mut crypto = Crypto::new();
        let salt: PackedByteArray = crypto.generate_random_bytes(16);

        let mut encrypted_account_private_key: &mut [u8];

        pbkdf2_hmac::<Sha256>(
            account_password.as_bytes(),
            salt.as_slice(),
            750_000,
            encrypted_account_private_key,
        );
        master_private_key
            .derive(harden(1852))
            .derive(harden(1815))
            .derive(harden(account_index));

        // we also store the account public key, unencrypted
        let account_public_key =
            PackedByteArray::from(account_private_key.to_public().as_bytes().as_slice());

        Ok(Self {
            account_index,
            encrypted_account_private_key: PackedByteArray::from(
                encrypted_account_private_key.as_ref(),
            ),
            account_public_key,
            salt,
        })
    }

    #[func]
    fn _import(phrase: String, mnemonic_password: String, account_password: String) -> Gd<GResult> {
        Self::to_gresult_class(Self::import(phrase, mnemonic_password, account_password))
    }

    fn get_account_root(&self) -> Bip32PrivateKey {
        self.master_private_key
            .derive(harden(1852))
            .derive(harden(1815))
            .derive(harden(self.account_index))
    }

    fn get_address(&self) -> Address {
        let account: Bip32PublicKey =
            Bip32PublicKey::from_bytes(self.account_public_key.as_slice());
        let spend = account.derive(0).derive(0).to_public();
        let stake = account.derive(2).derive(0).to_public();
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
    fn get_address_bech32(&self) -> Result<String, SingleAddressKeyAccountError> {
        let addr = self.get_address();
        addr.to_bech32(None)
            .map_err(|e| SingleAddressKeyAccountError::Bech32Error(e))
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
