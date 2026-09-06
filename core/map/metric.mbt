// ノードの寸法。**ここが唯一の定義** — 字の大きさ・余白・行の高さ・隙間の数字は
// core のこのファイルにしか書かない。字の実測は canvas の仕事なので、
// `Measure` で外から受ける。
//
// ノードの「ラベル行」の寸法は、少なくとも 3 者が同じ値で見なければならない:
//   1. レイアウト（node_size が箱の大きさを決める）
//   2. SVG の描画（text 要素の font-size と x）
//   3. 編集用の <input> オーバーレイ（ts の label.ts。出口の mmmMetrics で受ける）
// 以前はこれが 3 箇所に散っていて、通常ノードは 13px/12、畳んだノードは
// 計測 10px・CSS 11px・input 13px と食い違い、折り畳んだノードを編集すると
// 文字がずれていた。font-size は CSS ではなく属性で入れて、CSS 側に同じ数字を持たせない。

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
pub type SizeOf = (@view.Node, Array[Card], Int) -> Size

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
pub let hidden : Row = { px: 11, pad: 9, h: 24, }

///|
/// 隙間。x は親子の間、y は兄弟の間、root は木と木の間
pub(all) struct Gap {
  x : Double
  y : Double
  root : Double
} derive(Eq, Debug, ToJson)

///|
pub let gap : Gap = { x: 45, y: 10, root: 34, }

///|
/// 畳んだノードはこれより広くならない
pub let hidden_max_w = 150.0

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
pub let img_min_w = 200.0

///|
/// コードのプレビュー 1 行の高さ
pub let code_line = 15.0

///|
/// コード行の上下の余白
pub let code_pad = 8.0

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
pub let empty_label = "(empty)"

///|
/// カード 1 枚ぶんの高さ
pub fn row_h(c : Card) -> Double {
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
/// 同じ場所を指さないと 2px ずれる — 実際にずれた。数字を 2 か所に置かないための唯一の定義
pub fn card_inset(c : Card) -> Double {
  match c {
    Code(..) => 5
    Link(..) | Details(..) => 4
    Break => 2
    Image(..) | Svg(..) => 6
  }
}

///|
/// カード 1 枚が、中身の箱から左右へはみ出す量。コードだけは背景をノードの
/// 縁近くまで塗るので、その分だけ広い
pub fn card_bleed(c : Card) -> Double {
  match c {
    Code(..) => 5
    _ => 0
  }
}

///|
/// その行のラベルを測るための字
pub fn label_font(row : Row) -> Font {
  { px: row.px, mono: false, }
}

///|
pub let card_font : Font = { px: 12, mono: false, }

///|
pub let mono_font : Font = { px: 11, mono: true, }

///|
/// Implicit は字を持たない。空の見出しと同じく空の字として扱う（種類は無い）
pub fn label_of(n : @view.Node) -> String {
  match n.label {
    Some(s) => s
    None => ""
  }
}

///|
/// 畳んだノードに出す字。**`<summary>` > ラベル**（spec「畳み」の表示名の規則。
/// 3 段目の「最初の行」はラベルも空のときにしか来ないので、いまはプレースホルダに任せる）。
/// GitHub が畳んだ塊に見せるのも summary なので、鏡としてもこちら
pub fn fold_name(n : @view.Node) -> String {
  match n.fold {
    Some({ summary: Some(s), .. }) => s
    _ => label_of(n)
  }
}

///|
pub fn row_of(n : @view.Node) -> Row {
  if n.fold is None {
    normal
  } else {
    hidden
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
pub fn clip_label(
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
pub fn collapsed_badge(buried : Int) -> String {
  if buried > 0 {
    "  +\{buried}"
  } else {
    ""
  }
}

///|
/// 畳んだノードの表示ラベル。幅で詰める（文字数だと CJK で箱からはみ出す）。
/// バッジは詰めの対象にしない — 「+3」が読めなくなっては意味がない
pub fn hidden_label(n : @view.Node, buried : Int, measure : Measure) -> String {
  let raw = display_label(fold_name(n))
  let badge = collapsed_badge(buried)
  let font = label_font(hidden)
  let budget = hidden_max_w - hidden.pad * 2.0 - measure(font, badge)
  clip_label(raw, font, budget, measure) + badge
}

///|
/// 箱の上から数えて、i 枚目のカードの上端はどこか。カードはラベル行の下に
/// 積むので、i = 枚数なら積み終わり = 箱の高さそのものになる。
/// 「行 i は縦のどこか」を数えるのはここだけ — 描画も当たり判定も落とし先も
/// 同じ積み方を見る（散らばっていた頃、余白が 2px ずれた）
pub fn row_top(cards : Array[Card], i : Int) -> Double {
  let mut y = normal.h
  for k in 0..<i {
    y += row_h(cards[k])
  }
  y
}

///|
/// ノードの箱の大きさ。ラベルとカードから決まる。
/// w は content 幅（左右の余白抜き）で数え、最後に余白を足す — img_min_w 等の
/// 「最低幅」も content 側の基準であって、箱の実測幅そのものではない
pub fn node_size(measure : Measure) -> SizeOf {
  fn(n, cards, buried) {
    if n.fold is Some(_) {
      // 畳み表示: ラベルを詰めた幅だけ。カード類は持たない
      let font = label_font(hidden)
      let w = @cmp.minimum(
        measure(font, hidden_label(n, buried, measure)),
        hidden_max_w,
      ).ceil()
      return { w: w + hidden.pad * 2.0, h: hidden.h, }
    }
    let mut w = measure(label_font(normal), display_label(label_of(n)))
    for c in cards {
      match c {
        Image(..) | Svg(..) => w = @cmp.maximum(w, img_min_w)
        Code(lines~, ..) =>
          for ln in lines {
            w = @cmp.maximum(w, measure(mono_font, ln) + 12.0)
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
          w = @cmp.maximum(w, measure(card_font, title) + 22.0)
        Break => ()
      }
    }
    { w: w.ceil() + normal.pad * 2.0, h: row_top(cards, cards.length()), }
  }
}
