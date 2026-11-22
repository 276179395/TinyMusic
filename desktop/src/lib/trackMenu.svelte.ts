/**
 * 曲目 / 专辑的右键菜单构造器。
 *
 * 菜单项本身只描述「做什么」，渲染统一交给 <ContextMenu />。
 */
import { isBlocked, type Track } from './api';
import { icons } from './icons';
import { openMenuAt, type MenuEntry } from './contextmenu.svelte';
import { playTrack, playNext, addToQueue, inQueue } from './player.svelte';
import { requestDownload } from './download.svelte';
import { go } from './router.svelte';
import { canFavorite, isFavorite, localFolders, toggleFavorite } from './localFolders.svelte';
import { showToast } from './toast.svelte';
import { t } from './i18n.svelte';

export interface TrackMenuOptions {
  /** 从哪个列表点出来的，播放时把整个列表作为队列 */
  queue?: Track[];
  /** 额外插入到末尾的菜单项（如播放列表里的「从列表移除」） */
  extra?: MenuEntry[];
}

/** 歌曲右键菜单：播放 / 下一首 / 加入列表 / 下载 / 喜欢 / 详情 / 歌手 / 专辑 */
export async function openTrackMenu(
  e: MouseEvent,
  track: Track,
  opts: TrackMenuOptions = {}
) {
  e.preventDefault();
  e.stopPropagation();
  const x = e.clientX;
  const y = e.clientY;

  const blocked = isBlocked(track.availability);
  const local = track.provider === 'local';
  const fav = isFavorite(track);

  const items: MenuEntry[] = [
    {
      label: t('播放'),
      icon: icons.play,
      disabled: blocked,
      run: () => {
        void playTrack(track, opts.queue);
      },
    },
    {
      label: t('下一首播放'),
      icon: icons.next,
      run: () => {
        playNext(track);
        showToast(t('已设为下一首'));
      },
    },
    {
      label: inQueue(track) ? t('已在播放列表') : t('添加到播放列表'),
      icon: icons.queue,
      disabled: inQueue(track),
      run: () => {
        if (addToQueue(track)) showToast(t('已加入播放列表'));
      },
    },
    { sep: true },
    ...(local ? [] : [{
      label: t('下载（含歌词与封面）'),
      icon: icons.download,
      disabled: blocked,
      run: () => {
        void requestDownload([track]);
      },
    }]),
    ...(canFavorite(track)
      ? [{
          label: fav ? t('取消喜欢') : t('添加到喜欢'),
          icon: icons.favorite,
          disabled: !localFolders.ready,
          run: async () => {
            try {
              await toggleFavorite(track);
            } catch (error) {
              showToast(String(error));
            }
          },
        }]
      : []),
    ...(!local ? [{ sep: true } as const] : []),
    {
      label: t('查看歌曲详情'),
      icon: icons.music,
      run: () => go({ name: 'track', track }),
    },
    ...(opts.extra ?? []),
  ];

  openMenuAt(x, y, items);
}
