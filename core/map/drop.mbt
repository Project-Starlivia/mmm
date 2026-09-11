// ドラッグしたものをどこへ落とすかの決定。DOM も地図も知らない純粋な層。
//
// マップでいちばん込み入った判断で、しかも「惜しい」が最も嫌われる場所
// （右に置いたのに兄弟になる、近くの子の帯に吸われて狙った子と違う所に落ちる）。
// だから見た目を塗る仕事から切り離して、ここだけを単体で試せるようにしてある。

///|
/// ノード相手の落とし先の刻み。その子の末尾 / 直前 / 直後
pub(all) enum Slot {
  Into
  Before
  After
} derive(Eq, Debug, ToJson, FromJson)

///|
/// ノード相手の落とし先（内部の刻み）
priv struct Target {
  id : Int
  slot : Slot
}

///|
/// 落とし先。**2 つだけ**:
/// - `Node` … その箱の `Slot`
/// - `Side` … 根の脇。その側の末尾へ
pub(all) enum Drop {
  Node(id~ : Int, slot~ : Slot)
  Side(root~ : Int, side~ : @tree.Side)
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
/// その列の住人（前後への挿入）のもの — 通路より広いと、列 N のノードが列 N+1 の
/// 兄弟挿入を横取りする（「下の兄弟にしたいのに隣の枝の子になる」）
let near : Double = gap.x

///|
/// 外側ゾーンが兄弟軸方向に箱からはみ出してよい量
let slack = 18.0

///|
/// 箱の中心から見たポインタの位置（du, dv）と、箱の半分の大きさ（hu, hv）。
/// `du` は**その枝が伸びる向き**を正とする（左の枝では左が正）ので、
/// 外側ゾーンの式を左右で書き分けなくてよい
fn offset(at : Pt, b : Box) -> (Double, Double, Double, Double) {
  let c = b.rect.center()
  let d = match b.parent {
    Some(p) => dir(p.side)
    None => 1
  }
  ((at.x - c.x) * d.to_double(), at.y - c.y, b.rect.w / 2.0, b.rect.h / 2.0)
}

///|
/// 落とし先になれる箱（`reachable`）のうち、`score` がいちばん小さいもの。
/// 同点なら先に見たほう。誰も居なければ (None, ∞)
fn[T] Scene::best(
  self : Scene,
  ids : Array[Int],
  score : (Box) -> (Double, T)?,
) -> (T?, Double) {
  let mut found : T? = None
  let mut least = @double.infinity
  for id in ids {
    guard reachable(self, id) is Some(b) else { continue }
    guard score(b) is Some((d, t)) && d < least else { continue }
    least = d
    found = Some(t)
  }
  (found, least)
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
  let up : Set[Int] = Set([])
  let down : Set[Int] = Set([])
  for _, col in columns(s.layout.boxes) {
    let mut first = col[0]
    let mut last = col[0]
    for b in col {
      if b.rect.y < first.rect.y {
        first = b
      }
      if b.rect.y + b.rect.h > last.rect.y + last.rect.h {
        last = b
      }
    }
    up.add(first.node.id)
    down.add(last.node.id)
  }
  (up, down)
}

///|
/// 通路（親の外側ゾーン）の縦の位置から、その親の子のどの隣かを決める。
/// 子が 1 つも無ければ None（= 「最初の子にする」に落ちる）。
///
/// 子は縦に積まれるので、いちばん近い子の上半分/下半分で手前/後ろが決まる。
/// これは箱の帯（前後への挿入）とまったく同じ読み方で、場所が通路に変わる
/// だけ — 通路と子の列で意味が変わらないので、指した高さがそのまま着地点
fn slot_among_kids(s : Scene, parent : Int) -> Target? {
  s.best(kids_in(s.layout, Some(parent)), b => {
    let c = b.rect.center()
    Some(
      (
        (s.at.y - c.y).abs(),
        { id: b.node.id, slot: if s.at.y < c.y { Before } else { After }, },
      ),
    )
  }).0
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
  s.best(s.layout.order, b => {
    let (du, dv, hu, hv) = offset(s.at, b)
    guard du.abs() <= hu + slop else { return None }
    let over = dv.abs() - hv
    guard over > 0.0 && over <= open_band else { return None }
    let up = dv < 0.0
    guard (if up { up_ends } else { down_ends }).contains(b.node.id) else {
      return None
    }
    Some((over, { id: b.node.id, slot: if up { Before } else { After }, }))
  }).0
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
/// なく近いほうを選ぶ — 文書順だと、親が違う子スタックの境目でどちらに倒れるかが運になる
fn banded(s : Scene) -> Near {
  let (target, dist) = s.best(s.layout.order, b => {
    let (du, dv, hu, hv) = offset(s.at, b)
    guard du.abs() <= hu + slop && dv.abs() <= hv + band else { return None }
    // 箱の中なら 0。外に出た分だけ距離が増える（兄弟軸のほうを重く見る）
    let dist = @cmp.maximum(0.0, du.abs() - hu) +
      @cmp.maximum(0.0, dv.abs() - hv) * 2.0
    Some((dist, { id: b.node.id, slot: slot_of(b, dv, hv), }))
  })
  { target, dist, }
}

///|
/// 帯のどこで拾ったか。**根に兄弟は無い**ので、上に落ちたものはすべて子になる。
fn slot_of(b : Box, dv : Double, hv : Double) -> Slot {
  guard b.parent is Some(_) else { return Into }
  if dv < -hv * 0.4 {
    Before
  } else if dv > hv * 0.4 {
    After
  } else {
    Into
  }
}

///|
/// 外側ゾーン — 箱の外、成長軸の方向へ少し出たところ。ここは「子にする」通路で、
/// 縦の位置が**どの子の隣か**まで決める（通路は子の列そのものではないが、
/// 子は縦に積まれるので縦は子の列と同じ意味を持つ — 一律「末尾に足す」だと、
/// 通路のどこを指しても印が最後の子の下に 1 点で出る）。
fn beyond(s : Scene) -> Zone {
  let (found, _) = s.best(s.layout.order, b => {
    let (du, dv, hu, hv) = offset(s.at, b)
    // 根は両方向に伸びる木の付け根なので、成長軸の判定を絶対値で見る
    //（`offset` の du は dir で片側だけ正にしてあるので、根では素のままだと右側しか拾えない）
    let is_root = b.parent is None
    let grow = if is_root { du.abs() } else { du }
    guard grow > hu && grow <= hu + reach && dv.abs() <= hv + slack else {
      return None
    }
    let edge = grow - hu
    // 根は側の話が乗るので、子の列には割り込まない
    let target = (if is_root { None } else { slot_among_kids(s, b.node.id) }).unwrap_or({
        id: b.node.id,
        slot: Into,
      },
    )
    Some((edge + @cmp.maximum(0.0, dv.abs() - hv) * 2.0, (target, edge)))
  })
  match found {
    Some((target, edge)) => { target: Some(target), edge, }
    None => { target: None, edge: @double.infinity, }
  }
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
  guard t.slot is Into else { return Some(Node(id=t.id, slot=t.slot)) }
  guard s.layout.boxes.get(t.id) is Some(b) else {
    return Some(Side(root=t.id, side=Right))
  }
  guard b.parent is None else { return Some(Node(id=t.id, slot=Into)) }
  // ポインタがその箱の中心のどちら側か。**側を決めるのはここだけ**
  Some(
    Side(
      root=t.id,
      side=side_of(if s.at.x < b.rect.center().x { -1 } else { 1 }),
    ),
  )
}

///|
/// 落とし先を Op に。側は根のものなので In(root, side) で言う
pub fn drop_op(d : Drop, ids : Array[Int]) -> @op.Op {
  let at : @op.NodePlace = match d {
    Side(root~, side~) => In(node=root, side=Some(side))
    Node(id~, slot=Into) => In(node=id, side=None)
    Node(id~, slot=Before) => Before(node=id)
    Node(id~, slot=After) => After(node=id)
  }
  MoveNode(ids~, at~)
}
