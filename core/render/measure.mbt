// 字の実測。map/ は字の大きさ（`Font` の px と mono）を決め、綴り（family）は
// **style.css の `--font` / `--mono` ひとつ**なので、幅を測る canvas のためにここで組み直す。
// map の layout / render はこれを閉包で受ける。

///|
/// 実測はレンダでいちばん回る呼び出し。ラベルはレンダをまたいで繰り返し出てくるので、
/// font + 字で幅を覚える。rename 中の途中の字などで無限に伸びるので上限を置く
let cache_max = 4000

///|
/// 綴りは起動後に 1 度だけ読む（テーマを変えても字は変わらないので、読み直す理由が無い）
fn family(doc : @dom.Document, name : String, fallback : String) -> String {
  let css = @web.css_var(doc, name)
  if css == "" {
    fallback
  } else {
    css
  }
}

///|
/// この文書の字を測るもの
pub fn measure(doc : @dom.Document) -> @map.Measure {
  let fonts : Map[Bool, String] = Map([])
  let widths : Map[String, Double] = Map([])
  fn font_of(f : @map.Font) -> String {
    let fam = match fonts.get(f.mono) {
      Some(v) => v
      None => {
        let v = if f.mono {
          family(doc, "--mono", "monospace")
        } else {
          family(doc, "--font", "sans-serif")
        }
        fonts[f.mono] = v
        v
      }
    }
    f.px.to_string() + "px " + fam
  }
  (f, text) => {
    let font = font_of(f)
    let key = font + " " + text
    match widths.get(key) {
      Some(w) => w
      None => {
        let w = @web.text_width(doc, font, text)
        if widths.length() >= cache_max {
          widths.clear()
        }
        widths[key] = w
        w
      }
    }
  }
}
