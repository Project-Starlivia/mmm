// Block → カードの分類。何をカードにし、何を落とすか。

///|
/// id は分類に関係ないので、ここでは 1 で揃える
fn block(content : @tree.Content) -> @tree.Block {
  { id: 1, content, }
}

///|
test "Block の種類がカードの種類になる。並びは Block のまま" {
  let rows = cards([
    block(Image(alt="", src="./p.png", title="")),
    block(ThematicBreak),
    block(Link(text="t", href="https://x.example/a", title="")),
    block(Code(info="js", text="1\n")),
    block(
      Details(text="<details>x</details>", open=false, summary=None, body="x"),
    ),
    block(Svg("<svg/>")),
  ])
  assert_eq(rows, [
    Image(path="p.png", name="p.png"),
    Break,
    Link(title="t", url="https://x.example/a"),
    Code(lang="js", lines=["1"]),
    Details(open=false, summary=None, lines=["x"]),
    Svg(markup="<svg/>"),
  ])
}

///|
test "details は open と summary をそのまま持ち、中身はコードと同じ割り方" {
  fn d(open : Bool, summary : String?, body : String) -> Array[Card] {
    cards([block(Details(text="", open~, summary~, body~))])
  }

  assert_eq(d(true, Some("s"), "a\n\nb\n"), [
    Details(open=true, summary=Some("s"), lines=["a", "", "b"]),
  ])
  assert_eq(d(false, None, ""), [Details(open=false, summary=None, lines=[""])])
  assert_eq(d(false, None, "1\n2\n3\n4\n5\n6\n7"), [
    Details(open=false, summary=None, lines=["1", "2", "3", "4", "5", "…"]),
  ])
}

///|
test "リンクは http(s) だけ。題が無ければホスト名" {
  assert_eq(
    cards([block(Link(text="", href="https://x.example/a", title=""))]),
    [Link(title="x.example", url="https://x.example/a")],
  )
  assert_eq(
    cards([
      block(Link(text="", href="http://User:pw@X.Example:8080/p?q#f", title="")),
    ]),
    [Link(title="x.example", url="http://User:pw@X.Example:8080/p?q#f")],
  )
  // scheme は小文字だけ（`new URL` は大文字も読むが、リンクとして拾うのは書かれたまま）
  assert_eq(
    cards([block(Link(text="", href="HTTPS://x.example/", title=""))]),
    [],
  )
  assert_eq(cards([block(Link(text="m", href="mailto:a@b", title=""))]), [])
  assert_eq(cards([block(Link(text="", href="https://", title=""))]), [])
}

///|
test "画像は相対パスだけ。./ は剥がし、名前は最後の要素" {
  assert_eq(cards([block(Image(alt="", src="../pics/y.png", title=""))]), [
    Image(path="../pics/y.png", name="y.png"),
  ])
  assert_eq(cards([block(Image(alt="", src="C:\\pics\\z.png", title=""))]), [
    Image(path="C:\\pics\\z.png", name="z.png"),
  ])
  assert_eq(cards([block(Image(alt="", src="https://x/a.png", title=""))]), [])
  assert_eq(
    cards([block(Image(alt="", src="data:image/png;base64,AA", title=""))]),
    [],
  )
  assert_eq(cards([block(Image(alt="", src="./", title=""))]), [])
}

///|
test "コードは 6 行まで。末尾の改行は行にならず、空なら 1 行" {
  let seven = cards([block(Code(info="", text="1\n2\n3\n4\n5\n6\n7\n"))])
  assert_eq(seven, [Code(lang="", lines=["1", "2", "3", "4", "5", "…"])])
  assert_eq(cards([block(Code(info="", text=""))]), [Code(lang="", lines=[""])])
  assert_eq(cards([block(Code(info="", text="\ta\n"))]), [
    Code(lang="", lines=["  a"]),
  ])
}

///|
test "bare は先頭の ./ だけを落とす" {
  assert_eq(@tree.bare_path("./x/y"), "x/y")
  assert_eq(@tree.bare_path("../x"), "../x")
}

///|
test "Raw はカードにならない" {
  assert_eq(cards([block(Raw("<x>"))]), [])
}
