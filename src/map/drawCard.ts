// カード 1 行を SVG にする。
//
// `cards.ts` が**分類**（Block → カード行。DOM を知らない）で、こちらが
// **見せ方**（カード行 → SVG）。種類ごとに形・クラス・埋め方が縦に並ぶので、
// リンクカードを直したい人はこのファイルの `link` だけを見ればよい。
//
// 置き場所は自分では数えない — `layout.cardRect` が唯一の出所で、選んだ枠も
// 入力欄も同じ数を使う。

import type { CardRow } from "./cards.ts";
import type { Rect } from "./geometry.ts";
import { tokenize } from "./highlight.ts";
import {
  CODE_LINE,
  DETAILS_INDENT,
  DETAILS_NAME,
  DETAILS_ROW,
  CODE_PAD,
  ROW_NORMAL,
} from "./metrics.ts";
import { svgEl } from "./svg.ts";

/** カード 1 行を置く場所。 */
export interface CardSpot {
  /** 中身を置く矩形（箱の左上から見た座標） */
  rect: Rect;
  /** 行の枠の上端。中身より上にあり、差は `cardInset` ぶん */
  rowY: number;
  /** ノードの箱の幅。仕切り線だけは中身ではなく箱に合わせて引く */
  boxW: number;
  /** `data-card` に入れる「どのノードの何行目か」 */
  spot: string;
}

/** 行と行のあいだの仕切り。種類によらず引く */
function separator(at: CardSpot): SVGElement {
  return svgEl("line", {
    class: "card-sep",
    x1: ROW_NORMAL.padX - 4,
    y1: at.rowY,
    x2: at.boxW - ROW_NORMAL.padX + 4,
    y2: at.rowY,
  });
}

function link(r: Extract<CardRow, { kind: "link" }>, at: CardSpot): SVGElement[] {
  const { x, y, w, h } = at.rect;
  // 当たり判定の面。他の 3 種は絵や背景がその役をするが、リンクは文字しか
  // 描かないので、行いっぱいの透明な面を敷く
  const hit = svgEl("rect", {
    class: "link-hit",
    "data-card": at.spot,
    x,
    y,
    width: w,
    height: h,
  });
  const title = svgEl("text", { class: "link-row", x, y: y + h / 2 });
  title.textContent = r.title;
  const tip = svgEl("title");
  tip.textContent = r.url;
  const open = svgEl("text", {
    class: "link-open",
    // 枠の内側に収める。外へ出すと、選択の枠が本体より小さく見える
    x: x + w,
    y: y + h / 2,
    "text-anchor": "end",
    "data-url": r.url,
  });
  open.textContent = "↗";
  return [hit, title, tip, open];
}

/** 絵を 1 枚。インライン SVG もローカル画像も、貼り方はここだけ */
function picture(href: string, at: CardSpot): SVGElement {
  const { x, y, w, h } = at.rect;
  return svgEl("image", {
    "data-card": at.spot,
    x,
    y,
    width: w,
    height: h,
    preserveAspectRatio: "xMidYMid meet",
    href,
  });
}

function inlineSvg(
  r: Extract<CardRow, { kind: "svg" }>,
  at: CardSpot,
): SVGElement[] {
  const href = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(r.markup)}`;
  return [picture(href, at)];
}

function image(
  r: Extract<CardRow, { kind: "img" }>,
  at: CardSpot,
  imageUrl: (path: string) => string | null,
  hint: string | null,
): SVGElement[] {
  const url = imageUrl(r.path);
  if (url !== null) return [picture(url, at)];
  // まだ読めていない（握っていない / ファイルが無い）。読めたときに配置が
  // 飛ばないよう、同じ大きさの場所取りを置く
  const { x, y, w, h } = at.rect;
  const box = svgEl("rect", {
    class: "img-ph",
    "data-card": at.spot,
    x,
    y,
    width: w,
    height: h,
  });
  // **黙って空にしない。** 読めない理由は 4 通りあるのに症状は 1 つなので、
  // 場所取りが自分で言う。握っていないだけなら、ここが入口も兼ねる
  const mid = y + h / 2;
  const name = svgEl("text", {
    class: "img-name",
    "data-card": at.spot,
    x: x + w / 2,
    y: hint === null ? mid : mid - 7,
    "text-anchor": "middle",
  });
  name.textContent = r.name;
  if (hint === null) return [box, name];
  // 入口は**この字だけ**。場所取りそのものは選択のままにしておく
  // （2 つの意味を 1 つの当たり判定に乗せない）
  const link = svgEl("text", {
    class: "img-connect",
    "data-connect": "1",
    x: x + w / 2,
    y: mid + 8,
    "text-anchor": "middle",
  });
  link.textContent = hint;
  return [box, name, link];
}

function code(
  r: Extract<CardRow, { kind: "code" }>,
  at: CardSpot,
): SVGElement[] {
  const { x, y, w, h } = at.rect;
  // 背景は左右にも張り出す（コードは箱の縁まで塗る）。張り出しは矩形に
  // 織り込み済みなので、ここで足し直さない
  const bg = svgEl("rect", {
    class: "code-bg",
    "data-card": at.spot,
    x,
    y,
    width: w,
    height: h,
  });
  if (r.lang !== "") {
    const tip = svgEl("title");
    tip.textContent = r.lang;
    bg.append(tip);
  }
  const out: SVGElement[] = [bg];
  const tokens = tokenize(r.lines, r.lang);
  for (let i = 0; i < r.lines.length; i++) {
    const line = svgEl("text", {
      class: "code-line",
      "data-card": at.spot,
      x: ROW_NORMAL.padX + 1,
      y: at.rowY + CODE_PAD + i * CODE_LINE + CODE_LINE / 2,
    });
    // 幅の判断は素の文字列で行い、色の付いた塊をそこへ合わせる
    for (const t of tokens[i]) {
      const span = svgEl("tspan", t.cls === "" ? {} : { class: t.cls });
      span.textContent = t.text;
      line.append(span);
    }
    out.push(line);
  }
  return out;
}

/** 装飾の水平線。中身の幅いっぱいに 1 本 */
function rule(at: CardSpot): SVGElement[] {
  const { x, y, w, h } = at.rect;
  return [
    svgEl("line", {
      class: "card-rule",
      "data-card": at.spot,
      x1: x,
      y1: y + h / 2,
      x2: x + w,
      y2: y + h / 2,
    }),
  ];
}

/**
 * `<details>`。GitHub と同じ見え方 — 三角と summary（無ければ Details）、
 * 開いていればその下に中身の字。開閉は md の `open` が決めるので、押しても動かない
 */
function details(r: Extract<CardRow, { kind: "details" }>, at: CardSpot): SVGElement[] {
  const { x } = at.rect;
  const rowMid = at.rowY + DETAILS_ROW / 2; // summary の行の中心
  const mark = svgEl("text", { class: "details-mark", x, y: rowMid });
  mark.textContent = r.open ? "▾" : "▸";
  const name = svgEl("text", { class: "details-row", x: x + DETAILS_INDENT, y: rowMid });
  name.textContent = r.summary ?? DETAILS_NAME;
  const out: SVGElement[] = [mark, name];
  if (!r.open) return out;
  const top = at.rowY + DETAILS_ROW;
  for (let i = 0; i < r.lines.length; i++) {
    const line = svgEl("text", {
      class: "details-line",
      x: x + DETAILS_INDENT,
      y: top + i * CODE_LINE + CODE_LINE / 2,
    });
    line.textContent = r.lines[i];
    out.push(line);
  }
  return out;
}

/** カード 1 行ぶんの要素。仕切り線を含む、並べればよい形で返す */
export function drawCard(
  r: CardRow,
  at: CardSpot,
  imageUrl: (path: string) => string | null,
  imageHint: string | null,
): SVGElement[] {
  const body =
    r.kind === "link"
      ? link(r, at)
      : r.kind === "svg"
        ? inlineSvg(r, at)
        : r.kind === "img"
          ? image(r, at, imageUrl, imageHint)
          : r.kind === "code"
            ? code(r, at)
            : r.kind === "rule"
              ? rule(at)
              : details(r, at);
  return [separator(at), ...body];
}
