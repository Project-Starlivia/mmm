// 「この md はこの木になる」を指紋で固定する。
//
//   #  見出し   ·  Implicit（綴りが無い）   >  右の翼   <  左の翼

///|
test "見出し 1 つが木 1 本になる" {
  inspect(
    sig(parse("# a\n")),
    content=(
      #|D[#"a"[]]
    ),
  )
}

///|
test "深さ 1 が 2 つなら木も 2 本" {
  inspect(
    sig(parse("# a\n\n# b\n")),
    content=(
      #|D[#"a"[] #"b"[]]
    ),
  )
}

///|
test "深さ 2 は根の翼になる" {
  inspect(
    sig(parse("# r\n\n## a\n\n## b\n")),
    content=(
      #|D[#"r"[>#"a" >#"b"]]
    ),
  )
}

///|
test "深さ 3 は翼の下の枝" {
  inspect(
    sig(parse("# r\n\n## a\n\n### x\n\n## b\n")),
    content=(
      #|D[#"r"[>#"a"[#"x"] >#"b"]]
    ),
  )
}

///|
test "浅く戻る" {
  inspect(
    sig(parse("# r\n\n## a\n\n### x\n\n#### y\n\n## b\n")),
    content=(
      #|D[#"r"[>#"a"[#"x"[#"y"]] >#"b"]]
    ),
  )
}

///|
test "飛びは Implicit が埋める" {
  inspect(
    sig(parse("# r\n\n### x\n")),
    content=(
      #|D[#"r"[>·[#"x"]]]
    ),
  )
}

///|
test "深さ 1 が無ければ根が Implicit になる" {
  inspect(
    sig(parse("## a\n\n## b\n")),
    content=(
      #|D[·[>#"a" >#"b"]]
    ),
  )
}

///|
test "ラベルは原文の逐語（インラインを解釈しない）" {
  inspect(
    sig(parse("# a **b** `c`\n")),
    content=(
      #|D[#"a **b** `c`"[]]
    ),
  )
}

///|
test "中身の無い見出しは空ラベル" {
  inspect(
    sig(parse("# \n")),
    content=(
      #|D[#""[]]
    ),
  )
}

///|
test "封筒と改行の流儀" {
  inspect(
    sig(parse("---\nk: v\n---\n\n# a\n")),
    content=(
      #|D+[#"a"[]]
    ),
  )
  inspect(
    sig(parse("# a\r\n")),
    content=(
      #|Dr[#"a"[]]
    ),
  )
}
