<script lang="ts">
  import { isCloudProvider } from '../lib/config.svelte';
  import ErrorNotice from '../components/ErrorNotice.svelte';
  import { HugeiconsIcon } from '@hugeicons/svelte';
  import {
    api,
    coverUrl,
    fmtDuration,
    formatLabel,
    isBlocked,
    qualityLabel,
    type Quality,
    type QualityCapability,
    type Track,
    type TrackDetail,
    type TrackQualities,
  } from '../lib/api';
  import { icons, ICON_SIZE } from '../lib/icons';
  import { playTrack } from '../lib/player.svelte';
  import { router } from '../lib/router.svelte';
  import { openMenuAt } from '../lib/contextmenu.svelte';
  import { requestDownload } from '../lib/download.svelte';
  import { copyText } from '../lib/toast.svelte';
  import { delayedVisible } from '../lib/loading.svelte';
  import { qualityChoices } from '../lib/quality';
  import { player } from '../lib/player.svelte';
  import { t } from '../lib/i18n.svelte';

  let track = $derived(router.route.name === 'track' ? (router.route.track as Track) : null);
  let detail = $state<TrackDetail | null>(null);
  let loading = $state(true);
  let err = $state('');
  let qualityMsg = $state('');
  let probing = $state(false);
  let caps = $state<QualityCapability[]>([]);
  let availability = $state<TrackQualities | null>(null);

  const choices = $derived(qualityChoices(track, caps, availability, player.quality));

  const lyricsSkel = delayedVisible(() => loading);
  const LYRIC_SK_WIDTHS = [58, 74, 46, 82, 64, 70, 52, 78];

  $effect(() => {
    const trk = track;
    if (!trk) return;
    detail = null;
    err = '';
    qualityMsg = '';
    availability = null;
    loading = true;
    api
      .detail(trk.provider, trk)
      .then((d) => (detail = d))
      .catch((e) => (err = String(e)))
      .finally(() => (loading = false));

    api.qualityCapabilities().then((v) => (caps = v)).catch(() => {});
    const fromTrack = trk.available_qualities ?? [];
    if (fromTrack.length) {
      availability = {
        available: fromTrack,
        has_advanced: !!trk.has_advanced,
        known: true,
      };
    }
    api
      .trackQualities(trk)
      .then((q) => (availability = q))
      .catch(() => {
        availability = {
          available: fromTrack,
          has_advanced: !!trk.has_advanced,
          known: fromTrack.length > 0,
        };
      });
  });

  function coverMenu(e: MouseEvent) {
    if (!track) return;
    e.preventDefault();
    e.stopPropagation();
    openMenuAt(e.clientX, e.clientY, [
      {
        label: t('下载这首歌（含歌词与封面）'),
        icon: icons.download,
        disabled: isBlocked(track.availability) || isCloudProvider(track.provider),
        run: () => requestDownload([track as Track]),
      },
      { sep: true },
      {
        label: t('复制歌曲 ID'),
        icon: icons.link,
        run: () => copyText(track!.id, t('已复制歌曲 ID')),
      },
    ]);
  }

  async function probe(q: Quality) {
    if (!track) return;
    probing = true;
    qualityMsg = '';
    try {
      const r = await api.resolve(track, q);
      const actual = formatLabel(r.format) || t(qualityLabel(r.quality));
      const size = r.bytes ? (r.bytes / 1048576).toFixed(1) + ' MB' : t('大小未知');
      const degraded = r.degraded ? t('（已降级）') : '';
      const unverified = r.verified ? '' : t('（未校验）');
      const via =
        r.via === 'trackmedia' ? t('资源链路') : r.via === 'anti' ? t('直连') : r.via;
      qualityMsg = `✔ ${actual}${unverified}${degraded} · ${size} · ${via}`;
    } catch (e) {
      qualityMsg = t('✘ {quality} 不可用（{err}）', {
        quality: t(qualityLabel(q)),
        err: String(e)
      });
    } finally {
      probing = false;
    }
  }
</script>

{#if track}
<div class="page detail">
  <button class="back" onclick={() => history.back()} aria-label={t('返回')}>
    <HugeiconsIcon icon={icons.back} size={ICON_SIZE.inline} />
    {t('返回')}
  </button>

  <div class="head">
    {#if track.cover}
      <img class="cover" src={coverUrl(track.cover, 500)} alt="" oncontextmenu={coverMenu} />
    {:else}
      <div class="cover ph" aria-hidden="true" oncontextmenu={coverMenu}>
        <HugeiconsIcon icon={icons.music} size={ICON_SIZE.empty} />
      </div>
    {/if}
    <div class="info">
      <h1>{track.title}</h1>
      <div class="line">
        <span class="trunc">
          {track.artist}
        </span>
        {#if track.album}
          <span class="dot">·</span>
          <span class="trunc">
            {track.album}
          </span>
        {/if}
        {#if track.duration_sec}
          <span class="dot">·</span>
          <span>{fmtDuration(track.duration_sec)}</span>
        {/if}
      </div>
      <div class="actions">
        <button
          class="primary"
          disabled={isBlocked(track.availability)}
          onclick={() => playTrack(track)}
          aria-label={t('播放')}
        >
          <HugeiconsIcon icon={icons.play} size={ICON_SIZE.inline} />
          {isBlocked(track.availability) ? t('不可播放') : t('播放')}
        </button>
        {#each choices as c (c.value)}
          <button
            class:on={c.current}
            onclick={() => probe(c.value)}
            disabled={probing || c.disabled}
          >
            {t('测 {label}', { label: c.label })}
          </button>
        {/each}
      </div>
      {#if qualityMsg}
        <div class="qmsg">{qualityMsg}</div>
      {/if}
      {#if track.availability === 'vip_only'}
        <div class="note">
          <strong>{t('会员曲目')}</strong>
          {t('这条信息来自搜索接口的')} <code>PAY</code> {t(
            '字段。本客户端会通过资源管理链路取直链， 未登录也能完整播放；上面的探测器可以直接验证每一档实际能拿到什么格式。'
          )}
        </div>
      {:else}
        <div class="note">
          {t('未登录状态下，酷我服务端对会员专享曲目可能只下发约 11 秒的占位片段。')}
        </div>
      {/if}
    </div>
  </div>

  {#if lyricsSkel.visible}
    <div class="lyrics sk-lyrics" role="status" aria-label={t('加载歌词')}>
      {#each LYRIC_SK_WIDTHS as w}
        <span class="sk sk-lyric-line" style="width:{w}%"></span>
      {/each}
    </div>
  {:else if !loading}
    {#if err}
      <div class="muted">{t('歌词获取失败（详情接口易限流，不影响播放）')}</div>
      <ErrorNotice text={err} compact />
    {:else if detail && detail.lyrics.length}
      <div class="lyrics">
        {#each detail.lyrics as l}
          <div class="ly">{l.text}</div>
        {/each}
      </div>
    {:else}
      <div class="muted">{t('暂无歌词')}</div>
    {/if}
  {/if}
</div>
{/if}
