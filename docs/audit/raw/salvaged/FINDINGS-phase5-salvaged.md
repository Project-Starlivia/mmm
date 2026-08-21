# フェーズ5: バグ洗い出し(9領域)

**この文書の読み方 — 検証状態について正直に書く**

9 領域それぞれを独立したパスとして通した。その後、各指摘を「反証しにいく」
検証パスに掛ける計画だったが、**セッション上限により検証パスは 2 領域
(永続化 / XSS・サニタイズ)でしか完走しなかった**。
さらに **ツリー操作の領域は探索パス自体が実行されなかった**。

したがって各指摘には次のいずれかが付く:

| 表示 | 意味 |
|---|---|
| **検証済(CONFIRMED)** | 別のエージェントがコードを開き直して反証を試み、それでも残ったもの |
| **検証済(要確認)** | 反証パスが「ソースだけでは決まらない」と判定したもの |
| **未検証** | 探索パスの自己申告のみ。**裏取りされていない**。読む側で確認が必要 |

未検証の指摘を消さずに残すのは、監査指示が「重要度で足切りせず、
気づいたものは全て出す。取捨選択はこちらがやる」だったため。
ただし**未検証を確定として扱ってはならない**。

なお本文書と別に、監査本体で**実測により確定させた** 11 件が
`audit/FINDINGS.md`(F-001〜F-009, S-001〜S-002)にある。そちらは全て確定。

## 概要

| 領域 | 指摘数 | 検証済 CONFIRMED | 検証済 要確認 | 未検証 |
|---|---|---|---|---|
| IME / 日本語入力（editor.ts, main.ts, mindmap.ts, popup.ts の composition 経路） | 9 | 0 | 0 | 9 |
| キャレットとテキスト選択、ノード選択（src/editor.ts / src/main.ts / src/mindmap.ts を全文精読。裏取りのため core/api.mbt・core/doc.mbt | 16 | 0 | 0 | 16 |
| キーボード入力全般（mindmap.ts onKeydown / vim 2ストローク、main.ts window capture、editor.ts keymap、popup.ts） | 16 | 0 | 0 | 16 |
| markdown 構文の境界（core/parser.mbt の行スキャナ、doc.mbt の木構築、cmds.mbt のテキスト生成、src/relevel.ts の深さ再割り当て、src/mindmap.ts のコンテンツカード mini パーサ） | 25 | 0 | 0 | 25 |
| XSS・サニタイズ・信頼境界（HTML/SVG への文字列注入経路、data URL、リンク・画像の検証、貼り付け経路、CSP、SVG エクスポート） | 10 | 9 | 1 | 0 |
| 永続化 | 17 | 17 | 0 | 0 |
| エクスポート・インポート・貼り付け（exportMap / exportSvg / downloadBlob / saveFile / openFile / drop / paste / pasteImage / saveImageToDisk / relevel / popup） | 27 | 0 | 0 | 27 |
| 非同期処理（await をまたぐ古い状態 / 競合する保存 / loadAsset・objectURL / catch 漏れ / ポップアップ中に届くイベント） | 20 | 0 | 0 | 20 |
| **ツリー操作** | **0(探索パス自体が未実行)** | — | — | — |
| **合計** | 140 | 26 | 1 | 113 |

**ツリー操作の領域が抜けている件**: 探索エージェントがセッション上限で
落ちたため、この領域だけ独立パスが通っていない。ただし監査本体で
ツリー操作に関わる欠陥を 3 件、実測とテストで確定させている
(F-004 段上げで id 消失 / F-005 重複ルートの巻き込み / F-006 ルート兄弟への移動)。
また `audit/tests/commands.test.mjs` の C12 で「自分の子孫への移動で木が壊れない」
ことは確認済み。**残る未確認**: ドラッグ中に再描画が走ったときの
`boxes` と `dragging.subtree` の整合、`pointercancel` の取りこぼし、
hidden ノードへの移動。

---

## 領域: IME / 日本語入力（editor.ts, main.ts, mindmap.ts, popup.ts の composition 経路）

**調べたもの**

- src/editor.ts, src/main.ts, src/mindmap.ts, src/popup.ts を全行 Read（mindmap.ts は NUL バイト対策で Read ツール＋bash grep -a を併用）。参考に src/coreApi.ts, index.html, src/style.css も確認
- src/*.ts 全体を grep -an "composit|isComposing|229|keyCode|beforeinput" で洗い出し: ヒットは editor.ts:106-108 / main.ts:257-258,885 / mindmap.ts:1281,1326 のみ。popup.ts と relevel.ts と coreApi.ts はゼロ件。compositionstart / compositionupdate のリスナはアプリ側に一つも存在しない
- keydown リスナの全列挙と各々のガード有無: main.ts:882(window, capture)=885 でガード有 / mindmap.ts:994(window, Space パン)=ガード無（activeElement===pane と !isEditing() で間接的に守られている） / mindmap.ts:1280(node-editor)=1281 でガード有 / mindmap.ts:1295→onKeydown:1326(map pane)=ガード有 + isEditing() 早期 return / popup.ts:48(overlay), 86(code textarea), 118(link inputs)=いずれもガード無 / CodeMirror の keymap=CM6 内部の ignoreDuringComposition で保護
- render() が label editor の input を作り直さないことの根拠を行番号で確認: input は constructor の mindmap.ts:243-246 で一度だけ生成され pane 直下（this.svg は 237 で append、input は 246 で append される兄弟）。render() が破棄するのは this.edgeLayer / this.nodeLayer だけ（558-559 の replaceChildren）で、両者は this.viewport 配下の <g>。したがって変換中に render() が走っても input の DOM ノード同一性は保たれ、composition 自体は生き残る。render() が input に対してするのは末尾 728 の positionEditor()（938-942 で left/top/width/height/fontSize を書き換える）だけ
- 編集中に render() が走る経路の洗い出し: (a) applySnap→map.render() (main.ts:198)、これは label editor の input ハンドラ自身から毎 composition update ごとに走る、(b) loadAsset の完了 (main.ts:678) — 非同期でフォーカス変化を伴わないので編集中に確実に走りうる、(c) boot の idbGet('dir') 復帰 (main.ts:1122-1131)。いずれも input を破棄はしないが positionEditor で動かす
- node-editor の CSS（style.css:277-289）に ime-mode / user-select / transform など IME に影響する指定が無いこと、position:absolute で positionEditor の left/top が直接効くこと
- CodeMirror 6 の実装を node_modules で実地確認: ignoreDuringComposition (view/dist/index.js:4645-4659, key* イベントのみ無視、Safari 用に compositionend 後 100ms の猶予あり) / observers.compositionend (5266-5285, pendingRecords があると Promise.resolve().then(flush) でマイクロタスク遅延フラッシュ) / userEvent への ".compose" 付与条件 (4417-4426)
- core 側の挙動: cmds.mbt:231-247 cmd_rename は find_node<0 で no-op（main.ts:336 の byId ガード欠如は現状クラッシュしない）、doc.mbt:221-238 の undo マージは「直前エントリの tag が一致したときだけ」マージ、api.mbt:99-111 init_doc が st.next_id を 1 に戻す
- popup が開いている間の keydown 到達順: main.ts:882 は window の capture 登録なので popup.ts:49 の e.stopPropagation() より必ず先に走る（＝popup 内で Mod+S/Mod+O/Mod+//Mod+Z が素通りする）
- md ペイン側で composition 中に CodeMirror へ dispatch が飛ぶ経路: applySnap の origin==='cm' は editor.applySets をスキップする (main.ts:183) ので通常は飛ばない。飛ぶのは main.ts:199 の selChanged→syncSelectionViews→editor.highlight (editor.ts:168-170) のみ

### P5-1 / 未検証 / `src/mindmap.ts:1276`

**ラベル編集の input ハンドラに composition ガードが無く、変換途中の文字列が全部 md 本文に書き込まれる**

```
this.host.rename(this.editingId, this.editor.value, this.editingTag);
```

**症状**: IME 変換中も input イベントは inputType=insertCompositionText で毎回発火するが、mindmap.ts:1274-1279 の input ハンドラには isComposing の判定が一切ない。結果、未確定の読み（"n" → "に" → "にh" → "にほ" …）と候補選択の一つ一つが core.renameNode → applySnap("map") 経由で本物のドキュメント変更になる。1 打鍵ごとに (1) md 本文の書き換え、(2) editor.applySets による CodeMirror へのトランザクション dispatch (main.ts:183)、(3) map.render() の全 SVG 再構築 (main.ts:198)、(4) schedulePersist() による localStorage 保存 (main.ts:203) が走る。さらに positionEditor() (mindmap.ts:1277 と render 末尾 728) がノード幅を再計算して input の left/top/width を書き換えるため、変換中に入力欄そのものが動く（左側グループのノードは幅が伸びると x が減るので入力欄が左へずれていく）。

**再現条件**: 1) npm run dev でアプリを開く。2) マップペインでノードを 1 つ選択し i を押してラベル編集に入る。3) 日本語 IME を ON にして nihongo と打つ（Space も Enter もまだ押さない）。4) md ペインを見ると見出し行が打鍵ごとに `# n` → `# に` → `# にh` → `# にほ` → `# にほn` → `# にほんg` → `# にほんご` と書き換わる。5) Space を連打して候補を切り替えると、候補を 1 つ送るたびに md 本文が書き換わりマップ全体が再レイアウトされ、入力欄が横に伸縮して IME の候補ウィンドウの位置がずれる。6) この状態でページをリロードすると localStorage から未確定のローマ字混じりのテキストが復元される。

**確度**: 未検証(自己申告: 確定)

**影響**: (a) 変換確定前の中間状態が単一の真実であるはずの markdown に流れ込み、localStorage にも保存される。(b) F-002 の新しい帰結として、ASCII 1 文字＝1 render に対し日本語 1 文字は打鍵＋候補送りで 3〜10 render になる。2001 ノードで 66ms/render なので、候補を 10 個送るだけで 0.6 秒以上 UI が固まる。変換中に同期処理で数十 ms 止まると IME の候補ウィンドウが追従せず打鍵取りこぼしの原因になる。(c) 入力欄が変換中に移動するため候補ウィンドウが飛ぶ。

**修正方針**: input ハンドラの先頭で composition 中（compositionstart/compositionend でフラグを持つか (e as InputEvent).isComposing）を判定して host.rename をスキップし、compositionend でまとめて 1 回 rename する。positionEditor() も composition 中は呼ばない。

### P5-2 / 未検証 / `src/mindmap.ts:1044`

**変換確定前にマップの別の場所をクリックすると、未変換の読み（末尾のローマ字ごと）がラベルとして確定される**

```
if (this.isEditing()) this.host.commitEdit();
```

**症状**: pane の pointerdown は blur より先に走るため、composition がまだ生きているうちに commitEdit() → endEdit() が呼ばれ、endEdit は mindmap.ts:923 で `this.editor.style.display = "none"` にする（＝composition 中の要素をそのまま非表示にする）。ドキュメントに残るのは finding #1 の input ハンドラが最後に書き込んだ「未確定の読み」であり、ローマ字の途中状態（例: 「にほn」）がそのままラベルになる。cancel の概念が無い仕様（1272-1273 のコメント）なので巻き戻す手段もない。

**再現条件**: 1) ノードを選択して i でラベル編集に入る。2) IME で nihon まで打つ（入力欄には「にほn」と表示されている状態）。3) 変換も確定もせずにマップの別のノードをクリックする。4) ラベルが「にほn」で確定され、md 本文の見出しも `## にほn` になる。5) Undo すると編集セッション全体（editingTag 1 個ぶん）が丸ごと戻るので、途中まで打った内容は残らない。

**確度**: 未検証(自己申告: 確定)

**影響**: 日本語入力の最もありふれた中断操作（変換前に他をクリック）でゴミ文字列が確定し、しかもキャンセル手段が無い。finding #1 を直さない限り commitEdit 側だけでは直らない。

**修正方針**: commitEdit / endEdit の前に composition 中なら input を blur して IME に確定させる（もしくは finding #1 の修正で「最後に確定した値だけを書く」ようにする）。display:none にする前に this.editor.blur() を挟むだけでも中間状態の混入は減る。

### P5-3 / 未検証 / `src/popup.ts:50`

**popup.ts の keydown ハンドラ 3 箇所に IME ガードが無い（Esc で変換取り消し＝ポップアップごと破棄）**

```
if (e.key === "Escape") {
```

**症状**: popup.ts には composition / isComposing / keyCode の記述が 1 つも無い（grep でゼロ件）。overlay の keydown (48-57) は Escape で close(null)、Ctrl/Cmd+Enter で commit する。加えて code textarea の Tab ハンドラ (86-92) は composition 中でも setRangeText でテキストを書き換え、link popup の url/title の Enter ハンドラ (118-123) は Enter で即 commit する。IME 変換中の Esc は「変換の取り消し」、Enter は「変換の確定」、Tab は IME によっては候補一覧の展開で、いずれも本来アプリに届いてはいけないキー。本プロジェクトの他の 3 経路（main.ts:885 / mindmap.ts:1281 / mindmap.ts:1326）はすべて `e.isComposing || e.keyCode === 229` でガードしているので、popup だけが例外になっている。

**再現条件**: 1) ノードを選択して Shift+C でコードポップアップを開く。2) textarea に日本語をたくさん打ち込み、最後の語を変換中（候補ウィンドウが出た状態）にする。3) Esc を押して変換だけ取り消そうとする。4) 期待: 変換のみ取り消し。実際に overlay の keydown に key==="Escape" が届く環境では close(null) が走り、ポップアップが閉じて入力内容が全部消える。要確認: この環境の Chrome/Windows では変換中のキーは key="Process" / keyCode=229 で来るため届かない可能性がある。popup.ts:48 の先頭に console.log(e.key, e.keyCode, e.isComposing) を仕込んで、変換中の Esc / Enter がどの値で来るかを 1 回見れば確定する（key が "Escape"/"Enter" のまま来るなら再現、"Process" なら現環境では非再現だがガード欠如は残る）。

**確度**: 未検証(自己申告: 要確認)

**影響**: 再現する環境では、長いコードや日本語タイトルを入力した内容が Esc 一発で無警告に消える（このポップアップにキャンセル確認は無い）。link popup の Enter は変換確定のつもりが未変換タイトルで commit される。

**修正方針**: popup.ts の 3 つの keydown ハンドラ冒頭に `if (e.isComposing || e.keyCode === 229) return;` を追加する（他の経路と同じガード）。

### P5-4 / 未検証 / `src/editor.ts:109`

**compositionend の境界マーカーが CM6 の遅延フラッシュより先に走るため、composition の末尾が次の composition と同じ undo エントリに入る**

```
onUserEdits([], "compose.end");
```

**症状**: CM6 の observers.compositionend（node_modules/@codemirror/view/dist/index.js:5266-5285）は compositionend の時点で pendingRecords があると `Promise.resolve().then(() => view.observer.flush())` で最後の変更をマイクロタスクに遅延させる。そのフラッシュが作るトランザクションの userEvent は同 4417-4426 の条件で "input.type.compose" になる。つまり順序は必ず「compose.end（main.ts:251-252 で typeKind=""）→ 遅れて input.type.compose」。main.ts:259-262 は typeKind!=="compose" を見て新しいタグ t(n+1) を採番し typeKind="compose" に戻すので、(1) composition #1 の末尾変更が本体と別の undo エントリになり、(2) 次に始まる composition #2 の更新は typeKind が "compose" のままなので t(n+1) を再利用して #1 の末尾と同じエントリにマージされる。doc.mbt:221-238 のマージ条件（直前エントリの tag 一致）から、これは undo 境界が composition の途中に落ちることを意味する。editor.ts:106-107 のコメントが宣言している「2 つの composition が 1 つの undo に混ざらない」保証が、まさにその末尾変更があるときに破れる。

**再現条件**: 1) main.ts:295 の for ループ直前に console.log(userEvent, tag, JSON.stringify(edits)) を一時的に入れる。2) md ペインで「日本語」を変換確定し、続けて「入力」を変換確定する。3) ログに `compose.end` の後に `input.type.compose` が現れるかを見る。現れたら確定: その行のタグと、その次の composition の各行のタグが同じ t 番号になっているはず。4) その状態で Mod+Z を 1 回押すと、1 回目の変換の末尾＋2 回目の変換がまとめて消え、1 回目の変換の途中状態が残る。要確認なのは compositionend 時に pendingRecords が非空になるかで、これはブラウザ/IME 依存。

**確度**: 未検証(自己申告: 要確認)

**影響**: undo の粒度が composition 単位にならず、境界が変換の途中に落ちる。1 回 Undo すると中途半端なかな/ローマ字が本文に残る。

**修正方針**: compose.end で typeKind をすぐ消さず、compose.end のフラグだけ立てておいて「次に来た input.type.compose が compose.end 直後（同一マイクロタスク/50ms 以内）なら前のタグを継続、それ以降なら新タグ」にする。もしくは境界判定を compositionstart 側に移す。

### P5-5 / 未検証 / `src/mindmap.ts:1281`

**確定用の Enter が compositionend の後に isComposing=false で届くケースにガードが無く、ラベル編集が変換確定の Enter で閉じる**

```
if (e.isComposing || e.keyCode === 229) return;
```

**症状**: node-editor / map pane / global の 3 経路のガードはいずれも「その keydown 自体が composition 中かどうか」しか見ていない。CM6 は同じ問題に対して ignoreDuringComposition（node_modules/@codemirror/view/dist/index.js:4645-4659）で `browser.safari && this.compositionPendingKey && Date.now() - this.compositionEndedAt < 100` という 100ms の猶予を追加しており、ソース中のコメントが「Safari では compositionend と keydown が逆順に出ることがある」と明言している。mmm 側にはこの猶予が無いので、その環境では変換確定の Enter が素の keydown として mindmap.ts:1283 に届き、host.commitEdit() が走ってラベル編集が閉じてしまう（Enter は「確定」なのでキャンセルにはならないが、変換を確定しただけのつもりで編集モードから抜ける）。

**再現条件**: 1) mindmap.ts:1281 の直前に console.log(e.key, e.keyCode, e.isComposing, Date.now()) を入れ、compositionend にも log を足す。2) ノードのラベル編集に入り「にほんご」を Space で変換し Enter で確定する。3) compositionend のログの後に key="Enter"/isComposing=false の keydown ログが出るかを見る。出たら確定（＝その 1 回目の Enter で編集が閉じる）。Chrome/Windows では keyCode=229 で来るはずなので非再現、Safari で再現する既知パターン。

**確度**: 未検証(自己申告: 要確認)

**影響**: 変換確定の Enter が編集終了とぶつかる。ラベルを続けて打てず、毎回 i を押し直すことになる。3 経路すべて（main.ts:885 / mindmap.ts:1281 / 1326）に同じ穴がある。

**修正方針**: compositionend の時刻を記録し、`Date.now() - lastCompositionEnd < 100` の間の Enter/Escape を無視する（CM6 と同じ手当て）。node-editor に compositionstart/end リスナを追加するだけで済む。

### P5-6 / 未検証 / `src/main.ts:199`

**md ペインで変換中に見出しが壊れると、composition の最中に CodeMirror へ decoration トランザクションが dispatch される**

```
if (selChanged) syncSelectionViews(false);
```

**症状**: applySnap は origin==="cm" のとき editor.applySets をスキップする（183 行）ので通常は composition 中に CM へ dispatch しない。しかし選択中のノードの id が消えると 192-195 で selChanged が立ち、199 で syncSelectionViews → editor.highlight（editor.ts:168-170 の view.dispatch）が走る。この dispatch は CM の updateListener（editor.ts:113-142）の中から同期的に、しかも composition が生きているまさにその行に対して decoration を張り替える形で発生する。CM6 は composition ノードを保護しようとするが、composing 中の行の DOM を作り直す変更は composition を壊す典型パターン。

**再現条件**: 1) マップで末尾のノード（例: 「双方向編集」）をクリックして選択する（md ペインでハイライトされる）。2) md ペインでその見出し行の行頭、`#` の直前にカーソルを置く。3) IME を ON にして「あいうえお」を変換せずに打ち始める。4) 1 文字目が入った瞬間に `# ` が行頭でなくなって見出しが消え、そのノードの id が消え、selChanged→highlight dispatch が composition 中に走る。5) 変換が中断される／候補ウィンドウが閉じる／打った文字が欠けるかを観察する。要確認なのは 5) の見え方のみで、dispatch が起きること自体はコードから確定。

**確度**: 未検証(自己申告: 要確認)

**影響**: 日本語入力中に見出しを壊す編集（行頭への挿入、`#` の前後での入力）をすると composition が中断され、入力が欠ける可能性がある。updateListener の中から同じ view に dispatch している構造自体が IME に対して脆い。

**修正方針**: highlight の dispatch を composition 中は遅延させる（compositionend まで queueMicrotask/フラグで保留）。少なくとも view.composing が真のあいだは decoration の張り替えを止める。

### P5-7 / 未検証 / `src/main.ts:478`

**loadText() が map.endEdit() を呼ばないので、ラベル編集中にファイルを読むと編集オーバーレイが生き残り、再利用された id で無関係なノードを rename しうる**

```
const snap = core.initDoc(text);
```

**症状**: loadText (473-488) は setSelection でマップの選択は消すが map.endEdit() は呼ばない。node-editor は render() では破棄されない（constructor 243-246 で作られた pane 直下の要素）ので display:block のまま残り、editingId は古い id を指したまま。core/api.mbt:99-111 の init_doc は st.next_id を 1 に戻すので、新しいドキュメントのノードに同じ数値 id が再利用される。その結果 positionEditor (931-943) は「別のノード」の box を見つけて入力欄をそこへ移動させ、以後の input は host.rename(その id, …) として無関係なノードのラベルを書き換える。main.ts:336-338 の rename は他の host メソッドと違い byId.has(id) ガードが無い（core 側 cmds.mbt:232-235 の find_node<0 で落ちはしないが、id が再利用されているので今回は「落ちない」ではなく「別ノードに当たる」）。

**再現条件**: 1) 保存済み（未保存インジケータが消えた）状態にする。2) ノードを選択して i でラベル編集に入る（まだ何も打たない）。3) エクスプローラから別の .md をウィンドウにドラッグ＆ドロップする（main.ts:857-878、confirmDiscard は未保存でないので確認ダイアログも出ない）。4) 新しいファイルが読み込まれた後も #node-editor の枠が表示されたままかを見る。5) そのまま日本語を打ち始めると、意図していないノードの見出しが書き換わる。要確認なのは 3) の drop でその input に blur が飛ぶかどうかだけ（開くボタンや Mod+O 経由は blur→commitEdit で守られている。Mod+O は main.ts:895 で map ペイン内では素通りするので別経路）。DevTools で document.activeElement と #node-editor の style.display を drop 前後で見れば決まる。

**確度**: 未検証(自己申告: 要確認)

**影響**: ファイル読み込み後に別ノードのラベルが黙って書き換わる。IME 変換中に踏むと未確定文字列がそのまま他人のノードに入る。

**修正方針**: loadText の先頭で `if (map.isEditing()) map.endEdit();` を呼ぶ。あわせて main.ts:336 の rename にも他メソッドと同じ `if (!byId.has(id)) return;` を入れる。

### P5-8 / 未検証 / `src/main.ts:902`

**popup が開いている間も main.ts の capture keydown が効き、Ctrl+Z が textarea ではなくドキュメントを undo する**

```
if (map.isEditing()) return; // native input undo while label editing
```

**症状**: main.ts:882 の keydown は window の capture 登録なので、popup.ts:49 の e.stopPropagation() より必ず先に走る（capture は overlay に到達する前）。除外条件は map.isEditing()（ラベルエディタのみ）だけで popup を見ていないため、ポップアップの textarea/input にフォーカスがあっても key==="z" で 903-906 の e.preventDefault(); e.stopPropagation(); doUndo() が実行される。stopPropagation のせいで textarea 自身のネイティブ undo も届かない。同様に Mod+S（保存）、Mod+/（togglePane がフォーカスを popup の外へ奪う）も popup 内で発火する。IME 的には、変換の取り消しに Ctrl+Z を使う操作でこれを踏む。

**再現条件**: 1) ノードを選択して Shift+C でコードポップアップを開く。2) textarea に数行入力する（日本語変換を含めてもよい）。3) Ctrl+Z を押す。4) textarea の内容は戻らず、代わりに背後のドキュメントが undo される（マップと md ペインが変化し、undo ボタンの活性が変わる）。5) Mod+/ を押すと popup を開いたままフォーカスが md ペイン／マップペインへ飛ぶ。

**確度**: 未検証(自己申告: 確定)

**影響**: ポップアップ編集中の Ctrl+Z が背後の文書を壊し、ユーザーには「入力が戻らない上に裏で何かが変わった」ように見える。ポップアップを閉じた後の undo 回数の勘定も狂う。

**修正方針**: モーダルが開いているかを示すフラグ（popup.ts の shell が公開する）を main.ts:884 の先頭で見て早期 return する。あるいは 902 の条件を `map.isEditing() || document.querySelector(".popup-overlay")` に広げる。

### P5-9 / 未検証 / `src/mindmap.ts:996`

**mindmap.ts の window keydown（Space パン）だけ IME ガードが無い**

```
e.code === "Space" &&
```

**症状**: 4 経路のうちこの 1 つだけ `e.isComposing || e.keyCode === 229` を持たない（994-1004）。現状は `!this.isEditing()` と `document.activeElement === pane` の 2 条件で守られており、ラベル編集中は isEditing() が真、md ペイン／ポップアップ入力中は activeElement が pane ではないので composition 中に到達しない。ただし e.code は IME の影響を受けない物理キー由来で、Windows の日本語 IME では Space が変換キーであるため、将来 map pane 自体を編集可能にする／フォーカス条件を緩めると即座に「変換キーを押すとパンモードに入り preventDefault される」バグになる。ガードの有無が他の 3 経路と非対称なのは、この 4 経路を「個別に確認する」という観点では明示すべき差分。

**再現条件**: 現時点で壊れる操作手順は書けない（上記 2 条件のどちらかを外さないと到達しない）。要確認: mindmap.ts:995 の直後に console.log(e.code, e.isComposing, document.activeElement) を入れ、(a) ラベル編集中に IME の Space を押したとき、(b) endEdit 直後に pane へフォーカスが戻った状態で IME を ON のまま Space を押したときに、この分岐へ入らないことを確認すれば決着する。

**確度**: 未検証(自己申告: 要確認)

**影響**: 現状は到達しないが、他の 3 経路と防御が非対称。フォーカス条件が変わった瞬間に「変換キーが効かない」形で表面化する。

**修正方針**: 994 のハンドラ冒頭にも `if (e.isComposing || e.keyCode === 229) return;` を入れて 4 経路の防御をそろえる。

---

## 領域: キャレットとテキスト選択、ノード選択（src/editor.ts / src/main.ts / src/mindmap.ts を全文精読。裏取りのため core/api.mbt・core/doc.mbt(apply_sets, map_offset, apply_edit_set)・core/cmds.mbt(cmd_rename)・index.html・src/style.css・node_modules/@codemirror/{state,view}/dist/index.js も参照）

**調べたもの**

- editor.ts 全 188 行（highlightField の map/set、applySets、reveal、setText、updateListener の userEvent 判定）
- main.ts 全 1135 行（applySnap の選択 prune、syncSelectionViews、setSelection、runCmd、onUserEdits の delta 計算、loadText、doUndo/doRedo、insertContentLine、paste）
- mindmap.ts 全 1814 行（pointerdown/move/up、dblclick、contextmenu、onKeydown 全分岐、beginEdit/endEdit/positionEditor、startDrag/updateDrop、refreshSelection、nodeAt、order の更新箇所）
- CodeMirror 実体の確認: node_modules/@codemirror/view/dist/index.js:293 `Decoration.set(of, sort = false)`、:308 MarkDecoration の startSide=500000000 / endSide=-600000000、@codemirror/state/dist/index.js:3394 RangeSet.of と :3478 の throw 文
- core 側のオフセット契約: apply_edit_set(doc.mbt:80) は 1 セット内の from/to が「セット適用前テキスト基準」であり CodeMirror の changes 配列と一致すること、replay_entry(doc.mbt:411) が undo 時に inv を逆順で last_sets に積むこと（= md ペインと core のテキストは原理的にズレない）を確認
- core/api.mbt:119 replace_text が編集を正規化せず 1 セットだけ返すこと（origin="cm" で applySets を捨てても発散しない）を確認
- core/cmds.mbt:231 cmd_rename が hs..he（見出し行まるごと）を毎打鍵で置換することを確認
- core/doc.mbt:113 map_offset の見出し先頭挿入/削除時の id 生存条件を確認
- index.html の #map-pane に tabindex="0" があり pane.focus()/keydown が成立すること
- style.css の #node-editor(position:absolute, z-index:10) / #rubber / #ctx-menu .item.disabled{pointer-events:none} を確認（無効メニュー項目はクリック不能＝誤爆しない、を否定的に確認）
- Shift+クリックの範囲が this.order（= 文書順）スライスで昇順になることを確認（ここは問題なし）
- Mod+A・矩形選択が this.order 由来で昇順になることを確認（ここは問題なし）
- editor.applySets が selection を指定しないため CM 側キャレットは常に「マップのみ」であること、reveal() が scrollIntoView のみでキャレットを動かさないことを確認

### P5-1 / 未検証 / `D:/1.atrium/mmm/src/editor.ts:74`

**Ctrl+クリック/Shift+↑ で選択集合が文書順にならず、Decoration.set が例外を投げてハイライトが凍る**

```
deco = Decoration.set(
          e.value
            .filter((r) => r.from < r.to)
            .map((r) => highlightMark.range(r.from, r.to)),
        );
```

**症状**: Decoration.set は第2引数 sort を省略すると sort=false（@codemirror/view dist:293 → RangeSet.of dist:3394）。未ソートの range を渡すと RangeSetBuilder.addInner（@codemirror/state dist:3478）が `Ranges must be added sorted by \`from\` position and \`startSide\`` を throw する。main.ts:213 の `[...selection]` は Set の挿入順であり、mindmap.ts:1184（Ctrl+クリック追加）と mindmap.ts:1551（Shift+矢印）は「今の選択の後ろに新 id を append」するので、文書上より前のノードを足すと降順の range 配列になる。例外は syncSelectionViews の途中（map.refreshSelection() の後、editor.highlight() で）投げられるのでマップ側だけ選択が更新され md ペインのハイライトは前の状態のまま固まる。さらに applySnap 経由（main.ts:199）で起きた場合は btnUndo/btnRedo の活性更新・updateDirty()・schedulePersist()（main.ts:200-203）が丸ごとスキップされ、その編集が localStorage に保存されない。

**再現条件**: 起動直後の既定文書で。(A) マップの「## mirror」をクリック → 続けて「## markdown」を Ctrl+クリック。(B) または「### 双方向編集」をクリック → Shift+↑ を1回。いずれも DevTools コンソールに Uncaught Error: Ranges must be added sorted by `from` position and `startSide` が出て、マップは2ノード選択表示なのに md ペインのハイライトは1ノード分のまま動かない。

**確度**: 未検証(自己申告: 確定)

**影響**: 最頻出の複数選択操作（Ctrl+クリック、Shift+↑）が毎回未捕捉例外になる。md ペインの選択ミラーが停止し、applySnap 内で起きた場合は自動保存(schedulePersist)と undo/redo ボタン状態の更新も落ちる。

**修正方針**: editor.ts:74 を `Decoration.set(..., true)`（sort 有効）にする。併せて main.ts:213 で `[...selection]` を n.hs 昇順に sort してから highlight に渡し、mindmap.ts:1184/1551 も this.order でフィルタして文書順の配列を作る。

### P5-2 / 未検証 / `D:/1.atrium/mmm/src/mindmap.ts:1549`

**Shift+↓/↑ がアンカーを選択から抜き、選択が非連続になる**

```
if (set.has(nx) && sel.size > 1) set.delete(anchor);
```

**症状**: 「隣が既に選択済みなら縮める」ロジックが、アンカーが選択範囲の端ではなく中央にある場合に穴を空ける。直上のコメントは「anchor edge stays (spec 3.4)」だが実装は 1551 行で毎回 anchor を nx へ移動させており、端固定になっていない。

**再現条件**: 既定文書で「## mindmap」をクリック（anchor=mindmap, order 上 index 3）→ Mod+A で全選択（anchor は mindmap のまま、main.ts の setSelection は anchor を保持）→ Shift+↓ を1回。期待は選択維持/拡張だが、実際は「## mindmap」だけが選択解除され、その子「### 空間的に見るもう一つの窓」は選択されたまま残る（マップ上に穴が空く）。もう一度 Shift+↓ で穴が広がる。

**確度**: 未検証(自己申告: 確定)

**影響**: 見た目に連続な範囲を選んだつもりで dd / Mod+X / インデントを実行すると、意図しない親抜けの集合に対して構造編集が走る。

**修正方針**: アンカーを固定端として保持し（setSelection の第2引数を anchor のままにする）、伸縮は「アンカーから現在の移動端までの this.order スライス」を作り直す方式に変える。

### P5-3 / 未検証 / `D:/1.atrium/mmm/src/mindmap.ts:1186`

**Ctrl+クリックでアンカー自身を外すと、選択0件なのに anchorId が生き残る**

```
next.has(id) ? id : this.host.anchor(),
```

**症状**: アンカーノードを Ctrl+クリックで外すと next からは消えるが anchor は this.host.anchor()（= 外したノード自身）のまま残る。main.ts:192 の prune は「byId に無い」場合しか anchor を捨てないので、選択集合の外にいる anchor は永久に残る。マップ上は何も選択されていないのに、キーボード操作は不可視のノードを対象にし続ける。

**再現条件**: 既定文書で「## markdown」をクリック（選択1件）→ 同じノードを Ctrl+クリック。マップの選択表示も md ペインのハイライトも消える。その状態で Enter を押すと「## markdown」の下に兄弟ノードが生成される。i を押すと「## markdown」のラベル編集が開く。Mod+V も「## markdown」の子として貼り付く。

**確度**: 未検証(自己申告: 確定)

**影響**: 何も選択していない見た目のまま構造編集が走る。ユーザは対象ノードを目で確認できない。

**修正方針**: mindmap.ts:1184-1187 で next が空、または next に anchor が含まれない場合は anchor を next の末尾要素（無ければ -1）にフォールバックさせる。

### P5-4 / 未検証 / `D:/1.atrium/mmm/src/mindmap.ts:1209`

**ラベル編集中のダブルクリックが編集を張り直し、入力欄の単語選択とキャレットを破壊する**

```
const id = this.nodeAt(e.clientX, e.clientY);
```

**症状**: pane の dblclick ハンドラには pointerdown（mindmap.ts:1043 の `if (e.target === this.editor) return;`）に相当する node-editor 除外がない。#node-editor はノード上に重なる pane の子要素なので、入力欄内のダブルクリックも pane まで bubble し nodeAt が編集中ノードを返す → host.editRequested → beginEdit が再入する。beginEdit は editor.value をノードのラベルで上書きし（mindmap.ts:904）、最後に setSelectionRange(pos,pos)（mindmap.ts:916）でキャレットを末尾へ潰す。さらに editRequested は新しい tag（main.ts:461）を発行するので、そこから先の入力が別の undo エントリに切れる。

**再現条件**: マップのノード（例「## mindmap」）をダブルクリックしてラベル編集を開始 → 入力欄の中の単語をダブルクリックして選択しようとする。期待は単語選択、実際は選択が消えてキャレットが末尾へ飛ぶ。トリプルクリック（全選択）でも同じ。

**確度**: 未検証(自己申告: 確定)

**影響**: ラベル編集中にマウスで単語選択・全選択ができない（Backspace 連打でしか消せない）。加えて undo の粒度が意図せず分割される。

**修正方針**: dblclick ハンドラ先頭に `if (e.target === this.editor) return;` を追加する（pointerdown と同じガード）。

### P5-5 / 未検証 / `D:/1.atrium/mmm/src/mindmap.ts:1262`

**ラベル編集中の右クリックがノードのコンテキストメニューに乗っ取られる**

```
e.preventDefault();
```

**症状**: pane の contextmenu ハンドラも node-editor を除外していない。入力欄上で右クリックすると preventDefault でブラウザ標準の「切り取り/コピー/貼り付け/元に戻す」メニューが抑止され、代わりに nodeAt が返したノードに対する #ctx-menu（子を追加/削除 など）が入力欄の上に開く。pointerdown 側は e.target===this.editor で早期 return するため commitEdit も走らず、編集中のまま構造編集メニューが出る。

**再現条件**: ノードをダブルクリックしてラベル編集を開始 → 入力欄の中で右クリック。ブラウザのテキスト編集メニューではなく「子を追加 / 下に追加 / 削除 …」のマップメニューが出る。

**確度**: 未検証(自己申告: 確定)

**影響**: ラベル編集中にテキストのコピー&ペーストをコンテキストメニューから行えない。誤って「削除」を選ぶと編集中ノードが消える（blur→commitEdit が先に走るのでテキストは確定されるが、直後に削除される）。

**修正方針**: contextmenu ハンドラ先頭に `if (e.target === this.editor) return;` を追加し、入力欄内では標準メニューを許可する。

### P5-6 / 未検証 / `D:/1.atrium/mmm/src/mindmap.ts:933`

**ファイル読み込み後もラベル編集オーバーレイが残り、id 再採番により無関係なノードに再バインドされる**

```
const b = this.boxes.get(this.editingId);
```

**症状**: loadText（main.ts:473-488）は map.endEdit() を呼ばない。editingId は前の文書の id のまま残り、positionEditor は箱が無ければ黙って return するので入力欄は古い座標に表示されっぱなしになる。さらに core/api.mbt:99 の init_doc が `st.next_id = 1` にリセットするため新文書のノード id は 1..n に再採番され、古い editingId（例 3）が新文書の3番目のノードと衝突する。その場合 positionEditor はそのノードの箱を見つけて入力欄をそこへ移動し、以後の入力は host.rename(3, ...) として全く別の見出しを書き換える。

**再現条件**: 1) Mod+S で保存して dirty を落とす（confirmDiscard を出さないため）。2) マップのノードをダブルクリックしてラベル編集を開き、何も入力しない。3) エクスプローラから別の .md をウィンドウにドラッグ&ドロップする（window の drop ハンドラ main.ts:857 が走る）。4) 新しいマップが描画された後も入力欄が残っているのを確認し、1文字入力する → 新文書側の同 id ノードの見出しが書き換わる。

**確度**: 未検証(自己申告: 要確認)

**影響**: 文書切り替え直後に、ユーザが意図していないノードの見出しが直接書き換わる。最低でも死んだオーバーレイが浮いたまま残る。

**修正方針**: loadText の先頭で `map.endEdit()`（と editingId のリセット）を呼ぶ。加えて positionEditor で箱が見つからない場合は早期 return ではなく endEdit して入力欄を閉じる。要確認点はステップ3で「ファイル drop が input の focus/blur を発火させないか」だけ（Chrome では発火しない見込み）。drop 後に入力欄が残って見えれば確定。

### P5-7 / 未検証 / `D:/1.atrium/mmm/src/main.ts:199`

**ノード範囲の末尾に足したテキストが md ペインのハイライトから外れ、再計算もされない**

```
if (selChanged) syncSelectionViews(false);
```

**症状**: ハイライトは Decoration.mark（非 inclusive）なので startSide=500000000 / endSide=-600000000（@codemirror/view dist:308）。境界ちょうどの挿入は from 側では range の外へ押し出され、to 側では range に取り込まれない。一方 applySnap は「選択の集合が変わったときだけ」syncSelectionViews を呼ぶので、選択メンバーが同じまま subEnd だけ伸びるケースではハイライトが再計算されず、CM のマッピング結果（＝取りこぼした範囲）がそのまま残る。insertContentLine（main.ts:722-736）と paste（main.ts:404-422）は葉ノードでは `at = n.subEnd`、すなわち必ずこの境界に挿入する。

**再現条件**: 既定文書で葉ノード「### 空間的に見るもう一つの窓」をクリック（md ペインに範囲ハイライトが出る）→ L キーでリンクポップアップを開き URL を入れて確定。マップにはリンクカードがそのノードの一部として描かれるが、md ペインのハイライトは挿入された `[title](url)` 行の直前で切れたまま。Mod+V の子貼り付けでも同じ（貼り付けたサブツリー全体がハイライトの外）。最後のノードを選んで md ペイン末尾に文字を打った場合も同様。

**確度**: 未検証(自己申告: 確定)

**影響**: 「マップの選択 = md の反転範囲」というミラーの前提が崩れる。ユーザは選択したノードの本文がどこまでか md 側で判断できない。

**修正方針**: applySnap の条件を外して常に syncSelectionViews(false) を呼ぶか、少なくとも insertContentLine / paste の直後に明示的に呼ぶ。ハイライト自体を inclusive な mark にするのは他の境界で副作用があるので非推奨。

### P5-8 / 未検証 / `D:/1.atrium/mmm/src/editor.ts:160`

**マップからのリネームは見出し行を丸ごと置換するため、md ペインのキャレット/テキスト選択が行頭に潰れる**

```
this.view.dispatch({
        changes: set.map((e) => ({ from: e.from, to: e.to, insert: e.insert })),
        annotations: fromCore.of(true),
      });
```

**症状**: applySets は selection を指定しないので CM 側は既存選択を assoc=-1 でマッピングするだけ。core/cmds.mbt:243 の cmd_rename は `Edit{ from: nd.hs, to: nd.he, insert: line }`、つまり毎打鍵で見出し行全体を置換する。置換範囲の内側にあった位置は mapPos により置換開始位置（= hs）へ collapse するので、md ペインにあったキャレットは行頭へ飛び、テキスト選択は消える。

**再現条件**: 1) md ペインで `## markdown` 行の「mark|down」の位置をクリック（またはその単語をダブルクリックして選択）。2) マップの「markdown」ノードをダブルクリックして 1 文字入力。3) Mod+/ で md ペインに戻る → キャレットは `## markdown` 行の先頭、選択は消えている。

**確度**: 未検証(自己申告: 確定)

**影響**: 両ペインを行き来しながら編集すると md 側の作業位置が毎回失われる。

**修正方針**: cmd_rename の置換範囲をラベル部分（he 側からの差分）だけに絞るか、applySets 側で編集前の selection を changes.map(assoc) ではなく明示的に保存/復元する。

### P5-9 / 未検証 / `D:/1.atrium/mmm/src/mindmap.ts:1555`

**j/k の兄弟ループがマップ右側から左側へ飛ぶ（「下」で横に移動する）**

```
const sibs = nodes.filter((n) => n.parent === cur.parent);
```

**症状**: 兄弟集合を文書順だけで作り、group（--- で分かれる左右の配置）を考慮していない。ルート直下では group 0 が右側、それ以降が左側に描画される（mindmap.ts:513-514）ため、文書順で隣でも画面上は反対側にある。

**再現条件**: 既定文書（`---` を含む）でマップの「## mindmap」をクリック → j を押す。選択は右側の下から左側の「## mirror」へ飛ぶ（画面上は下ではなく左へ移動）。さらに j でループして右側の「## markdown」へ戻る。

**確度**: 未検証(自己申告: 確定)

**影響**: vim キー/矢印での移動が画面上の位置と一致せず、選択を見失う。

**修正方針**: 上下移動の兄弟集合を `sideOf`（または group）が一致するものに限定し、左右キーで側を跨ぐようにする。

### P5-10 / 未検証 / `D:/1.atrium/mmm/src/mindmap.ts:1116`

**矩形選択が常に選択を置き換え、Shift/Ctrl を押しても追加選択にならない**

```
if (hit.length !== cur.size || hit.some((id) => !cur.has(id))) {
```

**症状**: ドラッグ中の setSelection は hit だけを渡しており、修飾キーを一切見ていない。修飾キーが見られているのは pointerup の「動かなかったクリック」判定（mindmap.ts:1150）だけ。Figma 準拠（spec 3.3）を謳っているが Shift+マーキーの加算選択がない。

**再現条件**: マップで数ノードをクリック/Ctrl+クリックで選択 → Shift を押したまま空白から別のノード群をドラッグで囲む。既存の選択は保持されず、囲んだ分だけに置き換わる。

**確度**: 未検証(自己申告: 確定)

**影響**: 広いマップで離れた複数グループを選ぶ手段がない（Ctrl+クリックの1個ずつしかない）。

**修正方針**: rubberStart 開始時に修飾キーと開始時の選択集合を保存し、Shift/Ctrl ドラッグ中は baseSelection ∪ hit を this.order 順で渡す。

### P5-11 / 未検証 / `D:/1.atrium/mmm/src/main.ts:493`

**undo/redo 後に選択が復元されない（core は id を復元しているのに使っていない）**

```
applySnap(core.undo(), "core");
```

**症状**: doUndo/doRedo は runCmd を通さないので snap.focus を完全に無視する。core 側は replay_entry(core/doc.mbt:411) が entry.before/after のペアからノード id を復元するため、削除を undo すると元の id でノードが戻ってくるが、削除時に applySnap の prune（main.ts:185-191）で selection からは既に消えているため、戻ってきたノードは選択されない。

**再現条件**: マップでノードを選んで dd で削除 → Mod+Z。ノードは戻るが選択は空、anchorId も -1 のまま。続けて Enter や i を押しても何も起きない。

**確度**: 未検証(自己申告: 確定)

**影響**: undo のたびに選択を手で取り直す必要がある。連続 undo で「どこを戻したか」がマップ上で分からない。

**修正方針**: doUndo/doRedo でも snap.focus を見て `setSelection([snap.focus], snap.focus)` + `map.ensureVisible` を行う（focus が -1 の場合のみ現状維持）。

### P5-12 / 未検証 / `D:/1.atrium/mmm/src/mindmap.ts:1443`

**i / a / A のキャレット位置が全て末尾で、vim の意味と一致しない**

```
this.editCaret = key === "I" ? "start" : "end";
```

**症状**: editCaret は "start"/"end" の二値しかなく、I のみ先頭、i/a/A は全て末尾になる。vim では i = カーソル直前、I = 行頭、a = カーソル直後、A = 行末。

**再現条件**: マップでノードを選び i を押す → キャレットはラベル末尾（vim なら行頭〜カーソル位置が期待値）。a / A を押しても同じ位置。

**確度**: 未検証(自己申告: 確定)

**影響**: vim キーバインドを期待するユーザが i と A を区別できない。実害は小さい。

**修正方針**: 仕様として意図的なら mmm.md に明記する。合わせるなら i を "start" 相当にするか、beginEdit に数値キャレット位置を渡せるようにする。

### P5-13 / 未検証 / `D:/1.atrium/mmm/src/mindmap.ts:901`

**beginEdit が箱を見つけられず早期 return すると editClear / editCaret が次回の編集へ漏れる**

```
if (!b) return;
```

**症状**: editClear は mindmap.ts:906-911 で、editCaret は mindmap.ts:917 で、いずれも「beginEdit が箱を取得できた後」にしか消費/リセットされない。s / cc（mindmap.ts:1364, 1372-1375）は editClear=true を立ててから editRequested を呼ぶので、beginEdit が 901 行で return するとフラグが立ちっぱなしになり、次に開いた編集で `this.host.rename(id, "", tag)`（mindmap.ts:910）が走って無関係なノードのラベルが空になる。

**再現条件**: 書けない。現状 render() が全ノードに箱を作るため this.boxes.get(id) が undefined になる経路を特定できなかった。要確認: host.editRequested（main.ts:458）が byId で通過し、かつ map.boxes に無い id が存在しうるか。具体的には (a) render() の tops 到達不能ノードが実在しうるか、(b) applySnap 以外の経路で host.nodes() だけが更新され render() が走らない瞬間があるか、をコア側の rebuild_nodes の parent 付与規則と合わせて確認すれば決まる。

**確度**: 未検証(自己申告: 要確認)

**影響**: 成立した場合はラベルの無音消去（データ損失）。成立しなくても、フラグを消費前に return する構造は将来の変更で壊れやすい。

**修正方針**: beginEdit の先頭（`if (!b) return;` の前）で editClear / editCaret をローカル変数に取り出して即座にフィールドをリセットする。

### P5-14 / 未検証 / `D:/1.atrium/mmm/src/main.ts:186`

**F-004 の map_offset=-1 の新しい影響: md ペインで見出しの # を1つ消すとマップの選択が無言で外れる**

```
selection.delete(id);
```

**症状**: 既知 F-004（core/doc.mbt:126 の「pure deletion starting here → return -1」）の根本原因が、outdent 以外に「md ペインでの通常のテキスト編集」でも表面化する、という新しい帰結。見出し先頭の `#` を1文字消すと map_offset が -1 を返してノード id が再採番され、main.ts:185-191 の prune が選択からそのノードを落とし、192-195 で anchorId も -1 になる。ノード自体は（レベルが変わっただけで）画面に残っているのに選択だけ消える。

**再現条件**: 既定文書でマップの「### 実体は .md ファイル」をクリック（両ペインでハイライト）→ md ペインでその行の3つ目の `#` の直後にキャレットを置き Backspace を1回（`## 実体は .md ファイル` になる）。ノードはマップに残っているが選択表示が消え、続けて Enter / i / Tab を押しても何も起きない（anchorId が -1）。

**確度**: 未検証(自己申告: 確定)

**影響**: md ペインで見出しレベルを直接直すという普通の操作のたびに、マップ側の作業対象を見失う。

**修正方針**: core 側で見出し先頭の純削除でも「行が依然として見出しなら同一ノード」と判定して id を継承させる（F-004 の修正と同一）。UI 側の暫定策としては prune で落ちた id を「同じ hs で始まる新 id」に張り替える。

### P5-15 / 未検証 / `D:/1.atrium/mmm/src/main.ts:470`

**md ペインのキャレット位置はマップの選択に一切反映されない（ミラーが片方向）**

```
const editor = new MdEditor(mdPane, onUserEdits);
```

**症状**: MdEditor に渡すコールバックは onUserEdits（テキスト変更）だけで、selection 変更を受け取る口がない。editor.ts 側にも selectionSet を監視する updateListener はない。したがって md ペインでキャレットを別の見出しへ動かしても selection / anchorId は変わらず、マップの選択は前のノードのまま。逆方向（マップ→md のハイライトと reveal）だけが実装されている。

**再現条件**: マップで「## markdown」を選択 → md ペインの `## mirror` 行をクリックしてキャレットを置く → Mod+/ でマップへ戻り Enter。「## mirror」ではなく「## markdown」の下に兄弟が作られる。

**確度**: 未検証(自己申告: 要確認)

**影響**: 両ペイン往復時に「今どのノードを操作しているか」が食い違う。

**修正方針**: 仕様（spec 4.4 / mmm.md）でミラーが map→md の片方向と決まっているかを確認するのが先。双方向にするなら editor.ts に selectionSet 用の updateListener を足し、キャレット位置を含む最深ノードを setSelection する（reveal=false で無限ループを避ける）。

### P5-16 / 未検証 / `D:/1.atrium/mmm/src/mindmap.ts:1525`

**Mod+←/→ がマップの選択移動として動作し、既定動作も潰される**

```
if (mod && (dirKey === "ArrowUp" || dirKey === "ArrowDown")) {
```

**症状**: 1512 行の `const dirKey = mod ? key : ...` により Mod+矢印も dirKey が Arrow* になり、1523-1524 で preventDefault される。しかし Mod 分岐は上下（並び替え）しか扱っていないので、Mod+←/→ はそのまま通常の左右ナビゲーションとして実行される。

**再現条件**: マップでノードを選び Mod+→ を押す。修飾なしの → と同じく子ノードへ選択が移動する（並び替えでもブラウザ既定動作でもない）。

**確度**: 未検証(自己申告: 確定)

**影響**: 割り当てのない修飾キー操作が別のコマンドとして誤発火する。将来 Mod+←/→ に機能を割り当てる際の衝突源。

**修正方針**: 1525 行の条件を `if (mod)` にして、上下以外は return する（または Mod+←/→ を indent/outdent に割り当てる）。

---

## 領域: キーボード入力全般（mindmap.ts onKeydown / vim 2ストローク、main.ts window capture、editor.ts keymap、popup.ts）

**調べたもの**

- src/mindmap.ts 全 1815 行を Read で通読（NUL バイト回避）。onKeydown(1325-1581) の全分岐、vim pendingKey/pendingTimer 機構(1204-1206, 1334-1347)、#node-editor の keydown/blur(1280-1292)、window の Space keydown/keyup(994-1010) を逐行確認
- src/main.ts 全 1136 行、src/editor.ts 全 189 行、src/popup.ts 全 237 行、index.html を通読
- src 内の keydown/keyup リスナを全列挙: main.ts:883(window capture), mindmap.ts:994/1005(window bubble, Space), mindmap.ts:1280(#node-editor), mindmap.ts:1295(map-pane), popup.ts:48(overlay)/86(textarea)/118(link 入力)。keypress は 0 件
- 伝播順の検証: main.ts の window capture がすべてに先行し、popup overlay の stopPropagation(popup.ts:49) は capture 段には効かない。#node-editor の stopPropagation(mindmap.ts:1282) は pane の onKeydown を確実に抑止している
- node_modules/@codemirror/view/dist/index.js:4568 と 4870 を確認 — CodeMirror は defaultPrevented のイベントを完全に無視する。したがって Mod+/ (main.ts:898 で preventDefault) が defaultKeymap の Mod-/ = toggleComment (commands/dist:1797) を二重発火することは無い。Mod+Z/Y も stopPropagation 済みで CM に届かない（かつ CM history 自体を読み込んでいない）
- md ペインの Tab トラップには脱出手段がある: @codemirror/view dist:4947 の Escape → tabFocusMode(2秒) と defaultKeymap の Ctrl-m / Shift-Alt-m toggleTabFocusMode(commands/dist:1799)。マップペインには相当物が無い
- IME ガード: mindmap.ts:1326(pane)、1281(#node-editor)、main.ts:885(global) の 3 箇所すべてに isComposing / keyCode===229 があることを確認
- マップペインにフォーカスがある状態の Mod+O は pane 側 onKeydown(1457-1463) が preventDefault するのでブラウザの既定動作は出ない（ラベル編集中のみ漏れる。所見 1 参照）
- 矢印キーはマップペインで常に preventDefault(1524) されるため、Alt+ArrowLeft によるブラウザ戻るはマップペインでは発生しない。md ペインでも Alt-ArrowLeft は CM の cursorSyntaxLeft(commands/dist:1780) が消費する
- e.repeat を参照している箇所は src 全体で 0 件（grep 済み）
- core/api.mbt:104 `st.next_id = 1` を確認 — init_doc でノード id が 1 から振り直される（所見 3 の前提）

### P5-1 / 未検証 / `D:/1.atrium/mmm/src/main.ts:895`

**ノードラベル編集中の Ctrl+O がブラウザの「ファイルを開く」ダイアログに素通りする**

```
if (mapPane.contains(document.activeElement)) return;
```

**症状**: コメントは「in the map pane (incl. its label editor) Mod+O belongs to the map」と書いているが、#node-editor は mapPane の子(mindmap.ts:246)なのでこの return に入り preventDefault されない。一方 #node-editor の keydown ハンドラ(mindmap.ts:1280-1289)は Escape / Enter / Tab しか扱わず preventDefault しない。結果 Ctrl+O の既定動作（ブラウザのローカルファイルを開くダイアログ）がそのまま発火する。

**再現条件**: 1. マップ上のノードをダブルクリック（または i / Enter）してラベル編集に入る。2. そのまま Ctrl+O を押す。3. OS のファイル選択ダイアログが開く。4. 適当なファイルを選ぶとタブがそのファイルへ遷移し、mmm のセッション（fileHandle、選択、編集中ラベル）が消える（未保存なら beforeunload の確認だけ出る）。マップペイン本体にフォーカスがある状態では同じ Ctrl+O が「--- グループ付き兄弟追加」になるので、編集に入った瞬間だけ挙動が変わる。

**確度**: 未検証(自己申告: 確定)

**影響**: 編集中の誤爆で意図せずアプリから離脱する。localStorage に本文は残るが、ファイルハンドルとフォーカス状態は失われる。

**修正方針**: #node-editor の keydown で mod+o を捕まえて preventDefault する（何もしない、またはマップと同じ addSibling(split) に流す）。あるいは main.ts:895 の early return を `preventDefault()` してから return に変える。

### P5-2 / 未検証 / `D:/1.atrium/mmm/src/popup.ts:219`

**お絵描きポップアップだけフォーカスを移さないため、モーダルの裏でマップのショートカットが全部生きている / Esc で閉じない**

```
body.append(bar, canvas);
```

**症状**: showCodePopup は `queueMicrotask(() => code.focus())` (popup.ts:94)、showLinkPopup は `queueMicrotask(() => url.focus())` (popup.ts:126) でフォーカスを奪うが、showDrawPopup にはフォーカス移動が一切無い。document.body.append(overlay) はフォーカスを動かさないので activeElement は map-pane のまま。よってキー入力は overlay の keydown(popup.ts:48) ではなく map-pane の onKeydown に届き、Esc も overlay に届かないためポップアップが閉じない。

**再現条件**: 1. ノードを 1 つ選択し、Shift+D でお絵描きポップアップを開く。2. Esc を押す → ポップアップは閉じず、代わりに選択だけが解除される（mindmap.ts:1506-1509）。3. 続けて d d と押す → 裏で選択ノードが削除される。y y でコピー、Enter で兄弟追加、Shift+Tab で親作成も全部通る。4. 絵を描いて「確定」を押すと、host.addDrawing の `byId.has(id)` (main.ts:450) が生きていれば既に別物になっている木に画像行が挿入される。

**確度**: 未検証(自己申告: 確定)

**影響**: モーダル表示中に文書が黙って破壊される。Esc が効かないので閉じ方がボタンしかないことも一貫性を欠く。

**修正方針**: showDrawPopup でも canvas か btnOk に queueMicrotask(() => …focus()) する。より確実には shell() 側で overlay 生成直後に panel（tabindex=-1）へフォーカスを移す。

### P5-3 / 未検証 / `D:/1.atrium/mmm/src/main.ts:909`

**グローバルショートカットが capture 段のためモーダルポップアップの裏で発火する（Mod+O でファイルを差し替えると id 再利用で別ノードに挿入される）**

```
{ capture: true },
```

**症状**: popup.ts:49 の `e.stopPropagation(); // keep map/global shortcuts out` は overlay（ターゲット側）でのバブル停止なので、window の capture リスナ(main.ts:883)には一切効かない。ポップアップ表示中でも Mod+S(保存)、Mod+O(ファイルを開く)、Mod+/(ペイン切替=モーダル裏へフォーカス移動)、Mod+Z/Y(undo/redo) がそのまま走る。さらに core/api.mbt:104 の `st.next_id = 1` によって initDoc でノード id が 1 から振り直されるため、ポップアップが握っている id が新文書の別ノードに一致してしまう。

**再現条件**: 1. ノードを選択し Shift+C でコードポップアップを開く（フォーカスは textarea）。2. Ctrl+O を押す → activeElement は mapPane の外なので main.ts:896 が preventDefault して openFile() が走り、ファイル選択ダイアログが出る。3. 別の .md を選ぶ（未保存なら破棄確認）→ loadText → core.initDoc で id が振り直される。4. 開いたままのポップアップにコードを書いて Mod+Enter → main.ts:437 の `if (r && byId.has(id))` が新文書の同 id ノードに当たり、まったく無関係なノードの本文にコードブロックが挿入される。Ctrl+Z を押した場合はモーダルの裏で undo が進む。

**確度**: 未検証(自己申告: 確定)

**影響**: モーダル中の操作でファイル差し替え・undo が起き、最終的に指定していないノードへ本文が混入する。

**修正方針**: モーダル表示中フラグ（開いている overlay の有無）を持ち、main.ts の capture ハンドラ冒頭で `if (document.querySelector('.popup-overlay')) return;` 相当のガードを入れる。加えて addLink/addCode/addDrawing は id ではなく rev+id で有効性を確認する。

### P5-4 / 未検証 / `D:/1.atrium/mmm/src/mindmap.ts:1429`

**CapsLock ON で h が「サブツリーをコメントアウト」に化ける（大文字判定のキーが e.shiftKey を見ていない）**

```
if (key === "H" && anchor !== -1) {
```

**症状**: CapsLock が有効だと e.key は大文字になる（shiftKey は false のまま）。onKeydown はほぼ全分岐で e.key の大文字小文字だけを見ており e.shiftKey を照合していないため、意味が入れ替わる。h→"H" で toggleHidden（破壊的）、d→"D" でお絵描きポップアップ、c→"C" でコードポップアップ、l→"L" でリンクポップアップ、g→"G" で最終ノードへジャンプ、j/k→"J"/"K" は未定義でナビゲーション不能、u/y/z/s も無効化される。なお o/O だけは line 1459 で e.shiftKey を見ているので CapsLock でも正しく動く＝実装が不統一であることの裏付け。

**再現条件**: 1. CapsLock を ON にする。2. マップペインでノードを選択し、左へ移動するつもりで h を押す。3. 移動せず、そのノードのサブツリー全体がコメントアウト（hidden 化）される。続けて j/k を押しても何も起きない。d を押すとお絵描きポップアップが開く。

**確度**: 未検証(自己申告: 確定)

**影響**: CapsLock ON のユーザは移動キーが破壊的コマンドになり、vim 系ショートカットの半分が沈黙する。

**修正方針**: 判定を `key.toLowerCase()` + `e.shiftKey` の組に統一する（例: `const k = key.toLowerCase(); if (k === "h" && e.shiftKey) toggleHidden…`）。既に正しい形の line 1459 に合わせる。

### P5-5 / 未検証 / `D:/1.atrium/mmm/src/mindmap.ts:1351`

**キーリピートに対するガードが無く、d を押しっぱなしにすると連続削除される**

```
if (prev === "d") this.host.deleteSelection();
```

**症状**: src 全体に e.repeat の参照が 0 件。OS のオートリピート（Windows 既定で初回 ~500ms、以降 ~30ms 間隔）は keydown を撃ち続けるため、2 回に 1 回 prev==="d" が成立して deleteSelection が走る。リピート間隔は pendingTimer の 700ms より短いのでタイマは救済にならない。deleteSelection 後は snap.focus が次のノードに移る(main.ts:349)ので、削除が次々と連鎖する。Delete / Backspace(1478) と Ctrl+X(1496) も同様に無防備。

**再現条件**: 1. ノードを選択し、d キーを 1.5 秒ほど押しっぱなしにする。2. 十数ノードが次々に削除される（undo エントリも同数積まれる）。Delete キーを押しっぱなしにしても同様に木が消えていく。

**確度**: 未検証(自己申告: 確定)

**影響**: キーが引っかかった／長押しした瞬間に文書が大量に失われる。復旧には undo の連打が必要。

**修正方針**: onKeydown 冒頭で破壊的コマンド（dd / Delete / Backspace / Mod+X）については `if (e.repeat) return;` を入れる。2 ストローク機構自体もリピート由来の keydown を prev として扱わないようにする。

### P5-6 / 未検証 / `D:/1.atrium/mmm/src/mindmap.ts:1000`

**Space 押下中にウィンドウがフォーカスを失うと spaceDown が true のまま残り、以後クリックがパンになる**

```
this.spaceDown = true;
```

**症状**: spaceDown を false に戻すのは window の keyup(1005-1010) だけ。Alt+Tab 等でウィンドウがフォーカスを失うと keyup は届かない。window の blur ハンドラ(1302)は hideMenu しかしておらず spaceDown をリセットしない。結果、戻ってきた後の左クリックが pointerdown(1048) で `e.button === 0 && this.spaceDown` に一致し、選択ではなくパンになる。カーソルも grab のまま固定される。

**再現条件**: 1. マップペインをクリックしてフォーカスを与える。2. Space を押したまま Alt+Tab で別アプリへ切り替え、そこで Space を離す。3. mmm に戻ってノードを左クリック→ドラッグ → ノードが選択されずキャンバスがパンする。Space を一度押して離すまで直らない。

**確度**: 未検証(自己申告: 確定)

**影響**: 入力モードが見た目上の手掛かりなく固着し、選択・ドラッグ移動が一切できなくなる。

**修正方針**: 既存の `window.addEventListener("blur", …)`(1302) に `this.spaceDown = false; this.panning = null; pane.style.cursor = "";` を追加する。document の visibilitychange でも同様に落とす。

### P5-7 / 未検証 / `D:/1.atrium/mmm/src/mindmap.ts:1466`

**マップペインが Tab のフォーカストラップになっていて脱出手段が無い**

```
if (key === "Tab" && !e.shiftKey) {
```

**症状**: Tab / Shift+Tab はどちらの分岐でも無条件に e.preventDefault()(1470, 1476)される。anchor === -1 かつ sel.size <= 1 で何も起きないケースでも preventDefault だけは実行されるため、マップペインに一度フォーカスが入るとキーボードだけではツールバー（開く/保存/undo/redo/テーマ）へ戻れない。md ペイン側は CodeMirror が Escape→Tab の脱出（@codemirror/view dist:4947）と Ctrl-m の toggleTabFocusMode を持つが、マップペインには相当物が無い。#node-editor 編集中も Tab は preventDefault(mindmap.ts:1286)。

**再現条件**: 1. ページ読み込み直後（main.ts:1135 で mapPane.focus() 済み）またはツールバーから Tab を押してマップペインに入る。2. Tab / Shift+Tab を何度押してもフォーカスリングがツールバーに移らない。3. マウスを使わずにツールバーへ到達する手段は Mod+/（md ペインへ移動）→ Escape → Tab しかない。

**確度**: 未検証(自己申告: 確定)

**影響**: キーボードのみの利用者・支援技術利用者がツールバーに到達できない。

**修正方針**: anchor === -1 のときは preventDefault しない、あるいは Escape を押した直後の Tab だけ既定動作を通す（CodeMirror の tabFocusMode と同じ方式）逃げ道を用意する。

### P5-8 / 未検証 / `D:/1.atrium/mmm/src/popup.ts:60`

**ポップアップにフォーカストラップが無く、Shift+Tab で背後の UI に抜けられる**

```
document.body.append(overlay);
```

**症状**: overlay は body 末尾に追加されるだけで、focus トラップも inert/aria-modal も無い。overlay の keydown(48)は Escape と Mod+Enter しか処理せず Tab を止めない。コードポップアップの textarea は Tab を潰す(popup.ts:86-92)が、その手前の「言語」入力からの Shift+Tab は素通りする。overlay は position:fixed の全面（style.css:172-180）なのでポインタは遮られるが、キーボードは遮られない。

**再現条件**: 1. ノードを選択し Shift+C でコードポップアップを開く（フォーカスは textarea）。2. Shift+Tab を 2 回押す → フォーカスがオーバーレイの背後にあるツールバー/マップペインへ抜ける。3. その状態で Enter / Space を押すと背後のボタン（開く・保存など）が起動する。

**確度**: 未検証(自己申告: 確定)

**影響**: モーダル表示中に背後の UI を誤操作できる。スクリーンリーダ利用時はモーダル外の内容も読み上げられる。

**修正方針**: shell() で overlay 内の最初/最後のフォーカス可能要素を掴んで Tab をラップさせる（または <dialog showModal()> に置き換える）。

### P5-9 / 未検証 / `D:/1.atrium/mmm/src/mindmap.ts:1802`

**コンテキストメニューがキーボードを一切受け付けず、Esc でも閉じない**

```
hideMenu(): void {
```

**症状**: #ctx-menu は document.body 直下(258)でフォーカス不可、キーボードハンドラも無い。hideMenu を呼ぶのは pointerdown(1299-1301)と window blur(1302)だけ。右クリック時は pointerdown(1046)で pane.focus() 済みなので、メニュー表示中のキーは全部 map-pane の onKeydown に流れる。Escape は clearSelection(1506-1509)するだけでメニューは残り、しかもメニュー項目は `this.host.anchor()` を実行時に読むため、選択解除後にクリックすると空振り（あるいは別ノードに対して実行）になる。

**再現条件**: 1. ノードを右クリックしてコンテキストメニューを開く。2. Esc を押す → メニューは開いたまま、ノードの選択ハイライトだけが消える。3. その状態でメニューの「削除」をクリック → deleteSelection は selection.size === 0 で何もしない(main.ts:346)。4. 手順 2 の代わりに d d を押すと、メニューが開いたまま裏でノードが削除される。

**確度**: 未検証(自己申告: 確定)

**影響**: メニューが閉じない・項目が無反応という不整合、およびメニュー表示中の裏側キー操作。

**修正方針**: showMenu 中は keydown を監視し、Escape で hideMenu、矢印/Enter で項目移動・実行できるようにする。少なくとも onKeydown の先頭で「メニューが開いていたら hideMenu して return」する。

### P5-10 / 未検証 / `D:/1.atrium/mmm/src/mindmap.ts:924`

**endEdit() が blur ハンドラ経由でも無条件に map-pane へフォーカスを引き戻し、クリック先とフォーカスを奪い合う**

```
this.pane.focus();
```

**症状**: #node-editor の blur → host.commitEdit()(1290-1292) → map.endEdit() → pane.focus() という経路があり、blur の原因が「別要素へのフォーカス移動」であっても無条件にマップペインへ引き戻す。CodeMirror の mousedown ハンドラは同期的に contentDOM.focus() したのち `let active = view.root.activeElement; if (active && !active.contains(view.contentDOM)) active.blur();`（@codemirror/view dist:4985-4987）を実行するので、割り込んだ pane.focus() の結果 map-pane が blur され、最終的にどこにもフォーカスが無い状態（body）になり得る。

**再現条件**: 1. マップのノードをダブルクリックしてラベル編集に入る。2. そのまま md ペインの本文を 1 回クリックする。3. キャレットが md ペインに入らない（続けてタイプしても文字が入らない）。DevTools の Console で `document.activeElement` を見て、body または #map-pane になっていれば本件。合わせて、ラベル編集中に Alt+Tab でウィンドウを離れるだけでも blur→commitEdit→pane.focus() が走り、戻ったときに編集モードが終了してフォーカスがマップに移っている。

**確度**: 未検証(自己申告: 要確認)

**影響**: 編集からの離脱操作が 1 クリック余分に必要になる。ブラウザ差で「どこにもフォーカスが無い」状態が残る可能性がある。

**修正方針**: endEdit に `refocus = true` 引数を設け、blur 由来の commitEdit では pane.focus() を呼ばない（または `if (!this.pane.contains(document.activeElement) && document.activeElement === document.body)` の条件付きにする）。

### P5-11 / 未検証 / `D:/1.atrium/mmm/src/mindmap.ts:1336`

**修飾キー単独の keydown が vim 2ストロークの前半を消す**

```
this.pendingKey = "";
```

**症状**: onKeydown は key の種類に関係なく先頭で pendingKey を読み捨てる。Shift / Control / Alt / Meta / CapsLock を単独で押した keydown もここを通るため（それらは以降のどの分岐にも当たらず 1523 の return で終わる）、d→Shift→d のように途中に修飾キーが挟まると 2 ストロークが不成立になる。ユーザ側にはフィードバックが無いので「dd が効かないことがある」という再現性の低い症状になる。

**再現条件**: 1. ノードを選択して d を押す。2. Shift キーを 1 回押して離す（何も入力しない）。3. もう一度 d を押す → 削除されず、また pending 状態に戻るだけ。手順 2 を CapsLock や Ctrl に変えても同じ。

**確度**: 未検証(自己申告: 確定)

**影響**: 2 ストロークコマンドが不定期に不発になる。

**修正方針**: onKeydown 冒頭で `if (e.key === "Shift" || e.key === "Control" || e.key === "Alt" || e.key === "Meta" || e.key === "CapsLock") return;` として pendingKey を保持する。

### P5-12 / 未検証 / `D:/1.atrium/mmm/src/main.ts:889`

**Ctrl+S の長押しで saveFile() が多重起動し、書き込みロック衝突で「保存失敗」になり得る**

```
if (key === "s") {
```

**症状**: e.repeat ガードも「保存処理が in-flight か」のフラグも無いまま `void saveFile()` を撃つ。saveFile は await fileHandle.createWritable()(main.ts:571) を使うが、FileSystemWritableFileStream は同一ファイルをロックするため、前の write が close される前に次の createWritable が走ると reject する。catch は AbortError 以外を「保存失敗」として flashFilename する(main.ts:593-596)。

**再現条件**: 1. ファイルハンドルを持った状態（一度 保存 済み）で編集する。2. Ctrl+S を 2 秒ほど押しっぱなしにする。3. ファイル名の横に「保存失敗」が出るか、Console に NoModificationAllowedError が出るかを確認する。出れば本件（実ファイルは最後の成功分まで書けている）。

**確度**: 未検証(自己申告: 要確認)

**影響**: 実際には保存できているのに失敗表示が出る／逆に失敗表示を無視する習慣がつく。

**修正方針**: saveFile に in-flight ガード（Promise を 1 本に畳む）を入れ、キーハンドラ側でも `if (e.repeat) return;` する。

### P5-13 / 未検証 / `D:/1.atrium/mmm/src/mindmap.ts:1430`

**Shift+H (toggleHidden) だけが複数選択を無視して anchor 1 個にしか効かない**

```
this.host.toggleHidden(anchor);
```

**症状**: dd / Delete / Tab(indent) / Shift+Tab(outdent) / Mod+C / Mod+X は selection 全体に作用する(1467, 1473, 1479, 1492, 1497)のに対し、H だけ anchor 単独。sel.size のガードも無いので「複数選択しているのに 1 個だけ折り畳まれた」という結果になる。しかも toggleHidden は runCmd 経由(main.ts:368-370)で snap.focus に選択を貼り替えるため、元の複数選択も失われる。

**再現条件**: 1. Shift+ArrowDown で 3 ノードを選択する。2. Shift+H を押す。3. anchor の 1 ノードだけが hidden になり、選択は 1 ノードに縮む。

**確度**: 未検証(自己申告: 確定)

**影響**: 複数選択に対する操作の一貫性が崩れ、選択もリセットされる。

**修正方針**: host に toggleHiddenSelection を追加して選択全体に適用するか、少なくとも sel.size > 1 のときは何もしない（あるいは全件に順次適用）。

### P5-14 / 未検証 / `D:/1.atrium/mmm/src/mindmap.ts:1502`

**マップペインの Mod+V はネイティブ貼り付けを preventDefault した上でエラーを全部握り潰すので、失敗が無言になる**

```
this.host.paste();
```

**症状**: 1503 で preventDefault するためブラウザの paste イベントは発生せず、実処理は navigator.clipboard.read()/readText()(main.ts:388, 399) に一本化される。その全体が `void (async () => {…})().catch(() => {});`(main.ts:384, 423) で包まれており、権限拒否・API 非対応・見出しを含まないクリップボード(main.ts:402 `if (!hasHeadings(normalized)) return;`)のいずれでも一切の通知が無い。

**再現条件**: 1. 見出しを含まない普通の文章をクリップボードにコピーする。2. マップでノードを選択し Mod+V（または p）を押す。3. 何も起きず、理由の表示も無い。クリップボード権限を「ブロック」に設定した場合も同じく無反応。

**確度**: 未検証(自己申告: 確定)

**影響**: 貼り付けが効かない理由をユーザが判別できない。ネイティブ貼り付けへのフォールバックも塞がれている。

**修正方針**: host.paste の catch と早期 return の各所で flashFilename に理由を出す（「見出しを含むテキストのみ貼り付けできます」「クリップボードの読み取りが許可されていません」）。

### P5-15 / 未検証 / `D:/1.atrium/mmm/src/mindmap.ts:1507`

**ドラッグ中の Escape は選択を消すだけでドロップは実行される**

```
this.host.clearSelection();
```

**症状**: pointerdown(1046)で pane にフォーカスが移っているためドラッグ中も onKeydown が動く。Escape の分岐は clearSelection のみで、this.dragging / this.dropTarget を触らない。pointerup(1155-1161)は `this.dragging` に保存済みの ids をそのまま `this.host.move(ids, drop.id, drop.pos)` に渡すので、Escape を押しても移動は取り消されない。

**再現条件**: 1. ノードを掴んで別ノードの上までドラッグする（ドロップインジケータが出る）。2. マウスボタンを押したまま Escape を押す → 選択ハイライトが消える。3. そのままドロップする → 移動は実行される。

**確度**: 未検証(自己申告: 確定)

**影響**: ドラッグ操作を中断する一般的な手段（Esc）が効かず、誤配置を undo で戻すしかない。

**修正方針**: Escape の分岐で `if (this.dragging) { this.stopDragVisuals(); this.dragCand = null; return; }` を先に処理する。

### P5-16 / 未検証 / `D:/1.atrium/mmm/src/mindmap.ts:901`

**s / cc の editClear フラグが beginEdit の早期 return で消費されず、次回の編集がラベルを消す可能性がある**

```
const b = this.boxes.get(id);
```

**症状**: onKeydown の s(1374) と cc(1364) は `this.editClear = true` を立ててから editRequested を呼ぶが、beginEdit は `if (!b) return;`(902) で editClear を消費せずに抜ける。フラグはインスタンスに残り続けるため、次に成功する beginEdit が `this.editor.value = ""; this.host.rename(id, "", tag);`(908-910) を実行して、substitute を意図していないノードのラベルを空にする。同じ形の取りこぼしが editCaret(1436-1443 と 917)にもある。

**再現条件**: 要確認: this.boxes に存在しない id が host.nodes()/byId 側には存在する状態を作れるかで決まる。render() が `const b = boxes.get(n.id); if (!b) continue;`(562-563) と防御しているとおり box 欠落は想定されているので、まず DevTools で `map` インスタンスの boxes.size と core のノード数が食い違う文書（既知 F-005 の 2 個目の "#" 見出しを含む md など）を探し、そのノードを anchor にして s を押したあと別ノードで i を押してラベルが消えるかを見る。boxes が常に全ノードを含むと確認できれば本件は到達不能。

**確度**: 未検証(自己申告: 要確認)

**影響**: 到達した場合、無関係なノードのラベルが無言で空になる（rename は undo 可能）。

**修正方針**: beginEdit の早期 return の前に `this.editClear = false; this.editCaret = "end";` を実行する（フラグは呼び出しごとに必ず消費する）。

---

## 領域: markdown 構文の境界（core/parser.mbt の行スキャナ、doc.mbt の木構築、cmds.mbt のテキスト生成、src/relevel.ts の深さ再割り当て、src/mindmap.ts のコンテンツカード mini パーサ）

**調べたもの**

- core/parser.mbt を全文精読（scan_lines / scan_doc / is_marker_line / is_separator / fence_open / fence_close_len）
- core/doc.mbt を全文精読（rebuild_nodes の重複ルート除去、seps の空行判定、has_content、compute_groups、map_offset）
- core/cmds.mbt を全文精読（insert_heading_edit / sanitize_label / nl / preceded_by_blank / tidy_del_start / cmd_toggle_hidden / move_block / selection_text）
- core/api.mbt, core/js/exports.mbt を全文精読
- src/relevel.ts を全文精読し、scanDepths のフェンス判定をコアの fence_open/fence_close_len と 1 行ずつ突き合わせ（開き・閉じ・info string・3スペース上限・タブ・見出し正規表現はすべて一致することを確認）
- src/mindmap.ts の parseLink(119-140) / parseImage(142-153) / render のコンテンツ行走査(313-379) / カード描画(616-724) を精読
- src/main.ts の paste(380-424) / addLink・addCode・addDrawing(426-457) / insertContentLine(720-736) / saveImageToDisk の名前検証(788-836) / onUserEdits(250-300) / openFile(518-543) / loadText(473-488) を精読
- src/popup.ts, src/editor.ts を全文精読
- コンパイル済みコア(core/_build/js/release/build/js/js.js)を Node から import し、フェンス変種（3/4連、チルダ、info string に空白・バッククォート、タブ/4スペースインデント）を実測
- setext 見出し・YAML front matter・raw HTML ブロック・blockquote・エスケープ `\#`・全角スペース・タブ・`#` 単独・`# `（末尾スペース）を実測
- `---` の区切り成立条件（3〜10連、スペース区切り、`***`/`___`、0〜4スペースインデント、末尾タブ、フェンス内、本文中の水平線）を実測
- `<!--` / `-->` の行単位判定（インデント、タブ、1行 `<!-- note -->`、未閉鎖、フェンス内、フェンス内に飲まれる `-->`、本文中の単独 `-->`）を実測し hide→show を往復
- mindmap.ts のカード mini パーサを verbatim に移植して Node で 15 パターン実行（info string、フェンス長、リスト内リンク、URL 中の括弧、パス中の空白、`<…>` 形式）
- CodeMirror の CRLF 正規化を node_modules/@codemirror/state から実測（core len 13 / cm len 10）
- toggleHidden / deleteNodes / reorderNode / selectionText / replaceText を実際に叩いてテキスト破壊を再現

### P5-1 / 未検証 / `core/parser.mbt:204`

**コードフェンスの info string にバッククォートが入るとフェンスが成立せず、以降の文書が丸ごとノードから消える（削除でデータ消失）**

```
if cc(text, r) == 96 {
```

**症状**: バッククォートフェンスは info string にバッククォートを含むと開きフェンスにならない（CommonMark 準拠）。するとフェンス内の `#` 行が本物の見出しになり、さらに「閉じ」のつもりの ``` 行が新しい開きフェンスになって EOF まで全部飲み込む。飲まれた見出しはノード一覧から消えるが、直前ノードの subEnd は EOF のままなので、そのノードを削除・コピー・hide すると見えていない部分まで巻き込む。src/popup.ts:101 は 言語 欄を trim するだけで検証しないので UI から到達可能。

**再現条件**: 1) `# R` / `## A` / `## B` + B に本文 のある文書を開く。2) A を選んでコードブロック追加ポップアップを開き、言語欄に `a\`b`（バッククォートを含む文字列）、コード欄に任意の複数行を入れて確定。3) マップから `## B` とその本文が消える。4) A を選んで削除すると本文は `# R\n` だけになり、B の本文が消滅する（実測済み）。

**確度**: 未検証(自己申告: 確定)

**影響**: ユーザーの本文が無警告で消える。F-005 と同じ「表示されていないブロックが直前ノードの範囲に含まれる」構造だが、発火経路（フェンス不成立）が別。

**修正方針**: popup.ts の 言語 入力からバッククォート（と空白）を落とすか拒否する。加えて main.ts:441 で lang をサニタイズしてから埋め込む。

### P5-2 / 未検証 / `src/main.ts:296`

**CRLF ファイルで md ペイン(CodeMirror)とコアのオフセットがズレ、入力が別の場所に書き込まれる**

```
snap = core.replaceText(e.from + delta, e.to + delta, e.insert, tag);
```

**症状**: CodeMirror は lineSeparator 未指定だと doc 生成時に `\r\n` を `\n` に正規化する（node_modules/@codemirror/state で実測: core len 13 / cm len 10）。main.ts:525 の `await f.text()` は正規化しないので、コアは CRLF のまま保持する。md ペインが返すオフセットをそのまま core.replaceText に渡すため、CRLF 1 個ごとに 1 文字ずつ位置がずれる。editor.highlight / editor.reveal に渡す n.hs / n.subEnd も同様にずれる。

**再現条件**: 1) Windows のメモ帳などで CRLF の md（例 `# R` 改行 空行 `## A`）を保存して開く。2) md ペインの末尾（`## A` の直後）にカーソルを置いて `X` を打つ。3) コアのテキストは `# R\r\n\r\n## XA\r\n` になり、マップ上のラベルが `XA` になる（実測）。md ペインには `## A` の後ろに `X` が見えたままなので、両ペインが恒久的に食い違う。

**確度**: 未検証(自己申告: 確定)

**影響**: CRLF ファイルで編集内容が破壊され、md ペインとマップが同期しなくなる。選択ハイライトも常にずれる。

**修正方針**: loadText の入口で `text.replace(/\r\n/g,"\n")` に正規化する（保存時に元の改行へ戻すなら別途保持）か、EditorState に `EditorState.lineSeparator.of("\r\n")` を設定して CodeMirror 側を合わせる。

### P5-3 / 未検証 / `core/cmds.mbt:661`

**hide→show が本文中の単独 `-->` 行を巻き添えで削除する**

```
for r in st.hide_regions {
```

**症状**: cmd_toggle_hidden の「入れ子 hide 拒否」ガードは st.hide_regions（対になったマーカー）しか見ない。本文に単独の `-->` 行があるノードは hide 可能だが、`<!--` を入れた瞬間その `-->` が閉じマーカーとして成立してしまい、末尾に入れた本来の `-->` は領域の外に取り残される。show するとコアは領域の閉じマーカー＝ユーザーの `-->` 行を削除する。

**再現条件**: 1) `# R` / `## A` を作り、A の本文に `content` / `-->` / `more` の 3 行を書く（HTML コメントの説明などで普通に起こる）。2) `## B` を A の後に置く。3) A を hide する → 本文は `# R\n\n<!--\n## A\n\ncontent\n-->\nmore\n\n-->\n## B\n` になり、`more` 以降は実際には隠れていない。4) A を show する → `# R\n\n## A\n\ncontent\nmore\n\n-->\n## B\n`。ユーザーが書いた `-->` 行が消え、代わりに孤児の `-->` 行が `## B` の直前に残る（実測）。

**確度**: 未検証(自己申告: 確定)

**影響**: ユーザーの本文行が無警告で消え、文書にゴミ行が残る。F-007（hide→show の末尾改行）とは別の破壊。

**修正方針**: hide 前に [hs, sub_end) の各行を is_marker_line で走査し、`<!--` / `-->` のどちらかが 1 つでもあれば no-op にする（現在の hide_regions ベースのガードを行ベースに変える）。

### P5-4 / 未検証 / `core/cmds.mbt:670`

**hide 対象に閉じていないフェンスがあると `-->` がフェンスに飲まれ、hide/show のたびに `-->` が増殖する**

```
let close = if nd.sub_end > 0 && cc(st.text, nd.sub_end - 1) != 10 {
```

**症状**: sub_end の位置でフェンスが開いたままだと、そこに挿入した `-->` 行はコード内容として扱われ、scan_doc は閉じマーカーを見つけられない（regions に (…, -1, -1) が入る）。show 側（cmds.mbt:634-657）は c_start == -1 のとき `<!--` だけを消すので `-->` が本文に残る。同じ操作を繰り返すと `-->` が 1 行ずつ増える。

**再現条件**: 1) `# R` / `## A` を作り、A の本文に閉じていないフェンス（例 ```js だけ書いて閉じない）とコード行を書く。2) A を hide → `# R\n\n<!--\n## A\n\n```js\ncode\n-->\n`（コードブロック内に `-->` が見える）。3) A を show → `# R\n\n## A\n\n```js\ncode\n-->\n`（`-->` が残る）。4) もう一度 hide → `…code\n-->\n-->\n`（実測）。

**確度**: 未検証(自己申告: 確定)

**影響**: コードブロックにゴミ行が混入し、hide/show を繰り返すほど増える。

**修正方針**: 上記と同じ行ベースのガードに加え、閉じマーカーを挿入する前に [hs, sub_end) をフェンススキャンし、未閉鎖なら hide を拒否する。

### P5-5 / 未検証 / `core/doc.mbt:257`

**文書先頭の複数行 HTML コメント内の `#` 行が「隠しルート」になり、本物のルート見出しが捨てられる**

```
continue
```

**症状**: scan_doc は行が丸ごと `<!--` / `-->` の場合を hide 領域とみなす（parser.mbt:88-97）。領域内の見出しは hidden フラグ付きで構造に残る。rebuild_nodes は depth==1 を最初の 1 個しか採らないため、コメント内の `#` がルートになり、後続の本物の `# Root` が黙って捨てられる。

**再現条件**: 1) 先頭に `<!--` 改行 `# draft root` 改行 `-->` を書いた md（ライセンスヘッダや markdownlint-disable などで普通に起こる形）を開く。2) 続けて `# Real Root` / `## B` を書く。3) マップのルートは hidden の「draft root」になり、`# Real Root` はノード一覧に一切現れない。B はその子になる（実測: nodes = draft root(hidden), B のみ）。

**確度**: 未検証(自己申告: 確定)

**影響**: よくある markdown ファイルを開いただけで実ルートが消え、以後その見出しに対する操作が一切できない。F-005（2 つ目の `#` が捨てられる）の新しい発火経路。

**修正方針**: hide 領域内の見出しを「重複ルート判定」の対象外にする（seen_root を hidden でない depth==1 だけで立てる）か、hidden な depth==1 をルート候補にしない。

### P5-6 / 未検証 / `core/parser.mbt:103`

**見出しだけ先頭スペースを 1 個も許さず、フェンス・区切りは 3 スペースまで許す（内部不整合／CommonMark 非互換）**

```
// strict ^(#+)\s+(.*)$ with no leading spaces allowed
```

**症状**: is_separator(parser.mbt:155) と fence_open(parser.mbt:182) は先頭 3 スペースまで許容するのに、見出し検出は l.start から直接 `#` を数える。CommonMark は ATX 見出しにも 3 スペースまで認めるので、`   # H` は外部レンダラでは見出しだが mmm では単なる本文になる。

**再現条件**: 1) `# R` の下に ` # 一スペース見出し` または `   ## 三スペース見出し` を書いた md を開く。2) マップにノードが出ない（実測: nodes = R のみ）。3) 一方 `   ---` は区切りとして機能し、`   ```` はフェンスとして機能する（実測）ので、同じ 3 スペースでも扱いが違う。

**確度**: 未検証(自己申告: 確定)

**影響**: 既存 md を読み込んだとき構造が黙って欠落する。欠落した見出しブロックは直前ノードの subtree に残るので F-005 と同じ巻き添え削除経路になる。

**修正方針**: 見出しスキャンにも 3 スペースまでの先頭スペース読み飛ばしを入れる（hs は行頭のままにするか、is_separator と同じ書き方に揃える）。仕様として 0 スペース固定にするなら、フェンス・区切り側も 0 に揃える。

### P5-7 / 未検証 / `core/parser.mbt:140`

**`<!--` / `-->` マーカーだけインデント上限が無く、インデントされたコードブロック内の行が hide 領域を開く**

```
while a < b && is_space(cc(text, a)) {
```

**症状**: is_marker_line は前後の空白・タブを無制限にトリムして比較する。フェンス(3スペース上限・スペースのみ)や区切り(3スペース上限)と違い、8 スペースやタブでインデントされた `<!--` も領域を開く。CommonMark では 4 スペース以上は indented code block なのでコメントですらない。

**再現条件**: 1) ノードの本文に、HTML コメントの書き方を説明する 4 スペースインデントのコードブロックを書く（例: 8 スペース + `<!--` の行）。2) その行以降の見出しがすべて hidden になる。3) 実測: `# R\n\n        <!--\n## A\n        -->\n\n## B\n` で A が hidden=true、タブインデント版でも同じ。

**確度**: 未検証(自己申告: 確定)

**影響**: 意図しない一括 hide。閉じ側が無い場合は文書末尾まで全ノードが hidden になる。

**修正方針**: is_marker_line にも先頭 3 スペース上限（かつスペースのみ）の制約を入れ、is_separator / fence_open と揃える。

### P5-8 / 未検証 / `core/parser.mbt:99`

**YAML front matter を認識せず、front matter 内の `#` コメント行がルート見出しになる**

```
if is_separator(text, l) {
```

**症状**: 先頭の `---` は単なるグループ区切りとして消費され、front matter の中身は普通の行として走査される。YAML のコメント `# …` は行頭にあるため見出しとして採られ、最初の depth==1 になってしまう。本物の `# Root` は重複ルートとして捨てられる。

**再現条件**: 1) `---` / `title: x` / `# メモ` / `---` / 空行 / `# Root` / `## B` という md を開く。2) マップのルートが「メモ」になり `# Root` はノードに現れない（実測: nodes = メモ(d1), B(d2)）。3) front matter に `#` コメントが無い場合は害はない（実測で確認済み）。

**確度**: 未検証(自己申告: 確定)

**影響**: front matter 付きの md（Obsidian / Hugo / Jekyll など）で構造が壊れる。

**修正方針**: 文書先頭の `---` … `---` を front matter として無条件にスキップする分岐を scan_doc の冒頭に入れる。

### P5-9 / 未検証 / `core/parser.mbt:47`

**`#` の直後が全角スペースだと見出しにならない（日本語 IME で踏みやすい）**

```
c == 32 || c == 9
```

**症状**: is_space は ASCII スペースとタブしか見ない。日本語入力中に `#` の後を全角スペースにすると（IME が変換前に全角を出すのはごく普通）、見出しとして認識されない。md ペインで書いても何も起こらず、エラーも出ない。

**再現条件**: 1) md ペインで `#`（半角）に続けて全角スペース、続けて `見出し` と打つ。2) マップにノードが 1 つも増えない（実測: `#　R\n` → nodes 0 件）。

**確度**: 未検証(自己申告: 確定)

**影響**: 日本語ユーザーが最初のノードを作れずに詰まる。既存の日本語 md でも見出しが丸ごと欠落しうる。

**修正方針**: is_space に U+3000 (12288) を加えるか、少なくとも見出し判定側で全角スペースを空白として受ける。sanitize_label 側の trim も同様に揃える。

### P5-10 / 未検証 / `core/cmds.mbt:237`

**空ラベル見出しが `"# "`（行末スペース）になり、行末空白を落とすツールでノードが消える**

```
let line = hashes(nd.depth) + " " + sanitize_label(label)
```

**症状**: rename も insert_heading_edit(cmds.mbt:92-93) も必ず `hashes(depth) + " "` を書く。ラベルが空だと行は `"# "` になる。ところが parser.mbt:109 は `p < l.end` を要求するため `"#"` 単独行は見出しではない。prettier / editorconfig / git hook などが行末空白を削るとノードが消滅する。

**再現条件**: 1) `# R` / `## A` / `### C` を作り、A のラベルを空にする（本文は `# R\n\n## \n\n### C\n`）。2) 保存後に行末空白を除去するフォーマッタを通す（`## ` → `##`）。3) 再度開くと A が消え、C が R の直下に昇格する（実測: nodes = R(d1), C(d3)）。

**確度**: 未検証(自己申告: 確定)

**影響**: 外部ツールを 1 回通しただけでノードと id が失われ、階層が変わる。

**修正方針**: `"#"` 単独行も depth 個の見出し（空ラベル）として受け付ける（CommonMark と同じ）。あるいは空ラベルのとき `"# "` ではなくプレースホルダ文字を書く。

### P5-11 / 未検証 / `src/main.ts:440`

**addCode のフェンス長選択が `includes("```")` だけなので、4 連バッククォートを含むコードでフェンスが即閉じし、コード内の見出しが本物のノードになる**

```
const fence = r.code.includes("```") ? "````" : "```";
```

**症状**: コード中の最長バッククォート連を数えていないため、コードが 4 連以上を含むと外側フェンス（4 連）が内側の 4 連行で閉じられる。以降のコード行が構造として解釈される。

**再現条件**: 1) 任意のノードでコードブロック追加ポップアップを開く。2) コード欄に ```` （4 連バッククォート）/ `## inner heading` / ```` （4 連）を貼る（markdown の入れ子フェンスを説明するときに普通に起こる）。3) 確定すると `## inner heading` がマップに本物のノードとして現れる（実測: nodes = R, A, inner heading, B）。

**確度**: 未検証(自己申告: 確定)

**影響**: コード内容が文書構造に混入し、以後の移動・削除がコードを破壊する。

**修正方針**: `Math.max(3, 最長バッククォート連 + 1)` 個のバッククォートでフェンスを組む。

### P5-12 / 未検証 / `src/mindmap.ts:334`

**カード mini パーサのフェンス正規表現が info string を 1 トークンしか許さず、コード本文が誤ってリンク/画像カードとして描画される**

```
const fence = /^(`{3,}|~{3,})\s*(\S*)\s*$/.exec(t);
```

**症状**: `(\S*)\s*$` なので info string に空白が入るとマッチしない。コアはこれを正しくフェンスと認識する（実測）ので、マップ側だけがフェンスを見落とし、コード本文の行を 1 行ずつ mini パーサにかけてしまう。裸 URL はリンクカードに、`![](…)` は画像カードになりディスクからの画像読み込みまで走る。閉じフェンス行は空のコードカードになる。

**再現条件**: 1) ノードの本文に ```js title="app.ts" で始まるフェンスを書き、中に `https://example.com/leak` と `![](pic.png)` を含める。2) マップのそのノードに「リンクカード」と「画像カード（pic.png の読み込み）」が並び、最後に空のコードカードが出る（mini パーサを verbatim 移植して実測）。

**確度**: 未検証(自己申告: 確定)

**影響**: コード本文の中身がカードとして表示され、意図しないローカル画像読み込みが発生する。

**修正方針**: 正規表現を `/^(`{3,}|~{3,})(.*)$/` にし、バッククォートフェンスのときだけ info string にバッククォートが無いことを確認する（コアの fence_open と同じ規則にする）。

### P5-13 / 未検証 / `src/mindmap.ts:340`

**カード mini パーサの閉じフェンス判定が開きフェンスの長さを見ない**

```
if (c.startsWith(fence[1][0].repeat(3)) && /^[`~]+$/.test(c)) {
```

**症状**: `repeat(3)` 固定なので、4 連で開いたフェンスが 3 連の行で閉じてしまう。コアは長さ >= を要求する（parser.mbt:76）ので判定が食い違い、1 個のコードブロックが 2 個の壊れたカードに割れる。`/^[`~]+$/` はバッククォートとチルダの混在も許すので `~~~```` のような行でも閉じる。

**再現条件**: 1) addCode で ``` を含むコードを入れる（main.ts:440 により 4 連フェンスで囲まれる）。2) マップにはコードカードが 2 個（1 個目は空、2 個目に残りの行）現れる（実測: `[{code,lines:[""]},{code,lines:["still code"]}]`）。

**確度**: 未検証(自己申告: 確定)

**影響**: アプリ自身の addCode 出力が自分のカード描画で崩れる。

**修正方針**: `c.length >= fence[1].length` と「全文字が開きフェンスと同じ文字」を条件にする。

### P5-14 / 未検証 / `src/main.ts:733`

**TS 側の「直前が空行か」判定が CRLF を見ておらず、余分な空行が入る**

```
else if (at >= 2 && text[at - 2] !== "\n") prefix = "\n";
```

**症状**: CRLF 文書では `text[at-2]` が `\r` なので「空行なし」と誤判定し、既に空行があるのに更に改行を足す。コア側の preceded_by_blank(cmds.mbt:51-67) は `\r` を正しく飛ばしており、実装が二重化した上に片方だけ誤っている。main.ts:418-419 の paste でも同じコードが使われている。

**再現条件**: 1) CRLF の md を開く（`# R\r\n\r\n## A\r\n\r\n## B\r\n`）。2) A にリンクを追加する。3) 本文が `## A\r\n\r\n\n[x](https://e.com)\n\n## B\r\n` となり、空行が 2 行になる（実測）。

**確度**: 未検証(自己申告: 確定)

**影響**: CRLF 文書で挿入のたびに空行が増える。

**修正方針**: TS 側の判定を廃し、コアに「ブロック境界に挿入」API を足して preceded_by_blank を再利用する。最低でも `\r` を飛ばす処理を入れる。

### P5-15 / 未検証 / `src/relevel.ts:54`

**貼り付け・コンテンツ挿入が常に LF 固定で、文書の改行種別を無視する**

```
.join("\n");
```

**症状**: relevel は delta!==0 のとき LF で join し、delta===0 のときは元の改行を保つという非対称な挙動。main.ts:401 は貼り付け前に CRLF→LF に正規化し、main.ts:416-420 と main.ts:735 も `"\n"` を直書きする。一方コアは cmds.mbt:39-46 の nl() で文書の改行を尊重する。結果として CRLF 文書に LF 行が混ざる。

**再現条件**: 1) CRLF の md を開く。2) 任意のノードにコードブロック / リンク / 画像を追加、または見出しを含むテキストを貼り付ける。3) 保存したファイルを改行コードを表示できるエディタで見ると、挿入部分だけ LF になっている（実測: `## A\r\n\r\n\n[x](…)\n\n## B\r\n`）。

**確度**: 未検証(自己申告: 確定)

**影響**: 改行コードが混在し、git の差分が汚れる。外部ツールによっては読み込みに失敗する。

**修正方針**: コアの nl() 相当を JS 側にも公開し（あるいは挿入をすべてコア API 経由にして）、挿入テキストの改行を文書に合わせる。

### P5-16 / 未検証 / `src/mindmap.ts:145`

**画像パスに空白があると parseImage が取りこぼす（`<…>` 形式のサポートも空回りしている）**

```
const m = /^!\[[^\]]*\]\(<?([^)\s>]+)>?\)$/.exec(line.trim());
```

**症状**: 文字クラス `[^)\s>]+` が空白を除くので `![](./my pic.png)` はマッチしない。`<?…>?` は山括弧形式を意図しているが、山括弧形式の存在理由（パス中の空白）が同じ文字クラスで潰されているため無意味。main.ts:797-800 のファイル名検証（`/[\\:*?"<>|]/`）は空白を許すので、UI から空白入りの名前を付けられる。

**再現条件**: 1) お絵描きポップアップで描いて確定。2) 画像名プロンプトに `my pic` と入力。3) ファイルはディスクに保存され md にも `![](./my pic.webp)` が書かれるが、マップにはカードが一切出ない（mini パーサ移植で実測: out = []）。

**確度**: 未検証(自己申告: 確定)

**影響**: 保存した画像が永遠に表示されず、ユーザーには原因が分からない。

**修正方針**: saveImageToDisk のセグメント検証で空白を弾く（または `-` に置換する）。合わせて parseImage の山括弧分岐を `\(<([^>]+)>\)` の別 alternative にして空白を許す。

### P5-17 / 未検証 / `src/mindmap.ts:121`

**parseLink が URL 中の `)` を扱えず、`[title](url)` 形式のリンクだけカードにならない**

```
const md = /^\[([^\]]*)\]\((https?:\/\/[^\s)]+)\)$/.exec(t);
```

**症状**: URL 部が `[^\s)]+` なので閉じ括弧を含む URL で失敗する。裸 URL の分岐（`/^https?:\/\/\S+$/`）は成功するので、同じ URL でもタイトル付きにした瞬間カードが消えるという一貫性のない挙動になる。タイトルに `]` が含まれる場合も同様に失敗する。

**再現条件**: 1) ノードの本文に `https://en.wikipedia.org/wiki/Foo_(bar)` を書く → リンクカードが出る。2) 同じ URL を `[Foo](https://en.wikipedia.org/wiki/Foo_(bar))` に書き換える → カードが消える（実測）。

**確度**: 未検証(自己申告: 確定)

**影響**: Wikipedia など括弧を含む URL でリンクカードが表示されない。

**修正方針**: URL 部を貪欲でない `(.+?)` にして末尾 `\)$` で切るか、括弧の対応を数える。

### P5-18 / 未検証 / `src/mindmap.ts:325`

**F-005 の新しい帰結: 捨てられた 2 つ目の `#` ブロックの本文が、前のノードのカードとして描画される**

```
i + 1 < nodes.length && nodes[i + 1].hs < n.subEnd
```

**症状**: コンテンツ範囲の終端は「次の *ノード* の hs」か subEnd。重複ルートとして捨てられた見出しはノードに現れないので、その見出しと本文がまるごと前のノードのコンテンツ範囲に入り、mini パーサに食われる。

**再現条件**: 1) `# Root` / 空行 / `# Second root` / 空行 / `![](pic.png)` という md を開く。2) `# Second root` はノードに現れない（F-005）が、Root には pic.png の画像カードが表示される（実測: Root は hasContent=true, subEnd=EOF）。

**確度**: 未検証(自己申告: 確定)

**影響**: 存在しないはずのセクションの画像・リンク・コードが別ノードのカードとして出る。F-005 の既知の症状（削除・コピーでの巻き添え）に加えた新しい表示面の帰結。

**修正方針**: F-005 の根本（捨てた見出しの範囲）を直すのが本筋。暫定的にはコンテンツ走査で `^#+[ \t]` に当たった時点で打ち切る。

### P5-19 / 未検証 / `core/parser.mbt:152`

**setext 見出しを一切見ず、`---` の直前に空行を要求しないので外部レンダラと構造が食い違う**

```
fn is_separator(text : String, l : Line) -> Bool {
```

**症状**: 段落の直後に置かれた `---` を mmm はグループ区切りとして扱うが、CommonMark ではその段落が `<h2>` になる（thematic break にならない）。逆に `Title` / `===` という setext h1 は mmm では完全に無視される。

**再現条件**: 1) `# R` / `## A` / `text` / `---` / 空行 / `## B` という md を開く。2) mmm では B がグループ 1 に分かれる（実測: A(g0), B(g1)）。3) 同じファイルを GitHub 等で表示すると `text` が `<h2>` になり `---` は区切り線として描かれない。

**確度**: 未検証(自己申告: 確定)

**影響**: mmm が見ている構造と外部レンダラの構造が食い違う。mmm 自身の insert_heading_edit は必ず空行を入れるので、mmm が作った文書では発生しない（読み込み時のみ）。

**修正方針**: is_separator に「直前の行が空行または文書先頭」という条件を足す。setext は仕様上サポートしない方針でよいが、その旨をドキュメント化する。

### P5-20 / 未検証 / `core/doc.mbt:273`

**グループ区切り `---` は直前ノードの subtree に属するため、そのノードを消すと次のグループが黙って前のグループに吸収される**

```
if hp < heads.length() && is_blank_range(s_next, heads[hp].hs) {
```

**症状**: `---` は「次の見出しの直前にある」ときだけ区切りになるが、テキスト上は直前ノードの [hs, sub_end) の中にある。そのノードを削除すると `---` も一緒に消え、後続グループの分割が失われる。

**再現条件**: 1) `# R` / `## A` / `para` / `## Z` / 空行 / `---` / 空行 / `## B` を開く（A(g0), Z(g0), B(g1)）。2) Z を削除する。3) 本文は `# R\n\n## A\n\npara\n\n## B\n` になり、B が g0 に戻る（実測）。

**確度**: 未検証(自己申告: 確定)

**影響**: グループ分けが無関係なノード削除で消える。undo で戻るので破壊的ではないが、意図しないレイアウト変化になる。

**修正方針**: 削除時に、削除範囲の末尾にある区切り行を残す（範囲末尾から後ろ向きに `---` 行を除外する）か、区切りを次の見出しの所有にする。

### P5-21 / 未検証 / `core/cmds.mbt:589`

**並べ替えで `---` が文書末尾に取り残され、区切りとして機能しないゴミ行になる**

```
move_block(i, st.nodes[nx].sub_end, st.nodes[i].depth)
```

**症状**: `---` の後ろに見出しが無くなると doc.mbt:270-276 の hp ループが範囲外になり、seps に入らない。行はテキストに残るので外部レンダラでは水平線として描かれる。

**再現条件**: 1) `# R` / `## A` / `para` / 空行 / `---` / 空行 / `## B`（A(g0), B(g1)）。2) B を上に移動（`K` など）。3) 本文が `# R\n\n## B\n\n## A\n\npara\n\n---\n` になり、末尾に孤立した `---` が残る。マップ上は A も B も g0（実測）。

**確度**: 未検証(自己申告: 確定)

**影響**: 文書末尾に無意味な水平線が蓄積する。

**修正方針**: move_block / cmd_reorder の後に「末尾に取り残された区切り行」を掃除するか、区切りを移動対象ブロックに含める。

### P5-22 / 未検証 / `core/parser.mbt:182`

**タブインデントのフェンス判定がコア・relevel・カード mini パーサの 3 者で食い違う**

```
while p < l.end && cc(text, p) == 32 && indent < 3 {
```

**症状**: コアと relevel.ts:12(`^ {0,3}`) はスペースのみ 3 個まで。mindmap.ts:334 は `lines[li].trim()` 済みの文字列に当てるのでインデントもタブも無制限に許す。同じ文書でも「構造としてはフェンスでない／カードとしてはフェンス」という状態が作れる。

**再現条件**: 1) ノード本文に 4 スペースインデントのフェンス（`    ```` / `    x` / `    ```` ）を書く。2) コアはフェンスと見なさない（実測: `# in fence` 相当の行が見出しになりうる）が、カードは code カードとして描画される（mini パーサ移植で実測: lines:["    x"]）。3) タブインデント版でも同じ。

**確度**: 未検証(自己申告: 確定)

**影響**: 表示と構造が食い違い、原因の切り分けが難しくなる。

**修正方針**: カード mini パーサでも trim せず `/^ {0,3}/` で判定し、コアと relevel と同じ規則に揃える（3 実装の共通化が望ましい）。

### P5-23 / 未検証 / `src/main.ts:402`

**見出しの無いテキストの貼り付けが無言で捨てられる**

```
if (!hasHeadings(normalized)) return; // fence-aware, matches relevel
```

**症状**: hasHeadings が false なら何もせず return する。ユーザーには成功も失敗も伝わらない。`#見出し`（スペース無し）や `#　見出し`（全角スペース）のクリップも見出し無しと判定される。

**再現条件**: 1) マップペインで任意のノードを選ぶ。2) 見出しを含まないプレーンテキスト（箇条書きなど）をコピーして貼り付ける。3) 何も起こらず、エラーもトーストも出ない。

**確度**: 未検証(自己申告: 確定)

**影響**: 貼り付けが効かない理由がユーザーに分からない。

**修正方針**: 見出しが無いクリップは選択ノードのコンテンツ行として挿入するか、flashFilename で理由を表示する。

### P5-24 / 未検証 / `core/parser.mbt:109`

**raw HTML ブロック内・blockquote 内の `#` の扱いが CommonMark と両方向にズレる**

```
if depth >= 1 && p < l.end && is_space(cc(text, p)) {
```

**症状**: scan_doc は HTML ブロックも blockquote も知らない。`<div>` … `</div>` の中の行頭 `#` は mmm では構造になる（CommonMark ではリテラル）。逆に `> # quoted` は mmm では本文（CommonMark では h1）。

**再現条件**: 1) `# R` / `<div>` / `## inside html` / `</div>` / `## B` を開く → `## inside html` が本物のノードになる。2) `# R` / `> # quoted heading` / `## A` を開く → quoted heading はノードにならない（両方実測）。

**確度**: 未検証(自己申告: 確定)

**影響**: HTML を含む md でノードが増減する。前者は F-005 と同じ「見えないブロックが subtree に残る」経路にもなりうる。

**修正方針**: 最低限 `<div>`/`<table>`/`<script>` 等の HTML ブロック開始・終了を行単位で追い、フェンスと同じく構造判定から除外する。仕様上サポートしないなら明記する。

### P5-25 / 未検証 / `core/doc.mbt:295`

**hide するだけで直前ノードの hasContent が true になる**

```
let has_content = !is_blank_range(h.content_start, content_end)
```

**症状**: cmd_toggle_hidden は `<!--` を対象ノードの hs に挿入するので、そのマーカー行はテキスト上「直前の見出しと隠したい見出しの間」に入り、直前ノードのコンテンツ範囲に含まれる。同様に `-->` は隠したサブツリー最後のノードの範囲に入る。

**再現条件**: 1) `# R` / `## A` / `## B`（3 つとも hasContent=false）。2) B を hide する。3) スナップショットで A の hasContent が true になる（実測: A:content=true）。

**確度**: 未検証(自己申告: 要確認)

**影響**: 現状 hasContent は mindmap.ts:318 でカード走査をするかどうかにしか使われておらず、マーカー行はどのカードにもならないので見た目の影響は無い。ただしコンテンツ有無をアイコン等で出す実装を足した瞬間に誤表示になる。要確認: hasContent を UI 表示に使う予定があるかどうかで深刻度が決まる。

**修正方針**: has_content の判定でマーカー行（is_marker_line）を空行と同じ扱いにする。

---

## 領域: XSS・サニタイズ・信頼境界（HTML/SVG への文字列注入経路、data URL、リンク・画像の検証、貼り付け経路、CSP、SVG エクスポート）

**調べたもの**

- src/mindmap.ts (1814行) を Read で全読。NUL バイト対策として grep は全て `grep -a` を使用し、空ヒットが偽陰性でないことを確認した
- src/main.ts (1135行)、src/popup.ts (236行)、src/editor.ts (188行)、src/coreApi.ts (66行)、src/relevel.ts (55行)、index.html (44行)、src/style.css (328行) を全読
- innerHTML / outerHTML / insertAdjacentHTML / document.write / eval( / new Function / DOMParser / createContextualFragment を全ソースに grep -a → ヒットは src/mindmap.ts:250 の 1 箇所のみ。中身は静的な日本語ヒント文字列で、外部由来データの補間は無い。実質 innerHTML 由来の XSS 面は存在しない
- 文字列を DOM に入れる全経路を列挙して確認: ノードラベル (mindmap.ts:609)、ノード title (614)、リンクタイトル (635)、リンク URL title (637)、↗ グリフ (644)、コード行 (684)、画像名プレースホルダ (719)、コンテキストメニュー項目 (1781,1786)、popup.ts の全ラベル、main.ts:602/607 のファイル名フラッシュ、main.ts:25/1079 — すべて textContent。HTML パースされる経路は 1 つも無い
- parseLink() (mindmap.ts:119-140) の URL 検証を確認: `^\[([^\]]*)\]\((https?:\/\/[^\s)]+)\)$` と `^https?:\/\/\S+$` のみ。javascript: / data: / vbscript: / file: は data-url 属性に一切入らない。従って mindmap.ts:1253 の window.open で任意コード実行は不可
- window.open(url, "_blank", "noopener") (mindmap.ts:1253) の第3引数に noopener があることを確認 → 逆タブナビング (opener 経由の元ページ書き換え) は塞がっている
- parseImage() (mindmap.ts:144-153) がスキーム付きパスを `/^[a-z][a-z0-9+.-]*:/i` で全拒否することを確認 → `![](javascript:...)` / `![](data:...)` / `![](http://...)` は image href に到達しない
- インライン `<svg>` ブロック (mindmap.ts:356-368 → 649-660) の安全性を詰めた: markup は `<image href="data:image/svg+xml,...">` としてのみ使われ、生 DOM には一切挿入されない。SVG を image として参照した場合ブラウザは secure static mode で描画するため、`<script>` / イベントハンドラ / 外部リソース読み込みは動作しない。=> 悪意ある .md のインライン SVG からのスクリプト実行は「実際には不可能」と判定
- encodeURIComponent が `<` `>` `"` `&` `#` を全てパーセントエンコードすることを確認 → data URL からの属性ブレイクアウトも不可 (mindmap.ts:658、main.ts:143、main.ts:1031 の3箇所すべて)
- exportSvg() (mindmap.ts:778-868) を全読。出力は XMLSerializer 経由 (main.ts:1014) で、ラベル等は textContent に入っているためエスケープされる → エクスポート SVG へのマークアップ注入は不可
- applyColor() (main.ts:131-150) の色検証 `^#?([0-9a-f]{6})$` を確認。favicon の data URL と CSS カスタムプロパティ双方に検証済みの値しか入らない (localStorage 由来でも同じ関数を通る: main.ts:1100)
- 貼り付け経路を確認: map ペインは navigator.clipboard.read() の image/* と readText() のみ (main.ts:387-399)。text/html は一切読まない。md ペインは CodeMirror 6 で text/plain のみ、markdown() は構文ハイライトのみでプレビュー描画を持たない → HTML 取り込み経路は存在しない
- iframe / <object> / <embed> / location 代入 / location.assign|replace / postMessage / message リスナを全ソースに grep → 0 件。untrusted SVG がトップレベル文書として読み込まれる経路は無い
- MoonBit コア core/_build/js/release/build/js/js.js (108KB) に document / window / fetch / XMLHttpRequest / eval / new Function が 1 件も無いことを確認 → コアは純粋な文字列処理で、DOM 面を持たない
- CSP を全プロジェクトに検索 → index.html に meta CSP 無し、vite.config.* も存在しない (package.json は vite 素のまま) → 配信ヘッダも無い
- D&D 経路 (main.ts:856-878) と openFile() (main.ts:518-549) を確認。dragover の preventDefault によりブラウザが .md へナビゲートしてしまう事故は防がれている
- loadAsset() のパス正規化 (main.ts:663-671) を確認: `..` は segs.pop() で処理され、segs が空になる時点で return するため許可フォルダ「外」へは出られない。バックスラッシュ区切りは 1 セグメント名として getFileHandle に渡り Chrome 側で TypeError → catch されるだけでトラバーサルにならない

### P5-1 / 検証済(CONFIRMED) / `src/mindmap.ts:837`

**信頼できない .md が許可済みフォルダ内の任意ファイルを読ませ、その全バイトを SVG エクスポートに base64 で埋め込ませる**

```
const b = await (await fetch(href)).blob();
```

**症状**: loadAsset() (main.ts:654-682) は `![](path)` の path を拡張子も MIME も検査せずに getFileHandle → createObjectURL する。画像でないファイル (.env / id_rsa / 他人の .md / .kdbx) でも blob URL が作られ、mindmap.ts:698 で `<image href="blob:...">` として DOM に入る。描画は失敗するので画面上は「何も無い箱」に見える。ところが exportSvg() の 833-844 行は href が blob: で始まる全 image を無条件に fetch → FileReader.readAsDataURL し、`data:application/octet-stream;base64,…` としてエクスポート SVG に埋め込む。blob.type の検査は無い。パスは `..` を含められる (loadAsset は許可フォルダのルートまで遡れる) ので、md と同じ階層に限らない。

**再現条件**: 1. 一度お絵描き(D)か画像貼り付けを行い、`D:\notes` を readwrite で許可する(「今後も許可」)。許可は main.ts:716 で IndexedDB "dir" に永続化される。
2. `D:\notes\sub\evil.md` を作り、内容を `# a` / 空行 / `![](../secret.txt)` にする(secret.txt には目印の文字列を入れておく)。
3. mmm のウィンドウに evil.md をドロップして開く(D&D なら fileHandle が付き、dir.resolve が通る)。
4. マップ上を 1 回クリックする(main.ts:687 の unlockAssets が発火して読み取りが走る)。画面には破線のプレースホルダが出るだけで、読み取りの表示は一切無い。
5. ツールバーの「SVG」を押してダウンロード(または Shift+クリックでクリップボードへ)。
6. 出力された .svg をテキストエディタで開く → `<image ... href="data:application/octet-stream;base64,…">` をデコードすると secret.txt の中身がそのまま入っている。

**確度**: 確定

**検証の根拠**: 全リンクが実コードで追える。src/mindmap.ts:837 の引用は正確 (`const b = await (await fetch(href)).blob();`)。parseImage (src/mindmap.ts:144-153) はスキーム付きパスだけを弾き (`if (/^[a-z][a-z0-9+.-]*:/i.test(path)) return null;` :148)、拡張子も MIME も見ない。loadAsset (src/main.ts:654-682) は `..` を許可フォルダのルートまで許し (:666 `if (segs.length === 0) return;` が唯一のガード)、任意ファイルに `URL.createObjectURL(await fh.getFile())` する (:676)。render はその blob URL を `<image href>` に入れ (src/mindmap.ts:689-698)、exportSvg は `href.startsWith("blob:")` だけを条件に全画像を fetch → readAsDataURL して埋め込む (src/mindmap.ts:833-844) — blob.type の検査は無い。exportMap → XMLSerializer → downloadBlob (src/main.ts:1009-1021) でファイルに出る。

**検証による訂正**: MIME は「常に application/octet-stream」ではなくブラウザが拡張子から決める Blob の type。`.txt` なら `data:text/plain;base64,…`、拡張子なし (id_rsa 等) なら `data:application/octet-stream;base64,…`。再現手順 4 の「破線のプレースホルダが出る」も不正確 — 破線プレースホルダ (src/mindmap.ts:703-720) は assetUrls が null の間だけで、読み取りが成功すると render が `<image>` に差し替え、デコードに失敗して「空白の帯」になる。さらに手順 4 のクリックは必須ではない: 「今後も許可」済みなら loadAsset 自身の queryPermission (src/main.ts:657) が granted を返し、ドロップ直後の render でそのまま読まれる (もしくは boot 時の src/main.ts:1128 のリトライ)。ユーザー操作ゼロで成立する分むしろ悪い。

**影響**: 許可済みフォルダ配下の任意ファイルが、ユーザーが「マップの図」として共有した SVG に不可視のまま同梱されて外部へ出る。WebP 書き出しでは画素にならないので漏れない = SVG エクスポート経路に固有。攻撃者は .md 1 枚を渡すだけでよく、ユーザー側に読み取りの痕跡は残らない。

**修正方針**: exportSvg の埋め込みループで `if (!b.type.startsWith("image/")) { img.remove(); continue; }` を入れる。併せて loadAsset (main.ts:675 付近) で拡張子または File.type を画像に限定し、非画像は assetUrls に null のまま残す。

### P5-2 / 検証済(CONFIRMED) / `src/mindmap.ts:359`

**閉じていない `<svg` 行で render が O(N^2) になり、untrusted .md を開いただけでアプリが固まる**

```
while (!buf[buf.length - 1].includes("</svg>") && j + 1 < lines.length) {
```

**症状**: `</svg>` が見つからなかった場合、363 行の if が偽になるので `li = j` の前進が起きず、buf は捨てられる。list にも何も積まれないため 331 行の `list.length < 4` による早期脱出も効かない。結果、コンテンツ N 行のうち `<svg` で始まる行が k 本あると、1 回の render で O(k×N) の文字列走査と N 要素配列の確保が k 回走る。render() は applySnap から毎スナップショット無条件に呼ばれる(F-002)ので、これが 1 打鍵ごとに繰り返される。

**再現条件**: 1. `# a` の次に空行、その後に `<svg` だけの行を 30000 行並べた .md を作る(`</svg>` はどこにも書かない)。
2. mmm にドロップして開く → 初回 render で数十秒〜完全フリーズ(30000^2/2 ≒ 4.5×10^8 回の includes と、3万要素配列の 3 万回確保)。
3. 開けた場合でも md ペインで 1 文字打つたびに同じ時間かかる。

**確度**: 確定

**検証の根拠**: src/mindmap.ts:359 の引用は正確。`</svg>` が無い場合 while は最終行まで走り、363 行の `if (buf[buf.length - 1].includes("</svg>"))` が偽になるので `li = j` は実行されず、外側 for (:331) は li++ で 1 行しか進まない。list には何も push されないので `list.length < 4` の早期脱出も効かない (:331)。1 ノードの本文全体が 1 回の doc.slice/split (:330) で lines に入る (cEnd = n.subEnd, :325-327) ため、k 本の `<svg` 行 × N 行 = O(N^2) の includes と、平均 N/2 要素の配列を k 回確保する。render は applySnap から無条件 (src/main.ts:198) なので 1 打鍵ごとに再発する。F-002 とは独立の、ノード数非依存な原因である点も正しい。

**影響**: 信頼できない .md を「開いただけ」でタブが応答不能になる(DoS)。HTML 断片を下書きに貼っただけの善意のファイルでも踏む。F-002 はノード数に対する render コストの指摘だったが、これはノード 1 個でも成立する別原因。

**修正方針**: 閉じフェンスが見つからなかった場合も `li = j` に進めて再走査を防ぐ。加えて走査幅に上限(例 200 行)を設ける。

### P5-3 / 検証済(CONFIRMED) / `src/mindmap.ts:646`

**リンクカードの遷移先 URL がどこにも表示されない(2 個目の `<title>` が無効化されている)ため、表示名詐称のままワンクリックで開く**

```
g.append(title, tt, open);
```

**症状**: g には既に 615 行で `g.append(label, t)` によりノードラベルの `<title>` が入っている。SVG では container 要素の最初の `<title>` 子だけがツールチップとして使われる仕様なので、636-637 行で作った URL 用の `tt` は永久に表示されない(コード行の言語表示 673-675 は rect 自身の子なので動く、という対比からもこれは意図と食い違っている)。結果、カードに見えるのは .md が指定した任意タイトルだけで、実際の遷移先を確認する手段がマップ側に一切無い。にもかかわらず 1249-1254 の click ハンドラは確認なしの単発クリックで window.open する。

**再現条件**: 1. `# a` の下に `[社内ポータル](https://evil.example.com/login)` と書いた .md を開く。
2. カードには「社内ポータル」とだけ表示される。タイトル文字の上でも、カードのどこでも、ホバーして出るツールチップは「a」(ノードラベル)で、URL は出ない。
3. 右端の ↗ を 1 回クリックすると evil.example.com が開く。

**確度**: 確定

**検証の根拠**: src/mindmap.ts:613-615 で `const t = svgEl("title"); t.textContent = n.label; g.append(label, t);` が先に g の最初の `<title>` 子を作る。646 行の `g.append(title, tt, open)` の tt (URL, :636-637) は 2 個目なので、SVG のツールチップ規則 (最初の title 子のみ) で使われない。対比として指摘どおりコード行の言語 title は rect 自身の子 (:672-676) なので動く。link-row の `<text>` 自体は title 子を持たないので、ホバーは祖先 g の最初の title = ノードラベルを出す。単発クリックで開くのも src/mindmap.ts:1249-1254 のとおり。

**検証による訂正**: 影響が過大。「遷移先を確認する手段が一切無い」のはマップ側だけで、`[title](url)` の生テキストは隣の md ペインに常に見えている。またガードはある: parseLink (src/mindmap.ts:119-140) は `https?://` のみ通し、window.open は `noopener` 付き (:1253)。したがってこれは「意図されたURLツールチップが死んでいる (tt が dead code)」という UI 欠陥であり、フィッシングとして成立するのは md ペインを隠している場合 (btn-view-md, src/main.ts:945) に限られる。

**影響**: 他人からもらった .md でのフィッシング。parseLink が javascript:/data: を弾いているので任意コード実行にはならないが、遷移先の詐称は完全に成立する。ローカル専用アプリでも「信頼できない .md を開く」経路がある以上、実害のある信頼境界の破れ。

**修正方針**: tt を g ではなく `open`(と `title`)の子として append する。併せて `title.textContent` にホスト名を併記する(例 `${r.link.title} — ${r.link.host}`)。

### P5-4 / 検証済(CONFIRMED) / `src/main.ts:696`

**永続化されたフォルダ許可がドキュメント単位でなく、untrusted .md を開いた「最初のクリック」で無言で復活する**

```
(await dh.requestPermission({ mode: "read" })) === "granted");
```

**症状**: dirHandle は IndexedDB の "dir" キー 1 個のみで、どの md に紐づく許可なのかの検査が無い。loadAsset は `dir.resolve(fileHandle)` が通りさえすれば読む(main.ts:650)ので、一度お絵描き保存のために `D:\notes` を readwrite 許可すると、その配下に置かれた「任意の」md がその後ずっと配下のファイルを読める。しかも読み取りのトリガは unlockAssets = window の capture 段 pointerdown なので、ユーザーから見れば「アプリのどこかを最初にクリックしただけ」で、.md の中身が原因だと分からない。「今後も許可」済みならプロンプトすら出ない。

**再現条件**: 1. 適当な .md を `D:\notes` に保存し、マップで D キー → お絵描きを確定してフォルダ許可ダイアログで `D:\notes` を選び「今後も許可」する。
2. ブラウザをリロード(main.ts:1122-1133 で dirHandle が IndexedDB から復元される)。
3. `D:\notes\evil.md`(内容は `# a` と `![](./任意のファイル)`)を開く。
4. マップの空白を 1 回クリックする → 追加のダイアログ無しでそのファイルが読み込まれ、assetUrls に blob URL が入る(DevTools の Application > IndexedDB と、ノードに画像が出るかで確認できる)。

**確度**: 確定

**検証の根拠**: src/main.ts:696 の引用は正確 (unlockAssets 内)。許可は IndexedDB の "dir" 1 キーのみ (src/main.ts:716 で put、:1122-1133 で復元) で、md との紐づけ検査は無い。loadAsset の唯一のスコープ検査は assetSegs の `dir.resolve(fileHandle)` (src/main.ts:646-652) だけなので、配下に置かれた任意の md が配下を読める。トリガが window の capture 段 pointerdown なのも :701 のとおり。

**検証による訂正**: (a) これは独立した欠陥というより指摘 1 の到達条件の分析で、実質同一の根本原因 (loadAsset のスコープ検査が dir.resolve だけ) を別角度から述べたもの。(b) 「最初のクリック」は必須ではない: 「今後も許可」なら loadAsset 内の queryPermission (src/main.ts:657) が granted を返し、クリック前の render 時点で読まれる。unlockAssets が要るのは許可が "prompt" 状態のときだけ。(c) 追加の観察: src/main.ts:697 は許可が拒否された場合でも removeEventListener を実行するので unlockAssets は一度きり — 以後どの md でも保留サムネイルは再試行されない。

**影響**: 上の 1 件目(SVG への任意ファイル埋め込み)の到達条件が「過去に一度でも画像機能を使ったことがある」だけに下がる。許可のスコープがユーザーの想定(「この図を保存するための許可」)より遥かに広い。

**修正方針**: 許可を md 単位で紐づける(fileHandle 名 + dir.resolve 結果をキーに IndexedDB へ保存し、一致しなければ再取得)。あるいは loadAsset を md と同一ディレクトリ配下に限定し `..` を一切許可しない。

### P5-5 / 検証済(CONFIRMED) / `src/main.ts:1114`

**開いた untrusted .md の本文が localStorage に残り、次回起動時にファイルを開き直さなくても復元・再実行される**

```
loadText(storedText ?? SAMPLE, storedName ?? "無題.md");
```

**症状**: applySnap の末尾で schedulePersist() が常に呼ばれ、本文が localStorage の `mmm.text` に書かれる(main.ts:105)。起動時はこの値が無条件に復元されるため、ユーザーがファイルを閉じたつもりでも untrusted な本文と、その中の `![](...)` 行が毎回復活する。同意は最初にファイルを開いた 1 回だけで、以後は無言。

**再現条件**: 1. 上の 4 件目の状態(dir 許可済み)にする。
2. `evil.md` を開き、そのまま数百 ms 待つ(applySnap → schedulePersist で書き込まれる)。DevTools > Application > Local Storage の `mmm.text` に本文が入っていることを確認。
3. タブを閉じて開き直す。ファイルを開いていないのに evil.md の本文とファイル名(`mmm.fileName`)が復元される。
4. 適当にクリックすると unlockAssets が走り、ローカルファイル読み取りが再発する。

**確度**: 確定

**検証の根拠**: src/main.ts:1114 の引用は正確。applySnap 末尾で無条件に schedulePersist (:203) → persistNow が `localStorage.setItem(LS_TEXT, core.getText())` (:105)、250ms デバウンス (:110-113) と pagehide (:115)。boot は :1110-1114 で storedText を無条件復元し、LS_SAVED/LS_NAME も loadText で書かれる (:483-484)。handle も名前一致なら復元される (:1119) ので、リロード後に loadAsset の前提 (fileHandle) が揃う点も正しい。

**検証による訂正**: 「ファイルを閉じたつもりでも」という前提は成立しない — このアプリに「閉じる」操作は存在せず、開く/ドロップで置き換えるだけ。正確には「最後に開いた本文が常に自動復元される」。また localStorage 書き込みは try/catch (src/main.ts:104-108) なので ~5MB 超の本文は静かに永続化されない: 影響で挙げた「指摘 2 の固まる .md が居座る」は 3 万行 `<svg` (約 150KB) なら成立するが、大きい untrusted ファイル一般には言えない。

**影響**: 信頼できない .md の影響が「開いている間」で終わらない。上の 2 件目(固まる .md)も、一度 render が完走してしまえば localStorage に居座り、以後の起動が毎回重くなる。

**修正方針**: 起動時の復元を「前回の内容を復元しますか」の明示確認にするか、少なくとも復元時は画像行の自動解決(loadAsset)を行わず、ユーザーが同じファイルを開き直したときだけ有効にする。

### P5-6 / 検証済(CONFIRMED) / `index.html:3`

**CSP がどこにも無く、オリジンに readwrite の FileSystemDirectoryHandle が常駐している**

```
<head>
```

**症状**: index.html の head(3-8 行)は charset / viewport / title / favicon だけで CSP meta が無く、vite.config.* も存在しないので配信ヘッダにも CSP が無い(既存の audit/MAP.md:36 も「CSP なし」と記録している)。現時点で HTML パースされる sink は無く、インライン `<svg>` も image 参照なので script は動かないが、その「動かない」根拠がブラウザの secure static mode 一枚だけになっている。一方このオリジンには localStorage の本文と、IndexedDB に FileSystemFileHandle および mode:"readwrite" の FileSystemDirectoryHandle(main.ts:515, 716)が常駐している。

**再現条件**: 1. `index.html` を開き、head 内に Content-Security-Policy meta が無いことを確認。
2. プロジェクト直下に vite.config.* が無いことを `ls` で確認(素の vite はセキュリティヘッダを付けない)。
3. `pnpm dev` の DevTools > Network で document のレスポンスヘッダに CSP が無いことを確認。

**確度**: 確定

**検証の根拠**: index.html:3-8 は charset / viewport / title / favicon のみで CSP meta 無し (実読で確認)。プロジェクト直下および 1 階層下に vite.config.* は存在しない (ディレクトリ列挙で確認、package.json も素の `vite` を dev/build に使用)。src/*.ts 内の HTML sink は mindmap.ts:250 の静的文字列 innerHTML 1 箇所のみ (innerHTML/outerHTML/insertAdjacentHTML/document.write/eval/new Function を全探索して他に無し)。IndexedDB に handle (src/main.ts:515) と mode:"readwrite" の dir (src/main.ts:714-716) が常駐するのも事実。

**検証による訂正**: (a) 引用箇所が `<head>` の 1 行だけなのは弱い — 正確な主張は「index.html:3-8 に CSP meta が無い」。(b) 参照している audit/MAP.md の「CSP なし」記述は 36 行目ではなく 30 行目 (index.html の表行)。(c) これは再現可能な症状を持つ欠陥ではなく多層防御の欠落であり、現時点で悪用可能な sink は存在しない — 指摘 6 自身が「単体では脆弱性ではない」と書いているとおり、トリアージ上は hardening 項目として扱うべき。

**影響**: 単体では脆弱性ではないが、他の全指摘の被害上限を押し上げる。将来 innerHTML 系の sink が 1 つでも増えるか、依存(CodeMirror 等)に HTML sink が入ると、XSS がそのまま「ユーザーのフォルダへの書き込み」に到達する。ローカル専用アプリだからこそ権限が強い。

**修正方針**: index.html に `default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' blob: data:; connect-src 'self' blob:; frame-src 'none'; object-src 'none'` 相当の meta CSP を入れる(dev は vite の HMR に合わせて緩める)。

### P5-7 / 検証済(CONFIRMED) / `src/mindmap.ts:658`

**インライン `<svg>` の join + encodeURIComponent が毎レンダリング走る(F-002 のノード数非依存な新しい増幅要因)**

```
`data:image/svg+xml;charset=utf-8,${encodeURIComponent(r.markup)}`,
```

**症状**: markup は 364 行の `buf.join("\n")` で毎 render 作り直され、658 行で毎回 percent-encode される。メモ化は無い。2 MB のインライン SVG を 1 個貼るだけで、1 render あたり 2 MB の join と約 6 MB の新規文字列生成が発生する。render は毎スナップショット呼ばれるので 1 打鍵ごと。

**再現条件**: 1. `# a` の下に 2 MB 程度の 1 個の `<svg>…</svg>`(パス多数の図など)を貼った .md を開く。
2. md ペインで文字を連打する → 1 打鍵ごとに数百 ms 以上のフリーズ。DevTools > Performance で encodeURIComponent と String.join が支配的であることを確認できる。

**確度**: 確定

**検証の根拠**: src/mindmap.ts:658 の引用は正確。markup は毎 render で :364 の `buf.join("\n")` から作り直され、:656-659 で毎回 percent-encode される。CardRow は render のローカル変数 contentRows (:314) に作られるだけでメモ化は無く、render は applySnap から無条件に呼ばれる (src/main.ts:198)。よって「1 打鍵ごとに全量再計算」という機構は成立する。

**検証による訂正**: encodeURIComponent が唯一/支配的なコストという点は未検証。同じ render は :330 で `doc.slice(cStart, cEnd).split(/\r?\n/)` を各ノードの本文全体に対して行っており (これは `<svg` 有無に関係なく O(本文長))、さらに数 MB の data: URL を setAttribute するたびにブラウザが SVG 画像を再デコード/再ラスタライズする。「約 6 MB の新規文字列生成」も実測ではなく見積り。指摘の骨子 (メモ化が無く毎 render 再計算) は正しいので、DevTools Performance で内訳を取り直した上で扱うべき。

**影響**: F-002 と同じ render 経路だが、原因がノード数ではなくコンテンツ長なので新しい consequence。ノード 1 個でも入力が実用不能になる。信頼できない .md でも、自分で貼った大きな図でも起きる。

**修正方針**: markup → data URL を (nodeId, コンテンツの範囲/ハッシュ) でメモ化する。根本的には CardRow の生成をテキスト変更時だけに限定する。

### P5-8 / 検証済(CONFIRMED) / `src/main.ts:860`

**D&D / ファイルオープンが拡張子しか見ずに全文をメモリへ読む**

```
if (!f || !/\.(md|markdown|txt)$/i.test(f.name)) return;
```

**症状**: サイズ上限もバイナリ判定も無く、876 行で `await f.text()` する。openFile() (main.ts:525, 535) も同様。拡張子を .txt にリネームしたバイナリでも、NUL やロンサロゲートを含んだまま core に渡り、そのまま localStorage 永続化まで進む。

**再現条件**: 1. 1 GB のダミーファイルを `big.txt` として作る(例: `fsutil file createnew big.txt 1073741824`)。
2. mmm のウィンドウにドロップする → タブが長時間フリーズするか、メモリ不足で落ちる。

**確度**: 確定

**検証の根拠**: src/main.ts:860 の引用は正確で、サイズ上限もバイナリ判定も存在しない。ドロップ経路は続けて `savedText = await f.text()` → loadText → core.initDoc → render → localStorage 永続化まで一直線 (src/main.ts:870-877)。openFile も同様に全文読み (:525, :536)。

**検証による訂正**: 行番号と症状の両方に誤りがある。(a) ドロップ経路の `await f.text()` は 876 行ではなく src/main.ts:874、FS API 無し経路は 535 行ではなく src/main.ts:536 (:535 は `fileHandle = null;`)。(b) 1GB の再現は記述どおりにはならない公算が大きい: 1e9 文字は V8 の最大文字列長 (~536M 文字) を超えるので f.text() は読み込み後に reject し、しかもドロップ側の IIFE (src/main.ts:870-877) には .catch が無い (openFile の try/catch :543-548 と非対称) ため、unhandled rejection で「読み込み失敗」の表示すら出ず無言で終わる。実際にフリーズまで到達させたいなら ~200MB 程度の .txt を使うべき。この「無言の unhandled rejection」自体が本指摘に付随する新しい観察。

**影響**: 誤ドロップでも起きる可用性の問題。信頼できないファイルを受け取る最初のゲートがここなので、以降の全処理の入力サイズがここで無制限になっている。

**修正方針**: `f.size` に上限(例 32 MB)を設けて超過時は flashFilename で拒否し、読み込み後に NUL 等の制御文字を検出したら読み込みを中止する。

### P5-9 / 検証済(CONFIRMED) / `src/mindmap.ts:107`

**untrusted な文字列をキーにした無制限キャッシュ(eviction が無い)**

```
const widthCache = new Map<string, number>();
```

**症状**: widthCache は font+文字列をキーに増え続けるだけで、eviction もファイル切り替え時のクリアも無い(clearAssets は assetUrls しか触らない)。ラベル・コード行・リンクタイトルの全異種文字列が永久に残る。同様に main.ts:629 の assetUrls は、存在しないパスに対して null エントリを積み続け(main.ts:638 で必ず set される)、こちらもファイル切り替え以外では縮まない。

**再現条件**: 1. `# ` + 連番で 50 万個の異なる見出しを持つ .md を生成して開く。
2. DevTools > Memory でヒープスナップショットを取ると widthCache の Map エントリが見出し数ぶん残っていることを確認できる。ファイルを別の .md に切り替えても解放されない。

**確度**: 確定

**検証の根拠**: src/mindmap.ts:107 の引用は正確。widthCache への参照はファイル内で :107 宣言 / :110 get / :114 set のみで、eviction もクリアも存在しない (measure 内に閉じている)。clearAssets (src/main.ts:631-634) は assetUrls だけを revoke/clear し widthCache に触れない。assetUrls が存在しないパスにも null エントリを積み続けるのも事実。

**検証による訂正**: assetUrls に null が入るのは src/main.ts:639 (`assetUrls.set(path, null);`) で、指摘の :638 は `if (hit !== undefined) return hit;` の早期 return 行。また補足として clipLabel (src/mindmap.ts:731-744) が二分探索で measure を呼ぶため、MAX_LABEL_W を超えるラベル 1 個につき本体 + 約 log2(長さ) 個の余分なキーが増える。再現手順の「50 万見出し」はそのままでは使えない (F-002 によりその規模では render 自体が完了しない) — 通常サイズの .md でラベル編集を大量に繰り返し、ヒープ上の widthCache エントリ数が単調増加することを見る方が確実。

**影響**: 実害はメモリ膨張のみだが、増加量が完全に .md の内容で決まるため、untrusted ファイル + 長時間セッションで効いてくる。

**修正方針**: widthCache に上限(例 20000 エントリ)を設けて超過時にクリアする、あるいは render 中に使われたキーだけを残す世代管理にする。

### P5-10 / 検証済(要確認) / `src/main.ts:788`

**クリップボード画像の MIME が IMG_EXT に無いと .png として保存される(拡張子と中身の型混同)**

```
const ext = IMG_EXT[out.type] ?? "png";
```

**症状**: pasteImage の選別は `t.startsWith("image/")` (main.ts:390) なので image/svg+xml や image/avif も通る。WebP 再エンコードは createImageBitmap が失敗すると 784 行の catch で素通りするため、元のバイト列がそのまま `name.png` としてユーザーのフォルダに書き込まれ、md には `![](./name.png)` が入る。

**再現条件**: 要確認: Chrome の navigator.clipboard.read() は unsanitized オプション無しでは image/png しか露出しない可能性が高い。決着させる観察 — DevTools コンソールで、SVG をコピーした状態で `(await navigator.clipboard.read())[0].types` を評価し、image/png 以外(特に image/svg+xml)が返るかを見る。返れば上記の経路が成立し、返らなければ現実的に到達不能と確定できる。

**確度**: 要確認

**検証の根拠**: コード側は確認できる: 選別は `item.types.find((x) => x.startsWith("image/"))` (src/main.ts:389 — 指摘の 390 は 1 行ずれ)、WebP 再エンコード失敗は素通り (src/main.ts:776-786 の catch)、拡張子は `IMG_EXT[out.type] ?? "png"` (src/main.ts:788)。しかし到達可能性はコードでは決着しない。決着させる観察: DevTools コンソールで SVG をコピーした状態で `(await navigator.clipboard.read()).flatMap(i => i.types)` を評価する。Chrome の sanitized read は text/plain / text/html / image/png のみを露出し、カスタム形式は "web image/svg+xml" のように "web " 接頭辞が付く (それだと src/main.ts:389 の startsWith("image/") を通らない) ため、現実には到達不能な可能性が高い。仮に非 png の `image/*` が返った場合は、さらに `createImageBitmap(blob)` (src/main.ts:776) がその型で reject することも確認する必要がある — 成功すると WebP に再エンコードされて食い違いは起きない。両方が満たされて初めて成立する。

**影響**: 到達した場合でも被害は「拡張子と中身が食い違うファイルがユーザーのフォルダに書かれる」まで。mmm 内では blob の type が image/png になるため描画に失敗するだけで、スクリプト実行には至らない。

**修正方針**: IMG_EXT に無い type は保存を拒否する(flashFilename で通知)。少なくとも image/svg+xml は明示的に除外する。

---

## 領域: 永続化 (localStorage / IndexedDB / File System Access) — src/main.ts の persistNow・schedulePersist・loadText・saveFile・openFile・drop・idb・dirHandle 権限復帰

**調べたもの**

- src/main.ts 全 1135 行を Read で通読（切り詰めなし、wc -l で 1135 行を確認）
- src/fs-access.d.ts 全 64 行（queryPermission/requestPermission/resolve の宣言、SaveFilePickerOptions に id/startIn が無いこと）
- src/coreApi.ts（core.getText() が毎回 MoonBit 側から全文を取り出す境界であること）
- index.html（#dirty / #filename / #btn-save の存在、module script の読み込み位置）
- grep -a で localStorage / indexedDB / sessionStorage / BroadcastChannel を src/*.ts 全体に対して検索 → ヒットは main.ts のみ。editor.ts / mindmap.ts / popup.ts / relevel.ts は永続化に一切触れない
- grep -a で pagehide / visibilitychange / beforeunload / freeze / unload を検索 → pagehide(115) と beforeunload(850) の 2 つだけ。visibilitychange と freeze は未購読
- src/style.css の :root で --accent / --accent-soft のデフォルト値が定義されていることを確認（applyColor 早期 return 時の退避先）
- 永続化キーの全書き込み箇所（105, 146, 483, 484, 585, 586, 929, 1081）と全読み出し箇所（1096, 1100, 1102, 1111, 1112, 1113）を突き合わせ
- IndexedDB キー "handle" / "dir" の書き込み（515, 716, 768）と読み出し（1115, 1122）を突き合わせ
- dirty 判定（207 updateDirty）と savedText を書き換える全経路（525, 538, 582, 874, 1113）を突き合わせ
- beforeunload(850) / confirmDiscard(612) が savedText のみに依存し fileHandle の有無を見ていないことを確認

### P5-1 / 検証済(CONFIRMED) / `D:/1.atrium/mmm/src/main.ts:483`

**localStorage の3キーが非原子的に書かれ「前の文書 × 新しいファイル名 × 新しいハンドル」で復元される**

```
localStorage.setItem(LS_NAME, name);
    localStorage.setItem(LS_SAVED, savedText);
```

**症状**: loadText() は mmm.fileName と mmm.savedText を即座（同期）に書き換えるが、本文 mmm.text は applySnap → schedulePersist(203) 経由で 250ms 後にしか書かれない。この間にプロセスが死ぬと、localStorage には「新ファイルの名前と新ファイルのディスク内容」＋「前の文書の本文」という矛盾した組が残る。起動時(1119)のハンドル採用条件は h.name === fileName の名前一致だけなので、新ファイルのハンドルがそのまま採用される。

**再現条件**: 1) mmm で文書 A を編集中にする。2) Ctrl+O で別のファイル B.md を開く。3) 開いた直後（250ms 以内）に DevTools → Application → Local Storage を見る。mmm.fileName="B.md"、mmm.savedText=B のディスク内容、mmm.text=A の本文、という状態が観測できる。窓を広げたいなら開いた直後に md ペインでキーを押しっぱなしにする（F-005 参照: デバウンスに max-wait が無いので押している限り mmm.text は永久に更新されない）。4) キーを押したまま Shift+Esc の Chrome タスクマネージャでタブのプロセスを End process する（pagehide が飛ばない）。5) 再読み込みすると、タイトルバーは B.md、本文は A、dirty ● 点灯、IDB の B ハンドルが採用済み。6) Ctrl+S を押すと B.md の中身が A で上書きされる。

**確度**: 確定

**検証の根拠**: main.ts:483-484 は loadText 内で同期に LS_NAME/LS_SAVED を書くが、LS_TEXT の唯一の書き手は main.ts:105 の persistNow で、loadText:480 の applySnap → main.ts:203 schedulePersist → main.ts:112 の 250ms トレーリングタイマー経由でしか呼ばれない。復元側 main.ts:1111-1114 は 3 キーを独立に読み、main.ts:1119 の採用条件は h.name === fileName だけ。ハンドル永続化は main.ts:527 persistHandle で開いた直後に走るので IDB 側は新ファイルを指す。

**検証による訂正**: 「無警告」は言い過ぎ。復元後は core.getText()(=A) !== savedText(=B のディスク内容) なので main.ts:207 で dirty ● が点灯し、beforeunload(850-853) と confirmDiscard(612-615) は鳴る。無警告なのは Ctrl+S を押した瞬間だけで、しかも復元ハンドルは prompt 状態なので Chrome の編集許可プロンプトが 1 回挟まる。破壊経路自体は実在する。

**影響**: 開いたばかりの実ファイルを、無関係な前の文書で無警告に破壊する。

**修正方針**: mmm.text / mmm.savedText / mmm.fileName を 1 つの JSON 値（1 キー）にまとめて必ず同時に setItem する。加えて loadText の末尾は schedulePersist ではなく persistNow() を呼び、ファイル同一性が変わった瞬間に本文も確定させる。

### P5-2 / 検証済(CONFIRMED) / `D:/1.atrium/mmm/src/main.ts:1113`

**mmm.text と mmm.savedText の ?? フォールバックが独立していて、片方欠落でサンプル文書が実ファイルを上書きする**

```
savedText = localStorage.getItem(LS_SAVED) ?? storedText ?? SAMPLE;
  loadText(storedText ?? SAMPLE, storedName ?? "無題.md");
```

**症状**: 本文とファイル名と savedText が別々のキーから別々の既定値で復元される。mmm.text だけ失われると「本文＝SAMPLE、名前＝実ファイル名、savedText＝実ファイルのディスク内容」になり、dirty ● が点いた状態でハンドルまで採用される。逆に mmm.savedText だけ失われると savedText = storedText となり、ディスクと違う文書が永久に「保存済み」扱いになる（しかも loadText:484 がその値を書き戻すので固定化する）。

**再現条件**: A) 1) Ctrl+O で ~/notes.md を開いて編集し保存する。2) DevTools → Application → Local Storage で mmm.text のキーだけ削除する。3) リロード。画面は mmm のサンプル文書、タイトルは notes.md、dirty ● 点灯、IDB ハンドルは名前一致で採用済み。4) Ctrl+S → notes.md がサンプル文書で上書きされ元の内容は復元不能。 B) 同じ状態で mmm.savedText だけ削除してリロードすると、ディスクと異なる本文なのに dirty ● が消え、beforeunload の警告も出ず、Ctrl+O の confirmDiscard(613) も確認なしで破棄する。

**確度**: 確定

**検証の根拠**: main.ts:1113 `savedText = localStorage.getItem(LS_SAVED) ?? storedText ?? SAMPLE;` と main.ts:1114 `loadText(storedText ?? SAMPLE, storedName ?? "無題.md");` は引用どおりで、3 値が別キー・別既定値から組み上がる。ケース B の固定化も main.ts:484 が loadText 内で savedText をそのまま LS_SAVED に書き戻すため成立する。main.ts:1119 のハンドル採用は名前一致のみ。

**検証による訂正**: 「1 キーだけ欠落」という引き金は DevTools 手動削除など特殊で、ブラウザのエビクションはオリジン単位なので通常は 3 キーとも消える(→ 全部 SAMPLE で無害)。実運用で同じ誤結合を作るのは所見 1/6/7 の「片方だけステール」経路であり、この所見の価値は独立フォールバック設計そのものの指摘にある。

**影響**: localStorage の 1 キー欠落だけでファイル破壊、または保存漏れの取りこぼしに直行する。

**修正方針**: 3 値を 1 つのレコードとして読み書きし、レコードが不完全なら fileName とハンドルを破棄して「無題」から起動する（実ファイルとの結び付きを絶つ）。

### P5-3 / 検証済(CONFIRMED) / `D:/1.atrium/mmm/src/main.ts:1119`

**復元したハンドルでディスクを一度も読み直さないため、外部エディタの変更を無警告で消す**

```
if (h && h.name === fileName) fileHandle = h;
```

**症状**: 起動時に採用したハンドルに対して getFile() も lastModified の比較も一切行わない。savedText は localStorage 由来の「前回セッション時点のディスク内容」であり、実際のディスクの現在値ではない。したがって外部で更新されたファイルでも core.getText() === savedText が成立し、dirty ● は消えたまま、beforeunload も confirmDiscard も黙る。

**再現条件**: 1) mmm で ~/notes.md を開き（FS ピッカー）、そのままタブを閉じる。2) VS Code など別エディタで notes.md に段落を 1 つ追記して保存する。3) mmm を開き直す。localStorage から古い本文が復元され、タイトルは notes.md、dirty ● は消灯（＝「ディスクと同じ」という誤った表示）。ここで mmm はファイルを一度も読んでいない。4) 文字を 1 つ打って Ctrl+S。手順 2 の追記は消える。

**確度**: 確定

**検証の根拠**: main.ts:1115-1121 のブートは idbGet("handle") の結果を fileHandle に代入するだけ。main.ts 全体で getFile() は 523(openFile) と 676(loadAsset の画像) の 2 か所しかなく、lastModified は 1 度も現れない(grep -a 済み)。savedText は main.ts:1113 の localStorage 由来なので、main.ts:207/613/852 の 3 判定はすべて「前回セッションのディスク内容」を基準にする。

**影響**: mmm 外での編集が毎回無言で失われる。ローカル専用エディタとして最も踏みやすい経路。

**修正方針**: 起動時にハンドルを採用したら getFile() で lastModified と内容を読み、localStorage の savedText と食い違う場合は「ディスク側が新しい」ことを提示して、ディスク採用／localStorage 採用をユーザーに選ばせる。保存直前にも lastModified を再確認する。

### P5-4 / 検証済(CONFIRMED) / `D:/1.atrium/mmm/src/main.ts:1096`

**起動時の localStorage.getItem が try/catch 外にあり、ストレージ禁止環境ではアプリが白画面で起動不能**

```
const stored = localStorage.getItem(LS_THEME) as Theme | null;
```

**症状**: 書き込み側（105, 146, 483, 585, 929, 1081）は全て try/catch で保護されているのに、読み出し側（1096, 1100, 1102, 1111, 1112, 1113）は 1 か所も保護されていない。localStorage プロパティのアクセス自体が SecurityError を投げる環境では、モジュール最上位の boot ブロックが例外で止まり、loadText も mapPane.focus() も実行されない。1096 はモジュール初期化中で最初の localStorage アクセス（grep -a で確認済み。editor.ts / mindmap.ts は localStorage に触れない）。

**再現条件**: 1) Chrome の 設定 → プライバシーとセキュリティ → サイトの設定 → Cookie とサイトデータ で mmm の配信元（例 http://localhost:5173）を「サイトデータの保存をブロック」に追加する。あるいは <iframe sandbox="allow-scripts"> に埋め込んで開く（オリジンが opaque になり localStorage アクセスが投げる）。2) リロード。ペインは空で何も表示されず、Console に main.ts:1096 の Uncaught SecurityError: Failed to read the 'localStorage' property from 'Window' が出る。3) 同条件で書き込みだけなら 104-108 の catch で無害に済むことと対比できる。

**確度**: 確定

**検証の根拠**: main.ts:1096/1100/1102/1111/1112/1113 の getItem はどれも try の外、対して書き込み側 105/146/483-484/585-586/929/1081 は全て try 内。localStorage 参照は src 配下で main.ts のみ(grep -a で editor.ts / mindmap.ts / popup.ts / coreApi.ts / relevel.ts はゼロ)なので 1096 が最初のアクセスで正しい。MindMap のコンストラクタ(mindmap.ts:208-262)は render() を呼ばず hint も display:none なので、例外時に両ペインが空になるのも正しい。

**検証による訂正**: 「起動不能」は誤り。例外で止まるのは 1096 以降のブートブロックだけで、UI リスナーは全て 1096 より前に登録済み(115,164,165,500,501,701,847,848,850,856,857,882,945,946,963,964,971,1066,1069,1087)。つまりトップバーは生きており「開く」ボタンや D&D からファイルを読めば main.ts:473 loadText が走って完全に復帰する。正しい症状は「両ペインが空・前回文書が復元されない・applyColor(1100) と applyPaneVis(1104) が未適用・mapPane.focus()(1135) が未実行」。

**影響**: 永続化を諦めれば動けるはずの環境で、エディタごと起動しない。

**修正方針**: localStorage アクセスを lsGet(key) / lsSet(key, v) の 2 関数に集約し、両方 try/catch で null / no-op に落とす。読み出しも例外安全にする。

### P5-5 / 検証済(CONFIRMED) / `D:/1.atrium/mmm/src/main.ts:110`

**schedulePersist に max-wait が無く、連続入力中は localStorage が一度も更新されない**

```
function schedulePersist(): void {
  if (persistTimer !== -1) window.clearTimeout(persistTimer);
  persistTimer = window.setTimeout(persistNow, 250);
}
```

**症状**: 純粋なトレーリングデバウンスで、キーストロークのたびにタイマーが破棄・再設定される。入力間隔が 250ms を切っている限り persistNow は永久に呼ばれない。コメント（114 行「don't lose the last debounce window on reload/close」）は「失うのは最後の 250ms だけ」という前提だが、実際に失いうるのは連続入力していた全期間。

**再現条件**: 1) md ペインにフォーカスして DevTools → Application → Local Storage を開いたまま、任意のキーを押しっぱなしにする（オートリピートは約 30ms 間隔）。2) mmm.text の値が 30 秒経っても一切変化しないことを確認する。3) キーを離すと 250ms 後に一度だけ更新される。4) 次にキーを押しっぱなしのまま Shift+Esc の Chrome タスクマネージャでそのタブのプロセスを End process する（pagehide が発火しない）。5) 開き直すと押しっぱなしにしていた間の入力が丸ごと消えている。

**確度**: 確定

**検証の根拠**: main.ts:110-113 は引用どおりの純トレーリングデバウンス(clearTimeout → setTimeout 250)。打鍵は editor.ts:113-142 の updateListener → main.ts:250 onUserEdits → main.ts:299 applySnap → main.ts:203 schedulePersist を毎回通るので、入力間隔が 250ms 未満の間 persistNow(99) は一度も走らない。フラッシュ経路は main.ts:115 の pagehide のみ。

**影響**: クラッシュ時の喪失量が 250ms ではなく「直近の入力バースト全部」。所見 1 の破壊窓も同じ理由で無制限に伸びる。

**修正方針**: 最初の schedulePersist 呼び出し時刻を保持し、経過が 1000ms を超えていたら debounce を無視して即 persistNow する（leading + max-wait 付き debounce）。

### P5-6 / 検証済(CONFIRMED) / `D:/1.atrium/mmm/src/main.ts:105`

**複数タブが同じ localStorage を奪い合い、storage イベントも見ていないため別タブの文書で実ファイルを上書きする**

```
localStorage.setItem(LS_TEXT, core.getText());
```

**症状**: どのタブも無条件に mmm.text を上書きし、他タブの書き込みを検知する storage イベントリスナーも、タブ所有権を示す仕組み（BroadcastChannel / Web Locks / セッション ID）も無い。しかも mmm.text を書くタブと mmm.fileName / mmm.savedText を書くタブが別々になりうるため、キー間の対応関係が壊れる。IDB の "handle" キーも全タブ共有で最後に書いた者が勝つ。

**再現条件**: 1) タブ A で mmm を開く（サンプル文書、無題.md）。2) タブ B でも同じ URL を開く（同じくサンプル、無題.md）。3) タブ A で Ctrl+O → ~/work/report.md を開き、文字を打つ。localStorage は fileName=report.md / savedText=report のディスク内容 / text=report+編集、IDB の handle=report.md になる。4) タブ B（まだサンプル文書、メモリ上の fileName は 無題.md）で文字を 1 つ打つ。250ms 後にタブ B が mmm.text をサンプル文書で上書きする。タブ B は mmm.fileName も mmm.savedText も触らない。5) タブ A をリロード（または新しいタブ C で開く）。本文＝サンプル、タイトル＝report.md、dirty ● 点灯、handle は名前一致で採用済み。6) Ctrl+S → ~/work/report.md がサンプル文書に置き換わる。

**確度**: 確定

**検証の根拠**: main.ts:105 は無条件上書き。src/*.ts 全体を grep -a しても addEventListener("storage"), BroadcastChannel, navigator.locks, sessionStorage は 1 件もヒットしない。タブ B は起動時に main.ts:1114 loadText 経由で LS_NAME/LS_SAVED を自分の値で書いた後は 105 の LS_TEXT しか触らないため、タブ A が 483-484 で書いた NAME/SAVED と組み合わさって記述どおりの誤結合になる。復元側 1119 の採用条件も名前一致のみ。

**影響**: 2 タブ開いていただけで実ファイルが無関係な内容に置換される。storage イベント未購読なので、どちらのタブにも警告が出ない。

**修正方針**: 起動時に navigator.locks か BroadcastChannel で「書き込み担当タブ」を 1 つに決め、非担当タブは永続化を止めて読み取り専用バナーを出す。最低限 storage イベントを購読し、自分が書いていない mmm.text の変化を検知したら永続化を停止して警告する。

### P5-7 / 検証済(CONFIRMED) / `D:/1.atrium/mmm/src/main.ts:104`

**QuotaExceededError が完全に沈黙し、古い localStorage が残るため「巻き戻り」になる**

```
try {
    localStorage.setItem(LS_TEXT, core.getText());
  } catch {
    /* storage full/blocked */
  }
```

**症状**: 本文を mmm.text と mmm.savedText に二重に持つため、localStorage の実効上限（Chrome は概ね 5MB を UTF-16 の 2 バイト/文字で計上 → 約 250 万文字）に対して扱えるのは半分の約 120 万文字。これを超えると setItem が投げるが、105 も 486 も 588 も catch で握り潰す。失敗しても古い値は消えないので、リロードすると「以前の文書」が復活する。flashFilename による通知も一切ない。さらに loadText:484 は起動のたびに数 MB の setItem を再試行する。

**再現条件**: 1) 約 2MB（200 万文字程度）の .md を用意する（例: 「# h」の行を 10 万行）。2) mmm を Ctrl+O で開く。3) DevTools → Application → Local Storage を見る。mmm.fileName は新ファイル名に更新されているのに（loadText:483 が先に成功する）、mmm.text と mmm.savedText は前の文書のまま（484 が QuotaExceededError で中断し catch に飲まれる）。4) 画面上には何のエラー表示も出ない。5) リロード → 前の文書が新ファイル名で復元され dirty ● 点灯、ハンドルは名前一致で採用。6) Ctrl+S で 2MB のファイルが前の文書に置き換わる。

**確度**: 確定

**検証の根拠**: main.ts:104-108 / 485-487 / 587-589 の catch は全て空で flashFilename(601) を呼ばない。本文の二重保持(LS_TEXT@105 と LS_SAVED@484,585)も事実。loadText:483 が NAME → 484 が SAVED の順なので、小さい NAME だけ成功して大きい SAVED が落ちる部分書き込みも成立する。

**検証による訂正**: 再現手順 5 の「dirty ● 点灯」は誤り。SAVED も TEXT も旧文書のまま残るので、復元後は core.getText() === savedText となり main.ts:207 で dirty ● は消灯する。つまり実際は警告表示すら出ないぶん記述より悪く、beforeunload(852) も confirmDiscard(613) も黙ったまま Ctrl+S で大きいファイルが旧文書に置き換わる。約 120 万文字という閾値はブラウザ実装依存で要実測。

**影響**: 大きめの文書では永続化が最初から効かず、しかも「保存された気になった上で巻き戻る」ため所見 1 と同じ破壊に合流する。閾値はブラウザ依存だが、二重保存で実効容量が半分になる点は確定。

**修正方針**: setItem 失敗時に古い値を removeItem して矛盾した組を残さず、flashFilename でユーザーに通知する。本文の保存先を localStorage ではなく IndexedDB（既にある mmm-store）に移し、mmm.savedText はハッシュだけ持つようにして二重保存をやめる。

### P5-8 / 検証済(CONFIRMED) / `D:/1.atrium/mmm/src/main.ts:115`

**フラッシュ経路が pagehide だけで、visibilitychange / freeze を購読していない**

```
window.addEventListener("pagehide", persistNow);
```

**症状**: デバウンス中の内容を確定させる経路はこの 1 本だけ。beforeunload(850) は persistNow を呼ばない。モバイルのバックグラウンド破棄・OOM kill・Chrome のタブ discard・OS のアプリ終了では pagehide が発火しない場合があり、その経路では所見 5 のバースト分が丸ごと消える。Page Lifecycle 的に確実なのは visibilitychange の hidden 遷移と freeze。

**再現条件**: Android Chrome で mmm を開き、md ペインで数十秒連続入力し、指を離さずにホームへ戻る。メモリ圧で該当タブが discard されるまで放置してから mmm に戻る（タブが再読み込みされる）。直前の入力バーストが失われている。デスクトップでは chrome://discards でそのタブに対し Urgent Discard を実行しても同じ観測ができる。

**確度**: 確定

**検証の根拠**: コード上の主張は完全に確定する。persistNow を呼ぶ登録は main.ts:115 の pagehide だけで、beforeunload ハンドラ(850-853)は preventDefault のみ。src 配下に visibilitychange / freeze / document.addEventListener は 1 件も無い(grep -a 済み)。

**検証による訂正**: タイトルの「購読していない」はコードで確定なので 要確認 ではなく確定扱いでよい。ただし影響欄の「discard で実際に喪失する」部分だけがブラウザ観測待ちで、決め手は chrome://discards で Urgent Discard した直後に Application → Local Storage の mmm.text が更新済みか(= pagehide が飛んだか)を見ること。

**影響**: モバイル／タブ discard 経路で編集内容が失われる。

**修正方針**: document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'hidden') persistNow(); }) と window.addEventListener('freeze', persistNow) を追加する。beforeunload(850) でも persistNow() を呼ぶ。

### P5-9 / 検証済(CONFIRMED) / `D:/1.atrium/mmm/src/main.ts:575`

**非 File System Access 環境の保存はダウンロードの成否を確認せず savedText を更新するため、偽の「保存済み」になる**

```
const a = document.createElement("a");
      a.href = URL.createObjectURL(new Blob([text], { type: "text/markdown" }));
      a.download = fileName;
      a.click();
      URL.revokeObjectURL(a.href);
    }
    savedText = text;
```

**症状**: a.click() はダウンロードの完了も、ユーザーがダイアログをキャンセルしたかも返さない。それでも無条件に savedText = text して dirty ● を消し、mmm.savedText まで書き換える(585)。以後 beforeunload(852) も confirmDiscard(613) も黙るので、未保存の変更が警告なしで捨てられる。加えて a.click() の直後に同期的に revokeObjectURL しており、Blob URL の読み出しが始まる前に失効させる典型パターンになっている。

**再現条件**: 1) Firefox（showOpenFilePicker が無いので hasFs=false になる）で mmm を開く。2) 文字を打って dirty ● を点灯させる。3) Ctrl+S。Firefox の「ファイルを保存/開く」ダイアログでキャンセルを押す。4) 何も書かれていないのに dirty ● が消える。5) Ctrl+O で別ファイルを開こうとしても「未保存の変更があります」の確認が出ず、編集内容がそのまま失われる。6) 同じ手順で保存を許可した場合に 0 バイトファイルやダウンロード失敗が起きるかは revokeObjectURL のタイミング依存（ブラウザ差あり）なので、ダウンロードしたファイルのサイズを確認して切り分ける。

**確度**: 確定

**検証の根拠**: main.ts:576-580 の <a download> 経路のあと、main.ts:582 `savedText = text;` が if/else の外で無条件に走り、583 updateDirty() が dirty ● を消し、585 が LS_SAVED まで書き換える。以後 613 confirmDiscard と 852 beforeunload はどちらも core.getText() === savedText で真になる。hasFs は main.ts:505 の "showOpenFilePicker" in window なので Firefox では false で正しい。

**検証による訂正**: 引用の開始行は 576（575 は `} else {`）、savedText 代入は 582。再現手順 3 の「Firefox の保存ダイアログでキャンセル」は既定設定では出ない(既定は Downloads へ直保存)ので、about:preferences の「ファイルごとに保存先を確認する」を有効にする必要がある。ダイアログを出さない構成でも、拡張機能によるブロックや容量不足でダウンロードが失敗すれば同じ偽「保存済み」になるため、欠陥自体は設定に依存しない。

**影響**: FS API 非対応ブラウザで dirty 表示と beforeunload 警告が信用できなくなる。

**修正方針**: revokeObjectURL を setTimeout(..., 60_000) か 'unload' まで遅らせる。非 FS 経路では savedText を更新せず「ダウンロードしました（保存先は未確認）」を flashFilename で出し、dirty ● は残す。

### P5-10 / 検証済(CONFIRMED) / `D:/1.atrium/mmm/src/main.ts:697`

**unlockAssets が許可拒否時にもリスナーを外すので、dirHandle の権限を一度 Block するとリロードするまで復帰できない**

```
window.removeEventListener("pointerdown", unlockAssets, true);
    if (ok) for (const p of pending) void loadAsset(p);
```

**症状**: removeEventListener が if (ok) の外にあるため、queryPermission が denied を返した場合も、requestPermission でユーザーが Block を押した場合も、リスナーは無条件に解除される。以後どれだけクリックしても再要求は起きず、loadAsset(657) は queryPermission !== granted で黙って return し続ける。サムネイルは空のまま、エラー表示も無い。

**再現条件**: 1) 画像を含む md（例: ![](./x.webp)）を開き、画像貼り付けでフォルダ許可を一度与えて mmm.dir を IDB に永続化する。2) タブを閉じて開き直す（復元したディレクトリハンドルの権限は通常 prompt 状態）。3) 画面のどこかを 1 回クリックすると Chrome の「このサイトにファイルの表示を許可しますか？」が出る。ここで「ブロック」を押す。4) サムネイルは空のまま。以後何度クリックしても二度とプロンプトは出ない（リスナーが外れている）。5) F5 でリロードすると再びチャンスがあるが、同じ操作で同じ袋小路に入る。

**確度**: 確定

**検証の根拠**: main.ts:697 の removeEventListener は 698 の `if (ok)` の外にあり、691-699 の async IIFE 内で権限結果に関わらず必ず実行される。以後 loadAsset は main.ts:657 の queryPermission !== granted で return し、エラー表示は無い。復帰不能の裏取りも取れる: imageUrl(636-641)は null を「解決済みの値」としてキャッシュして返すので再試行せず、ensureImageDir(704-718)で許可を取り直しても既存の pending サムネイルを再読込するコードは無い(再試行ループは 1128-1130 のブート時と 698 の 2 か所だけ)。

**検証による訂正**: 「ブロックを押す」操作すら不要な経路がある。ハンドルが denied 状態で復帰した場合、694-696 の条件が q==="prompt" のときしか requestPermission を呼ばないため、最初の pointerdown でプロンプトも出ないままリスナーだけが外れる。

**影響**: 許可の押し間違い 1 回で、そのセッション中は画像が一切表示できなくなる。復帰手段が UI 上に存在しない。

**修正方針**: removeEventListener を if (ok) の内側に移す。加えて権限が denied のときは flashFilename で「画像フォルダの許可がありません」を出し、明示的な再要求ボタン（トップバー）を用意する。

### P5-11 / 検証済(CONFIRMED) / `D:/1.atrium/mmm/src/main.ts:524`

**openFile / drop が await の前に fileHandle を差し替え、読み込み失敗時に「旧文書 × 新ファイルのハンドル」で残る**

```
fileHandle = h;
      savedText = await f.text();
      loadText(savedText, f.name);
```

**症状**: fileHandle の代入が await の前にあるため、f.text() が失敗すると savedText も loadText も実行されず、fileHandle だけが新しいファイルを指したまま残る。openFile は catch(543) で「読み込み失敗」を出すが fileHandle は戻さない。drop 側(873-875)は同じ順序に加えて async IIFE(870)に .catch が無いため、unhandled rejection になって表示すら出ない。しかも savedText は旧値のままなので core.getText() === savedText が成立し dirty ● は点かず、Ctrl+S が無警告で新ファイルを旧文書で上書きする。

**再現条件**: 1) DevTools → Sources で main.ts:874（savedText = await f.text() の行）にブレークポイントを置く。2) 別ファイル B.md をウィンドウにドラッグ＆ドロップする。3) 停止したらエクスプローラで B.md を削除（またはリネーム）する。4) 再開すると f.text() が NotFoundError で reject し、Console に unhandled rejection が出る。画面は前の文書のまま、dirty ● も消灯。5) B.md を戻して Ctrl+S を押すと B.md が前の文書で上書きされる。ネットワークドライブ上のファイルをドロップして直後に切断しても同じ状態になるはず。

**確度**: 確定

**検証の根拠**: main.ts:524 `fileHandle = h;` は 525 `savedText = await f.text();` より前で、catch(543-548) は fileHandle を戻さない。drop 側も main.ts:873 → 874 で同順、かつ 870 の async IIFE には .catch が付いていない(比較: paste 側 main.ts:423 は `})().catch(() => {});` で握っている)ので unhandled rejection になる。savedText が旧値のままなので 207(dirty)/613(confirmDiscard)/852(beforeunload) の 3 判定が全て「変更なし」になり、次の Ctrl+S(551) が新ハンドルへ旧文書を書く。

**影響**: 読み込み失敗が「別ファイルへの無警告な上書き権限」に化ける。drop 側は例外が握り潰されるので気付く手掛かりが無い。

**修正方針**: fileHandle の代入を f.text() 成功後（loadText の直前）に移す。drop の IIFE に .catch を付け、失敗時は flashFilename で通知しつつ fileHandle を元の値に戻す。

### P5-12 / 検証済(CONFIRMED) / `D:/1.atrium/mmm/src/main.ts:72`

**idbConn が接続オブジェクトを永久キャッシュし、接続が閉じると以後すべての永続化が沈黙して二度と回復しない**

```
idbConn ??= new Promise((resolve, reject) => {
    const req = indexedDB.open("mmm-store", 1);
```

**症状**: idbConn は一度解決した IDBDatabase を（あるいは reject した Promise を）ページの生存期間ずっと保持する。db.onversionchange も onblocked も未処理なので、ブラウザ側で接続が強制クローズされると db.transaction("kv") が InvalidStateError を同期的に投げ、idbSet/idbGet は reject し、呼び出し側(515, 716, 768)の .catch(() => {}) が全部飲み込む。再接続の試行は無い。onupgradeneeded も objectStoreNames.contains("kv") を確認せず createObjectStore する。

**再現条件**: 1) mmm を開き、Ctrl+O でファイルを開く（IDB に handle が入る）。2) DevTools → Application → IndexedDB → mmm-store で「Delete database」を実行する（開いている接続に versionchange が飛び、接続が閉じられる）。3) タブはそのまま。もう一度 Ctrl+O で別ファイルを開く。persistHandle()(515) は静かに失敗し、Console にも画面にも何も出ない。4) リロードすると handle が復元されず、Ctrl+S が「名前を付けて保存」ピッカーを開く（保存先を見失っている）。5) 画像フォルダの許可も同様に毎回聞き直しになる。

**確度**: 確定

**検証の根拠**: main.ts:70-79 の `idbConn ??=` は解決済み/reject 済みのどちらの Promise も保持し続け、再接続コードは存在しない。db.onversionchange / req.onblocked は未設定、74 の onupgradeneeded も objectStoreNames.contains("kv") を確認しない。呼び出し側は 515 / 716 / 768 / 1115 / 1122 が全て .catch(() => {}) で沈黙する。

**検証による訂正**: 再現手順 2 が不正確。onversionchange を実装していないため接続が閉じられず、DevTools の「Delete database」は blocked のままペンディングになり接続は生き続ける(=persistHandle は成功してしまう)。確実な引き金は Application → Storage の「Clear site data」、ブラウザによる強制クローズ/エビクション、あるいは indexedDB.open 自体が失敗する環境(reject した Promise が 72 行の ??= に焼き付き、以後 idbSet/idbGet が永久に失敗する)。なお onversionchange 欠落そのものも別の欠陥で、他タブからの deleteDatabase / バージョン更新を無期限にブロックする。

**影響**: IndexedDB が一度でも切れると、ファイルハンドルとフォルダ許可の永続化がセッション中ずっと無言で死ぬ。プライベートウィンドウ等で open が最初から失敗する環境でも、reject した Promise がキャッシュされて再試行されない。

**修正方針**: db.onversionchange と db.onclose で idbConn = null にして次回アクセス時に再オープンする。reject 時も idbConn = null に戻す。req.onblocked を実装し、onupgradeneeded では objectStoreNames.contains("kv") を確認してから createObjectStore する。

### P5-13 / 検証済(CONFIRMED) / `D:/1.atrium/mmm/src/main.ts:585`

**LS_SAVED と LS_NAME の書き込み順が 2 か所で逆になっていて、部分失敗時の壊れ方が経路ごとに違う**

```
localStorage.setItem(LS_SAVED, savedText);
      localStorage.setItem(LS_NAME, fileName);
```

**症状**: saveFile は SAVED → NAME の順、loadText(483-484) は NAME → SAVED の順で書く。どちらも同じ try に入っているので、1 つ目が成功して 2 つ目が QuotaExceededError で落ちると片方だけ更新された状態が残る。結果、経路によって「名前だけ新しい」または「savedText だけ新しい」という別々の不整合が生まれ、所見 2 の復元ロジックがそのまま誤動作する。

**再現条件**: DevTools の Console で localStorage を上限近くまで埋める（例: localStorage.setItem('pad', 'x'.repeat(2_400_000))）。その状態で Ctrl+O で 100KB 程度の .md を開く。Application → Local Storage を見ると mmm.fileName だけが新ファイル名に変わり mmm.savedText は前の文書のまま（loadText の順序）。逆に既存ファイルを Ctrl+S した場合は mmm.savedText が更新されて mmm.fileName が取り残される。

**確度**: 確定

**検証の根拠**: main.ts:482-487 は setItem(LS_NAME) → setItem(LS_SAVED)、main.ts:584-589 は setItem(LS_SAVED) → setItem(LS_NAME) で、いずれも同一 try 内・catch は空。順序が逆なのは事実。

**検証による訂正**: saveFile 側の再現(「mmm.savedText が更新されて mmm.fileName が取り残される」)はほぼ発生しない。通常の Ctrl+S では fileName は変わらないので 586 は同値の書き直しで、失敗しても差分が生じない。可視の不整合になるのは 563-569 の showSaveFilePicker を通って fileName が変わった保存だけ。実質的には所見 7 の部分書き込みの一亜種で、単独の価値は低い。

**影響**: 部分書き込みが 2 通りの異なる不整合を生み、どちらも所見 2 のファイル破壊経路に入る。

**修正方針**: 3 キーを 1 つの JSON 値にまとめて 1 回の setItem で書き、部分失敗をそもそも起こさせない。

### P5-14 / 検証済(CONFIRMED) / `D:/1.atrium/mmm/src/main.ts:560`

**保存時に権限が拒否されて fileHandle を捨てても IndexedDB 側は更新しない**

```
if (r !== "granted") fileHandle = null;
```

**症状**: メモリ上の fileHandle は null になるが persistHandle() は呼ばれず、IDB の "handle" には古いハンドルが残る。続く showSaveFilePicker をユーザーがキャンセルすると catch(593) で抜けるので、メモリと IDB が食い違ったまま。リロードすると「拒否したはずのハンドル」が名前一致で再採用される。

**再現条件**: 1) Ctrl+O でファイルを開く（IDB に handle が入る）。2) タブを閉じて開き直す（復元ハンドルは prompt 状態）。3) Ctrl+S を押し、Chrome の編集許可プロンプトで「ブロック」を押す。4) 続いて出る「名前を付けて保存」をキャンセルする。5) DevTools → Application → IndexedDB → mmm-store → kv を見ると handle は古いまま。6) リロードすると同じハンドルが再び採用され、ユーザーの拒否が引き継がれない。

**確度**: 確定

**検証の根拠**: main.ts:560 `if (r !== "granted") fileHandle = null;` の直後に persistHandle() は無く、persistHandle の呼び出しは main.ts:527 / 538 / 574 / 876 の 4 か所のみ。574 は createWritable 成功後なので、563 の showSaveFilePicker をキャンセルすると 590-597 の catch(AbortError)で抜けて IDB は古いハンドルのまま。再起動時は 1119 の名前一致だけで再採用される(fileName もキャンセル時は 568 に到達しないので変わらない)。

**影響**: メモリと永続層の状態が乖離する。実害は再プロンプトが出る程度だが、所見 3 と組み合わさると「拒否したファイル」を保存先として保持し続ける。

**修正方針**: fileHandle = null にした直後に persistHandle() を呼ぶ。

### P5-15 / 検証済(CONFIRMED) / `D:/1.atrium/mmm/src/main.ts:132`

**applyColor が不正な保存値で早期 return し、DEFAULT_COLOR にフォールバックしない／ピッカードラッグ中に毎回 setItem する**

```
const m = /^#?([0-9a-f]{6})$/i.exec(hex);
  if (!m) return;
```

**症状**: boot(1100)は localStorage.getItem(LS_COLOR) ?? DEFAULT_COLOR なので、キーが存在するが値が壊れている場合（手動編集・旧フォーマット・他アプリの混入）は ?? を通過してこの early return に落ち、--accent も favicon も一切設定されない。CSS の :root に --accent: #5932ff があるので画面は救われるが、favicon リンクは前の data URI（またはビルド既定の /favicon.svg）のまま残り、以後どのブランド色にも追随しない。また 146 行の setItem は color input の input イベントごとに走るため、ピッカーのドラッグ中に同期書き込みが毎フレーム発生する。

**再現条件**: 1) DevTools → Application → Local Storage で mmm.color の値を rgb(1,2,3) に書き換える。2) リロード。アクセントは CSS 既定の紫に戻るが、タブの favicon は前回の色のまま更新されない。3) ロゴをクリックしてピッカーを開き色をドラッグすると、Application → Local Storage の mmm.color が連続的に書き換わるのが観測できる。

**確度**: 確定

**検証の根拠**: main.ts:1100 の ?? は null にしか反応せず、"rgb(1,2,3)" は main.ts:132-133 の正規表現で弾かれて 139-144 の setProperty も favicon 更新も実行されない。画面が救われる根拠は style.css:8 `--accent: #5932ff;`、favicon が取り残される根拠は index.html:7 `<link rel="icon" ... href="/favicon.svg" />`。main.ts:164 の input リスナーがドラッグ中も毎回 146 の同期 setItem を叩くのも事実。

**検証による訂正**: 「以後どのブランド色にも追随しない」は言い過ぎ。ロゴ(165-174)から有効な色を選べばその場で 139-146 が走って復帰する。正確には「壊れた値が localStorage に残る限り、毎回のリロードで favicon だけ既定に戻る」。

**影響**: 軽微。壊れた設定値からの復帰が不完全で、色ピッカー操作中にメインスレッドで同期 I/O が連発する。

**修正方針**: applyColor が false を返したら applyColor(DEFAULT_COLOR) で確実に初期化する。setItem は change イベント（またはデバウンス）に移す。

### P5-16 / 検証済(CONFIRMED) / `D:/1.atrium/mmm/src/main.ts:207`

**updateDirty が全スナップショットで全文比較し、core.getText() をスナップショットあたり複数回呼ぶ**

```
elDirty.hidden = core.getText() === savedText;
```

**症状**: applySnap は updateDirty()(202) で 1 回、schedulePersist 経由の persistNow(105) で 1 回、さらに mindmap 側が host.docText()(306) で 1 回、core.getText() を呼ぶ。これは MoonBit 側の文字列を JS 側に丸ごと materialize する境界呼び出し。加えて === による比較は差分が末尾にある場合（＝文末で編集している通常のケース）に文書全長を走査する。1 打鍵ごとに全部走る。

**再現条件**: 1MB 程度の .md を開き、文書の末尾に移動して連続入力しながら DevTools → Performance でプロファイルを取る。getText 由来の文字列生成と比較が 1 打鍵ごとに複数回現れる。savedText を保持する代わりにハッシュを比較するようにした場合との差で切り分けられる。実測コスト（mbt.getText() が毎回コピーを作るのか参照を返すのか）は要確認。

**確度**: 確定

**検証の根拠**: main.ts:207 の全文 === 比較と、main.ts:198 map.render() → mindmap.ts:313 `const doc = this.host.docText();`(main.ts:306 = core.getText()) が applySnap ごとに必ず走る。docText の呼び出しは mindmap.ts:313 の 1 か所のみ(grep -a 済み)。

**検証による訂正**: 「スナップショットあたり複数回」は 2 回(main.ts:207 と mindmap.ts:313)であって 3 回ではない。main.ts:105 の persistNow はデバウンス発火時のみ(所見 5 のとおり連続入力中は 0 回)なので「schedulePersist 経由で 1 回」は毎スナップショットではない。実コスト(mbt.getText() がコピーを作るか、=== が O(n) になるか)は依然として要実測。

**影響**: 軽微〜中。F-002 の描画コストと同じ打鍵経路に乗るため、大きな文書での入力レイテンシに上乗せされる。

**修正方針**: savedText の代わりに保存時点の rev（Snapshot.rev）またはハッシュを保持して比較する。applySnap 内で core.getText() を 1 回だけ呼び、その値を updateDirty と persistNow に渡す。

### P5-17 / 検証済(CONFIRMED) / `D:/1.atrium/mmm/src/main.ts:678`

**loadAsset が画像 1 枚ごとに map.render() を呼ぶ（F-002 の新しい呼び出し元）**

```
map.render();
```

**症状**: 既知の F-002（render() が毎回 SVG を全破棄・全再構築する）について、永続化まわりに新しい呼び出し元がある点を明示的に報告する。復元した dirHandle が届いた後の boot 経路(1128-1130)は保留中サムネイル全件に対して loadAsset を並列に走らせ、その各々が成功時に map.render() を呼ぶ。画像 N 枚なら起動直後にフルレンダリングが N 回走る。unlockAssets(698) も同じく pending 全件でこれを起こす。

**再現条件**: 画像を 20 枚含む md を開き、フォルダ許可を与えた状態で mmm をリロードする。DevTools → Performance で記録すると、IDB から dir が復元された直後にレンダリングのフルリビルドが画像枚数ぶん連続して発生する。2000 ノード規模なら F-002 の実測 66ms × 枚数ぶん、起動直後に入力を受け付けない時間が生じる。

**確度**: 確定

**検証の根拠**: main.ts:678 は loadAsset の成功パスにあり、ブートの main.ts:1122-1133 は assetUrls 内の null 全件に対して loadAsset を並列起動、unlockAssets の main.ts:698 も pending 全件で同じことをする。したがって画像 N 枚で render() が N 回走る。

**検証による訂正**: 暴走はしない点を補足すべき。imageUrl(main.ts:637-638)は `hit !== undefined` で null もキャッシュ値として返すため、render() 内から未解決画像の loadAsset が再度キックされることはなく、上限は N 回で止まる。内容としては新しい欠陥ではなく F-002 の新規呼び出し元の報告。

**影響**: 起動直後のフリーズ。F-002 の修正（差分レンダリング）が入るまでは画像枚数に比例して悪化する。

**修正方針**: loadAsset 群の完了を待って 1 回だけ再描画する（requestAnimationFrame で合流させる）か、該当 <image> の href だけを差し替えて map.render() を呼ばない。

---

## 領域: エクスポート・インポート・貼り付け（exportMap / exportSvg / downloadBlob / saveFile / openFile / drop / paste / pasteImage / saveImageToDisk / relevel / popup）

**調べたもの**

- src/main.ts 全1136行を通読（exportMap, downloadBlob, saveFile, openFile, drop handler, paste, pasteImage, saveImageToDisk, insertContentLine, loadText, imageUrl/loadAsset/assetSegs/ensureImageDir/unlockAssets, persistNow/schedulePersist, boot ブロック）
- src/mindmap.ts 全1814行を Read ツールで通読（NUL バイト回避。exportSvg:778-868, render():290-729, parseImage:144, parseLink:119, onKeydown の p/P・Mod+V・Mod+C/X 経路, 右クリックメニュー）
- src/relevel.ts 全55行（scanDepths のフェンス判定・hasHeadings・relevel の delta 計算）
- src/popup.ts 全237行（shell のキーイベント配線、showCodePopup / showLinkPopup / showDrawPopup の focus・collect）
- src/editor.ts 全188行（EditorState.create に lineSeparator ファセット指定が無いこと、applySets/setText、input.drop が userEvent "input" に落ちること）
- src/style.css 全329行（PROPS に無い white-space:pre / color-mix / rx / background-image を洗い出し）
- index.html（btn-export-svg / btn-export-webp の title と Shift 修飾の説明）
- src/coreApi.ts（selectionText の型と JSON 境界）
- core/parser.mbt 全238行（scan_lines の \r\n 扱い、fence_open/fence_close_len を relevel.ts の scanDepths と 1 対 1 で突き合わせ → 見出し・フェンス判定は一致、--- 区切りとコメント領域の扱いだけが不一致）
- core/doc.mbt 全528行（sub_end = 次の同深度以下見出しの hs、compute_groups の --- 適用規則、apply_sets の tag マージ、normalize_selection）
- core/cmds.mbt の selection_text(595-616) と nl()(39-46)
- core/api.mbt の init_doc(99-111) — CRLF 正規化も BOM 除去も行っていないことを確認
- node で @codemirror/state 6.7.1 を直接読み込み、CRLF 文字列を insert したときの doc 長を実測（21 → 16、\r が全て消える）
- node_modules/@codemirror/view の handlers.drop / dropText を読み、ファイルドロップ時に FileReader でテキスト挿入し userEvent "input.drop" を出すこと、ハンドラが contentDOM に張られていることを確認
- エクスポート対象の DOM 構成（plus-btn / drop-line / rubber / map-hint は nodeLayer・edgeLayer の外＝エクスポートに含まれない）を確認
- exportSvg の strip→clone→inline→restore の順序に await が挟まっていないこと（選択状態の復元漏れは無い）を確認
- 別ツリー（root より前の見出し）と隠しノードはいずれも boxes に入り、exportSvg の bbox とクローンに含まれる（欠落していない）ことを確認。blob: サムネイルの data URL 化も行われている

### P5-1 / 未検証 / `src/editor.ts:96 / src/main.ts:479-480`

**CRLF ファイルを開くと md ペインと core のオフセットがずれ、以後の編集が文書を破壊する**

```
src/editor.ts:96 `state: EditorState.create({ doc: "", extensions: [...] })`（lineSeparator ファセット未指定） / src/main.ts:479-480 `const snap = core.initDoc(text);` `editor.setText(text);`
```

**症状**: CodeMirror 6 は lineSeparator 未指定時 /\r\n?|\n/ で行分割し lineBreak "\n" で保持するため \r が消える。core/api.mbt:100 は `st.text = text` で CRLF をそのまま保持する。両者の文字オフセットが CRLF 1 個につき 1 ずつずれる。実測: "# a\r\n\r\n## b\r\n\r\nbody\r\n" は core 21 文字 / CM 16 文字。

**再現条件**: 1) メモ帳などで CRLF 改行の .md（見出し 5 行＋本文）を作る。2) mmm で「開く」。3) マップで下の方のノードをクリックする → md ペインのハイライト位置が行数分下にずれている（editor.highlight(n.hs..n.subEnd) が core オフセットのまま渡されるため）。4) md ペインの最終行末尾に 1 文字打つ → core は CRLF テキストの別位置に適用するので見出しが壊れ、md ペインの表示と core.getText() が食い違う。

**確度**: 未検証(自己申告: 確定)

**影響**: CRLF の .md（Windows で作られた md の大半）を開いた時点で双方向ミラーが壊れ、その壊れた結果が保存でファイルに書き戻る。インポート経路で最も深刻。

**修正方針**: EditorState.create の extensions に `EditorState.lineSeparator.of("\r\n")` を文書の改行種別に応じて Compartment で切り替えるか、loadText 側で LF に正規化して core にも正規化後のテキストを渡す。

### P5-2 / 未検証 / `src/main.ts:525 / src/main.ts:571-573`

**UTF-16 / BOM 付きファイルを開いて保存すると元ファイルを破壊する**

```
main.ts:525 `savedText = await f.text();` / main.ts:571-573 `const w = await fileHandle.createWritable();` `await w.write(text);` `await w.close();`
```

**症状**: Blob.text() は常に UTF-8 デコード（BOM は除去、不正バイトは U+FFFD 置換）。UTF-16LE の .md を開くと ASCII 部が U+0000 と交互に並ぶ文字列になり、w.write(text) はそれを UTF-8 でそのまま書き戻す。createWritable() は既定で全 truncate なので元の UTF-16 バイト列は残らない。UTF-8 BOM の場合も、開いて保存するだけで BOM が消える。

**再現条件**: 1) Windows PowerShell 5.1 で `"# a" | Out-File t.md`（既定 UTF-16LE+BOM）。2) mmm で t.md を開く。3) md ペインが 1 文字おきに空白のような表示（NUL 混じり）になる。4) Ctrl+S。5) t.md をバイナリで見ると UTF-16 ではなく NUL 混じりの UTF-8 になっている。BOM のみの確認なら UTF-8 BOM 付き .md を開いて即 Ctrl+S し、先頭 3 バイト EF BB BF が消えることを見る。

**確度**: 未検証(自己申告: 確定)

**影響**: 無編集で開いて保存しただけで原本が壊れる。ユーザーのメモリにも「PowerShell BOM/文字化けの罠」がある環境なので現実的に踏む。

**修正方針**: openFile / drop で `await f.arrayBuffer()` を取り、先頭バイトで UTF-16 BOM を検出したら TextDecoder("utf-16le"/"utf-16be") を使い、元のエンコーディングと BOM 有無を保持して saveFile で再付与する。対応しないなら読み込みを拒否して flashFilename で通知する。

### P5-3 / 未検証 / `src/main.ts:857-878`

**md ペインへ .md をドロップすると CodeMirror の挿入と loadText の再読込が二重に走る**

```
main.ts:857 `window.addEventListener("drop", (e) => {` … main.ts:875-876 `savedText = await f.text();` `loadText(savedText, f.name);`
```

**症状**: CodeMirror 6 は contentDOM の drop ハンドラで dataTransfer.files を FileReader.readAsText し、その全文をドロップ位置へ挿入する（node_modules/@codemirror/view/dist/index.js:5110-5127 → dropText で userEvent "input.drop"）。preventDefault はするが伝播は止めないので window の drop も走り、loadText が文書を丸ごと置換する。両方非同期でレースする。

**再現条件**: 1) mmm を開き md ペインに文字が見えている状態にする。2) エクスプローラから別の .md を md ペインの 1 行目の文字の上へドロップ。3) 破棄確認が出たら「はい」。4) 数回繰り返すと、読み込んだ内容だけになる回と、読み込んだ文書の途中にもう一度全文が挿入された二重文書になる回が出る。DevTools で core.getText().length を見れば差が分かる。

**確度**: 未検証(自己申告: 確定)

**影響**: ファイルを開く操作が非決定的に文書を二重化する。挿入は core にも流れるので undo スタックにも残る。

**修正方針**: window ではなく #map-pane / #md-pane に個別に drop を張るか、window の dragover/drop を capture フェーズで受けて e.stopPropagation() してから自前処理する。もしくは MdEditor に `EditorView.domEventHandlers({ drop: () => true })` を追加して CM のファイルドロップを無効化する。

### P5-4 / 未検証 / `src/main.ts:377-378`

**カット時にクリップボード書き込みの失敗を握り潰したまま削除する**

```
`    void navigator.clipboard.writeText(text).catch(() => {});`\n`    if (cut) host.deleteSelection();`
```

**症状**: writeText の reject を空の catch で捨て、成否に関わらず deleteSelection() を実行する。さらに非セキュアコンテキストでは navigator.clipboard 自体が undefined なので `.writeText` 参照で同期 TypeError が投げられ、Mod+C / Mod+X / yy が何の表示も無く全部無反応になる（paste() 側も void async + catch(()=>{}) で同様に沈黙する）。

**再現条件**: 非セキュアコンテキスト: 1) `vite --host` で LAN IP（http://192.168.x.x:5173、localhost ではない）から開く。2) ノードを選択して Mod+C → 何も起きない、通知も無い。3) Mod+V も無反応。書き込み reject 側: DevTools で `navigator.clipboard.writeText = () => Promise.reject(new DOMException("x","NotAllowedError"))` を差し込んでからノードを選んで Mod+X → ノードは消えるがクリップボードは空のままで、別ノードで Mod+V しても復元できない。

**確度**: 未検証(自己申告: 確定)

**影響**: カットでノードが復元不能に見える形で消える（undo は残るが、ユーザーは貼り付けようとして初めて気づく）。非セキュアコンテキストではコピー／貼り付け／画像貼り付けが全滅するのに一切のフィードバックがない。

**修正方針**: copySelection を async にして `await navigator.clipboard.writeText(text)` を try/catch で包み、成功したときだけ deleteSelection()、失敗時は flashFilename でエラー表示する。起動時に navigator.clipboard の有無を見て非対応なら該当ショートカットを無効化する。

### P5-5 / 未検証 / `src/popup.ts:219-220`

**お絵描きポップアップがフォーカスを取らないため、背後のマップにキー入力が素通りする**

```
`    body.append(bar, canvas);`\n`    void commit; // committing a drawing goes through the 確定 button / Mod+Enter`
```

**症状**: showDrawPopup はどの要素にも focus() しない（showCodePopup:94 / showLinkPopup:126 にある queueMicrotask(…focus()) が無い）。呼び出し元 host.addDrawing は map ペインの D キーからなので activeElement は #map-pane のまま。shell() の keydown リスナは overlay に張られているのでイベントが到達せず、MindMap.onKeydown と window の capture keydown だけが生きている。

**再現条件**: 1) ノードを 1 つ選択して D を押し、お絵描きポップアップを出す。2) Esc を押す → ポップアップは閉じず、代わりに背後の選択が解除される。3) d を 2 回押す → 背後のノードが削除される。4) Enter → 背後に兄弟ノードが追加される。5) Mod+Enter → 確定されない。canvas をクリックして描いた後も activeElement は body になるだけで overlay 外のままなので同じ。

**確度**: 未検証(自己申告: 確定)

**影響**: 画像挿入の途中で気づかないうちに文書が壊れる。ポップアップはボタンでしか閉じられない。

**修正方針**: showDrawPopup の build 末尾で canvas に tabindex="0" を付けて queueMicrotask(() => canvas.focus()) するか、shell() 側で panel に tabindex="-1" を付けて overlay 追加後に panel.focus() する。合わせて shell の keydown を document に capture で張る方が確実。

### P5-6 / 未検証 / `core/cmds.mbt:603 / src/main.ts:414`

**--- 区切り行がクリップボードに紛れ込み、貼り付けでマップの左右レイアウトが勝手に組み替わる**

```
cmds.mbt:603 `let mut block = sub(st.text, nd.hs, nd.sub_end)` / main.ts:414 `body = relevel(normalized, n.depth + 1).trimEnd();`
```

**症状**: sub_end は「次の同深度以下の見出しの hs」（doc.mbt:309-317）なので、ノードの後ろに置かれた `---` 行はそのノードの範囲に含まれる。selection_text は末尾改行だけ削るので `---` が最終行としてクリップボードに残る。relevel は見出し行しか触らないので `---` はそのまま貼られ、doc.mbt:339-389 の compute_groups で直後の見出しが別グループになり、mindmap.ts:513-514 によりルート直下のグループ 0 以外は左側へ回る。

**再現条件**: 起動直後のサンプル文書でそのまま再現する。1) マップで「mindmap」ノードを選択して Mod+C（クリップボードは `## mindmap\n\n### 空間的に見るもう一つの窓\n\n---`）。2)「markdown」ノードを選択して Mod+V。3) 貼られた `---` が `## mindmap` の直上に来るため mindmap と mirror が新グループになり、マップの左側へ飛ぶ。md ペインに `---` が 2 本並ぶ。

**確度**: 未検証(自己申告: 確定)

**影響**: コピー→貼り付けの往復で構造が保たれない。往復のたびに `---` が 1 本増え、無関係な部分のレイアウトが右→左に飛ぶ。

**修正方針**: selection_text で、末尾の空行に続く `---` 区切り行を削る（sub_end 直前の区切り行を範囲から除く）。加えて貼り付け側で、対象がルート直下でないときは `---` 行を除去する。

### P5-7 / 未検証 / `src/mindmap.ts:803-815 / src/mindmap.ts:823`

**エクスポート SVG で white-space:pre が落ち、コードブロックのインデントと連続空白が潰れる**

```
mindmap.ts:803-815 `const PROPS = ["fill","stroke","stroke-width","stroke-dasharray","stroke-linecap","font-family","font-size","font-weight","opacity","dominant-baseline","text-anchor"];` / mindmap.ts:823 `copy.removeAttribute("class");`
```

**症状**: style.css:137 `.node text.label { white-space: pre; }` と style.css:244 `.node text.code-line { white-space: pre; }` が表示を支えているのに、PROPS に white-space が無く、さらに class を削除するので複製側にはこの規則が一切効かない。xml:space="preserve" も付けていないので、SVG 既定の空白圧縮（先頭・末尾除去と連続空白の 1 個化）がかかる。

**再現条件**: 1) ノードを選択して C を押し、コードポップアップに `def f():` 改行 `    return 1`（4 スペースインデント）を入力して確定。2) マップ上ではインデント付きで表示される。3) 上部の SVG ボタンで保存し、書き出した .svg をブラウザで開く → `return 1` が左端に寄っている。4) WebP ボタンでも同じ（同じ SVG をラスタライズするため）。見出し側は `# a␣␣␣␣b` のような連続空白を含む見出しで同様に確認できる。

**確度**: 未検証(自己申告: 確定)

**影響**: コードブロックを持つマップのエクスポートが読めなくなる。SVG／WebP／クリップボード SVG の全経路が影響を受ける。

**修正方針**: white-space は SVG のプレゼンテーション属性ではないので PROPS に足すだけでは不十分。inline() で text 要素に `copy.setAttribute("xml:space", "preserve")` を付けるか `style="white-space:pre"` を直接書く。

### P5-8 / 未検証 / `src/main.ts:475 / src/main.ts:660-661`

**別フォルダの md を開くと dirHandle が古いまま残り、画像サムネイルが永久にプレースホルダになる**

```
main.ts:475 `clearAssets(); // image paths are relative to the (new) md` / main.ts:660-661 `const base = await assetSegs(dirHandle);` `if (!base) return;`
```

**症状**: loadText は assetUrls を捨てるが dirHandle は捨てない。assetSegs は dir.resolve(fileHandle) で新しい md が旧フォルダ配下か調べ、外なら null を返し loadAsset は無言で return する。unlockAssets（main.ts:687-700）は 1 回走ると自分の pointerdown リスナを外すので再試行の道も消える。

**再現条件**: 1) A フォルダの a.md を開き、ノードに画像を貼って保存（A に対する読み書き許可が dirHandle に入る）。2) A の外にある B フォルダに、`![](./x.webp)` の行を持つ b.md と x.webp を置く。3) mmm で b.md を開く。4) マップには破線のプレースホルダ矩形とファイル名だけが出て、何度クリックしても画像は出ない。エラー表示も無い。5) リロードしても idbGet("dir") が A を復元するので同じ。

**確度**: 未検証(自己申告: 確定)

**影響**: 別フォルダの文書を開いた瞬間に画像表示機能が黙って死ぬ。ユーザーには「画像が壊れている」ようにしか見えない。

**修正方針**: loadText で `dirHandle = null; void idbSet("dir", null)` も行い、次のサムネイル要求時に改めてフォルダ許可を求める。少なくとも assetSegs が null を返したときは flashFilename で「この md を含むフォルダを選び直してください」を出す。

### P5-9 / 未検証 / `src/main.ts:796-804`

**画像名に空白や括弧を許すため、書き出した markdown 行が parseImage に弾かれ画像が表示されない**

```
`  const name = typed.trim().replace(/\.(webp|png|jpe?g|gif)$/i, "");`\n`  const segs = name.split("/").filter((s) => s !== "" && s !== ".");`\n`  if (`\n`    segs.length === 0 ||`\n`    segs.some((s) => s === ".." || /[\\:*?"<>|]/.test(s))`\n`  ) {`
```

**症状**: 検証は `..` と `\ : * ? " < > |` しか弾かない。空白・`(`・`)`・`#`・`%` は通る。main.ts:843 が書く `![](./${rel})` は空白や `)` を含むと mindmap.ts:145 の `/^!\[[^\]]*\]\(<?([^)\s>]+)>?\)$/` に合致せず、parseLink にも合致しないので render のカード行から無言で落ちる。ファイル自体はディスクに書かれている。

**再現条件**: 1) ノードを選択して D でお絵描き、適当に描いて確定。2) 画像名プロンプトに `my photo` と入力して OK。3) md ペインに `![](./my photo.webp)` が入る。4) マップのノードには画像行が一切出ない（プレースホルダすら出ない）。5) エクスプローラで見ると my photo.webp は実在する。`a(1)` でも同じ。

**確度**: 未検証(自己申告: 確定)

**影響**: 保存は成功したのに表示されないので、ユーザーは保存失敗と誤解する。Windows 予約名（CON, NUL, COM1 等）や末尾ドット・空白も未検証で、その場合は getFileHandle が投げて「画像の保存に失敗しました」になる。

**修正方針**: segs の各要素をホワイトリストで検証するか、URL として安全でない文字を含む場合は `![](<./my photo.webp>)` の山括弧形式で書く（parseImage は既に `<?…>?` を受ける）。予約名・末尾ドット・末尾空白も弾く。

### P5-10 / 未検証 / `src/main.ts:402`

**ATX 見出しを含まないクリップボードの貼り付けが完全に無反応（Setext・箇条書き・他ツールの方言）**

```
`      if (!hasHeadings(normalized)) return; // fence-aware, matches relevel`
```

**症状**: relevel.ts:27 の `/^(#+)[ \t]/` にしか反応しないので、Setext 見出し（Title + =====）、番号／箇条書きリスト、素の段落、URL 1 行、HTML 断片は全て hasHeadings=false になり、paste は何のメッセージも出さず return する。文脈メニューの「子として貼り付け」も同じく無反応。

**再現条件**: 1) テキストエディタで `hello world` をコピー。2) mmm のマップでノードをクリックして選択。3) Mod+V → 何も起きない。md ペインもマップも無変化、エラーも通知も無い。4) 続けて `Title\n=====\n本文`（Obsidian / 旧形式の md）をコピーして Mod+V → 同じく無反応。

**確度**: 未検証(自己申告: 確定)

**影響**: 他ツールから持ってきた markdown が「貼れない」のか「アプリが壊れている」のか区別できない。mmm の主要な取り込み経路が沈黙する。

**修正方針**: hasHeadings が false のときは flashFilename で「見出しを含まないテキストは貼り付けられません」を出す。もしくは見出しの無いテキストは insertContentLine 経由で attached content として追加し、Setext は貼り付け前に ATX へ変換する。

### P5-11 / 未検証 / `src/main.ts:401 / src/main.ts:416-420 / src/main.ts:735`

**貼り付けと挿入が \n 決め打ちで、CRLF 文書に混在改行を作る**

```
main.ts:401 `const normalized = clip.replace(/\r\n/g, "\n");` / main.ts:416-420 `body += "\n";` … `const suffix = at !== text.length ? "\n" : "";` / main.ts:735 `applySnap(core.replaceText(at, at, prefix + line + "\n" + suffix, ""), "map");`
```

**症状**: core は cmds.mbt:39-46 の nl() で文書の改行種別を維持する設計（selection_text も br=nl() を使う）なのに、TS 側の貼り付け・リンク／コード／画像挿入は全て LF 固定。CRLF 文書に貼ると挿入部分だけ LF になる。

**再現条件**: 1) CRLF の .md を用意して開く。2) ノードを選択して Mod+C（クリップボードは nl() により CRLF）。3) 別ノードを選択して Mod+V。4) 保存後にファイルをバイナリで見ると、貼った範囲だけ 0A 単独になっている（`grep -c $'\r' file` の行数が全行数より少ない）。5) L でリンクを挿入しても同じ。

**確度**: 未検証(自己申告: 確定)

**影響**: git 差分が改行だけで汚れる。CRLF 破綻（一件目）と重なると影響が拡大する。

**修正方針**: core に nl() 相当を公開する API（core.lineBreak()）を追加し、paste / insertContentLine の prefix・suffix・body の改行をそれで組み立てる。CRLF を全面的に LF 正規化する方針ならそちらでも解消する。

### P5-12 / 未検証 / `src/main.ts:1033-1039`

**大きなマップの WebP エクスポートが canvas 上限で失敗し、汎用エラーしか出ない**

```
`    const scale = 2; // crisp text at typical zoom levels`\n`    const cv = document.createElement("canvas");`\n`    cv.width = img.naturalWidth * scale;`\n`    cv.height = img.naturalHeight * scale;`
```

**症状**: scale が固定 2 で上限クランプが無い。Chrome の canvas は 1 辺 65535px・面積約 2.68 億 px が上限で、超えると toBlob が null を返し main.ts:1057 の `throw new Error("image encode failed")` → catch で flashFilename("エクスポートに失敗しました") だけになる。SVG エクスポートは通るので何が違うのかユーザーには分からない。

**再現条件**: 1) `## n1` 〜 `## n1600` のように第 2 階層見出しを 1600 個並べた .md を作って開く（縦に 1600×(30+10)≈64000px）。2) マップが描かれたことを確認。3) SVG ボタン → 保存できる。4) WebP ボタン → 「エクスポートに失敗しました」のみ。console に "export failed: Error: image encode failed" が残る。

**確度**: 未検証(自己申告: 確定)

**影響**: ノード数が数百〜数千の実用文書でラスタライズ経路が使えなくなる。原因も回避策も画面から分からない。

**修正方針**: 辺長・面積の上限（例 16384px / 2.5e8px）から scale = min(2, 上限/naturalWidth, 上限/naturalHeight, …) を計算し、1 を下回るなら縮小する。上限に当たったことを flashFilename で「マップが大きすぎるため SVG を使ってください」と具体的に伝える。

### P5-13 / 未検証 / `core/cmds.mbt:603 / core/parser.mbt:94-95`

**隠しノードをコピーすると閉じマーカー --> だけがクリップボードに入り、貼り付け先にゴミ行が残る**

```
cmds.mbt:603 `let mut block = sub(st.text, nd.hs, nd.sub_end)` / parser.mbt:94-95 `if in_comment && is_marker_line(text, l, "-->") {` `regions.push((c_open, c_open_next, l.start, l.next))`
```

**症状**: 隠し領域の `<!--` は対象ノードの hs より前の行なのでコピー範囲外だが、`-->` は sub_end の手前にあるので含まれる。結果、開きマーカー無しの `-->` 単独行が貼られ、in_comment=false では単なる本文行として扱われる。

**再現条件**: 1) ノード X（子を 1 つ持つ、深さ 2）を選択して Shift+H で非表示にする。2) X を選択したまま Mod+C。3) 別のノード Y を選択して Mod+V。4) md ペインの貼付部分の末尾に `-->` という行が残り、マップでは貼った最後の子ノードの attached content として扱われる（隠しにはならない）。

**確度**: 未検証(自己申告: 確定)

**影響**: コピー→貼り付けの往復で文書にゴミが混入する。逆に `<!--` だけが入る構成になれば、以降の文書全体が隠し扱いになりうる。

**修正方針**: selection_text で、コピー範囲に対応する開きマーカーが含まれていない `-->` 行（および閉じの無い `<!--` 行）を除去する。または貼り付け側 relevel でマーカーの対応を検査して不整合なら落とす。

### P5-14 / 未検証 / `src/main.ts:104-108 / src/main.ts:1113-1114`

**localStorage の容量超過を握り潰すため、大きな文書のリロードで古い版が黙って復元される**

```
main.ts:104-108 `try { localStorage.setItem(LS_TEXT, core.getText()); } catch { /* storage full/blocked */ }` / main.ts:1113-1114 `savedText = localStorage.getItem(LS_SAVED) ?? storedText ?? SAMPLE;` `loadText(storedText ?? SAMPLE, storedName ?? "無題.md");`
```

**症状**: localStorage の枠は一般に約 5MB（実装は UTF-16 換算なので実効約 250 万文字）。超えると setItem が QuotaExceededError を投げるが catch で捨てるだけなので、LS_TEXT には超過前の古いテキストが残り続ける。リロード時はその古いテキストが loadText に渡る。

**再現条件**: 1) 300 万文字程度の .md（`## n` を 30 万行など）を開く。2) 1 文字編集する（警告は出ない）。3) DevTools の Application → Local Storage で mmm.text の長さが最新の core.getText().length と一致しないことを確認。4) リロードする → 編集前（もしくはさらに古い）内容が復元される。

**確度**: 未検証(自己申告: 確定)

**影響**: 「edits survive reloads via localStorage」（main.ts:851 のコメント）の保証が大きな文書で破れ、しかもユーザーには成功しているように見える。

**修正方針**: catch で失敗を検知したら flashFilename で「この文書は自動保存できません。こまめに保存してください」を出し、LS_TEXT を削除して古い版が復元されないようにする。既に IndexedDB を使っているのでテキストの保存先もそちらへ移すのが素直。

### P5-15 / 未検証 / `src/main.ts:1113-1119`

**リロード後の savedText が localStorage 由来なので、外部で変更されたファイルを警告無く上書きする**

```
`  savedText = localStorage.getItem(LS_SAVED) ?? storedText ?? SAMPLE;`\n`  void idbGet<FileSystemFileHandle | null>("handle")`\n`    .then((h) => {`\n`      // only adopt a persisted handle that matches the restored file name —`\n`      if (h && h.name === fileName) fileHandle = h;`
```

**症状**: ファイル名の一致だけを見て IndexedDB のハンドルを採用するが、savedText はディスクではなく localStorage から復元される。ディスク側が別プロセスで書き換わっていても検知されず、Ctrl+S は createWritable で全 truncate して書き戻す。コメントは「間違ったファイルに書く」リスクにしか言及していない。

**再現条件**: 1) mmm で notes.md を開き、編集せずタブを閉じる。2) VS Code で notes.md に段落を追加して保存。3) mmm を開き直す（notes.md が復元され、ハンドルも採用される）。4) mmm でノードを 1 つリネームして Ctrl+S（パーミッションの再取得だけ起きる）。5) VS Code で追加した段落が消えている。

**確度**: 未検証(自己申告: 確定)

**影響**: 外部エディタとの併用でサイレントなデータ喪失が起きる。ローカル専用アプリでこそ他ツール併用は普通の使い方。

**修正方針**: 保存前に fileHandle.getFile() の lastModified／内容を読み、savedText と一致しなければ confirm で上書き可否を尋ねる。起動時にハンドルを採用した時点で照合するのが望ましい。

### P5-16 / 未検証 / `src/mindmap.ts:849-854 / src/mindmap.ts:844`

**エクスポート SVG がフォントを埋め込まず xlink:href も付けないため、外部ツールで崩れる**

```
mindmap.ts:849-854 `const out = svgEl("svg", { xmlns: SVG_NS, viewBox: `${x0 - M} ${y0 - M} ${w} ${h}`, width: String(w), height: String(h) });` / mindmap.ts:844 `img.setAttribute("href", dataUrl);`
```

**症状**: (a) font-family は computed value のフォントスタック文字列として属性化されるだけでフォントデータは埋め込まれない。ボックス幅は mindmap.ts:108-116 の canvas measureText で決めているので、同じフォントが無い環境ではテキストがボックスからはみ出す。(b) 画像は SVG2 の href のみで xlink:href も xmlns:xlink 宣言も無い。(c) dominant-baseline: central に依存している。

**再現条件**: (a) 書き出した .svg を Segoe UI / Meiryo が無い環境や日本語フォントを持たないビューアで開くとラベルが枠外へ出る。(b) 古い Inkscape / Office に読み込ませると埋め込みサムネイルが表示されない。(c) 同じビューアでラベルが上下にずれる。要確認: どのビューアまでサポート対象とするかは製品判断。ブラウザで見るだけなら問題ない。

**確度**: 未検証(自己申告: 要確認)

**影響**: exportSvg の docstring は「self-contained」と謳っているが、実際に自己完結しているのは色と画像だけ。共有先で見た目が変わる。

**修正方針**: 最低限 xmlns:xlink を宣言して xlink:href を併記し、font-family の末尾に汎用ファミリ（sans-serif / monospace）が残ることを保証する。厳密にやるなら text をパス化する。

### P5-17 / 未検証 / `src/mindmap.ts:816-830`

**exportSvg が要素ごとに getComputedStyle を呼ぶため、大きなマップで UI が固まる**

```
`    const inline = (orig: Element, copy: Element): void => {`\n`      if (orig.tagName !== "title") {`\n`        const cs = getComputedStyle(orig);`\n`        for (const p of PROPS) {`
```

**症状**: ノード 1 個あたり g / rect / text / title ＋カード行の要素があり、それぞれに getComputedStyle と 11 回のプロパティ読み出しを行う。同期ループなので途中で描画も入力も返せない。F-002 の render() の重さとは別経路（エクスポート時のみ）で、スタイル解決が加わる分だけ重い。

**再現条件**: 1) 2000 ノード規模の .md を開く。2) DevTools の Performance を録画開始。3) SVG ボタンを押す。4) inline() の長い Recalculate Style 連発を確認し、その間クリックもキー入力も効かないことを見る。要確認: 実測秒数（inline() の合計時間が何 ms か）を見れば優先度が確定する。

**確度**: 未検証(自己申告: 要確認)

**影響**: エクスポート中にアプリが無応答になり、押した本人には固まったのか失敗したのか分からない。

**修正方針**: CSS ルールは十数種類しかないので、class ごとに代表 1 要素から computed style を一度だけ取り、同じ class には結果を使い回す。あるいは class を保ったまま出力 SVG に <style> ブロックを埋め込む。

### P5-18 / 未検証 / `src/main.ts:774-787`

**WebP 再エンコードに解像度上限もサイズ比較も無く、ImageBitmap も解放していない**

```
`  if (out.type !== "image/webp") {`\n`    try {`\n`      const bmp = await createImageBitmap(blob);`\n`      const cv = new OffscreenCanvas(bmp.width, bmp.height);`\n`      cv.getContext("2d")!.drawImage(bmp, 0, 0);`\n`      const webp = await cv.convertToBlob({ type: "image/webp", quality: 0.92 });`
```

**症状**: (a) 元画像の実サイズで OffscreenCanvas を確保する。8000×6000 の貼付で RGBA 約 192MB を一時確保する。(b) bmp.close() が無くデコード済みピクセルが GC 待ちになる。(c) コメントは「smaller on disk」だが、既に圧縮済みの JPEG 写真を quality 0.92 の webp に再エンコードすると多くの場合サイズが増える。

**再現条件**: (c) 1) 3000×2000 程度の写真 JPEG（例 1.2MB）をクリップボードにコピー。2) mmm のノードを選んで Mod+V、名前を付けて保存。3) 生成された .webp のサイズを元 JPEG と比べる → 大きくなっている。(a)(b) は 8000×6000 の PNG を貼って DevTools の Memory で確認。

**確度**: 未検証(自己申告: 確定)

**影響**: 「小さくするため」の再エンコードが逆にファイルを膨らませ、巨大画像ではメモリを浪費する。

**修正方針**: 長辺上限（例 2048px）を決めて drawImage 時に縮小し、finally で bmp.close() を呼ぶ。`if (webp.type === "image/webp" && webp.size < blob.size) out = webp;` としてサイズが増える場合は元を使う。

### P5-19 / 未検証 / `src/main.ts:809-821`

**上書き確認より先にサブフォルダを作るため、キャンセルしても空フォルダが残る**

```
`    for (const seg of segs.slice(0, -1)) {`\n`      d = await d.getDirectoryHandle(seg, { create: true });`\n`    }`\n`    …`\n`    if (exists && !confirm(`${leaf} は既にあります。上書きしますか？`)) {`\n`      return null;`
```

**症状**: create:true でのディレクトリ作成が、存在チェックと上書き確認の前に実行される。確認で「いいえ」を選んでも、作られたディレクトリは消されない。

**再現条件**: 1) ノードを選んで D で描いて確定、名前に `assets/pic` と入力して保存 → md の隣に assets/pic.webp ができる。2) もう一度 D で描いて確定、今度は `assets/pic`（同名）を入力。3) 上書き確認ダイアログで「いいえ」を選ぶ —— この時点で assets/ は既にあるので影響なし。4) 同じ手順を `newdir/pic` （newdir は存在しない）で行い、既存ファイルと同名にして上書きを拒否する → 画像は書かれないが newdir/ は残っている。

**確度**: 未検証(自己申告: 確定)

**影響**: 軽微だが、キャンセルしたのにユーザーのフォルダにゴミが残る。

**修正方針**: 存在チェックと confirm を、親ディレクトリを create:true で辿る前に移す（getDirectoryHandle を create:false で試し、無ければ新規と判断する）。

### P5-20 / 未検証 / `src/main.ts:788`

**IMG_EXT に無い MIME が無条件で .png 拡張子になる**

```
`  const ext = IMG_EXT[out.type] ?? "png";`（IMG_EXT は main.ts:738-743 で webp/png/jpeg/gif のみ）
```

**症状**: createImageBitmap が失敗して元 blob を保った場合、out.type が image/svg+xml や image/avif / image/bmp でも拡張子は png になり、`![](./name.png)` として中身が SVG のファイルが書かれる。

**再現条件**: 要確認: Chrome の navigator.clipboard.read() は既定で image/png しか露出しないため通常の貼り付けでは踏みにくい。確認方法: DevTools で `pasteImage(new Blob(['<svg xmlns="http://www.w3.org/2000/svg"/>'], {type:'image/svg+xml'}))` を直接呼び、書かれたファイル名と中身を照合する。unsanitized clipboard read が有効な環境や将来の対応拡大では通常操作でも起こりうる。

**確度**: 未検証(自己申告: 要確認)

**影響**: 拡張子と中身が食い違うファイルがユーザーのフォルダに書かれる。ブラウザは content sniffing で表示できてしまうため気づきにくい。

**修正方針**: IMG_EXT に無い MIME は保存を拒否して flashFilename で通知するか、blob.type のサブタイプをサニタイズして拡張子に使う。

### P5-21 / 未検証 / `src/main.ts:996-1002 / src/main.ts:576-580`

**downloadBlob が objectURL を click() 直後に同期解放し、アンカーを DOM に入れていない**

```
`function downloadBlob(blob: Blob, name: string): void {`\n`  const a = document.createElement("a");`\n`  a.href = URL.createObjectURL(blob);`\n`  a.download = name;`\n`  a.click();`\n`  URL.revokeObjectURL(a.href);`\n`}`
```

**症状**: 同じパターンが saveFile の非 File System Access フォールバック（main.ts:576-580）にもある。Chrome ではダウンロードが click() 内で同期キューされるため通常は動くが、blob が大きいと解放と競合しうる。アンカーを document に追加していないため、ブラウザによっては download 属性が効かない。

**再現条件**: 要確認: Chrome では再現しない可能性が高い。判定材料は (1) Firefox や古い WebKit で 100MB 級の SVG をエクスポートしてダウンロードが中断しないか、(2) 対応ブラウザの範囲をプロジェクトとして Chromium に限定するか、の 2 点。

**確度**: 未検証(自己申告: 要確認)

**影響**: エクスポートとフォールバック保存が特定ブラウザ・大サイズで無言に失敗しうる。

**修正方針**: url を変数に保持したうえで `document.body.append(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 60_000);` に変える。

### P5-22 / 未検証 / `src/popup.ts:48-57`

**ポップアップの Esc / Mod+Enter が、入力欄からフォーカスが外れると効かなくなる**

```
`    overlay.addEventListener("keydown", (e) => {`\n`      e.stopPropagation(); // keep map/global shortcuts out`\n`      if (e.key === "Escape") {`
```

**症状**: keydown は overlay に張られているので、フォーカスが overlay の子孫にある間しか届かない。overlay / panel / body / canvas はいずれも focusable でないため、パネルの余白をクリックすると activeElement が body になり、以後キーイベントは overlay を通らない。

**再現条件**: 1) ノードを選択して C（コードポップアップ）を出す。2) 「コードブロックを追加」のタイトル行の余白を 1 回クリックする。3) Esc を押す → ポップアップは閉じない。4) Mod+Enter → 確定もされない。ボタンを押すしか脱出手段が無い。

**確度**: 未検証(自己申告: 確定)

**影響**: ポップアップから抜けられなくなったように見える。お絵描きポップアップでは最初からこの状態（別項目）。

**修正方針**: keydown を document に capture で張り overlay が存在する間だけ処理する。もしくは panel に tabindex="-1" を付け、開いた直後と focusout 時に panel.focus() へ戻す。

### P5-23 / 未検証 / `src/popup.ts:223-234`

**お絵描きポップアップは白紙のまま確定でき、空画像がディスクに書かれる**

```
`    return () => {`\n`      let dataUrl = canvas.toDataURL("image/webp", 0.92);`\n`      …`\n`      return new Blob([bytes], { type: mime });`\n`    };`
```

**症状**: showCodePopup:96-100 / showLinkPopup:128-140 の collect は空入力で null を返して閉じないが、showDrawPopup の collect は常に Blob を返す。何も描かなくても白紙 720×440 の webp が保存対象になる。

**再現条件**: 1) ノードを選択して D。2) 何も描かずに「確定」を押す。3) 画像名プロンプトが出るのでそのまま OK。4) md の隣に真っ白な image-YYYYMMDD-HHMMSS.webp が書かれ、ノードに空白の画像行が追加される。

**確度**: 未検証(自己申告: 確定)

**影響**: 軽微だが、フォルダ許可プロンプトとファイル書き込みを伴うので副作用は小さくない。

**修正方針**: pointermove で 1 本でも描かれたかをフラグで追跡し、未描画なら collect で null を返す。

### P5-24 / 未検証 / `src/main.ts:410-414`

**貼ったテキストの「最初の見出しより前の本文」が、対象ノードではなく最深の末尾子孫に付く**

```
`        const n = byId.get(anchorId);`\n`        if (!n) return;`\n`        at = n.subEnd;`\n`        body = relevel(normalized, n.depth + 1).trimEnd();`
```

**症状**: 挿入位置がノード n の subEnd（n のサブツリー全体の末尾）なので、貼ったテキストのうち最初の見出しより前にある段落は、直前の「n の最も深い末尾の子孫ノード」の attached content として解釈される。「子として貼り付け」というメニュー表示と実際の帰属が食い違う。

**再現条件**: 1) `# R` / `## A` / `### A1` という文書を作る。2) 外部エディタで `まえがき` 改行空行 `# 見出し` 改行空行 `本文` をコピー。3) マップで A（深さ 2）を選択して Mod+V。4) md ペインを見ると `まえがき` は `### A1` の直後に入り、マップでは A1 側の内容に付く。A の直下ではない。

**確度**: 未検証(自己申告: 確定)

**影響**: 貼り付け結果の構造が直感と食い違う。他ツールからの取り込みでは普通に起きる。

**修正方針**: relevel 後、最初の見出しより前の行があれば切り出して insertContentLine と同じ位置（n の自前コンテンツ末尾）に入れる。あるいは破棄する旨を通知する。

### P5-25 / 未検証 / `src/relevel.ts:52`

**relevel に深さ上限が無く、深い位置への貼り付けで外部レンダラが解釈できない見出しが生成される**

```
`      return "#".repeat(Math.max(1, d + delta)) + line.slice(d);`
```

**症状**: targetDepth = n.depth + 1 に対して下限クランプ（Math.max(1, …)）はあるが上限が無い。core は深さ無制限を仕様としているので mmm 内では整合するが、書き出した .md を CommonMark / GitHub / Obsidian で開くと 7 個以上の `#` は見出しにならず段落として描画される。

**再現条件**: 1) `# R` / `## A` / `### B` / `#### C` / `##### D` の 5 階層を作る。2) 外部から `# X` 改行空行 `## Y` をコピー。3) D（深さ 5）を選択して Mod+V。4) md ペインに `###### X` と `####### Y` が入る。5) 保存して GitHub でプレビューすると `####### Y` がそのままのテキストとして描画される。

**確度**: 未検証(自己申告: 確定)

**影響**: 「git に乗る。差分がテキストとして読める」という設計目標に対して、外部レンダラでの可読性が失われる。

**修正方針**: 仕様として許容するなら文書化する。許容しないなら relevel の結果が 6 を超えるときに flashFilename で警告する。

### P5-26 / 未検証 / `src/main.ts:421-422`

**貼り付け後に新ノードが選択も表示もされない／コピー成功のフィードバックも無い**

```
`      const snap = core.replaceText(at, at, prefix + body + suffix, "");`\n`      applySnap(snap, "map");`
```

**症状**: runCmd（main.ts:231-242）を通る他のコマンドは snap.focus でフォーカス移動と map.ensureVisible を行うが、paste は applySnap のみで setSelection も ensureVisible もしない。copySelection（main.ts:374-379）も flashFilename を呼ばないので成功したか分からない（exportMap は成功時に flashFilename(..., false) を出しているのでアプリ内で一貫していない）。

**再現条件**: 1) ノードが 30 個以上ある文書でマップをスクロールし、画面外にあるノードを（md ペイン側の選択経由で）アンカーにする。2) 見出しを含むテキストを Mod+V。3) 画面上は何も変わらない。md ペインを見て初めて挿入されたと分かる。

**確度**: 未検証(自己申告: 確定)

**影響**: 取り込み操作の結果が不可視で、前述の hasHeadings 無反応と区別できない。

**修正方針**: paste の applySnap 前後の byId の差分から新ノード id を求めて setSelection し、map.ensureVisible する。copySelection は成功時に flashFilename("コピーしました", false) を出す。

### P5-27 / 未検証 / `src/main.ts:859-869`

**ドロップ時に .md 以外／複数ファイル／string アイテム先頭のケースが無言で扱われる**

```
`  const f = e.dataTransfer?.files?.[0];`\n`  if (!f || !/\.(md|markdown|txt)$/i.test(f.name)) return;`\n`  const item = e.dataTransfer!.items?.[0] as DataTransferItem & {`
```

**症状**: (a) .png / .json / フォルダを落としても何も起きず通知も無い（画像貼り付けを備えたアプリなので画像ドロップが無反応なのは機能欠落に見える）。(b) 複数 .md を落としても先頭 1 つだけ開き、残りは黙って捨てられる。(c) files[0] で名前を判定するのに handle は items[0] から取るため、両者が対応しないドラッグでは getAsFileSystemHandle が null になり fileHandle=null で開かれ、Ctrl+S が「名前を付けて保存」になる。

**再現条件**: (a) マップペインに .png をドロップ → 何も起きない。(b) .md を 2 つ選択してドロップ → 1 つ目だけ開く。(c) 要確認: items[0] が kind==="string" になる具体的なドラッグ元は環境依存。drop ハンドラ内で `[...e.dataTransfer.items].map(i=>i.kind)` を console に出し、kind が "string" 先頭になるアプリがあるか見れば決まる。

**確度**: 未検証(自己申告: 確定)

**影響**: (a)(b) は UX の欠落、(c) は保存先ハンドルが静かに失われる。

**修正方針**: (a) 画像ファイルなら saveImageToDisk → insertContentLine の経路に流す。それ以外は flashFilename で「.md ファイルを落としてください」。(b) 複数時は先頭を開く旨を通知。(c) items から kind==="file" のものを選ぶ。

---

## 領域: 非同期処理（await をまたぐ古い状態 / 競合する保存 / loadAsset・objectURL / catch 漏れ / ポップアップ中に届くイベント）— src/main.ts, src/popup.ts, src/editor.ts, src/mindmap.ts の非同期部分

**調べたもの**

- src/main.ts 全 1135 行を通読（persistence/idb, applySnap, host, file I/O, images, export, boot）
- src/popup.ts 全 236 行を通読（shell の Promise 化、collect の同期契約、3 つの popup）
- src/editor.ts 全 188 行を通読（updateListener → onUserEdits、fromCore アノテーションでのエコー防止、applySets）
- src/mindmap.ts 全 1814 行を通読（exportSvg の fetch/FileReader、pointer/keydown ハンドラ、beginEdit/endEdit/blur）
- src/coreApi.ts（全 API が同期）と core/api.mbt:98-110・core/doc.mbt:280-290（init_doc が next_id を 1 にリセット＝id が再利用される）を確認
- exportSvg の「live DOM から class を剥がす→clone→inline→戻す」(mindmap.ts:794-831) が最初の await より前で完結していること＝エクスポート中の再描画で選択表示が壊れないことを確認
- paste() のテキスト経路が await 後に anchorId / byId / core.getText() を読み直していること (main.ts:405-421) を確認。ここは古い状態を掴んでいない
- addLink/addCode/addDrawing が await 後に byId.has(id) を再確認していること (main.ts:429/438/449) を確認（ただし id 再利用のため無効＝下記 F-3）
- persistNow が発火時に core.getText() を読むため、デバウンス中に文書が入れ替わっても古いテキストを書かないことを確認 (main.ts:99-113)
- drop ハンドラが DataTransferItem の死ぬ前に handlePromise を同期取得していること (main.ts:863-869) を確認
- idbSet の呼び出し順＝IDB トランザクション生成順になるため persistHandle の追い越しは起きないことを確認 (main.ts:80-88, 514-516)
- editor.applySets/highlight の dispatch が CodeMirror の updateListener 内から呼ばれても再入エラーにならない経路（origin==='cm' では applySets をスキップ）を確認 (main.ts:183, editor.ts:113-142)
- map.endEdit() が editingId を先に -1 にしてから display:none にするため blur→commitEdit の再入が起きないことを確認 (mindmap.ts:920-925, 1290-1292)
- copySelection / paste / unlockAssets / persistHandle など void 付き Promise 全箇所の catch 有無を個別に確認

### P5-1 / 未検証 / `src/main.ts:571`

**saveFile に多重実行ガードが無く、連打すると createWritable がロック衝突して「保存失敗」を出す**

```
const w = await fileHandle.createWritable();
```

**症状**: 保存は成功しているのに（あるいは片方だけ成功して）ファイル名の横に赤く「保存失敗」が出る。console に NoModificationAllowedError。mmm.md の「保存できないときがある」の正体の候補。

**再現条件**: 1) FS API のある Chrome で .md を開く。2) Ctrl+S を押しっぱなしにする（キーリピートで keydown が毎秒 30 回ほど発火し、main.ts:891 が saveFile() を毎回起動する）。または「保存」ボタンを素早く 2 回クリックする。3) 先行する createWritable が close() する前に次の createWritable が走り、同一エントリの排他ロックで reject。AbortError ではないので main.ts:593-596 の分岐に落ち、flashFilename("保存失敗") が出る。

**確度**: 未検証(自己申告: 確定)

**影響**: 実際には保存できているのに失敗表示が出て、ユーザーは保存されていないと誤認する（逆に本当に失敗した回と区別できない）。

**修正方針**: モジュールスコープに `let saving: Promise<void> | null` を持ち、saveFile 冒頭で in-flight なら return（または直列化してキュー）し、btnSave も disabled にする。

### P5-2 / 未検証 / `src/main.ts:552`

**saveFile が await 前に掴んだ text/fileName を完了後に savedText / localStorage へ書き戻す（保存中に別ファイルを開くと保存済みテキストが壊れる）**

```
const text = core.getText();
```

**症状**: 開いたばかりで一切編集していないファイルに dirty ドットが点き続ける。リロード後も dirty のままで、beforeunload の警告が毎回出る。

**再現条件**: 1) 一度保存済みのファイルをリロードして復元ハンドルを持たせる（main.ts:1115-1121）。2) 編集して Ctrl+S。3) `requestPermission`（main.ts:559）の権限バブルが出ている間、ページはブロックされないので「開く」で別ファイル B を読み込む（loadText が fileName / savedText / LS_SAVED を B のものに更新する）。4) バブルの「許可」を押す。→ 中断していた saveFile が再開し、A のテキストを A のファイルに書いた後、main.ts:582 `savedText = text;` と main.ts:585-586 で **B の名前のもとに A のテキスト**を LS_SAVED / LS_NAME に保存する。以後 updateDirty() は永久に不一致。

**確度**: 未検証(自己申告: 確定)

**影響**: 保存済みベースラインが別文書のテキストで上書きされ、dirty 表示が恒久的に嘘になる。main.ts:568-569 で fileName / elFilename も遅れて上書きされるので表示ファイル名も入れ替わる。

**修正方針**: saveFile 開始時に世代番号（fileHandle と rev のペア）を捕まえ、書き込み完了後にその世代がまだカレントの場合だけ savedText / fileName / localStorage を更新する。

### P5-3 / 未検証 / `src/popup.ts:49`

**ポップアップ表示中でも window の capture キーハンドラが素通りし、文書を差し替えられる（init_doc で id が 1 から振り直されるので byId.has(id) ガードが機能しない）**

```
e.stopPropagation(); // keep map/global shortcuts out
```

**症状**: コードブロック用ポップアップで書いた内容が、まったく別のファイルの無関係なノードに挿入される。

**再現条件**: 1) ノードを選び Shift+C でコードポップアップを開き、コードを打つ（フォーカスは overlay 内の textarea）。2) Ctrl+O を押す。overlay の stopPropagation はバブル段階なので、main.ts:882-910 の `{ capture: true }` リスナのほうが先に走る。しかも Mod+O のガードは `mapPane.contains(document.activeElement)`（main.ts:895）で、activeElement は document.body 直下の overlay 内なので早期 return せず openFile() が走る。3) 別の .md を開く（loadText → core.initDoc → core/api.mbt:104 `st.next_id = 1` で id が 1 から再採番）。ポップアップは閉じられず残る。4) Ctrl+Enter で確定。main.ts:438 の `if (r && byId.has(id))` は、新文書の同じ番号の別ノードにヒットしてしまうため、insertContentLine が無関係な見出しの下にコードを差し込む。

**確度**: 未検証(自己申告: 確定)

**影響**: 開いたばかりのファイルが勝手に汚れる。Mod+S / Mod+/ も同様に素通りするので、ポップアップ中に保存やペイン切り替え（editor.focus() でフォーカス強奪）が起きる。ドロップでの読み込みも同じ経路。

**修正方針**: (a) popup 側は capture 段階で listen する（overlay に `{capture:true}` の keydown を付ける）か、開いている間フラグを立てて main.ts のグローバルハンドラを抑止する。(b) id だけでなく snapshot の rev（または文書世代カウンタ）を捕まえ、await 後に世代一致も確認する。

### P5-4 / 未検証 / `src/popup.ts:151`

**お絵描きポップアップが誰にもフォーカスを渡さないため、Esc/Mod+Enter が効かず、裏のマインドマップにキーが届く**

```
export function showDrawPopup(): Promise<Blob | null> {
```

**症状**: お絵描き中に Esc を押しても閉じない。d d と打つとポップアップの裏でノードが消え、確定しても絵が黙って捨てられる。

**再現条件**: 1) ノードを選択して Shift+D（mindmap.ts:1423）。showCodePopup(popup.ts:94) / showLinkPopup(popup.ts:126) と違い showDrawPopup には `queueMicrotask(() => …focus())` が無く、フォーカスは map-pane に残る。2) Esc を押す → overlay の keydown リスナ（popup.ts:48）はイベント経路に入らないので何も起きない。代わりに mindmap.ts:1295 の pane keydown が走り host.clearSelection() が呼ばれる。3) 続けて `d` `d` を打つ → deleteSelection でノードが消える。4) 絵を描いて「確定」ボタンを押す → main.ts:449 `if (blob && byId.has(id))` が false になり、描いた画像は保存も挿入もされず、エラーも出ずに消える。

**確度**: 未検証(自己申告: 確定)

**影響**: ポップアップが「モーダル」になっていない。キー入力が裏の文書を破壊し、成果物が無言で失われる。

**修正方針**: shell() 側で overlay（tabindex=-1）にフォーカスを移し、フォーカストラップを張る。少なくとも showDrawPopup でも canvas か確定ボタンに focus() する。

### P5-5 / 未検証 / `src/main.ts:873`

**drop ハンドラの async IIFE に catch が無く、しかも fileHandle をテキスト読み込みより先に代入している**

```
fileHandle = h?.kind === "file" ? (h as FileSystemFileHandle) : null;
```

**症状**: ドロップに失敗しても画面は何も変わらない（ファイル名も内容も前のまま）が、以後の Ctrl+S はドロップしたファイルへ書き込む。

**再現条件**: 1) 未保存の変更がある状態で .md をドラッグ＆ドロップ。2) confirmDiscard() の confirm ダイアログ（main.ts:614）が出ている間に、エクスプローラでその .md を削除またはリネームする。3) 「OK」を押す → main.ts:873 で fileHandle は新ファイルを指すが、直後の main.ts:874 `savedText = await f.text();` が NotFoundError で reject。main.ts:877 `})();` には catch が無いので Uncaught (in promise) だけが出て UI は無反応（openFile と違い flashFilename("読み込み失敗") も無い）。4) Ctrl+S → 前の文書の内容がドロップ先のパスへ書き込まれる（createWritable は消えたファイルを作り直す）。

**確度**: 未検証(自己申告: 確定)

**影響**: 保存先が黙って別ファイルにすり替わる。main.ts:511-513 のコメントが警告している「stale handle + fresh text」そのものが、失敗経路で成立する。

**修正方針**: await f.text() を先に済ませてから fileHandle を代入し、IIFE に `.catch(err => { fileHandle = prev; flashFilename("読み込み失敗"); })` を付ける。

### P5-6 / 未検証 / `src/main.ts:1119`

**boot の idbGet('handle')/('dir') が、解決前にユーザーが取得したハンドルを上書きする**

```
if (h && h.name === fileName) fileHandle = h;
```

**症状**: 起動直後に開いたファイルとは別フォルダの同名ファイルへ Ctrl+S が書き込む。

**再現条件**: 1) 事前に ~/a/notes.md を開いておく（handle が IndexedDB に永続化される）。2) リロード。3) IndexedDB のオープン（main.ts:71-79、DB オープン＋トランザクションで数十 ms）が完了する前に ~/b/notes.md をドラッグ＆ドロップする。ドロップ側は confirmDiscard→handlePromise→f.text() で先に fileHandle を b に設定し、その後 idbGet の then が走ると `h.name === fileName`（どちらも "notes.md"）が成立して **a のハンドルで上書き**される。4) Ctrl+S → ~/a/notes.md が b の内容で潰れる。同型の問題が main.ts:1125 `dirHandle = d;` にもあり、ブート中に画像貼り付けでフォルダを選ぶと永続化された古い dirHandle に戻される（結果 assetSegs が null → 「この md を含むフォルダを選んでください」）。

**確度**: 未検証(自己申告: 要確認)

**影響**: 名前一致だけでは同名別フォルダを弁別できない。成立すれば別ファイルの破壊。どちらの Promise が先に解決するかで結果が変わる（要確認: DevTools で idbGet の then とドロップ完了の順序をログして、ドロップ側が先になり得るか）。

**修正方針**: ブート時に世代フラグ（例 `let handleAdopted = false` / bootEpoch）を持ち、ユーザー操作で fileHandle・dirHandle が確定していたら then 側では代入しない。

### P5-7 / 未検証 / `src/main.ts:677`

**loadAsset が多重起動し得て、objectURL を revoke せずに上書きする（恒久リーク）**

```
assetUrls.set(path, url);
```

**症状**: 画像を含む文書を開くたびに blob URL が解放されずに残り、タブのメモリが増え続ける。

**再現条件**: 1) 画像を N 枚含む .md を開いた状態でリロード。2) ブート直後（main.ts:1122-1133 の idbGet('dir') の then が pending 資産に対して loadAsset を回す瞬間）に、ペイン上でクリックする。unlockAssets(main.ts:687-700) も同じ pending 配列を作って loadAsset を回すため、同じ path に対して 2 本の loadAsset が並走する。3) 先に完了した側が assetUrls に url1 を入れ、後発が main.ts:677 で url2 に **revoke せず**差し替える → url1 は誰にも revoke されない。saveImageToDisk(main.ts:832-834) では `if (old) URL.revokeObjectURL(old);` と正しく解放しているので、対処漏れであることが対比で分かる。同じ経路で、loadText の clearAssets(main.ts:631-634) 中に飛んでいた loadAsset が完了すると、消したはずの旧文書のエントリが新文書のキャッシュに復活する（assetSegs が await 後の fileHandle を読むため、旧文書の path を新文書のフォルダで解決する）。

**確度**: 未検証(自己申告: 確定)

**影響**: blob URL はファイル実体をメモリに固定するので、画像の多い文書ではセッション中に無視できない量が漏れる。加えて文書をまたいだキャッシュ汚染。

**修正方針**: loadAsset に in-flight Map（path→Promise）を持たせて多重起動を防ぎ、set 前に既存 URL を revoke。さらに開始時の fileHandle/dirHandle を引数で束ね、完了時に一致しなければ生成した URL を捨てる。

### P5-8 / 未検証 / `src/main.ts:697`

**unlockAssets が「拒否されたとき」もリスナを外すので、サムネイルはリロードするまで二度と復帰しない**

```
window.removeEventListener("pointerdown", unlockAssets, true);
```

**症状**: 一度「ブロック」を押すと、以後どこをクリックしても画像がプレースホルダのまま。loadAsset のコメント（main.ts:658「retried on the next user gesture」）が守られていない。

**再現条件**: 1) 画像入り .md を開いた状態でリロード。2) ペインをクリックすると権限プロンプトが出るので「ブロック」を選ぶ。3) ok=false のまま main.ts:697 で listener を外しているため、以降どれだけクリックしても loadAsset は再試行されない。さらに、removeEventListener が 2 つの await の **後**にあるので、プロンプト表示中に続けてクリックすると unlockAssets が何本も走り requestPermission が多重に呼ばれる。

**確度**: 未検証(自己申告: 確定)

**影響**: 誤って拒否したユーザーの復帰手段がリロードしかない。多重 requestPermission は Chrome では 2 本目が reject され catch で握り潰される。

**修正方針**: removeEventListener を `if (ok)` の内側に置き、加えて実行中フラグで多重起動を防ぐ。

### P5-9 / 未検証 / `src/main.ts:377`

**カット(Mod+X)がクリップボード書き込みの成否を待たず・握り潰したまま削除する**

```
void navigator.clipboard.writeText(text).catch(() => {});
```

**症状**: カットしたのにクリップボードは空（古い内容のまま）で、ノードだけが消える。

**再現条件**: 1) ノードを選択。2) ページからフォーカスが外れている状態（DevTools のコンソールにフォーカスを置いた状態、または権限が拒否されている環境）で Mod+X。3) writeText が NotAllowedError / "Document is not focused" で reject → catch(()=>{}) で無言。4) だが main.ts:378 `if (cut) host.deleteSelection();` は成否に関係なく実行され、ノードが消える。ペーストしても取れない。

**確度**: 未検証(自己申告: 確定)

**影響**: 見た目上のデータ消失（undo でしか戻せない上に、ユーザーはクリップボードに入っていると信じている）。

**修正方針**: cut のときは `await navigator.clipboard.writeText(text)` の解決後に deleteSelection し、reject 時は flashFilename でコピー失敗を知らせる。

### P5-10 / 未検証 / `src/main.ts:396`

**paste() の try が画像保存フロー全体を包んでおり、画像の保存失敗が「無言のテキスト貼り付け（＝何も起きない）」に化ける**

```
} catch {
```

**症状**: 画像を貼っても何も起きず、エラーもコンソールにも出ない。

**再現条件**: 1) md を開いた後、その .md をエクスプローラで別フォルダへ移動する（fileHandle は生きたまま）。2) 画像をクリップボードにコピーしてノードを選び Mod+V。3) pasteImage → saveImageToDisk → main.ts:763 `const base = await assetSegs(dir);` は try の外にあり、dir.resolve() の reject がそのまま伝播する。4) その例外は main.ts:386-398 の「clipboard.read が使えないとき用」の try に吸われ、テキスト経路へフォールバック。5) クリップボードにテキストが無いので `if (!clip.trim()) return;`（main.ts:400）で終了 → 完全に無反応。

**確度**: 未検証(自己申告: 確定)

**影響**: 画像貼り付けの失敗原因がユーザーにもログにも一切残らない。try の意図（clipboard.read の可用性判定）と実際のカバー範囲がずれている。

**修正方針**: try のスコープを `navigator.clipboard.read()` の呼び出しだけに絞り、pasteImage は外側で await して失敗時に flashFilename する。saveImageToDisk の assetSegs も try に入れる。

### P5-11 / 未検証 / `src/main.ts:839`

**pasteImage の貼り付け先が「クリップボード読み取り完了後の anchorId」なので、権限プロンプト中に選択を変えると別ノードに入る**

```
const targetId = anchorId;
```

**症状**: Mod+V で貼った画像が、貼ったつもりのノードではなく後からクリックしたノードに入る。

**再現条件**: 1) 初回の画像ペーストでクリップボード読み取り権限のプロンプトが出る状態にする。2) ノード A を選び Mod+V。main.ts:387 の `anchorId !== -1` チェックは A で通るが、その後 `await navigator.clipboard.read()`（main.ts:388）と `await item.getType(t)`（main.ts:391）で待たされる。3) プロンプトが出ている間にノード B をクリック（ページはブロックされていない）。4) 「許可」を押す → pasteImage が走り、main.ts:839 は **今の** anchorId ＝ B を読む。画像は B に入る。

**確度**: 未検証(自己申告: 確定)

**影響**: 入口のガードと実際の挿入先が別の時点の状態を見ている。長い await（権限プロンプト）があるほど食い違う。

**修正方針**: paste() の同期部分で targetId を確定させ、pasteImage に引数で渡す。併せて rev も渡して、文書が入れ替わっていたら中止する。

### P5-12 / 未検証 / `src/main.ts:519`

**confirm を挟むためユーザー操作の有効期限（transient activation）が切れ、ファイルピッカーが拒否される**

```
if (!(await confirmDiscard())) return;
```

**症状**: Ctrl+O を押してダイアログに OK と答えたのに、ファイル選択が開かず「読み込み失敗」だけが出る。

**再現条件**: 1) 未保存の変更がある状態で Ctrl+O。2) 「未保存の変更があります…」の confirm を 6 秒以上放置してから OK を押す。3) transient user activation（約 5 秒）が切れているため main.ts:522 の showOpenFilePicker が SecurityError で reject。AbortError ではないので main.ts:544-547 で console.error + 「読み込み失敗」。同型のリスクが main.ts:714 showDirectoryPicker（clipboard.read の await を挟んだ後に呼ばれる）と main.ts:1046 navigator.clipboard.write（exportSvg の fetch/FileReader の後）にもある。

**確度**: 未検証(自己申告: 要確認)

**影響**: 操作が失敗したように見え、原因表示も誤り（読み込み失敗＝ファイルが壊れている、と誤解させる）。

**修正方針**: 要確認: DevTools で「confirm を長時間放置→OK」を試し、reject の name が SecurityError/NotAllowedError かを見る。修正はカスタムモーダル（非ブロッキング）へ置き換えるか、activation が切れた場合の専用メッセージを出す。

### P5-13 / 未検証 / `src/main.ts:532`

**非 FS 経路の input.onchange が async かつ catch 無しで、失敗時に無言で終わる**

```
input.onchange = async () => {
```

**症状**: ファイルを選んだのに何も読み込まれず、エラーも出ない。

**再現条件**: FS API の無いブラウザ（または hasFs=false 環境）で「開く」→ ファイルを選ぶ →（読み取り中にそのファイルを削除するなどで）`await f.text()`(main.ts:535) が reject。onchange の戻り値の Promise は誰も受け取らないため、openFile の try/catch（main.ts:543）にも入らず Unhandled rejection のみ。fileHandle は既に null 化済み（main.ts:534）。

**確度**: 未検証(自己申告: 確定)

**影響**: 読み込み失敗が UI に一切出ない（FS 経路とはエラーハンドリングの品質が非対称）。

**修正方針**: onchange をハンドラ内で try/catch し、失敗時に flashFilename("読み込み失敗") を呼ぶ。

### P5-14 / 未検証 / `src/main.ts:561`

**権限拒否で fileHandle を null にするとき persistHandle() を呼んでいない（lockstep コメントの契約破り）**

```
if (r !== "granted") fileHandle = null;
```

**症状**: 権限を拒否して保存ダイアログもキャンセルした後、リロードすると同じ古いファイルが再び保存先として復活する。

**再現条件**: 1) 復元ハンドルのある状態で Ctrl+S。2) 権限プロンプトを拒否 → main.ts:561 で fileHandle=null になるが IndexedDB の 'handle' は古いまま。3) 続く showSaveFilePicker(main.ts:564) を Esc でキャンセル → AbortError で catch。4) リロード → main.ts:1119 で名前が一致するので古いハンドルが再採用される。以後の Ctrl+S は再びそのファイルを狙う。

**確度**: 未検証(自己申告: 確定)

**影響**: main.ts:511-513 のコメント（「persist と fileHandle を lockstep に保つ」）が守られていない箇所。単体では致命的でないが、F-6 の名前一致だけの再採用と組み合わさると誤爆先が増える。

**修正方針**: fileHandle を null にする全経路（main.ts:534, 561, 873）で persistHandle() を呼ぶ。

### P5-15 / 未検証 / `src/main.ts:448`

**popup の .then に catch が無く、例外時に mapPane.focus() の復帰も飛ぶ**

```
void showDrawPopup().then(async (blob) => {
```

**症状**: ポップアップを閉じた後、マップペインでキーが一切効かなくなる（クリックし直すと直る）。

**再現条件**: main.ts:449-456 の then コールバック内で saveImageToDisk（→ main.ts:763 の assetSegs は try の外）や insertContentLine が throw すると、`void …then(…)` には catch が無いので Unhandled rejection になり、main.ts:455 の `mapPane.focus()` に到達しない。ポップアップは既に DOM から消えているため、フォーカスは detach 済み要素＝実質 body に落ちる。addLink(main.ts:428) / addCode(main.ts:437) も同じ形。

**確度**: 未検証(自己申告: 要確認)

**影響**: キーボード操作が無言で死ぬ。要確認: DevTools で「Uncaught (in promise)」が出た直後に document.activeElement を見る（body になっているはず）。

**修正方針**: `.finally(() => mapPane.focus())` にし、`.catch()` で flashFilename する。

### P5-16 / 未検証 / `src/mindmap.ts:837`

**exportSvg の blob: 取得失敗を握り潰し、画像が抜けたまま「成功」する**

```
const b = await (await fetch(href)).blob();
```

**症状**: 書き出した SVG / WebP から画像だけが消えているのに、エラーも警告も出ない。

**再現条件**: 1) 画像サムネイル付きのマップで SVG エクスポートを実行。2) fetch 待ちの間に別ファイルを開く（loadText → clearAssets(main.ts:631-634) が blob URL を revoke する）か、同名画像を貼り直す（main.ts:833 が revoke する）。3) 残りの fetch が TypeError → mindmap.ts:846 `img.remove();` で該当画像を消したまま書き出しが完了し、main.ts の catch にも入らないので成功扱い。

**確度**: 未検証(自己申告: 要確認)

**影響**: 出力物が黙って欠落する。要確認: エクスポート中に別ファイルを開いて、出力 SVG の <image> 数が減るかを数える。

**修正方針**: 失敗を数えて 1 件でもあれば flashFilename("一部の画像を埋め込めませんでした") を出す。あるいは fetch ではなく assetUrls 側の元 Blob を保持して読む。

### P5-17 / 未検証 / `src/main.ts:678`

**loadAsset 完了時の map.render() がドラッグ中のドロップ表示を消す**

```
map.render();
```

**症状**: ノードをドラッグしている最中に、ドロップ先を示すリング（drop-child）が突然消える。

**再現条件**: 画像を含む文書で、サムネイル読み込みが未完のままノードのドラッグを開始し、ドラッグ中に loadAsset が解決する。mindmap.ts:1669-1682 の drop-child クラスは updateDrop でしか付かず、render() は dragging クラスしか復元しない（mindmap.ts:592）ので、次の pointermove まで指示子が消える。

**確度**: 未検証(自己申告: 要確認)

**影響**: 仕様 3.3.2 の「ドロップ指示子は必須」が一瞬破れる。実害は視覚のみ。要確認: 大きめの画像でサムネイル読み込みを遅らせて再現するか確認。

**修正方針**: render() 内で this.dropTarget からも drop-child を復元する（または loadAsset 中の render を dragging 中は遅延させる）。

### P5-18 / 未検証 / `src/editor.ts:108`

**compositionend で typeKind を先に潰しており、IME 確定分が別 undo エントリになる可能性**

```
compositionend: () => {
```

**症状**: IME で 1 語入力して確定した後、Mod+Z を 1 回押しても語全体が消えず 2 回必要になる。

**再現条件**: md ペインで IME をオンにし「にほんご」と入力して確定 → Mod+Z を 1 回押す。Chrome では compositionend（DOM イベント）が CodeMirror の最終トランザクション（input.type.compose）より先に届くため、main.ts:252-254 で typeKind が "" にリセットされ、直後の最終編集が新しいタグ t{n} を取って別エントリになる。

**確度**: 未検証(自己申告: 要確認)

**影響**: IME 入力の undo 粒度が壊れる（1 語が 2 手に割れる）。要確認: onUserEdits の先頭に console.log(userEvent, tag) を入れて、compose.end と最後の input.type.compose の到着順とタグを観察すれば確定する。

**修正方針**: compose.end は即座に潰さず「次の非 compose 編集で潰す」遅延フラグにする（例 pendingComposeBreak）。

### P5-19 / 未検証 / `src/popup.ts:43`

**shell() の commit が collect の TDZ を参照している（build が同期 commit したらクラッシュ）**

```
const val = collect();
```

**症状**: 現状の 3 つの popup では踏まないが、build 内で同期的に commit() を呼ぶ実装を足すと ReferenceError: Cannot access 'collect' before initialization。

**再現条件**: popup.ts:59 `const collect = build(body, commit);` より前に commit が呼ばれる経路を作る（例: build 内で `if (prefill) commit();`）と即座に落ちる。今は commit の呼び出しがすべてイベント/マイクロタスク経由なので顕在化していない。

**確度**: 未検証(自己申告: 要確認)

**影響**: 潜在的な時限爆弾。collect が同期契約であること自体は守られている（showDrawPopup は toBlob を避けて toDataURL を使っている: popup.ts:221-233）。

**修正方針**: collect を let で先に宣言するか、commit を `() => { const v = collectRef.current?.(); … }` にする。

### P5-20 / 未検証 / `src/main.ts:1001`

**downloadBlob / 非 FS 保存が click 直後に objectURL を revoke している**

```
URL.revokeObjectURL(a.href);
```

**症状**: ブラウザによってはダウンロードが 0 バイト / 失敗になる。

**再現条件**: main.ts:996-1002（エクスポート）と main.ts:576-580（非 FS 環境の保存）はどちらも `a.click()` の直後に同期で revoke している。Chrome はクリック時点でダウンロードを開始するため通常は成功するが、a を DOM に追加していないこともあり実装依存。

**確度**: 未検証(自己申告: 要確認)

**影響**: 要確認: FS API の無いブラウザ（Firefox/Safari）で保存とエクスポートを実行し、ファイルが正しい内容で落ちるかを見る。

**修正方針**: revoke を setTimeout(…, 60_000) か次のイベントループに送る。

