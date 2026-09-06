// md と操作の境界。操作（Doc → Doc）と合流（前後の木 → 編集列）を繋ぐ
// 唯一の場所で、core はここでも状態を持たない — 操作 1 回ごとに md を読み直す。
//
//   (before, spans) = survey(md)
//   done            = apply(before, op)           None なら編集は無い
//   edits           = merge(md, before, spans, done.doc)
//   focus           = done.focus を、読み直したときの番号に読み替える

///|
/// 操作を md に映した結果。edits は CodeMirror の changes の形。
/// focus は編集を当てて読み直した木での id（ノードを消せば隣、中身を消せば持ち主。最後の根か文書の散文を消した後は None）。
pub(all) struct Edited {
  edits : Array[@tree.Edit]
  focus : Int?
} derive(Eq, Debug, ToJson)

///|
pub fn edit(md : String, op : @op.Op) -> Edited {
  let (before, spans) = @tree.survey(md)
  match @op.apply(before, op) {
    Some(done) => {
      let edits = @tree.merge(md, before, spans, done.doc)
      // 書いた md を読み直して枠（字を消した形）が合わなければ focus は無い —
      // focus は文書順の番号なので、要素の並びがずれたまま返すと別のノードを指す
      // （中身の尻の水平線に骨格が続く形は境界に読まれて要素が消える等。形は md が
      // 決める）。字の正規化だけなら枠は変わらないので focus はそのまま
      let same = @tree.frame(@tree.parse(@tree.apply(md, edits))) ==
        @tree.frame(done.doc)
      let focus = if same {
        done.focus.bind(id => @tree.number(done.doc, id))
      } else {
        None
      }
      { edits, focus, }
    }
    None => { edits: [], focus: None, }
  }
}
