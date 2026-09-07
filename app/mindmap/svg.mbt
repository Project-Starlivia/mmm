// マップを 1 枚の <svg> にする。画面の DOM から、一時的な UI 状態
// （選択・ドロップ印）を取り除き、計算済みスタイルを属性に焼き込むので、
// この結果だけで単体表示できる。
//
// **写すのは全体。** 枝だけを書き出したいときは、写すものを選ぶ口をここに
// 足す（どれが選ばれているかを知っているのは地図の側）。
//
// **地は持たない。** 貼り先の色にそのまま乗るよう透明のままにする —
// 板を敷かないので、角丸にする／しないの検討も要らない。

///|
/// 透かしの出所。配り先（wrangler.jsonc の `workers_dev` 名）を変えたらここも
let watermark_url = "https://mmm.chiwawaz.workers.dev/"

///|
/// 本文の下端から透かしの帯までの高さ。余白に足す
let wm_band = 22.0

///|
/// 本文のまわりの余白
let margin = 24.0

///|
/// いまの操作の状態。書き出しには載せない
let transient : ReadOnlyArray[String] = ["selected", "drop-parent", "dragging"]

///|
/// 属性に焼き込む計算済みスタイル
let props : ReadOnlyArray[String] = [
  "fill", "stroke", "stroke-width", "stroke-dasharray", "stroke-linecap", "font-family",
  "font-size", "font-weight", "opacity", "dominant-baseline", "text-anchor",
]

///|
/// 計算済みスタイルを写しの属性に焼き込む。`<title>` は字だけなので触らない
fn inline(orig : @dom.Element, copy : @dom.Element) -> Unit {
  if orig.tagName() != "title" {
    for p in props {
      let v = @web.computed(orig, p)
      if v != "" {
        copy.setAttribute(p, v)
      }
    }
    copy.removeAttribute("class")
  }
  let a = orig.children()
  let b = copy.children()
  for i in 0..<a.length() {
    inline(a[i], b[i])
  }
}

///|
/// 写し。計算済みスタイルは**元の要素から読む**
fn copy_of(orig : @dom.Element, into : @dom.Element) -> Unit {
  let copy = @dom.Element::cast_from_node(orig.cloneNode(true))
  inline(orig, copy)
  into.append(copy.as_node())
}

///|
/// 右下の帯に置く「made with mmm」。`right`/`band_top` は viewBox の右端・本文下端
fn watermark(
  doc : @dom.Document,
  right : Double,
  band_top : Double,
  pane : @dom.Element,
) -> @dom.Element {
  let text = @web.el(doc, "text", [
    ("x", @web.num(right - 8.0)),
    ("y", @web.num(band_top + wm_band / 2.0)),
    ("text-anchor", "end"),
    ("dominant-baseline", "central"),
    ("font-family", @web.computed(pane, "--font")),
    ("font-size", "11"),
    ("fill", @web.computed(pane, "--ink-dim")),
  ])
  text.setTextContent("made with mmm")
  let link = @web.el(doc, "a", [("href", watermark_url)])
  link.append(text.as_node())
  link
}

///|
/// 書き出し用の SVG。全体。空なら None。
/// `blob:` のサムネイルはページの外では解けないので data URL に埋め直す
/// （各画像は互いに独立なので、全部始めてから待つ）。読めない絵は場所ごと空ける
pub async fn Mindmap::to_svg(self : Mindmap) -> @dom.Element? {
  let (boxes, edge_els, node_els) = self.svg_parts()
  guard boxes.length() > 0 else { return None }
  let doc = self.pane.ownerDocument().unwrap()
  let mut x0 = @double.infinity
  let mut y0 = @double.infinity
  let mut x1 = @double.neg_infinity
  let mut y1 = @double.neg_infinity
  for b in boxes {
    x0 = @cmp.minimum(x0, b.x)
    y0 = @cmp.minimum(y0, b.y)
    x1 = @cmp.maximum(x1, b.x + b.w)
    y1 = @cmp.maximum(y1, b.y + b.h)
  }
  let w = (x1 - x0 + margin * 2.0).ceil()
  let h = (y1 - y0 + margin * 2.0 + wm_band).ceil()
  // いまの操作の状態は書き出さない。計算済みスタイルは元の要素から読むので、
  // 写す前に画面側から外し、写し終えたら戻す
  let stripped : Array[(@dom.Element, String)] = []
  let selector = "." + transient.join(",.")
  for root in edge_els + node_els {
    for e in [root] + root.querySelectorAll(selector) {
      if transient.any(c => @web.has_class(e, c)) {
        stripped.push((e, e.getAttribute("class").unwrap_or("")))
        for c in transient {
          @web.toggle_class(e, c, false)
        }
      }
    }
  }
  let edges = @web.el(doc, "g", [])
  let nodes = @web.el(doc, "g", [])
  for e in edge_els {
    copy_of(e, edges)
  }
  for e in node_els {
    copy_of(e, nodes)
  }
  for s in stripped {
    s.0.setAttribute("class", s.1)
  }
  let pending = []
  for img in nodes.querySelectorAll("image") {
    let href = img.getAttribute("href").unwrap_or("")
    if href.has_prefix("blob:") {
      pending.push((img, @web.data_url(href)))
    }
  }
  for p in pending {
    p.0.setAttribute("href", p.1.wait()) catch {
      _ => p.0.remove()
    }
  }
  let out = @web.el(doc, "svg", [
    ("xmlns", @web.svg_ns),
    ("viewBox", [x0 - margin, y0 - margin, w, h].map(@web.num).join(" ")),
    ("width", @web.num(w)),
    ("height", @web.num(h)),
  ])
  out.append(edges.as_node())
  out.append(nodes.as_node())
  out.append(
    watermark(doc, x1 + margin, y1 + margin, self.pane.as_element()).as_node(),
  )
  Some(out)
}
