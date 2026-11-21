use std::{
    collections::BTreeMap,
    fs::{self, File},
    io::{Cursor, Read, Write},
    path::{Path, PathBuf},
};

use base64::{engine::general_purpose::STANDARD, Engine};
use tauri::Manager;

const MAX_PACK_BYTES: u64 = 8 * 1024 * 1024;

#[derive(serde::Serialize)]
pub struct ThemePackSource {
    config: serde_json::Value,
    css: String,
    images: BTreeMap<String, String>,
}

fn is_zip(path: &Path) -> bool {
    path.extension()
        .is_some_and(|ext| ext.eq_ignore_ascii_case("zip"))
}

fn pack_bytes(path: &Path) -> Result<Vec<u8>, String> {
    if !is_zip(path) {
        return Err("请选择 ZIP 格式的主题包".into());
    }
    let file = File::open(path).map_err(|e| e.to_string())?;
    let mut bytes = Vec::new();
    file.take(MAX_PACK_BYTES + 1)
        .read_to_end(&mut bytes)
        .map_err(|e| e.to_string())?;
    if bytes.len() as u64 > MAX_PACK_BYTES {
        return Err("主题包超过 8 MiB".into());
    }
    Ok(bytes)
}

fn read_pack(bytes: &[u8]) -> Result<ThemePackSource, String> {
    let mut archive = zip::ZipArchive::new(Cursor::new(bytes)).map_err(|e| e.to_string())?;
    if archive.len() > 64 {
        return Err("主题包条目超过 64 个".into());
    }
    let mut config = None;
    let mut css = None;
    let mut images = BTreeMap::new();
    let mut remaining = MAX_PACK_BYTES;
    for index in 0..archive.len() {
        let entry = archive.by_index(index).map_err(|e| e.to_string())?;
        if entry.is_dir() {
            continue;
        }
        let size = entry.size();
        remaining = remaining
            .checked_sub(size)
            .ok_or("主题包解压大小超过 8 MiB")?;
        let name = entry.name().map_err(|e| e.to_string())?.into_owned();
        let text = matches!(name.as_str(), "config.json" | "index.css");
        let mime = match name
            .rsplit_once('.')
            .map(|(_, ext)| ext.to_ascii_lowercase())
            .as_deref()
        {
            Some("png") => Some("image/png"),
            Some("jpg" | "jpeg") => Some("image/jpeg"),
            Some("webp") => Some("image/webp"),
            _ => None,
        };
        if !text && mime.is_none() {
            continue;
        }
        if !name.split('/').all(|part| {
            !part.is_empty()
                && !matches!(part, "." | "..")
                && part
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || b"._-".contains(&byte))
        }) {
            return Err("主题包文件名包含不支持的字符或路径".into());
        }
        if (name == "config.json" && config.is_some())
            || (name == "index.css" && css.is_some())
            || images.contains_key(&name)
        {
            return Err("主题包包含重名文件".into());
        }
        if text && size > 64 * 1024 {
            return Err("主题配置或 CSS 超过 64 KiB".into());
        }
        let mut bytes = Vec::new();
        entry
            .take(size + 1)
            .read_to_end(&mut bytes)
            .map_err(|e| e.to_string())?;
        if bytes.len() as u64 != size {
            return Err("主题包条目大小不匹配".into());
        }
        match name.as_str() {
            "config.json" => {
                config = Some(serde_json::from_slice(&bytes).map_err(|e| e.to_string())?)
            }
            "index.css" => css = Some(String::from_utf8(bytes).map_err(|e| e.to_string())?),
            _ => {
                if let Some(mime) = mime {
                    images.insert(
                        name,
                        format!("data:{mime};base64,{}", STANDARD.encode(bytes)),
                    );
                }
            }
        }
    }
    Ok(ThemePackSource {
        config: config.ok_or("主题包根目录缺少 config.json")?,
        css: css.ok_or("主题包根目录缺少 index.css")?,
        images,
    })
}

pub fn directory(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let base = app.path().app_config_dir().map_err(|e| e.to_string())?;
    let dir = if tauri::is_dev() {
        base.join("dev").join("theme")
    } else {
        base.join("theme")
    };
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir)
}

#[tauri::command]
pub async fn read_theme_pack(path: String) -> Result<ThemePackSource, String> {
    tokio::task::spawn_blocking(move || read_pack(&pack_bytes(Path::new(&path))?))
        .await
        .map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn list_theme_packs(app: tauri::AppHandle) -> Result<Vec<ThemePackSource>, String> {
    tokio::task::spawn_blocking(move || {
        let mut paths = fs::read_dir(directory(&app)?)
            .map_err(|e| e.to_string())?
            .filter_map(Result::ok)
            .map(|entry| entry.path())
            .filter(|path| path.is_file() && is_zip(path))
            .collect::<Vec<_>>();
        paths.sort();
        Ok(paths
            .iter()
            .filter_map(|path| read_pack(&pack_bytes(path).ok()?).ok())
            .collect())
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn save_theme_pack(
    app: tauri::AppHandle,
    path: String,
    id: String,
) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        let bytes = pack_bytes(Path::new(&path))?;
        let source = read_pack(&bytes)?;
        if !(1..=64).contains(&id.len())
            || !id.as_bytes()[0].is_ascii_alphanumeric()
            || !id
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_'))
            || source.config.get("id").and_then(serde_json::Value::as_str) != Some(id.as_str())
        {
            return Err("主题包 ID 无效或文件已更改".into());
        }
        let dir = directory(&app)?;
        let mut temp = tempfile::NamedTempFile::new_in(&dir).map_err(|e| e.to_string())?;
        temp.write_all(&bytes).map_err(|e| e.to_string())?;
        temp.as_file().sync_all().map_err(|e| e.to_string())?;
        temp.persist(dir.join(format!("pack-{}.zip", id.to_ascii_lowercase())))
            .map_err(|e| e.to_string())?;
        Ok(())
    })
    .await
    .map_err(|e| e.to_string())?
}
