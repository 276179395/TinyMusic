<script lang="ts">
  import { HugeiconsIcon } from '@hugeicons/svelte';
  import { icons } from '../lib/icons';
  import {
    importQueue,
    removeImport,
    clearFinishedImports,
  } from '../lib/importQueue.svelte';
  import ProgressBar from './ProgressBar.svelte';
  import ErrorNotice from './ErrorNotice.svelte';
  import { t } from '../lib/i18n.svelte';

  const queuedCount = $derived(
    importQueue.tasks.filter((task) => task.status === 'queued').length
  );
  const finishedCount = $derived(
    importQueue.tasks.filter((task) => task.status === 'done' || task.status === 'error').length
  );
</script>

{#if importQueue.tasks.length}
  <section class="impq" aria-label={t('导入队列')}>
    <div class="impq-head">
      <span class="impq-title">{t('导入队列')}</span>
      <span class="impq-count">
        {#if importQueue.running}{t('导入中')}{/if}
        {#if queuedCount}
          {#if importQueue.running} · {/if}{t('{n} 个排队', { n: queuedCount })}
        {/if}
      </span>
      {#if finishedCount}
        <button class="impq-clear" onclick={clearFinishedImports}>{t('清空已结束')}</button>
      {/if}
    </div>

    <div class="impq-list">
      {#each importQueue.tasks as task (task.id)}
        <div class="impq-row">
          <div class="impq-main">
            <div class="impq-names" title={`${task.name} → ${task.target}`}>
              <span class="impq-src">{task.name}</span>
              <span class="impq-arrow">→</span>
              <span class="impq-target">{task.target}</span>
            </div>
            {#if task.status === 'running'}
              <ProgressBar value={task.pct} label={task.label || t('正在导入…')} />
            {:else if task.status === 'queued'}
              <div class="impq-sub">{t('排队中，轮到后自动开始')}</div>
            {:else if task.status === 'done'}
              <div class="impq-sub ok">
                {t('已导入 {n} 首', { n: task.uploaded })}{#if task.failed}{t('，{n} 首失败', { n: task.failed })}{/if}
              </div>
            {:else}
              <ErrorNotice text={task.error || t('导入失败')} compact />
            {/if}
          </div>

          <div class="impq-side">
            {#if task.status === 'running'}
              <span class="impq-badge on">{t('导入中')}</span>
            {:else if task.status === 'queued'}
              <span class="impq-badge">{t('排队中')}</span>
            {:else if task.status === 'done'}
              <span class="impq-badge done">{t('完成')}</span>
            {:else}
              <span class="impq-badge bad">{t('失败')}</span>
            {/if}
            {#if task.status !== 'running'}
              <button
                class="impq-x"
                title={t('移除任务')}
                aria-label={t('移除 {name} 的导入任务', { name: task.name })}
                onclick={() => removeImport(task.id)}
              >
                <HugeiconsIcon icon={icons.close} size={12} />
              </button>
            {/if}
          </div>
        </div>
      {/each}
    </div>
  </section>
{/if}
