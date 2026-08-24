// 貼り付けられた markdown 断片の、見出しの深さを読み替える。
//
// ここだけは「いまの文書」ではなくクリップボードの中身を相手にするので、
// st を一切触らない純関数として書く。それでもコアに置くのは、**見出しとは
// 何か・フェンスとは何かの答えを 2 つ持たないため** — 以前は同じ規則が
// TS 側（src/relevel.ts）にもう 1 つ書かれていた。

///|
/// 断片に（フェンスの外の）見出しが 1 つでもあるか。
fn has_any_heading(text : String) -> Bool {
  scan_doc(text, scan_lines(text)).heads.length() > 0
}

///|
/// いちばん浅い見出しが `target_depth` になるよう、断片全体をずらす。
/// 見出しが無ければそのまま返す。深さは 1 を下回らない。
fn relevel(text : String, target_depth : Int) -> String {
  let heads = scan_doc(text, scan_lines(text)).heads
  if heads.length() == 0 {
    return text
  }
  let mut min_depth = heads[0].depth
  for h in heads {
    if h.depth < min_depth {
      min_depth = h.depth
    }
  }
  let delta = target_depth - min_depth
  if delta == 0 {
    return text
  }
  let edits : Array[Edit] = []
  for h in heads {
    let depth = if h.depth + delta < 1 { 1 } else { h.depth + delta }
    edits.push(Edit::{
      from: h.hs,
      to: h.hs + h.depth,
      insert: hashes(depth),
      removed: sub(text, h.hs, h.hs + h.depth),
    })
  }
  apply_edit_set(text, edits)
}
