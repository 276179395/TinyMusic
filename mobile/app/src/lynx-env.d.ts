declare module '@lynx-js/types' {
  interface GlobalProps {
    /** 宿主注入：深浅色（'dark' | 'light'） */
    appTheme?: string;
    /** 宿主注入：安全区（px） */
    safeAreaTop?: number;
    safeAreaBottom?: number;
  }
}

// 让这个文件成为模块
export {};
