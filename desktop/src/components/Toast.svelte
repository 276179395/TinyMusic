<script lang="ts">
  import { toast, copyText } from '../lib/toast.svelte';
  import { t } from '../lib/i18n.svelte';
</script>

{#if toast.visible}
  <div
    class="toast"
    role="status"
    aria-live="polite"
    title={t('点击复制这条提示')}
    onclick={() => copyText(toast.msg, t('已复制'))}
  >
    {toast.msg}
  </div>
{/if}
