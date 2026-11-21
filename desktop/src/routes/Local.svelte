<script lang="ts">
  import { HugeiconsIcon } from '@hugeicons/svelte';
  import { open } from '@tauri-apps/plugin-dialog';
  import ErrorNotice from '../components/ErrorNotice.svelte';
  import { api, type LocalMusicItem, type Track } from '../lib/api';
  import { icons, ICON_SIZE } from '../lib/icons';
  import { t } from '../lib/i18n.svelte';
  import { player, playTrack, removeAt } from '../lib/player.svelte';
  import { openTrackMenu } from '../lib/trackMenu.svelte';
  import { openMenuAt } from '../lib/contextmenu.svelte';
  import { initializeLocalFolders, localFolders, localTrackKey, setLocalFolderTrack } from '../lib/localFolders.svelte';

  let { folderId }: { folderId?: string } = $props();
  let items = $state<LocalMusicItem[]>([]);
  const folder = $derived(localFolders.items.find((item) => item.id === folderId));
  const visibleItems = $derived(folderId === undefined
    ? items
    : items.filter(({ track }) => folder?.tracks.includes(localTrackKey(track))));
  const tracks = $derived(visibleItems.map(({ track }) => track));
  let loading = $state(true);
  let busy = $state(false);
  let error = $state('');
  let loadError = $state('');
  let refreshInFlight = false;

  async function refresh() {
    if (refreshInFlight) return;
    refreshInFlight = true;
    try {
      await initializeLocalFolders();
      items = await api.localMusicList();
      loadError = '';
    } catch (err) {
      loadError = String(err);
    } finally {
      loading = false;
      refreshInFlight = false;
    }
  }

  $effect(() => {
    void refresh();
    const timer = window.setInterval(refresh, 1000);
    return () => window.clearInterval(timer);
  });

  async function addMusic(directory: boolean) {
    busy = true;
    error = '';
    try {
      const defaultPath = await api.localMusicInputDir();
      const selection = await open({
        defaultPath,
        directory,
        multiple: !directory,
        filters: directory ? undefined : [{ name: t('音频文件'), extensions: ['mp3', 'flac', 'm4a', 'aac', 'ogg', 'wav'] }],
      });
      if (selection) {
        const added = await api.localMusicAdd(Array.isArray(selection) ? selection : [selection]);
        if (!added.length) error = t('所选文件夹中没有支持的音频文件');
        await refresh();
      }
    } catch (err) {
      error = String(err);
    } finally {
      busy = false;
    }
  }

  async function remove(track: Track) {
    if (busy) return;
    busy = true;
    error = '';
    try {
      if (folder) {
        await setLocalFolderTrack(folder.id, track, false);
        return;
      }
      await api.localMusicRemove(track.id);
      await refresh();
      const index = player.queue.findIndex(
        (item) => item.provider === track.provider && item.id === track.id
      );
      if (index >= 0) removeAt(index);
    } catch (err) {
      error = String(err);
    } finally {
      busy = false;
    }
  }

  function chooseFolder(event: MouseEvent, track: Track) {
    const button = (event.currentTarget as HTMLButtonElement).getBoundingClientRect();
    openMenuAt(button.left, button.bottom, localFolders.items.map((item) => {
      const included = item.tracks.includes(localTrackKey(track));
      return {
        label: item.name,
        selected: included,
        run: async () => {
          try {
            await setLocalFolderTrack(item.id, track, !included);
          } catch (err) {
            error = String(err);
          }
        },
      };
    }));
  }
</script>

<div class="page">
  <div class="summary">
    {folder?.name ?? t('本地音乐')}
    {#if !folder}
      <button class="mini primary" onclick={() => addMusic(false)} disabled={loading || busy}>
        <HugeiconsIcon icon={icons.folder} size={ICON_SIZE.inline} />
        {t('添加音乐文件')}
      </button>
      <button class="mini" onclick={() => addMusic(true)} disabled={loading || busy}>
        <HugeiconsIcon icon={icons.folder} size={ICON_SIZE.inline} />
        {t('添加文件夹')}
      </button>
    {/if}
    {#if tracks.length}
      <button class="mini" onclick={() => playTrack(tracks[0], tracks)} disabled={busy}>
        <HugeiconsIcon icon={icons.play} size={ICON_SIZE.inline} />
        {t('播放全部')}
      </button>
    {/if}
  </div>

  {#if error || loadError}
    <ErrorNotice text={error || loadError} />
  {/if}
  {#if loading}
    <div class="empty" role="status">{t('加载中…')}</div>
  {:else if tracks.length === 0}
    <div class="empty">
      <div class="big" aria-hidden="true"><HugeiconsIcon icon={icons.music} size={32} /></div>
      {folder ? t('在「本地」选择曲目旁的收藏夹按钮来添加歌曲') : t('添加本机上的音频文件以开始播放')}
    </div>
  {:else}
    <ul aria-label={folder?.name ?? t('本地音乐')}>
      {#each visibleItems as { track, source } (localTrackKey(track))}
        {@const current = player.current?.provider === track.provider && player.current.id === track.id}
        <li>
          <button
            class="song"
            class:current
            aria-current={current ? 'true' : undefined}
            title={track.id}
            disabled={busy}
            onclick={() => playTrack(track, tracks)}
            oncontextmenu={(event) => openTrackMenu(event, track, { queue: tracks })}
          >
            <HugeiconsIcon icon={current && player.playing ? icons.music : icons.play} size={ICON_SIZE.inline} />
            <span>{track.title}</span>
            {#if source !== 'imported'}
              <small>{t('已下载')}</small>
            {/if}
          </button>
          {#if localFolders.items.length && !folder}
            <button class="song-action" title={t('选择收藏夹')} aria-label={t('选择收藏夹')}
              disabled={busy} onclick={(event) => chooseFolder(event, track)}>
              <HugeiconsIcon icon={icons.star} size={ICON_SIZE.inline} />
            </button>
          {/if}
          {#if folder || source === 'imported'}
            <button
            class="song-action delete"
            title={t(folder ? '从收藏夹移除 {title}' : '从本地音乐移除 {title}', { title: track.title })}
            aria-label={t(folder ? '从收藏夹移除 {title}' : '从本地音乐移除 {title}', { title: track.title })}
            disabled={busy}
            onclick={() => remove(track)}
          >
              <HugeiconsIcon icon={icons.trash} size={ICON_SIZE.inline} />
            </button>
          {/if}
        </li>
      {/each}
    </ul>
  {/if}
</div>

<style>
  ul {
    list-style: none;
    padding: 0;
  }
  li {
    display: flex;
    align-items: center;
    gap: 8px;
    border-radius: 8px;
  }
  li:hover,
  li:focus-within {
    background: var(--hover);
  }
  .song {
    display: flex;
    align-items: center;
    gap: 12px;
    flex: 1;
    min-width: 0;
    min-height: 44px;
    padding: 0 12px;
    color: inherit;
    text-align: left;
  }
  .song.current {
    color: var(--brand);
  }
  .song span {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .song small {
    color: var(--fg2);
    white-space: nowrap;
  }
  .song-action {
    display: grid;
    place-items: center;
    min-width: 44px;
    min-height: 44px;
    color: var(--fg2);
  }
  .song-action:hover:enabled {
    color: var(--fg);
  }
  .song-action.delete {
    color: var(--danger);
  }
  .song-action.delete:hover:enabled {
    filter: brightness(1.2);
  }
</style>
