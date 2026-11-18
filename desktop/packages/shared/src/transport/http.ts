//! mobile 实现：本地 HTTP（127.0.0.1 + 随机 token）。
//!
//! 进度：后端把进度写进内存登记表，这里轮询 /api/progress 后回调，
//! 语义与桌面的 Channel 推送一致，上层不用区分平台。

import type { ProgressCallback, Transport } from './index';

export interface HttpTransportOptions {
  baseUrl: string;
  token: string;
  /** 方便测试注入；默认用全局 fetch */
  fetchImpl?: typeof fetch;
  /** 轮询间隔，毫秒 */
  pollMs?: number;
}

interface ProgressEntry {
  task_id?: string;
  downloaded?: number;
  total?: number | null;
  id?: string;
  status?: string;
  done?: number;
}

export function createHttpTransport(opts: HttpTransportOptions): Transport {
  const base = opts.baseUrl.replace(/\/+$/, '');
  const doFetch = opts.fetchImpl ?? fetch;
  const pollMs = opts.pollMs ?? 400;

  async function call<T>(cmd: string, args?: Record<string, unknown>): Promise<T> {
    const res = await doFetch(`${base}/api/${cmd}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-tm-token': opts.token },
      body: JSON.stringify(args ?? {}),
    });
    if (res.status === 401) throw new Error('本地服务鉴权失败（token 不匹配）');
    const body = (await res.json()) as { ok?: boolean; data?: unknown; error?: string };
    if (!body?.ok) throw new Error(body?.error || `命令 ${cmd} 失败`);
    return body.data as T;
  }

  async function readProgress(): Promise<{ tasks: Record<string, ProgressEntry>; s3fix: ProgressEntry | null }> {
    const res = await doFetch(`${base}/api/progress`, {
      headers: { 'x-tm-token': opts.token },
    });
    if (!res.ok) return { tasks: {}, s3fix: null };
    return (await res.json()) as { tasks: Record<string, ProgressEntry>; s3fix: ProgressEntry | null };
  }

  const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

  async function startTask<T>(
    cmd: string,
    args: Record<string, unknown>,
    onProgress: ProgressCallback
  ): Promise<T> {
    // 同步长任务（补齐网盘）：先发出请求，同时轮询 s3fix 槽
    if (cmd === 's3_integrity_fix') {
      const pending = call<T>(cmd, args);
      let last = '';
      for (;;) {
        const snap = await readProgress();
        const p = snap.s3fix;
        if (p) {
          const key = JSON.stringify(p);
          if (key !== last) {
            last = key;
            onProgress(p);
          }
          if ((p.status === 'done' || p.status === 'failed') && (p.done ?? 0) >= 0) {
            const settled = await Promise.race([pending, sleep(0).then(() => null)]);
            if (settled !== null) return settled;
          }
        }
        await sleep(pollMs);
      }
    }

    // 其余命令：立即返回 task id（或 id 列表），任务在后台跑
    const result = await call<T>(cmd, args);
    const ids: string[] = Array.isArray(result)
      ? (result as unknown[]).filter((x): x is string => typeof x === 'string')
      : typeof result === 'string'
        ? [result]
        : [];
    if (ids.length === 0) return result;

    const remaining = new Set(ids);
    const started = Date.now();
    const timeoutMs = 30 * 60 * 1000;
    const seen = new Set<string>();
    while (remaining.size > 0 && Date.now() - started < timeoutMs) {
      const snap = await readProgress();
      for (const id of [...remaining]) {
        const p = snap.tasks[id];
        if (!p) continue;
        const key = `${id}:${p.downloaded ?? 0}/${p.total ?? '?'}`;
        if (!seen.has(key)) {
          seen.add(key);
          onProgress(p);
        }
        if (p.total != null && (p.downloaded ?? 0) >= p.total) remaining.delete(id);
      }
      if (remaining.size > 0) await sleep(pollMs);
    }
    return result;
  }

  return {
    call,
    startTask,
    shell: <T>() => Promise.reject(new Error('该能力只在桌面端提供')),
  };
}
