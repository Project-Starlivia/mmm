// 名乗り。帯の左 — ファイル名と、それを押せば改名、未保存の印。
// 名前を決めるのは App（保存済みならそのファイル名、まだなら本文から導く）。ここは見せるだけ

///|
pub struct Name {
  doc : @dom.Document
  filename : @dom.Element
  dirty : @dom.Element
  theme : Theme
}

///|
/// `rename` は名前が押されたとき。押せなさは `show` が付け、押した先（改名）は App が持つ。
/// `<span role="button">` なので Enter / Space を自分で出す（theme.mbt のロゴと同じ）
pub fn Name::new(
  doc : @dom.Document,
  filename : @dom.Element,
  dirty : @dom.Element,
  theme : Theme,
  rename : () -> Unit,
) -> Name {
  @web.listen(filename, "click", _ => rename())
  @web.listen(filename, "keydown", e => {
    let k = @web.keyboard(e)
    guard k.key == "Enter" || k.key == " " else { return }
    @web.prevent(e)
    rename()
  })
  { doc, filename, dirty, theme, }
}

///|
/// 名乗りを出し直す。`shown` はいまの名前、`titled` ならタブも名乗る（`filename.md - mmm`）、
/// `saved` はディスクに在るか（改名できるか）。打鍵のたびに呼ばれるので、変わっていないなら DOM に触らない
pub fn Name::show(
  self : Name,
  shown : String,
  titled : Bool,
  saved : Bool,
) -> Unit {
  let title = if titled { shown + " - mmm" } else { "mmm" }
  if self.doc.title() != title {
    self.doc.setTitle(title)
  }
  if self.filename.textContent() != shown {
    self.filename.setTextContent(shown)
  }
  // **押せるときだけ押せる顔をする。** 理由は Files の Rename の行と同じものを使う。
  // 押せなさは `aria-disabled` の 1 つで言う（見た目も読み上げも同じ源）
  match rename_problem(@web.can_save_as(), @web.can_rename(), saved) {
    Some(why) => {
      self.filename.setAttribute("title", why)
      self.filename.setAttribute("aria-disabled", "true")
      self.filename.removeAttribute("tabindex")
    }
    None => {
      self.filename.setAttribute("title", "Rename — click")
      self.filename.removeAttribute("aria-disabled")
      self.filename.setAttribute("tabindex", "0")
    }
  }
}

///|
/// 未保存の印。**判定は App の 1 か所**で、帯の `●` とタブの favicon の両方が同じ答えを見る
pub fn Name::set_dirty(self : Name, dirty : Bool) -> Unit {
  if dirty {
    self.dirty.removeAttribute("hidden")
  } else {
    self.dirty.setAttribute("hidden", "")
  }
  self.theme.set_dirty(dirty)
}
