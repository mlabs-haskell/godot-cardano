//! A class for storing useful functions that should not / cannot belong to
//! other classes.
//!
//! For example, some classes have partial constructors that cannot be
//! implemented as static methods due godot-rust not supporting them.

use cardano_serialization_lib::{
    fees::LinearFee, tx_builder::TransactionBuilderConfigBuilder, utils::to_bignum,
};
use godot::prelude::*;

use crate::{ProtocolParameters, TxBuilder, TxBuilderError};

#[derive(GodotClass)]
#[class(init, base=Object)]
struct Utils {}

// #[godot_api]
// impl Utils {
//     #[func]
//     fn create_protocol_parameters(
//         params: &ProtocolParameters,
//     ) -> Result<TxBuilder, TxBuilderError> {
//         let tx_builder_config = TransactionBuilderConfigBuilder::new()
//             .coins_per_utxo_byte(&to_bignum(params.coins_per_utxo_byte))
//             .pool_deposit(&to_bignum(params.pool_deposit))
//             .key_deposit(&to_bignum(params.key_deposit))
//             .max_value_size(params.max_value_size)
//             .max_tx_size(params.max_tx_size)
//             .fee_algo(&LinearFee::new(
//                 &to_bignum(params.linear_fee_coefficient),
//                 &to_bignum(params.linear_fee_constant),
//             ))
//             .build()
//             .map_err(|e| TxBuilderError::BadProtocolParameters(e))?;

//         Ok(TxBuilder { tx_builder_config })
//     }
// }
