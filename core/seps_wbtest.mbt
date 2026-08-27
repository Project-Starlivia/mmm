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
test "3 本以上の境界も切り替え 1 回" {
  // 本数の偶奇に意味を持たせない — 3 本も 2 本と同じく 1 回だけ切り替わる
  let s = sides_of("# r\n\n## a\n\n---\n---\n---\n\n## b\n")
  assert_eq(s[2], ("b", 1, true))
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
test "ルート直後の境界は、ルートの本文に数えない" {
  // ルートの範囲は境界で切られない（子を全部含む）ので、has_content の
  // 判定を素朴に「次の見出しの手前」で取ると、区切り行が本文に見えてしまう
  ignore(init_doc("# r\n\n---\n---\n\n## a\n"))
  assert_eq(st.nodes[0].has_content, false)
}

///|
test "本文の追記は、ルートの境界の手前に書く" {
  // Node.content_end も has_content と同じ規則（境界で頭打ち）を見ないと、
  // 追記した本文がルート自身の境界の下、次のグループの前に紛れ込む
  ignore(init_doc("# r\n\n---\n---\n\n## a\n"))
  ignore(insert_content(st.nodes[0].id, "![](x.png)", ""))
  assert_eq(get_text(), "# r\n\n![](x.png)\n\n---\n---\n\n## a\n")
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

///|
/// ラベル → 側（左なら true）。
fn side_of(label : String) -> Bool {
  for nd in st.nodes {
    if nd.label == label {
      return nd.left
    }
  }
  abort("side_of: label not found: " + label)
}

///|
test "グループが空になったら、両脇の境界は xor で 1 つに畳む" {
  // [a] 分割 [b] 切り替え [c] … b を消すと 分割+切り替え = 切り替え 1 つ
  ignore(init_doc("# r\n\n## a\n\n---\n\n## b\n\n---\n---\n\n## c\n"))
  assert_eq(side_of("c"), true)
  let b = st.nodes[2].id
  ignore(delete_nodes([b]))
  assert_eq(get_text(), "# r\n\n## a\n\n---\n---\n\n## c\n")
  assert_eq(side_of("c"), true) // 側は変わらない
}

///|
test "切り替え + 切り替え は分割に畳む（反転 2 回 = 無し）" {
  ignore(init_doc("# r\n\n## a\n\n---\n---\n\n## b\n\n---\n---\n\n## c\n"))
  assert_eq(side_of("c"), false)
  ignore(delete_nodes([st.nodes[2].id]))
  assert_eq(get_text(), "# r\n\n## a\n\n---\n\n## c\n")
  assert_eq(side_of("c"), false)
}

///|
test "分割 + 分割 は分割 1 つに畳む" {
  // 2 行続きに見えても、元が分割 2 つなら反転は 0 回。行数で読むと
  // 「2 本 = 切り替え」に化けるので、ここを書き直すのが掃除の仕事
  ignore(init_doc("# r\n\n## a\n\n---\n\n## b\n\n---\n\n## c\n"))
  ignore(delete_nodes([st.nodes[2].id]))
  assert_eq(get_text(), "# r\n\n## a\n\n---\n\n## c\n")
  assert_eq(side_of("c"), false)
}

///|
test "段下げはグループの壁で止まる（分割の壁でも）" {
  // b の前の兄弟 a は別グループ（分割だけの壁でも Tab は止まる）。
  // 段下げ自体がグループを空けることはもう無い — 空にできる相手（前の
  // 兄弟）は必ず壁の向こうなので、壁で先に止まる
  let src = "# r\n\n## a\n\n---\n\n## b\n\n---\n---\n\n## c\n"
  ignore(init_doc(src))
  ignore(indent_nodes([st.nodes[2].id]))
  assert_eq(get_text(), src)
  assert_eq(side_of("c"), true)
}

///|
test "複数選択の Tab はグループの壁を越えない（無関係なグループの側を変えない）" {
  // r / a(右) / 切り替え / c(左) / 分割 / d(左)。indent([a, c]): a は前の
  // 兄弟が無いので元から対象外、c は前の兄弟 a が別グループなので壁で
  // 止まる。どちらも実行されないので、操作対象のはずだった c はもちろん、
  // 操作対象でない d の側も変わらない（cmd_indent に壁が無かったころは
  // c の段下げだけ通ってしまい、d が右へ飛んでいた）
  let src = "# r\n\n## a\n\n---\n---\n\n## c\n\n---\n\n## d\n"
  ignore(init_doc(src))
  let a = st.nodes[1].id
  let c = st.nodes[2].id
  ignore(indent_nodes([a, c]))
  assert_eq(get_text(), src)
  assert_eq(side_of("a"), false)
  assert_eq(side_of("c"), true)
  assert_eq(side_of("d"), true)
}

///|
test "隣り合わずに無効化した境界も、後ろの生きた境界へ反転を畳む" {
  // cmd_indent は壁で止まるようになったので、「境界が隣り合わずに無効に
  // なる」経路（段下げで見出しの親がルートでなくなる）はもう通れない。
  // sweep_seps 自体の規則を直に確かめるため、その経路が作る状況（c を
  // a の子にする深さ編集）を生の編集で再現する。a-c の切り替えが無効に
  // なっても、その反転ぶんは c-d の分割へ畳まれて切り替えになり、
  // 操作対象でない d の側は変わらない
  ignore(init_doc("# r\n\n## a\n\n---\n---\n\n## c\n\n---\n\n## d\n"))
  assert_eq(side_of("c"), true)
  assert_eq(side_of("d"), true)
  let marks = sep_marks()
  let base = st.last_sets.length()
  apply_sets([[prefix_edit(2, st.nodes[2].depth + 1)]], "")
  sweep_seps(marks, base)
  assert_eq(get_text(), "# r\n\n## a\n\n### c\n\n---\n---\n\n## d\n")
  assert_eq(side_of("d"), true)
}

///|
test "キーからの追加は、文書末尾のグループに入る" {
  ignore(init_doc("# r\n\n## a\n\n---\n---\n\n## b\n"))
  ignore(add_child(1, "")) // ルートに子を足す
  assert_eq(get_text(), "# r\n\n## a\n\n---\n---\n\n## b\n\n## \n")
  assert_eq(st.nodes[3].left, true) // 末尾のグループ = 左
  // 兄弟の追加は、その枝のグループの中に入る（区切りは書かれない）
  ignore(add_sibling(2, ""))
  assert_eq(get_text(), "# r\n\n## a\n\n## \n\n---\n---\n\n## b\n\n## \n")
}

///|
test "末尾のグループが空になったら、手前の境界ごと消す" {
  ignore(init_doc("# r\n\n## a\n\n---\n---\n\n## b\n"))
  ignore(delete_nodes([st.nodes[2].id]))
  assert_eq(get_text(), "# r\n\n## a\n")
}

///|
test "先頭の境界（左始まりの表現）は、そのまま残す" {
  ignore(init_doc("# r\n\n---\n---\n\n## a\n\n## b\n"))
  ignore(delete_nodes([st.nodes[2].id])) // b を消しても a はまだ居る
  assert_eq(get_text(), "# r\n\n---\n---\n\n## a\n")
  assert_eq(side_of("a"), true)
}

///|
test "掃除まで含めて undo は 1 回" {
  let src = "# r\n\n## a\n\n---\n\n## b\n\n---\n---\n\n## c\n"
  ignore(init_doc(src))
  ignore(delete_nodes([st.nodes[2].id]))
  ignore(undo())
  assert_eq(get_text(), src)
}

///|
test "移動でグループが空になっても掃除が効く" {
  ignore(init_doc("# r\n\n## a\n\n---\n\n## b\n\n---\n---\n\n## c\n"))
  // b を a の子にする（グループ 1 が空になる）
  ignore(move_nodes([st.nodes[2].id], st.nodes[1].id, 0))
  assert_eq(side_of("c"), true)
  assert_eq(get_text(), "# r\n\n## a\n\n### b\n\n---\n---\n\n## c\n")
}

///|
test "手で書いた本文の `---` には触らない" {
  // 深い階層の `---` は境界ではない = 掃除の対象にもならない
  let src = "# r\n\n## a\n\n### deep\n\n---\n\n#### x\n\n## b\n"
  ignore(init_doc(src))
  // ノードは r(0) a(1) deep(2) x(3) b(4) の順。消すのは x = 添字 3
  ignore(delete_nodes([st.nodes[3].id])) // x を消す
  assert_eq(get_text(), "# r\n\n## a\n\n### deep\n\n---\n\n## b\n")
}

///|
test "2 つの末尾境界が同時に空いても、1 つの生ランとして畳む" {
  // b, c を両方消すと、a-b と b-c の 2 つの境界が同時に効かなくなり、
  // 間に何も残らないので地続きの 1 本の生ランに潰れる。2 つの目印が
  // 同じランを指すことになるので、掃除が二重に消そうとして編集が
  // 重ならないことを見張る（重なると apply_edit_set が壊れる）
  ignore(init_doc("# r\n\n## a\n\n---\n\n## b\n\n---\n\n## c\n"))
  let b = st.nodes[2].id
  let c = st.nodes[3].id
  ignore(delete_nodes([b, c]))
  assert_eq(get_text(), "# r\n\n## a\n")
}

///|
test "move_as_parent は 2 重に積んだ with_sweep でも掃除が走り、undo は 1 回" {
  // b, c だけの 2 グループ（分割 + 切り替え）で、c を b の子にする。
  // move_as_parent([b], c) は b を c の直前へ動かしてから c を 1 段下げる
  // ので、b-c 間にあった 2 つの境界（a-b, b-c）が同時に空いてくっつき、
  // 掃除（xor で 1 つに畳む）が実際に走る。cmd_move_as_parent は
  // begin_tx の中で cmd_indent（それ自身も with_sweep で包まれている）を
  // 呼ぶので、with_sweep の枠が 2 重に積まれる唯一の場所になる。内側の枠が
  // commit を辞退して undo が 1 回にまとまることをここで見張る
  let src = "# r\n\n## a\n\n---\n\n## b\n\n---\n---\n\n## c\n"
  ignore(init_doc(src))
  let b = st.nodes[2].id
  let c = st.nodes[3].id
  ignore(move_as_parent([b], c))
  assert_eq(get_text(), "# r\n\n## a\n\n---\n---\n\n## b\n\n### c\n")
  ignore(undo())
  assert_eq(get_text(), src)
}

///|
test "flip_side はそのグループだけを反対側へ移す" {
  ignore(init_doc("# r\n\n## a\n\n---\n\n## b\n\n---\n---\n\n## c\n"))
  // 真ん中のグループ [b] だけ左へ。a と c の側は動かない
  ignore(flip_side(st.nodes[2].id))
  assert_eq(side_of("a"), false)
  assert_eq(side_of("b"), true)
  assert_eq(side_of("c"), true)
  assert_eq(get_text(), "# r\n\n## a\n\n---\n---\n\n## b\n\n---\n\n## c\n")
}

///|
test "先頭のグループを反対側へ移すと、ルート直後に境界ができる" {
  ignore(init_doc("# r\n\n## a\n\n---\n\n## b\n"))
  ignore(flip_side(st.nodes[1].id))
  assert_eq(get_text(), "# r\n\n---\n---\n\n## a\n\n---\n---\n\n## b\n")
  assert_eq(side_of("a"), true)
  assert_eq(side_of("b"), false)
}

///|
test "グループが 1 つだけなら、全部が反対側へ" {
  ignore(init_doc("# r\n\n## a\n\n## b\n"))
  ignore(flip_side(st.nodes[1].id))
  assert_eq(get_text(), "# r\n\n---\n---\n\n## a\n\n## b\n")
  assert_eq(side_of("a"), true)
  assert_eq(side_of("b"), true)
}

///|
test "flip_side は 1 回の undo で戻る" {
  let src = "# r\n\n## a\n\n---\n\n## b\n"
  ignore(init_doc(src))
  ignore(flip_side(st.nodes[1].id))
  ignore(undo())
  assert_eq(get_text(), src)
}

///|
test "その側にグループがあれば、最後のグループの末尾へ入れるだけ" {
  ignore(init_doc("# r\n\n## a\n\n---\n\n## b\n\n## c\n"))
  // c を右（既にある側）の末尾へ = 何も書かれない。既に末尾なので変化なし
  ignore(move_side_end([st.nodes[3].id], st.nodes[0].id, false))
  assert_eq(get_text(), "# r\n\n## a\n\n---\n\n## b\n\n## c\n")
  // a を右の末尾へ = グループ 1 の末尾に移る
  ignore(move_side_end([st.nodes[1].id], st.nodes[0].id, false))
  assert_eq(get_text(), "# r\n\n---\n\n## b\n\n## c\n\n## a\n")
}

///|
test "その側にグループが無ければ、切り替えの境界ごと書く" {
  ignore(init_doc("# r\n\n## a\n\n## b\n"))
  ignore(move_side_end([st.nodes[2].id], st.nodes[0].id, true))
  assert_eq(get_text(), "# r\n\n## a\n\n---\n---\n\n## b\n")
  assert_eq(side_of("b"), true)
}

///|
test "空のルートの左へ落とすと、左始まりの文書になる" {
  ignore(init_doc("# r\n\n## a\n"))
  ignore(move_side_end([st.nodes[1].id], st.nodes[0].id, true))
  assert_eq(get_text(), "# r\n\n---\n---\n\n## a\n")
  assert_eq(side_of("a"), true)
}

///|
test "子の無いルートの右脇へ落としても、境界を書かない（右は既定の側）" {
  // r には子が 1 つも無い。右脇へ落とすのはルートの既定の側と同じなので、
  // 境界は要らない。flip を決め打ちしていたころは、右に落としたのに
  // 左始まりの境界を書いてしまっていた
  ignore(init_doc("# r\n\n# r2\n\n## b\n"))
  let r = st.nodes[0].id
  let b = st.nodes[2].id
  ignore(move_side_end([b], r, false))
  assert_eq(get_text(), "# r\n\n## b\n\n# r2\n")
  assert_eq(side_of("b"), false)
}

///|
test "子の無いルートの左脇へ落とすと、切り替えを書く（右が既定の側なので）" {
  ignore(init_doc("# r\n\n# r2\n\n## b\n"))
  let r = st.nodes[0].id
  let b = st.nodes[2].id
  ignore(move_side_end([b], r, true))
  assert_eq(get_text(), "# r\n\n---\n---\n\n## b\n\n# r2\n")
  assert_eq(side_of("b"), true)
}

///|
test "その側の最後のグループが文書の最後のグループでなくても、そこへ入る" {
  // 右の最後のグループ（a）は文書の最後のグループ（x, y の左グループ）
  // ではない。右へ落とした x は文書末尾ではなく a の直後に入るべきで、
  // 残った y の側は変わらない
  ignore(init_doc("# r\n\n## a\n\n---\n---\n\n## x\n\n## y\n"))
  let root = st.nodes[0].id
  let x = st.nodes[2].id
  ignore(move_side_end([x], root, false))
  assert_eq(get_text(), "# r\n\n## a\n\n## x\n\n---\n---\n\n## y\n")
  assert_eq(side_of("x"), false)
  assert_eq(side_of("y"), true)
}

///|
test "move_side_end は 1 回の undo で戻る" {
  let src = "# r\n\n## a\n\n## b\n"
  ignore(init_doc(src))
  ignore(move_side_end([st.nodes[2].id], st.nodes[0].id, true))
  ignore(undo())
  assert_eq(get_text(), src)
}

///|
test "グループの真ん中に落とすと、そのグループを割って入る" {
  ignore(init_doc("# r\n\n## a\n\n## b\n\n## c\n"))
  // c を a と b の間へ、同じ側の新しいグループとして
  ignore(move_new_group([st.nodes[3].id], st.nodes[2].id, true, false))
  assert_eq(get_text(), "# r\n\n## a\n\n---\n\n## c\n\n---\n\n## b\n")
  assert_eq(side_of("a"), false)
  assert_eq(side_of("c"), false)
  assert_eq(side_of("b"), false)
}

///|
test "反対側の新しいグループとして落とす" {
  ignore(init_doc("# r\n\n## a\n\n## b\n\n## c\n"))
  ignore(move_new_group([st.nodes[3].id], st.nodes[2].id, true, true))
  assert_eq(get_text(), "# r\n\n## a\n\n---\n---\n\n## c\n\n---\n---\n\n## b\n")
  assert_eq(side_of("c"), true)
  assert_eq(side_of("b"), false)
}

///|
test "末尾に落とせば、後ろの境界は要らない" {
  ignore(init_doc("# r\n\n## a\n\n## b\n"))
  ignore(move_new_group([st.nodes[1].id], st.nodes[2].id, false, false))
  assert_eq(get_text(), "# r\n\n## b\n\n---\n\n## a\n")
}

///|
test "複数選択は文書順のまま 1 つの新しいグループになる" {
  ignore(init_doc("# r\n\n## a\n\n## b\n\n## c\n\n## d\n"))
  ignore(
    move_new_group([st.nodes[1].id, st.nodes[2].id], st.nodes[4].id, true, true),
  )
  assert_eq(get_text(), "# r\n\n## c\n\n---\n---\n\n## a\n\n## b\n\n---\n---\n\n## d\n")
  assert_eq(side_of("a"), true)
  assert_eq(side_of("b"), true)
  assert_eq(side_of("d"), false)
}

///|
test "移動元の単独グループが空になっても、指定した側を誤らない" {
  // b だけの中間グループを c の後ろへ、同じ側の新しいグループとして動かす。
  // 空いた b の両脇の境界（a-b, b-c）はその場でくっついて 1 本の生の
  // かたまりになる。まだ畳んでいない生の行数のまま読むと 2 行 = 切り替えに
  // 見えてしまい、それを元に c から後ろの側を判定すると誤る
  // （畳んだ後の正しい値は 1 行 = 分割のまま、側は変わらない）
  ignore(init_doc("# r\n\n## a\n\n---\n\n## b\n\n---\n\n## c\n"))
  let b = st.nodes[2].id
  let c = st.nodes[3].id
  ignore(move_new_group([b], c, false, false))
  assert_eq(get_text(), "# r\n\n## a\n\n---\n\n## c\n\n---\n\n## b\n")
  assert_eq(side_of("a"), false)
  assert_eq(side_of("c"), false)
  assert_eq(side_of("b"), false)
}

///|
test "move_new_group で移動元グループが空になっても undo は 1 回" {
  let src = "# r\n\n## a\n\n---\n\n## b\n\n---\n\n## c\n"
  ignore(init_doc(src))
  let b = st.nodes[2].id
  let c = st.nodes[3].id
  ignore(move_new_group([b], c, false, false))
  ignore(undo())
  assert_eq(get_text(), src)
}

///|
test "手前に枝が無くても、既にある先頭の境界は必ず正す（左始まり→右の新グループ）" {
  // 前提: r は右, 先頭の切り替え境界で a・x は左。x を a の手前へ、右の
  // 新グループとして落とす。手前に枝は無いが、ルート直後には既に境界が
  // 効いている（左始まりの表現）。それを無視すると x は古い切り替えを
  // そのまま被って左に着地し、後ろの腕が a との間に書く境界も古い a.left
  // を基準にしてしまい、無関係な a の側まで変わってしまう
  //
  // 「正す」の中身は**消す**こと。x を右にしたい先頭では切り替えが要らず、
  // 先頭の境界の効果は切り替えだけなので、残せば何の意味も持たない行になる
  ignore(init_doc("# r\n\n---\n---\n\n## a\n\n## x\n"))
  let a = st.nodes[1].id
  let x = st.nodes[2].id
  ignore(move_new_group([x], a, true, false))
  assert_eq(get_text(), "# r\n\n## x\n\n---\n---\n\n## a\n")
  assert_eq(side_of("x"), false) // 指定どおり右
  assert_eq(side_of("a"), true) // 操作対象でない a の側は変わらない
}

///|
test "手前に枝が無いとき、既存の境界がそのまま正しければ書き直すだけ（左始まり→左の新グループ）" {
  // 同じ前提で、今度は左の新グループとして落とす。先頭の切り替えは
  // そのままで正しいので、正規形への書き直し（内容は変わらない）になる。
  // x と a の間は新しいグループの区切りとして 1 本増えるが、先頭の境界が
  // 二重に増えることはない
  ignore(init_doc("# r\n\n---\n---\n\n## a\n\n## x\n"))
  let a = st.nodes[1].id
  let x = st.nodes[2].id
  ignore(move_new_group([x], a, true, true))
  assert_eq(get_text(), "# r\n\n---\n---\n\n## x\n\n---\n\n## a\n")
  assert_eq(side_of("x"), true)
  assert_eq(side_of("a"), true)
}

///|
test "既存の境界を書き直す経路（2 つの既存グループの間に割り込む）" {
  // a --- b,c の b の手前へ c を新グループとして落とす。a-b の既存境界は
  // 動かした塊の**手前**（a-c）に付け替えられ、b との間には新しく足す。
  // set_sep_edit（既存の書き直し）と insert_sep_edit（新規）の両方を
  // 1 回の呼び出しで踏む
  ignore(init_doc("# r\n\n## a\n\n---\n\n## b\n\n## c\n"))
  let b = st.nodes[2].id
  let c = st.nodes[3].id
  ignore(move_new_group([c], b, true, false))
  assert_eq(get_text(), "# r\n\n## a\n\n---\n\n## c\n\n---\n\n## b\n")
  assert_eq(side_of("a"), false)
  assert_eq(side_of("c"), false)
  assert_eq(side_of("b"), false)
}

///|
test "並べ替えはグループの壁で止まる" {
  let src = "# r\n\n## a\n\n---\n\n## b\n"
  ignore(init_doc(src))
  ignore(reorder_node(st.nodes[2].id, -1, false)) // b を上へ = 壁
  assert_eq(get_text(), src)
}

///|
test "cross なら壁を越え、越えた先の側になる" {
  ignore(init_doc("# r\n\n## a\n\n---\n---\n\n## b\n"))
  assert_eq(side_of("b"), true)
  ignore(reorder_node(st.nodes[2].id, -1, true))
  assert_eq(get_text(), "# r\n\n## b\n\n## a\n")
  assert_eq(side_of("b"), false)
}

///|
test "壁の無い深さでは cross の有無で変わらない" {
  ignore(init_doc("# r\n\n## a\n\n### x\n\n### y\n"))
  ignore(reorder_node(st.nodes[3].id, -1, false))
  assert_eq(get_text(), "# r\n\n## a\n\n### y\n\n### x\n")
}

///|
test "薄い境界を cross で越えても、分割だけなので側は変わらない" {
  // 1 本の境界（切り替えなし）を越えるだけなら、越えた先も同じ側
  ignore(init_doc("# r\n\n## a\n\n---\n\n## b\n"))
  ignore(reorder_node(st.nodes[2].id, -1, true))
  assert_eq(get_text(), "# r\n\n## b\n\n## a\n")
  assert_eq(side_of("a"), false)
  assert_eq(side_of("b"), false)
}

///|
test "cross で真ん中のグループが空になっても、両脇の境界が畳まれて残る" {
  // b だけの真ん中のグループを cross で抜けると、b の前後の境界が
  // 隣り合って 1 つに畳まれる。操作対象でない a の側は変わらない
  ignore(init_doc("# r\n\n## a\n\n---\n\n## b\n\n---\n\n## c\n"))
  ignore(reorder_node(st.nodes[2].id, 1, true))
  assert_eq(get_text(), "# r\n\n## a\n\n---\n\n## c\n\n## b\n")
  assert_eq(side_of("a"), false)
}

///|
test "壁は dir=1（下方向）でも止まる" {
  let src = "# r\n\n## a\n\n---\n\n## b\n"
  ignore(init_doc(src))
  ignore(reorder_node(st.nodes[1].id, 1, false)) // a を下へ = 壁
  assert_eq(get_text(), src)
}

///|
test "壁を越えた並べ替えも undo は 1 回で戻る" {
  let src = "# r\n\n## a\n\n---\n---\n\n## b\n"
  ignore(init_doc(src))
  ignore(reorder_node(st.nodes[2].id, -1, true))
  ignore(undo())
  assert_eq(get_text(), src)
  assert_eq(side_of("b"), true)
}

///|
/// 先頭の境界は「切り替えが要るなら 1 本、要らないなら無い」。
/// 効果の無い細い境界を残さないし、打ち消すためにもう 1 本足したりもしない。
test "その側の枝を全部反対側へ送ると、先頭の境界は消える" {
  ignore(init_doc("# r\n\n---\n---\n\n## a\n"))
  ignore(move_side_end([st.nodes[1].id], st.nodes[0].id, false))
  assert_eq(get_text(), "# r\n\n## a\n")
  assert_eq(side_of("a"), false)
}

///|
test "枝が複数でも、全部送れば先頭の境界は消える" {
  ignore(init_doc("# r\n\n---\n---\n\n## a\n\n## b\n"))
  ignore(
    move_side_end([st.nodes[1].id, st.nodes[2].id], st.nodes[0].id, false),
  )
  assert_eq(get_text(), "# r\n\n## a\n\n## b\n")
  assert_eq(side_of("a"), false)
  assert_eq(side_of("b"), false)
}

///|
/// 反転は自分自身が逆操作。2 回かければ**バイト単位で**元に戻る。
test "flip_side を 2 回かけると元のテキストに戻る" {
  let src = "# r\n\n## a\n"
  ignore(init_doc(src))
  ignore(flip_side(st.nodes[1].id))
  assert_eq(get_text(), "# r\n\n---\n---\n\n## a\n")
  ignore(flip_side(st.nodes[1].id))
  assert_eq(get_text(), src)
}

///|
test "先頭のグループを右へ戻すと、効果の無い境界は残らない" {
  ignore(init_doc("# r\n\n---\n---\n\n## a\n\n## b\n"))
  // a を先頭の右の新グループへ。先頭の切り替えは要らなくなるので消える
  ignore(move_new_group([st.nodes[1].id], st.nodes[2].id, true, false))
  assert_eq(get_text(), "# r\n\n## a\n\n---\n---\n\n## b\n")
  assert_eq(side_of("a"), false)
  assert_eq(side_of("b"), true)
}

///|
test "move_new_group は、target が動かす範囲の中にあると丸ごと何もしない" {
  // target = a（選んだ 2 つのうちの 1 つ自身）。move_steps の 1 ノードずつの
  // ガードは a だけを飛ばして続行してしまうので、単独選択では隠れる —
  // 後続の c が「動いていない a の手前」へ動いてしまう事故は、複数選択で
  // 初めて表に出る。move_lands_outside はコマンドの入口で丸ごと弾くので、
  // a も c も一切動かない
  let src = "# r\n\n## a\n\n## b\n\n## c\n"
  ignore(init_doc(src))
  let a = st.nodes[1].id
  let c = st.nodes[3].id
  ignore(move_new_group([a, c], a, true, false))
  assert_eq(get_text(), src)
}

///|
test "move_new_group の target はルート直下でなければならない" {
  // a1 はルート直下ではない（a の子）。深い target を渡しても何もしない —
  // 何もしないので、区切りが枝の中に書かれて溜まることも無い
  let src = "# r\n\n## a\n\n### a1\n\n## b\n"
  ignore(init_doc(src))
  let a1 = st.nodes[2].id
  let b = st.nodes[3].id
  ignore(move_new_group([b], a1, true, false))
  assert_eq(get_text(), src)
}

///|
test "見出しの無い文書に区切りだけあっても、境界は 1 つも無くクラッシュもしない" {
  // valid_bounds は「区切りの後ろの最初の見出し」を探すので、見出しが
  // 1 つも無ければ全部の区切りが k>=hn で落ちる。ノードも境界も空のまま
  ignore(init_doc("---\n\n---\n\n---\n"))
  assert_eq(st.nodes.length(), 0)
  assert_eq(st.bounds.length(), 0)
}

///|
test "outdent は掃除を通さない — 無効だった `---` を有効化しても放置する（docstring の例）" {
  // `## a` の下、深い階層にある `---` は元は無効（次の見出し x の親が
  // ルートでない）。x を 2 回段上げしてルート直下の深さまで浅くすると、
  // 次の再構築でその `---` がそのまま境界として読まれるようになる。
  // cmd_outdent は掃除を通さないので、これはそのまま起きる — 意図した挙動
  let src = "# r\n\n## a\n\n### mid\n\n---\n\n#### x\n"
  ignore(init_doc(src))
  let x = st.nodes[3].id // r, a, mid, x
  ignore(outdent_nodes([x]))
  ignore(outdent_nodes([x]))
  assert_eq(get_text(), "# r\n\n## a\n\n### mid\n\n---\n\n## x\n")
  assert_eq(side_of("x"), false) // 区切りは 1 本（分割）なので側は変わらない
}

///|
test "cross は dir=1（下方向）でも壁を越え、越えた先の側になる" {
  // 既存の cross テストは dir=-1 だけを見ていた。切り替え境界を下方向に
  // 越えるときも、越えた先の側になることを確かめる
  ignore(init_doc("# r\n\n## a\n\n---\n---\n\n## b\n"))
  assert_eq(side_of("a"), false)
  ignore(reorder_node(st.nodes[1].id, 1, true)) // a を下へ、cross で b の後ろへ
  assert_eq(get_text(), "# r\n\n---\n---\n\n## b\n\n## a\n")
  assert_eq(side_of("a"), true)
}
