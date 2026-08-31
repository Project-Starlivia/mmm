// md を読む段。読みの正義は CommonMark で、実装は mizchi/markdown が持つ。
//
// 自前で書かないのは、ブロック規則を手で写すと間違いを照合する相手が
// 居なくなるから。旧 core はそれで往復を壊していた（字下げ行を段落と読み、
// 書き戻すと見出しが生える）。
//
// 払った値段は **配布物で gzip +31KB**（591KB → 622KB。vite の dist で実測）。
// 上流に parser だけを取る道は無く、MoonBit にパッケージ単位の DCE も無い。
// 生の出力では +49KB だが、到達しないコードは rollup が落とす。

///|
/// md の AST。ここを通すことで、パーサの差し替えがこの 1 ファイルに閉じる。
pub fn read(md : String) -> @markdown.Document {
  @markdown.parse(md).document
}
