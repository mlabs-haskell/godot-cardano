use std::ffi::CString;
use std::ptr;

use cardano_serialization_lib::address::Address;

#[no_mangle]
pub extern "C" fn new_address_from_bech32(addr_bech32: *mut i8) -> *const Address {
    let c_string = unsafe { CString::from_raw(addr_bech32) };
    match c_string.clone().into_string() {
        Err(_) => return ptr::null(),
        Ok(addr_bech33) => {
            let addr = Address::from_bech32(&addr_bech33).expect("Could not parse address bech32");
            let _ = c_string.into_raw();
            return Box::into_raw(Box::new(addr));
        }
    }
}

#[no_mangle]
pub extern "C" fn free_address(address: *mut Address) {
    unsafe { let _ = Box::from_raw(address); }
}

#[no_mangle]
pub extern "C" fn address_to_hex(address: *const Address) -> *const i8 {
    let c_string;
    if address.is_null() {
        c_string = CString::new("")
    } else {
        c_string = CString::new(unsafe { address.as_ref().expect("Unexpected address error").to_hex() });
    }

    return c_string.expect("Failed to create CString").into_raw();
}

#[no_mangle]
pub extern "C" fn free_string(s: *mut i8) {
   unsafe { let _ = CString::from_raw(s); };
}
