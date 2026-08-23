// ライト/ダークの切り替え (mmm.md そのに: default = OS, fallback dark)。
// 暗い部屋で目が痛いのは実用の問題なので残す。ブランドカラーは趣味の
// 問題なので持たない — 色は style.css の --accent に固定。

import { LS_THEME, load, store } from "./persist.ts";
import { logoInner, logoSvg } from "./logo.ts";

export type Theme = "light" | "dark";

/**
 * テーマの配線と保存値の復元。
 * `setEditorTheme` は CodeMirror 側のテーマ切り替え（DOM の外なので注入）。
 */
export function initTheme(args: {
  logo: HTMLElement;
  themeButton: HTMLButtonElement;
  setEditorTheme: (dark: boolean) => void;
}): void {
  const { logo, themeButton } = args;

  // 形の源は logo.ts ひとつ（静的ファイルに複製すると、以前のように片方だけ
  // 左右が反転していても誰も気づけない）。色の源は style.css の --accent
  // ひとつ。favicon は data URL なので色を実値で埋める必要があり、ここでだけ
  // CSS から読み出す。
  logo.insertAdjacentHTML("beforeend", logoInner());
  const accent = getComputedStyle(document.documentElement)
    .getPropertyValue("--accent")
    .trim();
  const icon = document.createElement("link");
  icon.rel = "icon";
  icon.href = `data:image/svg+xml,${encodeURIComponent(logoSvg(accent))}`;
  document.head.append(icon);

  const applyTheme = (t: Theme): void => {
    document.documentElement.classList.toggle("light", t === "light");
    args.setEditorTheme(t !== "light");
    themeButton.textContent = t === "light" ? "◐" : "◑";
    store(LS_THEME, t);
  };
  themeButton.addEventListener("click", () => {
    applyTheme(
      document.documentElement.classList.contains("light") ? "dark" : "light",
    );
  });

  const stored = load(LS_THEME) as Theme | null;
  const osLight = window.matchMedia?.("(prefers-color-scheme: light)").matches;
  applyTheme(stored ?? (osLight ? "light" : "dark"));
}
