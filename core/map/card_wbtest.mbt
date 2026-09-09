// Block → カードの分類。何をカードにし、何を落とし、どの中身から起きたか。

///|
fn block(id : Int, content : @tree.Content) -> @tree.Block {
  { id, source: None, content: Some(content), }
}

///|
/// 分類だけを見るとき用。出どころは下の「カードは出どころの id を持つ」が見る
fn kinds(blocks : Array[@tree.Block]) -> Array[Kind] {
  cards(blocks).map(c => c.kind)
}

///|
/// 中身 1 つを分類した結果
fn kind(content : @tree.Content) -> Array[Kind] {
  kinds([block(1, content)])
}

///|
test "Block の種類がカードの種類になる。並びは Block のまま" {
  assert_eq(
    kinds([
      block(1, Image(alt="", src="./p.png", title="")),
      block(2, ThematicBreak),
      block(3, Link(text="t", href="https://x.example/a", title="")),
      block(4, Code(info="js", text="1\n")),
      block(5, Details(open=false, summary=None, body="x")),
      block(6, Svg("<svg/>")),
    ]),
    [
      Image(path="p.png", name="p.png"),
      Break,
      Link(title="t", url="https://x.example/a"),
      Code(lang="js", lines=["1"]),
      Details(open=false, summary=None, lines=["x"]),
      Svg(markup="<svg/>"),
    ],
  )
}

///|
/// **添字は出どころにならない。** カードにならない中身が混じれば枚数はずれるので、
/// 1 枚ずつが自分の出どころを名乗る（#212 — ここがずれて別のカードを掴んでいた）
test "カードは出どころの id を持つ。カードにならない中身は番号を送らない" {
  assert_eq(
    cards([
      block(7, Link(text="a", href="./b.md", title="")),
      block(3, Image(alt="p", src="./p.png", title="")),
      block(9, Image(alt="q", src="https://x/q.png", title="")),
      { id: 2, content: None, source: Some("<x>"), },
      block(5, ThematicBreak),
    ]).map(c => c.id),
    [3, 5],
  )
}

///|
test "details は open と summary をそのまま持ち、中身はコードと同じ割り方" {
  fn d(open : Bool, summary : String?, body : String) -> Array[Kind] {
    kind(Details(open~, summary~, body~))
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
  assert_eq(kind(Link(text="", href="https://x.example/a", title="")), [
    Link(title="x.example", url="https://x.example/a"),
  ])
  assert_eq(
    kind(Link(text="", href="http://User:pw@X.Example:8080/p?q#f", title="")),
    [Link(title="x.example", url="http://User:pw@X.Example:8080/p?q#f")],
  )
  // scheme は小文字だけ（`new URL` は大文字も読むが、リンクとして拾うのは書かれたまま）
  assert_eq(kind(Link(text="", href="HTTPS://x.example/", title="")), [])
  assert_eq(kind(Link(text="m", href="mailto:a@b", title="")), [])
  assert_eq(kind(Link(text="", href="https://", title="")), [])
}

///|
test "画像は相対パスだけ。./ は剥がし、名前は最後の要素" {
  assert_eq(kind(Image(alt="", src="../pics/y.png", title="")), [
    Image(path="../pics/y.png", name="y.png"),
  ])
  assert_eq(kind(Image(alt="", src="C:\\pics\\z.png", title="")), [
    Image(path="C:\\pics\\z.png", name="z.png"),
  ])
  assert_eq(kind(Image(alt="", src="https://x/a.png", title="")), [])
  assert_eq(kind(Image(alt="", src="data:image/png;base64,AA", title="")), [])
  assert_eq(kind(Image(alt="", src="./", title="")), [])
}

///|
test "コードは 6 行まで。末尾の改行は行にならず、空なら 1 行" {
  assert_eq(kind(Code(info="", text="1\n2\n3\n4\n5\n6\n7\n")), [
    Code(lang="", lines=["1", "2", "3", "4", "5", "…"]),
  ])
  assert_eq(kind(Code(info="", text="")), [Code(lang="", lines=[""])])
  assert_eq(kind(Code(info="", text="\ta\n")), [Code(lang="", lines=["  a"])])
}

///|
test "bare は先頭の ./ だけを落とす" {
  assert_eq(@tree.bare_path("./x/y"), "x/y")
  assert_eq(@tree.bare_path("../x"), "../x")
}

///|
test "読み解かなかった中身はカードにならない" {
  assert_eq(cards([{ id: 1, content: None, source: Some("<x>"), }]), [])
}
