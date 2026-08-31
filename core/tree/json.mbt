// 木を JSON にする。**境界を渡るのはこの形だけ**（TS は木の型を知らない）。
//
// 指紋（sig.mbt）が「1 行で読む」ためのものなのに対して、こちらは
// 「機械が読む・畳んで探る」ため。両方あるのは、人が見たいものが場面で違うから。

///|
/// 文書ぜんぶを JSON にする。
pub fn json(doc : Doc) -> String {
  let sb = StringBuilder::new()
  sb.write_string("{\"frontmatter\":")
  match doc.frontmatter {
    Some(f) => sb.write_string(quote(f))
    None => sb.write_string("null")
  }
  sb.write_string(",\"eol\":")
  sb.write_string(quote(if doc.eol is Crlf { "crlf" } else { "lf" }))
  sb.write_string(",\"body\":")
  sb.write_string(blocks_json(doc.body))
  sb.write_string(",\"roots\":[")
  for i, r in doc.roots {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string("{\"id\":\{r.id},\"node\":")
    sb.write_string(node_json(r.node))
    sb.write_string(",\"wings\":[")
    for j, w in r.wings {
      if j > 0 {
        sb.write_string(",")
      }
      sb.write_string("{\"side\":")
      sb.write_string(quote(if w.side is Right { "right" } else { "left" }))
      sb.write_string(",\"branch\":")
      sb.write_string(branch_json(w.branch))
      sb.write_string("}")
    }
    sb.write_string("]}")
  }
  sb.write_string("]}")
  sb.to_string()
}

///|
fn branch_json(b : Branch) -> String {
  let sb = StringBuilder::new()
  sb.write_string("{\"id\":\{b.id},\"node\":")
  sb.write_string(node_json(b.node))
  sb.write_string(",\"children\":[")
  for i, c in b.children {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string(branch_json(c))
  }
  sb.write_string("]}")
  sb.to_string()
}

///|
/// Implicit は綴りが無いので、`sign` も `label` も持たせない
/// （null を並べると「空ラベル」と見分けが付かなくなる）。
fn node_json(n : Node) -> String {
  match n {
    Implicit => "{\"implicit\":true}"
    Explicit(sign~, label~, folded~, body~) => {
      let sb = StringBuilder::new()
      sb.write_string("{\"sign\":")
      sb.write_string(quote(if sign is Heading { "heading" } else { "item" }))
      sb.write_string(",\"label\":")
      sb.write_string(quote(label))
      sb.write_string(",\"folded\":\{folded},\"body\":")
      sb.write_string(blocks_json(body))
      sb.write_string("}")
      sb.to_string()
    }
  }
}

///|
fn blocks_json(bs : Array[Block]) -> String {
  let sb = StringBuilder::new()
  sb.write_string("[")
  for i, b in bs {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string(block_json(b))
  }
  sb.write_string("]")
  sb.to_string()
}

///|
fn block_json(b : Block) -> String {
  match b {
    Rule => "{\"kind\":\"rule\"}"
    Opaque(text) => "{\"kind\":\"opaque\",\"text\":\{quote(text)}}"
    Content(Image(alt~, src~)) =>
      "{\"kind\":\"image\",\"alt\":\{quote(alt)},\"src\":\{quote(src)}}"
    Content(Link(text~, href~)) =>
      "{\"kind\":\"link\",\"text\":\{quote(text)},\"href\":\{quote(href)}}"
    Content(Code(info~, text~)) =>
      "{\"kind\":\"code\",\"info\":\{quote(info)},\"text\":\{quote(text)}}"
    Content(Svg(text)) => "{\"kind\":\"svg\",\"text\":\{quote(text)}}"
  }
}

///|
/// JSON の文字列。制御文字は `\uXXXX` へ逃がす。
fn quote(s : String) -> String {
  let sb = StringBuilder::new()
  sb.write_string("\"")
  for c in s {
    match c {
      '"' => sb.write_string("\\\"")
      '\\' => sb.write_string("\\\\")
      '\n' => sb.write_string("\\n")
      '\r' => sb.write_string("\\r")
      '\t' => sb.write_string("\\t")
      _ =>
        if c.to_int() < 0x20 {
          sb.write_string("\\u\{hex4(c.to_int())}")
        } else {
          sb.write_char(c)
        }
    }
  }
  sb.write_string("\"")
  sb.to_string()
}

///|
fn hex4(n : Int) -> String {
  // 文字列の添字は UInt16 を返すので、Char の配列で持つ
  let digits = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  let sb = StringBuilder::new()
  for shift in [12, 8, 4, 0] {
    sb.write_char(digits[(n >> shift) & 0xf])
  }
  sb.to_string()
}
