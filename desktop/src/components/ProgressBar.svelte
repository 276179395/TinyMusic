<script lang="ts">
  import { HugeiconsIcon } from '@hugeicons/svelte';
  import { icons, ICON_SIZE } from '../lib/icons';
  import { t } from '../lib/i18n.svelte';

  /**
   * 统一下载/导入进度展示。
   * value 为 0..1；为 null 时显示不确定进度（来回滑动的填充），
   * 适合「刚开始、还没收到第一帧进度」的阶段。
   */
  let {
    value = null,
    label,
    busy = true
  }: {
    value?: number | null;
    label?: string;
    busy?: boolean;
  } = $props();

  const pct = $derived(value == null ? null : Math.max(0, Math.min(1, value)) * 100);
  const displayLabel = $derived(label ?? t('处理中…'));
</script>

<div class="pbar" role="group" aria-label={t('进度')}>
  <div
    class="pbar-track"
    class:indeterminate={pct == null}
    role="progressbar"
    aria-label={displayLabel}
    aria-valuemin="0"
    aria-valuemax="100"
    aria-valuenow={pct == null ? undefined : Math.round(pct)}
  >
    <span class="pbar-fill" style={pct == null ? '' : `width:${pct}%`}></span>
  </div>
  <div class="pbar-meta">
    {#if busy}
      <span class="spin"><HugeiconsIcon icon={icons.loading} size={ICON_SIZE.inline} /></span>
    {/if}
    <span class="pbar-label">{displayLabel}</span>
    {#if pct != null}<span class="pbar-pct">{Math.round(pct)}%</span>{/if}
  </div>
</div>
