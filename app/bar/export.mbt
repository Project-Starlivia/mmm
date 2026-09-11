// マップを外へ出す。ファイルにも、クリップボードにも。
//
// 1 枚の <svg> にするのは render の仕事（`Mindmap::to_svg`）で、ここが持つのは
// **その先の出し口**だけ — 直列化・ラスタ化・ダウンロード・クリップボード。
//
// **出し方 4 通りの定義はここ 1 か所**。対象は常に全体 — 新規 / 開く / 保存 が
// 文書ぜんぶを相手にするのと同じ高さにヘッダを置く（枝だけの書き出しは、
// 選択が戻ったときに右クリックへ）。

///|
/// ラスタの倍率。**選ばせない** — 書き出したものは画面で見えている通りで
/// あるべきで、選ばせるほど何が出るか分からなくなる。貼り先で粗く見えない
/// 下限として 2 倍だけ取る
let scale = 2.0

///|
/// 出すものが無い理由。ボタンの `title` にも行の hover にも同じ言葉を出す
let nothing = "Nothing to export yet"

///|
/// `▾` の名乗り。絵しか持たないので、名前は綴りで持つ
let choose = "Choose how to export"

///|
/// 出せたことをボタンが言っている長さ。読めるだけ在って、次に押すときには
/// もう「いまの出し方」に戻っている、の間
let hold = 1500

///|
pub(all) struct ExportDeps {
  /// 全体の SVG。空なら None。出し口はこの要素の文書を通る
  svg : async () -> @dom.Element?
  /// ダウンロード名の元になる、いまのファイル名
  name : () -> String
  /// 果たせなかった
  failed : (String) -> Unit
  /// 出すものが無い。キーから来たときだけここへ落ちる
  blocked : (String) -> Unit
  /// マップに 1 つも枝が無いか。**押す前に分かるので、押す前に言う**
  empty : () -> Bool
}

///|
/// 出し方 1 つ。`short` はボタンの表示で、`label`（並びの表示）から動詞を落としたもの。
/// **行き先は `mark` の絵が言う** — 落とすのか、貼れるようにするのか。形式ではなく行き先に印が付く
pub(all) struct Way {
  id : String
  short : String
  mark : String
  label : String
  out : async (@dom.Document, @dom.Element, String) -> Unit
}

///|
/// canvas が受け取れる面積の上限（px）。形式によらず同じ
let max_area = 268435456.0

///|
/// canvas が受け取れる 1 辺の上限（px）。**WebP だけ狭い** — しかも超えた分を
/// 黙って切り落とす（null も例外も返さない）ので、渡す前に収めないと地図の
/// 右端・下端が欠けた絵が出る。PNG は超えると toBlob が null を返す。
/// どちらも Chromium で実測（2026-09-07）
fn max_side(mime : String) -> Double {
  if mime == "image/webp" {
    16383.0
  } else {
    65535.0
  }
}

///|
/// 上限に収まる倍率。**欠かすくらいなら小さくする** — 画面のとおりに出すのが
/// 本義だが、一部が欠けた絵や「出せない」より、粗くても全体が写るほうが良い。
/// 上限に当たらない大きさでは `want` のまま
fn fit(w : Double, h : Double, want : Double, mime : String) -> Double {
  let side = max_side(mime)
  let by_side = @cmp.minimum(side / w, side / h)
  let by_area = (max_area / (w * h)).sqrt()
  @cmp.minimum(want, @cmp.minimum(by_side, by_area))
}

///|
/// 倍率を当てた px。**切り上げない** — 上限ちょうどの倍率で 1 px はみ出す。
/// 0 px の canvas は絵にならないので下限は 1
fn pixels(v : Double, scale : Double) -> Int {
  @cmp.maximum(1, (v * scale).to_int())
}

///|
/// SVG を絵にする。大きさが読めなければ投げる
async fn raster(
  doc : @dom.Document,
  svg : @dom.Element,
  mime : String,
) -> @core.Any {
  let size = (n : String) => {
    @string.parse_double(svg.getAttribute(n).unwrap_or("")) catch {
      _ => 0.0
    }
  }
  let w = size("width")
  let h = size("height")
  guard w > 0.0 && h > 0.0 else { fail("書き出す大きさが読めない") }
  let s = fit(w, h, scale, mime)
  @web.rasterize(doc, @web.serialize(svg), mime, pixels(w, s), pixels(h, s)).wait()
}

///|
/// 出し方 4 通り。**行き先で選べる形式が違う**。
///
/// `WebP` はクリップボードに置けない — Chromium の `ClipboardItem` が受け取る
/// のは `image/png` と `image/svg+xml` だけ（`ClipboardItem.supports` に聞いた）。
/// なのでコピー側の絵は PNG。
///
/// SVG のコピーは `text/plain` にも同じものを載せる — Figma や Illustrator は
/// 画像として受け取るより、SVG のソースを貼られたほうが確実に開く
let ways : Array[Way] = [
  {
    id: "svg-file",
    short: "SVG",
    mark: "download",
    label: "Download SVG",
    out: fn(doc, svg, base) {
      @web.download(
        doc,
        @web.text_blob(@web.serialize(svg), "image/svg+xml"),
        base + ".svg",
      )
    },
  },
  {
    id: "webp-file",
    short: "WebP",
    mark: "download",
    label: "Download WebP",
    out: async fn(doc, svg, base) {
      @web.download(doc, raster(doc, svg, "image/webp"), base + ".webp")
    },
  },
  {
    id: "png-copy",
    short: "PNG",
    mark: "copy",
    label: "Copy PNG",
    out: async fn(doc, svg, _) {
      @web.clipboard_write(doc, ["image/png"], [raster(doc, svg, "image/png")]).wait()
    },
  },
  {
    id: "svg-copy",
    short: "SVG",
    mark: "copy",
    label: "Copy SVG",
    out: async fn(doc, svg, _) {
      let text = @web.serialize(svg)
      @web.clipboard_write(doc, ["image/svg+xml", "text/plain"], [
        @web.text_blob(text, "image/svg+xml"),
        @web.text_blob(text, "text/plain"),
      ]).wait()
    },
  },
]

///|
/// 覚えていた出し方。知らない値なら既定へ落とす
fn way_of(saved : String?) -> Way {
  match saved {
    Some(id) =>
      match ways.search_by(w => w.id == id) {
        Some(i) => ways[i]
        None => ways[0]
      }
    None => ways[0]
  }
}

///|
/// そのやり方で 1 回出す。**出せたかを返す** — 済んだらヘッダーのボタンが
/// チェックで答えるので、答えてよいかを呼ぶ側が知る必要がある。
/// しくじりはここがしらせに出し、投げない（呼ぶ側に try を書かせない）
async fn export_once(deps : ExportDeps, way : Way) -> Bool {
  (async fn() -> Bool {
    guard (deps.svg)() is Some(svg) else {
      // ボタンは沈めてあるので、ここへ来るのはキー（`Mod+E`）から。
      // **触って読める言葉と同じものを出す** — 同じ壁に 2 つの綴りを持たない
      (deps.blocked)(nothing)
      return false
    }
    (way.out)(svg.ownerDocument().unwrap(), svg, @read.bare((deps.name)()))
    true
  })() catch {
    _ => {
      (deps.failed)("Couldn't export")
      false
    }
  }
}

///|
/// 出し方の並び（`▾` に出す）。
///
/// `header` はヘッダから開いたときの走らせ方。**選ばれた出し方を渡すだけで、
/// その先はヘッダが持つ**（次の既定にし、済んだらボタンの絵で答える） —
/// 答える場所がボタンなので、答え方を知っているのもボタンを持つ側。
/// 無ければここが走らせるだけ
pub fn export_ways(
  deps : ExportDeps,
  header : ((Way) -> Unit)?,
) -> Array[@parts.Entry] {
  let entries = []
  for i, way in ways {
    // ダウンロードとコピーのあいだに線を引く（行き先が変わるところ）
    if i == 2 {
      entries.push(@parts.Sep)
    }
    let disabled = @parts.unless(!(deps.empty)(), why=nothing)
    entries.push(
      @parts.Run(@parts.row(way.label, mark=Some(way.mark), disabled~), () => {
        match header {
          Some(h) => h(way)
          None => @web.spawn(async fn() { export_once(deps, way) |> ignore })
        }
      }),
    )
  }
  entries
}

///|
/// ヘッダの書き出し。対象は常に全体。
///
/// ボタンには**いまの出し方**が出ていて、押せばそれで出る。`▾` で選び直すと
/// その場で出て、次からの既定になる — 押す前に何が起きるかが常に見えている
pub struct Export {
  doc : @dom.Document
  deps : ExportDeps
  button : @dom.Element
  way_button : @dom.Element
  mut way : Way
  /// 頷きを戻す時計。無ければ頷いていない
  mut back : @global.Timer?
}

///|
pub fn Export::new(
  doc : @dom.Document,
  deps : ExportDeps,
  button : @dom.Element,
  way_button : @dom.Element,
) -> Export {
  way_button.replaceChildren([@parts.icon(doc, "chevron-down").as_node()])
  let self : Export = {
    doc,
    deps,
    button,
    way_button,
    way: way_of(@prefs.load(doc, "way")),
    back: None,
  }
  self.refresh()
  // 出せたことをボタンの絵で言い、**戻すきっかけは 2 つ** — ボタンから離れたときと、
  // 離れないまま hold が経ったとき。離れたときだけにすると、`▾` の並びから選んだときや
  // キーで出したときはポインタが乗っておらず戻らない。時間だけにすると、次に押したい
  // ときまで「いまの出し方」が読めないままになる。早く来たほうを採る
  @web.listen(button, "pointerleave", _ => self.undo())
  @web.listen(button, "click", _ => self.fire(self.way))
  @parts.open_on_click(way_button, () => {
    export_ways(deps, Some(w => self.pick(w)))
  })
  self
}

///|
/// 形式が文字、行き先が絵。押す前に何が起きるかが見えている。
/// 出すものが無いなら押せない。**なぜ押せないかも同じ場所が言う** —
/// ボタンは 1 つしか言えないので、言えるほうを言う。
/// **`▾` も一緒に沈む。** 選び直すことは出すことなので（選べばその場で出る）、
/// 出せないなら選ぶ意味も無い
pub fn Export::refresh(self : Export) -> Unit {
  self.put(self.way.mark)
  let empty = (self.deps.empty)()
  @web.set_disabled(self.button, empty)
  self.button.setAttribute(
    "title",
    if empty {
      nothing
    } else {
      "Export the whole Mindmap — " + self.way.label
    },
  )
  @web.set_disabled(self.way_button, empty)
  let why = if empty { nothing } else { choose }
  self.way_button.setAttribute("title", why)
  self.way_button.setAttribute("aria-label", why)
}

///|
/// ボタンの中身を、いまの出し方の字とその絵に
fn Export::put(self : Export, mark : String) -> Unit {
  self.button.replaceChildren(
    @parts.label(self.doc, self.way.short, mark, true),
  )
}

///|
fn Export::undo(self : Export) -> Unit {
  guard self.back is Some(t) else { return }
  @global.clear_timeout(t)
  self.back = None
  self.refresh()
}

///|
/// ヘッダから 1 回出す。走っているあいだボタンが回り、出せたらうなずく
/// （`nod` が決める）。しくじったときは `refresh` で戻す — 回していた
/// かもしれないので、必ず通す
fn Export::fire(self : Export, chosen : Way) -> Unit {
  @parts.nod(
    k => @web.spawn(async fn() { k(export_once(self.deps, chosen)) }),
    mark => self.put(mark),
    ok => {
      if ok {
        match self.back {
          Some(t) => @global.clear_timeout(t)
          None => ()
        }
        self.back = Some(@global.set_timeout(() => self.undo(), hold))
      } else {
        self.refresh()
      }
    },
  )
}

///|
/// 選び直して出す。次からの既定にもなる
fn Export::pick(self : Export, chosen : Way) -> Unit {
  self.way = chosen
  @prefs.store(self.doc, "way", chosen.id)
  self.refresh()
  self.fire(chosen)
}

///|
/// キー（Mod+E）。ボタンと同じものを走らせる
pub fn Export::run(self : Export) -> Unit {
  self.fire(self.way)
}

///|
/// キー（Mod+Shift+E）から出し方を選び直す。`▾` の click を通すので、
/// 沈んでいれば開かず、開いたメニューは先頭の行に焦点が乗る（detail 0）
pub fn Export::choose(self : Export) -> Unit {
  @web.click(self.way_button)
}
