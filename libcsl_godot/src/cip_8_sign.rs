use cardano_message_signing as cms;
use cardano_serialization_lib::{Bip32PrivateKey, Bip32PublicKey};
use cms::{
    builders, cbor,
    error::JsError,
    utils::{self, ToBytes},
    COSEKey, COSESign1, HeaderMap, Headers, Label, ProtectedHeaderMap,
};

pub struct DataSignatureCOSE1 {
    pub cose_key: COSEKey,
    pub cose_sig1: COSESign1,
}

pub fn sign_data(
    spending_private_key: &Bip32PrivateKey,
    address: Vec<u8>,
    payload: Vec<u8>,
) -> Result<DataSignatureCOSE1, JsError> {
    let spending_pub_key: Bip32PublicKey = spending_private_key.to_public();
    let algorithm_id = builders::AlgorithmId::EdDSA;

    let cose_key = mk_cose_key(&spending_pub_key, algorithm_id)?;
    let cose_sig1 = mk_cose_1_sig(spending_private_key, address, payload, algorithm_id)?;
    Ok(DataSignatureCOSE1 {
        cose_key,
        cose_sig1,
    })
}

fn mk_cose_1_sig(
    spending_private_key: &Bip32PrivateKey,
    address: Vec<u8>,
    payload: Vec<u8>,
    algorithm_id: builders::AlgorithmId,
) -> Result<COSESign1, JsError> {
    let mut protected_headers = HeaderMap::new();
    // algorithm header
    let algorithm_id = Label::from_algorithm_id(algorithm_id);
    protected_headers.set_algorithm_id(&algorithm_id);

    // address header
    let addr_label = Label::new_text("address".to_owned());
    let addr_hex_cbor = cbor::CBORValue::new_bytes(address);
    protected_headers.set_header(&addr_label, &addr_hex_cbor)?;

    // cose_sign1
    let protected_serialized = ProtectedHeaderMap::new(&protected_headers);
    let unprotected = HeaderMap::new();
    let headers = Headers::new(&protected_serialized, &unprotected);
    let builder = builders::COSESign1Builder::new(&headers, payload, false);

    let to_sign = builder.make_data_to_sign().to_bytes();
    let signed_sig_struct = spending_private_key.to_raw_key().sign(&to_sign).to_bytes();
    Ok(builder.build(signed_sig_struct))
}

fn mk_cose_key(
    spending_pub_key: &Bip32PublicKey,
    algorithm_id: builders::AlgorithmId,
) -> Result<COSEKey, JsError> {
    let mut key = cms::COSEKey::new(&Label::from_key_type(cms::builders::KeyType::OKP));
    key.set_algorithm_id(&Label::from_algorithm_id(algorithm_id));

    // crv (-1) - must be set to Ed25519 (6)
    let crv = utils::BigNum::from_str("1").map(utils::Int::new_negative)?;
    key.set_header(
        &cms::Label::new_int(&crv),
        &cms::cbor::CBORValue::new_int(&cms::utils::Int::new_i32(6)),
    )?;

    // x (-2) - must be set to the public key bytes of the key used to sign the
    let x = utils::BigNum::from_str("2").map(utils::Int::new_negative)?;
    // according to Nami and Gero examples, we need key w/o chain code here
    let raw_key = spending_pub_key.to_raw_key();
    key.set_header(
        &cms::Label::new_int(&x),
        &cbor::CBORValue::new_bytes(raw_key.as_bytes()),
    )?;
    Ok(key)
}
