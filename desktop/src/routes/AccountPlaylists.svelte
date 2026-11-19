<script lang="ts">
  import ErrorNotice from '../components/ErrorNotice.svelte';
  import { onMount } from 'svelte';
  import { HugeiconsIcon } from '@hugeicons/svelte';
  import { api, type PlaylistRef } from '../lib/api';
  import { icons, ICON_SIZE } from '../lib/icons';
  import { account } from '../lib/account.svelte';
  import { go } from '../lib/router.svelte';
  import { openMenuAt } from '../lib/contextmenu.svelte';
  import { copyText, showToast } from '../lib/toast.svelte';
  import BackLink from '../components/BackLink.svelte';
  import PlaylistsSkeleton from '../components/PlaylistsSkeleton.svelte';
  import ImportQueue from '../components/ImportQueue.svelte';
  import { enqueueImport } from '../lib/importQueue.svelte';
  import { delayedVisible } from '../lib/loading.svelte';
  import { t } from '../lib/i18n.svelte';

  let playlists = $state<PlaylistRef[]>([]);
  let plLoading = $state(true);
  let err = $state('');

  const skel = delayedVisible(() => plLoading);

  let s3On = $state(false);
  let importPl = $state<PlaylistRef | null>(null);
  let importTarget = $state('');

  async function loadPlaylists() {
    if (!account.uid) {
      plLoading = false;
      return;
    }
    plLoading = true;
    err = '';
    try {
      playlists = await api.userPlaylists(account.provider, account.uid, 100);
    } catch (e) {
      err = String(e);
      playlists = [];
    } finally {
      plLoading = false;
    }
  }

  function openImport(pl: PlaylistRef) {
    importPl = pl;
    importTarget = pl.name;
  }

  function closeImport() {
    importPl = null;
  }

  function startImport() {
    const pl = importPl;
    if (!pl) return;
    if (enqueueImport(pl, importTarget)) {
      showToast(t('已加入导入队列'));
      importPl = null;
    }
  }

  $effect(() => {
    account.uid;
    loadPlaylists();
  });

  onMount(() => {
    api
      .settingsGet()
      .then((s) => (s3On = !!s.s3_enabled && !!s.s3_bucket))
      .catch(() => (s3On = false));
  });
</script>

<div class="page">
  <BackLink />
  <h1>{t('账号歌单')}</h1>

  {#if err}<ErrorNotice text={err} />{/if}

  <ImportQueue />

  {#if !account.uid}
    <div class="empty">
      <div class="big" aria-hidden="true">
        <HugeiconsIcon icon={icons.account} size={ICON_SIZE.empty} />
      </div>
      <p>{t('还没有登录')}</p>
      <button class="primary btn-ico" onclick={() => go({ name: 'account' })}>{t('去登录')}</button>
    </div>
  {:else if !s3On}
    <div class="acct-hint">{t('登录只用于把平台歌单导入网盘。先到「网盘」页启用网盘配置。')}</div>
  {/if}

  {#if account.uid}
    {#if skel.visible}
      <PlaylistsSkeleton rows={6} withIcon={s3On} />
    {:else if plLoading}
      <!-- 等骨架屏延迟 -->
    {:else if playlists.length === 0}
      <div class="muted small">{t('这个账号还没有歌单')}</div>
    {:else}
      <div class="pllist wide">
        {#each playlists as pl (pl.id)}
          <div
            class="plrow"
            role="group"
            oncontextmenu={(e) => {
              e.preventDefault();
              e.stopPropagation();
              openMenuAt(e.clientX, e.clientY, [
                {
                  label: t('打开歌单'),
                  icon: icons.playlist,
                  run: () =>
                    go({
                      name: 'playlist',
                      provider: pl.provider,
                      playlistId: pl.id,
                      title: pl.name,
                    }),
                },
                ...(s3On
                  ? [
                      {
                        label: t('一键导入到网盘'),
                        icon: icons.cloud,
                        run: () => openImport(pl),
                      },
                    ]
                  : []),
                { sep: true },
                {
                  label: t('复制歌单 ID'),
                  icon: icons.link,
                  run: () => copyText(pl.id, t('已复制歌单 ID')),
                },
              ]);
            }}
          >
            <button
              class="plopen"
              onclick={() =>
                go({ name: 'playlist', provider: pl.provider, playlistId: pl.id, title: pl.name })}
            >
              <span class="plname">{pl.name}</span>
              <span class="plnum">{t('{n} 首', { n: pl.track_count })}</span>
            </button>
            {#if s3On}
              <button
                class="plicon"
                title={t('一键导入到网盘')}
                aria-label={t('把歌单 {name} 导入到网盘', { name: pl.name })}
                onclick={() => openImport(pl)}
              >
                <HugeiconsIcon icon={icons.cloud} size={ICON_SIZE.inline} />
              </button>
            {/if}
          </div>
        {/each}
      </div>
    {/if}
  {/if}
</div>

{#if importPl}
  <div
    class="modal-mask"
    role="presentation"
    onclick={(e) => {
      if (e.target === e.currentTarget) closeImport();
    }}
  >
    <div class="modal" role="dialog" aria-modal="true" aria-label={t('导入歌单到网盘')}>
      <div class="modal-head">
        <div>
          <h2>{t('导入到网盘')}</h2>
          <p class="hint">
            {t('{name} · {n} 首 · 逐首下载后上传', {
              name: importPl.name,
              n: importPl.track_count
            })}
          </p>
        </div>
        <button class="icon" onclick={closeImport} aria-label={t('关闭')}>
          <HugeiconsIcon icon={icons.close} size={ICON_SIZE.inline} />
        </button>
      </div>

      <div class="field">
        <div class="lbl">{t('网盘歌单（目标目录）')}</div>
        <input
          bind:value={importTarget}
          placeholder={t('目标歌单名称')}
          spellcheck="false"
        />
        <p class="hint" style="margin-top:8px">
          {t('文件会存到')} <code>{t('前缀/歌单名/')}</code> {t(
            '下，包含内嵌封面的音频、同名 .lrc 与封面图。'
          )}
        </p>
        <p class="hint" style="margin-top:6px">
          {t('加入队列后可以直接关掉弹窗，不需要在这里等；进度和结果在页面顶部的「导入队列」里看。')}
        </p>
      </div>

      <div class="modal-actions">
        <button class="mini" onclick={closeImport}>{t('关闭')}</button>
        <button
          class="primary btn-ico"
          onclick={startImport}
          disabled={!importTarget.trim()}
        >
          <HugeiconsIcon icon={icons.cloud} size={ICON_SIZE.inline} />
          {t('加入导入队列')}
        </button>
      </div>
    </div>
  </div>
{/if}
