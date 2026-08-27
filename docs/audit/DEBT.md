# フェーズ2: 構造的負債

6 観点から構造的負債を洗い、各指摘を反証パスに掛けた。

| 観点 | 指摘 | CONFIRMED | 要確認 | 反証で除外 | 判定なし |
|---|---|---|---|---|---|
| 単一の真実 | 9 | 9 | 0 | 0 | 0 |
| 往復 | 10 | 10 | 0 | 0 | 0 |
| 同一性 | 7 | 7 | 0 | 0 | 0 |
| 状態の重複 | 12 | 11 | 0 | 1 | 0 |
| undo/redo の粒度 | 10 | 10 | 0 | 0 | 0 |
| 抽象の漏れ | 11 | 11 | 0 | 0 | 0 |
| **合計** | **59** | **58** | **0** | **1** | **0** |

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

**同一性の実体は「見出し行の開始文字オフセット (hs)」ただ一つである。** テキスト中に id は書かれていない。`Node.id`(core/doc.mbt:35)は `rebuild_nodes`(core/doc.mbt:247)が毎回ゼロから振り直し、前世代の id を引き継ぐ唯一の入力が `id_at : Map[hs → 旧id]`(core/doc.mbt:281-288)である。この `id_at` を作るのが `apply_sets`(core/doc.mbt:200-205)で、その中身は `map_offset`(core/doc.mbt:113-143)が「編集前の hs を編集後の hs へ写せたか、破壊されたか(-1)」を判定した結果だけである。undo/redo だけは別経路で、`Entry.before`/`after`(core/doc.mbt:29-30)に `id_pairs()`(core/doc.mbt:148)で焼いた (hs,id) 対を `pairs_map`(core/doc.mbt:157)経由で `rebuild_nodes` に渡す(core/doc.mbt:430)。`move_block` だけは `apply_sets` の後に `at_hs`(core/cmds.mbt:501-511)で id を手で書き戻し、`refresh_entry_after()`(core/doc.mbt:169)で undo エントリの `after` を貼り直す。

**`map_offset` の場合分け(実測、全 23 通り)。** 検査文書 `# root\n\n## p\n\n### t\n\n本文\n\n### sib\n` の `### t`(id 3)に対し `replace_text` を直接叩いて測った結果:

| 種別 | 位置 | 条件 | id |
|---|---|---|---|
| 挿入 | 見出しより前 / 途中 / 末尾(he) / より後 | 改行終端の有無を問わず | **保存** |
| 挿入 | 見出し先頭ちょうど | 改行(LF)で終わる | **保存**(右へ押される, core/doc.mbt:132-134) |
| 挿入 | 見出し先頭ちょうど | 改行で終わらない(= indent の `#`) | **保存**(その行の書き換え扱い) |
| 挿入 | 見出し先頭ちょうど | **改行を含むが改行で終わらない** | **窃取** — 新しく生まれた上の見出しが旧 id を継ぎ、元ノードは消える |
| 挿入 | 見出し先頭ちょうど | **CR で終わる**(LF でない) | **窃取** — 同上 |
| 削除 | 見出しより前 / 途中 / 直前 1 文字 / より後 | — | **保存** |
| 削除 | **見出し先頭ちょうど**(1 文字でも行全体でも) | — | **消失**(core/doc.mbt:126 の `return -1`) |
| 置換 | 見出し行全体(rename) / 行の途中 / より前 | — | **保存** |
| 置換 | 見出し先頭ちょうど(1→1, 1→2, 2→1 文字) | 深さを変えても | **保存**(core/doc.mbt:120-124) |

読み取れる非対称: **「改行で終わらない純挿入 = その行の書き換え = 生存」という救済規則(core/doc.mbt:128-135)に、対になる純削除の規則が無い。** 見出し先頭ちょうどの削除は無条件に -1。一方「置換」は増減どちらでも生存する。この 1 点が構造コマンド側の id 消失をすべて説明する。

**F-004 の訂正。** 「outdent は常に id を落とす」は正確ではない。落とすのは `pe == nd.sub_end`(core/cmds.mbt:407)= 「対象が親の最後のブロック」の分岐だけで、そこは `#` を 1 個 **削除**する(core/cmds.mbt:409-419)。別分岐は `move_block`(core/cmds.mbt:421)で id は保たれる。**ただし失う側は対象ノードだけでなく部分木の全見出し**が対象で(`subtree_nodes(nd.hs, nd.sub_end)` の全件に削除 Edit が出る)、実測で `### t`+3 子孫の outdent が id 3,4,5,6 を全部捨てて 7,8,9,10 を発番した。分岐に当たる頻度は低くない: 出荷 SAMPLE 文書(src/main.ts:39-58)では **深さ 3 以上のノード 3 件すべて**が消失側、`mmm.md` では 262 件中 **116 件 (44%)** が消失側だった。

**F-004 以外に id を落とす/すり替える操作(場合分けから導き、実行で確認したもの)。** ①`outdent` 最後の子分岐(部分木全滅)。②`cmd_move` の pos 1/2 で対象が深さ 1 のとき — 重複ルート抑制(core/doc.mbt:252-262)がどちらかの `#` 見出しをノード列から落とすため、pos=1 では**旧ルートの id**、pos=2 では**移動したノードの id** が消える(全ペア×3 pos の総当り 22050 回中 1800 回、すべてこの形)。現状 `updateDrop`(src/mindmap.ts:1641-1644)が深さ 1 で pos=0 を強制するので UI からは届かない(F-006)。③md ペインで**ルートの上に `# 見出し` を打つ** — 旧ルート id 1 が消え、子が新ルートへ付け替わる(実測)。④md ペインで**見出し先頭に改行入りの断片を貼る** — 新見出しが旧 id を継ぐ(窃取)。⑤`init_doc` が `next_id` を 1 に戻す(core/api.mbt:104)ため、ファイルを開き直すと id 1,2,3… が別文書の別ノードとして復活する(ABA)。⑥`move_block` の `at_hs` 復元は失敗時に無言 `None => ()`(core/cmds.mbt:507-510)。総当りでは②以外に外れは出なかったが、検知手段が無い。なお `indent` / `rename` / `add_child` / `add_sibling` / `add_parent` / `hide` / `show` / `reorder` / `delete`(対象以外)は 400 文書×11 コマンドのファズで id 消失ゼロ、id 重複ゼロ、undo のテキスト・id 復元失敗ゼロだった。

**id に依存している上位機構(全件)と、id が変わったときの挙動。** `selection`(src/main.ts:32)→ `applySnap` が生存 id で刈り込む(src/main.ts:186-191)ので**選択が消える**。`anchorId`(src/main.ts:33)→ 死ぬと選択末尾か -1(src/main.ts:192-195)。`byId`(src/main.ts:31)/`nodes`(src/main.ts:30)→ 毎スナップショットで作り直し。`snap.focus` → `runCmd`(src/main.ts:237-241)と `deleteSelection`(src/main.ts:349-353)は使うが、`indentSelection`/`outdentSelection`(src/main.ts:355-364)は**使わない**。`g.dataset.id`(src/mindmap.ts:595)→ `refreshSelection`(src/mindmap.ts:1810)、`startDrag`(src/mindmap.ts:1609)、`updateDrop`(src/mindmap.ts:1679)が文字列で読み戻す。`boxes`(src/mindmap.ts:183)/`order`(:184)/`sideOf`(:185)/`frameOf`(:186)/`contentRows`(:314)/`subV`(:424)→ 全て id キー、render で再構築。`hoverId`(:196)→ 死ぬと `updatePlus` が箱を引けず + ボタンが消えるだけ。`dragCand.id`(:193)/`dragging.ids`,`subtree`(:194)/`dropTarget.id`(:195)→ ドラッグ中に id が変わると `cmd_move` の `find_node` が -1 を返して**無言で移動しない**(core/cmds.mbt:535-537)。`editingId`/`editingTag`(:199-200)→ **回復手段が一つも無い**: 変わっても `positionEditor`(:931-934)が早期 return するだけで、以後の打鍵は `host.rename(旧id, …)` を投げ続ける。`ensureVisible`(:881)/`centerOn`(:871)→ `boxes.get(id)` が空振りして無言 return。非同期に id を跨ぐのは `addLink`/`addCode`/`addDrawing`(src/main.ts:426-457)、`pasteImage`(:838-845)、`insertContentLine`(:722)で、いずれも await 後に `byId.has(id)` を再確認している(唯一まともな防御)。

**要するに: id の寿命 = ユーザの選択・編集セッションの寿命であり、id を捨てる編集はそのまま UI 状態を捨てる編集になる。** そして「テキストが唯一の真実」というアーキテクチャ主張の代償が全部ここに集まっている — テキストには id を書けないので、位置だけが同一性の担保になり、位置を動かす編集の種類ごとに救済規則を継ぎ足す構造になっている。

なお本監査では、この問いを **19 通りの実測マトリクス**でも裏取りしている。
詳細は `audit/identity-matrix.md`。要点:

- 同一性の代理キーは**見出し行の開始文字オフセット**。`map_offset`(`core/doc.mbt`)が
  編集前オフセットを編集後へ写し、`rebuild_nodes` が `id_at` で id を再利用する。
- 19 通りを実測した結果、**id を失うのは「見出し先頭ちょうどの純削除」1 パターンのみ**
  (17 通りは保存)。
- そのため outdent は **対象が親の最後の子のときだけ** id を落とす。後続の兄弟が
  あるときはブロック移動が走り `move_block` の `at_hs` で復元される。
- **同じ位置の「置換」は深さを増減しても id を保存する**。したがって outdent が
  ハッシュを「削除」ではなく「ハッシュ列の置換」として出せば、テキストは
  バイト同一のまま id が保たれる(実測確認済み)。→ F-004

---

## 観点: 単一の真実はどちらか

### D-単一の真実-1 / CONFIRMED / `core/doc.mbt:54, core/doc.mbt:281-288, core/api.mbt:104, src/mindmap.ts:199, src/main.ts:180-204`

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

**検証の根拠**: 引用箇所は全て実在。core/doc.mbt:48-59 の St に id を持つのは Node.id と st.next_id のみで、テキスト側に id の表現は 0 バイト（core/api.mbt:64-91 の snapshot も id を出力するだけで入力しない）。core/doc.mbt:281-288 の採番、core/api.mbt:104 の `st.next_id = 1` を確認。src/main.ts:180-204 の applySnap は nodes/byId 再構築と selection(185-191)・anchorId(192-195) の刈り込みだけで、map.editingId には触れない。`grep -an editingId src/*.ts` = main.ts:341 と mindmap.ts 内 8 箇所のみ、applySnap からの参照 0 件。src/main.ts で map.endEdit() を呼ぶのは commitEdit (main.ts:339-344) 一本だけで、loadText (main.ts:473-488) は setSelection([],-1,false) するが編集セッションは閉じない。drop ハンドラ (main.ts:857-878) も blur を起こさず、clean なら confirmDiscard (main.ts:612-615) はダイアログ無しで true。host.rename (main.ts:336-338) に byId.has ガード無しも確認。cmd_rename の find_node<0 無音 return は core/cmds.mbt:232-235 に実在。

**検証による訂正**: 機構は全てコードで確認できる。ただし最後の 1 マイル（OS からのファイル drop 中に input が DOM フォーカスを保持し blur→commitEdit (src/mindmap.ts:1290-1292) が発火しないこと）はブラウザ挙動でありソースからは決められない — ここだけ 未確認。なお Ctrl+O 経路は global keydown (src/main.ts:892-897) の `mapPane.contains(document.activeElement)` で弾かれ、ツールバー「開く」ボタンはクリックで blur→commitEdit するため、この穴を通せるのは drop 経路だけ、という点はむしろ主張を補強する。

**修正コスト**: editingId の刈り込みを applySnap に足すだけなら 3〜4 行（src/main.ts:195 付近に `if (map.isEditing() && !byId.has(map.editingId)) map.endEdit();`）。loadText 側で無条件に endEdit するなら 1 行。id 空間そのものを直すのは非現実的で、寿命管理側で閉じるのが妥当。

### D-単一の真実-2 / CONFIRMED / `src/main.ts:183, src/main.ts:206-207, core/api.mbt:32-96, core/api.mbt:126-132`

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

**検証の根拠**: src/main.ts:183 の条件、core/api.mbt:126-132 の 2 つの早期 return、snapshot() (core/api.mbt:32-96) が rev/focus/canUndo/canRedo/editSets/nodes の 6 キーのみで text を持たないこと、を実地確認。早期 return が「正常な no-op」と区別不能なのも確認 — snapshot() は末尾 (core/api.mbt:93-94) で st.last_sets=[] / st.focus=-1 にリセットするため、拒否時の返り値は editSets 空・focus -1 で、成功した no-op と 1 ビットも違わない。`grep -arn "\.rev" src/` は reveal/revokeObjectURL しかヒットせず snap.rev の読み手は 0 件、`grep -arnE "assert|invariant|console.assert" src/` も 0 件。src/editor.ts が state.doc に触れるのは :151 と :173 の 2 箇所のみ。全文の照合コードはアプリ全体で src/main.ts:206-207 の updateDirty（core 側 vs savedText）だけで、CM の doc とは一度も突き合わせない。

**検証による訂正**: 「2 つの独立した権威に分裂する」は言い過ぎ。cm 経路では CM が唯一の書き手で、コアは onUserEdits が渡した編集をそのまま追随する従属側であり、両者が独立に進むわけではない。しかも core/doc.mbt:12 の sub() 由来でオフセット空間は CM と同じ UTF-16 コードユニット（audit/MAP.md:251 と一致）、かつ tr.changes.iterChanges は昇順・元文書座標なので、整合状態からは core/api.mbt:126 の範囲外拒否は起こり得ない。正しい負債の言い方は「分裂する」ではなく『一度でも（別要因で）ずれたら検出も復旧もできない設計になっている — 突き合わせ 0 行、rev 未読、拒否と no-op が区別不能、そして保存 (main.ts:552) と localStorage (main.ts:105) は共に core 側テキストを書くので CM 側にしか無い編集は消える』。

**修正コスト**: 検出だけなら applySnap 末尾に 3〜4 行（dev ビルド限定で core.getText() と editor.view.state.doc.toString() を比較して console.error）。自動復旧まで入れるなら editor.setText(core.getText()) による再同期を足して 10 行程度。

### D-単一の真実-3 / CONFIRMED / `src/main.ts:293-299, core/api.mbt:126-132, src/editor.ts:132-140`

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

**検証の根拠**: src/main.ts:293-299 は引用通りで、delta は core.replaceText の結果に関係なく無条件に加算される。core/api.mbt:119-135 の返り値 Snapshot に成否フィールドは無く（core/api.mbt:32-96 の 6 キー）、呼び出し側が適用可否を知る手段は本当に無い。src/editor.ts:133-139 の iterChanges が渡すのが fromA/toA（トランザクション適用前座標）であることも確認。

**検証による訂正**: 「将来のバグ」の引き金は独立には到達しない。iterChanges は昇順・非重複で e.to<=n0 を保証し、k 番目の呼び出し時のコア長は n0+delta なので e.to+delta<=現長・e.from+delta>=前編集末尾となり、整合状態からは core/api.mbt:126-128 の範囲外拒否は発生しない。もう一方の早期 return (core/api.mbt:130-132, removed==insert) は長さ差 0 なので delta も 0 で無害。したがってこれは単独の欠陥ではなく『第 2 項のずれが一度起きた後、以降の全編集を任意の位置へばら撒く増幅器』であり、マルチカーソル編集そのものが文書を壊すわけではない。負債としての実体は delta の算術ではなく、成否を返さない API 契約（core/api.mbt:32-96）の側にある。

**修正コスト**: replaceText の戻り値に適用可否を載せるならコア側 (core/api.mbt:119-135) と coreApi の型 (src/coreApi.ts:26-33, :42-43) で 10 行程度。呼び出し側で snap.rev の増分を見て中断するだけなら src/main.ts:295-298 に 3 行。

### D-単一の真実-4 / CONFIRMED / `src/editor.ts:113-142, src/main.ts:250-299, src/main.ts:198-203, node_modules/@codemirror/view/dist/index.js:8031-8039`

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

**検証の根拠**: node_modules/@codemirror/view/dist/index.js:8031-8039 は引用と一字一句一致（8031 が `if (!update.empty)`、8036-8038 が catch→logException）。logException は同 :1371-1379 で、exceptionSink facet が未設定なら console.error に落とすだけ（src/ に exceptionSink は 0 件）。src/editor.ts:113-142 が唯一の編集転送口であることも確認（compositionend 経路 src/editor.ts:108-111 は空配列を渡すだけ）。src/main.ts:198-203 の applySnap 後半（map.render → syncSelectionViews → ボタン状態 → updateDirty → schedulePersist）がこの listener の内側で同期実行され、途中の throw で schedulePersist (src/main.ts:110-113) に到達しないのも構造上その通り。

**検証による訂正**: 「将来のバグ」の具体シナリオは支持できない。引用された 4 つの非 null アサーションはいずれも局所的に安全: src/mindmap.ts:466/:526 の `subV.get(...)!` は直前の calcV (:436-445) が必ず set 済み、:488 の `boxes.get(id)!` は placeF (:475) が入れた id、:536 は `[...boxes.keys()]` 由来。親子閉路も起こり得ない — recompute_parents (core/doc.mbt:472-486) は文書順スタックで必ず森を作り、move_block の id 書き戻し (core/cmds.mbt:505-511) が重複 id を作ることもない（新規 id は単調増加の st.next_id 由来なので復元する旧 id と衝突しない）。よって正しい主張は『throw の引き金は現時点で未確認だが、握り潰しと、throw 時に永続化がまとめてスキップされる構造は確定している』まで。

**修正コスト**: onUserEdits の本体を try/catch で包み、catch で flashFilename に出す + applySnap の後半（永続化・ボタン状態）を finally に逃がす、で 10〜15 行。根治は applySnap を listener から出して microtask に逃がす設計変更で、影響範囲は src/main.ts:180-204 と全 origin。

### D-単一の真実-5 / CONFIRMED / `core/cmds.mbt:499-515, core/doc.mbt:166-177, core/cmds.mbt:554-566, src/main.ts:237-241`

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

**検証の根拠**: core/cmds.mbt:499-515 は引用通り。apply_sets(:493) の後に at_hs を組み(:501-504)、`None => ()`(:509) で無音のまま st.nodes[idx].id を直接代入(:508)、続けて recompute_parents/refresh_entry_after を呼び、照合結果に関係なく `st.focus = old_id`(:514)。これがシステム唯一の「テキスト由来でないツリー書き換え」であることも確認（他コマンドは全て apply_sets→rebuild_nodes 経由）。失敗時に cmd_move が黙って脱落する経路も実在: :562 で anchor=st.focus(=old_id)、次周回の find_node(anchor) が -1 で :535-537 の continue に落ちる。UI 側 src/main.ts:237 の byId.has(snap.focus) で選択が空になるだけ、も確認。

**検証による訂正**: 2 点を落とすべき。(1)「undo スタックが不変でなくなる」は過大。refresh_entry_after (core/doc.mbt:169-177) は同一コマンド内で、push 直後に、まだ誰も観測していないエントリの after を完成させるだけで、履歴の遡及書き換えではない。そもそも do_redo (core/doc.mbt:445-452) が entry.after で id を復元する以上、これが無いと redo で id が変わる — バグではなく必要な補完処理。(2) 5 ノード中 1 つだけ動く話は 未確認。base = new_hs + prefix_len の prefix_len は `moved` に前置した文字数そのもの (core/cmds.mbt:480-484)、rel は先行見出しごとに delta を累積した厳密値 (:448-451)、new_hs も削除幅を差し引いた厳密値 (:494-498) で、at2<=del_from / at2>=sub_end / at2==sub_end の各分岐を追った限りずれる筋は見つからない。`None => ()` は現状トリガの無い防御分岐であり、負債の実体は『唯一の非導出書き換えが、失敗時に例外も返り値も残さない』という設計そのもの。

**修正コスト**: 照合失敗を検出して返すようにするなら move_block に成否の戻り値を足して cmd_move / cmd_reorder / cmd_outdent の 3 呼び出し元を直す、40 行程度。最小限なら None 分岐でカウントを取り、1 件でも外れたら st.focus = -1 にする 5 行。

### D-単一の真実-6 / CONFIRMED / `src/mindmap.ts:61-68, src/mindmap.ts:475-482, src/mindmap.ts:555, src/mindmap.ts:900-904, src/mindmap.ts:931-943, src/mindmap.ts:1311-1321`

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

**検証の根拠**: src/mindmap.ts:61-68 の Box が `n: NodeInfo` を保持、代入は :555 の `this.boxes = boxes` ただ 1 箇所（`grep -an "this.boxes" src/mindmap.ts` の他 14 箇所は全て読み取り）。beginEdit が host.nodes() ではなく b.n.label を使うのは :904、nodeAt が order+boxes だけを見るのは :1311-1321。ensureVisible(:882)/centerOn(:872)/positionEditor(:933)/updatePlus(:948)/fitView(:749-760)/exportSvg(:779-784)/updateDrop(:1636,:1657,:1674) も全て boxes 読み。F-002 の通り applySnap は src/main.ts:198 で無条件に render() を呼ぶので今は常に最新。ドロップが boxes 由来の target/pos を core の tn.hs / tn.sub_end に翻訳する経路も core/cmds.mbt:544-550 で確認。F-006 に関する記述も正確: host.move の呼び出し元は src/mindmap.ts:1159 の 1 箇所だけで、その入力 dropTarget は :1641（本体判定）と :1662（外側ゾーン）の両方で depth-1 に pos=0 を強制しており、これが唯一の抑止になっている。

**検証による訂正**: 「boxes が古くなる」現象は現時点では 1 度も起きない、と明記すべき（applySnap は必ず render を呼び、非同期に nodes だけ差し替わる経路も無い。src/main.ts:678 の loadAsset も render() で追随する）。したがってこれは現存バグではなく『性能修正と正面衝突する潜在結合』であり、負債としての価値は「boxes が座標キャッシュに留まらず NodeInfo 参照（label・depth という意味論）まで抱えているので、キャッシュを差分化した瞬間に見た目と操作対象が乖離する」という一点に集約される。

**修正コスト**: Box に NodeInfo 参照ごと持たせるのをやめて id だけにし、読み手が host.nodes() から引き直す形にすると src/mindmap.ts の 8 箇所前後（:904, :963, :1620 ほか）で 30〜40 行。render 差分化に着手する前にやらないと意味がない。

### D-単一の真実-7 / CONFIRMED / `src/mindmap.ts:243-246, src/mindmap.ts:904, src/mindmap.ts:1274-1279, src/main.ts:336-338, core/cmds.mbt:16-35, core/cmds.mbt:231-247`

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

**検証の根拠**: src/mindmap.ts:1274-1279 の input ハンドラ、:904 の `this.editor.value = b.n.label`（テキスト→input はここだけ。他は :909 の空文字クリアのみ）、src/main.ts:336-338 の無ガード rename、core/cmds.mbt:232-235 と :239-241 の 2 つの無音 return を全て確認。commitEdit→endEdit で入力欄ごと消える (src/main.ts:339-344 → src/mindmap.ts:920-925)、cmd_rename が早期 return した以上 apply_sets を通らないので undo エントリも作られない（core/doc.mbt:183-241 は apply_sets 内でのみ push）も正しい。

**検証による訂正**: 「host.rename は byId.has(id) ガードを持たない唯一のミューテータ」は誤り。src/main.ts:365-367 reorder、:368-370 toggleHidden、:371-373 move も同じくガードを持たない（addChild/addSibling/addSiblingBefore/addParent/addLink/addCode/addDrawing/editRequested が持つのは記載通り）。加えて src/mindmap.ts:910 の editClear 経路も無ガードで host.rename を呼ぶ。正しくは『id を取るミューテータ 4 つ（rename, reorder, toggleHidden, move）がガード無しで、そのうち rename だけが死んだ id を延々と受け付け続ける唯一の連続入力経路である』。他の残りは全て妥当。

**修正コスト**: host.rename に byId.has(id) ガードを 1 行足す。加えて cmd_rename の失敗を snapshot の focus か新フィールドで返して map 側で endEdit する、で 10 行程度。

### D-単一の真実-8 / CONFIRMED / `core/doc.mbt:251-262, core/doc.mbt:309-317, core/cmds.mbt:279-302, core/cmds.mbt:597-624`

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

**検証の根拠**: core/doc.mbt:252-262 の重複ルート破棄、:309-317 の sub_end 決定（破棄後の heads だけを使うスタック）を確認 — 捨てられた `# ` 行は直前ノードの sub_end の内側に取り込まれる。巻き添えの 3 経路も実在: cmd_delete が [hs, sub_end) をそのまま削除範囲にするのは core/cmds.mbt:279-301、selection_text の切り出しは :601-611、cmd_toggle_hidden の `<!--`/`-->` 挿入も同じ hs/sub_end で :675-683。テストの限界も確認 — core/core_test.mbt:255-261 「duplicate roots are ignored as structure」は rename_node(2,"c2") 後の get_text() だけを見ており、削除・コピー・非表示の巻き添えは一切検証していない。

**検証による訂正**: 最後の「今後 depth-1 の重複が起きやすくなる」は速断。第 2 のルートを禁じるガードは 1 箇所ではなく複数ある — cmd_add_root (core/cmds.mbt:218-222)、cmd_add_sibling / cmd_add_sibling_before の depth==1→add_child 迂回 (:161-165, :179-182)、cmd_add_parent の depth==1 即 return (:198-200)、cmd_outdent の depth>=3 フィルタ (:386-390)。日常的に重複ルートを生む状態にするにはこれらを複数外す必要があり、現に開いている穴は F-006（move 経由）と、ユーザが md ペインに 2 つ目の `# ` を直接書く場合の 2 つ。前半（現在進行形で巻き添えが起きること）は完全に成立する。

**修正コスト**: 捨てた見出しを Node として持ち（例: depth-1 だが構造から外れたことを示すフラグ付き）sub_end の計算に参加させるのが筋。core/doc.mbt:251-320 と snapshot のノードキー（core/api.mbt:70-90）、src/mindmap.ts の描画分岐に波及して 60〜100 行。

### D-単一の真実-9 / CONFIRMED / `src/main.ts:206-207, src/coreApi.ts:37, core/api.mbt:32-96, src/editor.ts:151, src/editor.ts:173, package.json:6-13`

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

**検証の根拠**: 検証コマンドを全て再実行して一致。`grep -arn "\.rev" src/` は reveal / revokeObjectURL のみ（snap.rev の読み手 0 件、core/api.mbt:34 では毎回送出）、`grep -arnE "assert|invariant|console.assert" src/` は 0 件。src/coreApi.ts:37 の `JSON.parse` は型検査ゼロの単独信頼境界、src/main.ts:206-207 の updateDirty がアプリ唯一の全文比較で、比較相手は core 側テキストのみ。src/editor.ts が doc に触れるのは :151 と :173 だけ。package.json の scripts は 6-13 行、test 系は `test:core`（moon test）1 本のみ、devDependencies は typescript と vite のみで TS テストランナー無し、src/ に *.test.ts は 0 件。core/core_test.mbt は `grep -c "^test "` = 44 件、`editSets`/`edit_sets` の出現 0 件（全て get_text() のバイト比較）。保存経路も確認: saveFile は src/main.ts:552 で core.getText()、成功後 :582 で savedText=text、persistNow は :105 で core.getText()。

**検証による訂正**: 補足 2 点。(1) audit/tests/ に roundtrip / commands / copypaste の .test.mjs があるが、これは監査で追加した資産で package.json のどのスクリプトからも起動されない — 「プロジェクトの TS テストは 0 件」という主張自体は成立する。(2) src/editor.ts:151 は「長さチェック」ではなく setText の置換範囲としての doc.length 参照（:173 の reveal は境界チェック）。いずれも結論（コアと CM の一致を主張するコードが 0 行）を変えない。

**修正コスト**: applySnap の末尾に dev 限定の一致チェックを 4 行入れるだけで、本項の 2・3・4・6 の全部が初回発生時に console に出る:
    if (import.meta.env.DEV && core.getText() !== editor.view.state.doc.toString()) console.error("core/CM diverged", snap.rev);
テスト基盤（vitest + coreApi のモック）を入れて applySnap の origin 分岐を固定するなら 200 行規模。

---

## 観点: 往復で情報が落ちる入力

### D-往復-1 / CONFIRMED / `core/cmds.mbt:626-685, core/cmds.mbt:661-667, core/parser.mbt:88-98, core/parser.mbt:137-147`

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

**検証の根拠**: 実測で主張のバイト列を再現。`# R\n\n## A\n\narrow -->\n-->\n\n## B\n` の A を hide→show → `"# R\n\n## A\n\narrow -->\n\n-->\n## B\n"`(ユーザの `-->` 行が消え、mmm の `-->` が残骸として残る)。4スペース字下げ版も同一挙動。コードも一致: core/parser.mbt:94 の `-->` 分岐は `in_comment` が真のときしか発火しないので、開いていない裸の `-->` は core/parser.mbt:95 の regions に載らず、core/doc.mbt:250 の `st.hide_regions` にも入らない。よって core/cmds.mbt:661-667 のガード(引用は行と完全一致)は候補ゼロで素通りし、core/cmds.mbt:678-679 が挿入した `<!--` に対して裸の `-->` が閉じマーカーになり、show 側の core/cmds.mbt:647-652 がその行を削除する。core/parser.mbt:140-145(is_marker_line)は前後の空白/タブを無制限に落とすので `    -->` もマーカー扱い。hidden がテキスト再走査からしか導出されない設計は core/cmds.mbt:621-625 のコメントどおり。

**検証による訂正**: 根拠の焦点をずらすとより正確: 「ガードが不十分」ではなく、この経路ではガードの入力である `st.hide_regions` がそもそも空。真の欠陥は core/parser.mbt:94 が `-->` を `in_comment` 条件下でしか記録しないこと(= 裸の `-->` はどの状態にも残らない)。なお undo は 1 手で hide 状態(ユーザの `-->` は健在)、2 手で原文に戻る(実測)。

**修正コスト**: 約 20 行。cmd_toggle_hidden の hide 側ガードを「部分木テキストを走査して `<!--`/`-->` に一致する行が 1 本でもあれば拒否」に変える(regions ではなく行走査にする)か、show 側で「削除する close マーカーが自分の入れた位置と対応するか」を検証する。影響は core/cmds.mbt の 1 関数に閉じる。

### D-往復-2 / CONFIRMED / `core/parser.mbt:88-93, core/parser.mbt:129-131, core/doc.mbt:250, core/cmds.mbt:633-659`

**本文中の裸の `<!--` 行が無関係なノードを hidden にし、show で消える**

**根拠**: 入力 `# R\n\n## A\n\nHTML comments open with\n<!--\nand close with -->\n\n## B\n\n## C\n`
nodes → [R:false, A:false, B:**true**, C:**true**]  ← B と C が hidden 扱い
B に toggleHidden(=表示に戻す)すると:
"# R\n\n## A\n\nHTML comments open with\nand close with -->\n\n## B\n\n## C\n"  ← A の本文から `<!--` 行が消える
字下げ版 `    <!--` でも同じ: `# R\n\n## A\n\n    <!--\n\n## B\n\n## C\n` → C を show すると `    <!--` 行が消えて空行だけ残る。
scan_doc は閉じない領域を close=(-1,-1) で push する(core/parser.mbt:129-131)ので、以降の全見出しが hidden:true になる。

**負債**: `<!--` 単独行という「普通の Markdown 本文にも現れうる文字列」を、文書全体に効くグローバルな状態遷移として扱っている。しかも閉じない領域を許して(-1,-1)、その状態を hidden フラグとしてノードに焼き付ける。ユーザの意図(単なるテキスト)と mmm の制御構文が同じ字面を共有しており、逃げ道(エスケープ)がない。

**このままだと顕在化するバグ**: Markdown の書き方を説明する文書、あるいは他ツールが吐いた `<!-- prettier-ignore -->` 系の断片を貼った瞬間、以降のノードが全部グレー(hidden)表示になる。ユーザは「なぜか非表示になった」と思って表示に戻す操作をし、その 1 クリックで元の `<!--` 行が削除される。B と C を順に戻せば `<!--` の削除は 1 回だけだが、その後 hidden 表示が直らない(閉じマーカーが無いまま)ので操作を繰り返し、周辺の行を削り続ける。

**検証の根拠**: 実測一致。`# R\n\n## A\n\nHTML comments open with\n<!--\nand close with -->\n\n## B\n\n## C\n` → nodes は R:h0, A:h0, B:h1, C:h1。B に toggleHidden → `"# R\n\n## A\n\nHTML comments open with\nand close with -->\n\n## B\n\n## C\n"`(A の本文から `<!--` 行が消失)。字下げ版 `    <!--` も同様に消えて空行だけ残る。コード: core/parser.mbt:88-93 が `<!--` 単独行でグローバル状態 in_comment を立て、core/parser.mbt:125 が以降の全見出しに hidden:true を焼き、閉じない領域は core/parser.mbt:129-131 で (-1,-1) として push、core/doc.mbt:250 で st.hide_regions に格納。show 側 core/cmds.mbt:636 が `c_start == -1` のとき body_end を EOF に広げて全後続ノードを対象にし、core/cmds.mbt:638-645 が open マーカー行だけを削除する(c_start==-1 なので core/cmds.mbt:646-653 は走らない)。

**検証による訂正**: 最後の一文「その後 hidden 表示が直らない(閉じマーカーが無いまま)ので操作を繰り返し、周辺の行を削り続ける」は REFUTED。実測では B を 1 回 show した時点で `<!--` が消えるため領域自体が消滅し、B も C も同時に hidden:false に戻る(削除は 1 行 1 回きり、エスカレーションしない)。残りの主張はそのまま成立。

**修正コスト**: 約 10-30 行。最小対応は「閉じない `<!--` 領域は領域として採用しない」(core/parser.mbt:129-131 の push をやめる)。ただし hidden の意味論が変わるので core_test.mbt の hide 系テストの見直しが要る。

### D-往復-3 / CONFIRMED / `core/doc.mbt:279-308, core/cmds.mbt:597-618, src/mindmap.ts:1483-1489`

**最初の見出しより前のテキストはどのノードにも属さず、コピーで消える**

**根拠**: 入力 `---\ntitle: x\n---\n\n# R\n\n## A\n`
nodes = [R(hs=18, subEnd=28), A(hs=23, subEnd=28)]  ← hs が 0 から始まらない
selection_text([R.id, A.id]) = "# R\n\n## A\n"   ← frontmatter 3 行が含まれない
前書き散文でも同じ: `intro paragraph\n\n# R\n\n## A\n` → R.hs=17、selection_text([R]) = "# R\n\n## A\n"
マップ側には全選択がある: src/mindmap.ts:1483 `if (mod && (key === "a" || key === "A")) { this.host.setSelection([...this.order], ...) }`、src/mindmap.ts:1491 で copySelection。

**負債**: ノード配列が heads(=見出し行)からしか作られない(core/doc.mbt:279)ため、[0, heads[0].hs) の区間を指す木構造上の入れ物が存在しない。テキストが真実なので保存はされるが、木を経由するあらゆる操作(選択・コピー・移動・hide・エクスポート)からは到達不能な暗黒領域になっている。「テキストが唯一の真実」という宣言(core/core.mbt:1-4)と「木からしか操作できない UI」の間の穴。

**このままだと顕在化するバグ**: YAML frontmatter 付きの記事を mmm で開き、Mod+A → Mod+C で全部コピーして別ファイルに貼ると title/date/tags が消える。ユーザは「全部選んだ」と信じているので欠落に気づくのは公開後。さらに frontmatter の閉じ `---` は `is_separator` に拾われて最初の見出しの group 区切りとして働く(core/doc.mbt:266-276)ので、マップ上に説明のつかないグループ境界が出る。

**検証の根拠**: 実測一致。`---\ntitle: x\n---\n\n# R\n\n## A\n` → nodes = R(hs=18, subEnd=28), A(hs=23, subEnd=28)、`selectionText([R,A])` = `"# R\n\n## A\n"`(frontmatter 3 行が欠落)。前書き散文版も R.hs=17 / `"# R\n\n## A\n"`。コード: core/doc.mbt:279 のループは `heads`(= 見出し行)だけを走査し、[0, heads[0].hs) を指す入れ物を作らない。core/cmds.mbt:603 は `sub(st.text, nd.hs, nd.sub_end)` しか切り出さない。UI 側の全選択は src/mindmap.ts:1483-1489(`[...this.order]`、this.order は src/mindmap.ts:292 で全ノード id)、コピーは src/mindmap.ts:1491-1495 → src/main.ts:376 `core.selectionText([...selection])`。アーキ宣言は core/core.mbt:1-4 で確認。

**検証による訂正**: 最後の一文「frontmatter の閉じ `---` が最初の見出しの group 区切りとして働くので、マップ上に説明のつかないグループ境界が出る」は REFUTED。core/doc.mbt:273 で seps に採用されるのは事実だが、core/doc.mbt:363-388 の親ごとの dense 正規化が「全体一律 +1」を打ち消す。実測で frontmatter 有無 4 パターンを比較し group 値は完全に同一(例: `---\ntitle: x\n---\n\n## P1\n\n---\n\n## P2\n\n# R\n` と `## P1\n\n---\n\n## P2\n\n# R\n` はともに P1:g0, P2:g1, R:g1)。frontmatter の `---` は単独では可視なグループ境界を生み得ない。

**修正コスト**: 約 30-60 行。preamble を持つ疑似ノード(あるいは Snapshot に preamble 範囲を足して UI 側でコピーに含める)を導入する。selection_text と exportSvg と paste の 3 経路に波及する。

### D-往復-4 / CONFIRMED / `core/doc.mbt:252-262, core/doc.mbt:309-317, src/relevel.ts:40-55`

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

**検証の根拠**: 実測一致。`# One\n\ntext\n\n# Two\n\nbody of two\n\n## Child\n` → nodes = One(d1,hs0,subEnd42=EOF), Child(d2,hs33)(`# Two` はノードにならない)。(a) `deleteNodes([One.id])` → getText() === `""`。(b) `selectionText([One.id])` = 文書全文、それを Child(depth2) に貼る経路(src/main.ts:414 `relevel(normalized, n.depth + 1)`)を src/relevel.ts の逐語移植で再現 → relevel 後 `"### One\n\ntext\n\n### Two\n\nbody of two\n\n#### Child\n"`、貼り付け後 nodes = One(d1) | Child(d2) | One(d3) | **Two(d3)** | Child(d4)。コード: core/doc.mbt:254-262 の seen_root ループ(引用は実物と一致)が 2 個目以降の depth-1 を heads から落とし、core/doc.mbt:311-317 の sub_end スタックは落とした見出しを知らないので前ノードの部分木に丸ごと吸収される。TS 側 src/relevel.ts:27 `/^(#+)[ \t]/` には seen_root 相当が無いため同じテキストを depth 1 と数える。

**検証による訂正**: (a) の「削除でファイルが空になる」半分は既出 F-005 と同一経路(重複計上に注意)。新規で価値があるのは (b) 側 ——「コアがノードと認めない `# Two` が、relevel を通ると本物のノードとして復活する」というコア/TS の見出し定義不一致。

**修正コスト**: 約 40-80 行。設計判断が要る(重複 root を許す / 独立ツリーとして扱う / 深さ 1 の 2 個目を構造エラーとして UI に出す)。rebuild_nodes・normalize_selection・cmd_add_root・relevel の 4 箇所に波及。

### D-往復-5 / CONFIRMED / `src/relevel.ts:43-52, src/main.ts:414`

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

**検証の根拠**: 実測一致。`# R\n\n## A\n\n<div>\n# raw html line\n</div>\n\n## B\n` → nodes = R(d1) | A(d2,subEnd41) | B(d2)(`# raw html line` は重複 root として core/doc.mbt:254-262 で破棄)。`selectionText([A])` = `"## A\n\n<div>\n# raw html line\n</div>\n"`。src/relevel.ts の逐語移植で B(depth2) への貼り付けを再現 → relevel(target=3) は scanDepths が `# raw html line` を depth 1 と数えて minDepth=1, delta=2、結果 `"#### A\n\n<div>\n### raw html line\n</div>\n"`。貼り付け後 nodes = R(d1) | A(d2) | B(d2) | **A(d4)** | **raw html line(d3)** ——コピーした A は depth 3 のはずが depth 4 に着地し、HTML の行が親ノードになる。引用の src/relevel.ts:43-44 は実物と一致し、src/main.ts:414 が `relevel(normalized, n.depth + 1)` であることも確認。src/relevel.ts:1-2 のコメント(コア規則の TS 再実装宣言)も実在。

**修正コスト**: 約 15 行(relevel を「コアが返す nodes の深さ」基準にする)〜 60 行(コピー時にコアが深さメタ情報を返し、TS 側の再走査をやめる)。後者が筋。src/relevel.ts と src/main.ts:402,414、core/api.mbt の selection_text 契約に波及。

### D-往復-6 / CONFIRMED / `src/main.ts:401, src/main.ts:414-421, src/main.ts:730-735, src/relevel.ts:54`

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

**検証の根拠**: 実測一致。CRLF 文書 `# R\r\n\r\n## A\r\n\r\n## B\r\n` で B をコピー(core/cmds.mbt:599 の `nl()` により clip = `"## B\r\n"`)、src/main.ts:399-422 を逐語移植して A に貼ると結果は `"# R\r\n\r\n## A\r\n\r\n\n### B\n\n## B\r\n"` ——(1) 挿入部が LF、(2) すでに空行があるのに prefix `"\n"` が付いて空行が 2 本。原因は src/main.ts:418-419(引用は実物と一致): CRLF では `text[at-2]` が常に `"\r"` なので第 2 分岐が必ず真。src/main.ts:730-735 の insertContentLine も同じ判定+`"\n"` 直書きで、実測 `"# R\r\n\r\n## A\r\n\r\n\n[t](https://example.com)\n\n## B\r\n"`。改行種別の知識は core/cmds.mbt:39-46 の `nl()` にしかなく、core/api.mbt:32-96 の snapshot は rev/focus/canUndo/canRedo/editSets/nodes の 6 キーのみで改行種別を露出しない(全文確認)。

**検証による訂正**: 2 点補正。(1) src/relevel.ts:54 の `.join("\n")` は独立原因ではない —— src/main.ts:401 が `clip.replace(/\r\n/g, "\n")` で先に CRLF を落としているため、relevel に届く時点で既に LF。CRLF 破壊の一次原因は src/main.ts:401 と :418-419。(2) 「貼り付けのたびに空行が 1 本ずつ増えるので、同じ場所に 3 回貼ると空行 4 本の穴が空く」は REFUTED。実測で同じ A に 3 回貼っても余分な空行は 1 本のみ(`"# R\r\n\r\n## A\r\n\r\n\n### B\n\n### B\n\n### B\n\n## B\r\n"`)—— 2 回目以降は挿入点の直前 2 文字がどちらも LF になり prefix が空になるため。増分は「CRLF 境界 1 箇所につき 1 回だけ」。

**修正コスト**: 約 15 行。Snapshot に eol を 1 フィールド足し(core/api.mbt:34 付近)、src/main.ts:416-420 と :731-735、src/relevel.ts:54 でそれを使う。あるいは貼り付け文字列の組み立てをコア側の新 API に移す(30 行程度)。

### D-往復-7 / CONFIRMED / `core/cmds.mbt:231-247, core/cmds.mbt:16-35, src/mindmap.ts:1273-1276`

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

**検証の根拠**: 機構は実在し実測も一致。core/cmds.mbt:237 は `let line = hashes(nd.depth) + " " + sanitize_label(label)` で行全体を組み直す(実物と逐語一致)。実測: `"##  Spaced"`→`"## Spaced"`、`"##\tTabbed"`→`"## Tabbed"`、`"## Trailing  "`→`"## Trailing"`、`"##   x   y  "`→`"## x   y"` —— いずれも **同一ラベルを渡しただけ** で core/cmds.mbt:239-241 の同値ガードを抜けて編集が発生し canUndo が true になる。ラベルが派生値である点も確認(core/parser.mbt:110-124 が先頭空白を読み飛ばし末尾空白/CR を落として `sub(text, p, label_end)` を生成)。ATX 閉じは実測でラベルに混入: `"## Closed ##"`→label `"Closed ##"`、`"## Closed   ###   "`→label `"Closed   ###"`。1 打鍵ごとに rename が飛ぶのも src/mindmap.ts:1274-1279 の input リスナで確認。

**検証による訂正**: 3 点補正。(1) 引用の `this.editor.addEventListener("input", …)` は src/mindmap.ts:1274 起点(1272-1273 はコメント)。(2) 「将来のバグ」の (a)(b) —— タブ揃えの表・末尾 2 スペースの hard break —— は REFUTED に近い: ATX 見出し行は 1 行完結で hard break の意味を持たず、見出しでの表整形も成立しない。空白正規化そのものは core/cmds.mbt:230 のコメント(spec 2.5「編集した見出し行だけ正規化する」)どおりの意図的仕様。(3) 実損として残るのは ATX 閉じ列: マップが `"Closed ##"` と表示するため、ユーザが `##` を消して確定するとファイルから閉じ記号が消える —— これは「派生ラベルの定義が Markdown レンダラと食い違っている」という本物の往復欠落。この 1 点に絞れば債務として妥当。

**修正コスト**: 約 10-25 行。cmd_rename を「hs..he のうちラベル部分 [label_start, label_end) だけを置換」に変える。そのためには Heading に label_start を持たせる(core/parser.mbt:119-126)必要があり、core/doc.mbt:296-307 の Node にも 1 フィールド増える。

### D-往復-8 / CONFIRMED / `core/doc.mbt:266-276, core/cmds.mbt:437-515, core/cmds.mbt:597-618`

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

**検証の根拠**: 機構は実在。core/doc.mbt:270-275(引用は実物と逐語一致)により `---` は「直後の見出し」に効く一方、core/cmds.mbt:437-515 の move_block が動かすのは [nd.hs, nd.sub_end) だけなので、所属の決定要因がプリミティブの守備範囲外にある。実測で「触っていない兄弟のグループ境界が変わる」ケースを確認: (i) `# R\n\n## A\n\nsome text\n\n---\n\n## B\n\n## C\n`(A=0,B=1,C=1)で reorderNode(A,+1) → `"# R\n\n## B\n\n## A\n\nsome text\n\n---\n\n## C\n"`、groups は B=**0**, A=0, C=1 —— A の本文内にあった `---` が A と一緒に移動し、B が失っていた区切りを失う。(ii) `# R\n\n## A\n\ncontent\n\n---\n\n## B\n\n## C\n`(A=0,B=1,C=1)で moveNodes([A], C, 0) → groups は B=**0**, C=**0** —— 別の親へ 1 ノードをドラッグしただけで、動かしていない B と C のグループ境界が消滅。

**検証による訂正**: 2 点補正。(1) 提示された 1 番目の実測(moveNodes([B], C, 0) → A=0, C=1)は **証拠にならない**。C は移動前からすでに group 1 であり、移動後も 1 のまま(実測)。マップ上の見た目は変わらない。「B に付いていたグループ境界が C に移った」のはセパレータの指す先が変わっただけで観測可能な差は無い。上記 reason の (i)(ii) に差し替えるべき。(2) 「selection_text も同じ理由で `---` を含めない / コピー&ペーストではグループが常に消える」も REFUTED。実測 `selectionText([A])` on `# R\n\n## A\n\n### x\n\n---\n\n### y\n\n## B\n` = `"## A\n\n### x\n\n---\n\n### y\n"` —— 部分木の **内側** の `---` は [hs, sub_end) に入るので持ち越される。落ちるのは「コピーしたノード自身の group を決めている、hs より手前の `---`」だけ。

**修正コスト**: 約 30-50 行。move_block / cmd_delete の対象範囲を「直前の採用済み `---` を含む」よう拡張し、selection_text も同様にするか、group を Node の派生ではなくブロックの属性として運ぶ。undo の invert は既存機構でそのまま通る。

### D-往復-9 / CONFIRMED / `core/parser.mbt:152-173, core/doc.mbt:266-276`

**setext 見出しの下線が group 区切りとして誤読される**

**根拠**: 入力 `# R\n\n## A\n\nSubtitle\n---\n\n## B\n`
nodes/groups = [R:0, A:0, **B:1**]  ← "Subtitle" の setext H2 下線がグループ境界として採用されている
core/parser.mbt:152-173 の is_separator は「先頭空白 3 個まで + `-` 3 個以上 + 行末まで空白」しか見ておらず、直前の行が段落かどうかを一切見ない。core/doc.mbt:273 の採用条件も「セパレータの次行から次の見出しまでが空白のみ」だけなので、setext 下線 + 空行 + 見出し という並びを区別できない。

**負債**: CommonMark では `---` の意味は直前行に依存する(段落の直後なら setext heading、そうでなければ thematic break)。パーサは行単位のスキャナとして設計されており(core/parser.mbt:1-3 のコメント)、直前行の状態を持たないのでこの区別ができない。同時に setext 見出しそのものは見出しとして認識されないので、`Subtitle` はノードにならず本文扱いのまま残る。

**このままだと顕在化するバグ**: setext 記法で書かれた既存の Markdown(Jekyll/Hugo の古い記事など)を開くと、本文中の下線の数だけマップに説明のつかないグループ境界が現れる。ユーザがそのグループを消そうとして `---` を消すと setext 見出しが段落に化け、外部レンダラでの見た目が変わる。逆に mmm で新しい兄弟をグループ分割(split)付きで追加すると、setext 下線の位置と mmm の `---` が混ざって、どちらがどちらか判別できなくなる。

**検証の根拠**: 実測一致。`# R\n\n## A\n\nSubtitle\n---\n\n## B\n` → nodes/groups = R:0, A:0, **B:1**。core/parser.mbt:152-173 の is_separator は先頭空白 3 個まで + `-` 3 個以上 + 行末まで空白しか見ず、直前行が段落かどうかの状態を持たない(core/parser.mbt:1-3 が行単位スキャナであることを宣言)。採用条件 core/doc.mbt:273 も `is_blank_range(s_next, heads[hp].hs)` だけなので setext 下線 + 空行 + 見出しの並びを区別できない。setext 見出し `Subtitle` 自体はノードにならず本文扱いのまま残る点も実測で確認(nodes に現れない)。

**検証による訂正**: 「本文中の下線の数だけマップに説明のつかないグループ境界が現れる」は過大。実測で発火条件はかなり狭い: (a) 下線が `---` 以上(`-`/`--` の setext H2 下線は is_separator の `q - p < 3` で落ちる —— 実測で group 変化なし)、(b) 下線から次の ATX 見出しまでが空白のみ(`Subtitle\n---\nmore text\n\n## B\n` は group 変化なし)、(c) 後続に ATX 見出しが存在すること(`…Subtitle\n---\n` で EOF なら発火せず)。さらに 1 つの間隙に下線が 2 本あっても境界は 1 つだけ(`S1\n---\n\nS2\n---\n\n## B\n` → B:1)。つまり「次の ATX 見出しの直前に置かれた 3 ダッシュ以上の setext 下線」だけが誤読される。

**修正コスト**: 約 10 行。is_separator の呼び出し側(core/parser.mbt:99)に「直前行が空行 or 行頭」という条件を足す。core_test.mbt のセパレータ系テストと、既存文書の group 番号が変わる点の確認が要る。

### D-往復-10 / CONFIRMED / `src/main.ts:399-421, src/main.ts:402, core/parser.mbt:73-87`

**未閉フェンスを含む断片の貼り付けが後続の見出しを全部飲み込む / 見出しの無い断片は無言で捨てられる**

**根拠**: (a) 未閉フェンス: 文書 `# R\n\n## A\n\n## B\n\n## C\n` の A に clip `"## Snippet\n\n```js\nconst x = 1;\n"` を貼る(hasHeadings は true を返す)。
  結果テキスト = "# R\n\n## A\n\n### Snippet\n\n```js\nconst x = 1;\n\n## B\n\n## C\n"
  結果 nodes = [R, A, **Snippet**] のみ ← B と C がフェンス内に飲まれてノードから消え、Snippet.subEnd が EOF になる。
(b) 見出し無し: 同じ文書で clip `"- item one\n- item two\n"` を貼ると src/main.ts:402 `if (!hasHeadings(normalized)) return;` で何も起きない(getText は不変)。エラーもトーストも無い。

**負債**: 貼り付けが「断片をそのままテキストに挿入する」だけで、挿入後の構造が壊れないかの検証をしていない。フェンス状態は文書全体をまたぐグローバル状態(core/parser.mbt:67-69 のループローカル変数)なので、断片単体では balanced に見えても挿入すると後続を破壊する。hasHeadings ゲート(src/main.ts:402)は逆に安全側に倒しすぎていて、正当な入力を黙って捨てている。

**このままだと顕在化するバグ**: AI チャットや Stack Overflow からコード片ごとコピペする典型的な操作で、貼った瞬間に下半分のノードがマップから消える。テキストは残っているのでユーザは「壊れていない」と思うが、消えた領域は Snippet ノードの subEnd に入るので、Snippet を削除するとそこから EOF まで全部消える(この監査の項目 4 と同じ経路)。見出し無し貼り付けの方は「貼れない」というだけだが、原因が clipboard の中身にあるので何度やっても失敗し、ユーザは機能が壊れていると判断する。

**検証の根拠**: 実測一致。(a) 文書 `# R\n\n## A\n\n## B\n\n## C\n` の A に clip `"## Snippet\n\n```js\nconst x = 1;\n"` を src/main.ts:399-422 の逐語移植で貼る: hasHeadings(clip) = true(src/relevel.ts:36-38 はフェンス外の `## Snippet` を拾う)、結果テキスト `"# R\n\n## A\n\n### Snippet\n\n```js\nconst x = 1;\n\n## B\n\n## C\n"`、結果 nodes = R | A | Snippet のみで B と C が消え、Snippet.subEnd = EOF(55)。続けて Snippet を deleteNodes すると getText() = `"# R\n\n## A\n"` —— B と C がファイルから消滅(監査項目 4 と同一経路を実測で確認)。フェンス状態が文書全体をまたぐループローカル変数である点は core/parser.mbt:67-69 / :73-87 で確認。(b) 同じ文書に clip `"- item one\n- item two\n"` を貼ると src/main.ts:402 `if (!hasHeadings(normalized)) return;` で早期 return、getText() は不変。src/main.ts:380-424 を全読したが、この経路にトースト・flashFilename・console 出力は一切無い。

**修正コスト**: (a) 約 20 行 — 挿入前に断片のフェンス収支を数え、奇数なら閉じフェンスを補うか拒否+通知。(b) 約 10 行 — hasHeadings で弾く代わりに、見出し無し断片はアンカーの本文行として挿入する(insertContentLine src/main.ts:722 が既にある)。

---

## 観点: ノード同一性

### D-同一性-1 / CONFIRMED / `core/cmds.mbt:407-419, core/doc.mbt:123-127`

**outdent の「最後の子」分岐が部分木の id を全部捨てる（F-004 の実体と拡張）**

**根拠**: cmds.mbt:409-419 は `for m in subtree_nodes(nd.hs, nd.sub_end) { set.push(Edit::{ from: hs, to: hs + 1, insert: "", removed: "#" }) }` — 部分木の全見出しに「先頭 1 文字の純削除」を出す。doc.mbt:120-127 は `p == e.from` かつ `e.to > e.from` かつ `e.insert.length() == 0` を無条件に `return -1` にする。実測: `# root/## p/### t/#### t1/##### t2/#### t3` で t を outdent → 失った id [3,4,5,6]、発番 [7,8,9,10]。出荷 SAMPLE(src/main.ts:39-58)では深さ 3 以上の 3 件すべてが、mmm.md では 262 件中 116 件がこの分岐。

**負債**: 同一性の代理キーが「見出し開始オフセット」であることの直接の帰結。map_offset は「改行で終わらない純挿入 = 行の書き換え = 生存」という救済規則(doc.mbt:128-135)を indent のために入れたが、その逆操作である純削除に対応する規則を入れなかった。同じ操作の往復が非対称という、規則の穴がそのままコマンドの穴になっている。

**このままだと顕在化するバグ**: ユーザが 3 ノードを選んで Shift+Tab を押す → applySnap(src/main.ts:186-191)が選択を空にする → 2 回目の Shift+Tab は `if (selection.size === 0) return`(src/main.ts:361)で無反応。「1 段上げを 2 回連続でできない」というバグ報告として顕在化する。ラベル編集中に outdent が走れば editingId が死んだ id を指したまま残り、以後の打鍵が存在しないノードへの rename になって何も起きない。

**検証の根拠**: 機構は行番号どおり実在。core/cmds.mbt:407 `if pe == nd.sub_end` の分岐で :410-417 が部分木の全見出しに `from: hs, to: hs+1, insert: ""` を出し、core/doc.mbt:119-126 が `p == e.from && e.to > e.from && e.insert.length() == 0` を無条件に `return -1` にする。救済規則 doc.mbt:128-135 は純挿入側にしか無く、非対称は本物。実測で再現(built core): `# root/## p/### t/#### t1/##### t2/#### t3` の t(id 3) を outdent → 失った id [3,4,5,6]、発番 [7,8,9,10]、focus=7。SAMPLE(src/main.ts:39-58)の深さ 3 の 3 件は subEnd == 親の subEnd がすべて成立し 3/3 がこの分岐、mmm.md も depth>=3 が 262 件・うち 116 件がこの分岐で、数値まで一致。

**検証による訂正**: 将来のバグの経路記述を訂正。(a) Shift+Tab が outdentSelection に落ちるのは sel.size > 1 のときだけで(src/mindmap.ts:1472-1473)、単一選択の Shift+Tab は addParent(:1474)。よって「1 段上げを 2 回連続でできない」は 2 ノード以上の選択、またはコンテキストメニュー「1 段上げ」(src/mindmap.ts:1759)でのみ起きる。(b) 2 回目が止まるのは src/main.ts:361 ではなく src/mindmap.ts:1472-1476(sel.size が 1 以下かつ anchor === -1 で何もせず return)。観測される無反応は同じ。(c) 「ラベル編集中に outdent が走れば editingId が死んだ id を指したまま残る」は到達不能。キーボード経路は src/mindmap.ts:1327 `if (this.isEditing()) return;` で塞がれ、メニュー経路も menu が document.body 直下(src/mindmap.ts:257)・項目が click ハンドラのみ(:1789)で mousedown を preventDefault しないため、項目押下でまず input が blur → src/mindmap.ts:1290-1292 が commitEdit → endEdit が走ってから it.run() が実行される。

**修正コスト**: core/cmds.mbt:409-419 の 1 箇所、約 10 行。削除 `[hs, hs+1)` を「ハッシュ列の置換 `[hs, hs+depth) → hashes(depth-1)`」に変えるだけ。実測でテキストはバイト単位で同一(`# root\n\n## p\n\n## t\n\n### t1\n\n#### t2\n`)、id 3,4,5 は全部保存された。map_offset には触らなくてよい。

### D-同一性-2 / CONFIRMED / `src/main.ts:355-364, src/main.ts:237-241, src/main.ts:349-353, core/cmds.mbt:419`

**id を落とす唯一のコマンドが、唯一 snap.focus を使わない UI 経路になっている**

**根拠**: outdentSelection は `applySnap(core.outdentNodes([...selection]), "map"); syncSelectionViews(false);` の 2 行だけで snap.focus を読まない。一方 runCmd(src/main.ts:237-241)と deleteSelection(:349-353)は `if (snap.focus !== -1 && byId.has(snap.focus)) setSelection([snap.focus], snap.focus)` で復帰する。コア側は cmds.mbt:419 の focus_node_at(nd.hs) と :428-430 で正しい新 id を計算しており、SAMPLE 文書の 3 ケースすべてで focus=8(有効な新 id)が返っていた。UI がそれを捨てている。

**負債**: 「id が死んだときの回復」を各呼び出し側が個別に実装していて、共通の規約が無い。12 個の id 依存機構(selection, anchorId, byId, editingId, boxes, order, sideOf, frameOf, hoverId, dragCand, dragging.subtree, dropTarget)のどれもが、死んだ id を「無言で無視する」か「刈り込む」だけで、コアが返している後継 id に乗り換える経路は runCmd と deleteSelection の 2 つしかない。

**このままだと顕在化するバグ**: コアの id 保存性を将来どこか 1 箇所でも壊すと、その操作の直後に選択が消えて連続操作が止まる。逆に item 1 を直しても、focus を使わない経路が残る限り「id は保たれたのに選択が別の場所へ飛ぶ」類の不整合を作り込みやすい。indentSelection も同じ形なので、indent 側の Edit 形状を将来変えた瞬間に同じ症状が出る。

**検証の根拠**: src/main.ts:360-364 の outdentSelection は applySnap + syncSelectionViews の 2 行だけで snap.focus を読まない。src/main.ts で snap.focus を読むのは 237-240(runCmd)と 349-350(deleteSelection)の 2 箇所のみ(grep 済み)。コア側は core/cmds.mbt:419 focus_node_at(nd.hs) と :428-430 で後継 id を計算しており、SAMPLE の 3 ケースすべてで focus=8、しかも実測でその id は新ノード列に生存(focusAlive=true)。UI が捨てているのは事実。id 依存機構 12 個も実在(src/main.ts:31,32,33 / src/mindmap.ts:183,184,185,186,193,194,195,196,199)。

**検証による訂正**: タイトルの 2 つの「唯一」はどちらも成り立たない。(a) id を落とすコマンドは outdent だけではない — replace_text 経由の id 窃取(項目 3)と cmd_move の重複ルート消失(項目 4)でも落ちる。(b) snap.focus を使わない UI 経路も outdentSelection だけではない — indentSelection(src/main.ts:355-359)、rename(:336-338)、paste(:421-422)、insertContentLine(:735)も applySnap のみで focus を読まない。正しい言い方は「id が確実に死ぬ唯一のコマンドが、focus を読まない多数派の経路の側に置かれていて、復帰規約を持つ 2 経路(runCmd / deleteSelection)から外れている」。負債の中身(回復規約が呼び出し側ごとの個別実装)はそのまま成立する。

**修正コスト**: src/main.ts:360-364 に runCmd と同じ 3 行を足すだけ(選択集合を復元したいなら focus 単独ではなく id 配列を返す必要があり、その場合は core/api.mbt の snapshot に focusIds を足して ~20 行)。

### D-同一性-3 / CONFIRMED / `core/doc.mbt:128-135`

**「改行で終わらない挿入」規則が、新しい見出しに他ノードの id を渡す（id 窃取）**

**根拠**: `let n = e.insert.length(); if n > 0 && cc(e.insert, n - 1) == 10 { delta = delta + n }; break` — 判定は「挿入文字列の最後のコードユニットが LF か」だけ。実測: `### t`(id 3)の hs に `"## up\ntail"` を挿入 → 結果 `## up\ntail### t`、id 3 は新しい見出し `up` に付き、元の t はノードごと消滅(ノード数 4→4、ラベルだけ入れ替わる)。`"## up\r"`(CR 終端)でも同じく窃取が起きる。

**負債**: 「行の書き換えか、上に行を作ったか」を末尾 1 コードユニットで代理判定している。本来知りたいのは「編集後、位置 p から始まる行は元の見出しか」だが、それを問わずに文字列の形で近似している。近似が外れる入力(改行を含むが改行で終わらない挿入)は CodeMirror ペインの貼り付けで日常的に作れる。

**このままだと顕在化するバグ**: md ペインで見出し行の先頭にカーソルを置いて、末尾に改行を含まない複数行断片を貼る → 選択中だったノードの id が新しい見出しへ移り、選択ハイライトとラベル編集オーバーレイが別ノードを指す。ユーザから見ると「貼り付けたら選択が勝手に上の行へ飛んだ」「ラベルを直したら関係ない見出しが書き換わった」になる。原因がテキスト側に残らないので再現報告から追えない。

**検証の根拠**: core/doc.mbt:128-135 は挿入文字列の最後のコードユニットが 10 かどうかだけを見て delta を足すか否かを決め、直後に break する。判定に「編集後、位置 p から始まる行が元の見出しか」を問う経路は無い。実測で再現: `# r/## a/### t` の t(id 3, hs=11)に `"## up\ntail"` を挿入 → 結果 `## a\n\n## up\ntail### t\n`、ノードは `1:r, 2:a, 3:up`、t はノードごと消滅して id 3 が新見出し up に付いた。対照として `"## up\n\n"`(LF 終端)では id 3 は t に残り新見出しが id 4 を取る。ゲートは無い: core/api.mbt:126-132 の replace_text は範囲チェックのみで、貼り付けは src/main.ts:295-299 → api.mbt:119 に素通しで届く。

**検証による訂正**: CR 終端 `"## up\r"` の挙動を正確に。実測ではノードは `3:"up\r### t"` になる — 改行が入らないので行が結合し、id 3 は「ラベルが行全体になった別の見出し」に付く。id の移動という点では窃取だが、`## up` という独立見出しができるわけではない。

**修正コスト**: core/doc.mbt:113-143 の中核 ~15 行。ただしここは indent(cmds.mbt:358-365)と add_parent(cmds.mbt:203-210)の正しさが乗っている場所なので、変更にはコア 44 件のテスト(core/core_test.mbt:301 と :312)の読み直しと、上表 23 通りの再測定が要る。

### D-同一性-4 / CONFIRMED / `core/doc.mbt:252-262, core/cmds.mbt:544-550`

**重複ルート抑制が、id の所有権を「テキスト上の先着順」に委ねている**

**根拠**: rebuild_nodes は `if h.depth == 1 { if seen_root { continue }; seen_root = true }` で 2 つ目以降の `#` 見出しをノード列から落とす。実測 ①md ペインで先頭に `"# new\n\n"` を挿入 → 旧ルート id 1 が消え、`## a` の親が新ルート id 4 に付け替わる(テキストには `# root` が残るがノードではない)。②cmd_move の pos 1/2 で深さ 1 を対象にすると、pos=1 で旧ルート id、pos=2 で移動ノード id が消える。全ノードペア×3 pos の総当り 22050 回中 1800 回がこの形で、それ以外の id 消失は 0 件だった。

**負債**: 「ルートは 1 つ」という構造規則を、パース時に黙って捨てることで実装している。捨てられた見出しはノードでないので id を持てず、それが誰かの id の消失として現れる。F-005(2 つ目の `#` が前ノードの subEnd 内に居座る)と同じ根で、id 側の顔がこれ。どのノードが id を保持するかがテキスト上の物理的な前後関係で決まる。

**このままだと顕在化するバグ**: md ペインで文書の一番上に新しい `# タイトル` を書いた瞬間、マップ側で選択していたノード(旧ルート)が選択から外れ、ツリー全体の親子が付け替わって再レイアウトされる。ユーザは「見出しを 1 行足しただけでマップが作り直された」と報告する。cmd_move 側は src/mindmap.ts:1641-1644 の pos=0 強制だけが盾になっており、ドロップ判定を「ルートにも前後を許す」方向に触った瞬間にルートが消える(F-006)。

**検証の根拠**: core/doc.mbt:254-262 が `if h.depth == 1 { if seen_root { continue }; seen_root = true }` で 2 つ目以降の depth-1 見出しをノード列から落とす。実測① `# root/## a/## b` の先頭に `"# new\n\n"` を挿入 → `4:new@0, 2:a, 3:b` で旧ルート id 1 が消え、テキストには `# root` が残る。しかも貼り付け限定ではなく素の打鍵で到達する: 先頭で Enter → `#` → 空白 と打った瞬間(1 行目が有効な depth-1 見出しになった打鍵)に id 1 が消え id 3 が発番され、`## a` の親が付け替わった。実測② `# root/## a/## b` に対し moveNodes([3], 1, pos): pos=0 は無変化、pos=1 で失う id [1](旧ルート)、pos=2 で失う id [3](移動ノード) — F-006 と一致。盾も実在: src/mindmap.ts:1641-1644 が depth===1 のとき target を pos:0 に固定し、host.move の呼び出し元は src/mindmap.ts:1159 の 1 箇所のみ。

**修正コスト**: core/doc.mbt:252-262 と rebuild_nodes の id 割当まわりで ~30 行。ただし「重複ルートをどう扱うか」は仕様判断(落とす/深さ 2 として扱う/エラーにする)を伴うため、mmm.md の仕様確認が先に要る。

### D-同一性-5 / CONFIRMED / `core/cmds.mbt:499-511`

**move_block の id 復元が再パース結果への当て推量で、失敗が完全に無言**

**根拠**: `let base = new_hs + prefix_len` ... `for r in rels { match at_hs.get(base + rel) { Some(idx) => st.nodes[idx].id = rid; None => () } }`。base は `new_hs`(挿入位置の算術)と `prefix_len`(preceded_by_blank による先頭改行の有無)から手で組み立てた予測値で、rels は移動前に計算した相対オフセット。予測が 1 文字でも外れれば全件 `None` に落ちてブロック全体の id が黙って捨てられる。失敗を報告する経路も、テストで固定している assert も無い(audit/MAP.md 6.2 のとおり snapshot の id は直接 assert されていない)。

**負債**: apply_sets が「位置で id を運ぶ」ことに失敗する唯一のコマンドが、その後始末を自分で再実装している。つまり同一性の担保が 2 系統(map_offset と at_hs)に分裂しており、後者は nl()・preceded_by_blank・insert_heading_edit・tidy_del_start・パーサのどれが変わっても静かに壊れる。

**このままだと顕在化するバグ**: 将来 `preceded_by_blank`(cmds.mbt:51-67)の空行判定や `move_block` の末尾改行整形(cmds.mbt:462-477)を 1 行いじると、特定の文脈だけドラッグ移動後に部分木ごと id が入れ替わる。症状は「ドラッグしたら選択が外れる」だけで、テキストは正しいので原因が move_block だと分からない。総当り 22050 回で外れが出なかったことが逆に危険で、退行しても誰も気づかない。

**検証の根拠**: core/cmds.mbt:494-500 で new_hs を算術(at2 と削除幅)から組み、prefix_len(:480-484、preceded_by_blank 依存)を足して base を作り、:501-504 で再パース後の hs→index 表を引き、:505-511 で `None => ()` に落とす。失敗を報告する経路は無く、直後の :514 `st.focus = old_id` は復元成功を前提にしている。同一性の担保が map_offset と at_hs の 2 系統に分裂しているという指摘は正しい。

**検証による訂正**: 2 点が事実に反するので削る必要がある。(1)「テストで固定している assert も無い」は誤り。core/core_test.mbt:175-187「ids and parents survive a move」が move_nodes([3],2,0) の後に rename_node(3,…) と outdent_nodes([4]) を実行して本文を assert_eq しており、id 復元が壊れれば find_node が -1 を返して rename が no-op になり :182 / :186 が落ちる。core_test.mbt:323-335 が move + undo を同様に押さえている。よって「退行しても誰も気づかない」は成り立たず、正しくは「テストが押さえているのは『最後の子として移動』と『その undo』の 2 形状だけで、preceded_by_blank / 末尾改行整形 / EOF 収束の分岐は未カバー」。(2)「apply_sets が位置で id を運ぶことに失敗する唯一のコマンド」も誤り。項目 1 の cmd_outdent 純深さ変更分岐(core/cmds.mbt:409-419)でも失敗する — そちらは後始末を実装していない。正しくは「失敗を自前で補償している唯一のコマンド」。

**修正コスト**: 検知だけなら cmds.mbt:507-510 に「全 rels が解決したか」の判定を足して ~5 行(コアにログ経路が無いので st に失敗フラグを置く形になる)。根治は move_block が id 復元を必要としない形(移動を「削除+挿入」ではなく map_offset が追える編集列にする)への作り替えで、cmds.mbt:437-515 の約 80 行。

### D-同一性-6 / CONFIRMED / `core/doc.mbt:76-79 対 core/doc.mbt:119-136, core/cmds.mbt:201-211`

**apply_edit_set が許す編集セットの形を map_offset が処理できない（同一オフセットの後続編集を見ずに break する）**

**根拠**: apply_edit_set の doc コメントは「長さ 0 の挿入が同じオフセットを共有してよい(配列順に適用)。長さ 0 の挿入が、続く削除/置換と同じオフセットを共有してもよい」と明記する(doc.mbt:77-79)。しかし map_offset は `p == e.from` に当たった時点で必ず break し(doc.mbt:126, :135)、同じオフセットにある後続の編集を一切見ない。現に cmd_add_parent は同一オフセット `nd.hs` に [見出し挿入, "#" 挿入] の 2 本を出しており(cmds.mbt:201-210)、正しく動くのは **配列順が偶然この順だから**である。

**負債**: データ構造の契約(何が有効な編集セットか)と、それを解釈する 2 つの関数の実装が食い違っている。片方は仕様どおり全部処理し、片方は最初の 1 本で打ち切る。契約を書いた側と読む側が別々に進化した痕跡で、テストも編集セットの形を固定していない(MAP.md 6.2: editSets を assert するテストは 44 件中 0 件)。

**このままだと顕在化するバグ**: cmd_add_parent の 2 本を「先に `#` を入れてから見出しを入れる」順に書き換える、あるいは新しいコマンドが同一オフセットに [挿入, 削除] を出した瞬間、map_offset は最初の編集だけ見て「生存」と判断し、実際には消えた見出しの位置に旧 id を割り当てる。結果は無言の id 窃取で、テキストは正しいのに選択とラベル編集だけが別ノードを指す。レビューで気づける手がかりがコメント 2 行しかない。

**検証の根拠**: core/doc.mbt:76-79 の doc コメントは長さ 0 の挿入が同一オフセットを共有すること、および長さ 0 の挿入が後続の削除/置換と同一オフセットを共有することを明示的に許す。一方 core/doc.mbt:119-136 の map_offset は `p == e.from` に当たると必ず :126 で return するか :135 で break し、同一オフセットの後続編集を見ない。cmd_add_parent が同一オフセットに 2 本出しているのも実測どおり — snapshot の editSets は `[{5,5,"## \n\n"},{5,5,"#"},{11,11,"#"}]`。editSets を assert するテストは core/core_test.mbt に 0 件(grep 済み)。

**検証による訂正**: 2 点補強・訂正。(1) 契約の後半節は死んだ文言ではなく現役: move_block は nd.sub_end == len かつ挿入点が拡幅削除域に入るとき at2 = del_from(core/cmds.mbt:474)となり :492 で `[ins@del_from, del@del_from..sub_end]` を出す。`# r\n\n## a\n\n## b\n` で b を a の子にする(core_test.mbt:101, :175 の形)と del_from=10, at2=10 でまさにこの形になる。今日無害なのは del_from が空行走査の先頭で、そこを hs に持つノードが存在しないという偶然だけによる。(2)「cmd_add_parent の 2 本を逆順に書き換えたときレビューの手がかりがコメント 2 行しかない」は誤り。逆順にすると apply_edit_set の出力テキスト自体が変わり、core/core_test.mbt:312-320「add_parent keeps the wrapped subtree's ids」が本文と(rename_node(2/3/4) 経由で)id の両方を assert しているので落ちる。未検査で残る露出は「新しいコマンドが同一オフセットに [挿入, 削除] を出す」場合。

**修正コスト**: core/doc.mbt:113-143 に「同一オフセットの編集列をまとめて評価する」ループを足して ~10 行 + 同一オフセットの [挿入, 削除] を含むコアテスト 2 件。

### D-同一性-7 / CONFIRMED / `core/api.mbt:104, src/main.ts:473-488, src/main.ts:857-878, src/mindmap.ts:199-200, src/mindmap.ts:920-925`

**init_doc が next_id を 1 に戻すのに、loadText がラベル編集を終了しない（id の ABA）**

**根拠**: init_doc は `st.next_id = 1`(api.mbt:104)。実測で doc1 の id 1,2,3 が doc2 でも 1,2,3 として再発番される。loadText(main.ts:473-488)は clearAssets / setSelection / initDoc / setText / applySnap / fitView を呼ぶが `map.endEdit()` を呼ばない — endEdit の呼び出し元は grep で main.ts:342(host.commitEdit)ただ 1 箇所。ドロップ経路(main.ts:857-878)はラベル編集中でも pane の pointerdown(mindmap.ts:1040-1044)も editor の blur(mindmap.ts:1290-1292)も踏まずに loadText へ到達しうる。

**負債**: id は「その文書の、そのセッションでの」識別子なのに、文書を跨いで生き延びる参照(editingId)がある。文書に世代トークンが無いため、旧文書の id と新文書の id を型でも値でも区別できない。undo/redo は Entry.before/after で id を正しく往復させる(実測 1,2,3,4 → 1,2,5,6 → 1,2,3,4)ので ABA が起きないが、init_doc だけがカウンタを巻き戻す。

**このままだと顕在化するバグ**: 保存済み(dirty でない)状態でノードのラベルを編集中に、別の .md をウィンドウへドラッグ＆ドロップする → confirmDiscard は confirm を出さずに true を返し(main.ts:613)、loadText が走って文書が入れ替わる → ラベル入力欄は開いたまま、次の 1 打鍵が `host.rename(旧id, …)` として **新しい文書の別のノード** を書き換える。ユーザは「ファイルを開いたら見出しが 1 つ壊れていた」と報告し、undo スタックは init_doc でクリア済み(api.mbt:101)なので元に戻せない。未確認: ネイティブ confirm() が input の blur を発火するかは実行未検証。dirty な文書では confirm 経由で救われる可能性がある。

**検証の根拠**: core/api.mbt:104 `st.next_id = 1`、:101-102 で undo/redo を clear。実測: doc1 が 1,2,3 → initDoc(doc2) 後も 1,2,3 が再発番され、古い editingId=2 を模した renameNode(2,"HIJACKED") が doc2 の別ノードを書き換えた(`# alpha/## HIJACKED/## gamma`)。src/main.ts:473-488 の loadText は clearAssets / setSelection / initDoc / setText / applySnap / fitView のみで map.endEdit() を呼ばず、endEdit の呼び出し元は src/main.ts:342 の 1 箇所だけ(grep 済み)。ドロップ経路(src/main.ts:857-878)は外部ファイルの drop なので input に mousedown が入らず src/mindmap.ts:1290-1292 の blur も src/mindmap.ts:1040-1044 の pane pointerdown も踏まない。src/main.ts:613 は未 dirty なら confirm を出さずに true を返す。ラベル編集を開始しただけで打鍵していなければ未 dirty は成立する。

**検証による訂正**: 症状はむしろ記述より強い。render() の末尾が src/mindmap.ts:728 `this.positionEditor()` で、positionEditor(:931-943)は boxes.get(editingId) が無いときだけ早期 return する。id が 1 から振り直される以上、旧 editingId は新文書にもたいてい実在するので、入力欄は消えも止まりもせず新文書の無関係なノードの上へ位置合わせされる。つまり「入力欄が開いたまま残る」ではなく「入力欄が別ノードへ乗り移って表示される」。ネイティブ confirm() が blur を発火するかが未確認である点はそのまま(dirty 文書は救われる可能性がある)。

**修正コスト**: 応急処置は src/main.ts:473 の先頭に `map.endEdit()` の 1 行。根治(文書世代トークンを snapshot に載せ、id 参照側で照合)は core/api.mbt の snapshot、src/coreApi.ts の Snapshot 型、src/main.ts の applySnap で計 ~20 行。

---

## 観点: 状態の重複と DOM を状態源にしている箇所

## 結論

MAP.md 4.6 の表は 13 行すべて実在を確認した(誤りなし)。ただし「重複している」だけでは危険度が測れないので、行ごとに**同期が破れる具体的なイベント順序**を以下に示す。あわせて、DOM が唯一の真実になっている箇所を 5 分類で洗い出した。

全体像として言えるのは:このアプリの重複状態には **2 種類**あり、扱いが違う。

- **(A) applySnap を漏斗にして毎回まるごと作り直すもの** — `nodes`/`byId`(src/main.ts:181-182)、`boxes`/`order`(src/mindmap.ts:292, :555)、`.node` の class 列(src/mindmap.ts:585-594)、`btnUndo/btnRedo.disabled`(src/main.ts:200-201)、`elDirty.hidden`(src/main.ts:207)。これらは「重複」だが再構築が無条件なのでズレにくい。代償は F-002 のコスト。
- **(B) 書いた場所と読む場所が違い、再構築の対象外のもの** — ここが実際に壊れる。`drop-child` クラス(src/mindmap.ts:1680)、`rubber` のインラインスタイル(src/mindmap.ts:1089-1095)、documentElement のインライン `--accent-soft`(src/main.ts:140)、`spaceDown`(src/mindmap.ts:1000)、`savedText`(src/main.ts:35)、CodeMirror の `highlightField`(src/editor.ts:68)。

そして**(B) の全件に共通する構造**は「値を保持する変数と、その値を消す/直す責任を持つ関数が 1 対 1 になっていない」こと。render() は class 列を作り直すが `drop-child` は作り直さない。pointerup は `rubberStart` を消すが `rubber.style.width` は消さない。keyup は `spaceDown` を消すが blur は消さない。

---

## 1. MAP.md 4.6 の各行 — 同期が破れる瞬間

### 行1 文書テキスト(st.text / CodeMirror doc / mmm.text / disk / savedText)
`applySnap` は `origin === "cm"` のとき `editor.applySets` をスキップする(src/main.ts:183)。つまりユーザーがタイプした経路では**コアと CodeMirror の一致は一度も検証されない**。そしてコア側 `replace_text` は `from < 0 || to > n || from > to` で**黙って無変更 snapshot を返す**(core/api.mbt:125-128、実際に開いて確認)。したがって一度ズレると自己修復せず、増幅する。

破れる瞬間(確実に再現するもの): `storage` イベントの購読が**リポジトリ全体で 0 件**(`grep -an 'addEventListener("storage"' src/` が空)。同じ文書を 2 タブで開くと両方が 250ms デバウンスで `mmm.text` に全文を書き(src/main.ts:105, :112)、読むのは boot だけ(src/main.ts:1111)。→ 後勝ち。さらに `savedText`(src/main.ts:35)は**ディスクの内容の代理**にすぎず、外部エディタで .md を書き換えても更新されない。リロード後 `savedText = localStorage.getItem(LS_SAVED)`(src/main.ts:1113)なので dirty ドットは消えたまま、`confirmDiscard`(src/main.ts:613)も `beforeunload`(src/main.ts:852)も通過し、Ctrl+S が外部の変更を無警告で潰す。

### 行2 ノードツリー(st.nodes / nodes,byId / boxes(Box.n),order)
`applySnap` は 181 行で `nodes` を差し替え、198 行で `map.render()` を呼ぶ。**その間の 183-195 行では `nodes` は新・`boxes`/`order` は旧**という混在状態。この窓の中で 183 行が CodeMirror へ dispatch する(src/main.ts:183 → src/editor.ts:157-165)。現状ここからマップへ再入する経路は無いので実害は出ていないが、`selChanged` の判定(src/main.ts:186-195)はこの混在窓の中で行われている。

より実害があるのは `Box.n` が**前回 render 時点の NodeInfo を握り続ける**こと(src/mindmap.ts:475-482)。`updateDrop` はルート保護の判定に `b.n.depth === 1` を使い(src/mindmap.ts:1641)、`beginEdit` は初期値に `b.n.label` を使う(src/mindmap.ts:904)。両方とも「今の木」ではなく「最後に描いた木」を見ている。→ 項目4・5参照。

### 行3 選択集合(selection / .node.selected / highlightField)
`applySnap` は `if (selChanged) syncSelectionViews(false)`(src/main.ts:199)。`selChanged` は**選択 id が消えたときだけ**立つ(src/main.ts:186-195)。つまり選択集合が同じまま**範囲だけが変わった**場合、md ペインのハイライトは更新されない。→ 項目8。

### 行4 アクセント色 / 行5 テーマ / 行6 ペイン可視性
→ 項目1・2・3・10。

### 行7 ファイルハンドル(fileHandle / IndexedDB "handle")
`persistHandle()` は `void idbSet(...).catch(() => {})` の fire-and-forget(src/main.ts:514-516)。IDB 書き込みが落ちても誰も気づかない。採用条件は `h.name === fileName` の**名前一致だけ**(src/main.ts:1119)。→ 項目11。コード自身のコメント(src/main.ts:511-513)が「stale handle + fresh text で Ctrl+S が別ファイルを上書きする」と危険を明記しているのに、その保証が名前一致 1 本しかない。

### 行8 画像フォルダ許可(dirHandle / IndexedDB "dir")
`dirHandle = null` は同期、`idbSet("dir", null)` は fire-and-forget(src/main.ts:767-768)。取り消しの片方だけが成功すると、次回起動で無効な許可が復活する(src/main.ts:1122-1125)。

### 行9 ファイル名(fileName / mmm.fileName / elFilename.textContent / fileHandle.name)
`flashFilename` が 4 秒間 `elFilename.textContent` を `${fileName} — ${msg}` に差し替える(src/main.ts:601-609)。この間、ファイル名表示・エラー通知・成功通知(src/main.ts:1019, :1047)が**同じ 1 本の DOM チャネルに多重化**されている。復帰は JS 変数 `fileName` から行う(src/main.ts:607)ので自己修復はする。ただし `localStorage` への書き戻しは `saveFile` の成功パス(src/main.ts:586)と `loadText`(src/main.ts:483)にしかなく、どちらも try/catch で握り潰す(src/main.ts:487, :588)。

### 行10 Undo 可否(st.undo/redo の長さ / btn.disabled)
JS 側に深さを持たない(src/main.ts:200-201)。かつ `snapshot()` は `st.last_sets = []` / `st.focus = -1` を**副作用として実行する破壊的読み出し**(core/api.mbt:93-94、実ファイルで確認)。`onUserEdits` はループで `core.replaceText` を複数回呼び、**最後の snapshot しか applySnap に渡さない**(src/main.ts:294-299)。中間の snapshot の editSets は drain されて永久に失われる。origin が `"cm"` なので今は捨てて構わないが、「applySnap を 1 回でも落とせば復元不能」という設計になっている。

### 行11 編集中ラベル(st.text の見出し行 / editor.value / Box.n.label)
`cmd_rename` は正規化後が同一なら**編集も undo エントリも作らずに return する**(core/cmds.mbt:238-241、実ファイルで確認)。`sanitize_label` は前後の空白をトリムする(core/cmds.mbt:16-33)。したがってラベル末尾にスペースを打つと `editor.value` は `"abc "`、`st.text` は `"## abc"` で**確実にズレる**。マップの表示・`<title>`(src/mindmap.ts:613-614)はコア側なので "abc"、入力欄だけ "abc "。そのまま Mod+Z を押すと、その打鍵に対応するエントリが存在しないので**1 手前のコマンドが取り消される**。

### 行12 ノード id(Node.id / g.dataset.id / byId / order / boxes)
→ 項目4・5。

### 行13 ロゴのパス文字列(index.html:16 / public/favicon.svg:4 / LOGO_PATH)
→ 項目12。3 箇所コピーのうち **1 箇所が実際に食い違っている**ことを確認した。

---

## 2. DOM を状態源にしている箇所(分類別・全件)

### (a) `g.dataset.id` を読み戻している箇所 — 4 箇所
src/mindmap.ts:1222(pointerover → hoverId)、:1609(startDrag → dragging クラス付与)、:1679(updateDrop → drop-child 付与)、:1810(refreshSelection)。書き込みは src/mindmap.ts:595 の 1 箇所のみ。
ノード id が `Node.id`(Int)→ `String(n.id)` → `Number(dataset.id)` と 2 回変換されており、`boxes`/`order`/`byId` という 3 つの型付き索引が既にあるのにそれらを使っていない。実害は「DOM の生存期間が id の生存期間になる」こと: `nodeLayer.replaceChildren()`(src/mindmap.ts:559)で消えた `<g>` の id は、それを読む 4 箇所から**静かに消える**(例外ではなく無反応になる)。→ 項目4・5。

### (b) `classList.contains` を条件に使っている箇所 — 4 箇所
- src/main.ts:1089 `document.documentElement.classList.contains("light")` — テーマトグルの**唯一の入力**。→ 項目3。
- src/mindmap.ts:1206 / :1251 / :1256 — `link-open` グリフの判定。特に :1251-1253 は URL を `t.getAttribute("data-url")` から取って `window.open` に渡す。**URL はモデルに存在せず DOM 属性にしかない**(src/mindmap.ts:645)。値自体は `parseLink` が `https?://` + `new URL()` で検証済み(src/mindmap.ts:121-137)なので現状は安全。ただし `nodeLayer` は毎 render で `replaceChildren` されるので、pointerdown と click の間に render が走る(例: 画像 blob 解決 → src/main.ts:678)と click は `nodeLayer` に到達せず**無反応で消える**。

### (c) documentElement のクラス / インラインスタイルから現在値を読み直している箇所
- `applyTheme`(src/main.ts:1076-1085) — 書くだけ。読み戻すのは src/main.ts:1089 のトグル。→ 項目3。
- `applyColor`(src/main.ts:131-150) — 書くだけ。読み戻すのは src/main.ts:166-172 のロゴ click。→ 項目1・2。
- `togglePaneVis`(src/main.ts:938-943) — **プロンプトの前提と違い、これは DOM を読んでいない**。`paneVis`(src/main.ts:914)という JS ミラーを読む。DOM を読むのは同じ領域の別の 2 箇所: `applyPaneVis` の focus 救済(src/main.ts:934-935)と `togglePane`(src/main.ts:950)で、どちらも `document.activeElement` を唯一の入力にしている。→ 項目10。

### (d) `getComputedStyle` を状態の読み出しに使っている箇所 — 3 箇所
- src/main.ts:167 と :169(同じ値を **2 回** getComputedStyle して 2 回 trim している)— アクセント色の現在値。→ 項目2。
- src/mindmap.ts:818 — `exportSvg` が要素ごとに 11 プロパティを読む。
- src/mindmap.ts:855 — `exportSvg` が背景色を読む。**この 2 つは `await` を挟んで別のタイミングで読まれる**(要素は 829-830、背景は 833-848 の await 群の後の 855)。→ 項目12 の補足として記載。

### (e) ボタンの textContent / disabled を状態として読んでいる箇所
**読んでいる箇所は 0 件**だった。`btnTheme.textContent`(src/main.ts:1079)も `btnUndo/btnRedo.disabled`(src/main.ts:200-201)も書き捨てのミラー。ただし `disabled` は**ブラウザが読む**ので、Undo 可否の実効ゲートは DOM 属性である(キーボード経路 src/main.ts:901-906 はこのゲートを通らないため、ボタンとキーで到達条件が違う)。`index.html:34` はテーマグリフを `◑` にハードコードしており、boot の `applyTheme`(src/main.ts:1098)が上書きするまで実状態と無関係。

### (f) その他の DOM 読み戻し(表に無いが同種)
- `parseFloat(this.rubber.style.width)`(src/mindmap.ts:1146-1147)— 「実際にドラッグしたか」をインラインスタイル文字列から復元。→ 項目6。
- `this.menu.offsetWidth / offsetHeight`(src/mindmap.ts:1796-1797)— 表示してから実測してクランプするので 1 フレーム画面外に出る可能性。
- `this.rubber.style.display === "block"`(src/mindmap.ts:1145)、`menu.style.display`(src/mindmap.ts:1795, :1803)、`plusBtn` の `visibility` 属性(src/mindmap.ts:950-951, :954)、`hint.style.display`(src/mindmap.ts:293)、`editor.style.display`(src/mindmap.ts:905, :923)— 開閉状態が全部 DOM プロパティ。`editor` の可視性だけは `editingId !== -1`(src/mindmap.ts:928)という JS 側の真実と二重管理。

---

## 3. 未確認

- `applyPaneVis` の focus 救済(src/main.ts:934-935)は、クラスを `display:none` に変えた**直後**に `document.activeElement` を読む。ブラウザの focus fixup が同期で走るか(→ 救済が発火せず focus が `<body>` に落ちてマップのキー操作が全滅)、次のスタイル解決まで遅延するか(→ 救済が発火する)で結果が正反対になる。**未確認**。決着させるには: Chrome で MD ペインにフォーカスした状態で「MD」ボタンを押し、`document.activeElement` が `#map-pane` か `body` かを見る。
- 項目8 の CodeMirror 側の挙動(`Decoration.mark` が範囲末尾への挿入を取り込むか)は `deco.map(tr.changes)`(src/editor.ts:70)のマッピング規則に依存する。**未確認**。ただし「applySnap が選択集合の変化時にしか highlight を再送しない」(src/main.ts:199)という構造的事実はソースから確定している。
- `ensureVisible`(src/mindmap.ts:881-895)/`centerOn`(:871-878)/`toWorld`(:269-275)には `fitView`(:751-754)が持つ「ペインにサイズがあるか」のガードが無い。マップペインを隠したまま `runCmd` 経由で `ensureVisible` に到達できるかは、focus 救済のレース次第なので **未確認**。

### D-状態の重複-1 / CONFIRMED / `src/main.ts:140, src/main.ts:1100, src/style.css:26, src/style.css:9`

**インラインの --accent-soft が :root.light の指定を恒久的に殺している(ライトテーマの CSS が死にコード)**

**根拠**: applyColor(): rootStyle.setProperty("--accent-soft", `rgba(${r}, ${g}, ${b}, 0.2)`) — documentElement のインラインスタイル。
boot: applyColor(localStorage.getItem(LS_COLOR) ?? DEFAULT_COLOR) が src/main.ts:1100 で無条件に実行される(DEFAULT_COLOR="#5932ff" は正規表現 src/main.ts:132 を通る)。
style.css:9  :root      { --accent-soft: rgba(89, 50, 255, 0.2); }
style.css:26 :root.light { --accent-soft: rgba(89, 50, 255, 0.12); }

**負債**: アクセント色の「実効値」が documentElement のインラインスタイルに置かれている。インラインは :root にも :root.light にも勝つので、ライトテーマ用に用意された薄いアルファ(0.12)は起動直後から到達不能になる。テーマは class、色はインラインスタイルという 2 つの別々の DOM チャネルに置かれ、片方がもう片方のカスケードを無効化している。CSS 変数を「テーマ依存の派生値」として書いた設計と、JS が「テーマ非依存の実効値」として上書きする設計が衝突している。

**このままだと顕在化するバグ**: 同期が破れる瞬間: boot の src/main.ts:1100 が走った直後。以降どのタイミングでライトテーマに切り替えても --accent-soft は 0.2 のまま。結果、ライトテーマで accent-soft を使う全箇所 — トップバーのボタン hover(style.css:80)、マップペインのフォーカスリング(:113)、選択ノードのハイライト(:93 .cm-mmm-selected)、ラバーバンドの塗り(:273)、コンテキストメニューの hover(:313) — が意図の 1.67 倍濃く出る。白背景上で md ペインの選択ハイライトが読みづらいというバグ報告が来ても、style.css:26 を修正しても直らない(インラインが勝つ)ため、原因究明に時間が溶ける。今後 --accent-soft 以外のテーマ依存変数を applyColor が触り始めると、同じ形の不具合が線形に増える。

**検証の根拠**: src/main.ts:140 が --accent-soft を documentElement の**インライン**宣言として書き、src/main.ts:1100 が boot で無条件に applyColor を実行する。DEFAULT_COLOR(src/main.ts:68 = "#5932ff")は src/main.ts:132 の正規表現を通るので早期 return はせず、インライン宣言は必ず存在する。src/style.css:26 の :root.light は作者スタイルシート規則であり !important も無い(style.css 全 328 行に !important は .pane-off:84 のみ、--accent-soft には無い)ので、インラインが常に勝つ。grep 上 removeProperty は 0 件、--accent-soft の他の書き手も 0 件、applyTheme(src/main.ts:1076-1085)はこの変数に触れず、style.css に @media も 0 件。よってライト用 0.12 は boot 直後から到達不能。

**検証による訂正**: 消費側の行番号を 1 つ訂正: ラバーバンドの塗りは src/style.css:272(:273 は pointer-events)。また死ぬのは --accent-soft **1 個だけ**で、--accent は :root.light(style.css:19-32)が再定義していないためインラインとの衝突は起きない。「テーマ依存変数を applyColor が触り始めると線形に増える」は将来予測であって現状の事実ではない。

**修正コスト**: 小(5-10行)。applyColor から --accent-soft の設定を外し、CSS 側で color-mix(in srgb, var(--accent) 20%, transparent) 等に置き換えて :root.light で比率だけ変える。ただし applyColor の r/g/b 分解(src/main.ts:135-137)がこの用途にしか使われていないので併せて削れる。

### D-状態の重複-2 / CONFIRMED / `src/main.ts:132-133, src/main.ts:139-140, src/main.ts:145-149, src/main.ts:165-174, src/main.ts:1100`

**アクセント色の現在値を getComputedStyle から読み戻しており、applyColor の早期 return と組み合わさって壊れた localStorage 値が永久に生き残る**

**根拠**: applyColor 冒頭: const m = /^#?([0-9a-f]{6})$/i.exec(hex); if (!m) return;  ← 検証失敗時、インラインも favicon も localStorage も一切触らずに黙って抜ける。
ロゴ click(src/main.ts:166-172): colorInput.value = /^#[0-9a-f]{6}$/i.test(getComputedStyle(document.documentElement).getPropertyValue("--accent").trim()) ? getComputedStyle(document.documentElement).getPropertyValue("--accent").trim() : DEFAULT_COLOR;
(同じ getComputedStyle を 2 回呼んで 2 回 trim している)
localStorage への書き込みは try/catch で握り潰す(src/main.ts:145-149)。

**負債**: 色の真実が 5 箇所に散っている(インライン --accent / localStorage mmm.color / style.css:8 の :root 既定 / DEFAULT_COLOR src/main.ts:68 / colorInput.value)のに、権威が「documentElement の計算値」という DOM に置かれている。applyColor が唯一の書き手なのにバリデーション失敗を無音の no-op にしているため、永続層と実効層が食い違ったまま安定してしまう。

**このままだと顕在化するバグ**: 同期が破れる瞬間: (1) localStorage の mmm.color が想定外の形式になった瞬間 — 3桁hex `#f00`、`rgb(...)`、旧バージョンや手動編集、拡張機能。boot の applyColor(src/main.ts:1100)が早期 return → インラインは設定されず getComputedStyle は style.css:8 の #5932ff を返す → ロゴを開くとピッカーは #5932ff を指すが localStorage は壊れた値のまま。ユーザーが色を変えない限り毎回の起動で無音で無視され続ける。しかも壊れた値は上書きされないので、後から applyColor の正規表現を緩めた瞬間に「何年も前に保存された謎の色」が突然復活する。(2) localStorage.setItem が失敗した瞬間(容量超過 / プライベートモード / サードパーティ Cookie ブロック) — DOM は新色、永続は旧色。ユーザーは色を変えたつもりでリロードすると戻っている、を再現できず「たまに戻る」バグとして残る。

**検証の根拠**: 引用したコードはすべて実在する: 早期 return は src/main.ts:132-133、インライン書き込みは :139-140、localStorage 書き込みの握り潰しは :145-149、ロゴ click の getComputedStyle 二重呼び出しは :166-171。現在色を保持する JS 変数は存在しない(grep: --accent の書き手は :139 のみ、LS_COLOR の書き手は :146 のみ)。不正値が来れば :133 で抜けるためインラインも localStorage も更新されず、永続層に不正値が残ったまま実効層は style.css:8 の既定で安定する、という記述はコードのとおり。

**検証による訂正**: 因果の記述が誤り。getComputedStyle の読み戻し自体は破綻を生まない: 返るのは applyColor が直前に書いたインライン値か、無ければ style.css:8 の #5932ff で、これは DEFAULT_COLOR(src/main.ts:68)と同一値なので src/main.ts:172 の else 分岐は事実上デッドで、ピッカーは常に妥当な色を指す。不正値が永続する状態も**アプリ単体では到達不能**である(applyColor が LS_COLOR の唯一の書き手で、常に正規化済み `#rrggbb` しか書かない)ので、前提には外部書き換え(手動編集/拡張機能/旧版)が必要。シナリオ(2)の setItem 失敗も色に固有ではなく、このファイルの全永続化(:106-108, :147, :485, :587, :930, :1082)が同じ形で失敗を握り潰す一般的劣化。正しい言い換え: 「現在色を保持する JS 変数が無く、applyColor が検証失敗を無音の no-op にしているため、不正な永続値を検出も修復もできない」。

**修正コスト**: 小(10-15行)。色を JS のモジュール変数 currentColor に持たせ、applyColor は失敗時に DEFAULT_COLOR へフォールバックして必ず書き戻す。ロゴ click は currentColor を読む。getComputedStyle の 2 重呼び出しも消える。

### D-状態の重複-3 / CONFIRMED / `src/main.ts:1076-1085, src/main.ts:1087-1091, src/main.ts:1096-1098, src/editor.ts:88, src/editor.ts:102`

**テーマの実効値が documentElement の class にしかなく、boot で OS 由来の値を無条件に永続化するため OS 追従は初回のみ**

**根拠**: applyTheme(t): document.documentElement.classList.toggle("light", t === "light"); editor.setTheme(t !== "light"); btnTheme.textContent = t === "light" ? "◐" : "◑"; localStorage.setItem(LS_THEME, t);  ← 4 箇所に同じ事実を書く。JS 変数には残さない。
トグル: applyTheme(document.documentElement.classList.contains("light") ? "dark" : "light");  ← 現在値の唯一の読み出しが DOM。
boot: applyTheme(stored ?? (osLight ? "light" : "dark"));  ← stored が null でも applyTheme が localStorage.setItem を実行する。
matchMedia は src/main.ts:1097 で .matches を 1 回読むだけ。change リスナは grep で 0 件。style.css の @media も 0 件。
editor.ts:102 themeComp.of(DARK_EXT) — 初期値は無条件に dark。

**負債**: テーマという 1 つの事実が「documentElement の class(実効値)」「localStorage(永続値)」「MdEditor.themeComp の中身」「btnTheme.textContent」の 4 箇所に複製され、権威が DOM の class になっている。さらに boot で派生値(OS 設定から導いた既定)を永続値と同じ場所に書き込んでいるため、「まだユーザーが選んでいない」という状態を表現できなくなっている。

**このままだと顕在化するバグ**: 同期が破れる瞬間: 初回起動の src/main.ts:1098 が走った直後。stored が null でも applyTheme が localStorage に書くので、以降 mmm.theme は必ず非 null。src/main.ts:1073 のコメント「default = OS, fallback dark」は初回の 1 回しか成立せず、以後 OS をダークに変えても、別の PC で同じプロファイルを同期しても、アプリはライトのまま。matchMedia の change 未購読なので、セッション中に OS がダークへ切り替わっても(macOS の自動切替、Windows の夜間モード)追従しない。style.css に @media が 1 件も無いので CSS 側の救済も無い。加えて applyTheme の localStorage.setItem が失敗すると DOM だけが変わり、リロードで巻き戻る。「テーマがたまに戻る」「OS に合わない」という報告が来ても、権威が DOM の class なので JS 側にログを仕込む対象が無い。

**検証の根拠**: applyTheme(src/main.ts:1076-1085)は class(:1077)/editor.setTheme(:1078)/btnTheme.textContent(:1079)/localStorage(:1081)の 4 箇所に書き、JS 変数には残さない。現在値の唯一の読み出しは src/main.ts:1089 の classList.contains("light")。boot(src/main.ts:1095-1098)は stored が null でも applyTheme を呼ぶので :1081 が必ず走り、以後 mmm.theme は非 null。grep 実測: matchMedia は src/main.ts:1097 の 1 件のみで change リスナ 0 件、src/style.css に @media 0 件、visibilitychange 0 件。よって src/main.ts:1073 のコメント「default = OS」が成立するのは初回起動の 1 回だけで、以後 OS 変更にもプロファイル同期にも追従しない。editor.ts:88/:102 の themeComp 初期値 DARK_EXT も引用どおり。

**検証による訂正**: 「4 箇所に複製され権威が DOM」の部分は負債の核ではない: applyTheme が唯一の書き手で 4 つは単なるファンアウト、DOM class の読み出しも :1089 の 1 箇所だけなので、これ自体では不整合は生まれない。実際に効いている欠陥は 2 つ — (a) boot(:1098→:1081)が「まだ選んでいない」という派生状態を永続値として固定してしまうこと、(b) matchMedia change の未購読と @media 0 件で CSS 側の救済も無いこと。editor.ts:102 の DARK_EXT 初期値も boot の applyTheme が即座に上書きする(editor 生成は :470、boot は :1095)ため実害は無い。

**修正コスト**: 中(20-30行)。theme を JS 変数 + 明示的な "auto"|"light"|"dark" の 3 値に昇格。boot は選択が無いとき永続化しない。matchMedia の change を購読して auto のときだけ適用。btnTheme.textContent と editor.setTheme はその変数からの純粋な派生にする。

### D-状態の重複-4 / CONFIRMED / `src/mindmap.ts:1678-1682, src/mindmap.ts:585-594, src/mindmap.ts:558-559, src/main.ts:678, src/mindmap.ts:1668`

**drop-child クラスだけが render() で再構築されず、ドラッグ中の非同期 render でドロップ先の表示が消えたまま drop が実行される**

**根拠**: render() が作る class 列(src/mindmap.ts:586-592):
  "node" + root + link-card + hidden-node + (sel.has(n.id) ? " selected" : "") + (this.dragging?.subtree.has(n.id) ? " dragging" : "")
→ selected と dragging は JS 状態から再構築されるが、drop-child は含まれていない。
drop-child を付ける唯一の場所は updateDrop(src/mindmap.ts:1680) — pointermove でしか呼ばれない。
render() は毎回 this.nodeLayer.replaceChildren()(src/mindmap.ts:559)で全 <g> を破棄する。
render() はドラッグ中でも外から呼ばれうる: loadAsset の成功時に map.render()(src/main.ts:678)。
src/mindmap.ts:1668 のコメント: 「indicator is mandatory (spec 3.3.2)」

**負債**: ドロップ先という 1 つの事実が this.dropTarget(JS、src/mindmap.ts:195)と .drop-child クラス(DOM)と #drop-line の visibility 属性(SVG、src/mindmap.ts:1692)の 3 箇所に分かれ、しかも 3 つの寿命が全部違う。dropTarget は pointermove/pointerup/pointercancel が管理、drop-child は nodeLayer の寿命に縛られ、dropLine は viewport 直下なので render に破壊されない。render() が「JS 状態からの純粋な再構築」を謳いながら 1 つだけ取りこぼしている。

**このままだと顕在化するバグ**: 同期が破れる瞬間: ノードをドラッグ開始 → ドロップ先の上でホバー(.drop-child のリングが出る)→ マウスボタンを押したまま、その瞬間に画像サムネイルが解決して src/main.ts:678 の map.render() が走る。結果、リングだけが消え、#drop-line は残り、this.dropTarget は生きたまま。ユーザーには「どこに落ちるか分からない」状態になるが、ボタンを離すと src/mindmap.ts:1159 の this.host.move(ids, drop.id, drop.pos) は古い dropTarget で実行される。仕様が「インジケータ必須」と明記している契約(src/mindmap.ts:1668)を、その契約を知らない render() が破る。画像を含む文書ほど再現しやすく、画像が無い環境では絶対に再現しないため「たまにノードが変な所に移動する」というバグとして長期化する。

**検証の根拠**: src/mindmap.ts:585-592 の class 列は root/link-card/hidden-node/selected/dragging を JS 状態から再構築するが drop-child を含まない。src/mindmap.ts:559 の nodeLayer.replaceChildren() が毎 render で全 <g> を破棄する。drop-child を付けるのは updateDrop の src/mindmap.ts:1678-1682 のみで、これは pointermove(:1133)からしか呼ばれない。render() の呼び出し元は src/main.ts:198 と src/main.ts:678(loadAsset 成功時)の 2 箇所だけ(grep 実測)で、後者はドラッグ中でも非同期に届く。dragging クラスだけが :592 で救われていて drop-child が漏れているという非対称は、コードのとおり実在する。

**検証による訂正**: 結果の記述が過大。#drop-line は viewport 直下(src/mindmap.ts:216, :229-235)で nodeLayer の外にあるため render() に破壊されず、src/mindmap.ts:1668 が「必須」と言うインジケータ本体は生き残る。消えるのは pos=0 のリングだけで、次の pointermove(:1133→updateDrop)で復帰する。また render() は host.nodes() を再描画するだけで木を変えないので、pointerup(:1159)の move は「ユーザーが最後にホバーした場所」に正しく落ちる。したがって「たまにノードが変な所に移動する」は導けない。正しい被害は「静止したまま離すとリングだけが欠けた状態で drop する(表示契約の一時的破れ)」。

**修正コスト**: 小(3-5行)。render() の class 列に (this.dropTarget?.id === n.id ? " drop-child" : "") を足す。ただし根本解決は「DOM class を JS 状態からの派生に統一する」ことで、そのためには updateDrop / startDrag / refreshSelection の直接 classList 操作(src/mindmap.ts:1610, :1669, :1680, :1714, :1811)を全部やめる必要がある(30-40行)。

### D-状態の重複-5 / CONFIRMED / `src/mindmap.ts:1143-1153, src/mindmap.ts:1089-1095, src/mindmap.ts:1062-1071, src/mindmap.ts:1081, src/mindmap.ts:1137, src/mindmap.ts:1060, src/mindmap.ts:1302`

**ラバーバンドの「実際に動いたか」をインラインスタイル文字列から parseFloat で復元しており、rubberStart が pointerdown でクリアされず、pointerup に e.button のフィルタが無い**

**根拠**: pointerup(src/mindmap.ts:1144-1147):
  const moved = this.rubber.style.display === "block" &&
    (parseFloat(this.rubber.style.width) > 3 || parseFloat(this.rubber.style.height) > 3);
→ ドラッグ距離という判断材料を、pointermove(src/mindmap.ts:1089-1095)が自分で書いた CSS 文字列から読み直している。rubberStart(src/mindmap.ts:192)には始点しか入っていない。
pointerdown(src/mindmap.ts:1062-1071): ノードに当たれば this.dragCand を、当たらなければ this.rubberStart を立てるが、もう一方を null にしない。
pointermove の分岐順(src/mindmap.ts:1075, :1081, :1125): panning → rubberStart → dragCand。rubberStart が残っていると dragCand は永久に読まれない。
pointerdown は src/mindmap.ts:1060 で if (e.button !== 0) return; を持つが、pointerup(src/mindmap.ts:1137)には button の判定が一切ない。
window blur(src/mindmap.ts:1302)は this.hideMenu() だけで、panning / rubberStart / dragCand / dragging を触らない。

**負債**: ポインタ操作の状態が JS フィールド 5 個(spaceDown / panning / rubberStart / dragCand / dragging)と DOM 3 種(rubber のインラインスタイル、pane.style.cursor、node の class)に分散し、それぞれ消す場所が違う。pointerup は 4 つのフィールドを見るが 1 つずつ早期 return する排他前提のコードなのに、pointerdown はその排他を保証していない。「どのジェスチャ中か」を表す 1 個の状態機械が無い。

**このままだと顕在化するバグ**: 同期が破れる瞬間 A: ノードを左ボタンでドラッグしている最中に右クリックする。pointerdown は e.button !== 0 で無視されるが、右ボタンの pointerup は src/mindmap.ts:1137 に素通りし、this.dragCand が生きているので src/mindmap.ts:1163-1190 の「ノードの単純クリック」分岐に入る → this.host.setSelection([id], id) で複数選択が 1 個に潰れ、dragCand が null になってドラッグが死ぬ。左ボタンはまだ押されたままなので、以後マウスを動かしても何も起きない。
同期が破れる瞬間 B: ラバーバンド中に pointerup も pointercancel も来ない(ネイティブモーダル、ウィンドウ切替、キャプチャ喪失)。this.rubberStart が残り、次にノードを掴もうとしても pointermove が src/mindmap.ts:1081 で先に rubberStart 分岐へ吸われる → ノードが動かず、古い始点から画面を横断する選択矩形が出て、意図しない大量選択のまま dd を押すと大量削除になる。window blur(src/mindmap.ts:1302)が menu しか片付けないので自己復旧しない。

**検証の根拠**: 3 つの機構すべてが引用行に実在する。(1) src/mindmap.ts:1144-1147 が this.rubber.style.width/height を parseFloat して移動判定にしている(始点は :192 にあり e.clientX も手元にあるのに使っていない)。(2) pointerdown(:1062-1071)は dragCand と rubberStart のどちらか一方を立てるだけで他方を null にせず、pointermove の分岐順(:1075 panning → :1081 rubberStart → :1125 dragCand)は排他を前提にしている。(3) pointerdown には :1060 の `if (e.button !== 0) return;` があるが pointerup(:1137)には button 判定が無い。window blur(:1302)は hideMenu のみ、lostpointercapture ハンドラは 0 件(grep)。瞬間 A は成立する: 左ボタン押下中の右ボタン pointerup は(ポインタキャプチャで pane に再ターゲットされて)そのまま :1137 に届き、dragCand が生きていれば :1163-1190 の単純クリック分岐で選択が 1 個に潰れ dragCand が null になる。

**検証による訂正**: 2 点補正。(a) 瞬間 A はドラッグ閾値(:1130、64px²)を越えた後だともっと悪い: 右ボタンの pointerup が :1155 の dragging 分岐に入り、左ボタンを押したまま **move が実行される**。(b) DOM 読み戻し(:1144-1147)自体には破綻経路が無い — 同じハンドラが直前に書いた文字列を読み直しているだけで、display!=="block" の場合は先に弾かれるので parseFloat の NaN も無害。負債の実体は「排他の未保証」と「button フィルタの欠落」の 2 つで、readback は臭いに留まる。なお瞬間 B の後始末漏れはさらに深く、rubber 分岐(:1143-1153)は return する際に dragCand を消さないので dragCand も居残る。

**修正コスト**: 中(20-30行)。pointerdown で他ジェスチャのフィールドを明示的に null にする、pointerup に e.button === 0(または現在のジェスチャに対応するボタン)のガードを足す、window blur / visibilitychange で全ジェスチャ状態をリセットする。moved の判定は rubberStart と現在座標から直接計算し、DOM 読み戻しをやめる。

### D-状態の重複-6 / CONFIRMED / `src/mindmap.ts:189, src/mindmap.ts:994-1010, src/mindmap.ts:1048, src/mindmap.ts:1140, src/mindmap.ts:1302`

**spaceDown に blur リセットが無く、Space を押したままフォーカスを失うと恒久的にパンモードに固着する**

**根拠**: keydown(window, src/mindmap.ts:994-1004): e.code === "Space" && !this.isEditing() && document.activeElement === pane のときだけ this.spaceDown = true; pane.style.cursor = "grab";
keyup(window, src/mindmap.ts:1005-1010): if (e.code === "Space") { this.spaceDown = false; if (!this.panning) pane.style.cursor = ""; }
spaceDown を読む場所: src/mindmap.ts:1048(左クリックをパンに変える)、:1140(pointerup 後のカーソル復帰)。
window blur ハンドラ(src/mindmap.ts:1302)は hideMenu のみ。visibilitychange のリスナは grep で 0 件。

**負債**: モディファイアキーの押下状態という「ブラウザがいつでも取りこぼしうる事実」を JS フィールドに保持し、さらに pane.style.cursor という DOM にも二重化している。keydown 側にはフォーカス条件(document.activeElement === pane)があるのに keyup 側には無い、という非対称は「取りこぼし対策のつもり」だが、キー自体が別ウィンドウに行く場合には効かない。

**このままだと顕在化するバグ**: 同期が破れる瞬間: Space を押しながらパンしている最中に Alt+Tab / Win+D / OS の通知でフォーカスが移る。keyup は別ウィンドウに行くので this.spaceDown は true のまま、pane.style.cursor も "grab" のまま残る。戻ってきてノードを左クリックすると src/mindmap.ts:1048 が真になり、選択ではなくパンが始まる。ユーザーからは「クリックしてもノードが選べなくなった」に見え、Space を押して離すまで直らない(押して離す発想に至らない)。リロード以外の復旧手段が無い。同じ形の固着は panning / rubberStart / dragCand / dragging すべてに存在する(項目6 の瞬間 B と同根)。

**検証の根拠**: keydown(src/mindmap.ts:994-1004)は document.activeElement === pane を条件に spaceDown=true と pane.style.cursor="grab" を立て、keyup(:1005-1010)にはその条件が無い、という非対称は引用どおり。spaceDown の読み手は :1048(左クリックをパンに変換)と :1140 の 2 箇所。window blur(:1302)は hideMenu のみ、visibilitychange のリスナは grep で 0 件、lostpointercapture も 0 件。Space 押下中に別ウィンドウへフォーカスが移れば keyup は届かず、戻ってからの左クリックが :1048 で panning に化ける、という経路はソース上成立する。panning / rubberStart / dragCand / dragging にも同じ取りこぼし経路がある(pointerup と pointercancel:1194-1202 でしか消えない)という指摘も正しい。

**検証による訂正**: 復旧手段の記述が誤り。keyup(:1005-1010)には**フォーカス条件が無い**ので、その後アプリ内のどこで Space を離しても(例: md ペインで空白を 1 つ打つ)spaceDown は false に戻る。「リロード以外の復旧手段が無い」は成立せず、同じ段落内の「Space を押して離すまで直らない」とも矛盾している。正しくは「次に Space キーが離されるまで固着する(ユーザーには原因が見えない)」。

**修正コスト**: 極小(5行)。window の blur と document の visibilitychange で spaceDown = false / panning = null / rubberStart = null / dragCand = null / stopDragVisuals() を行う 1 関数を足す。項目6 と同時に直すべき。

### D-状態の重複-7 / CONFIRMED / `src/main.ts:199, src/main.ts:186-195, src/main.ts:210-222, src/editor.ts:68-84, src/editor.ts:70`

**md ペインの選択ハイライトは選択『集合』が変わったときしか再送されず、範囲だけが動いたときは CodeMirror 側のマッピングに任せきりで実際の subEnd とズレる**

**根拠**: applySnap(src/main.ts:185-199):
  let selChanged = false;
  for (const id of [...selection]) { if (!byId.has(id)) { selection.delete(id); selChanged = true; } }
  if (anchorId !== -1 && !byId.has(anchorId)) { ...; selChanged = true; }
  ...
  if (selChanged) syncSelectionViews(false);
→ selChanged は「id が消えたか」だけ。範囲(hs / subEnd)の変化では立たない。
syncSelectionViews(src/main.ts:212-217)が editor.highlight を呼ぶ唯一の場所で、範囲を n.hs / n.subEnd から作り直す。
highlightField.update(src/editor.ts:70): deco = deco.map(tr.changes); — 効果が来ない限り、デコレーションはユーザー自身のトランザクションでマッピングされるだけ。

**負債**: 選択集合が 3 箇所(selection という Set / .node.selected クラス / CodeMirror の DecorationSet)に複製されているが、3 つの更新規則が違う。selection は id の集合、.node.selected は render で id から再構築、DecorationSet は文字オフセットの範囲で、しかもコアの再導出ではなく CodeMirror 独自の変更マッピングで維持される。id ベースの真実と、オフセットベースの表現の間に、同期を強制する経路が『集合が変わったときだけ』という条件付きでしか無い。

**このままだと顕在化するバグ**: 同期が破れる瞬間: マップでノード X を選択(md ペインに X の [hs, subEnd) がハイライトされる)→ そのまま md ペインに移り、X の本文の末尾に行を書き足す。onUserEdits → applySnap(snap, "cm") が走るが、X は消えていないので selChanged は false、syncSelectionViews は呼ばれない。コア側の X.subEnd は伸びているのに、md ペインのハイライトは CodeMirror の deco.map が決めた範囲のまま。以後 X を削除すると、ハイライトが示していた範囲より広い(または狭い)ブロックが消え、ユーザーの『選択されている範囲』の理解と実際の削除範囲が食い違う。F-005(2 個目以降の # が前ノードの subEnd に含まれる)と重なると、ハイライトに出ていない見出しブロックが道連れに消える。再現には md ペインとマップペインを跨ぐ操作順が要るので、単体では絶対に出ない。

**検証の根拠**: applySnap の selChanged は src/main.ts:186-195 で「id が byId から消えたか」だけで立ち、範囲(hs/subEnd)の変化では立たない。再送は src/main.ts:199 の `if (selChanged) syncSelectionViews(false)` に限られ、editor.highlight の呼び出し元は src/main.ts:212 の 1 箇所のみ(grep 実測)。そこで初めて n.hs / n.subEnd から範囲が作り直される(:216)。それ以外の間、デコレーションは src/editor.ts:71 の `deco = deco.map(tr.changes)` によりユーザー自身のトランザクションで写像されるだけ(highlightField:68-84)。md ペインでの打鍵は applySnap(snap, "cm")(src/main.ts:299)を通るが選択集合は変わらないので再送されず、id ベースの真実(subEnd)とオフセットベースの表現が独立に動く。

**検証による訂正**: ズレの向きは両方向とも実在し、片方はより簡単に出る。(a) 末尾追記: Decoration.mark は既定で inclusiveEnd=false なので `to` 位置ちょうどの挿入では伸びず、コアの subEnd だけが伸びる(ハイライトが狭くなる)。(b) より容易な経路: X の本文中に、より浅い見出しを打ち込むと X.subEnd はその hs まで縮むのに、デコレーションは古い広い範囲のまま残る(ハイライトが広くなる)。どちらもペイン跨ぎの操作順が要るという指摘は正しい。

**修正コスト**: 小(1-3行)。applySnap の末尾で選択が空でなければ無条件に syncSelectionViews(false) を呼ぶ。ただし syncSelectionViews は毎回 editor.highlight を dispatch するので、F-002 と同じく打鍵ごとのコストが増える。範囲が実際に変わったときだけ送る差分判定を入れるなら 10-15行。

### D-状態の重複-8 / CONFIRMED / `src/main.ts:35, src/main.ts:206-208, src/main.ts:552, src/main.ts:576-583, src/main.ts:612-615, src/main.ts:850-853, src/main.ts:1111-1114`

**savedText がディスク内容の代理として使われ、storage イベント未購読・非 FS ブラウザの保存キャンセル時も無条件に更新されるため dirty 判定が嘘になる**

**根拠**: updateDirty(): elDirty.hidden = core.getText() === savedText;  ← 毎スナップショット、全文比較。
confirmDiscard(): if (core.getText() === savedText) return true;  ← savedText が唯一の判断材料。
beforeunload: if (core.getText() !== savedText) e.preventDefault();  ← 同上。
saveFile の非 FS 分岐(src/main.ts:576-581):
  const a = document.createElement("a"); a.href = URL.createObjectURL(...); a.download = fileName; a.click(); URL.revokeObjectURL(a.href);
  ← ダウンロードの成否は分からない。にもかかわらず直後の src/main.ts:582 で savedText = text; が無条件に走る。
boot: savedText = localStorage.getItem(LS_SAVED) ?? storedText ?? SAMPLE;(src/main.ts:1113)
`grep -an 'addEventListener("storage"' src/` は 0 件。

**負債**: 文書テキストが st.text(真実) / CodeMirror doc / localStorage mmm.text / localStorage mmm.savedText / ディスクの .md / savedText 変数 の 6 箇所にあり、そのうち savedText だけが『他の 5 つと照合されないローカルな信念』になっている。savedText はディスクの内容ではなく『最後にこのタブがディスクへ書いたと信じている内容』であり、その差を検出する手段(ファイルの mtime 確認、storage イベント、再読み込み)が 1 つも無い。

**このままだと顕在化するバグ**: 同期が破れる瞬間 A: Firefox / Safari(hasFs が false、src/main.ts:505)で Mod+S を押し、ブラウザのダウンロードダイアログを『キャンセル』する。src/main.ts:582 の savedText = text は無条件に実行済みなので dirty ドットが消え、beforeunload の警告(src/main.ts:852)も confirmDiscard(src/main.ts:613)も無効化される。ユーザーは保存できたと信じてタブを閉じ、変更は localStorage にしか残らない。
同期が破れる瞬間 B: 同じ .md を 2 タブで開く、あるいは外部エディタで .md を編集する。storage イベントを購読していないので他タブの mmm.text 更新は届かず、mmm.savedText も外部の変更を知らない。リロードすると savedText は古い『自分が書いた内容』のままなので dirty は消えており、Ctrl+S が他タブ/外部エディタの変更を無警告で上書きする。src/main.ts:511-513 のコメントが handle について同じ危険を認識しているのに、テキスト側には同じ配慮が無い。

**検証の根拠**: savedText(src/main.ts:35)は dirty ドット(:206-208)、confirmDiscard(:612-615)、beforeunload(:850-853)の唯一の判断材料。非 FS 分岐(:576-581)は <a download>.click() の成否を知る術が無いのに、:582 の `savedText = text;` は try 内で分岐に関係なく実行され、続く :584-586 が mmm.savedText / mmm.fileName まで書く。boot は :1113 で `localStorage.getItem(LS_SAVED) ?? storedText ?? SAMPLE`。`addEventListener("storage"` は grep で 0 件(src/ 全体)。よってダウンロードをキャンセルしても dirty は消え、beforeunload の警告(:852)も confirmDiscard(:613)も無効化される、という記述はコードのとおり。

**検証による訂正**: 2 点追記して補強。(a) 偽クリーン状態はリロードを跨いで残る — LS_SAVED は :585 だけでなく loadText の :484 でも書かれるため。(b) 瞬間 B はさらに強い: 2 タブは同じ mmm.text(:105、250ms デバウンス)を無調停で上書きし合うので、storage 未購読の影響は savedText だけでなく自動保存本体にも及ぶ。なお :580 の URL.revokeObjectURL が a.click() の直後に走る点はこの主張の範囲外だが、非 FS 保存経路の信頼性をさらに下げる。

**修正コスト**: 中。A は 5-10行(FS 分岐の外で savedText を更新しない、非 FS では『保存した』と断定しない表示にする)。B は 30-50行(storage イベント購読、保存前にディスクの mtime/内容を再確認、衝突時のプロンプト)。

### D-状態の重複-9 / CONFIRMED / `src/main.ts:198, src/main.ts:919-936, src/mindmap.ts:290-729, src/mindmap.ts:558-559, src/style.css:84, src/mindmap.ts:751-754, src/mindmap.ts:881-895`

**render() が paneVis を一切見ないため、マップペインを隠しても打鍵ごとの SVG 全面再構築コストを払い続ける**

**根拠**: applySnap: map.render();  ← src/main.ts:198、条件なし。
applyPaneVis は class を付け替えるだけ(src/main.ts:922-927)で、MindMap 側へは何も通知しない。
.pane-off { display: none !important; }(src/style.css:84)
render() 本体(src/mindmap.ts:290-729)に可視性の判定は 1 つも無い。this.edgeLayer.replaceChildren() / this.nodeLayer.replaceChildren()(:558-559)が毎回走る。
計測は切り離し canvas(src/mindmap.ts:95)なので display:none でも成功し、レイアウト計算も全て実行される。
『ペインにサイズがあるか』のガードは fitView(src/mindmap.ts:751-754)にしか無く、ensureVisible(:881-895)/ centerOn(:871-878)/ toWorld(:269-275)は getBoundingClientRect の 0 をそのまま使う。

**負債**: ペイン可視性が paneVis(src/main.ts:914)という JS 変数と DOM の class の両方にあるのに、その事実を消費すべき render() には届いていない。可視性は『CSS の display で表現される見た目の話』として扱われ、『計算を省いてよいという契約』としては扱われていない。同じ形で『ペインにレイアウトが付いているか』も getBoundingClientRect を毎回叩いて判定しており、4 箇所のうち 1 箇所しかガードを持っていない。

**このままだと顕在化するバグ**: 同期が破れる瞬間: ユーザーが『マップ』ボタン(src/main.ts:946)でマップを隠し、md ペインだけで大きな文書を編集する。F-002 の計測(2001ノードで 25.8ms、5000ノードで 70.2ms)がそのまま打鍵ごとに乗り続け、しかも画面には何の変化も無い。ユーザーは『マップを隠せば軽くなる』と期待するのに逆に何の効果も無く、原因が見えない。さらに render は host.imageUrl(src/mindmap.ts:689)を呼ぶので、見えないペインのために画像の読み込みとフォルダ権限の要求まで走る。将来ノード数の上限を上げたり、隠したペインで大きなファイルを開く運用が入った時点で、体感がリニアに悪化する。ガードの非対称(fitView だけがサイズを見る)も、隠したペインで ensureVisible に到達する経路が 1 本でも生まれた瞬間に tx/ty が壊れ、ペインを再表示しても何も見えない状態になる。

**検証の根拠**: applySnap の map.render()(src/main.ts:198)は無条件。applyPaneVis(src/main.ts:919-936)は class の付け替えと localStorage 書き込みだけで MindMap へは何も通知せず、paneVis の参照箇所も grep 上 src/main.ts:914/921/939/951/954 の 5 件のみで src/mindmap.ts には 1 件も無い。render() 本体(src/mindmap.ts:290-729)には可視性判定が無く、:558-559 の replaceChildren が毎回走る。getBoundingClientRect の呼び出しは src/mindmap.ts:270/750/874/884/1018/1068/1082 の 7 箇所で、サイズガードを持つのは fitView(:751-754)だけ — centerOn(:871-878)も ensureVisible(:881-895)も toWorld(:269-275)も 0 をそのまま使う、という非対称も実在する。計測は切り離し canvas(src/mindmap.ts:95)なので display:none でも成立する。

**検証による訂正**: コストの記述が過大。`.pane-off { display: none !important }`(src/style.css:84)配下ではブラウザがスタイル再計算・レイアウト・ペイントを省くので、F-002 の実測値(2001 ノード 25.8ms / 5000 ノード 70.2ms、可視状態での測定)が**そのまま**残るとは言えない。残るのは JS 側(レイアウト計算 + 要素生成 + 属性設定)の分で、その割合は未確認。また「フォルダ権限の要求まで走る」は render 経由ではない — loadAsset は queryPermission が granted でなければ即 return し(src/main.ts:657-659)、requestPermission を出すのは pointerdown に載る unlockAssets(:687-701)と ensureImageDir(:704-718)。ensureVisible が隠れたペインで呼ばれる経路も現時点では存在しない(runCmd:239 に至るコマンドはマップペイン由来で、applyPaneVis:934-935 がフォーカスを退避させる)ため、こちらは将来リスクとしてのみ正しい。

**修正コスト**: 小(5-10行)。MindMap に setVisible(bool) を足し、非表示中は render を dirty フラグ立てだけにして再表示時に 1 回だけ描く。ensureVisible / centerOn にも fitView と同じサイズガードを入れる(さらに 5行)。

### D-状態の重複-10 / CONFIRMED / `src/main.ts:36, src/main.ts:511-516, src/main.ts:1115-1121, src/main.ts:763-771`

**fileHandle と IndexedDB の同期が fire-and-forget で、採用条件がファイル名の一致だけ**

**根拠**: persistHandle(): void idbSet("handle", fileHandle).catch(() => {});  ← 失敗を誰も知らない。
boot(src/main.ts:1115-1121): idbGet("handle").then((h) => { if (h && h.name === fileName) fileHandle = h; }).catch(() => {});
コメント(src/main.ts:511-513): 『a stale handle plus fresh text means Ctrl+S after reload silently overwrites the WRONG file』
画像フォルダ側も同型: dirHandle = null(同期)と void idbSet("dir", null).catch(() => {})(src/main.ts:767-768)。

**負債**: 同じ事実(どのファイルを開いているか)が JS 変数と IndexedDB に二重化され、片方の書き込みが非同期・失敗無視という非対称になっている。整合性の担保が『名前が一致すること』という、ディレクトリを区別しない弱い述語 1 本に依存している。コメント自身が危険を認識しているのに、その危険を実際に塞いでいるのは name の比較だけ。

**このままだと顕在化するバグ**: 同期が破れる瞬間: ~/a/notes.md を開いて保存 → ~/b/notes.md を開く(fileHandle が更新され persistHandle が走る)→ この idbSet が失敗する(容量、IDB のブロック、タブが即座に閉じられて transaction が中断)。リロードすると mmm.fileName は notes.md、IDB の handle は ~/a/notes.md。h.name === fileName が真になるので採用され、Ctrl+S が ~/b の内容を ~/a に書き込む。savedText(項目9)も ~/b の内容なので dirty は出ず、警告も出ない。ファイルを失うタイプの障害で、しかも再現条件が『IDB 書き込みの失敗』なので事後の追跡が極めて困難。

**検証の根拠**: persistHandle(src/main.ts:514-516)は `void idbSet("handle", fileHandle).catch(() => {})` で失敗を誰にも伝えない。boot(:1115-1121)の採用条件は `h && h.name === fileName` だけで、ディレクトリを区別しない。危険自体はコメント(:511-513)が明示しているのに、塞いでいるのは name 比較 1 本。画像フォルダ側も同型(:767-768 の `dirHandle = null` は同期、`idbSet("dir", null)` は fire-and-forget)。IDB 書き込みが失われれば、LS 側の mmm.fileName(loadText :483 で同期書き込み)だけが新しくなり、同名異ディレクトリのハンドルが採用されて Ctrl+S(:571-573)が別ファイルへ書く、という連鎖は成立する。

**検証による訂正**: 発火条件の主因を差し替えると説得力が上がる。「容量超過」より現実的なのは**永続化の非対称そのもの**: mmm.fileName は localStorage で同期に確定するのに handle は IDB の非同期トランザクション待ちなので、ファイルを開いた直後にタブ/ブラウザを閉じるとトランザクションだけが失われ、両者が食い違ったまま残る。なお復元ハンドルは saveFile:557-561 で queryPermission→requestPermission を通るが、ブラウザの許可ダイアログはファイル**名**しか出さず a/notes.md と b/notes.md を区別できないため、この再許可は柵として機能しない(「毎回許可」済みならプロンプト自体が出ない)。

**修正コスト**: 小(10-15行)。handle と一緒に一意なドキュメント ID(保存時に発番)を IDB に入れ、boot ではその ID で照合する。あるいは persistHandle の失敗を握り潰さず、失敗したら IDB の handle を削除する。

### D-状態の重複-11 / CONFIRMED / `index.html:14-16, public/favicon.svg:3, src/main.ts:119-128, src/main.ts:141-144`

**ロゴのパスと transform が 3 箇所にコピーされ、そのうち favicon.svg だけが逆向きにスケールしている(コメントが明示的に禁じている書き方)**

**根拠**: index.html:14 のコメント: 『パスは既に左右反転済みの m（ステムが右）。scale は正のまま使うこと』
index.html:15:            <g transform="translate(27.2,23) scale(0.68,0.68)" fill="currentColor">
src/main.ts:126 (faviconSvg): <g transform="translate(27.2,23) scale(0.68,0.68)" fill="${color}">
public/favicon.svg:3:        <g transform="translate(117.2,23) scale(-0.68,0.68)" fill="#5932FF">   ← x スケールが負
path の d 属性は 3 ファイルとも逐語同一(od で比較済み)。共有元は無い。
applyColor が起動時に link[rel=icon].href を data: URI で差し替える(src/main.ts:141-144)。

**負債**: 同じ図形が 3 箇所に逐語コピーされ、うち 1 箇所が別の transform を持ち、色も 3 通り(currentColor / 引数 / ハードコードされた #5932FF)。ビルド時に共有する仕組みが無いので、コメントによる口頭の規約だけが整合性を保っている。そしてその規約は既に破られている。

**このままだと顕在化するバグ**: 既に破れている: index.html:7 が参照する /favicon.svg は左右反転が 1 回多いので、ロゴ本体(ステムが右)と鏡像(ステムが左)の 2 種類のマークが同時に出荷されている。JS が読み込まれる前のタブアイコン、ブックマーク、履歴、OS のショートカット、ブラウザのファビコンキャッシュには反転した方が残り、起動後は applyColor(src/main.ts:1100 → :143)が正しい向きに差し替えるので、タブのアイコンが読み込み時に一瞬反転する。色も同様で、favicon.svg の #5932FF はユーザーがブランドカラーを変えても永久に追従しない。将来ロゴを差し替えるとき、3 箇所のうち 1 箇所を忘れる確率は経験上高く、しかも 3 箇所目(public/)はビルドを通らないので型検査でもリントでも捕まらない。

**検証の根拠**: 3 箇所とも確認した。index.html:14 のコメント「scale は正のまま使うこと」、index.html:15 `translate(27.2,23) scale(0.68,0.68)` fill=currentColor、src/main.ts:126 `translate(27.2,23) scale(0.68,0.68)` fill=${color}、public/favicon.svg:3 `translate(117.2,23) scale(-0.68,0.68)` fill="#5932FF"。path の d は 3 ファイルで逐語同一(index.html:16 / src/main.ts:121 / public/favicon.svg:4)、共有機構は無い。x スケールが負なのは favicon.svg だけで、コメント自身が「再反転すると普通の m に戻る」と書いているとおり、静的ファビコンはステムが左の鏡像になる。index.html:7 が参照するのはその /favicon.svg で、JS 側は applyColor(src/main.ts:1100 → :141-144)が link[rel=icon] を data: URI で差し替えるため、規約違反はすでに出荷済み。

**検証による訂正**: 「タブのアイコンが読み込み時に一瞬反転する」の可視性はブラウザのファビコンキャッシュ次第で、常に見えるとは限らない(未確認)。確実に言えるのは、ブックマーク/履歴/OS ショートカットなど JS が走らない文脈では反転版かつ #5932FF 固定のマークが使われ続けること。また public/favicon.svg は tsc(package.json:10 の `tsc --noEmit`、tsconfig.json:15 の include:["src"])の対象外なので型検査にもリントにも掛からない、という指摘はそのとおり。

**修正コスト**: 極小(3行)。public/favicon.svg の transform を translate(27.2,23) scale(0.68,0.68) に直す。根本解決は LOGO_PATH を単一の .ts モジュールに置き、index.html のインライン SVG も public/favicon.svg もビルド時生成にすること(15-25行 + ビルド設定)。

### 反証により除外(1 件)

- **dragging.ids / dropTarget.id が render を跨いで再検証されず、host.move だけが他の全コマンドと違って byId 検証を持たない** — 根拠の中心である非対称が事実に反する。src/main.ts:336-338 rename、:365-367 reorder、:368-370 toggleHidden はいずれも byId 検証なしで runCmd を呼んでおり、move(:371-373)は「唯一の例外」ではない。さらに死んだ id は**コア側が全て弾く**: cmd_move は normalize_selection(core/cmds.mbt:520 → core/doc.mbt:502-527、st.nodes を走査するので未知 id は out に入らない)を通し、続けて find_node の結果が負なら continue する(core/cmds.mbt:533-537)。したがってドラッグ中に dd(src/mindmap.ts:1351)や u(:1411-1414)が通って ids/dropTarget が死んでも、pointerup(:1159)の core.moveNodes は無変更で終わる。UI 側の検証欠落は load-bearing ではない。

---

## 観点: undo/redo の粒度と永続化の単位

## 1. タグ合体の状態機械（src/main.ts:246-300）

状態は 3 変数 `typeTag` / `typeKind` / `typePos`（src/main.ts:246-248）。`typeKind` は `""` | `"type"` | `"del"` | `"compose"` の 4 値。

**分岐は 5 本**（src/main.ts:251-292、この順で排他）:
1. `userEvent === "compose.end"` → `typeKind = ""` して即 return（:251-254）。編集は流さない。
2. `userEvent === "input.type.compose"` → `typeKind !== "compose"` なら `typeTag = t{++sessionN}` を発番、`typeKind = "compose"`。tag = typeTag（:256-263）。**位置チェックが一切ない**のがこの腕だけの特徴。`typePos` も更新しない。
3. `edits.length === 1 && userEvent === "input.type" && pureInsert` → `typeKind === "type" && e.from === typePos` なら前タグ再利用、さもなくば新タグ。`typePos = e.from + e.insert.length`（:268-276）。
4. `edits.length === 1 && userEvent === "delete.backward" && pureDelete` → `typeKind === "del" && e.to === typePos` なら再利用。`typePos = e.from`（:277-285）。
5. それ以外の単一編集 → `typeKind = ""`、**tag も `""` のまま**（:286-288）＝ 合体なしの単独エントリ。複数編集 → `typeKind = ""`、`tag = t{++sessionN}`（:289-292）＝ そのトランザクション内の全 op が 1 エントリ。

**切れる条件**は 2 つだけ: (a) `applySnap` が `origin !== "cm"` のとき `typeKind = ""`（src/main.ts:197）＝ マップコマンド・undo/redo・ファイル読み込みで切れる。(b) `compose.end`（:252）。`typeTag` と `typePos` は決してリセットされないが、合体条件が必ず `typeKind` の一致を要求するので実害はない。

**切れそこなう条件**（＝ 上限がない）: 時間窓・打鍵数・語境界・行境界のいずれにも上限がない。キャレットが連続している限り、5000 文字の連続入力が 1 エントリになる。逆に Enter は `insertNewlineAndIndent` の userEvent が `"input"`（node_modules/@codemirror/commands/dist/index.js:1546）、Tab は `indentMore` の `"input.indent"`（:1606）、Delete 前方は `"delete.forward"`（:1171）、選択削除は `"delete.selection"`（:1161）で、すべて src/editor.ts:118-126 の固定優先リストで `"input"` / `"delete"` に潰れ、分岐 5 に落ちて **1 打鍵 = 1 エントリ**になる。つまり粒度は「連続タイプ＝無限に合体／Enter・Tab・Delete＝毎回独立」という非対称で、ユーザから予測できない。

**IME**: src/editor.ts:105-112 の `compositionend` は `EditorView.domEventHandlers` 経由＝ CodeMirror の `handlers` 側で、`runHandlers` は observers → handlers の順に呼ぶ（node_modules/@codemirror/view/dist/index.js:4562-4571）。先に走る `observers.compositionend` は `compositionPendingChange = pendingRecords().length > 0` を立て、真なら `Promise.resolve().then(() => flush())` を予約する（同 :5266-5281）。そのマイクロタスクで流れるトランザクションは `compositionPendingChange && compositionEndedAt > Date.now()-50` により userEvent が `"input.type.compose"` になる（同 :4416-4424）。**つまり compose.end のリセットの後に compose の最終片が来る**。詳細は項目 1。

## 2. sNN と tNN の混在

`sessionN` は単調増加で一度もリセットされない（src/main.ts:34、`init_doc` も触らない: core/api.mbt:99-111）。`apply_sets` の合体判定は **スタック最上位のエントリのタグとの完全一致のみ**（core/doc.mbt:221-235）。この 2 点により、`s` タグと `t` タグが偶然合体することはない。唯一の意図的な混在は `runCmd(fn, {edit:{tag}})`（src/main.ts:231-242）で、同一の `s{n}` を構造コマンドと `map.beginEdit` の両方に渡すため「ノード作成 + ラベル入力全部」が 1 undo になる。逆に既存ノードの編集は `editRequested` が新タグを発番する（:458-463）ので別エントリ。ここは設計どおり動いている。

代償は粒度ではなく**量**にある。ラベル編集は 1 打鍵ごとに `host.rename` → `cmd_rename` が **見出し行全体を置換**（core/cmds.mbt:237-245、`removed` = 旧行全体）し、`apply_sets` の合体は `top.steps.push(sets[i])` で**セットを積むだけ・結合しない**（core/doc.mbt:224-227）。項目 2・3 参照。

## 3. コア側トランザクション（st.tx）

`begin_tx`/`commit_tx` を使うのは **`cmd_outdent`（core/cmds.mbt:394, :427）と `cmd_move`（:528, :568）の 2 つだけ**、どちらもタグ `""`。tx が開いている間 `apply_sets` は tag 引数を完全に無視し、`st.redo.clear()` も行わない（core/doc.mbt:212-218）。`commit_tx` は `tx.steps.length() > 0` のときだけ redo をクリアして push する（:401-405）ので、全 drop が拒否された move は redo を残す（core_test.mbt:352 が固定）。

**undo の 1 単位**は結局こうなる:
- `replace_text` × 同タグ連続 → 1 エントリ（打鍵数だけセットが積まれる）
- `add_child`/`add_sibling`/`add_parent`/`add_root` + 直後のラベル入力 → 1 エントリ
- `rename` 単独セッション → 1 エントリ
- `delete_nodes` / `indent_nodes` / `reorder` / `toggle_hidden` → 各 1 エントリ（`apply_sets` を 1 回しか呼ばないという実装上の偶然に依存、項目 9）
- `outdent_nodes` / `move_nodes` → tx で明示的に 1 エントリ
- `abort_session` → **アプリから到達不能**（項目 8）

## 4. 永続化

`schedulePersist()` は `applySnap` の末尾から毎回呼ばれ（src/main.ts:203）、250ms のトレーリングデバウンス（:110-113）を経て `persistNow` が `localStorage["mmm.text"]` に**文書全文**を書く（:105）。`pagehide` で即書き（:115）。`beforeunload` は `preventDefault` するだけで書かない（:850-853）。`updateDirty()` は毎スナップショットで `core.getText() === savedText` の全文比較（:206-207）＝ 打鍵ごとに O(文書長)。IndexedDB へのハンドル書き込みは `persistHandle`（:514-516）と `ensureImageDir`（:716）で、どちらも await なし・catch 空。

**どのタイミングで落ちると何を失うか**:
| 落ちる場所 | 失うもの |
|---|---|
| 最後の打鍵から 250ms 以内 | その打鍵。ただしデバウンスがリセット式なので、**連続入力中は入力が止まるまで一切書かれない**（項目 4）。バースト全体を失う |
| いつでも | **undo/redo スタック全体**。永続化されず、`init_doc` が起動時にクリアする（core/api.mbt:101-102）。復元後は canUndo=false で「保存版に戻す」手段がゼロ（項目 7） |
| `saveFile` 成功直後〜次の debounce 発火前 | LS_TEXT だけが巻き戻り、LS_SAVED は新しい。起動時に「ディスクより古い本文 + 新しい savedText」で立ち上がり、Ctrl+S でディスクを壊す（項目 6） |
| localStorage が quota に達した後 | 何も。例外は空 catch で握り潰され（:106-108, :587-589）、LS_TEXT と LS_SAVED が**揃って古い値のまま整合**するので dirty ドットまで消える（項目 5） |
| `showSaveFilePicker` 成功〜`w.close()` 失敗の間 | `fileName`/`elFilename` だけが新名に進み、LS_NAME と IDB handle は旧のまま（:563-574、項目 10） |
| 起動直後の `idbGet("handle")` 解決前の Ctrl+S | ハンドルを取り逃してピッカーが開く（:1115-1121） |

未確認: `createWritable`/`w.write` の途中でプロセスが死んだときにディスク上の .md が破損するか（Chromium の swap-file + atomic rename 実装に依存、ソースからは決まらない）。実測には実ブラウザでの強制終了が要る。

### D-undo/redo の粒度-1 / CONFIRMED / `src/editor.ts:105-112, src/main.ts:251-263, node_modules/@codemirror/view/dist/index.js:4562-4571, :5266-5281, :4416-4424`

**IME の合体境界が 1 つ後ろにずれる（compose.end が最終フラッシュより先に走る）**

**根拠**: editor.ts:108-111 `compositionend: () => { onUserEdits([], "compose.end"); return false; }` — コメントは「boundary marker so two separate IME compositions never merge into one undo entry」。しかし CM6 の runHandlers は `for (let observer of handlers.observers) observer(...)` を先に回し（view:4565-4566）、`observers.compositionend` が `view.inputState.compositionPendingChange = view.observer.pendingRecords().length > 0` を立て、真なら `Promise.resolve().then(() => view.observer.flush())` を予約する（view:5272, :5280）。その後で我々の handler が typeKind="" にする。マイクロタスクで流れる変更は `if (view.composing || view.inputState.compositionPendingChange && view.inputState.compositionEndedAt > Date.now() - 50) { userEvent += ".compose" }`（view:4417-4421）で `input.type.compose` を名乗る。main.ts:259 の `if (typeKind !== "compose")` はここで真になり、**新しいタグ t{n+1} を発番して typeKind="compose" のまま残す**。次のコンポジションの最初の変更は `input.type.compose.start`（view:4422）で、editor.ts:127 の `tr.isUserEvent("input.type.compose")` が前方一致で真 → typeKind はまだ "compose" → **t{n+1} を再利用して直前コンポジションの末尾エントリに合体する**。

**負債**: コンポジション境界の検出が「compositionend イベントの発火順」という CodeMirror 内部のスケジューリング詳細に依存している。`typeKind` は compose 腕でだけ位置チェックを持たないため、いったん "compose" のまま残ると、**文書内のどこであっても**次の composition が前のエントリに吸い込まれる。境界マーカーは「全部が 1 エントリになる」ことは防いでいるが、境界を正しい場所に置いてはいない。

**このままだと顕在化するバグ**: 日本語で「今日は」「いい天気」と 2 語変換して Ctrl+Z を押すと、期待は「いい天気」が消えることだが、実際には（compositionend 時点で未処理の MutationRecord がある IME/ブラウザでは）『「今日は」の最後の 1 片 + 「いい天気」全部』が 1 エントリなので、変換の途中状態が混ざった位置まで戻る。もう 1 回押すと「今日は」の頭だけが残る。逆に pendingRecords が空の環境では正しく切れるので、「環境によって undo の刻みが違う」という再現しないバグ報告になる。未確認: 実ブラウザ + 実 IME での pendingRecords の有無。Chrome + Google 日本語入力で `input.type.compose` トランザクションの発火回数を数えれば決着する。

**検証の根拠**: 全リンクを実コードで確認。src/editor.ts:108-111 は EditorView.domEventHandlers 経由なので node_modules/@codemirror/view/dist/index.js:4718 の `record(type).handlers.push(handlers[type])` 側に入り、モジュールレベル observers は :4719 で observers 側に入る。runHandlers(:4562-4566) は observers を先に回すので、:5266-5281 の compositionend observer が compositionPendingChange を立て Promise.resolve().then(flush) を予約した後で我々の handler が走り main.ts:251-254 で typeKind="" にする。マイクロタスクのフラッシュは applyDOMChangeInner(:4346-4347) で composing を 0→1 にしてから applyDefaultInsert(:4417-4424) に入り、`view.composing` 真 or compositionPendingChange+50ms 窓で userEvent が input.type.compose になる（compositionFirstChange は :5271 で null 済みなので .start は付かない）。main.ts:256-263 の compose 腕は typeKind!=="compose" を見るだけで typePos の位置チェックを持たず（:269, :278 の type/del 腕だけが持つ）、新タグを発番して typeKind="compose" を残す。次のコンポジション初弾は :4422-4423 で input.type.compose.start になり、editor.ts:118-131 の前方一致で "input.type.compose" に落ちるので typeTag が再利用される。typeKind をリセットする経路は main.ts:197（origin!=="cm"）と :252, :287, :290 だけで、compositionstart ハンドラは editor.ts / main.ts / mindmap.ts のどこにも存在しない（grep 済み）ため、コンポジション間で境界が張り直されることはない。

**検証による訂正**: 「境界が 1 つ後ろにずれる」は無条件ではなく、compositionend 時点で pendingRecords が非空かつそのフラッシュが実際に docChanged トランザクションを生む環境でのみ起きる（空なら typeKind は "" のまま残り境界は正しい位置に立つ）。ソースで確定できるのは (a) 我々の compose.end handler が CM6 内蔵 observer より必ず後に走ること、(b) compose 腕にだけ位置ガードがなく一度 "compose" が残ると文書内のどこでも次のコンポジションが吸い込まれること、の 2 点。実際の undo 刻みのズレ有無は Chrome + Google 日本語入力で input.type.compose トランザクション数を数えるまで未確認。

**修正コスト**: main.ts:256-263 に位置ガード（`e.from` と直前の compose 範囲の連続性チェック）を足すか、compose.end を `queueMicrotask` で遅延させる。10-20 行、onUserEdits 内で閉じる。

### D-undo/redo の粒度-2 / CONFIRMED / `core/doc.mbt:221-235, core/doc.mbt:414-432, src/main.ts:268-276, core/api.mbt:42-63, src/editor.ts:157-165`

**タグ合体に上限がなく、undo 1 回が「打鍵数 × 文書長」の文字列コピーになる**

**根拠**: doc.mbt:224-227 の合体は `for i = 0; i < sets.length(); i = i + 1 { top.steps.push(sets[i]); top.inv.push(inv_sets[i]) }` — **セットを連結するだけで結合しない**。main.ts:268-276 の合体条件は `typeKind === "type" && e.from === typePos` のみで、時間窓も文字数上限も語境界もない。undo は doc.mbt:419-423 で `for i = sets.length()-1; i >= 0; i = i - 1 { st.text = apply_edit_set(st.text, sets[i]); st.last_sets.push(sets[i]) }`、`apply_edit_set`（doc.mbt:80-90）は毎回 StringBuilder で**文書全体を作り直す**。さらに N 個のセットが全部 `st.last_sets` に積まれ、snapshot() が全部を JSON 化し（api.mbt:42-63）、`MdEditor.applySets` が `for (const set of sets) this.view.dispatch(...)`（editor.ts:158-164）で **N 回別々に dispatch する**。

**負債**: 「1 undo = 1 論理操作」という粒度の意図と、「1 エントリ = N 個の独立した編集セット」という実装表現がずれている。エントリのコストが操作の意味ではなく打鍵回数に比例する。F-002 が測った no-op undo 134.7ms @5000 ノードは N=1 のケースであり、N は無制限に増える。

**このままだと顕在化するバグ**: 段落を 1 回もキャレットを動かさずに 800 文字打ち、Ctrl+Z を押す。コアは 800 回の全文再構築 + 1 回の rebuild_nodes を同期実行し、snapshot は 800 セット分の JSON を吐き、CodeMirror は 800 回 dispatch する。数百 KB の文書ではここで数秒 UI がフリーズし、ユーザは「Ctrl+Z でハングした」と報告する。バックスペース長押し（オートリピート 30/秒）でも同じエントリが育つ。

**検証の根拠**: core/doc.mbt:221-235 の合体は :224-227 で `top.steps.push(sets[i])` / `top.inv.push(inv_sets[i])` するだけで、隣接する Edit を結合する処理はどこにもない（doc.mbt 全 528 行を読了、結合関数は存在しない）。合体条件 src/main.ts:268-276 は `typeKind === "type" && e.from === typePos` のみで時間窓・文字数上限・語境界なし。undo 側は core/doc.mbt:419-423 が sets を逆順にループし、毎回 apply_edit_set(core/doc.mbt:80-90) が StringBuilder で全文を作り直す（rebuild_nodes は :430 で 1 回のみ、これは主張どおり）。各セットは :422 で st.last_sets に積まれ、core/api.mbt:42-63 が全セットを JSON 化し、src/editor.ts:157-165 が `for (const set of sets) this.view.dispatch(...)` で N 回 dispatch する。N を打ち切る機構は core/api.mbt:119-135（replace_text は removed==insert の無変更判定のみ）にも main.ts にもない。

**検証による訂正**: 「時間窓も文字数上限も語境界もない」は正しいが、鎖が切れる条件は 2 つ実在する: キャレット位置が typePos から外れる（main.ts:269）と、cm 以外の origin の applySnap（main.ts:197）。したがって「1 回もキャレットを動かさずに 800 文字」は正確な前提であり、シナリオは成立する。

**修正コスト**: apply_sets の合体時に隣接する Edit を結合するコアレスを入れる（doc.mbt:221-235 に 20-30 行）。または合体鎖に上限（文字数 or 時間）を設ける（main.ts:268-285 に 5-10 行）。前者が根治。

### D-undo/redo の粒度-3 / CONFIRMED / `src/mindmap.ts:1274-1279, core/cmds.mbt:237-245, src/main.ts:336-338, src/main.ts:198`

**ラベル編集が打鍵ごとに見出し行「全体」を置換し、1 セッションで O(L²) の undo データを作る**

**根拠**: mindmap.ts:1274-1279 は `this.editor.addEventListener("input", () => { if (this.editingId !== -1) { this.host.rename(this.editingId, this.editor.value, this.editingTag); ... } })` — 遅延コミットなしで打鍵ごとに rename。cmds.mbt:237-243 は `let line = hashes(nd.depth) + " " + sanitize_label(label)` / `let old = sub(st.text, nd.hs, nd.he)` / `apply_sets([[Edit::{ from: nd.hs, to: nd.he, insert: line, removed: old }]], tag)` — **毎回 insert と removed の両方に見出し行全体**が入る。長さ L のラベルを 1 文字ずつ打つと Σ2(k+prefix) ≈ L² 文字が 1 エントリに溜まる。加えて host.rename → applySnap(…, "map") が毎打鍵 `map.render()`（main.ts:198、F-002 により全 SVG 破棄再構築）と `updateDirty()` の全文比較を走らせる。IME 入力中も input イベントは発火するので、変換途中の読み（「にほn」等）が毎回 Markdown 見出し行に書き込まれる。

**負債**: 「ラベル編集 = テキスト編集の連続」という設計判断（mindmap.ts:3 のコメントが input 要素を選んだ理由を書いている）が、コア側に「行全体を置換する rename しかない」という API 形状と噛み合っていない。文字単位の差分を作る手段がないので、1 打鍵の意味的コストが行長に比例する。

**このままだと顕在化するバグ**: 120 文字の見出しを持つノードのラベルを末尾から編集して 40 文字打つと、1 undo エントリに約 40×2×140 ≈ 11,000 文字の Edit データが積まれ、その undo で 40 回の全文再構築 + 40 回の CodeMirror dispatch が走る（項目 2 と複合）。さらに毎打鍵の full render により、大きなマップではラベル入力自体が体感で詰まる（F-002 の 25.8ms @2001 ノードが 1 打鍵あたり乗る）。IME 変換中に別プロセスが localStorage を読むと、未確定の読み（「にほn」）が保存済み本文として観測される。

**検証の根拠**: src/mindmap.ts:1274-1279 は input イベントで無条件に `this.host.rename(this.editingId, this.editor.value, this.editingTag)` を呼ぶ（遅延コミットなし、isComposing チェックなし。keydown 側の :1281 にはあるが input 側にはない）。core/cmds.mbt:237-245 は `hashes(nd.depth) + " " + sanitize_label(label)` を作り `old = sub(st.text, nd.hs, nd.he)` を removed に入れて [hs,he) を丸ごと置換する 1 本の Edit を発行、つまり insert/removed 双方に見出し行全体が入る。タグは beginEdit(src/mindmap.ts:899-903) で受けた同一の s{n} なので doc.mbt:221-227 で全打鍵が 1 エントリに合体する。src/main.ts:336-338 の rename は applySnap(..., "map") を通り、origin が "map" なので :183 で editor.applySets も走り（打鍵ごとに CM へ 1 dispatch）、:198 の map.render() と :206-207 の updateDirty() 全文比較が無条件に実行される（render に編集中の早期 return はない、src/mindmap.ts:290-）。40 打鍵 × 2 × 約 140 文字 ≈ 11,000 文字という試算も式どおり。

**検証による訂正**: core/cmds.mbt:239-241 に「正規化後が同一なら何もしない」ガードがあるので、値が変わらない input（IME の未確定状態が同じ読みを再送する等）は Edit を積まない。それ以外は主張どおり。なお localStorage への未確定読みの流出は項目 4 のデバウンス（250ms）を超える停止が変換途中に入った場合に限られる。

**修正コスト**: cmd_rename を「行末側の共通接頭辞/接尾辞を除いた最小差分」に変える（cmds.mbt:231-247 に 15-25 行）。加えて rename 経路だけ render を選択的更新にするなら mindmap 側に部分更新 API が要る（別課題、100 行規模）。

### D-undo/redo の粒度-4 / CONFIRMED / `src/main.ts:110-113, src/main.ts:98-109, src/main.ts:203`

**schedulePersist が maxWait なしのリセット式デバウンスで、連続入力中は一度も保存されない**

**根拠**: main.ts:110-113 `function schedulePersist(): void { if (persistTimer !== -1) window.clearTimeout(persistTimer); persistTimer = window.setTimeout(persistNow, 250); }` — 呼ばれるたびにタイマーを**破棄して張り直す**。呼び出しは applySnap の末尾（:203）で 1 編集ごと。コメント（:114）は「don't lose the last debounce window on reload/close」と書き、pagehide だけを想定している（:115）。最大待ち時間の上限はどこにもない。

**負債**: 「250ms デバウンス」という記述（README/MAP を含む）が最大損失窓を 250ms だと誤解させるが、実際の損失窓は『最後に 250ms 以上入力が途切れた時点から現在まで』で上限がない。デバウンスにトレーリング以外の保証（maxWait / リーディング）がない。

**このままだと顕在化するバグ**: Backspace を長押しして 500 文字消す（オートリピート約 33ms 間隔 = 250ms のギャップが一度も生まれない）。その最中にタブが OOM で落ちる／PC が電源断すると、リロード後の localStorage には**長押しを始める前の本文**が入っている。undo スタックも消えているので、消した 500 文字も、消す前に戻す手段も両方失う。IME の長い連文節変換、ペーストマクロ、外部ツールによる自動入力でも同じ。

**検証の根拠**: src/main.ts:110-113 は `if (persistTimer !== -1) window.clearTimeout(persistTimer); persistTimer = window.setTimeout(persistNow, 250);` そのままで、リーディング実行も maxWait も経過時間の記録もない。呼び出し元は applySnap 末尾の src/main.ts:203 のみで 1 編集ごと。persistNow(:99-109) は保留タイマーを消して LS_TEXT を書くだけ。上限を与える経路は main.ts 全 1135 行のどこにもなく（persistTimer の出現は :98, :100-102, :111-112 のみ）、トレーリング以外の保証は :115 の pagehide 一発だけ。33ms 間隔のオートリピートでは 250ms のギャップが生まれないので永久に発火しない、という帰結はコードから直接従う。

**検証による訂正**: 「README/MAP を含む」記述の誤解誘導という部分は半分誤り: README.md に 250ms もデバウンスも localStorage クラッシュ復旧も一切書かれていない（grep 済み）。250ms を最大損失窓のように読ませているのは audit/MAP.md:97, :147, :162 のみ。また pagehide(main.ts:115) は通常のリロード・タブクローズ・ナビゲーションを救うので、露出はタブの OOM kill / ブラウザクラッシュ / 電源断に限られる。それ以外は主張どおり。

**修正コスト**: persistNow を最後に走らせた時刻を持ち、`Date.now() - lastPersist > 2000` なら clearTimeout をスキップする maxWait を足す。main.ts:98-113 に 5-8 行。

### D-undo/redo の粒度-5 / CONFIRMED / `src/main.ts:104-108, src/main.ts:584-589, src/main.ts:1110-1120, src/main.ts:206-207`

**localStorage の quota 例外を握り潰した結果、mmm.text と mmm.savedText が「揃って古い」状態で整合し、dirty ドットまで消える**

**根拠**: main.ts:104-108 `try { localStorage.setItem(LS_TEXT, core.getText()); } catch { /* storage full/blocked */ }` — 失敗を一切表面化しない。saveFile 側も同じ（:584-589 `try { localStorage.setItem(LS_SAVED, savedText); localStorage.setItem(LS_NAME, fileName); } catch { /* ignore */ }`）。起動時は両者を独立に読む: `savedText = localStorage.getItem(LS_SAVED) ?? storedText ?? SAMPLE; loadText(storedText ?? SAMPLE, storedName ?? "無題.md")`（:1113-1114）。dirty は `core.getText() === savedText` の一致だけで判定する（:207）。ハンドルは名前一致だけで採用される（:1119 `if (h && h.name === fileName) fileHandle = h;`）。localStorage は UTF-16 で数え、LS_TEXT と LS_SAVED が同時に全文を保持するので実効上限は文書サイズの約半分。

**負債**: クラッシュ復旧ストアの健全性を検証する経路がゼロ。書き込み失敗が状態に痕跡を残さず、しかも 2 つのキーが**同じ失敗で同時に止まる**ため、古い LS_TEXT と古い LS_SAVED が一致してしまい「クリーンな状態」として観測される。真実（ディスク上の .md）とは一度も突き合わせない。

**このままだと顕在化するバグ**: 小さい文書で保存 → LS_TEXT/LS_SAVED ともに小。その後ドキュメントを quota 超えまで育てる → 以後 persistNow も saveFile の LS 書き込みも黙って失敗し、両キーは小さい旧値のまま。ディスクの .md には大きい正しい本文が書かれている。ここでリロードすると、アプリは**小さい旧文書を開き、savedText も同じなので dirty ドットは消えている**。ユーザは「保存済みの自分のファイル」だと信じて 1 文字打ち、Ctrl+S を押す（IDB ハンドルは名前一致で採用済み）。大きい本文が小さい旧本文で上書きされ、undo スタックも空なので回復不能。

**検証の根拠**: src/main.ts:104-108 と :584-589 はどちらも空 catch で失敗を状態に残さない（loadText 内の :482-487 も同様）。起動時は src/main.ts:1113-1114 で `savedText = localStorage.getItem(LS_SAVED) ?? storedText ?? SAMPLE` と `loadText(storedText ?? SAMPLE, ...)` を独立に読み、dirty は :206-207 の `core.getText() === savedText` だけで決まる。ハンドル採用は :1119 の `if (h && h.name === fileName) fileHandle = h;` の名前一致のみ。起動経路(:1110-1121)にディスク上の .md を読み直して突き合わせる処理は存在せず（idbGet は handle と dir を取るだけ）、健全性検証はゼロ。LS_TEXT と LS_SAVED が同時に全文を持つ点も :105 と :585 で確認。

**検証による訂正**: 「両キーが同じ失敗で同時に止まるので必ず揃って古くなる」は一般には成り立たない: LS_TEXT は毎編集、LS_SAVED は保存時に書かれるため、文書が徐々に育った場合は LS_TEXT が「quota に収まった最大の版」、LS_SAVED が「小さい保存版」となり両者は食い違い、リロード後 dirty ドットは点灯する。dirty が消える（=両キーが一致した古い値で固まる）のは、保存直後で両キーが等しい状態から、次の 1 回の書き込みが一気に quota を越える場合（大きな貼り付け等）に限られる。その条件下では主張どおり「小さい旧本文を保存済みと信じて Ctrl+S → ディスクの大きい本文を破壊」まで到達可能。

**修正コスト**: catch で quota を検出して flashFilename で通知 + LS_TEXT を消して不整合を防ぐ（main.ts:104-108 と 584-589 に各 5 行）。起動時にディスク側と突き合わせるなら追加 20-30 行。

### D-undo/redo の粒度-6 / CONFIRMED / `src/main.ts:551-598, src/main.ts:203, src/main.ts:110-113, src/main.ts:1111-1114`

**saveFile が persistNow を呼ばないため、保存直後のクラッシュで localStorage だけが巻き戻る**

**根拠**: saveFile はディスク書き込み後に `savedText = text; updateDirty();` と LS_SAVED/LS_NAME の書き込みを**同期・即時**で行う（:582-586）が、`persistNow()` も `schedulePersist()` も呼ばない。LS_TEXT を更新する経路は applySnap 末尾の schedulePersist だけ（:203）で、saveFile は文書を変更しないので applySnap を通らない。したがって保存時点の LS_TEXT は「最後に 250ms 入力が途切れた時点の本文」のまま。起動時は LS_TEXT を本文に、LS_SAVED を dirty 基準に、独立に採用する（:1113-1114）。

**負債**: 永続化の 2 つの単位（クラッシュ復旧バッファと保存基準値）が別々のスケジュールで動いており、両者の相対的な新しさに関する不変条件（savedText は常に text 以前の状態であるべき）がどこでも保証されていない。

**このままだと顕在化するバグ**: 文章を打っている途中（項目 4 によりデバウンスが張り直され続けている）に Ctrl+S を押し、その直後にブラウザが落ちる。リロードすると本文はバースト開始前の古い版、savedText は保存した新しい版になり、dirty ドットは点灯するが**中身が savedText より古い**という逆転が起きる。ユーザは「保存したのに未保存マークが出ている」と見て Ctrl+S を押し、ディスクの新しい版を古い版で上書きする。

**検証の根拠**: src/main.ts:551-598 を全読。ディスク書き込み後に :582-586 で `savedText = text; updateDirty();` と LS_SAVED / LS_NAME を同期で書くが、persistNow() も schedulePersist() も呼んでいない（main.ts 内の persistNow 呼び出しは :112 の setTimeout と :115 の pagehide のみ、schedulePersist の呼び出しは :203 のみ）。saveFile は core.getText() を読むだけで文書を変えないので applySnap を通らず、LS_TEXT は最後にデバウンスが発火した時点のまま。起動時は :1113-1114 で LS_TEXT を本文、LS_SAVED を dirty 基準として独立に採用するため、「本文が savedText より古い」という逆転状態が復元されうる。この逆転を検出・拒否するコードは存在しない。

**検証による訂正**: 逆転が残る窓は「250ms」ではなく、項目 4 のデバウンス張り直しにより入力が続く限り無制限（Ctrl+S 後も打ち続ければ LS_TEXT は更新されない）。ただし pagehide(:115) が通常のリロード・クローズを救うので、実際に逆転が観測されるのはクラッシュ／電源断の場合のみ。

**修正コスト**: saveFile の成功パス（main.ts:582 付近）に persistNow() を 1 行足すだけ。1-2 行。

### D-undo/redo の粒度-7 / CONFIRMED / `core/api.mbt:99-111, src/main.ts:473-488, src/main.ts:1110-1114, src/main.ts:200-201`

**undo/redo スタックが永続化されず、init_doc が起動時に必ず捨てる（「保存版に戻す」手段が存在しない）**

**根拠**: api.mbt:101-102 `st.undo.clear(); st.redo.clear()` — init_doc は無条件にスタックを破棄する。loadText は起動時（main.ts:1114）・ファイルオープン時（:526）・ドロップ時（:875）に必ず initDoc を通る（:478）。スタックを保存する経路は localStorage にも IndexedDB にも存在しない（永続化キーは color/theme/text/savedText/fileName/panes の 6 つ、:62-67）。復元後は canUndo=false なのでボタンは無効（:200-201）だが、本文は未保存のバッファなので dirty ドットは点灯する。

**負債**: 「テキストが唯一の真実、変更はすべて単一 undo スタックに載る」というアーキテクチャ主張が、セッション境界を跨いだ瞬間に半分だけ成立しなくなる。テキストは復元されるのに、そのテキストへ至る履歴は消える。savedText は手元にあるのに「保存版に戻す」コマンドが提供されていない。

**このままだと顕在化するバグ**: 編集途中でうっかりリロード（またはブラウザのクラッシュ復帰）した直後、ユーザは「さっきの変更を 3 手戻したい」と Ctrl+Z を押す。何も起きず、undo ボタンはグレーアウトしている。savedText はメモリにも localStorage にもあるので機械的には復元可能なのに、UI からは到達できない。手作業で書き戻すしかない。

**検証の根拠**: core/api.mbt:99-111 の init_doc は :101-102 で `st.undo.clear(); st.redo.clear()` を無条件に実行し、:103 で tx も捨てる。src/main.ts:473-488 の loadText は :478 で必ず core.initDoc を通り、起動(:1114)・ファイルオープン(:526, :537)・ドロップ(:875)の全経路がここを通る。永続化キーは src/main.ts:62-67 の 6 本（color/theme/text/savedText/fileName/panes）だけで、IndexedDB に入るのは "handle"(:515) と "dir" のみ。スタックを直列化する関数はコアにも TS にも存在しない（core/api.mbt の pub fn 19 本、core/js/exports.mbt の #export_name 18 本を全読、該当なし）。復元後は canUndo=false なのでボタンは :200-201 で disabled、一方 LS_TEXT と LS_SAVED が食い違えば :206-207 で dirty ドットは点灯する。savedText を本文へ書き戻す「保存版に戻す」経路も存在しない（savedText の読みは :207, :613 の比較と :585 の書き出しだけ）。

**検証による訂正**: 「アーキテクチャ主張がセッション境界で半分だけ成立しなくなる」は言い過ぎ。core/core.mbt:1-4 と mmm.md の主張はセッション内の単一 undo スタックについてで、履歴のセッション跨ぎ永続化は主張していない（多くのエディタ同様、リロードで履歴が消えるのは標準的）。本当の非対称はもっと具体的で、「未保存バッファは復元するのにその履歴だけ捨て、しかも savedText が localStorage にあるのに戻す手段を UI が提供しない」点。将来のバグの記述自体はコードから正確に導ける。

**修正コスト**: 最小対応は「保存版に戻す」コマンド（savedText を initDoc し直す）を 1 本足す: main.ts に 10-15 行。スタック自体の永続化は Entry の JSON 直列化が要るのでコア側 40-60 行。

### D-undo/redo の粒度-8 / CONFIRMED / `core/api.mbt:222-225, core/js/exports.mbt:5-110, src/coreApi.ts:39-66, src/mindmap.ts:1283-1285, core/doc.mbt:457-466`

**abort_session がアプリから到達不能で、編集セッションの「取り消し」が実装上存在しない**

**根拠**: api.mbt:222 に `pub fn abort_session(tag : String) -> String` があり doc.mbt:457-466 の do_abort（トップエントリのタグが一致すれば inv を再生して redo を残さず捨てる）を呼ぶ。しかし core/js/exports.mbt の `#export_name` は 18 個で abortSession を含まない（grep 済み、最後は :107 の selectionText）。src/coreApi.ts:39-66 の core オブジェクトにも abortSession はない。UI 側はラベル編集の Escape も Enter も同じく commitEdit を呼ぶ（mindmap.ts:1283-1285、コメント :1272-1273 が「キャンセルは存在しない」と明記）。core_test.mbt:154 だけがこの関数をテストしている。

**負債**: undo 粒度の設計にはセッション（タグ）という概念があり、その終端処理として commit と abort の 2 つが想定されていたのに、abort だけが配線されないまま残った。結果として『開始した編集を「なかったこと」にする』操作が、undo（別エントリを 1 つ消費し、直前の構造コマンドまで一緒に巻き戻す）でしか代用できない。

**このままだと顕在化するバグ**: ユーザが `+` ボタンで子ノードを作り（tag s5）、ラベルを打っている途中で「やっぱりやめる」と Escape を押す。Escape はコミットなので空ラベルの見出しが文書に残る。消すには Ctrl+Z を 1 回押すが、s5 は作成とラベル入力が合体した 1 エントリなので、意図どおりノードごと消える——ここまでは偶然うまくいく。ところが既存ノードの改名（editRequested が新タグ）を Escape で抜けた場合は、改名済みの状態がコミットされ、Ctrl+Z で戻すと**改名前の状態に加えて、その前に打っていた別の編集の合体鎖**まで巻き込まれる可能性がある。将来 rename を「行の最小差分」に変えて別エントリが挟まるようになると、Escape が何を戻すのか完全に予測不能になる。

**検証の根拠**: core/api.mbt:222-225 に `pub fn abort_session(tag : String)` が存在し core/doc.mbt:457-466 の do_abort（トップエントリのタグ一致時に inv を再生し redo を残さず捨てる）を呼ぶ。core/js/exports.mbt を全 110 行読了、#export_name は 18 本で最後が :107 の selectionText、abortSession は存在しない。src/coreApi.ts:39-66 の core オブジェクトにも undo/redo はあるが abortSession はない。したがってブラウザからこの関数へ到達する経路はゼロ。src/mindmap.ts:1280-1289 で Escape も Enter も同じ commitEdit を呼び、:1272-1273 のコメントが「キャンセルは存在しない」と明記。core/core_test.mbt でこの関数に触れるのは :154 の 1 箇所（test "typing coalesces by tag and abort reverts the session"）だけ。

**検証による訂正**: 「将来のバグ」の後半は refute。既存ノードの改名は editRequested(src/main.ts:458-463) が毎回一意の `s{++sessionN}` を発番し、doc.mbt:221 の合体条件は「トップエントリのタグが完全一致」なので、改名は必ず単独エントリになる。Escape 後の Ctrl+Z は改名だけを（全打鍵まとめて）戻し、直前の別編集の合体鎖を巻き込むことはない。加えて main.ts:197 が origin!=="cm" で typeKind を切るため CM 側の鎖も切れる。正しく言えば本項目の実体は「デッドコードとして残った未配線の API と、そこだけをテストする core_test.mbt:154」であり、ラベル編集にキャンセルが無いこと自体は mmm.md 由来の意図的な仕様（mindmap.ts:1272-1273）。

**修正コスト**: exports.mbt に #export_name("abortSession") を 1 本（6 行）、coreApi.ts に 1 行、mindmap.ts の Escape 分岐を host.abortEdit に振り替えて main.ts に host メソッドを 1 つ（10 行程度）。合計 20 行弱。

### D-undo/redo の粒度-9 / CONFIRMED / `core/cmds.mbt:394, :427, :528, :568（tx を張る 2 箇所）, core/cmds.mbt:211, :302, :371, :493, :654, :675（tx なしで apply_sets を呼ぶ箇所）, core/doc.mbt:212-241`

**undo が 1 手になる保証が tx ではなく「cmd が apply_sets を 1 回しか呼ばない」という偶然に依存している**

**根拠**: begin_tx/commit_tx を使うのは cmd_outdent（:394, :427）と cmd_move（:528, :568）だけ。cmd_delete は複数ノードでも `apply_sets([set], "")` を 1 回（:302）、cmd_indent も 1 回（:371）、cmd_add_parent も見出し挿入と全子孫への # 挿入を 1 セットにまとめて 1 回（:211）。これらが 1 undo になるのはタグ合体（tag が "" なので doc.mbt:221 の `tag != ""` を満たさず合体しない）ではなく、単に apply_sets が 1 回しか呼ばれないから。doc.mbt:236-238 は tag が "" のとき必ず新規 Entry を push する。

**負債**: 「1 コマンド = 1 undo」という不変条件を強制する仕組みがコマンド層に存在しない。tx はオプトインで、しかも 2 箇所でしか使われていない。tag "" は「合体するな」の意味なので、同じコマンドが apply_sets を 2 回呼んだ瞬間に静かに 2 エントリになる。テストは get_text() しか見ないもの（44 件中 42 件）が大半で、undo 回数を数えるのは core_test.mbt:135 の 1 件だけ。

**このままだと顕在化するバグ**: cmd_delete の EOF 掃除（cmds.mbt:283-296）を別セットに分ける、あるいは cmd_toggle_hidden のマーカ挿入を open/close で 2 回に分けるといった、見た目には無害なリファクタを入れた途端に、そのコマンドの undo が 2 回押さないと戻らなくなる。テストは最終テキストしか見ないので緑のまま通り、ユーザ報告（「削除を 1 回の Ctrl+Z で戻せない」）で初めて分かる。move_block を新しいコマンドから tx なしで呼ぶと refresh_entry_after（doc.mbt:169-177）が別のエントリの after を書き換える危険もある。

**検証の根拠**: begin_tx/commit_tx の使用は core/cmds.mbt:394+:427（cmd_outdent）と :528+:568（cmd_move）の 2 コマンドのみ。tx なしで apply_sets を呼ぶのは :211(add_parent), :225(add_root), :302(delete), :371(indent), :493(move_block), :654/:675(toggle_hidden) ほか :150, :167, :184, :242 で、いずれも 1 コマンド 1 回。core/doc.mbt:212-241 は tx が開いていれば steps に積むだけ、開いていなければ tag 一致時のみ合体し、:236-238 でそれ以外は必ず新規 Entry を push する。つまり「1 コマンド = 1 undo」を強制する検査・型・アサーションはコマンド層にもコア層にも存在せず、同じコマンドが apply_sets を 2 回呼べば静かに 2 エントリになる、という指摘は正しい。

**検証による訂正**: 3 点を訂正。(1)「これらは tag が "" なので合体しない」は cmd_add_parent には当てはまらない。cmds.mbt:211 は UI 由来の `s{n}` タグを渡しており（cmd_add_root :225 も同様）、1 エントリになるのは「一意タグ＋apply_sets 1 回」だから。(2)「偶然」は不正確。doc.mbt:179-182 の doc コメントが「open tx か同タグのトップエントリに合体する」と契約を明示しており、複数回呼ぶコマンドは実際に tx を使っている。正しい言い方は「契約はあるが強制機構がなく、違反しても静かに通る」。(3)「undo 回数を数えるテストは core_test.mbt:135 の 1 件だけ」は誤り。:135 の "multi-node command is one undo step" のほか、:351-359（no-op move はエントリを積まないことを undo 1 回で検証）と :385-394（rename と hide が別エントリであることを undo 2 回で検証）も粒度を拘束する。したがって「cmd_toggle_hidden のマーカ挿入を 2 回に分ける」リファクタは :392-393 のテストが赤くなる。緑のまま通ってしまうのは cmd_delete の EOF 掃除分割など未カバーのコマンド側。さらに「move_block を tx なしで呼ぶと refresh_entry_after(doc.mbt:169-177) が別のエントリの after を書き換える」も現状のコードからは導けない: move_block は tag "" で apply_sets を呼ぶので必ず直前に新規エントリが push されており、refresh_entry_after が触るトップは常に自分のエントリ。

**修正コスト**: 全 cmd_* を begin_tx/commit_tx で包む（cmds.mbt に各 2 行 × 13 コマンド ≈ 30 行）か、apply_sets 呼び出し回数を数える debug assert を足す。テスト側に undo 回数の assert を 13 本追加で 60 行程度。

### D-undo/redo の粒度-10 / CONFIRMED / `src/main.ts:563-574, src/main.ts:582-589, src/main.ts:473-487, src/main.ts:1115-1121, src/main.ts:514-516`

**fileName / LS_NAME / IndexedDB handle の三者が別々のタイミングで更新され、保存失敗時に乖離する**

**根拠**: saveFile は `fileHandle = await window.showSaveFilePicker(...); fileName = fileHandle.name; elFilename.textContent = fileName;` を先に行い（:564-569）、`createWritable`/`write`/`close`（:571-573）と `persistHandle()`（:574）と LS_NAME 書き込み（:586）は**その後**。したがって書き込みが例外を投げると、メモリ上の fileName と fileHandle は新ファイルを指し、LS_NAME と IDB の handle は旧ファイルのまま残る。起動時の採用条件は名前一致だけ（:1119 `if (h && h.name === fileName) fileHandle = h;`）で、これは loadText 後に非同期解決するため（:1115）、解決前の Ctrl+S は handle なしとして扱われる。persistHandle 自体も await されない fire-and-forget（:515）。

**負債**: 「どのファイルに書くか」という単一の事実が、メモリ変数・localStorage・IndexedDB の 3 箇所に別々の書き込みタイミングで散っていて、途中で失敗したときの巻き戻しがない。コメント（:511-513）は「stale handle + fresh text は間違ったファイルを上書きする」と危険を認識しているが、対策は名前一致チェックだけ。

**このままだと顕在化するバグ**: 「名前を付けて保存」で new.md を選んだが、対象がロックされている等で createWritable が失敗する。画面のファイル名は new.md に変わり「保存失敗」がフラッシュされる。ユーザは編集を続け、debounce が LS_TEXT を更新する。ここでリロードすると、LS_NAME は old.md のままなので fileName=old.md で起動し、IDB の old.md ハンドルが名前一致で採用される。次の Ctrl+S は「new.md に保存したはずの内容」を**old.md に黙って上書きする**。ユーザには保存先が変わったことを示す手がかりが何もない。

**検証の根拠**: src/main.ts:563-574 の順序を確認: :563-567 で showSaveFilePicker、:568-569 で `fileName = fileHandle.name; elFilename.textContent = fileName;`、:571-573 で createWritable/write/close、:574 で persistHandle()。LS_NAME の書き込みは :586 でさらに後。したがって write が例外を投げると catch(:590-597)へ飛び、メモリ上の fileHandle/fileName は新ファイルを指したまま、IDB の handle と LS_NAME は旧ファイルのまま残り、巻き戻し処理は存在しない。起動時の採用条件は :1119 の名前一致のみで、:1115 の idbGet は loadText(:1114) の後に非同期解決するため解決前の Ctrl+S は fileHandle=null 扱い（saveFile:563 の `if (!fileHandle)` でピッカーが開く）。persistHandle(:514-516) は `void idbSet(...).catch(() => {})` で await されない fire-and-forget。危険を認識したコメントが :511-513 にあり、対策が名前一致だけという指摘もそのとおり。

**検証による訂正**: 「ユーザには保存先が変わったことを示す手がかりが何もない」は言い過ぎ。リロード後は fileName が LS_NAME から復元されるため、ファイル名ラベル(:475)は new.md ではなく old.md を表示する（保存失敗直後は :569 で new.md、:595 の「保存失敗」フラッシュも 4 秒出る）。乖離の本体は「表示」ではなく状態側、すなわち書き込み失敗時に fileHandle/fileName がロールバックされず、単一の事実（どのファイルに書くか）がメモリ・localStorage・IndexedDB に別スケジュールで散っていて、次セッションでは名前一致という弱い照合だけで旧ファイルへ再結線される点。

**修正コスト**: showSaveFilePicker の結果を一時変数に受け、write/close 成功後に初めて fileName/fileHandle/elFilename/LS_NAME/IDB をまとめて更新する。main.ts:563-586 の並べ替えで 10-15 行。

---

## 観点: 抽象の漏れと拡張の詰まり

漏れは3層で起きている。

**(1) コア↔TS の JSON 境界は「半分だけ」型がある。** MAP.md:529 の「`mbt.*` の全エクスポートは any」は誤り。`./node_modules/.bin/tsc --noEmit --traceResolution` を実行して確認したところ、`src/coreApi.ts:5` の import は `core/_build/js/release/build/js/js.d.ts` に解決される（"File '…/js.d.ts' exists - use it as a name resolution result."）。`moonbit.d.ts` は `type String = string` / `Int = number` / `Bool = boolean` なので、**引数側は実際に検査される**。検査されないのは (a) `Array[Int]` 引数 5 本（`deleteNodes`/`indentNodes`/`outdentNodes`/`moveNodes`/`selectionText` がすべて `ids: any`）、(b) **返り値の全部** — 戻り型は一律 `string` で、`const snap = (s: string): Snapshot => JSON.parse(s);`（src/coreApi.ts:37）が無検査キャストする。つまり Snapshot 6 キー / NodeInfo 10 キーというワイヤ契約は `core/api.mbt:70-91` の手組み文字列連結にしか存在せず、突き合わせるものが型にもテストにもない（MAP 6.2: editSets/rev/focus の assert 0 件）。検査される半分があることが、むしろ「境界は守られている」という誤読を生む。

もう一つの型の虚構: `moveNodes(…, pos: 0 | 1 | 2)`（src/coreApi.ts:58）と `reorderNode(id, dir: -1 | 1)`（:60）はコア側に対応物がない。`cmd_move` は `if anchor_pos == 0 … else if anchor_pos == 1 … else`（core/cmds.mbt:544-549）で pos=3 も pos=-7 も「後ろ」に落とし、`cmd_reorder` は `if dir < 0 … else`（:581）なので dir=0 は「次の兄弟」。**F-006 を止めているのは `src/mindmap.ts:1641-1645` の `if (b.n.depth === 1) { target = { id, pos: 0 }; break; }` という SVG ヒットテスト内の if 1 本だけ**で、モデルには不変条件がない。貼り付けの安全性も同様に TS 側のゲート `if (!hasHeadings(normalized)) return;`（src/main.ts:402）に依存している。

**(2) markdown 解析は 4 実装。** 見出し+フェンス規則は 3 箇所に独立に書かれている: `core/parser.mbt:100-135`+`:179-232`、`src/relevel.ts:5-33`（:2 で "mirroring the core's scan rule" と自白）、`src/mindmap.ts:334` の `^(\`{3,}|~{3,})\s*(\S*)\s*$`。インライン構文（リンク/画像/`<svg>`）は `src/mindmap.ts:119,144,356` にのみ。`@codemirror/lang-markdown`（src/editor.ts:101）はハイライト専用で構造に一切関与しない。加えて「ブロック挿入時の空行パディング」規則が 3 実装（core/cmds.mbt:78-85、src/main.ts:418-419、src/main.ts:732-733 — 後者 2 つは逐語同一）。
`mindmap.ts` が `docText()` を必要とする根本原因は、**コアが content の範囲を計算しているのに snapshot に出さないこと**にある。`Heading.content_start`（core/parser.mbt:124）と `content_end`（core/doc.mbt:290-294）はコア内に存在し `has_content` の算出に使われるが、`snapshot()`（core/api.mbt:70-91）は捨てる。結果、TS 側が `i + 1 < nodes.length && nodes[i + 1].hs < n.subEnd ? nodes[i + 1].hs : n.subEnd` を **src/main.ts:727 と src/mindmap.ts:325 に逐語で 2 度**書き直し、開始側はさらに別実装 `doc.indexOf("\n", n.he)`（src/mindmap.ts:322）になっている。

**(3) render() 全再構築（F-002）の本当のコストは速度ではなく到達不能性。** `render()` は src/mindmap.ts:290-729 の 440 行 1 メソッドで、children/contentRows/rowsOf/rowH/heightOf/widthOf/effU/effV/subV/stackV/calcV/placeF/centerOf/placeSide の 14 個のクロージャがすべてローカル。**レイアウトを計算する手段が render() を丸ごと走らせる以外に存在しない**。しかも `placeF` は render ローカルの `boxes` に書きつつ `this.sideOf`/`this.frameOf` にも副作用を書く（:483-484）。これがドラッグ中のライブプレビューと部分更新を構造的に不可能にしている。仮想化を塞いでいるのは別の理由で、`exportSvg` が `this.nodeLayer.cloneNode(true)`（:802）で生きた DOM を写し、`refreshSelection`（:1809）/`startDrag`（:1608）/`updateDrop`（:1669,:1678）/`stopDragVisuals`（:1713）が `nodeLayer.children` を走査する — **5 機能が DOM をインデックスとして使っている**。アニメーションは `replaceChildren()`（:558-559）で毎 render 要素が新品になるため CSS transition が原理的に発火しない。フォーカス保持は既に妥協の産物で、ラベル入力が `nodeLayer` の外（pane 直下、:243-246）に置かれているのは IME 理由（:3 のコメント）と同時に全消しを生き延びるためであり、ノード内に別の focusable を置いた瞬間に打鍵ごとに焦点が飛ぶ（:1274-1279 → main.ts:337 → :198）。アクセシビリティは `index.html:38` の `tabindex="0"` がマップ全体で 1 つ、ノードの `<g>`（:585-595）は class/transform/data-id のみで role も aria も持たない。

**(4) 分割線。** `mindmap.ts` は「レイアウト（純関数になれる: nodes+docText+measure → boxes/order/sideOf/frameOf、:416-555）」「コンテンツミニパーサ（:119-153,:313-379）」「DOM 生成（:557-726）」「エクスポート（:775-868）」「操作（:991-1804）」の 5 区画で、前 2 つは `this` を一切必要としない。`main.ts` は画像パイプライン（:617-845、229 行、コアに一切触れず `fileHandle` と `map.render()` のみ）とシェル UI（:880-1091、212 行、`core.getText()` 以外モデル非依存）が丸ごと外せる。中核（applySnap+選択+host）は約 290 行しかない。

**(5) 新種別の追加コストは実測 9 / 15 / 19 箇所**（受動的な表示のみ / マップから作成可 / 行頭 `#` を隠しうる構文）。コア側（doc.mbt / cmds.mbt / api.mbt / exports.mbt）は 0 箇所 — コマンド層にとってコンテンツが不透明である点だけは抽象が保たれている。

**(6) 死んでいるコードは実測 6 種**: `abort_session`（core/api.mbt:222、exports.mbt に `#export_name` なし、`grep -rn abort src/ core/js/` = 0 件）、`MapHost.redo`（src/mindmap.ts:45、`grep -an redo src/mindmap.ts` は 45 行目のみ）、`Snapshot.rev`（src/coreApi.ts:27、`grep -arn "\.rev\b" src/` = 0 件）、`link-card` クラス（src/mindmap.ts:589、`grep -n link-card src/style.css` = 0 件）、`.cm-cursor`/`.cm-selectionBackground`/`.cm-activeLine` の計 6 規則（src/editor.ts:33,34,37,46,47,50 — `drawSelection`/`highlightActiveLine` は :13-19 の import にも :98-143 の拡張リストにもない）、`void commit;`（src/popup.ts:220、抑止対象の `noUnusedParameters` は tsconfig.json:2-13 に存在せず `noUnusedLocals` のみ :8）。

**未確認**: `moon test` は実行していないので core の 44 件が現在 pass するかは不明。ブラウザで実際に走らせて F-002 の数値を再測してはいない（既確立事実として受け取った）。

### D-抽象の漏れ-1 / CONFIRMED / `src/coreApi.ts:37, src/coreApi.ts:26-33, core/api.mbt:32-96, core/_build/js/release/build/js/js.d.ts`

**Snapshot の返り値だけが完全に無検査（引数側は js.d.ts で検査される）**

**根拠**: src/coreApi.ts:37 `const snap = (s: string): Snapshot => JSON.parse(s);` / 生成された js.d.ts: `export function moveNodes(ids: any, target: MoonBit.Int, pos: MoonBit.Int): MoonBit.String;`、`export function deleteNodes(ids: any): MoonBit.String;`。moonbit.d.ts: `export type String = string; export type Int = number;`。`tsc --noEmit --traceResolution` の出力: "File 'D:/1.atrium/mmm/core/_build/js/release/build/js/js.d.ts' exists - use it as a name resolution result."

**負債**: 境界の型検査が非対称。引数のスカラは実際に検査されるが、(a) Array[Int] を取る 5 本（deleteNodes/indentNodes/outdentNodes/moveNodes/selectionText）は `ids: any`、(b) 18 本すべての返り値は `string` → JSON.parse → 無検査キャスト。Snapshot 6 キー・NodeInfo 10 キーというワイヤ契約は core/api.mbt:70-91 の手組み文字列連結にしか存在せず、両端を突き合わせる型もテストもない（MAP 6.2: editSets/rev/focus/hs/he/subEnd の assert は 0 件）。検査される半分があることが「境界は守られている」という誤読を生んでいる。

**このままだと顕在化するバグ**: core/api.mbt:80 の `,\"subEnd\":` を将来 `,\"sub_end\":` に直す（あるいは snapshot にフィールドを足して並びを変える）と、tsc は無警告で通り、実行時に `n.subEnd === undefined` になる。src/mindmap.ts:325-327 の cEnd が undefined になり `doc.slice(cStart, undefined)` が文書末尾まで切り出すので、全ノードのカードが同じ末尾テキストを表示する。同時に src/main.ts:216 が `{from: n.hs, to: undefined}` を editor.highlight に渡し、CodeMirror の `highlightMark.range(from, to)`（src/editor.ts:77）が例外を投げて md ペインが死ぬ。原因は「JSON のキー名を変えた」だが症状は「マップが全部同じ内容になり md ペインが固まる」なので追跡に時間がかかる。

**検証の根拠**: 機構は実在。src/coreApi.ts:37 `const snap = (s: string): Snapshot => JSON.parse(s);` に検証なし。生成済み core/_build/js/release/build/js/js.d.ts を実物で確認: 18 本すべて戻り値 `MoonBit.String`、うち deleteNodes/indentNodes/outdentNodes/moveNodes/selectionText の 5 本が `ids: any`。moonbit.d.ts の `export type Int = number; export type String = string;` も確認。`npx tsc --noEmit --traceResolution` を実行し 'Module name ...js.js was successfully resolved to ...js.d.ts' を自分で確認したので、引数スカラが実際に検査される点も成立。ワイヤ契約が core/api.mbt:70-91 の手組み文字列連結にしか無い点、core/core_test.mbt に hs/he/subEnd の assert が無い点（grep で :79/:282/:372 のコメント 3 件のみ）も確認。ただし「将来のバグ」の症状 2 つは両方とも到達不能。

**検証による訂正**: 「将来のバグ」段落を差し替えること。api.mbt:80 の subEnd をリネームしても (1) src/mindmap.ts:329 の `if (cStart > 0 && cStart < cEnd)` が cEnd=undefined で false になるため `doc.slice(cStart, undefined)`（:330）には決して到達せず、症状は「全ノードが同じ末尾テキストを表示」ではなく「カード行が全ノードで消える」。(2) src/editor.ts:76 の `.filter((r) => r.from < r.to)` が {from:X, to:undefined} を先に落とすので :77 の `highlightMark.range(from, to)` は呼ばれず、例外も md ペイン停止も起きない。実際に危険なのは無言の経路のほう: src/main.ts:413 と :729 が `n.subEnd`(=undefined) を `core.replaceText` に渡し、core/api.mbt:126 の `from < 0 || to > n || from > to` は NaN 比較で全て false になるためガードを素通りする。また「18 本すべての返り値が JSON.parse される」は不正確で、getText と selectionText は素の string を返し parse されない（src/coreApi.ts:41, :65）ので、無検査キャストは 16 本。

**修正コスト**: src/coreApi.ts に実行時バリデータ（nodes 配列の 10 キー存在・型チェック、editSets 形状チェック）を 1 箇所 20-40 行。または core/core_test.mbt に snapshot の全キーを assert する契約テスト 1 本 +30 行。影響範囲は coreApi.ts のみで呼び出し側は無変更。

### D-抽象の漏れ-2 / CONFIRMED / `core/parser.mbt:124, core/doc.mbt:290-295, core/api.mbt:70-91, src/mindmap.ts:322-327, src/main.ts:726-729, src/mindmap.ts:15-16`

**コアが計算済みの content 範囲を snapshot に出さず、同じ規則が TS 側に 3 実装**

**根拠**: core/parser.mbt:124 `content_start: l.next,` / core/doc.mbt:290-294 `let content_end = if i + 1 < heads.length() { heads[i + 1].hs } else { n }` — どちらも core/api.mbt:70-91 の snapshot に出ない。TS 側は逐語同一の式を 2 箇所に持つ: src/main.ts:727 と src/mindmap.ts:325 がともに `i + 1 < nodes.length && nodes[i + 1].hs < n.subEnd ? nodes[i + 1].hs : n.subEnd`。開始側はさらに別実装 src/mindmap.ts:322 `const nlPos = doc.indexOf("\n", n.he);`。MapHost のコメントが漏れを自白している: src/mindmap.ts:15-16 `/** full markdown text (for reading attached content) */ docText(): string;`

**負債**: 「ノード自身の本文はどこからどこまでか」の定義が 4 実装を持ち、権威が定まっていない。今一致しているのは偶然（leaf のとき nodes[i+1].hs == subEnd になるため）。この 1 フィールドの不在が MapHost.docText() の存在理由であり、mindmap.ts にミニパーサ（:313-379）を置く理由でもある。

**このままだと顕在化するバグ**: 折り畳みや hidden の扱いで sub_end の意味を少しでも変える（例: hide 中のノードの sub_end をコメントマーカ行の外まで伸ばす）と、コアの has_content（core/doc.mbt:295）は heads[i+1].hs 基準なので変わらず、TS 側の cEnd（src/mindmap.ts:325）だけが変わる。結果 hasContent=false なのにカード行が描かれる（あるいは逆）が起き、src/mindmap.ts:318 の `if (!n.hasContent || n.hidden)` 早期 return と食い違うのでノードによって出たり出なかったりする。hs/he/subEnd を直接 assert するテストが 1 件もない（MAP 6.2）ので CI では絶対に捕まらない。

**検証の根拠**: 重複は実在。core/doc.mbt:290-294 の content_end と core/parser.mbt:123 の content_start は core/api.mbt:70-91 の snapshot に出ない（出るのは id/depth/parent/hs/he/subEnd/group/hasContent/hidden/label の 10 キーのみ、実読で確認）。src/main.ts:727-729 と src/mindmap.ts:325-327 は逐語同一の三項式。開始側は src/mindmap.ts:322 に別実装。src/mindmap.ts:15-16 の docText() コメントも実在。ただし「負債」の因果と「将来のバグ」の向きが誤り。

**検証による訂正**: 3 点訂正。(1) 引用行がずれている: `content_start: l.next,` は core/parser.mbt:123（:124 は `label: sub(text, p, label_end),`）。(2) 「この 1 フィールドの不在が MapHost.docText() の存在理由」は誤り。snapshot はテキストを 1 文字も運ばない（core/api.mbt:32-96 に text フィールドなし）ので、範囲フィールドがあってもマップは本文を読むために docText() が必要。ミニパーサ（src/mindmap.ts:331-376）の存在理由も範囲ではなく「行を CardRow に分類する」ことなので、範囲の不在とは独立。(3) 「今一致しているのは偶然」は誤りで、core/doc.mbt:309-317 の不変条件による。sub_end は定義上「深さ以下の次の見出しの hs」なので常に heads[i+1].hs <= sub_end が成り立ち、TS 側の `nodes[i+1].hs < n.subEnd` ガードは冗長（等号時は両腕とも同値）。さらに「将来のバグ」の向きが逆: src/mindmap.ts:318 の `if (!n.hasContent || n.hidden)` 早期 return は cEnd を計算する前に走るので、hasContent=false でカード行が描かれることは構造上ありえない。起こりうるのは逆（hasContent=true なのに行が出ない）だけ。

**修正コスト**: NodeInfo に contentStart/contentEnd を追加 = core/api.mbt に 2 フィールド +8 行、src/coreApi.ts:13-24 の interface +2 行、TS 側 2 箇所の再導出を削除 -8 行。src/mindmap.ts:322 の indexOf も削除できる。

**解消（2026-08-27）**: 記載どおりの形で直した。`Node`（core/doc.mbt:19-38）に `content_start` / `content_end` を追加し、`rebuild_nodes`（core/doc.mbt:191-206）が既に計算していた値をそのまま格納。`take_snapshot`（core/api.mbt:113-117）が `contentStart`/`contentEnd` として snapshot に出す。`src/coreApi.ts:26-34` の `NodeInfo` に同じ 2 フィールドを追加。TS 側の再導出はすべて削除: `src/map/cards.ts` の `contentEnd()`（旧 :216-221 の三項式）と `rowsOfNode` の `doc.text.indexOf("\n", n.headEnd)`（旧 :238-239、これが件の「別実装」）を削除し、`rowsOfNode`（:213-226）は `n.contentStart`/`n.contentEnd` を読むだけになった。`contentEndOf`（:255-257）も内部の再導出呼び出しをやめてフィールドを直接読む。`src/main.ts`/`src/mindmap.ts` 側は既に別コミットでこの式を持たなくなっていた（main.ts の `contentEnd()` は cards.ts の `contentEndOf` に委譲済み、mindmap.ts の `docText()`/ミニパーサは廃止済み）ので、触っていない。ついでに core 内にも同じ規則の再導出が 1 つ見つかった（core/format.mbt の `content_end_of`、`append_content_edit` 専用）— これも削除して `st.nodes[i].content_end` を直接読ませた（core/format.mbt:200-207）。

これで見つかった実バグ: カードなしルート（左スタート文書、例 `# r\n\n---\n---\n\n## a\n\n![](x.png)\n`）へカードを「末尾へ落とす」と、境界を知らない旧 `contentEnd()` が区切りの下（`## a` の見出し）を指し、コアは区切りの向こうを本文と認めない（`cap_at_first_bound`）ため、落としたカードが地図のどこにも描かれず消えていた。`test/cards.test.ts`（`moveCardTo 相当: カードなしルートへ落とすと区切りの手前に着地し、地図から消えない`）が旧実装で RED（`at` が区切りの位置 5 ではなく `## a` の位置 14 を指す）→ 新実装で GREEN になることを確認済み。`moon test`（158/158）・`pnpm test`（170/170）とも全数通過、`moon check` の警告 0 も変わらず。

### D-抽象の漏れ-3 / CONFIRMED / `core/parser.mbt:100-135, core/parser.mbt:179-232, src/relevel.ts:5-33, src/mindmap.ts:334, core/cmds.mbt:78-85, src/main.ts:418-419, src/main.ts:732-733`

**見出し/フェンス規則が 3 実装、空行パディング規則が 3 実装**

**根拠**: フェンス開始判定が 3 通り: コアは `fence_open`（core/parser.mbt:179-210、インデント 3 まで、バッククォート info にバッククォート不可）、TS は `/^ {0,3}(`{3,}|~{3,})(.*)$/` + `!(fence[1][0] === "`" && fence[2].includes("`"))`（src/relevel.ts:12,:22）、マップは `/^(`{3,}|~{3,})\s*(\S*)\s*$/`（src/mindmap.ts:334、先に trim 済みなので先頭空白の概念がない）。src/relevel.ts:2 が "Fence-aware, mirroring the core's scan rule." と明記。空行パディングは core/cmds.mbt:78-85 の `if at > 0 && cc(st.text, at - 1) != 10 { …br br… } else if !preceded_by_blank(at) { …br… }` に対し、src/main.ts:418-419 と src/main.ts:732-733 が逐語同一の `if (at > 0 && text[at - 1] !== "\n") prefix = "\n\n"; else if (at >= 2 && text[at - 2] !== "\n") prefix = "\n";`

**負債**: 「テキストが唯一の真実」というアーキテクチャの根幹規則（何が見出しか、フェンスの中か外か、ブロック挿入時の改行は何本か）に共有実装がない。3 実装のうち 2 つは TS 側で、片方はテストが 1 件も存在しない（MAP 6.3: src/ 配下は完全に未テスト）。

**このままだと顕在化するバグ**: YAML front-matter（`---` で囲む）や数式ブロック（`$$`）を content として許すと 3 実装が別々に反応する: core/parser.mbt:99-102 は `---` を区切り候補として拾い、直上に見出しがあればグループ分割になる（core/doc.mbt:266-276）。src/relevel.ts:27 の `/^(#+)[ \t]/` は front-matter 内の `# comment` 行を見出しとして数えるので、その断片を貼り付けると relevel の minDepth が狂い全体の深さが 1 段ずれる。src/mindmap.ts:334 はどちらも認識せずただの行として扱う。同じ 1 つの文書が「コアではグループ 2 つ、貼り付けでは深さ +1、マップではプレーンテキスト」と 3 通りに解釈される。

**検証の根拠**: 3 実装は実在し、しかも仮定の将来ではなく現状で既に食い違う。フェンス: core/parser.mbt:179-210（インデント 3 まで、バッククォート info にバッククォート不可）、src/relevel.ts:12+:22（同規則の TS 再実装、:2 に 'mirroring the core's scan rule' と明記）、src/mindmap.ts:334 は :332 で trim 済みの文字列に `/^(`{3,}|~{3,})\s*(\S*)\s*$/` を当てる。実際の乖離を 3 件確認: 先頭空白 5 個の ``` はマップだけがフェンス扱い、'```js foo'（info に空白）はコアだけがフェンス扱い（マップの (\S*) が空白を跨げない）、'```a`b' はマップだけがフェンス扱い（core/parser.mbt:201-209 と relevel.ts:22 は拒否）。空行パディングも core/cmds.mbt:78-85 と src/main.ts:418-419 / :732-733 の 3 実装を実読で確認。

**検証による訂正**: タイトルのうち「見出し規則が 3 実装」は 2 実装。見出し検出は core/parser.mbt:104-109 と src/relevel.ts:27 の 2 箇所だけで、src/mindmap.ts はコアの hs/he/subEnd オフセットを消費するだけで見出しを一切検出しない。逆に主張が弱すぎる点が 1 つ: 空行パディングの TS 2 実装はコアと逐語同一ではなく既に乖離している。core/cmds.mbt:75 は `nl()` で文書自身の改行種別を使い :82 の `preceded_by_blank`（core/cmds.mbt:51-67）は CR と行頭空白を読み飛ばすのに対し、TS 側は '\n' 決め打ちで `at >= 2 && text[at-2] !== '\n'` という 1 文字判定なので、CRLF 文書では両者が異なる本数の改行を入れる。

**修正コスト**: スキャン規則をコアの 1 関数に集約して JS へ輸出（core/api.mbt に scan API 1 本 +25 行、core/js/exports.mbt に 1 本 +5 行、src/coreApi.ts に 1 本 +3 行）、src/relevel.ts:5-33 を削除 -29 行、src/mindmap.ts:334-353 のフェンス判定を差し替え -15 行。

### D-抽象の漏れ-4 / CONFIRMED / `src/mindmap.ts:290-729, src/mindmap.ts:436, src/mindmap.ts:448, src/mindmap.ts:483-484, src/mindmap.ts:517, src/mindmap.ts:555`

**render() が 440 行 1 メソッドで、レイアウトが外から呼べない**

**根拠**: `render(): void {`（:290）から `}`（:729）まで 440 行。中でローカルに定義されるクロージャが 14 個: children(:296) contentRows(:314) rowsOf(:380) rowH(:381) heightOf(:387) widthOf(:393) effU(:419) effV(:421) subV(:424) stackV(:425) calcV(:436) placeF(:448) centerOf(:487) placeSide(:517)。placeF は render ローカルの boxes に書きつつクラスフィールドにも副作用を書く: :483 `this.sideOf.set(n.id, f.ux < -1e-6 ? -1 : 1);` :484 `this.frameOf.set(n.id, f);`。最後に :555 `this.boxes = boxes;` で丸ごと差し替え。

**負債**: 「木 → 座標」という本来純関数（入力: NodeInfo[] + docText + measure、出力: boxes/order/sideOf/frameOf）が DOM 構築と同一スコープに閉じ込められている。レイアウトを計算する API が存在せず、しかも副作用付きなので投機的なレイアウトを試すと生きているレイアウトが壊れる。

**このままだと顕在化するバグ**: ドラッグ中のライブプレビュー（「ここに落とすとこう並ぶ」）を実装しようとすると updateDrop（:1615）から仮レイアウトが必要になるが calcV/placeF に届かないので render() を呼ぶしかない。すると :555 で this.boxes が仮配置に上書きされ、ドロップをキャンセルしても復元経路がない。さらに :483-484 で this.sideOf も書き換わるので、キャンセル後の左右矢印ナビ（:1563-1575 が sideOf を読む）が逆方向に動く。ユーザから見ると「ドラッグをやめたのに矢印キーが逆になった」という再現条件不明のバグになる。

**検証の根拠**: 実測一致。src/mindmap.ts:290 `render(): void {` と :729 の閉じ括弧を sed で直接確認、440 行。座標計算 API はクラスに存在せず全て render ローカル。副作用も実在: :483 `this.sideOf.set(...)`、:484 `this.frameOf.set(...)`、:555 `this.boxes = boxes;`。ただし「将来のバグ」は成立しない。

**検証による訂正**: 2 点訂正。(1) 「クロージャが 14 個」は 11 個。列挙のうち children(:296)・contentRows(:314)・subV(:424) は Map リテラルでクロージャではない。実クロージャは rowsOf/rowH/heightOf/widthOf/effU/effV/stackV/calcV/placeF/centerOf/placeSide の 11 個。(2) 「ドロップをキャンセルしても復元経路がない／矢印キーが逆になる」は誤り。src/mindmap.ts:492-493 が毎 render で `this.sideOf = new Map(); this.frameOf = new Map();` と作り直し :555 が boxes を丸ごと差し替えるので、これらは累積状態ではなく完全再生成であり、render() を 1 回呼べば全復元される。しかも applySnap（src/main.ts:198）が無条件に render を呼ぶ（F-002）ため、以後どの操作でも自動復旧する。加えて render() は :291 で host.nodes()、:313 で host.docText() を直接読むので、host を差し替えない限り投機的レイアウトを作ること自体ができない。真の障壁は「純関数レイアウト API が無い」ことであって「壊れたら戻せない」ことではない。

**修正コスト**: レイアウトを純関数として src/layout.ts に切り出す = :416-555 の 140 行を移動 + measure/rowsOf を引数に注入 +20 行。sideOf/frameOf を戻り値に変える（呼び出し側 render で代入）= 5 行。DOM 生成（:557-726）はそのまま残せる。

### D-抽象の漏れ-5 / CONFIRMED / `src/mindmap.ts:558-559, src/mindmap.ts:795-802, src/mindmap.ts:1608-1611, src/mindmap.ts:1669-1682, src/mindmap.ts:1713-1715, src/mindmap.ts:1807-1812`

**DOM がインデックスとして使われているので仮想化すると export と選択が壊れる**

**根拠**: :558-559 `this.edgeLayer.replaceChildren(); this.nodeLayer.replaceChildren();` で毎 render 全消し。一方で DOM を読み戻す箇所が 5 つ: :802 `const nodesG = this.nodeLayer.cloneNode(true) as SVGGElement;`（exportSvg）、:1809-1811 `for (const g of this.nodeLayer.children) { const id = Number((g as SVGGElement).dataset.id); g.classList.toggle("selected", sel.has(id)); }`（refreshSelection）、:1608-1611（startDrag）、:1669 と :1678-1682（updateDrop）、:1713-1715（stopDragVisuals）。

**負債**: 5 機能が「全ノードが DOM に存在する」ことを暗黙の前提にしている。boxes（モデル）と nodeLayer（ビュー）の二重台帳があり、selected/dragging/drop-child の現在値は後者にしか存在しない（render 外で直接 classList 操作される）。

**このままだと顕在化するバグ**: 5000 ノードで 70.2ms/打鍵（F-002）を解消するため可視ノードだけ描く仮想化を入れると、exportSvg（:778）が画面外のノードを 1 つも含まない SVG を吐く。しかも viewBox は boxes（:784-789）から全ノード分の広さで計算されるので、正しい大きさのキャンバスの中に一部のノードだけが浮いた画像になる。ユーザは「ズームアウトして全体を表示してから SVG 出力」しても直前のビューポート分しか出ず、白紙が多いだけの一見それっぽい画像なので壊れていることに気づきにくい。同時に refreshSelection（:1807）がラバーバンドで掴んだ画面外ノードにクラスを付けられなくなり、選択したはずのノードが選択されていないように見える。

**検証の根拠**: 5 つの読み戻し箇所を全て実読で確認: exportSvg(:801-802 の cloneNode)、refreshSelection(:1809-1811)、startDrag(:1608-1611)、updateDrop(:1669, :1678-1682)、stopDragVisuals(:1713-1715)。毎 render の全消しも :558-559 で確認。exportSvg の二重台帳は特に明確で、viewBox は this.boxes（:784-789, :851）から全ノード分を計算する一方、中身は nodeLayer のクローン（:802）から採るので、可視ノードのみ描画する仮想化を入れると「正しい大きさのキャンバスに一部のノードだけ」という結果になるのは論理的に必然。refreshSelection が画面外ノードにクラスを付けられなくなるのも同様。

**検証による訂正**: 「selected/dragging/drop-child の現在値は後者（DOM）にしかない」は 3 つのうち 2 つが誤り。selected の権威は src/main.ts:32 の `selection` Set で、render も :560 で `this.host.selection()` を読んで :591 でクラスを付け直す。dragging も this.dragging.subtree（src/mindmap.ts:194）というモデル側フィールドがあり、render が :592 で `this.dragging?.subtree.has(n.id)` から再適用する。render 外の直接 classList 操作でしか表現されていないのは drop-child ただ 1 つで（:585-592 のクラス組み立てに drop-child は無い）、それも次の pointermove で updateDrop が再導出するため失われても実害がない。二重台帳の指摘自体は成立するが、その規模は主張の 1/3。

**修正コスト**: exportSvg をモデル（boxes）から組み直す = :778-868 のうち約 90 行の書き直し（inline() による computed style 取り込みは live DOM を要するので、非表示のオフスクリーン層に一時描画する設計に変える必要がある）。selection/drag のクラス操作を id→要素の Map 経由に変える = 5 箇所 25 行。

### D-抽象の漏れ-6 / CONFIRMED / `src/mindmap.ts:71-76, src/mindmap.ts:515-516, src/mindmap.ts:547, src/mindmap.ts:569, src/mindmap.ts:956, src/mindmap.ts:1621`

**Frame 抽象の 2 軸が恒常 0（24 行が 0 との積）**

**根拠**: Frame は 4 成分 `{ ux; uy; vx; vy }`（:71-76）。生成されるリテラルは 5 箇所で、すべて uy=0 かつ vx=0: `const R: Frame = { ux: 1, uy: 0, vx: 0, vy: 1 };`（:515）、`const L: Frame = { ux: -1, uy: 0, vx: 0, vy: 1 };`（:516）、`R_FRAME`（:547）、フォールバック 3 箇所（:569, :956, :1621）。`f.uy` または `f.vx` を含む行は 24 行（:420,422,471,472,570,571,574,575,576,577,957,960,1628,1629,1630,1631,1684,1686,1688,1690,1701,1702,1703,1704）で、すべて 0 との積または Math.abs(0)。

**負債**: 縦方向レイアウトのための一般化が書かれているが有効化する経路がない。読み手は「4 方向対応済み」と誤読し、実際には一度も通ったことがない（テストも実使用もゼロの）分岐を信じることになる。

**このままだと顕在化するバグ**: 「上下に伸びるマップ」を足そうとして `{ux:0, uy:1, vx:1, vy:0}` を 1 つ追加すると、effU/effV/exitPoint は正しく射影するので一見動くが、0 で隠れていた y 前提が 3 箇所で一斉に表に出る: placeSide の整列（:531-537）が `boxes.get(id)!.y -= mid` と y だけを補正するので横軸フレームでは中心がずれる、分離木の積み上げ（:543-554）が maxBottom / top という y 前提、updatePlus のルート左ボタン（:963-968）が `translate(${b.x - 14} ${b.y + b.h / 2})` と決め打ち。「新しい Frame を 1 個足すだけ」のつもりが 3 箇所の暗黙前提を踏み抜く。

**検証の根拠**: 実測完全一致。`grep -n 'f\.uy\|f\.vx' src/mindmap.ts` の結果は 420,422,471,472,570,571,574,575,576,577,957,960,1628,1629,1630,1631,1684,1686,1688,1690,1701,1702,1703,1704 の 24 行で、主張の列挙と 1 行も違わない。Frame 定義 :71-76、リテラルは全て uy=0 かつ vx=0。将来のバグで挙げられた 3 つの暗黙 y 前提も実読で確認: placeSide の整列 :531-537 は `boxes.get(id)!.y -= mid` と cF.y/cL.y のみ、分離木の積み上げ :543-554 は maxBottom = b.y + b.h と top、updatePlus のルート左ボタン :963-968 は `translate(${b.x - 14} ${b.y + b.h / 2})` の決め打ち。

**検証による訂正**: 2 点訂正。(1) 「生成されるリテラルは 5 箇所」は 6 箇所。grep 実測で :515, :516, :547, :569, :956, :1621（主張本文も 3+3 で 6 個を列挙しており、数え間違いは 5 という総数のほう）。(2) 「読み手は 4 方向対応済みと誤読する」という負債の中心部分は、src/mindmap.ts:416-418 のコメント 'Only two frames exist — right and left — so the projections below are always exact box sizes.' に明示的に否定されているので成立しない。また Frame は死んだ一般化ではなく、ux = ±1 によって左右のミラーを 1 実装で共有するために現に働いている抽象で、uy/vx が 0 なのは「符号ではなく行列で書いた」ことの代償にすぎない。指摘すべきは「未使用の 2 軸がある」ことではなく「上下フレームを足すと :531-537 / :543-554 / :963-968 の 3 箇所が同時に破れる」という後段のみ。

**修正コスト**: 縦を本当に足すなら :531-537 / :543-554 / :963-968 を frame 化 = 約 40 行。足さないなら Frame を `{ dir: -1 | 1 }` に潰して 24 行の 0 項を削除（レイアウト・エッジ・ドロップ線・updatePlus の 4 箇所を書き換え、正味 -30 行程度）。

### D-抽象の漏れ-7 / CONFIRMED / `src/mindmap.ts:12-46, src/main.ts:304-466, src/main.ts:312-331`

**MapHost が 28 メンバ、実装側に逐語同型の本体が 4 つ**

**根拠**: MapHost のメンバは 28 個（`sed -n '12,46p' src/mindmap.ts | grep -c '^  [a-z].*('` = 28）。6 つの無関係なプロトコルが同居: モデル読み出し 2（nodes/docText）、選択 4（selection/anchor/setSelection/clearSelection）、構造コマンド 15、コンテンツ作成 3（addLink/addCode/addDrawing）、アセット解決 1（imageUrl）、編集ライフサイクル 3（rename/commitEdit/editRequested）。実装側 src/main.ts:312-331 の 4 本は本体が同型: `if (!byId.has(id)) return; const tag = `s${++sessionN}`; runCmd(() => core.addChild(id, tag, split), { edit: { tag } });` — addSibling/addSiblingBefore/addParent がコア関数名だけ違う同じ 4 行。

**負債**: インターフェースの幅がコマンド数に比例して単調増加し、1 コマンド追加で interface + 実装 + 呼び出し元の 3 箇所が増える。プロトコルが分かれていないので「宣言したが繋いでいない」を目視で検出できない。

**このままだと顕在化するバグ**: すでに 1 件顕在化している: `redo(): void;`（src/mindmap.ts:45）は宣言され src/main.ts:465 で実装されているが、`grep -an redo src/mindmap.ts` の結果は 45 行目だけ — マップペインに redo のキーバインドが存在しない（undo は :1411 の `u` キーだけある）。次に addTable / addFormula を足しても同じことが起きる: interface に宣言し main.ts に実装したのにキーバインドとコンテキストメニューへの登録を忘れ、「実装したのに使えない機能」が増える。特にコンテキストメニュー（:1723-1771）には現状コンテンツ系の項目が 1 つもないため、キーボードを知らないユーザには addLink/addCode/addDrawing が存在しないのと同じ状態になっている。

**検証の根拠**: 実測一致。`sed -n '12,46p' src/mindmap.ts | grep -c '^  [a-z].*('` = 28 を自分で実行して確認。src/main.ts:312-331 の addChild/addSibling/addSiblingBefore/addParent は `if (!byId.has(id)) return; const tag = ...; runCmd(() => core.XXX(id, tag, split), { edit: { tag } });` の 4 行がコア関数名以外完全同一。redo の未接続も確認: `grep -an redo src/mindmap.ts` は :45 の宣言 1 行のみで、onKeydown には :1411 の `u`（undo）しかない。コンテキストメニュー :1723-1771 の items 配列も実読し、addLink/addCode/addDrawing/toggleHidden/undo/redo が 1 項目も無いことを確認（:1417-1427 の C/D/L キーが唯一の入口）。

**検証による訂正**: 2 点訂正。(1) 6 グループの内訳が破綻している。rename と commitEdit が「構造コマンド 15」と「編集ライフサイクル 3」の両方に数えられており、一方で undo/redo がどのグループにも入っていない。合計 28 が合うのはこの二重計上と欠落が相殺しているため。(2) redo は機能としては死んでいない。src/main.ts:882-910 の window capture 段リスナが Mod+Z / Mod+Y をどのペインにフォーカスがあっても処理する（:901-906）ので、マップペインからも redo できる。死んでいるのは MapHost.redo という interface メンバであって、ユーザから見た redo 機能ではない。

**修正コスト**: MapHost を 4 つ（MapModel / MapSelection / MapCommands / MapContent）に分割 = 宣言の移動のみ 30 行、main.ts 側は 1 オブジェクトを 4 つに分けるだけ。同型 4 本をファクトリに畳む = -12 行。

### D-抽象の漏れ-8 / CONFIRMED / `src/coreApi.ts:58-61, core/cmds.mbt:544-550, core/cmds.mbt:581-591, core/api.mbt:192-195, src/mindmap.ts:1641-1645, src/main.ts:402`

**コアの不変条件がビュー層の if 1 本で守られている（型は虚構）**

**根拠**: src/coreApi.ts:58 `moveNodes: (ids: number[], target: number, pos: 0 | 1 | 2)` / :60 `reorderNode: (id: number, dir: -1 | 1)` に対し、js.d.ts は `pos: MoonBit.Int`（= number）。core/cmds.mbt:544-549 は `let (at, depth) = if anchor_pos == 0 { … } else if anchor_pos == 1 { … } else { (tn.sub_end, tn.depth) }` — pos=3 も pos=-7 も「後ろ」になる。core/cmds.mbt:581 `if dir < 0 { … } else { … }` なので dir=0 は「次の兄弟と入れ替え」。core/api.mbt:192-195 の `move_nodes` に引数検証はない。F-006 を止めているのは src/mindmap.ts:1641-1645 の `if (b.n.depth === 1) { target = { id, pos: 0 }; break; }` のみ。貼り付けも src/main.ts:402 `if (!hasHeadings(normalized)) return;` という TS 側ゲート依存。

**負債**: 構造上の不変条件（「ルートは 1 つ」「pos は 3 値」「dir は 2 値」）がモデルではなく SVG のヒットテストとクリップボードのゲートに置かれている。コアの公開 API は不正入力を拒否も報告もせず、黙って別の構造編集を実行して Undo スタックに載せる。

**このままだと顕在化するバグ**: マップのヒットテスト以外から move を呼ぶ経路を 1 つ足すだけで F-006 が即座に再現する — コンテキストメニューに「ルートの前に移動」を追加する、キーボードによるノード移動を実装する、あるいは将来のスクリプト API。ガード（src/mindmap.ts:1641）を通らないので `moveNodes(ids, rootId, 1)` が通り、2 つ目の depth-1 見出しができ、rebuild_nodes の重複ルート除外（core/doc.mbt:252-262）で元のルートが構造から消える。テキスト上には残っているのにマップからは木が丸ごと消え、しかも F-005 により消えたルートのブロックは前ノードの subEnd 内に居るので、その前ノードを削除すると無選択のまま元のルートが本当に消滅する。

**検証の根拠**: 引用行は全て実読で一致。core/cmds.mbt:544-550 は `if anchor_pos == 0 / else if anchor_pos == 1 / else` なので pos が 0,1 以外は全て「後ろ」に落ちる。core/cmds.mbt:581 `if dir < 0 { prev } else { next }` なので dir=0 は次の兄弟と入れ替え。core/api.mbt:192-195 の move_nodes に検証は 1 行も無い（cmd_move の内部ガードは :541-543 の自部分木拒否と :551-560 の同位置拒否だけで、depth-1 ターゲットは素通り）。js.d.ts の `pos: MoonBit.Int` も実物で確認。ガードの唯一性も確認: `host.move` の呼び出しは src/mindmap.ts:1159 の 1 箇所のみで、そこへ至る updateDrop の 2 経路（:1640-1649 と :1655-1665）のうち後者は常に pos:0、前者は :1641-1645 の `if (b.n.depth === 1) { target = { id, pos: 0 }; break; }` で pos を潰す。

**検証による訂正**: 2 点訂正。(1) 「型は虚構」は言い過ぎ。src/coreApi.ts:58 の `pos: 0 | 1 | 2` と :60 の `dir: -1 | 1` は TS 側の全呼び出し（src/main.ts:371-373, :365-367 が唯一の経路）に対して tsc が実際に強制する。虚構なのは JS↔MoonBit 境界から先だけで、正確には「TS の型は TS の中でだけ本物、コアには一切伝わらない」。(2) src/main.ts:402 の hasHeadings ゲートは単一ルート不変条件を守っていない。src/main.ts:406-409 の `anchorId === -1` 分岐は空文書に対してクリップを逐語挿入する（relevel を通さない）ので、`# A` と `# B` を含むクリップは hasHeadings を通過した上で depth-1 見出しを 2 つ作る。このゲートが実際に止めているのは「見出しの無い断片の貼り付け」だけ。

**修正コスト**: core/cmds.mbt の cmd_move / cmd_reorder に引数検証と早期 return を足す = +10 行。pos=1|2 かつ target が depth-1 のときの拒否 = +5 行。core/core_test.mbt に 2 本 +20 行（現状 pos=2 も不正 id も未テスト、MAP 6.2）。

### D-抽象の漏れ-9 / CONFIRMED / `core/api.mbt:222-225, src/mindmap.ts:45, src/coreApi.ts:27, src/mindmap.ts:589, src/editor.ts:33-37, src/editor.ts:46-50, src/popup.ts:220`

**死んでいる・到達不能なコード 6 種（実測）**

**根拠**: (1) `pub fn abort_session(tag : String) -> String`（core/api.mbt:222）に対応する `#export_name` が core/js/exports.mbt に無い（同ファイルは :110 の selectionText で終端）。`grep -rn abort src/ core/js/` = 0 件。(2) `redo(): void;`（src/mindmap.ts:45）— `grep -an redo src/mindmap.ts` は 45 行目のみ。(3) `rev: number;`（src/coreApi.ts:27）— `grep -arn '\.rev\b' src/` = 0 件。core/api.mbt:34-35 が毎回直列化し core/doc.mbt:207 が毎回インクリメント。(4) `(b.rows.length > 0 ? " link-card" : "")`（src/mindmap.ts:589）— `grep -n link-card src/style.css` = 0 件（exit 1）。(5) `.cm-cursor` / `.cm-selectionBackground` / `.cm-activeLine` 計 6 規則（src/editor.ts:33,34,37 と :46,47,50）— これらの要素を生成する drawSelection / highlightActiveLine は src/editor.ts:13-19 の import にも :98-143 の拡張リストにも無い。(6) `void commit;`（src/popup.ts:220）— 抑止対象の noUnusedParameters は tsconfig.json:2-13 に無い（noUnusedLocals のみ :8）。

**負債**: 「宣言されているから使える」と読める記述が 6 箇所。特に rev は「リビジョンで再描画を判定できる」という誤読を誘発するが、実際は src/main.ts:198 が無条件に render する。

**このままだと顕在化するバグ**: F-002 の最初の対策として誰かが「rev が変わったときだけ render する」を実装する。しかし rev は「テキストが変わった」フラグであって「ツリーが変わった」フラグではない: core/api.mbt:126-132 の replace_text ガードは apply_sets を通らずに snapshot を返すので rev 据え置き、一方 rename は打鍵ごとに +1 する（core/doc.mbt:207）。結果、ラベル編集中は相変わらず毎打鍵で全再構築が走って効果ゼロ、その代わりに no-op 系の操作（範囲外 replaceText、空スタック undo）で render がスキップされて選択ハイライトの取りこぼしが出る。「性能は変わらず新しい表示バグだけが増えた」という最悪の結果になる。

**検証の根拠**: 6 件すべてを自分で再測して一致。(1) core/api.mbt:222 の abort_session に対する #export_name が core/js/exports.mbt に無い（同ファイルは :107-110 の selectionText で終端）、`grep -rn abort src/ core/js/` は exit 1。(2) `grep -an redo src/mindmap.ts` は :45 のみ。(3) `grep -arn '\.rev\b' src/` は exit 1、rev の出現は src/coreApi.ts:27 の宣言だけ（他は reveal/revoke の部分一致）。(4) `grep -n link-card src/style.css` は exit 1 で、src/mindmap.ts:589 が付けるクラスに対応する規則が無い。(5) `grep -rn 'drawSelection\|highlightActiveLine' src/` は exit 1。node_modules/@codemirror/view/dist/index.js:9556 が `cm-cursor cm-cursor-primary` を生成する唯一の箇所で drawSelection 内、:10017 が highlightActiveLine の cm-activeLine 定義。src/editor.ts:13-19 の import にも :98-143 の拡張配列にも両者が無いので :33,34,37 / :46,47,50 の 6 規則は要素が存在しない。(6) src/popup.ts:220 の `void commit;` に対し tsconfig.json は noUnusedLocals（:8）のみで noUnusedParameters 不在を実読で確認。

**検証による訂正**: 「将来のバグ」の後半だけ訂正。前半（core/api.mbt:126-132 の replace_text ガードが rev を据え置く一方、rename は core/doc.mbt:207 で打鍵ごとに +1 するので rev ゲートは肝心のホットパスに効かない）は正しく、実読で確認した。後半の「no-op 操作で render がスキップされて選択ハイライトの取りこぼしが出る」は成立しない。選択の再描画は render 経由ではなく syncSelectionViews → map.refreshSelection()（src/mindmap.ts:1807-1812）が担い、これは doUndo/doRedo（src/main.ts:494, :498）と applySnap の selChanged 経路（:199）から render とは独立に呼ばれるため、render をスキップしても selected クラスは付く。

**修正コスト**: 削除のみなら計 20 行（api.mbt 4 行、mindmap.ts 1 行 + 1 行、coreApi.ts 1 行、editor.ts 6 行、popup.ts 1 行）。abort_session を活かすなら core/js/exports.mbt +5 行、src/coreApi.ts +2 行、src/main.ts の IME/構造セッション中断経路 +5 行。

### D-抽象の漏れ-10 / CONFIRMED / `src/mindmap.ts:55-59, :78-92, :96-103, :331-376, :381-386, :399-412, :629-723, :803-815, src/style.css:238-246, src/mindmap.ts:40-42, :1417-1427, :1723-1771, src/main.ts:9, :426-457, src/popup.ts, core/parser.mbt:60-135, src/relevel.ts:5-33`

**新しいコンテンツ種別 1 つの追加コスト = 9 / 15 / 19 箇所（実測）**

**根拠**: 表示のみの受動的な種別（例: markdown 表）で 9 箇所 —(1) CardRow union（src/mindmap.ts:55-59）(2) レイアウト定数（:78-92）(3) フォント定数（:96-103、measure に渡す font が必要）(4) 検出分岐（:331-376、if/else の梯子で順序依存。複数行を食う種別は `li = j;` の更新も必要 — :345 と :365 に前例）(5) rowH（:381-386）(6) widthOf（:399-412）(7) DOM 生成分岐（:629-723）(8) exportSvg の PROPS 配列（:803-815）(9) src/style.css。マップから作成可能にすると +6 = 15 箇所: MapHost（src/mindmap.ts:40-42）、onKeydown の C/D/L 分岐（:1417-1427）、main.ts の host 実装（src/main.ts:426-457）、main.ts の import（:9）、src/popup.ts の新モーダル、コンテキストメニュー（src/mindmap.ts:1723-1771）。行頭に `#` が来うる構文なら +4 = 19 箇所: core/parser.mbt:60-135、src/relevel.ts:5-33、src/mindmap.ts:334、core/core_test.mbt。core/doc.mbt / cmds.mbt / api.mbt / exports.mbt / coreApi.ts は 0 箇所。

**負債**: コンテンツ種別が「型 + 検出 + 高さ + 幅 + 描画 + スタイル + エクスポート」に散っており、1 種別を 1 箇所にまとめる registry がない。検出は if/else の梯子で新しい枝の挿入位置が意味を持つ。ただしコマンド層（doc.mbt/cmds.mbt/api.mbt）にとってコンテンツが不透明である点だけは抽象が保たれており、ここは触らなくてよい。

**このままだと顕在化するバグ**: 9 箇所のうち exportSvg の PROPS（src/mindmap.ts:803-815）が最も忘れられやすい。表のセル背景を `fill-opacity` で、あるいは表の見出しを `letter-spacing` で表現すると、画面上は CSS が効くので正しく見えるが、export は PROPS にある 11 プロパティしかインライン化せず `copy.removeAttribute("class")`（:823）でクラスを剥がすため、SVG エクスポートでだけセルが真っ黒になる/文字が重なる。ユーザは「表を入れたら SVG 出力が壊れる」と報告し、原因は 9 箇所目の文字列配列にある。しかも TS のテストが 1 件も存在しない（MAP 6.3）ので、export の回帰を検出する仕組みが全く無い。

**検証の根拠**: 9 箇所すべての行範囲を実読で確認: CardRow union(:55-59)、レイアウト定数(:78-92)、フォント定数(:96-103)、検出の if/else 梯子(:331-376、複数行を食う種別の `li = j;` 前例が :345 と :365 に実在)、rowH(:381-386)、widthOf(:399-412)、DOM 生成分岐(:629-723)、exportSvg の PROPS(:803-815、要素数はちょうど 11)、src/style.css:238-246（.node rect.code-bg と .node text.code-line）。+6 の側も MapHost(:40-42)、C/D/L 分岐(:1417-1427)、src/main.ts:426-457、import(:9)、src/popup.ts、コンテキストメニュー(:1723-1771) を確認。エクスポートの罠は特に堅い: :823 の `copy.removeAttribute('class')` でクラスが剥がれるため、PROPS に無いプロパティ（fill-opacity, letter-spacing 等）は画面では効いてエクスポートでだけ落ちる。TS のテストが 0 件（package.json:6-13 のスクリプトは test:core のみ、devDependencies は typescript と vite の 2 つだけ）も確認済みで、回帰検出手段が無いのも事実。コマンド層が不透明という留保も正しい（has_content は core/doc.mbt:295 の空白判定だけで内容を見ない）。

**検証による訂正**: 9 のうち 2 つは条件付きで必須ではない。(3) フォント定数(:96-103) は新種別が新しいフォントを使う場合のみ、(8) exportSvg の PROPS(:803-815) は PROPS 外の CSS プロパティを使う場合のみ必要。したがって最小コストは 7 箇所、最悪 9 箇所とするのが正確。逆にこの条件性こそが指摘の核心を強めており、「触らなくても動いてしまう」ため忘れられるのが (8)。

**修正コスト**: 受動的な種別で約 120 行（9 箇所）、作成 UI 込みで約 230 行（15 箇所）。registry 化（kind ごとに { detect, height, width, draw, props } を 1 オブジェクトにまとめる）なら初期投資 80 行で以後 1 種別 = 1 オブジェクト + style.css。

### D-抽象の漏れ-11 / CONFIRMED / `src/main.ts:180-204, src/main.ts:198, src/main.ts:919-936, src/mindmap.ts:290-729, src/mindmap.ts:900-904`

**分割線が無いため「マップを閉じたら描かない」すら書けない**

**根拠**: map への出力呼び出しは全部で 4 箇所しかない: src/main.ts:198 `map.render();`（applySnap 内、無条件）、:211 `map.refreshSelection();`、:481 `map.fitView();`（loadText）、:678 `map.render();`（loadAsset）。ペイン表示切替 `applyPaneVis`（src/main.ts:919-936）は render も fitView も呼ばない。src/mindmap.ts:475-482 が Box に前回 render 時点の NodeInfo を丸ごと格納（`boxes.set(n.id, { n, x, y, w, h, rows })`）し、:904 `this.editor.value = b.n.label;` がそれを読む。

**負債**: main.ts は 12 の関心事（永続化 :60-115、色/テーマ :117-174+:1073-1091、同期漏斗 :176-242、CM→core アダプタ :244-300、MapHost 実装 :302-466、ファイル I/O :503-615、画像パイプライン :617-845、グローバルショートカット :880-910、ペイン表示 :912-965、スプリッタ :967-992、エクスポート :994-1071、boot :1093-1135）を 1 モジュールに持つ。うち画像パイプライン 229 行はコアに一切触れず、シェル UI 212 行は core.getText() 以外モデル非依存。中核は約 290 行しかない。

**このままだと顕在化するバグ**: ペイン切替が今正しく動くのは、applySnap が無条件に全再構築するため隠れているペインの SVG も常に最新だから。F-002 の最も自明な第一手として src/main.ts:198 の前に `if (!paneVis.map) return;` を足すと、マップを再表示したときに this.boxes / this.order が古いまま残る（applyPaneVis は render を呼ばない）。この状態で最初のクリックは nodeAt（src/mindmap.ts:1311-1320）が古い boxes でヒットテストして、既に存在しない id を返す。setSelection がそれを受けて byId.get(id) が undefined になり md ペインのハイライトが消え、さらにダブルクリックすると beginEdit（:900-904）が古い Box から `b.n.label` を読むので**編集ボックスに以前のラベルが表示され、1 文字打った瞬間に別のノードが rename される**。「マップを閉じて開くと編集が別ノードに入る」という再現条件の見えないデータ破壊になる。

**検証の根拠**: 事実関係は全て一致。`grep -n '\bmap\.[a-zA-Z]' src/main.ts` を実行し、描画系の呼び出しが :198 render / :211 refreshSelection / :481 fitView / :678 render の 4 箇所であることを確認（他は ensureVisible :239, beginEdit :240/:462, isEditing, endEdit, exportSvg）。applyPaneVis(:919-936) は render も fitView も呼ばない。Box が前回 render 時点の NodeInfo を丸ごと抱える点(:475-482 の `boxes.set(n.id, { n, ... })`)と beginEdit(:904) の `this.editor.value = b.n.label;` も実読で確認。12 の関心事の行範囲もすべて実在し、中核 176-242 + 244-300 + 302-466 = 289 行という計算も合う。

**検証による訂正**: 3 点訂正。(1) タイトルの「すら書けない」は誤り。書ける — :198 の前にガードを置き、applyPaneVis(:919-936) に再表示時の render() を 1 行足せば済む（3 行程度）。欠けているのは可能性ではなく dirty/invalidate の継ぎ目。(2) 「画像パイプライン 229 行はコアに一切触れず」は誤り。その範囲(:617-845)の中にある insertContentLine が core.getText()(:730) と core.replaceText()(:735) を呼び、byId(:723) も読む。(3) 失敗シナリオの前半が塞がれている。nodeAt が既に存在しない id を返した場合、setSelection 経由で md ペインのハイライトが空になるところまでは主張どおりだが（src/main.ts:214-215 が byId.get で落とす）、ダブルクリック経路は src/main.ts:459 の `if (!byId.has(id)) return;` が editRequested を止めるので beginEdit には到達しない。実際に起きるのは「まだ生きているが位置がずれた id」の場合で、ユーザは位置 P をダブルクリックしたのに、以前 P にあったノードのラベルが編集ボックスに出てそちらが rename される、という形になる。

**修正コスト**: applyPaneVis に再表示時の `map.render()` を足すのは 1 行だが、根治は分割: src/assets.ts（src/main.ts:617-845、229 行を移動）、src/shell.ts（:880-1091、212 行）、src/layout.ts（src/mindmap.ts:416-555、140 行）、src/mapContent.ts（:119-153 + :313-379、110 行）。結果 main.ts は約 690 行、mindmap.ts は約 1400 行。

