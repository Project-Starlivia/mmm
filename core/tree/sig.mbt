// 木の指紋。木ぜんぶを 1 行の文字列にする。
//
// テストの期待値がこれになるので、**読めること**を最優先にした。
// 意味を 1 つも落とさない（落とすと、違う木が同じ指紋になって嘘をつく）。
//
//   D[#"a"[>#"b" <#"c"]]  `# a` の右に `## b`、左に `## c`
//   D[#"a"[>·[#"b"]]]     飛びを埋める Implicit（骨格行が無いノード）
//   D[-"a"[>-"b"]]        リストで書かれた木
//   D+[#"a"[]]            封筒つき
//
// ラベルは引用符で囲む。裸で置くと `[` や `>` を含むラベルが構造に見えて、
// 違う木が同じ指紋になる（法則の照合が嘘をつく）。
//
//   #  見出し   -  項目   ·  Implicit（綴りが無い）
//   >  右の翼   <  左の翼
//   ^  畳んである
//   (…)  中身。r=飾りの水平線 / "…"=逐語 / img,link,code,svg

///|
/// 文書ぜんぶの指紋。
pub fn sig(doc : Doc) -> String {
  let sb = StringBuilder::new()
  sb.write_string("D")
  if doc.frontmatter is Some(_) {
    sb.write_string("+")
  }
  if doc.eol is Crlf {
    sb.write_string("r")
  }
  sb.write_string(blocks_sig(doc.body))
  sb.write_string("[")
  for i, r in doc.roots {
    if i > 0 {
      sb.write_string(" ")
    }
    sb.write_string(node_sig(r.node))
    sb.write_string("[")
    for j, w in r.wings {
      if j > 0 {
        sb.write_string(" ")
      }
      sb.write_string(if w.side is Right { ">" } else { "<" })
      sb.write_string(branch_sig(w.branch))
    }
    sb.write_string("]")
  }
  sb.write_string("]")
  sb.to_string()
}

///|
fn branch_sig(b : Branch) -> String {
  let sb = StringBuilder::new()
  sb.write_string(node_sig(b.node))
  if not_empty(b.children) {
    sb.write_string("[")
    for i, c in b.children {
      if i > 0 {
        sb.write_string(" ")
      }
      sb.write_string(branch_sig(c))
    }
    sb.write_string("]")
  }
  sb.to_string()
}

///|
/// 骨格 1 つ。`#ラベル` / `-ラベル` / `·`（綴りが無い）。
fn node_sig(n : Node) -> String {
  match n {
    Implicit => "·"
    Explicit(sign~, label~, folded~, body~) => {
      let sb = StringBuilder::new()
      sb.write_string(if sign is Heading { "#" } else { "-" })
      if folded {
        sb.write_string("^")
      }
      sb.write_string(label.escape())
      sb.write_string(blocks_sig(body))
      sb.to_string()
    }
  }
}

///|
/// 中身の列。空なら何も書かない（在るときだけ `(…)`）。
fn blocks_sig(bs : Array[Block]) -> String {
  if bs.is_empty() {
    return ""
  }
  let sb = StringBuilder::new()
  sb.write_string("(")
  for i, b in bs {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string(block_sig(b))
  }
  sb.write_string(")")
  sb.to_string()
}

///|
fn block_sig(b : Block) -> String {
  match b {
    Rule => "r"
    Opaque(text) => text.escape()
    Content(Image(..)) => "img"
    Content(Link(..)) => "link"
    Content(Code(..)) => "code"
    Content(Svg(_)) => "svg"
  }
}

///|
fn not_empty(a : Array[Branch]) -> Bool {
  !a.is_empty()
}
