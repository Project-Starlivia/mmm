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
fn press(
  l : Layout,
  sel : Selection,
  key : String,
  shift : Bool,
  mod : Bool,
) -> Intent? {
  keyed(l, sel, { key, shift, mod, alt: false, })
}

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
/// 右クリックの行
pub fn items(l : Layout, sel : Selection) -> Array[Entry] {
  let id = solo(sel)
  let node = node_of(l, sel.anchor)
  /// 宛先が 1 つに決まらないと沈む行の why
  let why_one = if id is None { Some(one_node) } else { None }
  let only = (i : Intent?) => if id is None { None } else { i }
  let folded = node is Some(n) && n.fold is Some(_)
  // Below / Above は「押せば足す」が常に正しい（Enter は名前の無いノードでは
  // 「埋める」に化けるが、メニューの Below/Above はそれでは困る）。ここだけ
  // press を通さず、AddNode を直に組む
  let add_at = (at : @op.NodePlace) => {
    Op(op=AddNode(at~, labels=[""]), edit=true)
  }
  let sub = (label : String, key : String, intent : Intent?) => {
    (
      {
        label,
        key: Some(key),
        mark: None,
        intent: only(intent),
        why: why_one,
        items: None,
      } : Item)
  }
  [
    item(
      "Add",
      only(press(l, sel, "Tab", false, false)),
      key="Tab",
      why?=why_one,
      items=[
        sub("Child", "Tab", press(l, sel, "Tab", false, false)),
        sub("Below", "Enter", id.map(i => add_at(After(node=i)))),
        sub("Above", "Shift+Enter", id.map(i => add_at(Before(node=i)))),
        sub("Parent", "Shift+Tab", press(l, sel, "Tab", true, false)),
      ],
    ),
    item(
      "Rename",
      only(press(l, sel, "Enter", false, true)),
      key="Mod+Enter",
      mark="pencil",
      why?=why_one,
    ),
    Sep,
    // anchor が無い（node が None）なら、沈む理由は「選んでいない」こと自体が
    // 語るので why は付けない
    item(
      if folded {
        "Show (unfold)"
      } else {
        "Hide (fold)"
      },
      if node is None {
        None
      } else {
        press(l, sel, "H", true, false)
      },
      key="Shift+H",
      mark=if folded { "chevrons-up-down" } else { "chevrons-down-up" },
    ),
    match sel.anchor {
      Some(a) if parent_of(l, a) is Some(_) =>
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
    Sep,
    item(
      "Link",
      id.map(i => AddLink(id=i)),
      key="Shift+L",
      mark="link",
      why?=why_one,
    ),
    item(
      "Code",
      id.map(i => AddCode(id=i)),
      key="Shift+C",
      mark="code",
      why?=why_one,
    ),
    item(
      "Draw",
      id.map(i => Draw(id=i)),
      key="Shift+D",
      mark="paintbrush",
      why?=why_one,
    ),
    Sep,
    item("Copy", press(l, sel, "c", false, true), key="Mod+C", mark="copy"),
    item("Cut", press(l, sel, "x", false, true), key="Mod+X", mark="scissors"),
    item(
      "Paste",
      press(l, sel, "v", false, true),
      key="Mod+V",
      mark="clipboard-paste",
    ),
    Sep,
    item(
      "Delete",
      press(l, sel, "Delete", false, false),
      key="Del",
      mark="trash-2",
    ),
  ]
}
