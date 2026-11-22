//! 后端命令的 TS 门面：desktop 与 mobile 完全共用。
//!
//! 只描述「调什么命令、参数叫什么」；怎么送出去由 transport 决定。

import type { ProgressCallback } from './transport';
import { invoke, invokeTask, shellInvoke } from './transport';
import type { LocalFolder, LocalMusicItem } from './types';
import type { Availability, Quality, Track, AudioFormat, QualityCapability, TrackQualities, TrackDetail, PlayerSource, DownloadRow, S3IntegrityIssue, S3IntegrityReport, S3FixProgress, FailedPartName, FailedPart, FailedDownload, Settings, S3PlaylistInfo, S3TrackRow, Progress } from './types';

type ThemePackSource = { config: unknown; css: string; images: Record<string, string> };

export const api = {
  resolve: (track: Track, quality: Quality) =>
    invoke<{
      url: string;
      quality: Quality;
      requested: Quality;
      bytes: number | null;
      content_type: string;
      availability: Availability;
      format: AudioFormat;
      via: string;
      degraded: boolean;
      verified: boolean;
    }>('resolve', { track, quality }),

  qualityCapabilities: () => invoke<QualityCapability[]>('quality_capabilities'),

  qualitySet: (quality: Quality) => invoke<string>('quality_set', { quality }),

  trackQualities: (track: Track) => invoke<TrackQualities>('track_qualities', { track }),

  detail: (provider: string, track: Track) =>
    invoke<TrackDetail>('track_detail', { provider, track }),

  playerOpen: (track: Track, quality: Quality, forceRefresh = false, allowLocal = true) =>
    invoke<PlayerSource>('player_open', { track, quality, forceRefresh, allowLocal }),

  localMusicList: () => invoke<LocalMusicItem[]>('local_music_list'),
  localMusicInputDir: () => shellInvoke<string>('local_music_input_dir'),
  localMusicAdd: (paths: string[]) => shellInvoke<Track[]>('local_music_add', { paths }),
  localMusicRemove: (id: string) => invoke<void>('local_music_remove', { id }),
  localMusicMigrate: (legacy: LocalFolder[]) => shellInvoke<LocalFolder[]>('local_music_migrate', { legacy }),
  localMusicFolders: () => invoke<LocalFolder[]>('local_music_folders'),
  localMusicCreateFolder: (name: string) => invoke<LocalFolder[]>('local_music_create_folder', { name }),
  localMusicRenameFolder: (id: string, name: string) => invoke<LocalFolder[]>('local_music_change_folder', { id, name }),
  localMusicDeleteFolder: (id: string) => invoke<LocalFolder[]>('local_music_delete_folder', { id }),
  localMusicSetFolderTrack: (folder: string, id: string, included: boolean) =>
    invoke<LocalFolder[]>('local_music_set_folder_track', { folder, id, included }),
  localMusicSetFavorite: (track: Track, included: boolean) =>
    invoke<LocalFolder[]>('local_music_set_favorite', { track, included }),
  localMusicCopyLibrary: (destination: string) => shellInvoke<string>('local_music_copy_library', { destination }),

  downloadStart: (track: Track, quality: Quality, onProgress: (p: Progress) => void) => {
    return invokeTask<string>('download_start', { track, quality }, onProgress as ProgressCallback);
  },

  downloads: () => invoke<DownloadRow[]>('download_list'),
  downloadClear: () => invoke<void>('download_clear'),

  // ---- 下载失败记录 / 手动重试 ----
  downloadFailures: () => invoke<FailedDownload[]>('download_failures'),
  /** 只补失败的部分；返回重试后仍然失败的记录 */
  downloadRetryFailed: (ids: string[]) =>
    invoke<FailedDownload[]>('download_retry_failed', { ids }),
  downloadFailureDismiss: (id: string) =>
    invoke<void>('download_failure_dismiss', { id }),
  downloadFailuresClear: () => invoke<void>('download_failures_clear'),

  favoriteAdd: (track: Track) => invoke<void>('favorite_add', { track }),
  favoriteRemove: (track: Track) =>
    invoke<void>('favorite_remove', {
      provider: track.provider,
      id: track.id,
      title: track.title,
      artist: track.artist,
    }),
  favoriteList: () => invoke<Track[]>('favorite_list'),
  favoritesPull: () => invoke<Track[]>('favorites_pull'),
  /**
   * 是否已收藏。
   *
   * 收藏存在网盘「喜欢」目录里，id 是那边的副本 key，跟歌单里的原始 key 不同，
   * 所以要把标题/歌手一起带上，后端用它认「同一首歌」。
   */
  favoriteCheck: (track: Track) =>
    invoke<boolean>('favorite_check', {
      provider: track.provider,
      id: track.id,
      title: track.title,
      artist: track.artist,
    }),

  /** 批量下载（顺序执行） */
  downloadBatch: (
    tracks: Track[],
    quality: Quality,
    onProgress: (p: Progress) => void
  ) => {
    return invokeTask<string[]>('download_batch', { tracks, quality }, onProgress as ProgressCallback);
  },

  setWindowTheme: (mode: 'auto' | 'light' | 'dark') =>
    shellInvoke<void>('set_window_theme', { theme: mode === 'auto' ? null : mode }),
  settingsGet: () => invoke<Settings>('settings_get'),
  settingsSet: (settings: Settings) => invoke<void>('settings_set', { settings }),
  playbackCacheQueue: (track: Track) => invoke<void>('playback_cache_queue', { track }),
  playbackCacheClear: (cacheDir: string) => invoke<void>('playback_cache_clear', { cacheDir }),
  openDownloadDir: () => shellInvoke<void>('open_download_dir'),
  readThemePack: (path: string) => shellInvoke<ThemePackSource>('read_theme_pack', { path }),
  listThemePacks: () => shellInvoke<ThemePackSource[]>('list_theme_packs'),
  saveThemePack: (path: string, id: string) => shellInvoke<void>('save_theme_pack', { path, id }),

  // ---- 网盘（S3） ----
  s3Test: () => invoke<string>('s3_test'),
  s3Playlists: () => invoke<S3PlaylistInfo[]>('s3_playlists'),
  s3PlaylistCreate: (name: string) => invoke<string>('s3_playlist_create', { name }),
  s3PlaylistDelete: (name: string) => invoke<void>('s3_playlist_purge', { name }),
  s3PlaylistRename: (oldName: string, newName: string) =>
    invoke<string>('s3_playlist_rename', { old: oldName, new: newName }),
  s3PlaylistTracks: (name: string, root = false) =>
    invoke<S3TrackRow[]>('s3_playlist_tracks', { name, root }),
  s3ReorderPlaylists: (names: string[]) => invoke<void>('s3_playlists_reorder', { names }),
  /** 重新签一个网盘曲目的封面直链（签名地址会过期） */
  s3Cover: (key: string, provider?: string) => invoke<string | null>('s3_cover', { key, provider }),

  // ---- 网盘完整性检测 ----
  /** 检查整库（playlist 为空）或某个歌单里缺音频 / 歌词 / 封面的条目 */
  s3IntegrityCheck: (playlist?: string | null) =>
    invoke<S3IntegrityReport>('s3_integrity_check', { playlist: playlist || null }),
  /** 补齐选中的条目，返回补齐后重新扫描的结果 */
  s3IntegrityFix: (
    playlist: string | null,
    ids: string[],
    onProgress: (p: S3FixProgress) => void
  ) => {
    return invokeTask<S3IntegrityReport>('s3_integrity_fix', { playlist,
      ids
    }, onProgress as ProgressCallback);
  },
  s3TrackDelete: (key: string) => invoke<void>('s3_track_delete', { key }),
  s3Download: (
    track: Track,
    quality: Quality,
    playlist: string,
    onProgress: (p: Progress) => void
  ) => {
    return invokeTask<string>('s3_download', { track, quality, playlist }, onProgress as ProgressCallback);
  },
  s3DownloadBatch: (
    tracks: Track[],
    quality: Quality,
    playlist: string,
    onProgress: (p: Progress) => void
  ) => {
    return invokeTask<string[]>('s3_download_batch', { tracks, quality, playlist }, onProgress as ProgressCallback);
  },

  /** 把主窗口收进托盘（播放不中断） */
  hideToTray: () => shellInvoke<void>('hide_to_tray'),
};
