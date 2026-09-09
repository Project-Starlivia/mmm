// 右クリックメニューの行。何をするかは Intent で言い、沈む行は理由を持つ。
// キーの表（keys.mbt）と同じ作り方を引き、意味を 2 か所に書かない。
// 器（並べる・置く・閉じる）は ts の menu.ts。

///|
/// 1 行。`mark` は絵の名（ts の icons.ts の表）。intent が None なら沈む（why が理由）
pub(all) struct Item {
  label : String
  key : String?
  mark : String?
  intent : Intent?
  why : String?
  items : Array[Item]?
} derive(Eq, Debug, ToJson)

///|
pub(all) enum Entry {
  Item(Item)
  Sep
} derive(Eq, Debug, ToJson)

///|
let one_node = "Select one node"

///|
fn item(
  label : String,
  intent : Intent?,
  key? : String,
  mark? : String,
  why? : String,
  items? : Array[Item],
) -> Entry {
  Item({ label, key, mark, intent, why, items, })
}

///|
/// 右クリックの行。**群ごとに区切りを挟んだ 1 本の列**で、意味はキーの表
/// （keys.mbt）から引く — 同じことを 2 か所に書かない。
pub fn items(l : Layout, sel : Selection) -> Array[Entry] {
  let m = Menu::new(l, sel)
  [
    ..adding(m),
    Sep,
    ..turning(m),
    Sep,
    ..attaching(m),
    Sep,
    ..clipping(m),
    Sep,
    item("Delete", m.press("Delete", false, false), key="Del", mark="trash-2"),
  ]
}

///|
/// 行を組む手元。**宛先が 1 つに決まるか**が多くの行の沈む理由なので、
/// その答えと言い分をここが持つ。
priv struct Menu {
  l : Layout
  sel : Selection
  /// 宛先。1 つに決まらなければ無い
  id : Int?
  /// 宛先のノード
  node : @view.Node?
}

///|
fn Menu::new(l : Layout, sel : Selection) -> Menu {
  { l, sel, id: solo(sel), node: node_of(l, sel.anchor), }
}

///|
/// そのキーを押したのと同じ Intent。
fn Menu::press(self : Menu, key : String, shift : Bool, mod : Bool) -> Intent? {
  keyed(self.l, self.sel, { key, shift, mod, alt: false, })
}

///|
/// 宛先が 1 つに決まるときだけ通す。
fn Menu::only(self : Menu, i : Intent?) -> Intent? {
  if self.id is None {
    None
  } else {
    i
  }
}

///|
/// 宛先が 1 つに決まらないと沈む行の言い分。
fn Menu::why_one(self : Menu) -> String? {
  if self.id is None {
    Some(one_node)
  } else {
    None
  }
}

///|
/// 宛先が畳まれている。
fn Menu::folded(self : Menu) -> Bool {
  self.node is Some(n) && n.fold is Some(_)
}

// ══════════════════════════════════════════════════════════════════
// 群 — 区切りで挟む 1 かたまり
// ══════════════════════════════════════════════════════════════════

///|
/// 足す・名前を直す。**Below / Above は「押せば足す」が常に正しい**ので、ここだけ
/// キーを通さず `AddNode` を直に組む（Enter は名前の無いノードでは「埋める」に
/// 化けるが、メニューの Below / Above はそれでは困る）。
fn adding(m : Menu) -> Array[Entry] {
  let at = (a : @op.NodePlace) => Op(op=AddNode(at=a, labels=[""]), edit=true)
  let sub = (label : String, key : String, intent : Intent?) => {
    (
      {
        label,
        key: Some(key),
        mark: None,
        intent: m.only(intent),
        why: m.why_one(),
        items: None,
      } : Item)
  }
  [
    item(
      "Add",
      m.only(m.press("Tab", false, false)),
      key="Tab",
      why?=m.why_one(),
      items=[
        sub("Child", "Tab", m.press("Tab", false, false)),
        sub("Below", "Enter", m.id.map(i => at(After(node=i)))),
        sub("Above", "Shift+Enter", m.id.map(i => at(Before(node=i)))),
        sub("Parent", "Shift+Tab", m.press("Tab", true, false)),
      ],
    ),
    item(
      "Rename",
      m.only(m.press("Enter", false, true)),
      key="Mod+Enter",
      mark="pencil",
      why?=m.why_one(),
    ),
  ]
}

///|
/// 見え方を変える — 畳む / 開く、側を裏返す。
/// **anchor が無いなら why は付けない**（沈む理由は「選んでいない」こと自体が語る）。
fn turning(m : Menu) -> Array[Entry] {
  [
    // 畳みは 1 歩ずつ巡る（畳む → 開く → 外す）。行はキーと同じ 1 歩を名乗る
    item(
      fold_label(m.node),
      if m.node is None {
        None
      } else {
        m.press("F", true, false)
      },
      key="Shift+F",
      mark=if m.folded() { "chevrons-up-down" } else { "chevrons-down-up" },
    ),
    match m.sel.anchor {
      Some(a) if parent_of(m.l, a) is Some(_) =>
        item(
          "Flip side",
          Some(Op(op=FlipSide(id=a), edit=false)),
          mark="flip-horizontal",
        )
      _ =>
        item(
          "Flip side",
          None,
          mark="flip-horizontal",
          why="The root has no side",
        )
    },
  ]
}

///|
/// 中身を 1 枚足す — リンク / コード / 絵。宛先が 1 つに決まるときだけ。
fn attaching(m : Menu) -> Array[Entry] {
  [
    item(
      "Link",
      m.id.map(i => AddLink(id=i)),
      key="Shift+L",
      mark="link",
      why?=m.why_one(),
    ),
    item(
      "Code",
      m.id.map(i => AddCode(id=i)),
      key="Shift+C",
      mark="code",
      why?=m.why_one(),
    ),
    item(
      "Draw",
      m.id.map(i => Draw(id=i)),
      key="Shift+D",
      mark="paintbrush",
      why?=m.why_one(),
    ),
  ]
}

///|
/// クリップボード — 写す / 切り取る / 貼る。
fn clipping(m : Menu) -> Array[Entry] {
  [
    item("Copy", m.press("c", false, true), key="Mod+C", mark="copy"),
    item("Cut", m.press("x", false, true), key="Mod+X", mark="scissors"),
    item(
      "Paste",
      m.press("v", false, true),
      key="Mod+V",
      mark="clipboard-paste",
    ),
  ]
}
