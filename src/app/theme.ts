// 見た目の好み: アクセントカラーと、ライト/ダーク（既定は OS 設定、
// 分からなければダーク）。どちらも保存して、次のセッションでもそのまま。

import { LS_COLOR, LS_THEME, load, store } from "./persist.ts";
import { logoInner, logoSvg } from "./logo.ts";

/**
 * いまのアクセントカラー。**綴りの源は style.css の `--accent` だけ**で、
 * ここは読むだけ（既定色を TS にも書くと、同じ数字が 2 か所になる）。
 * 読んだ値は名乗らせず確かめる — 6 桁の hex でなければ null。
 * 筆にする側（app/draw.ts）も同じ 1 つを読む。
 */
export function accent(): string | null {
  const value = getComputedStyle(document.documentElement).getPropertyValue("--accent").trim();
  return /^#[0-9a-f]{6}$/i.test(value) ? value : null;
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
}): {
  toggle: () => void;
  isLight: () => boolean;
  pickColor: () => void;
  /** 未保存かどうかが変わった。タブの印を描き直す（帯の `●` と同じ話） */
  setDirty: (dirty: boolean) => void;
} {
  const { logo } = args;

  // 既定色は style.css のもの。読めないなら配線が壊れているので、黙って
  // 別の色にすり替えない
  const base = accent();
  if (base === null) throw new Error("style.css の --accent が読めない");

  // ロゴの形の源は logo.ts ひとつ。topbar も favicon もここから作る
  // （静的ファイルに複製すると、以前のように片方だけ左右が反転していても
  // 誰も気づけない）。色は currentColor = --accent。
  logo.insertAdjacentHTML("beforeend", logoInner());

  // favicon は**色と未保存の印**の 2 つで決まる。片方だけ変わっても描き直す
  // ので、両方をここが覚えておく（呼ぶ側に「前は何色だったか」を持たせない）
  let faviconColor = base;
  let faviconDirty = false;

  /** favicon は data URL なので、色も印も実値で埋める必要がある。 */
  const applyFavicon = (): void => {
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
    const svg = logoSvg(faviconColor, faviconDirty);
    link.href = `data:image/svg+xml,${encodeURIComponent(svg)}`;
  };

  /**
   * アクセントカラーを当てる。**置くのは色そのものだけ** — 薄い版
   * （`--accent-soft`）も輪（`--ring`）も style.css が色から作る。
   *
   * ここで `rgba(...)` を組んで置くと、それは要素のインラインスタイルなので
   * `.light` の宣言に**必ず**勝ってしまう。ライト用に薄くしてあった
   * 宣言が一度も効かず、ライトでもダークの濃さのままになっていた。
   */
  const applyColor = (hex: string): void => {
    const m = /^#?([0-9a-f]{6})$/i.exec(hex);
    if (!m) return;
    const c = `#${m[1]}`;
    document.documentElement.style.setProperty("--accent", c);
    faviconColor = c;
    applyFavicon();
    store(LS_COLOR, c);
  };

  // ---- アクセントカラー ----
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
    colorInput.value = accent() ?? base;
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
  applyColor(load(LS_COLOR) ?? base);

  const setDirty = (dirty: boolean): void => {
    // 変わっていないなら描き直さない。data URL の組み立てと favicon の
    // 差し替えは打鍵のたびに起きうるので、同じ絵を作り直さない
    if (dirty === faviconDirty) return;
    faviconDirty = dirty;
    applyFavicon();
  };
  return { toggle, isLight, pickColor, setDirty };
}
