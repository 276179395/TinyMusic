import type { Track } from './api';

export type Route =
  | { name: 'track'; track: Track }
  | { name: 'downloads' }
  | { name: 'local'; folderId?: string }
  | { name: 'cloud' }
  | { name: 'settings' };

/** 侧边栏一级页面：进入时清空返回栈 */
const TOP_LEVEL: ReadonlySet<Route['name']> = new Set([
  'downloads',
  'local',
  'cloud',
  'settings'
]);

export const router = $state<{ route: Route; history: Route[] }>({
  route: { name: 'cloud' },
  history: []
});

function sameRoute(a: Route, b: Route): boolean {
  if (a.name !== b.name) return false;
  if (a.name === 'local' && b.name === 'local') return a.folderId === b.folderId;
  if (a.name === 'track' && b.name === 'track') return a.track.provider === b.track.provider && a.track.id === b.track.id;
  return true;
}

export function go(r: Route) {
  const current = router.route;
  if (sameRoute(current, r)) return;

  if (TOP_LEVEL.has(r.name)) {
    router.history = [];
  } else {
    router.history = [...router.history, current];
  }
  router.route = r;
  scrollMainTop();
}

/** 返回上一级；没有可返回的页面时返回 false */
export function back(): boolean {
  const prev = router.history.pop();
  if (!prev) return false;
  router.route = prev;
  scrollMainTop();
  return true;
}

export function canBack(): boolean {
  return router.history.length > 0;
}

/** 把主滚动区域拉回顶部（切页、换搜索结果时都需要） */
export function scrollMainTop() {
  requestAnimationFrame(() => {
    document.querySelector('main')?.scrollTo({ top: 0, behavior: 'auto' });
  });
}
