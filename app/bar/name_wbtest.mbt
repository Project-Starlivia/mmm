// 名乗り

///|
test "Name: 名前とタブ、改名できない理由、未保存の印。押せば改名の続きへ" {
  with_doc(doc => {
    @web.set_style(doc.documentElement(), "--accent", "#5932ff")
    let logo = doc.createElement("svg")
    let filename = doc.createElement("span")
    let dirty = doc.createElement("span")
    let renamed : Ref[Int] = { val: 0, }
    let name = Name::new(doc, filename, dirty, Theme::new(logo, _ => ()), () => {
      renamed.val += 1
    })
    name.show("empty.md", false, false)
    assert_eq(doc.title(), "mmm")
    assert_eq(filename.textContent(), "empty.md")
    // Node にはピッカーも改名の口も無い。**根の深いほうを言う** —
    // ファイルを持てないのだから、改名を持たないのはその後の話
    assert_eq(filename.getAttribute("title"), Some(@parts.no_file_access))
    assert_eq(filename.getAttribute("aria-disabled"), Some("true"))
    name.show("r.md", true, false)
    assert_eq(doc.title(), "r.md - mmm")
    name.set_dirty(true)
    assert_eq(dirty.getAttribute("hidden"), None)
    name.set_dirty(false)
    assert_eq(dirty.getAttribute("hidden"), Some(""))
    @web.click(filename)
    assert_eq(renamed.val, 1)
  })
}
