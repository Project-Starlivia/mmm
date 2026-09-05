// md と操作の境界。操作（Doc → Doc）と反映（前後の木 → 編集列）を繋ぐ
// 唯一の場所で、core はここでも状態を持たない — 操作 1 回ごとに md を読み直す。
//
//   (before, spans) = survey(md)
//   done            = apply(before, op)           None なら編集は無い
//   edits           = merge(md, before, spans, done.doc)
//   focus           = done.focus を、読み直したときの番号に読み替える

///|
/// 操作を md に映した結果。edits は CodeMirror の changes の形。
/// focus は編集を当てて読み直した木での id（消した後は None）。
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
      let focus = done.focus.bind(id => @tree.number(done.doc, id))
      { edits, focus }
    }
    None => { edits: [], focus: None }
  }
}
