// マップの DOM を差分で更新する層。**何を描くかは決めない** — レイアウトを
// 受け取って、SVG をそれに合わせるだけ。
//
// 毎レンダで全消しして作り直していた頃は、1 打鍵ごとに数万個の SVG 要素を
// 生成・破棄していて、それが入力遅延の実体だった。位置(transform)と class は
// 毎回書き換えても安いが、**要素の生成と破棄は高い**ので、そこだけを
// 「中身が変わったノード」に絞る。
//
// 差分の鍵は id。**id は文書順の位置**なので、上に 1 つ足せば以降が作り直される
// だけで、正しさは壊れない（docs/core.md「id は読みのサイクルを越えて持たない」）。

import type * as core from "../coreApi.ts";
import type { CardRow } from "./cards.ts";
import { type Box, type Layout, cardRect, edgeEnds } from "./layout.ts";
import { drawCard } from "./drawCard.ts";
import { edgePath } from "./edge.ts";
import { languageEpoch } from "./highlight.ts";
import { displayLabel, foldName, hiddenLabel, labelOf, rowOf, rowTop } from "./metrics.ts";
import { svgEl } from "./svg.ts";

/**
 * 1 回の描き直しに要るもの。文書とレイアウトから決まるものだけ。
 */
export interface Scene {
  layout: Layout;
  /** ローカル画像の objectURL（まだ読めていなければ null） */
  imageUrl: (path: string) => string | null;
  /** 読めていない場所取りに添える字。握っていないときだけ（他は null） */
  imageHint: string | null;
}

/**
 * ノードの中身を作り直すかどうかの判定材料。値をそのまま持って、そのまま
 * 比べる（畳んだ文字列にしない — 下記 sameShape）。私用の比較用で、層の語ではない。
 */
interface NodeShape {
  w: number;
  h: number;
  folded: boolean;
  buried: number;
  epoch: number;
  label: string;
  rows: CardRow[];
  /** rows と同じ並びで、画像だけ解決済みの URL（他は null） */
  urls: (string | null)[];
  /** 場所取りに添える字。**繋がった瞬間は URL がどれも null のままなので、
   *  これを姿に載せていないと描き直されない** */
  hint: string | null;
}

const sameLines = (a: string[], b: string[]): boolean =>
  a.length === b.length && a.every((l, i) => l === b[i]);

/** カード 1 枚が、描き直しを要するほど変わったか */
function sameRow(a: CardRow, b: CardRow): boolean {
  if (a.kind === "link" && b.kind === "link") {
    return a.title === b.title && a.url === b.url;
  }
  if (a.kind === "svg" && b.kind === "svg") return a.markup === b.markup;
  if (a.kind === "image" && b.kind === "image") return a.path === b.path;
  if (a.kind === "code" && b.kind === "code") {
    return a.lang === b.lang && sameLines(a.lines, b.lines);
  }
  if (a.kind === "break" && b.kind === "break") return true;
  if (a.kind === "details" && b.kind === "details") {
    return a.open === b.open && a.summary === b.summary && sameLines(a.lines, b.lines);
  }
  return false;
}

/** 前回と同じなら、その要素はそのまま置いておける */
function sameShape(a: NodeShape | undefined, b: NodeShape): boolean {
  if (
    a === undefined ||
    a.w !== b.w ||
    a.h !== b.h ||
    a.folded !== b.folded ||
    a.buried !== b.buried ||
    a.epoch !== b.epoch ||
    a.label !== b.label ||
    a.hint !== b.hint ||
    a.rows.length !== b.rows.length
  ) {
    return false;
  }
  for (let i = 0; i < a.rows.length; i++) {
    if (a.urls[i] !== b.urls[i] || !sameRow(a.rows[i], b.rows[i])) return false;
  }
  return true;
}

export class MapRenderer {
  readonly edgeLayer = svgEl("g");
  readonly nodeLayer = svgEl("g");

  // 差分更新用: id → DOM
  private nodeEls = new Map<number, SVGGElement>();
  private edgeEls = new Map<number, SVGPathElement>();
  private nodeShape = new Map<number, NodeShape>(); // 内側を作り直す判定用
  // 直前に書いた transform。同じ値の setAttribute はスタイル無効化を
  // 起こすだけ無駄なので書かない（プロファイル上いちばん重い JS 呼び出しだった）
  private nodeTf = new Map<number, string>();
  private edgeD = new Map<number, string>();
  private domOrderSig = ""; // DOM の並び（= 重なり順）を直す判定用

  /** id を指定して要素を引く（書き出しに写すため） */
  nodeEl(id: number): SVGGElement | undefined {
    return this.nodeEls.get(id);
  }

  edgeEl(id: number): SVGPathElement | undefined {
    return this.edgeEls.get(id);
  }

  /** 選ばれた箱に印を付ける。レイアウトを見直さない軽い塗り替え（値は main.ts のもの） */
  paintSelection(sel: Set<number>): void {
    for (const [id, g] of this.nodeEls) g.classList.toggle("selected", sel.has(id));
  }

  private shapeOf(b: Box, p: Scene): NodeShape {
    const n = b.node;
    return {
      w: b.w,
      h: b.h,
      folded: n.fold !== null,
      buried: b.buried,
      // 言語の読み込みは後から効くので、世代も見る
      epoch: languageEpoch(),
      // 畳んでいれば summary が字になる。summary だけ変わっても描き直すように
      label: n.fold !== null ? foldName(n) : labelOf(n),
      rows: b.rows,
      // 画像は「まだ読めていない」から「読めた」へ後から変わる
      urls: b.rows.map((r) => (r.kind === "image" ? p.imageUrl(r.path) : null)),
      hint: p.imageHint,
    };
  }

  /** 場面を DOM に写す。文書順（= 重なり順）も合わせる。 */
  draw(p: Scene): void {
    const L = p.layout;
    // ---- DOM を差分更新する ----
    // 位置(transform)と class は毎回書き換えても安い。高いのは要素の生成と
    // 破棄なので、そこは「中身が変わったノードだけ」に絞る。
    const seen = new Set<number>();

    for (const id of L.order) {
      const b = L.boxes.get(id);
      if (!b) continue;
      seen.add(id);
      const n: core.Node = b.node;

      // --- エッジ（親への曲線）---
      const ends = edgeEnds(L, id);
      if (ends) {
        let path = this.edgeEls.get(id);
        if (!path) {
          path = svgEl("path", { class: "edge" });
          this.edgeLayer.append(path);
          this.edgeEls.set(id, path);
        }
        const d = edgePath(ends.from, ends.to);
        if (this.edgeD.get(id) !== d) {
          path.setAttribute("d", d);
          this.edgeD.set(id, d);
        }
      } else {
        const stale = this.edgeEls.get(id);
        if (stale) {
          stale.remove();
          this.edgeEls.delete(id);
          this.edgeD.delete(id);
        }
      }

      // --- ノード本体 ---
      let g = this.nodeEls.get(id);
      if (!g) {
        g = svgEl("g", { class: "node" });
        g.dataset.id = String(id);
        this.nodeLayer.append(g);
        this.nodeEls.set(id, g);
        this.nodeShape.delete(id); // 新規なので必ず中身を作る
      }
      // **文書から決まるクラスだけ**を、1 つずつ付け外しする
      g.classList.toggle("root", b.parent === null);
      g.classList.toggle("folded", n.fold !== null);
      const tf = `translate(${b.x} ${b.y})`;
      if (this.nodeTf.get(id) !== tf) {
        g.setAttribute("transform", tf);
        this.nodeTf.set(id, tf);
      }

      const shape = this.shapeOf(b, p);
      if (sameShape(this.nodeShape.get(id), shape)) continue; // 中身は据え置き
      this.nodeShape.set(id, shape);
      g.replaceChildren();
      g.append(
        // 角丸は状態（畳んでいるか）で変わるだけの定数なので CSS が持つ。
        // ここが出すのはレイアウトが計算した数だけ
        svgEl("rect", { class: "box", width: b.w, height: b.h }),
      );
      const text = n.fold !== null ? foldName(n) : labelOf(n);
      const label = svgEl("text", {
        class: "label" + (text === "" ? " empty" : ""),
        x: rowOf(n).padX,
        y: rowOf(n).rowH / 2,
        // font-size は CSS ではなく属性で入れる（同じ数字を 2 箇所に置かない）
        "font-size": rowOf(n).fontPx,
      });
      label.textContent = n.fold !== null ? hiddenLabel(n, b.buried) : displayLabel(text);
      const t = svgEl("title");
      t.textContent = n.fold !== null ? `${text}\n(${b.buried} folded)` : text;
      g.append(label, t);
      // ラベルの下に、本文から起こしたカードを積む。**形は drawCard が持つ**
      // — ここが決めるのは「どこに置くか」だけ
      for (let i = 0; i < b.rows.length; i++) {
        const rect = cardRect(b, i);
        if (rect === null) continue;
        g.append(
          ...drawCard(
            b.rows[i],
            { rect, rowY: rowTop(b.rows, i), boxW: b.w, spot: `${id},${i}` },
            p.imageUrl,
            p.imageHint,
          ),
        );
      }
    }

    // 見えなくなったノード / エッジを片付ける
    for (const [id, el] of this.nodeEls) {
      if (seen.has(id)) continue;
      el.remove();
      this.nodeEls.delete(id);
      this.nodeShape.delete(id);
      this.nodeTf.delete(id);
    }
    for (const [id, el] of this.edgeEls) {
      if (seen.has(id)) continue;
      el.remove();
      this.edgeEls.delete(id);
      // 値キャッシュも一緒に捨てる。残すと、畳んで戻したときに
      // 「テキストが元通り = 署名も元通り」で書き換えがスキップされ、
      // 作り直した空の <path> に d が入らないままエッジが消える
      this.edgeD.delete(id);
    }

    // DOM の並び = 重なり順。文書順が変わったときだけ並べ直す
    // （既存要素の append は「移動」であって作り直しではない）
    const orderSig = L.order.join(",");
    if (orderSig !== this.domOrderSig) {
      for (const id of L.order) {
        const el = this.nodeEls.get(id);
        if (el) this.nodeLayer.append(el);
      }
      this.domOrderSig = orderSig;
    }
  }
}
