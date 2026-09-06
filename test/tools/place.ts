// 試験用の置き方。md を core に読ませて置く — 手で View を組まないのは、それが
// 嘘の木になるから。字の実測は「どの字も 76px」にして、字だけのノードを全部
// 100 × 30 に揃える（w = ceil(76) + 左右の余白 24、h = ラベル行 30）。
// id は文書順の通し番号（文書が 1、最初の根が 2）。

import * as core from "../../src/coreApi.ts";

export const place = (md: string): core.Layout => core.layout(core.survey(md), () => 76);
