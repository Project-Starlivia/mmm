// 外部（別のエディタ・git など）でファイルが変わったときの判断。
//
// 自分の保存はネイティブ本体（Rust）がハッシュ照合で弾くので、ここに
// 来るのは本物の外部変更だけ。未編集なら黙って追従し、編集中なら
// 勝手に捨てず知らせるに留める。

export type ExternalChangeAction = "reload" | "warn";

/**
 * current = いま core が持っているテキスト、savedText = 最後に保存/読込した
 * 内容。両者が一致する（未編集）なら reload、編集中なら warn。
 */
export function decideExternalChange(
  current: string,
  savedText: string,
): ExternalChangeAction {
  return current === savedText ? "reload" : "warn";
}
