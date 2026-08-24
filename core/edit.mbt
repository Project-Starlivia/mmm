// テキストの差分。Edit は「[from, to) を insert で置き換えた。消えたのは
// removed」という 1 かたまりで、すべての変更はこれの集合として表される。
// この層は文書の状態 (st) を知らない。

///|
priv struct Edit {
  from : Int
  to : Int
  insert : String
  removed : String
}

///|
/// Apply one edit set. Offsets refer to the pre-apply text; edits are
/// ascending and non-overlapping. Several zero-length inserts may share an
/// offset (applied in array order), and a zero-length insert may share its
/// offset with a following deletion/replacement.
fn apply_edit_set(text : String, edits : Array[Edit]) -> String {
  let sb = StringBuilder::new()
  let mut pos = 0
  for e in edits {
    sb.write_string(slice(text, pos, e.from))
    sb.write_string(e.insert)
    pos = e.to
  }
  sb.write_string(slice(text, pos, text.length()))
  sb.to_string()
}

///|
/// Inverse of an edit set; offsets are valid in the post-apply text.
fn invert_edit_set(edits : Array[Edit]) -> Array[Edit] {
  let out : Array[Edit] = []
  let mut delta = 0
  for e in edits {
    let f = e.from + delta
    out.push(Edit::{
      from: f,
      to: f + e.insert.length(),
      insert: e.removed,
      removed: e.insert,
    })
    delta = delta + e.insert.length() - (e.to - e.from)
  }
  out
}

///|
/// Map a pre-edit heading-start offset to a post-edit offset. Returns -1
/// if the position was destroyed.
fn map_offset(p : Int, edits : Array[Edit]) -> Int {
  let mut delta = 0
  for e in edits {
    if p < e.from {
      break
    }
    if p == e.from {
      if e.to > e.from {
        // replacement (rename): the line is rewritten in place — survives
        if e.insert.length() > 0 {
          break
        }
        // 純削除。行の中だけを消すなら（outdent が `#` を 1 個消す等）
        // 行は短くなるだけでその場に残るので、位置も生きている。
        // 改行をまたぐ削除は行ごと消えるので破壊。
        //
        // ここを一律に破壊扱いしていたため、最後の子を outdent すると
        // id が捨てられ、その場で選択が外れていた（F-004）。
        // 楽観的に残す方が安全でもある: 位置に見出しが無ければ
        // rebuild_nodes が拾わないだけで、誤って別のノードに id が
        // 付くことはない
        let mut has_nl = false
        for k = 0; k < e.removed.length(); k = k + 1 {
          if code_at(e.removed, k) == 10 {
            has_nl = true
            break
          }
        }
        if has_nl {
          return -1
        }
        break
      }
      // pure insertion exactly at the heading start: text ending with a
      // newline creates new line(s) ABOVE and pushes the heading right;
      // anything else (e.g. an indent's "#") rewrites this line in place
      let n = e.insert.length()
      if n > 0 && code_at(e.insert, n - 1) == 10 {
        delta = delta + n
      }
      break
    }
    if p < e.to {
      return -1
    }
    delta = delta + e.insert.length() - (e.to - e.from)
  }
  p + delta
}
