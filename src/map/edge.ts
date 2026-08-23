// 親子をつなぐラインの形。DOM を知らない、経路（SVG の d）を作るだけの層。
//
//   親の縁 --曲線--> 子の縁
//
// 座標はすべて x・y のローカル座標（親の出口が原点）で組む。
//
// 経路は「制御点2つをそのまま持つ三次ベジェ」1 種類のみ。かつては経路の種類
// (quad/cubic/sweep/arc/line/diagonal/elbow/spine) や見た目の修飾
// (先細り・手描き風ゆらぎ・破線・階層別の太さ・下線)を選べる調整パネルが
// あったが、2026-08-15 にパネルごと撤去した。パネルの識別子は消えても
// 「9 種類・6 修飾を切り替えられる」というエンジンの複雑さ自体は残っていて、
// 実際に選ばれ続けているのはこの 1 本だけだった。使われない経路を選択肢
// として残すのは「今だけを見て組む」という方針に反するので、生きている
// 式だけへ畳んだ。

import { type Pt, round2 } from "./geometry.ts";

/** 見た目の固定パラメータ。実文書の上で詰めた値（出発点は見本 Vector.svg）。 */
export const EDGE = {
  // ハンドル2つをそのまま持つ三次ベジェ。子を (1,1) とする正規化座標で、
  // h1 は親から、h2 は子から測る（親側は縦に立ち上がり、子側は横から入る）
  h1u: 0.08,
  h1v: 0.27,
  h2u: 0.58,
  h2v: 0.05,
  spread: 0.6, // 親の辺のうち何割を「付け根の帯」に使うか。0 で 1 点から出る
  width: 1.7,
};

/** 経路の一区間。座標は u, v の並び（L は 1 点、C は 3 点）。 */
export interface Seg {
  c: "L" | "C";
  p: number[];
}

/**
 * 親 → 子 の経路をローカル座標で組み立てる。du = 成長軸方向の距離、
 * dv = 兄弟軸方向の段差。始点は常に (0,0)。
 */
export function edgeSegs(du: number, dv: number): Seg[] {
  if (Math.abs(dv) < 0.5) return [{ c: "L", p: [du, dv] }]; // 真横に並ぶ親子は直線
  return [
    {
      c: "C",
      p: [du * EDGE.h1u, dv * EDGE.h1v, du - du * EDGE.h2u, dv - dv * EDGE.h2v, du, dv],
    },
  ];
}

/** 折れ線に落とす（線分距離判定などに使う） */
export function flattenSegs(segs: Seg[], per: number): number[][] {
  const pts: number[][] = [[0, 0]];
  let cu = 0;
  let cv = 0;
  for (const s of segs) {
    if (s.c === "L") {
      pts.push([s.p[0], s.p[1]]);
    } else {
      const [au, av, bu, bv, eu, ev] = s.p;
      for (let i = 1; i <= per; i++) {
        const t = i / per;
        const m = 1 - t;
        pts.push([
          m * m * m * cu + 3 * m * m * t * au + 3 * m * t * t * bu + t * t * t * eu,
          m * m * m * cv + 3 * m * m * t * av + 3 * m * t * t * bv + t * t * t * ev,
        ]);
      }
    }
    cu = s.p[s.p.length - 2];
    cv = s.p[s.p.length - 1];
  }
  return pts;
}

/** ローカル座標 (u, v) を world の "x y" 文字列にする写像 */
type At = (u: number, v: number) => string;

/** 始点 a から、写像 At を作る */
const atOf = (a: Pt): At => (u, v) => `${round2(a.x + u)} ${round2(a.y + v)}`;

/** 経路を d 属性の文字列にする */
export function segsToD(segs: Seg[], a: Pt): string {
  const at = atOf(a);
  let d = `M ${at(0, 0)}`;
  for (const s of segs) {
    const pairs: string[] = [];
    for (let i = 0; i < s.p.length; i += 2) pairs.push(at(s.p[i], s.p[i + 1]));
    d += ` ${s.c} ${pairs.join(", ")}`;
  }
  return d;
}

/** 1 本のエッジをどう描くか */
export interface EdgeDraw {
  d: string;
  width: number;
}

/**
 * 点 a から点 z へのライン。箱ではなく点を受けるのは、ドロップの予告のように
 * 「箱が無い場所」へも同じ形で引きたいため。
 */
export function edgeDraw(a: Pt, z: Pt): EdgeDraw {
  return { d: segsToD(edgeSegs(z.x - a.x, z.y - a.y), a), width: EDGE.width };
}

/**
 * 2 点のあいだに、いまの形の曲線を引く。ドロップ予告のように
 * 「まだノードが無いところ」へ線を伸ばしたいときに使う。
 */
export function edgeHintPath(a: Pt, z: Pt): string {
  return segsToD(edgeSegs(z.x - a.x, z.y - a.y), a);
}
