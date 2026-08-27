// 見た目の好み: ブランドカラーと、ライト/ダーク（既定は OS 設定、
// 分からなければダーク）。どちらも保存して、次のセッションでもそのまま。

import { LS_COLOR, LS_THEME, load, store } from "./persist.ts";
import { logoInner, logoSvg } from "./logo.ts";

/** 既定のブランドカラー。style.css の `--accent` の初期値と同じ。 */
const DEFAULT_COLOR = "#5932ff";

/** favicon は data URL なので、色を実値で埋める必要がある。 */
function applyFavicon(color: string): void {
  const found = document.querySelector('link[rel="icon"]');
  // 型は名乗らせず確かめる。`<link rel=icon>` でないものが居たら作り直す
  let link: HTMLLinkElement;
  if (found instanceof HTMLLinkElement) {
    link = found;
  } else {
    link = document.createElement("link");
    link.rel = "icon";
    document.head.append(link);
  }
  link.href = `data:image/svg+xml,${encodeURIComponent(logoSvg(color))}`;
}

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
  applyFavicon(c);
  store(LS_COLOR, c);
}

export type Theme = "light" | "dark";

/**
 * カラーとテーマの配線と、保存値の復元。
 * `setEditorTheme` は CodeMirror 側のテーマ切り替え（DOM の外なので注入）。
 */
export function initTheme(args: {
  /** topbar の `<svg id="logo">`。中身は logo.ts が入れる */
  logo: SVGSVGElement;
  setEditorTheme: (dark: boolean) => void;
}): { toggle: () => void; isLight: () => boolean } {
  const { logo } = args;

  // ロゴの形の源は logo.ts ひとつ。topbar も favicon もここから作る
  // （静的ファイルに複製すると、以前のように片方だけ左右が反転していても
  // 誰も気づけない）。色は currentColor = --accent。
  logo.insertAdjacentHTML("beforeend", logoInner());

  // ---- ブランドカラー ----
  const colorInput = document.createElement("input");
  colorInput.type = "color";
  // ロゴの下に（見えない形で）置く。ネイティブのピッカーが画面外ではなく
  // 左上に開くようにするため
  colorInput.style.position = "fixed";
  colorInput.style.left = "10px";
  colorInput.style.top = "10px";
  colorInput.style.width = "24px";
  colorInput.style.height = "24px";
  colorInput.style.opacity = "0";
  colorInput.style.pointerEvents = "none";
  document.body.append(colorInput);
  colorInput.addEventListener("input", () => applyColor(colorInput.value));
  const pickColor = (): void => {
    const cur = getComputedStyle(document.documentElement)
      .getPropertyValue("--accent")
      .trim();
    colorInput.value = /^#[0-9a-f]{6}$/i.test(cur) ? cur : DEFAULT_COLOR;
    colorInput.click();
  };
  logo.addEventListener("click", pickColor);
  // ロゴは <svg role="button">。SVG はフォーカスされても Enter / Space で
  // click を出さないので、ボタンだと名乗る以上ここで自分で出す
  logo.addEventListener("keydown", (e) => {
    if (e.key !== "Enter" && e.key !== " ") return;
    e.preventDefault();
    pickColor();
  });

  // ---- ライト / ダーク ----
  // **ボタンは持たない。** どう見せるかは呼ぶ側の仕事で、ここは
  // 「切り替える」「いまどちらか」だけを渡す（テーマの置き場所は
  // 帯だったりメニューだったり変わるので、器に縛られない）
  const isLight = (): boolean =>
    document.documentElement.classList.contains("light");
  const applyTheme = (t: Theme): void => {
    document.documentElement.classList.toggle("light", t === "light");
    args.setEditorTheme(t !== "light");
    store(LS_THEME, t);
  };
  const toggle = (): void => applyTheme(isLight() ? "dark" : "light");

  // ---- 復元 ----
  // localStorage の中身は何でもありうる（人が書き替えられるし、昔の版が
  // 別の値を入れているかもしれない）。名乗らせずに確かめる
  const stored = load(LS_THEME);
  const saved: Theme | null =
    stored === "light" || stored === "dark" ? stored : null;
  const osLight = window.matchMedia?.("(prefers-color-scheme: light)").matches;
  applyTheme(saved ?? (osLight ? "light" : "dark"));
  applyColor(load(LS_COLOR) ?? DEFAULT_COLOR);
  return { toggle, isLight };
}
