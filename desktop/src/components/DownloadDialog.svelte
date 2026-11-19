<script lang="ts">
  import { HugeiconsIcon } from '@hugeicons/svelte';
  import MorphIcon from './MorphIcon.svelte';
  import { fmtDuration } from '../lib/api';
  import { icons, ICON_SIZE } from '../lib/icons';
  import {
    downloadUi,
    closeDownloadDialog,
    createPlaylistAndSelect,
    runLocal,
    runS3,
  } from '../lib/download.svelte';
  import ProgressBar from './ProgressBar.svelte';
  import ErrorNotice from './ErrorNotice.svelte';
  import { t } from '../lib/i18n.svelte';

  const count = $derived(downloadUi.targets.length);
  const preview = $derived(downloadUi.targets.slice(0, 4));
  const more = $derived(Math.max(0, count - preview.length));

  function close() {
    if (downloadUi.busy) return;
    closeDownloadDialog(true);
  }

  async function start() {
    if (downloadUi.busy) return;
    downloadUi.err = '';
    if (downloadUi.mode === 's3') {
      let pl = downloadUi.playlist;
      if (downloadUi.newPlaylist.trim()) {
        pl = downloadUi.newPlaylist.trim();
        await createPlaylistAndSelect(pl);
        if (downloadUi.err) return;
        pl = downloadUi.playlist || pl;
      }
      await runS3(downloadUi.targets, pl);
    } else {
      await runLocal(downloadUi.targets);
    }
    if (!downloadUi.err) {
      setTimeout(() => {
        if (!downloadUi.busy) downloadUi.open = false;
      }, 900);
    }
  }

  function onKey(e: KeyboardEvent) {
    if (e.key === 'Escape') close();
  }
</script>

<svelte:window onkeydown={onKey} />

{#if downloadUi.open}
  <div
    class="modal-mask"
    role="presentation"
    onclick={(e) => {
      if (e.target === e.currentTarget) close();
    }}
  >
    <div class="modal" role="dialog" aria-modal="true" aria-label={t('下载歌曲')}>
      <div class="modal-head">
        <div>
          <h2>{t('下载 {n} 首歌曲', { n: count })}</h2>
          <p class="hint">
            {t('音频内嵌封面标签，歌词保存为同名 .lrc 文件；音频 / 歌词 / 封面失败会自动重试 5 次')}
          </p>
        </div>
        <button class="icon" onclick={close} aria-label={t('关闭')} disabled={downloadUi.busy}>
          <HugeiconsIcon icon={icons.close} size={ICON_SIZE.inline} />
        </button>
      </div>

      <div class="targets">
        <label class="target" class:on={downloadUi.mode === 'local'}>
          <input type="radio" bind:group={downloadUi.mode} value="local" />
          <span class="tico"><HugeiconsIcon icon={icons.downloadDir} size={ICON_SIZE.inline} /></span>
          <span>
            <strong>{t('下载到本地')}</strong>
            <em>{t('保存到设置里的下载目录')}</em>
          </span>
        </label>
        <label class="target" class:on={downloadUi.mode === 's3'}>
          <input type="radio" bind:group={downloadUi.mode} value="s3" />
          <span class="tico"><HugeiconsIcon icon={icons.cloud} size={ICON_SIZE.inline} /></span>
          <span>
            <strong>{t('下载到网盘')}</strong>
            <em>{t('S3 兼容存储，可归入歌单')}</em>
          </span>
        </label>
      </div>

      {#if downloadUi.mode === 's3'}
        <div class="field">
          <div class="lbl">{t('网盘歌单')}</div>
          <select class="select" bind:value={downloadUi.playlist} disabled={downloadUi.busy}>
            <option value="">{t('（未分类，放在根目录）')}</option>
            {#each downloadUi.playlists as p (p.name)}
              <option value={p.name}>{t('{name}（{n} 首）', { name: p.name, n: p.count })}</option>
            {/each}
          </select>
          <div class="newpl">
            <input
              bind:value={downloadUi.newPlaylist}
              placeholder={t('新建歌单名称（可选）')}
              disabled={downloadUi.busy}
            />
            <button
              class="mini"
              disabled={downloadUi.busy || !downloadUi.newPlaylist.trim()}
              onclick={() => createPlaylistAndSelect(downloadUi.newPlaylist)}
            >
              <HugeiconsIcon icon={icons.plus} size={ICON_SIZE.inline} />
              {t('新建歌单')}
            </button>
          </div>
        </div>
      {/if}

      <div class="dl-preview">
        {#each preview as track (track.provider + track.id)}
          <div class="dl-prow">
            <span class="dp-t">{track.title}</span>
            <span class="dp-a">{track.artist}</span>
            <span class="dp-d">{fmtDuration(track.duration_sec)}</span>
          </div>
        {/each}
        {#if more > 0}
          <div class="dl-prow muted">{t('… 还有 {n} 首', { n: more })}</div>
        {/if}
      </div>

      {#if downloadUi.busy || downloadUi.progress}
        <ProgressBar
          value={downloadUi.progressPct}
          label={downloadUi.progress || t('处理中…')}
        />
      {/if}
      {#if downloadUi.doneMsg}<div class="ok small">{downloadUi.doneMsg}</div>{/if}
      {#if downloadUi.err}<ErrorNotice text={downloadUi.err} compact />{/if}

      <div class="modal-actions">
        <button class="mini" onclick={close} disabled={downloadUi.busy}>{t('取消')}</button>
        <button class="primary" onclick={start} disabled={downloadUi.busy || count === 0}>
          <MorphIcon
            icon={downloadUi.mode === 's3' ? icons.cloud : icons.download}
            size={ICON_SIZE.inline}
          />
          {downloadUi.busy
            ? t('任务进行中…')
            : downloadUi.mode === 's3'
              ? t('下载到网盘')
              : t('下载到本地')}
        </button>
      </div>
    </div>
  </div>
{/if}
