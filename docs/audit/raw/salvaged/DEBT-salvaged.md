# フェーズ2: 構造的負債

**検証状態**: 6 観点のうち 5 観点で探索パスが完走した。
**「ノード同一性」の観点は探索パス自体がセッション上限で落ちた**ため、
この文書には含まれない — ただしその問いは監査本体で実測により
答えを出している(下記「3. ノードの同一性」を参照)。
また **反証パスは 1 つも完走しなかった**ので、各観点の指摘は
すべて **未検証(探索エージェントの自己申告)** である。
確定しているのは `audit/FINDINGS.md` の F-001〜F-009 と S-001〜S-002 のみ。

## 三つの問いへの回答

### 1. markdown とノードツリー、どちらが単一の真実か / 両方が真実になっている箇所

## 結論

**「文書の内容」に限れば、テキストが単一の真実である。これはコア側で実際にコードによって強制されている。** しかし **「ノードの同一性（id）」「編集履歴」「選択・フォーカス・編集中状態」の 3 つは、テキストからは導出できないツリー側だけの真実**であり、さらに **テキストとツリーが独立に更新される瞬間が 4 箇所ある**。そして **両者の収束を検証する仕組みは、assert・テスト・ランタイム検査のいずれとしても 1 つも存在しない。**

## テキストが真実であることを実際に支えているコード

- `st.text` を書くのは 3 箇所だけ: `apply_sets` (core/doc.mbt:198)、`replay_entry` (core/doc.mbt:421, :426)、`init_doc` (core/api.mbt:100)。`cmd_*` はどれも `st.text` に直接触らず、`Edit` 配列を組んで `apply_sets` に渡すだけ (core/cmds.mbt:242, :302, :493 ほか)。
- `st.nodes` を作るのは `rebuild_nodes` (core/doc.mbt:318) だけ。しかも毎回 `scan_lines(st.text)` + `scan_doc(st.text, lines)` (core/doc.mbt:248-249) で**全文を再走査**する。差分更新は存在しない。
- `hidden` / `group` / `parent` / `sub_end` / `has_content` / `label` はすべて毎回テキストから再計算される (core/doc.mbt:295-320, core/parser.mbt:119-126)。UI 側もこれらを一切記憶していない — `n.hidden` は src/mindmap.ts:318, :388, :396, :590 で読むだけ、`n.group` は :431, :464, :507, :513 で読むだけ、`n.parent` は :299-304, :564 で読むだけ。
- `snapshot()` (core/api.mbt:32-96) には **`text` フィールドが無い**。UI はテキストのコピーを変数に持たず、必要なたびに `core.getText()` を呼ぶ (src/main.ts:105, :207, :306, :403, :552, :613, :730, :852 の 8 箇所)。
- 逆方向 (tree→text) の唯一の直列化は `selection_text` (core/cmds.mbt:597) で、これはクリップボード用の断片切り出しであり文書本体には書き戻らない。

つまり「導出される値」については規律が保たれている。**ただしその安全性は F-002 の「applySnap が無条件に render() を呼ぶ」に完全に依存している** — `sideOf` / `frameOf` (src/mindmap.ts:185-186) や `boxes` / `order` (:183-184) は毎 render で丸ごと作り直される (:492-493, :555, :292) からこそ古くならない。性能修正で render を差分化・デバウンスした瞬間、この規律は崩れる。

## それが破れている箇所

**(A) ツリー側にしか無い情報 — テキストから復元できない**

1. **ノード id**。`st.next_id` (core/doc.mbt:54) は単調カウンタで、`rebuild_nodes` が `id_at` に無い見出しに新規発番する (core/doc.mbt:281-288)。同じテキストでも編集履歴が違えば id 割り当ては変わる。UI 側が id で持つものすべて（`selection` src/main.ts:32、`anchorId` :33、`byId` :31、`boxes` src/mindmap.ts:183、`order` :184、`g.dataset.id` :595、`editingId` :199）がこの「記憶」の下流にある。
2. **Undo/Redo スタック**。`st.undo` / `st.redo` (core/doc.mbt:51-52) は各 `Entry` に `removed` テキスト全文 (core/doc.mbt:21) と `(hs, id)` 対 (core/doc.mbt:29-30) を持つ。これは文書テキストの第 2 のコピーであり、上限も無い。
3. **選択・アンカー・フォーカス・編集中状態**。`selection` / `anchorId` (src/main.ts:32-33)、`st.focus` (core/doc.mbt:55)、`map.editingId` / `editingTag` (src/mindmap.ts:199-200)。どれもテキストに痕跡が無い。

**(B) ツリー側で決まってテキストに戻らない情報**

4. **`move_block` の id 直接書き戻し** (core/cmds.mbt:505-511)。`apply_sets` の**外**で `st.nodes[idx].id = rid` を実行し、続けて `recompute_parents()` (:512) と `refresh_entry_after()` (:513) で既に push 済みの undo エントリを遡って書き換える (core/doc.mbt:174)。ここだけツリーが「導出」ではなく「著述」される。MAP.md:7 が「唯一の例外」と呼ぶ箇所であり、実際に F-006 の 2 つ目のルート問題の発生源でもある。
5. **`sanitize_label` による正規化** (core/cmds.mbt:16-35, :237)。`## &nbsp;&nbsp;&nbsp;a&nbsp;&nbsp;&nbsp;` を map 側でリネームすると `## a` になる。テキストの原形はツリー由来の値に上書きされる（仕様どおりだが、方向はツリー→テキスト）。

**(C) テキストとツリーが独立に更新される瞬間**

6. **`applySnap` の origin `"cm"` 分岐** (src/main.ts:183)。CodeMirror の `EditorState.doc` は CM 自身が、`st.text` は `core.replaceText` が、**それぞれ独立に**更新する。以後どこも突き合わせない。
7. **`onUserEdits` の running delta** (src/main.ts:293-298)。コアが編集を拒否しても delta は進む。
8. **ラベル編集中の `input.value`** (src/mindmap.ts:904, :1274-1279)。`beginEdit` の 1 回だけがテキスト→input 方向で、あとは input→テキストの片方向。
9. **`core.*` 呼び出しから `applySnap` までの間** (src/main.ts:235-236)。`nodes` / `byId` / `boxes` は 1 つ前のテキストを記述している。同期実行なので今は隙間が無いが、`host.paste` (src/main.ts:384-423) と `insertContentLine` を呼ぶポップアップ経路 (src/main.ts:428, :437, :448) は await を挟むため、この隙間が実時間で開く。

**(D) 逆方向の破れ — テキストにあってツリーに無いもの**

10. F-005 のとおり、2 つ目以降の `#` 見出しは `rebuild_nodes` (core/doc.mbt:252-262) で構造から捨てられるが、テキストには残り、前のノードの `sub_end` (core/doc.mbt:310-317) の内側に入る。つまり **text→tree は情報を保存しない写像**であり、ツリー範囲で動く全コマンド（削除・コピー・非表示）が、自分が代表していないテキストを黙って巻き込む。

## 収束を検証している仕組み

**存在しない。** 根拠:

- 全文比較はアプリ全体で 1 箇所だけ、`updateDirty()` の `core.getText() === savedText` (src/main.ts:206-207)。これはコアと**最後に保存したテキスト**の比較で、CodeMirror には一切言及しない。
- `snap.rev` はコアが毎回計算して送っている (core/api.mbt:34-35, core/doc.mbt:207) が、`grep -rn "\.rev" src/` の結果は **0 件**。誰も読んでいない。
- `src/coreApi.ts:37` の `const snap = (s: string): Snapshot => JSON.parse(s);` に try/catch も形状検査も無い。
- `src/editor.ts` が `view.state.doc` を読むのは `setText` の長さ取得 (:151) と `reveal` の範囲チェック (:173) だけ。コアテキストと比較する行は存在しない。
- TypeScript のテストは 0 件（MAP.md:525、`package.json` のテストスクリプトは `test:core` のみ）。コアの 44 件はすべて `get_text()` のバイト比較で、`editSets` を assert するものは 0 件（MAP.md:500）。
- ランタイム assert / dev ガードは `src/` に 1 つも無い（`grep -rn "assert|invariant|console.assert" src/` が 0 件）。

さらに悪いことに、**CodeMirror の updateListener 内の例外は CM が握り潰す**（node_modules/@codemirror/view/dist/index.js:8032-8039 の `try { listener(update) } catch (e) { logException(...) }`）。md ペイン→コアの唯一の経路である `onUserEdits` (src/main.ts:250) はこのリスナの中で走るので、途中で何かが throw すると CM は自分の編集を保持したまま、コアには届かず、`console.error` 以外に何の兆候も出ない。

### 2. 往復で情報が落ちる入力

結論から言うと、落ちるのは大きく 3 系統ある。(1) **パーサがノードとして認めないのに、範囲としてはノードに含まれてしまう行** —— 2 つ目以降の `#`、生 HTML 中の `#` 行、最初の見出しより前のテキスト。(2) **`<!--` / `-->` / `---` という「行そのものがマーカーになる」テキスト** —— 本文中にこれらの行があると、hide/show や group 判定がユーザの行を巻き込んで削除・誤読する。(3) **書式の正規化** —— rename が見出し行を、move/copy がブロック間の空行を、paste が改行コードを潰す。以下すべて `core/_build/js/release/build/js/js.js` を Node から直接叩いて確認した実測値である。

**(1) 認識されない行が範囲に入る。** `rebuild_nodes` は見出しの配列 `heads` からしかノードを作らず (core/doc.mbt:279-308)、`sub_end` は「自分以下の深さの次の *採用された* 見出しの hs」でしかない (core/doc.mbt:309-317)。だから最初の見出しより前のテキストは**どのノードの範囲にも入らない**。`---\ntitle: x\n---\n\n# R\n\n## A\n` を読ませると nodes は `R(hs=18)` と `A(hs=23)` だけで、`selection_text` に全 id を渡しても返るのは `"# R\n\n## A\n"` (core/cmds.mbt:597-618)。マップペインには Mod+A で全選択 (src/mindmap.ts:1483-1489)、Mod+C でコピー (src/mindmap.ts:1491) があるので、「全部選んでコピー → 新規文書に貼る」で frontmatter と前書きが消える。逆に 2 つ目以降の `#` は `seen_root` で構造から捨てられる (core/doc.mbt:252-262) のに、前ノードの `sub_end` の内側には残る。`# One\n\ntext\n\n# Two\n\nbody of two\n\n## Child\n` は nodes が `One(subEnd=42=EOF)` と `Child` の 2 個で、`One` を削除すると文書が `""` になる（実測）。

**(2) マーカー行。** `is_marker_line` は行の前後空白を落として `<!--` / `-->` と完全一致するかだけを見る (core/parser.mbt:137-147)。4 スペース字下げしたコードブロック中の `-->` も、リスト外の裸の `-->` も、すべてマーカーになる。`cmd_toggle_hidden` の「入れ子拒否」ガード (core/cmds.mbt:661-667) は `st.hide_regions` に載った *対になった* 領域しか見ないので、**閉じていない `-->` 単独行は素通り**する。結果、hide → show でユーザの行が消える（実測: `# R\n\n## A\n\narrow -->\n-->\n\n## B\n` が `# R\n\n## A\n\narrow -->\n\n-->\n## B\n` になる）。`---` も同様で、`is_separator` (core/parser.mbt:152-173) が setext 見出しの下線を group 区切りと誤読し、`move_block` はその `---` を置いてけぼりにして別ノードの境界に付け替える。

**(3) 正規化。** `cmd_rename` は `hashes(depth) + " " + sanitize_label(label)` で見出し行を丸ごと書き直し (core/cmds.mbt:237)、マップのラベル編集は 1 打鍵ごとに rename を発行する (src/mindmap.ts:1273-1276)。`move_block` と `selection_text` は末尾改行を全部剥がして 1 行の空行に固定する (core/cmds.mbt:462-477, :604-615)。paste は CRLF を LF に潰したうえ (src/main.ts:401)、`relevel` の再結合が `"\n"` 固定 (src/relevel.ts:54)、prefix/suffix も `"\n"` リテラル (src/main.ts:416-420) なので CRLF 文書が混在改行になる。

なお `moveNodes(id, rootId, 1)` は `# S2\n\n# Two\n\nbody\n\n# One\n\n## S1\n` を作り、元の root `One` がマップから消える（F-006 の実測例）。今日は src/mindmap.ts:1641-1645 が depth-1 への drop を pos=0 に強制するので UI からは届かない。

### 3. ノードの同一性は何で担保され、どの操作で崩れるか

この観点の探索パスは実行されなかったが、監査本体で実測により確定させた:

- **同一性の担保**: ノード id は「見出し行の開始文字オフセット」を代理キーとして
  編集をまたいで引き継がれる。`core/doc.mbt` の `map_offset` が編集前オフセットを
  編集後オフセットへ写し、`rebuild_nodes` が `id_at` マップで再利用する。
  undo/redo では Entry が `before`/`after` の (hs, id) スナップショットを持ち、
  `replay_entry` がそれを使って復元する。
- **崩れる操作**(実測):
  | 操作 | 編集の形 | id | 根拠 |
  |---|---|---|---|
  | rename | 見出し行の置換 | **保存** | C8 が通る |
  | indent | 見出し先頭に `#` を挿入(改行で終わらない) | **保存** | C9a が通る |
  | **outdent** | 見出し先頭から `#` を削除 | **消失** | C9b が失敗 / F-004 |
  | move(ルート以外) | ブロックの切り貼り + `at_hs` で復元 | 保存 | C10a はルート絡み以外では通る |
  | **move(ルート兄弟へ)** | 深さ1昇格 → 重複ルート | **ノードごと消失** | C10b が失敗 / F-006 |
  | undo / redo | 逆編集の適用 | **保存** | C11 が通る |
- **規則の非対称性**: `map_offset` は「改行で終わらない純挿入 = 行の書き換え =
  位置は生存」と扱うが、対になる「純削除」は無条件に `-1`(破壊)とする。
  同じ操作の逆向きが非対称であることが F-004 の直接原因。

---

## 観点: 単一の真実はどちらか

## 結論

**「文書の内容」に限れば、テキストが単一の真実である。これはコア側で実際にコードによって強制されている。** しかし **「ノードの同一性（id）」「編集履歴」「選択・フォーカス・編集中状態」の 3 つは、テキストからは導出できないツリー側だけの真実**であり、さらに **テキストとツリーが独立に更新される瞬間が 4 箇所ある**。そして **両者の収束を検証する仕組みは、assert・テスト・ランタイム検査のいずれとしても 1 つも存在しない。**

## テキストが真実であることを実際に支えているコード

- `st.text` を書くのは 3 箇所だけ: `apply_sets` (core/doc.mbt:198)、`replay_entry` (core/doc.mbt:421, :426)、`init_doc` (core/api.mbt:100)。`cmd_*` はどれも `st.text` に直接触らず、`Edit` 配列を組んで `apply_sets` に渡すだけ (core/cmds.mbt:242, :302, :493 ほか)。
- `st.nodes` を作るのは `rebuild_nodes` (core/doc.mbt:318) だけ。しかも毎回 `scan_lines(st.text)` + `scan_doc(st.text, lines)` (core/doc.mbt:248-249) で**全文を再走査**する。差分更新は存在しない。
- `hidden` / `group` / `parent` / `sub_end` / `has_content` / `label` はすべて毎回テキストから再計算される (core/doc.mbt:295-320, core/parser.mbt:119-126)。UI 側もこれらを一切記憶していない — `n.hidden` は src/mindmap.ts:318, :388, :396, :590 で読むだけ、`n.group` は :431, :464, :507, :513 で読むだけ、`n.parent` は :299-304, :564 で読むだけ。
- `snapshot()` (core/api.mbt:32-96) には **`text` フィールドが無い**。UI はテキストのコピーを変数に持たず、必要なたびに `core.getText()` を呼ぶ (src/main.ts:105, :207, :306, :403, :552, :613, :730, :852 の 8 箇所)。
- 逆方向 (tree→text) の唯一の直列化は `selection_text` (core/cmds.mbt:597) で、これはクリップボード用の断片切り出しであり文書本体には書き戻らない。

つまり「導出される値」については規律が保たれている。**ただしその安全性は F-002 の「applySnap が無条件に render() を呼ぶ」に完全に依存している** — `sideOf` / `frameOf` (src/mindmap.ts:185-186) や `boxes` / `order` (:183-184) は毎 render で丸ごと作り直される (:492-493, :555, :292) からこそ古くならない。性能修正で render を差分化・デバウンスした瞬間、この規律は崩れる。

## それが破れている箇所

**(A) ツリー側にしか無い情報 — テキストから復元できない**

1. **ノード id**。`st.next_id` (core/doc.mbt:54) は単調カウンタで、`rebuild_nodes` が `id_at` に無い見出しに新規発番する (core/doc.mbt:281-288)。同じテキストでも編集履歴が違えば id 割り当ては変わる。UI 側が id で持つものすべて（`selection` src/main.ts:32、`anchorId` :33、`byId` :31、`boxes` src/mindmap.ts:183、`order` :184、`g.dataset.id` :595、`editingId` :199）がこの「記憶」の下流にある。
2. **Undo/Redo スタック**。`st.undo` / `st.redo` (core/doc.mbt:51-52) は各 `Entry` に `removed` テキスト全文 (core/doc.mbt:21) と `(hs, id)` 対 (core/doc.mbt:29-30) を持つ。これは文書テキストの第 2 のコピーであり、上限も無い。
3. **選択・アンカー・フォーカス・編集中状態**。`selection` / `anchorId` (src/main.ts:32-33)、`st.focus` (core/doc.mbt:55)、`map.editingId` / `editingTag` (src/mindmap.ts:199-200)。どれもテキストに痕跡が無い。

**(B) ツリー側で決まってテキストに戻らない情報**

4. **`move_block` の id 直接書き戻し** (core/cmds.mbt:505-511)。`apply_sets` の**外**で `st.nodes[idx].id = rid` を実行し、続けて `recompute_parents()` (:512) と `refresh_entry_after()` (:513) で既に push 済みの undo エントリを遡って書き換える (core/doc.mbt:174)。ここだけツリーが「導出」ではなく「著述」される。MAP.md:7 が「唯一の例外」と呼ぶ箇所であり、実際に F-006 の 2 つ目のルート問題の発生源でもある。
5. **`sanitize_label` による正規化** (core/cmds.mbt:16-35, :237)。`## &nbsp;&nbsp;&nbsp;a&nbsp;&nbsp;&nbsp;` を map 側でリネームすると `## a` になる。テキストの原形はツリー由来の値に上書きされる（仕様どおりだが、方向はツリー→テキスト）。

**(C) テキストとツリーが独立に更新される瞬間**

6. **`applySnap` の origin `"cm"` 分岐** (src/main.ts:183)。CodeMirror の `EditorState.doc` は CM 自身が、`st.text` は `core.replaceText` が、**それぞれ独立に**更新する。以後どこも突き合わせない。
7. **`onUserEdits` の running delta** (src/main.ts:293-298)。コアが編集を拒否しても delta は進む。
8. **ラベル編集中の `input.value`** (src/mindmap.ts:904, :1274-1279)。`beginEdit` の 1 回だけがテキスト→input 方向で、あとは input→テキストの片方向。
9. **`core.*` 呼び出しから `applySnap` までの間** (src/main.ts:235-236)。`nodes` / `byId` / `boxes` は 1 つ前のテキストを記述している。同期実行なので今は隙間が無いが、`host.paste` (src/main.ts:384-423) と `insertContentLine` を呼ぶポップアップ経路 (src/main.ts:428, :437, :448) は await を挟むため、この隙間が実時間で開く。

**(D) 逆方向の破れ — テキストにあってツリーに無いもの**

10. F-005 のとおり、2 つ目以降の `#` 見出しは `rebuild_nodes` (core/doc.mbt:252-262) で構造から捨てられるが、テキストには残り、前のノードの `sub_end` (core/doc.mbt:310-317) の内側に入る。つまり **text→tree は情報を保存しない写像**であり、ツリー範囲で動く全コマンド（削除・コピー・非表示）が、自分が代表していないテキストを黙って巻き込む。

## 収束を検証している仕組み

**存在しない。** 根拠:

- 全文比較はアプリ全体で 1 箇所だけ、`updateDirty()` の `core.getText() === savedText` (src/main.ts:206-207)。これはコアと**最後に保存したテキスト**の比較で、CodeMirror には一切言及しない。
- `snap.rev` はコアが毎回計算して送っている (core/api.mbt:34-35, core/doc.mbt:207) が、`grep -rn "\.rev" src/` の結果は **0 件**。誰も読んでいない。
- `src/coreApi.ts:37` の `const snap = (s: string): Snapshot => JSON.parse(s);` に try/catch も形状検査も無い。
- `src/editor.ts` が `view.state.doc` を読むのは `setText` の長さ取得 (:151) と `reveal` の範囲チェック (:173) だけ。コアテキストと比較する行は存在しない。
- TypeScript のテストは 0 件（MAP.md:525、`package.json` のテストスクリプトは `test:core` のみ）。コアの 44 件はすべて `get_text()` のバイト比較で、`editSets` を assert するものは 0 件（MAP.md:500）。
- ランタイム assert / dev ガードは `src/` に 1 つも無い（`grep -rn "assert|invariant|console.assert" src/` が 0 件）。

さらに悪いことに、**CodeMirror の updateListener 内の例外は CM が握り潰す**（node_modules/@codemirror/view/dist/index.js:8032-8039 の `try { listener(update) } catch (e) { logException(...) }`）。md ペイン→コアの唯一の経路である `onUserEdits` (src/main.ts:250) はこのリスナの中で走るので、途中で何かが throw すると CM は自分の編集を保持したまま、コアには届かず、`console.error` 以外に何の兆候も出ない。

### D-1 / `core/doc.mbt:54, core/doc.mbt:281-288, core/api.mbt:104, src/mindmap.ts:199, src/main.ts:180-204` / 未検証

**ノード id はテキストから導出できない — ツリー側だけの真実であり、文書読み込みで番号空間ごと作り直される**

**根拠**: core/doc.mbt:281-288 —
    let id = match id_at.get(h.hs) {
      Some(old) => old
      None => { let fresh = st.next_id; st.next_id = st.next_id + 1; fresh }
    }
core/api.mbt:104 (init_doc) — `st.next_id = 1`
src/main.ts:186-195 (applySnap) は `selection` と `anchorId` を byId で刈り込むが、`map.editingId` には一切触れない。`grep -an "editingId" src/*.ts` の結果、applySnap 側からの参照は 0 件。

**負債**: 「テキストが単一の真実」と言いながら、ノードの同一性だけはテキストに一切の表現を持たない純粋な記憶である。同じバイト列でも編集履歴が違えば id 割り当てが変わる。そして UI が id で持つ状態（selection, anchorId, byId, boxes, order, g.dataset.id, editingId, undo エントリの (hs,id) 対）はすべてこの記憶の下流にあるのに、寿命管理は applySnap の刈り込み 1 箇所（src/main.ts:186-195）にしかなく、editingId はそこから漏れている。

**このままだと顕在化するバグ**: ラベル編集を開いたまま .md をウィンドウにドロップする。drop ハンドラ (src/main.ts:857-878) は input をブラーせず、文書がクリーンなら confirmDiscard (src/main.ts:612-615) はダイアログも出さずに true を返す。loadText → core.initDoc で next_id が 1 に戻る (core/api.mbt:104)。map.editingId は旧文書の id（例: 7）のまま、input も display:block のまま残る。次の 1 打鍵で host.rename(7, ...) が走り、新文書に id 7 が存在すれば **まったく無関係のノードの見出しが書き換わる**。存在しなければ cmd_rename が find_node<0 で黙って return し (core/cmds.mbt:232-235)、ユーザは何も起きないまま入力を続ける。

**修正コスト**: editingId の刈り込みを applySnap に足すだけなら 3〜4 行（src/main.ts:195 付近に `if (map.isEditing() && !byId.has(map.editingId)) map.endEdit();`）。loadText 側で無条件に endEdit するなら 1 行。id 空間そのものを直すのは非現実的で、寿命管理側で閉じるのが妥当。

### D-2 / `src/main.ts:183, src/main.ts:206-207, core/api.mbt:32-96, core/api.mbt:126-132` / 未検証

**applySnap の origin "cm" 分岐 — CodeMirror の doc とコアの st.text が独立に進み、以後どこも突き合わせない**

**根拠**: src/main.ts:183 —
    if (origin !== "cm" && origin !== "load") editor.applySets(snap.editSets);
core/api.mbt:126-132 (replace_text) —
    if from < 0 || to > n || from > to { return snapshot() }
    let removed = sub(st.text, from, to)
    if removed == insert { return snapshot() }
snapshot() (core/api.mbt:32-96) は rev/focus/canUndo/canRedo/editSets/nodes の 6 キーのみ。**text キーは存在しない**。

**負債**: md ペインでのタイプ入力という最も頻度の高い経路で、文書が 2 つの独立した権威（CM の EditorState.doc と st.text）に分裂する。分裂したことを検出する手段が意図的に潰されている: snapshot に text が無く、snap.rev は送られているのに src/ 全体で 0 回しか読まれず（`grep -rn "\.rev" src/` = 0 件）、src/editor.ts が state.doc を読むのは長さチェック 2 箇所（:151, :173）のみ。さらに replace_text の 2 つの早期 return は **編集セットが空の正常な snapshot** を返すので、TS 側から「拒否された」と「何も変わらなかった」を区別できない。

**このままだと顕在化するバグ**: 一度でも両者がずれると自己修復しない。CM 側だけが長い文書を持った状態で末尾付近を編集すると、その編集の to が core の st.text.length() を超え、replace_text が core/api.mbt:126-128 で無音で拒否する。origin が "cm" なので editSets による訂正も入らない。ユーザは md ペインに正しい文章が見えているのに、Ctrl+S は core.getText() を書き (src/main.ts:552)、persistNow も core.getText() を書く (src/main.ts:105) ため、**ディスクの .md にも localStorage のバックアップにも、その編集が 1 文字も入らない**。dirty ドットは core 側のテキストだけを見る (src/main.ts:207) ので消えたままのこともある。

**修正コスト**: 検出だけなら applySnap 末尾に 3〜4 行（dev ビルド限定で core.getText() と editor.view.state.doc.toString() を比較して console.error）。自動復旧まで入れるなら editor.setText(core.getText()) による再同期を足して 10 行程度。

### D-3 / `src/main.ts:293-299, core/api.mbt:126-132, src/editor.ts:132-140` / 未検証

**onUserEdits の running delta がコアの拒否を考慮せず、1 件の拒否で以降の全編集がずれる**

**根拠**: src/main.ts:293-299 —
    let delta = 0;
    let snap: Snapshot | null = null;
    for (const e of edits) {
      snap = core.replaceText(e.from + delta, e.to + delta, e.insert, tag);
      delta += e.insert.length - (e.to - e.from);
    }
    if (snap) applySnap(snap, "cm");
core.replaceText の戻り値 Snapshot には成否を示すフィールドが無い (core/api.mbt:32-96)。

**負債**: delta はコアが編集を適用したかどうかに関係なく無条件に進む。edits は tr.changes.iterChanges が返すトランザクション適用**前**座標 (src/editor.ts:133-139) なので、delta による繰り上げは「直前の編集がすべて適用された」ことを前提にしている。その前提を検証する手段が呼び出し側に無い（前項のとおり戻り値からは判別不能）。

**このままだと顕在化するバグ**: マルチカーソル編集や CodeMirror の置換系コマンドが 1 トランザクションで複数の EditOp を出すとき、先頭の 1 件が core/api.mbt:126-128 で範囲外拒否されると、後続の全編集が「先頭が適用された前提」の delta で投入され、**コアのテキスト内の見当違いの位置に文字が挿入される**。origin が "cm" なので CM 側は訂正されない。結果として map ペインは壊れたテキストから導出されたツリーを描き、md ペインは正常なテキストを表示する — 同じ画面の左右で違う文書が見えるが、例外も警告も出ない。

**修正コスト**: replaceText の戻り値に適用可否を載せるならコア側 (core/api.mbt:119-135) と coreApi の型 (src/coreApi.ts:26-33, :42-43) で 10 行程度。呼び出し側で snap.rev の増分を見て中断するだけなら src/main.ts:295-298 に 3 行。

### D-4 / `src/editor.ts:113-142, src/main.ts:250-299, src/main.ts:198-203, node_modules/@codemirror/view/dist/index.js:8031-8039` / 未検証

**md ペイン→コアの唯一の経路が CodeMirror の updateListener の中にあり、例外は console.error に握り潰される**

**根拠**: node_modules/@codemirror/view/dist/index.js:8031-8039 —
    if (!update.empty)
      for (let listener of this.state.facet(updateListener)) {
        try { listener(update); }
        catch (e) { logException(this.state, e, "update listener"); }
      }
src/main.ts:198-203（applySnap の後半、この listener の中で走る） —
    map.render();
    if (selChanged) syncSelectionViews(false);
    btnUndo.disabled = !snap.canUndo;
    btnRedo.disabled = !snap.canRedo;
    updateDirty();
    schedulePersist();

**負債**: onUserEdits は「編集をコアへ転送する」だけでなく、applySnap 経由で map.render()（src/mindmap.ts:290、SVG 全再構築）と syncSelectionViews（src/main.ts:210、CM への dispatch）まで同期実行する。この全部が CM の listener 内なので、どこで throw しても CM は自分の編集を保持したまま握り潰す。しかも applySnap は throw した時点で打ち切られ、undo ボタン状態・dirty ドット・localStorage 書き込み（src/main.ts:200-203）がまとめてスキップされる。

**このままだと顕在化するバグ**: render 経路には非 null アサーションが並んでいる（src/mindmap.ts:466 `subV.get(kids[i].id)!`、:488 `boxes.get(id)!`、:526、:536）。move_block の id 書き戻し（core/cmds.mbt:505-511）が想定外の状態を作って親子関係に閉路や重複 id が生じると、calcV の再帰（src/mindmap.ts:436-445）がスタックオーバーフローするか centerOf が undefined を読んで TypeError になる。どちらも logException で console に出るだけ。**その打鍵以降 schedulePersist が呼ばれないので localStorage が更新されなくなり、次のリロードで数分ぶんの編集が静かに消える**。ユーザから見ればアプリは動き続けている。（正確な throw の引き金は 未確認 — 実行して再現させるのが確実。握り潰し自体は上記の CM ソースで確認済み。）

**修正コスト**: onUserEdits の本体を try/catch で包み、catch で flashFilename に出す + applySnap の後半（永続化・ボタン状態）を finally に逃がす、で 10〜15 行。根治は applySnap を listener から出して microtask に逃がす設計変更で、影響範囲は src/main.ts:180-204 と全 origin。

### D-5 / `core/cmds.mbt:499-515, core/doc.mbt:166-177, core/cmds.mbt:554-566, src/main.ts:237-241` / 未検証

**move_block だけが apply_sets の外でツリーを直接書き換え、失敗しても黙って通過する**

**根拠**: core/cmds.mbt:499-514 —
    let base = new_hs + prefix_len
    let at_hs : Map[Int, Int] = Map([])
    for idx = 0; idx < st.nodes.length(); idx = idx + 1 { at_hs[st.nodes[idx].hs] = idx }
    for r in rels {
      let (rid, rel) = r
      match at_hs.get(base + rel) {
        Some(idx) => st.nodes[idx].id = rid
        None => ()          // ← 失敗が無音
      }
    }
    recompute_parents()
    refresh_entry_after()
    st.focus = old_id       // ← 上の照合が全滅しても無条件に設定
core/doc.mbt:173-175 (refresh_entry_after) — `st.undo[st.undo.length() - 1].after = id_pairs()` : push 済みの undo エントリを遡って書き換える。

**負債**: システム全体で唯一、ツリーが「テキストから導出された結果」ではなく「オフセット算術で著述された結果」になる箇所。base + rel が 1 でもずれると None 分岐に落ちて id が引き継がれず、しかも例外も戻り値も無い。加えて undo スタックが不変でなくなる（refresh_entry_after が過去のエントリを書き換える）ので、「undo エントリは適用時点のスナップショット」という他の全コードの前提が崩れている。

**このままだと顕在化するバグ**: 複数ノードのドラッグ移動（core/cmds.mbt:554-566、MAP.md:508 のとおりテスト 0 件）では、1 ノード移動するたびに `anchor = st.focus` でアンカーを更新する。at_hs の照合が外れると st.focus は old_id のままだが実際のノードは別 id を持っているので、次の周回の `find_node(anchor)` が -1 を返して `continue`（core/cmds.mbt:535-537）— **選択した 5 ノードのうち 1 つだけが移動し、残り 4 つは黙って移動しない**。全体が 1 トランザクション（begin_tx/commit_tx, :528/:568）なので undo は全部戻し、ユーザには「何が動いて何が動かなかったか」が最後まで分からない。UI 側も runCmd が `byId.has(snap.focus)` (src/main.ts:237) で弾いて選択が空になるだけで、エラーは出ない。

**修正コスト**: 照合失敗を検出して返すようにするなら move_block に成否の戻り値を足して cmd_move / cmd_reorder / cmd_outdent の 3 呼び出し元を直す、40 行程度。最小限なら None 分岐でカウントを取り、1 件でも外れたら st.focus = -1 にする 5 行。

### D-6 / `src/mindmap.ts:61-68, src/mindmap.ts:475-482, src/mindmap.ts:555, src/mindmap.ts:900-904, src/mindmap.ts:931-943, src/mindmap.ts:1311-1321` / 未検証

**MindMap.boxes が前回 render 時点の NodeInfo を丸ごと抱え、当たり判定・ドラッグ・ラベル初期値の全部がそこから来る**

**根拠**: src/mindmap.ts:61-68 —
    interface Box { n: NodeInfo; x: number; y: number; w: number; h: number; rows: CardRow[]; }
src/mindmap.ts:900-904 (beginEdit) —
    const b = this.boxes.get(id);
    if (!b) return;
    ...
    this.editor.value = b.n.label;      // ← host.nodes() ではなく boxes 経由
src/mindmap.ts:1311-1321 (nodeAt) は this.order と this.boxes だけを見る。

**負債**: boxes はジオメトリだけでなく NodeInfo への参照ごと保持する「ツリーの第 2 のコピー」で、更新は render() でしか起きない (src/mindmap.ts:555)。nodeAt / startDrag / updateDrop / ensureVisible / positionEditor / updatePlus / exportSvg がすべてこれを読む。今それが安全なのは F-002 のとおり applySnap が render() を無条件に呼ぶ (src/main.ts:198) からだけであり、**性能問題（5000 ノードで 70.2ms/打鍵、no-op undo 134.7ms）の修正と、この正しさの前提が正面から衝突している**。

**このままだと顕在化するバグ**: render を差分化またはデバウンスした瞬間、boxes は設計上古くなる。ドロップ処理 updateDrop (src/mindmap.ts:1620-1692) は boxes の座標からターゲット id と pos を決め、host.move(ids, target, pos) を呼ぶ (src/main.ts:371-373)。古い boxes に基づく target/pos は、コア側では tn.hs / tn.sub_end という**現在のテキストオフセット**に翻訳される (core/cmds.mbt:544-550)。つまり「ユーザが見て狙った場所」ではなく「1 世代前のレイアウトの場所」にブロックが移動する。しかも移動はテキスト編集として完全に正当なので、例外もガードも発火しない。F-006 の 2 つ目のルート生成もこの経路（src/mindmap.ts:1641 の pos=0 強制だけが今それを防いでいる）。

**修正コスト**: Box に NodeInfo 参照ごと持たせるのをやめて id だけにし、読み手が host.nodes() から引き直す形にすると src/mindmap.ts の 8 箇所前後（:904, :963, :1620 ほか）で 30〜40 行。render 差分化に着手する前にやらないと意味がない。

### D-7 / `src/mindmap.ts:243-246, src/mindmap.ts:904, src/mindmap.ts:1274-1279, src/main.ts:336-338, core/cmds.mbt:16-35, core/cmds.mbt:231-247` / 未検証

**node-editor の input.value は見出し行の 3 つ目のコピーで、テキスト→input は beginEdit の 1 回きり**

**根拠**: src/mindmap.ts:1274-1279 —
    this.editor.addEventListener("input", () => {
      if (this.editingId !== -1) {
        this.host.rename(this.editingId, this.editor.value, this.editingTag);
        this.positionEditor();
      }
    });
src/main.ts:336-338 —
    rename(id, label, tag) {
      applySnap(core.renameNode(id, label, tag), "map");
    },
core/cmds.mbt:232-241 —
    let i = find_node(id)
    if i < 0 { return }                       // ← 無音
    let line = hashes(nd.depth) + " " + sanitize_label(label)
    let old = sub(st.text, nd.hs, nd.he)
    if line == old { return }                 // ← 無音

**負債**: ラベルは st.text の見出し行（sanitize_label で trim 済み）、Box.n.label（前回 render 時点）、input.value（生の入力）の 3 箇所にある。テキストから input への流れは beginEdit (src/mindmap.ts:904) の 1 回だけで、以後は input→テキストの片方向。cmd_rename には無音の早期 return が 2 つあり、どちらもフィードバックが無いので input.value がテキストに存在しない内容を保持し続けうる。さらに host.rename は **byId.has(id) ガードを持たない唯一のミューテータ**である — addChild (src/main.ts:313)、addSibling (:318)、addSiblingBefore (:323)、addParent (:328)、addLink (:427)、addCode (:436)、addDrawing (:447)、editRequested (:459) はすべて持っている。

**このままだと顕在化するバグ**: editingId が死んだ id を指した状態（前掲の loadText 経路、あるいは今後 id を失う操作が増えたとき）で、ユーザはラベルを最後まで打ち込める。cmd_rename は find_node<0 で return し (core/cmds.mbt:233-235)、host.rename もガードが無いので通し、applySnap は editSets が空の snapshot を普通に処理して map.render() まで走る。**入力欄には打った文字が見えているのに、文書には 1 文字も入っていない**。Enter を押すと commitEdit → endEdit で入力欄が消え、打った内容が丸ごと消滅する。undo しても戻らない（そもそも undo エントリが作られていない）。

**修正コスト**: host.rename に byId.has(id) ガードを 1 行足す。加えて cmd_rename の失敗を snapshot の focus か新フィールドで返して map 側で endEdit する、で 10 行程度。

### D-8 / `core/doc.mbt:251-262, core/doc.mbt:309-317, core/cmds.mbt:279-302, core/cmds.mbt:597-624` / 未検証

**text→tree が情報を保存しない写像である（F-005）ため、ツリー範囲で動くコマンドが自分の代表しないテキストを巻き込む**

**根拠**: core/doc.mbt:252-262 —
    let heads : Array[Heading] = []
    let mut seen_root = false
    for h in all {
      if h.depth == 1 { if seen_root { continue }; seen_root = true }
      heads.push(h)
    }
core/doc.mbt:311-317（sub_end はこの heads だけから決まる） —
    while open.length() > 0 && nodes[open[open.length()-1]].depth >= nodes[i].depth {
      nodes[open.unsafe_pop()].sub_end = nodes[i].hs
    }

**負債**: 「テキストが真実、ツリーは導出」は導出が全単射である限り安全な設計だが、ここでは全単射ではない。捨てられた depth-1 見出しはテキストに残ったまま、直前ノードの sub_end の内側（core/doc.mbt:310-317）に取り込まれる。cmd_delete は [hs, sub_end) をそのまま削除範囲にし (core/cmds.mbt:281)、selection_text も同じ範囲を切り出し (core/cmds.mbt:597 以降)、cmd_toggle_hidden も同じ範囲を <!-- --> で囲む (core/cmds.mbt:675-683)。ツリーに存在しないものをツリー操作が動かしている。

**このままだと顕在化するバグ**: F-005 で確認済みのとおり、2 つ目の `# ` ブロックを持つ文書で直前ノードを削除すると、選択もしていない `#` ブロックがまるごと消える。README の「行は保存される」は成立しない。今後 depth-1 の重複が起きやすくなる変更（F-006 の 2 つ目のルート生成、あるいは add_root のガード core/cmds.mbt:218-222 の緩和）を入れると、この「見えないブロック」が日常的に生成されるようになり、削除・コピー・非表示の 3 コマンドすべてが不可視の巻き添えを起こす。テストは 1 件（core/core_test.mbt:256 duplicate roots are ignored as structure）あるが、それは「id 2 が c になる」ことしか見ておらず、巻き添え削除は検証していない。

**修正コスト**: 捨てた見出しを Node として持ち（例: depth-1 だが構造から外れたことを示すフラグ付き）sub_end の計算に参加させるのが筋。core/doc.mbt:251-320 と snapshot のノードキー（core/api.mbt:70-90）、src/mindmap.ts の描画分岐に波及して 60〜100 行。

### D-9 / `src/main.ts:206-207, src/coreApi.ts:37, core/api.mbt:32-96, src/editor.ts:151, src/editor.ts:173, package.json:6-13` / 未検証

**収束を検証する仕組みが assert・テスト・ランタイム検査のいずれにも存在しない**

**根拠**: src/main.ts:206-207（アプリ唯一の全文比較） —
    function updateDirty(): void {
      elDirty.hidden = core.getText() === savedText;
    }
src/coreApi.ts:37（唯一の信頼境界、検査ゼロ） —
    const snap = (s: string): Snapshot => JSON.parse(s);
検証コマンド: `grep -rn "\.rev" src/` = 0 件（rev は core/api.mbt:34 で毎回送られている）。`grep -rn "assert|invariant|console.assert" src/` = 0 件。src/editor.ts が view.state.doc を読むのは :151 と :173 の length 参照のみ。

**負債**: コアとテキスト、コアと CodeMirror、コアと boxes の 3 つの境界すべてで、一致を主張するコードが 0 行。コア側の 44 テスト（core/core_test.mbt）はすべて get_text() のバイト比較で、editSets を assert するものは 0 件（MAP.md:500）。TypeScript のテストは 1 件も無い（package.json:6-13、devDependencies は typescript と vite のみ）。つまり本項の他の 8 件はどれも、起きたことに誰も気づけない。

**このままだと顕在化するバグ**: 上記のどの経路でずれても、症状が出るのは Ctrl+S の後になる。saveFile は core.getText() を書き (src/main.ts:552)、成功後 savedText = text (src/main.ts:582) で dirty ドットを消す。persistNow も core.getText() を書く (src/main.ts:105)。したがって **ディスクの .md も localStorage のバックアップも同じ「コア側の」テキストになり、CodeMirror にしか無かった編集はどこにも残らない**。ユーザは md ペインに正しい文章が表示されたまま保存し、次に開いたときに一部が欠けているのを見る — 再現手順も原因も特定できない形で。

**修正コスト**: applySnap の末尾に dev 限定の一致チェックを 4 行入れるだけで、本項の 2・3・4・6 の全部が初回発生時に console に出る:
    if (import.meta.env.DEV && core.getText() !== editor.view.state.doc.toString()) console.error("core/CM diverged", snap.rev);
テスト基盤（vitest + coreApi のモック）を入れて applySnap の origin 分岐を固定するなら 200 行規模。

---

## 観点: 抽象の漏れと拡張の詰まり

**層の境界はどこで漏れているか。**

漏れは 4 段ある。

(1) *コア → TS の境界に検査が無い*。`src/coreApi.ts:37` は `const snap = (s: string): Snapshot => JSON.parse(s)` の 1 行で、try/catch も形状検査も無い。しかも `src/coreApi.ts:5` が import するのは `tsconfig.json:15` の `include: ["src"]` の**外**の `../core/_build/js/release/build/js/js.js` で、`allowJs: true`(tsconfig.json:10)かつ `checkJs` 無しなので `mbt.*` は全て `any`。`src/coreApi.ts:39-66` の 18 個のシグネチャは「宣言」であって検査ではない。api.mbt 側の JSON は `StringBuilder` の手組み(core/api.mbt:32-96)なので、フィールド名を 1 つ変えても TS のビルドは通り、実行時に `undefined` が座標計算へ流れる。

(2) *コアが計算済みの情報を捨て、TS が再導出している*。ノードの「自分自身のコンテンツ範囲」はコアが持っている: `Heading.content_start`(core/parser.mbt:40, 代入は :123)と `content_end`(core/doc.mbt:290-294)。しかし snapshot が輸出するのはその真偽値化された `hasContent` だけ(core/api.mbt:84-85)。結果として同じ範囲計算が TS に 2 回、逐語コピーで存在する:
- `src/mindmap.ts:324-327` — `i + 1 < nodes.length && nodes[i + 1].hs < n.subEnd ? nodes[i + 1].hs : n.subEnd`
- `src/main.ts:726-729` — 同一式(変数名 `at`)

(3) *`docText()` がビューに生の markdown を渡している*。`MapHost.docText()`(src/mindmap.ts:16)→ `core.getText()`(src/main.ts:306)。`render()` は毎フレーム全文を受け取り(src/mindmap.ts:313)、全ノードに対して独立した markdown スキャナを回す(src/mindmap.ts:315-379)。1 打鍵ごとに、コアが全文を再走査(core/doc.mbt:247)した直後に、**別言語・別文法**でもう一度全文を走査している。

(4) *同じ文法が 5 箇所に独立実装されている*(数えた結果):

| 規則 | 実装場所 |
|---|---|
| 見出し | core/parser.mbt:104-109 / src/relevel.ts:27 |
| フェンス(読み) | core/parser.mbt:179-232 / src/relevel.ts:12-25 / src/mindmap.ts:334,340 |
| フェンス(書き) | src/main.ts:440 — 独自ルール(バックティックのみ、3→4 のみ) |
| 空行ブロック境界 | core/cmds.mbt:51-67 / src/main.ts:417-420 / src/main.ts:731-734 |
| 改行種別 | core/cmds.mbt:39-46 `nl()` / TS は全経路で `"\n"` ベタ書き |
| インラインリンク・画像・`<svg>` | src/mindmap.ts:119,144,356 のみ(コアに対応物なし) |

加えて `@codemirror/lang-markdown`(src/editor.ts:101)という完全な CommonMark パーサがバンドルに入っているが、構造導出には一切使われず着色専用。実質 markdown パーサが 3 種類同居している。

**render() 全再構築(F-002)が将来どの機能を実装不能にするか。**

`src/mindmap.ts:558-559` が両レイヤを `replaceChildren()` で空にする。`render()` は `applySnap` から無条件(src/main.ts:198)、画像 1 枚の解決ごと(src/main.ts:678)に呼ばれる。src/ 全体に `requestAnimationFrame` は 0 件、CSS の `transition` はスプリッタの 1 件のみ(src/style.css:100)。

- **アニメーション**: 要素の同一性が毎フレーム消えるので CSS transition / WAAPI / SMIL は全て初期状態から再スタートする。enter/exit/move のアニメはキー付き差分なしには原理的に書けない。
- **フォーカス保持・アクセシビリティ**: `grep -an "aria|tabindex|role="` が src/mindmap.ts で **0 件**。しかも回避策が既にコードに残っている — ラベルエディタが SVG の**外**の HTML `<input>`(src/mindmap.ts:243-246)で、render のたびに位置だけ付け替える(src/mindmap.ts:728)。SVG 内に focusable を置けないことを設計者は既に知っている。roving tabindex、`<foreignObject>` エディタ、スクリーンリーダ用ツリーは全て入らない。
- **折り畳み**: render をまたいで生き残るノード単位のビュー状態が 1 つも無い。`order`(:292)、`sideOf`/`frameOf`(:492-493)、`boxes`(:555)は全て毎回作り直し。`collapsed: Set<id>` が最初のそれになるが、キーはノード id であり、F-004 により outdent で id は失われる。折り畳んだノードを outdent すると畳んだ状態が別ノードへ移るか消える。
- **部分更新・仮想化**: 部分更新の実例は `refreshSelection()`(src/mindmap.ts:1807-1812)ただ 1 つで、`Number(g.dataset.id)` の文字列往復で id を復元する場当たり実装。仮想化は `boxes` が完全であることに `nodeAt`(:1311-1320)、`fitView`(:760-765)、`exportSvg`(:784-789)が依存しているため、レイアウト層と DOM 発行層の 2 段分離が要る。`placeF` が `boxes` に書き(:475)、発行ループが読む(:561)ので**分離はほぼできているのに誰も強制していない**。
- **ドラッグ中のライブプレビュー**: `updateDrop`(:1615-1707)はドロップ線とクラスしか動かさない。実際に木が流れるのを見せるには「仮に落としたらどうなるか」の木が要るが、マップ側に木を作る手段は無い(`MapHost` は全てテキスト編集コマンド、src/mindmap.ts:25-45)。core/api.mbt の 19 本の `pub fn` は全て `st` を破壊するか `st.text` を読むだけで、dry-run / branch API が無い。

**分割線。**

`src/main.ts`(1135 行)は「文書モデルの同期」が実は 176-300 + 304-466 の約 290 行しかない。残り約 845 行はシェル: 永続化(60-115)、ブランドカラー/ファビコン(117-174)、ファイル I/O(503-615)、画像アセットパイプライン(617-845)、エクスポート(994-1071)、テーマ/ペイン/スプリッタ(1073-1091, 912-992)。分割線は `doc.ts`(applySnap / selection / typing タグ機械 / host)、`files.ts`、`assets.ts`、`export.ts`、`chrome.ts` の 5 本。

`src/mindmap.ts`(1814 行)は 3 つの別モジュールが 1 クラスに同居している。`render()` は 290-729 の **440 行 1 メソッド**で、その中に (a) markdown コンテンツパーサ(315-379)、(b) 純粋レイアウト(381-554)、(c) DOM 発行(556-729)が入っている。`onKeydown` は 1325-1581 の **257 行 1 メソッド**。分割線は `content.ts`(パーサ — 本来コアにあるべき)、`layout.ts`(`NodeInfo[] + CardRow[] → Map<id, Box>` の純関数。DOM に触れないのでテスト可能)、`render.ts`(CardRow 種別ごとの発行レジストリ)、`keymap.ts`(テーブルデータ化)、`exportSvg.ts`。

**新しいコンテンツ種別を 1 つ足すときの実測箇所数。**

表示だけなら **8 箇所**(CardRow union :55-59 / 定数 :78-92 / 検出ラダー :331-376 / `rowH` :381-386 / `widthOf` :399-412 / 発行ラダー :619-724 / style.css / exportSvg の PROPS :803-815)。マップから作れるようにすると **+7 = 15 箇所**(popup.ts / popup 用 CSS / MapHost 宣言 :40-42 / キーバインド :1417-1427 / コンテキストメニュー配列 :1723-1771 / main.ts の host 実装 :426-457 / `insertContentLine` は再利用可)。その構文が `#` `---` `<!--` を含みうるなら **+3 = 18 箇所**(core/parser.mbt:60-131 / src/relevel.ts:5-33 / src/mindmap.ts:334-353 に同じ規則を 3 回)。

そして罠がある。`widthOf`(:399-412)と発行ラダー(:619-724)は最終 else が `link` / `img` に絞られるので**型エラーになって手を入れざるを得ない**が、`rowH`(:381-386)はネストした三項の最終腕が `LINK_ROW` なので**新種別が黙って 26px として通る**。高さを決めるのは `rowH` → `heightOf`(:387-392)→ レイアウトなので、コンパイラが 3 箇所中 2 箇所を捕まえて、幾何を決める 1 箇所だけを見逃す。

**死んでいる / 到達不能なコード(全て実測)。** `abort_session`(core/api.mbt:222)、`MapHost.redo`(src/mindmap.ts:45)、`snapshot.rev`(core/api.mbt:34-35)、`.link-card` クラス、editor.ts の 6 個の CodeMirror テーマ規則 — 詳細は items に記載。

### D-1 / `core/api.mbt:32-96, core/api.mbt:93-94, core/api.mbt:99-230` / 未検証

**snapshot() は読み出しに見えて破壊的。木を非破壊で読む API が存在しない**

**根拠**: snapshot() の末尾: `st.last_sets = []` (api.mbt:93) と `st.focus = -1` (api.mbt:94)。つまり snapshot は 1 回しか読めない。19 本の `pub fn` のうち `get_text`(:114)と `selection_text_api`(:228)以外は全て `st` を変更してから snapshot() を返す。ノード配列を得る非破壊 API は 1 つも無い。

**負債**: 「現在のツリーを読む」という最も基本的な読み取り操作が、副作用を伴うコマンド呼び出しとしてしか存在しない。ワイヤ契約(snapshot)が読み取りモデルではなく「直前のコマンドの差分通知」になっており、状態の問い合わせと状態の変更が同一の関数に融合している。加えて `st.rev`(doc.mbt:53)は毎回インクリメントされ(doc.mbt:207)JSON に載る(api.mbt:34-35)のに、`grep '\.rev\b' src/*.ts` は 0 件 — 収束検証を安価にできる唯一のフィールドが死んでいる。

**このままだと顕在化するバグ**: MAP 2.2 step 13 が指摘する未検証点(origin=="cm" のとき editSets を捨てるのでコアと CodeMirror の一致が誰も確認していない)を将来直そうとして applySnap(src/main.ts:183)の条件を外すと、直ちに壊れる。onUserEdits(src/main.ts:295-298)はマルチカーソル編集で core.replaceText をループで呼び、**最後の snap しか保持しない**(`snap = core.replaceText(...)`)。中間の snapshot は last_sets を drain 済みで復元不可能なので、3 カーソル編集のうち 1 つ分の editSets だけが CodeMirror に適用され、2 ペインが黙って乖離する。同様に、アウトラインペイン・ミニマップ・デバッグパネル・TS 側のプロパティテストなど「木をもう一度読みたい」機能は、ダミーのコマンドを撃って副作用を起こすしか手がない。

**修正コスト**: api.mbt に非破壊の `read_snapshot()` を足し `snapshot()` を drain 無しに分離: 約 30 行。coreApi.ts / exports.mbt に 1 メソッド追加。呼び出し側の変更は無し(既存の drain 依存箇所が無いため)。

### D-2 / `src/coreApi.ts:5, src/coreApi.ts:37, src/coreApi.ts:39-66, tsconfig.json:10-15` / 未検証

**coreApi.ts の JSON 境界は型宣言だけで検査ゼロ。tsconfig の外を any で import している**

**根拠**: `const snap = (s: string): Snapshot => JSON.parse(s);`(coreApi.ts:37)— try/catch なし、形状検査なし。import 先は `../core/_build/js/release/build/js/js.js`(coreApi.ts:5)で、tsconfig.json:15 の `include: ["src"]` の外。`allowJs: true`(:10)かつ `checkJs` 無しなので `mbt.*` の全エクスポートは `any`。JSON 自体は core/api.mbt:32-96 の StringBuilder 手組みで、スキーマ定義は存在しない。

**負債**: 「唯一の信頼境界」とコメント(coreApi.ts:35-36)が宣言している場所に、実際の検証コードが 1 行も無い。TS の型は境界のこちら側の願望を書いただけで、向こう側(手書き JSON)とを結びつけるものが何も無い。しかも生成物が .gitignore 済み(.gitignore:3)なので、clone 直後は import 先すら存在しない。

**このままだと顕在化するバグ**: core/api.mbt:80-81 の `"subEnd"` を `"sub_end"` に改名する(MoonBit 側の命名を snake_case に揃える、というごく自然なリファクタ)と、`pnpm build`(package.json:10 の tsc --noEmit を含む)は通る。実行時に NodeInfo.subEnd が undefined になり、src/mindmap.ts:325 の比較が false になって全ノードのコンテンツ範囲が壊れ、src/main.ts:216 の `to: n.subEnd` が undefined を CodeMirror の decoration range に渡して RangeSet が例外を投げるか、SVG 属性に "NaN" が入って全ノードが原点に重なる。エラーメッセージは JSON とは無関係な場所で出る。

**修正コスト**: snap() に必須キーの実行時アサート(nodes が配列 / 各要素の 10 キーが number|boolean|string)を書く: 約 25 行。あるいは core 側に JSON スキーマを 1 本置き、双方から生成する: 約 80 行 + ビルド手順 1 段。

### D-3 / `core/parser.mbt:40, core/doc.mbt:289-295, src/mindmap.ts:322-327, src/main.ts:725-729` / 未検証

**ノードの「自分のコンテンツ範囲」をコアが捨て、TS が 2 箇所で逐語再導出している**

**根拠**: コアは Heading.content_start(parser.mbt:40「offset just after the heading line's newline」、代入は parser.mbt:123)と content_end(doc.mbt:290-294)を計算し、真偽値 has_content(doc.mbt:295)に潰して捨てる。snapshot が出すのは `hasContent`(api.mbt:84-85)だけ。TS 側は 2 ファイルで同じ式を再実装している。mindmap.ts:324-327 `i + 1 < nodes.length && nodes[i + 1].hs < n.subEnd ? nodes[i + 1].hs : n.subEnd`、main.ts:726-729 は変数名以外**逐語同一**。開始側も mindmap.ts:322 が `doc.indexOf("\n", n.he)` でコアの content_start を再計算している。

**負債**: 「ノード n に属するコンテンツはどこからどこまでか」はドキュメントモデルの概念であってビューの概念ではない。それがコアで計算されてから 2 回捨てられ、2 つの独立した TS 実装として復活している。現時点で 3 者の答えが一致するのは、重複ルート除去後の heads 配列(doc.mbt:252-262)の性質による偶然であり、それを保証するテストは 0 件(MAP 6.2「hs/he/subEnd に直接の assert が皆無」)。

**このままだと顕在化するバグ**: F-005 の周辺で必ず割れる。2 つ目以降の `#` 見出しは heads から落ちる(doc.mbt:255-259)が、コアの content_end は「次に**残った**見出しの hs」なので落ちたブロックを自分のコンテンツに含める。ここに将来 `subEnd` の意味を少しでも変える修正(F-005 や F-006 の修正はまさにここを触る)を入れると、コアの has_content と mindmap の cEnd と main の挿入位置 at が 3 者バラバラになる。症状は「カードが隣のノードの本文を表示する」「リンク追加が隣のノードの中に着地する」で、どちらもコアのテスト 44 件を 1 つも落とさずに起きる。

**修正コスト**: Node に content_start / content_end を持たせ snapshot に 2 キー追加: core 約 15 行 + api.mbt 4 行 + coreApi.ts の NodeInfo に 2 フィールド。TS 側の 2 箇所を置換: 約 10 行削除。

### D-4 / `core/parser.mbt:104-109 & :179-232, src/relevel.ts:12-27, src/mindmap.ts:334-340, src/main.ts:440, src/editor.ts:101` / 未検証

**同じ markdown 文法が 5 箇所に独立実装。フェンスの「書き手」だけ別ルール**

**根拠**: 見出し規則は core/parser.mbt:104-109 と src/relevel.ts:27 の 2 実装。フェンス**読み取り**は core/parser.mbt:179-232、src/relevel.ts:12-25(ファイル冒頭 relevel.ts:2 が「mirroring the core's scan rule」と自認)、src/mindmap.ts:334(`/^(`{3,}|~{3,})\s*(\S*)\s*$/`)と :340(閉じ判定 `c.startsWith(fence[1][0].repeat(3))`)の 3 実装。フェンス**生成**は src/main.ts:440 の `const fence = r.code.includes("```") ? "````" : "```";` の 1 箇所だけで、これはバックティックのみ・3→4 のみを知る第 4 の規則。さらに src/editor.ts:101 の `markdown()` は完全な CommonMark パーサだが構造導出には一切使われない。

**負債**: 1 つの文法に対して権威が無い。読み手 3 つと書き手 1 つが別々の部分集合を実装しており、書き手だけが他の 3 つと違う世界観(チルダフェンスも 5 個以上のフェンスも知らない)を持っている。共有もテストも無い(TS のテストは 0 件、package.json:6-13)。

**このままだと顕在化するバグ**: 4 個以上のバックティックを含むコードを「コードブロックを追加」ポップアップに貼ると即座に壊れる。main.ts:440 は `includes("```")` が真なので `"````"` を選ぶが、本文中の ```` がその 4 個フェンスを閉じてしまい、以降の行が文書の生テキストとして露出する。その中に列頭 `# ` の行があれば core/parser.mbt:104-109 がそれを見出しとして拾い、マップに幽霊ノードが生える。逆に `~~~` を含むコードは検出されずそのまま通る。

**修正コスト**: フェンス長を実測して max+1 にする最小修正: main.ts:440 を 4 行に。根治(規則を 1 箇所に集約し core から TS へ輸出)は core に `fence_for(text)` を足して exports 経由で公開: 約 40 行 + relevel.ts / mindmap.ts の置換 30 行。

### D-5 / `src/mindmap.ts:356-368, core/parser.mbt:88-92, core/parser.mbt:137-147, src/mindmap.ts:318-321` / 未検証

**インライン <svg> は mindmap だけが知る文法。コアのスキャナと衝突して非表示領域を誤爆する**

**根拠**: mindmap.ts:356-368 は `<svg` で始まる行から `</svg>` を含む行までを 1 個の CardRow として飲み込む。core/parser.mbt にはこの規則が無い(スキップするのはフェンス :75-87 と hide 領域 :88-98 のみ)。core/parser.mbt:88 の `is_marker_line(text, l, "<!--")` は parser.mbt:137-146 で前後の空白を**トリムしてから**完全一致を見るので、インデントされた `<!--` 行でも領域が開く。開いている間の見出しは全て `hidden: in_comment`(parser.mbt:125)。mindmap.ts:318-321 は `n.hidden` のノードのカード行を空にする。

**負債**: マップペインがコアの知らないコンテンツ種別の文法を持っている。コアはテキストの唯一の権威なのに、その権威が理解できない構文をビューが正当な内容として描いている。両者の文法が交差する箇所(`<!--` / `-->` / 行頭 `#` / `---`)に安全弁が無い。

**このままだと顕在化するバグ**: 整形済みの SVG は XML コメントを含むのが普通で、そのコメントは慣例的に `<!--` だけの行で始まる。そういう SVG をノードに貼ると core/parser.mbt:88 が hide 領域を開き、`-->` の行までの**後続の全ノード**が hidden になる。画面上は「貼った SVG のカードが消え、以降のノードが小さく半透明になる」(style.css:252-254)。しかも復旧しようと H キー(mindmap.ts:1429)で表示に戻そうとしても、cmds.mbt:661-667 の入れ子マーカガードに引っかかって無反応になる。ユーザから見れば「SVG を貼ったらマップの下半分が壊れて元に戻せない」。同様に SVG 内の列頭 `# ` 行(CSS の id セレクタを `# foo {` と書いた場合など)は幽霊ノードになる。

**修正コスト**: core/parser.mbt に `<svg`…`</svg>` のスキップ状態を足す: 約 25 行(フェンス処理と同型)。相互に src/mindmap.ts:334-368 と src/relevel.ts:5-33 にも同じ規則が要るので合計 3 箇所 60 行。回避策だけなら mindmap 側で svg 内に `<!--` があれば行を検出して警告: 5 行。

### D-6 / `src/mindmap.ts:290-729, src/mindmap.ts:558-559, src/main.ts:198, src/main.ts:678, src/mindmap.ts:1807-1812` / 未検証

**render() 全再構築(F-002)が、アニメーション・折り畳み・仮想化・a11y を構造的に不可能にしている**

**根拠**: `this.edgeLayer.replaceChildren(); this.nodeLayer.replaceChildren();`(mindmap.ts:558-559)。render() は applySnap から無条件(main.ts:198)、画像 1 枚の解決ごと(main.ts:678)。src/ 全体で `requestAnimationFrame` は grep 0 件、CSS transition はスプリッタ 1 件のみ(style.css:100)。`grep -an "aria|tabindex|role=" src/mindmap.ts` は **0 件**。ノードのビュー状態は全て毎回作り直し: order(:292)、sideOf/frameOf(:492-493)、boxes(:555)。部分更新の実例は refreshSelection(:1807-1812)だけで、`Number(g.dataset.id)` の文字列往復で id を復元する。

**負債**: 要素の同一性が 1 打鍵ごとに消える。同一性を前提とする機能群 — CSS transition / WAAPI / SMIL、DOM フォーカス、スクリーンリーダのカーソル、要素に紐づくビュー状態 — が全て使えない。回避策は既にコードに埋まっていて、ラベルエディタが SVG の外の HTML `<input>`(mindmap.ts:243-246)として実装され render のたびに位置だけ付け替えられている(:728)。設計者は「SVG 内に focusable を置けない」ことを既に知りながら、その制約を構造として直さずに 1 箇所だけ迂回した。

**このままだと顕在化するバグ**: 折り畳みを足すと F-004 と直結して壊れる。collapsed は `Set<node id>` としてしか持てない(render をまたぐ他の同一性が無いため)が、F-004 により outdent はノード id を失う(core/doc.mbt:113-143 の map_offset が純削除で -1 を返す)。ユーザが A を折り畳んでから A を outdent すると、A の折り畳み状態は消えるか、`st.next_id` の再利用によって**別のノード**に付く。症状は「アウトデントしたら関係ないノードが勝手に畳まれた」。同じ理屈で、将来入れる per-node のあらゆる UI 状態(ピン留め、色、メモ、選択順序)が同じ壊れ方をする。

**修正コスト**: キー付き差分レンダラへの置換は render() 440 行の書き換え + boxes/order の意味の再定義: 約 500 行、mindmap.ts のほぼ半分。段階的には (a) レイアウト(:381-554)を DOM に触れない純関数へ切り出し(約 175 行の移動)、(b) 発行ループ(:556-729)を id キー付き reconcile に置換(約 175 行)の 2 段。

### D-7 / `core/api.mbt:99-230, src/mindmap.ts:25-45, src/mindmap.ts:1615-1707` / 未検証

**投機的ツリー(what-if)を作る手段が無い。core の 19 API は全て破壊的**

**根拠**: core/api.mbt の 19 本の `pub fn` は、`get_text`(:114)と `selection_text_api`(:228)を除き全て `st` を書き換える。dry-run / branch / clone に相当するものは無い。MapHost(mindmap.ts:25-45)が公開するのは全てコマンドで、木を計算する手段は 0。updateDrop(mindmap.ts:1615-1707)はドロップ線の座標とクラスしか触らない。

**負債**: 「この操作を仮に適用したらどうなるか」を問える場所がシステムのどこにも無い。木の変形はテキスト編集としてしか定義されておらず、テキスト編集は唯一のグローバル `st` にしか適用できない。プレビュー・差分・提案・検証は全て、実際に文書を壊してから undo するか、TS 側に 3 つ目のツリーモデルを作るかの二択になる。

**このままだと顕在化するバグ**: ドラッグ中のライブプレビュー(木が実際に流れて見える、市販のマインドマップでは標準)を実装しようとすると、pointermove ごとに `core.moveNodes` → `applySnap` → `render` → pointerup で戻すために `core.undo` を撃つ実装に必然的になる。すると (a) F-002 の実測 70.2ms @5000 ノードが 1 move ごとに掛かって 14fps、(b) undo スタック(core/doc.mbt:51, 上限なし)に move/undo のペアが毎フレーム積まれ、(c) tag マージ(doc.mbt:221-235)がかからないので 1 回のドラッグで数百エントリになり、(d) undo の最中に F-004 でノード id が失われてドラッグ対象が選択から消える。「ドラッグしたら Ctrl+Z が 300 回必要になった」という形で出る。

**修正コスト**: core に `begin_preview()` / `discard_preview()`(既存の begin_tx/commit_tx doc.mbt:393-404 と do_abort :458 を土台にできる): 約 60 行 + api/exports/coreApi に 2 メソッド。真の分岐(st の複製)は St が単一グローバル(doc.mbt:62)なので下記の項目とセットで約 200 行。

### D-8 / `core/doc.mbt:62-73, core/api.mbt:99-230, src/main.ts:35, src/main.ts:206-208` / 未検証

**st がグローバル 1 個。文書は永久に 1 個しか持てない**

**根拠**: `let st : St = { text: "", nodes: [], ... }`(doc.mbt:62-73)。文書ハンドルを取る API は 19 本中 0 本。TS 側は既に 2 つ目の文書を欲しがっており、`savedText`(main.ts:35)を素の String として持ち、`updateDirty()`(main.ts:206-208)が `core.getText() === savedText` の**全文比較を毎スナップショット**実行している。

**負債**: 文書という概念にアイデンティティが無い。タブ、分割ビュー、保存版との差分、貼り付け断片のプレビュー、そして「1 プロセスで 2 文書を扱うテスト」が全てブロックされる。TS 側が全文文字列比較でダーティ判定しているのは、2 つ目の文書を持てないことの直接の帰結。

**このままだと顕在化するバグ**: タブ機能を足そうとした時点で、core/doc.mbt の全関数(st を直接参照する doc.mbt / cmds.mbt / api.mbt の全体)を書き換えるまで一切前に進めない。より近い将来では、`rev`(doc.mbt:53)が文書をまたいで共有される単調カウンタなので、2 文書目を無理やり load すると undo スタック(doc.mbt:51-52)が前の文書の編集を保持したままになり、Ctrl+Z が「別のファイルの編集」を現在のファイルに適用する。init_doc は st.undo.clear() する(api.mbt:101)のでこの経路は塞がれているが、逆に言えば **文書切り替えのたびに undo 履歴が全消去される**のが現在の仕様であり、タブを足すと「タブを切り替えたら undo 履歴が消えた」になる。

**修正コスト**: St をハンドル辞書化し 19 API に doc_id を足す: core 側 約 250 行(doc.mbt 527 行 + cmds.mbt 685 行の `st.` 参照を全て引数経由に)。exports.mbt / coreApi.ts / main.ts で約 80 行。

### D-9 / `src/mindmap.ts:12-46, src/main.ts:304-466, src/mindmap.ts:1325-1581, src/mindmap.ts:1723-1771` / 未検証

**MapHost 28 メンバの肥大。コマンドを 1 本足すと 8 ファイルを触る**

**根拠**: MapHost のメンバは 28 個(mindmap.ts:12-46 を実測)。うち 20 個はコアコマンドの 1 対 1 パススルー。実装(main.ts:304-466)は 163 行で、`if (!byId.has(id)) return; const tag = `s${++sessionN}`; runCmd(() => core.X(id, tag, split), { edit: { tag } });` の定型が 5 回繰り返される(main.ts:312-335)。コマンド 1 本の追加が触る場所: MapHost 宣言(mindmap.ts:12-46)、キーマップ(mindmap.ts:1325-1581 の 257 行 1 メソッド)、コンテキストメニュー配列(mindmap.ts:1723-1771)、host 実装(main.ts)、coreApi.ts、core/js/exports.mbt、core/api.mbt、core/cmds.mbt の 8 ファイル。

**負債**: ビューとコマンド層の間にインターフェースがあるのではなく、コマンドの目録がそのままインターフェースになっている。抽象化されていないので、境界を挟んで数だけが増える。インターフェースは既に腐り始めていて、`redo()` は mindmap.ts:45 で宣言され main.ts:465 で実装されているのに、`grep -an redo src/mindmap.ts` の結果は宣言行 1 件のみ — マップペインには undo の `u`(mindmap.ts:1411)だけがあり redo キーは無い。

**このままだと顕在化するバグ**: コンテキストメニュー(mindmap.ts:1723-1771)は既に MapHost の一部としか同期していない: C/D/L のコンテンツ追加(mindmap.ts:1417-1427)と toggleHidden(:1429)と reorder(:1525-1529)がメニューに無い。次にコマンドを足すとき 8 箇所のうち 1 つを落とすのは確実で、落ちやすいのはテストが無く目に触れにくいコンテキストメニューとキーマップ。症状は「ボタンからはできるがキーボードからはできない」「右クリックメニューに出ない機能がある」という恒常的な非対称の蓄積で、どのバグレポートも再現手順が食い違う。

**修正コスト**: MapHost を `nodes/docText/selection/...` の 7 個の問い合わせ + `dispatch(cmd: MapCommand)` の 1 個に縮める: mindmap.ts 側 約 60 行、main.ts の host を discriminated union のディスパッチャに 約 80 行。キーマップとメニューを同一のコマンドテーブルから生成すれば非対称が構造的に消える(追加 40 行)。

### D-10 / `core/api.mbt:222-225, src/mindmap.ts:45, core/api.mbt:34-35, src/mindmap.ts:589, src/editor.ts:33-37 & :46-50, src/editor.ts:87` / 未検証

**死んでいる / 到達不能なコードの実測列挙**

**根拠**: (1) `abort_session`(api.mbt:222-225): core/js/exports.mbt の `#export_name` は 18 個で、その一覧(:5,11,17,23,29,35,41,47,53,59,65,71,77,83,89,95,101,107)に abortSession は無い。src/coreApi.ts:39-66 の 18 メソッドにも無い。テスト(core_test.mbt:154)からしか呼べない。(2) `MapHost.redo`(mindmap.ts:45): `grep -an redo src/mindmap.ts` = 宣言 1 行のみ。(3) `snapshot.rev`(api.mbt:34-35): 毎回 JSON に載るが `grep -an '\.rev\b' src/*.ts` = 0 件。(4) `.link-card`(mindmap.ts:589 でカード行を持つ全ノードに付与): `grep -c link-card src/style.css` = **0**。(5) editor.ts の `.cm-cursor`(:33,:46)/`.cm-selectionBackground`(:34,:47)/`.cm-activeLine`(:37,:50)の 6 個のテーマ宣言: これらの要素を作るのは drawSelection(node_modules/@codemirror/view/dist/index.js:9528、マーカ生成は :9586)と highlightActiveLine(:10020-10023)だけで、`grep -c 'drawSelection|highlightActiveLine' src/editor.ts` = **0**、拡張リスト(editor.ts:98-143)にも無い。(6) `MdEditor.view` は public readonly(editor.ts:87)だがクラス外からの参照は 0 件。

**負債**: 「あるように見えて無い」もの、「無いように見えてあるもの」が両方ある。abort_session はコアにテスト付きで存在するのに出荷経路が無く、MapHost.redo は契約に載っているのに呼ばれず、rev は毎回ワイヤを通るのに誰も見ず、link-card は毎ノードのクラス文字列を消費するのに CSS 規則が無い。読み手はこれらを「使われている」と信じてコードを書く。

**このままだと顕在化するバグ**: 最も危険なのは (5)。誰かがテーマの選択色が効かないことに気づいて `.cm-selectionBackground` の色を直しても何も変わらず、原因(drawSelection 未導入)にたどり着けない。実際に足すと今度は `EditorState.allowMultipleSelections` も無いため挙動が変わる。次に (2): マップペインに redo を実装する人は `host.redo` が既にあるのを見て「呼び出しだけ足せばよい」と判断するが、Mod+Z/Y は window の capture 段で `stopPropagation` 付き(main.ts:901-906)なので、マップに `Ctrl+R` 等を足すと二重に発火するか、既存の capture ハンドラに食われて無反応になる。

**修正コスト**: 削除だけなら約 20 行(link-card 1 箇所、rev の serialize 2 行、editor.ts の 6 宣言、MdEditor.view を private 化)。abort_session は exports.mbt に 6 行足して生かすか、api.mbt から 4 行削るかの判断が要る。

### D-11 / `src/mindmap.ts:803-828, src/style.css:137, src/style.css:244` / 未検証

**exportSvg の PROPS が手書き 11 個。white-space: pre が既に落ちている**

**根拠**: PROPS = fill, stroke, stroke-width, stroke-dasharray, stroke-linecap, font-family, font-size, font-weight, opacity, dominant-baseline, text-anchor の 11 個(mindmap.ts:803-815)。`inline()`(:816-828)はこの 11 個を getComputedStyle からコピーし、`copy.removeAttribute("class")`(:823)で class を剥がす。style.css:137 の `.node text.label { white-space: pre }` と style.css:244 の `.node text.code-line { white-space: pre }` は PROPS に無い。

**負債**: 表示とエクスポートの間で、スタイル契約が手で維持されるリストになっている。class を剥がすので、リストに載っていないプロパティは**必ず**失われる。失敗のシグナルが無い(例外も警告も出ない)。

**このままだと顕在化するバグ**: 現時点で既にバグっている: エクスポートした SVG / WebP のコードプレビュー行はインデントが潰れる(mindmap.ts:684 が `\t` を空白 2 個に展開して入れた字下げが、white-space: pre 無しの text 要素で連続空白として畳まれる)。ラベル先頭・末尾の空白も同様。さらに将来 `letter-spacing`、`fill-opacity`、`text-decoration`、`paint-order`、`stroke-opacity` のいずれかを CSS に足した瞬間、画面とエクスポートが黙って食い違い、「PNG に落とすと見た目が変わる」というバグレポートが出るが、CSS を見ても mindmap.ts を見ても原因は見えない(PROPS 配列だけが答え)。

**修正コスト**: white-space を PROPS に足す最小修正: 1 行。根治(class を剥がさず `<style>` 要素として CSS 全文を埋め込む)は inline() を約 30 行書き換え + 埋め込み 15 行。

### D-12 / `src/mindmap.ts:55-59, :78-92, :331-376, :381-386, :399-412, :619-724, :803-815` / 未検証

**新コンテンツ種別 1 つ = 8〜18 箇所。しかも幾何を決める rowH だけが型検査をすり抜ける**

**根拠**: 表示だけの追加で触る 8 箇所: CardRow union(:55-59)、レイアウト定数(:78-92)、検出ラダー(:331-376、順序依存 + `list.length < 4` のベタ書き上限 :331)、rowH(:381-386)、widthOf(:399-412)、DOM 発行ラダー(:619-724)、style.css、exportSvg の PROPS(:803-815)。作成 UI まで足すと +7(popup.ts、popup 用 CSS、MapHost 宣言 :40-42、キーバインド :1417-1427、コンテキストメニュー :1723-1771、main.ts の host :426-457)。構文が `#`/`---`/`<!--` を含みうるなら +3(core/parser.mbt:60-131、src/relevel.ts:5-33、src/mindmap.ts:334-353)。決定的な非対称: widthOf(:399-412)の最終 else は `r.link.title` を読み、発行ラダー(:688-723)の最終 else は `r.path` を読むので**両方とも型エラーになる**が、rowH(:381-386)は `r.kind === "img" || r.kind === "svg" ? IMG_ROW : r.kind === "code" ? … : LINK_ROW` のネスト三項で、新種別が最終腕の `LINK_ROW` に**型エラー無しで落ちる**。

**負債**: CardRow 種別が「1 つの概念 = 1 箇所」ではなく、6 つの並行する switch/ladder に散っている。しかもコンパイラが 3 つのうち 2 つしか守ってくれない。守られない 1 つがレイアウト幾何を決める場所であるという最悪の組み合わせ。

**このままだと顕在化するバグ**: 表(table)や数式(math)の行を足すと、rowH が LINK_ROW = 26 を返す一方で発行ラダーは実寸(例えば表 4 行なら 80px 以上)を描くため、heightOf(:387-392)が実際より小さい高さを返し、calcV(:436-445)/placeF(:448-486)がその小さい高さで兄弟を積む。結果、表を持つノードが下の兄弟に重なって描画される。ビルドは通り、テストも無いので気づくのはユーザ。しかも nodeAt(:1311-1320)は boxes の(小さい)矩形で当たり判定するので、はみ出した部分をクリックしても選択できない。

**修正コスト**: CardRow ごとの `{ detect, measure, emit, css }` レジストリに集約: mindmap.ts で約 180 行の再構成(検出ラダー・rowH・widthOf・発行ラダーの 4 箇所を 1 テーブルへ)。応急処置として rowH の最終腕を `((r: never) => { throw new Error() })(r)` の網羅チェックに変える: 3 行。

### D-13 / `core/cmds.mbt:39-46, src/main.ts:735, src/main.ts:401, src/main.ts:416-420` / 未検証

**改行種別の権威がコアと TS で二重化し、TS 側は常に LF をベタ書きする**

**根拠**: コアの `nl()`(cmds.mbt:39-46)は文書の**最初の**改行から CRLF/LF を決め、全てのコア挿入がそれに従う(core_test.mbt:363 の「crlf newlines are preserved and matched on insert」で固定済み)。一方 TS の挿入経路は LF ベタ書き: `insertContentLine`(main.ts:735)が `prefix + line + "\n" + suffix` を挿入し、prefix/suffix も `"\n\n"` / `"\n"`(main.ts:731-734)。`host.paste`(main.ts:401)は `clip.replace(/\r\n/g, "\n")` で CRLF を潰してから main.ts:416-421 で挿入する。insertContentLine はリンク・コードブロック・お絵描きの共通着地点(main.ts:430, :441, :452)。

**負債**: 「この文書の改行は何か」という 1 つの事実に対して権威が 2 つあり、片方(TS)はそもそも問い合わせる手段を持たない — `nl()` は core/cmds.mbt の private fn で API に露出していない(core/api.mbt の 19 本に無い)。コアが慎重に守っている不変条件を、UI 層が知らないまま毎回破っている。

**このままだと顕在化するバグ**: Windows で作った CRLF の .md を開き、ノードにリンクを 1 本足すだけで文書が混在改行になる。しかも `nl()` は最初の改行しか見ない(cmds.mbt:40-45)ので以降のコア挿入は CRLF のままで、混在が固定される。ファイルを保存すると(main.ts:571-573 は core.getText() をそのまま書く)git の差分に無関係な行が大量に出る、あるいは `core.autocrlf` 設定次第で毎回全行差分になる。ユーザから見れば「リンクを 1 個足しただけなのに git が 500 行変更と言う」。同じ経路で貼り付け(main.ts:401)も CRLF 文書を汚す。

**修正コスト**: `nl()` を API に露出(api.mbt に 3 行 + exports.mbt 6 行 + coreApi.ts 1 行)し、main.ts:401 の正規化と :416-420 / :731-735 の 2 箇所をその値で組み立てる: TS 側 約 15 行。あるいは挿入自体をコアの `insert_content_line(id, text)` コマンドに移す(こちらが正しい層): core 約 40 行、main.ts から 14 行削除。

---

## 観点: undo/redo の粒度と永続化の単位

## 1. タグ合体の状態機械 (src/main.ts:246-300)

状態は 3 変数だけ: `typeTag` / `typeKind` / `typePos` (src/main.ts:246-248)。`typeKind` は `""` / `"compose"` / `"type"` / `"del"` の 4 値。タグはコアの `apply_sets` に渡され、**「スタック最上位のエントリのタグ文字列が一致するか」だけ**でマージが決まる (core/doc.mbt:221-235)。位置も時刻も見ない。

`sessionN` は単調増加で `t{n}` / `s{n}` を共有採番する (src/main.ts:34, :291, :313) ので、タグ文字列が偶然再利用されることはない。これは確認済みで安全。

**合体する条件** (src/main.ts:264-285):
- `edits.length === 1` かつ `userEvent === "input.type"` かつ純挿入 (`e.from === e.to && insert.length > 0`) かつ `typeKind === "type"` かつ `e.from === typePos`。→ 前タグ再利用、`typePos = e.from + insert.length`。
- `edits.length === 1` かつ `userEvent === "delete.backward"` かつ純削除 (`insert === "" && e.to > e.from`) かつ `typeKind === "del"` かつ `e.to === typePos`。→ 前タグ再利用、`typePos = e.from`。
- `userEvent === "input.type.compose"` かつ `typeKind === "compose"` (src/main.ts:256-263)。位置は一切見ない。

**切れる条件**:
- キャレットが飛んだ (`e.from !== typePos` / `e.to !== typePos`) → 新タグ。
- 種別が変わった (type↔del↔compose) → 新タグ。
- 選択を上書きするタイプ入力 (`from < to` かつ insert あり) → `pureInsert` でも `pureDelete` でもないので src/main.ts:287 の `typeKind = ""`、`tag` は `""` のまま = **単独エントリ**。
- **Enter** は `insertNewlineAndIndent` → userEvent `"input"` (node_modules/@codemirror/commands/dist/index.js:1521,1546)。src/editor.ts:126 の `"input"` にマッチ → src/main.ts:287 へ落ちて `tag = ""`。行境界で切れるのは**偶然そうなっている**だけで、意図的な境界処理はどこにもない。
- Tab (`insertTab`, userEvent `"input"`)、paste (`"input.paste"`)、drop (`"move.drop"`) も同様に単独エントリ。
- `edits.length > 1` (マルチカーソル) → `typeKind = ""` かつ新タグ `t{n}` を採番 (src/main.ts:289-292)。これは `core.replaceText` を N 回呼ぶ (src/main.ts:295-298) のを 1 エントリに束ねるための必須処理。
- `applySnap` が `origin !== "cm"` で呼ばれた (src/main.ts:197)。マップ側コマンド・undo・redo・ファイル読込がすべてここを通る。

**切れそこなう / 切れすぎる条件**:
- **時間境界が存在しない**。CodeMirror 標準の history は `newGroupDelay: 500` を持つが、mmm はコア独自 undo で history 拡張を外している (src/editor.ts:1-4, :98-143 に `history()` なし)。キャレットを動かさずに 10 分放置してから続きを打つと同じエントリに合体する。
- **Delete (前方削除) は合体しない**。`deleteBy` は userEvent `"delete.forward"` を出す (node_modules/@codemirror/commands/dist/index.js:1171)。src/editor.ts:118-126 のリストに `"delete.forward"` は無く、`isUserEvent` の前方一致で `"delete"` (src/editor.ts:122) にマッチする。src/main.ts:277 は `"delete.backward"` を厳密比較するので不一致 → `typeKind = ""`、`tag = ""`。**Backspace 20 回 = 1 エントリ、Delete 20 回 = 20 エントリ**という非対称が出る。
- **IME**: src/editor.ts:108-111 の `compositionend` DOM ハンドラが `compose.end` を送り `typeKind = ""` にする (src/main.ts:251-254)。ところが CodeMirror の `runHandlers` は **observer を先、plugin handler を後**に回す (node_modules/@codemirror/view/dist/index.js:4562-4567)。組み込み observer `observers.compositionend` (同 :5266-5282) が先に走り、未処理の MutationRecord があれば `compositionPendingChange = true` を立てて `Promise.resolve().then(() => observer.flush())` (同 :5281) で**マイクロタスクに flush を予約**する。その後に mmm のハンドラが `typeKind = ""` を実行し、**さらにその後**に flush → `applyDOMChange` が `compositionPendingChange && compositionEndedAt > Date.now() - 50` により userEvent を `"input.type.compose"` にする (同 :4417-4426)。結果、`typeKind` は既に `""` なので**確定文字が別タグ = 別 undo エントリになる**。EditContext 経路は `browser.android` 限定 (同 :7145) なのでデスクトップ Chrome では回避されない。しかも CM は各変換の最初の変更に `"input.type.compose.start"` を付けている (同 :4422-4424) のに、src/editor.ts:119 の `"input.type.compose"` が前方一致で吸収してしまい、**正しい境界情報が捨てられている**。

## 2. sNN と tNN が混ざったとき / ラベル編集の打鍵ごと rename

マップ側は `runCmd` (src/main.ts:231-242) が `s{n}` を採番し、**同じタグを構造コマンドと直後のラベル編集の両方に渡す** (src/main.ts:315, :240)。`core.addChild(id, "s7")` のエントリに、`map.beginEdit(id, "s7")` 後の全打鍵の rename が合体する。「新規ノード作成 + ラベル入力」が 1 undo になる設計は妥当。

ただし `map.editingTag` (src/mindmap.ts:200, :903, :922) は `endEdit()` でしか消えない。コア側には「セッションが開いている」概念が無く、マージ条件は最上位エントリのタグ一致だけ (core/doc.mbt:221-223) なので、ラベル編集中に別のエントリが 1 つでも積まれると、同じ `s7` を持つエントリが**スタック上に非隣接で 2 つ**でき、1 回のラベル編集が複数 undo に割れる。現状はラベル `<input>` がフォーカスを持つ間に他のエントリが積まれる経路が無い(blur → `commitEdit`、src/mindmap.ts:1290-1292)ので顕在化していないが、コードで守られてはいない。

ラベル編集の `input` ハンドラ (src/mindmap.ts:1274-1279) は **1 打鍵ごとに `host.rename`** を発行し、`cmd_rename` は毎回 `[hs, he)` = **見出し行全体を置換**する (core/cmds.mbt:237-245)。従って 1 打鍵ごとに `removed` = 旧行全文、`insert` = 新行全文の Edit が 1 つ、同一エントリの `steps` / `inv` に積まれる (core/doc.mbt:224-227)。20 文字打てば `steps` は 20 セット、保持テキストは O(行長 × 打鍵数)。さらに `host.rename` は `applySnap(..., "map")` (src/main.ts:337) を通るので、**打鍵ごとに `map.render()` (F-002) と `updateDirty()` の全文比較と `schedulePersist()` が走る**。`input` ハンドラに `isComposing` ガードが無いので、日本語ラベルは変換候補が確定前に .md 本文へ書き込まれ、その全部が localStorage 永続化の対象になる。

## 3. コア側トランザクション (st.tx) と undo 1 単位

`st.tx` (core/doc.mbt:57) を使うのは **2 コマンドだけ**: `cmd_outdent` (core/cmds.mbt:394 / :427) と `cmd_move` (core/cmds.mbt:528 / :568)。どちらも `begin_tx("")` = タグ空なので、生成されるエントリは他と絶対にマージしない。

タグを渡すのは `cmd_add_child` / `add_sibling` / `add_sibling_before` / `add_parent` / `add_root` / `cmd_rename` / `replace_text` の 7 経路 (core/cmds.mbt:150, :167, :184, :211, :225, :244、core/api.mbt:133)。残りは全部 `""`: `cmd_delete` (core/cmds.mbt:302)、`cmd_indent` (:371)、`move_block` (:493 — `cmd_reorder` からは tx 外で 1 エントリ)、`cmd_toggle_hidden` (:654, :675)。

**undo の 1 単位の実体**は「1 エントリ = `steps: Array[Array[Edit]]`」であり、**編集セットは畳まれない**。`replay_entry` (core/doc.mbt:414-432) はセット数ぶん `apply_edit_set` を回し、そのたび `st.last_sets.push` する (:421-423)。`snapshot()` はそれを全部シリアライズし (core/api.mbt:43-63)、`editor.applySets` が**セットごとに 1 dispatch** する (src/editor.ts:157-165)。つまり **30 打鍵ぶん合体したエントリを 1 回 undo すると、CodeMirror へ 30 回 dispatch し、MoonBit 側で 30 回の全文文字列再構築が起きる**。F-002 の「5000 ノードで no-op undo 134.7ms」はセット 0 個での測定なので、実 undo はこれに O(セット数 × 文書長) が加算される。

`do_abort` (core/doc.mbt:457-466) と `abort_session` (core/api.mbt:222-225) は実装されているが、core/js/exports.mbt に `abortSession` の `#export_name` が無く (18 本すべて確認)、src/coreApi.ts にも無い。**到達不能なデッドコード**で、ラベル編集の「キャンセル」は仕様上も実装上も存在しない (src/mindmap.ts:1272-1273, :1283-1285 は Escape も Enter も commit)。

## 4. 永続化

- `persistNow` (src/main.ts:99-109) は `localStorage["mmm.text"] = core.getText()` = **文書全文**。例外は無言で捨てる (:106-108)。
- `schedulePersist` (src/main.ts:110-113) は毎回 `clearTimeout` → `setTimeout(250)` の**トレーリングデバウンスで maxWait 無し**。`applySnap` の末尾から毎スナップショット呼ばれる (src/main.ts:203)。連続入力中は 250ms の空白が空くまで**一度も書かれない**。
- 保険は `pagehide` のみ (src/main.ts:115)。`visibilitychange` ハンドラも定期 flush も無い (grep 済み)。
- `savedText` はモジュール変数 (src/main.ts:35)。更新するのは `saveFile` (:582) と `openFile` (:525, :536) と drop (:874) とブート (:1113)。`updateDirty` (:206-208) は毎スナップショットで `core.getText() === savedText` の全文比較。
- `loadText` (src/main.ts:473-488) は `mmm.fileName` と `mmm.savedText` を**同期で**書くが `mmm.text` は書かない ─ それは `applySnap` 経由の 250ms 後。3 キーが別タイミング・非原子・文書同一性トークン無し。
- IndexedDB は `persistHandle` (src/main.ts:514-516) と `ensureImageDir` (:716) の fire-and-forget 2 本、catch は空。ブートでハンドルを採用する条件は **`h.name === fileName` のファイル名一致だけ** (:1119)。
- ブートは常に `localStorage` の `mmm.text` を優先し、ハンドルがあってもディスクを読み直さない (src/main.ts:1111-1114)。mtime 比較なし。

**どのタイミングで落ちると何を失うか**:
1. 連続入力中にタブ/OS がクラッシュ → `pagehide` は発火しない → **最後に 250ms 手が止まった時点以降の全入力**を失う。速いタイピストほど失う量が増える。
2. ファイルを開いた直後 250ms 以内にクラッシュ → `mmm.fileName` / `mmm.savedText` は新ファイル、`mmm.text` は**前の文書**。次回起動は「B のファイル名・B の savedText・A の本文」。名前が一致すれば IndexedDB のハンドルも B を指す → dirty 点灯 → Ctrl+S で **A の本文が B に書き込まれる**。
3. `localStorage` quota 超過 (`mmm.text` + `mmm.savedText` で文書 2 コピー、origin 上限 ~5MB) → `persistNow` が無言で no-op (src/main.ts:106-108)。UI 表示は一切変わらない。以後クラッシュすれば**セッション全部**を失い、リロードすれば**古い `mmm.text` に無警告で巻き戻る** (`beforeunload` は `savedText` としか比較しない、src/main.ts:850-853)。
4. `saveFile` の LS 書き込みが失敗 (src/main.ts:584-589 の catch 空) → `mmm.savedText` が古いまま → 次回起動の dirty 判定が嘘になる。
5. 保存直後にタブを閉じると `persistHandle` の IndexedDB トランザクションが完了しないことがある → ハンドル喪失 → 次回 Ctrl+S でピッカーが出る (復旧可能だが無警告)。

### D-1 / `src/editor.ts:105-112, src/main.ts:251-254, node_modules/@codemirror/view/dist/index.js:4562-4567, :5266-5282, :4417-4426` / 未検証

**compose.end が最後の compose トランザクションより先に走り、IME 1 変換が 2 つの undo に割れる**

**根拠**: editor.ts:108-111 `compositionend: () => { onUserEdits([], "compose.end"); return false; }` / main.ts:251-254 `if (userEvent === "compose.end") { typeKind = ""; return; }` / view/index.js:4565-4567 `for (let observer of handlers.observers) observer(this.view, event); for (let handler of handlers.handlers)` — 組み込み observer が plugin handler より先。 / view/index.js:5272,5281 `compositionPendingChange = view.observer.pendingRecords().length > 0` … `Promise.resolve().then(() => view.observer.flush())` / view/index.js:4418-4421 `if (view.composing || view.inputState.compositionPendingChange && view.inputState.compositionEndedAt > Date.now() - 50) { … userEvent += ".compose"; }`

**負債**: undo の境界を「変換の終わり」の DOM イベントで引いているが、CodeMirror は確定文字を compositionend の後のマイクロタスクで flush する。境界マーカとトランザクションの順序が保証されていない。しかも CM は変換ごとの最初の変更に `input.type.compose.start` を付けており、正しい境界情報が既に流れているのに、editor.ts:119 の `"input.type.compose"` が isUserEvent の前方一致で吸収して捨てている。EditContext 経路は view/index.js:7145 で `browser.android` 限定なのでデスクトップでは迂回されない。

**このままだと顕在化するバグ**: 日本語で「にほんご」→変換→「日本語」を確定した直後に Ctrl+Z を 1 回押すと、文書が空に戻らず「にほんご」(確定前の最後の候補文字列)が残る。ユーザは「undo が効いていない」と思ってもう 1 回押し、今度はその前の入力まで巻き戻る。マップ側は applySnap 経由で毎回 render するので、中間候補が SVG のラベルとしても一瞬見える。

**修正コスト**: editor.ts の compositionend ハンドラを削除し、userEvent リストに "input.type.compose.start" を "input.type.compose" より前に追加、main.ts:256-263 を「start なら新タグ、それ以外は継続」に変える。約 10-15 行、影響は onUserEdits と updateListener のみ。

### D-2 / `src/editor.ts:118-126, src/main.ts:277-288, node_modules/@codemirror/commands/dist/index.js:1167, :1171` / 未検証

**Delete は 1 打鍵 1 エントリ、Backspace は全部 1 エントリ ― 削除方向で undo 粒度が非対称**

**根拠**: commands/index.js:1167 `event = "delete.backward";` / :1171 `event = "delete.forward";` に対し、editor.ts:120-122 のリストは `"delete.backward"`, `"delete"` のみ。前方一致で delete.forward は `"delete"` にマッチする。main.ts:277 `} else if (userEvent === "delete.backward" && pureDelete) {` は厳密比較なので不一致 → main.ts:287 `typeKind = "";` に落ち、`let tag = ""` (main.ts:255) のまま core/doc.mbt:221 の `tag != ""` を満たさず必ず新エントリ。

**負債**: 入力イベント名の集合が editor.ts の固定リストにハードコードされ、CodeMirror が実際に発行する名前と突き合わせる仕組みが無い。onUserEdits の分岐は「タイプ入力」と「後方削除」しか知らないので、それ以外の全ユーザ操作が一律「単独エントリ」に落ちる。時間境界も無いため、マージ側は逆に無制限に伸びる。

**このままだと顕在化するバグ**: 長い行を Delete キーで消したユーザは、Ctrl+Z を押した回数だけ 1 文字ずつ戻る (100 文字消したら 100 回)。同じユーザが Backspace で同じ操作をすると 1 回で全部戻る。さらに時間境界が無いため、キャレットを動かさずに書き続けた 2000 文字の段落は 1 エントリになり、Ctrl+Z 1 回でセッション全部が消える。どちらも「Ctrl+Z が何を戻すか予測できない」というバグ報告になる。

**修正コスト**: main.ts:264-292 に delete.forward 分岐 (typePos === e.from で合体) と、直近打鍵時刻を持って 500ms 超で強制的に新タグにする処理を追加。約 15-25 行、onUserEdits に閉じる。

### D-3 / `core/doc.mbt:414-432, core/doc.mbt:224-227, core/api.mbt:43-63, src/editor.ts:157-165, core/cmds.mbt:237-245, src/mindmap.ts:1274-1279` / 未検証

**undo の 1 単位が N 個の編集セットのまま畳まれず、1 回の undo が N 回の dispatch と N 回の全文再構築になる**

**根拠**: doc.mbt:224-227 マージは `top.steps.push(sets[i]); top.inv.push(inv_sets[i])` で追記するだけ。 / doc.mbt:419-429 `for i = sets.length()-1; i >= 0; i = i-1 { st.text = apply_edit_set(st.text, sets[i]); st.last_sets.push(sets[i]) }` — セットごとに文書全文を作り直す。 / api.mbt:43 `for i = 0; i < st.last_sets.length(); i = i + 1` で全部 JSON 化。 / editor.ts:158-164 `for (const set of sets) { … this.view.dispatch({…}) }` — セットごとに 1 dispatch。 / cmds.mbt:238-243 rename は毎回 `[nd.hs, nd.he)` を丸ごと置換し `removed = old` に行全文を持つ。 / mindmap.ts:1276 `this.host.rename(this.editingId, this.editor.value, this.editingTag);` を input ごとに発行。

**負債**: 「マージ = 配列に append」で済ませており、隣接・連続する Edit を 1 本に畳む正規化が存在しない。テキストレベルの往復は健全 (F-007 の property test) だが、その健全性を保つために編集履歴を圧縮しない設計になっている。ラベル編集は行全文置換なので、保持データも再生コストも打鍵数の 1 乗ではなく行長×打鍵数で効く。

**このままだと顕在化するバグ**: F-002 の測定 (5000 ノードで no-op undo 134.7ms) に対し、40 文字のラベルを打った直後の undo は 40 セット分の apply_edit_set (各 O(文書長)) と 40 回の CodeMirror dispatch が上乗せされ、体感で数百 ms〜秒オーダーの固まりになる。ユーザは Ctrl+Z を連打し、キューに溜まった undo が一気に走ってさらに前まで戻る。

**修正コスト**: apply_sets のマージ時に「直前セットと隣接・同方向なら 1 本の Edit に畳む」正規化を入れる (doc.mbt に 40-60 行)。あるいは replay_entry で全セットを合成して 1 セットとして last_sets に積む (30 行程度、snapshot / applySets 側は無変更)。

### D-4 / `core/doc.mbt:25-31, core/doc.mbt:51-52, core/doc.mbt:237, core/api.mbt:101-102` / 未検証

**undo スタックに上限が無く、各 Entry が削除テキスト全文を保持したまま init_doc 以外に解放点が無い**

**根拠**: doc.mbt:17-22 `priv struct Edit { from; to; insert : String; removed : String }` / doc.mbt:26-27 `steps : Array[Array[Edit]]` と `inv : Array[Array[Edit]]` の両方を保持 (invert_edit_set は removed/insert を入れ替えて再度 String を持つ) / doc.mbt:51-52 `undo : Array[Entry]` `redo : Array[Entry]` に長さ制限のコードは無い / doc.mbt:237 `st.undo.push(...)` に trim なし / api.mbt:101-102 `st.undo.clear(); st.redo.clear()` — 唯一の解放は init_doc、つまりファイルを開き直したときだけ。

**負債**: undo 履歴が「文書テキストのコピーの集積」として際限なく伸びる構造。cmd_delete (cmds.mbt:300) は削除した部分木の全文を removed に、move_block (cmds.mbt:489) は移動ブロックの全文を removed に、rename は打鍵ごとに行全文を steps と inv の両方に入れる。ローカル専用アプリで「タブを開きっぱなしで一日書く」使い方を前提にしているのに、履歴の予算がどこにも定義されていない。

**このままだと顕在化するバグ**: 大きな部分木を切って貼るのを繰り返す長時間セッションで、MoonBit ヒープ (JS 側のヒープ) が文書サイズの数十倍に膨れ、タブが OOM で落ちる。落ちれば pagehide は発火しないので (main.ts:115)、直近 250ms 分どころか最後にタイプが止まった時点以降の入力も失う。

**修正コスト**: apply_sets / commit_tx の push 直後に「上限超過なら st.undo の先頭から捨てる」を入れる。doc.mbt に 10-20 行。上限値の決定と、canUndo の意味が変わることの UI 側確認が必要。

### D-5 / `core/doc.mbt:221-235, core/doc.mbt:457-466, core/api.mbt:222-225, core/js/exports.mbt:5-107, src/main.ts:246-248, src/mindmap.ts:200, :903, :922` / 未検証

**編集セッションの所有権が JS 側に分散し、コアには「開いているセッション」の概念が無い ― abort_session は実装済みで到達不能**

**根拠**: doc.mbt:221-223 `let merged = if tag != "" && st.undo.length() > 0 { let top = st.undo[st.undo.length()-1]; if top.tag == tag {` — 判定は最上位エントリのタグ文字列一致のみ。位置も時刻もセッション状態も見ない。 / api.mbt:222 `pub fn abort_session(tag : String) -> String` は存在するが、core/js/exports.mbt の #export_name 18 本 (initDoc…selectionText) に abortSession は無く、src/coreApi.ts:39-66 にもラッパが無い。 / mindmap.ts:200 `editingTag = ""` は :903 (beginEdit) と :922 (endEdit) でしか書かれない。main.ts:197 `if (origin !== "cm") typeKind = "";` は md 側の鎖しか切らない。

**負債**: 「1 つの編集セッションが 1 つの undo エントリ」という不変条件を守る責任が、main.ts の typeKind/typePos と mindmap.ts の editingTag という 2 つの独立した JS 変数に分散している。コア側は文字列が一致するかしか見ないので、その 2 つが食い違ってもエラーにならず静かに粒度が壊れる。さらに「セッションを中断して捨てる」の実装 (do_abort) は完成しているのに、エクスポート表に載せ忘れて誰も呼べない。

**このままだと顕在化するバグ**: ラベル編集中に別の undo エントリを積む経路 (画像の非同期ロード完了後の再描画に構造コマンドを足す、オートセーブ的なリネームを入れる、Mod+Z のガード main.ts:902 を外す等) を今後 1 つでも追加すると、同じ s7 タグのエントリがスタック上に非隣接で複数でき、1 回のラベル入力を戻すのに Ctrl+Z が 3 回必要になる。また `s`/`cc` キー (mindmap.ts:1364, :1374 の editClear) はラベルを即座に空にするエントリを積む (mindmap.ts:910) ので、Escape でキャンセルしたつもりのユーザはラベルが消えた状態で確定される — 本来 abort_session が担うはずの動作。

**修正コスト**: exports.mbt に abortSession を 1 本追加 (6 行) + coreApi.ts に 1 行 + mindmap.ts の Escape を abort に振り分け (10 行)。所有権をコアに移す本格対応なら open_session/close_session を doc.mbt に足して 60-100 行。

### D-6 / `core/doc.mbt:392-409, core/doc.mbt:212-218, core/cmds.mbt:394, :427, :528, :568` / 未検証

**begin_tx が st.tx を無条件に上書きし、tx 中の apply_sets は redo を clear しない**

**根拠**: doc.mbt:392-394 `fn begin_tx(tag : String) -> Unit { st.tx = Some(Entry::{ steps: [], inv: [], tag, before: id_pairs(), after: [] }) }` — 既に Some かどうかを見ない。 / doc.mbt:212-218 `match st.tx { Some(tx) => { for … tx.steps.push(sets[i]) … } None => { st.redo.clear() … } }` — tx 経路には redo.clear が無い。 / doc.mbt:400-405 `commit_tx` は `if tx.steps.length() > 0` のときだけ push し、その中で redo.clear。 / 使用箇所は cmds.mbt:394/427 (outdent) と :528/568 (move) の 2 組だけ。

**負債**: トランザクションが単一スロットでネスト非対応なのに、ガードもアサーションも無い。しかも tx 中は「テキストは変わったが undo エントリはまだ存在しない」という中間状態が実在し (doc.mbt:198 で st.text は更新済み)、commit_tx に到達しなければその編集は永久に undo 不能になる。cmd_outdent / cmd_move は現状 continue しかしないので早期 return は無いが、それはコードの形に依存した偶然。

**このままだと顕在化するバグ**: 「複数ノードをまとめて別の親へ移してから一段アウトデントする」のような複合コマンドを 1 つ足すと、内側の begin_tx が外側の tx を丸ごと捨てる。テキストは両方の編集を受けているのに undo スタックには内側のエントリしか積まれず、Ctrl+Z を押すと外側の移動だけが取り消せないまま残る = 木が壊れた状態で固定される。tx 中に例外的な早期 return を足した場合も同じ (st.tx が Some のまま残り、以後のあらゆるコマンドが undo スタックに積まれなくなる)。

**修正コスト**: begin_tx に `if st.tx is Some(_) { abort/panic }` かネストカウンタを追加。doc.mbt に 5-15 行。

### D-7 / `src/main.ts:98-115, src/main.ts:203` / 未検証

**250ms トレーリングデバウンスに maxWait が無く、連続入力中は一度も localStorage に書かれない (保険は pagehide のみ)**

**根拠**: main.ts:110-113 `function schedulePersist(): void { if (persistTimer !== -1) window.clearTimeout(persistTimer); persistTimer = window.setTimeout(persistNow, 250); }` / main.ts:203 `schedulePersist();` が applySnap の末尾 = 全スナップショット経路。 / main.ts:115 `window.addEventListener("pagehide", persistNow);` が唯一の保険。visibilitychange も setInterval も無い (grep 済み)。

**負債**: デバウンスの目的 (書き込み回数の削減) と永続化の目的 (クラッシュ耐性) が同じ 1 本のタイマーに載っていて、前者が後者を無条件に打ち消す。maxWait も、rev ベースの「N リビジョンごとに必ず書く」も無い。pagehide はナビゲーション/タブ閉じでは発火するが、レンダラプロセスのクラッシュ・OOM・OS の強制終了・電源断では発火しない。

**このままだと顕在化するバグ**: 手が止まらないタイピスト (あるいはマップのドラッグ操作を連続でやるユーザ) が 5 分書き続けた後にタブがクラッシュすると、5 分ぶん全部が消える。localStorage には 5 分前の状態しか無い。ユーザから見ると「保存してないファイルだからしょうがない」ではなく「自動保存されているはずだった」という報告になる。

**修正コスト**: schedulePersist に「最初の schedule から 2 秒経ったら強制 flush」の maxWait と、`visibilitychange` で hidden のとき persistNow を追加。main.ts に 12-20 行。

### D-8 / `src/main.ts:104-108, src/main.ts:484, :585, src/main.ts:206-208` / 未検証

**永続化の単位が「文書全文 × 2 コピーを毎回 localStorage へ」で、quota 例外を無言で握り潰す**

**根拠**: main.ts:104-108 `try { localStorage.setItem(LS_TEXT, core.getText()); } catch { /* storage full/blocked */ }` — 失敗しても UI に何も出ない。 / main.ts:484 と :585 `localStorage.setItem(LS_SAVED, savedText);` — mmm.text と mmm.savedText で文書 2 コピーを同一 origin (通常 ~5MB) に置く。 / main.ts:206-208 `elDirty.hidden = core.getText() === savedText;` は永続化の成否を一切反映しない。

**負債**: 差分ではなく全文を、非同期ストレージではなく同期 API の localStorage に、しかも同じ文書を 2 つ持つ形で書いている。IndexedDB は既に開いていて (main.ts:71-96 の idb/idbSet/idbGet) ファイルハンドルの保存に使われているのに、本文だけが localStorage に取り残されている。書き込み失敗の観測点がゼロ。

**このままだと顕在化するバグ**: 2MB 程度の .md (画像パス付きの長い設計メモなら現実的) で mmm.text + mmm.savedText が quota を超え、以後 persistNow は毎回 catch に落ちて何も保存しない。UI は正常に見えたまま。ユーザがリロードすると、quota 超過前の古い mmm.text が復元され、その間の編集が無警告で消える。beforeunload (main.ts:852) は savedText としか比較しないので「未保存の変更があります」の警告も出ない場合がある (ディスク保存直後にリロードしたとき)。

**修正コスト**: 本文の保存先を IndexedDB に移し (idbSet の流用で 30-50 行)、setItem 失敗時に flashFilename で通知 (5 行)。savedText の保持を「ハッシュ or 長さ+ハッシュ」に変えて 2 コピー目を消せば追加で 20 行。

### D-9 / `src/main.ts:473-488, src/main.ts:203, src/main.ts:511-516, src/main.ts:1110-1121` / 未検証

**mmm.text / mmm.fileName / mmm.savedText / IndexedDB handle が別々のタイミングで書かれ、文書同一性トークンが無い**

**根拠**: main.ts:480-487 loadText は `applySnap(snap, "load")` (→ schedulePersist で 250ms 後に mmm.text) のあと `localStorage.setItem(LS_NAME, name); localStorage.setItem(LS_SAVED, savedText);` を同期で書く。3 キーの書き込み時刻が異なる。 / main.ts:511-513 のコメント `a stale handle plus fresh text means Ctrl+S after reload silently overwrites the WRONG file` / main.ts:1119 `if (h && h.name === fileName) fileHandle = h;` — 同一性判定はファイル名だけ。 / main.ts:1111-1114 ブートは常に storedText を採用し、復元したハンドルからディスクを読み直さない。

**負債**: 「今開いている文書」を表すのが 3 つの独立した localStorage キーと 1 つの IndexedDB エントリで、それらを結びつける id もリビジョンも無い。原子的に書く手段が無いストレージに、原子的でなければ意味を成さない状態を分散させている。コード自身のコメント (main.ts:511-513) が危険を認識しているのに、対策として置かれた名前一致チェック (:1119) は同一性の検査になっていない。

**このままだと顕在化するバグ**: (a) ~/work/README.md を開いて作業 → 別プロジェクトの ~/lib/README.md を開いた直後 250ms 以内にクラッシュ → 再起動すると「~/lib の名前・~/lib の savedText・~/work の本文」になり、名前が一致するのでハンドルも ~/lib を指す。Ctrl+S で ~/lib/README.md が ~/work の内容で上書きされる。(b) クラッシュしなくても、同名ファイルを別フォルダで開き直せば古いハンドルが採用される。(c) ブートは常に localStorage 優先なので、mmm を閉じている間に git checkout でファイルが変わっても mmm は古い本文を表示し、Ctrl+S でディスクの新しい内容を破壊する。

**修正コスト**: 文書ごとに uuid を発番して 4 つの保存先すべてに同じ uuid を書き、ブート時に不一致なら localStorage 側を捨てる。main.ts に 50-70 行。ハンドルからの mtime 比較を足すならさらに 20 行。

### D-10 / `src/main.ts:183, core/api.mbt:125-132, src/main.ts:105, src/main.ts:552` / 未検証

**origin "cm" では editSets を CodeMirror に当てないため、replace_text の範囲拒否が無言の乖離になり、永続化と保存はコア側のテキストを書く**

**根拠**: main.ts:183 `if (origin !== "cm" && origin !== "load") editor.applySets(snap.editSets);` / api.mbt:125-128 `let n = st.text.length(); if from < 0 || to > n || from > to { return snapshot() }` — 範囲外なら編集を捨てて空の editSets を返す。 / main.ts:105 `localStorage.setItem(LS_TEXT, core.getText());` / main.ts:552 `const text = core.getText();` (saveFile)。 / main.ts / editor.ts のどこにも `view.state.doc.length` と `core.getText().length` を突き合わせる箇所は無い (grep 済み)。

**負債**: 「テキストが唯一の真実」の真実はコア側にあり、CodeMirror はそのミラーのはずなのに、cm 由来の編集だけはミラーを更新しない (echo 回避のため)。この経路には整合性の検査点が一つも無く、コアが編集を拒否する唯一の分岐 (api.mbt:126) がまさにその経路にある。乖離が起きても rev も長さも比較されないので検出されない。

**このままだと顕在化するバグ**: 何らかの理由で 1 回でも from/to が文書長を超えて渡ると (マルチカーソル編集の delta 計算 main.ts:295-298 のずれ、あるいは今後 CodeMirror 側に別の編集拡張を足したとき)、その編集はコアに入らず CodeMirror にだけ残る。以後ユーザが md ペインで見ている内容と、localStorage に書かれ Ctrl+S でディスクに書かれる内容が恒久的に食い違う。マップペインは正しい (コア側の) 木を描くので、ユーザは「md ペインに書いた行がマップに出ない」という形で気付き、保存すると md ペインの内容が消える。

**修正コスト**: applySnap に `if (origin === "cm" && editor.view.state.doc.length !== core.getText().length)` の検査を入れて、不一致なら editor.setText(core.getText()) で強制同期 + 通知。main.ts に 8-12 行。api.mbt:126 の拒否パスに理由を返せるようにするなら追加で 10 行。

---

## 観点: 往復で情報が落ちる入力

結論から言うと、落ちるのは大きく 3 系統ある。(1) **パーサがノードとして認めないのに、範囲としてはノードに含まれてしまう行** —— 2 つ目以降の `#`、生 HTML 中の `#` 行、最初の見出しより前のテキスト。(2) **`<!--` / `-->` / `---` という「行そのものがマーカーになる」テキスト** —— 本文中にこれらの行があると、hide/show や group 判定がユーザの行を巻き込んで削除・誤読する。(3) **書式の正規化** —— rename が見出し行を、move/copy がブロック間の空行を、paste が改行コードを潰す。以下すべて `core/_build/js/release/build/js/js.js` を Node から直接叩いて確認した実測値である。

**(1) 認識されない行が範囲に入る。** `rebuild_nodes` は見出しの配列 `heads` からしかノードを作らず (core/doc.mbt:279-308)、`sub_end` は「自分以下の深さの次の *採用された* 見出しの hs」でしかない (core/doc.mbt:309-317)。だから最初の見出しより前のテキストは**どのノードの範囲にも入らない**。`---\ntitle: x\n---\n\n# R\n\n## A\n` を読ませると nodes は `R(hs=18)` と `A(hs=23)` だけで、`selection_text` に全 id を渡しても返るのは `"# R\n\n## A\n"` (core/cmds.mbt:597-618)。マップペインには Mod+A で全選択 (src/mindmap.ts:1483-1489)、Mod+C でコピー (src/mindmap.ts:1491) があるので、「全部選んでコピー → 新規文書に貼る」で frontmatter と前書きが消える。逆に 2 つ目以降の `#` は `seen_root` で構造から捨てられる (core/doc.mbt:252-262) のに、前ノードの `sub_end` の内側には残る。`# One\n\ntext\n\n# Two\n\nbody of two\n\n## Child\n` は nodes が `One(subEnd=42=EOF)` と `Child` の 2 個で、`One` を削除すると文書が `""` になる（実測）。

**(2) マーカー行。** `is_marker_line` は行の前後空白を落として `<!--` / `-->` と完全一致するかだけを見る (core/parser.mbt:137-147)。4 スペース字下げしたコードブロック中の `-->` も、リスト外の裸の `-->` も、すべてマーカーになる。`cmd_toggle_hidden` の「入れ子拒否」ガード (core/cmds.mbt:661-667) は `st.hide_regions` に載った *対になった* 領域しか見ないので、**閉じていない `-->` 単独行は素通り**する。結果、hide → show でユーザの行が消える（実測: `# R\n\n## A\n\narrow -->\n-->\n\n## B\n` が `# R\n\n## A\n\narrow -->\n\n-->\n## B\n` になる）。`---` も同様で、`is_separator` (core/parser.mbt:152-173) が setext 見出しの下線を group 区切りと誤読し、`move_block` はその `---` を置いてけぼりにして別ノードの境界に付け替える。

**(3) 正規化。** `cmd_rename` は `hashes(depth) + " " + sanitize_label(label)` で見出し行を丸ごと書き直し (core/cmds.mbt:237)、マップのラベル編集は 1 打鍵ごとに rename を発行する (src/mindmap.ts:1273-1276)。`move_block` と `selection_text` は末尾改行を全部剥がして 1 行の空行に固定する (core/cmds.mbt:462-477, :604-615)。paste は CRLF を LF に潰したうえ (src/main.ts:401)、`relevel` の再結合が `"\n"` 固定 (src/relevel.ts:54)、prefix/suffix も `"\n"` リテラル (src/main.ts:416-420) なので CRLF 文書が混在改行になる。

なお `moveNodes(id, rootId, 1)` は `# S2\n\n# Two\n\nbody\n\n# One\n\n## S1\n` を作り、元の root `One` がマップから消える（F-006 の実測例）。今日は src/mindmap.ts:1641-1645 が depth-1 への drop を pos=0 に強制するので UI からは届かない。

### D-1 / `core/cmds.mbt:626-685, core/cmds.mbt:661-667, core/parser.mbt:88-98, core/parser.mbt:137-147` / 未検証

**hide→show が本文中の `-->` 行を削除する**

**根拠**: 入力 `# R\n\n## A\n\narrow -->\n-->\n\n## B\n` で A を hide→show した実測:
hide  → "# R\n\n<!--\n## A\n\narrow -->\n-->\n\n-->\n## B\n"
show  → "# R\n\n## A\n\narrow -->\n\n-->\n## B\n"   ← ユーザの `-->` 行が消え、mmm が入れた `-->` が残骸として残る
4スペース字下げでも同じ (`    -->` は is_marker_line が前後空白を落とすのでマーカー扱い): `# R\n\n## A\n\n    x -->\n    -->\n\n## B\n` → show 後 `    -->` 行が消失。
該当コード core/cmds.mbt:661-667:
```
for r in st.hide_regions {
  let (o_start, _, c_start, _) = r
  if (o_start >= nd.hs && o_start < nd.sub_end) || (c_start >= nd.hs && c_start < nd.sub_end) { return }
}
```

**負債**: 入れ子 hide のガードが `st.hide_regions`(= scan_doc が対にできた領域だけ, core/parser.mbt:95)しか見ていない。開いていない裸の `-->` 行は regions に載らないので、部分木内にあってもガードを通過する。hide が挿入したマーカーで開いた領域は、その裸の `-->` で早期クローズし、show はその行を「領域の閉じマーカー」として削除する(core/cmds.mbt:647-652)。hidden という状態がテキストの再走査からしか導出されない設計(core/cmds.mbt:621-625 のコメント)なので、コアは自分が入れたマーカーとユーザの行を区別する手段を持たない。

**このままだと顕在化するバグ**: mermaid 記法・HTML コメントの説明・diff 断片などを字下げコードブロックで貼った文書で、隣のノードを一時的に非表示にして戻すだけで、そのコードブロックの `-->` 行が黙って消える。文字数が変わるだけなのでダーティドット以外に警告はなく、保存すればディスク上のファイルからも消える。undo は 1 手で戻せるが、show した後に別の編集を挟むと気づいた時にはもう戻せない。

**修正コスト**: 約 20 行。cmd_toggle_hidden の hide 側ガードを「部分木テキストを走査して `<!--`/`-->` に一致する行が 1 本でもあれば拒否」に変える(regions ではなく行走査にする)か、show 側で「削除する close マーカーが自分の入れた位置と対応するか」を検証する。影響は core/cmds.mbt の 1 関数に閉じる。

### D-2 / `core/parser.mbt:88-93, core/parser.mbt:129-131, core/doc.mbt:250, core/cmds.mbt:633-659` / 未検証

**本文中の裸の `<!--` 行が無関係なノードを hidden にし、show で消える**

**根拠**: 入力 `# R\n\n## A\n\nHTML comments open with\n<!--\nand close with -->\n\n## B\n\n## C\n`
nodes → [R:false, A:false, B:**true**, C:**true**]  ← B と C が hidden 扱い
B に toggleHidden(=表示に戻す)すると:
"# R\n\n## A\n\nHTML comments open with\nand close with -->\n\n## B\n\n## C\n"  ← A の本文から `<!--` 行が消える
字下げ版 `    <!--` でも同じ: `# R\n\n## A\n\n    <!--\n\n## B\n\n## C\n` → C を show すると `    <!--` 行が消えて空行だけ残る。
scan_doc は閉じない領域を close=(-1,-1) で push する(core/parser.mbt:129-131)ので、以降の全見出しが hidden:true になる。

**負債**: `<!--` 単独行という「普通の Markdown 本文にも現れうる文字列」を、文書全体に効くグローバルな状態遷移として扱っている。しかも閉じない領域を許して(-1,-1)、その状態を hidden フラグとしてノードに焼き付ける。ユーザの意図(単なるテキスト)と mmm の制御構文が同じ字面を共有しており、逃げ道(エスケープ)がない。

**このままだと顕在化するバグ**: Markdown の書き方を説明する文書、あるいは他ツールが吐いた `<!-- prettier-ignore -->` 系の断片を貼った瞬間、以降のノードが全部グレー(hidden)表示になる。ユーザは「なぜか非表示になった」と思って表示に戻す操作をし、その 1 クリックで元の `<!--` 行が削除される。B と C を順に戻せば `<!--` の削除は 1 回だけだが、その後 hidden 表示が直らない(閉じマーカーが無いまま)ので操作を繰り返し、周辺の行を削り続ける。

**修正コスト**: 約 10-30 行。最小対応は「閉じない `<!--` 領域は領域として採用しない」(core/parser.mbt:129-131 の push をやめる)。ただし hidden の意味論が変わるので core_test.mbt の hide 系テストの見直しが要る。

### D-3 / `core/doc.mbt:279-308, core/cmds.mbt:597-618, src/mindmap.ts:1483-1489` / 未検証

**最初の見出しより前のテキストはどのノードにも属さず、コピーで消える**

**根拠**: 入力 `---\ntitle: x\n---\n\n# R\n\n## A\n`
nodes = [R(hs=18, subEnd=28), A(hs=23, subEnd=28)]  ← hs が 0 から始まらない
selection_text([R.id, A.id]) = "# R\n\n## A\n"   ← frontmatter 3 行が含まれない
前書き散文でも同じ: `intro paragraph\n\n# R\n\n## A\n` → R.hs=17、selection_text([R]) = "# R\n\n## A\n"
マップ側には全選択がある: src/mindmap.ts:1483 `if (mod && (key === "a" || key === "A")) { this.host.setSelection([...this.order], ...) }`、src/mindmap.ts:1491 で copySelection。

**負債**: ノード配列が heads(=見出し行)からしか作られない(core/doc.mbt:279)ため、[0, heads[0].hs) の区間を指す木構造上の入れ物が存在しない。テキストが真実なので保存はされるが、木を経由するあらゆる操作(選択・コピー・移動・hide・エクスポート)からは到達不能な暗黒領域になっている。「テキストが唯一の真実」という宣言(core/core.mbt:1-4)と「木からしか操作できない UI」の間の穴。

**このままだと顕在化するバグ**: YAML frontmatter 付きの記事を mmm で開き、Mod+A → Mod+C で全部コピーして別ファイルに貼ると title/date/tags が消える。ユーザは「全部選んだ」と信じているので欠落に気づくのは公開後。さらに frontmatter の閉じ `---` は `is_separator` に拾われて最初の見出しの group 区切りとして働く(core/doc.mbt:266-276)ので、マップ上に説明のつかないグループ境界が出る。

**修正コスト**: 約 30-60 行。preamble を持つ疑似ノード(あるいは Snapshot に preamble 範囲を足して UI 側でコピーに含める)を導入する。selection_text と exportSvg と paste の 3 経路に波及する。

### D-4 / `core/doc.mbt:252-262, core/doc.mbt:309-317, src/relevel.ts:40-55` / 未検証

**2つ目以降の `#` ブロックが前ノードの subEnd に閉じ込められ、削除で消滅しコピーで復活する**

**根拠**: 入力 `# One\n\ntext\n\n# Two\n\nbody of two\n\n## Child\n`
nodes = [One(depth1, hs=0, subEnd=42=EOF), Child(depth2, hs=33)]   ← `# Two` はノードにならない
(a) deleteNodes([One.id]) → getText() === ""   ← 文書全体が消える
(b) selectionText([One.id]) = 文書全文。これを Child(depth2)に貼ると relevel(target=3, min=1, delta=2)で
    "# R…" 系がすべて 2 段深くなり、結果:
    "…## Child\n\n### One\n\ntext\n\n### Two\n\nbody of two\n\n#### Child\n"
    nodes = [One, Child, One, **Two**, Child]  ← 元文書に無かった "Two" ノードが生える
core/doc.mbt:254-260:
```
for h in all {
  if h.depth == 1 { if seen_root { continue }; seen_root = true }
  heads.push(h)
}
```

**負債**: 「構造から外す」と「範囲から外す」が分離されていない。seen_root で heads から落とした見出しは、残った見出しの sub_end 計算(core/doc.mbt:309-317)では存在しない扱いになるので、前ノードの部分木に丸ごと吸収される。一方 TS 側の relevel(src/relevel.ts:27 `/^(#+)[ \t]/`)には seen_root の概念が無いので、同じテキストを深さ 1 の見出しとして数える。コアと TS で「見出しの定義」が食い違っており、copy と delete で挙動が非対称になる。

**このままだと顕在化するバグ**: 既存の Markdown ノート(`# 章1` `# 章2` の並列構造)を開くと、マップには 1 個目の章しか出ない。ユーザがその 1 個を「いらない章」と思って Delete を押すとファイルが空になる。逆にコピー&ペーストで複製すると、隠れていた章が突然ノードとして現れ、しかも意図した深さより 1 段深い位置に着地する。どちらも「表示されているものと実際に動くものが違う」ため、ユーザは何が起きたか説明できない。

**修正コスト**: 約 40-80 行。設計判断が要る(重複 root を許す / 独立ツリーとして扱う / 深さ 1 の 2 個目を構造エラーとして UI に出す)。rebuild_nodes・normalize_selection・cmd_add_root・relevel の 4 箇所に波及。

### D-5 / `src/relevel.ts:43-52, src/main.ts:414` / 未検証

**relevel の基準が「mmm がノードと認めない `#` 行」になり、貼り付け深さがずれる**

**根拠**: 入力 `# R\n\n## A\n\n<div>\n# raw html line\n</div>\n\n## B\n`
nodes = [R(1), A(2, subEnd=41), B(2)]  ← `# raw html line` は重複 root として捨てられている
A をコピー → clip = "## A\n\n<div>\n# raw html line\n</div>\n"
B(depth2) に貼り付け → relevel(target=3): scanDepths が `# raw html line` を depth 1 と数え minDepth=1、delta=2。
  relevel 結果 = "#### A\n\n<div>\n### raw html line\n</div>\n"
貼り付け後 nodes = [R(1), A(2), B(2), **A(4)**, **raw html line(3)**]
  ← コピーした A は depth 3 のはずが depth 4 に着地し、HTML の行が A の親ノードになる。
src/relevel.ts:43-46:
```
let minDepth = Infinity;
for (const d of depths) if (d > 0 && d < minDepth) minDepth = d;
```

**負債**: relevel は「断片の最浅見出しを targetDepth に合わせる」という前提だが、その最浅見出しがコアの木では存在しないことがある。src/relevel.ts:1-2 のコメントどおりコアの走査規則を TS で再実装しているが、再実装したのはフェンス規則だけで、重複 root の除外(core/doc.mbt:252-262)・最初の見出しより前の扱い・hide 領域は写していない。真実が 2 実装に分かれているので、片方だけ直しても必ずずれが残る。

**このままだと顕在化するバグ**: 生 HTML ブロックや、隠れた 2 個目の `#` を含むノードをコピペするたびに、貼り付け先の階層が 1 段ずつ深くなり、身に覚えのないノードが親として挿入される。ユーザは「同じものを複製したのに形が違う」と感じるが、原因が clipboard の中身にあるため再現条件を特定できない。深いコピペを繰り返すと `####…` が延々増えていく。

**修正コスト**: 約 15 行(relevel を「コアが返す nodes の深さ」基準にする)〜 60 行(コピー時にコアが深さメタ情報を返し、TS 側の再走査をやめる)。後者が筋。src/relevel.ts と src/main.ts:402,414、core/api.mbt の selection_text 契約に波及。

### D-6 / `src/main.ts:401, src/main.ts:414-421, src/main.ts:730-735, src/relevel.ts:54` / 未検証

**CRLF 文書への貼り付け・行挿入が LF を混入させ、空行を 1 つ余計に入れる**

**根拠**: 入力(CRLF) `# R\r\n\r\n## A\r\n\r\n## B\r\n` で B をコピー(selection_text は文書の改行を使うので `"## B\r\n"`)、A に貼り付け:
結果 = "# R\r\n\r\n## A\r\n\r\n**\n**### B**\n\n**## B\r\n"
  ← (1) 挿入行が LF、(2) すでに空行があるのに prefix "\n" が付いて空行が 2 つになる。
原因: src/main.ts:418-419
```
if (at > 0 && text[at - 1] !== "\n") prefix = "\n\n";
else if (at >= 2 && text[at - 2] !== "\n") prefix = "\n";
```
CRLF では text[at-2] が常に "\r" なので第 2 分岐が必ず真になる。
src/relevel.ts:54 も `.join("\n")` 固定。insertContentLine も同じ: src/main.ts:735 `core.replaceText(at, at, prefix + line + "\n" + suffix, "")`。
コア側は改行種別を持っている(`nl()` core/cmds.mbt:39-46)のに、TS 側の 3 経路がそれを使っていない。

**負債**: 改行種別の知識がコア(core/cmds.mbt:39 `nl()`)にだけあり、テキストを組み立てる TS 側(paste / insertContentLine / relevel)は `"\n"` をハードコードしている。しかも空行判定が「1 文字前が \n」「2 文字前が \n」という LF 前提の位置計算になっており、CRLF では常に外れる。Snapshot に改行種別が入っていない(core/api.mbt:32-96 の 6 キーに無い)ので TS 側は知りようがない。

**このままだと顕在化するバグ**: Windows で作った CRLF の Markdown を mmm で編集すると、貼り付けたノードだけ LF になる。保存して git に入れると、その行だけ差分が出る/エディタによっては文書全体が改行混在としてリライトされ、次のコミットで全行差分になる。さらに貼り付けのたびに空行が 1 本ずつ増えるので、同じ場所に 3 回貼ると空行 4 本の穴が空く。

**修正コスト**: 約 15 行。Snapshot に eol を 1 フィールド足し(core/api.mbt:34 付近)、src/main.ts:416-420 と :731-735、src/relevel.ts:54 でそれを使う。あるいは貼り付け文字列の組み立てをコア側の新 API に移す(30 行程度)。

### D-7 / `core/cmds.mbt:231-247, core/cmds.mbt:16-35, src/mindmap.ts:1273-1276` / 未検証

**rename が 1 打鍵で見出し行の書式(余分な空白・タブ・末尾空白)を潰す**

**根拠**: core/cmds.mbt:237: `let line = hashes(nd.depth) + " " + sanitize_label(label)`
実測(いずれも同じラベルで rename しただけで行が書き換わる):
  "##  Spaced"   → label "Spaced"   → rename 後 "## Spaced"   (変化した: true)
  "##\tTabbed"   → label "Tabbed"   → rename 後 "## Tabbed"   (変化した: true)
  "## Trailing  " → label "Trailing" → rename 後 "## Trailing" (変化した: true)
  "##   x   y  " → label "x   y"    → rename 後 "## x   y"    (変化した: true)
マップのラベル編集は 1 打鍵ごとに rename を投げる — src/mindmap.ts:1273-1276:
```
this.editor.addEventListener("input", () => {
  if (this.editingId !== -1) { this.host.rename(this.editingId, this.editor.value, this.editingTag); ... }
});
```

**負債**: 「編集した見出し行だけ正規化する」という仕様(core/cmds.mbt:230 のコメント)は妥当だが、正規化の対象が「ユーザが打った文字」ではなく「行全体の書式」になっている。ラベルは parser が hs..he から再生成する派生値(core/parser.mbt:113-124)なので、書式(空白の数・タブ・末尾空白)を保持する場所がどこにも無い。ATX の閉じ `#` も label に含まれてしまう("## Closed ##" → label "Closed ##")ため、マップ表示が他の Markdown レンダラと食い違う。

**このままだと顕在化するバグ**: 表を整形するために見出しをタブ揃えしている文書、あるいは末尾 2 スペース(hard break)を使っている文書で、ノードを 1 文字リネームしただけで整形が崩れる。ATX 閉じ `##` を使う文書ではマップに "Closed ##" と表示され、ユーザがそれを消して "Closed" にリネームすると閉じ記号がファイルから消える。どちらも「見出し 1 行だけ触ったつもり」なので diff レビューで見落とされる。

**修正コスト**: 約 10-25 行。cmd_rename を「hs..he のうちラベル部分 [label_start, label_end) だけを置換」に変える。そのためには Heading に label_start を持たせる(core/parser.mbt:119-126)必要があり、core/doc.mbt:296-307 の Node にも 1 フィールド増える。

### D-8 / `core/doc.mbt:266-276, core/cmds.mbt:437-515, core/cmds.mbt:597-618` / 未検証

**`---` の所属が移動で別ノードに付け替わり、コピーでは持ち越されない**

**根拠**: 入力 `# R\n\n## A\n\n---\n\n## B\n\n## C\n` (groups: A=0, B=1, C=1)
moveNodes([B], C, 0) の実測 → "# R\n\n## A\n\n---\n\n## C\n\n### B\n"、groups は A=0, **C=1**
  ← B を動かしただけで、B に付いていたグループ境界が C に移った。
入力 `# R\n\n## A\n\nsome text\n\n---\n\n## B\n\n## C\n` (A=0, B=1, C=1)
reorderNode(A, +1) → "# R\n\n## B\n\n## A\n\nsome text\n\n---\n\n## C\n"、groups は B=0, A=0, **C=1**
判定は core/doc.mbt:270-275:
```
while hp < heads.length() && heads[hp].hs < s_start { hp = hp + 1 }
if hp < heads.length() && is_blank_range(s_next, heads[hp].hs) { seps.push(s_start) }
```
= セパレータは「直後の見出し」に効く。移動は [hs, sub_end) しか動かさないので `---` は取り残される。

**負債**: group という構造情報が、ノードにも Edit にも属さない「テキスト上の位置関係」としてしか存在しない。move_block(core/cmds.mbt:437-515)はブロックを [nd.hs, nd.sub_end) で切り出すが、そのブロックの group 境界を決めているのは hs の *手前* にある `---` なので、移動プリミティブの守備範囲の外にある。selection_text(core/cmds.mbt:603)も同じ理由で `---` を含めない。

**このままだと顕在化するバグ**: グループ分けを使って整理したマップで、1 ノードを別の親にドラッグしただけで、動かしていない兄弟のグループ境界が入れ替わる。ユーザから見ると「触っていないノードの見た目が変わった」現象で、undo で戻すまで原因が分からない。コピー&ペーストではグループが常に消えるので、部分木を複製すると整理が壊れる。

**修正コスト**: 約 30-50 行。move_block / cmd_delete の対象範囲を「直前の採用済み `---` を含む」よう拡張し、selection_text も同様にするか、group を Node の派生ではなくブロックの属性として運ぶ。undo の invert は既存機構でそのまま通る。

### D-9 / `core/parser.mbt:152-173, core/doc.mbt:266-276` / 未検証

**setext 見出しの下線が group 区切りとして誤読される**

**根拠**: 入力 `# R\n\n## A\n\nSubtitle\n---\n\n## B\n`
nodes/groups = [R:0, A:0, **B:1**]  ← "Subtitle" の setext H2 下線がグループ境界として採用されている
core/parser.mbt:152-173 の is_separator は「先頭空白 3 個まで + `-` 3 個以上 + 行末まで空白」しか見ておらず、直前の行が段落かどうかを一切見ない。core/doc.mbt:273 の採用条件も「セパレータの次行から次の見出しまでが空白のみ」だけなので、setext 下線 + 空行 + 見出し という並びを区別できない。

**負債**: CommonMark では `---` の意味は直前行に依存する(段落の直後なら setext heading、そうでなければ thematic break)。パーサは行単位のスキャナとして設計されており(core/parser.mbt:1-3 のコメント)、直前行の状態を持たないのでこの区別ができない。同時に setext 見出しそのものは見出しとして認識されないので、`Subtitle` はノードにならず本文扱いのまま残る。

**このままだと顕在化するバグ**: setext 記法で書かれた既存の Markdown(Jekyll/Hugo の古い記事など)を開くと、本文中の下線の数だけマップに説明のつかないグループ境界が現れる。ユーザがそのグループを消そうとして `---` を消すと setext 見出しが段落に化け、外部レンダラでの見た目が変わる。逆に mmm で新しい兄弟をグループ分割(split)付きで追加すると、setext 下線の位置と mmm の `---` が混ざって、どちらがどちらか判別できなくなる。

**修正コスト**: 約 10 行。is_separator の呼び出し側(core/parser.mbt:99)に「直前行が空行 or 行頭」という条件を足す。core_test.mbt のセパレータ系テストと、既存文書の group 番号が変わる点の確認が要る。

### D-10 / `src/main.ts:399-421, src/main.ts:402, core/parser.mbt:73-87` / 未検証

**未閉フェンスを含む断片の貼り付けが後続の見出しを全部飲み込む / 見出しの無い断片は無言で捨てられる**

**根拠**: (a) 未閉フェンス: 文書 `# R\n\n## A\n\n## B\n\n## C\n` の A に clip `"## Snippet\n\n```js\nconst x = 1;\n"` を貼る(hasHeadings は true を返す)。
  結果テキスト = "# R\n\n## A\n\n### Snippet\n\n```js\nconst x = 1;\n\n## B\n\n## C\n"
  結果 nodes = [R, A, **Snippet**] のみ ← B と C がフェンス内に飲まれてノードから消え、Snippet.subEnd が EOF になる。
(b) 見出し無し: 同じ文書で clip `"- item one\n- item two\n"` を貼ると src/main.ts:402 `if (!hasHeadings(normalized)) return;` で何も起きない(getText は不変)。エラーもトーストも無い。

**負債**: 貼り付けが「断片をそのままテキストに挿入する」だけで、挿入後の構造が壊れないかの検証をしていない。フェンス状態は文書全体をまたぐグローバル状態(core/parser.mbt:67-69 のループローカル変数)なので、断片単体では balanced に見えても挿入すると後続を破壊する。hasHeadings ゲート(src/main.ts:402)は逆に安全側に倒しすぎていて、正当な入力を黙って捨てている。

**このままだと顕在化するバグ**: AI チャットや Stack Overflow からコード片ごとコピペする典型的な操作で、貼った瞬間に下半分のノードがマップから消える。テキストは残っているのでユーザは「壊れていない」と思うが、消えた領域は Snippet ノードの subEnd に入るので、Snippet を削除するとそこから EOF まで全部消える(この監査の項目 4 と同じ経路)。見出し無し貼り付けの方は「貼れない」というだけだが、原因が clipboard の中身にあるので何度やっても失敗し、ユーザは機能が壊れていると判断する。

**修正コスト**: (a) 約 20 行 — 挿入前に断片のフェンス収支を数え、奇数なら閉じフェンスを補うか拒否+通知。(b) 約 10 行 — hasHeadings で弾く代わりに、見出し無し断片はアンカーの本文行として挿入する(insertContentLine src/main.ts:722 が既にある)。

---

## 観点: 状態の重複と DOM を状態源にしている箇所

## 結論

MAP.md 4.6 の 15 行はすべて実在を確認した。訂正は 2 点、追記は 6 点。ただし「重複しているが壊れない」行と「すでに壊れている行」を分けないと指摘として意味がないので、まずその切り分けを述べる。

### 壊れない重複（構造が守っている）

- **ノードツリー**（`st.nodes` / `nodes`+`byId`(src/main.ts:181-182) / `boxes`+`order`(src/mindmap.ts:555, :292)）と **ノード id の DOM コピー**（`g.dataset.id`, src/mindmap.ts:595）は、今日は絶対にズレない。理由は一つだけで、`applySnap` が無条件に `map.render()` を呼び(src/main.ts:198)、`render()` が `edgeLayer.replaceChildren()` / `nodeLayer.replaceChildren()`(src/mindmap.ts:558-559) で DOM を全部捨てるから。つまり **F-002 の「毎回全再構築」は性能上の欠陥であると同時に、5 つのキャッシュ（`order` / `boxes` / `sideOf` / `frameOf` / `dataset.id`）の唯一の整合性保証になっている**。F-002 を素直に直すと、この 5 つは無効化プロトコルを持たない独立キャッシュに変わる。これが本監査で見つけた最大の構造的負債（項目 4）。
- **ペイン可視性**。プロンプトの仮説（`togglePaneVis` が DOM を読み戻している）は**誤り**。`togglePaneVis`(src/main.ts:938-943) は `paneVis`(src/main.ts:914) を読んでいて DOM は読まない。`applyPaneVis`(src/main.ts:919-936) が JS 変数・5 個の class・localStorage を一括で書く単一書き込み口になっている。MAP.md 4.6 のこの行は「重複しているが単一書き込み口なので破れない」と書き直すべき。

### 実際に破れている / すでに破れている重複

1. **アクセント色** — `applyColor` が `documentElement.style` に `--accent-soft` をインラインで書く(src/main.ts:140)。インラインは `:root.light`(src/style.css:26) に無条件で勝つ。`applyColor` は boot で無条件に走る(src/main.ts:1100)。よって **`:root.light { --accent-soft: rgba(89,50,255,0.12) }` は初回ロードの瞬間から到達不能な死んだ宣言**。ライトテーマの選択ハイライト・ボタン hover・ラバーバンドはすべてダーク用の alpha 0.2 のまま。これは「破れうる」ではなく「もう破れている」。
2. **テーマ** — 実効値は `documentElement.classList.contains("light")` だけ(src/main.ts:1077, :1089)。JS 変数はない。かつ `applyTheme` が末尾で無条件に `localStorage` に書く(src/main.ts:1081)ため、**boot の `applyTheme(stored ?? osLight ...)`(src/main.ts:1098) 自身が `stored` を作ってしまい、`prefers-color-scheme` は生涯で 1 回しか効かない**。`src/style.css` に `@media` は 0 件（`grep -c` で確認）なので CSS 側の受け皿もない。
3. **ロゴのパス文字列** — 3 箇所に逐語コピー(index.html:16 / public/favicon.svg:3 / src/main.ts:121)されており、**すでに食い違っている**。index.html:15 と src/main.ts:126 は `translate(27.2,23) scale(0.68,0.68)`、public/favicon.svg:3 は `translate(117.2,23) scale(-0.68,0.68)`。index.html:14 のコメントが「パスは既に左右反転済み。scale は正のまま使うこと」と明記しているので、favicon.svg は**もう一度反転している別のグリフ**。しかも色が `#5932FF`(大文字)固定で `--accent` に追従しない。
4. **選択集合** — 権威は `selection: Set<number>`(src/main.ts:32)。マップ側の投影は箱 1 個、md ペイン側の投影は文字範囲 `{from: n.hs, to: n.subEnd}`(src/main.ts:216)。この 2 つの投影は F-005（2 個目以降の `#` 見出しが前ノードの `subEnd` に飲まれる）で必ず食い違う。**同じ id が、マップでは 1 ノード、md ペインでは見えないブロックを含む範囲を指す**。
5. **編集中ラベル** — `st.text` の見出し行 / `editor.value`(src/mindmap.ts:904) / `Box.n.label` の 3 つ。`cmd_rename` は `sanitize_label`(core/cmds.mbt:16)で正規化した結果が現在と同じなら何もしない(core/cmds.mbt:239-241)ので、**正規化で消える文字（前後空白）は `editor.value` にだけ残り、コミットで無言に消える**。

### DOM を状態源にしている箇所（全件、厳しめの評価）

| 読み戻し | 場所 | 評価 |
|---|---|---|
| `classList.contains("light")` | src/main.ts:1089 | テーマの唯一の真実。項目 2。 |
| `getComputedStyle(:root).--accent` | src/main.ts:167, :169 | アクセント色の唯一の in-memory 読み出し。同一ハンドラ内で 2 回呼んでいる。無効値なら `applyColor` は黙って return(src/main.ts:133) するので、`--accent` はインラインに書かれず `:root` の既定値にフォールバックし、**ファビコンだけ更新されない**という半端な状態になりうる。 |
| `getComputedStyle(el)` × 11 プロパティ | src/mindmap.ts:818, :855 | `exportSvg` はライブ CSS を唯一のテーマ源にしている。同時に `querySelectorAll(".selected, .drop-child, .dragging")`(src/mindmap.ts:795) で**選択状態も DOM から読み戻している**。strip → clone → inline → restore は 831 行目まで完全に同期なので今日は安全だが、この関数に `await` を 1 つ足すと選択クラスが復元されないまま他コードから見える窓が開く。 |
| `g.dataset.id` を `Number()` で読み戻し | src/mindmap.ts:1222, :1609, :1679, :1810 | 唯一の書き手は `render()`(:595)。今日ズレないのは全再構築のおかげ（項目 4）。`Number(undefined) === NaN` で無言に false になる形なので、ズレたときに例外が出ない。 |
| `classList.contains("link-open")` | src/mindmap.ts:1206, :1251, :1256 | リンク URL は `data-url` 属性にしか存在しない(:645)。dblclick / click / pointerdown の 3 判定が同じ文字列に依存。 |
| `document.activeElement` | src/main.ts:895, :934, :935, :950 / src/mindmap.ts:998 | 「どちらのペインが現在か」の唯一の状態源。項目 3 で 2 つの具体的な破れ方を示す。 |
| `rubber.style.width/height` を `parseFloat` | src/mindmap.ts:1145-1147 | 「実際にドラッグしたか」がインライン CSS 文字列としてだけ存在する。`pointercancel`(:1198) は `display` だけ戻して width/height は残すので、次のジェスチャは前回の寸法を持ったまま始まる（`display` チェックが救っているだけ）。 |
| `menu.offsetWidth/offsetHeight` | src/mindmap.ts:1796-1797 | 表示してから実測してクランプ。強制同期レイアウトだが状態源としては妥当。 |
| ボタンの `textContent` / `disabled` | — | **読み戻している箇所は 0 件**（`grep` で確認）。`btnTheme.textContent`(src/main.ts:1079)、`btnUndo/btnRedo.disabled`(src/main.ts:200-201)、`elDirty.hidden`(src/main.ts:207) はすべて書き専用。ただしこれは安全ではなく、**誰もガードに使っていない**ことを意味する（項目 7）。 |

以下、各項目に「どのイベント順序でズレるか」を書く。

### D-1 / `src/main.ts:140, src/main.ts:1100, src/style.css:26, src/style.css:9` / 未検証

**ライトテーマの --accent-soft は初回ロードの瞬間から到達不能（すでに壊れている重複）**

**根拠**: src/main.ts:138-140:
  const rootStyle = document.documentElement.style;
  rootStyle.setProperty("--accent", c);
  rootStyle.setProperty("--accent-soft", `rgba(${r}, ${g}, ${b}, 0.2)`);
src/style.css:26 (`:root.light` 内):
  --accent-soft: rgba(89, 50, 255, 0.12);
src/main.ts:1100 (boot, 無条件):
  applyColor(localStorage.getItem(LS_COLOR) ?? DEFAULT_COLOR);
なお `:root.light`(src/style.css:19-32) は `--accent` 自体は上書きしていない。上書きしているのは `--accent-soft` だけ。

**負債**: `--accent-soft` は `--accent` からの派生値だが、派生ロジックが CSS(`:root` / `:root.light` の 2 つのリテラル)と JS(applyColor の rgba 生成)の 2 箇所に独立に書かれている。JS 側は documentElement のインラインスタイルに書くので、セレクタ由来の宣言には常に勝つ。テーマ依存の alpha を CSS に持たせた設計と、色を JS のインラインで持たせた設計が正面衝突している。

**このままだと顕在化するバグ**: すでに顕在化している。イベント順序:(1) boot で src/main.ts:1100 の applyColor が無条件に走り、インライン --accent-soft = alpha 0.2 が確定する。(2) ユーザがテーマボタン(src/main.ts:1087)を押して light にする。(3) `:root.light` の alpha 0.12 はインラインに負けて一切効かない。結果、ライトテーマでは選択ノードの塗り(src/style.css:250 の color-mix は --accent 直参照なので無関係)、`#topbar button:hover`(src/style.css:80)、`.cm-mmm-selected`(src/style.css:93)、`#rubber` の背景(src/style.css:273)、`#map-pane.pane-focused` のリング(src/style.css:113)がすべてダーク用の濃さのまま白背景に乗る。今後カラーピッカーで淡色(例 #ffe066)を選ぶと、ライト背景 + alpha 0.2 で選択ハイライトが視認不能になる、という形でユーザに届く。

**修正コスト**: 小。src/style.css:26 の宣言を削除して applyColor をテーマ依存にする(alpha を light/dark で分ける)か、逆に applyColor から --accent-soft の書き込みを外して CSS に `color-mix(in srgb, var(--accent) 20%, transparent)` を書く。後者なら実質 差し引き -3 行、影響範囲は applyColor 1 関数と style.css 2 行。

### D-2 / `src/main.ts:1076-1085, src/main.ts:1095-1099, src/main.ts:1089` / 未検証

**applyTheme 自身が localStorage を書くので prefers-color-scheme は生涯 1 回しか効かない**

**根拠**: src/main.ts:1076-1084:
  function applyTheme(t: Theme): void {
    document.documentElement.classList.toggle("light", t === "light");
    editor.setTheme(t !== "light");
    btnTheme.textContent = t === "light" ? "◐" : "◑";
    try { localStorage.setItem(LS_THEME, t); } catch {}
  }
src/main.ts:1096-1098 (boot):
  const stored = localStorage.getItem(LS_THEME) as Theme | null;
  const osLight = window.matchMedia?.("(prefers-color-scheme: light)").matches;
  applyTheme(stored ?? (osLight ? "light" : "dark"));
src/main.ts:1089 (トグルは DOM を読み戻す):
  document.documentElement.classList.contains("light") ? "dark" : "light"
`src/style.css` の @media 件数は 0（grep -c "@media" src/style.css = 0）。

**負債**: テーマの実効値が documentElement の class にしかなく(JS 変数なし)、その永続化コピー(localStorage `mmm.theme`)を書く関数が「明示的なユーザ選択」と「OS 由来の既定値の適用」を区別していない。src/main.ts:1073 のコメントは `default = OS, fallback dark` と宣言しているが、実装は OS 追従を一度きりの初期化に降格させている。

**このままだと顕在化するバグ**: イベント順序:(1) ダークの OS でアプリを初めて開く → src/main.ts:1098 が applyTheme("dark") を呼ぶ → LS_THEME="dark" が書き込まれる。(2) ユーザはテーマボタンを一度も押していない。(3) OS をライトに切り替えてリロード → `stored`(="dark") が非 null なので `osLight` は評価されるが捨てられ、アプリだけが黒いまま。以後この状態は永久に続き、ユーザから見ると「OS テーマに追従しないバグ」。@media が 0 件なので CSS 側の救済もない。将来 `mmm.theme` に "system" を足そうとしたとき、既存ユーザ全員の localStorage が "dark"/"light" で汚染済みなので移行不能になる、という二次被害まで確定している。

**修正コスト**: 小。applyTheme に `persist: boolean` を足し、boot の呼び出しだけ false にする(+3 行)。加えて matchMedia の change リスナを 4 行。合計 ~8 行、影響範囲は applyTheme の呼び出し元 2 箇所(src/main.ts:1088, :1098)のみ。

### D-3 / `src/main.ts:950-956, src/main.ts:934-935, src/main.ts:1135, src/mindmap.ts:920-924, src/mindmap.ts:1290-1292` / 未検証

**document.activeElement を「現在のペイン」の状態源にしており、endEdit の pane.focus() がフォーカス移動を奪い返す**

**根拠**: src/main.ts:948-957:
  function togglePane(): void {
    if (mdPane.contains(document.activeElement)) { ...; mapPane.focus(); }
    else { if (!paneVis.md) applyPaneVis({...paneVis, md:true}); editor.focus(); }
  }
src/mindmap.ts:1290-1292:
  this.editor.addEventListener("blur", () => {
    if (this.editingId !== -1) this.host.commitEdit();
  });
src/mindmap.ts:920-924:
  endEdit(): void { this.editingId = -1; this.editingTag = "";
    this.editor.style.display = "none"; this.pane.focus(); }
`#node-editor` は map ペインの子(src/mindmap.ts:243-246)。Mod+/ のハンドラは capture 段(src/main.ts:882-910, {capture:true})なので、editor keydown の stopPropagation(src/mindmap.ts:1282) より先に走る。

**負債**: 「どちらのペインがアクティブか」という状態を JS に持たず、毎回 `document.activeElement` の包含判定で導出している。しかも `endEdit` がフォーカス復帰の責務まで持っている(src/mindmap.ts:924)ため、フォーカスを能動的に動かす側(togglePane / applyPaneVis)と、フォーカスが動いたことに反応する側(blur → commitEdit → endEdit → pane.focus())が、同一の同期呼び出しスタックの中で逆向きに引っ張り合う。

**このままだと顕在化するバグ**: 確定している破れ方その 1(Mod+/):(1) マップペインでラベル編集中 → activeElement は `#node-editor`。(2) Mod+/ を押す → capture 段の src/main.ts:898-901 が togglePane() を呼ぶ。(3) `mdPane.contains(activeElement)` は false なので else 枝 → src/main.ts:955 `editor.focus()`。(4) その .focus() の中で `#node-editor` に blur が同期発火 → src/mindmap.ts:1291 → host.commitEdit()(src/main.ts:339) → map.endEdit() → src/mindmap.ts:924 `this.pane.focus()`。(5) map ペインは表示中なので focus は成功し、フォーカスはマップに戻る。Mod+/ が無反応に見える。
破れ方その 2(boot、確認済み):src/main.ts:1101-1108 で `mmm.panes` が "md," (マップ非表示)だった場合、src/main.ts:1135 の `mapPane.focus()` は display:none の要素への focus なので no-op。md ペインは誰も focus しない。結果 activeElement は body のまま起動し、`#map-pane` の keydown(src/mindmap.ts:1295) も CodeMirror も反応しない。
未確認:src/main.ts:934-935 の救済は「class を付けた直後に contains() が真を返すか」というブラウザのフォーカス再計算タイミングに依存する。既にブラウザが blur 済みなら activeElement は body になり救済が発火せず、フォーカスが body に落ちる。決着方法:md ペインに CodeMirror のフォーカスがある状態で MD ボタンを押し、直後に `document.activeElement` を読む。

**修正コスト**: 中。endEdit からフォーカス復帰を外し、呼び出し元(src/mindmap.ts:1044, :1284, :1291 と src/main.ts:342)にフォーカス先を渡す形に変える。~15 行。加えて boot(src/main.ts:1135)を paneVis を見て分岐させる ~4 行。endEdit の呼び出し元 4 箇所すべての回帰確認が要る。

### D-4 / `src/main.ts:198, src/mindmap.ts:558-559, src/mindmap.ts:292, src/mindmap.ts:555, src/mindmap.ts:492-493, src/mindmap.ts:595` / 未検証

**5 つの派生キャッシュの整合性を「毎回全消し」だけが保証している（F-002 を直すと同時に壊れる）**

**根拠**: src/main.ts:198 (applySnap、無条件):
  map.render();
src/mindmap.ts:558-559 (render 冒頭の DOM 破棄):
  this.edgeLayer.replaceChildren();
  this.nodeLayer.replaceChildren();
render() が毎回作り直す 5 つ: this.order(:292)、this.boxes(:555)、this.sideOf / this.frameOf(:492-493 で new Map() してから placeF(:483-484) が埋める)、g.dataset.id(:595)。
読み手は別々: nodeAt は order+boxes(:1313-1314)、onKeydown の兄弟ループは *ライブの* host.nodes()(:1331, :1555)、左右ナビは sideOf(:1563)、updatePlus は frameOf(:956)、refreshSelection は dataset.id(:1810)、startDrag は dataset.id(:1609)、updateDrop は order+boxes+dataset.id(:1634, :1636, :1679)。

**負債**: 同じツリーが 6 つの表現(st.nodes / main.nodes+byId / order / boxes(Box.n は前回 render 時点の NodeInfo オブジェクト) / sideOf+frameOf / DOM の dataset.id 文字列)に存在し、無効化プロトコルは存在しない。整合性は「applySnap が例外なく render() を呼び、render() が全部作り直す」という 1 本の運用規約だけに乗っている。onKeydown が order(前回 render)と host.nodes()(ライブ)を同じ関数内で混ぜて読んでいる(src/mindmap.ts:1331 と :1544)のが、その規約への暗黙依存の証拠。

**このままだと顕在化するバグ**: F-002(5000 ノードで 1 打鍵 70.2ms、no-op undo 134.7ms)を直すには render() を差分化するしかない。差分化した瞬間、上の 6 表現は独立更新可能になり、規約は消える。最初に出るバグは高確率で drag と rubber:startDrag(src/mindmap.ts:1600-1606)は host.nodes() から subtree を計算し、その直後に dataset.id で `<g>` を引く(:1609)。差分 render が `<g>` を再利用すると dataset.id は更新されるが `dragging` クラスは残り、逆に新規作成された `<g>` には付かない。結果「ドラッグ中の半透明表示が別ノードに付く」→「host.move(ids, ...) が画面と違うノードを動かす」。onKeydown の左右ナビも sideOf が古いまま参照され、右矢印で左側に飛ぶ。いずれも例外を出さず静かに間違う(Number(undefined) が NaN になり Set.has(NaN) が false を返すだけ)。

**修正コスト**: 大。差分 render を入れるなら、rev(core/doc.mbt:53、snapshot に既に出ている src/coreApi.ts の rev)をキーにした世代管理を order/boxes/sideOf/frameOf/DOM に導入し、読み手側で世代不一致を検出して落とす必要がある。~150-250 行、src/mindmap.ts のほぼ全域。先に「dataset.id を捨てて WeakMap<SVGGElement, number> にする」だけを分離すれば ~30 行で 1 表現減らせる。

### D-5 / `src/main.ts:183, src/main.ts:295-299, src/main.ts:552, core/api.mbt:118-135, src/editor.ts:157-165` / 未検証

**コアテキストと CodeMirror 文書の照合が存在せず、replace_text の 2 つの黙殺リターンが検出されない**

**根拠**: core/api.mbt:118-135:
  pub fn replace_text(from, to, insert, tag) -> String {
    let n = st.text.length()
    if from < 0 || to > n || from > to { return snapshot() }
    let removed = sub(st.text, from, to)
    if removed == insert { return snapshot() }
    apply_sets([[Edit::{ from, to, insert, removed }]], tag)
    snapshot()
  }
→ 拒否時も成功時と区別できない snapshot が返る。
src/main.ts:183:
  if (origin !== "cm" && origin !== "load") editor.applySets(snap.editSets);
→ cm 由来の編集では editSets を捨てるので、コアが拒否しても CodeMirror は巻き戻されない。
src/main.ts:552 (保存はコア側のテキスト):
  const text = core.getText();
src/editor.ts:157-165: applySets はセット 1 つにつき 1 dispatch。ループ途中で例外が出れば前半だけが CodeMirror に入る。

**負債**: アーキテクチャ宣言(core/core.mbt:1-4)は「テキストが唯一の真実」だが、実装では CodeMirror の EditorState.doc がその完全な second copy であり、両者が一致していることを確認する assert もテストもランタイム検査も 1 つもない(MAP.md 6.3 で確認)。しかも一致が破れたときに最初に被害を受けるのは表示ではなく保存(src/main.ts:552)と dirty 判定(src/main.ts:207)で、どちらもコア側だけを見る。

**このままだと顕在化するバグ**: 顕在化の形:ユーザは md ペインに見えているテキストを保存したつもりで、コアのテキストが .md に書かれる。差が 1 文字でも、以後 md ペインでの編集オフセットはコア座標系とズレ続け、`to > n` で replace_text が黙って拒否を始め、md ペインだけが編集を受け付けているように見える(打鍵は反映されるがマップが動かない)。ここから復帰する手段はリロードだけで、しかも `mmm.text`(src/main.ts:105)にはコア側のテキストが 250ms ごとに書かれているので、リロードすると md ペインの内容が失われる。
引き金として最も現実的なのは src/editor.ts:158-164 のループ途中の例外(セット #2 が CodeMirror の範囲外で RangeError)。cmd_outdent(core/cmds.mbt:380-427)や cmd_move(core/cmds.mbt:519-570)は 1 コマンドで複数セットを返すので、この形の多セット snapshot は日常的に発生する。
未確認:今日この不一致を生じさせる具体的な入力列は特定できていない(initDoc/setText は同一文字列で開始する、src/main.ts:478-479)。決着方法は `applySnap` の末尾に開発時限定で `console.assert(core.getText() === editor.view.state.doc.toString())` を 1 行入れ、既存操作を一通り流すこと。これは 1 行で恒久的な検出器にもなる。

**修正コスト**: 小(検出)/中(恒久対策)。検出は src/main.ts:204 付近に import.meta.env.DEV ガード付きの 1 行 assert。恒久対策は replace_text の拒否を snapshot と区別可能にする(core/api.mbt に rejected フラグを足す ~6 行 + core/js/exports.mbt + src/coreApi.ts の型)か、applySets を 1 トランザクションにまとめて原子化する(~10 行)。

### D-6 / `src/main.ts:678, src/mindmap.ts:1155-1161, src/mindmap.ts:1615-1667, src/mindmap.ts:1669-1682, src/mindmap.ts:592, src/mindmap.ts:229-235` / 未検証

**ドラッグ中に非同期 render が走り、dropTarget と boxes が食い違ったままドロップが確定する**

**根拠**: src/main.ts:676-678 (loadAsset、applySnap を経由しない render):
  const url = URL.createObjectURL(await fh.getFile());
  assetUrls.set(path, url);
  map.render();
src/mindmap.ts:1155-1161 (pointerup、前回の pointermove の結果をそのまま使う):
  if (this.dragging) {
    const drop = this.dropTarget;
    const ids = this.dragging.ids;
    this.stopDragVisuals();
    if (drop) this.host.move(ids, drop.id, drop.pos);
render() が復元するクラスは `dragging` だけ(src/mindmap.ts:592 の `this.dragging?.subtree.has(n.id)`)。`drop-child` は render のクラス文字列(src/mindmap.ts:585-594)に含まれず、updateDrop(:1680)でしか付かない。
dropLine は viewport の子(src/mindmap.ts:229-235)なので nodeLayer.replaceChildren() では消えない。

**負債**: ドロップ先という状態が「最後の pointermove 時点の boxes に対する判定結果」として `this.dropTarget` に凍結されている一方、`this.boxes` は pointer イベントと無関係な非同期経路(画像サムネイル解決 → src/main.ts:678)から更新されうる。再検証のタイミングが pointermove にしかない。

**このままだと顕在化するバグ**: イベント順序:(1) 画像を含む md を開き、サムネイルはまだ未解決(placeholder)。(2) ノードをドラッグし、あるノードの上でポインタを止める → updateDrop が dropTarget={id:A, pos:2} を確定し、drop line を描く。(3) この瞬間に loadAsset が解決 → src/main.ts:678 の render() が走る。画像行 1 本で heightOf が IMG_ROW=76px 増え(src/mindmap.ts:82, :390)、calcV/placeF がその部分木全体を再配置する。ポインタの下にあるノードは B に変わる。(4) ポインタを動かさずに離す → src/mindmap.ts:1159 が古い A に対して host.move を実行する。ユーザは B の下にドロップしたのに A の下に入る。
同時に視覚も割れる:`drop-child` のリングは render で消え、drop line だけが残る(dropLine は nodeLayer の外)。spec 3.3.2 が「ドロップインジケータは必須」としている 2 要素の片方だけが消えた状態でドロップが確定する。

**修正コスト**: 小。pointerup の先頭で `this.updateDrop(e.clientX, e.clientY)` を呼び直す(+1 行)か、render() の冒頭で `if (this.dragging) this.dropTarget = null` として明示的に無効化する(+1 行)。より正しくは render に「ドラッグ中は drop-child も復元する」を足す ~4 行。合計 ~6 行、影響範囲は src/mindmap.ts の 2 メソッド。

### D-7 / `src/main.ts:200-201, src/main.ts:492-499, src/main.ts:901-906, src/mindmap.ts:1411-1414` / 未検証

**Undo 可否がボタンの disabled 属性にしか無く、誰も読まないので空スタックの Mod+Z が全描画を走らせる**

**根拠**: src/main.ts:200-201 (唯一の書き込み、JS 変数への写しはない):
  btnUndo.disabled = !snap.canUndo;
  btnRedo.disabled = !snap.canRedo;
src/main.ts:492-499 (読まずに実行):
  function doUndo(): void { applySnap(core.undo(), "core"); syncSelectionViews(false); }
  function doRedo(): void { applySnap(core.redo(), "core"); syncSelectionViews(false); }
src/main.ts:901-906 の Mod+Z/Mod+Y と src/mindmap.ts:1411-1414 の `u` キーはどちらもガードなしで doUndo を呼ぶ。
grep 結果:`.disabled` の出現は src/main.ts:200, :201 と src/mindmap.ts:1779 のみ。読み戻しは 0 件。

**負債**: Undo スタックの深さという状態が、コア(core/doc.mbt:51-52)と DOM の disabled 属性の 2 箇所にあり、DOM 側は「表示のためだけ」に存在してロジックからは不可視。結果、キーボード経路にはガードが一切なく、コスト判断が呼び出し側でできない。canUndo/canRedo は snapshot に載っている(core/api.mbt:38, :40)のに JS 変数に写されていない。

**このままだと顕在化するバグ**: F-002 の測定がそのまま帰結。5000 ノードの文書で空の undo スタックに対し Mod+Z を押すと、core/doc.mbt:436-438 が即 return するにもかかわらず applySnap → map.render() の全 SVG 再構築 + updateDirty() の全文比較 + schedulePersist が走り、134.7ms 固まる。ユーザから見ると「戻せないのに押すと固まる」。キーリピートで押しっぱなしにすると 1 秒あたり十数回それが起き、ブラウザが応答不能になる。ボタンは disabled で押せないのに、同じ操作のキーボード経路だけが罠になっている、という一貫性のなさが原因。

**修正コスト**: 極小。canUndo/canRedo をモジュール変数に写し(+2 行)、doUndo/doRedo の先頭で早期 return(+2 行)。合計 4 行。副次的に「disabled は状態源ではない」ことをコードで明示できる。

### D-8 / `src/main.ts:627-642, src/main.ts:687-701` / 未検証

**assetUrls の null が三義(読込中/許可待ち/欠落)で、unlockAssets が拒否時もリスナを外すため再試行不能**

**根拠**: src/main.ts:627-629 (コメント自身が三義を認めている):
  /** objectURL cache keyed by md-relative image path; null = not resolved
   * (loading, permission pending, or missing file). */
  const assetUrls = new Map<string, string | null>();
src/main.ts:691-699:
  void (async () => {
    const q = await dh.queryPermission({ mode: "read" });
    const ok = q === "granted" ||
      (q === "prompt" && (await dh.requestPermission({ mode: "read" })) === "granted");
    window.removeEventListener("pointerdown", unlockAssets, true);
    if (ok) for (const p of pending) void loadAsset(p);
  })().catch(() => {});
removeEventListener は `if (ok)` の外にあり、無条件に実行される。

**負債**: 画像 1 枚あたりの状態が「URL 文字列 | null」の 2 値に潰されており、実際には 4 状態(未着手 / 読込中 / 許可待ち / 欠落)ある。区別できないので再試行の判断が「pending が 1 件以上あるか」という粗い条件でしか書けず、リトライ機構(unlockAssets)は 1 回きりの使い捨てになっている。IndexedDB の `dir`(src/main.ts:716)と `dirHandle`(src/main.ts:625)という別軸の重複も、この曖昧さの上に乗っている。

**このままだと顕在化するバグ**: イベント順序:(1) リロード直後、IndexedDB から dirHandle が復元される(src/main.ts:1122-1131)が権限は "prompt"。(2) 最初の pointerdown で unlockAssets が発火し requestPermission が出る。(3) ユーザが誤って「ブロック」を押す。(4) src/main.ts:697 が無条件に走ってリスナが外れる。(5) 以後そのセッションでは、後から許可し直しても、別のノードをクリックしても、画像は永久に placeholder(src/mindmap.ts:703-720)のまま。リロード以外に復帰手段がない。
さらに、存在しないファイルも null のままなので pending に残り続け、`pending.length === 0` による早期 return(src/main.ts:690)が永久に成立しなくなる。「壊れたリンク 1 本があるだけで、全 pointerdown で unlockAssets のクロージャが走り続ける」形にもなる(リスナが外れるまで)。
未確認:src/main.ts:692 の `await dh.queryPermission(...)` を挟んでから requestPermission を呼ぶため、ユーザアクティベーションが残っているかはブラウザ依存。決着方法は Chrome で実際に「毎回確認」設定にして pointerdown 経路を通すこと。

**修正コスト**: 中。assetUrls の値を `{state: "loading"|"pending"|"missing"|"ok", url?: string}` に変える ~25 行(src/main.ts:629, :636-642, :677, :689, :832-834, :1128-1130 の 6 箇所)。unlockAssets のリスナ除去を `if (ok)` の中に移すだけなら 1 行で最悪の症状は消える。

### D-9 / `src/main.ts:569, src/main.ts:600-610, src/main.ts:475` / 未検証

**ファイル名表示 elFilename が「表示名」と「一時エラー通知」の 2 役を兼ね、error クラスが条件より長生きする**

**根拠**: src/main.ts:600-609:
  let flashTimer = -1;
  function flashFilename(msg: string, isError = true): void {
    elFilename.textContent = `${fileName} — ${msg}`;
    elFilename.classList.toggle("error", isError);
    if (flashTimer !== -1) window.clearTimeout(flashTimer);
    flashTimer = window.setTimeout(() => {
      flashTimer = -1;
      elFilename.textContent = fileName;
      elFilename.classList.remove("error");
    }, 4000);
  }
src/main.ts:569 (saveFile 内、classList も flashTimer も触らない):
        elFilename.textContent = fileName;
src/main.ts:475 (loadText、同じく触らない):
  elFilename.textContent = name;
src/style.css:66: `#filename.error { color: #e5534b; }`

**負債**: ファイル名という状態が `fileName`(src/main.ts:37)、localStorage `mmm.fileName`、`elFilename.textContent`、`fileHandle.name` の 4 箇所にあるうえ、DOM の 1 箇所だけが別の状態(エラー通知)と時分割で共有されている。textContent を書く 4 箇所(src/main.ts:475, :569, :602, :607)のうち、付随する `error` クラスと `flashTimer` を管理しているのは flashFilename だけ。

**このままだと顕在化するバグ**: イベント順序:(1) 保存に失敗する(ファイルが他アプリにロックされている等) → src/main.ts:595 flashFilename("保存失敗") → textContent が赤くなり 4 秒タイマー開始。(2) ユーザが 1 秒後に「保存」を押し直し、今度は Save-As ピッカーが出て成功 → src/main.ts:569 が textContent を新ファイル名で上書きするが、`error` クラスも flashTimer もそのまま。(3) 保存は成功したのにファイル名が赤いまま残り、しかも 3 秒後に古いタイマーが発火して textContent を `fileName` に戻す。
同型の順序が loadText でも起きる:エラー表示中に別ファイルをドロップすると、新ファイル名が赤字で表示される。
これは今は見た目だけだが、`elFilename` は現状アプリ唯一の非モーダル通知チャネル(src/main.ts:546, :595, :750, :759, :769, :802, :828, :1011, :1019, :1047, :1062 の 11 箇所が使う)なので、通知が増えるほど「前の通知の色が次の通知に乗る」形で誤解を生む。

**修正コスト**: 小。elFilename の書き込みを 1 関数(setFilenameLabel)に集約し、flashTimer のクリアをそこに寄せる。~10 行、書き換え箇所は src/main.ts:475, :569, :602, :607 の 4 箇所。

### D-10 / `src/main.ts:210-222, src/main.ts:216, src/main.ts:186-195, src/editor.ts:68-84` / 未検証

**選択集合の 2 つの投影(マップの箱 / md の [hs, subEnd) 範囲)が F-005 で必ず食い違う**

**根拠**: src/main.ts:212-217:
  editor.highlight(
    [...selection]
      .map((id) => byId.get(id))
      .filter((n): n is NodeInfo => !!n)
      .map((n) => ({ from: n.hs, to: n.subEnd })),
  );
src/main.ts:186-195 の刈り込みは「id が byId に無い」ことしか見ない。id が生きたまま subEnd の意味が変わる場合は検出しない。
権威は src/main.ts:32 の `selection: Set<number>`、マップ側の投影は src/mindmap.ts:591 と :1811 のクラス、md 側の投影は src/editor.ts:68-84 の highlightField(DecorationSet)。

**負債**: 選択という 1 つの概念が、ノード id の集合(権威)、SVG のクラス(render が毎回再構築)、CodeMirror の Decoration(文書変更を通して *マップされ続ける* 独立した生存状態)の 3 表現を持つ。3 つ目だけが自前の寿命を持ち、setHighlights 効果でしか全置換されない(src/editor.ts:74-79)。そのうえ 1 つ目→3 つ目の変換関数 `{from: n.hs, to: n.subEnd}` が、マップ側の「箱 1 個」と意味的に一致しない。

**このままだと顕在化するバグ**: F-005 が確定させている顕在化:文書中の 2 個目以降の `#` 見出しはノード一覧から落ちるが、直前ノードの subEnd の内側に残る。よってその直前ノードを 1 つ選ぶと、マップでは箱が 1 個光るのに、md ペインでは見えない `#` ブロック丸ごとがハイライトされる。ユーザは「1 ノードを選んだ」と認識したまま Delete を押し、F-005 の通り無関係な `#` ブロックが消える。この時、消えた側は選択表示すらされていなかったので、原因の特定手段がない。
もう 1 つの経路:src/main.ts:199 の `if (selChanged) syncSelectionViews(false)` により、id が生き残る編集では editor.highlight が呼ばれ直さない。`host.rename`(src/main.ts:336-338)は 1 打鍵ごとに applySnap するが syncSelectionViews を呼ばないので、md ペインのハイライトは CodeMirror の変更マッピング(src/editor.ts:70 `deco.map(tr.changes)`)にだけ依存して漂う。
未確認:見出し行 [hs, he) を丸ごと置換する rename に対し、Decoration.mark の from/to がどう写るかはソースからは決められない。決着方法:ノードを選択したままラベル編集を数打鍵行い、md ペインのハイライト範囲が [hs, subEnd) と一致し続けるか目視する。

**修正コスト**: 大。根治は subEnd の定義側(F-005、core/doc.mbt:252-262 の重複 depth-1 除外)に手を入れる必要があり core テストの追加を伴う。~60 行 + core_test 数件。UI 側の緩和(applySnap の末尾で常に syncSelectionViews(false) を呼ぶ)は 1 行だが、1 打鍵ごとに CodeMirror へ余分な dispatch を出すので F-002 の負荷が増える。

### D-11 / `src/main.ts:473-488, core/api.mbt:104, src/mindmap.ts:196, src/mindmap.ts:199-200, src/mindmap.ts:932-934, src/mindmap.ts:948` / 未検証

**loadText が map の対話状態(editingId / hoverId / dragging)を戻さず、init_doc は next_id を 1 に戻すので id が別文書で衝突する**

**根拠**: src/main.ts:473-481:
  function loadText(text: string, name: string): void {
    fileName = name; elFilename.textContent = name;
    clearAssets();
    setSelection([], -1, false);       // ← selection / anchorId だけ戻す
    const snap = core.initDoc(text);
    editor.setText(text);
    applySnap(snap, "load");
    map.fitView();
core/api.mbt:104 (init_doc):
  st.next_id = 1
→ ファイルを開くたび id は 1 から振り直される。
戻されないマップ側フィールド: hoverId(src/mindmap.ts:196)、editingId / editingTag(:199-200)、dragging / dropTarget(:194-195)、pendingKey(:205)。
positionEditor(:932-934) と updatePlus(:948) はこれらの id で boxes を引く。

**負債**: 文書スコープの状態(選択、アンカー、画像キャッシュ)は loadText がリセットするのに、同じく文書スコープであるマップの対話状態は MindMap クラスの private フィールドに閉じていてリセット手段が無い。ノード id が文書横断で一意でない(init_doc がカウンタを戻す)ため、この取りこぼしが「無効な id」ではなく「別文書の有効な id」として現れる。

**このままだと顕在化するバグ**: イベント順序その 1(ホバー):文書 A で id 7 のノードにポインタを乗せる → hoverId=7。ポインタを動かさずに .md ファイルをウィンドウにドロップ(src/main.ts:857-878) → loadText → applySnap("load") → map.render() → 末尾で updatePlus()(src/mindmap.ts:727)。文書 B の id 7 の箱に対して + ボタンが表示される。ポインタはそこに無い。そのまま + をクリックすると、狙っていないノードに子が生える。
イベント順序その 2(編集中、より深刻):文書 A のラベルを編集中(editingId=7、`#node-editor` は display:block でフォーカス保持) → .md をドロップ。drop/dragover は要素にフォーカスを移さないので blur は発火せず、endEdit は呼ばれない。loadText → render → positionEditor(src/mindmap.ts:728)が boxes.get(7) を引き当てて入力欄を文書 B の id 7 の箱の上に移動する。以後の 1 打鍵ごとに src/mindmap.ts:1276 が host.rename(7, value, editingTag) を発行し、文書 B の無関係なノードのラベルが、しかも文書 A で採番した editingTag で undo にマージされながら書き換わる。
未確認:ドロップ操作が `#node-editor` の blur を発火させるかはブラウザ依存。決着方法:ラベル編集中に .md をウィンドウにドロップして document.activeElement を読む。

**修正コスト**: 小〜中。MindMap に `reset()`(endEdit + hoverId=-1 + stopDragVisuals + pendingKey クリア)を足し、loadText の setSelection の隣で呼ぶ。~14 行、影響範囲は src/mindmap.ts に 1 メソッド追加と src/main.ts:477 付近に 1 行。より根本的には init_doc で next_id をリセットしない(core/api.mbt:104 を削る 1 行)ほうが安全側だが、core テストへの影響確認が要る。

### D-12 / `src/main.ts:511-516, src/main.ts:1115-1121, src/main.ts:563-574` / 未検証

**復元したファイルハンドルの採用条件が name の一致だけで、フォルダを見ていない**

**根拠**: src/main.ts:511-513 (コメントが危険を明示している):
  /** Keep the persisted handle in lockstep with `fileHandle` — a stale
   * handle plus fresh text means Ctrl+S after reload silently overwrites
   * the WRONG file. */
src/main.ts:1115-1121:
  void idbGet<FileSystemFileHandle | null>("handle")
    .then((h) => {
      // only adopt a persisted handle that matches the restored file name —
      // a mismatch would make Ctrl+S write into the wrong file
      if (h && h.name === fileName) fileHandle = h;
    })
src/main.ts:563-574 (saveFile、persistHandle は書き込み *後*):
  if (!fileHandle) { fileHandle = await window.showSaveFilePicker({...});
    fileName = fileHandle.name; elFilename.textContent = fileName; }
  const w = await fileHandle.createWritable();
  await w.write(text); await w.close();
  persistHandle();

**負債**: 保存先という状態が `fileHandle`(src/main.ts:36、メモリ)、IndexedDB の `handle`、localStorage の `mmm.fileName`、`fileName`(src/main.ts:37)の 4 箇所にあり、突き合わせキーが「ファイル名文字列」という最も弱い識別子になっている。FileSystemHandle には `isSameEntry()` があるが使われていない。加えて persistHandle は fire-and-forget(src/main.ts:515 の `void ... .catch(() => {})`)なので、IDB と メモリ の乖離は検出されない。

**このままだと顕在化するバグ**: イベント順序:(1) `~/work/notes.md` を開いて編集・保存 → IDB に work/notes.md のハンドル、LS_NAME="notes.md"。(2) 保存ボタンから Save-As で `~/archive/notes.md` に保存し直す(同名・別フォルダ)。(3) src/main.ts:571 の createWritable が失敗する(archive がクラウド同期中でロック等)と、src/main.ts:574 の persistHandle には到達せず IDB は work/ のハンドルのまま。しかし src/main.ts:568 で fileName は既に "notes.md"(同名なので見た目の変化なし)。(4) リロード → `h.name === fileName` が真になり、work/notes.md のハンドルが採用される。(5) Ctrl+S → archive に保存したつもりの内容が work/notes.md を上書きする。コメントが防ごうとしていた事故そのものが、名前一致という条件の穴を通って起きる。
同名ファイルはプロジェクトごとの README.md / notes.md / index.md で日常的に発生するので、確率は低くない。

**修正コスト**: 小。採用判定を `h.name === fileName` から、保存時に一緒に永続化しておいたパス断片との比較、または `dirHandle?.resolve(h)` による所在確認に置き換える。~10 行(src/main.ts:1119 と persistHandle 周辺)。最小の緩和なら persistHandle の失敗を握り潰さず flashFilename で通知する +3 行。

### D-13 / `index.html:14-16, public/favicon.svg:3-4, src/main.ts:120-128` / 未検証

**ロゴのパス文字列が 3 箇所に逐語コピーされ、すでに別のグリフに分岐している**

**根拠**: index.html:14-15:
  <!-- パスは既に左右反転済みの m（ステムが右）。scale は正のまま使うこと -->
  <g transform="translate(27.2,23) scale(0.68,0.68)" fill="currentColor">
src/main.ts:126 (実行時ファビコン、同じ変換):
  `<g transform="translate(27.2,23) scale(0.68,0.68)" fill="${color}">`
public/favicon.svg:3 (静的ファビコン、*もう一度反転* + 色ハードコード):
  <g transform="translate(117.2,23) scale(-0.68,0.68)" fill="#5932FF">
path の d 属性そのものは 3 箇所とも同一文字列(src/main.ts:121 の LOGO_PATH)。共有元は無い。

**負債**: 同一のベクタ資産が、HTML インライン・静的 SVG ファイル・JS 文字列リテラルの 3 形式で複製されており、それぞれ別の変換行列と別の色指定を持つ。ビルド時に 1 箇所から生成する仕組みは無い(vite の設定にも該当処理なし)。

**このままだと顕在化するバグ**: すでに顕在化している:ページロード直後、ブラウザは index.html:7 の `<link rel="icon" href="/favicon.svg">` を読み、`scale(-0.68,...)` の *正立した* m をタブに表示する。その後 src/main.ts:1100 の applyColor が src/main.ts:143 で href を data: URI に差し替え、`scale(0.68,...)` の *左右反転した* m に変わる。タブアイコンがロード中に鏡像反転する。加えて静的側の色は `#5932FF` 固定なので、ユーザがブランドカラーを変えていてもロード瞬間だけ紫が出る。
将来の形:ロゴを変更する作業者は 3 箇所のうち 1〜2 箇所しか直さない。とくに public/favicon.svg は index.html にも main.ts にも参照が書かれていない(参照は index.html:7 の href 文字列だけ)ので grep でも辿りにくく、「タブアイコンだけ旧ロゴのまま」が長期間残る。applyColor が早期 return する(src/main.ts:133、localStorage の mmm.color が壊れている場合)と、旧ロゴが恒久的に表示される。

**修正コスト**: 小。public/favicon.svg を削除し、index.html:7 の link を空にして applyColor(src/main.ts:141-144)に生成させるか、逆に LOGO_PATH を単一モジュールに切り出して index.html のインライン SVG も実行時に注入する。~15 行 + vite の public 資産 1 件削除。最小の是正は public/favicon.svg:3 の transform を `translate(27.2,23) scale(0.68,0.68)` に直す 1 行。

