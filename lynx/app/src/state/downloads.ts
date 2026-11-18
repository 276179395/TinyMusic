import { useEffect, useState } from '@lynx-js/react';
import { api } from '@tinymusic/shared/api';
import type { DownloadRow, FailedDownload, Progress, Quality, Track } from '@tinymusic/shared/types';

export interface DownloadsSnapshot {
  rows: DownloadRow[];
  failures: FailedDownload[];
  /** 正在下载的进度（按 taskId） */
  progress: Record<string, Progress>;
  busy: boolean;
  message: string;
  error: string;
}

type Listener = () => void;

/**
 * 下载状态（mobile）。
 *
 * 编排（批量/重试/失败记录）都在 Rust 的 crates/app 里，
 * 这里只负责：发命令、把进度回调写进快照、给界面订阅。
 */
class DownloadsStore {
  private state: DownloadsSnapshot = {
    rows: [],
    failures: [],
    progress: {},
    busy: false,
    message: '',
    error: '',
  };

  private listeners = new Set<Listener>();

  snapshot(): DownloadsSnapshot {
    return { ...this.state, rows: [...this.state.rows], failures: [...this.state.failures] };
  }

  subscribe(fn: Listener): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  private patch(next: Partial<DownloadsSnapshot>): void {
    this.state = { ...this.state, ...next };
    for (const fn of this.listeners) fn();
  }

  async refresh(): Promise<void> {
    try {
      const [rows, failures] = await Promise.all([api.downloads(), api.downloadFailures()]);
      this.patch({ rows, failures });
    } catch (e) {
      this.patch({ error: String(e) });
    }
  }

  /** 下载一首（进度回调用 httpTransport 的轮询实现） */
  async start(track: Track, quality: Quality = 'super'): Promise<void> {
    this.patch({ busy: true, message: '正在下载…', error: '' });
    try {
      const taskId = await api.downloadStart(track, quality, (p: Progress) => {
        this.patch({ progress: { ...this.state.progress, [p.task_id]: p } });
      });
      this.patch({ message: '已加入下载：' + track.title });
      void taskId;
      await this.refresh();
    } catch (e) {
      this.patch({ error: String(e) });
    } finally {
      this.patch({ busy: false });
    }
  }

  async retry(ids: string[]): Promise<void> {
    this.patch({ busy: true, message: '正在重试…' });
    try {
      await api.downloadRetryFailed(ids);
      await this.refresh();
      this.patch({ message: '重试完成' });
    } catch (e) {
      this.patch({ error: String(e) });
    } finally {
      this.patch({ busy: false });
    }
  }

  async dismiss(id: string): Promise<void> {
    await api.downloadFailureDismiss(id);
    await this.refresh();
  }

  async clearFailures(): Promise<void> {
    await api.downloadFailuresClear();
    await this.refresh();
  }
}

export const downloads = new DownloadsStore();

export function useDownloads(): DownloadsSnapshot {
  const [snap, setSnap] = useState<DownloadsSnapshot>(downloads.snapshot());
  useEffect(() => {
    'background only';
    void downloads.refresh();
    return downloads.subscribe(() => setSnap(downloads.snapshot()));
  }, []);
  return snap;
}
