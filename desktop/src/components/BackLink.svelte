<script lang="ts">
  import { HugeiconsIcon } from '@hugeicons/svelte';
  import { icons, ICON_SIZE } from '../lib/icons';
  import { router, back } from '../lib/router.svelte';
  import { t } from '../lib/i18n.svelte';

  const show = $derived(router.history.length > 0);
</script>

{#if show}
  <button
    class="backlink"
    onclick={() => back()}
    title={t('返回上一级')}
    aria-label={t('返回上一级')}
  >
    <HugeiconsIcon icon={icons.back} size={ICON_SIZE.inline} />
    {t('返回')}
  </button>
{/if}
