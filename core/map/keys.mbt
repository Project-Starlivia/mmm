// 地図のキー → 何をするか。DOM も host も知らない表。地図は返った Intent を
// 実行するだけで、段が進めばここに行を足す。
// 決めは docs/superpowers/specs/2026-09-04-label-design.md と shortcuts.md「Mindmap」。

///|
/// 押されたキー。mod は Ctrl / Cmd のどちらか
pub(all) struct Key {
  key : String
  shift : Bool
  mod : Bool
  alt : Bool
} derive(Eq, Debug)

///|
/// 何をするか。ts は実行するだけ（mindmap の act）
pub(all) enum Intent {
  /// 操作を md に映す。edit なら focus をそのまま編集開始。消した後に選ぶ隣は core の focus
  Op(op~ : @op.Op, edit~ : Bool)
  /// その場編集に入る。seed は最初の字（空のノードで打ち始めたとき）
  Edit(id~ : Int, seed~ : String?)
  Select(sel~ : Selection, reveal~ : Bool)
  /// 選択（無ければ根）を画面の中心へ
  Center
  /// カードを選ぶ（None で外す）
  Pick(id~ : Int?)
  /// カードをその場で直す
  EditCard(id~ : Int)
  /// クリップボードの URL をリンクカードにして題を打つ / 空のコードを足して打つ / 描いて貼る
  AddLink(id~ : Int)
  AddCode(id~ : Int)
  Draw(id~ : Int)
  /// クリップボードを貼る。anchor があればそこへ、無ければ文書へ
  Paste
  /// 選んでいるもの（カードならその原文、でなければ選択の部分木）をクリップボードへ写す。
  /// cut は写せてから消すもの（Delete と同じ Intent）。写せなければ消さない
  Copy(cut~ : Intent?)
  /// ペインから帯へ抜ける。**Tab は子を足すのに使うので、抜け道はこれ 1 つ**
  /// （キーボードだけで帯やブラウザへ戻れないと、ペインが罠になる）
  Leave
} derive(Eq, Debug, ToJson, FromJson)

///|
fn op(o : @op.Op) -> Intent {
  Op(op=o, edit=true)
}

///|
/// 空のラベルで足す。読めば label "" になり、そのまま打ち始める
fn add(at : @op.NodePlace) -> Intent {
  op(AddNode(at~, label=""))
}

///|
/// 選択を消す（Delete と Mod+X が同じものを使う）。消した後に選ぶ隣は core が focus で返す
fn remove(sel : Selection) -> Intent? {
  if sel.ids.length() == 0 {
    None
  } else {
    Some(Op(op=Delete(ids=sel.ids), edit=false))
  }
}

///|
/// Mod+C / Mod+X。写すものが無ければ None。cut は消すもの（無ければ Mod+X も拾わない）
fn copy_of(k : Key, cut : () -> Intent?) -> Intent? {
  guard k.mod && !k.alt && !k.shift else { return None }
  let key = k.key.to_lower()
  if key == "c" {
    return Some(Copy(cut=None))
  }
  guard key == "x" else { return None }
  match cut() {
    Some(c) => Some(Copy(cut=Some(c)))
    None => None
  }
}

///|
fn node_of(l : Layout, id : Int?) -> @tree.Node? {
  id.bind(id => l.boxes.get(id)).map(b => b.node)
}

///|
/// キー 1 回ぶん。None は拾わない（ブラウザに渡す）。
///
/// - **宛先は anchor。** いくつ選んでいても同じ（複数選択で Enter を押しても、anchor に
///   対する Enter と同じことが起きる）
/// - 名前がまだ無いノード（label が ""）では「足す」より「埋める」が先: Enter は
///   そのノードの編集に入り、字を打てばその字から書ける（Enter を挟まない）
/// - ノードが 1 つも無ければ、Enter は最初の根
/// - Tab / Shift+Tab は 1 つなら足す・包む、複数なら段下げ・上げ（先頭の前の兄弟の子へ / 先頭の親の後ろへ）
pub fn keyed(l : Layout, sel : Selection, k : Key) -> Intent? {
  // `reordered` が先頭なのは Alt をそこで閉じるため、`pasted` が早いのは貼るのに
  // anchor が要らないため
  table(Hand::new(l, sel, k), [
    reordered, pasted, copied, attached, entered, tabbed, deleted, folded, escaped,
    centered, chose_all, arrowed, typed,
  ])
}

///|
/// **上から順に当て、キーを名乗った行で終わる。** None は拾わない
fn[H] table(h : H, rows : Array[(H) -> Answer]) -> Intent? {
  for row in rows {
    match row(h) {
      Do(i) => return Some(i)
      Stop => return None
      Pass => ()
    }
  }
  None
}

///|
/// 行の答え。**「拾わない」と「拾ったが、いまはできない」は別。** 後者を次の行へ
/// 落とすと、キーが 2 つの意味を持ってしまう（Alt+↑ が動かせないときに素の矢印として
/// 選択を動かす、Shift+L が 2 つ選んでいるときに名前の頭文字として打たれる）。
priv enum Answer {
  /// このキーは自分のものではない。次の行へ
  Pass
  /// 拾った
  Do(Intent)
  /// 拾ったが、いまはできない。次の行へは落とさない
  Stop
}

///|
/// 拾った行の答え。できなければそこで止まる。
fn claimed(i : Intent?) -> Answer {
  match i {
    Some(x) => Do(x)
    None => Stop
  }
}

///|
/// 押されたときの手元。**どの行も同じ形でここを読む。**
priv struct Hand {
  l : Layout
  sel : Selection
  k : Key
  /// 宛先。いくつ選んでいても、行が見るのはこれ 1 つ
  anchor : Int?
  /// 宛先の名前がまだ空。打ち始めればそのまま書ける。**Implicit は当てはまらない**
  /// — 綴りの無いノードは、名前より先に綴りを当てる操作が要る
  blank : Bool
}

///|
fn Hand::new(l : Layout, sel : Selection, k : Key) -> Hand {
  let anchor = sel.anchor
  let blank = node_of(l, anchor) is Some(n) &&
    @tree.sign_of(n) is Some(_) &&
    n.label == ""
  { l, sel, k, anchor, blank, }
}

// ══════════════════════════════════════════════════════════════════
// 行 — 1 つにつき 1 つ。上から順に当たる
// ══════════════════════════════════════════════════════════════════

///|
/// Alt+↑↓ — 兄弟の並べ替え。先頭の手前へ / 末尾の後ろへ。
/// **Alt が意味を持つのはここだけ**なので、ほかの Alt もここで閉じる。
fn reordered(h : Hand) -> Answer {
  guard h.k.alt else { return Pass }
  guard h.k.key == "ArrowUp" || h.k.key == "ArrowDown" else { return Stop }
  guard h.sel.ids.length() > 0 && !h.k.mod else { return Stop }
  let ids = h.sel.ids
  let moved = (at : @op.NodePlace) => Op(op=MoveNode(ids~, at~), edit=false)
  if h.k.key == "ArrowUp" {
    return claimed(prev_sibling(h.l, ids[0]).map(p => moved(Before(node=p))))
  }
  claimed(
    next_sibling(h.l, ids[ids.length() - 1]).map(n => moved(After(node=n))),
  )
}

///|
/// Mod+V — クリップボードを貼る。**anchor が無くても拾う**（貼る先が無ければ文書へ）。
fn pasted(h : Hand) -> Answer {
  guard h.k.mod && !h.k.shift && h.k.key.to_lower() == "v" else { return Pass }
  Do(Paste)
}

///|
/// Mod+C / Mod+X — 選んでいるものを写す・切り取る。選んでいなければ他の行へ譲る。
fn copied(h : Hand) -> Answer {
  guard h.sel.ids.length() > 0 else { return Pass }
  match copy_of(h.k, () => remove(h.sel)) {
    Some(c) => Do(c)
    None => Pass
  }
}

///|
/// Shift+L / C / D — 中身を 1 枚足す。宛先が 1 つに決まるときだけ。
fn attached(h : Hand) -> Answer {
  guard h.k.shift && !h.k.mod else { return Pass }
  guard h.k.key == "L" || h.k.key == "C" || h.k.key == "D" else { return Pass }
  guard solo(h.sel) is Some(id) else { return Stop }
  Do(
    match h.k.key {
      "L" => AddLink(id~)
      "C" => AddCode(id~)
      _ => Draw(id~)
    },
  )
}

///|
/// Enter — 足す、または埋める。文書が空なら最初の根、Mod なら名前を直す、
/// Shift なら手前に、名前がまだ無いなら埋める、でなければ後ろに。
fn entered(h : Hand) -> Answer {
  guard h.k.key == "Enter" else { return Pass }
  guard h.l.order.length() > 0 else {
    return Do(add(In(node=@tree.doc_id, side=None)))
  }
  guard h.anchor is Some(anchor) else { return Stop }
  if h.k.mod {
    return Do(Edit(id=anchor, seed=None))
  }
  // **Shift は blank より先。** 名前がまだ無いノードでも Shift+Enter は手前に足す
  if h.k.shift {
    return Do(add(Before(node=anchor)))
  }
  if h.blank {
    return Do(Edit(id=anchor, seed=None))
  }
  Do(add(After(node=anchor)))
}

///|
/// Tab — 1 つなら子を足す・包む、複数なら段下げ・段上げ
/// （先頭の前の兄弟の子へ / 先頭の親の後ろへ）。
fn tabbed(h : Hand) -> Answer {
  guard h.k.key == "Tab" && !h.k.mod else { return Pass }
  if solo(h.sel) is Some(id) {
    return Do(
      if h.k.shift {
        op(Wrap(id~, label=""))
      } else {
        add(In(node=id, side=None))
      },
    )
  }
  guard h.sel.ids.length() >= 2 else { return Stop }
  let ids = h.sel.ids
  let first = ids[0]
  if h.k.shift {
    return claimed(
      parent_of(h.l, first).map(p => {
        Op(op=MoveNode(ids~, at=After(node=p)), edit=false)
      }),
    )
  }
  claimed(
    prev_sibling(h.l, first).map(prev => {
      Op(op=MoveNode(ids~, at=In(node=prev, side=None)), edit=false)
    }),
  )
}

///|
/// Delete / Backspace — 選んでいるものを消す。
fn deleted(h : Hand) -> Answer {
  guard (h.k.key == "Delete" || h.k.key == "Backspace") && !h.k.mod else {
    return Pass
  }
  claimed(remove(h.sel))
}

///|
/// Shift+F — 畳み（F = fold）。畳む（閉）→ 開く（`<details open>`）→ 外す、を
/// 1 つのキーで 1 歩ずつ巡る。
fn folded(h : Hand) -> Answer {
  guard h.k.key == "F" && h.k.shift && !h.k.mod else { return Pass }
  guard h.anchor is Some(anchor) else { return Stop }
  guard node_of(h.l, Some(anchor)) is Some(node) else { return Stop }
  Do(fold_step(node, anchor))
}

///|
/// 畳みの次の 1 歩。畳んでいなければ畳む（閉）、閉じていれば開く（子は出るが
/// 畳みのまま）、開いていれば外す。右クリックの行も同じ 1 歩を名乗る
fn fold_step(node : @tree.Node, id : Int) -> Intent {
  match node.fold {
    None => Op(op=Fold(id~, open=false), edit=false)
    Some({ open: false, .. }) => Op(op=Fold(id~, open=true), edit=false)
    Some(_) => Op(op=Unfold(id~), edit=false)
  }
}

///|
/// 畳みの行の字。次の 1 歩を名乗る
fn fold_label(node : @tree.Node?) -> String {
  match node {
    Some({ fold: Some({ open: false, .. }), .. }) => "Open (folded)"
    Some({ fold: Some(_), .. }) => "Unfold"
    _ => "Fold"
  }
}

///|
/// Escape — **1 段ずつ外へ。** 選んでいれば解き、解くものが無ければ帯へ抜ける。
/// Tab は子を足すのに使うので、キーボードだけで帯へ戻る道はこれしかない。
fn escaped(h : Hand) -> Answer {
  guard h.k.key == "Escape" else { return Pass }
  Do(
    if h.sel.ids.length() > 0 {
      Select(sel=none, reveal=false)
    } else {
      Leave
    },
  )
}

///|
/// Home — 選択（無ければ根）を画面の中心へ。
fn centered(h : Hand) -> Answer {
  guard h.k.key == "Home" && !h.k.mod else { return Pass }
  Do(Center)
}

///|
/// Mod+A — ぜんぶ選ぶ。
fn chose_all(h : Hand) -> Answer {
  guard h.k.mod && h.k.key.to_lower() == "a" else { return Pass }
  Do(Select(sel=all(h.l), reveal=false))
}

///|
/// 矢印 — 選択を動かす。Shift なら伸ばす。
fn arrowed(h : Hand) -> Answer {
  guard arrow_of(h.k.key) is Some(a) && !h.k.mod else { return Pass }
  guard step(h.sel, h.l, a, h.k.shift) is Some(sel) else { return Stop }
  Do(Select(sel~, reveal=true))
}

///|
/// 名前がまだ無いノードで字を打つ — そのまま書き始める。字は `e.key` のまま
/// （CapsLock の正規化を通さない）。Space はパンに使うので除く。
fn typed(h : Hand) -> Answer {
  guard h.blank && h.anchor is Some(anchor) else { return Pass }
  guard !h.k.mod && h.k.key.char_length() == 1 && h.k.key != " " else {
    return Pass
  }
  Do(Edit(id=anchor, seed=Some(h.k.key)))
}

///|
/// カードを選んでいるときのキー 1 回ぶん。`keyed` と同じ表の読み方
pub fn keyed_card(l : Layout, picked : Int, k : Key) -> Intent? {
  // 外すのに持ち主は要らない（畳まれて箱が無くても、ここから抜けられる）
  guard k.key != "Escape" else { return Some(Pick(id=None)) }
  guard owner_of(l, picked) is Some((owner, index)) else { return None }
  table({ k, picked, owner: owner.node.id, cards: owner.cards, index, }, [
    card_reordered, card_copied, card_deleted, card_stepped, card_left, card_edited,
  ])
}

///|
/// カードを選んでいるときの手元。隣は**描かれているカード**の隣 —
/// カードにならなかった中身は飛ばす
priv struct Deck {
  k : Key
  /// 選んでいる中身の id
  picked : Int
  /// 持ち主のノード
  owner : Int
  /// 持ち主のカードの列と、その中の枚目
  cards : Array[Card]
  index : Int
}

///|
/// 選んでいるカードを消す。消した後に持ち主を選ぶのは core の focus
fn Deck::remove(self : Deck) -> Intent {
  Op(op=Delete(ids=[self.picked]), edit=false)
}

///|
/// Alt+↑↓ — 前後のカードの前後へ並べ替え。Alt はここで閉じる（`reordered` と同じ）
fn card_reordered(d : Deck) -> Answer {
  guard d.k.alt else { return Pass }
  guard d.k.key == "ArrowUp" || d.k.key == "ArrowDown" else { return Stop }
  guard !d.k.mod else { return Stop }
  let moved = (at : @op.BlockPlace) => {
    Op(op=MoveBlock(ids=[d.picked], at~), edit=false)
  }
  if d.k.key == "ArrowUp" {
    return claimed(d.cards.get(d.index - 1).map(p => moved(Before(block=p.id))))
  }
  claimed(d.cards.get(d.index + 1).map(n => moved(After(block=n.id))))
}

///|
/// Mod+C / Mod+X — そのカードを写す・切り取る
fn card_copied(d : Deck) -> Answer {
  match copy_of(d.k, () => Some(d.remove())) {
    Some(c) => Do(c)
    None => Pass
  }
}

///|
/// Delete / Backspace — そのカードを消す
fn card_deleted(d : Deck) -> Answer {
  guard (d.k.key == "Delete" || d.k.key == "Backspace") && !d.k.mod else {
    return Pass
  }
  Do(d.remove())
}

///|
/// ↑↓ — 隣のカードを選ぶ。端では拾うが動かない（#244）
fn card_stepped(d : Deck) -> Answer {
  guard (d.k.key == "ArrowDown" || d.k.key == "ArrowUp") && !d.k.mod else {
    return Pass
  }
  let i = if d.k.key == "ArrowDown" { d.index + 1 } else { d.index - 1 }
  claimed(d.cards.get(i).map(c => Pick(id=Some(c.id))))
}

///|
/// ← — 持ち主のノードへ戻る
fn card_left(d : Deck) -> Answer {
  guard d.k.key == "ArrowLeft" && !d.k.mod else { return Pass }
  Do(Select(sel=Selection::only(d.owner), reveal=false))
}

///|
/// Mod+Enter — その場で直す
fn card_edited(d : Deck) -> Answer {
  guard d.k.mod && d.k.key == "Enter" else { return Pass }
  Do(EditCard(id=d.picked))
}
