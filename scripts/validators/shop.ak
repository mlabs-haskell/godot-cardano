use aiken/bytearray
use aiken/list
use aiken/math
use aiken/hash.{Hash, Blake2b_224}
use aiken/string
use aiken/transaction.{ScriptContext, Spend, InlineDatum}
use aiken/transaction/credential.{VerificationKey}
use aiken/transaction/value.{PolicyId, AssetName}

type Cip68Ref {
  metadata: Data,
  version: Int,
  extra: Int
}

validator(_tag: Int) {
  fn spend(owner: Hash<Blake2b_224, VerificationKey>, _r: Data, ctx: ScriptContext) {
    let ScriptContext(tx_info, purpose) = ctx
    expect Spend(out_ref) = purpose
    expect Some(self_in) = list.find(
      tx_info.inputs,
      fn(input) { input.output_reference == out_ref }
    )
    let valid_sale = fn() {
      expect [self_out] = list.filter(
        tx_info.outputs,
        fn(output) { output.address.payment_credential == self_in.output.address.payment_credential }
      )
      expect new_datum: Hash<Blake2b_224, VerificationKey> = {
        expect InlineDatum(data) = self_out.datum
        data
      }

      let diff = value.merge(value.negate(self_in.output.value), self_out.value)
      let paid = value.lovelace_of(diff)

      let find_cip68_ref =
        fn(minting_policy: PolicyId, asset_name: AssetName) {
          trace string.join([@"Looking for reference input for", bytearray.to_hex(asset_name)], @" ")
          list.find(
            tx_info.reference_inputs,
            fn (input) {
              trace string.join([
                @"Trying",
                bytearray.to_hex(input.output_reference.transaction_id.hash),
                @"#",
                string.from_int(input.output_reference.output_index)
              ], @"")
              let ref_asset_name = bytearray.concat(#"000643b0", bytearray.drop(asset_name, 4))
              value.quantity_of(input.output.value, minting_policy, ref_asset_name) >= 1
            }
          )
        }
      
      let token_value_diff =
        value.reduce(
          value.without_lovelace(diff),
          0,
          fn (policy_id, asset_name, quantity, acc) {
            expect Some(ref_input) = find_cip68_ref(policy_id, asset_name)
            expect InlineDatum(datum) = ref_input.output.datum
            expect Cip68Ref{extra: price, ..}: Cip68Ref = datum
            trace string.join([
              if quantity < 0 { @"Selling" } else { @"Buying" },
              string.from_int(math.abs(quantity)),
              @"tokens for",
              string.from_int(price),
              @"each"
            ], @" ")
            acc + price * quantity
          }
        )

      paid == -token_value_diff && new_datum == owner
    }

    let owner_signed = list.has(tx_info.extra_signatories, owner)
    trace string.join([@"Owner has ", if owner_signed { @"" } else { @"not " }, @"signed"], @"")

    owner_signed || valid_sale()
  }
}

validator(_tag: Int) {
  fn tagged_mint(_r: Data, _ctx: ScriptContext) {
    True
  }
}

validator(_tag: Int) {
  fn tagged_spend(_d: Data, _r: Data, _ctx: ScriptContext) {
    True
  }
}
