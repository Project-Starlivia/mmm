// 部分木 1 つを md にする「断片」を固定する。合流が dirty の地番に差すもの。
// 木は手で組む（unbuild_wbtest.mbt と同じ道具）。

///|
test "見出しは渡した深さから" {
  inspect(
    fragment(h("a", children=[h("b")]), 2, [], []),
    content=(
      #|## a
      #|
      #|### b
      #|
    ),
  )
}

///|
/// 入れ子は列 0 で出る。容器の桁に合わせるのは差す側の仕事
test "項目は入れ子込み" {
  inspect(
    fragment(item("a", children=[item("b")]), 0, [], []),
    content=(
      #|- a
      #|  - b
      #|
    ),
  )
}

///|
test "Implicit は子だけを書き、側は水平線。綴りが在ればそれ" {
  inspect(
    fragment(gap([h("a"), h("b")]), 1, [Right, Left], []),
    content=(
      #|## a
      #|
      #|---
      #|
      #|## b
      #|
    ),
  )
  inspect(
    fragment(gap([h("a"), h("b")]), 1, [Right, Left], ["", "___"]),
    content=(
      #|## a
      #|
      #|___
      #|
      #|## b
      #|
    ),
  )
}

///|
test "畳みは部分木ごと包む" {
  inspect(
    fragment(
      h("a", children=[h("b")], fold=Some({ open: false, summary: None, })),
      2,
      [],
      [],
    ),
    content=(
      #|<details>
      #|
      #|## a
      #|
      #|### b
      #|
      #|</details>
      #|
    ),
  )
}

///|
/// 定義行は断片の中に留まる。文書の尻へ動かすと、触っていない場所が動く
test "定義行は断片の中" {
  inspect(
    fragment(h("a", body=[raw("[q]: /r")]), 1, [], []),
    content=(
      #|# a
      #|
      #|[q]: /r
      #|
    ),
  )
}

///|
test "散文は根を持たない中身の列" {
  inspect(
    prose([raw("hello"), ..blocks([ThematicBreak])]),
    content=(
      #|hello
      #|
      #|---
      #|
    ),
  )
}
