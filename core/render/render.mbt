// マップの DOM を差分で更新する層。**何を描くかは決めない** — レイアウトを
// 受け取って、SVG をそれに合わせるだけ。
//
// 毎レンダで全消しして作り直していた頃は、1 打鍵ごとに数万個の SVG 要素を
// 生成・破棄していて、それが入力遅延の実体だった。位置(transform)と class は
// 毎回書き換えても安いが、**要素の生成と破棄は高い**ので、そこだけを
// 「中身が変わったノード」に絞る。
//
// 差分の鍵は id。**id は文書順の位置**なので、上に 1 つ足せば以降が作り直される
// だけで、正しさは壊れない（docs/core.md「id は読みのサイクルを越えて持たない」）。

///|
/// 1 回の描き直しに要るもの。文書とレイアウトから決まるものと、外から受けるもの
pub(all) struct Scene {
  layout : @map.Layout
  /// 字の実測。畳んだノードの字を幅で詰めるのに要る
  measure : @map.Measure
  /// ローカル画像の objectURL（まだ読めていなければ None）
  image_url : (String) -> String?
  /// 読めていない場所取りに添える字。握っていないときだけ（他は None）
  image_hint : String?
  /// コードの色分け。(行, 言語) → 行ごとの塊。実体は ts の highlight（CodeMirror の言語表）
  tokens : (Array[String], String) -> Array[Array[Token]]
  /// 言語の読み込みの世代。読み終わると変わるので、色の付かないまま出した
  /// コードが描き直される
  epoch : Int
}

///|
/// ノードの中身を作り直すかどうかの判定材料。値をそのまま持って、そのまま比べる
pub struct Shape {
  w : Double
  h : Double
  folded : Bool
  buried : Int
  epoch : Int
  label : String
  cards : Array[@map.Card]
  /// cards と同じ並びで、画像だけ解決済みの URL（他は None）
  urls : Array[String?]
  /// 場所取りに添える字。**繋がった瞬間は URL がどれも None のままなので、
  /// これを姿に載せていないと描き直されない**
  hint : String?
} derive(Eq)

///|
pub struct Renderer {
  doc : @dom.Document
  edge_layer : @dom.Element
  node_layer : @dom.Element
  // 差分更新用: id → DOM
  node_els : Map[Int, @dom.Element]
  edge_els : Map[Int, @dom.Element]
  shapes : Map[Int, Shape]
  // 直前に書いた transform / d。同じ値の setAttribute はスタイル無効化を
  // 起こすだけ無駄なので書かない（プロファイル上いちばん重い JS 呼び出しだった）
  node_tf : Map[Int, String]
  edge_d : Map[Int, String]
  /// DOM の並び（= 重なり順）を直す判定用
  mut order_sig : String
  /// 直前に paint で塗った id。箱が無いものも残す（戻ったとき draw が塗る）
  mut selected : Set[Int]
}

///|
pub fn Renderer::new(doc : @dom.Document) -> Renderer {
  {
    doc,
    edge_layer: el(doc, "g", []),
    node_layer: el(doc, "g", []),
    node_els: Map([]),
    edge_els: Map([]),
    shapes: Map([]),
    node_tf: Map([]),
    edge_d: Map([]),
    order_sig: "",
    selected: Set([]),
  }
}

///|
/// id を指定して要素を引く（書き出しに写す・印を付けるため）
pub fn Renderer::node_el(self : Renderer, id : Int) -> @dom.Element? {
  self.node_els.get(id)
}

///|
pub fn Renderer::edge_el(self : Renderer, id : Int) -> @dom.Element? {
  self.edge_els.get(id)
}

///|
/// 選ばれた箱に印を付ける。レイアウトを見直さない軽い塗り替え。
/// 触るのは前回と変わった箱だけ — 矩形選択は pointermove ごとに来るので、
/// 全箱を toggle すると 5000 ノードで 1 回に 5000 回 DOM を触る
pub fn Renderer::paint(self : Renderer, sel : Array[Int]) -> Unit {
  let next = Set::from_array(sel)
  for id in self.selected {
    if !next.contains(id) {
      match self.node_els.get(id) {
        Some(g) => toggle_class(g, "selected", false)
        None => ()
      }
    }
  }
  for id in next {
    if !self.selected.contains(id) {
      match self.node_els.get(id) {
        Some(g) => toggle_class(g, "selected", true)
        None => ()
      }
    }
  }
  self.selected = next
}

///|
fn shape_of(b : @map.Box, scene : Scene) -> Shape {
  let n = b.node
  {
    w: b.w,
    h: b.h,
    folded: n.fold is Some(_),
    buried: b.buried,
    epoch: scene.epoch,
    // 畳んでいれば summary が字になる。summary だけ変わっても描き直すように
    label: if n.fold is Some(_) {
      @map.fold_name(n)
    } else {
      @map.label_of(n)
    },
    cards: b.cards,
    // 画像は「まだ読めていない」から「読めた」へ後から変わる
    urls: b.cards.map(c => {
      match c {
        Image(path~, ..) => (scene.image_url)(path)
        _ => None
      }
    }),
    hint: scene.image_hint,
  }
}

///|
/// 場面を DOM に写す。文書順（= 重なり順）も合わせる
pub fn Renderer::draw(self : Renderer, scene : Scene) -> Unit {
  let doc = self.doc
  let l = scene.layout
  // 位置(transform)と class は毎回書き換えても安い。高いのは要素の生成と
  // 破棄なので、そこは「中身が変わったノードだけ」に絞る
  let seen : Set[Int] = Set([])
  for id in l.order {
    guard l.boxes.get(id) is Some(b) else { continue }
    seen.add(id)
    let n = b.node

    // --- エッジ（親への曲線）---
    match @map.edge_ends(l, id) {
      Some((from, to)) => {
        let path = match self.edge_els.get(id) {
          Some(p) => p
          None => {
            let p = el(doc, "path", [("class", "edge")])
            self.edge_layer.append(p.as_node())
            self.edge_els[id] = p
            p
          }
        }
        let d = @map.edge_path(from, to)
        if self.edge_d.get(id) != Some(d) {
          path.setAttribute("d", d)
          self.edge_d[id] = d
        }
      }
      None =>
        match self.edge_els.get(id) {
          Some(stale) => {
            stale.remove()
            self.edge_els.remove(id)
            self.edge_d.remove(id)
          }
          None => ()
        }
    }

    // --- ノード本体 ---
    let g = match self.node_els.get(id) {
      Some(g) => g
      None => {
        let g = el(doc, "g", [("class", "node"), ("data-id", id.to_string())])
        self.node_layer.append(g.as_node())
        self.node_els[id] = g
        self.shapes.remove(id) // 新規なので必ず中身を作る
        // 選んだまま消えて戻った箱（畳みを開いた等）。印は paint の差分の外
        if self.selected.contains(id) {
          toggle_class(g, "selected", true)
        }
        g
      }
    }
    // **文書から決まるクラスだけ**を、1 つずつ付け外しする
    toggle_class(g, "root", b.parent is None)
    toggle_class(g, "folded", n.fold is Some(_))
    let tf = "translate(\{num(b.x)} \{num(b.y)})"
    if self.node_tf.get(id) != Some(tf) {
      g.setAttribute("transform", tf)
      self.node_tf[id] = tf
    }
    let shape = shape_of(b, scene)
    if self.shapes.get(id) == Some(shape) {
      continue // 中身は据え置き
    }
    self.shapes[id] = shape
    g.replaceChildren([])
    // 角丸は状態（畳んでいるか）で変わるだけの定数なので CSS が持つ。
    // ここが出すのはレイアウトが計算した数だけ
    g.append(
      el(doc, "rect", [
        ("class", "box"),
        ("width", num(b.w)),
        ("height", num(b.h)),
      ]).as_node(),
    )
    let folded = n.fold is Some(_)
    let text = if folded { @map.fold_name(n) } else { @map.label_of(n) }
    let row = @map.row_of(n)
    let label = el(doc, "text", [
      ("class", "label" + (if text == "" { " empty" } else { "" })),
      ("x", num(row.pad)),
      ("y", num(row.h / 2.0)),
      // font-size は CSS ではなく属性で入れる（同じ数字を 2 箇所に置かない）
      ("font-size", row.px.to_string()),
    ])
    label.setTextContent(
      if folded {
        @map.hidden_label(n, b.buried, scene.measure)
      } else {
        @map.display_label(text)
      },
    )
    let title = el(doc, "title", [])
    title.setTextContent(
      if folded {
        "\{text}\n(\{b.buried} folded)"
      } else {
        text
      },
    )
    g.append(label.as_node())
    g.append(title.as_node())
    // ラベルの下に、本文から起こしたカードを積む。**形は draw_card が持つ**
    // — ここが決めるのは「どこに置くか」だけ
    for i, c in b.cards {
      guard @map.card_rect(b, i) is Some(rect) else { continue }
      let at : Spot = {
        rect,
        row_y: @map.row_top(b.cards, i),
        box_w: b.w,
        spot: "\{id},\{i}",
      }
      for e in draw_card(doc, c, at, scene) {
        g.append(e.as_node())
      }
    }
  }

  // 見えなくなったノード / エッジを片付ける
  let gone = self.node_els.keys().filter(id => !seen.contains(id)).collect()
  for id in gone {
    match self.node_els.get(id) {
      Some(e) => e.remove()
      None => ()
    }
    self.node_els.remove(id)
    self.shapes.remove(id)
    self.node_tf.remove(id)
  }
  let gone_edges = self.edge_els
    .keys()
    .filter(id => !seen.contains(id))
    .collect()
  for id in gone_edges {
    match self.edge_els.get(id) {
      Some(e) => e.remove()
      None => ()
    }
    self.edge_els.remove(id)
    // 値キャッシュも一緒に捨てる。残すと、畳んで戻したときに
    // 「テキストが元通り = 署名も元通り」で書き換えがスキップされ、
    // 作り直した空の <path> に d が入らないままエッジが消える
    self.edge_d.remove(id)
  }

  // DOM の並び = 重なり順。文書順が変わったときだけ並べ直す
  // （既存要素の append は「移動」であって作り直しではない）
  let sig = l.order.map(id => id.to_string()).join(",")
  if sig != self.order_sig {
    for id in l.order {
      match self.node_els.get(id) {
        Some(e) => self.node_layer.append(e.as_node())
        None => ()
      }
    }
    self.order_sig = sig
  }
}
