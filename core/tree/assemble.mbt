// ひと切れの列から木を組む。**裁定は 1 つも下さない。**
//
// 裁定は読み（`deem.mbt`）が下している。ここは深さから枠（`Frame`）を積み直し、
// 中身を持ち主に配り、側を `Border` で裏返すだけ。深さ 1 / 2 / 3 以降で型が違う
// （`Root` / `sides` / ただの子）ので、根と側への割り付けは最後に 1 回だけやり、
// その違いをここへ閉じ込める。

///|
/// 組み立て中のノード。深さは stack の高さが持つので、自分では持たない。
/// 番号と場所は導けるので持たず、`to_node` が配る。
priv struct Frame {
  /// 行に書かれていた綴り。飛び（Implicit）は None
  mark : Mark?
  label : String
  fold : Fold?
  body : Array[Block]
  kids : Array[Frame]
  /// 深さ 2 の枠だけが持つ。深い所の側は型に存在しない
  side : Side
  /// 自分の手前で側を変えた水平線の原文。変えていなければ空
  rule : String
  /// その水平線の頭。変えていなければ None
  border : Int?
  /// **骨格の行だけ**の原文の範囲。中身と子の尻は `to_node` が足す。
  /// 畳んだ枠は `<details>` 〜 `</details>`（尻は閉じが伸ばす）。
  /// 飛び（Implicit）は行を持たないので -1
  from : Int
  mut to : Int
  /// ラベルの頭（マーカーの後ろ）。飛び（Implicit）は行を持たないので -1
  at_label : Int
  /// 中身（body）と並走する場所。`to_node` が番号と付き合わせて spots に写す
  body_at : Array[Spot]
}

///|
/// 行を持たない枠（飛び）の目印。範囲は子の和で決まる。
let no_line : Int = -1

///|
/// 組み立ての途中。**裁定は 1 つも下さない** — 深さから枠を積み直し、中身を
/// 持ち主に配り、側を `Border` で裏返すだけ。
priv struct Lay {
  roots : Array[Frame]
  stack : Array[Frame]
  /// 書かれた行の枠を、行の頭で引く。**中身の持ち主はこれで指す** — 境界が行を
  /// 閉じても持ち主は変わらないので、積みから降りた枠にも中身が届く
  owners : Map[Int, Frame]
  body : Array[Block]
  body_at : Array[Spot]
  mut body_to : Int
  /// 次の子の側。木が変わるたびに右へ戻る
  mut side : Side
  /// 境界になった水平線の綴り。次に座る深さ 2 の枠が受け取る
  mut rule : String
  /// その水平線の頭
  mut border : Int?
  /// まだ閉じていない畳みの、畳んだノードの深さ
  fold_roots : Array[Int]
  /// まだ閉じていない畳みの、畳んだ枠。閉じがその尻を `</details>` まで伸ばす
  folded : Array[Frame]
  /// 跨いだばかりの畳みの開きの綴りと頭。**次に座る枠が畳みの根** —
  /// 畳みを言うのは開きのひと切れだけで、骨格の行は畳みを持たない
  mut opening : (Fold, Int)?
}

///|
/// これから座る枠の側と、その手前で側を変えた水平線の原文と頭。
/// **側を持つのは深さ 2 の枠だけ**（根の子）。境界の綴りは、その次に座る深さ 2 の枠が受け取る
fn Lay::born(self : Lay) -> (Side, String, Int?) {
  guard self.stack.length() == 1 else { return (Right, "", None) }
  guard self.rule != "" else { return (self.side, "", None) }
  let rule = self.rule
  let border = self.border
  self.rule = ""
  self.border = None
  self.side = flipped(self.side)
  (self.side, rule, border)
}

///|
/// 積んである親の子にし、次の子の親にする。deem.mbt の `seat` と同じ規則
fn Lay::seat(self : Lay, f : Frame) -> Unit {
  if self.stack.is_empty() {
    self.roots.push(f)
  } else {
    self.stack[self.stack.length() - 1].kids.push(f)
  }
  self.stack.push(f)
}

///|
fn flipped(s : Side) -> Side {
  if s is Right {
    Left
  } else {
    Right
  }
}

///|
/// ひと切れの列から木を組む。**この関数に裁定は無い。**
fn assemble(n : Notation) -> (Doc, Map[Int, Spot]) {
  let l : Lay = {
    roots: [],
    stack: [],
    owners: Map([]),
    body: [],
    body_at: [],
    body_to: 0,
    side: Right,
    rule: "",
    border: None,
    fold_roots: [],
    folded: [],
    opening: None,
  }
  for p in n.pieces {
    match p.verdict {
      None => ()
      Some(Border(rule~)) => {
        l.rule = rule
        l.border = Some(p.at.from)
      }
      Some(FoldOpen(open~, summary~)) =>
        l.opening = Some(({ open, summary, }, p.at.from))
      Some(FoldClose) => {
        shut(l.stack, l.fold_roots)
        if l.folded.pop() is Some(f) {
          f.to = p.at.to
        }
      }
      Some(Block(content~, source~, owner~)) => {
        let block : Block = { id: 0, content, source, }
        let at : Spot = {
          from: p.at.from,
          label: None,
          to: p.at.to,
          border: None,
        }
        // **持ち主は裁定が言う**（`owner`）。積んである頂上とは限らない —
        // 字下げの戻った塊は開いている項目を閉じ、境界は行を閉じても持ち主を変えない。
        // 枠は降ろさない — 降ろすのは骨格の行の仕事（`under`）
        match owner.bind(from => l.owners.get(from)) {
          Some(f) => {
            f.body.push(block)
            f.body_at.push(at)
          }
          None => {
            l.body.push(block)
            l.body_at.push(at)
            if at.to > l.body_to {
              l.body_to = at.to
            }
          }
        }
      }
      Some(Node(depth~, under~, label~, at_label~, mark~, at~)) => {
        while l.stack.length() > under {
          ignore(l.stack.unsafe_pop())
        }
        // **積みが空になれば新しい木**で、側は右から始まる — 深さ 1 の行でも、根を
        // Implicit が埋める深い行でも。新しい木の手前の水平線は境界にならない（`resolve`）
        // ので、受け取る綴りは残っていない
        if under == 0 {
          l.side = Right
        }
        // 足りない深さは飛び（Implicit）が埋める。行を持たないので範囲は無い
        while l.stack.length() < depth - 1 {
          let (side, rule, border) = l.born()
          l.seat({
            mark: None,
            label: "",
            fold: None,
            body: [],
            kids: [],
            side,
            rule,
            border,
            from: no_line,
            to: no_line,
            at_label: no_line,
            body_at: [],
          })
        }
        let (side, rule, border) = l.born()
        let f : Frame = {
          mark,
          label,
          fold: l.opening.map(o => o.0),
          body: [],
          kids: [],
          side,
          rule,
          border,
          from: match l.opening {
            Some((_, from)) => from
            None => at.from
          },
          to: at.to,
          at_label,
          body_at: [],
        }
        l.seat(f)
        l.owners[p.at.from] = f
        if l.opening is Some(_) {
          l.fold_roots.push(l.stack.length())
          l.folded.push(f)
          l.opening = None
        }
      }
    }
  }
  let spots : Map[Int, Spot] = Map([])
  // 番号を配る箱。木を歩きながら文書順に振る
  let next : Ref[Int] = { val: doc_id + 1, }
  let from = match n.frontmatter {
    Some(f) => f.span.to
    None => 0
  }
  spots[doc_id] = {
    from,
    label: None,
    border: None,
    to: if l.body_to > from {
      l.body_to
    } else {
      from
    },
  }
  number_blocks(l.body, next)
  for i, at in l.body_at {
    spots[l.body[i].id] = at
  }
  let doc : Doc = {
    // frontmatter の字もライブラリから来る。木が抱える字は LF だけ
    frontmatter: n.frontmatter.map(f => lf(f.raw)),
    body: l.body,
    roots: l.roots.map(f => to_root(f, next, spots)),
  }
  (doc, spots)
}

///|
/// 森の 1 本を根にする。子の側と境界の綴りは積むときに決まっている。
fn to_root(f : Frame, next : Ref[Int], spots : Map[Int, Spot]) -> Root {
  {
    node: to_node(f, next, spots),
    sides: f.kids.map(k => k.side),
    rules: f.kids.map(k => k.rule),
  }
}

///|
/// 枠をノードにし、番号と場所を配る。綴りはそのまま運ぶ。
/// **番号は文書順**（自分 → 中身 → 子）なので行きがけに振り、**場所は子が
/// 揃ってからでないと決まらない**ので帰りがけに置く。
fn to_node(f : Frame, next : Ref[Int], spots : Map[Int, Spot]) -> Node {
  let id = next.val
  next.val = id + 1
  // 中身は子より前に書かれているので、先に振る
  number_blocks(f.body, next)
  for i, at in f.body_at {
    spots[f.body[i].id] = at
  }
  let children = f.kids.map(k => to_node(k, next, spots))
  spots[id] = frame_at(f, children, spots)
  { id, label: f.label, fold: f.fold, body: f.body, children, mark: f.mark, }
}

///|
/// 中身へ、ノードと同じ列で文書順の番号を振る。読み解かなかったものにも
/// 振るので、View が Raw を落としても残りの番号は動かない。
fn number_blocks(body : Array[Block], next : Ref[Int]) -> Unit {
  for i, x in body {
    body[i] = { id: next.val, content: x.content, source: x.source, }
    next.val = next.val + 1
  }
}

///|
/// 枠の場所。骨格の行の頭から、**自分と子孫の中身の一番後ろの尻まで**。
/// **尻は最後の子とは限らない** — 境界は中身の持ち主を変えないので、子の中身が後ろの子
/// （置き直された行）より下に書かれていることがある（`## a / --- / - b / text` の text）。
/// 行を持たない飛びは範囲ごと子の和。畳みの尻（`</details>`）は子より後ろに
/// 在るので、大きいほうを採れば保たれる。
fn frame_at(f : Frame, children : Array[Node], spots : Map[Int, Spot]) -> Spot {
  let mut from = f.from
  let mut to = f.to
  for at in f.body_at {
    if at.to > to {
      to = at.to
    }
  }
  for k in children {
    let at = spots[k.id]
    if from == no_line {
      from = at.from
    }
    if at.to > to {
      to = at.to
    }
  }
  {
    from,
    label: if f.at_label == no_line {
      None
    } else {
      Some(f.at_label)
    },
    to,
    border: f.border,
  }
}
