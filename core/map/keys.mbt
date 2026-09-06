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
} derive(Eq, Debug, ToJson, FromJson)

///|
fn op(o : @op.Op) -> Intent {
  Op(op=o, edit=true)
}

///|
/// 空のラベルで足す。読めば label "" になり、そのまま打ち始める
fn add(at : @op.NodePlace) -> Intent {
  op(AddNode(at~, labels=[""]))
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
fn copied(k : Key, cut : () -> Intent?) -> Intent? {
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
fn node_of(l : Layout, id : Int?) -> @view.Node? {
  match id {
    Some(id) => l.boxes.get(id).map(b => b.node)
    None => None
  }
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
  // Alt が意味を持つのは Alt+↑↓（並べ替え）だけ。それ以外の Alt の組は拾わない。
  // ここで先に他のキーだけ弾く — Alt+↑↓ 自身の判断は後ろの専用の行に任せる
  // （Alt を真っ先に全部捨てると、並べ替えが書けなくなる）
  if k.alt && k.key != "ArrowUp" && k.key != "ArrowDown" {
    return None
  }
  // anchor が無くても拾う（貼る先が無ければ文書へ）。anchor 頼みの行より先に置く
  if k.mod && !k.alt && !k.shift && k.key.to_lower() == "v" {
    return Some(Paste)
  }
  if sel.ids.length() > 0 {
    match copied(k, () => remove(sel)) {
      Some(c) => return Some(c)
      None => ()
    }
  }
  let anchor = sel.anchor
  let label = match node_of(l, anchor) {
    Some(n) => n.label
    None => None
  }
  let blank = label == Some("")
  if k.shift &&
    !k.mod &&
    !k.alt &&
    (k.key == "L" || k.key == "C" || k.key == "D") {
    guard solo(sel) is Some(id) else { return None }
    return Some(
      match k.key {
        "L" => AddLink(id~)
        "C" => AddCode(id~)
        _ => Draw(id~)
      },
    )
  }
  if k.key == "Enter" {
    if l.order.length() == 0 {
      return Some(add(In(node=@tree.doc_id, side=None)))
    }
    guard anchor is Some(anchor) else { return None }
    if k.mod {
      return Some(Edit(id=anchor, seed=None))
    }
    if k.shift {
      return Some(add(Before(node=anchor)))
    }
    if blank {
      return Some(Edit(id=anchor, seed=None))
    }
    return Some(add(After(node=anchor)))
  }
  if k.key == "Tab" && !k.mod {
    match solo(sel) {
      Some(id) =>
        return Some(
          if k.shift {
            op(Wrap(id~, label=""))
          } else {
            add(In(node=id, side=None))
          },
        )
      None => ()
    }
    guard sel.ids.length() >= 2 else { return None }
    let first = sel.ids[0]
    if k.shift {
      guard parent_of(l, first) is Some(p) else { return None }
      return Some(Op(op=MoveNode(ids=sel.ids, at=After(node=p)), edit=false))
    }
    guard prev_sibling(l, first) is Some(prev) else { return None }
    return Some(
      Op(op=MoveNode(ids=sel.ids, at=In(node=prev, side=None)), edit=false),
    )
  }
  if (k.key == "Delete" || k.key == "Backspace") && !k.mod {
    return remove(sel)
  }
  if k.alt && (k.key == "ArrowUp" || k.key == "ArrowDown") && !k.mod {
    guard sel.ids.length() > 0 else { return None }
    let first = sel.ids[0]
    let last = sel.ids[sel.ids.length() - 1]
    let moved = (at : @op.NodePlace) => {
      Op(op=MoveNode(ids=sel.ids, at~), edit=false)
    }
    if k.key == "ArrowUp" {
      return prev_sibling(l, first).map(p => moved(Before(node=p)))
    }
    return next_sibling(l, last).map(n => moved(After(node=n)))
  }
  if k.alt {
    return None
  }
  if k.key == "H" && k.shift && !k.mod {
    guard anchor is Some(anchor) else { return None }
    guard node_of(l, Some(anchor)) is Some(node) else { return None }
    return Some(
      if node.fold is Some(_) {
        Op(op=Unfold(id=anchor), edit=false)
      } else {
        Op(op=Fold(id=anchor, open=false), edit=false)
      },
    )
  }
  if k.key == "Escape" {
    return Some(Select(sel=none, reveal=false))
  }
  if k.key == "Home" && !k.mod {
    return Some(Center)
  }
  if k.mod && k.key.to_lower() == "a" {
    return Some(Select(sel=all(l), reveal=false))
  }
  if arrow_of(k.key) is Some(a) && !k.mod {
    guard arrow(l, sel.anchor, a) is Some(next) else { return None }
    let sel = if k.shift {
      extend_to(sel, next)
    } else {
      { ids: [next], anchor: Some(next), }
    }
    return Some(Select(sel~, reveal=true))
  }
  // 名前が無いなら、打ち始めればそのまま書ける。字は e.key のまま（CapsLock の
  // 正規化を通さない）。Space はパンに使うので除く
  if blank &&
    anchor is Some(anchor) &&
    !k.mod &&
    k.key.char_length() == 1 &&
    k.key != " " {
    return Some(Edit(id=anchor, seed=Some(k.key)))
  }
  None
}

///|
/// カードを選んでいるときの表。持ち主は `node.blocks` に `picked` が居るノード、
/// 隣はその `blocks` を文書順（= 配列順）に見た前後。持ち主が見つからなければ
/// （箱が無い = 畳まれて埋もれた）None
pub fn keyed_card(l : Layout, picked : Int, k : Key) -> Intent? {
  // 外すのに持ち主は要らない（畳まれて箱が無くても、ここから抜けられる）
  if k.key == "Escape" {
    return Some(Pick(id=None))
  }
  guard owner_of(l, picked) is Some((owner, index)) else { return None }
  let blocks = owner.node.blocks
  // 消した後に持ち主を選ぶのは core の focus
  let remove : Intent = Op(op=Delete(ids=[picked]), edit=false)
  if (k.key == "Delete" || k.key == "Backspace") && !k.mod {
    return Some(remove)
  }
  match copied(k, () => Some(remove)) {
    Some(c) => return Some(c)
    None => ()
  }
  if (k.key == "ArrowDown" || k.key == "ArrowUp") && !k.mod && !k.alt {
    let i = if k.key == "ArrowDown" { index + 1 } else { index - 1 }
    return blocks.get(i).map(b => Pick(id=Some(b.id)))
  }
  if k.key == "ArrowLeft" && !k.mod {
    return Some(
      Select(
        sel={ ids: [owner.node.id], anchor: Some(owner.node.id), },
        reveal=false,
      ),
    )
  }
  if k.alt && (k.key == "ArrowUp" || k.key == "ArrowDown") && !k.mod {
    let moved = (at : @op.BlockPlace) => {
      Op(op=MoveBlock(ids=[picked], at~), edit=false)
    }
    if k.key == "ArrowUp" {
      return blocks.get(index - 1).map(p => moved(Before(block=p.id)))
    }
    return blocks.get(index + 1).map(n => moved(After(block=n.id)))
  }
  if k.mod && k.key == "Enter" {
    return Some(EditCard(id=picked))
  }
  None
}
