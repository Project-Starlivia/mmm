// md と操作の境界。操作（Doc → Doc）と合流（前後の木 → 編集列）を繋ぐ
// 唯一の場所で、core はここでも状態を持たない — 操作 1 回ごとに md を読み直す。
//
//   (before, spans) = build(md)
//   done            = apply(before, op)           None なら編集は無い
//   merged          = merge(md, before, spans, done.doc)
//   focus           = done.focus を、読み直したときの番号に読み替える
//                     合流が形の一致を言えば。言わなければ無い

///|
/// 操作を md に映した結果。edits は CodeMirror の changes の形。
/// focus は編集を当てて読み直した木での id（ノードを消せば隣、中身を消せば持ち主。最後の根か文書の散文を消した後、
/// および書いた md が別の形に読まれたときは None）。
pub(all) struct Edited {
  edits : Array[@tree.Edit]
  focus : Int?
} derive(Eq, Debug, ToJson)

///|
pub fn edit(md : String, op : Op) -> Edited {
  let (before, spans) = @tree.build(md)
  match apply(before, op) {
    Some(done) => {
      // 書いた md を読み直して形が合わなければ focus は無い — focus は文書順の
      // 番号なので、形がずれたまま返すと別のノードを指す（`- ---` が水平線になる等）。
      // 読み直しは合流がもう済ませているので、答え（same）をそのまま貰う
      let { edits, same, } = @tree.merge(md, before, spans, done.doc)
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
