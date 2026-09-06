// しらせ。**答えを待たない** — 出て、勝手に消える。
//
// **器は 1 つ。** 続けて呼べば中身が差し替わる — 積み上げると、何秒でどう
// 畳むか・古いものが新しいものを押し出す向きは、といった規則が要る。
// 出るのは操作の直後だけなので、いちばん新しい 1 つで足りる。
//
// **出るのは「起きなかったこと」だけ。** 済んだことは押した場所の絵が言う
// （icons.mbt の `nod`）。そのうえで、起きなかった理由には**向きが 2 つ**ある。
//
//   failed  … こちらが果たせなかった。ほとんどはこちら
//   blocked … 先へ進めない。**次の一手はそちらにある**
//
// **その向きを言うのは印の形で、色は増やさない。** 危険色を 1 つ足せば
// 「その色＝まずいこと」を覚えてもらう話になるし、形なら、テーマにも色覚にも
// 寄りかからない。読み上げにはどちらも `alert`（すぐ割り込む）で出す —
// 頼んだことが起きなかったのは同じで、待たせる理由が無い。

///|
/// 出したままにする時間（ms）
let linger = 4000

///|
/// 詫び。**綴りはここ 1 つで、`failed` の側が持つ** — 言葉ごとに書くと、
/// 足すたびに付け忘れるし、詫びるかどうかは文言ではなく**向き**の話。
///
/// 末尾が `.` ではなく `...` なのは、言い切って区切るのではなく、
/// そのまま続けて言うため。文言のほうが `—` を持っていることがあるので、`—` は使わない
let sorry = "Sorry..."

///|
/// 言葉の全部。**綴りはここ 1 つ** — 呼ぶ側はこの中の 1 つを渡す（外れていれば
/// 壊れている）ので、足すときはまずここに書く。並べて見る道具もこれを読む。
/// 名前を付けて引かないのは、呼び出し元で文言そのものが読める方が早いから。
pub let failed_words : Array[String] = [
  "Couldn't save", "Couldn't save the image", "Couldn't open the file", "Couldn't open the dropped file",
  "Couldn't open the image folder", "Couldn't create a new file", "Couldn't rename the file",
  "Couldn't export", "Couldn't copy", "Couldn't copy the link", "Couldn't paste",
  "Couldn't read that as a link", "Couldn't add the drawing", "Couldn't open that card",
  "Couldn't start editing — the node is folded", "Couldn't do that here", "Select a node to paste an image into",
  "Select a node to paste a link into", no_file_access,
]

///|
/// File System Access API が無いブラウザで、Files のできない行とショートカットの両方が言う理由。しらせにもなる
pub let no_file_access = "This browser cannot open or save files"

///|
/// 次の一手が相手にあるもの。いまは書き出すものが無いときの Mod+E だけ
pub let blocked_words : Array[String] = ["Nothing to export yet"]

///|
/// body に置いた 1 つの器と、消す時計
priv struct Shown {
  mut box : @dom.Element?
  mut timer : @global.Timer?
}

///|
let shown : Shown = { box: None, timer: None, }

///|
/// 字のひと続き。**`span` は「意味を持たない字の一区切り」そのもの**なので、
/// ここに `div` を置くと「段落だ」と嘘をつくことになる
fn words(doc : @dom.Document, name : String, text : String) -> @dom.Element {
  let el = doc.createElement("span")
  el.setAttribute("class", name)
  el.setTextContent(text)
  el
}

///|
/// しらせ 1 つぶん。器（`.notice`）ごと組んで返す — **置くのは呼ぶ側**。
/// アプリは下の `show` が body に 1 個だけ置き、並べて見る道具はどこにでも置く。
///
/// 中身は 3 つ。**入れ物は、意味を持つか CSS で言えない境目があるときだけ置く。**
///
///   .icon  印（飾り。意味は role と字が持つので `aria-hidden`）
///   .lead  詫び（`blocked` では出さない）
///   .msg   何が起きなかったか
pub fn notice(
  doc : @dom.Document,
  mark : String,
  msg : String,
  apologize : Bool,
) -> @dom.Element {
  let box = doc.createElement("div")
  box.setAttribute("class", "notice")
  // HTML に「しらせ」のタグは無い。`<output>` は `role="status"` に落ちる
  // ので、すぐ割り込む `alert` が要るこちらは div に role を載せる
  box.setAttribute("role", "alert")
  box.append(icon(doc, mark).as_node())
  if apologize {
    box.append(words(doc, "lead", sorry).as_node())
  }
  box.append(words(doc, "msg", msg).as_node())
  box
}

///|
/// body に 1 個。続けて呼べば中身が差し替わり、時計は打ち直す
fn show(mark : String, msg : String, apologize : Bool) -> Unit {
  let doc = @dom.document()
  let next = notice(doc, mark, msg, apologize)
  let box = match shown.box {
    Some(b) => {
      b.replaceChildren(next.childNodes())
      b
    }
    None => {
      match doc.body() {
        Some(body) => body.append(next.as_node())
        None => ()
      }
      shown.box = Some(next)
      next
    }
  }
  @web.toggle_class(box, "on", true)
  match shown.timer {
    Some(t) => @global.clear_timeout(t)
    None => ()
  }
  shown.timer = Some(
    @global.set_timeout(
      () => {
        shown.timer = None
        @web.toggle_class(box, "on", false)
      },
      linger,
    ),
  )
}

///|
/// こちらが果たせなかった。**鳴らすのではなく、認める。**
///
/// 印が三角でなく丸なのは、三角が道路標識と同じで「この先危ない・気をつけろ」と
/// **読む人へ向けて**言う形だから。ここで気をつけるべきだったのは相手ではない。
/// 字も人の言い方で言う（`Couldn't …`。`Could not` はログの口調）。頭には
/// **詫びが 1 文**付く — 起きなかったのはこちらの都合なので、そう言う。
/// 知らない言葉は綴りの食い違い — 壊れている
pub fn failed(msg : String) -> Unit {
  guard failed_words.contains(msg) else {
    abort("知らないしらせ: " + msg)
  }
  show("circle-alert", msg, true)
}

///|
/// 先へ進めない。**次の一手はそちらにある。**
///
/// こちらは三角でいい — 読む人へ向けて言う形が、ここでは実際に正しい
/// （動くのは相手）。触って読める言葉と同じものを出す
pub fn blocked(msg : String) -> Unit {
  guard blocked_words.contains(msg) else {
    abort("知らないしらせ: " + msg)
  }
  show("triangle-alert", msg, false)
}
