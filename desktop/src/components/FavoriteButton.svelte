<script lang="ts">
  import { HugeiconsIcon } from '@hugeicons/svelte';
  import type { Track } from '../lib/api';
  import { icons, ICON_SIZE } from '../lib/icons';
  import { t } from '../lib/i18n.svelte';
  import { canFavorite, isFavorite, localFolders, toggleFavorite } from '../lib/localFolders.svelte';
  import { showToast } from '../lib/toast.svelte';

  let { track }: { track: Track } = $props();
  let busy = $state(false);
  const favorite = $derived(isFavorite(track));

  async function toggle() {
    busy = true;
    try {
      await toggleFavorite(track);
    } catch (error) {
      showToast(String(error));
    } finally {
      busy = false;
    }
  }
</script>

{#if canFavorite(track)}
  <button
    type="button"
    class="favorite"
    class:filled={favorite}
    title={favorite ? t('取消喜欢') : t('添加到喜欢')}
    aria-label={t('喜欢')}
    aria-pressed={favorite}
    disabled={!localFolders.ready || busy}
    onclick={toggle}
  >
    <HugeiconsIcon icon={icons.favorite} size={ICON_SIZE.inline} aria-hidden="true" />
  </button>
{/if}

<style>
  .favorite {
    display: grid;
    place-items: center;
    flex: 0 0 auto;
    width: 36px;
    height: 36px;
    border-radius: var(--r-sm);
    color: var(--fg);
  }
  .favorite:hover:enabled {
    background: var(--hover);
  }
  .favorite.filled {
    color: var(--danger);
  }
  .favorite.filled :global(svg path) {
    fill: currentColor;
  }
</style>
