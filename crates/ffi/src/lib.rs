//! 给原生壳用的最小 C ABI。
//!
//! Swift/Kotlin 只需要：
//!   let json = tm_start(configJson)
//!   let cfg = parse(json)   // {"baseUrl":"http://127.0.0.1:PORT","token":"..."}
//!   ...
//!   tm_stop()
//!
//! 设计：起一个 tokio runtime 常驻，服务跑在里面；token 每次启动随机。

use std::ffi::{c_char, CStr, CString};
use std::path::PathBuf;
use std::sync::Mutex;

use serde::Deserialize;

struct Running {
    // 丢弃 Runtime 会停掉服务；保留它表示"后端在跑"
    _runtime: tokio::runtime::Runtime,
}

static RUNNING: Mutex<Option<Running>> = Mutex::new(None);

#[derive(Debug, Deserialize)]
struct StartConfig {
    config_dir: String,
    download_dir: String,
    #[serde(default)]
    bind: Option<String>,
}

fn into_c_string(s: String) -> *mut c_char {
    match CString::new(s) {
        Ok(c) => c.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// 启动后端，返回 {"baseUrl","token"} 或 {"error"}
///
/// SAFETY: json 必须是合法的以 NUL 结尾的 UTF-8 C 字符串；返回值需要 tm_free 释放。
#[no_mangle]
pub unsafe extern "C" fn tm_start(config_json: *const c_char) -> *mut c_char {
    if config_json.is_null() {
        return into_c_string(r#"{"error":"config_json 为空"}"#.into());
    }
    let raw = match CStr::from_ptr(config_json).to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return into_c_string(r#"{"error":"config_json 不是 UTF-8"}"#.into()),
    };
    let cfg: StartConfig = match serde_json::from_str(&raw) {
        Ok(c) => c,
        Err(e) => return into_c_string(format!(r#"{{"error":"解析配置失败: {e}"}}"#)),
    };

    let runtime = match tokio::runtime::Builder::new_multi_thread().enable_all().build() {
        Ok(r) => r,
        Err(e) => return into_c_string(format!(r#"{{"error":"创建 runtime 失败: {e}"}}"#)),
    };

    let token = tinymusic_server::random_token();
    let bind = cfg.bind.unwrap_or_else(|| "127.0.0.1:0".into());
    let started = runtime.block_on(tinymusic_server::start(
        PathBuf::from(&cfg.config_dir),
        PathBuf::from(&cfg.download_dir),
        &bind,
        token.clone(),
    ));
    let (addr, _handle, _state) = match started {
        Ok(v) => v,
        Err(e) => return into_c_string(format!(r#"{{"error":{}}}"#, serde_json::to_string(&e).unwrap_or_else(|_| "\"启动失败\"".into()))),
    };

    if let Ok(mut slot) = RUNNING.lock() {
        *slot = Some(Running { _runtime: runtime });
    }

    into_c_string(format!(
        r#"{{"baseUrl":"http://{addr}","token":"{token}"}}"#
    ))
}

/// 停掉后端（进程退出前调用即可）
#[no_mangle]
pub extern "C" fn tm_stop() {
    if let Ok(mut slot) = RUNNING.lock() {
        *slot = None;
    }
}

/// 释放 tm_start 返回的字符串
///
/// SAFETY: 只能传 tm_start 返回的指针，且只能释放一次。
#[no_mangle]
pub unsafe extern "C" fn tm_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}
