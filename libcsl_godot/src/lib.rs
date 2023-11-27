use cardano_multiplatform_lib::address::{Address, BaseAddress, NetworkInfo, StakeCredential};
use cardano_multiplatform_lib::builders::input_builder::SingleInputBuilder;
use cardano_multiplatform_lib::builders::output_builder::*;
use cardano_multiplatform_lib::builders::tx_builder::*;
use cardano_multiplatform_lib::crypto::Bip32PrivateKey;
use cardano_multiplatform_lib::error::JsError;
use cardano_multiplatform_lib::ledger::alonzo::fees::LinearFee;
use cardano_multiplatform_lib::ledger::common::hash::hash_transaction;
use cardano_multiplatform_lib::ledger::common::value::to_bignum;
use cardano_multiplatform_lib::ledger::shelley::witness::make_vkey_witness;
use cardano_multiplatform_lib::plutus::ExUnitPrices;
use cardano_multiplatform_lib::{TransactionInput, TransactionOutput, UnitInterval};
use serde::{Deserialize, Serialize};
use serde_json;

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
            master_private_key: None,
        }
    }
}

struct KeyEntropy {
    leftover: u8,
    entropy: Vec<u8>,
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
                    self.entropy
                        .push((upper << (8 - self.leftover)) | (lower >> self.leftover));
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

// Due to CML not providing JSON serialisation for `TransactionUnspentOutput`,
// we have to provide it ourselves.
#[derive(Clone, Debug, Serialize, Deserialize)]
struct TransactionUnspentOutput_ {
    pub input: TransactionInput,
    pub output: TransactionOutput,
}

#[derive(Clone, Debug)]
struct TransactionUnspentOutputs_(Vec<TransactionUnspentOutput_>);

impl TransactionUnspentOutputs_ {
    // pub fn to_json(&self) -> Result<String, JsError> {
    //     serde_json::to_string_pretty(&self)
    //         .map_err(|e| JsError::from_str(&format!("to_json: {}", e)))
    // }

    pub fn from_json(json: &str) -> Result<Self, JsError> {
        println!("JSON: {}", json);
        serde_json::from_str(json)
            .map(|outputs| TransactionUnspentOutputs_(outputs))
            .map_err(|e| JsError::from_str(&format!("from_json: {}", e)))
    }
}

#[godot_api]
impl Wallet {
    #[func]
    fn set_from_mnemonic(&mut self, mnemonic: String) {
        let words = String::from_utf8_lossy(include_bytes!("bip39/english.txt"));
        let word_list: Vec<&str> = words.lines().collect();
        let mnemonic_lowercase = mnemonic.to_lowercase();
        let mut mnemonic_list = mnemonic_lowercase.split_whitespace();
        let mut ke = KeyEntropy {
            leftover: 0,
            entropy: Vec::new(),
        };
        let result = mnemonic_list.try_fold(&mut ke, |key_entropy, word| {
            match word_list.iter().position(|&x| x == word) {
                None => Err(format!("Invalid word in mneomnic phrase {}", word)),
                Some(ix) => Ok(key_entropy.push(ix.try_into().unwrap())),
            }
        });
        match result {
            Err(msg) => godot_print!("{}", msg),
            Ok(_) => {
                ke.entropy.pop(); // discard checksum, TODO: verify
                self.master_private_key =
                    Some(Bip32PrivateKey::from_bip39_entropy(&ke.entropy, &[]));
            }
        }
    }

    fn get_address(&mut self) -> Address {
        let priv_key = self
            .master_private_key
            .as_ref()
            .expect("No wallet selected!");
        let account_root = priv_key
            .derive(harden(1852))
            .derive(harden(1815))
            .derive(harden(0));
        let spend = account_root.derive(0).derive(0).to_public();
        let stake = account_root.derive(2).derive(0).to_public();
        let spend_cred = StakeCredential::from_keyhash(&spend.to_raw_key().hash());
        let stake_cred = StakeCredential::from_keyhash(&stake.to_raw_key().hash());
        let address = BaseAddress::new(
            // TODO: Check why `NetworkInfo` has only main net and testnet. Is it oudated?
            NetworkInfo::testnet().network_id(),
            &spend_cred,
            &stake_cred,
        )
        .to_address();
        return address;
    }

    #[func]
    fn get_address_bech32(&mut self) -> String {
        return self.get_address().to_bech32(None).unwrap();
    }

    #[func]
    fn send_lovelace(
        &mut self,
        addr_bech32: String,
        amount: u64,
        utxos: String,
    ) -> PackedByteArray {
        // Get keys, address and inputs
        let priv_key = self
            .master_private_key
            .as_ref()
            .expect("No wallet selected!");
        let spend_key = priv_key
            .derive(harden(1852))
            .derive(harden(1815))
            .derive(harden(0))
            .derive(0)
            .derive(0)
            .to_raw_key();
        let address = Address::from_bech32(&addr_bech32).expect("Could not parse address bech32");
        let inputs: TransactionUnspentOutputs_ =
            TransactionUnspentOutputs_::from_json(&utxos).expect("Could not parse UTxO JSON");
        // Outputs
        let output_builder = TransactionOutputBuilder::new();
        let amount_builder = output_builder
            .with_address(&address)
            .next()
            .expect("Failed to build transaction output");
        let output = amount_builder
            .with_coin(&amount.try_into().unwrap())
            .build()
            .expect("Failed to build amount output");
        // Build transaction
        // TODO: We should dynamically get these protocol parameters using Blockfrost
        let tx_builder_config = TransactionBuilderConfigBuilder::new()
            .coins_per_utxo_byte(&to_bignum(4310))
            .pool_deposit(&to_bignum(500000000))
            .key_deposit(&to_bignum(2000000))
            .max_value_size(5000)
            .max_tx_size(16384)
            .fee_algo(&LinearFee::new(&to_bignum(155381), &to_bignum(44)))
            .ex_unit_prices(&ExUnitPrices::new(
                &UnitInterval::new(&to_bignum(577), &to_bignum(10000)),
                &UnitInterval::new(&to_bignum(721), &to_bignum(10000000)),
            ))
            .collateral_percentage(150u32)
            .max_collateral_inputs(3)
            .build()
            .expect("Failed to build transaction builder config");
        let mut tx_builder = TransactionBuilder::new(&tx_builder_config);
        tx_builder
            .add_output(&output)
            .expect("Could not add output");
        add_utxos(&mut tx_builder, &inputs);
        tx_builder
            .select_utxos(CoinSelectionStrategyCIP2::LargestFirst)
            .expect("Could not select utxos");
        let mut signed_tx_builder = tx_builder
            .build(ChangeSelectionAlgo::Default, &self.get_address())
            .expect("Could not build transaction");
        // Add witnesses to transaction
        signed_tx_builder.add_vkey(&make_vkey_witness(
            &hash_transaction(&signed_tx_builder.body()),
            &spend_key,
        ));
        // Serialise
        let final_tx = signed_tx_builder
            .build_checked()
            .expect("Error while building final TX");
        let bytes_vec = final_tx.to_bytes();
        let bytes: &[u8] = bytes_vec.as_slice().try_into().unwrap();
        return PackedByteArray::from(bytes);
    }
}

// Helper for adding all inputs in `TransactionUnspentOutputs` to TX builder.
fn add_utxos(tx_builder: &mut TransactionBuilder, utxos: &TransactionUnspentOutputs_) -> () {
    let TransactionUnspentOutputs_(us) = utxos;
    us.iter().for_each(|utxo| {
        tx_builder.add_utxo({
            &SingleInputBuilder::new(&utxo.input, &utxo.output)
                .payment_key()
                .expect("add_utxos: Could not get payment key from input")
        })
    })
}

#[gdextension]
unsafe impl ExtensionLibrary for MyExtension {}
