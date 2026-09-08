// ドラッグしたものをどこへ落とすかの決定。DOM も地図も知らない純粋な層。
//
// マップでいちばん込み入った判断で、しかも「惜しい」が最も嫌われる場所
// （右に置いたのに兄弟になる、近くの子の帯に吸われて狙った子と違う所に落ちる）。
// だから見た目を塗る仕事から切り離して、ここだけを単体で試せるようにしてある。

///|
/// ノード相手の落とし先（内部の刻み）。pos は 0 = target の子 / 1 = 直前 / 2 = 直後
priv struct Target {
  id : Int
  pos : Int
}

///|
/// 落とし先。**2 つだけ**:
/// - `Node` … pos 0 = 子の末尾 / 1 = 直前 / 2 = 直後
/// - `Side` … 根の脇。その側の末尾へ
pub(all) enum Drop {
  Node(id~ : Int, pos~ : Int)
  Side(root~ : Int, left~ : Bool)
} derive(Eq, Debug, ToJson, FromJson)

///|
/// 判定に要るものすべて。世界座標で話す
priv struct Scene {
  /// ポインタの位置
  at : Pt
  layout : Layout
  /// いま掴んでいる部分木。落とし先から外す
  dragging : Set[Int]
}

///|
/// 箱の左右へのはみ出しをどこまで箱の内と見るか
let slop = 16.0

///|
/// 前後への挿入を狙える帯の広さ
let band = 40.0

///|
/// 開いている側では同じ帯をここまで広げる
let open_band : Double = band * 5.0

///|
/// 「子にする」外側ゾーンを成長軸方向にどこまで伸ばすか
let reach : Double = gap.x * 4.0 + 16.0

///|
/// 子を優先するのは**親と子の列のあいだの通路**まで。次の列に入ったら、そこは
/// その列の住人（前後への挿入）のもの。通路より広く取っていたころは、列 N の
/// ノードが列 N+1 の兄弟挿入を横取りし、「下の兄弟にしたいのに隣の枝の子になる」
/// が起きていた
let near : Double = gap.x

///|
/// 外側ゾーンが兄弟軸方向に箱からはみ出してよい量
let slack = 18.0

///|
/// 箱の中心から見たポインタの位置（du, dv）と、箱の半分の大きさ（hu, hv）。
/// `du` は**その枝が伸びる向き**を正とする（左の枝では左が正）ので、
/// 外側ゾーンの式を左右で書き分けなくてよい
fn offset(at : Pt, b : Box) -> (Double, Double, Double, Double) {
  let c = b.rect().center()
  let d = match b.parent {
    Some(p) => dir(p.side)
    None => 1
  }
  ((at.x - c.x) * d.to_double(), at.y - c.y, b.w / 2.0, b.h / 2.0)
}

///|
/// 列の上端 / 下端のノード（up, down）。
///
/// 兄弟は縦に積まれるので、上端の**上**と下端の**下**には競う相手がそもそも
/// 居ない。そこは帯を広げても何も奪わない。同じ親でも左右で別の列になるので、
/// 端は (親, 側) ごとに数える。
///
/// 上下は文書順ではなく**箱の y** で決める（見た目の端がそのまま端になる）。
/// 掴んでいるノードも数に入れる — ドラッグ中もその箱は元の場所に描かれた
/// ままなので、見た目の上下端は動かない
fn open_ends(s : Scene) -> (Set[Int], Set[Int]) {
  let first : Map[(Int, Int), Box] = Map([])
  let last : Map[(Int, Int), Box] = Map([])
  for id in s.layout.order {
    guard s.layout.boxes.get(id) is Some(b) else { continue }
    guard b.parent is Some(p) else { continue } // 根に兄弟は無い
    let key = (p.id, dir(p.side))
    match first.get(key) {
      Some(f) => if b.y < f.y { first[key] = b }
      None => first[key] = b
    }
    match last.get(key) {
      Some(l) => if b.y + b.h > l.y + l.h { last[key] = b }
      None => last[key] = b
    }
  }
  (
    Set::from_iter(first.values().map(b => b.node.id)),
    Set::from_iter(last.values().map(b => b.node.id)),
  )
}

///|
/// 通路（親の外側ゾーン）の縦の位置から、その親の子のどの隣かを決める。
/// 子が 1 つも無ければ None（= 「最初の子にする」に落ちる）。
///
/// 子は縦に積まれるので、いちばん近い子の上半分/下半分で手前/後ろが決まる。
/// これは箱の帯（前後への挿入）とまったく同じ読み方で、場所が通路に変わる
/// だけ — 通路と子の列で意味が変わらないので、指した高さがそのまま着地点
fn slot_among_kids(s : Scene, parent : Int) -> Target? {
  let mut best = @double.infinity
  let mut hit : Target? = None
  for id in s.layout.order {
    guard !s.dragging.contains(id) else { continue }
    guard s.layout.boxes.get(id) is Some(b) else { continue }
    guard b.parent is Some(p) && p.id == parent else { continue }
    let c = b.rect().center()
    let d = (s.at.y - c.y).abs()
    if d < best {
      best = d
      hit = Some({ id, pos: if s.at.y < c.y { 1 } else { 2 }, })
    }
  }
  hit
}

///|
/// 列の上端より上 / 下端より下の空白。**誰も取らなかったときだけ**拾う
/// 最後の受け皿なので、外側ゾーン（子にする）も帯も奪わない。
///
/// 横は帯と同じ「その列に居ること」（`hu + slop`）のまま。縦だけを `open_band` まで
/// 広げる。無制限にしないのは、**横に外す以外のキャンセルの手を残す**ため —
/// 列の x に収まったまま上下にいくら離してもどこかへ落ちてしまう、では
/// ドラッグを諦める手が横だけになる
fn find_open_end(s : Scene) -> Target? {
  let (up_ends, down_ends) = open_ends(s)
  let mut best = @double.infinity
  let mut hit : Target? = None
  for id in s.layout.order {
    guard !s.dragging.contains(id) else { continue }
    guard s.layout.boxes.get(id) is Some(b) else { continue }
    let (du, dv, hu, hv) = offset(s.at, b)
    guard du.abs() <= hu + slop else { continue }
    let over = dv.abs() - hv
    guard over > 0.0 && over <= open_band else { continue }
    let up = dv < 0.0
    guard (if up { up_ends } else { down_ends }).contains(id) else { continue }
    if over < best {
      best = over
      hit = Some({ id, pos: if up { 1 } else { 2 }, })
    }
  }
  hit
}

///|
/// ポインタの下に落とす。**帯（箱とその前後）と外側ゾーン（成長軸の先の通路）を
/// それぞれ当たって、近いほうを採る**。誰も取らなければ、開いている側の上下端が受ける。
pub fn resolve(l : Layout, at : Pt, dragging : Array[Int]) -> Drop? {
  let s : Scene = { at, layout: l, dragging: Set::from_array(dragging), }
  let inner = banded(s)
  let outer = beyond(s)
  // 外側ゾーンの**近い側は帯より強い**（右に置いたのに兄弟になる、を防ぐ）。
  // 遠い側は「誰も取らない空間の受け皿」なので、帯が居れば譲る
  let winner = if outer.target is Some(_) &&
    inner.dist > 0.0 &&
    (outer.edge <= near || inner.target is None) {
    outer.target
  } else {
    inner.target
  }
  // 誰も取らなかった空白は、開いている側の上下端が受ける
  let target = match winner {
    Some(t) => Some(t)
    None => find_open_end(s)
  }
  guard target is Some(t) else { return None }
  landed(s, t)
}

///|
/// 帯の中でいちばん近い相手と、その近さ。
priv struct Near {
  target : Target?
  /// 箱からの距離。箱の中なら 0
  dist : Double
}

///|
/// 外側ゾーンでいちばん近い相手。順位づけ（縦のずれも足した距離）は `beyond` の
/// 中だけの話で、外に出るのは**近い側は帯より強い**の判定に使う素の距離。
priv struct Zone {
  target : Target?
  /// 箱の外縁からどれだけ出た所で拾ったか
  edge : Double
}

///|
/// 帯の中でいちばん近い相手。**帯は隣の兄弟と重なる**ので、最初に見つかった相手では
/// なく近いほうを選ぶ（文書順で決めていたころは、親が違う子スタックの境目で
/// どちらに倒れるかが実質その場の運になっていた）。
fn banded(s : Scene) -> Near {
  let mut target : Target? = None
  let mut best = @double.infinity
  for id in s.layout.order {
    guard reachable(s, id) is Some(b) else { continue }
    let (du, dv, hu, hv) = offset(s.at, b)
    guard du.abs() <= hu + slop && dv.abs() <= hv + band else { continue }
    // 箱の中なら 0。外に出た分だけ距離が増える（兄弟軸のほうを重く見る）
    let dist = @cmp.maximum(0.0, du.abs() - hu) +
      @cmp.maximum(0.0, dv.abs() - hv) * 2.0
    guard dist < best else { continue }
    best = dist
    target = Some({ id, pos: slot_of(b, dv, hv), })
  }
  { target, dist: best, }
}

///|
/// 帯のどこで拾ったか。0 = その子 / 1 = 直前 / 2 = 直後。
/// **根に兄弟は無い**ので、上に落ちたものはすべて子になる。
fn slot_of(b : Box, dv : Double, hv : Double) -> Int {
  guard b.parent is Some(_) else { return 0 }
  if dv < -hv * 0.4 {
    1
  } else if dv > hv * 0.4 {
    2
  } else {
    0
  }
}

///|
/// 外側ゾーン — 箱の外、成長軸の方向へ少し出たところ。ここは「子にする」通路で、
/// 縦の位置が**どの子の隣か**まで決める（通路は子の列そのものではないが、
/// 子は縦に積まれるので縦は子の列と同じ意味を持つ。一律「末尾に足す」に潰していた
/// ころは、通路のどこを指しても印が最後の子の下に 1 点で出ていた）。
fn beyond(s : Scene) -> Zone {
  let mut target : Target? = None
  let mut best = @double.infinity
  let mut edge = @double.infinity
  for id in s.layout.order {
    guard reachable(s, id) is Some(b) else { continue }
    let (du, dv, hu, hv) = offset(s.at, b)
    // 根は両方向に伸びる木の付け根なので、成長軸の判定を絶対値で見る
    //（`local` の du は dir で片側だけ正にしてあるので、根では素のままだと右側しか拾えない）
    let is_root = b.parent is None
    let grow = if is_root { du.abs() } else { du }
    guard grow > hu && grow <= hu + reach && dv.abs() <= hv + slack else {
      continue
    }
    let d = grow - hu + @cmp.maximum(0.0, dv.abs() - hv) * 2.0
    guard d < best else { continue }
    best = d
    edge = grow - hu
    // 根は側の話が乗るので、子の列には割り込まない
    target = match (if is_root { None } else { slot_among_kids(s, id) }) {
      Some(t) => Some(t)
      None => Some({ id, pos: 0, })
    }
  }
  { target, edge, }
}

///|
/// 落とし先になれる箱。掴んでいる部分木と、箱を持たないものは外す。
fn reachable(s : Scene, id : Int) -> Box? {
  guard !s.dragging.contains(id) else { return None }
  s.layout.boxes.get(id)
}

///|
/// 相手を落とし先にする。**「子にする」は、木の根が相手なら**どちら側か**まで
/// 決まって初めて意味を持つ**ので、ポインタが根の中心のどちら側にあるかで振り分ける。
fn landed(s : Scene, t : Target) -> Drop? {
  guard t.pos == 0 else { return Some(Node(id=t.id, pos=t.pos)) }
  guard s.layout.boxes.get(t.id) is Some(b) else {
    return Some(Side(root=t.id, left=false))
  }
  guard b.parent is None else { return Some(Node(id=t.id, pos=0)) }
  // ポインタがその箱の中心より左か。**側を決めるのはここだけ**
  Some(Side(root=t.id, left=s.at.x < b.rect().center().x))
}

///|
/// 落とし先を Op に。側は根のものなので In(root, side) で言う
pub fn drop_op(d : Drop, ids : Array[Int]) -> @op.Op {
  match d {
    Side(root~, left~) =>
      MoveNode(
        ids~,
        at=In(node=root, side=Some(if left { Left } else { Right })),
      )
    Node(id~, pos~) =>
      match pos {
        0 => MoveNode(ids~, at=In(node=id, side=None))
        1 => MoveNode(ids~, at=Before(node=id))
        _ => MoveNode(ids~, at=After(node=id))
      }
  }
}
