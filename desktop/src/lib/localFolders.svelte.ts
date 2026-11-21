import { api, type LocalFolder, type Track } from './api';

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

export const localFolders = $state({ items: [] as LocalFolder[] });
let initialization: Promise<void> | undefined;

export const localTrackKey = (track: Track) => JSON.stringify([track.provider, track.id]);

export function initializeLocalFolders() {
  initialization ??= api.localMusicMigrate(loadFolders()).then((folders) => {
    localFolders.items = folders;
  }).catch((error) => {
    initialization = undefined;
    throw error;
  });
  return initialization;
}

export async function refreshLocalFolders() {
  await initializeLocalFolders();
  localFolders.items = await api.localMusicFolders();
}

export async function createLocalFolder(input: string) {
  const name = input.trim();
  await initializeLocalFolders();
  localFolders.items = await api.localMusicCreateFolder(name);
  return name;
}

export async function setLocalFolderTrack(id: string, track: Track, included: boolean) {
  localFolders.items = await api.localMusicSetFolderTrack(id, track.id, included);
}

export async function renameLocalFolder(id: string, name: string) {
  localFolders.items = await api.localMusicRenameFolder(id, name);
}

export async function deleteLocalFolder(id: string) {
  localFolders.items = await api.localMusicDeleteFolder(id);
}
