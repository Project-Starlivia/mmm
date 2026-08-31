// md を読む段。読みの正義は CommonMark で、実装は mizchi/markdown が持つ。
//
// 自前で書かないのは、ブロック規則を手で写すと間違いを照合する相手が
// 居なくなるから。旧 core はそれで往復を壊していた（字下げ行を段落と読み、
// 書き戻すと見出しが生える）。

///|
/// md の AST。ここを通すことで、パーサの差し替えがこの 1 ファイルに閉じる。
pub fn read(md : String) -> @markdown.Document {
  @markdown.parse(md).document
}
