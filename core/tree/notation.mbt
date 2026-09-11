// 記法構造。**読んだ md そのもの**を、原文を隙間なく覆うひと切れの列で持つ。
//
// 木（`Doc`）が「構造と機能」を持つのに対し、こちらは「記法と綴り」を持つ。
// 決めは docs/superpowers/specs/2026-09-09-notation-design.md。
//
// **読みの段だけのもの。** `build` が md をここへ通して木を組む（`assemble`）。
// 書き戻しは木から綴る（`unbuild`）ままで、ここは通らない — 隙間の答えが階層から
// 出たので、piece を書き道にしても消える行が無かった（spec「止めた」）。
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
  /// `at_label` はラベルの頭（マーカーの後ろ）。綴りが無ければ飛び（Implicit）だが、
  /// 飛びは原文に行を持たないのでひと切れにならない。
  ///
  /// `label` と `at` は**組み立てに要るぶんだけ**の持ち出し。字は本来 `md` に 1 か所
  /// だが、ラベルの切り出しには測りの但し書き（`head_label` の定義行の穴）が在り、
  /// 地番は畳まれた行なら `<details>` の範囲まで伸びる。**どちらもひと切れの範囲
  /// には畳めない** — 行の字とラベルと地番が、それぞれ別の所で終わる
  Line(
    depth~ : Int,
    under~ : Int,
    label~ : String,
    at_label~ : Int,
    mark~ : Mark?,
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
  /// 骨格でない塊。`under` は**持ち主の枠の深さ**（0 なら文書）で、
  /// `Line` の同じ名の欄と同じ意味 — 列 0 の塊は開いている項目を閉じるので、
  /// 積んである高さそのままとは限らない（#204）
  Card(content~ : Content?, source~ : String?, under~ : Int)
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
/// md を記法構造にする。**裁定を下すのは `Deem`**（deem.mbt）— md を 1 度歩いて、
/// 自分が何を見たかを控える。列はそれを原文の順に敷き詰めたもの。
fn notation(md : String) -> Notation {
  let ast = read(md)
  let d = Deem::new(md, ast.definitions.map(def => def.span))
  for cut in sift(md, ast.children, d.defs, 0) {
    deem(d, cut, 0)
  }
  spill(d)
  {
    md,
    frontmatter: ast.frontmatter,
    pieces: tile(md, ast.frontmatter, d.pieces),
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
    Some(Line(depth~, at_label~, mark~, ..)) =>
      "Line\{at}(\{depth},\{at_label},\{mark_sig(mark)})"
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
    if !space(md[i]) {
      return false
    }
  }
  true
}

///|
/// 記法構造 → md。**ひと切れの原文をそのまま継ぐ。**
///
/// ひと切れは原文を隙間なく覆うので、触っていない列を書けば**原文がそのまま返る**。
/// それが記法構造の前提そのもの（md が真実で、木は派生）で、`serialize` のように
/// 意味から綴り直す道とは別のもの。差し替えた piece を綴るのは反映の段。
fn write_pieces(n : Notation) -> String {
  let out = StringBuilder()
  match n.frontmatter {
    Some(f) => out.write_string(slice(n.md, f.span.from, f.span.to))
    None => ()
  }
  for p in n.pieces {
    out.write_string(slice(n.md, p.at.from, p.at.to))
  }
  out.to_string()
}

///|
pub fn notation_back(md : String) -> String {
  write_pieces(notation(md))
}
