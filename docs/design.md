# 設計の型

部品ごとに「何をしているか」「どの既知の型か」「段の間で何を約束するか」を 1 ページで言う。
設計を監督するための地図。細部は [spec.md](spec.md)（UI）と [core.md](core.md)（core）、見た目の数字は [look.md](look.md)。

## 部品と型

| 部品 | やっていること | 既知の型 |
|---|---|---|
| md が真実、木は派生 | 打鍵 → parse → View → 描画。読みは書かない | LSP / IDE の「テキストが真実、AST は派生」 |
| 方言（md.mbt） | ライブラリの mdAst を mmm の決めに揃える層。読みは `stretch ∘ parse`（span の尻を伸ばすだけで、意味は 1 つも足さない）、書きは `serialize` そのまま（読んだ原文は生の塊で通す）。癖を知るのはここだけ | 腐敗防止層（anti-corruption layer）。アダプタ |
| Op → apply → check | 操作は値。木に当てるのは純粋関数。書けない木は check が断る | Command + 不変条件で弾く |
| merge | 正規形を base にした 3-way merge。base → theirs（操作の差）だけを ours（原文）に写し、流儀の差は写さない。要素は手前の隙間を持つ。最後に読み直して形を検証 | 3-way merge（git）。recast（変わっていないノードは元の原文を再利用）。React の keyed diff |
| focus | 操作が「次に選ぶもの」を返す。ノードを消せば次の兄弟 → 前の兄弟 → 親 | ProseMirror の transaction が selection を運ぶ。Lexical の `$removeNode` |
| Intent の表 | キー・右クリック・ドラッグ・貼り付けを純粋な表で Intent にし、`apply` 1 本へ | エディタの keymap → command |
| 状態と拍（state.ts） | doc・カーソル・履歴と並べて、core の読み（持ち手）・地図の選択の位置・持ち主・選択を EditorState の field に置く。1 トランザクション = 1 サイクル。位置は CodeMirror が編集で写す | Lezer の `syntaxTree`（構文木が StateField）。Redux 型の単一 store |
| 選択の持ち主（core/read の chosen） | 持ち主（フォーカスのあるペイン）が決める。md が持つ間はカーソルから、地図が持つ間は位置から導く値。地図は塗るだけ | VS Code / Obsidian のアウトライン（カーソル追従）+ CodeMirror の選択（位置を編集で写す） |
| 配置と描画と入力（core/map・core/render） | View + 寸法 → Layout → SVG の差分。ペインの出来事も core が受け、判断して host の閉包へ答える。字の実測・画像の URL・色分け・文書と選択の読み書き・ブラウザの API は閉包で外から受け、MoonBit の値は持ち手で往復する | keyed diff（id → 要素）。依存の注入（measure / host）。opaque handle |

### なぜ CodeMirror 6 か

md のプレーンテキストが真実なので、候補はプレーンテキストのエディタ（CodeMirror 6 / Monaco）に
絞られる。Monaco はタッチ非対応で大きい。ProseMirror / Lexical 系は自前の木が真実で「md が真実」と
衝突する。CodeMirror 6 は状態が不変値 + トランザクションで、位置の写しと履歴が同じ拍に在り、
`@codemirror/state` は DOM 無しで動く（node で試験できる）。Lezer の markdown がフェンスの色を
map と同じ表から出す。棚卸しは [ai-docs/codemirror.md](../ai-docs/codemirror.md)。

## 段の間の法則

段ごとに閉じた法則（op × check、op × 合流、読み × 書き）は各 wbtest が持つ。
段をまたぐ前提は、頼る側の段の試験に書く。

- **行の不可侵**（merge） — 行（ラベル・畳み・種類）が同じノードの行は、どの編集の範囲にも入らない。
  地図の選択の位置（ラベルの頭）はこれに頼る
- **隙間の保存**（merge / edit） — 編集を当てた md に、元に無かった連続空行と頭の空行は無い。
  merge の変え方と、edit の全操作の両方で回す
- **形の一致**（edit） — edit の編集を md に当てて読み直せば、apply の後の木と形が一致する
- **focus**（edit） — 読み替えた focus は、後の木で focus だったのと同じ部分木を指す
- **Delete の focus**（edit） — 消した後の focus は消えていない兄弟か祖先（中身なら持ち主）で、
  畳みの中に埋もれていない。無いのは最後の根と文書の散文を消したときだけ
- **id の順 = 文書順**（ts） — 読みは文書順に番号を振るので、id の大小がそのまま文書順。
  select.ts の並べ替えと `Layout.order` はこれに頼る
- **中身は子より前に書かれる**（ts） — ノードの自身の文は地番の頭から最初の子の頭まで。core/read/caret.mbt はこれに頼る
- **選択に居るのは箱のあるものだけ**（chosen） — 畳まれて埋もれたノードは選択に入らない
- **選択を書くのは持ち主の操作だけ**（core/main） — `apply` は focus を選ぶ。`write`（投下・宣言・
  画像の保存）は md を書くだけで選択に触らない

## 同一性は focus 1 本

操作の結果は **focus**（core が返す）。それ以外は同一性を持たず、位置（テキストの中の場所）から
毎サイクル導く。位置は CodeMirror が編集で写す。サイクルを越えて持つ id は無い。
