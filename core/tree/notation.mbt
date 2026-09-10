// 記法構造。**読んだ md そのもの**を、原文を隙間なく覆うひと切れの列で持つ。
//
// 木（`Doc`）が「構造と機能」を持つのに対し、こちらは「記法と綴り」を持つ。
// 決めは docs/superpowers/specs/2026-09-09-notation-design.md。
//
// **いまは誰も呼ばない。** 段 1 の床で、列は木を組む機械（`build`）が判断を
// 下すそばから控えたもの。判断そのものを読みの段へ移すのは段 6 で、そのとき
// 赤くなる網（指紋・敷き詰め）をここで先に張っておく。網を後から張ると、
// 移した後のコードが言うことをそのまま正解として焼き込んでしまう。
//
// **字は 1 か所。** ひと切れは範囲だけを持ち、字は `md` から切り出す（#185）。

///|
/// 読んだ md そのもの。ひと切れが**原文を隙間なく覆う**（前の to = 次の from）。
priv struct Notation {
  md : String
  /// frontmatter。ひと切れはその尻から始まる
  frontmatter : @markdown.Frontmatter?
  pieces : Array[Piece]
}

///|
/// 原文のひと続きと、mmm がそこに何を見たか。**裁定が無ければ隙間** —
/// 空行と、綴りとして落ちた字がそこに入る。
priv struct Piece {
  at : @markdown.Span
  verdict : Verdict?
}

///|
/// mmm がその範囲に見た意味。
///
/// 同じ `---` が `Border` にも `Card` にもなり、同じ `<details>` が `FoldOpen` にも
/// `Card` にもなる。**どちらに読んだかを裁定が言う。**
priv enum Verdict {
  /// 骨格の行。`depth` は**積まれた深さ**（`#` の本数でも入れ子の段数でもない）。
  /// `under` は**どの深さの下に付くか** — 0 なら新しい木。深さだけでは足りない：
  /// 列 0 の見出しは開いている項目を閉じ（`- a` の後の `### x` は新しい木）、
  /// 境界は部分木を深さ 1 まで引き出す。閉じた分と、飛び（Implicit）で埋める分は
  /// 別のことなので、両方を言う。
  /// `label` はラベルの頭（マーカーの後ろ）。綴りが無ければ飛び（Implicit）だが、
  /// 飛びは原文に行を持たないのでひと切れにならない。
  ///
  /// `text` と `at` は**組み立てに要るぶんだけ**の持ち出し。字は本来 `md` に 1 か所
  /// だが、ラベルの切り出しには測りの但し書き（`head_label` の定義行の穴）が在り、
  /// 地番は畳まれた行なら `<details>` の範囲まで伸びる。どちらも綴りを痩せさせる段で
  /// 範囲 1 つに畳む（spec「ラベルを字で持つか、範囲で持つか」）
  Line(
    depth~ : Int,
    under~ : Int,
    label~ : Int,
    mark~ : Mark?,
    text~ : String,
    fold~ : Fold?,
    at~ : @markdown.Span
  )
  /// 側の変わり目になった水平線。`rule` は書き戻しに要る綴り
  Border(rule~ : String)
  /// 立った畳みの開き
  FoldOpen(open~ : Bool, summary~ : String?)
  /// 立った畳みの閉じ。**その部分木が終わったという宣言**
  FoldClose
  /// 中身。持ち主は手前の `Line`。`source` は読んだ原文で、切り出しの流儀が
  /// 塊ごとに違う（`verbatim` / `carve` / `strip`）ので字で持ち出す
  Card(content~ : Content?, source~ : String?)
}

///|
/// 控えた裁定から、原文を隙間なく覆うひと切れの列を組む。
///
/// **隙間は捨てない。** 空行も、綴りとして落ちた `<details>` の字も、範囲としては
/// 原文に在る。裁定の無いひと切れとして置くことで「塊の外」を無くす —
/// 覆えていない字が在れば、それは裁定がどこかで自分の記法を取りこぼしている。
fn tile(
  md : String,
  frontmatter : @markdown.Frontmatter?,
  noted : Array[Piece],
) -> Array[Piece] {
  let sorted = noted.copy()
  sorted.sort_by((a, b) => {
    let d = a.at.from - b.at.from
    if d != 0 {
      d
    } else {
      a.at.to - b.at.to
    }
  })
  let out : Array[Piece] = []
  let head = match frontmatter {
    Some(f) => f.span.to
    None => 0
  }
  let mut at = head
  fn gap(to : Int) {
    if to > at {
      out.push({ at: { from: at, to, }, verdict: None, })
    }
  }

  for p in sorted {
    // 控えが重なることは無いはずだが、重なったら手前を優先して落とす —
    // 覆いの法則で鳴らせるように、黙って伸ばしたりはしない
    if p.at.from < at {
      continue
    }
    gap(p.at.from)
    out.push(p)
    at = p.at.to
  }
  gap(md.length())
  out
}

///|
/// md を記法構造にする。**判断は木を組む機械のもの** — 段 1 は控えるだけで、
/// 移すのは段 6。だから木も md も 1 つも変わらない。
fn notation(md : String) -> Notation {
  let ast = read(md)
  let b = Build::new(md, ast.definitions.map(d => d.span))
  for cut in sift(md, ast.children, b.defs, 0) {
    lay(b, cut, 0)
  }
  spill(b)
  {
    md,
    frontmatter: ast.frontmatter,
    pieces: tile(md, ast.frontmatter, b.pieces),
  }
}

///|
/// 記法構造の指紋。`裁定[from,to]` を原文の順に並べる。**範囲は必ず出す**
/// （`md.mbt` の `at` は空の範囲を隠すので使わない）。裁定の無いひと切れは
/// 隙間で、原文が空白だけなら `Blank`、字が在れば `Rest` — **`Rest` は
/// 覆えていない字**なので、増えたらどこかの裁定が記法を取りこぼしている。
/// frontmatter が在れば頭に付く（ひと切れはその尻から始まる）。
pub fn notation_sig(md : String) -> String {
  let n = notation(md)
  let head = match n.frontmatter {
    Some(f) => "Front[\{f.span.from},\{f.span.to}] "
    None => ""
  }
  head + n.pieces.map(p => piece_sig(n.md, p)).join(" ")
}

///|
fn piece_sig(md : String, p : Piece) -> String {
  let at = "[\{p.at.from},\{p.at.to}]"
  match p.verdict {
    None => if blank_span(md, p.at) { "Blank\{at}" } else { "Rest\{at}" }
    Some(Line(depth~, label~, mark~, ..)) =>
      "Line\{at}(\{depth},\{label},\{mark_sig(mark)})"
    Some(Border(..)) => "Border\{at}"
    Some(FoldOpen(open~, summary~)) => {
      let flag = if open { "open" } else { "-" }
      let name = match summary {
        Some(s) => ",\{s.escape()}"
        None => ""
      }
      "Fold\{at}(\{flag}\{name})"
    }
    Some(FoldClose) => "Shut\{at}"
    Some(Card(content~, ..)) =>
      match content {
        None => "Card\{at}"
        Some(c) => "Card\{at}\{c.to_json().stringify()}"
      }
  }
}

///|
/// 綴りの指紋。見出しは `#` と閉じの本数（setext は `=`）、項目はマーカー・桁・詰め。
/// 飛び（Implicit）は行を持たないのでひと切れにならないが、型の上では在りうる
fn mark_sig(m : Mark?) -> String {
  match m {
    None => "-"
    Some(Heading(setext=true, ..)) => "="
    Some(Heading(closing~, ..)) => "#\{closing}"
    Some(Item(marker~, offset~, loose~)) => {
      let gap = if loose { "loose" } else { "tight" }
      "\{marker},\{offset},\{gap}"
    }
  }
}

///|
/// その範囲が空白だけか。隙間が空行なのか、覆えていない字なのかを分ける
fn blank_span(md : String, at : @markdown.Span) -> Bool {
  for i in at.from..<at.to {
    if !blank(md[i]) {
      return false
    }
  }
  true
}

///|
/// 組み立ての途中。**裁定は 1 つも下さない** — 深さから枠を積み直し、中身を
/// 持ち主に配り、側を `Border` で裏返すだけ。
priv struct Lay {
  roots : Array[Frame]
  stack : Array[Frame]
  body : Array[Block]
  body_at : Array[Spot]
  mut body_to : Int
  /// 次の子の側。木が変わるたびに右へ戻る
  mut side : Side
  /// 境界になった水平線の綴り。次に座る深さ 2 の枠が受け取る
  mut rule : String
  /// まだ閉じていない畳みの、畳んだノードの深さ
  fold_roots : Array[Int]
  /// 直前に畳みの開きを跨いだ。次に座る枠が畳みの根
  mut opening : Bool
}

///|
/// これから座る枠の側と、その手前で側を変えた水平線の原文。
/// **側を持つのは深さ 2 の枠だけ**（根の子）。`born` と同じ規則
fn Lay::born(self : Lay) -> (Side, String) {
  guard self.stack.length() == 1 else { return (Right, "") }
  guard self.rule != "" else { return (self.side, "") }
  let rule = self.rule
  self.rule = ""
  self.side = flipped(self.side)
  (self.side, rule)
}

///|
/// 積んである親の子にし、次の子の親にする。`seat` と同じ規則
fn Lay::seat(self : Lay, f : Frame) -> Unit {
  if self.stack.is_empty() {
    self.roots.push(f)
  } else {
    self.stack[self.stack.length() - 1].kids.push(f)
  }
  self.stack.push(f)
}

///|
/// ひと切れの列から木を組む。**この関数に裁定は無い。**
fn assemble(n : Notation) -> (Doc, Map[Int, Spot]) {
  let l : Lay = {
    roots: [],
    stack: [],
    body: [],
    body_at: [],
    body_to: 0,
    side: Right,
    rule: "",
    fold_roots: [],
    opening: false,
  }
  for p in n.pieces {
    match p.verdict {
      None => ()
      Some(Border(rule~)) => l.rule = rule
      Some(FoldOpen(..)) => l.opening = true
      Some(FoldClose) =>
        match l.fold_roots.pop() {
          Some(root) =>
            while l.stack.length() >= root && !l.stack.is_empty() {
              ignore(l.stack.unsafe_pop())
            }
          None => ()
        }
      Some(Card(content~, source~)) => {
        let block : Block = { id: 0, content, source, }
        let at : Spot = { from: p.at.from, label: None, to: p.at.to, }
        if l.stack.is_empty() {
          l.body.push(block)
          l.body_at.push(at)
          if at.to > l.body_to {
            l.body_to = at.to
          }
        } else {
          let f = l.stack[l.stack.length() - 1]
          f.body.push(block)
          f.body_at.push(at)
        }
      }
      Some(Line(depth~, under~, label~, mark~, text~, fold~, at~)) => {
        // 新しい木は側を持たない。**保留の綴りはもう中身に落ちている**
        // （裁定の側の `spill` が `Card` として出しているので、ここでは捨てるだけ）
        if depth == 1 {
          l.side = Right
          l.rule = ""
        }
        while l.stack.length() > under {
          ignore(l.stack.unsafe_pop())
        }
        // 足りない深さは飛び（Implicit）が埋める。行を持たないので範囲は無い
        while l.stack.length() < depth - 1 {
          let (side, rule) = l.born()
          l.seat({
            mark: None,
            label: "",
            fold: None,
            body: [],
            kids: [],
            side,
            rule,
            from: no_line,
            to: no_line,
            at_label: no_line,
            body_at: [],
          })
        }
        let (side, rule) = l.born()
        l.seat({
          mark,
          label: text,
          fold,
          body: [],
          kids: [],
          side,
          rule,
          from: at.from,
          to: at.to,
          at_label: label,
          body_at: [],
        })
        if l.opening {
          l.fold_roots.push(l.stack.length())
          l.opening = false
        }
      }
    }
  }
  let spans : Map[Int, Spot] = Map([])
  let next = { val: doc_id + 1, }
  let from = match n.frontmatter {
    Some(f) => f.span.to
    None => 0
  }
  spans[doc_id] = {
    from,
    label: None,
    to: if l.body_to > from {
      l.body_to
    } else {
      from
    },
  }
  number_blocks(l.body, next)
  for i, at in l.body_at {
    spans[l.body[i].id] = at
  }
  let doc : Doc = {
    frontmatter: n.frontmatter.map(f => f.raw),
    body: l.body,
    roots: l.roots.map(f => to_root(f, next, spans)),
  }
  (doc, spans)
}
