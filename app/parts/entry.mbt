// メニューの行。**何を並べるかは持たない** — 並びは呼ぶ側（bar/ の表、mindmap/act）が
// 決めて渡し、ここは行の形と、それを器（menu.mbt の `Menu`）に敷く `fill` だけを持つ。
// 並べて見るだけなら `rows` — 位置も開閉も無い、行だけの器。

///|
/// 押せない理由。**言葉を持てば、それが押せない理由として hover に出る。**
/// 真偽と 1 つに畳んであるので、「無効なのに理由が無い」と「理由があるのに押せる」が
/// 食い違いようがない。理由を書くのは、見ただけでは分からないときだけ —
/// 「選んでいない」「複数選んでいる」は行の並びと選択そのものが既に言っている
pub(all) enum Disabled {
  No
  Yes
  Why(String)
} derive(Eq, Debug)

///|
/// 沈む理由。押せるなら `No`、理由があれば `Why`、理由の無い沈みは `Yes`
pub fn unless(ok : Bool, why? : String) -> Disabled {
  if ok {
    No
  } else {
    match why {
      Some(w) => Why(w)
      None => Yes
    }
  }
}

///|
/// 押す前の但し書き。**届くのに一手かかるもの**（リンクの長さは gzip してからでないと
/// 分からない）を、開くのを遅らせずに言うための続き — 届いた時点で行に印が付く。
/// 空を渡せば何も出ない
pub type Caveat = ((Array[String]) -> Unit) -> Unit

///|
/// 行に共通の見た目。押したときの振る舞いは `Entry` が持つ。
///
/// `caveat` は**押す前に知っておくとよいこと**。押せなくはしない（押せないなら
/// `disabled` の側）。**1 つにつき印 1 つ**を右端に並べ、中身は触れば**すぐ**読める
/// （`title` はブラウザ任せで一拍待たされるので、吹き出しは自前で出す）
pub(all) struct Row {
  label : String
  key : String?
  /// 行の頭の絵。無ければ字だけ
  mark : String?
  caveat : Caveat?
  disabled : Disabled
}

///|
/// 1 行。
///
/// `Run` は閉じて走る — 結果が画面のどこかに出るもの。
/// `Done` は**閉じずに走り、済んだらその行の絵がチェックになる** —
/// 手元から何も見えないもの（コピー）を、押した場所で答えるため。
/// **できたかを続きで返す** — しくじりに頷いてしまわないように。
/// `Flip` は**閉じずに走り、並びを綴り直す** — 行そのものが次の状態を名乗るもの
/// （`Dark theme` を押すと行が `Light theme` になる）。閉じないのは、変わったのが
/// 画面の見え方そのもので、押した場所から確かめられるため。**綴り直すのは並び全部** —
/// 行が自分だけを書き換えると、同じ状態を 2 か所（並びを組む表と行）が持つことになる。
/// `Sub` は入れ子。**入れ子の行も走れる** — 触れば開き、押せばその場で走る
/// （`Add ▸` を押すと子ノードが増え、開けば下や上や親も選べる）。走るものの無い
/// 入れ子は開くだけ。
/// `Caption` は**続く行たちが何に効くか**を言う、押せない見出し。`mark` は
/// **主語を絵で言う**（値の無い状態 `not saved yet` では、何の話か絵が言う）
pub(all) enum Entry {
  Run(Row, () -> Unit)
  Done(Row, ((Bool) -> Unit) -> Unit)
  Flip(Row, () -> Unit)
  Sub(Row, Array[Entry], (() -> Unit)?)
  Caption(String, String?)
  Sep
}

///|
/// 押せる行（Caption / Sep でない）
pub fn row(
  label : String,
  key? : String? = None,
  mark? : String? = None,
  caveat? : Caveat? = None,
  disabled? : Disabled = No,
) -> Row {
  { label, key, mark, caveat, disabled, }
}

///|
fn Entry::row_of(self : Entry) -> Row? {
  match self {
    Run(r, _) | Done(r, _) | Flip(r, _) | Sub(r, _, _) => Some(r)
    _ => None
  }
}

///|
/// 行が器へ返すもの。位置・開閉・焦点は器（`Menu`）の持ち物で、行は
/// 「入れ子を開いて」「選んだから閉じて」と言うだけ
pub(all) struct Ways {
  /// 入れ子をその行の隣に開く
  open_sub : (@dom.Element, Array[Entry]) -> Unit
  /// 開いている入れ子を閉じる（別の行へ移った）
  close_sub : () -> Unit
  /// 選んだので器ごと閉じる
  close : () -> Unit
  /// 状態が変わったので、いまの状態から並びを引き直す（閉じない）
  respell : () -> Unit
}

///|
/// 但し書きの印と吹き出し。**印は 1 つ。** その行についての但し書きが何本あっても、
/// 「この一手には気に留めることがある」という同じ 1 つの話なので、印を数だけ
/// 並べると別々の物に見える。数は吹き出しの中で言う
fn caveat_box(doc : @dom.Document, texts : Array[String]) -> @dom.Element {
  let mark = icon(doc, "triangle-alert")
  @web.toggle_class(mark, "note", true)
  // 印そのものが読み上げの対象になる。行の名前に但し書きを足すので
  // はなく、印に名前を持たせる（label は label のまま）
  mark.removeAttribute("aria-hidden")
  mark.setAttribute("role", "img")
  mark.setAttribute("aria-label", texts.join(". "))
  // 吹き出しは自前。`title` はブラウザ任せで一拍待たされる
  let tip = @web.html(doc, "div", "tip")
  for text in texts {
    tip.append(@web.html_text(doc, "div", "", text).as_node())
  }
  // `<span>` にしない — 行は「`.key` でも絵でもない `<span>` は
  // 字だ」と見て `flex: 1` を当てるので、印の器が横幅を全部
  // 持っていってしまう
  let box = @web.html(doc, "div", "note-box")
  box.append(mark.as_node())
  box.append(tip.as_node())
  box
}

///|
/// `.menu` の器に行を並べる。**中身だけ** — どこに出すか・いつ閉じるかは
/// 持たない。返るのは、入れ子を持つ行の「開く」動作（ArrowRight とホバーの
/// 両方がこれを引く。2 つの入口が同じ判断をばらばらに持たない）
fn fill(
  el : @dom.Element,
  items : Array[Entry],
  ways : Ways,
) -> Array[(@dom.Element, () -> Unit)] {
  guard el.ownerDocument() is Some(doc) else { return [] }
  el.replaceChildren([])
  let openers : Array[(@dom.Element, () -> Unit)] = []
  // 空欄で頭出しを揃えるのは、**このメニューの中に絵を持つ行が 1 つでも
  // あるとき**だけ。1 つも無いなら（Add の子など）揃える相手が無いので、
  // 全部の行を左端まで詰める — 空欄ぶんの余白だけが浮いて見えていた
  let any_mark = items.any(it => it.row_of() is Some({ mark: Some(_), .. }))
  for it in items {
    match it {
      Sep => {
        el.append(doc.createElement("hr").as_node())
        continue
      }
      Caption(text, mark) => {
        let cap = @web.html(doc, "div", "caption")
        match mark {
          Some(m) => cap.append(icon(doc, m).as_node())
          None => ()
        }
        // 字は span に入れる — 長い名前を省略するのは字だけで、絵は縮めない
        cap.append(@web.html_text(doc, "span", "", text).as_node())
        el.append(cap.as_node())
        continue
      }
      _ => ()
    }
    guard it.row_of() is Some(r) else { continue }
    let row = @web.html(doc, "div", "item")
    row.setAttribute("role", "menuitem")
    // 矢印キーで辿れる。触っても効かない行だけが機能しないので、
    // トップレベルには常に参加させる（見えるが効かない、が Tab と同じ形）
    row.setAttribute("tabindex", "-1")
    // 理由を持つなら、触れば読める。アクセシブルネームも同じ理由を言う —
    // hover できない読み上げでも「なぜ」がその場で分かる
    let off = !(r.disabled is No)
    if off {
      row.setAttribute("aria-disabled", "true")
    }
    match r.disabled {
      Why(why) => {
        row.setAttribute("title", why)
        row.setAttribute("aria-label", "\{r.label}, \{why}")
      }
      _ => ()
    }
    // 絵の有る行と無い行で字の頭出しがずれないよう、無い行にも同じ幅の
    // 空欄を置く（絵は行ごとの都合、字の頭は並びの都合 — 別の話）。
    // 空欄は中身が無いだけの `.icon`
    match r.mark {
      Some(m) => row.append(icon(doc, m).as_node())
      None =>
        if any_mark {
          row.append(@web.html(doc, "span", "icon").as_node())
        }
    }
    row.append(@web.html_text(doc, "span", "", r.label).as_node())
    let nested = it is Sub(_, _, _)
    if nested {
      row.setAttribute("aria-haspopup", "menu")
      row.setAttribute("aria-expanded", "false")
    }
    // 但し書きは**印だけ**を右端に出し、中身は触れば読める。
    // **待たずに開いて、届いたら付ける** — 閉じた後に届いても、器ごと
    // 捨てられているだけなので何も起きない
    match r.caveat {
      Some(caveat) =>
        caveat(texts => {
          if texts.length() > 0 {
            row.append(caveat_box(doc, texts).as_node())
          }
        })
      None => ()
    }
    // 押して走る行のキーと、開ける印は同居しうる（`Tab ▸`）
    let hint = [r.key.unwrap_or(""), if nested { "▸" } else { "" }]
      .filter(s => s != "")
      .join(" ")
    if hint != "" {
      row.append(@web.html_text(doc, "span", "key", hint).as_node())
    }
    // 「開く」判断は 1 か所。ホバーと ArrowRight の両方がこれを呼ぶ
    match it {
      Sub(_, items, _) if !off =>
        openers.push((row, () => (ways.open_sub)(row, items)))
      _ => ()
    }
    // どの行へ移っても、開いていた子は閉じる。入れ子の行なら開き直す
    @web.listen(row, "pointerenter", _ => {
      (ways.close_sub)()
      for o in openers {
        if @web.same(o.0, row) {
          (o.1)()
        }
      }
    })
    @web.listen(row, "click", _ => {
      // **押せなさは、ここが持つ。** CSS の `pointer-events: none` だと
      // hover まで死んで、理由が読めない
      if off {
        return
      }
      match it {
        // 走るものが無い入れ子は「開く」だけ。触るとすぐ閉じては選べない
        Sub(_, items, None) => (ways.open_sub)(row, items)
        // **`Done` の行は閉じない。** 済んだことはその場で絵が言うので、
        // 閉じて別の場所に出すより近いし、続けてもう 1 つ選べる
        Done(_, work) =>
          nod(
            work,
            mark => {
              // 行の頭の絵だけを差し替える（`:scope >` が無いと、但し書きの
              // 印まで拾いうる）。差し替えるたび引き直すので、そのつど探す
              match row.querySelector(":scope > .icon") {
                Some(old) => old.replaceWith([icon(doc, mark).as_node()])
                None => ()
              }
            },
            _ => (),
          )
        // **`Flip` の行も閉じない。** 走らせてから並びを引き直すので、
        // 押した行がその場で次の状態を名乗る
        Flip(_, run) => {
          run()
          (ways.respell)()
        }
        Sub(_, _, Some(run)) | Run(_, run) => {
          (ways.close)()
          run()
        }
        _ => ()
      }
    })
    el.append(row.as_node())
  }
  openers
}

///|
/// 行だけのメニュー。位置も開閉も持たない — 並べて見るためのもの。
/// 器へ返すものは無いので、`Ways` は全部が空
pub fn rows(doc : @dom.Document, items : Array[Entry]) -> @dom.Element {
  let el = @web.html(doc, "div", "menu")
  el.setAttribute("role", "menu")
  fill(el, items, {
    open_sub: (_, _) => (),
    close_sub: () => (),
    close: () => (),
    respell: () => (),
  })
  |> ignore
  el
}
