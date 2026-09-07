// 字の実測。map/ は字の大きさ（`Font` の px と mono）を決め、綴り（family）は
// **style.css の `--font` / `--mono` ひとつ**なので、幅を測る canvas のためにここで組み直す。
// map の layout / render はこれを閉包で受ける。

///|
/// 1 世代に覚える上限。**世代は 2 つ**なので、実際に当たるのはこの倍まで。
/// 上限が要るのは、名前を打っている最中の途中の字（`あ` `あい` `あいう` …）や、
/// 詰める位置を探る途中の字が、二度と使われないまま溜まるため
let cache_max = 4000

///|
/// 覚えの 2 世代。いっぱいになったら古いほうを捨てて入れ替える
priv struct Ages {
  mut live : Map[String, Double]
  mut prev : Map[String, Double]
}

///|
/// 覚えを噛ませる。**いっぱいになったら古い世代を捨て、今を 1 つ古くする** —
/// 全部捨てると、測る綴りが上限を超える文書では 1 つも当たらなくなる（1 周の
/// 途中で捨てられ、次の周も頭から外れる）。1 世代残せば、上限の倍までの綴りを
/// 持つ文書は 2 周目から全部当たる。使われない字は世代交代 2 回で落ちる
pub fn cached(cap : Int, raw : (@map.Font, String) -> Double) -> @map.Measure {
  let ages : Ages = { live: Map([]), prev: Map([]), }
  (f, text) => {
    let key = "\{f.px} \{f.mono} \{text}"
    match ages.live.get(key) {
      Some(w) => w
      // 古い世代に在ればそれを使う。**今の世代へは写さない** — 写すと世代交代が
      // 早まり、「上限の倍まで覚える」という広さが縮む
      None =>
        match ages.prev.get(key) {
          Some(w) => w
          None => {
            let w = raw(f, text)
            ages.live[key] = w
            // **超えてから**交代する。ちょうどで交代すると、綴りが上限の倍
            // ちょうどの文書で 1 周の終わりにもう一度交代し、最初の世代が落ちる
            if ages.live.length() > cap {
              ages.prev = ages.live
              ages.live = Map([])
            }
            w
          }
        }
    }
  }
}

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

  cached(cache_max, (f, text) => @web.text_width(doc, font_of(f), text))
}
