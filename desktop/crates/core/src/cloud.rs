use crate::error::Result;
use crate::model::AudioFormat;
use crate::proxy::StreamProxy;
use crate::quality::{audio_offset, mime_for_codec, AUDIO_HEADER_BYTES};
use crate::s3::S3;
use crate::webdav::WebDav;

#[derive(Clone)]
pub enum CloudLibrary {
    S3(S3),
    WebDav(WebDav, StreamProxy),
}

impl CloudLibrary {
    pub fn provider(&self) -> &'static str {
        match self {
            Self::S3(_) => "s3",
            Self::WebDav(..) => "webdav",
        }
    }

    pub fn normalized_prefix(&self) -> String {
        match self {
            Self::S3(client) => client.normalized_prefix(),
            Self::WebDav(client, _) => client.normalized_prefix(),
        }
    }

    pub fn playlist_prefix(&self, name: &str) -> String {
        match self {
            Self::S3(client) => crate::library::playlist_prefix(&client.normalized_prefix(), name),
            Self::WebDav(client, _) => client.playlist_prefix(name),
        }
    }

    pub fn bucket(&self) -> Option<&str> {
        match self {
            Self::S3(client) => Some(client.config().bucket.trim()),
            Self::WebDav(..) => None,
        }
    }

    pub async fn test(&self) -> Result<String> {
        match self {
            Self::S3(client) => client.test().await,
            Self::WebDav(client, _) => client.test().await,
        }
    }

    pub async fn list_keys(&self, prefix: &str) -> Result<Vec<String>> {
        match self {
            Self::S3(client) => client.list_keys(prefix).await,
            Self::WebDav(client, _) => client.list_keys(prefix).await,
        }
    }

    pub async fn list_keys_all(&self, prefix: &str) -> Result<Vec<String>> {
        match self {
            Self::S3(client) => client.list_keys_all(prefix).await,
            Self::WebDav(client, _) => client.list_keys(prefix).await,
        }
    }

    pub async fn list_playlist_keys(&self, prefix: &str) -> Result<Vec<String>> {
        match self {
            Self::S3(client) => client.list_keys_all(prefix).await,
            Self::WebDav(client, _) => client.list_playlist_keys(prefix).await,
        }
    }

    pub async fn get_object(&self, key: &str) -> Result<Option<Vec<u8>>> {
        match self {
            Self::S3(client) => client.get_object(key).await,
            Self::WebDav(client, _) => client.get_object(key).await,
        }
    }

    pub async fn download_object(
        &self,
        key: &str,
        path: &std::path::Path,
        replace: bool,
        on_progress: crate::download::ProgressFn,
    ) -> Result<std::path::PathBuf> {
        let response = match self {
            Self::S3(client) => client.get_object_response(key).await?,
            Self::WebDav(client, _) => client.get_object_response(key).await?,
        };
        let response = response.ok_or_else(|| crate::Error::NotFound(key.into()))?;
        crate::download::save_cloud_object(response, path, replace, on_progress).await
    }

    pub async fn put_object(&self, key: &str, body: Vec<u8>, mime: &str) -> Result<()> {
        match self {
            Self::S3(client) => client.put_object(key, body, mime).await,
            Self::WebDav(client, _) => client.put_object(key, body, mime).await,
        }
    }

    pub async fn delete_object(&self, key: &str) -> Result<()> {
        match self {
            Self::S3(client) => client.delete_object(key).await,
            Self::WebDav(client, _) => client.delete_object(key).await,
        }
    }

    pub async fn copy_object(&self, from: &str, to: &str) -> Result<bool> {
        match self {
            Self::S3(client) => client.copy_object(from, to).await,
            Self::WebDav(client, _) => client.copy_object(from, to).await,
        }
    }

    pub async fn move_object(&self, from: &str, to: &str) -> Result<()> {
        match self {
            Self::S3(client) => client.move_object(from, to).await,
            Self::WebDav(client, _) => client.move_object(from, to).await,
        }
    }

    pub async fn audio_url(
        &self,
        key: &str,
        proxy: &StreamProxy,
        http: &reqwest::Client,
    ) -> Result<(String, AudioFormat, Option<u64>)> {
        match self {
            Self::S3(client) => {
                let signed = client.presign_get(key, 6 * 3600)?;
                let (format, bytes) = probe_audio(http.get(&signed)).await?;
                let mime = mime_for_codec(format.codec);
                Ok((
                    proxy.register(signed, Some(mime.into())).await,
                    format,
                    bytes,
                ))
            }
            Self::WebDav(client, _) => {
                let (format, bytes) =
                    probe_audio(client.read_request(key, reqwest::Method::GET)?).await?;
                let mime = mime_for_codec(format.codec);
                let url = proxy
                    .register_webdav(client.clone(), key.into(), Some(mime.into()))
                    .await?;
                Ok((url, format, bytes))
            }
        }
    }

    pub async fn cover_url(&self, key: &str) -> Option<String> {
        match self {
            Self::S3(client) => client.presign_get(key, 6 * 3600).ok(),
            Self::WebDav(client, proxy) => {
                let (_, extension) = key.rsplit_once('.')?;
                let mime = match extension.to_ascii_lowercase().as_str() {
                    "jpg" | "jpeg" => "image/jpeg",
                    "png" => "image/png",
                    "webp" => "image/webp",
                    _ => return None,
                };
                proxy
                    .register_webdav(client.clone(), key.into(), Some(mime.into()))
                    .await
                    .ok()
            }
        }
    }
}

async fn probe_audio(request: reqwest::RequestBuilder) -> Result<(AudioFormat, Option<u64>)> {
    let first_request = request.try_clone().expect("audio probe GET has no body");
    let (mut head, bytes) = read_audio_prefix(first_request, 0).await?;
    if let Some(offset) =
        audio_offset(&head).filter(|offset| bytes.is_none_or(|bytes| *offset < bytes))
    {
        head = read_audio_prefix(request, offset).await?.0;
    }
    Ok((AudioFormat::from_audio_header(&head), bytes))
}

async fn read_audio_prefix(
    request: reqwest::RequestBuilder,
    offset: u64,
) -> Result<(Vec<u8>, Option<u64>)> {
    use reqwest::header::{CONTENT_RANGE, RANGE};

    let mut response = request
        .header(
            RANGE,
            format!("bytes={offset}-{}", offset + AUDIO_HEADER_BYTES as u64 - 1),
        )
        .send()
        .await?
        .error_for_status()?;
    let content_range = response
        .headers()
        .get(CONTENT_RANGE)
        .and_then(|value| value.to_str().ok());
    let bytes = if response.status() == reqwest::StatusCode::PARTIAL_CONTENT {
        content_range
            .and_then(|range| range.rsplit_once('/'))
            .and_then(|(_, total)| total.parse().ok())
    } else {
        response.content_length()
    };
    // A server may ignore Range. Avoid downloading the entire tag to reach the requested offset.
    if offset != 0
        && !content_range.is_some_and(|range| {
            range
                .strip_prefix("bytes ")
                .and_then(|range| range.split_once('-'))
                .and_then(|(start, _)| start.parse().ok())
                == Some(offset)
        })
    {
        return Ok((Vec::new(), bytes));
    }
    let mut head = Vec::new();
    while head.len() < AUDIO_HEADER_BYTES {
        let Some(chunk) = response.chunk().await? else {
            break;
        };
        head.extend_from_slice(&chunk[..chunk.len().min(AUDIO_HEADER_BYTES - head.len())]);
    }
    Ok((head, bytes))
}
