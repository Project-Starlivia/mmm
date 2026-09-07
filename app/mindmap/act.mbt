// 出ていくもの。Intent（map/keys.mbt・map/context.mbt）を host の操作に、右クリックの行を器の行に。
// 意味は map/ が持ち、ここは配線だけ

///|
/// `https?://` で始まり、空白を含まない
fn is_url(s : String) -> Bool {
  guard s.has_prefix("http://") || s.has_prefix("https://") else {
    return false
  }
  let scheme = if s.has_prefix("https://") { 8 } else { 7 }
  guard s.length() > scheme else { return false }
  for i in 0..<s.length() {
    let c = s[i]
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      return false
    }
  }
  true
}

///|
/// クリップボードの URL をリンクカードにして足し、題（`[]` の中）を打つ。
/// URL として読めなければ `failed`（core にも聞かない — Mod+V は raw を core に
/// 読ませるが、ここは「URL か否か」だけを見て、違えば言う）
fn Mindmap::add_link(self : Mindmap, id : Int) -> Unit {
  (self.host.read_clipboard)(raw => {
    let url = raw.trim(chars=" \t\r\n").to_owned()
    guard is_url(url) else {
      (self.host.failed)("Couldn't read that as a link")
      return
    }
    let f = (self.host.apply)(
      AddBlock(at=In(node=id), content=Link(text="", href=url, title="")),
      false,
    )
    match f {
      Some(block) => self.edit_card(block, from=Some(1), to=Some(1))
      None => ()
    }
  })
}

///|
/// 空のコードカードを足して、本文の行を打つ。core は空のコードを開きと閉じの
/// 2 行で書くので、欄には空行を 1 つ挟んだ形で載せ、そこに頭を置く（打たなければ書かない）
fn Mindmap::add_code(self : Mindmap, id : Int) -> Unit {
  let f = (self.host.apply)(
    AddBlock(at=In(node=id), content=Code(info="", text="")),
    false,
  )
  match f {
    Some(block) =>
      self.edit_card(block, from=Some(4), to=Some(4), text=Some("```\n\n```"))
    None => ()
  }
}

///|
/// その画面の点でメニューを開く。箱の外なら閉じるだけ。触った箱がまだ選ばれて
/// いなければ、それ 1 つに選び直してから並びを組む — 右クリックは選ぶ動作も兼ねる
fn Mindmap::open_menu(self : Mindmap, x : Double, y : Double) -> Unit {
  // メニューも地図の入力。まず地図に持たせてから選ぶ（focusin → 持ち主 → 選択）—
  // 右押下でペインに焦点が入らない環境があり、持たないままだと選び直しが届かない
  self.pane.focus()
  // 開いている欄は閉じてから。メニューは選択を据え直すので、欄の下で id が動かないように
  self.label.close()
  self.card.close()
  guard self.node_at(x, y) is Some(id) else {
    self.menu.hide(false)
    return
  }
  let sel = (self.host.selection)()
  if !sel.ids.contains(id) {
    (self.host.set_selection)({ ids: [id], anchor: Some(id), }, false)
  }
  self.menu.show(
    x,
    y,
    items_of(@map.items(self.layout, (self.host.selection)()), i => self.act(i)),
  )
}

///|
/// 右クリックの行（map/context.mbt）をメニューの器の行に写す。押せば `act` へ渡すだけで、
/// 意味はここに増やさない。沈む行は `why` を押せない理由として持ち、無ければただ沈む。
/// 絵の名は表（parts/icons.mbt）に無ければ落とす
pub fn items_of(
  es : Array[@map.Entry],
  act : (@map.Intent) -> Unit,
) -> Array[@parts.Entry] {
  fn one(it : @map.Item) -> @parts.Entry {
    let row = @parts.row(
      it.label,
      key=it.key,
      mark=it.mark.filter(@parts.is_icon),
      disabled=match (it.intent, it.why) {
        (Some(_), _) => No
        (None, Some(why)) => Why(why)
        (None, None) => Yes
      },
    )
    let run = it.intent.map(i => () => act(i))
    match it.items {
      Some(items) => Sub(row, items.map(one), run)
      None => Run(row, run.unwrap_or(() => ()))
    }
  }

  es.map(e => {
    match e {
      Sep => @parts.Sep
      Item(it) => one(it)
    }
  })
}

///|
/// 「何をするか」を実行する。意味は map/keys.mbt と map/context.mbt が持ち、ここは配線だけ
pub fn Mindmap::act(self : Mindmap, intent : @map.Intent) -> Unit {
  match intent {
    Op(op~, edit~) => (self.host.apply)(op, edit) |> ignore
    Edit(id~, seed~) => self.begin_edit(id, seed) |> ignore
    Select(sel~, reveal~) => {
      (self.host.set_selection)(sel, reveal)
      // 矢印で辿るときだけ寄せる（Mod+A / Esc は reveal が偽）
      match sel.anchor {
        Some(a) if reveal => self.ensure_visible(a)
        _ => ()
      }
    }
    Center => self.center_on_target()
    Pick(id~) => (self.host.set_picked)(id)
    EditCard(id~) => self.edit_card(id)
    AddLink(id~) => self.add_link(id)
    AddCode(id~) => self.add_code(id)
    Draw(id~) => (self.host.draw)(id)
    Paste => (self.host.paste)()
    Copy(cut~) =>
      // 消すのは写せてから。写せなければ（クリップボードが断った）何も失わない
      (self.host.copy)(ok => {
        match cut {
          Some(c) if ok => self.act(c)
          _ => ()
        }
      })
  }
}
