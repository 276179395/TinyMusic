use std::{collections::BTreeMap, fs::File, io::Read, path::Path};

use base64::{engine::general_purpose::STANDARD, Engine};

const MAX_PACK_BYTES: u64 = 8 * 1024 * 1024;

#[derive(serde::Serialize)]
pub struct ThemePackSource {
    config: serde_json::Value,
    css: String,
    images: BTreeMap<String, String>,
}

fn read_pack(path: &Path) -> Result<ThemePackSource, String> {
    if !path
        .extension()
        .is_some_and(|ext| ext.eq_ignore_ascii_case("zip"))
    {
        return Err("请选择 ZIP 格式的主题包".into());
    }
    let file = File::open(path).map_err(|e| e.to_string())?;
    if file.metadata().map_err(|e| e.to_string())?.len() > MAX_PACK_BYTES {
        return Err("主题包超过 8 MiB".into());
    }
    let mut archive = zip::ZipArchive::new(file).map_err(|e| e.to_string())?;
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

#[tauri::command]
pub async fn read_theme_pack(path: String) -> Result<ThemePackSource, String> {
    tokio::task::spawn_blocking(move || read_pack(Path::new(&path)))
        .await
        .map_err(|e| e.to_string())?
}
