// ノードの寸法。**ここが唯一の定義** — 字の大きさ・余白・行の高さ・隙間の数字は
// core のこのファイルにしか書かない。字の実測は canvas の仕事なので、
// `Measure` で外から受ける。
//
// ノードの「ラベル行」の寸法は、少なくとも 3 者が同じ値で見なければならない:
//   1. レイアウト（node_size が箱の大きさを決める）
//   2. SVG の描画（text 要素の font-size と x）
//   3. 編集用の <input> オーバーレイ（app/mindmap/field.mbt。寸法は place.mbt が数える）
// 1 つでも別の数字を持つと、編集に入った瞬間に文字がずれる。font-size は CSS ではなく
// 属性で入れて、CSS 側に同じ数字を持たせない。

///|
/// 字。大きさは core が決め、綴り（family）は ts が CSS の `--font` / `--mono` から読む
pub(all) struct Font {
  px : Int
  mono : Bool
} derive(Eq, Debug, ToJson)

///|
/// 幅を測る。実体は ts の canvas measureText（キャッシュ込み）
pub type Measure = (Font, String) -> Double

///|
pub(all) struct Size {
  w : Double
  h : Double
} derive(Eq, Debug, ToJson)

///|
/// ノードの箱の大きさを答えるもの。layout はこれしか知らない — 試験は数で渡す
pub type SizeOf = (@tree.Node, Array[Card], Int) -> Size

///|
/// ラベル行の規格。pad は文字の開始位置（箱の左からの距離）
pub(all) struct Row {
  px : Int
  pad : Double
  h : Double
} derive(Eq, Debug, ToJson)

///|
pub let normal : Row = { px: 13, pad: 12, h: 30, }

///|
/// 通常ノードの余白比（pad/字 = 0.92、行高/字 = 2.31）に寄せてある。
/// 小さく見せたいからと詰めすぎると、+N バッジが窮屈になって読めない
let hidden : Row = { px: 11, pad: 9, h: 24, }

///|
/// 隙間。x は親子の間、y は兄弟の間、root は木と木の間
pub(all) struct Gap {
  x : Double
  y : Double
  root : Double
} derive(Eq, Debug, ToJson)

///|
let gap : Gap = { x: 45, y: 10, root: 34, }

///|
/// 畳んだノードはこれより広くならない
let hidden_max_w = 150.0

// ---- カード行の寸法 ----

///|
/// リンクカード 1 行の高さ
let link_row = 26.0

///|
/// 画像行の中のサムネイルの高さ
let img_h = 64.0

///|
/// 画像行の高さ
let img_row : Double = img_h + 12.0

///|
/// 画像 / svg の中身はこれより狭くならない（余白抜き）
let img_min_w = 200.0

///|
/// コードのプレビュー 1 行の高さ
pub let code_line = 15.0

///|
/// コード行の上下の余白
pub let code_pad = 8.0

///|
/// コード行の字の後ろに残す幅。右の縁に貼り付かせない
let code_tail = 12.0

///|
/// リンク行の題の後ろに残す幅。開く印 ↗ がここに立つ
let link_tail = 22.0

///|
/// 装飾の水平線の行の高さ
let rule_row = 12.0

///|
/// details の summary の行。リンクと同じ 1 行の字
pub let details_row : Double = link_row

///|
/// ▸ のぶん、summary と中身の字を右へ寄せる
pub let details_indent = 14.0

///|
/// summary の無い details の名。ブラウザと GitHub の既定と同じ字
pub let details_name = "Details"

///|
/// ラベルが空のときに表示するプレースホルダ。表示箇所すべてがこれ 1 つを見る
let empty_label = "(empty)"

///|
/// カード 1 枚ぶんの高さ
fn row_h(c : Kind) -> Double {
  match c {
    Image(..) | Svg(..) => img_row
    Code(lines~, ..) => lines.length().to_double() * code_line + code_pad * 2.0
    Break => rule_row
    Details(open~, lines~, ..) =>
      details_row +
      (if open {
        lines.length().to_double() * code_line + code_pad
      } else {
        0.0
      })
    Link(..) => link_row
  }
}

///|
/// カード 1 枚の、行の枠から中身までの上下の余白。描くのも書き出すのも
/// 同じ場所を指す唯一の定義 — 別の数字を持てば 2px ずれる
fn card_inset(c : Kind) -> Double {
  match c {
    Code(..) => 5.0
    Link(..) | Details(..) => 4.0
    Break => 2.0
    Image(..) | Svg(..) => 6.0
  }
}

///|
/// カード 1 枚が、中身の箱から左右へはみ出す量。コードだけは背景をノードの
/// 縁近くまで塗るので、その分だけ広い
fn card_bleed(c : Kind) -> Double {
  match c {
    Code(..) => 5.0
    _ => 0.0
  }
}

///|
/// その行のラベルを測るための字
pub fn label_font(row : Row) -> Font {
  { px: row.px, mono: false, }
}

///|
let card_font : Font = { px: 12, mono: false, }

///|
/// コードの字。カードの入力欄も同じ字で打つ
pub let mono_font : Font = { px: 11, mono: true, }

///|
/// 畳んだノードに出す字。**`<summary>` > ラベル**（spec「畳み」の表示名の規則。
/// 3 段目の「最初の行」はラベルも空のときにしか来ないので、いまはプレースホルダに任せる）。
/// GitHub が畳んだ塊に見せるのも summary なので、鏡としてもこちら
pub fn fold_name(n : @tree.Node) -> String {
  match n.fold {
    Some({ summary: Some(s), .. }) => s
    _ => n.label
  }
}

///|
/// 畳まれて閉じているか。子を隠し、小さく描くのはこのときだけ。`<details open>` は
/// **開いた畳み**で、子は普通に出る（名前は summary のまま）。畳みは mmm の独自要素で、
/// `<details>` の見た目には引っ張られない — GitHub は summary の行の下に中身を並べるが、
/// mmm は畳まれたノードの名前を summary で統一する（開いていても）
pub fn closed(n : @tree.Node) -> Bool {
  n.fold is Some({ open: false, .. })
}

///|
/// 畳みの印。閉じていれば ▷、開いていれば ▽（名前の前に付く）
let fold_mark_closed = "▷ "

///|
let fold_mark_open = "▽ "

///|
/// 開いた畳みの字。印 + 名前（summary）
pub fn open_label(n : @tree.Node) -> String {
  fold_mark_open + display_label(fold_name(n))
}

///|
pub fn row_of(n : @tree.Node) -> Row {
  if closed(n) {
    hidden
  } else {
    normal
  }
}

///|
pub fn display_label(label : String) -> String {
  if label == "" {
    empty_label
  } else {
    label
  }
}

///|
/// 幅 max_w に収まるところで「…」を付けて詰める。
/// **通常のノードは詰めない** — 使うのは折り畳み表示だけ（そこは「小さく畳む」
/// ことが目的なので、長いラベルをそのまま出すと意味が無くなる）。
/// 切り口が上位サロゲートなら 1 つ戻して、ペアを割らない
fn clip_label(
  label : String,
  font : Font,
  max_w : Double,
  measure : Measure,
) -> String {
  guard measure(font, label) > max_w else { return label }
  let mut lo = 0
  let mut hi = label.length()
  while lo < hi {
    let mid = (lo + hi + 1) >> 1
    if measure(font, slice(label, 0, mid) + "…") <= max_w {
      lo = mid
    } else {
      hi = mid - 1
    }
  }
  if lo > 0 {
    let cut = label[lo - 1]
    if cut >= 0xd800 && cut <= 0xdbff {
      lo -= 1
    }
  }
  slice(label, 0, lo) + "…"
}

///|
/// 折り畳んだ子孫の数を示すバッジ（無ければ空）
fn collapsed_badge(buried : Int) -> String {
  if buried > 0 {
    "  +\{buried}"
  } else {
    ""
  }
}

///|
/// 畳んだノードの表示ラベル。幅で詰める（文字数だと CJK で箱からはみ出す）。
/// バッジは詰めの対象にしない — 「+3」が読めなくなっては意味がない
pub fn hidden_label(n : @tree.Node, buried : Int, measure : Measure) -> String {
  let raw = display_label(fold_name(n))
  let badge = collapsed_badge(buried)
  let font = label_font(hidden)
  // 印とバッジは詰めない。名前だけを残りの幅に詰める
  let budget = hidden_max_w -
    hidden.pad * 2.0 -
    measure(font, fold_mark_closed + badge)
  fold_mark_closed + clip_label(raw, font, budget, measure) + badge
}

///|
/// 箱の上から数えて、i 枚目のカードの上端はどこか。カードはラベル行の下に
/// 積むので、i = 枚数なら積み終わり = 箱の高さそのものになる。
/// 「行 i は縦のどこか」を数えるのはここだけ — 描画も当たり判定も落とし先も
/// 同じ積み方を見る（別々に数えれば余白が 2px ずれる）
pub fn row_top(cards : Array[Card], i : Int) -> Double {
  let mut y = normal.h
  for k in 0..<i {
    y += row_h(cards[k].kind)
  }
  y
}

///|
/// ノードの箱の大きさ。ラベルとカードから決まる。
/// w は content 幅（左右の余白抜き）で数え、最後に余白を足す — img_min_w 等の
/// 「最低幅」も content 側の基準であって、箱の実測幅そのものではない
pub fn node_size(measure : Measure) -> SizeOf {
  fn(n, cards, buried) {
    if closed(n) {
      // 閉じた畳み: ラベルを詰めた幅だけ。カード類は持たない
      let font = label_font(hidden)
      let w = @cmp.minimum(
        measure(font, hidden_label(n, buried, measure)),
        hidden_max_w,
      ).ceil()
      return { w: w + hidden.pad * 2.0, h: hidden.h, }
    }
    // 開いた畳みは印 + summary、それ以外はラベル
    let text = if n.fold is Some(_) {
      open_label(n)
    } else {
      display_label(n.label)
    }
    let mut w = measure(label_font(normal), text)
    for c in cards {
      match c.kind {
        Image(..) | Svg(..) => w = @cmp.maximum(w, img_min_w)
        Code(lines~, ..) =>
          for ln in lines {
            w = @cmp.maximum(w, measure(mono_font, ln) + code_tail)
          }
        Details(open~, summary~, lines~) => {
          let name = match summary {
            Some(s) => s
            None => details_name
          }
          w = @cmp.maximum(w, measure(card_font, name) + details_indent)
          if open {
            for ln in lines {
              w = @cmp.maximum(w, measure(card_font, ln) + details_indent)
            }
          }
        }
        Link(title~, ..) =>
          w = @cmp.maximum(w, measure(card_font, title) + link_tail)
        Break => ()
      }
    }
    { w: w.ceil() + normal.pad * 2.0, h: row_top(cards, cards.length()), }
  }
}
