// 指の台帳。**何本が生きていて、前回どこに居たか**だけを持つ。
//
// 「いま何本の指か」は、mindmap.ts の 5 つの状態（パン / 矩形選択 /
// ノードのドラッグ / カードのドラッグ / ドラッグ候補）とは別の次元なので、
// 混ぜない。1 本のときは何も言わず、既存の 1 ポインタの流れがそのまま担う。
//
// **DOM を知らない。** 受け取るのはペインの左上から測った画面 px で、
// 出すのは `map/view.ts` の `Span`。だから値として試験できる。

import type { Span } from "./view.ts";

/** 組にする 2 本。**途中で入れ替えない** — 入れ替わると地図が跳ぶ */
type Pair = [number, number];

export class Fingers {
  private at = new Map<number, { x: number; y: number }>();
  private pair: Pair | null = null;

  get pinching(): boolean {
    return this.pair !== null;
  }

  /** 2 本以上あって組が無いなら、いま生きている先頭の 2 本で組む */
  private form(): void {
    if (this.pair !== null || this.at.size < 2) return;
    const [a, b] = [...this.at.keys()];
    if (a !== undefined && b !== undefined) this.pair = [a, b];
  }

  down(id: number, x: number, y: number): void {
    this.at.set(id, { x, y });
    // 3 本目以降は台帳には載るが、組は最初の 2 本のまま
    this.form();
  }

  /** 組の片方が実際に動いたときだけ、その前後を返す */
  move(id: number, x: number, y: number): { from: Span; to: Span } | null {
    const known = this.at.get(id);
    if (!known) return null;
    this.at.set(id, { x, y });
    const pair = this.pair;
    if (!pair || (pair[0] !== id && pair[1] !== id)) return null;
    if (known.x === x && known.y === y) return null;
    const other = this.at.get(pair[0] === id ? pair[1] : pair[0]);
    if (!other) return null;
    return {
      from: { a: { x: other.x, y: other.y }, b: { x: known.x, y: known.y } },
      to: { a: { x: other.x, y: other.y }, b: { x, y } },
    };
  }

  up(id: number): void {
    this.at.delete(id);
    if (!this.pair) return;
    if (this.pair[0] !== id && this.pair[1] !== id) return;
    // 組の片方が離れた。3 本置いて 1 本離した場合は残りで組み直す
    this.pair = null;
    this.form();
  }

  clear(): void {
    this.at.clear();
    this.pair = null;
  }
}
