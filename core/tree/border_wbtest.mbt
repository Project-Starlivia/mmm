// 境界（左右の反転）を、定義の 3 手どおりに固定する。
//
// 1. `---` で左右が変わらないものとして読む — 深さと中身の持ち主はここで決まる
// 2. 持ち主がノード・直後が骨格の行・その行が同じ木、の 3 つを満たす水平線だけが境界
// 3. 境界は、後ろの行を前の行（根を除く）の子にせず、深さのまま根の下へ置き直すだけ
//
// 決めは docs/spec.md「水平線」と docs/superpowers/specs/2026-09-15-border-design.md。
// 表は設計書の例そのもの。木を 1 行の形にして比べる。

///|
/// 木の形を 1 行に。Implicit は `()`、名前の無い行は `""`、中身は `{}` に原文、
/// 根の子で左に居るものは `左:`、根どうしは ` ; `、文書の中身は頭に `文書{}`
fn border_sig(md : String) -> String {
  let doc = parse(md)
  fn label(n : Node) -> String {
    match (n.mark, n.label) {
      (None, _) => "()"
      (_, "") => "\"\""
      (_, l) => l.split("\n").map(x => x.to_owned()).collect().join("⏎")
    }
  }

  fn body(bs : Array[Block]) -> String {
    if bs.is_empty() {
      ""
    } else {
      "{" + bs.map(b => b.source.unwrap_or("?")).join(", ") + "}"
    }
  }

  fn node(n : Node, sides : Array[Side]) -> String {
    let head = label(n) + body(n.body)
    guard !n.children.is_empty() else { return head }
    let kids = n.children.mapi((i, k) => {
      let left = if sides.get(i) is Some(Left) { "左:" } else { "" }
      left + node(k, [])
    })
    head + " → [" + kids.join(", ") + "]"
  }

  let roots = doc.roots.map(r => node(r.node, r.sides)).join(" ; ")
  if doc.body.is_empty() {
    roots
  } else {
    "文書" + body(doc.body) + " " + roots
  }
}

///|
/// 設計書の例。(md, 木の形)
let border_cases : Array[(String, String)] = [
  // ---- 見出しの根 ----
  ("# r\n\n## a\n\n---\n\n## b\n", "r → [a, 左:b]"),
  ("# r\n\n---\n\n## a\n", "r → [左:a]"),
  ("# r\n\n## a\n\n---\n\n### x\n", "r → [a, 左:() → [x]]"),
  ("# r\n\n## a\n\n### x\n\n---\n\n### y\n", "r → [a → [x], 左:() → [y]]"),
  ("# r\n\n## a\n\n---\n\n- b\n- c\n", "r → [a, 左:() → [b, c]]"),
  ("# r\n\n## a\n\n---\n\n---\n\n## b\n", "r → [a{---}, 左:b]"),
  ("# r\n\n---\n\n# s\n", "r{---} ; s"),
  ("# H\n\n- r\n\n---\n\n- c\n", "H → [r, 左:c]"),
  ("# r\n\n---\n\n## b\n\ntext\n", "r → [左:b{text}]"),
  ("# r\n\n## a\n\n---\n\n- b\n\ntext\n", "r → [a{text}, 左:() → [b]]"),
  ("## 野菜\n\n---\n\n- 肉\n\nメモ\n", "() → [野菜{メモ}, 左:() → [肉]]"),
  // ---- 文書の body ----
  ("---\n\n## a\n", "文書{---} () → [a]"),
  ("---\n\n- a\n", "文書{---} a"),
  ("body\n\n---\n\n# a\n", "文書{body, ---} a"),
  ("- a\n\n---\n\n## b\n", "文書{---} a ; () → [b]"),
  ("- a\n\n---\n\n- b\n", "文書{---} a ; b"),
  ("- r\n  - b\n\n---\n\n  - c\n", "文書{---} r → [b] ; c"),
  // ---- 項目の根 ----
  ("- r\n\n  ---\n\n  - a\n", "r → [左:a]"),
  ("- r\n\n  ---\n\n  # head\n", "r → [左:head]"),
  ("- r\n\n  ---\n\n  - a\n\n  ---\n\n  # b\n", "r → [左:a, b]"),
  ("- r\n  - b\n\n    ---\n\n  - c\n", "r → [b, 左:c]"),
  ("- r\n  - b\n\n    ---\n\n    - x\n", "r → [b, 左:() → [x]]"),
  (
    "- r\n  - b\n\n    ---\n\n    - x\n\n    text\n\n    - y\n", "r → [b{text}, 左:() → [x, y]]",
  ),
  (
    "- 買い物\n  - 野菜\n\n    ---\n\n    - 肉\n\n    メモ\n\n    - 魚\n", "買い物 → [野菜{メモ}, 左:() → [肉, 魚]]",
  ),
  ("- r\n\n  ---\n", "r{---}"),
  ("- r\n\n  ---\n\n  memo\n", "r{---, memo}"),
  ("- r\n\n  ---\n\n- s\n", "r{---} ; s"),
  ("- r\n\n---\n", "文書{---} r"),
  ("- r\n  ---\n", "\"\" → [() → [r]]"),
  // ---- 根でない項目 ----
  ("# R\n\n- r\n\n  ---\n\n  - x\n", "R → [r, 左:() → [x]]"),
  // ---- 項目の body（字下げが戻れば入れ子を閉じる） ----
  ("- r\n\n  text\n", "r{text}"),
  ("- r\n  - a\n\n    text\n", "r → [a{text}]"),
  ("- r\n  - a\n\n  text\n", "r{text} → [a]"),
  ("- r\n  - a\n\n  text\n\n  - b\n", "r{text} → [a, b]"),
  ("- r\n  - a\n\ntext\n", "文書{text} r → [a]"),
  ("# H\n\n- r\n  - a\n\ntext\n", "H{text} → [r → [a]]"),
  ("- r\n\n  # h\n\n  text\n", "r → [h{text}]"),
  ("- r\n  - a\n    - b\n\n  ## h\n", "r → [a → [b], () → [h]]"),
  // ---- 作者の確認の見本 ----
  (
    "- # head\n  - li\n  memo\n  \n  ---\n  \n  ## abc\n- - - li\n\n  ---\n\n  memo\n  - li\n    memo\n    - li\n    memo\n",
    "\"\" → [head → [li⏎memo], 左:() → [abc]] ; \"\"{---, memo} → [\"\" → [li], li⏎memo → [li⏎memo]]",
  ),
]

///|
test "境界 — 設計書の例" {
  let bad = []
  for c in border_cases {
    let got = border_sig(c.0)
    if got != c.1 {
      bad.push("\{c.0.escape()}\n  want \{c.1}\n  got  \{got}")
    }
  }
  if !bad.is_empty() {
    fail("\{bad.length()} / \{border_cases.length()} が違う\n" + bad.join("\n"))
  }
}
