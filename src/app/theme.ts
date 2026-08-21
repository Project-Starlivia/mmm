// 見た目の好み: ブランドカラー (mmm.md 課題: カラーピッカー) と
// ライト/ダーク (mmm.md そのに: default = OS, fallback dark)。
// どちらも保存して、次のセッションでもそのまま。

import { LS_COLOR, LS_THEME, load, store } from "./persist.ts";
import { LOGO_COLOR, logoInner, logoSvg } from "./logo.ts";

function applyColor(hex: string): void {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex);
  if (!m) return;
  const c = `#${m[1]}`;
  const r = parseInt(m[1].slice(0, 2), 16);
  const g = parseInt(m[1].slice(2, 4), 16);
  const b = parseInt(m[1].slice(4, 6), 16);
  const rootStyle = document.documentElement.style;
  rootStyle.setProperty("--accent", c);
  rootStyle.setProperty("--accent-soft", `rgba(${r}, ${g}, ${b}, 0.2)`);
  // favicon は静的ファイルを持たず、ここで色付きの実体を作って差し込む
  let link = document.querySelector<HTMLLinkElement>('link[rel="icon"]');
  if (!link) {
    link = document.createElement("link");
    link.rel = "icon";
    document.head.append(link);
  }
  link.href = `data:image/svg+xml,${encodeURIComponent(logoSvg(c))}`;
  store(LS_COLOR, c);
}

export type Theme = "light" | "dark";

/**
 * カラーとテーマの配線と、保存値の復元。
 * `setEditorTheme` は CodeMirror 側のテーマ切り替え（DOM の外なので注入）。
 */
export function initTheme(args: {
  logo: HTMLElement;
  themeButton: HTMLButtonElement;
  setEditorTheme: (dark: boolean) => void;
}): void {
  const { logo, themeButton } = args;

  // ロゴの中身は源（logo.ts）から注入する。色は currentColor = --accent。
  logo.insertAdjacentHTML("beforeend", logoInner());

  // ---- ブランドカラー ----
  const colorInput = document.createElement("input");
  colorInput.type = "color";
  // keep it (invisibly) under the logo so the native picker opens at the
  // top-left instead of somewhere off-screen (mmm.md そのに)
  colorInput.style.position = "fixed";
  colorInput.style.left = "10px";
  colorInput.style.top = "10px";
  colorInput.style.width = "24px";
  colorInput.style.height = "24px";
  colorInput.style.opacity = "0";
  colorInput.style.pointerEvents = "none";
  document.body.append(colorInput);
  colorInput.addEventListener("input", () => applyColor(colorInput.value));
  logo.addEventListener("click", () => {
    const cur = getComputedStyle(document.documentElement)
      .getPropertyValue("--accent")
      .trim();
    colorInput.value = /^#[0-9a-f]{6}$/i.test(cur) ? cur : LOGO_COLOR;
    colorInput.click();
  });

  // ---- ライト / ダーク ----
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

  // ---- 復元 ----
  const stored = load(LS_THEME) as Theme | null;
  const osLight = window.matchMedia?.("(prefers-color-scheme: light)").matches;
  applyTheme(stored ?? (osLight ? "light" : "dark"));
  applyColor(load(LS_COLOR) ?? LOGO_COLOR);
}
