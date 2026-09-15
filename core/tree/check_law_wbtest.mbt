// check の約束を法則で固定する。
//
//   法則 — check が通る木は、書いて読み直すと同じ形
//
// 見本を手で選ぶと、書く側と check が別々に持つ規則の食い違いを見落とす（#382）。
// 見出し・項目・Implicit・側・中身（字と水平線）を無作為に組んだ木で回す。種は固定。

///|
/// 無作為な木を組む途中。種と、配った id の最後。
priv struct Grow {
  mut seed : Int64
  mut id : Int
}

///|
/// 0 から n 未満の数を 1 つ。
fn Grow::pick(self : Grow, n : Int) -> Int {
  self.seed = self.seed * 6364136223846793005L + 1442695040888963407L
  ((self.seed >> 33) & 0x7fffffffL).to_int() % n
}

///|
fn Grow::fresh(self : Grow) -> Int {
  self.id = self.id + 1
  self.id
}

///|
/// 中身の列 — 0〜2 枚の、水平線か字。
fn Grow::blocks(self : Grow) -> Array[Block] {
  let out : Array[Block] = []
  for _ in 0..<self.pick(3) {
    let id = self.fresh()
    out.push(
      if self.pick(2) == 0 {
        { id, content: Some(ThematicBreak), source: Some("---"), }
      } else {
        { id, content: None, source: Some("t"), }
      },
    )
  }
  out
}

///|
/// 深さ `depth` のノード 1 つと、残り `room` 段の部分木。`base` は抱える項目の深さ。
fn Grow::node(self : Grow, depth : Int, base : Int, room : Int) -> Node {
  let id = self.fresh()
  let mark : Mark? = match
    (if depth - base >= deepest { 1 } else { self.pick(3) }) {
    0 => Some(atx)
    1 => Some(bullet)
    _ => None
  }
  let inner = if mark is Some(Item(..)) { depth } else { base }
  let children : Array[Node] = []
  if room > 0 {
    for _ in 0..<self.pick(3) {
      children.push(self.node(depth + 1, inner, room - 1))
    }
  }
  // 子の無い Implicit は在り得ない（`BarrenImplicit`）
  if mark is None && children.is_empty() {
    children.push(self.node(depth + 1, inner, 0))
  }
  {
    id,
    label: if mark is None {
      ""
    } else {
      "n"
    },
    fold: None,
    body: if mark is None {
      []
    } else {
      self.blocks()
    },
    children,
    mark,
  }
}

///|
/// 文書 1 つ — 根 1〜2 本、根の子の側は 3 つに 1 つ左。
fn Grow::doc(self : Grow) -> Doc {
  let roots : Array[Root] = []
  for _ in 0..<(1 + self.pick(2)) {
    let node = self.node(1, 0, 3)
    roots.push({
      node,
      sides: node.children.map(_ => if self.pick(3) == 0 { Left } else { Right }),
      rules: node.children.map(_ => ""),
    })
  }
  {
    frontmatter: None,
    body: if self.pick(3) == 0 {
      self.blocks()
    } else {
      []
    },
    roots,
  }
}

///|
test "法則 — check が通る木は、書いて読み直すと同じ形" {
  let grow : Grow = { seed: 42L, id: doc_id + 1, }
  let mut passed = 0
  let bad : Array[String] = []
  for _ in 0..<20000 {
    let doc = grow.doc()
    guard check(doc).is_empty() else { continue }
    passed = passed + 1
    let md = serialize(doc)
    if shape(parse(md)) != shape(doc) && bad.length() < 5 {
      bad.push(md)
    }
  }
  json_inspect(bad, content=[])
  // 全部 check に落ちる退化を落とすための下限
  guard passed > 4000 else {
    fail("check を通った木が \{passed} 本しか無い")
  }
}

///|
/// 貼る断片は根でない席に差されるので、側は中身の水平線に戻して運ぶ（`bordered`）。
/// **変わり目ぜんぶに線が置け、check がその線だけを `BorderBreak`（境界に読まれる線）と
/// 言う木**で回す。置けない変わり目（子が項目だけの根の最初の子）は側が落ち、中身が挟まる所や
/// 項目の宿が要る所の線は飾りに読まれる — そこは md の読みが形を決める（docs/spec.md「水平線」）
test "法則 — 側を中身の水平線に戻しても、書けば同じ木に読まれる" {
  let grow : Grow = { seed: 7L, id: doc_id + 1, }
  let mut kept = 0
  let bad : Array[String] = []
  for _ in 0..<20000 {
    let doc = grow.doc()
    guard check(doc).is_empty() else { continue }
    let mut turned = 0
    for r in doc.roots {
      for t in turns(r) {
        if t is Some(_) {
          turned = turned + 1
        }
      }
    }
    let top = top_id(doc)
    let lined = bordered(doc)
    let plain : Doc = {
      ..lined,
      roots: lined.roots.map(r => {
        ..r,
        sides: r.sides.map(_ => Right),
        rules: r.rules.map(_ => ""),
      }),
    }
    let flaws = check(plain)
    guard turned > 0 &&
      top_id(lined) - top == turned &&
      flaws.length() == turned &&
      flaws.iter().all(f => f is BorderBreak(id) && id > top) else {
      continue
    }
    kept = kept + 1
    let md = serialize(plain)
    if shape(parse(md)) != shape(doc) && bad.length() < 5 {
      bad.push(md)
    }
  }
  json_inspect(bad, content=[])
  // 全部 篩に落ちる退化を落とすための下限（線が境界に読まれる木は 2 割ほど）
  guard kept > 300 else {
    fail("線を置けた木が \{kept} 本しか無い")
  }
}
