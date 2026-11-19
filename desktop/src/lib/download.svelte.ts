/**
 * 下载流程（本地 / 网盘）。
 *
 * 所有下载入口（单曲、批量、专辑）都走 `requestDownload`：
 * * S3 未启用 → 直接开始本地下载，行为与旧版一致
 * * S3 已启用 → 弹窗让用户选择「本地」还是「网盘」，网盘还要选歌单
 */
import { api, isBlocked, type Quality, type S3PlaylistInfo, type Track } from './api';
import { player } from './player.svelte';
import { t } from './i18n.svelte';

export type DownloadTarget = 'local' | 's3';

export const downloadUi = $state({
  open: false,
  targets: [] as Track[],
  mode: 'local' as DownloadTarget,
  playlists: [] as S3PlaylistInfo[],
  playlist: '',
  newPlaylist: '',
  busy: false,
  active: [] as string[],
  progress: '',
  /** 0..1；null 表示还没有可用的百分比 */
  progressPct: null as number | null,
  err: '',
  doneMsg: '',
  playlistLoading: false,
});

const keyOf = (track: Track) => `${track.provider}:${track.id}`;

export function isPending(track: Track): boolean {
  return downloadUi.active.includes(keyOf(track));
}

function markActive(track: Track, on: boolean) {
  const k = keyOf(track);
  if (on) {
    if (!downloadUi.active.includes(k)) downloadUi.active = [...downloadUi.active, k];
  } else {
    downloadUi.active = downloadUi.active.filter((x) => x !== k);
  }
}

function currentQuality(): Quality {
  return player.quality || 'super';
}

export function closeDownloadDialog(force = false) {
  if (downloadUi.busy && !force) return;
  downloadUi.open = false;
}

export async function loadPlaylists() {
  downloadUi.playlistLoading = true;
  try {
    // 「未分类」是根目录的伪歌单，下拉框里已经有「（未分类，放在根目录）」了
    const list = (await api.s3Playlists()).filter((p) => !p.root);
    downloadUi.playlists = list;
    if (!list.some((p) => p.name === downloadUi.playlist)) {
      downloadUi.playlist = list[0]?.name ?? '';
    }
  } catch (e) {
    downloadUi.playlists = [];
    downloadUi.err = String(e);
  } finally {
    downloadUi.playlistLoading = false;
  }
}

/** 下载入口：按设置决定「直接下载」还是「弹窗选择」 */
export async function requestDownload(tracks: Track[]) {
  const list = tracks.filter((track) => track && !isBlocked(track.availability));
  if (!list.length) return;

  let s3Enabled = false;
  try {
    const s = await api.settingsGet();
    s3Enabled = !!s.s3_enabled && !!s.s3_bucket;
  } catch {
    s3Enabled = false;
  }

  if (!s3Enabled) {
    void runLocal(list);
    return;
  }

  downloadUi.targets = list;
  downloadUi.mode = 'local';
  downloadUi.newPlaylist = '';
  downloadUi.err = '';
  downloadUi.progress = '';
  downloadUi.progressPct = null;
  downloadUi.doneMsg = '';
  downloadUi.busy = false;
  downloadUi.open = true;
  void loadPlaylists();
}

/** 本地下载（单曲走 download_start，多曲顺序批量） */
export async function runLocal(list: Track[], onProgress?: (msg: string) => void) {
  const q = currentQuality();
  downloadUi.busy = true;
  downloadUi.err = '';
  downloadUi.progress = '';
  downloadUi.progressPct = null;
  downloadUi.doneMsg = '';

  try {
    if (list.length === 1) {
      const track = list[0];
      markActive(track, true);
      downloadUi.progress = t('正在下载…');
      onProgress?.(t('正在下载…'));
      await api.downloadStart(track, q, (p) => {
        if (p.total && p.total > 0) {
          downloadUi.progressPct = Math.min(1, p.downloaded / p.total);
          onProgress?.(`${Math.round((p.downloaded / p.total) * 100)}%`);
        }
      });
      downloadUi.progress = '';
      downloadUi.progressPct = null;
      downloadUi.doneMsg = t('已加入下载队列（音频 + 歌词 + 封面）');
      onProgress?.(t('已加入下载'));
    } else {
      downloadUi.progress = t('准备中…');
      onProgress?.(t('准备中…'));
      const ids = await api.downloadBatch(list, q, (p) => {
        if (
          p.total &&
          p.task_id.startsWith('batch-') &&
          !p.task_id.startsWith('batch-done')
        ) {
          downloadUi.progress = t('第 {i} / {n} 首', { i: p.downloaded + 1, n: p.total });
          downloadUi.progressPct = Math.min(1, p.downloaded / p.total);
          onProgress?.(downloadUi.progress);
        }
      });
      downloadUi.progress = '';
      downloadUi.progressPct = null;
      downloadUi.doneMsg = t('已下载 {n} 首（音频 + 歌词 + 封面）', { n: ids.length });
      onProgress?.(t('已下载 {n} 首', { n: ids.length }));
    }
  } catch (e) {
    const msg = String(e);
    downloadUi.err = msg.includes('unavailable')
      ? t('部分曲目不可下载（服务端没给完整音频）')
      : msg;
    downloadUi.progress = '';
    downloadUi.progressPct = null;
    onProgress?.(t('下载失败'));
  } finally {
    if (list.length === 1) markActive(list[0], false);
    downloadUi.busy = false;
    setTimeout(() => {
      if (!downloadUi.busy) downloadUi.doneMsg = '';
    }, 4000);
  }
}

/** 上传到 S3 网盘（单曲 / 批量） */
export async function runS3(list: Track[], playlist: string, onProgress?: (msg: string) => void) {
  const q = currentQuality();
  const pl = playlist.trim();
  downloadUi.busy = true;
  downloadUi.err = '';
  downloadUi.progress = '';
  downloadUi.progressPct = null;
  downloadUi.doneMsg = '';

  try {
    if (list.length === 1) {
      markActive(list[0], true);
      downloadUi.progress = t('正在上传…');
      onProgress?.(t('正在上传…'));
      await api.s3Download(list[0], q, pl, (p) => {
        if (p.total && p.total > 0) {
          downloadUi.progressPct = Math.min(1, p.downloaded / p.total);
          onProgress?.(`${Math.round((p.downloaded / p.total) * 100)}%`);
        }
      });
      downloadUi.progress = '';
      downloadUi.progressPct = null;
      downloadUi.doneMsg = t('已保存到网盘（音频 + 歌词 + 封面）');
      onProgress?.(t('已上传'));
    } else {
      downloadUi.progress = t('准备中…');
      onProgress?.(t('准备中…'));
      const keys = await api.s3DownloadBatch(list, q, pl, (p) => {
        if (
          p.total &&
          p.task_id.startsWith('batch-') &&
          !p.task_id.startsWith('batch-done')
        ) {
          downloadUi.progress = t('第 {i} / {n} 首', { i: p.downloaded + 1, n: p.total });
          downloadUi.progressPct = Math.min(1, p.downloaded / p.total);
          onProgress?.(downloadUi.progress);
        }
      });
      downloadUi.progress = '';
      downloadUi.progressPct = null;
      downloadUi.doneMsg = t('已上传 {n} 首到网盘', { n: keys.length });
      onProgress?.(t('已上传 {n} 首', { n: keys.length }));
      void loadPlaylists();
    }
  } catch (e) {
    downloadUi.err = String(e);
    downloadUi.progress = '';
    downloadUi.progressPct = null;
    onProgress?.(t('上传失败'));
  } finally {
    if (list.length === 1) markActive(list[0], false);
    downloadUi.busy = false;
    setTimeout(() => {
      if (!downloadUi.busy) downloadUi.doneMsg = '';
    }, 5000);
  }
}

export async function createPlaylistAndSelect(name: string) {
  const n = name.trim();
  if (!n) return;
  try {
    await api.s3PlaylistCreate(n);
    downloadUi.newPlaylist = '';
    await loadPlaylists();
    downloadUi.playlist = n;
  } catch (e) {
    downloadUi.err = String(e);
  }
}
