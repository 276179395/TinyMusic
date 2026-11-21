<script lang="ts">
  import ErrorNotice from '../components/ErrorNotice.svelte';
  import { onMount } from 'svelte';
  import { HugeiconsIcon } from '@hugeicons/svelte';
  import { api, type Settings, type Quality, type QualityCapability } from '../lib/api';
  import { icons, ICON_SIZE } from '../lib/icons';
  import { refreshAppCfg } from '../lib/config.svelte';
  import { clearQueue, player, setPreferredQuality } from '../lib/player.svelte';
  import { initializeLocalFolders, refreshLocalFolders } from '../lib/localFolders.svelte';
  import {
    theme, setTheme, themeBackground, setThemeBackground, importThemeImage,
    type ThemeMode, type ThemeBackground,
  } from '../lib/theme.svelte';
  import { glass, setGlassEnabled } from '../lib/glass.svelte';
  import { getVersion } from '@tauri-apps/api/app';
  import { check } from '@tauri-apps/plugin-updater';
  import ProgressBar from '../components/ProgressBar.svelte';
  import { relaunch } from '@tauri-apps/plugin-process';
  import { ask, open as openDialog } from '@tauri-apps/plugin-dialog';
  import { slide } from 'svelte/transition';
  import { pendingUpdate, setPendingUpdate, updateState } from '../lib/update.svelte';
  import {
    EQ_PRESETS,
    currentPresetName,
    equalizer,
    openEqualizer,
    setEqualizerEnabled
  } from '../lib/equalizer.svelte';
  import { showToast } from '../lib/toast.svelte';
  import { themePacks, importThemePack, selectThemePack } from '../lib/themePacks.svelte';
  import { t, i18n, setLanguage, type LanguageSetting } from '../lib/i18n.svelte';

  /** 关掉动画就别展开收起，直接跳 */
  const REDUCE_MOTION = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // ---- 更新 ----
  let appVersion = $state('');
  let updMsg = $state('');
  let updErr = $state('');
  let updBusy = $state(false);
  let progress = $state(0);

  /** 后台检查已经找到新版时这里直接拿得到句柄，不用再点一次「检查更新」 */
  const pending = $derived(updateState.version ? pendingUpdate() : null);

  $effect(() => {
    getVersion().then((v) => (appVersion = v)).catch(() => {});
  });

  async function checkUpdate() {
    updBusy = true;
    updErr = '';
    updMsg = '';
    try {
      const u = await check();
      setPendingUpdate(u ?? null);
      updMsg = u
        ? t('发现新版本 {version}', { version: u.version })
        : t('已经是最新版本');
    } catch (e) {
      updErr = t('检查失败：{err}', { err: String(e) });
    } finally {
      updBusy = false;
    }
  }

  async function doUpdate() {
    const u = pending;
    if (!u) return;
    updBusy = true;
    updErr = '';
    progress = 0;
    let total = 0;
    let got = 0;
    try {
      await u.downloadAndInstall((ev) => {
        if (ev.event === 'Started') {
          total = ev.data.contentLength ?? 0;
        } else if (ev.event === 'Progress') {
          got += ev.data.chunkLength;
          progress = total > 0 ? Math.round((got / total) * 100) : 0;
        } else if (ev.event === 'Finished') {
          progress = 100;
        }
      });
      updMsg = t('安装完成，正在重启…');
      await relaunch();
    } catch (e) {
      updErr = t('更新失败：{err}', { err: String(e) });
      updBusy = false;
    }
  }

  // ---- 设置（改动即保存） ----
  let s = $state<Settings>({
    download_dir: '',
    music_dir: '',
    cache_dir: '',
    default_quality: 'super',
    settings_version: 2,
    concurrency: 2,
    s3_enabled: false,
    s3_endpoint: '',
    s3_region: 'us-east-1',
    s3_bucket: '',
    s3_access_key: '',
    s3_secret_key: '',
    s3_prefix: 'TinyMusic',
    s3_path_style: false,
    close_to_tray: true,
    webdav_enabled: false,
    webdav_endpoint: '',
    webdav_root: 'TinyMusic',
    webdav_username: '',
    webdav_password: '',
  });
  let loaded = $state(false);
  let err = $state('');
  let savedHint = $state(false);
  let saveTimer: ReturnType<typeof setTimeout> | null = null;
  let caps = $state<QualityCapability[]>([]);

  onMount(async () => {
    try {
      const v = await api.settingsGet();
      s = v;
      loaded = true;
    } catch (e) {
      err = String(e);
      loaded = true;
    }
    try {
      caps = await api.qualityCapabilities();
    } catch {
      caps = [];
    }
  });

  async function saveNow() {
    if (!loaded) return;
    try {
      await api.settingsSet($state.snapshot(s) as Settings);
      setPreferredQuality(s.default_quality);
      await refreshAppCfg();
      savedHint = true;
      setTimeout(() => (savedHint = false), 1500);
    } catch (e) {
      err = String(e);
    }
  }

  /** 调系统目录选择框；取消或非 Tauri 环境（浏览器调试）就原样不动 */
  async function pickDir(field: 'cache_dir') {
    try {
      const picked = await openDialog({
        directory: true,
        multiple: false,
        title: t('选择缓存目录'),
        defaultPath: s[field] || undefined
      });
      if (typeof picked === 'string' && picked) {
        s[field] = picked;
        await saveNow();
      }
    } catch {
      /* 浏览器里没有原生对话框，忽略 */
    }
  }

  let musicDirectoryBusy = $state(false);

  async function chooseMusicDirectory(copy: boolean) {
    musicDirectoryBusy = true;
    err = '';
    try {
      await initializeLocalFolders();
      const picked = await openDialog({
        directory: true,
        multiple: false,
        title: t(copy ? '选择用于复制音乐库的空目录' : '打开音乐库目录'),
        defaultPath: s.music_dir || undefined,
      });
      if (typeof picked !== 'string' || picked === s.music_dir) return;
      if (copy) {
        s.music_dir = await api.localMusicCopyLibrary(picked);
      } else {
        await api.settingsSet({ ...$state.snapshot(s), music_dir: picked });
        s.music_dir = picked;
        if (player.queue.some((track) => track.provider === 'local')) clearQueue();
      }
      await refreshLocalFolders();
      showToast(t('音乐库目录已更新'));
    } catch (error) {
      err = String(error);
    } finally {
      musicDirectoryBusy = false;
    }
  }

  let cacheClearing = $state(false);

  async function clearPlaybackCache() {
    if (cacheClearing) return;
    cacheClearing = true;
    const cacheDir = s.cache_dir;
    try {
      const confirmed = await ask(t('删除当前缓存目录中的播放缓存？手动下载的文件会保留。'), {
        title: t('清空播放缓存'),
      });
      if (!confirmed) return;
      await api.playbackCacheClear(cacheDir);
      showToast(t('播放缓存已清空'));
    } catch (e) {
      err = String(e);
    } finally {
      cacheClearing = false;
    }
  }

  /** 文本输入用 400ms 防抖，避免每敲一个字都写盘 */
  function scheduleSave() {
    if (saveTimer) clearTimeout(saveTimer);
    saveTimer = setTimeout(() => saveNow(), 400);
  }

  // S3 测试
  let s3Msg = $state('');
  let s3Err = $state('');
  let s3Busy = $state(false);

  async function selectCloud(event: Event) {
    const protocol = (event.currentTarget as HTMLSelectElement).value;
    s.s3_enabled = protocol === 's3';
    s.webdav_enabled = protocol === 'webdav';
    s3Msg = '';
    s3Err = '';
    await saveNow();
  }

  async function testCloud() {
    s3Busy = true;
    s3Msg = '';
    s3Err = '';
    try {
      if (saveTimer) clearTimeout(saveTimer);
      await api.settingsSet($state.snapshot(s) as Settings);
      await refreshAppCfg();
      s3Msg = await api.s3Test();
    } catch (e) {
      s3Err = String(e);
    } finally {
      s3Busy = false;
    }
  }

  const themeOptions = $derived<{ value: ThemeMode; label: string }[]>([
    { value: 'auto', label: t('跟随系统') },
    { value: 'dark', label: t('深色') },
    { value: 'light', label: t('浅色') },
    { value: 'custom', label: t('自定义') },
  ]);
  const themePackOptions = $derived([
    { value: '', label: t('应用外观') },
    ...themePacks.items.map((pack) => ({ value: pack.id, label: pack.name })),
  ]);
  const backgroundOptions = $derived<{ value: ThemeBackground; label: string }[]>([
    { value: 'default', label: t('默认背景') },
    { value: 'color', label: t('纯色') },
    { value: 'image', label: t('本地图片') },
  ]);

  let backgroundInput = $state<HTMLInputElement>();
  let backgroundBusy = $state(false);
  let backgroundError = $state('');
  let themePackBusy = $state(false);
  let themePackError = $state('');

  async function chooseThemePack() {
    if (themePackBusy) return;
    themePackBusy = true;
    themePackError = '';
    try {
      const path = await openDialog({
        title: t('导入主题包'),
        filters: [{ name: t('主题包'), extensions: ['zip'] }],
      });
      if (typeof path === 'string') {
        await importThemePack(path);
        showToast(t('主题包已应用'));
      }
    } catch (error) {
      themePackError = error instanceof Error ? error.message : String(error);
    } finally {
      themePackBusy = false;
    }
  }

  function changeThemePack(id: string) {
    themePackError = '';
    try {
      selectThemePack(id);
    } catch {
      themePackError = t('无法保存主题设置');
    }
  }

  function updateBackground(kind: ThemeBackground, color?: string) {
    backgroundError = '';
    try {
      setThemeBackground(kind, color);
    } catch {
      backgroundError = t('无法保存主题设置');
    }
  }

  async function selectBackgroundImage(event: Event) {
    const input = event.currentTarget as HTMLInputElement;
    const file = input.files?.[0];
    input.value = '';
    if (!file) return;
    backgroundError = '';
    backgroundBusy = true;
    try {
      await importThemeImage(file);
    } catch (error) {
      const message = error instanceof Error ? error.message : '';
      backgroundError = message.startsWith('请选择') ? t(message) : t('无法载入或保存背景图片');
    } finally {
      backgroundBusy = false;
    }
  }

  const languageOptions: { v: LanguageSetting; label: string }[] = [
    { v: 'auto', label: '跟随系统' },
    { v: 'zh', label: '简体中文' },
    { v: 'en', label: 'English' }
  ];

  const DEFAULT_QUALITIES: { v: Quality; label: string }[] = [
    { v: 'standard', label: '标准 128k' },
    { v: 'super', label: '高品质 320k' },
    { v: 'lossless', label: '无损 FLAC' },
    { v: 'hires', label: 'Hi-Res' },
    { v: 'atmos', label: '杜比全景声' },
    { v: 'master', label: '母带' },
  ];

  const qualityOptions = $derived(
    caps.length
      ? caps.map((c) => ({ v: c.value, label: t(c.label), disabled: !c.available }))
      : DEFAULT_QUALITIES.map((c) => ({
          ...c,
          label: t(c.label),
          disabled: c.v === 'hires' || c.v === 'atmos' || c.v === 'master',
        }))
  );
</script>

<div class="page settings-page">
  <div class="st-head">
    <h1>{t('设置')}</h1>
    {#if savedHint}<span class="st-saved">{t('已保存')}</span>{/if}
  </div>

  {#if err}<ErrorNotice text={err} />{/if}

  <section class="st-section">
    <div class="st-section-title">{t('外观')}</div>
    <div class="st-card">
      <div class="st-row">
        <div class="st-label">{t('主题')}</div>
        <div class="st-seg" role="group" aria-label={t('主题')}>
          {#each themeOptions as opt (opt.value)}
            <button type="button" class:on={theme.mode === opt.value}
              aria-pressed={theme.mode === opt.value} onclick={() => setTheme(opt.value)}>
              {opt.label}
            </button>
          {/each}
        </div>
      </div>

      {#if theme.mode === 'custom'}
        <div class="st-row">
          <div class="st-label">
            {t('主题包')}
            {#if themePacks.activeId}
              <span class="st-desc">{theme.resolved === 'light' ? t('浅色底板') : t('深色底板')}</span>
            {/if}
          </div>
          <div class="st-control">
            <select class="st-select" aria-label={t('主题包')} value={themePacks.activeId}
              disabled={!themePacks.loaded || themePackBusy}
              onchange={(e) => changeThemePack(e.currentTarget.value)}>
              {#each themePackOptions as opt (opt.value)}
                <option value={opt.value}>{opt.label}</option>
              {/each}
            </select>
            <button type="button" class="st-btn" disabled={!themePacks.loaded || themePackBusy} onclick={chooseThemePack}>
              {themePackBusy ? t('正在载入…') : t('导入主题包')}
            </button>
          </div>
        </div>
        {#if themePackError || themePacks.error}
          <div class="st-row"><ErrorNotice text={themePackError || themePacks.error} /></div>
        {/if}

        {#if !themePacks.activeId}
          <div class="st-row">
            <div class="st-label">{t('自定义背景')}</div>
            <select class="st-select" aria-label={t('自定义背景')} value={themeBackground.kind}
              disabled={backgroundBusy} onchange={(e) => updateBackground(e.currentTarget.value as ThemeBackground)}>
              {#each backgroundOptions as opt (opt.value)}
                <option value={opt.value}>{opt.label}</option>
              {/each}
            </select>
          </div>
          {#if themeBackground.kind === 'color'}
            <div class="st-row">
              <div class="st-label">{t('背景颜色')}</div>
              <div class="st-control">
                <span class="st-value">{themeBackground.color.toUpperCase()}</span>
                <input
                  class="st-color"
                  type="color"
                  aria-label={t('背景颜色')}
                  value={themeBackground.color}
                  onchange={(e) => updateBackground('color', e.currentTarget.value)}
                />
              </div>
            </div>
          {:else if themeBackground.kind === 'image'}
            <div class="st-row">
              <div class="st-label">
                {t('背景图片')}
                {#if themeBackground.image}<span class="st-desc">{themeBackground.image.name}</span>{/if}
              </div>
              <input
                type="file"
                accept="image/jpeg,image/png,image/webp"
                bind:this={backgroundInput}
                onchange={selectBackgroundImage}
                hidden
              />
              <button type="button" class="st-btn" disabled={backgroundBusy} onclick={() => backgroundInput?.click()}>
                {backgroundBusy ? t('正在载入…') : t('选择图片…')}
              </button>
            </div>
          {/if}
          {#if backgroundError}
            <div class="st-row"><ErrorNotice text={backgroundError} /></div>
          {/if}
        {/if}
      {/if}

      <div class="st-row">
        <div class="st-label">{t('语言')}</div>
        <select
          class="st-select"
          aria-label={t('语言')}
          value={i18n.setting}
          onchange={(e) => setLanguage(e.currentTarget.value as LanguageSetting)}
        >
          {#each languageOptions as opt (opt.v)}
            <option value={opt.v}>{t(opt.label)}</option>
          {/each}
        </select>
      </div>

      <div class="st-row">
        <div class="st-label">{t('玻璃材质')}</div>
        <span class="st-value">{glass.mode === 'glass' ? t('已开启') : t('已关闭')}</span>
        <label
          class="st-switch"
          title={glass.forced
            ? t('当前系统不支持毛玻璃')
            : glass.mode === 'glass'
              ? t('关闭毛玻璃（改用边框材质）')
              : t('开启毛玻璃')}
        >
          <input
            type="checkbox"
            aria-label={t('开启毛玻璃')}
            checked={glass.mode === 'glass'}
            disabled={glass.forced}
            onchange={(e) => setGlassEnabled(e.currentTarget.checked)}
          />
          <span class="st-switch-track" aria-hidden="true"></span>
        </label>
      </div>
    </div>
  </section>

  <section class="st-section">
    <div class="st-section-title">{t('音效')}</div>
    <div class="st-card">
      <div class="st-row">
        <div class="st-label">
          {t('均衡器')}
          <span class="st-desc">
            {#if equalizer.enabled}
              {t('已开启 · 当前预设：{preset} · 10 段图形均衡', {
                preset: t(currentPresetName())
              })}
            {:else}
              {t('已关闭 · 10 段图形均衡，内置 {n} 种预设', { n: EQ_PRESETS.length })}
            {/if}
          </span>
        </div>
        <span class="st-value">{equalizer.enabled ? t('已开启') : t('已关闭')}</span>
        <label class="st-switch" title={equalizer.enabled ? t('关闭均衡器') : t('开启均衡器')}>
          <input
            type="checkbox"
            aria-label={t('开启均衡器')}
            checked={equalizer.enabled}
            onchange={(e) => {
              const input = e.currentTarget;
              if (!setEqualizerEnabled(input.checked) && input.checked) {
                input.checked = false;
                showToast(t('当前系统不支持均衡器，已关闭'));
              }
            }}
          />
          <span class="st-switch-track" aria-hidden="true"></span>
        </label>
        <button class="st-btn" onclick={openEqualizer}>{t('调整…')}</button>
      </div>
    </div>
  </section>

  <section class="st-section">
    <div class="st-section-title">{t('下载')}</div>
    <div class="st-card">
      <div class="st-row">
        <div class="st-label">{t('音乐库目录')}</div>
        <div class="st-control st-grow">
          <input
            class="st-input"
            value={s.music_dir}
            aria-label={t('音乐库目录')}
            readonly
            spellcheck="false"
          />
          <button class="st-btn" disabled={!loaded || musicDirectoryBusy} onclick={() => chooseMusicDirectory(false)}>{t('切换音乐库…')}</button>
          <button class="st-btn" disabled={!loaded || musicDirectoryBusy} onclick={() => chooseMusicDirectory(true)}>{t('复制音乐库…')}</button>
        </div>
      </div>

      <div class="st-row">
        <div class="st-label">{t('默认音质')}</div>
        <select
          class="st-select"
          aria-label={t('默认音质')}
          bind:value={s.default_quality}
          onchange={saveNow}
        >
          {#each qualityOptions as q (q.v)}
            <option value={q.v} disabled={q.disabled}>{q.label}</option>
          {/each}
        </select>
      </div>

      <div class="st-row">
        <div class="st-label">{t('并发下载数')}</div>
        <select
          class="st-select"
          aria-label={t('并发下载数')}
          value={s.concurrency}
          onchange={(e) => {
            s.concurrency = Number(e.currentTarget.value);
            void saveNow();
          }}
        >
          {#each [1, 2, 3, 4, 5, 6] as n (n)}
            <option value={n}>{n}</option>
          {/each}
        </select>
      </div>
    </div>
  </section>

  <section class="st-section">
    <div class="st-section-title">{t('播放缓存')}</div>
    <div class="st-card">
      <div class="st-row">
        <div class="st-label">{t('缓存目录')}</div>
        <div class="st-control st-grow">
          <input class="st-input" value={s.cache_dir} aria-label={t('缓存目录')} readonly />
          <button class="st-btn" onclick={() => pickDir('cache_dir')} disabled={cacheClearing}
            title={t('选择缓存目录')}>{t('选择…')}</button>
        </div>
      </div>
      <div class="st-row">
        <div class="st-label">{t('清空播放缓存')}</div>
        <button class="st-btn" onclick={clearPlaybackCache} disabled={cacheClearing || !loaded}>
          {cacheClearing ? t('正在清空…') : t('清空')}
        </button>
      </div>
    </div>
  </section>

  <section class="st-section">
    <div class="st-section-title">{t('窗口')}</div>
    <div class="st-card">
      <div class="st-row">
        <div class="st-label">
          {t('关闭窗口时收进托盘')}
          <span class="st-desc">{t('继续在后台播放')}</span>
        </div>
        <label class="st-switch">
          <input
            type="checkbox"
            aria-label={t('关闭窗口时收进托盘')}
            bind:checked={s.close_to_tray}
            onchange={saveNow}
          />
          <span class="st-switch-track" aria-hidden="true"></span>
        </label>
      </div>
    </div>
  </section>

  <section class="st-section">
    <div class="st-section-title">{t('网盘')}</div>
    <div class="st-card">
      <div class="st-row">
        <div class="st-label">
          {t('网盘协议')}
        </div>
        <select class="st-select" aria-label={t('网盘协议')}
          value={s.webdav_enabled ? 'webdav' : s.s3_enabled ? 's3' : 'off'}
          onchange={selectCloud}
        >
          <option value="off">{t('关闭')}</option>
          <option value="s3">S3</option>
          <option value="webdav">WebDAV</option>
        </select>
      </div>

      {#if s.webdav_enabled}
        <div class="st-row">
          <div class="st-label">{t('服务地址')}</div>
          <input class="st-input st-input-wide" type="url"
            aria-label={t('服务地址')} bind:value={s.webdav_endpoint}
            oninput={scheduleSave} placeholder="https://nas.example.com/dav/" spellcheck="false" />
        </div>
        <div class="st-row">
          <div class="st-label">
            {t('音乐根目录')}
            <span class="st-desc">{t('留空使用服务地址对应的目录')}</span>
          </div>
          <input class="st-input st-input-wide"
            aria-label={t('音乐根目录')} bind:value={s.webdav_root}
            oninput={scheduleSave} placeholder="TinyMusic" spellcheck="false" />
        </div>
        <div class="st-row">
          <div class="st-label">{t('WebDAV 用户名')}</div>
          <input class="st-input st-input-wide"
            aria-label={t('WebDAV 用户名')} bind:value={s.webdav_username}
            oninput={scheduleSave} autocomplete="off" spellcheck="false" />
        </div>
        <div class="st-row">
          <div class="st-label">{t('WebDAV 密码')}</div>
          <input class="st-input st-input-wide" type="password"
            aria-label={t('WebDAV 密码')} bind:value={s.webdav_password}
            oninput={scheduleSave} autocomplete="off" />
        </div>
      {/if}

      {#if s.s3_enabled && !s.webdav_enabled}
        <div class="st-s3-more" transition:slide={{ duration: REDUCE_MOTION ? 0 : 180 }}>
          <div class="st-row">
            <div class="st-label">Endpoint</div>
            <input
              class="st-input st-input-wide"
              bind:value={s.s3_endpoint}
              aria-label="S3 Endpoint"
              oninput={scheduleSave}
              placeholder="https://s3.us-east-1.amazonaws.com"
              spellcheck="false"
            />
          </div>

          <div class="st-row">
            <div class="st-label">Region</div>
            <input
              class="st-input"
              bind:value={s.s3_region}
              aria-label="S3 Region"
              oninput={scheduleSave}
              placeholder="us-east-1"
              spellcheck="false"
            />
          </div>

          <div class="st-row">
            <div class="st-label">Bucket</div>
            <input
              class="st-input"
              bind:value={s.s3_bucket}
              aria-label="S3 Bucket"
              oninput={scheduleSave}
              placeholder="my-music"
              spellcheck="false"
            />
          </div>

          <div class="st-row">
            <div class="st-label">{t('前缀目录')}</div>
            <input
              class="st-input"
              bind:value={s.s3_prefix}
              aria-label={t('S3 前缀目录')}
              oninput={scheduleSave}
              placeholder="TinyMusic"
              spellcheck="false"
            />
          </div>

          <div class="st-row">
            <div class="st-label">Access Key</div>
            <input
              class="st-input st-input-wide"
              bind:value={s.s3_access_key}
              aria-label="S3 Access Key"
              oninput={scheduleSave}
              spellcheck="false"
              autocomplete="off"
            />
          </div>

          <div class="st-row">
            <div class="st-label">Secret Key</div>
            <input
              class="st-input st-input-wide"
              type="password"
              bind:value={s.s3_secret_key}
              aria-label="S3 Secret Key"
              oninput={scheduleSave}
              autocomplete="off"
            />
          </div>

          <div class="st-row">
            <div class="st-label">{t('Path-Style 寻址')}</div>
            <label class="st-switch">
              <input
                type="checkbox"
                aria-label={t('Path-Style 寻址')}
                bind:checked={s.s3_path_style}
                onchange={saveNow}
              />
              <span class="st-switch-track" aria-hidden="true"></span>
            </label>
          </div>

        </div>
      {/if}
      {#if s.s3_enabled || s.webdav_enabled}
        <div class="st-row">
          <div class="st-label">{t('连接')}</div>
          <button class="st-btn" onclick={testCloud} disabled={s3Busy}>
            {s3Busy ? t('连接中…') : t('测试连接')}
          </button>
        </div>
        {#if s3Err}
          <ErrorNotice text={s3Err} compact />
        {:else if s3Msg}
          <div class="st-status">{s3Msg}</div>
        {/if}
      {/if}
    </div>
  </section>

  <section class="st-section">
    <div class="st-section-title">{t('关于')}</div>
    <div class="st-card">
      <div class="st-row">
        <div class="st-label">{t('当前版本')}</div>
        <span class="st-value">v{appVersion || '—'}</span>
        {#if pending}
          <span class="st-value new">{t('可更新到 v{version}', { version: pending.version })}</span>
        {/if}
      </div>
      <div class="st-row">
        <div class="st-label">
          {t('软件更新')}
          {#if pending}
            <span class="st-desc">
              {t('发现新版本 v{version}，装完会自动重启', { version: pending.version })}
            </span>
          {:else if updMsg}
            <span class="st-desc">{updMsg}</span>
          {/if}
        </div>
        <div class="st-control">
          {#if pending}
            <button class="st-btn primary" onclick={doUpdate} disabled={updBusy}>
              {t('下载并安装')}
            </button>
          {/if}
          <button class="st-btn" onclick={checkUpdate} disabled={updBusy}>
            {updBusy && !pending ? t('检查中…') : t('检查更新')}
          </button>
        </div>
      </div>
      {#if updBusy && pending}
        <div class="st-status">
          <ProgressBar value={progress / 100} label={t('正在下载更新…')} />
        </div>
      {/if}
      {#if updErr}<ErrorNotice text={updErr} compact />{/if}
    </div>
  </section>
</div>

<style>
  .st-color {
    inline-size: 44px;
    block-size: 30px;
    padding: 2px;
    border: 1px solid var(--line);
    border-radius: var(--r-sm);
    background: var(--bg3);
    cursor: pointer;
  }

  .settings-page {
    max-width: 760px;
    padding-top: 26px;
  }

  .st-head {
    display: flex;
    align-items: baseline;
    gap: 10px;
    margin-bottom: 6px;
  }

  .st-head h1 {
    margin: 0;
  }

  .st-saved {
    color: var(--success);
    font-size: 12px;
  }

  .st-section {
    margin-top: 22px;
  }

  .st-section-title {
    margin: 0 6px 8px;
    color: var(--fg);
    font-size: 14px;
    font-weight: 600;
    letter-spacing: -0.01em;
  }

  .st-card {
    overflow: hidden;
    border: 1px solid var(--line-soft);
    border-radius: var(--r-lg);
    background-color: var(--bg2);
  }

  /* 网盘没启用时这块整段不渲染；收起后它不再是 .st-row 的兄弟，自己补一条分隔线 */
  .st-s3-more > .st-row:first-child {
    border-top: 1px solid var(--line);
  }

  .st-row {
    display: flex;
    align-items: center;
    gap: 16px;
    min-height: 48px;
    padding: 9px 16px;
  }

  .st-row + .st-row {
    border-top: 1px solid var(--line);
  }

  .st-label {
    flex: 1;
    min-width: 0;
    color: var(--fg);
    font-size: 13px;
    line-height: 1.35;
  }

  .st-desc {
    display: block;
    margin-top: 2px;
    color: var(--fg3);
    font-size: 11px;
    font-weight: 400;
  }

  .st-value {
    flex: none;
    color: var(--fg2);
    font-size: 12px;
  }

  /* 当前版本右边挂一句「可更新到 vX」，琥珀色，和列表里的无损标记同一种语气 */
  .st-value.new {
    color: var(--warn);
  }

  .st-control {
    flex: none;
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .st-grow {
    flex: 1;
    min-width: 0;
  }

  .st-grow .st-input {
    flex: 1;
    min-width: 0;
  }

  .st-input {
    box-sizing: border-box;
    height: 30px;
    width: 190px;
    max-width: 100%;
    padding: 0 10px;
    border: 1px solid var(--field-edge);
    border-radius: var(--r-sm);
    background-color: var(--field);
    color: var(--fg);
    font-size: 12px;
    outline: none;
  }

  .st-input-wide {
    width: 300px;
  }

  .st-input:focus {
    border-color: var(--focus-line);
  }

  .st-select {
    box-sizing: border-box;
    height: 30px;
    min-width: 150px;
    max-width: 100%;
    padding: 0 28px 0 10px;
    border: 1px solid var(--field-edge);
    border-radius: var(--r-sm);
    background-color: var(--field);
    background-image: var(--select-arrow);
    background-repeat: no-repeat;
    background-position: right 9px center;
    color: var(--fg);
    font-size: 12px;
    appearance: none;
    outline: none;
  }

  .st-select option {
    background-color: var(--popover-solid);
    color: var(--fg);
  }

  .st-select:disabled,
  .st-select option:disabled {
    color: var(--fg3);
  }

  .st-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    height: 30px;
    padding: 0 12px;
    border: 1px solid var(--field-edge);
    border-radius: var(--r-sm);
    background-color: var(--field);
    color: var(--fg);
    font-size: 12px;
    white-space: nowrap;
    cursor: pointer;
  }

  .st-btn:hover:not(:disabled) {
    background-color: var(--hover);
  }

  .st-btn:disabled {
    opacity: 0.45;
    cursor: default;
  }

  .st-btn.primary {
    border-color: transparent;
    background-color: #0a84ff;
    color: #fff;
  }


  .st-seg {
    display: inline-flex;
    flex-wrap: wrap;
    gap: 2px;
    padding: 2px;
    border: 1px solid var(--field-edge);
    border-radius: var(--r-sm);
    background-color: var(--field);
  }

  .st-seg button {
    height: 26px;
    padding: 0 12px;
    border-radius: 6px;
    color: var(--fg2);
    font-size: 12px;
    white-space: nowrap;
  }

  .st-seg button:hover {
    color: var(--fg);
  }

  .st-seg button.on {
    background-color: var(--hover);
    color: var(--fg);
    box-shadow:
      inset 0 1px 0 var(--glass-rim),
      0 1px 2px rgba(0, 0, 0, 0.18);
  }

  .st-switch {
    position: relative;
    flex: none;
    display: inline-flex;
    width: 40px;
    height: 24px;
    cursor: pointer;
  }

  .st-switch input {
    position: absolute;
    inset: 0;
    z-index: 1;
    width: 100%;
    height: 100%;
    margin: 0;
    opacity: 0;
    cursor: pointer;
  }

  .st-switch-track {
    position: absolute;
    inset: 0;
    border-radius: 999px;
    background-color: var(--track);
    box-shadow: inset 0 0 0 1px var(--line-strong);
    transition: background-color 160ms ease;
  }

  .st-switch-track::after {
    content: '';
    position: absolute;
    top: 2px;
    left: 2px;
    width: 20px;
    height: 20px;
    border-radius: 50%;
    background-color: var(--knob);
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.28);
    transition: transform 160ms cubic-bezier(0.22, 1, 0.36, 1);
  }

  .st-switch input:checked + .st-switch-track {
    background-color: #0a84ff;
    box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.08);
  }

  .st-switch input:checked + .st-switch-track::after {
    transform: translateX(16px);
  }

  .st-switch input:focus-visible + .st-switch-track {
    outline: 2px solid var(--focus-line);
    outline-offset: 2px;
  }

  /* 引擎不支持毛玻璃时开关不可用：只是把状态说清楚，不做成第二个颜色 */
  .st-switch input:disabled {
    cursor: not-allowed;
  }

  .st-switch input:disabled + .st-switch-track {
    opacity: 0.45;
  }

  .st-status {
    padding: 8px 16px 10px;
    border-top: 1px solid var(--line);
    color: var(--fg2);
    font-size: 11px;
    line-height: 1.5;
    overflow-wrap: anywhere;
  }

  .st-status.bad {
    color: var(--danger);
  }

  @media (max-width: 620px) {
    .st-row {
      align-items: flex-start;
      flex-direction: column;
      gap: 8px;
    }

    .st-control,
    .st-input,
    .st-input-wide {
      width: 100%;
    }

    .st-grow {
      width: 100%;
    }
  }
</style>
