//! 调试用：`cargo run -p tinymusic-server -- --config-dir /tmp/tm`
//!
//! 打印 baseUrl 与 token 后常驻，方便在 Mac 上用 curl 验收命令面（不需要模拟器）。

use std::path::PathBuf;

fn arg(args: &[String], name: &str) -> Option<String> {
    args.iter().position(|a| a == name).and_then(|i| args.get(i + 1)).cloned()
}

#[tokio::main]
async fn main() {
    let args: Vec<String> = std::env::args().collect();
    let config_dir = PathBuf::from(arg(&args, "--config-dir").unwrap_or_else(|| "/tmp/tinymusic-dev".into()));
    let download_dir = PathBuf::from(arg(&args, "--download-dir").unwrap_or_else(|| "/tmp/tinymusic-dev/downloads".into()));
    let bind = arg(&args, "--bind").unwrap_or_else(|| "127.0.0.1:0".into());
    let token = tinymusic_server::random_token();

    match tinymusic_server::start(config_dir, download_dir, &bind, token.clone()).await {
        Ok((addr, _handle, _state)) => {
            println!("TM_BASE_URL=http://{addr}");
            println!("TM_TOKEN={token}");
            // 常驻
            loop {
                tokio::time::sleep(std::time::Duration::from_secs(3600)).await;
            }
        }
        Err(e) => {
            eprintln!("启动失败: {e}");
            std::process::exit(1);
        }
    }
}
