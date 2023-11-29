use std::ops::Deref;

use cardano_serialization_lib::address::{Address, BaseAddress, NetworkInfo, StakeCredential};
use cardano_serialization_lib::crypto::{Bip32PrivateKey, TransactionHash, Vkeywitnesses};
use cardano_serialization_lib::utils::*;
use cardano_serialization_lib::output_builder::*;
use cardano_serialization_lib::tx_builder::*;
use cardano_serialization_lib::fees::LinearFee;
use cardano_serialization_lib::{
    Transaction,
    TransactionInput,
    TransactionOutput,
    TransactionWitnessSet,
};
use cardano_serialization_lib::utils as CSL;

use bip32::{Mnemonic, Language};

use godot::prelude::*;

struct MyExtension;

#[derive(GodotClass, Eq, Hash, Ord, PartialEq, PartialOrd)]
#[class(init, base=RefCounted)]
struct BigInt {
    #[init(default = CSL::BigInt::from_str("0").unwrap())]
    #[doc(hidden)]
    b: CSL::BigInt
}

#[godot_api] 
impl BigInt {
    #[func]
    fn from_str(text: String) -> Gd<BigInt> {
        let b = CSL::BigInt::from_str(&text).expect("Could not parse BigInt");
        return Gd::from_object(Self { b });
    }

    #[func]
    fn to_str(&self) -> String {
        return self.b.to_str();
    }

    #[func]
    fn to_string(&self) -> String {
        return self.to_str();
    }

    #[func]
    fn from_int(n: i64) -> Gd<BigInt> {
        let b = CSL::BigInt::from_str(&n.to_string()).unwrap();
        return Gd::from_object(Self { b });
    }

    #[func]
    fn add(&self, other: Gd<BigInt>) -> Gd<BigInt> {
        let b = self.b.add(&other.bind().deref().b);
        return Gd::from_object(Self { b });
    }

    #[func]
    fn mul(&self, other: Gd<BigInt>) -> Gd<BigInt> {
        let b = self.b.mul(&other.bind().deref().b);
        return Gd::from_object(Self { b });
    }

    #[func]
    fn zero() -> Gd<BigInt> {
        return Self::from_str("0".to_string());
    }

    #[func]
    fn one() -> Gd<BigInt> {
        return Self::from_str("1".to_string());
    }

    #[func]
    fn eq(&self, other: Gd<BigInt>) -> bool {
        return self.b == other.bind().b;
    }

    #[func]
    fn gt(&self, other: Gd<BigInt>) -> bool {
        return self > &other.bind();
    }

    #[func]
    fn lt(&self, other: Gd<BigInt>) -> bool {
        return self < &other.bind();
    }
}

#[derive(GodotClass, Debug)]
#[class(init, base=RefCounted)]
struct Utxo {
    #[var(get)] tx_hash: GString,
    #[var(get)] output_index: u32,
    #[var(get)] address: GString,
    #[var(get)] coin: Gd<BigInt>,
    #[var(get)] assets: Dictionary
}

#[godot_api]
impl Utxo {
    #[func]
    fn create(
        tx_hash: GString,
        output_index: u32,
        address: GString,
        coin: Gd<BigInt>,
        assets: Dictionary
    ) -> Gd<Utxo> {
        return Gd::from_object(
            Self {
                tx_hash,
                output_index,
                address,
                coin,
                assets
            }
        );
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
        return Gd::from_object(
            Self {
                coins_per_utxo_byte,
                pool_deposit,
                key_deposit,
                max_value_size,
                max_tx_size,
                linear_fee_constant,
                linear_fee_coefficient,
            }
        );
    }
}

#[derive(GodotClass)]
#[class(init, base=Node)]
struct Wallet {
    master_private_key: Option<Bip32PrivateKey>,
}

fn harden(index: u32) -> u32 {
    return index | 0x80000000;
}

#[godot_api]
impl Wallet {
    #[func]
    fn set_from_mnemonic(&mut self, mnemonic: String) {
        let result = Mnemonic::new(
            mnemonic
                .to_lowercase()
                .split_whitespace()
                .collect::<Vec<_>>()
                .join(" "),
            Language::English
        );
        match result {
            Err(msg) => {
                godot_print!("{}", msg);
                self.master_private_key = None;
            }
            Ok(mnemonic) => {
                self.master_private_key = Some(Bip32PrivateKey::from_bip39_entropy(mnemonic.entropy(), &[]));
            }
        }
    }

    fn get_address(&self) -> Address {
        let priv_key = self.master_private_key.as_ref().expect("No wallet selected!");
        let account_root = 
            priv_key
                .derive(harden(1852))
                .derive(harden(1815))
                .derive(harden(0));
        let spend = account_root.derive(0).derive(0).to_public();
        let stake = account_root.derive(2).derive(0).to_public();
        let spend_cred = StakeCredential::from_keyhash(&spend.to_raw_key().hash());
        let stake_cred = StakeCredential::from_keyhash(&stake.to_raw_key().hash());
        let address =
            BaseAddress::new(
                NetworkInfo::testnet_preview().network_id(),
                &spend_cred,
                &stake_cred
            ).to_address();
        return address;
    }

    #[func]
    fn get_address_bech32(&self) -> String {
        return self.get_address().to_bech32(None).unwrap();
    }
}

#[derive(GodotClass)]
#[class(init, base=Node, rename=_Provider)]
struct Provider {
}

#[godot_api]
impl Provider {
    #[signal] fn got_parameters(parameters: Gd<ProtocolParameters>);
    #[signal] fn got_wallet_utxos(utxos: Array<Gd<Utxo>>);
}

#[derive(GodotClass)]
#[class(init, base=RefCounted, rename=_Cardano)]
struct Cardano {
    // godot types
    #[var] provider: Option<Gd<Provider>>,
    #[var] wallet: Option<Gd<Wallet>>,

    // csl types
    tx_builder_config: Option<TransactionBuilderConfig>,
}

#[godot_api]
impl Cardano {
    #[func]
    fn set_protocol_parameters(&mut self, parameters: Gd<ProtocolParameters>) {
        let params = parameters.bind();
        godot_print!("Setting parameters");
        self.tx_builder_config =
            Some(
                TransactionBuilderConfigBuilder::new()
                    .coins_per_utxo_byte(&to_bignum(params.coins_per_utxo_byte))
                    .pool_deposit(&to_bignum(params.pool_deposit))
                    .key_deposit(&to_bignum(params.key_deposit))
                    .max_value_size(params.max_value_size)
                    .max_tx_size(params.max_tx_size)
                    .fee_algo(
                        &LinearFee::new(
                            &to_bignum(params.linear_fee_constant),
                            &to_bignum(params.linear_fee_coefficient)
                        )
                    )
                    .build().expect("Failed to build transaction builder config")
            );
    }

    #[func]
    fn send_lovelace(&mut self, addr_bech32: String, amount: Gd<BigInt>, gutxos: Array<Gd<Utxo>>) -> PackedByteArray {
        let bound_wallet = self.wallet.as_ref().unwrap().bind();
        let wallet: &Wallet = bound_wallet.deref();

        let tx_builder_config = self.tx_builder_config.as_ref().unwrap();

        let priv_key = wallet.master_private_key.as_ref().expect("No wallet selected!");
        let spend_key = 
            priv_key
                .derive(harden(1852))
                .derive(harden(1815))
                .derive(harden(0))
                .derive(0)
                .derive(0)
                .to_raw_key();
        let address = Address::from_bech32(&addr_bech32).expect("Could not decode address bech32");
        let mut utxos: TransactionUnspentOutputs = TransactionUnspentOutputs::new();
        gutxos.iter_shared().for_each(|gutxo| {
            let utxo = gutxo.bind();
            utxos.add(
                &TransactionUnspentOutput::new(
                    &TransactionInput::new(
                        &TransactionHash::from_hex(&utxo.tx_hash.to_string()).expect("Could not decode transaction hash"),
                        utxo.output_index
                    ),
                    &TransactionOutput::new(
                        &Address::from_bech32(&utxo.address.to_string()).expect("Could not decode address bech32"), 
                        &Value::new(&to_bignum(utxo.coin.bind().b.as_u64().expect("UTxO Lovelace exceeds maximum").into()))
                    )
                )
            );
        });
        let output_builder = TransactionOutputBuilder::new();
        let amount_builder = output_builder.with_address(&address).next().expect("Failed to build transaction output");
        let output = amount_builder.with_coin(&amount.bind().b.as_u64().expect("Output lovelace exceeds maximum")).build().expect("Failed to build amount output");
        let mut tx_builder = TransactionBuilder::new(&tx_builder_config);
        tx_builder.add_inputs_from(&utxos, CoinSelectionStrategyCIP2::RandomImprove).expect("Could not add inputs");
        tx_builder.add_output(&output).expect("Could not add output");
        tx_builder.add_change_if_needed(&wallet.get_address()).expect("Could not set change address");
        let tx_body = tx_builder.build().expect("Could not build transaction");

        let mut witnesses = TransactionWitnessSet::new();
        let mut vkey_witnesses = Vkeywitnesses::new();
        vkey_witnesses.add(&make_vkey_witness(&hash_transaction(&tx_body), &spend_key));

        witnesses.set_vkeys(&vkey_witnesses);

        let signed_tx = Transaction::new(&tx_body, &witnesses, None);

        let bytes_vec = signed_tx.to_bytes();
        let bytes: &[u8] = bytes_vec.as_slice().into();
        return PackedByteArray::from(bytes);
    }
}

#[gdextension]
unsafe impl ExtensionLibrary for MyExtension {}
