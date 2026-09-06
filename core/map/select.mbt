// 選択。何を選んでいるかの値と、入力（クリック・矩形・矢印）でそれがどう変わるか。
// DOM も地図も知らない — 地図は入力を値にして渡し、返った値を塗るだけ。
// 決めは docs/superpowers/specs/2026-09-04-select-design.md と spec.md「Mindmap 側」。
//
// id は文書順の通し番号なので、数の順がそのまま文書順。

///|
/// 選んでいるノード（文書順）と、範囲選択・矢印の基点
pub(all) struct Selection {
  ids : Array[Int]
  anchor : Int?
} derive(Eq, Debug, ToJson)

///|
pub let none : Selection = { ids: [], anchor: None, }

///|
pub(all) enum Modifier {
  Plain
  Shift
  Mod
} derive(Eq, Debug)

///|
/// 重複を除いて文書順に
fn sorted(ids : Array[Int]) -> Array[Int] {
  let set : Set[Int] = Set::from_array(ids)
  let out = set.iter().collect()
  out.sort()
  out
}

///|
fn last(ids : Array[Int]) -> Int? {
  ids.last()
}

///|
/// 選ぶ。`Shift` は anchor から文書順に範囲（anchor は動かない）、`Mod` は足す・外す
pub fn click(
  sel : Selection,
  id : Int,
  mod : Modifier,
  order : Array[Int],
) -> Selection {
  match mod {
    Mod => {
      let ids = if sel.ids.contains(id) {
        sel.ids.filter(x => x != id)
      } else {
        sorted(sel.ids + [id])
      }
      { ids, anchor: if ids.contains(id) { Some(id) } else { last(ids) }, }
    }
    Shift =>
      match sel.anchor {
        Some(anchor) =>
          match (order.search(anchor), order.search(id)) {
            (Some(a), Some(b)) => {
              let (lo, hi) = if a < b { (a, b) } else { (b, a) }
              { ids: sorted(order[lo:hi + 1].to_owned()), anchor: sel.anchor, }
            }
            _ => { ids: [id], anchor: Some(id), }
          }
        None => { ids: [id], anchor: Some(id), }
      }
    Plain => { ids: [id], anchor: Some(id), }
  }
}

///|
/// 矩形（world）に触れる箱を全部。anchor は文書順の最後
pub fn rubber(l : Layout, r : Rect) -> Selection {
  let ids = l.order.filter(id => {
    match l.boxes.get(id) {
      Some(b) =>
        b.x < r.x + r.w && r.x < b.x + b.w && b.y < r.y + r.h && r.y < b.y + b.h
      None => false
    }
  })
  { ids, anchor: last(ids), }
}

///|
/// 点から矩形までの、軸ごとの距離。中なら 0
fn gap_to(r : Rect, x : Double, y : Double) -> (Double, Double) {
  (
    @cmp.maximum(@cmp.maximum(r.x - x, 0.0), x - (r.x + r.w)),
    @cmp.maximum(@cmp.maximum(r.y - y, 0.0), y - (r.y + r.h)),
  )
}

///|
fn inside(r : Rect, x : Double, y : Double) -> Bool {
  let (dx, dy) = gap_to(r, x, y)
  dx == 0.0 && dy == 0.0
}

///|
/// 見た目の箱の外まで当たりを広げる幅（world px）。`pad` は四方、`edge` は子の見えない
/// 端のノードが枝の伸びる向きにさらに伸ばす分（根は向きが無いので伸びない）
pub(all) struct Reach {
  pad : Double
  edge : Double
} derive(Eq, Debug)

///|
/// 見た目どおり
pub let exact : Reach = { pad: 0, edge: 0, }

///|
/// ⋯ の Easy grab。見た目は変えず、判定だけ箱の外へ広げる。pad は四方 —
/// 兄弟の隙間（gap.y）は丸ごと飲み、親子の隙間（gap.x）はほぼ埋まる。
/// edge は子の見えない端のノードが、枝の伸びる向きにさらに伸ばす分
pub let grab : Reach = { pad: 41, edge: 63, }

///|
fn grown(b : Rect, pad : Double) -> Rect {
  { x: b.x - pad, y: b.y - pad, w: b.w + pad * 2.0, h: b.h + pad * 2.0, }
}

///|
/// 箱 1 つの当たりの範囲（near, far）。`near` は pad の分、`far` はそれに端の伸びを
/// 足したもの（near ⊆ far）
pub fn reach_of(b : Box, r : Reach, parents : Set[Int]) -> (Rect, Rect) {
  let near = grown(b.rect(), r.pad)
  let out = if b.parent is Some(_) && !parents.contains(b.node.id) {
    r.edge
  } else {
    0.0
  }
  let left = b.parent is Some(p) && dir(p.side) == -1
  (
    near,
    { ..near, x: near.x - (if left { out } else { 0.0 }), w: near.w + out, },
  )
}

///|
/// world の点がどの箱に居るか。当たりは見た目の箱を `reach` の分だけ広げた範囲。
/// 複数の範囲に入れば見た目の箱に近い方 — ふつうは直線距離。ただし端の伸び（far）
/// だけで届く箱が居るときは行で読む: y の近さ、同じなら x の近さ（端の伸びは横に長く、
/// 直線距離では隣の行の箱に負けてしまうため）。同じ近さなら文書順の後ろ。外なら None
pub fn hit(l : Layout, x : Double, y : Double, reach : Reach) -> Int? {
  let parents : Set[Int] = Set([])
  for b in l.boxes.values() {
    match b.parent {
      Some(p) => parents.add(p.id)
      None => ()
    }
  }
  // (id, dx, dy, far だけで届いたか)
  let found : Array[(Int, Double, Double, Bool)] = []
  for id in l.order {
    guard l.boxes.get(id) is Some(b) else { continue }
    let (near, far) = reach_of(b, reach, parents)
    guard inside(far, x, y) else { continue }
    let (dx, dy) = gap_to(b.rect(), x, y)
    found.push((id, dx, dy, !inside(near, x, y)))
  }
  guard found.length() > 0 else { return None }
  let rowwise = found.iter().any(f => f.3)
  let key = (f : (Int, Double, Double, Bool)) => {
    if rowwise {
      (f.2, f.1)
    } else {
      (@math.hypot(f.1, f.2), 0.0)
    }
  }
  // 文書順の後ろが勝つよう、同じ近さでは後ろで置き換える
  let mut best = found[0]
  for f in found[1:] {
    let (a, b) = (key(f), key(best))
    if a.0 < b.0 || (a.0 == b.0 && a.1 <= b.1) {
      best = f
    }
  }
  Some(best.0)
}

///|
pub fn all(l : Layout) -> Selection {
  { ids: sorted(l.order), anchor: last(l.order), }
}

///|
pub(all) enum Arrow {
  Up
  Down
  Left
  Right
} derive(Eq, Debug)

///|
/// キーの名（`e.key`）が矢印なら
pub fn arrow_of(key : String) -> Arrow? {
  match key {
    "ArrowUp" => Some(Up)
    "ArrowDown" => Some(Down)
    "ArrowLeft" => Some(Left)
    "ArrowRight" => Some(Right)
    _ => None
  }
}

///|
/// 根からの深さ。Layout は持たないので親を辿って数える。
/// 未知の id は根と同じ 0（`arrow` は先に箱で弾くので届かない）
fn depth_of(l : Layout, id : Int) -> Int {
  let mut d = 0
  let mut cur = l.boxes.get(id)
  while cur is Some(b) && b.parent is Some(p) {
    d += 1
    cur = l.boxes.get(p.id)
  }
  d
}

///|
/// 矢印 1 回ぶんの行き先。行けなければ None。何も選んでいなければ先頭。
///
/// - 上下 … **同じ深さの列**を文書順に辿り、端でループする。兄弟に限らずいとこも含む
/// - 左右 … **画面の向き**で読む。根と右の枝は ← が親・→ が子、左の枝は鏡像。
///   子が無ければ先頭へ回る（行き止まりで無反応になるより一周できるほうが迷わない）
pub fn arrow(l : Layout, anchor : Int?, key : Arrow) -> Int? {
  let order = l.order
  guard order.length() > 0 else { return None }
  guard anchor is Some(anchor) else { return Some(order[0]) }
  guard l.boxes.get(anchor) is Some(cur) else { return None }
  if key is Up || key is Down {
    let depth = depth_of(l, anchor)
    let level = order.filter(id => depth_of(l, id) == depth)
    guard level.search(anchor) is Some(i) else { return None }
    let step = if key is Up { -1 } else { 1 }
    return Some(level[(i + step + level.length()) % level.length()])
  }
  // 側を符号に読むのは dir だけ、という不変条件を守る
  let d = match cur.parent {
    Some(p) => dir(p.side)
    None => 1
  }
  let to_parent = if d == -1 { key is Right } else { key is Left }
  if to_parent {
    return cur.parent.map(p => p.id)
  }
  let kid = order
    .iter()
    .find_first(id => {
      match l.boxes.get(id) {
        Some(b) => b.parent is Some(p) && p.id == anchor
        None => false
      }
    })
  match kid {
    Some(k) => Some(k)
    None => Some(order[0])
  }
}

///|
/// Shift+矢印。行き先を足す。行き先が既に選ばれていれば、いま居た側を外して縮める
pub fn extend_to(sel : Selection, next : Int) -> Selection {
  // arrow は深さが 1 つしか無い列や、子の無いノードから回った先で anchor
  // 自身を返すことがある。そのまま外すと anchor が選択から消えてしまう
  guard sel.anchor != Some(next) else { return sel }
  if sel.ids.contains(next) && sel.ids.length() > 1 && sel.anchor is Some(a) {
    return { ids: sel.ids.filter(x => x != a), anchor: Some(next), }
  }
  { ids: sorted(sel.ids + [next]), anchor: Some(next), }
}

///|
/// 親の id。根なら None
pub fn parent_of(l : Layout, id : Int) -> Int? {
  match l.boxes.get(id) {
    Some(b) => b.parent.map(p => p.id)
    None => None
  }
}

///|
/// 同じ親の子（根なら根どうし）を文書順に
fn siblings_of(l : Layout, id : Int) -> Array[Int] {
  let p = parent_of(l, id)
  l.order.filter(x => parent_of(l, x) == p)
}

///|
pub fn prev_sibling(l : Layout, id : Int) -> Int? {
  let s = siblings_of(l, id)
  match s.search(id) {
    Some(i) => if i > 0 { Some(s[i - 1]) } else { None }
    None => None
  }
}

///|
pub fn next_sibling(l : Layout, id : Int) -> Int? {
  let s = siblings_of(l, id)
  match s.search(id) {
    Some(i) => if i < s.length() - 1 { Some(s[i + 1]) } else { None }
    None => None
  }
}

///|
/// ちょうど 1 つ選んでいる id。宛先が 1 つに決まる操作はこれを見る
pub fn solo(sel : Selection) -> Int? {
  if sel.ids.length() == 1 {
    sel.anchor
  } else {
    None
  }
}
