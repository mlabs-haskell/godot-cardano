use std::array::TryFromSliceError;

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
use godot::engine::Crypto;
use godot::prelude::*;

pub mod bigint;
pub mod gresult;

use bigint::BigInt;
use gresult::FailsWith;
use pkcs5::pbes2;
use scrypt::errors::InvalidParams;

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

// #[derive(GodotClass)]
// #[class(base=RefCounted, rename=_SingleAddressAccount)]
// struct SingleAddressAccount {
//     account_public_key: Bip32PublicKey,
// }

/// A single address account store is essentially a Cardano single-address
/// wallet, with possibly many accounts.
///
/// The wallet can be imported by inputting a seed phrase together
/// with a password (as explained in the BIP39 standard).
///
/// The wallet is serialised to disk, however, as the Cardano private master key.
/// We are not interested in preserving the seed phrase. For safety, the private key
/// is stored using the PBES2 encryption scheme.
///
/// For convenience, the account public key is also stored. Considering that
/// this is a single address wallet, not much privacy is lost by simply storing
/// the public key, as it is equivalent to storing the only address that will
/// be in use for any given account.
#[derive(GodotClass)]
#[class(base=Resource, rename=_SingleAddressAccountStore)]
struct SingleAddressAccountStore {
    #[var]
    encrypted_master_private_key: PackedByteArray,
    #[var]
    account_public_keys: Array<PackedByteArray>,
    #[var]
    scrypt_salt: PackedByteArray,
    #[var]
    scrypt_log_n: u8,
    #[var]
    scrypt_r: u32,
    #[var]
    scrypt_p: u32,
    #[var]
    aes_iv: PackedByteArray,
}

#[derive(Debug)]
pub enum SingleAddressAccountStoreError {
    BadPhrase(bip32::Error),
    Bip32Error(JsError),
    Pkcs5Error(pkcs5::Error),
    BadScryptParams(InvalidParams),
    CouldNotParseAesIv(TryFromSliceError),
}

impl GodotConvert for SingleAddressAccountStoreError {
    type Via = i64;
}

impl ToGodot for SingleAddressAccountStoreError {
    fn to_godot(&self) -> Self::Via {
        use SingleAddressAccountStoreError::*;
        match self {
            BadPhrase(_) => 1,
            Bip32Error(_) => 2,
            Pkcs5Error(_) => 3,
            BadScryptParams(_) => 4,
            CouldNotParseAesIv(_) => 5,
        }
    }
}

impl FailsWith for SingleAddressAccountStore {
    type E = SingleAddressAccountStoreError;
}

#[godot_api]
impl SingleAddressAccountStore {
    fn import(
        phrase: String,
        mnemonic_password: String,
        account_password: String,
    ) -> Result<SingleAddressAccountStore, SingleAddressAccountStoreError> {
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
        .map_err(|e| SingleAddressAccountStoreError::BadPhrase(e))?;

        let master_private_key =
            Bip32PrivateKey::from_bip39_entropy(mnemonic.entropy(), mnemonic_password.as_bytes())
                .derive(harden(1852))
                .derive(harden(1815));

        // TODO: Check how good this RNG actually is.
        // Use Godot RNG for Scrypt salt and AES initialization vector
        let mut crypto = Crypto::new();
        let salt: PackedByteArray = crypto.generate_random_bytes(64);
        let aes_iv_array: PackedByteArray = crypto.generate_random_bytes(16);
        // this is safe
        let aes_iv = <&[u8; 16]>::try_from(aes_iv_array.as_slice()).unwrap();

        let scrypt_params = scrypt::Params::recommended();

        let pbes2_params =
            pbes2::Parameters::scrypt_aes128cbc(scrypt_params, salt.as_slice(), aes_iv)
                .map_err(|e| SingleAddressAccountStoreError::Pkcs5Error(e))?;

        let encrypted_master_private_key = pbes2_params
            .encrypt(account_password, master_private_key.as_bytes().as_slice())
            .map_err(|e| SingleAddressAccountStoreError::Pkcs5Error(e))?;

        // We also store the account public keys, unencrypted
        let mut account_public_keys = Array::<PackedByteArray>::new();

        // We store the first account (zero index). Any further accounts need to be created.
        account_public_keys.push(PackedByteArray::from(
            master_private_key
                .derive(0)
                .to_public()
                .as_bytes()
                .as_slice(),
        ));

        Ok(Self {
            encrypted_master_private_key: PackedByteArray::from(
                encrypted_master_private_key.as_slice(),
            ),
            account_public_keys,
            scrypt_salt: salt,
            scrypt_log_n: scrypt_params.log_n(),
            scrypt_r: scrypt_params.r(),
            scrypt_p: scrypt_params.p(),
            aes_iv: aes_iv_array,
        })
    }

    #[func]
    fn _import(phrase: String, mnemonic_password: String, account_password: String) -> Gd<GResult> {
        Self::to_gresult_class(Self::import(phrase, mnemonic_password, account_password))
    }

    fn get_scrypt_params(&self) -> Result<scrypt::Params, SingleAddressAccountStoreError> {
        scrypt::Params::new(
            self.scrypt_log_n,
            self.scrypt_r,
            self.scrypt_p,
            10, // we don't care about `len` parameter, it's not used
        )
        .map_err(|e| SingleAddressAccountStoreError::BadScryptParams(e))
    }

    fn get_pbes2_params(&self) -> Result<pbes2::Parameters, SingleAddressAccountStoreError> {
        let scrypt_params = self.get_scrypt_params()?;
        let aes_iv = <&[u8; 16]>::try_from(self.aes_iv.as_slice())
            .map_err(|e| SingleAddressAccountStoreError::CouldNotParseAesIv(e))?;
        pbes2::Parameters::scrypt_aes128cbc(scrypt_params, self.scrypt_salt.as_slice(), aes_iv)
            .map_err(|e| SingleAddressAccountStoreError::Pkcs5Error(e))
    }

    fn with_account_private_key<F, O>(
        &self,
        password: String,
        account_index: u32,
        f: F,
    ) -> Result<O, SingleAddressAccountStoreError>
    where
        F: Fn(Bip32PrivateKey) -> O,
    {
        self.with_master_private_key(password, |master_key| f(master_key.derive(account_index)))
    }

    fn with_master_private_key<F, O>(
        &self,
        password: String,
        f: F,
    ) -> Result<O, SingleAddressAccountStoreError>
    where
        F: Fn(Bip32PrivateKey) -> O,
    {
        let pbes2_params = self.get_pbes2_params()?;
        let decrypted_bytes = pbes2_params
            .decrypt(
                AsRef::<[u8]>::as_ref(&password),
                self.encrypted_master_private_key.as_slice(),
            )
            .map_err(|e| SingleAddressAccountStoreError::Pkcs5Error(e))?;
        let master_key = Bip32PrivateKey::from_bytes(decrypted_bytes.as_slice())
            .map_err(|e| SingleAddressAccountStoreError::Bip32Error(e))?;
        Ok(f(master_key))
    }

    fn get_address(&self, account_index: usize) -> Result<Address, SingleAddressAccountStoreError> {
        let account_key: Bip32PublicKey =
            Bip32PublicKey::from_bytes(self.account_public_keys.get(account_index).as_slice())
                .map_err(|e| SingleAddressAccountStoreError::Bip32Error(e))?;
        let spend = account_key.derive(0).unwrap().derive(0).unwrap();
        let stake = account_key.derive(2).unwrap().derive(0).unwrap();
        let spend_cred = StakeCredential::from_keyhash(&spend.to_raw_key().hash());
        let stake_cred = StakeCredential::from_keyhash(&stake.to_raw_key().hash());

        // TODO: We should not hardcode the network
        Ok(BaseAddress::new(
            NetworkInfo::testnet_preview().network_id(),
            &spend_cred,
            &stake_cred,
        )
        .to_address())
    }

    /// It may fail due to a conversion error to Bech32.
    // FIXME: We should be using a prefix that depends on the network we are connecting to.
    fn get_address_bech32(
        &self,
        account_index: usize,
    ) -> Result<String, SingleAddressAccountStoreError> {
        let addr = self.get_address(account_index)?;
        addr.to_bech32(None)
            .map_err(|e| SingleAddressAccountStoreError::Bip32Error(e))
    }

    #[func]
    fn _get_address_bech32(&self, account_index: u64) -> Gd<GResult> {
        Self::to_gresult(self.get_address_bech32(account_index as usize))
    }

    fn sign_transaction(
        &self,
        password: String,
        account_index: u32,
        gtx: &GTransaction,
    ) -> Result<GSignature, SingleAddressAccountStoreError> {
        self.with_account_private_key(password, account_index, |master_private_key| {
            let spend_key = master_private_key
                .derive(account_index)
                .derive(0)
                .derive(0)
                .to_raw_key();
            let stake_key = master_private_key
                .derive(account_index)
                .derive(2)
                .derive(0)
                .to_raw_key();
            let tx_hash = hash_transaction(&gtx.transaction.body());
            GSignature {
                signature: vec![
                    make_vkey_witness(&tx_hash, &spend_key),
                    make_vkey_witness(&tx_hash, &stake_key),
                ],
            }
        })
    }

    #[func]
    fn _sign_transaction(
        &self,
        password: String,
        account_index: u32,
        gtx: Gd<GTransaction>,
    ) -> Gd<GResult> {
        Self::to_gresult_class(self.sign_transaction(password, account_index, &gtx.bind()))
    }

    fn add_account(&mut self, password: String) -> Result<String, SingleAddressAccountStoreError> {
        // TODO: Make this safer
        let new_account_index = (self.account_public_keys.len() + 1) as u32;
        let new_account_key = self.with_master_private_key(password, |master_key| {
            master_key.derive(new_account_index).to_public()
        })?;

        let spend = new_account_key.derive(0).unwrap().derive(0).unwrap();
        let stake = new_account_key.derive(2).unwrap().derive(0).unwrap();
        let spend_cred = StakeCredential::from_keyhash(&spend.to_raw_key().hash());
        let stake_cred = StakeCredential::from_keyhash(&stake.to_raw_key().hash());

        // // TODO: We should not hardcode the network
        // Ok(BaseAddress::new(
        //     NetworkInfo::testnet_preview().network_id(),
        //     &spend_cred,
        //     &stake_cred,
        // )
        // }
    }
}

// TODO: qualify all CSL types and skip renaming
#[derive(GodotClass)]
#[class(base=RefCounted, rename=Signature)]
struct GSignature {
    signature: Vec<Vkeywitness>,
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
        for witness in &signature.bind().signature {
            vkey_witnesses.add(witness);
        }
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
            .add_output(&output)
            .expect("Could not add output");
        tx_builder
            .add_inputs_from(&utxos, CoinSelectionStrategyCIP2::LargestFirstMultiAsset)
            .expect("Could not add inputs");
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
