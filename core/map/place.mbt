// 入力欄（ラベル・カード）を箱の上のどこに重ねるかの算術。DOM を知らない。
//
// 枠(border)と余白(padding)は CSS ピクセルでズームに追従しないので、world の
// 単位で組んでから 1 度だけ倍率を掛け、追従しないぶんを別に足す — これを間違えると
// 倍率 1 では合っているのに 2 倍で箱と文字がずれる。器（`<input>` / `<textarea>`）は ts。

///|
/// そのまま style へ入れる値（px）
pub(all) struct Placement {
  left : Double
  top : Double
  width : Double
  height : Double
  font_size : Double
  padding : Double
} derive(Eq, Debug)

///|
/// 入力欄の枠。拡大しない
pub let label_border = 2.0

///|
/// 余白をいくら縮めても、これだけは残す（字が縁に貼り付かないように）
let label_min_pad = 2.0

///|
/// 入力欄をノードのラベル行に**ぴったり**重ねる。`text_w` は world 単位で実測した
/// 字の幅（余白は含まない）。`box-sizing: border-box` なので字は left + border + padding
/// から始まる。left を border ぶん外へずらせばその分が打ち消え、padding は SVG の
/// ラベルの x（= `row.pad`）をそのまま倍率に掛けた値でよい。
/// 字が箱より長くなったら右へ伸び、短いときは箱に重なったまま
pub fn label_place(b : Box, cam : Camera, text_w : Double) -> Placement {
  let row = row_of(b.node)
  let w_world = @cmp.maximum(b.w, text_w + row.pad * 2.0)
  {
    left: b.x * cam.k + cam.tx - label_border,
    top: b.y * cam.k + cam.ty - label_border,
    width: w_world * cam.k + label_border * 2.0,
    height: row.h * cam.k + label_border * 2.0,
    font_size: row.px.to_double() * cam.k,
    padding: @cmp.maximum(row.pad * cam.k, label_min_pad),
  }
}

///|
/// カードの入力欄の枠。拡大しない
pub let card_border = 2.0

///|
/// カードの入力欄の内側の余白（world の単位）
let card_pad = 5.0

///|
/// カードの入力欄の字の大きさ（world の単位。カードのコードと同じ）
pub let card_font_px = 11.0

///|
/// カードの入力欄を、カードの矩形（world）に重ねる。枠は `rect` の上に置き、余白は内側
/// （label_place と同じ）— 外へ育てると隣の行に被る。中身が rect より
/// 大きければ、その分だけ下と右へ伸びる（打っている途中で文字が隠れると
/// 何を書いているか分からなくなる）。枠の分を足しておかないと最終行が削れる
pub fn card_place(
  rect : Rect,
  cam : Camera,
  lines : Int,
  widest : Double,
) -> Placement {
  let w_world = @cmp.maximum(rect.w, widest + card_pad * 2.0)
  let h_world = @cmp.maximum(
    rect.h,
    lines.to_double() * code_line + card_pad * 2.0,
  )
  {
    left: rect.x * cam.k + cam.tx,
    top: rect.y * cam.k + cam.ty,
    width: w_world * cam.k + card_border * 2.0,
    height: h_world * cam.k + card_border * 2.0,
    font_size: card_font_px * cam.k,
    padding: card_pad * cam.k,
  }
}
