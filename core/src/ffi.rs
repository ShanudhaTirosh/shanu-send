use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_uchar};
use std::sync::Arc;
use crate::shanuconnect::ShanuConnectEngine;

pub struct EngineHandle {
    pub inner: Arc<ShanuConnectEngine>,
    pub runtime: tokio::runtime::Runtime,
}

#[no_mangle]
pub unsafe extern "C" fn shanusend_init_engine(device_name: *const c_char) -> *mut EngineHandle {
    if device_name.is_null() {
        return std::ptr::null_mut();
    }
    let name_str = match CStr::from_ptr(device_name).to_str() {
        Ok(s) => s,
        Err(_) => "ShanuSend Device",
    };

    let rt = match tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build() {
            Ok(r) => r,
            Err(_) => return std::ptr::null_mut(),
        };

    let engine = Arc::new(ShanuConnectEngine::new(name_str));
    let handle = Box::new(EngineHandle {
        inner: engine,
        runtime: rt,
    });

    Box::into_raw(handle)
}

#[no_mangle]
pub unsafe extern "C" fn shanusend_start_listeners(handle: *mut EngineHandle) -> bool {
    if handle.is_null() {
        return false;
    }
    let engine_handle = &*handle;
    let engine = Arc::clone(&engine_handle.inner);
    engine_handle.runtime.spawn(async move {
        engine.start_listeners().await;
    });
    true
}

#[no_mangle]
pub unsafe extern "C" fn shanusend_approve_pairing(
    handle: *mut EngineHandle,
    device_id: *const c_char,
    pin: *const c_char,
) -> c_uchar {
    if handle.is_null() || device_id.is_null() || pin.is_null() {
        return 0;
    }
    let dev_str = match CStr::from_ptr(device_id).to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };
    let pin_str = match CStr::from_ptr(pin).to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    let engine_handle = &*handle;
    let engine = Arc::clone(&engine_handle.inner);
    
    let result = engine_handle.runtime.block_on(async move {
        engine.approve_pairing(dev_str, pin_str).await
    });

    if result { 1 } else { 0 }
}

#[no_mangle]
pub unsafe extern "C" fn shanusend_free_engine(handle: *mut EngineHandle) {
    if !handle.is_null() {
        let _ = Box::from_raw(handle);
    }
}

#[no_mangle]
pub unsafe extern "C" fn shanusend_free_string(s: *mut c_char) {
    if !s.is_null() {
        let _ = CString::from_raw(s);
    }
}
