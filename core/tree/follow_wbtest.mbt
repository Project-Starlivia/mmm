// 選択の持ち越し（follow）を、spec の表の行ごとに固定する。
// 入力が md と編集列なので、ここは読みに依存する（位置の話だから）。

///|
/// id のノードの目印（前のサイクルの地番から抜く）。
fn mark_at(md : String, id : Int) -> Mark {
  let (_, spots) = survey(md)
  let s = spots.get(id).unwrap()
  { from: s.from, label: s.label.unwrap() }
}

///|
/// md に edits を当てて読み直し、ids の目印がいまどの id かを並べる。
fn followed(md : String, edits : Array[Edit], ids : Array[Int]) -> Array[Int?] {
  let (_, spots) = survey(apply(md, edits))
  follow(spots, edits, ids.map(id => mark_at(md, id))).map(t => {
    t.bind(x => x.id)
  })
}

///|
test "上にノードを足しても同じノード" {
  // "# r\n\n## a\n" の a は 3。5 に "## n\n\n" を差すと n が 3 になり、a は 4
  assert_eq(
    followed("# r\n\n## a\n", [{ from: 5, to: 5, insert: "## n\n\n" }], [3]),
    [Some(4)],
  )
}

///|
test "頭に # を足す・項目を字下げする" {
  // a は 3。# を足すと "### a" になり、Implicit がもう 1 つ挟まって a は 4
  assert_eq(followed("## a\n", [{ from: 0, to: 0, insert: "#" }], [3]), [
    Some(4),
  ])
  // b が a の子になるが、文書順は変わらないので id も 3 のまま
  assert_eq(followed("- a\n- b\n", [{ from: 4, to: 4, insert: "  " }], [3]), [
    Some(3),
  ])
}

///|
test "行ごと消せば死ぬ。後ろのノードは残る" {
  // a = 3、b = 4。a の行 "## a\n\n" を消すと b が 3
  assert_eq(
    followed("# r\n\n## a\n\n## b\n", [{ from: 5, to: 11, insert: "" }], [3, 4]),
    [None, Some(3)],
  )
}

///|
test "マーカーの一部が残れば生きる。丸ごと消えれば死ぬ" {
  // a は 3。"#" を 1 つ消すと "# a" は深さ 1 に収まり、Implicit が要らず a は 2
  assert_eq(followed("## a\n", [{ from: 0, to: 1, insert: "" }], [3]), [Some(2)])
  assert_eq(followed("## a\n", [{ from: 0, to: 3, insert: "" }], [3]), [None])
}

///|
test "ラベルを消して打ち直しても生きる。行をまるごと打ち直せば死ぬ" {
  // a は 3。ラベルの中だけの編集なら地番は変わらない
  assert_eq(followed("## a\n", [{ from: 3, to: 4, insert: "" }], [3]), [Some(3)])
  assert_eq(followed("## a\n", [{ from: 3, to: 4, insert: "b" }], [3]), [
    Some(3),
  ])
  assert_eq(followed("## a\n", [{ from: 0, to: 4, insert: "## b" }], [3]), [
    None,
  ])
}

///|
test "ラベルの頭が消去の内側に落ちれば死ぬ" {
  assert_eq(followed("## a\n", [{ from: 1, to: 4, insert: "" }], [3]), [None])
}

///|
/// 頭にカーソルを置いて `## n` を打ち、それから Enter。打った瞬間は 1 つの見出し
/// `## n## a` で当たらないが、目印は黙って持ち越し、Enter で戻る。
test "途中のサイクルでは黙って持ち越し、次で戻る" {
  let md = "# r\n\n## a\n"
  let m = mark_at(md, 3)
  assert_eq(m, { from: 5, label: 8 })
  let e1 : Array[Edit] = [{ from: 5, to: 5, insert: "## n" }]
  let md1 = apply(md, e1)
  let (_, s1) = survey(md1)
  let t1 = follow(s1, e1, [m])
  assert_eq(t1, [Some({ mark: { from: 5, label: 12 }, id: None })])
  let e2 : Array[Edit] = [{ from: 9, to: 9, insert: "\n\n" }]
  let (_, s2) = survey(apply(md1, e2))
  // 当たったら目印は今の地番のもの（from も新しくなる）
  assert_eq(follow(s2, e2, [t1[0].unwrap().mark]), [
    Some({ mark: { from: 11, label: 14 }, id: Some(4) }),
  ])
}

///|
test "目印が無ければ何も返らない。編集が無ければそのまま当たる" {
  assert_eq(followed("# a\n", [], []), [])
  assert_eq(followed("# a\n", [], [2]), [Some(2)])
}

///|
/// 編集列に消去と挿入が並ぶ。写す差分は元の位置に対して合算する
/// （写した位置と元座標の編集を比べると、消去の後ろの挿入を取りこぼす）。
test "消去の後ろの挿入も数える" {
  // r=2 a=3 b=4 c=5。a の行を消し、b の後ろに XX を足す。c は 4 になり、ラベルは 20 → 16
  assert_eq(
    followed(
      "# r\n\n## a\n\n## b\n\n## c\n",
      [{ from: 5, to: 11, insert: "" }, { from: 15, to: 15, insert: "XX" }],
      [5],
    ),
    [Some(4)],
  )
}

///|
/// 隣り合う消去が合わせてマーカーを消せば死ぬ。`followed` は「死んだ」（Trail 自体
/// が None）と「亡霊」（Trail はあるが id が None）を id だけでは見分けられないので、
/// ここは `follow` を直に呼んで Trail のレベルで確かめる。
test "繋がった消去でマーカーが消えれば死ぬ" {
  let md = "# r\n\n## a\n"
  let m = mark_at(md, 3)
  let edits : Array[Edit] = [
    { from: 5, to: 6, insert: "" },
    { from: 6, to: 8, insert: "" },
  ]
  let (_, spots) = survey(apply(md, edits))
  assert_eq(follow(spots, edits, [m]), [None])
}
