// ドラッグしたものをどこへ落とすかの決定。DOM も MindMap も知らない純粋な層。
//
// マップでいちばん込み入った判断で、しかも「惜しい」が最も嫌われる場所
// （右に置いたのに兄弟になる、線に落としたのに子になる）。だから見た目を
// 塗る仕事から切り離して、ここだけを単体で試せるようにしてある。

import { type Pt, centerOf, distToSeg } from "./geometry.ts";
import { type Box, GAP } from "./layout.ts";

/**
 * 落とし先。
 * - `0` = target の子にする
 * - `1` = target の直前へ挿入 / `2` = 直後へ挿入
 * - `3` = target の親として割り込む（A→B の線へのドロップ）
 */
export interface DropTarget {
  id: number;
  pos: 0 | 1 | 2 | 3;
}

/** 判定に要るものすべて。世界座標で話す。 */
export interface DropScene {
  /** ポインタの位置 */
  at: Pt;
  /** 文書順の id */
  order: number[];
  boxes: Map<number, Box>;
  /** 子 → 親（線が引かれている組だけ） */
  parentOf: Map<number, number>;
  /** いま掴んでいる部分木。落とし先から外す */
  dragging: Set<number>;
  /** 掴んでいるのが 1 つだけか。複数だと「誰が親になるか」が決まらない */
  single: boolean;
  /** Shift を押しているか */
  preferEdge: boolean;
  /** 子 id → その親へのエッジの折れ線 */
  polyline: (id: number) => Pt[] | null;
}

export interface DropDecision {
  target: DropTarget | null;
  /**
   * 別の親になる候補がすぐ隣にいるか。挿入線だけだと「上の親の末尾」と
   * 「下の親の先頭」が同じ場所に出て区別できないので、迷う場面でだけ
   * 「どの親につくのか」を予告線で足す。
   */
  ambiguous: boolean;
}

const SLOP = 16; // 箱の左右へのはみ出しをどこまで箱の内と見るか
const BAND = 40; // 前後への挿入を狙える帯の広さ
const REACH = GAP.x * 4 + 16; // 「子にする」外側ゾーンを成長軸方向にどこまで伸ばすか
const NEAR = REACH * 0.4; // ここまでは前後への挿入より子を優先する
const SLACK = 18; // 外側ゾーンが兄弟軸方向に箱からはみ出してよい量
const AMBIGUOUS = 26; // 候補どうしがこれより競っていれば迷う場面とみなす

/** 箱の中心から見たポインタの位置と、箱の半分の大きさ */
function local(at: Pt, b: Box) {
  const c = centerOf(b);
  return { du: at.x - c.x, dv: at.y - c.y, hu: b.w / 2, hv: b.h / 2 };
}

/**
 * A→B の線のまんなかに落とす = B の親として割り込む（A→C→B）。
 *
 * Shift を押していなければ**いちばん最後**に判定する。ノードの上でも、その
 * 外側の「子にする」帯でもない、どこにも属さない空間だけを拾う — 頻度の高い
 * 「子にする」から場所を取ると使いにくい、という実際の使用感を優先。
 * 押していれば先に判定し、狙える範囲も広げる。
 */
function findEdge(scene: DropScene): DropTarget | null {
  if (!scene.single) return null;
  let best = scene.preferEdge ? 30 : 16; // 線からこの距離まで拾う
  const band = scene.preferEdge ? 0.1 : 0.3; // 端から何割を狙い所から外すか
  let onEdge: number | null = null;
  for (const id of scene.parentOf.keys()) {
    if (scene.dragging.has(id)) continue;
    const pts = scene.polyline(id);
    if (!pts) continue;
    // 端のほうは「前後に挿入」や「子にする」と紛らわしいので、
    // 長さで測って真ん中あたりだけを狙い所にする
    let total = 0;
    const segLen: number[] = [];
    for (let i = 1; i < pts.length; i++) {
      const l = Math.hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y);
      segLen.push(l);
      total += l;
    }
    let acc = 0;
    for (let i = 1; i < pts.length; i++) {
      const mid = acc + segLen[i - 1] / 2;
      acc += segLen[i - 1];
      if (mid < total * band || mid > total * (1 - band)) continue;
      const d = distToSeg(scene.at, pts[i - 1], pts[i]);
      if (d < best) {
        best = d;
        onEdge = id;
      }
    }
  }
  return onEdge === null ? null : { id: onEdge, pos: 3 };
}

/**
 * どこへ落とすか。優先順は 4 段:
 *   1. 箱の中
 *   2. 外側ゾーンの近い側（NEAR まで）… 前後への挿入より強い
 *   3. 前後への挿入（箱の上下の帯）
 *   4. 外側ゾーンの遠い側（REACH まで）… 誰も取らない空間の受け皿
 *
 * 近くを子に振らないと、次の列の子の帯に吸われて「右に置いたのに兄弟になる」
 * が起きる。逆に遠くまで子を優先させると前後への挿入がほぼ出せなくなるので、
 * そこは前後に譲る。
 */
export function resolveDrop(scene: DropScene): DropDecision {
  // Shift = 線への割り込みを最優先。見つかったかどうかは後の段でも使う
  // （見つかった線を、外側ゾーンや帯が黙って横取りしない）
  const edgeTarget = scene.preferEdge ? findEdge(scene) : null;
  let target: DropTarget | null = edgeTarget;

  const parentFor = (id: number, pos: 0 | 1 | 2 | 3): number =>
    pos === 0 ? id : (scene.parentOf.get(id) ?? -1);

  // 帯は隣の兄弟と重なるので、最初に見つかった相手ではなく「いちばん近い」
  // 相手を選ぶ。文書順で決めていたころは、親が違う子スタックの境目で
  // どちらに倒れるかが実質その場の運になっていた。
  let best = Infinity;
  const cands: { dist: number; parent: number }[] = [];
  for (const id of scene.order) {
    if (scene.dragging.has(id)) continue;
    const b = scene.boxes.get(id);
    if (!b) continue;
    const { du, dv, hu, hv } = local(scene.at, b);
    if (Math.abs(du) > hu + SLOP || Math.abs(dv) > hv + BAND) continue;
    // 箱の中なら 0。外に出た分だけ距離が増える（兄弟軸のほうを重く見る）
    const dist =
      Math.max(0, Math.abs(du) - hu) + Math.max(0, Math.abs(dv) - hv) * 2;
    // ルートに兄弟は無い。上に落ちたものはすべて子になる
    const pos: 0 | 1 | 2 =
      b.n.depth === 1 ? 0 : dv < -hv * 0.4 ? 1 : dv > hv * 0.4 ? 2 : 0;
    cands.push({ dist, parent: parentFor(id, pos) });
    if (dist < best) {
      best = dist;
      if (!edgeTarget) target = { id, pos };
    }
  }

  // 外側ゾーン: 箱の外、成長軸の方向へ少し出たところも「子にする」
  let outTarget: DropTarget | null = null;
  let bestOut = Infinity;
  let outU = Infinity; // 選んだ相手の、箱の外縁からの距離
  for (const id of scene.order) {
    if (scene.dragging.has(id)) continue;
    const b = scene.boxes.get(id);
    if (!b) continue;
    const { du, dv, hu, hv } = local(scene.at, b);
    if (du <= hu || du > hu + REACH || Math.abs(dv) > hv + SLACK) continue;
    const d = du - hu + Math.max(0, Math.abs(dv) - hv) * 2;
    if (d < bestOut) {
      bestOut = d;
      outU = du - hu;
      outTarget = { id, pos: 0 };
    }
  }
  if (outTarget && !edgeTarget && best > 0 && (outU <= NEAR || !target)) {
    target = outTarget;
  }

  if (!target) target = findEdge(scene);

  // 迷う場面かどうかは、**行き先が決まってから**測る。外側ゾーンなどで
  // 差し替えたあとに帯の時点の判定を使うと、予告線の出る/出ないが行き先とずれる
  let rival = Infinity;
  if (target) {
    const chosen = parentFor(target.id, target.pos);
    for (const c of cands) {
      if (c.parent !== chosen && c.dist < rival) rival = c.dist;
    }
  }
  return { target, ambiguous: rival - best <= AMBIGUOUS };
}
