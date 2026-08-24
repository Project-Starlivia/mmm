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
/// 見出しの先頭位置をまとめて写す（編集の前 → 後）。行ごと消えた位置は -1 に
/// なり、以降は -1 のまま。
///
/// 位置も編集も昇順なので、**両方を 1 度ずつ歩けば足りる**。1 つずつ写して
/// いたころ、1 つの編集集合の中で「ノード数 × 編集数」になっていて、
/// まとめて段下げすると件数の二乗の時間がかかっていた。
fn map_offsets(positions : Array[Int], edits : Array[Edit]) -> Unit {
  let m = edits.length()
  let mut ei = 0
  let mut delta = 0
  for k = 0; k < positions.length(); k = k + 1 {
    let p = positions[k]
    if p < 0 {
      continue
    }
    // p より手前で完結している編集を消化する（p が昇順なので戻らない）
    while ei < m && edits[ei].from < p && edits[ei].to <= p {
      let e = edits[ei]
      delta = delta + e.insert.length() - (e.to - e.from)
      ei = ei + 1
    }
    if ei < m && edits[ei].from < p {
      positions[k] = -1 // 消える範囲に飲まれた
      continue
    }
    if ei < m && edits[ei].from == p {
      let e = edits[ei]
      if e.to > e.from {
        // 置換（rename）: 行はその場で書き直されるので位置は生きている
        if e.insert.length() > 0 {
          positions[k] = p + delta
          continue
        }
        // 純削除。行の中だけを消すなら（outdent が `#` を 1 個消す等）
        // 行は短くなるだけでその場に残るので、位置も生きている。
        // 改行をまたぐ削除は行ごと消えるので破壊。
        //
        // ここを一律に破壊扱いしていたため、最後の子を outdent すると
        // id が捨てられ、その場で選択が外れていた。楽観的に残す方が安全
        // でもある: 位置に見出しが無ければ rebuild_nodes が拾わないだけで、
        // 誤って別のノードに id が付くことはない
        let mut has_nl = false
        for c = 0; c < e.removed.length(); c = c + 1 {
          if code_at(e.removed, c) == 10 {
            has_nl = true
            break
          }
        }
        positions[k] = if has_nl { -1 } else { p + delta }
        continue
      }
      // 見出しの先頭ちょうどへの純粋な挿入: 改行で終わる文字列は**上に**
      // 行を作って見出しを押し下げる。それ以外（indent の "#" 等）は
      // この行をその場で書き換えるだけ
      let n = e.insert.length()
      positions[k] = if n > 0 && code_at(e.insert, n - 1) == 10 {
        p + delta + n
      } else {
        p + delta
      }
      continue
    }
    positions[k] = p + delta
  }
}
