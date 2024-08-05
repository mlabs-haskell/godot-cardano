//! This module implements `SingleAddressWallet` and `SingleAddressWalletLoader`.
//! Together, these may be used to implement a Cardano single-address wallet with multiple accounts.
//!
//! By themselves, these classes are too low-level and error-prone to be used directly, and therefore
//! they are prefixed with underscores and are not part of the GDScript API.
//!
//! Also, it should be noted that all dynamic features (such as queries) are implemented in the GDScript
//! side of the codebase.
use std::array::TryFromSliceError;
use std::collections::BTreeMap;
use std::sync::mpsc::{self, Receiver, Sender};
use std::thread;

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

/// A single address wallet is a wallet with possibly many accounts and where
/// each account has one address.
///
/// A `SingleAddressWallet` is essentially a view into a
/// `SingleAddressWalletLoader` (a master key), with all mutation actions
/// forbidden (no account creation or editing). For this reason, `SingleAddressWallet`s
/// are created by calling the `get_wallet` method of the loader class.
///
/// After any mutation to the backing `SingleAddressWalletLoader`, a `SingleAddressWallet`
/// instance becomes immediately outdated and should be replaced.
#[derive(GodotClass, Clone)]
#[class(base=RefCounted, rename=_SingleAddressWallet)]
pub struct SingleAddressWallet {
    encrypted_master_private_key: Vec<u8>,
    salt: Vec<u8>,
    aes_iv: Vec<u8>,
    scrypt_params: scrypt::Params,
    account: Account,
    network: u8,
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
    // Sign a transaction using the given account's key. This operation requires
    // the wallet password.
    pub fn sign_transaction(
        &self,
        password: PackedByteArray,
        gtx: Gd<Transaction>,
    ) -> Result<Signature, SingleAddressWalletError> {
        let pbes2_params = unsafe_get_pbes2_params(&self.aes_iv, &self.scrypt_params, &self.salt);
        with_account_private_key(
            pbes2_params,
            self.encrypted_master_private_key.as_slice(),
            password.to_vec().as_slice(),
            self.account.index,
            &mut |account_private_key| {
                let spend_key = account_private_key.derive(0).derive(0).to_raw_key();
                let tx_hash = hash_transaction(&gtx.bind().transaction.body());
                Ok(Signature {
                    signature: make_vkey_witness(&tx_hash, &spend_key),
                })
            },
        )
    }

    #[func]
    fn _sign_transaction(&self, password: PackedByteArray, gtx: Gd<Transaction>) -> Gd<GResult> {
        Self::to_gresult_class(self.sign_transaction(password, gtx))
    }

    // Sign a data using the given account's key. This operation requires
    // the wallet password.
    pub fn sign_data(
        &self,
        password: Vec<u8>,
        data: Vec<u8>,
    ) -> Result<DataSignature, SingleAddressWalletError> {
        let pbes2_params = unsafe_get_pbes2_params(&self.aes_iv, &self.scrypt_params, &self.salt);
        let current_account = self.account.bind();
        let res = with_account_private_key(
            pbes2_params,
            self.encrypted_master_private_key.as_slice(),
            password.to_vec().as_slice(),
            current_account.index,
            &mut |account_private_key| {
                let spend_key = account_private_key.derive(0).derive(0);
                cip_8_sign::sign_data(
                    &spend_key,
                    self.account.bind().address.to_bytes(),
                    data.to_vec(),
                )
                .map_err(SingleAddressWalletError::DataSignCip30Error)
            },
        );
        match res {
            Ok(sign_result) => Ok(DataSignature::from(sign_result)),
            Err(other_err) => Err(other_err),
        }
    }

    #[func]
    fn _sign_data(&self, password: PackedByteArray, data: PackedByteArray) -> Gd<GResult> {
        Self::to_gresult_class(self.sign_data(password.to_vec(), data.to_vec()))
    }

    // pub fn get_base_address(&self) -> CSLAddress {
    //     address_from_key(self.network_id, &self.account_info.public_key)
    // }

    pub fn get_address(&self) -> Gd<Address> {
        Gd::from_object(Address {
            address: self.account.address.clone(),
        })
    }

    #[func]
    fn _get_address(&self) -> Gd<Address> {
        self.get_address()
    }

    #[func]
    pub fn get_address_bech32(&self) -> GString {
        self.account.address_bech32.to_godot()
    }

    // Switch to the given account
    #[func]
    pub fn switch_account(&mut self, new_account: Gd<Account>) -> u32 {
        self.account = new_account.bind().clone();
        self.account.index
    }

    #[func]
    pub fn get_network(&self) -> u8 {
        self.network
    }
}

/// The backing struct of a `SingleAddressWallet`. This struct is a safer
/// wrapper over the encrypted master key of a BIP32 wallet, with additional
/// features for creating, editing and keeping track of wallet accounts and
/// addresses.
///
/// A new `SingleAddressWalletLoader` may be created by:
///
/// * Calling `create`: this requires all the expected fields any BIP39
///   wallet needs. It returns a `SingleAddressWalletLoader`, as well as
///   a `SingleAddressWallet` with the given account loaded and the seed
///   phrase backup of the wallet.
///
/// A `SingleAddressWalletLoader` may be imported by:
///
/// * Using `import_from_seedphrase`, which requires a seed phrase and a
///   password (as explained in the BIP39 standard).
/// * Using `import_from_resource`, which requires a `Gd<Resource>` with
///   all the necessary fields. This is fundamentally unsafe if a `Resource`
///   not generated with `export` is passed.
///
/// A `SingleAddressWalletLoader` may be serialized by:
///
/// * Using `export_to_dict`, which generates a `Dictionary` with all the
///   necessary fields to create a `Resource` that can be imported.
///
/// The wallet is serialised to disk as the Cardano private master key.
/// We are not interested in preserving other currencies' keys. The seed phrase
/// is not stored either, only being returned during wallet creation.
///
/// For safety, the private key is stored using the PBES2 encryption scheme.
///
/// For convenience, the account public keys are also stored. Considering that
/// this is a single address wallet, not much privacy is lost by simply storing
/// the public key, as it is equivalent to storing the only address that will
/// be in use for any given account.
#[derive(GodotClass, Clone, Default)]
#[class(init, base=RefCounted, rename=_SingleAddressWalletLoader)]
pub struct SingleAddressWalletLoader {
    encrypted_master_private_key: Vec<u8>,
    salt: Vec<u8>,
    aes_iv: Vec<u8>,
    scrypt_params: scrypt::Params,
    accounts: BTreeMap<u32, Account>,
    network: u8,
}

#[derive(Debug, Clone)]
pub enum SingleAddressWalletLoaderError {
    BadPhrase(bip32::Error),
    Bip32Error(JsError),
    Pkcs5Error(pkcs5::Error),
    BadScryptParams(InvalidParams),
    CouldNotParseAesIv(TryFromSliceError),
    AccountNotFound(u32),
    AttributeNotFoundInResource(StringName),
    AttributeWithWrongTypeInResource(StringName),
    NoAccountsInWallet,
}

impl GodotConvert for SingleAddressWalletLoaderError {
    type Via = i64;
}

impl ToGodot for SingleAddressWalletLoaderError {
    fn to_godot(&self) -> Self::Via {
        use SingleAddressWalletLoaderError::*;
        match self {
            BadPhrase(_) => 1,
            Bip32Error(_) => 2,
            Pkcs5Error(_) => 3,
            BadScryptParams(_) => 4,
            CouldNotParseAesIv(_) => 5,
            AccountNotFound(_) => 6,
            AttributeNotFoundInResource(_) => 7,
            AttributeWithWrongTypeInResource(_) => 8,
            NoAccountsInWallet => 9,
        }
    }
}

impl From<Error> for SingleAddressWalletLoaderError {
    fn from(value: Error) -> Self {
        SingleAddressWalletLoaderError::Pkcs5Error(value)
    }
}

impl From<JsError> for SingleAddressWalletLoaderError {
    fn from(value: JsError) -> Self {
        SingleAddressWalletLoaderError::Bip32Error(value)
    }
}

impl From<InvalidParams> for SingleAddressWalletLoaderError {
    fn from(value: InvalidParams) -> Self {
        SingleAddressWalletLoaderError::BadScryptParams(value)
    }
}

impl FailsWith for SingleAddressWalletLoader {
    type E = SingleAddressWalletLoaderError;
}

#[godot_api]
impl SingleAddressWalletLoader {
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
        phrase_password: Vec<u8>,
        wallet_password: Vec<u8>,
        account_index: u32,
        account_name: String,
        account_description: String,
        network: u8,
    ) -> Result<SingleAddressWalletImportResult, SingleAddressWalletLoaderError> {
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
        .map_err(|e| SingleAddressWalletLoaderError::BadPhrase(e))?;
        Self::from_entropy(
            mnemonic.entropy(),
            phrase_password.to_vec(),
            wallet_password.to_vec(),
            account_index,
            account_name,
            account_description,
            network,
        )
    }

    /// This method checks that all fields are valid. It will do so by using
    /// the provided encryption parameters to load a wallet.
    fn check_fields(
        wallet_loader: &SingleAddressWalletLoader,
    ) -> Result<SingleAddressWallet, SingleAddressWalletLoaderError> {
        let first_account = wallet_loader
            .accounts
            .values()
            .next()
            .ok_or(SingleAddressWalletLoaderError::NoAccountsInWallet)?;

        // We validate that the PBES2 parameters are creatable.
        let aes_iv = <&[u8; 16]>::try_from(wallet_loader.aes_iv.as_slice())
            .map_err(|e| SingleAddressWalletLoaderError::CouldNotParseAesIv(e))?;
        let _pbes2_params = pbes2::Parameters::scrypt_aes128cbc(
            wallet_loader.scrypt_params,
            wallet_loader.salt.as_slice(),
            aes_iv,
        )
        .map_err(|e| SingleAddressWalletLoaderError::Pkcs5Error(e))?;

        // obtain a wallet
        let wallet = wallet_loader.get_wallet(first_account.index)?;

        Ok(wallet)
    }

    /// Create a `SingleAddressWalletLoader` by using entropy to generate the
    /// private key.
    ///
    /// The seed phrase is stored in the `wallet_seedphrase` parameter.
    pub fn create(
        wallet_password: Vec<u8>,
        account_index: u32,
        account_name: String,
        account_description: String,
        network: u8,
    ) -> Result<SingleAddressWalletCreateResult, SingleAddressWalletLoaderError> {
        // Considered to be a good cryptographic source of entropy:
        // https://rust-random.github.io/book/guide-rngs.html
        let rng = rand::rngs::StdRng::from_entropy();
        let seed_phrase = Mnemonic::random(rng, Language::English);
        let entropy_bytes = seed_phrase.entropy();
        let SingleAddressWalletImportResult {
            wallet_loader,
            wallet,
        } = Self::from_entropy(
            entropy_bytes,
            Vec::new(),
            wallet_password,
            account_index,
            account_name,
            account_description,
            network,
        )?;
        Ok(SingleAddressWalletCreateResult {
            wallet_loader: Gd::from_object(wallet_loader),
            wallet: Gd::from_object(wallet),
            seed_phrase: seed_phrase.phrase().to_string().to_godot(),
        })
    }

    fn from_entropy(
        entropy: &[u8],
        phrase_password: Vec<u8>,
        wallet_password: Vec<u8>,
        account_index: u32,
        account_name: String,
        account_description: String,
        network: u8,
    ) -> Result<SingleAddressWalletImportResult, SingleAddressWalletLoaderError> {
        let master_private_key =
            Bip32PrivateKey::from_bip39_entropy(entropy, phrase_password.as_slice())
                .derive(harden(1852))
                .derive(harden(1815));

        let mut rng = rand::rngs::StdRng::from_entropy();

        let salt_array: [u8; 64] = {
            let mut bs: [u8; 64] = [0; 64];
            rng.fill_bytes(&mut bs);
            bs
        };

        let salt: PackedByteArray = PackedByteArray::from(salt_array.as_slice());
        let aes_iv_array: [u8; 16] = {
            let mut bs: [u8; 16] = [0; 16];
            rng.fill_bytes(&mut bs);
            bs
        };

        // Create PBES2 params and encrypt the master key.
        // FIXME: ideally we would have a better choice for these parameters
        // for improved security, but this would depend on performing more
        // operations asynchronously and/or using a different set of parameters
        // for on-disk storage vs. in-memory.
        //let scrypt_params = scrypt::Params::recommended();
        let scrypt_params = mew_scrypt_params();
        let pbes2_params =
            pbes2::Parameters::scrypt_aes128cbc(scrypt_params, salt.as_slice(), &aes_iv_array)
                .map_err(|e| SingleAddressWalletLoaderError::Pkcs5Error(e))?;

        let encrypted_master_private_key = pbes2_params
            .encrypt(
                wallet_password.as_slice(),
                master_private_key.as_bytes().as_slice(),
            )
            .map_err(|e| SingleAddressWalletLoaderError::Pkcs5Error(e))?;

        // We create and store the first account. Any further accounts need to be added manually.
        let account = {
            let account_pub_key = master_private_key.derive(harden(account_index)).to_public();
            let address = address_from_key(network, &account_pub_key);
            let address_bech32 = address
                .to_bech32(None)
                .map_err(|e| SingleAddressWalletLoaderError::Bip32Error(e))?;

            Account {
                index: account_index,
                name: if account_name == "" {
                    "Default".to_string()
                } else {
                    account_name
                },
                description: if account_description == "" {
                    "Default account".to_string()
                } else {
                    account_description
                },
                public_key: duplicate_key(&account_pub_key),
                address,
                network,
                address_bech32,
            }
        };

        let mut accounts: BTreeMap<u32, Account> = BTreeMap::new();
        accounts.insert(account_index, account.clone());

        let wallet_loader = Self {
            encrypted_master_private_key: encrypted_master_private_key.to_vec(),
            accounts,
            scrypt_params,
            salt: salt_array.to_vec(),
            aes_iv: aes_iv_array.to_vec(),
            network,
        };

        // We return a `SingleAddressWallet` (for convenience).
        let wallet = wallet_loader.make_wallet(account);

        Ok(SingleAddressWalletImportResult {
            wallet_loader,
            wallet,
        })
    }

    /// Obtains a `SingleAddressWallet` that can be used for signing operations.
    /// It may fail if the account index is not found.
    pub fn get_wallet(
        &self,
        account_index: u32,
    ) -> Result<SingleAddressWallet, SingleAddressWalletLoaderError> {
        let account = self.accounts.get(&account_index).ok_or(
            SingleAddressWalletLoaderError::AccountNotFound(account_index),
        )?;

        Ok(self.make_wallet(account.clone()))
    }

    /// This just stores the public key of the new account
    pub fn add_account(
        &mut self,
        account_index: u32,
        name: GString,
        description: GString,
        password: PackedByteArray,
    ) -> Result<Account, SingleAddressWalletLoaderError> {
        let pbes2_params = unsafe_get_pbes2_params(&self.aes_iv, &self.scrypt_params, &self.salt);
        let encrypted_master_private_key = self.encrypted_master_private_key.to_vec();
        let (account, _) = Self::add_account_helper(
            name,
            description,
            password,
            account_index,
            pbes2_params,
            encrypted_master_private_key.as_slice(),
            self.network,
        )?;
        self.accounts.insert(account_index, account.clone());
        Ok(account)
    }

    /// HELPERS

    // This method *does not* validate that the contents of
    // `SingleAddressWallet` constitute valid PBES2 parameters.
    fn make_wallet(&self, account: Account) -> SingleAddressWallet {
        SingleAddressWallet {
            encrypted_master_private_key: self.encrypted_master_private_key.clone(),
            salt: self.salt.clone(),
            aes_iv: self.aes_iv.clone(),
            scrypt_params: self.scrypt_params,
            account,
            network: self.network,
        }
    }

    fn parse_accounts(
        resource: &Gd<Resource>,
        network: u8,
    ) -> Result<BTreeMap<u32, Account>, SingleAddressWalletLoaderError> {
        let accounts_untyped: Array<Gd<Resource>> = Self::get_attr("accounts", &resource)?;
        accounts_untyped
            .iter_shared()
            .enumerate()
            .map(|(idx, res): (usize, Gd<Resource>)| Self::parse_account(idx, res, network))
            .collect::<Result<BTreeMap<_, _>, SingleAddressWalletLoaderError>>()
    }

    fn parse_account(
        idx: usize,
        res: Gd<Resource>,
        network: u8,
    ) -> Result<(u32, Account), SingleAddressWalletLoaderError> {
        let public_key_ba: PackedByteArray = Self::get_attr("public_key", &res)?;
        let public_key = Bip32PublicKey::from_bytes(public_key_ba.as_slice())?;
        let address = address_from_key(network, &public_key);
        let address_bech32 = address.to_bech32(None)?;
        Ok((
            idx as u32,
            Account {
                index: Self::get_attr("index", &res)?,
                name: Self::get_attr("name", &res)?,
                description: Self::get_attr("description", &res)?,
                public_key,
                address,
                address_bech32,
                network,
            },
        ))
    }

    // helper for importing in a separate thread
    fn import_in_thread<F>(f: F) -> Gd<WalletImportReceiver>
    where
        F: Fn(Sender<Result<SingleAddressWalletImportResult, SingleAddressWalletLoaderError>>)
            + Send
            + 'static,
    {
        let (sender, receiver) = mpsc::channel();

        thread::spawn(move || {
            f(sender);
        });

        Gd::from_object(WalletImportReceiver {
            receiver: Some(receiver),
        })
    }

    // helper for getting attributes and casting them to the appropriate type
    fn get_attr<T>(name: &str, res: &Gd<Resource>) -> Result<T, SingleAddressWalletLoaderError>
    where
        T: FromGodot,
    {
        let attr_name = StringName::from(name);
        let attr: Variant = res.get(attr_name.clone());
        if attr.is_nil() {
            Err(SingleAddressWalletLoaderError::AttributeNotFoundInResource(
                attr_name,
            ))
        } else {
            match attr.try_to::<T>() {
                Ok(v) => Ok(v),
                Err(_) => Err(
                    SingleAddressWalletLoaderError::AttributeWithWrongTypeInResource(
                        attr_name.clone(),
                    ),
                ),
            }
        }
    }

    fn export_account_dicts(&self) -> Array<Dictionary> {
        let mut arr = Array::new();
        for (key, account) in &self.accounts {
            let account = account;
            let mut dict = Dictionary::new();
            dict.set("index", key.to_variant());
            dict.set("name", account.name.clone());
            dict.set("description", account.description.clone());
            dict.set(
                "public_key",
                PackedByteArray::from(account.public_key.as_bytes().as_slice()),
            );
            arr.push(dict);
        }
        arr
    }

    #[func]
    fn export_to_dict(&self) -> Dictionary {
        let mut dict = Dictionary::new();
        dict.set(
            "encrypted_master_private_key",
            PackedByteArray::from(self.encrypted_master_private_key.as_slice()),
        );
        dict.set("salt", PackedByteArray::from(self.salt.as_slice()));
        dict.set("scrypt_log_n", self.scrypt_params.log_n());
        dict.set("scrypt_r", self.scrypt_params.r());
        dict.set("scrypt_p", self.scrypt_params.p());
        dict.set("aes_iv", PackedByteArray::from(self.aes_iv.as_slice()));
        dict.set("accounts", self.export_account_dicts());
        dict
    }

    // UNSAFE! The fields need to be checked after importing
    fn import_from_dict(
        resource: Gd<Resource>,
        network: u8,
    ) -> Result<SingleAddressWalletLoader, SingleAddressWalletLoaderError> {
        // parse accounts
        let accounts = Self::parse_accounts(&resource, network)?;

        // create wallet loader

        let encrypted_master_private_key =
            Self::get_attr::<PackedByteArray>("encrypted_master_private_key", &resource)?.to_vec();

        let scrypt_params = {
            let log_n = Self::get_attr("scrypt_log_n", &resource)?;
            let r = Self::get_attr("scrypt_r", &resource)?;
            let p = Self::get_attr("scrypt_p", &resource)?;
            scrypt::Params::new(log_n, r, p, 32)
        }?;

        let aes_iv = Self::get_attr::<PackedByteArray>("aes_iv", &resource)?.to_vec();
        let salt = Self::get_attr::<PackedByteArray>("salt", &resource)?.to_vec();

        Ok(Self {
            encrypted_master_private_key,
            accounts,
            aes_iv,
            scrypt_params,
            salt,
            network,
        })
    }
    // This implementation avoids using &mut self to escape borrowing issues.
    fn add_account_helper(
        name: GString,
        description: GString,
        password: PackedByteArray,
        new_account_index: u32,
        pbes2_params: pbes2::Parameters,
        encrypted_master_private_key: &[u8],
        network: u8,
    ) -> Result<(Account, Bip32PublicKey), SingleAddressWalletLoaderError> {
        with_master_private_key(
            pbes2_params,
            encrypted_master_private_key.to_vec().as_slice(),
            password.to_vec().as_slice(),
            &mut |master_key| {
                let new_account_key = master_key.derive(harden(new_account_index)).to_public();
                let address = address_from_key(network, &new_account_key);
                let address_bech32: GString = address.to_bech32(None)?.to_godot();
                let new_account = Account {
                    index: new_account_index,
                    public_key: duplicate_key(&new_account_key),
                    name: name.to_string(),
                    description: description.to_string(),
                    network,
                    address,
                    address_bech32: address_bech32.to_string(),
                };
                Ok((new_account, new_account_key))
            },
        )
    }

    #[func]
    fn get_accounts(&self) -> Array<Gd<Account>> {
        self.accounts
            .values()
            .map(|o| Gd::from_object(o.clone()))
            .collect()
    }

    #[func]
    fn _import_from_seedphrase(
        phrase: String,
        mnemonic_password: PackedByteArray,
        wallet_password: PackedByteArray,
        account_index: u32,
        account_name: String,
        account_description: String,
        network: u8,
    ) -> Gd<WalletImportReceiver> {
        let mnemonic_password_v = mnemonic_password.to_vec();
        let wallet_password_v = wallet_password.to_vec();
        Self::import_in_thread(move |sender| {
            let result = Self::import_from_seedphrase(
                phrase.clone(),
                mnemonic_password_v.clone(),
                wallet_password_v.clone(),
                account_index,
                account_name.clone(),
                account_description.clone(),
                network,
            );
            let send_res = sender.send(result);
            if let Err(e) = send_res {
                println!(
                    "_import_from_seedphrase: There was error while trying to send the result: {e} "
                )
            }
        })
    }

    #[func]
    fn _import_from_resource(resource: Gd<Resource>, network: u8) -> Gd<WalletImportReceiver> {
        let loader = Self::import_from_dict(resource, network);
        Self::import_in_thread(move |sender| {
            let result: Result<SingleAddressWalletImportResult, SingleAddressWalletLoaderError> = {
                loader.clone().and_then(|wallet_loader| {
                    Self::check_fields(&wallet_loader).and_then(|wallet| {
                        Ok(SingleAddressWalletImportResult {
                            wallet_loader,
                            wallet,
                        })
                    })
                })
            };
            let send_res = sender.send(result);
            if let Err(e) = send_res {
                println!(
                    "_import_from_resource: There was error while trying to send the result: {e} "
                )
            }
        })
    }

    #[func]
    fn _create(
        wallet_password: PackedByteArray,
        account_index: u32,
        account_name: String,
        account_description: String,
        network: u8,
    ) -> Gd<GResult> {
        Self::to_gresult_class(Self::create(
            wallet_password.to_vec(),
            account_index,
            account_name,
            account_description,
            network,
        ))
    }

    #[func]
    pub fn _add_account(
        &mut self,
        account: u32,
        name: GString,
        description: GString,
        password: PackedByteArray,
    ) -> Gd<GResult> {
        Self::to_gresult_class(self.add_account(account, name, description, password))
    }

    #[func]
    pub fn _get_wallet(&self, account_index: u32) -> Gd<GResult> {
        Self::to_gresult_class(self.get_wallet(account_index))
    }
}

/// An account as tracked inside `SingleAddressWallet`.
#[derive(GodotClass)]
#[class(base=RefCounted, rename=_Account)]
pub struct Account {
    index: u32,
    name: String,
    description: String,
    public_key: Bip32PublicKey,
    address: CSLAddress,
    address_bech32: String,
    network: u8,
}

impl Clone for Account {
    fn clone(&self) -> Self {
        let public_key = duplicate_key(&self.public_key);
        Account {
            index: self.index,
            name: self.name.to_owned(),
            description: self.description.to_owned(),
            public_key,
            address: self.address.to_owned(),
            address_bech32: self.address_bech32.to_owned(),
            network: self.network,
        }
    }
}

// This class must be passed from the Rust thread back to Godot, so
// it can't hold any GDExt types. Therefore we must provide accessor
// functions for wrapping the properties in a Gd pointer.
#[derive(GodotClass)]
#[class(base=RefCounted, rename=_SingleAddressWalletImportResult)]
pub struct SingleAddressWalletImportResult {
    wallet_loader: SingleAddressWalletLoader,
    wallet: SingleAddressWallet,
}

#[godot_api]
impl SingleAddressWalletImportResult {
    #[func]
    fn wallet_loader(&self) -> Gd<SingleAddressWalletLoader> {
        Gd::from_object(self.wallet_loader.clone())
    }

    #[func]
    fn wallet(&self) -> Gd<SingleAddressWallet> {
        Gd::from_object(self.wallet.clone())
    }
}

#[derive(GodotClass)]
#[class(base=RefCounted, rename=_SingleAddressWalletCreateResult)]
pub struct SingleAddressWalletCreateResult {
    #[var]
    wallet_loader: Gd<SingleAddressWalletLoader>,
    #[var]
    wallet: Gd<SingleAddressWallet>,
    #[var]
    seed_phrase: GString,
}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct WalletImportReceiver {
    receiver:
        Option<Receiver<Result<SingleAddressWalletImportResult, SingleAddressWalletLoaderError>>>,
}

#[godot_api]
impl WalletImportReceiver {
    #[func]
    pub fn get_import_result(&mut self) -> Option<Gd<GResult>> {
        if let Some(rec) = &self.receiver {
            let res = rec.try_recv();
            match res {
                Ok(import_result) => {
                    self.receiver = None;
                    println!("(WalletImportReceiver) Received import from the Rust thread");
                    Some(SingleAddressWalletLoader::to_gresult_class(import_result))
                }
                Err(_) => None,
            }
        } else {
            println!(
                "(WalletImportReceiver) Tried to obtain result from a used WalletImportReceiver"
            );
            None
        }
    }
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
    F: FnMut(Bip32PrivateKey) -> Result<O, E>,
    E: From<Error> + From<JsError>,
{
    let decrypted_bytes = pbes2_params.decrypt(password, encrypted_master_private_key)?;
    let master_key = Bip32PrivateKey::from_bytes(decrypted_bytes.as_slice())?;
    f(master_key)
}

fn with_account_private_key<F, O, E>(
    pbes2_params: pbes2::Parameters,
    encrypted_master_private_key: &[u8],
    password: &[u8],
    account_index: u32,
    f: &mut F,
) -> Result<O, E>
where
    F: FnMut(Bip32PrivateKey) -> Result<O, E>,
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
    Bip32PublicKey::from_bytes(k.as_bytes().as_slice()).unwrap() // should be safe
}

// Takes the account key
fn address_from_key(network: u8, key: &Bip32PublicKey) -> CSLAddress {
    let spend = key.derive(0).unwrap().derive(0).unwrap(); // safe by construction
    let stake = key.derive(2).unwrap().derive(0).unwrap(); // idem
    let spend_cred = StakeCredential::from_keyhash(&spend.to_raw_key().hash());
    let stake_cred = StakeCredential::from_keyhash(&stake.to_raw_key().hash());

    BaseAddress::new(network, &spend_cred, &stake_cred).to_address()
}

// WARNING: This function assumes the wallet was created/imported
// properly and the PBES2 struct was constructed and validated before hand.
//
// Unfortunately the PBES2 params cannot be stored inside
// `SingleAddressWalletLoader` due to GDExt not supporting lifetime parameters
// in classes. Thus we must create the PBES2 params whenever they are needed.
fn unsafe_get_pbes2_params<'a>(
    aes_iv_vec: &'a Vec<u8>,
    scrypt_params: &'a scrypt::Params,
    salt_vec: &'a Vec<u8>,
) -> pbes2::Parameters<'a> {
    let aes_iv = <&[u8; 16]>::try_from(aes_iv_vec.as_slice())
        .map_err(|e| SingleAddressWalletLoaderError::CouldNotParseAesIv(e))
        .unwrap();
    pbes2::Parameters::scrypt_aes128cbc(*scrypt_params, salt_vec.as_slice(), aes_iv)
        .map_err(|e| SingleAddressWalletLoaderError::Pkcs5Error(e))
        .unwrap()
}

// The parameters used by MyEtherWallet--not considered secure without a
// sufficiently strong password.
fn mew_scrypt_params() -> scrypt::Params {
    scrypt::Params::new(13, 8, 1, 32).unwrap() // safe by construction
}

fn _fast_scrypt_params() -> scrypt::Params {
    scrypt::Params::new(12, 4, 1, 32).unwrap() // safe by construction
}
