import { api, type LocalFolder, type Track } from './api';

export const FAVORITES_FOLDER = '喜欢';
const KEY = 'tinymusic:local-folders';

function loadFolders(): LocalFolder[] {
  try {
    const saved: unknown = JSON.parse(localStorage.getItem(KEY) ?? '[]');
    if (!Array.isArray(saved)) return [];
    return saved.filter((folder) =>
      typeof folder?.id === 'string' &&
      typeof folder?.name === 'string' &&
      Array.isArray(folder?.tracks) &&
      folder.tracks.every((track: unknown) => typeof track === 'string')
    );
  } catch {
    return [];
  }
}

export const localFolders = $state({
  items: [{ id: FAVORITES_FOLDER, name: FAVORITES_FOLDER, tracks: [] }] as LocalFolder[],
  ready: false,
});
let pendingUpdate = Promise.resolve();
let initialization: Promise<void> | undefined;

export const localTrackKey = (track: Track) => JSON.stringify([track.provider, track.id]);

export function initializeLocalFolders() {
  initialization ??= api.localMusicMigrate(loadFolders()).then((folders) => {
    localFolders.items = folders;
    localFolders.ready = true;
  }).catch((error) => {
    initialization = undefined;
    throw error;
  });
  return initialization;
}

function updateFolders(load: () => Promise<LocalFolder[]>) {
  const update = pendingUpdate.then(async () => {
    await initializeLocalFolders();
    localFolders.items = await load();
  });
  pendingUpdate = update.catch(() => {});
  return update;
}

export function refreshLocalFolders() {
  return updateFolders(api.localMusicFolders);
}

export async function createLocalFolder(input: string) {
  const name = input.trim();
  await updateFolders(() => api.localMusicCreateFolder(name));
  return name;
}

export function setLocalFolderTrack(id: string, track: Track, included: boolean) {
  return updateFolders(() => api.localMusicSetFolderTrack(id, track.id, included));
}

export function isFavorite(track: Track) {
  return localFolders.items.find(({ id }) => id === FAVORITES_FOLDER)?.tracks.includes(localTrackKey(track)) ?? false;
}

export function canFavorite(track: Track) {
  return ['local', 's3', 'webdav'].includes(track.provider);
}

export function toggleFavorite(track: Track) {
  return updateFolders(() => api.localMusicSetFavorite(track, !isFavorite(track)));
}

export function renameLocalFolder(id: string, name: string) {
  return updateFolders(() => api.localMusicRenameFolder(id, name));
}

export function deleteLocalFolder(id: string) {
  return updateFolders(() => api.localMusicDeleteFolder(id));
}
