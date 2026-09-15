// md と操作の境界を固定する。入力が md なので、ここだけは読みに依存する。
// 見るのは「編集を当てた md」の正規形と focus — 編集の切り方（空行を
// どこまで残すか）は合流の試験のもの。

///|
fn applied(md : String, op : Op) -> (String, Int?) {
  let r = edit(md, op)
  (@tree.serialize(@tree.parse(@tree.patched(md, r.edits))), r.focus)
}

///|
test "Rename — 編集を当てれば名前が替わり、focus はそのノード" {
  assert_eq(applied("# a\n", Rename(id=2, label="b")), ("# b\n", Some(2)))
}

///|
test "Rename — 名前の字はそのまま md に置かれ、読み直しても同じ" {
  assert_eq(
    applied("# a\n", Rename(id=2, label="foo_bar")),
    ("# foo_bar\n", Some(2)),
  )
  assert_eq(
    applied("# a\n", Rename(id=2, label="__init__")),
    ("# __init__\n", Some(2)),
  )
  assert_eq(applied("- a\n", Rename(id=2, label="2*3")), ("- 2*3\n", Some(2)))
}

///|
/// 名前が `---` の項目の行（`- ---`）は md では水平線。項目は無くなり、`a` の
/// 中身の水平線になる（その行は読んだ原文なのでそのまま残る）。木と md の形が
/// 食い違うので focus は無い（番号のまま返すと別のノードを指す）
test "Rename — 書いた md が別の形に読まれるなら focus は無い" {
  assert_eq(
    applied("# a\n\n- b\n", Rename(id=3, label="---")),
    ("# a\n\n- ---\n", None),
  )
}

///|
/// 名前が `---` の項目の行（`- ---`）は md では水平線。持ち主 b の中身の尻で、直後の骨格
/// `## d` が同じ木に入るので境界になる — 項目 `c` は木から消え、`d` の側が右から左へ変わる。
/// 書かれた行（`- ---` も 4 本の水平線）は読んだ綴りなので、そのまま返る。
test "Rename — 名前が `---` になれば、直後の骨格の手前の境界になる" {
  assert_eq(
    applied("# a\n\n## b\n\n- c\n\n## d\n", Rename(id=4, label="---")),
    ("# a\n\n## b\n\n- ---\n\n## d\n", None),
  )
}

///|
/// 閉じの `#` は飾りなので、`# foo ##` は名前 `foo` + 閉じ 2 本に読まれる。
/// 読んだ綴りで書き戻すので行は残るが、木（名前 `foo ##`）と md の形が
/// 食い違うので focus は無い。
test "Rename — 閉じの `#` は飾りなので、書けば読みは変わり focus は無い" {
  assert_eq(
    applied("# a\n", Rename(id=2, label="foo ##")),
    ("# foo ##\n", None),
  )
}

///|
test "できない操作 — 編集は無く、focus も無い" {
  assert_eq(edit("# a\n", Rename(id=9, label="b")), { edits: [], focus: None, })
}

///|
test "AddNode — 新しいノードの focus は、読み直したときの番号" {
  // 操作は max+1 の 4 を振るが、a と b の間に差さるので読み直せば 3
  assert_eq(
    applied("# a\n\n# b\n", AddNode(at=After(node=2), label="n")),
    ("# a\n\n# n\n\n# b\n", Some(3)),
  )
}

///|
test "Delete — 消した後は隣が focus。最後の根なら無い" {
  assert_eq(applied("# a\n\n# b\n", Delete(ids=[3])), ("# a\n", Some(2)))
  assert_eq(applied("# a\n", Delete(ids=[2])), ("", None))
}

///|
/// 貼り付けは Graft そのもの（TS は raw を送るだけ）。断片が持ち込むのは形で、綴りは席。
/// 見本は docs/superpowers/specs/2026-09-06-paste-design.md の例
test "Graft — 貼り付けの見本" {
  // 項目を、子が見出しの見出しへ → 見出し
  assert_eq(
    applied(
      "# r\n\n## a\n",
      Graft(at=NodePlace::In(node=2, side=None), md="- b\n"),
    ),
    ("# r\n\n## a\n\n## b\n", Some(4)),
  )
  // 見出し + 項目を、子が項目の見出しへ → 項目
  assert_eq(
    applied(
      "# r\n\n- a\n",
      Graft(at=NodePlace::In(node=2, side=None), md="## b\n\n- c\n"),
    ),
    ("# r\n\n- a\n- b\n  - c\n", Some(4)),
  )
  // カード 1 枚は中身
  assert_eq(
    applied(
      "# r\n",
      Graft(at=NodePlace::In(node=2, side=None), md="![](q.png)\n"),
    ),
    ("# r\n\n![](q.png)\n", Some(3)),
  )
  // 文書へ中身は文書の散文（最初の骨格より前）へ。手で頭に書いたのと同じ形
  assert_eq(
    applied(
      "# r\n",
      Graft(at=NodePlace::In(node=@tree.doc_id, side=None), md="![](q.png)\n"),
    ),
    ("![](q.png)\n\n# r\n", Some(2)),
  )
  // 途中の飛びを 6 段目へ — 飛びは空の項目 `- - - b`
  let six = "# 1\n\n## 2\n\n### 3\n\n#### 4\n\n##### 5\n\n###### t\n"
  assert_eq(
    applied(
      six,
      Graft(at=NodePlace::In(node=7, side=None), md="# a\n\n#### b\n"),
    ),
    (six + "\n- a\n\n  - - - b\n", Some(8)),
  )
}

///|
/// #383 — 断片の側は、書く側と同じ表（`@tree.bordered`）で線に戻す。先頭の子が左でも運び、
/// 手前の部分木の尻が畳みなら線を畳みの中に置かない（置ける行が無ければ側は落ちる）
test "Graft — 断片の先頭の左も運び、畳みの中には線を置かない" {
  let (first, _) = applied(
    "# r\n",
    Graft(at=NodePlace::In(node=2, side=None), md="# p\n\n---\n\n## q\n"),
  )
  inspect(
    first,
    content=(
      #|# r
      #|
      #|## p
      #|
      #|---
      #|
      #|### q
      #|
    ),
  )
  let (folded, _) = applied(
    "# r\n",
    Graft(
      at=NodePlace::In(node=2, side=None),
      md="# p\n\n## a\n\n<details>\n<summary>b</summary>\n\n### b\n\n</details>\n\n---\n\n## c\n",
    ),
  )
  inspect(
    folded,
    content=(
      #|# r
      #|
      #|## p
      #|
      #|### a
      #|
      #|<details>
      #|<summary>b</summary>
      #|
      #|#### b
      #|
      #|</details>
      #|
      #|### c
      #|
    ),
  )
}

///|
/// #118 — 貼った `---` は md と同じ意味。次に骨格が来れば境界（根の子なら側の
/// 反転、深ければ深さを保って根の反対側へ置き直す）。形は md が決めるので focus は無い。
/// 順は崩れない — 中身は直前に生えたノードのもの
test "Graft — 貼った `---` は境界。md が形を決め、focus は無い" {
  // 深さ 2 の席: 次が反対側に
  assert_eq(
    applied(
      "# r\n\n## a\n",
      Graft(at=NodePlace::In(node=2, side=None), md="説明\n\n---\n\n次\n"),
    ),
    ("# r\n\n## a\n\n## 説明\n\n---\n\n## 次\n", None),
  )
  // 深い席: 次は深さを保って根の反対側へ置き直される（md ペインに同じ字を打ったのと同じ）
  assert_eq(
    applied(
      "# r\n\n## a\n\n### x\n",
      Graft(at=NodePlace::In(node=4, side=None), md="説明\n\n---\n\n次\n"),
    ),
    ("# r\n\n## a\n\n### x\n\n#### 説明\n\n---\n\n#### 次\n", None),
  )
  // 断片の側も境界として運ぶ。読んだ字はそのまま（`___` は `___`）
  assert_eq(
    applied(
      "# r\n",
      Graft(at=NodePlace::In(node=2, side=None), md="## q\n\n---\n\n## s\n"),
    ),
    ("# r\n\n## q\n\n---\n\n## s\n", None),
  )
  assert_eq(
    applied(
      "# r\n",
      Graft(at=NodePlace::In(node=2, side=None), md="## q\n\n___\n\n## s\n"),
    ),
    ("# r\n\n## q\n\n___\n\n## s\n", None),
  )
  // md ペインで末尾に `---` を書いてから隣に足す操作も、同じ 1 つの解釈
  assert_eq(
    applied("# r\n\n## a\n\n---\n", AddNode(at=After(node=3), label="b")),
    ("# r\n\n## a\n\n---\n\n## b\n", None),
  )
}

///|
/// #118 — 一番外は順に読む。表 → 段落 → 表 なら、後ろの表は段落のノードの中身
test "Graft — 貼った順は崩れない。中身は直前に生えたノードのもの" {
  let table = "| p | q |\n|---|---|"
  assert_eq(
    applied(
      "# r\n",
      Graft(
        at=NodePlace::In(node=2, side=None),
        md=table + "\n\n説明\n\n" + table + "\n",
      ),
    ),
    ("# r\n\n" + table + "\n\n## 説明\n\n" + table + "\n", Some(4)),
  )
}

///|
/// #84 — 差すものの綴りは席が決める。隣が `*` の列なら `*`
test "新しい項目は隣の綴りを継ぐ — * の列に足せば *" {
  assert_eq(
    applied("# a\n\n* b\n", AddNode(at=After(node=3), label="c")),
    ("# a\n\n* b\n* c\n", Some(4)),
  )
}

///|
/// #84 — 文書の席（`In(doc_id)`）も最後の根に従う。`sign` と同じ見方。
/// 詰まった列に足せば詰まったまま（#203）
test "新しい根の項目は最後の根の綴りを継ぐ — * の根に足せば *" {
  let md = "* a\n"
  let r = edit(md, AddNode(at=In(node=@tree.doc_id, side=None), label="b"))
  assert_eq(@tree.patched(md, r.edits), "* a\n* b\n")
  assert_eq(r.focus, Some(3))
}

///|
/// #84 の見本 — 席で綴り直す。`*` の列の項目を `-` の列へ動かせばマーカーは `-`
test "MoveNode — 席の列の綴りを継ぐ" {
  let md = "# h\n\n* a\n\n## s\n\n- x\n- y\n"
  // a（id 3）を x（id 5）の後ろへ
  let r = edit(md, MoveNode(ids=[3], at=After(node=5)))
  assert_eq(@tree.patched(md, r.edits), "# h\n\n## s\n\n- x\n- a\n- y\n")
  assert_eq(r.focus, Some(5))
}

///|
/// #84 — 詰めも席のもの。空いた列から詰まった列へ動かしても、
/// 触っていない隣の項目の間に空行は生えない
test "MoveNode — 詰まった列へ動かせば詰まったまま" {
  let md = "# h\n\n* a\n\n* b\n\n## s\n\n- x\n- y\n"
  // a（id 3）を y（id 7）の後ろへ
  let r = edit(md, MoveNode(ids=[3], at=After(node=7)))
  assert_eq(@tree.patched(md, r.edits), "# h\n\n* b\n\n## s\n\n- x\n- y\n- a\n")
  assert_eq(r.focus, Some(7))
}

///|
test "MoveNode — 項目を子が見出しの見出しへ動かせば見出しになる" {
  assert_eq(
    applied(
      "# r\n\n## a\n\n# s\n\n- b\n",
      MoveNode(ids=[5], at=NodePlace::In(node=2, side=None)),
    ),
    ("# r\n\n## a\n\n## b\n\n# s\n", Some(4)),
  )
}

///|
/// #85 — 2 行の名前の見出しを触っても 2 行のまま。正規形は冪等
test "改行を含む名前は setext のまま — 触っても 2 行目は消えない" {
  let md = "a\nb\n===\n\ntail\n"
  inspect(@tree.serialize(@tree.parse(md)), content=md)
  assert_eq(
    applied(md, Rename(id=2, label="c\nd")),
    ("c\nd\n===\n\ntail\n", Some(2)),
  )
}

///|
/// 深さ 3 へ改行入りの名前を持ち込む操作は断る
test "改行を含む名前を深さ 3 へ — できない操作" {
  let md = "# a\n\n## b\n\nc\nd\n---\n"
  // c\nd（id 4）を b（id 3）の子へ
  assert_eq(edit(md, MoveNode(ids=[4], at=In(node=3, side=None))), {
    edits: [],
    focus: None,
  })
}

///|
/// #85 — 席が変われば綴りも変わる。項目に読んだ 2 行の名前は setext を持たないが、
/// 深さ 2 の見出しの席なら書けるので setext で綴る（ATX に落とすと 2 行目が消える）
test "MoveNode — 改行を含む名前を見出しの席へ動かせば setext で綴る" {
  let md = "# r\n\n- a\n  b\n\n# s\n"
  // a\nb（id 3）を s（id 4）の子へ
  let r = edit(md, MoveNode(ids=[3], at=In(node=4, side=None)))
  assert_eq(@tree.patched(md, r.edits), "# r\n\n# s\n\na\nb\n---\n")
  assert_eq(r.focus, Some(4))
}

///|
/// #85 — 名前が空なら setext では綴れない。`===` だけの行は下線にならず、
/// 見出しが段落に落ちて子が 1 つ浅くなる。席で保てない綴りは ATX に落とす
/// （空の見出しの行は `#` だけ — Implicit を綴った空の見出しと同じ）
test "Rename — 空の名前の setext は ATX に落ちる" {
  assert_eq(
    applied("a\n===\n\ntail\n", Rename(id=2, label="")),
    ("#\n\ntail\n", Some(2)),
  )
}

///|
/// #85 — 綴りは形ではない。改行の無い setext の見出しを深さ 3 へ動かせば
/// `### c` に綴り直されるが、形は変わらないので focus は残り、編集も
/// その行だけ（文書ごとの置き換えに落ちない）
test "MoveNode — setext の見出しを深さ 3 へ動かせば ATX で綴り直す" {
  let md = "# a\n\n## b\n\nc\n---\n"
  // c（id 4）を b（id 3）の子へ
  let r = edit(md, MoveNode(ids=[4], at=In(node=3, side=None)))
  assert_eq(@tree.patched(md, r.edits), "# a\n\n## b\n\n### c\n")
  assert_eq(r.focus, Some(4))
  assert_false(r.edits.any(e => e.from == 0 && e.to == md.length()))
}

///|
/// #385 — 境界のすぐ手前で子を足す・消す、名前の無い根に名前を付ける、どれも合流は触った所
/// だけを書き換える。境界の `---` は後ろの子の隙間なので、子の手前に差す物は線より前に入り、
/// 手前の子を消しても線は残る
test "合流 — 境界のすぐ手前の足し・消し・名付けは全文へ落ちない" {
  let cases : Array[(String, Op)] = [
    (
      "# r\n\n## a\n\n- i\n\ntext\n\n---\n\n## b\n",
      AddNode(at=After(node=3), label="n"),
    ),
    ("# r\n\n\n\n## a\n\n---\n\n## b\n", AddNode(at=After(node=3), label="n")),
    ("# r\n\n## a\n\n---\n\n## b\n\n## c\n", Delete(ids=[3])),
    ("- r\n  - b\n\n  ---\n\n  - c\n", AddNode(at=After(node=3), label="n")),
    ("- r\n  - b\n\n  ---\n\n  - c\n", Delete(ids=[3])),
    ("## 野菜\n\n---\n\n- 肉\n\nメモ\n", Rename(id=2, label="x")),
  ]
  let out = cases.map(c => {
    let (md, op) = c
    let r = edit(md, op)
    let whole = r.edits.length() == 1 &&
      r.edits[0].from == 0 &&
      r.edits[0].to == md.length()
    "whole=\{whole} \{@tree.patched(md, r.edits).escape()}"
  })
  json_inspect(out, content=[
    "whole=false \"# r\\n\\n## a\\n\\n- i\\n\\ntext\\n\\n## n\\n\\n---\\n\\n## b\\n\"",
    "whole=false \"# r\\n\\n\\n\\n## a\\n\\n## n\\n\\n---\\n\\n## b\\n\"", "whole=false \"# r\\n\\n---\\n\\n## b\\n\\n## c\\n\"",
    "whole=false \"- r\\n  - b\\n\\n  - n\\n\\n  ---\\n\\n  - c\\n\"", "whole=false \"- r\\n\\n  ---\\n\\n  - c\\n\"",
    "whole=false \"# x\\n\\n## 野菜\\n\\n---\\n\\n- 肉\\n\\nメモ\\n\"",
  ])
}
