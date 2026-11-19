<script lang="ts">
  import { HugeiconsIcon } from '@hugeicons/svelte';
  import type { Track } from '../lib/api';
  import { icons, ICON_SIZE } from '../lib/icons';
  import { playTrack } from '../lib/player.svelte';
  import { requestDownload, downloadUi } from '../lib/download.svelte';
  import { t } from '../lib/i18n.svelte';

  let { tracks, label = '' }: { tracks: Track[]; label?: string } = $props();

  const busy = $derived(downloadUi.busy);
  const msg = $derived(
    downloadUi.busy ? downloadUi.progress : downloadUi.doneMsg || downloadUi.err || ''
  );

  const localTracks = $derived(tracks.filter((t) => t.provider !== 's3'));

  function downloadAll() {
    void requestDownload(localTracks);
  }
</script>

<div class="batchbar">
  <button
    class="primary"
    disabled={tracks.length === 0}
    onclick={() => tracks[0] && playTrack(tracks[0], tracks)}
  >
    <HugeiconsIcon icon={icons.play} size={ICON_SIZE.inline} />
    {t('播放全部')}
  </button>
  <button disabled={busy || localTracks.length === 0} onclick={downloadAll}>
    {#if busy}
      <span class="spin"><HugeiconsIcon icon={icons.loading} size={ICON_SIZE.inline} /></span>
    {:else}
      <HugeiconsIcon icon={icons.download} size={ICON_SIZE.inline} />
    {/if}
    {busy ? t('下载中…') : label ? t('下载全部 · {label}', { label }) : t('下载全部')}
  </button>
  {#if msg}<span class="muted small">{msg}</span>{/if}
</div>
