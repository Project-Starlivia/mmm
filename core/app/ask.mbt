// たずね。**答えを待つ** — 塞いで、返ってくるまで進まない。
//
// 器は `<dialog>` 1 つ。焦点を閉じ込める・Escape で閉じる・後ろを暗くする
// (`::backdrop`) はブラウザが持っているので、こちらは書かない。
//
// **中身は「字」と「欄」を並べただけ**（`Part`）。聞き方が増えても器は 1 つ
// で、増えるのは並べ方だけ — はい/いいえ は欄ゼロ、名前は欄 1 つ、
// 画像の行き先は `![](` 字 + 欄 + `.webp)` 字、というように。
// **分かっているところは字、分からないところだけ欄**を、この形が守る。
//
// ここに来ないもの: ファイルを開く・保存する・フォルダを選ぶ・権限を聞く。
// あれはこちらが持っていない持ち場なので、ブラウザのピッカーのまま。

///|
/// 打てる欄。並びの中で値を 1 つ受け持つ。`check` はその値では進めない理由
/// （進めるなら None）。**打つそばから効く** — だめな値のまま押させて後から
/// 失敗を言うのは、打った本人が既に知っていることを後出しするのと同じ
pub(all) struct Field {
  value : String
  check : ((String) -> String?)?
}

///|
/// 並べるもの。ただの字か、打てる欄か
pub(all) enum Part {
  Text(String)
  Blank(Field)
}

///|
pub(all) struct Ask {
  /// 何を聞いているか。1 行で言い切る
  title : String
  /// 補足。**要るときだけ** — 題で足りるなら書かない
  note : String?
  /// 進む側のボタンの名前（`OK` / `Discard` など）
  ok : String
  /// 断る側の名前。無ければ `Cancel`（`Keep as is` のように意味を持つことがある）
  cancel : String?
  /// 字と欄の並び。空なら はい/いいえ
  parts : Array[Part]
  /// 何の話をしているかを見せる絵（画像の名前を聞くときの、その画像）
  preview : String?
}

///|
pub fn ask_of(
  title : String,
  ok : String,
  note? : String? = None,
  cancel? : String? = None,
  parts? : Array[Part] = [],
  preview? : String? = None,
) -> Ask {
  { title, note, ok, cancel, parts, preview, }
}

///|
fn p(doc : @dom.Document, class : String, text : String) -> @dom.Element {
  let e = doc.createElement("p")
  e.setAttribute("class", class)
  e.setTextContent(text)
  e
}

///|
/// たずねの中身（form）を組む。**器に載せるのは呼ぶ側** — `ask` は `<dialog>` に
/// 載せて `showModal` し、並べて見る道具は開いたまま置く。
///
/// `cancel` は断る側のボタンが押されたときに呼ぶ（器を閉じる係は器が持つ）。
/// 進む側は `method="dialog"` の送信そのもので、押したボタンの value（`"ok"`）が
/// `returnValue` になる。返るのは form と、欄の値を並び順で読む口
pub fn ask_form(
  doc : @dom.Document,
  a : Ask,
  cancel : () -> Unit,
) -> (@dom.Element, () -> Array[String]) {
  let form = doc.createElement("form")
  form.setAttribute("method", "dialog") // 送ると dialog が閉じ、押したボタンの value が returnValue
  form.append(p(doc, "title", a.title).as_node())
  match a.note {
    Some(n) => form.append(p(doc, "note", n).as_node())
    None => ()
  }
  // 何の話かを見せる絵。字より先に置く — 名前を聞かれている相手が、読む前に分かる
  match a.preview {
    Some(src) => {
      let img = doc.createElement("img")
      img.setAttribute("class", "shot")
      img.setAttribute("src", src)
      img.setAttribute("alt", "")
      form.append(img.as_node())
    }
    None => ()
  }
  // 字と欄の並び。**欄は並びの中に居る** — 別行に切り出すと、その値が
  // 何の一部なのかが読めなくなる
  let inputs : Array[(@dom.Element, ((String) -> String?)?)] = []
  if a.parts.length() > 0 {
    let row = doc.createElement("div")
    row.setAttribute("class", "parts")
    for part in a.parts {
      match part {
        Blank(f) => {
          let input = doc.createElement("input")
          input.setAttribute("type", "text")
          @web.set_value(input, f.value)
          // 中身なりの幅。短い値の欄が横いっぱいに伸びると、並びが読めない
          input.setAttribute(
            "size",
            @cmp.maximum(f.value.length(), 6).to_string(),
          )
          row.append(input.as_node())
          inputs.push((input, f.check))
        }
        Text(t) => {
          let span = doc.createElement("span")
          span.setTextContent(t)
          row.append(span.as_node())
        }
      }
    }
    form.append(row.as_node())
  }
  // だめな理由の置き場。**並びのすぐ下** — 直したい字と、直せと言う言葉が
  // 離れていると目が往復する。要らないうちは場所も取らない。
  // `aria-live` は要る側だけに付ける — 何も言わない要素を読み上げの
  // 監視対象に加えても、黙って何も起きないだけ
  let checked = inputs.any(i => i.1 is Some(_))
  let bad = p(doc, "bad", "")
  bad.setAttribute("hidden", "")
  if checked {
    bad.setAttribute("aria-live", "polite")
    form.append(bad.as_node())
  }
  let row = doc.createElement("div")
  row.setAttribute("class", "row")
  let no = doc.createElement("button")
  no.setAttribute("type", "button") // 送らない。閉じるだけ（returnValue は空のまま）
  no.setTextContent(a.cancel.unwrap_or("Cancel"))
  @web.listen(no, "click", _ => cancel())
  let go = doc.createElement("button")
  go.setAttribute("class", "go")
  go.setAttribute("value", "ok")
  go.setTextContent(a.ok)
  row.append(no.as_node())
  row.append(go.as_node())
  form.append(row.as_node())
  // 打つそばから見直す。**進めない理由がある間は、進む道そのものを閉じる** —
  // ボタンが沈めば Enter でも送られない（送信は無効なボタンからは起きない）。
  // 欄が 2 つ以上あるときは、**先に見つかった 1 つだけ**を言う（並べると、
  // どれを直せば進めるのかが読めなくなる）
  if checked {
    let review = () => {
      let mut why : String? = None
      for i in inputs {
        why = i.1.bind(check => check(@web.value(i.0)))
        if why is Some(_) {
          break
        }
      }
      @web.set_disabled(go, why is Some(_))
      bad.setTextContent(why.unwrap_or(""))
      if why is Some(_) {
        bad.removeAttribute("hidden")
      } else {
        bad.setAttribute("hidden", "")
      }
    }
    for i in inputs {
      @web.listen(i.0, "input", _ => review())
    }
    review()
  }
  (form, () => inputs.map(i => @web.value(i.0)))
}

///|
/// 器を組んで開き、**欄の値を並び順で**続きに渡す。断られたら None。
/// 開くたびに作る — 聞くのは操作のたびに 1 回きりで、使い回す得が無い。
///
/// 続きに渡るのは `<dialog>` の `returnValue` 由来: 進んだときだけ `"ok"`。
/// Escape・背景・Cancel はすべて空文字（＝ 断り）に落ちる
pub fn ask(doc : @dom.Document, a : Ask, k : (Array[String]?) -> Unit) -> Unit {
  let dlg = doc.createElement("dialog")
  dlg.setAttribute("class", "ask")
  let (form, values) = ask_form(doc, a, () => @web.close_dialog(dlg))
  dlg.append(form.as_node())
  match doc.body() {
    Some(b) => b.append(dlg.as_node())
    None => ()
  }
  @web.listen(dlg, "close", _ => {
    let ok = @web.return_value(dlg) == "ok"
    let out = values()
    dlg.remove()
    k(if ok { Some(out) } else { None })
  })
  @web.show_modal(dlg)
  // 最初の欄を選んだ状態で開く（打ち直しがすぐ始められる）
  match form.querySelector("input") {
    Some(i) => @web.select_all(i)
    None => ()
  }
}
