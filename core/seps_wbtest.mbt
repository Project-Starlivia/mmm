// 区切りの境界から導いたグループ・左右（nd.group / nd.left）を検証する。
// st.nodes を直接見たいので whitebox テスト。

///|
/// ラベル → (group, left)。
fn sides_of(md : String) -> Array[(String, Int, Bool)] {
  ignore(init_doc(md))
  let out : Array[(String, Int, Bool)] = []
  for nd in st.nodes {
    out.push((nd.label, nd.group, nd.left))
  }
  out
}

///|
test "1 本は分割だけ、2 本は左右が替わる" {
  let s = sides_of(
    "# r\n\n## a\n\n---\n\n## b\n\n---\n---\n\n## c\n",
  )
  // r(0,右) a(0,右) b(1,右) c(2,左)
  assert_eq(s[0], ("r", 0, false))
  assert_eq(s[1], ("a", 0, false))
  assert_eq(s[2], ("b", 1, false))
  assert_eq(s[3], ("c", 2, true))
}

///|
test "枝の中のノードは、その枝と同じグループ・同じ側" {
  let s = sides_of("# r\n\n---\n---\n\n## a\n\n### a1\n")
  assert_eq(s[1], ("a", 1, true))
  assert_eq(s[2], ("a1", 1, true))
}

///|
test "front matter・木またぎ・深い階層の区切りは効かない" {
  // front matter: ルートより前。閉じの `---` は直前が本文行なので setext の
  // 下線として消え、開きの `---` だけが区切り候補になるが、直前にノードが
  // 無いので k==0 で落ちる（見出しは r, a の 2 つだけ = 添字は 1 まで）
  assert_eq(sides_of("---\ntitle: x\n---\n\n# r\n\n## a\n")[1].2, false)
  // 木をまたぐ: 次が別の木のルート
  let two = sides_of("# r\n\n## a\n\n---\n\n# r2\n\n## b\n")
  assert_eq(two[2], ("r2", 0, false))
  assert_eq(two[3], ("b", 0, false))
  // 深い階層: 次がルート直下より深い
  assert_eq(sides_of("# r\n\n## a\n\n---\n\n### deep\n")[2], ("deep", 0, false))
}

///|
test "ルート見出しの直後の境界も効く（左始まりの文書）" {
  let s = sides_of("# r\n\n---\n---\n\n## a\n")
  assert_eq(s[0], ("r", 0, false))
  assert_eq(s[1], ("a", 1, true))
}

///|
test "区切りはどのノードの範囲にも属さない" {
  // a をコピーしても `---` は付いてこない
  ignore(init_doc("# r\n\n## a\n\n---\n\n## b\n"))
  assert_eq(selection_text([2]), "## a\n")
  // ルートの範囲は境界で切れない（子を全部含む）
  assert_eq(selection_text([1]), "# r\n\n## a\n\n---\n\n## b\n")
}

///|
test "境界で範囲が切れても親子は変わらない" {
  ignore(init_doc("# r\n\n## a\n\n### a1\n\n---\n\n## b\n"))
  let r = st.nodes[0]
  let a = st.nodes[1]
  let a1 = st.nodes[2]
  let b = st.nodes[3]
  assert_eq(a.parent, r.id)
  assert_eq(a1.parent, a.id)
  assert_eq(b.parent, r.id)
}

///|
test "各木が自分の区切りを読む" {
  // 2 つ目の `#` の下の区切りも、その木の中で効く
  let s = sides_of("# r\n\n## a\n\n# r2\n\n## b\n\n---\n---\n\n## c\n")
  assert_eq(s[3], ("b", 0, false))
  assert_eq(s[4], ("c", 1, true))
}

///|
test "境界の正規形は 1 行 / 2 行、列はルートの形に従う" {
  ignore(init_doc("# r\n\n## a\n"))
  assert_eq(sep_body(1, false), "---\n")
  assert_eq(sep_body(1, true), "---\n---\n")
  // リストの形では、ルート項目の中身の列まで字下げする
  ignore(init_doc("- r\n\n  - a\n"))
  assert_eq(sep_body(1, false), "  ---\n")
}

///|
test "境界の書き足し・書き直し・削除" {
  ignore(init_doc("# r\n\n## a\n\n## b\n"))
  let b = st.nodes[1] // a
  apply_sets([[insert_sep_edit(b.to, 1, false)]], "")
  assert_eq(get_text(), "# r\n\n## a\n\n---\n\n## b\n")
  // 1 本 → 2 本
  apply_sets([[set_sep_edit(st.bounds[0], 1, true)]], "")
  assert_eq(get_text(), "# r\n\n## a\n\n---\n---\n\n## b\n")
  // 消す（前後の空行を 1 つに戻す）
  apply_sets([[remove_sep_edit(st.bounds[0])]], "")
  assert_eq(get_text(), "# r\n\n## a\n\n## b\n")
}
