// 貼り付けられた markdown 断片の、見出しの深さを読み替える。
//
// ここだけは「いまの文書」ではなくクリップボードの中身を相手にするので、
// 呼び出し側から見れば純関数（`st.text` は書き換えない）。それでもコアに
// 置くのは、**見出しとは何か・フェンスとは何かの答えを 2 つ持たないため**
// — 以前は同じ規則が TS 側（src/relevel.ts）にもう 1 つ書かれていた。

///|
/// 断片に（フェンスの外の）見出しが 1 つでもあるか。
fn has_any_heading(text : String) -> Bool {
  scan_doc(text, scan_lines(text)).heads.length() > 0
}

///|
/// いちばん浅い構造行が `target_depth` になるよう、断片全体をずらす。
/// 構造が無ければそのまま返す。深さは 1 を下回らない。
///
/// **断片だけを読み直した深さは使わない。** 断片には周りの見出しが無いので、
/// 単独で読み直すと入れ子の段数が浅く数え直されてしまう（実際に踏んだ —
/// 貼り先の深さのつもりで書いた字下げが、貼り付け直後の reformat 相当で
/// 浅い深さへ引き戻された）。`format_edits` に**貼り先で本当になる深さ**を
/// 外から渡すことで、断片自身の構造（どの行がどの見出しの中身か・
/// フェンスの範囲）は使いつつ、深さの答えだけ上書きする。
///
/// 接頭辞・字下げ・空行はすべて**いまの文書のモード**の正規形で書く —
/// リストの断片を見出しの文書に貼れば見出しに、逆なら逆になる。
fn relevel(text : String, target_depth : Int) -> String {
  let saved_text = st.text
  let saved_nodes = st.nodes
  let saved_fences = st.fences
  let saved_hides = st.hide_regions
  let saved_head = st.head
  let saved_index = st.index_of
  let saved_next_id = st.next_id
  st.text = text
  // rebuild_nodes が st の欄を増やしたら、ここにも同じ欄を足すこと
  // （st.head を一度足し忘れ、断片の頭の区間が文書の頭として残った）
  rebuild_nodes(Map([]))
  let out = if st.nodes.length() == 0 {
    text
  } else {
    let mut min_depth = st.nodes[0].depth
    for nd in st.nodes {
      if nd.depth < min_depth {
        min_depth = nd.depth
      }
    }
    let delta = target_depth - min_depth
    let target : Array[Int] = []
    for nd in st.nodes {
      let d = nd.depth + delta
      target.push(if d < 1 { 1 } else { d })
    }
    apply_edit_set(text, format_edits(fn(i) { target[i] }))
  }
  st.text = saved_text
  st.nodes = saved_nodes
  st.fences = saved_fences
  st.hide_regions = saved_hides
  st.head = saved_head
  st.index_of = saved_index
  st.next_id = saved_next_id
  out
}
