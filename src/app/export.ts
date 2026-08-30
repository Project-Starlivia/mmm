// マップを外へ出す。ファイルにも、クリップボードにも。
//
// 1 枚の <svg> にするのは map/toSvg.ts の仕事で、ここが持つのは
// **その先の出し口**だけ — 直列化・ラスタ化・ダウンロード・クリップボード。
//
// **出し方 4 通りの定義はここ 1 か所**。ヘッダも右クリックも同じ並びを開く。
// 違うのは対象だけ — ヘッダは常に全体、右クリックは選んでいる枝。
// 新規 / 開く / 保存 が文書ぜんぶを相手にするのと同じ高さにヘッダを置き、
// 「これ」を相手にする操作は右クリックへ寄せる。

import type { Mindmap } from "../mindmap.ts";
import { type MenuEntry, openOnClick } from "../map/menu.ts";
import type { RadialEntry } from "../map/radialMenu.ts";
import { type IconName, icon, label, nod } from "../icons.ts";
import { LS_WAY, load, store } from "./persist.ts";

/**
 * ラスタの倍率。**選ばせない** — 書き出したものは画面で見えている通りで
 * あるべきで、選ばせるほど何が出るか分からなくなる。貼り先で粗く見えない
 * 下限として 2 倍だけ取る。
 */
const SCALE = 2;

export interface ExportDeps {
  map: Mindmap;
  /** ダウンロード名の元になる、いまのファイル名 */
  name: () => string;
  /** 果たせなかった */
  failed: (msg: string) => void;
  /** 出すものが無い。キーから来たときだけここへ落ちる */
  blocked: (msg: string) => void;
  /** マップに 1 つも枝が無いか。**押す前に分かるので、押す前に言う** */
  empty: () => boolean;
}

/** 出すものが無い理由。ボタンの `title` にも行の hover にも同じ言葉を出す */
const NOTHING = "Nothing to export yet";

/** `▾` の名乗り。絵しか持たないので、名前は綴りで持つ */
const CHOOSE = "Choose how to export";

/** 出せたことをボタンが言っている長さ。読めるだけ在って、次に押すときには
 *  もう「いまの出し方」に戻っている、の間 */
const HOLD = 1500;

function downloadBlob(blob: Blob, name: string): void {
  const a = document.createElement("a");
  const url = URL.createObjectURL(blob);
  a.href = url;
  a.download = name;
  a.click();
  // click() の直後に revoke するとダウンロードが始まる前に URL が
  // 消えることがある。次のタスクまで待つ
  setTimeout(() => URL.revokeObjectURL(url), 0);
}

const serialize = (svg: SVGSVGElement): string =>
  new XMLSerializer().serializeToString(svg);

/**
 * SVG を絵にする。
 *
 * `toSvg` が `blob:` のサムネイルを data URL に埋め直しているので、
 * canvas は汚染されない（外部を参照したままだと toBlob が例外になる）。
 */
async function rasterize(svg: SVGSVGElement, mime: string): Promise<Blob> {
  const w = Number(svg.getAttribute("width"));
  const h = Number(svg.getAttribute("height"));
  if (!Number.isFinite(w) || !Number.isFinite(h) || w <= 0 || h <= 0) {
    throw new Error("書き出す大きさが読めない");
  }
  const src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(serialize(svg))}`;
  const img = new Image();
  await new Promise<void>((resolve, reject) => {
    img.onload = () => resolve();
    img.onerror = () => reject(new Error("SVG を絵にできない"));
    img.src = src;
  });
  const canvas = document.createElement("canvas");
  canvas.width = Math.ceil(w * SCALE);
  canvas.height = Math.ceil(h * SCALE);
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("2d コンテキストを作れない");
  ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
  return await new Promise<Blob>((resolve, reject) => {
    canvas.toBlob(
      (blob) => (blob ? resolve(blob) : reject(new Error("絵にできなかった"))),
      mime,
    );
  });
}

/**
 * 出し方 4 通り。**行き先で選べる形式が違う**。
 *
 * `WebP` はクリップボードに置けない — Chromium の `ClipboardItem` が受け取る
 * のは `image/png` と `image/svg+xml` だけ（`ClipboardItem.supports` に聞いた）。
 * なのでコピー側の絵は PNG。
 *
 * SVG のコピーは `text/plain` にも同じものを載せる — Figma や Illustrator は
 * 画像として受け取るより、SVG のソースを貼られたほうが確実に開く。
 *
 * `short` はボタンの表示で、`label`（並びの表示）から動詞を落としたもの。
 * **行き先は `mark` の絵が言う** — 落とすのか、貼れるようにするのか。
 * 形式ではなく行き先に印が付く。
 */
const WAYS: readonly {
  id: string;
  short: string;
  mark: IconName;
  label: string;
  out: (svg: SVGSVGElement, base: string) => Promise<void>;
}[] = [
  {
    id: "svg-file",
    short: "SVG",
    mark: "download",
    label: "Download SVG",
    out: async (svg: SVGSVGElement, base: string): Promise<void> => {
      downloadBlob(
        new Blob([serialize(svg)], { type: "image/svg+xml" }),
        `${base}.svg`,
      );
    },
  },
  {
    id: "webp-file",
    short: "WebP",
    mark: "download",
    label: "Download WebP",
    out: async (svg: SVGSVGElement, base: string): Promise<void> => {
      downloadBlob(await rasterize(svg, "image/webp"), `${base}.webp`);
    },
  },
  {
    id: "png-copy",
    short: "PNG",
    mark: "copy",
    label: "Copy PNG",
    out: async (svg: SVGSVGElement): Promise<void> => {
      const png = await rasterize(svg, "image/png");
      await navigator.clipboard.write([new ClipboardItem({ "image/png": png })]);
    },
  },
  {
    id: "svg-copy",
    short: "SVG",
    mark: "copy",
    label: "Copy SVG",
    out: async (svg: SVGSVGElement): Promise<void> => {
      const text = serialize(svg);
      await navigator.clipboard.write([
        new ClipboardItem({
          "image/svg+xml": new Blob([text], { type: "image/svg+xml" }),
          "text/plain": new Blob([text], { type: "text/plain" }),
        }),
      ]);
    },
  },
] as const;

type Way = (typeof WAYS)[number];

/** 覚えていた出し方。知らない値なら既定へ落とす（型は名乗らせず確かめる） */
const wayOf = (saved: string | null): Way =>
  WAYS.find((w) => w.id === saved) ?? WAYS[0];

/**
 * そのやり方で 1 回出す。**出せたかを返す** — 済んだらヘッダーのボタンが
 * チェックで答えるので、答えてよいかを呼ぶ側が知る必要がある。
 * しくじりはここがしらせに出し、約束は拒まない（呼ぶ側に try を書かせない）。
 */
async function run(deps: ExportDeps, way: Way, whole: boolean): Promise<boolean> {
  try {
    const svg = await deps.map.exportSvg(whole);
    if (!svg) {
      // ボタンは沈めてあるので、ここへ来るのはキー（`Mod+E`）から。
      // **触って読める言葉と同じものを出す** — 同じ壁に 2 つの綴りを持たない
      deps.blocked(NOTHING);
      return false;
    }
    const base = deps.name().replace(/\.(md|markdown|txt)$/i, "") || "mmm";
    await way.out(svg, base);
    return true;
  } catch (error: unknown) {
    console.error("export failed:", error);
    deps.failed("Couldn't export");
    return false;
  }
}

/**
 * 出し方の並び。**ヘッダも右クリックも同じものを開く** — 違うのは対象だけで、
 * `whole` なら全体、そうでなければ選んでいる枝。
 *
 * `header` はヘッダから開いたときの走らせ方。**選ばれた出し方を渡すだけで、
 * その先はヘッダが持つ**（次の既定にし、済んだらボタンの絵で答える） —
 * 答える場所がボタンなので、答え方を知っているのもボタンを持つ側。
 * 無ければここが走らせるだけ（右クリック側。押せば閉じて、それで終わる）。
 */
export function exportWays(
  deps: ExportDeps,
  whole: boolean,
  header?: (way: Way) => void,
): MenuEntry[] {
  const entries: MenuEntry[] = [];
  for (const [i, way] of WAYS.entries()) {
    // ダウンロードとコピーのあいだに線を引く（行き先が変わるところ）
    if (i === 2) entries.push("sep");
    entries.push({
      label: way.label,
      mark: way.mark,
      // 対象が枝のときは、枝を選んでいること自体が呼び出し側で保証されている
      // （右クリックの Export は `anchor === -1` で既に閉じている）
      disabled: whole && deps.empty() && NOTHING,
      run: () => {
        if (header) header(way);
        else void run(deps, way, whole);
      },
    });
  }
  return entries;
}

/**
 * ヘッダの書き出し。対象は常に全体。
 *
 * ボタンには**いまの出し方**が出ていて、押せばそれで出る。`▾` で選び直すと
 * その場で出て、次からの既定になる — 押す前に何が起きるかが常に見えている。
 *
 * 戻り値はキーボードショートカット（`Mod+E` / `Mod+Shift+E`）用。**出し方
 * 4 通りの定義は増やさない** — `run` はこのボタンと同じものを走らせるだけ、
 * `ways` は `WAYS` をラジアルメニュー用の形へ薄く写すだけ
 */
export function initExport(
  deps: ExportDeps & { button: HTMLButtonElement; wayButton: HTMLButtonElement },
): { run: () => void; ways: () => RadialEntry[]; refresh: () => void } {
  deps.wayButton.replaceChildren(icon("chevron-down"));
  let way = wayOf(load(LS_WAY));
  const show = (): void => {
    // 形式が文字、行き先が絵。押す前に何が起きるかが見えている
    deps.button.replaceChildren(...label(way.short, way.mark, true));
    // 出すものが無いなら押せない。**なぜ押せないかも同じ場所が言う** —
    // ボタンは 1 つしか言えないので、言えるほうを言う
    const empty = deps.empty();
    deps.button.disabled = empty;
    deps.button.title = empty ? NOTHING : `Export the whole Mindmap — ${way.label}`;
    // **`▾` も一緒に沈む。** 選び直すことは出すことなので（選べばその場で
    // 出る）、出せないなら選ぶ意味も無い。並びを開いて 4 行とも沈んでいる
    // のを見せるより、開く前に同じ言葉で言うほうが早い
    deps.wayButton.disabled = empty;
    deps.wayButton.title = empty ? NOTHING : CHOOSE;
    deps.wayButton.setAttribute("aria-label", deps.wayButton.title);
  };
  show();

  const remember = (chosen: Way): void => {
    way = chosen;
    store(LS_WAY, chosen.id);
    show();
  };

  /**
   * 出せたことを**ボタンの絵で**言う。しらせを出して残すほどの話ではなく、
   * 手元には何も現れないので（クリップボードも、ブラウザ任せのダウンロードも）
   * 押した場所が一度うなずくだけでいい。
   *
   * **戻すきっかけは 2 つ。ボタンから離れたときと、離れないまま HOLD が
   * 経ったとき。** 離れたときだけにすると、`▾` の並びから選んだときや
   * キーで出したときはポインタがボタンに乗っておらず、離れる瞬間が
   * 来ないので戻らない。時間だけにすると、次に押したいときまで
   * 「いまの出し方」が読めないままになる。早く来たほうを採る。
   */
  let back: ReturnType<typeof setTimeout> | undefined;
  const undo = (): void => {
    if (back === undefined) return;
    clearTimeout(back);
    back = undefined;
    show();
  };
  deps.button.addEventListener("pointerleave", undo);

  /**
   * ヘッダから 1 回出す。走っているあいだボタンが回り、出せたらうなずく
   * （`nod` が決める）。しくじったときは `show()` で戻す — 回していた
   * かもしれないので、必ず通す
   */
  const fire = (chosen: Way): void => {
    const put = (mark: IconName): void => {
      deps.button.replaceChildren(...label(chosen.short, mark, true));
    };
    void nod(run(deps, chosen, true), put).then((ok) => {
      if (!ok) return show();
      clearTimeout(back);
      back = setTimeout(undo, HOLD);
    });
  };
  /** 選び直して出す。次からの既定にもなる（`▾` の並びと放射メニュー） */
  const pick = (chosen: Way): void => {
    remember(chosen);
    fire(chosen);
  };

  deps.button.addEventListener("click", () => fire(way));

  openOnClick(deps.wayButton, () => exportWays(deps, true, pick));

  return {
    run: () => fire(way),
    ways: () =>
      WAYS.map((w) => ({ mark: w.mark, label: w.short, run: () => pick(w) })),
    /** 文書が変わった。押せるかどうかを見直す（applySnap から呼ばれる） */
    refresh: show,
  };
}
