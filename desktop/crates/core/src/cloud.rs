use crate::error::Result;
use crate::proxy::StreamProxy;
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

    pub async fn audio_url(&self, key: &str, proxy: &StreamProxy, mime: &str) -> Result<String> {
        match self {
            Self::S3(client) => {
                let signed = client.presign_get(key, 6 * 3600)?;
                Ok(proxy.register(signed, Some(mime.into())).await)
            }
            Self::WebDav(client, _) => {
                proxy
                    .register_webdav(client.clone(), key.into(), Some(mime.into()))
                    .await
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
