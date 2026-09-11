// 記法がどこまでかを、原文から測る。**ライブラリの span では足りない所だけ。**
//
// 見出しはラベルの頭と尻（インラインの span は中身に対する相対で、定義行の形をした
// 1 行目では中身を覆いきらない）、項目はマーカーと桁と詰め（ライブラリは番号を振り
// 直すので飛んだ数字が取れず、詰めは列にしか無いので項目ごとには測れない）。
//
// 字と行の算術は `text.mbt`。ここに在るのは「その記法がどこで終わるか」だけ。

///|
/// 見出しの中身を、原文からそのまま切り出す（mmm はインラインを解釈しない）。
/// 中身が無ければ空ラベル（`## ` のような行）。
///
/// インラインの span は**中身に対する 0 始まりの相対**なので、原文の
/// どこから中身が始まるかは自分で数える。実測（`# a` / `#   a` / `# a #` /
/// setext）は md_wbtest.mbt に固定してある。
fn head_label(
  md : String,
  span : @markdown.Span,
  style : @markdown.HeadingStyle,
  children : Array[@markdown.Inline],
) -> String {
  if children.is_empty() {
    return ""
  }
  let from = head_start(md, span, style)
  carve(md, from, head_end(md, span, style))
}

///|
/// 見出しの中身が原文で終わる位置。
///
/// **インラインの並びからは導けない。** mdAst は 1 行目がリンクの定義行の形を
/// していると中身の一部を定義として引き取るので、インラインが行の全部を覆わない
/// ことがある（`[q]: /r` + 改行 + `ZZZ` + `---` で `ZZZ` が落ちていた）。
/// 記法は md の規則で決まるので、そちらから引く。
fn head_end(
  md : String,
  span : @markdown.Span,
  style : @markdown.HeadingStyle,
) -> Int {
  let mut z = span.to
  // 末尾の空白と改行は記法
  while z > span.from && space(md[z - 1]) {
    z = z - 1
  }
  if style is Atx {
    // 閉じの `#` は飾り。前に空白があるときだけ（`a#` は中身）
    let mut h = z
    while h > span.from && md[h - 1] == '#' {
      h = h - 1
    }
    if h < z && (h == span.from || space(md[h - 1])) {
      z = h
      while z > span.from && space(md[z - 1]) {
        z = z - 1
      }
    }
  } else {
    // setext の下線 1 行ぶんを落とす
    while z > span.from && md[z - 1] != '\n' {
      z = z - 1
    }
    while z > span.from && space(md[z - 1]) {
      z = z - 1
    }
  }
  z
}

///|
/// 見出しの中身が原文で始まる位置。ATX は飾りの字下げと `#` とその後ろの
/// 空白を飛ばす。setext には `#` が無いので飛ばさない（`#hashtag` を
/// 食べてしまうため）。
fn head_start(
  md : String,
  span : @markdown.Span,
  style : @markdown.HeadingStyle,
) -> Int {
  let mut p = skip_space(md, span.from, span.to)
  if style is Atx {
    while p < span.to && md[p] == '#' {
      p = p + 1
    }
    p = skip_space(md, p, span.to)
  }
  p
}

///|
/// 項目のラベルの頭。マーカーと空白を読み飛ばす。
/// 1 行目が段落ならその span の頭と一致する。段落の無い項目のために持つ。
fn item_start(md : String, span : @markdown.Span) -> Int {
  skip_space(md, marker_end(md, span), span.to)
}

///|
/// 列の詰め — 項目ごとに、手前の項目との間に空行が有るか。
///
/// **ライブラリの `tight` では測れない。** CommonMark の `tight` は列のどこかに
/// 空行があれば偽なので、項目 1 つの中の空行でも列ぜんぶが loose になる。それで
/// 書き戻すと、空行が項目と項目の**間**へ移る（触っていない字が変わり、冪等でもない）。
/// 隙間は原文から測る。
///
/// 列の頭の隙間は列の手前のもの（その項目のものではない）ので、2 つ目に従う。
/// 項目が 1 つだけなら間が無いので詰まっている。
fn item_gaps(md : String, items : Array[@markdown.ListItem]) -> Array[Bool] {
  let out = Array::makei(items.length(), i => {
    let head = line_start(md, items[i].span.from)
    i > 0 && blank_start(md, head) < head
  })
  if out.length() > 1 {
    out[0] = out[1]
  }
  out
}

///|
/// 項目のマーカーの字。**読んだ綴りをそのまま持つ** — 番号はライブラリが
/// 列の先頭から振り直すので、飛んだ数字（`1.` の次が `5.`）は原文からしか取れない。
fn item_marker(md : String, span : @markdown.Span) -> String {
  carve(md, skip_space(md, span.from, span.to), marker_end(md, span))
}

///|
/// 項目のマーカーの尻。`-` `*` `+` か、数字と `.` `)`。
fn marker_end(md : String, span : @markdown.Span) -> Int {
  let mut p = skip_space(md, span.from, span.to)
  while p < span.to && md[p] >= '0' && md[p] <= '9' {
    p = p + 1
  }
  if p < span.to &&
    (
      md[p] == '-' ||
      md[p] == '*' ||
      md[p] == '+' ||
      md[p] == '.' ||
      md[p] == ')'
    ) {
    p = p + 1
  }
  p
}
