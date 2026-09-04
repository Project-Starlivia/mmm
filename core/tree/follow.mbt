// 選択が md の打鍵をまたいで同じノードを指し続けるための、同一性の引き直し。
//
// 前のサイクルの目印（マーカーの範囲とラベルの頭）を編集列で写し、いまの地番で
// ラベルの頭が一致するノードを答える。id は読みのサイクルを越えて持たないので、
// 持ち越すのは位置。決めは docs/superpowers/specs/2026-09-04-select-design.md。
//
// core は状態を持たない — 前のサイクルの目印は ts が渡す。

///|
/// 前のサイクルの目印。from はマーカーの頭（骨格の行の頭）、label はラベルの頭。
pub(all) struct Mark {
  from : Int
  label : Int
} derive(Eq, Debug, ToJson, FromJson)

///|
/// 写した目印と、いま当たるノード。当たらなくても目印は返す（黙って持ち越す）。
pub(all) struct Trail {
  mark : Mark
  id : Int?
} derive(Eq, Debug, ToJson)

///|
/// 目印ごとに、編集の後でどこに居るか。None は死んだ — マーカーが丸ごと消されたか、
/// ラベルの頭が消去の内側に落ちた。当たったら目印は今の地番のものに置き換える。
pub fn follow(
  spots : Map[Int, Spot],
  edits : Array[Edit],
  marks : Array[Mark],
) -> Array[Trail?] {
  marks.map(m => {
    match carry(edits, m) {
      Some(mark) => {
        let mut hit : Int? = None
        for id, s in spots {
          if s.label == Some(mark.label) {
            hit = Some(id)
          }
        }
        match hit {
          Some(id) => {
            let s = spots.get(id).unwrap()
            Some({ mark: { from: s.from, label: mark.label }, id: Some(id) })
          }
          None => Some({ mark, id: None })
        }
      }
      None => None
    }
  })
}

///|
/// 目印を編集列で写す。編集は前の座標で from 順、重ならないので、**元の位置に
/// 対する差分を合算**する（写した位置と元座標の編集を比べると、消去の後ろの挿入を
/// 取りこぼす）。マーカー `[from, label)` は隣り合う消去が合わせて消すこともあるので、
/// 消えた範囲を繋いで測る。
fn carry(edits : Array[Edit], m : Mark) -> Mark? {
  let mut reach = m.from
  let mut d_from = 0
  let mut d_label = 0
  for e in edits {
    let deleting = e.to > e.from
    // マーカーが丸ごと消えた（消去が繋がって from から label まで届く）
    if deleting && e.from <= reach && e.to > reach {
      reach = e.to
    }
    if reach >= m.label {
      return None
    }
    // ラベルの頭が消去の内側
    if e.from < m.label && m.label < e.to {
      return None
    }
    d_from = d_from + delta(m.from, e)
    d_label = d_label + delta(m.label, e)
  }
  Some({ from: m.from + d_from, label: m.label + d_label })
}

///|
/// 元の位置 pos が、編集 1 つでどれだけずれるか。手前の編集ぶんずれる。
/// **ちょうどその位置への挿入は動かさない**（挿入の前に留まる — ラベルの頭に字を
/// 足せば、その字がラベルの先頭）。その位置で終わる消去はずらす（`##` を 1 つ消せば
/// ラベルは 1 つ手前）。消去の内側なら消去の頭へ。
fn delta(pos : Int, e : Edit) -> Int {
  let grown = e.insert.length() - (e.to - e.from)
  if e.to < pos || (e.to == pos && e.to > e.from) {
    grown
  } else if e.from < pos && pos < e.to {
    e.from + e.insert.length() - pos
  } else {
    0
  }
}
