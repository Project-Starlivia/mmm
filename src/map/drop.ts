// ドラッグしたものをどこへ落とすかの決定。DOM も MindMap も知らない純粋な層。
//
// マップでいちばん込み入った判断で、しかも「惜しい」が最も嫌われる場所
// （右に置いたのに兄弟になる、線に落としたのに子になる）。だから見た目を
// 塗る仕事から切り離して、ここだけを単体で試せるようにしてある。

import { type Pt, centerOf, distToSeg } from "./geometry.ts";
import { type Box, GAP, dirOf } from "./layout.ts";

/**
 * ノード相手の落とし先。
 * - `0` = target の子にする
 * - `1` = target の直前へ挿入 / `2` = 直後へ挿入
 * - `3` = target の親として割り込む（A→B の線へのドロップ）
 */
export interface DropTarget {
  id: number;
  pos: 0 | 1 | 2 | 3;
}

/**
 * 落とし先。**3 つだけ**:
 * - `node` … 従来どおり（0 = 子 / 1 = 直前 / 2 = 直後 / 3 = 線への割り込み）
 * - `side` … ルートの脇。その側の末尾へ（区切りは要るときだけ書かれる）
 * - `group` … Mod を押したまま落とした。そこに新しいグループ
 */
export type Drop =
  | { kind: "node"; id: number; pos: 0 | 1 | 2 | 3 }
  | { kind: "side"; root: number; left: boolean }
  | { kind: "group"; target: number; before: boolean; left: boolean };

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
  /** ドロップの瞬間に Mod を押しているか（新しいグループとして落とす） */
  newGroup: boolean;
  /** 子 id → その親へのエッジの折れ線 */
  polyline: (id: number) => Pt[] | null;
}

export interface DropDecision {
  drop: Drop | null;
}

const SLOP = 16; // 箱の左右へのはみ出しをどこまで箱の内と見るか
const BAND = 40; // 前後への挿入を狙える帯の広さ
const OPEN = BAND * 5; // 開いている側では同じ帯をここまで広げる
const REACH = GAP.x * 4 + 16; // 「子にする」外側ゾーンを成長軸方向にどこまで伸ばすか
// 子を優先するのは**親と子の列のあいだの通路**まで。次の列に入ったら、そこは
// その列の住人（前後への挿入）のもの。通路より広く取っていたころは、列 N の
// ノードが列 N+1 の兄弟挿入を横取りし、「下の兄弟にしたいのに隣の枝の子になる」
// が起きていた（`f` の下の空きを、隣に並ぶ `b` が丸ごと持っていく）
const NEAR = GAP.x;
const SLACK = 18; // 外側ゾーンが兄弟軸方向に箱からはみ出してよい量

/**
 * 箱の中心から見たポインタの位置と、箱の半分の大きさ。
 * `du` は**その枝が伸びる向き**を正とする（左の枝では左が正）ので、
 * 外側ゾーンの式を左右で書き分けなくてよい。
 */
function local(at: Pt, b: Box) {
  const c = centerOf(b);
  return {
    du: (at.x - c.x) * dirOf(b.n),
    dv: at.y - c.y,
    hu: b.w / 2,
    hv: b.h / 2,
  };
}

/** 非 Mod の外側ゾーンと同じ範囲（成長軸は REACH、それ以外は SLACK まで）に、
 *  ポインタがその箱から見て収まっているか */
function withinReach(at: Pt, b: Box): boolean {
  const { du, dv, hu, hv } = local(at, b);
  return Math.abs(du) - hu <= REACH && Math.abs(dv) - hv <= SLACK;
}

/**
 * いちばん近い木の根（複数の木が縦に積まれているので、どれの脇かを決める）。
 * どの木からも遠い空所では `-1`（= 見つからない）を返す — この上限が無いと、
 * Mod を押したままの空振り（キャンセルのつもり）が必ずどこかの根への移動
 * として成立してしまう。
 *
 * 「木から遠いか」は**根自身の箱ではなく、木のどの箱でも**測る。グループが
 * 複数あれば枝は根から縦に大きく離れた位置にも並ぶので、根の小さい箱だけを
 * 基準にすると、根のすぐ近くにしか Mod+ドロップが効かなくなる
 * （新しいグループを作る Mod+ドロップの狙い所そのものが遠い枝の隣であるため）。
 *
 * 上限は「掴んでいる木も含めて」どれかの箱に届いているかで見る。掴んでいる
 * 木の真上で離したときは、そこは紛れもなく木の上（キャンセルしたい空所ではない）
 * なので、その場合は掴んでいない側の木を距離に関わらず探しに行く。
 */
function nearestRoot(scene: DropScene): number {
  let reachable = false;
  for (const id of scene.order) {
    const b = scene.boxes.get(id);
    if (b && withinReach(scene.at, b)) {
      reachable = true;
      break;
    }
  }
  if (!reachable) return -1;

  // どの木かも、**上の上限とまったく同じ尺度で測る** — 木のどの箱までが
  // いちばん近いか。根の箱の中心だけで測っていたころは木の広がりが式に
  // 入らず、枝の箱のど真ん中で Mod ドロップしても隣の木へ落ちた（素の
  // ドラッグは正しく指した枝を選ぶので、同じ位置で答えが食い違っていた）。
  const rootOf = new Map<number, number>();
  const treeOf = (id: number): number => {
    const seen = rootOf.get(id);
    if (seen !== undefined) return seen;
    const up = scene.parentOf.get(id);
    const r = up === undefined ? id : treeOf(up);
    rootOf.set(id, r);
    return r;
  };
  const near = new Map<number, number>(); // 根 → その木のどれかの箱までの最短
  for (const id of scene.order) {
    const b = scene.boxes.get(id);
    if (!b) continue;
    const r = treeOf(id);
    if (scene.dragging.has(r)) continue; // 掴んでいる木そのものは候補外
    // 箱までの距離（中に居れば 0）。中心までの距離だと、大きく広がった木ほど
    // 遠く見えてしまう
    const dx = Math.max(0, b.x - scene.at.x, scene.at.x - (b.x + b.w));
    const dy = Math.max(0, b.y - scene.at.y, scene.at.y - (b.y + b.h));
    const d = dx + dy;
    const seen = near.get(r);
    if (seen === undefined || d < seen) near.set(r, d);
  }
  let best = Infinity;
  let hit = -1;
  for (const [r, d] of near) {
    if (d < best) {
      best = d;
      hit = r;
    }
  }
  return hit;
}

/**
 * Mod を押したまま落とすときのスロット。**ルート直下の並びの隙間**が全部
 * 候補になり、いちばん近い枝の上半分/下半分で「手前/後ろ」が決まる。
 * その側に枝がまだ無ければ「その側の末尾」（= 同じ結果に落ちる縮退）。
 */
function findSlot(scene: DropScene, root: number, left: boolean): Drop {
  let best = Infinity;
  let target = -1;
  let before = false;
  for (const id of scene.order) {
    if (scene.dragging.has(id)) continue;
    if (scene.parentOf.get(id) !== root) continue;
    const b = scene.boxes.get(id);
    if (!b || b.n.left !== left) continue;
    const c = centerOf(b);
    const d = Math.abs(scene.at.y - c.y);
    if (d < best) {
      best = d;
      target = id;
      before = scene.at.y < c.y;
    }
  }
  return target === -1
    ? { kind: "side", root, left }
    : { kind: "group", target, before, left };
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
    // 狙い所の弧長の窓。**区間を窓で切ってから測る** — 区間の中点が窓の中か
    // どうかで捨てていたころは、真横に並ぶ親子（`edgeSegs` が 1 本の直線に
    // 畳む = 折れ線が 2 点）だと中点が必ず 50% になり、端を外す規則が一度も
    // 発火しなかった。線の端まで拾えてしまい、Shift 中は箱の内側まで
    // 割り込みに飲まれていた。
    const lo = total * band;
    const hi = total * (1 - band);
    let acc = 0;
    for (let i = 1; i < pts.length; i++) {
      const a0 = acc;
      const a1 = acc + segLen[i - 1];
      acc = a1;
      const from = Math.max(a0, lo);
      const to = Math.min(a1, hi);
      if (to <= from || a1 === a0) continue;
      const t0 = (from - a0) / (a1 - a0);
      const t1 = (to - a0) / (a1 - a0);
      const p = pts[i - 1];
      const q = pts[i];
      const at = (t: number) => ({
        x: p.x + (q.x - p.x) * t,
        y: p.y + (q.y - p.y) * t,
      });
      const d = distToSeg(scene.at, at(t0), at(t1));
      if (d < best) {
        best = d;
        onEdge = id;
      }
    }
  }
  return onEdge === null ? null : { id: onEdge, pos: 3 };
}

/**
 * 列の上端 / 下端のノードと、その「開いている側」。
 *
 * 兄弟は縦に積まれるので、上端の**上**と下端の**下**には競う相手がそもそも
 * 居ない。そこは帯を広げても何も奪わない。同じ親でも左右で別の列になるので、
 * 端は (親, 側) ごとに数える。
 *
 * 上下は文書順ではなく**箱の y** で決める（見た目の端がそのまま端になる）。
 * 掴んでいるノードも数に入れる — ドラッグ中もその箱は元の場所に描かれた
 * ままなので、見た目の上下端は動かない。
 */
function openEnds(scene: DropScene): { up: Set<number>; down: Set<number> } {
  const first = new Map<string, Box>();
  const last = new Map<string, Box>();
  for (const id of scene.order) {
    const b = scene.boxes.get(id);
    if (!b) continue;
    const parent = scene.parentOf.get(id);
    if (parent === undefined) continue; // 根に兄弟は無い
    const key = `${parent},${b.n.left}`;
    const f = first.get(key);
    if (!f || b.y < f.y) first.set(key, b);
    const l = last.get(key);
    if (!l || b.y + b.h > l.y + l.h) last.set(key, b);
  }
  return {
    up: new Set([...first.values()].map((b) => b.n.id)),
    down: new Set([...last.values()].map((b) => b.n.id)),
  };
}

/**
 * 通路（親の外側ゾーン）の縦の位置から、その親の子のどの隣かを決める。
 * 子が 1 つも無ければ `null`（= 「最初の子にする」に落ちる）。
 *
 * 子は縦に積まれるので、いちばん近い子の上半分/下半分で手前/後ろが決まる。
 * これは箱の帯（前後への挿入）とまったく同じ読み方で、場所が通路に変わる
 * だけ — 通路と子の列で意味が変わらないので、指した高さがそのまま着地点。
 */
function slotAmongKids(scene: DropScene, parent: number): DropTarget | null {
  let best = Infinity;
  let hit: DropTarget | null = null;
  for (const id of scene.order) {
    if (scene.dragging.has(id)) continue;
    if (scene.parentOf.get(id) !== parent) continue;
    const b = scene.boxes.get(id);
    if (!b) continue;
    const c = centerOf(b);
    const d = Math.abs(scene.at.y - c.y);
    if (d < best) {
      best = d;
      hit = { id, pos: scene.at.y < c.y ? 1 : 2 };
    }
  }
  return hit;
}

/**
 * 列の上端より上 / 下端より下の空白。**誰も取らなかったときだけ**拾う
 * 最後の受け皿なので、外側ゾーン（子にする）も線への割り込みも奪わない。
 *
 * 横は帯と同じ「その列に居ること」（`hu + SLOP`）のまま。縦だけを `OPEN` まで
 * 広げる。無制限にしないのは、**横に外す以外のキャンセルの手を残す**ため —
 * 列の x に収まったまま上下にいくら離してもどこかへ落ちてしまう、では
 * ドラッグを諦める手が横だけになる。
 */
function findOpenEnd(scene: DropScene): DropTarget | null {
  const ends = openEnds(scene);
  let best = Infinity;
  let hit: DropTarget | null = null;
  for (const id of scene.order) {
    if (scene.dragging.has(id)) continue;
    const b = scene.boxes.get(id);
    if (!b) continue;
    const { du, dv, hu, hv } = local(scene.at, b);
    if (Math.abs(du) > hu + SLOP) continue;
    const over = Math.abs(dv) - hv;
    if (over <= 0 || over > OPEN) continue;
    const up = dv < 0;
    if (!(up ? ends.up : ends.down).has(id)) continue;
    if (over < best) {
      best = over;
      hit = { id, pos: up ? 1 : 2 };
    }
  }
  return hit;
}

/**
 * どこへ落とすか。優先順は 5 段:
 *   1. 箱の中
 *   2. 前後への挿入（箱の上下の帯）
 *   3. 線への割り込み（Shift ならここが 1 番）
 *   4. 外側ゾーン（REACH まで）… 近い側は NEAR まで帯より強い
 *   5. 列の上端の上 / 下端の下（OPEN まで）… 誰も取らなかった空白
 *
 * 近くを子に振らないと、次の列の子の帯に吸われて「右に置いたのに兄弟になる」
 * が起きる。逆に遠くまで子を優先させると前後への挿入がほぼ出せなくなるので、
 * そこは前後に譲る。
 *
 * **線は外側ゾーンより先**。後ろに置いていたころは、親が子を持つほど親の帯が
 * 線を丸ごと覆い、その子への割り込みが一切狙えなかった（子が 3 つあれば
 * 真ん中の子の線は帯のど真ん中を通る）。線は端から 30% を狙い所から外すので、
 * 先に置いても帯は三層に分かれるだけで消えない —
 * **付け根側 = 親のゾーン / 真ん中 = 線 / 子側 = 前後への挿入**。
 * 子を 1 つも持たない枝からは線が出ないので、その帯は丸ごと親のまま。
 */
export function resolveDrop(scene: DropScene): DropDecision {
  // ポインタがその箱の中心より左か。**側を決めるのはここだけ**
  const sideOf = (b: Box): boolean => scene.at.x < centerOf(b).x;

  // Mod を押している間は、スロットだけが生きる（深いところの行き先は休む）
  if (scene.newGroup) {
    const near = nearestRoot(scene);
    if (near === -1) return { drop: null };
    const rb = scene.boxes.get(near);
    if (!rb) return { drop: null };
    return { drop: findSlot(scene, near, sideOf(rb)) };
  }

  // Shift = 線への割り込みを最優先。見つかったかどうかは後の段でも使う
  // （見つかった線を、外側ゾーンや帯が黙って横取りしない）
  const edgeTarget = findEdge(scene);
  let target: DropTarget | null = scene.preferEdge ? edgeTarget : null;
  const shiftWon = target !== null;

  // 帯は隣の兄弟と重なるので、最初に見つかった相手ではなく「いちばん近い」
  // 相手を選ぶ。文書順で決めていたころは、親が違う子スタックの境目で
  // どちらに倒れるかが実質その場の運になっていた。
  let best = Infinity;
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
    if (dist < best) {
      best = dist;
      if (!shiftWon) target = { id, pos };
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
    // 根は両方向に伸びる木の付け根なので、成長軸の判定を絶対値で見る
    // （`local` の du は dirOf で片側だけ正にしてあるので、根では素のままだと右側しか拾えない）
    const isRoot = scene.parentOf.get(id) === undefined;
    const growOffset = isRoot ? Math.abs(du) : du;
    if (growOffset <= hu || growOffset > hu + REACH || Math.abs(dv) > hv + SLACK)
      continue;
    const d = growOffset - hu + Math.max(0, Math.abs(dv) - hv) * 2;
    if (d < bestOut) {
      bestOut = d;
      outU = growOffset - hu;
      // 既に子がいるなら、通路の**縦の位置**で「どの子の隣か」まで決める。
      // 通路は子の列そのものではないが、縦は子の列とそのまま同じ意味を持つ
      // （子は縦に積まれるので）。ここを一律「末尾に足す」に潰していたころは、
      // 通路のどこを指しても印が最後の子の下に 1 点で出て、指した場所と
      // 着地点が対応しなかった。根は側とグループの話が乗るので触らない
      outTarget = (isRoot ? null : slotAmongKids(scene, id)) ?? { id, pos: 0 };
    }
  }
  // 外側ゾーンの**近い側は帯より強い**（右に置いたのに兄弟になる、を防ぐ）。
  // 遠い側は「誰も取らない空間の受け皿」なので、帯が居れば譲る。
  //
  // **既知の穴**: `!edgeTarget` は「線が見つかったか」だけを見て外側ゾーンを
  // 落とすが、線はすぐ下の `if (!target)` でしか据えられない。帯が既に
  // 埋まっていると線も据えられず、調停していた二者のどちらでもない帯が残る
  // — 通路の付け根側の細い帯で、着地する親が 1 段上へ黙って飛ぶ。
  // 直すには「線が勝つ」か「外側ゾーンが勝つ」かを決める必要があり、
  // どちらにしても通路の三層（付け根=親 / 真ん中=線 / 子側=前後）の
  // 見え方が変わるので、意図して手を付けずに残してある。
  if (outTarget && !edgeTarget && best > 0 && (outU <= NEAR || !target)) {
    target = outTarget;
  }

  if (!target) target = edgeTarget;

  // 誰も取らなかった空白は、開いている側の上下端が受ける
  if (!target) target = findOpenEnd(scene);

  // 木の根が相手の「子にする」は、**どちら側か**まで決まって初めて意味を持つ。
  // ポインタが根の中心のどちら側にあるかで振り分ける（素のドラッグでの左右）
  const asDrop = (t: DropTarget): Drop => {
    if (t.pos !== 0) return { kind: "node", id: t.id, pos: t.pos };
    if (scene.parentOf.get(t.id) !== undefined) {
      return { kind: "node", id: t.id, pos: 0 };
    }
    const rb = scene.boxes.get(t.id);
    return { kind: "side", root: t.id, left: rb ? sideOf(rb) : false };
  };
  return { drop: target ? asDrop(target) : null };
}
