# CodeMirror 6 — 棚卸し

mmm が乗っている CodeMirror 6 に何が在り、そのうち何を使っているかの事実。
確認日 2026-09-05。版は `@codemirror/state 6.7.1` / `view 6.43.8` / `commands 6.10.4` /
`language 6.12.4` / `lang-markdown 6.5.2` / `language-data 6.5.2` / `theme-one-dark 6.1.3`、
`@lezer/markdown 1.7.2`。出典は公式の System Guide とリファレンス、`node_modules` の実装、
node での実測。

## 設計（System Guide の記述）

- 状態は不変値で、変更はトランザクション。「view の状態は EditorState の値で完全に決まる」
- StateField について: "In almost all cases, it is a really good idea to tie your state into
  the editor-wide state update cycle, because it makes it a lot easier to keep it in sync with
  the rest of the editor state." 例として挙がるのは undo 履歴・構文木・ツールチップの数と位置
- view plugin は「導出でない状態を持つべきでなく、state の上の浅い見方であるのが最良」
- `@codemirror/state` は DOM に依存しない。node で `EditorState.create` と `update` が動く（実測）

## 実装の事実（`@codemirror/state` の `ensureAddr`、node で実測）

- field と facet は**アクセスされた時に計算**される。ある field の `update` の中で
  `tr.state.field(other)` を読むと、`other` の新しい値が先に計算される。extensions に並べた
  順は関係ない
- 循環すると `Cyclic dependency between fields and/or facets` を投げる
- `tr.changes.mapPos(pos, assoc)` — assoc が負なら、その位置への挿入の前に留まる。消去に
  覆われた位置は消去の頭に潰れる（`MapMode.Simple`）。`MapMode.TrackDel` なら null

## `Language.state`（`@codemirror/language` の実装）

- 構文木は StateField。`docChanged` のトランザクションごとに**同期で** parse する
- field の `update` の中で働くのは 20ms まで（`Work.Apply`）。残りは `ViewPlugin` の worker が
  `requestIdleCallback` で続ける（`Work.Slice` 100ms、`ChunkBudget` 3000ms / 30s）
- Marijn（作者）の発言（discuss、2021）: 「ハイライト・畳み・括弧対応など多くの状態が更新時に
  木が在ることに頼るので、parse の debounce は複雑さの代償が高い」

## mmm が使っているもの

| パッケージ | 使っている |
|---|---|
| state | `EditorState` / `Compartment`（テーマ）/ `StateField` + `StateEffect`（薄塗り）/ `ChangeSet.compose`（操作の編集列の合成） |
| view | `EditorView` / `lineNumbers` / `lineWrapping` / `Decoration.mark` / `updateListener` / `scrollIntoView` / `contentAttributes`（aria-placeholder）/ `keymap` |
| commands | `history` / `undo` / `redo` / `defaultKeymap` / `historyKeymap` / `indentWithTab` |
| language | `syntaxHighlighting` / `defaultHighlightStyle`（色付けだけ。md の読みは core） |
| lang-markdown | `markdown({ codeLanguages })`。既定で `markdownKeymap`（Enter でリスト継続、Backspace でマーカー削除）が入る |
| language-data | `languages`（143 言語。map のコードカードと同じ表） |
| theme-one-dark | ダークの配色 |

## 在るが使っていないもの

### state

| 機能 | 何か |
|---|---|
| `RangeSet` / `RangeValue` / `Range` | 位置の集合を変更で写す汎用の器。装飾の下地。`map(changes)` で写る |
| `MapMode` | 写し方 4 種（`Simple` / `TrackDel` / `TrackBefore` / `TrackAfter`） |
| `Annotation` / `Transaction.userEvent` | トランザクションに印。履歴は `input` / `delete` / `undo` / `redo` を付けている |
| `transactionFilter` / `transactionExtender` | トランザクションの差し替え・追加 |
| `allowMultipleSelections` | 複数カーソルの許可。**既定は false** |
| `Text` / `Line` | 行の索引（`lineAt` / `iterLines`）、ロープ |
| `EditorState.phrases` | UI 文言の表 |
| `Prec` | 拡張の優先順 |

### view

| 機能 | 何か |
|---|---|
| `Decoration.widget` / `replace` / `line`、block widget | 行の中・行の間に DOM を挟む、範囲を置き換える、行に class |
| `MatchDecorator` | 正規表現で装飾 |
| `gutter()` / `GutterMarker` | 行番号の隣の帯に印 |
| `showPanel` | エディタの上下の板 |
| `showTooltip` / `hoverTooltip` | 位置に浮く箱、ホバーで出る箱 |
| `layer()` | 文字の下・上に描く層（選択の描画がこれ） |
| `drawSelection` | 自前の選択描画。複数カーソルを描くのに要る |
| `rectangularSelection` / `crosshairCursor` | Alt+ドラッグの矩形選択と、その印 |
| `dropCursor` | ドラッグ中の落とし先 |
| `inputHandler` | 打鍵の直前の差し替え |
| `atomicRanges` | カーソルが中に入れない範囲 |
| `viewport` / `visibleRanges` | いま描いている範囲 |
| `announce` | 読み上げ |
| `domEventHandlers` / `ViewPlugin` | DOM の出来事、view 側の拡張 |
| `theme` / `baseTheme` / `darkTheme` | 見た目（mmm は `dark` の真偽だけ渡す） |

### commands

| 機能 | 何か |
|---|---|
| `invertedEffects` | effect を undo で逆向きに戻す |
| `isolateHistory` | 隣のトランザクションと併合させない |
| `moveLineUp/Down` / `copyLineUp/Down` / `joinLines` / `splitLine` | 行の操作 |
| `selectParentSyntax` / `simplifySelection` | 構文木で選択を広げる、1 つに畳む |
| `toggleLineComment` / `toggleBlockComment` | コメント |

### language / lezer

| 機能 | 何か |
|---|---|
| `syntaxTree` / `ensureSyntaxTree` | Lezer の木（mmm は色付けだけに使い、読みには使わない） |
| `foldService` / `foldGutter` / `codeFolding` | 折り畳み。範囲は関数で与えられる |
| `bracketMatching` / `indentOnInput` / `indentService` | 括弧対応、入力時の字下げ |
| `@lezer/markdown` の拡張 | GFM / Table / TaskList / Strikethrough など |

### 入れていないパッケージ

| パッケージ | 何か |
|---|---|
| `@codemirror/search` | 検索・置換の板、`highlightSelectionMatches`、`searchKeymap` |
| `@codemirror/lint` | 診断（`Diagnostic`）と gutter |
| `@codemirror/autocomplete` | 補完・スニペット・`closeBrackets` |
| `@codemirror/collab` | 版番号で更新を送受する協調編集の下地 |
| `@codemirror/merge` | 差分ビュー（`MergeView` / `unifiedMergeView`） |
| `@codemirror/lsp-client` | LSP |

## 齟齬

- spec.md「二つをまたぐ印」は `Alt+クリック` の複数カーソルを前提に書いているが、
  `allowMultipleSelections` と `drawSelection` が入っていない（issue #66）
- CodeMirror を選んだ理由がリポジトリに無い（v1 の 2026-08-08、git 導入より前。issue #67）

## 出典

- [System Guide](https://codemirror.net/docs/guide/)、[Reference](https://codemirror.net/docs/ref/)
- [@codemirror/state README](https://github.com/codemirror/state/blob/main/src/README.md)
- discuss: [Attach a variable/object on the state](https://discuss.codemirror.net/t/attach-a-variable-object-on-the-state/7457)、
  [Efficient way to get current syntax tree to extract headers](https://discuss.codemirror.net/t/efficient-way-to-get-current-syntax-tree-to-extract-headers/3975)、
  [Language parser performance and debouncing](https://discuss.codemirror.net/t/language-parser-syntax-tree-performance-and-debouncing/3976)
- Obsidian: [Editor extensions](https://marcusolsson.github.io/obsidian-plugin-docs/editor/extensions)、
  [CM6 migration guide](https://obsidian.md/blog/codemirror-6-migration-guide/)
