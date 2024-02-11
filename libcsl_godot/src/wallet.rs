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
use cardano_serialization_lib::address::{Address, BaseAddress, NetworkInfo, StakeCredential};
use cardano_serialization_lib::crypto::{Bip32PrivateKey, Bip32PublicKey};
use cardano_serialization_lib::error::JsError;
use cardano_serialization_lib::utils::{hash_transaction, make_vkey_witness};
use godot::builtin::meta::GodotConvert;
use godot::engine::Crypto;
use godot::prelude::*;
use pkcs5::{pbes2, Error};
use scrypt::errors::InvalidParams;

use crate::gresult::{FailsWith, GResult};
use crate::{GSignature, GTransaction};

/// A single address wallet is a wallet with possibly many accounts
/// and where each account has one address. It is possible to switch from one
/// account to the other, but adding new accounts is not possible.
///
/// A `SingleAddressWallet` is essentially a view into a
/// `SingleAddressWalletStore`, so mutating the wallet (by adding or removing
/// accounts) is in that struct's scope.
#[derive(GodotClass)]
#[class(base=Object, rename=_SingleAddressWallet)]
pub struct SingleAddressWallet {
    encrypted_master_private_key: Vec<u8>,
    salt: Vec<u8>,
    aes_iv: Vec<u8>,
    scrypt_params: scrypt::Params,
    accounts: BTreeMap<u32, AccountInfo>,
    // Currently selected account
    account_info: AccountInfo,
}

#[derive(Debug)]
pub enum SingleAddressWalletError {
    DecryptionError(pkcs5::Error),
    BadDecryptedKey(JsError),
    Bech32Error(JsError),
    NonExistentAccount(u32),
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
        password: String,
        gtx: Gd<GTransaction>,
    ) -> Result<GSignature, SingleAddressWalletError> {
        let pbes2_params = self.get_pbes2_params();
        with_account_private_key(
            pbes2_params,
            self.encrypted_master_private_key.as_slice(),
            password,
            self.account_info.index,
            &mut |account_private_key| {
                let spend_key = account_private_key.derive(0).derive(0).to_raw_key();
                let tx_hash = hash_transaction(&gtx.bind().transaction.body());
                GSignature {
                    signature: vec![make_vkey_witness(&tx_hash, &spend_key)],
                }
            },
        )
    }

    #[func]
    fn _sign_transaction(&self, password: String, gtx: Gd<GTransaction>) -> Gd<GResult> {
        Self::to_gresult_class(self.sign_transaction(password, gtx))
    }

    pub fn get_address(&self) -> Address {
        address_from_key(&self.account_info.public_key)
    }

    pub fn get_address_bech32(&self) -> GString {
        self.account_info.address_bech32.to_owned()
    }

    #[func]
    fn _get_address_bech32(&self) -> GString {
        self.get_address_bech32()
    }

    // Switch to the given account
    pub fn switch_account(&mut self, account_index: u32) -> Result<(), SingleAddressWalletError> {
        let new_account = self
            .accounts
            .get(&account_index)
            .ok_or(SingleAddressWalletError::NonExistentAccount(account_index))?;
        self.account_info = new_account.to_owned();
        Ok(())
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
        phrase_password: String,
        wallet_password: String,
        account_index: u32,
        account_name: String,
        account_description: String,
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

        let master_private_key =
            Bip32PrivateKey::from_bip39_entropy(mnemonic.entropy(), phrase_password.as_bytes())
                .derive(harden(1852))
                .derive(harden(1815));

        // TODO: Check how good this RNG actually is.
        // Use Godot RNG for Scrypt salt and AES initialization vector
        let mut crypto = Crypto::new();
        let salt: PackedByteArray = crypto.generate_random_bytes(64);
        // this is safe
        let aes_iv_array: PackedByteArray = crypto.generate_random_bytes(16);
        let aes_iv = <&[u8; 16]>::try_from(aes_iv_array.as_slice()).unwrap();

        // Create PBES2 params and encrypt the master key.
        let scrypt_params = scrypt::Params::recommended();
        let pbes2_params =
            pbes2::Parameters::scrypt_aes128cbc(scrypt_params, salt.as_slice(), aes_iv)
                .map_err(|e| SingleAddressWalletStoreError::Pkcs5Error(e))?;

        let encrypted_master_private_key = pbes2_params
            .encrypt(wallet_password, master_private_key.as_bytes().as_slice())
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
            aes_iv: aes_iv_array.clone(),
        };

        // We return a `SingleAddressWallet` (for convenience). We know that
        // all the encryption parameters work by this point, so no validation
        // is necessary.
        let mut account_infos = BTreeMap::new();
        let public_key = duplicate_key(&account_pub_key);
        let address = address_from_key(&public_key);
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
            aes_iv,
            &scrypt_params,
            account_info,
            account_infos,
        );

        Ok(SingleAddressWalletImportResult {
            wallet_store: Gd::from_object(wallet_store),
            wallet: Gd::from_object(wallet),
        })
    }

    /// Obtains a `SingleAddressWallet` that can be used for signing operations.
    /// This step may fail, since a `SingleAddressWalletStore` is a resource
    /// loaded from disk and may contain erroneous information.
    pub fn get_wallet(
        &self,
        account_index: u32,
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
        let account_infos = Self::make_account_info_map(&self.accounts)?;
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
        ))
    }

    #[func]
    pub fn _get_wallet(&self, account_index: u32) -> Gd<GResult> {
        Self::to_gresult_class(self.get_wallet(account_index))
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
    ) -> SingleAddressWallet {
        SingleAddressWallet {
            encrypted_master_private_key: Vec::from(encrypted_master_key),
            salt: salt.to_vec(),
            aes_iv: aes_iv.to_vec(),
            scrypt_params: scrypt_params.clone(),
            account_info,
            accounts: account_infos,
        }
    }

    // Parse accounts as public keys.
    fn make_account_info_map(
        accounts: &Array<Gd<Account>>,
    ) -> Result<BTreeMap<u32, AccountInfo>, SingleAddressWalletStoreError> {
        let mut account_infos = BTreeMap::new();
        for (index, account) in accounts.iter_shared().enumerate() {
            let account = account.bind();
            let public_key = Bip32PublicKey::from_bytes(account.public_key.as_slice())
                .map_err(|e| SingleAddressWalletStoreError::Bip32Error(e))?;
            let address = address_from_key(&public_key);
            let address_bech32 = address
                .to_bech32(None)
                .map_err(|e| SingleAddressWalletStoreError::Bip32Error(e))?
                .to_godot();
            let account_info = AccountInfo {
                index: index as u32,
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

    #[func]
    fn _import_from_seedphrase(
        phrase: String,
        mnemonic_password: String,
        account_password: String,
        account_index: u32,
        account_name: String,
        account_description: String,
    ) -> Gd<GResult> {
        Self::to_gresult_class(Self::import_from_seedphrase(
            phrase,
            mnemonic_password,
            account_password,
            account_index,
            account_name,
            account_description,
        ))
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

    /// This just stores the public key of the new account. The new account's
    /// index will be equal to the largest stored index + 1.
    pub fn add_account(
        &mut self,
        name: GString,
        description: GString,
        password: String,
    ) -> Result<Bip32PublicKey, SingleAddressWalletStoreError> {
        let max_index = self.accounts.iter_shared().map(|a| a.bind().index).max();
        // if there are no accounts stored, we just use 0 as index
        let new_account_index = max_index.map_or(0, |i| i + 1);
        let pbes2_params = self.get_pbes2_params()?;
        let encrypted_master_private_key = self.encrypted_master_private_key.to_vec();
        Self::add_account_helper(
            name,
            description,
            password,
            new_account_index,
            pbes2_params,
            encrypted_master_private_key.as_slice(),
            &mut (self.accounts.duplicate_shallow()),
        )
    }

    // This implementation avoids using &mut self to escape borrowing issues.
    fn add_account_helper(
        name: GString,
        description: GString,
        password: String,
        new_account_index: u32,
        pbes2_params: pbes2::Parameters,
        encrypted_master_private_key: &[u8],
        accounts: &mut Array<Gd<Account>>,
    ) -> Result<Bip32PublicKey, SingleAddressWalletStoreError> {
        with_master_private_key(
            pbes2_params,
            encrypted_master_private_key.to_vec().as_slice(),
            password,
            &mut |master_key| {
                let new_account_key = master_key.derive(harden(new_account_index)).to_public();
                let new_account = Account {
                    index: new_account_index,
                    name: name.clone(),
                    description: description.clone(),
                    public_key: PackedByteArray::from(new_account_key.as_bytes().as_slice()),
                };
                accounts.push(Gd::from_object(new_account));
                new_account_key
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
    address: Address,
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

// Utility functions
fn harden(index: u32) -> u32 {
    return index | 0x80000000;
}

fn with_master_private_key<F, O, E>(
    pbes2_params: pbes2::Parameters,
    encrypted_master_private_key: &[u8],
    password: String,
    f: &mut F,
) -> Result<O, E>
where
    F: FnMut(Bip32PrivateKey) -> O,
    E: From<Error> + From<JsError>,
{
    let decrypted_bytes = pbes2_params.decrypt(
        AsRef::<[u8]>::as_ref(&password),
        encrypted_master_private_key,
    )?;
    let master_key = Bip32PrivateKey::from_bytes(decrypted_bytes.as_slice())?;
    Ok(f(master_key))
}

fn with_account_private_key<F, O, E>(
    pbes2_params: pbes2::Parameters,
    encrypted_master_private_key: &[u8],
    password: String,
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
fn address_from_key(key: &Bip32PublicKey) -> Address {
    let spend = key.derive(0).unwrap().derive(0).unwrap();
    let stake = key.derive(2).unwrap().derive(0).unwrap();
    let spend_cred = StakeCredential::from_keyhash(&spend.to_raw_key().hash());
    let stake_cred = StakeCredential::from_keyhash(&stake.to_raw_key().hash());

    // TODO: We should not hardcode the network
    BaseAddress::new(
        NetworkInfo::testnet_preview().network_id(),
        &spend_cred,
        &stake_cred,
    )
    .to_address()
}
