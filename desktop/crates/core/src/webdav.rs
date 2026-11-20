use std::collections::BTreeSet;

use percent_encoding::percent_decode_str;
use reqwest::{Client, Method, RequestBuilder, Response, StatusCode, Url};
use serde::Deserialize;

use crate::error::{Error, Result};

const PROPERTIES: &str =
    r#"<D:propfind xmlns:D="DAV:"><D:prop><D:resourcetype/></D:prop></D:propfind>"#;

#[derive(Clone)]
pub struct WebDav {
    http: Client,
    endpoint: Url,
    root: String,
    username: String,
    password: String,
}

#[derive(Deserialize)]
struct MultiStatus {
    #[serde(default, rename = "response")]
    entries: Vec<DavEntry>,
}

#[derive(Deserialize)]
struct DavEntry {
    href: String,
    #[serde(default)]
    propstat: Vec<PropertyStatus>,
}

#[derive(Deserialize)]
struct PropertyStatus {
    status: String,
    prop: Properties,
}

#[derive(Deserialize)]
struct Properties {
    resourcetype: Option<ResourceType>,
}

#[derive(Deserialize)]
struct ResourceType {
    collection: Option<Collection>,
}

#[derive(Deserialize)]
struct Collection {}

impl WebDav {
    pub fn new(endpoint: &str, root: &str, username: String, password: String) -> Result<Self> {
        let mut endpoint =
            Url::parse(endpoint.trim()).map_err(|_| Error::Parse("WebDAV 服务地址无效".into()))?;
        if !matches!(endpoint.scheme(), "https" | "http")
            || endpoint.host_str().is_none()
            || !endpoint.username().is_empty()
            || endpoint.password().is_some()
            || endpoint.query().is_some()
            || endpoint.fragment().is_some()
        {
            return Err(Error::Parse(
                "请填写 WebDAV 的 HTTP(S) 服务地址，凭据请单独填写".into(),
            ));
        }
        endpoint
            .path_segments_mut()
            .map_err(|_| Error::Parse("WebDAV 服务地址无效".into()))?
            .pop_if_empty()
            .push("");
        let root = root.trim().trim_matches('/').to_owned();
        validate_path(&root)?;
        let http = Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .connect_timeout(std::time::Duration::from_secs(10))
            .read_timeout(std::time::Duration::from_secs(30))
            .build()?;
        Ok(Self {
            http,
            endpoint,
            root,
            username,
            password,
        })
    }

    pub fn normalized_prefix(&self) -> String {
        self.root.clone()
    }

    pub(crate) fn playlist_prefix(&self, name: &str) -> String {
        if self.root.is_empty() {
            format!("{name}/")
        } else {
            format!("{}/{name}/", self.root)
        }
    }

    fn url_for(&self, key: &str, directory: bool) -> Result<Url> {
        let key = key.trim_end_matches('/');
        validate_path(key)?;
        let mut url = self.endpoint.clone();
        if !key.is_empty() {
            let mut segments = url
                .path_segments_mut()
                .map_err(|_| Error::Parse("WebDAV 服务地址无效".into()))?;
            segments.pop_if_empty().extend(key.split('/'));
            if directory {
                segments.push("");
            }
        }
        Ok(url)
    }

    fn scoped_url(&self, key: &str, directory: bool) -> Result<Url> {
        let key = key.trim_end_matches('/');
        if !self.root.is_empty()
            && key != self.root
            && !key
                .strip_prefix(&self.root)
                .is_some_and(|rest| rest.starts_with('/'))
        {
            return Err(Error::Parse("WebDAV 路径超出音乐根目录".into()));
        }
        self.url_for(key, directory)
    }

    fn request(&self, method: Method, url: Url) -> RequestBuilder {
        let request = self.http.request(method, url);
        if self.username.is_empty() && self.password.is_empty() {
            return request;
        }
        request.basic_auth(&self.username, Some(&self.password))
    }

    pub fn read_request(&self, key: &str, method: Method) -> Result<RequestBuilder> {
        Ok(self.request(method, self.object_url(key)?))
    }

    pub(crate) fn object_url(&self, key: &str) -> Result<Url> {
        if key.is_empty() || key == self.root || key.ends_with('/') {
            return Err(Error::Parse("WebDAV 文件路径无效".into()));
        }
        self.scoped_url(key, false)
    }

    pub async fn get_object(&self, key: &str) -> Result<Option<Vec<u8>>> {
        match self.get_object_response(key).await? {
            Some(response) => Ok(Some(response.bytes().await?.to_vec())),
            None => Ok(None),
        }
    }

    pub(crate) async fn get_object_response(&self, key: &str) -> Result<Option<Response>> {
        let response = self.read_request(key, Method::GET)?.send().await?;
        if response.status() == StatusCode::NOT_FOUND {
            return Ok(None);
        }
        Ok(Some(checked(response)?))
    }

    pub async fn list_keys(&self, prefix: &str) -> Result<Vec<String>> {
        self.list_tree(prefix, false).await
    }

    pub async fn list_playlist_keys(&self, prefix: &str) -> Result<Vec<String>> {
        self.list_tree(prefix, true).await
    }

    async fn list_tree(&self, prefix: &str, include_directories: bool) -> Result<Vec<String>> {
        let mut pending = vec![prefix.trim_end_matches('/').to_owned()];
        let mut keys = BTreeSet::new();
        while let Some(folder) = pending.pop() {
            for (key, directory) in self.children(&folder).await? {
                if directory {
                    if include_directories {
                        keys.insert(format!("{key}/"));
                    }
                    pending.push(key);
                } else {
                    keys.insert(key);
                }
            }
        }
        Ok(keys.into_iter().collect())
    }

    pub async fn test(&self) -> Result<String> {
        let entries = self.children(&self.root).await?;
        Ok(format!("WebDAV 连接成功（{} 项）", entries.len()))
    }

    fn playlist_url(&self, name: &str) -> Result<Url> {
        if name.is_empty() || name.starts_with('.') || name.contains('/') {
            return Err(Error::Parse("WebDAV 歌单名无效".into()));
        }
        let key = self.playlist_prefix(name);
        self.scoped_url(&key, true)
    }

    pub async fn create_playlist(&self, name: &str) -> Result<()> {
        let url = self.playlist_url(name)?;
        let method = Method::from_bytes(b"MKCOL").expect("valid WebDAV method");
        checked(self.request(method, url).send().await?)?;
        Ok(())
    }

    pub async fn delete_playlist(&self, name: &str) -> Result<()> {
        let url = self.playlist_url(name)?;
        let response = self.request(Method::DELETE, url).send().await?;
        if response.status() != StatusCode::NOT_FOUND {
            checked(response)?;
        }
        Ok(())
    }

    pub async fn rename_playlist(&self, from: &str, to: &str) -> Result<()> {
        let source = self.playlist_url(from)?;
        let destination = self.playlist_url(to)?;
        let method = Method::from_bytes(b"MOVE").expect("valid WebDAV method");
        checked(
            self.request(method, source)
                .header("Destination", destination.as_str())
                .header("Overwrite", "F")
                .send()
                .await?,
        )?;
        Ok(())
    }

    async fn children(&self, folder: &str) -> Result<Vec<(String, bool)>> {
        let url = self.scoped_url(folder, true)?;
        let response = self
            .request(
                Method::from_bytes(b"PROPFIND").expect("valid WebDAV method"),
                url.clone(),
            )
            .header("Depth", "1")
            .header("Content-Type", "application/xml; charset=utf-8")
            .body(PROPERTIES)
            .send()
            .await?;
        if response.status() == StatusCode::NOT_FOUND && folder != self.root {
            return Ok(Vec::new());
        }
        if response.status() != StatusCode::MULTI_STATUS {
            let status = response.status();
            return Err(Error::Http(format!(
                "WebDAV PROPFIND 返回 HTTP {}",
                status.as_u16()
            )));
        }
        let body = response.bytes().await?;
        parse_children(&url, folder, &body)
    }

    async fn create_parents(&self, key: &str) -> Result<()> {
        self.object_url(key)?;
        let Some((parent, _)) = key.rsplit_once('/') else {
            return Ok(());
        };
        let mut path = String::new();
        for segment in parent.split('/') {
            if !path.is_empty() {
                path.push('/');
            }
            path.push_str(segment);
            let url = self.url_for(&path, true)?;
            let response = self
                .request(
                    Method::from_bytes(b"MKCOL").expect("valid WebDAV method"),
                    url,
                )
                .send()
                .await?;
            if response.status() != StatusCode::METHOD_NOT_ALLOWED {
                checked(response)?;
            }
        }
        Ok(())
    }

    pub async fn put_object(&self, key: &str, bytes: Vec<u8>, mime: &str) -> Result<()> {
        self.create_parents(key).await?;
        checked(
            self.request(Method::PUT, self.object_url(key)?)
                .header("Content-Type", mime)
                .body(bytes)
                .send()
                .await?,
        )?;
        Ok(())
    }

    pub async fn delete_object(&self, key: &str) -> Result<()> {
        let response = self
            .request(Method::DELETE, self.object_url(key)?)
            .send()
            .await?;
        if response.status() != StatusCode::NOT_FOUND {
            checked(response)?;
        }
        Ok(())
    }

    async fn transfer(&self, method: Method, from: &str, to: &str) -> Result<bool> {
        let source = self.object_url(from)?;
        let destination = self.object_url(to)?;
        self.create_parents(to).await?;
        let response = self
            .request(method, source)
            .header("Destination", destination.as_str())
            .header("Overwrite", "T")
            .send()
            .await?;
        if response.status() == StatusCode::NOT_FOUND {
            return Ok(false);
        }
        checked(response)?;
        Ok(true)
    }

    pub async fn copy_object(&self, from: &str, to: &str) -> Result<bool> {
        self.transfer(
            Method::from_bytes(b"COPY").expect("valid WebDAV method"),
            from,
            to,
        )
        .await
    }

    pub async fn move_object(&self, from: &str, to: &str) -> Result<()> {
        self.transfer(
            Method::from_bytes(b"MOVE").expect("valid WebDAV method"),
            from,
            to,
        )
        .await?
        .then_some(())
        .ok_or_else(|| Error::NotFound(from.into()))
    }
}

fn parse_children(url: &Url, folder: &str, body: &[u8]) -> Result<Vec<(String, bool)>> {
    let parsed: MultiStatus = quick_xml::de::from_reader(body)
        .map_err(|_| Error::Parse("无法解析 WebDAV 目录响应".into()))?;
    let directory_path = percent_decode_str(url.path())
        .decode_utf8()
        .map_err(|_| Error::Parse("WebDAV 目录路径不是有效的 UTF-8".into()))?;
    let mut children = std::collections::BTreeMap::new();
    for entry in parsed.entries {
        let Some(kind) = entry
            .propstat
            .into_iter()
            .filter(|p| p.status.split_whitespace().nth(1) == Some("200"))
            .find_map(|p| p.prop.resourcetype)
        else {
            continue;
        };
        let Ok(href) = url.join(entry.href.trim()) else {
            continue;
        };
        if href.origin() != url.origin() || href.query().is_some() || href.fragment().is_some() {
            continue;
        }
        let Ok(resource_path) = percent_decode_str(href.path()).decode_utf8() else {
            continue;
        };
        let Some(name) = resource_path.strip_prefix(directory_path.as_ref()) else {
            continue;
        };
        let name = name.trim_end_matches('/');
        if name.is_empty() || name.contains('/') || validate_path(name).is_err() {
            continue;
        }
        let key = if folder.is_empty() {
            name.to_owned()
        } else {
            format!("{folder}/{name}")
        };
        children.insert(key, kind.collection.is_some());
    }
    Ok(children.into_iter().collect())
}

fn validate_path(path: &str) -> Result<()> {
    if !path.is_empty()
        && path.split('/').any(|segment| {
            segment.is_empty()
                || matches!(segment, "." | "..")
                || segment.contains('\\')
                || segment.chars().any(char::is_control)
        })
    {
        return Err(Error::Parse("WebDAV 路径无效".into()));
    }
    Ok(())
}

fn checked(response: Response) -> Result<Response> {
    if response.status().is_success() && response.status() != StatusCode::MULTI_STATUS {
        return Ok(response);
    }
    Err(Error::Http(format!(
        "WebDAV 返回 HTTP {}",
        response.status().as_u16()
    )))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn multistatus_decodes_names_and_ignores_entries_outside_the_directory() {
        let url = Url::parse("https://nas.example/dav/TinyMusic/").unwrap();
        let xml = r#"<D:multistatus xmlns:D="DAV:">
            <D:response><D:href>/dav/TinyMusic/</D:href><D:propstat>
                <D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop>
                <D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>
            <D:response><D:href>/dav/TinyMusic/%E9%80%9A%E5%8B%A4/</D:href><D:propstat>
                <D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop>
                <D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>
            <D:response><D:href>Artist%20-%20Song%20%231%25.flac</D:href><D:propstat>
                <D:prop><D:resourcetype/></D:prop>
                <D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>
            <D:response><D:href>https://other.example/dav/TinyMusic/other.flac</D:href><D:propstat>
                <D:prop><D:resourcetype/></D:prop>
                <D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>
        </D:multistatus>"#;
        let entries = parse_children(&url, "TinyMusic", xml.as_bytes()).unwrap();
        assert_eq!(
            entries,
            vec![
                ("TinyMusic/Artist - Song #1%.flac".to_owned(), false),
                ("TinyMusic/通勤".to_owned(), true),
            ]
        );
    }

    #[test]
    fn media_request_encodes_paths_and_keeps_credentials_out_of_the_url() {
        let client = WebDav::new(
            "https://nas.example/dav",
            "/TinyMusic/",
            "user".into(),
            "pass".into(),
        )
        .unwrap();
        let request = client
            .read_request("TinyMusic/通勤/歌手 - 歌名 #1%.flac", Method::GET)
            .unwrap()
            .build()
            .unwrap();
        assert_eq!(request.url().username(), "");
        assert!(request
            .url()
            .path()
            .starts_with("/dav/TinyMusic/%E9%80%9A%E5%8B%A4/"));
        assert!(request.url().path().ends_with("%20%231%25.flac"));
        assert_eq!(
            client.playlist_url(" 通勤 ").unwrap().path(),
            "/dav/TinyMusic/%20%E9%80%9A%E5%8B%A4%20/"
        );
        assert_eq!(
            request.headers()[reqwest::header::AUTHORIZATION],
            "Basic dXNlcjpwYXNz"
        );
        assert!(client
            .read_request("TinyMusic/../outside.flac", Method::GET)
            .is_err());
        assert!(client
            .read_request("Other/outside.flac", Method::GET)
            .is_err());
    }
}
