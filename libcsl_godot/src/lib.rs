use cardano_serialization_lib::address::{Address, BaseAddress, NetworkInfo, StakeCredential};
use cardano_serialization_lib::crypto::{Bip32PrivateKey, Vkeywitnesses};
use cardano_serialization_lib::utils::*;
use cardano_serialization_lib::output_builder::*;
use cardano_serialization_lib::tx_builder::*;
use cardano_serialization_lib::tx_builder::tx_inputs_builder::*;
use cardano_serialization_lib::fees::LinearFee;
use cardano_serialization_lib::{Transaction, TransactionWitnessSet};

use godot::prelude::*;

struct MyExtension;

#[derive(GodotClass)]
#[class(base=Node)]
struct Wallet {
    master_private_key: Option<Bip32PrivateKey>,

    #[base]
    node: Base<Node>,
}

#[godot_api]
impl INode for Wallet {
    fn init(node: Base<Node>) -> Self {
        Self {
            node,
            master_private_key: None
        }
    }
}

struct KeyEntropy {
    leftover: u8,
    entropy: Vec<u8>
}

impl KeyEntropy {
    fn push(&mut self, bits: u16) -> &mut Self {
        let lower: u8 = (bits << 5) as u8;
        let upper: u8 = (bits >> 3) as u8;
        match self.entropy.pop() {
            None => {
                self.entropy.push(upper);
                self.entropy.push(lower);
                self.leftover = 3;
            }
            Some(prev) => {
                self.entropy.push((upper >> self.leftover) | prev);
                if self.leftover > 0 {
                    self.entropy.push((upper << (8 - self.leftover)) | (lower >> self.leftover));
                    if self.leftover > 4 {
                        self.entropy.push(lower << (8 - self.leftover));
                    }
                } else {
                    self.entropy.push(lower);
                }
                self.leftover = (self.leftover + 11) % 8;
            }
        }
        self
    }
}

fn harden(index: u32) -> u32 {
    return index | 0x80000000;
}

#[godot_api]
impl Wallet {
    #[func]
    fn set_from_mnemonic(&mut self, mnemonic: String) {
        let words = String::from_utf8_lossy(include_bytes!("bip39/english.txt"));
        let word_list: Vec<&str> = words.lines().collect();
        let mnemonic_lowercase = mnemonic.to_lowercase();
        let mut mnemonic_list = mnemonic_lowercase.split_whitespace();
        let mut ke = KeyEntropy { leftover: 0, entropy: Vec::new() };
        let result = mnemonic_list.try_fold(
            &mut ke,
            |key_entropy, word| {
                match word_list.iter().position(|&x| x == word) {
                    None => Err(format!("Invalid word in mneomnic phrase {}", word)),
                    Some(ix) => Ok(key_entropy.push(ix.try_into().unwrap()))
                }
            }
        );
        match result {
            Err(msg) => godot_print!("{}", msg),
            Ok(_) => {
                // discard checksum, TODO: verify
                self.master_private_key = Some(Bip32PrivateKey::from_bip39_entropy(&(ke.entropy[0..32]), &[]));
            }
        }
    }

    fn get_address(&mut self) -> Address {
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
    fn get_address_bech32(&mut self) -> String {
        return self.get_address().to_bech32(None).unwrap();
    }

    #[func]
    fn send_lovelace(&mut self, addr_bech32: String, amount: u64, utxos: String) -> PackedByteArray {
        let priv_key = self.master_private_key.as_ref().expect("No wallet selected!");
        let spend_key = 
            priv_key
                .derive(harden(1852))
                .derive(harden(1815))
                .derive(harden(0))
                .derive(0)
                .derive(0)
                .to_raw_key();
        let address = Address::from_bech32(&addr_bech32).expect("Could not parse address bech32");
        let utxos: TransactionUnspentOutputs = TransactionUnspentOutputs::from_json(&utxos).expect("Could not parse UTxO JSON");
        let output_builder = TransactionOutputBuilder::new();
        let amount_builder = output_builder.with_address(&address).next().expect("Failed to build transaction output");
        let output = amount_builder.with_coin(&amount.try_into().unwrap()).build().expect("Failed to build amount output");
        let tx_builder_config = 
            TransactionBuilderConfigBuilder::new()
                .coins_per_utxo_byte(&to_bignum(4310))
                .pool_deposit(&to_bignum(500000000))
                .key_deposit(&to_bignum(2000000))
                .max_value_size(5000)
                .max_tx_size(16384)
                .fee_algo(&LinearFee::new(&to_bignum(155381), &to_bignum(44)))
                .build().expect("Failed to build transaction builder config");
        let mut tx_builder = TransactionBuilder::new(&tx_builder_config);
        tx_builder.add_inputs_from(&utxos, CoinSelectionStrategyCIP2::RandomImprove).expect("Could not add inputs");
        tx_builder.add_output(&output).expect("Could not add output");
        tx_builder.add_change_if_needed(&self.get_address()).expect("Could not set change address");
        let tx_body = tx_builder.build().expect("Could not build transaction");

        let mut witnesses = TransactionWitnessSet::new();
        let mut vkey_witnesses = Vkeywitnesses::new();
        let vkey_witness =
            vkey_witnesses.add(&make_vkey_witness(&hash_transaction(&tx_body), &spend_key));

        witnesses.set_vkeys(&vkey_witnesses);

        let signed_tx = Transaction::new(&tx_body, &witnesses, None);


        let bytes_vec = signed_tx.to_bytes();
        let bytes: &[u8] = bytes_vec.as_slice().try_into().unwrap();
        return PackedByteArray::from(bytes);
    }
}

#[gdextension]
unsafe impl ExtensionLibrary for MyExtension {}
