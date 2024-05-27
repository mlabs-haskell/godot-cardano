//! This module implements `SingleAddressWallet` and its resource counterpart
//! `SingleAddressWalletStore`. Together, these implement a Cardano
//! single-address wallet with multiple accounts, that can be persisted as a
//! Godot resource.
//!
//! The querying functionality, however, is implemented in the GDScript side
//! of the codebase.
use std::array::TryFromSliceError;
use std::collections::BTreeMap;

use bip32::{Language, Mnemonic};
use cardano_serialization_lib::address::Address as CSLAddress;
use cardano_serialization_lib::address::{BaseAddress, StakeCredential};
use cardano_serialization_lib::crypto::{Bip32PrivateKey, Bip32PublicKey};
use cardano_serialization_lib::error::JsError;
use cardano_serialization_lib::utils::{hash_transaction, make_vkey_witness};
use godot::builtin::meta::GodotConvert;
use godot::prelude::*;
use pkcs5::{pbes2, Error};
use rand::{RngCore, SeedableRng};
use scrypt::errors::InvalidParams;

use crate::cip_30_sign::DataSignature;
use crate::cip_8_sign;
use crate::gresult::{FailsWith, GResult};
use crate::ledger::transaction::{Address, Signature, Transaction};
use cardano_message_signing as cms;

/// A single address wallet is a wallet with possibly many accounts
/// and where each account has one address. It is possible to switch from one
/// account to the other, but adding new accounts is not possible.
///
/// A `SingleAddressWallet` is essentially a view into a
/// `SingleAddressWalletStore`, so mutating the wallet (by adding or removing
/// accounts) is in that struct's scope.
#[derive(GodotClass)]
#[class(base=RefCounted, rename=_SingleAddressWallet)]
pub struct SingleAddressWallet {
    encrypted_master_private_key: Vec<u8>,
    salt: Vec<u8>,
    aes_iv: Vec<u8>,
    scrypt_params: scrypt::Params,
    accounts: BTreeMap<u32, AccountInfo>,
    // Currently selected account
    account_info: AccountInfo,
    network_id: u8,
}

#[derive(Debug)]
pub enum SingleAddressWalletError {
    DecryptionError(pkcs5::Error),
    BadDecryptedKey(JsError),
    Bech32Error(JsError),
    NonExistentAccount(u32),
    DataSignCip30Error(cms::error::JsError),
}

impl GodotConvert for SingleAddressWalletError {
    type Via = i64;
}

impl ToGodot for SingleAddressWalletError {
    fn to_godot(&self) -> Self::Via {
        use SingleAddressWalletError::*;
        match self {
            DecryptionError(_) => 1,
            BadDecryptedKey(_) => 2,
            Bech32Error(_) => 3,
            NonExistentAccount(_) => 4,
            DataSignCip30Error(_) => 5,
        }
    }
}

impl From<Error> for SingleAddressWalletError {
    fn from(value: Error) -> Self {
        SingleAddressWalletError::DecryptionError(value)
    }
}

impl From<JsError> for SingleAddressWalletError {
    fn from(value: JsError) -> Self {
        SingleAddressWalletError::BadDecryptedKey(value)
    }
}

impl FailsWith for SingleAddressWallet {
    type E = SingleAddressWalletError;
}

#[godot_api]
impl SingleAddressWallet {
    fn get_pbes2_params(&self) -> pbes2::Parameters {
        // We know this is safe because we only construct a `SingleAddressWallet`
        // by using `SingleAddressWalletStore::get_wallet`, which validates this
        // is possible.
        let aes_iv = <&[u8; 16]>::try_from(self.aes_iv.as_slice()).unwrap();
        pbes2::Parameters::scrypt_aes128cbc(self.scrypt_params, self.salt.as_slice(), aes_iv)
            .unwrap()
    }

    // Sign a transaction using the given account's key. This operation requires
    // the wallet password.
    pub fn sign_transaction(
        &self,
        password: PackedByteArray,
        gtx: Gd<Transaction>,
    ) -> Result<Signature, SingleAddressWalletError> {
        let pbes2_params = self.get_pbes2_params();
        with_account_private_key(
            pbes2_params,
            self.encrypted_master_private_key.as_slice(),
            password.to_vec().as_slice(),
            self.account_info.index,
            &mut |account_private_key| {
                let spend_key = account_private_key.derive(0).derive(0).to_raw_key();
                let tx_hash = hash_transaction(&gtx.bind().transaction.body());
                Signature {
                    signature: make_vkey_witness(&tx_hash, &spend_key),
                }
            },
        )
    }

    #[func]
    fn _sign_transaction(&self, password: PackedByteArray, gtx: Gd<Transaction>) -> Gd<GResult> {
        Self::to_gresult_class(self.sign_transaction(password, gtx))
    }

    // Sign a transaction using the given account's key. This operation requires
    // the wallet password.
    pub fn sign_data(
        &self,
        password: PackedByteArray,
        cbor_string: String,
    ) -> Result<DataSignature, SingleAddressWalletError> {
        let pbes2_params = self.get_pbes2_params();

        let data = hex::decode(cbor_string).expect("CBOR decoding failed");

        let res = with_account_private_key(
            pbes2_params,
            self.encrypted_master_private_key.as_slice(),
            password.to_vec().as_slice(),
            self.account_info.index,
            &mut |account_private_key| {
                let spend_key = account_private_key.derive(0).derive(0);
                let address = address_from_key(&account_private_key.to_public());
                cip_8_sign::sign_data(data.clone(), &spend_key, &address)
                    .map_err(SingleAddressWalletError::DataSignCip30Error)
            },
        );
        match res {
            Ok(sign_result) => sign_result.map(DataSignature::from),
            Err(other_err) => Err(other_err),
        }
    }

    #[func]
    fn _sign_data(&self, password: PackedByteArray, cbor_string: String) -> Gd<GResult> {
        Self::to_gresult_class(self.sign_data(password, cbor_string))
    }

    pub fn get_address(&self) -> Gd<Address> {
        Gd::from_object(Address {
            address: address_from_key(self.network_id, &self.account_info.public_key),
        })
    }

    #[func]
    fn _get_address(&self) -> Gd<Address> {
        self.get_address()
    }

    pub fn get_address_bech32(&self) -> GString {
        self.account_info.address_bech32.to_owned()
    }

    #[func]
    fn _get_address_bech32(&self) -> GString {
        self.get_address_bech32()
    }

    // Switch to the given account
    pub fn switch_account(&mut self, account_index: u32) -> Result<u32, SingleAddressWalletError> {
        let new_account = self
            .accounts
            .get(&account_index)
            .ok_or(SingleAddressWalletError::NonExistentAccount(account_index))?;
        self.account_info = new_account.to_owned();
        Ok(account_index)
    }

    #[func]
    fn _switch_account(&mut self, account_index: u32) -> Gd<GResult> {
        Self::to_gresult(self.switch_account(account_index))
    }
}

/// The backing storage of a `SingleAddressWallet`.
///
/// The wallet can be imported by inputting a seed phrase together
/// with a password (as explained in the BIP39 standard).
///
/// The wallet is serialised to disk, but as the Cardano private master key.
/// We are not interested in preserving the seed phrase or other currencies' keys.
/// For safety, the private key is stored using the PBES2 encryption scheme.
///
/// For convenience, the account public key is also stored. Considering that
/// this is a single address wallet, not much privacy is lost by simply storing
/// the public key, as it is equivalent to storing the only address that will
/// be in use for any given account.
#[derive(GodotClass)]
#[class(base=Resource, rename=_SingleAddressWalletStore)]
pub struct SingleAddressWalletStore {
    #[var]
    encrypted_master_private_key: PackedByteArray,
    #[var]
    accounts: Array<Gd<Account>>,
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
pub enum SingleAddressWalletStoreError {
    BadPhrase(bip32::Error),
    Bip32Error(JsError),
    Pkcs5Error(pkcs5::Error),
    BadScryptParams(InvalidParams),
    CouldNotParseAesIv(TryFromSliceError),
    AccountNotFound(u32),
}

impl GodotConvert for SingleAddressWalletStoreError {
    type Via = i64;
}

impl ToGodot for SingleAddressWalletStoreError {
    fn to_godot(&self) -> Self::Via {
        use SingleAddressWalletStoreError::*;
        match self {
            BadPhrase(_) => 1,
            Bip32Error(_) => 2,
            Pkcs5Error(_) => 3,
            BadScryptParams(_) => 4,
            CouldNotParseAesIv(_) => 5,
            AccountNotFound(_) => 6,
        }
    }
}

impl From<Error> for SingleAddressWalletStoreError {
    fn from(value: Error) -> Self {
        SingleAddressWalletStoreError::Pkcs5Error(value)
    }
}

impl From<JsError> for SingleAddressWalletStoreError {
    fn from(value: JsError) -> Self {
        SingleAddressWalletStoreError::Bip32Error(value)
    }
}

impl FailsWith for SingleAddressWalletStore {
    type E = SingleAddressWalletStoreError;
}

#[godot_api]
impl SingleAddressWalletStore {
    /// Imports a wallet from a seed `phrase` and (possibly) a
    /// `phrase_password` (an empty string should be used if there is no
    /// phrase password).
    ///
    /// The wallet will be encrypted using the `wallet_password` and one
    /// account will be generated. This password should be *STRONG*.
    ///
    /// Optionally, the `account_index` may be selected (by default it's zero).
    /// A name and description may be used for the account.
    pub fn import_from_seedphrase(
        phrase: String,
        phrase_password: PackedByteArray,
        wallet_password: PackedByteArray,
        account_index: u32,
        account_name: String,
        account_description: String,
        network_id: u8,
    ) -> Result<SingleAddressWalletImportResult, SingleAddressWalletStoreError> {
        // We obtain the master private key with the mnemonic and the user
        // password
        let mnemonic = Mnemonic::new(
            phrase
                .to_lowercase()
                .split_whitespace()
                .collect::<Vec<_>>()
                .join(" "),
            Language::English,
        )
        .map_err(|e| SingleAddressWalletStoreError::BadPhrase(e))?;
        Self::from_entropy(
            mnemonic.entropy(),
            phrase_password,
            wallet_password,
            account_index,
            account_name,
            account_description,
            network_id,
        )
    }

    /// Create a `SingleAddressWalletStore` by using entropy to generate the
    /// private key.
    ///
    /// The seed phrase is stored in the `wallet_seedphrase` parameter.
    pub fn create(
        wallet_password: PackedByteArray,
        account_index: u32,
        account_name: String,
        account_description: String,
        network_id: u8,
    ) -> Result<SingleAddressWalletCreateResult, SingleAddressWalletStoreError> {
        // Widely considered to be a good cryptographic source of entropy:
        // https://rust-random.github.io/book/guide-rngs.html
        let rng = rand::rngs::StdRng::from_entropy();
        let seed_phrase = Mnemonic::random(rng, Language::English);
        let entropy_bytes = seed_phrase.entropy();
        let SingleAddressWalletImportResult {
            wallet_store,
            wallet,
        } = Self::from_entropy(
            entropy_bytes,
            PackedByteArray::new(),
            wallet_password,
            account_index,
            account_name,
            account_description,
            network_id,
        )?;
        Ok(SingleAddressWalletCreateResult {
            wallet_store,
            wallet,
            seed_phrase: seed_phrase.phrase().to_string().to_godot(),
        })
    }

    pub fn from_entropy(
        entropy: &[u8],
        phrase_password: PackedByteArray,
        wallet_password: PackedByteArray,
        account_index: u32,
        account_name: String,
        account_description: String,
        network_id: u8,
    ) -> Result<SingleAddressWalletImportResult, SingleAddressWalletStoreError> {
        let master_private_key =
            Bip32PrivateKey::from_bip39_entropy(entropy, phrase_password.as_slice())
                .derive(harden(1852))
                .derive(harden(1815));

        let mut rng = rand::rngs::StdRng::from_entropy();
        let salt: PackedByteArray = {
            let mut bs: [u8; 64] = [0; 64];
            rng.fill_bytes(&mut bs);
            PackedByteArray::from(bs.as_slice())
        };
        let aes_iv_array: [u8; 16] = {
            let mut bs: [u8; 16] = [0; 16];
            rng.fill_bytes(&mut bs);
            bs
        };
        let aes_iv: PackedByteArray = PackedByteArray::from(aes_iv_array.as_slice());

        // Create PBES2 params and encrypt the master key.
        //let scrypt_params = scrypt::Params::recommended();
        // FIXME: find the right parameters to balance performance with security
        let scrypt_params = scrypt::Params::new(12, 4, 1, 32).unwrap();
        let pbes2_params =
            pbes2::Parameters::scrypt_aes128cbc(scrypt_params, salt.as_slice(), &aes_iv_array)
                .map_err(|e| SingleAddressWalletStoreError::Pkcs5Error(e))?;

        let encrypted_master_private_key = pbes2_params
            .encrypt(
                wallet_password.as_slice(),
                master_private_key.as_bytes().as_slice(),
            )
            .map_err(|e| SingleAddressWalletStoreError::Pkcs5Error(e))?;

        // We store the first account (zero index). Any further accounts need
        // to be added manually.
        let account_pub_key = master_private_key.derive(harden(account_index)).to_public();
        let account = Account {
            index: account_index,
            name: if account_name == "" {
                GString::from("Default")
            } else {
                account_name.to_godot()
            },
            description: if account_description == "" {
                GString::from("Default account")
            } else {
                account_description.to_godot()
            },
            public_key: PackedByteArray::from(account_pub_key.as_bytes().as_slice()),
        };

        let mut accounts = Array::<Gd<Account>>::new();
        accounts.push(Gd::from_object(account));

        let wallet_store = Self {
            encrypted_master_private_key: PackedByteArray::from(
                encrypted_master_private_key.as_slice(),
            ),
            accounts,
            scrypt_salt: salt.clone(),
            scrypt_log_n: scrypt_params.log_n(),
            scrypt_r: scrypt_params.r(),
            scrypt_p: scrypt_params.p(),
            aes_iv,
        };

        // We return a `SingleAddressWallet` (for convenience). We know that
        // all the encryption parameters work by this point, so no validation
        // is necessary.
        let mut account_infos = BTreeMap::new();
        let public_key = duplicate_key(&account_pub_key);
        let address = address_from_key(network_id, &public_key);
        let address_bech32 = address.to_bech32(None)?.to_godot();
        let account_info = AccountInfo {
            index: account_index,
            name: account_name.to_godot(),
            description: account_description.to_godot(),
            public_key,
            address,
            address_bech32,
        };

        account_infos.insert(account_index, account_info.to_owned());
        let wallet = Self::unsafe_make_wallet(
            &encrypted_master_private_key,
            &salt.to_vec(),
            &aes_iv_array,
            &scrypt_params,
            account_info,
            account_infos,
            network_id,
        );

        Ok(SingleAddressWalletImportResult {
            wallet_store: Gd::from_object(wallet_store),
            wallet: Gd::from_object(wallet),
        })
    }

    #[func]
    fn _import_from_seedphrase(
        phrase: String,
        mnemonic_password: PackedByteArray,
        wallet_password: PackedByteArray,
        account_index: u32,
        account_name: String,
        account_description: String,
        network_id: u8,
    ) -> Gd<GResult> {
        Self::to_gresult_class(Self::import_from_seedphrase(
            phrase,
            mnemonic_password,
            wallet_password,
            account_index,
            account_name,
            account_description,
            network_id,
        ))
    }

    #[func]
    fn _create(
        wallet_password: PackedByteArray,
        account_index: u32,
        account_name: String,
        account_description: String,
        network_id: u8,
    ) -> Gd<GResult> {
        Self::to_gresult_class(Self::create(
            wallet_password,
            account_index,
            account_name,
            account_description,
            network_id,
        ))
    }

    /// Obtains a `SingleAddressWallet` that can be used for signing operations.
    /// This step may fail, since a `SingleAddressWalletStore` is a resource
    /// loaded from disk and may contain erroneous information.
    pub fn get_wallet(
        &self,
        account_index: u32,
        network_id: u8,
    ) -> Result<SingleAddressWallet, SingleAddressWalletStoreError> {
        // We must create the pbes2 params to validate the parameters
        let scrypt_params =
            scrypt::Params::new(self.scrypt_log_n, self.scrypt_r, self.scrypt_p, 10)
                .map_err(|e| SingleAddressWalletStoreError::BadScryptParams(e))?;
        let aes_iv = <&[u8; 16]>::try_from(self.aes_iv.as_slice())
            .map_err(|e| SingleAddressWalletStoreError::CouldNotParseAesIv(e))?;
        let _pbes2_params = pbes2::Parameters::scrypt_aes128cbc(
            scrypt_params,
            &self.scrypt_salt.as_slice(),
            aes_iv,
        )
        .map_err(|e| SingleAddressWalletStoreError::Pkcs5Error(e))?;
        // At this point, we know the parameters work.
        // We must also parse the accounts' public keys and obtain the current
        // key
        let account_infos = Self::make_account_info_map(network_id, &self.accounts)?;
        let account_info = account_infos.get(&account_index).ok_or(
            SingleAddressWalletStoreError::AccountNotFound(account_index),
        )?;

        Ok(Self::unsafe_make_wallet(
            self.encrypted_master_private_key.as_slice(),
            self.scrypt_salt.as_slice(),
            aes_iv,
            &scrypt_params,
            account_info.to_owned(),
            account_infos,
            network_id,
        ))
    }

    #[func]
    pub fn _get_wallet(&self, account_index: u32, network_id: u8) -> Gd<GResult> {
        Self::to_gresult_class(self.get_wallet(account_index, network_id))
    }

    /// This method *does not* validate that the contents of
    /// `SingleAddressWallet` constitute valid PBES2 parameters.
    fn unsafe_make_wallet(
        encrypted_master_key: &[u8],
        salt: &[u8],
        aes_iv: &[u8],
        scrypt_params: &scrypt::Params,
        account_info: AccountInfo,
        account_infos: BTreeMap<u32, AccountInfo>,
        network_id: u8,
    ) -> SingleAddressWallet {
        SingleAddressWallet {
            encrypted_master_private_key: Vec::from(encrypted_master_key),
            salt: salt.to_vec(),
            aes_iv: aes_iv.to_vec(),
            scrypt_params: scrypt_params.clone(),
            account_info,
            accounts: account_infos,
            network_id,
        }
    }

    // Parse accounts as public keys.
    fn make_account_info_map(
        network_id: u8,
        accounts: &Array<Gd<Account>>,
    ) -> Result<BTreeMap<u32, AccountInfo>, SingleAddressWalletStoreError> {
        let mut account_infos = BTreeMap::new();
        for account in accounts.iter_shared() {
            let account = account.bind();
            let public_key = Bip32PublicKey::from_bytes(account.public_key.as_slice())
                .map_err(|e| SingleAddressWalletStoreError::Bip32Error(e))?;
            let address = address_from_key(network_id, &public_key);
            let address_bech32 = address
                .to_bech32(None)
                .map_err(|e| SingleAddressWalletStoreError::Bip32Error(e))?
                .to_godot();
            let account_info = AccountInfo {
                index: account.index as u32,
                name: account.name.to_owned(),
                description: account.description.to_owned(),
                public_key,
                address,
                address_bech32,
            };
            account_infos.insert(account.index, account_info);
        }
        Ok(account_infos)
    }

    fn get_scrypt_params(&self) -> Result<scrypt::Params, SingleAddressWalletStoreError> {
        scrypt::Params::new(
            self.scrypt_log_n,
            self.scrypt_r,
            self.scrypt_p,
            10, // we don't care about `len` parameter, it's not used
        )
        .map_err(|e| SingleAddressWalletStoreError::BadScryptParams(e))
    }

    fn get_pbes2_params(&self) -> Result<pbes2::Parameters, SingleAddressWalletStoreError> {
        let scrypt_params = self.get_scrypt_params()?;
        let aes_iv = <&[u8; 16]>::try_from(self.aes_iv.as_slice())
            .map_err(|e| SingleAddressWalletStoreError::CouldNotParseAesIv(e))?;
        pbes2::Parameters::scrypt_aes128cbc(scrypt_params, self.scrypt_salt.as_slice(), aes_iv)
            .map_err(|e| SingleAddressWalletStoreError::Pkcs5Error(e))
    }

    #[func]
    pub fn _add_account(
        &mut self,
        account: u32,
        name: GString,
        description: GString,
        password: PackedByteArray,
    ) -> Gd<GResult> {
        Self::to_gresult(
            self.add_account(account, name, description, password)
                .map(|_| ()),
        )
    }

    /// This just stores the public key of the new account
    pub fn add_account(
        &mut self,
        account: u32,
        name: GString,
        description: GString,
        password: PackedByteArray,
    ) -> Result<Bip32PublicKey, SingleAddressWalletStoreError> {
        let pbes2_params = self.get_pbes2_params()?;
        let encrypted_master_private_key = self.encrypted_master_private_key.to_vec();
        let (account, private_key) = Self::add_account_helper(
            name,
            description,
            password,
            account,
            pbes2_params,
            encrypted_master_private_key.as_slice(),
        )?;
        self.accounts.push(Gd::from_object(account));
        Ok(private_key)
    }

    // This implementation avoids using &mut self to escape borrowing issues.
    fn add_account_helper(
        name: GString,
        description: GString,
        password: PackedByteArray,
        new_account_index: u32,
        pbes2_params: pbes2::Parameters,
        encrypted_master_private_key: &[u8],
    ) -> Result<(Account, Bip32PublicKey), SingleAddressWalletStoreError> {
        with_master_private_key(
            pbes2_params,
            encrypted_master_private_key.to_vec().as_slice(),
            password.to_vec().as_slice(),
            &mut |master_key| {
                let new_account_key = master_key.derive(harden(new_account_index)).to_public();
                let new_account = Account {
                    index: new_account_index,
                    name: name.clone(),
                    description: description.clone(),
                    public_key: PackedByteArray::from(new_account_key.as_bytes().as_slice()),
                };
                (new_account, new_account_key)
            },
        )
    }
}

/// An account, as stored within a `SingleAddressWalletStore`. This is a data
/// class and should not be manipulated directly
#[derive(GodotClass)]
#[class(base=Resource)]
pub struct Account {
    #[var]
    index: u32,
    #[var]
    name: GString,
    #[var]
    description: GString,
    #[var]
    public_key: PackedByteArray,
}

// Used internally inside `SingleAddressWallet` to track account information.
#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct AccountInfo {
    index: u32,
    name: GString,
    description: GString,
    public_key: Bip32PublicKey,
    address: CSLAddress,
    address_bech32: GString,
}

impl Clone for AccountInfo {
    fn clone(&self) -> Self {
        let public_key = duplicate_key(&self.public_key);
        AccountInfo {
            index: self.index,
            name: self.name.to_owned(),
            description: self.description.to_owned(),
            public_key,
            address: self.address.to_owned(),
            address_bech32: self.address_bech32.to_owned(),
        }
    }
}

#[derive(GodotClass)]
#[class(base=RefCounted, rename=_SingleAddressWalletImportResult)]
pub struct SingleAddressWalletImportResult {
    #[var]
    wallet_store: Gd<SingleAddressWalletStore>,
    #[var]
    wallet: Gd<SingleAddressWallet>,
}

#[derive(GodotClass)]
#[class(base=RefCounted, rename=_SingleAddressWalletCreateResult)]
pub struct SingleAddressWalletCreateResult {
    #[var]
    wallet_store: Gd<SingleAddressWalletStore>,
    #[var]
    wallet: Gd<SingleAddressWallet>,
    #[var]
    seed_phrase: GString,
}

// Utility functions
fn harden(index: u32) -> u32 {
    return index | 0x80000000;
}

fn with_master_private_key<F, O, E>(
    pbes2_params: pbes2::Parameters,
    encrypted_master_private_key: &[u8],
    password: &[u8],
    f: &mut F,
) -> Result<O, E>
where
    F: FnMut(Bip32PrivateKey) -> O,
    E: From<Error> + From<JsError>,
{
    let decrypted_bytes = pbes2_params.decrypt(password, encrypted_master_private_key)?;
    let master_key = Bip32PrivateKey::from_bytes(decrypted_bytes.as_slice())?;
    Ok(f(master_key))
}

fn with_account_private_key<F, O, E>(
    pbes2_params: pbes2::Parameters,
    encrypted_master_private_key: &[u8],
    password: &[u8],
    account_index: u32,
    f: &mut F,
) -> Result<O, E>
where
    F: FnMut(Bip32PrivateKey) -> O,
    E: From<Error> + From<JsError>,
{
    with_master_private_key(
        pbes2_params,
        encrypted_master_private_key,
        password,
        &mut |master_key| f(master_key.derive(harden(account_index))),
    )
}

// for some reason, keys are not cloneable or copiable
fn duplicate_key(k: &Bip32PublicKey) -> Bip32PublicKey {
    Bip32PublicKey::from_bytes(k.as_bytes().as_slice()).unwrap()
}

// Takes the account key
fn address_from_key(network_id: u8, key: &Bip32PublicKey) -> CSLAddress {
    let spend = key.derive(0).unwrap().derive(0).unwrap();
    let stake = key.derive(2).unwrap().derive(0).unwrap();
    let spend_cred = StakeCredential::from_keyhash(&spend.to_raw_key().hash());
    let stake_cred = StakeCredential::from_keyhash(&stake.to_raw_key().hash());

    BaseAddress::new(network_id, &spend_cred, &stake_cred).to_address()
}
