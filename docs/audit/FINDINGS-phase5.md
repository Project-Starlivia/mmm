# フェーズ5: バグ洗い出し(9領域)

9 領域それぞれを独立したパスとして通し、各指摘を「反証しにいく」検証パスに
掛けた。**9 領域すべてで探索・検証の両方が完走している。**

| 表示 | 意味 |
|---|---|
| **CONFIRMED** | 別のエージェントがコードを開き直して反証を試み、それでも残ったもの |
| **要確認** | 反証パスが「ソースだけでは決まらない」と判定したもの。何を見れば決まるかを併記 |
| **反証により除外** | 反証が成功したもの。本文からは外し、各領域の末尾に理由つきで残す |

検証は追認になっていない: 実際に **REFUTED が出ており**、その理由は
「pointer events の chorded-button 規則によりその手順は発火しない」
「その呼び出しはローカルに捕まえた値ではなくグローバルを読む」
「createWritable は WHATWG 仕様上 shared ロックなので競合しない」
のように具体的である。

なお本文書と別に、監査本体で**実測により確定させた** 11 件が
`audit/FINDINGS.md`(F-001〜F-009, S-001〜S-002)にある。そちらは
ブラウザ実測・Playwright 計測・往復テストのいずれかで裏を取っている。

## 概要

| # | 領域 | 指摘 | CONFIRMED | 要確認 | 反証で除外 | 判定なし |
|---|---|---|---|---|---|---|
| 1 | IME | 9 | 4 | 5 | 0 | 0 |
| 2 | キャレット | 16 | 14 | 0 | 1 | 1 |
| 3 | キーボード | 16 | 14 | 1 | 1 | 0 |
| 4 | ツリー操作 | 14 | 12 | 0 | 2 | 0 |
| 5 | markdown | 24 | 23 | 0 | 1 | 0 |
| 6 | XSS | 10 | 8 | 1 | 1 | 0 |
| 7 | 永続化 | 19 | 17 | 1 | 1 | 0 |
| 8 | エクスポート | 33 | 27 | 6 | 0 | 0 |
| 9 | 非同期 | 26 | 21 | 2 | 3 | 0 |
| | **合計** | **167** | **140** | **16** | **10** | **1** |

---

## 1. IME / 日本語入力（editor.ts, main.ts, mindmap.ts, popup.ts の composition 経路）

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

### P5-IME-1 / CONFIRMED / `src/mindmap.ts:1276`

**ラベル編集の input ハンドラに composition ガードが無く、変換途中の文字列が全部 md 本文に書き込まれる**

```
this.host.rename(this.editingId, this.editor.value, this.editingTag);
```

**症状**: IME 変換中も input イベントは inputType=insertCompositionText で毎回発火するが、mindmap.ts:1274-1279 の input ハンドラには isComposing の判定が一切ない。結果、未確定の読み（"n" → "に" → "にh" → "にほ" …）と候補選択の一つ一つが core.renameNode → applySnap("map") 経由で本物のドキュメント変更になる。1 打鍵ごとに (1) md 本文の書き換え、(2) editor.applySets による CodeMirror へのトランザクション dispatch (main.ts:183)、(3) map.render() の全 SVG 再構築 (main.ts:198)、(4) schedulePersist() による localStorage 保存 (main.ts:203) が走る。さらに positionEditor() (mindmap.ts:1277 と render 末尾 728) がノード幅を再計算して input の left/top/width を書き換えるため、変換中に入力欄そのものが動く（左側グループのノードは幅が伸びると x が減るので入力欄が左へずれていく）。

**再現条件**: 1) npm run dev でアプリを開く。2) マップペインでノードを 1 つ選択し i を押してラベル編集に入る。3) 日本語 IME を ON にして nihongo と打つ（Space も Enter もまだ押さない）。4) md ペインを見ると見出し行が打鍵ごとに `# n` → `# に` → `# にh` → `# にほ` → `# にほn` → `# にほんg` → `# にほんご` と書き換わる。5) Space を連打して候補を切り替えると、候補を 1 つ送るたびに md 本文が書き換わりマップ全体が再レイアウトされ、入力欄が横に伸縮して IME の候補ウィンドウの位置がずれる。6) この状態でページをリロードすると localStorage から未確定のローマ字混じりのテキストが復元される。

**確度**: 確定

**検証の根拠**: src/mindmap.ts:1274-1279 の input ハンドラは isComposing を一切見ずに host.rename を呼ぶ（引用は 1276 行と正確に一致）。src/main.ts:336-338 rename → applySnap(...,"map") で、editor.applySets(main.ts:183)・map.render()(main.ts:198)・schedulePersist()(main.ts:203) が毎回走る。render() の末尾は src/mindmap.ts:727-728 で updatePlus(); positionEditor(); なので入力欄の再配置も確定。左側フレームは src/mindmap.ts:471-478,516 で cx=-(edge+w/2), x=cx-w/2 = -(edge+w) となり、幅が伸びると x が減る（＝左へずれる）という記述も正しい。core 側も src/coreApi.ts:53-54 → core/cmds.mbt:230-246 でラベル行をそのまま書き換える（sanitize_label は core/cmds.mbt:16-35 で改行→空白と前後トリムのみ）ので、未確定の読みが本文に入るのは確定。

**検証による訂正**: 3 点だけ補正。(1) localStorage 書き込みは 1 打鍵ごとではない — schedulePersist は main.ts:110-113 の 250ms デバウンスなので、候補選択などで 250ms 以上手が止まった時点、または pagehide(main.ts:115) で未確定文字列が保存される。再現手順 6) は成立するが「打鍵ごとに保存」は誇張。(2) undo 粒度は壊れない。編集セッションは main.ts:461-462 の 1 タグを使い回し、core/doc.mbt:218-238 が同一 tag をトップエントリにマージするので Undo 1 回で編集前ラベルに戻る。(3) 影響 (c)「候補ウィンドウが飛ぶ」は positionEditor が left/top/width を書き換える事実までしかコードで確定できず、IME 候補ウィンドウ追従の可否はブラウザ観察が必要。

**影響**: (a) 変換確定前の中間状態が単一の真実であるはずの markdown に流れ込み、localStorage にも保存される。(b) F-002 の新しい帰結として、ASCII 1 文字＝1 render に対し日本語 1 文字は打鍵＋候補送りで 3〜10 render になる。2001 ノードで 66ms/render なので、候補を 10 個送るだけで 0.6 秒以上 UI が固まる。変換中に同期処理で数十 ms 止まると IME の候補ウィンドウが追従せず打鍵取りこぼしの原因になる。(c) 入力欄が変換中に移動するため候補ウィンドウが飛ぶ。

**修正方針**: input ハンドラの先頭で composition 中（compositionstart/compositionend でフラグを持つか (e as InputEvent).isComposing）を判定して host.rename をスキップし、compositionend でまとめて 1 回 rename する。positionEditor() も composition 中は呼ばない。

### P5-IME-2 / CONFIRMED / `src/mindmap.ts:1044`

**変換確定前にマップの別の場所をクリックすると、未変換の読み（末尾のローマ字ごと）がラベルとして確定される**

```
if (this.isEditing()) this.host.commitEdit();
```

**症状**: pane の pointerdown は blur より先に走るため、composition がまだ生きているうちに commitEdit() → endEdit() が呼ばれ、endEdit は mindmap.ts:923 で `this.editor.style.display = "none"` にする（＝composition 中の要素をそのまま非表示にする）。ドキュメントに残るのは finding #1 の input ハンドラが最後に書き込んだ「未確定の読み」であり、ローマ字の途中状態（例: 「にほn」）がそのままラベルになる。cancel の概念が無い仕様（1272-1273 のコメント）なので巻き戻す手段もない。

**再現条件**: 1) ノードを選択して i でラベル編集に入る。2) IME で nihon まで打つ（入力欄には「にほn」と表示されている状態）。3) 変換も確定もせずにマップの別のノードをクリックする。4) ラベルが「にほn」で確定され、md 本文の見出しも `## にほn` になる。5) Undo すると編集セッション全体（editingTag 1 個ぶん）が丸ごと戻るので、途中まで打った内容は残らない。

**確度**: 確定

**検証の根拠**: src/mindmap.ts:1040-1044 は引用どおりで、e.target が editor 以外なら commitEdit() を呼ぶ。main.ts:339-344 commitEdit → src/mindmap.ts:920-925 endEdit が editingId=-1 を先に立ててから display:none にするため、非表示後に composition 由来の input が来ても 1275 行の `if (this.editingId !== -1)` で捨てられる。つまりドキュメントに残るのは最後の input イベントが書いた未確定の読みで、finding #1 で確認したとおりそれは本文に書かれている。

**検証による訂正**: 「pointerdown が blur より先に走る」ことは本件の成否に効かない。src/mindmap.ts:1290-1292 の blur ハンドラも同じ host.commitEdit() を呼ぶので、どちらが先でも結果は同じ（順序が問題になるのは二重 commit の有無だけで、endEdit が editingId=-1 にするため二重にはならない）。また影響の「巻き戻す手段もない」は誤り — 編集セッション全体が 1 タグ（main.ts:461-462 + core/doc.mbt:218-238 のマージ）なので、u / Mod+Z 1 回で編集前のラベルに完全に戻せる。残る実害は「ゴミ文字列がいったん本文と localStorage に入る」ことと、Undo が編集全体を巻き戻すので途中まで打った分も消えること。

**影響**: 日本語入力の最もありふれた中断操作（変換前に他をクリック）でゴミ文字列が確定し、しかもキャンセル手段が無い。finding #1 を直さない限り commitEdit 側だけでは直らない。

**修正方針**: commitEdit / endEdit の前に composition 中なら input を blur して IME に確定させる（もしくは finding #1 の修正で「最後に確定した値だけを書く」ようにする）。display:none にする前に this.editor.blur() を挟むだけでも中間状態の混入は減る。

### P5-IME-3 / 要確認 / `src/popup.ts:50`

**popup.ts の keydown ハンドラ 3 箇所に IME ガードが無い（Esc で変換取り消し＝ポップアップごと破棄）**

```
if (e.key === "Escape") {
```

**症状**: popup.ts には composition / isComposing / keyCode の記述が 1 つも無い（grep でゼロ件）。overlay の keydown (48-57) は Escape で close(null)、Ctrl/Cmd+Enter で commit する。加えて code textarea の Tab ハンドラ (86-92) は composition 中でも setRangeText でテキストを書き換え、link popup の url/title の Enter ハンドラ (118-123) は Enter で即 commit する。IME 変換中の Esc は「変換の取り消し」、Enter は「変換の確定」、Tab は IME によっては候補一覧の展開で、いずれも本来アプリに届いてはいけないキー。本プロジェクトの他の 3 経路（main.ts:885 / mindmap.ts:1281 / mindmap.ts:1326）はすべて `e.isComposing || e.keyCode === 229` でガードしているので、popup だけが例外になっている。

**再現条件**: 1) ノードを選択して Shift+C でコードポップアップを開く。2) textarea に日本語をたくさん打ち込み、最後の語を変換中（候補ウィンドウが出た状態）にする。3) Esc を押して変換だけ取り消そうとする。4) 期待: 変換のみ取り消し。実際に overlay の keydown に key==="Escape" が届く環境では close(null) が走り、ポップアップが閉じて入力内容が全部消える。要確認: この環境の Chrome/Windows では変換中のキーは key="Process" / keyCode=229 で来るため届かない可能性がある。popup.ts:48 の先頭に console.log(e.key, e.keyCode, e.isComposing) を仕込んで、変換中の Esc / Enter がどの値で来るかを 1 回見れば確定する（key が "Escape"/"Enter" のまま来るなら再現、"Process" なら現環境では非再現だがガード欠如は残る）。

**確度**: 要確認

**検証の根拠**: popup.ts を全文読んだ: composition / isComposing / keyCode の記述はゼロで、overlay keydown(popup.ts:48-57)・code textarea の Tab(86-92)・link popup の Enter(118-123) はいずれも e.key だけを見ている（引用の 50 行も一致）。他 3 経路のガードも実在を確認（src/main.ts:885, src/mindmap.ts:1281, src/mindmap.ts:1326）。再現の入口 Shift+C も src/mindmap.ts:1417-1424 → src/main.ts:435-445 で確認。ただし「変換中の Esc/Enter/Tab が key="Escape" 等のままハンドラに届くか」はコードでは決まらない。決着方法は finding の記載どおりで妥当。

**検証による訂正**: 環境を明記すべき。本環境は Windows 11 + Chromium 系であり、Chromium は IME に消費されたキーを keydown key="Process" / keyCode=229 で配送するため、popup.ts:50 の `e.key === "Escape"` も 119 行の `e.key === "Enter"` も一致せず、現環境では非再現の公算が高い。したがって「入力内容が Esc 一発で消える」は現時点では未実証で、確定しているのは『4 つ目以降のキー経路として popup.ts の 3 ハンドラだけが IME ガードを持たない』という非対称性のみ。決定的観察は finding 記載のログ（popup.ts:48 冒頭で e.key / e.keyCode / e.isComposing を 1 回見る）で足りる。

**影響**: 再現する環境では、長いコードや日本語タイトルを入力した内容が Esc 一発で無警告に消える（このポップアップにキャンセル確認は無い）。link popup の Enter は変換確定のつもりが未変換タイトルで commit される。

**修正方針**: popup.ts の 3 つの keydown ハンドラ冒頭に `if (e.isComposing || e.keyCode === 229) return;` を追加する（他の経路と同じガード）。

### P5-IME-4 / 要確認 / `src/editor.ts:109`

**compositionend の境界マーカーが CM6 の遅延フラッシュより先に走るため、composition の末尾が次の composition と同じ undo エントリに入る**

```
onUserEdits([], "compose.end");
```

**症状**: CM6 の observers.compositionend（node_modules/@codemirror/view/dist/index.js:5266-5285）は compositionend の時点で pendingRecords があると `Promise.resolve().then(() => view.observer.flush())` で最後の変更をマイクロタスクに遅延させる。そのフラッシュが作るトランザクションの userEvent は同 4417-4426 の条件で "input.type.compose" になる。つまり順序は必ず「compose.end（main.ts:251-252 で typeKind=""）→ 遅れて input.type.compose」。main.ts:259-262 は typeKind!=="compose" を見て新しいタグ t(n+1) を採番し typeKind="compose" に戻すので、(1) composition #1 の末尾変更が本体と別の undo エントリになり、(2) 次に始まる composition #2 の更新は typeKind が "compose" のままなので t(n+1) を再利用して #1 の末尾と同じエントリにマージされる。doc.mbt:221-238 のマージ条件（直前エントリの tag 一致）から、これは undo 境界が composition の途中に落ちることを意味する。editor.ts:106-107 のコメントが宣言している「2 つの composition が 1 つの undo に混ざらない」保証が、まさにその末尾変更があるときに破れる。

**再現条件**: 1) main.ts:295 の for ループ直前に console.log(userEvent, tag, JSON.stringify(edits)) を一時的に入れる。2) md ペインで「日本語」を変換確定し、続けて「入力」を変換確定する。3) ログに `compose.end` の後に `input.type.compose` が現れるかを見る。現れたら確定: その行のタグと、その次の composition の各行のタグが同じ t 番号になっているはず。4) その状態で Mod+Z を 1 回押すと、1 回目の変換の末尾＋2 回目の変換がまとめて消え、1 回目の変換の途中状態が残る。要確認なのは compositionend 時に pendingRecords が非空になるかで、これはブラウザ/IME 依存。

**確度**: 要確認

**検証の根拠**: CM6 実体を確認: node_modules/@codemirror/view/dist/index.js:5266-5290 の observers.compositionend は compositionPendingChange = view.observer.pendingRecords().length > 0 とし、真なら Promise.resolve().then(() => view.observer.flush()) で遅延フラッシュする。そのトランザクションの userEvent は 4417-4426 で view.composing が false でも compositionPendingChange && compositionEndedAt > Date.now()-50 により "input.type.compose" になる（compositionFirstChange は 5271 で null 化済みなので ".start" は付かず、src/editor.ts:118-131 のマッチ表に正しく当たる）。src/editor.ts:108-111 の compositionend ハンドラは同期、遅延フラッシュはマイクロタスクなので順序も finding のとおり。src/main.ts:251-262 で compose.end が typeKind="" にし、遅延フラッシュが t(n+1) を採番して typeKind="compose" に戻し、以後 applySnap(...,"cm") は main.ts:197 で typeKind をリセットしないため、次の composition が同じタグを再利用する。core/doc.mbt:218-238 のトップエントリ tag 一致マージにより実際に 1 エントリへ融合する。ここまでは全てコードで確定。

**検証による訂正**: 未確定なのは 1 点だけで、finding もそう書いている: compositionend 時点で pendingRecords が非空になるか（＝遅延フラッシュが doc 変更トランザクションを生むか）。日本語 IME の確定 Enter では候補文字列が既に DOM に入っており DOM 変更が出ないケースがあり得るため、その場合は 5283-5289 の else 分岐（setTimeout 50ms の update([])）に落ちて本バグは発生しない。決着させる観察は finding の手順 3) のログで十分。なお症状の説明は正確で、壊れるのは undo 境界だけ（本文内容は壊れない）。

**影響**: undo の粒度が composition 単位にならず、境界が変換の途中に落ちる。1 回 Undo すると中途半端なかな/ローマ字が本文に残る。

**修正方針**: compose.end で typeKind をすぐ消さず、compose.end のフラグだけ立てておいて「次に来た input.type.compose が compose.end 直後（同一マイクロタスク/50ms 以内）なら前のタグを継続、それ以降なら新タグ」にする。もしくは境界判定を compositionstart 側に移す。

### P5-IME-5 / 要確認 / `src/mindmap.ts:1281`

**確定用の Enter が compositionend の後に isComposing=false で届くケースにガードが無く、ラベル編集が変換確定の Enter で閉じる**

```
if (e.isComposing || e.keyCode === 229) return;
```

**症状**: node-editor / map pane / global の 3 経路のガードはいずれも「その keydown 自体が composition 中かどうか」しか見ていない。CM6 は同じ問題に対して ignoreDuringComposition（node_modules/@codemirror/view/dist/index.js:4645-4659）で `browser.safari && this.compositionPendingKey && Date.now() - this.compositionEndedAt < 100` という 100ms の猶予を追加しており、ソース中のコメントが「Safari では compositionend と keydown が逆順に出ることがある」と明言している。mmm 側にはこの猶予が無いので、その環境では変換確定の Enter が素の keydown として mindmap.ts:1283 に届き、host.commitEdit() が走ってラベル編集が閉じてしまう（Enter は「確定」なのでキャンセルにはならないが、変換を確定しただけのつもりで編集モードから抜ける）。

**再現条件**: 1) mindmap.ts:1281 の直前に console.log(e.key, e.keyCode, e.isComposing, Date.now()) を入れ、compositionend にも log を足す。2) ノードのラベル編集に入り「にほんご」を Space で変換し Enter で確定する。3) compositionend のログの後に key="Enter"/isComposing=false の keydown ログが出るかを見る。出たら確定（＝その 1 回目の Enter で編集が閉じる）。Chrome/Windows では keyCode=229 で来るはずなので非再現、Safari で再現する既知パターン。

**確度**: 要確認

**検証の根拠**: src/mindmap.ts:1281 の引用は正確で、猶予ウィンドウは無い。CM6 側の対比も実在する: node_modules/@codemirror/view/dist/index.js:4645-4660 の ignoreDuringComposition に `browser.safari && !browser.ios && this.compositionPendingKey && Date.now() - this.compositionEndedAt < 100` と、Safari で compositionend と keydown が逆順になるというコメントがある。よって『同種の猶予が mmm 側に無い』は確定、『その環境で実際に Enter が素通しされるか』はブラウザ観察でしか決まらない（現環境の Chromium/Windows では keyCode 229 で来るので非再現）。

**検証による訂正**: 影響範囲の「3 経路すべて（main.ts:885 / mindmap.ts:1281 / 1326）に同じ穴がある」は誤り。実害があるのは src/mindmap.ts:1281 の 1 経路のみ。(a) src/main.ts:885 は直後の 886-887 で `if (!mod) return` なので裸の Enter は無視される。(b) src/mindmap.ts:1326 は 1327 の `if (this.isEditing()) return` があり、かつこのハンドラは #map-pane（index.html:39 の tabindex 付き非編集 div）にフォーカスがある時しかイベントを受けないので composition 自体が成立しない。また症状も軽め: rename は既に本文へ書き込み済みなのでラベルは失われず、起きるのは「確定と同時に編集モードが閉じる」ことだけ。

**影響**: 変換確定の Enter が編集終了とぶつかる。ラベルを続けて打てず、毎回 i を押し直すことになる。3 経路すべて（main.ts:885 / mindmap.ts:1281 / 1326）に同じ穴がある。

**修正方針**: compositionend の時刻を記録し、`Date.now() - lastCompositionEnd < 100` の間の Enter/Escape を無視する（CM6 と同じ手当て）。node-editor に compositionstart/end リスナを追加するだけで済む。

### P5-IME-6 / 要確認 / `src/main.ts:199`

**md ペインで変換中に見出しが壊れると、composition の最中に CodeMirror へ decoration トランザクションが dispatch される**

```
if (selChanged) syncSelectionViews(false);
```

**症状**: applySnap は origin==="cm" のとき editor.applySets をスキップする（183 行）ので通常は composition 中に CM へ dispatch しない。しかし選択中のノードの id が消えると 192-195 で selChanged が立ち、199 で syncSelectionViews → editor.highlight（editor.ts:168-170 の view.dispatch）が走る。この dispatch は CM の updateListener（editor.ts:113-142）の中から同期的に、しかも composition が生きているまさにその行に対して decoration を張り替える形で発生する。CM6 は composition ノードを保護しようとするが、composing 中の行の DOM を作り直す変更は composition を壊す典型パターン。

**再現条件**: 1) マップで末尾のノード（例: 「双方向編集」）をクリックして選択する（md ペインでハイライトされる）。2) md ペインでその見出し行の行頭、`#` の直前にカーソルを置く。3) IME を ON にして「あいうえお」を変換せずに打ち始める。4) 1 文字目が入った瞬間に `# ` が行頭でなくなって見出しが消え、そのノードの id が消え、selChanged→highlight dispatch が composition 中に走る。5) 変換が中断される／候補ウィンドウが閉じる／打った文字が欠けるかを観察する。要確認なのは 5) の見え方のみで、dispatch が起きること自体はコードから確定。

**確度**: 要確認

**検証の根拠**: dispatch が起きること自体はコードで確定した。src/main.ts:183 は origin==="cm" で applySets を飛ばすが、186-195 で選択ノードの id が消えれば selChanged が立ち、199 で syncSelectionViews → src/editor.ts:168-170 の view.dispatch が走る。id が本当に消えることも core 側で確認: core/doc.mbt:113-136 の map_offset は「見出し先頭への改行で終わらない純挿入」で p をそのまま返し、core/doc.mbt:278-284 の rebuild_nodes は同一オフセットに見出しが残っている場合しか旧 id を再利用しないため、行頭に 1 文字入れた時点で id は失われる。さらに CM6 の updateListener は node_modules/@codemirror/view/dist/index.js:8021-8036 のとおり updateState を Idle に戻した後に呼ばれるので、ネストした dispatch は同期的に完全な update を実行する（例外にはならない）。残るのは「それで composition が実際に壊れるか」だけ。

**検証による訂正**: 影響の断定は弱めるべき。CM6 は decoration だけの更新に対して composition を明示的に保護する: node_modules/@codemirror/view/dist/index.js:2943-2975 で、composing>=0 かつ変更が composition 範囲に触れない場合 readCompositionAt=selection.head として findCompositionRange で composition を再取得し、updateInner(changedRanges, composition) に渡して composing ノードを維持する。したがって「composing 中の行の DOM を作り直す典型パターン＝ほぼ確実に壊れる」という書き方は過大で、壊れるかどうかは finding 手順 5) のブラウザ観察でしか決まらない。確定しているのは『IME 変換中に、同じ view の updateListener の中から同期的に decoration トランザクションが dispatch される構造がある』ことまで。

**影響**: 日本語入力中に見出しを壊す編集（行頭への挿入、`#` の前後での入力）をすると composition が中断され、入力が欠ける可能性がある。updateListener の中から同じ view に dispatch している構造自体が IME に対して脆い。

**修正方針**: highlight の dispatch を composition 中は遅延させる（compositionend まで queueMicrotask/フラグで保留）。少なくとも view.composing が真のあいだは decoration の張り替えを止める。

### P5-IME-7 / 要確認 / `src/main.ts:478`

**loadText() が map.endEdit() を呼ばないので、ラベル編集中にファイルを読むと編集オーバーレイが生き残り、再利用された id で無関係なノードを rename しうる**

```
const snap = core.initDoc(text);
```

**症状**: loadText (473-488) は setSelection でマップの選択は消すが map.endEdit() は呼ばない。node-editor は render() では破棄されない（constructor 243-246 で作られた pane 直下の要素）ので display:block のまま残り、editingId は古い id を指したまま。core/api.mbt:99-111 の init_doc は st.next_id を 1 に戻すので、新しいドキュメントのノードに同じ数値 id が再利用される。その結果 positionEditor (931-943) は「別のノード」の box を見つけて入力欄をそこへ移動させ、以後の input は host.rename(その id, …) として無関係なノードのラベルを書き換える。main.ts:336-338 の rename は他の host メソッドと違い byId.has(id) ガードが無い（core 側 cmds.mbt:232-235 の find_node<0 で落ちはしないが、id が再利用されているので今回は「落ちない」ではなく「別ノードに当たる」）。

**再現条件**: 1) 保存済み（未保存インジケータが消えた）状態にする。2) ノードを選択して i でラベル編集に入る（まだ何も打たない）。3) エクスプローラから別の .md をウィンドウにドラッグ＆ドロップする（main.ts:857-878、confirmDiscard は未保存でないので確認ダイアログも出ない）。4) 新しいファイルが読み込まれた後も #node-editor の枠が表示されたままかを見る。5) そのまま日本語を打ち始めると、意図していないノードの見出しが書き換わる。要確認なのは 3) の drop でその input に blur が飛ぶかどうかだけ（開くボタンや Mod+O 経由は blur→commitEdit で守られている。Mod+O は main.ts:895 で map ペイン内では素通りするので別経路）。DevTools で document.activeElement と #node-editor の style.display を drop 前後で見れば決まる。

**確度**: 要確認

**検証の根拠**: コード上のギャップは全て確認できた。src/main.ts:473-488 の loadText に endEdit は無く、endEdit の呼び出し元は src/main.ts:342（commitEdit）だけ（grep 済み）。#node-editor は src/mindmap.ts:243-246 で pane 直下に作られ、render() の DOM 再構築（src/mindmap.ts:558-559 は edgeLayer/nodeLayer だけ replaceChildren）では破棄されない。core/api.mbt:98-110 の init_doc は st.next_id=1 に戻すので id は必ず再利用される。src/main.ts:336-338 の rename に byId.has ガードが無いのも事実で（addChild 等 312-334 には有る）、core/cmds.mbt:230-235 の find_node は再利用された id で「別ノード」に命中する。render 末尾の positionEditor（src/mindmap.ts:728, 931-943）が入力欄を新しい box へ移すのも確定。決まらないのは finding 自身が挙げている 1 点、drop で #node-editor がフォーカス／表示を保つかどうかだけで、決着方法（drop 前後の document.activeElement と style.display）も妥当。

**検証による訂正**: 1 点補足。stale な editingTag（`s{n}`）で rename が走っても、init_doc が core/api.mbt:100-101 で undo/redo を clear 済みなので core/doc.mbt:218-238 のマージ相手が居らず、新規 undo エントリになる（＝旧ドキュメントの履歴に混ざる、という悪化はしない）。また Mod+O が「map ペイン内では素通り」という記述は正しいが（src/main.ts:895）、その後 src/mindmap.ts:1282 の e.stopPropagation() で pane の onKeydown にも届かないため、ラベル編集中の Mod+O は何も起きないのが実際の挙動。

**影響**: ファイル読み込み後に別ノードのラベルが黙って書き換わる。IME 変換中に踏むと未確定文字列がそのまま他人のノードに入る。

**修正方針**: loadText の先頭で `if (map.isEditing()) map.endEdit();` を呼ぶ。あわせて main.ts:336 の rename にも他メソッドと同じ `if (!byId.has(id)) return;` を入れる。

### P5-IME-8 / CONFIRMED / `src/main.ts:902`

**popup が開いている間も main.ts の capture keydown が効き、Ctrl+Z が textarea ではなくドキュメントを undo する**

```
if (map.isEditing()) return; // native input undo while label editing
```

**症状**: main.ts:882 の keydown は window の capture 登録なので、popup.ts:49 の e.stopPropagation() より必ず先に走る（capture は overlay に到達する前）。除外条件は map.isEditing()（ラベルエディタのみ）だけで popup を見ていないため、ポップアップの textarea/input にフォーカスがあっても key==="z" で 903-906 の e.preventDefault(); e.stopPropagation(); doUndo() が実行される。stopPropagation のせいで textarea 自身のネイティブ undo も届かない。同様に Mod+S（保存）、Mod+/（togglePane がフォーカスを popup の外へ奪う）も popup 内で発火する。IME 的には、変換の取り消しに Ctrl+Z を使う操作でこれを踏む。

**再現条件**: 1) ノードを選択して Shift+C でコードポップアップを開く。2) textarea に数行入力する（日本語変換を含めてもよい）。3) Ctrl+Z を押す。4) textarea の内容は戻らず、代わりに背後のドキュメントが undo される（マップと md ペインが変化し、undo ボタンの活性が変わる）。5) Mod+/ を押すと popup を開いたままフォーカスが md ペイン／マップペインへ飛ぶ。

**確度**: 確定

**検証の根拠**: src/main.ts:882-910 は window の capture 登録（909 行 `{ capture: true }`）で、popup の overlay は src/popup.ts:60 で document.body に append されるため、popup.ts:49 の e.stopPropagation()（バブル段階）より必ず先に走る。除外は src/main.ts:902 の `if (map.isEditing()) return` のみで popup の存在を見ていない。したがって 901-906 の key==="z"/"y" 分岐が textarea フォーカス中でも成立し、e.preventDefault() でネイティブ undo を潰したうえで doUndo() が背後の文書を巻き戻す。Mod+S(889-891)・Mod+/(898-900 → togglePane 948-957 で editor.focus()/mapPane.focus()) も同様に発火する。addCode は src/mindmap.ts:1417-1424 → src/main.ts:435 で、popup を開く時点では map.isEditing() は偽（1327 で編集中は onKeydown が即 return するため）。

**検証による訂正**: 漏れが 1 つある: Mod+O も除外されない。src/main.ts:895 は `mapPane.contains(document.activeElement)` のときだけ return するが、popup overlay は body 直下（popup.ts:60）なので条件に当たらず、ポップアップを開いたままファイルピッカーが開く（未保存なら main.ts:519 の confirmDiscard の confirm ダイアログまで出る）。影響欄に加えるべき。

**影響**: ポップアップ編集中の Ctrl+Z が背後の文書を壊し、ユーザーには「入力が戻らない上に裏で何かが変わった」ように見える。ポップアップを閉じた後の undo 回数の勘定も狂う。

**修正方針**: モーダルが開いているかを示すフラグ（popup.ts の shell が公開する）を main.ts:884 の先頭で見て早期 return する。あるいは 902 の条件を `map.isEditing() || document.querySelector(".popup-overlay")` に広げる。

### P5-IME-9 / CONFIRMED / `src/mindmap.ts:996`

**mindmap.ts の window keydown（Space パン）だけ IME ガードが無い**

```
e.code === "Space" &&
```

**症状**: 4 経路のうちこの 1 つだけ `e.isComposing || e.keyCode === 229` を持たない（994-1004）。現状は `!this.isEditing()` と `document.activeElement === pane` の 2 条件で守られており、ラベル編集中は isEditing() が真、md ペイン／ポップアップ入力中は activeElement が pane ではないので composition 中に到達しない。ただし e.code は IME の影響を受けない物理キー由来で、Windows の日本語 IME では Space が変換キーであるため、将来 map pane 自体を編集可能にする／フォーカス条件を緩めると即座に「変換キーを押すとパンモードに入り preventDefault される」バグになる。ガードの有無が他の 3 経路と非対称なのは、この 4 経路を「個別に確認する」という観点では明示すべき差分。

**再現条件**: 現時点で壊れる操作手順は書けない（上記 2 条件のどちらかを外さないと到達しない）。要確認: mindmap.ts:995 の直後に console.log(e.code, e.isComposing, document.activeElement) を入れ、(a) ラベル編集中に IME の Space を押したとき、(b) endEdit 直後に pane へフォーカスが戻った状態で IME を ON のまま Space を押したときに、この分岐へ入らないことを確認すれば決着する。

**確度**: 確定

**検証の根拠**: src/mindmap.ts:994-1004 に e.isComposing / e.keyCode の判定は無く、引用の 996 行も一致。到達不能である根拠もコードで確定する: 条件 `document.activeElement === pane` の pane は index.html:39 の `<section id="map-pane" tabindex="0">` という非編集要素で、そこにフォーカスがある間は IME の composition が成立しない。ラベル編集中は activeElement が #node-editor（src/mindmap.ts:243-246）なので `=== pane` が偽になり、`!this.isEditing()` を待つまでもなく弾かれる。よって「現状の実害なし＋防御の非対称性のみ」という finding の主張はそのまま正しい。

**検証による訂正**: タイトルの「だけ」は誤り。ガードを持たない keydown ハンドラは他にも src/popup.ts:48・86・118 の 3 つある（それが finding #3）。正しくは『IME ガードを持つのは main.ts:885 / mindmap.ts:1281 / mindmap.ts:1326 の 3 つで、ガードの無い keydown は mindmap.ts:994 と popup.ts の 3 箇所、計 4 箇所』。また本項は現時点でバグではなく、フォーカス条件を緩めた場合の回帰リスク注記として扱うべき（トリアージ上は最低優先度）。

**影響**: 現状は到達しないが、他の 3 経路と防御が非対称。フォーカス条件が変わった瞬間に「変換キーが効かない」形で表面化する。

**修正方針**: 994 のハンドラ冒頭にも `if (e.isComposing || e.keyCode === 229) return;` を入れて 4 経路の防御をそろえる。

---

## 2. キャレットとテキスト選択、ノード選択（src/editor.ts / src/main.ts / src/mindmap.ts を全文精読。裏取りのため core/api.mbt・core/doc.mbt(apply_sets, map_offset, apply_edit_set)・core/cmds.mbt(cmd_rename)・index.html・src/style.css・node_modules/@codemirror/{state,view}/dist/index.js も参照）

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

### P5-キャレット-1 / CONFIRMED / `D:/1.atrium/mmm/src/editor.ts:74`

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

**確度**: 確定

**検証の根拠**: 全経路を dist で確認。@codemirror/view dist:293 `static set(of, sort = false) { return RangeSet.of(of, sort); }` → @codemirror/state dist:3394 `RangeSet.of(ranges, sort=false)` は sort=false のとき lazySort を通さず生のまま RangeSetBuilder.add へ流す。dist:3475 addInner は `diff = from - this.lastTo || ...; if (diff <= 0 && (from - this.lastFrom || ...) < 0) throw new Error("Ranges must be added sorted by \`from\` position and \`startSide\`")`（dist:3478）。つまり「前の range の from より前で始まる」ときだけ throw し、包含（親→子）は false を返して nextLayer に落ちるだけなので投げない＝降順のときだけ落ちる、という finding の主張どおり。生成側も一致: src/main.ts:213 `[...selection]` は Set の挿入順、src/main.ts:224-228 `setSelection` が `selection = new Set(ids)` で順序をそのまま保持、src/mindmap.ts:1181-1187 の Mod+クリックは `next.add(id)` で末尾に追加、src/mindmap.ts:1550-1551 の Shift+矢印も `set.add(nx)` の後 `setSelection([...set], nx)`。例外の伝播も確認: @codemirror/view dist:7955 `state = tr.state;` は update() の try ブロックより前にあり、StateField.update 内の throw は view.dispatch から同期的に外へ出る。呼び出し順も src/main.ts:211→213 なので map.refreshSelection() は済んでいる。

**検証による訂正**: 投げるのは「新しく足す range が既存 range より前で始まる」ときだけ。したがって Shift+↓（後ろへ拡張）と Mod+A（this.order をそのまま渡す src/mindmap.ts:1484）と Shift+クリック（this.order.slice、src/mindmap.ts:1175-1178）は昇順なので安全で、実際に落ちるのは (a) 現在の選択より文書上前のノードの Mod+クリック追加、(b) Shift+↑ による拡張、の2つ。また mindmap.ts の該当行は 1183（next.add(id)）と 1550（set.add(nx)）で、引用された 1184 / 1551 はその直後の setSelection 行。

**影響**: 最頻出の複数選択操作（Ctrl+クリック、Shift+↑）が毎回未捕捉例外になる。md ペインの選択ミラーが停止し、applySnap 内で起きた場合は自動保存(schedulePersist)と undo/redo ボタン状態の更新も落ちる。

**修正方針**: editor.ts:74 を `Decoration.set(..., true)`（sort 有効）にする。併せて main.ts:213 で `[...selection]` を n.hs 昇順に sort してから highlight に渡し、mindmap.ts:1184/1551 も this.order でフィルタして文書順の配列を作る。

### P5-キャレット-2 / CONFIRMED / `D:/1.atrium/mmm/src/mindmap.ts:1549`

**Shift+↓/↑ がアンカーを選択から抜き、選択が非連続になる**

```
if (set.has(nx) && sel.size > 1) set.delete(anchor);
```

**症状**: 「隣が既に選択済みなら縮める」ロジックが、アンカーが選択範囲の端ではなく中央にある場合に穴を空ける。直上のコメントは「anchor edge stays (spec 3.4)」だが実装は 1551 行で毎回 anchor を nx へ移動させており、端固定になっていない。

**再現条件**: 既定文書で「## mindmap」をクリック（anchor=mindmap, order 上 index 3）→ Mod+A で全選択（anchor は mindmap のまま、main.ts の setSelection は anchor を保持）→ Shift+↓ を1回。期待は選択維持/拡張だが、実際は「## mindmap」だけが選択解除され、その子「### 空間的に見るもう一つの窓」は選択されたまま残る（マップ上に穴が空く）。もう一度 Shift+↓ で穴が広がる。

**確度**: 確定

**検証の根拠**: src/mindmap.ts:1548-1551 `const set = new Set(sel); if (set.has(nx) && sel.size > 1) set.delete(anchor); else set.add(nx); this.host.setSelection([...set], nx);` — 縮小分岐が「アンカー端を残す」ではなく毎回 anchor を落とし、かつ anchor は常に nx へ移る。1543 のコメント「anchor edge stays (spec 3.4)」と実装が矛盾。再現も成立: src/mindmap.ts:1483-1487 の Mod+A は `setSelection([...this.order], anchor !== -1 ? anchor : ...)` で既存 anchor を保持するので anchor=「## mindmap」(order index 3) のまま全選択になり、Shift+↓ で nx=order[4]=「### 空間的に見るもう一つの窓」が既に選択済み＆sel.size=7>1 → set.delete(mindmap)。親だけ抜けて子が残る穴ができる。2回目の Shift+↓ では anchor が空間ノードに移っているので今度はそれが抜け、穴が広がる。構造編集への影響も成立: core/doc.mbt:502-527 normalize_selection は「選択中の他ノードの範囲に含まれる id」だけを落とすので、親が非選択になった子は独立した操作対象として残り、dd/Mod+X/インデントがその集合に対して走る。

**影響**: 見た目に連続な範囲を選んだつもりで dd / Mod+X / インデントを実行すると、意図しない親抜けの集合に対して構造編集が走る。

**修正方針**: アンカーを固定端として保持し（setSelection の第2引数を anchor のままにする）、伸縮は「アンカーから現在の移動端までの this.order スライス」を作り直す方式に変える。

### P5-キャレット-3 / CONFIRMED / `D:/1.atrium/mmm/src/mindmap.ts:1186`

**Ctrl+クリックでアンカー自身を外すと、選択0件なのに anchorId が生き残る**

```
next.has(id) ? id : this.host.anchor(),
```

**症状**: アンカーノードを Ctrl+クリックで外すと next からは消えるが anchor は this.host.anchor()（= 外したノード自身）のまま残る。main.ts:192 の prune は「byId に無い」場合しか anchor を捨てないので、選択集合の外にいる anchor は永久に残る。マップ上は何も選択されていないのに、キーボード操作は不可視のノードを対象にし続ける。

**再現条件**: 既定文書で「## markdown」をクリック（選択1件）→ 同じノードを Ctrl+クリック。マップの選択表示も md ペインのハイライトも消える。その状態で Enter を押すと「## markdown」の下に兄弟ノードが生成される。i を押すと「## markdown」のラベル編集が開く。Mod+V も「## markdown」の子として貼り付く。

**確度**: 確定

**検証の根拠**: src/mindmap.ts:1180-1187: 解除側では `next.has(id)` が false になるので anchor は `this.host.anchor()`（＝外したノード自身）のまま。src/main.ts:192-195 の prune は `!byId.has(anchorId)` のときしか anchorId を捨てないので、ノードが生きている限り選択外の anchor が残る。後続動作も確認: Enter は src/mindmap.ts:1450-1454 `else if (anchor !== -1) this.host.addSibling(anchor, false)` で core/cmds.mbt:155-169 cmd_add_sibling が nd.sub_end に兄弟を挿入（＝「## markdown」の直下）。i は src/mindmap.ts:1437-1445 の条件 `anchor !== -1 && sel.size <= 1` を sel.size=0 で通過し editRequested→beginEdit。Mod+V は src/main.ts:383 `if (anchorId === -1 && nodes.length > 0) return;` を通過し 411-414 で anchor の子として貼り付く。

**影響**: 何も選択していない見た目のまま構造編集が走る。ユーザは対象ノードを目で確認できない。

**修正方針**: mindmap.ts:1184-1187 で next が空、または next に anchor が含まれない場合は anchor を next の末尾要素（無ければ -1）にフォールバックさせる。

### P5-キャレット-4 / CONFIRMED / `D:/1.atrium/mmm/src/mindmap.ts:1209`

**ラベル編集中のダブルクリックが編集を張り直し、入力欄の単語選択とキャレットを破壊する**

```
const id = this.nodeAt(e.clientX, e.clientY);
```

**症状**: pane の dblclick ハンドラには pointerdown（mindmap.ts:1043 の `if (e.target === this.editor) return;`）に相当する node-editor 除外がない。#node-editor はノード上に重なる pane の子要素なので、入力欄内のダブルクリックも pane まで bubble し nodeAt が編集中ノードを返す → host.editRequested → beginEdit が再入する。beginEdit は editor.value をノードのラベルで上書きし（mindmap.ts:904）、最後に setSelectionRange(pos,pos)（mindmap.ts:916）でキャレットを末尾へ潰す。さらに editRequested は新しい tag（main.ts:461）を発行するので、そこから先の入力が別の undo エントリに切れる。

**再現条件**: マップのノード（例「## mindmap」）をダブルクリックしてラベル編集を開始 → 入力欄の中の単語をダブルクリックして選択しようとする。期待は単語選択、実際は選択が消えてキャレットが末尾へ飛ぶ。トリプルクリック（全選択）でも同じ。

**確度**: 確定

**検証の根拠**: #node-editor は src/mindmap.ts:243-246 で `pane.append(this.editor)` されている pane の子で、CSS も pane 内の absolute（src/style.css:277-289、z-index:10）。pane の dblclick ハンドラ src/mindmap.ts:1204-1215 には pointerdown 側（1043 `if (e.target === this.editor) return;`）に相当する除外がなく、1206 の除外は `.link-open` のみ。1209 の nodeAt は座標判定なので入力欄が重なっている編集中ノードを返し、1214 host.editRequested → src/main.ts:458-463 で新 tag を採番して map.beginEdit を再入。beginEdit は 904 `this.editor.value = b.n.label`、916 `setSelectionRange(pos,pos)`（pos は editCaret="end" なので末尾）でダブルクリックの単語選択を潰す。undo 粒度の分割も src/main.ts:461 `const tag = \`s${++sessionN}\`` で成立（core/doc.mbt:221-238 の同一 tag マージが切れる）。README.md:69「編集中ノードのクリック｜カーソル移動(確定しない)」という明記された要求にも反する。

**検証による訂正**: 「トリプルクリック（全選択）でも同じ」は誤り。dblclick が発火するのは2打目で、3打目の mousedown は pointerdown ハンドラ 1043 行で早期 return するだけなのでブラウザ既定の行選択がそのまま残る。壊れるのはダブルクリックの単語選択のみ。また入力欄は positionEditor（936-937）で箱より約12px 幅広なので、末尾のはみ出し部分でダブルクリックすると nodeAt が -1 を返して 1210 行で return し、その場合は再現しない。

**影響**: ラベル編集中にマウスで単語選択・全選択ができない（Backspace 連打でしか消せない）。加えて undo の粒度が意図せず分割される。

**修正方針**: dblclick ハンドラ先頭に `if (e.target === this.editor) return;` を追加する（pointerdown と同じガード）。

### P5-キャレット-5 / CONFIRMED / `D:/1.atrium/mmm/src/mindmap.ts:1262`

**ラベル編集中の右クリックがノードのコンテキストメニューに乗っ取られる**

```
e.preventDefault();
```

**症状**: pane の contextmenu ハンドラも node-editor を除外していない。入力欄上で右クリックすると preventDefault でブラウザ標準の「切り取り/コピー/貼り付け/元に戻す」メニューが抑止され、代わりに nodeAt が返したノードに対する #ctx-menu（子を追加/削除 など）が入力欄の上に開く。pointerdown 側は e.target===this.editor で早期 return するため commitEdit も走らず、編集中のまま構造編集メニューが出る。

**再現条件**: ノードをダブルクリックしてラベル編集を開始 → 入力欄の中で右クリック。ブラウザのテキスト編集メニューではなく「子を追加 / 下に追加 / 削除 …」のマップメニューが出る。

**確度**: 確定

**検証の根拠**: src/mindmap.ts:1261-1270 の contextmenu ハンドラは pane に付いており、無条件 `e.preventDefault()`（1262）→ nodeAt（1263）→ showMenu（1269）。#node-editor は pane の子（1246）で contextmenu を止めるリスナも持たない（editor のリスナは 1274 input / 1280 keydown / 1290 blur のみ）ので入力欄上の右クリックが必ず pane に届く。pointerdown は右ボタンでも発火するが 1043 `if (e.target === this.editor) return;` で早期 return するため commitEdit（1044）は走らず、編集継続のまま構造メニューが開く。1268 `if (!this.host.selection().has(id))` は editRequested が既に setSelection([id],id) 済み（src/main.ts:460）なので素通り。#ctx-menu は position:fixed / z-index:100（src/style.css:291-294）で #node-editor の z-index:10 より上に重なる。削除まで到達した場合の挙動（メニュー div への mousedown で input が blur → 1290-1292 commitEdit でテキスト確定 → 1789-1792 の click で it.run() が削除）も順序どおり成立。

**影響**: ラベル編集中にテキストのコピー&ペーストをコンテキストメニューから行えない。誤って「削除」を選ぶと編集中ノードが消える（blur→commitEdit が先に走るのでテキストは確定されるが、直後に削除される）。

**修正方針**: contextmenu ハンドラ先頭に `if (e.target === this.editor) return;` を追加し、入力欄内では標準メニューを許可する。

### P5-キャレット-6 / CONFIRMED / `D:/1.atrium/mmm/src/mindmap.ts:933`

**ファイル読み込み後もラベル編集オーバーレイが残り、id 再採番により無関係なノードに再バインドされる**

```
const b = this.boxes.get(this.editingId);
```

**症状**: loadText（main.ts:473-488）は map.endEdit() を呼ばない。editingId は前の文書の id のまま残り、positionEditor は箱が無ければ黙って return するので入力欄は古い座標に表示されっぱなしになる。さらに core/api.mbt:99 の init_doc が `st.next_id = 1` にリセットするため新文書のノード id は 1..n に再採番され、古い editingId（例 3）が新文書の3番目のノードと衝突する。その場合 positionEditor はそのノードの箱を見つけて入力欄をそこへ移動し、以後の入力は host.rename(3, ...) として全く別の見出しを書き換える。

**再現条件**: 1) Mod+S で保存して dirty を落とす（confirmDiscard を出さないため）。2) マップのノードをダブルクリックしてラベル編集を開き、何も入力しない。3) エクスプローラから別の .md をウィンドウにドラッグ&ドロップする（window の drop ハンドラ main.ts:857 が走る）。4) 新しいマップが描画された後も入力欄が残っているのを確認し、1文字入力する → 新文書側の同 id ノードの見出しが書き換わる。

**確度**: 確定

**検証の根拠**: 要確認とされていたが、コードだけで確定できる。src/main.ts:473-488 loadText は map.endEdit() を呼ばず editingId / editingTag / editor.style.display="block" をそのまま残す。id 再採番も確定: core/api.mbt:99-111 init_doc が `st.next_id = 1`（104行）にリセットし rebuild_nodes(Map([])) を呼ぶので、core/doc.mbt:281-288 で新文書のノードは文書順に 1..n を新規採番する。よって旧 editingId=3 は新文書の3番目の見出しに衝突し、src/mindmap.ts:931-943 positionEditor がその箱を見つけて入力欄を移動、以後の入力は 1274-1279 の input ハンドラ経由で host.rename(3, ...) → core/cmds.mbt:231-247 cmd_rename が新文書側ノード3の見出し行を丸ごと置換する。入力欄のフォーカスが drop をまたいで残るかに依存する必要すらない: 残った入力欄をユーザがクリックしても pointerdown は 1043 行で early return して commitEdit しないので、そのままフォーカスして打てる。

**検証による訂正**: 影響をもう一段強く書ける。isEditing() が true のまま残るため、(a) src/mindmap.ts:1327 `if (this.isEditing()) return;` によりマップペインのキーボード操作が全て無効化され、(b) src/main.ts:902 `if (map.isEditing()) return;` により Mod+Z / Mod+Y も無効化される。Mod+/ でマップにフォーカスした場合、マップペインの空白を pointerdown する（1044 の commitEdit）まで回復しない。自己申告の「要確認」は不要で、CONFIRMED でよい。

**影響**: 文書切り替え直後に、ユーザが意図していないノードの見出しが直接書き換わる。最低でも死んだオーバーレイが浮いたまま残る。

**修正方針**: loadText の先頭で `map.endEdit()`（と editingId のリセット）を呼ぶ。加えて positionEditor で箱が見つからない場合は早期 return ではなく endEdit して入力欄を閉じる。要確認点はステップ3で「ファイル drop が input の focus/blur を発火させないか」だけ（Chrome では発火しない見込み）。drop 後に入力欄が残って見えれば確定。

### P5-キャレット-7 / CONFIRMED / `D:/1.atrium/mmm/src/main.ts:199`

**ノード範囲の末尾に足したテキストが md ペインのハイライトから外れ、再計算もされない**

```
if (selChanged) syncSelectionViews(false);
```

**症状**: ハイライトは Decoration.mark（非 inclusive）なので startSide=500000000 / endSide=-600000000（@codemirror/view dist:308）。境界ちょうどの挿入は from 側では range の外へ押し出され、to 側では range に取り込まれない。一方 applySnap は「選択の集合が変わったときだけ」syncSelectionViews を呼ぶので、選択メンバーが同じまま subEnd だけ伸びるケースではハイライトが再計算されず、CM のマッピング結果（＝取りこぼした範囲）がそのまま残る。insertContentLine（main.ts:722-736）と paste（main.ts:404-422）は葉ノードでは `at = n.subEnd`、すなわち必ずこの境界に挿入する。

**再現条件**: 既定文書で葉ノード「### 空間的に見るもう一つの窓」をクリック（md ペインに範囲ハイライトが出る）→ L キーでリンクポップアップを開き URL を入れて確定。マップにはリンクカードがそのノードの一部として描かれるが、md ペインのハイライトは挿入された `[title](url)` 行の直前で切れたまま。Mod+V の子貼り付けでも同じ（貼り付けたサブツリー全体がハイライトの外）。最後のノードを選んで md ペイン末尾に文字を打った場合も同様。

**確度**: 確定

**検証の根拠**: 3つの前提を全て dist / ソースで確認。(1) @codemirror/view dist:305-308 `class MarkDecoration ... super(start ? -1 : 500000000, end ? 1 : -600000000, ...)` で inclusive 無指定の Decoration.mark は startSide=5e8 / endSide=-6e8。(2) @codemirror/state dist:3104-3121 Chunk.map が `newFrom = changes.mapPos(curFrom, val.startSide); newTo = changes.mapPos(curTo, val.endSide);` を使い、dist:751-752 mapPos は `endA == pos` の挿入で assoc の符号によって前後を選ぶので、to 側（負 assoc）ちょうどの挿入は range 外に落ちる。(3) src/main.ts:199 `if (selChanged) syncSelectionViews(false);` — 選択メンバーが変わらない限りハイライトは再計算されない。挿入位置も一致: src/main.ts:722-729 insertContentLine は葉ノードで `at = n.subEnd`、src/main.ts:413 の paste も `at = n.subEnd`、そして src/main.ts:216 のハイライト範囲は `{ from: n.hs, to: n.subEnd }` なので挿入点＝range の to ちょうど。既定文書の「### 空間的に見るもう一つの窓」は subEnd が「## mirror」の hs（`---` は core/parser.mbt:99-102 で見出しではなくセパレータ扱い）で、nodes[i+1].hs < n.subEnd が偽なので確かに at = subEnd。挿入後も core/doc.mbt:119-135 map_offset により全ノードの id が生存するため selChanged=false で再計算されない。

**影響**: 「マップの選択 = md の反転範囲」というミラーの前提が崩れる。ユーザは選択したノードの本文がどこまでか md 側で判断できない。

**修正方針**: applySnap の条件を外して常に syncSelectionViews(false) を呼ぶか、少なくとも insertContentLine / paste の直後に明示的に呼ぶ。ハイライト自体を inclusive な mark にするのは他の境界で副作用があるので非推奨。

### P5-キャレット-8 / CONFIRMED / `D:/1.atrium/mmm/src/editor.ts:160`

**マップからのリネームは見出し行を丸ごと置換するため、md ペインのキャレット/テキスト選択が行頭に潰れる**

```
this.view.dispatch({
        changes: set.map((e) => ({ from: e.from, to: e.to, insert: e.insert })),
        annotations: fromCore.of(true),
      });
```

**症状**: applySets は selection を指定しないので CM 側は既存選択を assoc=-1 でマッピングするだけ。core/cmds.mbt:243 の cmd_rename は `Edit{ from: nd.hs, to: nd.he, insert: line }`、つまり毎打鍵で見出し行全体を置換する。置換範囲の内側にあった位置は mapPos により置換開始位置（= hs）へ collapse するので、md ペインにあったキャレットは行頭へ飛び、テキスト選択は消える。

**再現条件**: 1) md ペインで `## markdown` 行の「mark|down」の位置をクリック（またはその単語をダブルクリックして選択）。2) マップの「markdown」ノードをダブルクリックして 1 文字入力。3) Mod+/ で md ペインに戻る → キャレットは `## markdown` 行の先頭、選択は消えている。

**確度**: 確定

**検証の根拠**: core/cmds.mbt:242-245 `apply_sets([[Edit::{ from: nd.hs, to: nd.he, insert: line, removed: old }]], tag)` で毎打鍵ごとに見出し行全体を置換するのは事実。src/editor.ts:157-165 applySets は selection を指定しないので @codemirror/state dist:2272-2273 `get newSelection() { return this.selection || this.startState.selection.map(this.changes); }` が使われ、dist:1390 `EditorSelection.map(change, assoc = -1)` → dist:1321-1324 `if (this.empty) from = to = change.mapPos(this.from, assoc)` で assoc=-1。dist:751-752 `if (endA > pos ...) return pos == posA || assoc < 0 ? posB : posB + ins;` により、置換範囲の内側にあったキャレットは posB＝置換開始位置＝nd.hs（行頭）へ collapse する。finding の assoc=-1 という記述も正しい。

**検証による訂正**: 「テキスト選択は消える」の部分だけ厳密には別挙動。非空 range は dist:1327-1328 で `from = mapPos(from, 1)`（→置換後テキストの末尾）、`to = mapPos(to, -1)`（→hs）となり from > to の反転 range が作られる（dist:1330 `new SelectionRange(from, to, ...)`、EditorSelection.create は1本なら throw しない）。行頭に潰れるのではなく不正な反転選択になる、が正確。キャレット（空 range）が行頭へ飛ぶという主結論は正しい。

**影響**: 両ペインを行き来しながら編集すると md 側の作業位置が毎回失われる。

**修正方針**: cmd_rename の置換範囲をラベル部分（he 側からの差分）だけに絞るか、applySets 側で編集前の selection を changes.map(assoc) ではなく明示的に保存/復元する。

### P5-キャレット-9 / CONFIRMED / `D:/1.atrium/mmm/src/mindmap.ts:1555`

**j/k の兄弟ループがマップ右側から左側へ飛ぶ（「下」で横に移動する）**

```
const sibs = nodes.filter((n) => n.parent === cur.parent);
```

**症状**: 兄弟集合を文書順だけで作り、group（--- で分かれる左右の配置）を考慮していない。ルート直下では group 0 が右側、それ以降が左側に描画される（mindmap.ts:513-514）ため、文書順で隣でも画面上は反対側にある。

**再現条件**: 既定文書（`---` を含む）でマップの「## mindmap」をクリック → j を押す。選択は右側の下から左側の「## mirror」へ飛ぶ（画面上は下ではなく左へ移動）。さらに j でループして右側の「## markdown」へ戻る。

**確度**: 確定

**検証の根拠**: src/mindmap.ts:1554-1560 は `nodes.filter((n) => n.parent === cur.parent)` で文書順の兄弟集合を作り group を見ていない。一方 src/mindmap.ts:507-516 は `gids[0]`（=group 0）だけを rightKids、それ以外を leftKids として左右に振り分ける。既定文書での group 値も core 側で確認: core/parser.mbt:99-102 が `---` 行を seps に収集 → core/doc.mbt:266-276 で「直後が見出しまで空白のみ」なら採用 → core/doc.mbt:339-388 compute_groups により root 直下は markdown=0, mindmap=0, mirror=1。よって sibs=[markdown, mindmap, mirror] で「## mindmap」から j は i=1→j=2=「## mirror」（左側）、さらに j で (2+1)%3=0=「## markdown」（右側）へループする、という再現手順どおり。

**検証による訂正**: README.md:88 は「↑↓ ←→ / hjkl｜兄弟間を上下移動(ループ)」としか書いておらず、文書順の兄弟ループ自体は仕様どおりの実装。したがってこれは実装バグではなく「論理的な兄弟順と描画位置が一致しない仕様の副作用」。mmm.md そのに「移動について／描画されたノード位置から近似に移動するやつにしたい」が未実装、という位置づけが正確。

**影響**: vim キー/矢印での移動が画面上の位置と一致せず、選択を見失う。

**修正方針**: 上下移動の兄弟集合を `sideOf`（または group）が一致するものに限定し、左右キーで側を跨ぐようにする。

### P5-キャレット-10 / CONFIRMED / `D:/1.atrium/mmm/src/mindmap.ts:1116`

**矩形選択が常に選択を置き換え、Shift/Ctrl を押しても追加選択にならない**

```
if (hit.length !== cur.size || hit.some((id) => !cur.has(id))) {
```

**症状**: ドラッグ中の setSelection は hit だけを渡しており、修飾キーを一切見ていない。修飾キーが見られているのは pointerup の「動かなかったクリック」判定（mindmap.ts:1150）だけ。Figma 準拠（spec 3.3）を謳っているが Shift+マーキーの加算選択がない。

**再現条件**: マップで数ノードをクリック/Ctrl+クリックで選択 → Shift を押したまま空白から別のノード群をドラッグで囲む。既存の選択は保持されず、囲んだ分だけに置き換わる。

**確度**: 確定

**検証の根拠**: src/mindmap.ts:1113-1122 のラバーバンド確定は `this.host.setSelection(hit, hit.length ? hit[hit.length-1] : -1, false)` で hit をそのまま渡すだけ。pointermove ハンドラ全体（1074-1135）に e.shiftKey / e.ctrlKey / e.metaKey の参照は一切ない。修飾キーを見ているのは pointerup の 1150 行 `if (!moved && !e.shiftKey && !e.ctrlKey && !e.metaKey) this.host.clearSelection();` と 1168-1187 のクリック選択だけ、という指摘も正しい。

**検証による訂正**: 「Figma 準拠（spec 3.3）を謳っている」の根拠は README.md:16 の「mindmap.ts マインドマップペイン(SVG、Figma 準拠の操作系)」と mmm.md の「ショートカット>マウス>Figma」という一行のみで、README.md:97 の操作表には加算マーキーは記載がない。したがって明文化された仕様違反ではなく未実装の機能ギャップ。

**影響**: 広いマップで離れた複数グループを選ぶ手段がない（Ctrl+クリックの1個ずつしかない）。

**修正方針**: rubberStart 開始時に修飾キーと開始時の選択集合を保存し、Shift/Ctrl ドラッグ中は baseSelection ∪ hit を this.order 順で渡す。

### P5-キャレット-11 / CONFIRMED / `D:/1.atrium/mmm/src/main.ts:493`

**undo/redo 後に選択が復元されない（core は id を復元しているのに使っていない）**

```
applySnap(core.undo(), "core");
```

**症状**: doUndo/doRedo は runCmd を通さないので snap.focus を完全に無視する。core 側は replay_entry(core/doc.mbt:411) が entry.before/after のペアからノード id を復元するため、削除を undo すると元の id でノードが戻ってくるが、削除時に applySnap の prune（main.ts:185-191）で selection からは既に消えているため、戻ってきたノードは選択されない。

**再現条件**: マップでノードを選んで dd で削除 → Mod+Z。ノードは戻るが選択は空、anchorId も -1 のまま。続けて Enter や i を押しても何も起きない。

**確度**: 確定

**検証の根拠**: src/main.ts:492-499 doUndo/doRedo が runCmd を通さず snap.focus を読まないのは事実で、undo/redo 後に「戻ってきたノード」が選択されないという結論自体は正しい（core/doc.mbt:414-432 replay_entry が entry.before/after から id を復元しているのに UI 側が使っていない）。

**検証による訂正**: 機構の説明と再現手順が誤り。(1) undo/redo の snap.focus は常に -1 になる。core/api.mbt:210-219 の undo()/redo() は do_undo()/do_redo() を呼ぶだけで st.focus を設定せず、core/api.mbt:94 `st.focus = -1` が毎回 snapshot() の最後にリセットするため。したがって「runCmd を通していれば復元できたのに無視している」のではなく、そもそも core が undo 用の focus を返していない。(2) 再現の「選択は空、anchorId も -1 のまま。Enter や i を押しても何も起きない」は通常成立しない。core/cmds.mbt:263-278 cmd_delete は削除範囲の後ろ（なければ前）の生存ノードを focus_id に選ぶので、src/main.ts:346-354 deleteSelection がその隣接ノードを選択済みにする。undo 後もそのノードは生存しており src/main.ts:186 の prune に掛からないため選択も anchorId も残り、Enter / i は動く。空選択になるのは文書中の全ノードが消える削除（focus_id が -1 のまま）の場合だけ。実際の症状は「undo で復活したノードが選択されず、選択が削除直後の隣接ノードに残ったままになる」。

**影響**: undo のたびに選択を手で取り直す必要がある。連続 undo で「どこを戻したか」がマップ上で分からない。

**修正方針**: doUndo/doRedo でも snap.focus を見て `setSelection([snap.focus], snap.focus)` + `map.ensureVisible` を行う（focus が -1 の場合のみ現状維持）。

### P5-キャレット-12 / 判定なし / `D:/1.atrium/mmm/src/mindmap.ts:901`

**beginEdit が箱を見つけられず早期 return すると editClear / editCaret が次回の編集へ漏れる**

```
if (!b) return;
```

**症状**: editClear は mindmap.ts:906-911 で、editCaret は mindmap.ts:917 で、いずれも「beginEdit が箱を取得できた後」にしか消費/リセットされない。s / cc（mindmap.ts:1364, 1372-1375）は editClear=true を立ててから editRequested を呼ぶので、beginEdit が 901 行で return するとフラグが立ちっぱなしになり、次に開いた編集で `this.host.rename(id, "", tag)`（mindmap.ts:910）が走って無関係なノードのラベルが空になる。

**再現条件**: 書けない。現状 render() が全ノードに箱を作るため this.boxes.get(id) が undefined になる経路を特定できなかった。要確認: host.editRequested（main.ts:458）が byId で通過し、かつ map.boxes に無い id が存在しうるか。具体的には (a) render() の tops 到達不能ノードが実在しうるか、(b) applySnap 以外の経路で host.nodes() だけが更新され render() が走らない瞬間があるか、をコア側の rebuild_nodes の parent 付与規則と合わせて確認すれば決まる。

**確度**: 要確認(検証パスが判定を返さなかった)

**影響**: 成立した場合はラベルの無音消去（データ損失）。成立しなくても、フラグを消費前に return する構造は将来の変更で壊れやすい。

**修正方針**: beginEdit の先頭（`if (!b) return;` の前）で editClear / editCaret をローカル変数に取り出して即座にフィールドをリセットする。

### P5-キャレット-13 / CONFIRMED / `D:/1.atrium/mmm/src/main.ts:186`

**F-004 の map_offset=-1 の新しい影響: md ペインで見出しの # を1つ消すとマップの選択が無言で外れる**

```
selection.delete(id);
```

**症状**: 既知 F-004（core/doc.mbt:126 の「pure deletion starting here → return -1」）の根本原因が、outdent 以外に「md ペインでの通常のテキスト編集」でも表面化する、という新しい帰結。見出し先頭の `#` を1文字消すと map_offset が -1 を返してノード id が再採番され、main.ts:185-191 の prune が選択からそのノードを落とし、192-195 で anchorId も -1 になる。ノード自体は（レベルが変わっただけで）画面に残っているのに選択だけ消える。

**再現条件**: 既定文書でマップの「### 実体は .md ファイル」をクリック（両ペインでハイライト）→ md ペインでその行の3つ目の `#` の直後にキャレットを置き Backspace を1回（`## 実体は .md ファイル` になる）。ノードはマップに残っているが選択表示が消え、続けて Enter / i / Tab を押しても何も起きない（anchorId が -1）。

**確度**: 確定

**検証の根拠**: 「map_offset の -1 が outdent 以外にも md ペインの通常編集で表面化する」という帰結自体は成立する。core/doc.mbt:113-143 map_offset は `p == e.from` かつ `e.to > e.from` かつ `e.insert.length() == 0` のときだけ 126 行で -1 を返す。つまり見出し行の先頭オフセット hs ちょうどから始まる純削除なら id が失われ、core/doc.mbt:281-288 で新しい id が採番され、src/main.ts:185-195 の prune が選択から落として anchorId を -1 にする。ノード自体は（深さが変わっただけで）マップに残るので「見た目は残っているのに選択だけ消える」という症状も正しい。

**検証による訂正**: 再現手順が誤り。「3つ目の `#` の直後にキャレットを置き Backspace」は削除範囲が [hs+2, hs+3) なので map_offset は 116-118 行の `if (p < e.from) break` で抜け、hs はそのまま生存して id も選択も保持される。-1 になるのは削除が hs ちょうどから始まるときだけ。正しい再現は「見出しの1つ目と2つ目の `#` の間（hs+1）にキャレットを置いて Backspace」または「行頭にキャレットを置いて Delete（前方削除）」または「先頭の `#` を選択して削除」。この場合に id が再採番され、選択と anchorId が無言で失われる。

**影響**: md ペインで見出しレベルを直接直すという普通の操作のたびに、マップ側の作業対象を見失う。

**修正方針**: core 側で見出し先頭の純削除でも「行が依然として見出しなら同一ノード」と判定して id を継承させる（F-004 の修正と同一）。UI 側の暫定策としては prune で落ちた id を「同じ hs で始まる新 id」に張り替える。

### P5-キャレット-14 / CONFIRMED / `D:/1.atrium/mmm/src/main.ts:470`

**md ペインのキャレット位置はマップの選択に一切反映されない（ミラーが片方向）**

```
const editor = new MdEditor(mdPane, onUserEdits);
```

**症状**: MdEditor に渡すコールバックは onUserEdits（テキスト変更）だけで、selection 変更を受け取る口がない。editor.ts 側にも selectionSet を監視する updateListener はない。したがって md ペインでキャレットを別の見出しへ動かしても selection / anchorId は変わらず、マップの選択は前のノードのまま。逆方向（マップ→md のハイライトと reveal）だけが実装されている。

**再現条件**: マップで「## markdown」を選択 → md ペインの `## mirror` 行をクリックしてキャレットを置く → Mod+/ でマップへ戻り Enter。「## mirror」ではなく「## markdown」の下に兄弟が作られる。

**確度**: 確定

**検証の根拠**: 要確認とされていたがコードだけで確定する。src/editor.ts:90-93 の MdEditor コンストラクタが受け取るコールバックは `onUserEdits: (edits: EditOp[], userEvent: string) => void` の1つだけで、src/main.ts:470 の呼び出しもそれだけ。src/editor.ts:113-142 の唯一の updateListener は先頭で `if (!u.docChanged) return;` と書かれており選択変更を一切見ない（domEventHandlers も compositionend のみ、src/editor.ts:105-112）。selectionSet / selectionChanged を参照する箇所はファイル内に存在しない。逆方向（マップ→md）だけが src/main.ts:210-222 syncSelectionViews の editor.highlight / editor.reveal として実装されている。再現も成立: src/main.ts:948-957 togglePane は mapPane.focus() するだけで選択に触れず、src/mindmap.ts:1450-1454 の Enter は古い anchor に対して addSibling する。

**検証による訂正**: 自己申告の「要確認」は不要（CONFIRMED）。ただし README.md はマップ→md の片方向ミラーしか約束していない（README.md:96 以降の操作表は全てマップ側の操作）ので、仕様違反ではなく未実装の一方向同期として扱うのが正確。

**影響**: 両ペイン往復時に「今どのノードを操作しているか」が食い違う。

**修正方針**: 仕様（spec 4.4 / mmm.md）でミラーが map→md の片方向と決まっているかを確認するのが先。双方向にするなら editor.ts に selectionSet 用の updateListener を足し、キャレット位置を含む最深ノードを setSelection する（reveal=false で無限ループを避ける）。

### P5-キャレット-15 / CONFIRMED / `D:/1.atrium/mmm/src/mindmap.ts:1525`

**Mod+←/→ がマップの選択移動として動作し、既定動作も潰される**

```
if (mod && (dirKey === "ArrowUp" || dirKey === "ArrowDown")) {
```

**症状**: 1512 行の `const dirKey = mod ? key : ...` により Mod+矢印も dirKey が Arrow* になり、1523-1524 で preventDefault される。しかし Mod 分岐は上下（並び替え）しか扱っていないので、Mod+←/→ はそのまま通常の左右ナビゲーションとして実行される。

**再現条件**: マップでノードを選び Mod+→ を押す。修飾なしの → と同じく子ノードへ選択が移動する（並び替えでもブラウザ既定動作でもない）。

**確度**: 確定

**検証の根拠**: src/mindmap.ts:1512-1522 `const dirKey = mod ? key : (h/j/k/l 変換)` により Mod+ArrowLeft/Right も dirKey が "ArrowLeft"/"ArrowRight" のままになり、1523 `if (!dirKey.startsWith("Arrow")) return;` を通過して 1524 で preventDefault。1525 の Mod 分岐は ArrowUp/ArrowDown しか扱わないので、そのまま 1561-1575 の side-aware な左右ナビゲーションが実行される。到達性も確認: 1349 の `if (!mod && !e.altKey)` ブロック、1437-1505 の各分岐（Enter / i,a,A,I / o,O / Tab / Delete / Mod+A / Mod+C / Mod+X / Mod+V）と 1506 Escape のいずれにも Mod+Arrow は掛からない。src/main.ts:882-910 のグローバル capture ハンドラも s / o / / / z / y しか見ないので横取りしない。README.md:87 が定義しているのは `Mod+↑↓`（並べ替え）だけで Mod+←→ は未定義。

**検証による訂正**: 「既定動作も潰される」は誇張。マップペインは非編集領域の div なので Windows/Chrome では Ctrl+←/→ にブラウザ既定動作がなく、preventDefault は実害がない（macOS の Cmd+←/→ も同様にページ内では無動作）。実質的な問題は「未割り当ての修飾キー操作が修飾なしと同じコマンドとして誤発火する」点のみ。

**影響**: 割り当てのない修飾キー操作が別のコマンドとして誤発火する。将来 Mod+←/→ に機能を割り当てる際の衝突源。

**修正方針**: 1525 行の条件を `if (mod)` にして、上下以外は return する（または Mod+←/→ を indent/outdent に割り当てる）。

### 反証により除外(1 件)

- **i / a / A のキャレット位置が全て末尾で、vim の意味と一致しない** — コードの記述（src/mindmap.ts:1443 `this.editCaret = key === "I" ? "start" : "end";`、src/mindmap.ts:915-917 で "start" のみ 0、他は value.length）は正しいが、これは意図された仕様どおりの実装であって欠陥ではない。README.md:66-67 が「`Mod+Enter` / `i` `a` `A` / ダブルクリック｜編集開始(カーソルは末尾)」「`I`｜編集開始(カーソルは先頭)」と明記しており、企画メモ mmm.md の 課題>ux 節にも「編集開始時全選択／やめたい。最後にカーソル」と、末尾キャレットが明示的な要望として書かれている。src/mindmap.ts:1436 のコメントも同じ仕様を宣言している。マップの選択モードにはラベル内カーソルという概念自体が存在しないため「カーソル直前/直後」を実装する土台もない。

---

## 3. キーボード入力全般（mindmap.ts onKeydown / vim 2ストローク、main.ts window capture、editor.ts keymap、popup.ts）

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

### P5-キーボード-1 / CONFIRMED / `D:/1.atrium/mmm/src/main.ts:895`

**ノードラベル編集中の Ctrl+O がブラウザの「ファイルを開く」ダイアログに素通りする**

```
if (mapPane.contains(document.activeElement)) return;
```

**症状**: コメントは「in the map pane (incl. its label editor) Mod+O belongs to the map」と書いているが、#node-editor は mapPane の子(mindmap.ts:246)なのでこの return に入り preventDefault されない。一方 #node-editor の keydown ハンドラ(mindmap.ts:1280-1289)は Escape / Enter / Tab しか扱わず preventDefault しない。結果 Ctrl+O の既定動作（ブラウザのローカルファイルを開くダイアログ）がそのまま発火する。

**再現条件**: 1. マップ上のノードをダブルクリック（または i / Enter）してラベル編集に入る。2. そのまま Ctrl+O を押す。3. OS のファイル選択ダイアログが開く。4. 適当なファイルを選ぶとタブがそのファイルへ遷移し、mmm のセッション（fileHandle、選択、編集中ラベル）が消える（未保存なら beforeunload の確認だけ出る）。マップペイン本体にフォーカスがある状態では同じ Ctrl+O が「--- グループ付き兄弟追加」になるので、編集に入った瞬間だけ挙動が変わる。

**確度**: 確定

**検証の根拠**: src/main.ts:895 `if (mapPane.contains(document.activeElement)) return;` returns BEFORE `e.preventDefault()` (main.ts:896). #node-editor is appended to the map pane at src/mindmap.ts:246 (`pane.append(this.editor)`), and beginEdit focuses it (mindmap.ts:913), so during label editing activeElement IS inside mapPane. The editor's own handler (mindmap.ts:1280-1289) calls e.stopPropagation() but only preventDefault()s Escape/Enter/Tab, so Ctrl+O is never cancelled and the browser default runs. The pane-level handler that would have consumed o/O (mindmap.ts:1457-1463) is unreachable because onKeydown early-returns while editing (mindmap.ts:1327) and the editor stopPropagation()s anyway. No other guard exists.

**検証による訂正**: 再現手順 1 の「または i / Enter」は不正確: 素の Enter は編集ではなく addSibling (mindmap.ts:1450-1454) で、新規ノードが作られてからその新規ノードの編集に入る (main.ts:320 -> runCmd の opts.edit -> map.beginEdit)。編集モードに入る直接の操作は ダブルクリック / i / a / A / I / Mod+Enter (mindmap.ts:1437-1448)。それ以外(機構・影響)は引用どおり。

**影響**: 編集中の誤爆で意図せずアプリから離脱する。localStorage に本文は残るが、ファイルハンドルとフォーカス状態は失われる。

**修正方針**: #node-editor の keydown で mod+o を捕まえて preventDefault する（何もしない、またはマップと同じ addSibling(split) に流す）。あるいは main.ts:895 の early return を `preventDefault()` してから return に変える。

### P5-キーボード-2 / CONFIRMED / `D:/1.atrium/mmm/src/popup.ts:219`

**お絵描きポップアップだけフォーカスを移さないため、モーダルの裏でマップのショートカットが全部生きている / Esc で閉じない**

```
body.append(bar, canvas);
```

**症状**: showCodePopup は `queueMicrotask(() => code.focus())` (popup.ts:94)、showLinkPopup は `queueMicrotask(() => url.focus())` (popup.ts:126) でフォーカスを奪うが、showDrawPopup にはフォーカス移動が一切無い。document.body.append(overlay) はフォーカスを動かさないので activeElement は map-pane のまま。よってキー入力は overlay の keydown(popup.ts:48) ではなく map-pane の onKeydown に届き、Esc も overlay に届かないためポップアップが閉じない。

**再現条件**: 1. ノードを 1 つ選択し、Shift+D でお絵描きポップアップを開く。2. Esc を押す → ポップアップは閉じず、代わりに選択だけが解除される（mindmap.ts:1506-1509）。3. 続けて d d と押す → 裏で選択ノードが削除される。y y でコピー、Enter で兄弟追加、Shift+Tab で親作成も全部通る。4. 絵を描いて「確定」を押すと、host.addDrawing の `byId.has(id)` (main.ts:450) が生きていれば既に別物になっている木に画像行が挿入される。

**確度**: 確定

**検証の根拠**: src/popup.ts:151-235 の showDrawPopup には focus() 呼び出しが 1 つも無い(showCodePopup は popup.ts:94、showLinkPopup は popup.ts:126 で queueMicrotask focus)。overlay は popup.ts:60 で document.body に append されるだけでフォーカスを動かさず、host.addDrawing は map-pane の onKeydown (mindmap.ts:1417-1427) から同期的に呼ばれるので activeElement は #map-pane のまま。overlay の keydown リスナ(popup.ts:48)は overlay の子孫が target のときしか発火せず、#map-pane は overlay の子孫ではないため Escape は overlay に届かない。map-pane 側では Escape が clearSelection のみ(mindmap.ts:1506-1509)、dd は deleteSelection(mindmap.ts:1350-1355)を実行する。deleteSelection は selection 全体を消し(main.ts:345-354)、cmd_delete が st.focus を次の生存ノードに移す(core/cmds.mbt cmd_delete 末尾 `st.focus = focus_id`)ので連鎖もする。

**検証による訂正**: 補足: キャンバスを一度クリックすると Chrome では focus が非フォーカス要素経由で body へ移り、その後は Esc も dd も「何も起きない」状態になる(overlay は body の子なので body 経由でも overlay の keydown は発火しない)。つまり「裏でショートカットが効く」のは描き始める前、描き始めた後は「キーが完全に死ぬ」に変わる。どちらにせよ Esc で閉じないのは変わらない。

**影響**: モーダル表示中に文書が黙って破壊される。Esc が効かないので閉じ方がボタンしかないことも一貫性を欠く。

**修正方針**: showDrawPopup でも canvas か btnOk に queueMicrotask(() => …focus()) する。より確実には shell() 側で overlay 生成直後に panel（tabindex=-1）へフォーカスを移す。

### P5-キーボード-3 / CONFIRMED / `D:/1.atrium/mmm/src/main.ts:909`

**グローバルショートカットが capture 段のためモーダルポップアップの裏で発火する（Mod+O でファイルを差し替えると id 再利用で別ノードに挿入される）**

```
{ capture: true },
```

**症状**: popup.ts:49 の `e.stopPropagation(); // keep map/global shortcuts out` は overlay（ターゲット側）でのバブル停止なので、window の capture リスナ(main.ts:883)には一切効かない。ポップアップ表示中でも Mod+S(保存)、Mod+O(ファイルを開く)、Mod+/(ペイン切替=モーダル裏へフォーカス移動)、Mod+Z/Y(undo/redo) がそのまま走る。さらに core/api.mbt:104 の `st.next_id = 1` によって initDoc でノード id が 1 から振り直されるため、ポップアップが握っている id が新文書の別ノードに一致してしまう。

**再現条件**: 1. ノードを選択し Shift+C でコードポップアップを開く（フォーカスは textarea）。2. Ctrl+O を押す → activeElement は mapPane の外なので main.ts:896 が preventDefault して openFile() が走り、ファイル選択ダイアログが出る。3. 別の .md を選ぶ（未保存なら破棄確認）→ loadText → core.initDoc で id が振り直される。4. 開いたままのポップアップにコードを書いて Mod+Enter → main.ts:437 の `if (r && byId.has(id))` が新文書の同 id ノードに当たり、まったく無関係なノードの本文にコードブロックが挿入される。Ctrl+Z を押した場合はモーダルの裏で undo が進む。

**確度**: 確定

**検証の根拠**: src/main.ts:882-910 の window keydown は `{ capture: true }` (main.ts:909)。popup.ts:48-49 のリスナは overlay のバブル段なので、window の capture より必ず後に走り stopPropagation は無意味。コードポップアップ表示中の activeElement は overlay 内の textarea で mapPane の外なので main.ts:895 の return を通らず 896-897 で preventDefault + openFile() が走る。Mod+Z も map.isEditing() が false(ラベル編集ではない)なので main.ts:901-906 で doUndo が走り、textarea のネイティブ undo は preventDefault で潰される。Mod+/ は main.ts:950-956 の else 分岐で editor.focus() = モーダル裏の CodeMirror にフォーカスが移る。id 再利用も core/api.mbt:104 `st.next_id = 1` と core/doc.mbt:281-288 で確認、閉じ込めた id を見る main.ts:437 `if (r && byId.has(id))` は applySnap(main.ts:183) で差し替わった新 byId を読む。

**影響**: モーダル中の操作でファイル差し替え・undo が起き、最終的に指定していないノードへ本文が混入する。

**修正方針**: モーダル表示中フラグ（開いている overlay の有無）を持ち、main.ts の capture ハンドラ冒頭で `if (document.querySelector('.popup-overlay')) return;` 相当のガードを入れる。加えて addLink/addCode/addDrawing は id ではなく rev+id で有効性を確認する。

### P5-キーボード-4 / CONFIRMED / `D:/1.atrium/mmm/src/mindmap.ts:1429`

**CapsLock ON で h が「サブツリーをコメントアウト」に化ける（大文字判定のキーが e.shiftKey を見ていない）**

```
if (key === "H" && anchor !== -1) {
```

**症状**: CapsLock が有効だと e.key は大文字になる（shiftKey は false のまま）。onKeydown はほぼ全分岐で e.key の大文字小文字だけを見ており e.shiftKey を照合していないため、意味が入れ替わる。h→"H" で toggleHidden（破壊的）、d→"D" でお絵描きポップアップ、c→"C" でコードポップアップ、l→"L" でリンクポップアップ、g→"G" で最終ノードへジャンプ、j/k→"J"/"K" は未定義でナビゲーション不能、u/y/z/s も無効化される。なお o/O だけは line 1459 で e.shiftKey を見ているので CapsLock でも正しく動く＝実装が不統一であることの裏付け。

**再現条件**: 1. CapsLock を ON にする。2. マップペインでノードを選択し、左へ移動するつもりで h を押す。3. 移動せず、そのノードのサブツリー全体がコメントアウト（hidden 化）される。続けて j/k を押しても何も起きない。d を押すとお絵描きポップアップが開く。

**確度**: 確定

**検証の根拠**: onKeydown は e.key の値だけで分岐する: mindmap.ts:1429 `if (key === "H" && anchor !== -1)` -> toggleHidden、1417-1427 の C/D/L、1391 の G。KeyboardEvent.key は CapsLock の影響を受けて大文字になり shiftKey は false のままなので、これらは CapsLock ON の h/c/d/l/g で成立する。j/k は 1512-1522 の dirKey マップが小文字のみを見るため "J"/"K" は 1523 `if (!dirKey.startsWith("Arrow")) return;` で握り潰される。u(1411)/y(1356)/z(1400)/s(1372) も小文字比較のみで無効化。指摘どおり o/O だけが 1457-1461 で e.shiftKey を見ており、実装が不統一であることも確認。p/P(1406) と i/a/A/I(1439) は両ケース列挙で救われている。

**影響**: CapsLock ON のユーザは移動キーが破壊的コマンドになり、vim 系ショートカットの半分が沈黙する。

**修正方針**: 判定を `key.toLowerCase()` + `e.shiftKey` の組に統一する（例: `const k = key.toLowerCase(); if (k === "h" && e.shiftKey) toggleHidden…`）。既に正しい形の line 1459 に合わせる。

### P5-キーボード-5 / CONFIRMED / `D:/1.atrium/mmm/src/mindmap.ts:1351`

**キーリピートに対するガードが無く、d を押しっぱなしにすると連続削除される**

```
if (prev === "d") this.host.deleteSelection();
```

**症状**: src 全体に e.repeat の参照が 0 件。OS のオートリピート（Windows 既定で初回 ~500ms、以降 ~30ms 間隔）は keydown を撃ち続けるため、2 回に 1 回 prev==="d" が成立して deleteSelection が走る。リピート間隔は pendingTimer の 700ms より短いのでタイマは救済にならない。deleteSelection 後は snap.focus が次のノードに移る(main.ts:349)ので、削除が次々と連鎖する。Delete / Backspace(1478) と Ctrl+X(1496) も同様に無防備。

**再現条件**: 1. ノードを選択し、d キーを 1.5 秒ほど押しっぱなしにする。2. 十数ノードが次々に削除される（undo エントリも同数積まれる）。Delete キーを押しっぱなしにしても同様に木が消えていく。

**確度**: 確定

**検証の根拠**: src/ 全体を grep して e.repeat の参照は 0 件(src/mindmap.ts の hit は String.repeat と英文コメントのみ)。pendingKey は onKeydown 冒頭(mindmap.ts:1335-1336)で毎回読み捨てられるので、リピート列 d,d,d,d は pend -> delete -> pend -> delete と 2 回に 1 回 mindmap.ts:1351 の deleteSelection に落ちる。pendingTimer は 700ms(1346)で OS のリピート間隔より長いため救済にならない。削除後は core/cmds.mbt の cmd_delete が `st.focus = focus_id`(直後の生存ノード)を返し、main.ts:349-350 がそれを新しい選択にするので連鎖する。Delete/Backspace(1478-1482)と Mod+X(1496-1500 -> main.ts:374-379 -> deleteSelection)は 2 ストロークですらないので毎リピート削除。

**影響**: キーが引っかかった／長押しした瞬間に文書が大量に失われる。復旧には undo の連打が必要。

**修正方針**: onKeydown 冒頭で破壊的コマンド（dd / Delete / Backspace / Mod+X）については `if (e.repeat) return;` を入れる。2 ストローク機構自体もリピート由来の keydown を prev として扱わないようにする。

### P5-キーボード-6 / CONFIRMED / `D:/1.atrium/mmm/src/mindmap.ts:1000`

**Space 押下中にウィンドウがフォーカスを失うと spaceDown が true のまま残り、以後クリックがパンになる**

```
this.spaceDown = true;
```

**症状**: spaceDown を false に戻すのは window の keyup(1005-1010) だけ。Alt+Tab 等でウィンドウがフォーカスを失うと keyup は届かない。window の blur ハンドラ(1302)は hideMenu しかしておらず spaceDown をリセットしない。結果、戻ってきた後の左クリックが pointerdown(1048) で `e.button === 0 && this.spaceDown` に一致し、選択ではなくパンになる。カーソルも grab のまま固定される。

**再現条件**: 1. マップペインをクリックしてフォーカスを与える。2. Space を押したまま Alt+Tab で別アプリへ切り替え、そこで Space を離す。3. mmm に戻ってノードを左クリック→ドラッグ → ノードが選択されずキャンバスがパンする。Space を一度押して離すまで直らない。

**確度**: 確定

**検証の根拠**: spaceDown の出現箇所は mindmap.ts:189(宣言) / 1000(true) / 1007(false) / 1048(判定) / 1140(カーソル復帰)のみで、false に戻すのは window keyup(1005-1010)だけ。window blur ハンドラ(mindmap.ts:1302)は `() => this.hideMenu()` のみで spaceDown も pane.style.cursor もリセットしない。pointercancel(1194-1202)は panning/rubber/dragCand は畳むが spaceDown は触らない。したがってウィンドウ非フォーカス中の keyup を取り逃すと 1048 `e.button === 0 && this.spaceDown` が成立し続け、pointerup(1140)も `this.spaceDown ? "grab" : ""` なのでカーソルも grab のまま固定される。

**影響**: 入力モードが見た目上の手掛かりなく固着し、選択・ドラッグ移動が一切できなくなる。

**修正方針**: 既存の `window.addEventListener("blur", …)`(1302) に `this.spaceDown = false; this.panning = null; pane.style.cursor = "";` を追加する。document の visibilitychange でも同様に落とす。

### P5-キーボード-7 / CONFIRMED / `D:/1.atrium/mmm/src/mindmap.ts:1466`

**マップペインが Tab のフォーカストラップになっていて脱出手段が無い**

```
if (key === "Tab" && !e.shiftKey) {
```

**症状**: Tab / Shift+Tab はどちらの分岐でも無条件に e.preventDefault()(1470, 1476)される。anchor === -1 かつ sel.size <= 1 で何も起きないケースでも preventDefault だけは実行されるため、マップペインに一度フォーカスが入るとキーボードだけではツールバー（開く/保存/undo/redo/テーマ）へ戻れない。md ペイン側は CodeMirror が Escape→Tab の脱出（@codemirror/view dist:4947）と Ctrl-m の toggleTabFocusMode を持つが、マップペインには相当物が無い。#node-editor 編集中も Tab は preventDefault(mindmap.ts:1286)。

**再現条件**: 1. ページ読み込み直後（main.ts:1135 で mapPane.focus() 済み）またはツールバーから Tab を押してマップペインに入る。2. Tab / Shift+Tab を何度押してもフォーカスリングがツールバーに移らない。3. マウスを使わずにツールバーへ到達する手段は Mod+/（md ペインへ移動）→ Escape → Tab しかない。

**確度**: 確定

**検証の根拠**: index.html:39 で `<section id="map-pane" tabindex="0">`、main.ts:1135 で起動時に mapPane.focus()。mindmap.ts:1466-1477 の Tab / Shift+Tab はどちらも分岐の中身が何もしないケース(sel.size<=1 かつ anchor===-1、ノード 0 件を含む)でも 1469/1475 の e.preventDefault() に必ず到達する。ラベル編集中も editor 側 1286-1288 で Tab を preventDefault。md ペイン側の脱出路は実在する: node_modules/@codemirror/view/dist/index.js:4947-4948 が Escape(keyCode 27)で tabFocusMode を 2 秒有効化し、4599 がその間の Tab を素通しさせる。マップペインに相当物は無く、キーボードだけの脱出は Mod+/(main.ts:898-900 -> togglePane)のみ。

**影響**: キーボードのみの利用者・支援技術利用者がツールバーに到達できない。

**修正方針**: anchor === -1 のときは preventDefault しない、あるいは Escape を押した直後の Tab だけ既定動作を通す（CodeMirror の tabFocusMode と同じ方式）逃げ道を用意する。

### P5-キーボード-8 / CONFIRMED / `D:/1.atrium/mmm/src/popup.ts:60`

**ポップアップにフォーカストラップが無く、Shift+Tab で背後の UI に抜けられる**

```
document.body.append(overlay);
```

**症状**: overlay は body 末尾に追加されるだけで、focus トラップも inert/aria-modal も無い。overlay の keydown(48)は Escape と Mod+Enter しか処理せず Tab を止めない。コードポップアップの textarea は Tab を潰す(popup.ts:86-92)が、その手前の「言語」入力からの Shift+Tab は素通りする。overlay は position:fixed の全面（style.css:172-180）なのでポインタは遮られるが、キーボードは遮られない。

**再現条件**: 1. ノードを選択し Shift+C でコードポップアップを開く（フォーカスは textarea）。2. Shift+Tab を 2 回押す → フォーカスがオーバーレイの背後にあるツールバー/マップペインへ抜ける。3. その状態で Enter / Space を押すと背後のボタン（開く・保存など）が起動する。

**確度**: 確定

**検証の根拠**: popup.ts:60 で overlay を body 末尾に append するだけで、inert / aria-modal / focus トラップは一切無い(popup.ts 全 236 行に該当コード無し)。overlay の keydown(48-57)は Escape と Mod+Enter しか扱わず Tab の既定動作(フォーカス移動)は止まらない — stopPropagation はフォーカス移動を妨げない。style.css の .popup-overlay は position:fixed; inset:0; z-index:40 でポインタだけを遮る。textarea の Tab 潰し(popup.ts:86-92)は「言語」input には無いので前方向も後方向も抜けられる。

**検証による訂正**: 「Shift+Tab 2 回でツールバー/マップペインへ抜ける」は着地点が不正確。DOM 順は body > [#app(toolbar, panes), colorInput(main.ts:152-163), #ctx-menu(mindmap.ts:257), overlay] なので、textarea から Shift+Tab 1 回目 = 同 overlay 内の「言語」input、2 回目 = overlay の外にある不可視の colorInput(opacity:0 だが display/visibility では隠されていないので tabbable、Enter/Space で OS のカラーピッカーが開く)、3 回目以降で #map-pane(tabindex=0) -> md ペインの CodeMirror -> ツールバーのボタンに到達する。またフォーカスが overlay の外に出た時点で popup.ts:48 のリスナに keydown が届かなくなるため Esc でも閉じられなくなる、という追加の帰結がある。

**影響**: モーダル表示中に背後の UI を誤操作できる。スクリーンリーダ利用時はモーダル外の内容も読み上げられる。

**修正方針**: shell() で overlay 内の最初/最後のフォーカス可能要素を掴んで Tab をラップさせる（または <dialog showModal()> に置き換える）。

### P5-キーボード-9 / CONFIRMED / `D:/1.atrium/mmm/src/mindmap.ts:1802`

**コンテキストメニューがキーボードを一切受け付けず、Esc でも閉じない**

```
hideMenu(): void {
```

**症状**: #ctx-menu は document.body 直下(258)でフォーカス不可、キーボードハンドラも無い。hideMenu を呼ぶのは pointerdown(1299-1301)と window blur(1302)だけ。右クリック時は pointerdown(1046)で pane.focus() 済みなので、メニュー表示中のキーは全部 map-pane の onKeydown に流れる。Escape は clearSelection(1506-1509)するだけでメニューは残り、しかもメニュー項目は `this.host.anchor()` を実行時に読むため、選択解除後にクリックすると空振り（あるいは別ノードに対して実行）になる。

**再現条件**: 1. ノードを右クリックしてコンテキストメニューを開く。2. Esc を押す → メニューは開いたまま、ノードの選択ハイライトだけが消える。3. その状態でメニューの「削除」をクリック → deleteSelection は selection.size === 0 で何もしない(main.ts:346)。4. 手順 2 の代わりに d d を押すと、メニューが開いたまま裏でノードが削除される。

**確度**: 確定

**検証の根拠**: #ctx-menu は mindmap.ts:255-257 で document.body 直下に作られ、tabindex も keydown ハンドラも無い(showMenu 1720-1800 が付けるのは click のみ)。hideMenu(1802-1804)の呼び出し元は pane pointerdown(1045)、document pointerdown(1299-1301)、window blur(1302)、メニュー項目 click(1790)だけ。右クリックでも pane の pointerdown は走り(e.button!==0 の return は 1060、pane.focus() はその前の 1046)フォーカスは map-pane に残るので、メニュー表示中のキーは全部 onKeydown に流れ、Escape は clearSelection のみ(1506-1509)。その後「削除」を押しても main.ts:346 `if (selection.size === 0) return;` で空振り。メニュー項目が実行時に this.host.anchor() を読む点(1730/1736/1742/1748/1754)も引用どおりで、メニューを開いたまま矢印キーで選択を移せば別ノードに対して実行される。

**影響**: メニューが閉じない・項目が無反応という不整合、およびメニュー表示中の裏側キー操作。

**修正方針**: showMenu 中は keydown を監視し、Escape で hideMenu、矢印/Enter で項目移動・実行できるようにする。少なくとも onKeydown の先頭で「メニューが開いていたら hideMenu して return」する。

### P5-キーボード-10 / 要確認 / `D:/1.atrium/mmm/src/mindmap.ts:924`

**endEdit() が blur ハンドラ経由でも無条件に map-pane へフォーカスを引き戻し、クリック先とフォーカスを奪い合う**

```
this.pane.focus();
```

**症状**: #node-editor の blur → host.commitEdit()(1290-1292) → map.endEdit() → pane.focus() という経路があり、blur の原因が「別要素へのフォーカス移動」であっても無条件にマップペインへ引き戻す。CodeMirror の mousedown ハンドラは同期的に contentDOM.focus() したのち `let active = view.root.activeElement; if (active && !active.contains(view.contentDOM)) active.blur();`（@codemirror/view dist:4985-4987）を実行するので、割り込んだ pane.focus() の結果 map-pane が blur され、最終的にどこにもフォーカスが無い状態（body）になり得る。

**再現条件**: 1. マップのノードをダブルクリックしてラベル編集に入る。2. そのまま md ペインの本文を 1 回クリックする。3. キャレットが md ペインに入らない（続けてタイプしても文字が入らない）。DevTools の Console で `document.activeElement` を見て、body または #map-pane になっていれば本件。合わせて、ラベル編集中に Alt+Tab でウィンドウを離れるだけでも blur→commitEdit→pane.focus() が走り、戻ったときに編集モードが終了してフォーカスがマップに移っている。

**確度**: 要確認

**検証の根拠**: コード側の事実は全部確認できた: mindmap.ts:1290-1292 の blur -> main.ts:339-344 commitEdit -> mindmap.ts:920-925 endEdit -> 924 `this.pane.focus()` は blur の原因を問わず無条件。引用された CodeMirror のコードも実在する(node_modules/@codemirror/view/dist/index.js の handlers.mousedown 内、`focusPreventScroll(view.contentDOM); let active = view.root.activeElement; if (active && !active.contains(view.contentDOM)) active.blur();`、行番号もほぼ 4980 台で一致)。決着しないのは blur ハンドラ内の再入 focus() をブラウザがどう解決するか(進行中の focus 転送を中止するか上書きするか)で、これはコードからは判定できない。決め手となる観測: ラベル編集中に md ペイン本文を 1 回クリックし、DevTools Console で `document.activeElement` を評価する — #map-pane または body なら本件、.cm-content ならフォーカスは正常に渡っている。

**検証による訂正**: 2 つに分けるべき。(a) コードだけで確定する部分: ラベル編集中に Alt+Tab などでウィンドウがフォーカスを失うと input の blur -> commitEdit -> endEdit が走り、編集モードが黙って終了してフォーカスがマップペインに移る(mindmap.ts:1290-1292 / 920-925)。これは 確定。(b) 「md ペインをクリックしてもキャレットが入らない / どこにもフォーカスが無い」は上記のブラウザ観測が必要な 要確認 部分。

**影響**: 編集からの離脱操作が 1 クリック余分に必要になる。ブラウザ差で「どこにもフォーカスが無い」状態が残る可能性がある。

**修正方針**: endEdit に `refocus = true` 引数を設け、blur 由来の commitEdit では pane.focus() を呼ばない（または `if (!this.pane.contains(document.activeElement) && document.activeElement === document.body)` の条件付きにする）。

### P5-キーボード-11 / CONFIRMED / `D:/1.atrium/mmm/src/mindmap.ts:1336`

**修飾キー単独の keydown が vim 2ストロークの前半を消す**

```
this.pendingKey = "";
```

**症状**: onKeydown は key の種類に関係なく先頭で pendingKey を読み捨てる。Shift / Control / Alt / Meta / CapsLock を単独で押した keydown もここを通るため（それらは以降のどの分岐にも当たらず 1523 の return で終わる）、d→Shift→d のように途中に修飾キーが挟まると 2 ストロークが不成立になる。ユーザ側にはフィードバックが無いので「dd が効かないことがある」という再現性の低い症状になる。

**再現条件**: 1. ノードを選択して d を押す。2. Shift キーを 1 回押して離す（何も入力しない）。3. もう一度 d を押す → 削除されず、また pending 状態に戻るだけ。手順 2 を CapsLock や Ctrl に変えても同じ。

**確度**: 確定

**検証の根拠**: mindmap.ts:1325-1340: onKeydown は key の種類を見る前に 1335-1336 で `const prev = this.pendingKey; this.pendingKey = "";` を実行し、1337-1340 で pendingTimer もクリアする。Shift 単独(keyCode 16、isComposing false、mod false、altKey false)は 1349 のブロックに入るがどの key 比較にも当たらず、1437/1450/1457/1466/1478/1483/1506 も外れ、dirKey = "Shift" が 1523 `if (!dirKey.startsWith("Arrow")) return;` で終わる。Control/Meta 単独は mod=true で vim ブロックごと飛ばして同じく 1523 で終わる。いずれも pendingKey を消費だけして何も起こさないので d -> Shift -> d が dd にならない。

**影響**: 2 ストロークコマンドが不定期に不発になる。

**修正方針**: onKeydown 冒頭で `if (e.key === "Shift" || e.key === "Control" || e.key === "Alt" || e.key === "Meta" || e.key === "CapsLock") return;` として pendingKey を保持する。

### P5-キーボード-12 / CONFIRMED / `D:/1.atrium/mmm/src/main.ts:889`

**Ctrl+S の長押しで saveFile() が多重起動し、書き込みロック衝突で「保存失敗」になり得る**

```
if (key === "s") {
```

**症状**: e.repeat ガードも「保存処理が in-flight か」のフラグも無いまま `void saveFile()` を撃つ。saveFile は await fileHandle.createWritable()(main.ts:571) を使うが、FileSystemWritableFileStream は同一ファイルをロックするため、前の write が close される前に次の createWritable が走ると reject する。catch は AbortError 以外を「保存失敗」として flashFilename する(main.ts:593-596)。

**再現条件**: 1. ファイルハンドルを持った状態（一度 保存 済み）で編集する。2. Ctrl+S を 2 秒ほど押しっぱなしにする。3. ファイル名の横に「保存失敗」が出るか、Console に NoModificationAllowedError が出るかを確認する。出れば本件（実ファイルは最後の成功分まで書けている）。

**確度**: 確定

**検証の根拠**: main.ts:889-891 は `if (key === "s") { e.preventDefault(); void saveFile(); }` のみで、e.repeat ガードも in-flight フラグも無い(src 全体に e.repeat 参照 0 件)。saveFile(main.ts:551-598)自体も再入可能で、await queryPermission(557) の後 await createWritable(571) -> write -> close(573) と続くため、リピート間隔次第で前の writable が close される前に次の createWritable が走る。catch(590-597)は AbortError 以外を全部 flashFilename("保存失敗") にする。

**検証による訂正**: 確定部分は「ガードが無く saveFile が多重・並行起動する(毎リピートごとに同じ内容を再書き込みし、IndexedDB への persistHandle も毎回走る)」まで。「保存失敗」表示が実際に出るかは前の write が閉じる前に次の createWritable が来るかというタイミング依存で、コードだけでは決まらない — DevTools Console の NoModificationAllowedError の有無で確認すること。なお fileHandle 未取得の状態では showSaveFilePicker(564) が多重に呼ばれ、ピッカー二重起動で失敗する別経路もある。

**影響**: 実際には保存できているのに失敗表示が出る／逆に失敗表示を無視する習慣がつく。

**修正方針**: saveFile に in-flight ガード（Promise を 1 本に畳む）を入れ、キーハンドラ側でも `if (e.repeat) return;` する。

### P5-キーボード-13 / CONFIRMED / `D:/1.atrium/mmm/src/mindmap.ts:1430`

**Shift+H (toggleHidden) だけが複数選択を無視して anchor 1 個にしか効かない**

```
this.host.toggleHidden(anchor);
```

**症状**: dd / Delete / Tab(indent) / Shift+Tab(outdent) / Mod+C / Mod+X は selection 全体に作用する(1467, 1473, 1479, 1492, 1497)のに対し、H だけ anchor 単独。sel.size のガードも無いので「複数選択しているのに 1 個だけ折り畳まれた」という結果になる。しかも toggleHidden は runCmd 経由(main.ts:368-370)で snap.focus に選択を貼り替えるため、元の複数選択も失われる。

**再現条件**: 1. Shift+ArrowDown で 3 ノードを選択する。2. Shift+H を押す。3. anchor の 1 ノードだけが hidden になり、選択は 1 ノードに縮む。

**確度**: 確定

**検証の根拠**: mindmap.ts:1429-1433 は `if (key === "H" && anchor !== -1) { this.host.toggleHidden(anchor); }` で sel.size のガードすら無い。同じブロックの C/D/L は 1417-1421 で `sel.size <= 1` を要求し、Tab(1467)/Shift+Tab(1473)/Delete(1479)/Mod+C(1492)/Mod+X(1497) は selection 全体に作用する(main.ts:345-379)。選択リセットも確認: core/cmds.mbt の cmd_toggle_hidden は成功時に `st.focus = id` を設定し、main.ts:368-370 の runCmd が main.ts:237-241 で `setSelection([snap.focus], snap.focus)` を実行するため元の複数選択は 1 件に潰れる。

**検証による訂正**: 再現手順の「anchor の 1 ノード」= Shift+ArrowDown で最後に伸ばした先のノード。mindmap.ts:1542-1552 の Shift+矢印は `this.host.setSelection([...set], nx)` で anchor を新しく加えたノードに移すため、最初に選んだノードではない。

**影響**: 複数選択に対する操作の一貫性が崩れ、選択もリセットされる。

**修正方針**: host に toggleHiddenSelection を追加して選択全体に適用するか、少なくとも sel.size > 1 のときは何もしない（あるいは全件に順次適用）。

### P5-キーボード-14 / CONFIRMED / `D:/1.atrium/mmm/src/mindmap.ts:1502`

**マップペインの Mod+V はネイティブ貼り付けを preventDefault した上でエラーを全部握り潰すので、失敗が無言になる**

```
this.host.paste();
```

**症状**: 1503 で preventDefault するためブラウザの paste イベントは発生せず、実処理は navigator.clipboard.read()/readText()(main.ts:388, 399) に一本化される。その全体が `void (async () => {…})().catch(() => {});`(main.ts:384, 423) で包まれており、権限拒否・API 非対応・見出しを含まないクリップボード(main.ts:402 `if (!hasHeadings(normalized)) return;`)のいずれでも一切の通知が無い。

**再現条件**: 1. 見出しを含まない普通の文章をクリップボードにコピーする。2. マップでノードを選択し Mod+V（または p）を押す。3. 何も起きず、理由の表示も無い。クリップボード権限を「ブロック」に設定した場合も同じく無反応。

**確度**: 確定

**検証の根拠**: main.ts:380-424 の paste は全体が `void (async () => {…})().catch(() => {})`(384/423)で包まれ、さらに無言 return が 3 箇所ある: 383 `if (anchorId === -1 && nodes.length > 0) return;`、400 `if (!clip.trim()) return;`、402 `if (!hasHeadings(normalized)) return;`。hasHeadings(src/relevel.ts:36-38)は非フェンスの `#+[ \t]` が 1 つも無ければ false なので、見出しを含まない普通の文章は完全に無反応。clipboard.read/readText の権限拒否も 396-398 と 423 の catch で握り潰される。ユーザへの通知手段(flashFilename)はこの経路で一度も呼ばれない。

**検証による訂正**: 「ネイティブ貼り付けへのフォールバックも塞がれている」は誤り。src 全体に paste イベントのリスナは存在せず(grep で 0 件)、#map-pane は contenteditable でも input でもないので、preventDefault が無くてもネイティブ貼り付けは何も挿入しない。塞がれているフォールバックは元々存在しないので、実質的な欠陥は「無言の catch と無言の早期 return による原因不明の無反応」だけ。

**影響**: 貼り付けが効かない理由をユーザが判別できない。ネイティブ貼り付けへのフォールバックも塞がれている。

**修正方針**: host.paste の catch と早期 return の各所で flashFilename に理由を出す（「見出しを含むテキストのみ貼り付けできます」「クリップボードの読み取りが許可されていません」）。

### P5-キーボード-15 / CONFIRMED / `D:/1.atrium/mmm/src/mindmap.ts:1507`

**ドラッグ中の Escape は選択を消すだけでドロップは実行される**

```
this.host.clearSelection();
```

**症状**: pointerdown(1046)で pane にフォーカスが移っているためドラッグ中も onKeydown が動く。Escape の分岐は clearSelection のみで、this.dragging / this.dropTarget を触らない。pointerup(1155-1161)は `this.dragging` に保存済みの ids をそのまま `this.host.move(ids, drop.id, drop.pos)` に渡すので、Escape を押しても移動は取り消されない。

**再現条件**: 1. ノードを掴んで別ノードの上までドラッグする（ドロップインジケータが出る）。2. マウスボタンを押したまま Escape を押す → 選択ハイライトが消える。3. そのままドロップする → 移動は実行される。

**確度**: 確定

**検証の根拠**: pointerdown(mindmap.ts:1040-1046)で pane.focus() 済みなのでドラッグ中も pane の keydown -> onKeydown が走る。Escape 分岐(1506-1509)は `this.host.clearSelection()` だけで this.dragging / this.dropTarget / dropLine には触れない。pointerup(1155-1162)は `const drop = this.dropTarget; const ids = this.dragging.ids;` を読んでから stopDragVisuals し `if (drop) this.host.move(ids, drop.id, drop.pos)` を実行する。ids は startDrag(1585-1607)で確定済みなので選択解除の影響も受けない。pointercancel(1194-1202)には dragging を畳む処理があるが Escape はそこへ繋がっていない。

**影響**: ドラッグ操作を中断する一般的な手段（Esc）が効かず、誤配置を undo で戻すしかない。

**修正方針**: Escape の分岐で `if (this.dragging) { this.stopDragVisuals(); this.dragCand = null; return; }` を先に処理する。

### 反証により除外(1 件)

- **s / cc の editClear フラグが beginEdit の早期 return で消費されず、次回の編集がラベルを消す可能性がある** — beginEdit(mindmap.ts:899-901)の `if (!b) return;` は s / cc の経路からは到達不能。(1) core/doc.mbt:472-486 recompute_parents は文書順の走査中スタックに積んだ「リスト内の先行ノード」の id しか parent に入れないため、parent は必ず st.nodes 内に存在し、全ノードは parent===-1 の top を根とする森を成す。(2) render() は root 側を placeSide(mindmap.ts:517-540)、それ以外の top を 549-554 で処理し、placeF(448-486)が children を再帰的に辿って全ノードに boxes.set(475) するので boxes は常に全ノード id を含む。(3) anchor は applySnap(main.ts:192-195)で毎回 byId に無い id が刈られ、editRequested(main.ts:458)も `if (!byId.has(id)) return;` を通るので、beginEdit に渡る id は必ず boxes にある。したがって editClear がフラグとして残る経路が無い。なお F-005 で落ちる 2 個目の "#" 見出しは st.nodes 自体に入らない(core/doc.mbt:254-261)ので byId にも無く、anchor になり得ない。

---

## 4. ツリー操作（D&D・移動・複数選択・undo）— src/mindmap.ts のポインタ処理/startDrag/updateDrop、src/main.ts の host.move/indentSelection/outdentSelection/reorder、core/cmds.mbt の cmd_move/move_block/cmd_indent/cmd_outdent/cmd_reorder、core/doc.mbt の normalize_selection/apply_sets/map_offset

**調べたもの**

- src/mindmap.ts 全 1815 行（Read で 2 分割、NUL バイトは Grep を使わず回避）
- src/main.ts 全 1136 行
- core/cmds.mbt 全 686 行 / core/doc.mbt 全 528 行 / core/api.mbt / core/parser.mbt / core/js/exports.mbt / src/coreApi.ts
- 自分の子孫への D&D: UI 側は startDrag(1599-1606) の subtree セットで updateDrop(1635,1656) が除外、コア側も cmd_move(541) の `tn.hs >= nd.hs && tn.hs < nd.sub_end` で拒否。二重に防がれている（該当なし）
- 自分自身へのドロップ: subtree に自分が含まれる + cmd_move の同条件で弾かれる（該当なし）
- 親と子の同時選択: doc.mbt normalize_selection(502-527) が範囲包含で子を落とす。cmd_move/cmd_delete/cmd_indent/cmd_outdent/selection_text すべて通す。子は親のサブツリーごと動くので二重移動は起きない（該当なし）
- cmd_indent(351-375) が編集前の prev_sibling で一括 1 セットを作るため、連続兄弟をまとめて indent しても入れ子にならないことを確認（該当なし）
- cmd_move の anchor 連鎖(553-566): 2 個目以降は直前に動いたノードの後ろ・同深さに入るので、複数移動の順序と深さは保たれる（該当なし）
- cmd_move はトランザクション(528,568)で 1 undo エントリ。0 ステップのときは commit_tx(401) が push も redo.clear もしないので、no-op ドロップが redo を壊さないことを確認（該当なし）
- undo/redo の id 復元: move_block(499-511) が rels で id を貼り直し、tx 中は commit_tx が after を取り直す（refresh_entry_after 169-177 の tx 分岐）。undo 後もノード id は生き残る（該当なし）
- replay_entry(414-432) の逆順適用が invert_edit_set のオフセット規約と一致していること
- ドラッグ中に render() が走った場合: boxes/order は総入れ替えされるが id ベースなのでヒットテストは健全、dragging.subtree が古くなっても cmd_move のコア側チェックが最後の砦になる。ただし drop-child クラスは復元されない（finding 11）
- pointercancel(1194-1202) は panning/rubber/dragCand/dragging を全部落としており取りこぼしなし。dblclick(1204-1215) もドラッグを畳む（該当なし）
- ポインタキャプチャは pointerdown で必ず張られるので、ペイン外での pointerup は取りこぼさない（該当なし）
- ルート前ノード（別ツリー）との相互移動: 通常ノードの往復は正しく動く。ルート自身を動かす場合のみ破綻（finding 6）
- hidden ノードの subEnd が `-->` 行を跨ぐこと（parser.mbt scan_doc 94-98 + doc.mbt 311-317）を実文書でシミュレートして確認

### P5-ツリー操作-1 / CONFIRMED / `D:/1.atrium/mmm/src/mindmap.ts:1640`

**ドロップ先が文書順の先勝ちで決まり、BAND=40 が兄弟ピッチ 40 を丸ごと飲むため常に「1 つ前の兄弟」が奪う**

```
if (Math.abs(du) <= hu + SLOP && Math.abs(dv) <= hv + BAND) {
```

**症状**: ノード B のボックスのどこにポインタを置いても、ドロップ先が B ではなく直前の兄弟 A の pos=2（A の後ろ＝B の前）になる。B を「子として」狙うことはボックス上では原理的に不可能。

**再現条件**: 1. 起動直後のサンプル文書のまま（右側に `## markdown` → `## mindmap` が縦に並ぶ）。
2. `### 双方向編集` を掴んで `## mindmap` のボックスの上（中央でも下端でもどこでも）へ持っていく。
3. 期待: `## mindmap` にリング（子として）か `## mindmap` の下に挿入線。
4. 実際: 挿入線は `## markdown` と `## mindmap` の間に出る。離すと `## markdown` の直後（`## mindmap` の前）に入る。
数値: NODE_H=30 / GAP_Y=10 なので兄弟の中心間は 40px、A のマッチ帯は |dv| <= hv+BAND = 15+40 = 55px。B のボックス [+25,+55] は完全に A の帯の内側で、しかも dv=25〜55 はすべて hv*0.4=6 を超えるので必ず pos=2 になる。this.order は文書順で A が先、1651 行の break で確定する。

**確度**: 確定

**検証の根拠**: src/mindmap.ts:1634 `for (const id of this.order)` + :1649 `break` = first-match-wins over document order (this.order = nodes.map(n=>n.id), :292). Constants verified: NODE_H=30 (:78), GAP_Y=10 (:88), BAND=40 (:1639), pos=0 band = hv*0.4 (:1646-1648). Traced the sample doc (src/main.ts:39-56): `## markdown` and `## mindmap` are both leaves-with-one-leaf-child, so subV=30 each; placeSide (mindmap.ts:517-538) puts their centers at v=-20 and v=+20 (40px apart) with identical box x=edge0, so `## mindmap`'s whole box [+5,+35] sits inside `## markdown`'s |dv|<=hv+BAND=55 window and every point there has dv>=25 > hv*0.4=6 -> target={markdown,pos:2}. Repro produces exactly the described insertion line.

**検証による訂正**: Two fixes. (a) The `break` that locks in the winner is src/mindmap.ts:1649, not 1651 (1651 is the loop's closing brace). (b) "常に" is too strong: A only swallows B when A's reserved slot is small. Generally A steals B iff GAP_Y + 0.6*hv_B <= BAND, i.e. B shorter than ~100px, AND A's own subtree slot is not taller than its box (calcV/stackV, mindmap.ts:436-445). If the previous sibling has 2+ children its slot grows (e.g. 3 leaf children -> subV=110, centers 80px apart > hv+BAND=55) and B becomes targetable normally. So the failure hits leaf/single-child siblings — which is most of a typical map — not literally every node.

**影響**: D&D 再親付けの中核が壊れている。前の兄弟を持つノードは「子として」ドロップできず（唯一届くのは 1655-1665 の外側ゾーンだけ）、挿入位置も常に 1 つ手前にずれる。pos=0 の帯は hv*0.4 = 高さ 30px のノードでわずか 12px しかなく、BAND を「さらに拡大」した結果 pos=0 だけが取り残されている。

**修正方針**: 1634 の走査を「最初にマッチしたもの」ではなく「|dv|/hv が最小のもの」を選ぶようにする（break をやめて best を更新）。あわせて BAND をノード間ギャップ（GAP_Y/2 + 数 px）に縮め、pos=0 の帯を hv*0.4 ではなく実寸で広げる。

### P5-ツリー操作-2 / CONFIRMED / `D:/1.atrium/mmm/src/main.ts:372`

**D&D 移動後に複数選択が先頭 1 ノードへ潰れる（indent/outdent は保つのに move だけ潰す）**

```
runCmd(() => core.moveNodes(ids, target, pos));
```

**症状**: 複数ノードを掴んで移動すると全部動くが、移動後の選択は先頭 1 ノードだけになる。連続でもう一度動かしたい／色を変えたいときに選び直しが必要。Ctrl+Z しても選択は戻らない。

**再現条件**: 1. サンプル文書で `## markdown` をクリック、`## mindmap` を Shift+クリック（markdown / 実体 / mindmap の 3 つが選択される）。
2. その塊を掴んで `## mirror` の外側ギャップ（左方向）へドロップ。
3. 実際: 2 ブロックとも移動するが、選択は `## markdown` だけ。
4. Ctrl+Z で本文は戻るが選択は `## markdown` 1 つのまま。
5. 比較: 同じ複数選択でコンテキストメニューの「1 段下げ」（main.ts:355-359 indentSelection）を実行すると選択は 3 つのまま保たれる。

**確度**: 確定

**検証の根拠**: src/main.ts:371-373 routes move through runCmd, and runCmd (main.ts:237-238) unconditionally does `setSelection([snap.focus], snap.focus)`. core/cmds.mbt:569-571 sets st.focus = first_focus = the FIRST moved id, while move_block (cmds.mbt:499-511) restores every block id by position, so applySnap's pruning (main.ts:186-191) would have kept all of them. Contrast verified: indentSelection/outdentSelection (main.ts:355-364) use applySnap + syncSelectionViews(false) and never touch `selection`, and cmd_indent's "#" insertion survives map_offset (doc.mbt:128-135), so ids and selection are preserved there. Ctrl+Z path confirmed: doUndo (main.ts:492-493) is applySnap only, no selection restore, so the collapsed selection persists. Repro traced: normalize_selection (doc.mbt:502-527) drops `### 実体` as covered, cmd_move moves markdown then mindmap, first_focus = markdown.

**影響**: move だけ runCmd 経由なので main.ts:237-238 の `setSelection([snap.focus], snap.focus)` が走り、cmd_move が返す first_focus 1 個に上書きされる。move_block は id を復元しているので選択は保てるのに捨てている。undo が選択を戻さない件（領域の確認事項）も、実質この潰れが原因で「戻すべき選択」が失われている。

**修正方針**: host.move を runCmd ではなく indentSelection と同じ形（applySnap(core.moveNodes(...), "map") + syncSelectionViews(false)）にして、既存の selection をそのまま維持する。ensureVisible だけ snap.focus に対して呼べばよい。

### P5-ツリー操作-3 / CONFIRMED / `D:/1.atrium/mmm/core/cmds.mbt:472`

**move / reorder が `---` グループ区切りを壊し、左右 2 面レイアウトが片側に崩れる**

```
let del_from = if nd.sub_end == len { tidy_del_start(nd.hs) } else { nd.hs }
```

**症状**: グループをまたぐ移動・並べ替えをすると `---` が本文末尾に孤児として取り残され（または移動ブロックに巻き込まれて末尾へ運ばれ）、グループ分割そのものが消える。マップの左側の枝が丸ごと右側へ移動する。

**再現条件**: 1. 起動直後のサンプル文書（右: `## markdown` `## mindmap` / 左: `## mirror`）。
2. マップで `## mirror` をクリックして選択し、Ctrl+↑（reorder -1）。
3. 期待: `## mindmap` と `## mirror` が入れ替わり、左右の配置は保たれる。
4. 実際: md ペインの末尾が `---` だけになり、`## markdown` `## mirror` `## mindmap` の 3 つが全部右側に並ぶ。左側の枝が消える。
5. 同じ結果になる別経路: `## mindmap` を選んで Ctrl+↓。この場合は `## mindmap` の sub_end が `## mirror` の hs なので `---` がブロック本体に含まれ（cmds.mbt:460 の `sub(st.text, pos, nd.sub_end)`）、`---` ごと末尾へ運ばれる。
6. D&D でも同じ（`## mirror` を `## markdown` の「前」ゾーンにドロップ）。
原因: 末尾ブロックの削除開始位置は tidy_del_start が空白行までしか戻らず（is_space は 32/9 のみで改行を含まない、parser.mbt:46-48）、`---` 行は必ず残る。残った `---` の後ろに見出しが無くなると doc.mbt:270-275 のフィルタで seps から落ち、全兄弟が group 0 に正規化される。

**確度**: 確定

**検証の根拠**: Traced the exact repro on SAMPLE (main.ts:39-56). `## mirror`.sub_end == text length, so cmds.mbt:472 takes tidy_del_start(nd.hs); tidy_del_start (cmds.mbt:105-129) walks back over \n/\r/space to just after `---`'s newline and returns hs-1 — is_space is only 32/9 (parser.mbt:46-48), so the `---` line itself can never be included. Deletion therefore leaves text ending "...\n\n---\n". On reparse, rebuild_nodes' sep filter (doc.mbt:266-276) drops any raw_sep with no heading after it (hp reaches heads.length()), compute_groups(seps=[]) gives every root child group 0 (doc.mbt:339-388), and render's placeSide (mindmap.ts:512-540) puts all of them on the right. Alternate path 5 also verified: mindmap.sub_end == mirror.hs, so `---\n\n` is inside the moved range at cmds.mbt:460 and is carried to EOF. Both routes end with `---` orphaned at EOF and markdown/mirror/mindmap all on the right.

**影響**: ユーザーが触っていないノード（`## mirror`）の表示側が変わる、という見た目の破壊。かつ `---` が本文末尾にゴミとして残る。Ctrl+Z で戻せるが、気付かずに保存すると .md からグループ構造が消える。

**修正方針**: move_block / cmd_reorder でブロック境界を計算するときに、直前の `---` 区切り（st.hide_regions と同様に seps を持ち回る）をブロックの一部として扱うか、移動後に「移動先の group が変わる場合は `---` を再発行／削除する」正規化を入れる。最低限、見出しが後続しない `---` は削除する後処理を move_block に足す。

### P5-ツリー操作-4 / CONFIRMED / `D:/1.atrium/mmm/core/cmds.mbt:460`

**hidden ノードをドラッグすると閉じ `-->` ごと運ばれ、無関係な後続ノードが hidden 化する**

```
sb.write_string(sub(st.text, pos, nd.sub_end))
```

**症状**: コメントアウト（hidden）されたノードをマップでドラッグして別の場所へ落とすと、`-->` 行が一緒に移動し、`<!--` が元の位置に残る。その結果、間に挟まれた無関係なノードがすべて hidden（コメントアウト）になる。

**再現条件**: 1. md ペインに以下を書く。
```
# r

<!--
## H

### H1
-->

## B
```
マップ上で `## H` `### H1` はコンパクトな hidden 表示、`## B` は通常表示になる。
2. マップで `## H` を掴み、`## B` の外側ギャップ（子として）にドロップする。
3. 実際の md:
```
# r

<!--
## B

### H

#### H1
-->
```
触っていない `## B` が `<!--` の内側に入り hidden 表示に変わる。
原因: `## H` の sub_end は「深さ 2 以下の次の見出し」= `## B` の hs なので、ブロック範囲 [H.hs, B.hs) に `-->\n\n` が含まれる（doc.mbt:311-317）。move_block はその生テキストをそのまま切り出して運ぶ。

**確度**: 確定

**検証の根拠**: Byte-traced the repro. In `# r / <!-- / ## H / ### H1 / --> / ## B`, doc.mbt:311-317 gives H.sub_end = B.hs, so [H.hs, B.hs) = "## H\n\n### H1\n-->\n\n" — the `-->` line is inside the block cmds.mbt:460 copies. move_block(H, at=EOF, depth 3): delta=1 applies only to heads = [H,H1] (cmds.mbt:443), del_from = H.hs (sub_end != len), at2 = EOF, eof_effective true, prefix "\n" added. Result is exactly "# r\n\n<!--\n## B\n\n### H\n\n#### H1\n-->\n" as claimed. Reparse (parser.mbt:88-98) then flags `## B` hidden. Drop is reachable: startDrag's subtree (mindmap.ts:1600-1606) uses hs<subEnd so B is excluded from the subtree and stays a legal target, and updateDrop reaches it both on the box (root fails the du test) and via the outward zone (mindmap.ts:1655-1665).

**影響**: ユーザーが指定していないノードが外部レンダラから見えなくなる（実質的な意図しないデータ隠蔽）。マップ上ではコンパクト表示になるので気付きやすいが、`## B` の子孫が多いと全部まとめて隠れる。Ctrl+Z で戻せる。

**修正方針**: move_block でブロック範囲を切り出す前に、範囲内に閉じ `-->`（かつ対応する `<!--` が範囲外）があれば hide 区間の境界でクランプするか、移動時にマーカーを再バランスする（移動元に `-->` を、移動先に `<!--`/`-->` を張り直す）。UI 側でも hidden ノードのドラッグを禁止するのが安全。

### P5-ツリー操作-5 / CONFIRMED / `D:/1.atrium/mmm/core/cmds.mbt:547`

**hidden ノードの「前」にドロップすると、落としたサブツリーが黙って hidden 化する（「後ろ」は hidden にならず非対称）**

```
(tn.hs, tn.depth)
```

**症状**: hidden ノード H の上側バンド（pos=1）にドロップすると、挿入位置が `<!--` の内側になるので、落としたノードがコメントアウトされる。下側バンド（pos=2、at = tn.sub_end で `-->` の外）だと hidden にならない。ドロップ指示線には何の違いも出ない。

**再現条件**: 1. finding 4 と同じ文書を用意する。
2. マップで `## B` を掴み、`## H` の上側（前）ゾーンにドロップする。
3. 実際: md が
```
# r

<!--

## B

## H

### H1
-->
```
となり、`## B` がコンパクトな hidden 表示に変わる。
4. 同じ `## B` を `## H` の下側（後ろ）ゾーンに落とすと hidden にならない。上下でまったく違う結果になるのに、drop-line の見た目は同じ。

**確度**: 確定

**検証の根拠**: cmds.mbt:544-550: pos=1 gives (at, depth) = (tn.hs, tn.depth) and tn.hs of a hidden node is a line inside the `<!--`/`-->` span (parser.mbt:88-98 flags in_comment for lines after the marker). Byte-traced the repro: nd=B, sub_end==len so del_from = tidy_del_start(B.hs) = B.hs-1, at2 = H.hs (< del_from so no collapse), preceded_by_blank(H.hs) is false because H.hs-2 is '-' of `<!--`, giving the leading "\n" — output is exactly the claimed "# r\n\n<!--\n\n## B\n\n## H\n\n### H1\n-->\n", and B reparses hidden. updateDrop (mindmap.ts:1634-1665) indeed has no hidden check, and HIDDEN_H=22 (mindmap.ts:79) so the pos=1 band above H is comfortably reachable.

**検証による訂正**: The "後ろ" half needs two fixes. (a) In this exact document, dropping B after H is not "moves but stays visible" — it is a complete silent no-op: at = H.sub_end = B.hs and depth 2 == B.depth, so the same-place guard at cmds.mbt:551-560 skips the move entirely. (b) pos=2 is only outside the comment when the target is the LAST node of the hide region. For a hidden node with a hidden next sibling, tn.sub_end is that sibling's hs, still inside `<!--`/`-->`, so pos=2 hides the dropped block too. The real invariant is "any drop whose insertion offset falls between the markers hides the block", not "before hides / after doesn't".

**影響**: 「隣に置いただけ」のつもりでノードがコメントアウトされる。updateDrop（mindmap.ts:1634-1665）は hidden ノードを一切区別しないので、予防も警告もない。

**修正方針**: updateDrop で `b.n.hidden` のターゲットに対しては pos を hidden 領域と整合するように制限する（前ドロップを禁止するか、drop-line に hidden 化を示すスタイルを付ける）。あるいは cmd_move 側で pos=1 の at が hide 区間の内側に入る場合は区間の外へずらす。

### P5-ツリー操作-6 / CONFIRMED / `D:/1.atrium/mmm/src/mindmap.ts:1641`

**ルートをルート前ツリーへドラッグでき、文書から `#` 見出し（ルート）が消える**

```
if (b.n.depth === 1) {
```

**症状**: ルート前ノード（`#` より上に書かれた `##` 見出し）が存在する文書では、ルート `#` 自身をそのツリーにドロップできてしまい、ルートが深さ 3 に降格して文書からルートが消える。

**再現条件**: 1. md ペインで以下を書く。
```
## pre

# root

## a
```
マップには `# root` のツリーと、その下に別ツリーとして `## pre` が出る。
2. `# root` のボックスを掴んで `## pre` の外側ギャップ（子として）にドロップする。
3. 実際: md が
```
## pre

### root

#### a
```
になる。深さ 1 の見出しが 1 つも無くなる。
原因: startDrag の subtree は `m.hs >= nd.hs && m.hs < nd.subEnd` で作るので、ルートより前にある `## pre` は subtree に入らずドロップ先として残る。1641 の depth===1 ガードは「ルートに落とす側」しか塞いでいない（F-006 の UI ブロック）。

**確度**: 確定

**検証の根拠**: No guard blocks dragging the root: the only depth===1 checks in mindmap.ts are :306 (find root for layout), :588 (css class), :963 (left + button) and :1641 (drop-side guard, F-006). startDrag (mindmap.ts:1600-1606) builds the subtree from hs>=nd.hs, so a pre-root `## pre` (hs < root.hs) is not excluded and stays a drop target. Byte-traced the repro on "## pre\n\n# root\n\n## a\n": cmd_move's reject test (cmds.mbt:541-543) passes (pre.hs 0 is not >= root.hs), the same-place guard (cmds.mbt:551) fails on depth (3 != 1), move_block runs with delta=2, at2 collapses to del_from=7 via cmds.mbt:474, eof_effective true, and the output is exactly "## pre\n\n### root\n\n#### a\n". After reparse no depth-1 heading exists, so mindmap.ts:306 `tops.find(n => n.depth === 1)` is null and the whole placeSide/group left-right split at :494-541 is skipped. Recovery claim also holds: cmd_add_root (cmds.mbt:216-227) is only wired to keydown paths guarded by nodes.length === 0 (mindmap.ts:1441, 1451), and cmd_outdent refuses depth < 3 (cmds.mbt:387).

**影響**: 以後 render() の `root = tops.find(n => n.depth === 1)` が null になり、左右 2 面レイアウト（placeSide / group による左右分け）が完全に効かなくなる。`---` も無意味になる。cmd_add_sibling の「ルートは兄弟を作らず子にする」分岐も効かなくなる。UI からルートを復元する手段はなく、md を直接編集するしかない。Ctrl+Z では戻せる。

**修正方針**: updateDrop で `this.dragging.ids` にルート（depth===1）が含まれる場合はドロップ先を一切採らない。あわせて cmd_move 側でも depth==1 のノードの移動要求を無視する（cmds.mbt:532 のループ先頭で `if nd.depth == 1 { continue }`）。

### P5-ツリー操作-7 / CONFIRMED / `D:/1.atrium/mmm/src/mindmap.ts:1507`

**ドラッグを中止する手段が無い（Esc は選択を消すだけでドロップは実行される）**

```
this.host.clearSelection();
```

**症状**: ドラッグ中に Esc を押しても、選択が空になるだけでドラッグ状態は残り、ボタンを離すと移動が実行される。

**再現条件**: 1. マップでノード A を掴み、ノード B の上までドラッグしてドロップ線を出す。
2. Esc を押す（ペインにフォーカスがあるので onKeydown 1506-1509 に届く）。
3. 実際: 選択ハイライトは消えるが drop-line は出たまま。ボタンを離すと host.move が走って A が移動する。移動後は runCmd が選択を A に戻す。
4. pointercancel（1194-1202）は pen/touch のキャンセルでしか来ないので、マウスでは到達できない。

**確度**: 確定

**検証の根拠**: onKeydown (src/mindmap.ts:1325-1327) only bails on IME/editing, and Escape falls through every earlier branch to :1506-1509 `this.host.clearSelection(); return;` — it never touches this.dragging, this.dropTarget or this.dropLine (compare stopDragVisuals at :1709-1716, which is only called from pointerup/pointercancel/dblclick). clearSelection -> setSelection([], -1, false) -> syncSelectionViews -> map.refreshSelection (:1807-1812) only toggles the "selected" class, so the "dragging" class and the drop-line stay visible. On release, pointerup :1155-1161 uses this.dragging.ids captured at startDrag, so the originally grabbed nodes still move, and runCmd then re-selects them (main.ts:237-238). pointercancel (:1194-1202) confirmed to be the only abort path, and it is not reachable with a mouse.

**影響**: 「間違ったところに落としそう」と気付いてもキャンセルできない。Ctrl+Z で戻すしかない。

**修正方針**: onKeydown の先頭（1327 付近）で `if (this.dragging) { this.stopDragVisuals(); this.dragCand = null; if (key === "Escape") { e.preventDefault(); return; } }` のようにドラッグ中の Esc をキャンセルに割り当てる。

### P5-ツリー操作-8 / CONFIRMED / `D:/1.atrium/mmm/core/doc.mbt:314`

**F-005 の新しい帰結: 不採用の 2 つめ `#` ブロックが、深さ調整なしで移動ブロックに同乗する**

```
nodes[open.unsafe_pop()].sub_end = nodes[i].hs
```

**症状**: 既知の F-005（2 つめの `#` はノード一覧から落ちるが前ノードのサブツリー範囲には残る）は、削除・コピー・hide だけでなく「移動」でも起きる。しかも move_block の深さシフトは st.nodes に載っている見出しにしか掛からない（cmds.mbt:443 の subtree_nodes）ので、同乗した `#` 行だけ深さが変わらないまま別の場所へ運ばれる。

**再現条件**: 1. md ペインに以下を書く。
```
# A

## B

# C

## D
```
マップには A（ルート）・B・D の 3 ノードだけが出る（`# C` は重複ルートとして落ちる）。B の sub_end は D の hs なので `# C` ブロックが B の範囲に入っている。
2. マップで `## B` を掴み、`## D` の外側ギャップ（子として）にドロップ。
3. 実際の md:
```
# A

## D

### B

# C
```
`## B` は `### B` に降格するが、一緒に運ばれた `# C` は `#` のまま末尾へ移動している。ユーザーは `# C` を選んでいないし、マップ上に `# C` は表示すらされていない。

**確度**: 確定

**検証の根拠**: New consequence of F-005 and correctly reasoned. rebuild_nodes drops the second `#` (doc.mbt:251-262) before sub_end is computed at doc.mbt:311-317, so for `# A / ## B / # C / ## D` we get B.sub_end = D.hs with the `# C` block inside. subtree_nodes(nd.hs, nd.sub_end) (cmds.mbt:337-345, called at :443) only walks st.nodes, so heads = [B] and the delta=+1 '#' insertion never touches the `# C` line, while cmds.mbt:460 copies the whole raw range including it. Byte-traced move_block(B, at=EOF, depth 3): del_from = B.hs (sub_end != len), at2 = EOF, eof_effective true, leading "\n" added — output is exactly "# A\n\n## D\n\n### B\n\n# C\n" as claimed, with `# C` still depth 1 and still invisible on the map after reparse.

**影響**: マップに見えていないテキストブロックが移動で勝手に位置を変える。B が別ツリー（ルート前）へ移動する構成だと、運ばれた `# C` が文書中で最初の深さ 1 見出しになりルートが入れ替わる可能性がある（要検証だが同じ機構）。

**修正方針**: F-005 本体（2 つめ `#` の扱い）の修正が本筋。暫定的には move_block でブロック範囲内に「採用されなかった見出し行」がある場合を検出して、移動対象から切り離す（範囲を前倒しでクランプする）。

### P5-ツリー操作-9 / CONFIRMED / `D:/1.atrium/mmm/src/mindmap.ts:592`

**ドラッグ中に render() が走ると drop-child リングが消え、drop-line が古い座標のまま残る**

```
(this.dragging?.subtree.has(n.id) ? " dragging" : "") +
```

**症状**: render() は nodeLayer を作り直すが、復元するのは `dragging` クラスだけ。`drop-child`（ドロップ先のリング）は復元されず、dropLine は viewport 直下なので消えずに古い座標のまま残る。ドロップ指示が一時的に矛盾する。

**再現条件**: 要確認: ドラッグ中に render() を起こすタイミングを人手で作る必要がある。
1. 画像行（`![](./x.webp)`）を持つノードがある .md を開き、まだフォルダ許可が下りていない状態にする（サムネイルがプレースホルダ表示）。
2. ノードをドラッグし始める（この pointerdown で main.ts:687 unlockAssets が走り、許可が通ると loadAsset → map.render()（main.ts:678）が非同期に走る）。
3. 観測すべきもの: その瞬間にドロップ先のリング（.drop-child）だけが消え、drop-line は動かないまま残るか。次の pointermove で updateDrop が呼ばれれば自己修復する。
コード上は 1669/1678-1682 の drop-child 付与が render() の replaceChildren(558-559) を跨がないことが確定なので、症状の発生自体は確実。

**確度**: 確定

**検証の根拠**: Code settles it, so this is stronger than 要確認. render() does `this.nodeLayer.replaceChildren()` (mindmap.ts:559) and the rebuilt <g> class string at :585-592 restores only "selected" and "dragging" — "drop-child" is added nowhere else (grep: only :1680 adds it, :1669/:1714/:799 remove it). this.dropLine is appended to this.viewport, not nodeLayer (mindmap.ts:216, 229-232), so it survives with stale coordinates. render() never touches this.dragging/this.dropTarget, so the drop result is unaffected — impact statement is right.

**検証による訂正**: The repro should not rely on the permission prompt: dirHandle.requestPermission (main.ts:696) needs a user gesture and opens a modal that may itself interrupt the drag. A cleaner reachable path with no prompt: imageUrl (main.ts:636-641) is called during render, caches null and fires `void loadAsset(path)`; loadAsset ends in an unconditional `map.render()` (main.ts:678) once the File System handle resolves. Open a .md with an image row in an already-granted folder and start dragging immediately after load — the async loadAsset completion re-renders mid-drag. Same for the IndexedDB dir-handle retry loop at main.ts:1122-1131.

**影響**: 見た目だけの一時的な不整合で、次のマウス移動で直る。ドロップ結果は this.dropTarget（id 保持）を使うので正しい。

**修正方針**: render() の末尾で `if (this.dragging && this.dropTarget) this.applyDropVisual(this.dropTarget)` のように drop-child の再付与を行うか、updatePlus と同様に render 内で drop 表示を作り直す。

### P5-ツリー操作-10 / CONFIRMED / `D:/1.atrium/mmm/core/cmds.mbt:582`

**reorder の端（先頭/末尾）は無言の no-op（矢印キーの兄弟移動はループするのに並べ替えはループしない）**

```
let p = prev_sibling(i)
```

**症状**: 先頭の兄弟で Ctrl+↑、末尾の兄弟で Ctrl+↓ を押しても何も起きず、フィードバックも無い。同じ ↑↓ の単独押しはループする（mindmap.ts:1554-1560「上下はループする」）ので、挙動が食い違う。

**再現条件**: 1. サンプル文書で `## markdown`（右側グループの先頭）を選択し、Ctrl+↑ を押す。
2. 実際: 何も起きない。undo スタックにもエントリは積まれない（prev_sibling が -1 で move_block を呼ばないため）。
3. 同じノードで ↑ 単独を押すと `## mindmap` へループして選択が動く。
4. 末尾側: `## mirror` を選んで Ctrl+↓ でも何も起きない。

**確度**: 確定

**検証の根拠**: cmds.mbt:576-592: dir<0 with prev_sibling(i) == -1 (or dir>0 with next_sibling == -1) falls through without calling move_block, so no apply_sets, no undo entry. api.mbt:198-201 still returns snapshot(), and snapshot() resets st.focus to -1 at api.mbt:94, so main.ts's runCmd (:237) sees focus === -1 and does nothing at all — truly silent. Contrast is real: mindmap.ts:1554-1560 wraps with `% sibs.length`. Ctrl+Up reaches reorder only for sel.size === 1 (mindmap.ts:1525-1529), which the repro satisfies.

**検証による訂正**: Step 3 is wrong. `sibs` at mindmap.ts:1555 is `nodes.filter(n => n.parent === cur.parent)` — all root children in document order regardless of group — so from `## markdown` (index 0) ArrowUp wraps to index (0-1+3)%3 = 2, i.e. `## mirror`, not `## mindmap`. The asymmetry the finding is about is unaffected; if anything it is sharper, since plain ↑ jumps across the `---` boundary to the other side of the map while Ctrl+↑ does nothing.

**影響**: 軽微だが、ループする移動と対になっていないため「効かないキー」に見える。ユーザーは押し続けて別の操作を試すことになる。

**修正方針**: 意図的な仕様ならそのままでよい。合わせるなら cmd_reorder で prev/next が無いときに先頭↔末尾へラップする（ただし finding 3 の `---` 問題を先に直さないと、ラップで区切りが壊れる）。

### P5-ツリー操作-11 / CONFIRMED / `D:/1.atrium/mmm/src/mindmap.ts:1466`

**単一選択の Tab は「1 段下げ」ではなく子作成になり、コンテキストメニューと非対称**

```
if (key === "Tab" && !e.shiftKey) {
```

**症状**: 1467 行が `sel.size > 1` のときだけ indentSelection を呼ぶので、1 ノードだけ選んで Tab を押すと indent ではなく子ノードが作られる。一方コンテキストメニューの「1 段下げ」（1758）は単一選択でも indentSelection を呼ぶので indent される。同じ操作名で結果が違う。

**再現条件**: 1. サンプル文書で `## mindmap` を 1 つだけ選択する。
2. Tab を押す → 新しい子ノードが作られてラベル編集に入る（indent されない）。
3. 同じ状態で右クリック → 「1 段下げ」 → `## mindmap` が `## markdown` の子（`### mindmap`）になる。
4. Shift+Tab も同様に、単一選択では addParent、複数選択では outdentSelection と結果が変わる（1472-1474）。

**確度**: 確定

**検証の根拠**: Code is exactly as described: mindmap.ts:1466-1471 calls indentSelection only when sel.size > 1, else addChild; :1472-1477 mirrors it with outdentSelection/addParent. The menu entries at :1758-1759 have no `disabled: multi` (unlike :1731/:1737/:1743/:1749/:1755), so "1 段下げ"/"1 段上げ" do run indentSelection/outdentSelection on a single selection. So single-node indent is menu-only.

**検証による訂正**: Downgrade this to a documented design gap, not an inconsistency bug. README.md:77-78 and :85 specify exactly this split (`Tab` = 子要素, `Shift+Tab` = 親要素を作成, 複数選択で `Tab`/`Shift+Tab` = 1 段下げ / 1 段上げ). Also "同じ操作名で結果が違う" is inaccurate: showMenu attaches the "Tab" key hint to 「子を追加」 (mindmap.ts:1729) and gives 「1 段下げ」 no key hint at all (:1758), so the UI never claims Tab means indent. The accurate residual claim is only: there is no keyboard binding for single-node indent/outdent.

**影響**: キーボードだけでは 1 ノードの indent/outdent ができない。仕様（mmm.md）でそう決まっているなら該当なしだが、メニュー側と食い違っているのは事実。

**修正方針**: 仕様として意図的なら、コンテキストメニューの「1 段下げ／1 段上げ」に単一選択時のショートカット表記を出さないなど UI 側で揃える。indent を単一選択にも割り当てるなら別キー（例: Mod+])を用意する。

### P5-ツリー操作-12 / CONFIRMED / `D:/1.atrium/mmm/src/mindmap.ts:1669`

**pointermove ごとに nodeLayer を 2 回フル走査して classList を触っている**

```
for (const g of this.nodeLayer.children) g.classList.remove("drop-child");
```

**症状**: updateDrop はマウスが 1px 動くたびに、全ノードの <g> に対して classList.remove を呼び（1669）、pos=0 のときはさらにもう一周（1678-1682）走査する。加えて 1634 と 1655 の 2 つの走査が this.order 全体を舐める。startDrag(1600-1606) も `for (const nid of ids) for (const m of nodes)` で O(|ids| x n)。

**再現条件**: 要確認: 効き方はノード数次第。
1. 2000 ノード規模の .md を開く（F-002 の計測に使ったものでよい）。
2. Ctrl+A で全選択してからノードを掴む → startDrag が 2000x2000 = 400 万回のループを 1 回だけ回る。
3. そのままドラッグして DevTools の Performance で pointermove ハンドラの自己時間を見る。1 イベントあたり classList 操作が 2000〜4000 回。
観測して確定させるべきもの: pointermove 1 回あたりの updateDrop の実測時間が 1 フレーム（16ms）に対してどれくらいか。

**確度**: 確定

**検証の根拠**: The loops are exactly where claimed. mindmap.ts:1669 runs `for (const g of this.nodeLayer.children) g.classList.remove("drop-child")` unconditionally on every updateDrop call, and updateDrop is called from every pointermove while dragging (:1132-1134). The pos===0 path adds a second full pass at :1678-1682. startDrag's subtree build at :1600-1606 is genuinely O(|ids| x n) — with Ctrl+A (:1483-1490) selecting all, ids is the full order and a 2000-node doc gives 4M iterations in one call.

**検証による訂正**: Two overstatements. (a) The 2nd nodeLayer pass is conditional on target.pos === 0, so "pointermove ごとに 2 回" is really "1 回、pos=0 のときだけ 2 回". (b) The claim that :1634 and :1655 each sweep all of this.order is wrong on both counts: :1634 breaks at the first match (:1644/:1649) and :1655 runs only when :1634 found nothing, so at most one of them is a full sweep. The measurable risk is concentrated in startDrag's O(|ids| x n), which is a one-shot cost at grab time; the per-move classList passes are ~n cheap no-op removals. Reframe as "startDrag is quadratic in selection x nodes" and keep the DevTools measurement only for that.

**影響**: F-002（render が 66ms/2001 ノード）とは別経路の負荷。ドラッグ中は render が走らなくてもポインタ追従がもたつく可能性がある。

**修正方針**: 直前に drop-child を付けた要素の参照を 1 個だけ保持して、それだけ remove する。ターゲット探索も、前回のターゲットが依然ヒットするなら再走査を省く。startDrag の subtree 計算は nodes を 1 回走査して hs でソート済みの区間検索にする。

### 反証により除外(2 件)

- **pointerup が e.button を見ないため、ドラッグ中の右ボタン解放でドロップが確定する** — The code fact is right — src/mindmap.ts:1137-1162 never inspects e.button — but the claimed trigger cannot fire. Pointer Events (chorded button interactions) specifies that for a mouse, pointerdown fires only on the transition from no buttons pressed to one, and pointerup only on the transition back to none; pressing or releasing an additional button while another is held fires pointermove, not pointerdown/pointerup. So in step 4 the right-button release while the left button is still down produces a pointermove, `pane.addEventListener("pointerup")` at :1137 never runs, and host.move is not called. The residual real behaviour is different and much narrower: the contextmenu handler (:1261-1270) does not stop the drag, so the menu opens over a live drag, updateDrop keeps tracking, and the drop lands when the LAST button is released — meaning if the user releases left first and right second, the drop point is whatever the pointer reached after the left release. That is a separate, contrived issue, not the one described. Settled by a browser check if wanted: log pointerdown/pointerup with e.button/e.buttons while chording.
- **panning 分岐の早期 return で dragCand が残り、押し直していないのにドラッグが始まる** — Same chorded-button rule defeats step 2. this.panning is set ONLY inside the pointerdown handler (src/mindmap.ts:1048-1059), and per Pointer Events a middle-button press while the left button is already held fires pointermove, not pointerdown — so `this.panning` is never set and steps 3-5 cannot occur. What actually happens in that sequence is an ordinary left-button drag of node A (pointermove at :1125-1131 crosses the 8px threshold and calls startDrag). The underlying code smell is real: the panning branch (:1138-1142) and the rubber branch (:1143-1153) both return without clearing this.dragCand, unlike the dragging (:1160) and dragCand (:1166) branches. But it is unreachable with a mouse; it needs two simultaneous pointers (e.g. touch1 pressed on a node setting dragCand, touch2 pressed on empty space setting rubberStart, then touch1's pointerup taking the rubber branch and leaving dragCand alive) — a different finding with a different repro.

---

## 5. markdown 構文の境界（core/parser.mbt の行走査・フェンス・区切り・HTML コメント / core/doc.mbt のグループ計算 / core/cmds.mbt の非表示・コピー / src/relevel.ts / src/mindmap.ts のコンテンツカード mini パーサ）

**調べたもの**

- core/parser.mbt 全 238 行（scan_lines / scan_doc / is_marker_line / is_separator / fence_open / fence_close_len）
- core/doc.mbt 全 528 行（rebuild_nodes / compute_groups / is_blank_range / map_offset）
- core/cmds.mbt 全 686 行（insert_heading_edit / cmd_delete / move_block / selection_text / cmd_toggle_hidden）
- core/api.mbt 全 231 行
- src/relevel.ts 全 55 行（scanDepths / hasHeadings / relevel）
- src/mindmap.ts 90-380（parseLink / parseImage / render() 内のコンテンツ行走査）および 559-729（カード描画）
- src/editor.ts 全 188 行、src/main.ts の loadText / onUserEdits / applySnap / paste / addCode / insertContentLine / saveImageToDisk / imageUrl
- core を Node から実行して確認: インデント 0/3/4 スペース・タブ、# 直後の空白なし/タブ/全角スペース(U+3000)/NBSP(U+00A0)、バッククォートとチルダのフェンス混在・長さ違い・info string(バッククォート入り/複数語)、閉じフェンスの info、3/4/6 スペースインデントのフェンス、フェンス内の ---・見出し・<!--、setext 見出し(=== と ---)、本文中の水平線、*** と - - -、YAML フロントマター、生 HTML ブロック、エスケープ \##、閉じ ATX ハッシュ、深さ 7、CRLF / 単独 CR / BOM
- core を Node から実行して確認: 非表示の付け外しと delete / reorder / outdent / indent / selectionText / コンテンツ行挿入の相互作用
- src/relevel.ts の scanDepths を JS に移植し、18 パターンでコアの見出し判定と一致することを確認（不一致 0 件）
- src/mindmap.ts のカード mini パーサを JS に逐語移植し、22 パターンで誤検出・取りこぼしを確認
- node_modules/@codemirror/state を直接実行し、CRLF が LF に正規化されることを実測（21 文字 → 16 文字）

### P5-markdown-1 / CONFIRMED / `src/main.ts:478`

**CRLF ファイルは CodeMirror が \r を落とすのにコアは保持するため、md ペインの 1 打鍵ごとにオフセットがずれて本文が壊れる**

```
const snap = core.initDoc(text);
  editor.setText(text);
```

**症状**: CodeMirror は EditorState.lineSeparator 未設定なので DefaultSplit = /\r\n?|\n/ で分割し \r を捨てる（node_modules/@codemirror/state/dist/index.js:608, 972）。同じ文字列をコアには生のまま渡すので、行数ぶんオフセットが食い違う。md ペインの編集は src/main.ts:296 `core.replaceText(e.from + delta, ...)` で CM のオフセットをそのままコアに渡すため、挿入位置が行数ぶん手前になる。editor.applySets / editor.highlight も逆方向に同じだけずれる。

**再現条件**: 1. CRLF 改行の .md（例 "# R\r\n\r\n## a\r\n\r\n## b\r\n"）を開く。2. md ペインで "## b" 行末にカーソルを置き "!" を打つ。実測: CM オフセット 15 がコアの 19 とずれ、コア本文は "# R\r\n\r\n## a\r\n\r\n!## b\r\n" になりノード b がマップから消える（node で core.replaceText(15,15,"!") を実行して確認）。CodeMirror 側は 21→16 文字に正規化されることを @codemirror/state を直接実行して実測済み。

**確度**: 確定

**検証の根拠**: src/editor.ts:96-104 never sets EditorState.lineSeparator (I measured st.facet(EditorState.lineSeparator) === undefined), so both EditorState.create and the setText dispatch at src/editor.ts:150-153 run Text.of with DefaultSplit and drop \r: "# R\r\n\r\n## a\r\n\r\n## b\r\n" is 21 chars raw but 16 in the CM doc. src/main.ts:478-479 hands the SAME raw string to core.initDoc and to editor.setText, so core keeps 21. src/main.ts:296 forwards CM offsets verbatim (core.replaceText(e.from + delta, ...)). Executing core.replaceText(15,15,"!") on the CRLF doc gives "# R\r\n\r\n## a\r\n\r\n!## b\r\n" and the node list collapses from [R,a,b] to [R,a] — node b is gone. src/main.ts:216 (editor.highlight with n.hs/n.subEnd) and src/editor.ts:157-165 (applySets) use core offsets against the shorter CM doc, so they are off by the same amount in the other direction.

**影響**: CRLF の既存ファイル（Windows で作られた md はほぼこれ）を開くと、md ペインで文字を打った瞬間に見当違いの位置が書き換わり、見出しが壊れてノードが消える。保存すると壊れた内容がディスクに書かれる。マップ選択のハイライト位置も常時ずれる。

**修正方針**: loadText で `text.replace(/\r\n/g,"\n")` に正規化してから core.initDoc / editor.setText に渡す（保存時に元の改行へ戻すなら savedText 比較も揃える）。あるいは EditorState.lineSeparator を "\r\n" にして CM 側に \r を保持させる。

### P5-markdown-2 / CONFIRMED / `core/parser.mbt:103`

**見出し行は先頭スペース 0 個しか許さないのに md ペインの Tab がインデントを入れる（ノードが消え子が祖父に付け替わる）**

```
// strict ^(#+)\s+(.*)$ with no leading spaces allowed
    let mut p = l.start
```

**症状**: fence_open(parser.mbt:182) と is_separator(parser.mbt:155) は先頭スペース 3 個まで許すのに、見出しだけ 0 個。src/editor.ts:104 の `keymap.of([indentWithTab, ...defaultKeymap])` により md ペインで Tab を押すと indentUnit（既定 2 スペース）が行頭に入り、見出しが見出しでなくなる。

**再現条件**: 1. "# R\n\n## a\n\n### kid\n\n## b\n" を開く。2. md ペインで "## a" 行にカーソルを置き Tab。3. 本文は "  ## a" になり、マップからノード a が消え、"### kid" が深さ 3 のまま親が R（深さ 1）に付け替わる。実測で id=2 が消滅し kid の parent が 1 になることを確認。undo で戻せるが、Tab を押した本人はインデントしたつもりしかない。

**確度**: 確定

**検証の根拠**: core/parser.mbt:104-109 starts the '#' run at l.start with no indent skip, unlike fence_open (core/parser.mbt:182) and is_separator (core/parser.mbt:155) which both allow 3. src/editor.ts:104 registers indentWithTab; node_modules/@codemirror/commands/dist/index.js:1807 maps Tab→indentMore, which at :1604-1606 inserts state.facet(indentUnit) at line.from, and node_modules/@codemirror/language/dist/index.js:806-809 defaults indentUnit to "  ". lang-markdown binds no Tab (its markdownKeymap has no "Tab" entry), and src/mindmap.ts:994 only claims Space, so nothing intercepts it. Executed: replaceText(a.hs, a.hs, "  ") on "# R\n\n## a\n\n### kid\n\n## b\n" yields [1:d1 R, 3:d3 kid parent=1, 4:d2 b] — id 2 destroyed, kid reparented to R. undo() restores it exactly.

**影響**: 意図しない 1 打鍵でノードとその id が消え、子孫の親子関係が飛ぶ。CommonMark では 3 スペースまでの見出しは見出しなので、他エディタで整形した md を開いた時点でも構造が丸ごと欠ける。

**修正方針**: 見出し走査もフェンス・区切りと同じく先頭スペース 3 個まで許容する（p を進める while を追加）。合わせて relevel.ts:27 の /^(#+)[ \t]/ も /^ {0,3}(#+)[ \t]/ に揃える。

### P5-markdown-3 / CONFIRMED / `core/parser.mbt:109`

**空ノードの実体は末尾スペース付きの "## " で、その 1 文字を消すとノードと部分木構造が壊れる**

```
if depth >= 1 && p < l.end && is_space(cc(text, p)) {
```

**症状**: CommonMark は "##" 単独も空見出しと認めるが、この条件は # の直後に空白が「ある」ことを要求する。一方 cmds.mbt:92-94 は新規ノードを `hashes(depth) + " "` と書くので、空ノードの唯一の目印が行末スペース 1 文字になる。

**再現条件**: 1. "# R\n\n## \n\n### kid\n\n## b\n"（3 行目は "## " で末尾スペースあり）を開く。2. md ペインで "## " 行末にカーソルを置き Backspace 1 回。3. 実測: ノード（id=2、ラベル空）が消え、"### kid" が深さ 3 のまま R の直下に付け替わる。外部の formatter / エディタの trailing-whitespace 削除、git の whitespace フック、prettier でも同じことが起きる。

**確度**: 確定

**検証の根拠**: core/cmds.mbt:92-93 writes hashes(depth) then " " for every new heading, and core/cmds.mbt:237 (cmd_rename) rebuilds the line as hashes + " " + label, so an unnamed node is literally "## " with a trailing space. core/parser.mbt:109 requires `p < l.end && is_space(cc(text, p))`, so "##" alone is not a heading. Executed: replaceText(he-1, he, "") on "# R\n\n## \n\n### kid\n\n## b\n" gives "# R\n\n##\n\n### kid\n\n## b\n" and the node list goes from [1 R, 2 "", 3 kid(parent 2), 4 b] to [1 R, 3 kid(parent 1), 4 b] — id 2 gone, kid reparented to R.

**影響**: 「まだ名前を付けていないノード」がファイル整形やうっかり Backspace で消滅し、その子が祖父にぶら下がる。id も失われるので undo 以外では復元できない。

**修正方針**: parser.mbt:109 の条件を `depth >= 1 && (p >= l.end || is_space(cc(text, p)))` にして "##" 単独も見出しとして受ける（CommonMark と同じ）。

### P5-markdown-4 / CONFIRMED / `src/main.ts:441`

**コードポップアップの言語欄にバッククォートを入れるとフェンスが成立せず、コード本文が文書構造になり以降の見出しが全部消える**

```
insertContentLine(id, `${fence}${r.lang}\n${r.code}\n${fence}`);
```

**症状**: src/popup.ts:101 は `lang.value.trim()` を素通しする。core/parser.mbt:201-208 はバッククォートフェンスの info string にバッククォートが 1 個でもあればフェンスと認めないので、開きフェンスが無効化される。すると本文の # 行が見出しとして解釈され、閉じフェンスのほうが新しいフェンスを開いて EOF まで飲み込む。

**再現条件**: 1. ノードで「コードを追加」を開き、言語欄に ``js` ``（末尾にバッククォート。md ドキュメントからコピペすると起きる）、コード欄に "# swallowed?" を入れて確定。2. 本文は "```js`\n# swallowed?\n```" になる。3. 実測: "# R\n\n## a\n\n```js`\n# swallowed?\n```\n\n## b\n" をパースするとノードは R と a だけになり、後続の "## b" がマップから消える。

**確度**: 確定

**検証の根拠**: src/popup.ts:101 returns lang.value.trim() with no validation; src/main.ts:440-441 splices it straight after the fence run. core/parser.mbt:201-208 rejects a backtick fence whose info string contains a backtick. Executed: initDoc("# R\n\n## a\n\n```js`\n# swallowed?\n```\n\n## b\n") returns only [R, a] — "## b" is swallowed, exactly as claimed.

**検証による訂正**: 再現手順の理由付けだけ弱い。「md からコピペ」で最も起きるのは lang 欄に "```js" が入るケースで、その場合フェンス行は "``````js"（開き 6 個・info にバッククォート無し）になり core/parser.mbt:201-208 は通る。壊れる理由は別で、src/main.ts:440 が閉じフェンスを "```"（3 個）のまま書くため core/parser.mbt:215-229 の fence_close_len >= fence_len を満たさず EOF まで閉じない。実測でも lang="```js" は [R, a] だけになった（lang="js" と lang='js title="app.js"' は正常）。つまり lang にバッククォートが入る全パターンが壊れ、原因は「info string 拒否」と「閉じフェンスが短い」の 2 系統ある。

**影響**: コードを 1 つ貼っただけで、そのノード以降の全ノードがマップから消える。md 本文は残っているので気づきにくく、その状態で構造コマンドを打つとさらに壊れる。

**修正方針**: popup.ts で lang からバッククォートと空白を除去する（`lang.value.trim().replace(/[`\s]+/g,"")`）。もしくは main.ts:440 のフェンス選択で lang にバッククォートがあればチルダフェンスに切り替える。

### P5-markdown-5 / CONFIRMED / `src/main.ts:440`

**addCode のフェンス長ヒューリスティックが 4 個以上のバッククォートを含むコードで破綻する**

```
const fence = r.code.includes("```") ? "````" : "```";
```

**症状**: 判定は「``` を含むか」だけなので、本文が ```` 以上を含んでいても生成フェンスは ```` 止まり。core/parser.mbt:215-237 の fence_close_len は「開き以上の長さ + 後ろは空白のみ」で閉じるので、本文中の ```` 行が開きフェンスを閉じてしまい、残りの本文と最後の ```` が新しいフェンスを開いて EOF まで飲み込む。

**再現条件**: 1. 「コードを追加」でコード欄に markdown のフェンス入り断片（例: "````js\nx\n````"）を貼って確定。2. 生成される本文は ```` 開始 → 本文 2 行目の ````js は閉じない（後ろに js があるため）→ 本文 4 行目の ```` で閉じる → 生成側の閉じ ```` が新規フェンスを開く、となり以降の見出しが飲まれる。3. コード欄が "````\nx\n````" のように info string 無しならもっと確実に再現する。

**確度**: 確定

**検証の根拠**: src/main.ts:440 tests only `r.code.includes("```")`, so any code containing 4+ backticks still gets a 4-backtick wrapper. Executed the exact generation for code="````js\nx\n````": the produced document "# R\n\n## a\n\n````\n````js\nx\n````\n````\n\n## b\n" parses to [R, a] only — the body's "````" closes the wrapper (core/parser.mbt:215-236) and the generated closing "````" opens a new fence that runs to EOF, so "## b" disappears.

**影響**: markdown のコード例を貼るという普通の操作で、以降のノードがマップから消える。

**修正方針**: 本文に現れる最長のバッククォート連鎖を数え、その +1 の長さでフェンスを作る（`"`".repeat(Math.max(3, maxRun + 1))`）。

### P5-markdown-6 / CONFIRMED / `src/mindmap.ts:334`

**コンテンツカードの mini パーサが複数語 info string のフェンスを認識せず、コードブロックの中身をリンク/SVG カードとして描画する**

```
const fence = /^(`{3,}|~{3,})\s*(\S*)\s*$/.exec(t);
```

**症状**: `\s*(\S*)\s*$` は info string を空白なしの 1 トークンに限定するので、```js title="app.js" や ```python {1,3} をフェンスと見なさない。コアはこれらを正しくフェンスとして扱う（parser.mbt:179-211）ので、カード側だけがコード本文を通常のコンテンツ行として走査する。結果、コード内の URL 行がリンクカード（↗ で実際に開けるボタン付き）になり、コード内の <svg> が data URL で本物の画像として描画され、さらに閉じフェンス行が新しいコードカードを開いてブロック外のテキストをコード扱いする。

**再現条件**: 1. ノードの本文を md ペインで次にする: "```js title=\"app.js\"\nhttps://example.com\nconst a=1;\n```\nafter"。2. マップのカードには（a）example.com のリンク行（↗ 押下で外部を開く）と（b）"after" を中身とする空 lang のコードカードが出る。実測で cards() が [{kind:'link',...},{kind:'code',lang:'',lines:['after','']}] を返すことを確認。3. "```html title=\"x\"\n<svg width=\"10\"></svg>\n```" では kind:'svg' になり実際に SVG が描かれる。

**確度**: 確定

**検証の根拠**: src/mindmap.ts:334 `/^(`{3,}|~{3,})\s*(\S*)\s*$/` cannot match ```js title="app.js"` while core/parser.mbt:179-211 accepts it. Ran the mini parser verbatim: '```js title="app.js"\nhttps://example.com\nconst a=1;\n```\nafter' → [{kind:"link",...example.com},{kind:"code",lang:"",lines:["after",""]}]; '```html title="x"\n<svg width="10"></svg>\n```' → kind:"svg" (rendered as a real data-URL image at src/mindmap.ts:648-660); '```python {1,3}\nhttps://…\n```' → link card. The link row really is actionable: src/mindmap.ts:638-645 emits the ↗ glyph with data-url and src/mindmap.ts:1249-1253 calls window.open(url, "_blank", "noopener") on click.

**影響**: コードとして書いたつもりの URL がクリックできるリンクとして提示され（ユーザーが意図しない外部遷移の入口になる）、コードの実体はカードに出ず無関係な行がコードとして表示される。mermaid/shiki 系の info string 付きフェンスは実際によく使われる。

**修正方針**: カード側の正規表現をコアと同じ規則に揃える: `/^(`{3,}|~{3,})(.*)$/` にして、バッククォートフェンスのみ info string にバッククォートを含む場合を除外し、lang は info の先頭トークンを使う。

### P5-markdown-7 / CONFIRMED / `src/mindmap.ts:340`

**カード mini パーサのフェンス閉じ判定・インデント判定がコアと食い違う**

```
if (c.startsWith(fence[1][0].repeat(3)) && /^[`~]+$/.test(c)) {
```

**症状**: （a）開きフェンスの長さを見ないので ````` で開いたブロックを ``` 行が閉じる。コアは fence_close_len >= fence_len を要求するので閉じない。（b）`/^[`~]+$/` なのでバッククォートとチルダ混在の "```~~~" も閉じ扱い。コアは閉じない。（c）走査が src/mindmap.ts:332 の `const t = lines[li].trim();` を使うため、インデント何個でもフェンス扱い。コアは 3 スペースまで。

**再現条件**: 1. ノード本文を "`````\n```\nstill in code\n`````" にする。実測でカードは空のコードカード 2 個になり "still in code" が消える。コア側は 1 個のコードブロックとして扱う。2. 本文を "      ```\ncode\n      ```"（6 スペースインデント）にすると、カードは code カードを作るがコアはフェンスと見なさない。

**確度**: 確定

**検証の根拠**: src/mindmap.ts:340 `c.startsWith(fence[1][0].repeat(3)) && /^[`~]+$/.test(c)` ignores the opening run length and the fence character consistency, and src/mindmap.ts:332 trims the line before src/mindmap.ts:334 tests it. Ran verbatim: '`````\n```\nstill in code\n`````' → two empty code cards, "still in code" lost (core keeps one block, fence_close_len >= fence_len at core/parser.mbt:227-229); '```\ncode\n```~~~\nafter' → the card parser closes at "```~~~" while core/parser.mbt:230-235 returns 0 for it; '      ```\ncode\n      ```' (6 spaces) → the card parser makes a code card while core/parser.mbt:218-221 caps the indent at 3 so it is not a fence.

**影響**: マップのカード表示と md 本文・コアの解釈が食い違い、コードブロックの中身が欠けたり空カードが並ぶ。

**修正方針**: 閉じ判定を `run.length >= fenceLen && /^[`~]*$/.test(残り) && 残りが空白のみ` に、インデントは trim ではなく /^ {0,3}/ に揃える。

### P5-markdown-8 / CONFIRMED / `core/cmds.mbt:678`

**非表示ノードを削除すると <!-- が取り残され、無関係な次の兄弟が非表示になる**

```
Edit::{ from: nd.hs, to: nd.hs, insert: "<!--" + eol, removed: "" },
```

**症状**: <!-- は nd.hs（＝直前ノードのテキスト範囲の末尾）に、--> は nd.sub_end（＝非表示ノード自身の範囲の内側）に置かれる。どの構造コマンドもこのマーカー対を追跡しないので、範囲の切れ目をまたぐ操作でペアが分断される。cmd_delete は [hs, sub_end) しか消さないので閉じマーカーだけ消えて開きマーカーが孤立する。

**再現条件**: 1. "# R\n\n## a\n\n## b\n\n## c\n" を開く。2. マップで b を非表示にする（本文 "# R\n\n## a\n\n<!--\n## b\n\n-->\n## c\n"）。3. b を選んで削除。4. 実測: 本文が "# R\n\n## a\n\n<!--\n## c\n" になり、触っていない c が hidden=true になる（以降 EOF まで全部が非表示扱い）。

**確度**: 確定

**検証の根拠**: core/cmds.mbt:678 inserts "<!--"+eol at nd.hs, so after the reparse it belongs to the PREVIOUS node's [hs, sub_end); core/cmds.mbt:679 puts "-->" at nd.sub_end, inside the hidden node's own range. Executed on "# R\n\n## a\n\n## b\n\n## c\n": toggleHidden(b) → "# R\n\n## a\n\n<!--\n## b\n\n-->\n## c\n", then deleteNodes([b]) (core/cmds.mbt:279-301 deletes only [hs, sub_end)) → "# R\n\n## a\n\n<!--\n## c\n" with c.hidden === true. Matches the finding byte for byte.

**影響**: 非表示ブランチを消しただけで、後続の兄弟とその配下が丸ごと「無効化」状態になる。外部レンダラでも本当にコメントアウトされるので、公開文書から章が消える。

**修正方針**: cmd_delete（および move_block）で削除範囲を決めるとき st.hide_regions を参照し、範囲がマーカー対の片側だけを含む場合は対のもう一方も同じ編集セットに入れる。

### P5-markdown-9 / CONFIRMED / `core/cmds.mbt:250`

**非表示ノードの直前の兄弟を削除すると非表示が勝手に解除され、孤立した --> が本文に残る**

```
fn cmd_delete(ids : Array[Int]) -> Unit {
```

**症状**: 前項の裏返し。<!-- は直前ノードの範囲 [hs, sub_end) の内側にあるので、直前ノードを削除すると開きマーカーだけが消え、--> がゴミとして残る。

**再現条件**: 1. "# R\n\n## a\n\n## b\n\n## c\n" で b を非表示にする。2. a を削除する。3. 実測: 本文が "# R\n\n## b\n\n-->\n## c\n" になり、b の hidden が false に戻り（＝勝手に再表示され）、本文には対応する開きの無い "-->" 行が残る。この --> は b のコンテンツ範囲に入るので hasContent も true になる。

**確度**: 確定

**検証の根拠**: Same range mismatch, opposite direction: the "<!--" line inserted at core/cmds.mbt:678 sits inside the previous sibling's range, so cmd_delete (core/cmds.mbt:250) removes it. Executed: hide b, then deleteNodes([a]) → "# R\n\n## b\n\n-->\n## c\n" with b.hidden back to false and an orphan "-->" line. Node b's snapshot also reports hasContent for the "-->" line since it falls in b's content range (core/doc.mbt:289-295).

**影響**: 隠したはずのブランチが黙って復活し、md には意味不明な --> 行が残る。

**修正方針**: 同上。cmd_delete が範囲を広げるときに hide_regions の対を一緒に扱う。

### P5-markdown-10 / CONFIRMED / `core/cmds.mbt:437`

**非表示ノードの周りで reorder / outdent すると、触っていないノードが非表示領域に取り込まれる**

```
fn move_block(i : Int, at : Int, new_depth : Int) -> Unit {
```

**症状**: move_block の挿入位置 at は「ノードの hs」や「親の sub_end」で決まるが、非表示中はその位置が <!-- と --> の内側にあり得る。マーカーは単なるテキストなので、移動したブロックがコメント領域の中に入る／領域が別ノードを覆う。

**再現条件**: A. "# R\n\n## a\n\n## b\n\n## c\n" で b を非表示 → c を Ctrl+↑ 相当（reorderNode(c,-1)）で 1 つ上へ。実測: 本文 "# R\n\n## a\n\n<!--\n\n## c\n\n## b\n\n-->\n" となり、移動しただけの c が hidden=true になる。B. "# R\n\n## a\n\n### b\n\n### c\n" で b を非表示 → b を outdent。実測: 本文 "# R\n\n## a\n\n<!--\n### c\n\n## b\n\n-->\n" となり、触っていない c が hidden=true になる。C. 同じ初期状態で b を非表示 → c を indent すると "...<!--\n## b\n\n-->\n### c\n" となり、c はマップ上 b（非表示）の子なのに --> の外側＝外部レンダラでは表示される、という不整合になる。

**確度**: 確定

**検証の根拠**: core/cmds.mbt:437 move_block computes `at` from hs / sub_end (core/cmds.mbt:544-550, 584-589) and never inspects st.hide_regions, so the block lands inside the comment span. Executed all three: (A) hide b then reorderNode(c,-1) → "# R\n\n## a\n\n<!--\n\n## c\n\n## b\n\n-->\n" with c.hidden true; (B) "# R\n\n## a\n\n### b\n\n### c\n", hide b then outdent b → "# R\n\n## a\n\n<!--\n### c\n\n## b\n\n-->\n" with c.hidden true.

**検証による訂正**: C の引用テキストが実測と違う。同じ初期状態（"# R\n\n## a\n\n### b\n\n### c\n"）で b を非表示 → c を indent した実測結果は "# R\n\n## a\n\n<!--\n### b\n\n-->\n#### c\n"。b は "### b" のまま、c は "#### c"（depth 4）になる（cmd_indent は core/cmds.mbt:359-364 で '#' を足すだけで行は動かないため）。指摘の本質（c は hidden=false・親は hidden な b・かつ --> の外側という不整合）はそのまま成立する。

**影響**: 並べ替え・段下げという日常操作で、無関係なノードが非表示になったり、マップの「非表示ブランチ」と md のコメント範囲が食い違う。

**修正方針**: move_block の at を決める前に hide_regions を参照して境界外へ丸める、または非表示ノード自体をマーカー込みの 1 ブロックとして扱う（sub_end を --> の後ろまで含めて hs を <!-- から始める）。

### P5-markdown-11 / CONFIRMED / `core/cmds.mbt:603`

**非表示ノード（およびその直前の兄弟）をコピーすると、対にならないマーカーだけを含む断片がクリップボードに出る**

```
let mut block = sub(st.text, nd.hs, nd.sub_end)
```

**症状**: selection_text は [hs, sub_end) をそのまま切り出す。非表示ノードの範囲には --> だけが、その直前の兄弟の範囲には <!-- だけが入る。

**再現条件**: 1. "# R\n\n## a\n\n## b\n\n## c\n" で b を非表示。2. b をコピー → 実測 selectionText は "## b\n\n-->\n"（開き無しの -->）。3. a をコピー → 実測 "## a\n\n<!--\n"（閉じ無しの <!--）。4. その 2 を別ノードに貼り付ける（main.ts:402 の hasHeadings は true なので貼り付けは通る）。実測: "# R\n\n## x\n\n<!--\n### frag\n\n## y\n" となり、貼り付け位置以降の "## y" が hidden=true になる。

**確度**: 確定

**検証の根拠**: core/cmds.mbt:603 slices [nd.hs, nd.sub_end) raw. Executed after hiding b in "# R\n\n## a\n\n## b\n\n## c\n": selectionText([b]) === "## b\n\n-->\n", selectionText([a]) === "## a\n\n<!--\n". Pasting the a-fragment: hasHeadings passes (src/main.ts:402, src/relevel.ts:27 matches "## a"), relevel to depth 3, insert at x.subEnd per src/main.ts:414-421 → "# R\n\n## x\n\n### a\n\n<!--\n\n## y\n" with y.hidden === true. Reachable from the UI: src/mindmap.ts:1491-1504 wires Mod+C/Mod+X/Mod+V to these host calls.

**影響**: コピー＆ペーストで文書の残り全体がコメントアウトされる。切り取り（cut = copy + delete）ならコピー側とdelete側の両方の破壊が同時に起きる。

**修正方針**: selection_text は切り出した断片内でマーカーの釣り合いを取る（片側だけなら除去するか、対を補う）。

### P5-markdown-12 / CONFIRMED / `src/main.ts:726`

**非表示にした直後、その直前の兄弟にリンク/コード/画像を足すとコメント領域の内側に書き込まれる**

```
const at =
    i + 1 < nodes.length && nodes[i + 1].hs < n.subEnd
      ? nodes[i + 1].hs
      : n.subEnd;
```

**症状**: n.subEnd は <!-- 行の直後を指す（<!-- が直前ノードの範囲の末尾にあるため）。そこに挿入すると新しいコンテンツ行はコメント領域の中に入る。

**再現条件**: 1. "# R\n\n## a\n\n## b\n\n## c\n" で b を非表示。2. a を選んで「リンクを追加」で https://example.com を入れる。3. 実測: 本文が "# R\n\n## a\n\n<!--\n\nhttps://example.com\n\n## b\n\n-->\n## c\n" になる。マップでは a のリンクカードとして見えるが、md では HTML コメントの中なので GitHub 等では表示されない。

**確度**: 確定

**検証の根拠**: src/main.ts:726-729 picks n.subEnd when the next node's hs is not strictly inside, and after hiding b, a.subEnd === b.hs === just after the "<!--" line. Executed the exact insertContentLine arithmetic (at=16) plus core.replaceText: "# R\n\n## a\n\n<!--\n\nhttps://example.com\n\n## b\n\n-->\n## c\n" — byte-identical to the finding. The link still renders as a card of a because src/mindmap.ts:322-330 scans a's content range, which now contains the URL line.

**影響**: マップと出力 md が食い違う。b を再表示するとリンクだけが残るので気づきにくい。

**修正方針**: insertContentLine の at を hide_regions の開きマーカー手前に丸める（コア側に「そのノードのコンテンツ末尾」を返す API を用意するのが確実）。

### P5-markdown-13 / CONFIRMED / `core/doc.mbt:273`

**<!-- 行が --- と見出しの間に入るため、非表示にするとグループ分割（左右振り分け）が消える**

```
if hp < heads.length() && is_blank_range(s_next, heads[hp].hs) {
```

**症状**: --- がグループ区切りになる条件は「次の見出しまでが空白だけ」。cmd_toggle_hidden が挿入する <!-- 行がその間に入るので条件が崩れ、区切りが無効化される。

**再現条件**: 1. "# R\n\n## a\n\n---\n\n## b\n\n## c\n" を開く（実測: a が group 0、b/c が group 1 で b/c は左側に配置される）。2. b を非表示にする。3. 実測: 全ノードが group 0 になり、b/c がマップの右側へ飛ぶ。4. b を再表示すると group が戻る。

**確度**: 確定

**検証の根拠**: core/doc.mbt:270-275 only keeps a separator when is_blank_range(s_next, heads[hp].hs), and core/cmds.mbt:678 drops a "<!--" line into exactly that gap. Executed on "# R\n\n## a\n\n---\n\n## b\n\n## c\n": before, a=group 0 and b/c=group 1; after toggleHidden(b) the text is "# R\n\n## a\n\n---\n\n<!--\n## b\n\n-->\n## c\n" and every node reports group 0. Re-showing restores group 1. The left/right consequence follows from the layout rule documented at src/mindmap.ts:5-8.

**影響**: 1 ノードを非表示にしただけでマップのレイアウトが左右まるごと組み替わる。

**修正方針**: is_blank_range の判定でマーカー行（<!-- / -->）を空白扱いにするか、非表示挿入を --- の手前に置く。

### P5-markdown-14 / CONFIRMED / `core/parser.mbt:152`

**setext 見出しは構造として一切見えず、しかも下線の --- がグループ区切りとして解釈される**

```
/// A group separator: up to 3 leading spaces, then 3+ dashes, then only
/// whitespace.
fn is_separator(text : String, l : Line) -> Bool {
```

**症状**: scan_doc は ^(#+)\s+ しか見ないので "Title\n=====" / "Title\n---" は本文扱い。さらに後者の --- は is_separator に一致し、直後が見出しならグループ区切りとして働く。

**再現条件**: 1. "# R\n\n## a\nTitle\n---\n## b\n" を開く。2. 実測: "Title" はノードにならず a の本文、しかも b の group が 1 になり左側に飛ぶ。3. "Title\n=====\n\n## sub\n" を開くと "Title" 部分はどのノードにも属さない前置きテキストになり、マップから到達できない（削除・コピー・非表示のどれでも触れない）。

**確度**: 確定

**検証の根拠**: core/parser.mbt:99-109 checks is_separator before the '#' rule and never looks at underlines. Executed: "# R\n\n## a\nTitle\n---\n## b\n" → [R, a(group 0), b(group 1)] — "Title" is only a's content and the underline promoted b to another group. "Title\n=====\n\n## sub\n" → the only node is sub at hs=13, so the first 13 chars belong to no node and cannot be reached by delete/copy/hide, which all work off [hs, sub_end).

**影響**: setext 記法で書かれた既存 md を開くと章立てが丸ごと消え、下線が意図しないグループ分割になる。前置きテキストはマップ経由で編集できない。

**修正方針**: 最低限、直前行が非空行の --- は区切りにしない（setext 下線として除外する）。setext 見出しを構造として拾うなら scan_doc に 2 行先読みを足す。

### P5-markdown-15 / CONFIRMED / `core/parser.mbt:104`

**HTML ブロックの中の # 行を見出しとして扱うため、そのノードを削除すると HTML ブロックが壊れる**

```
let mut p = l.start
    while p < l.end && cc(text, p) == 35 {
```

**症状**: scan_doc はフェンスと <!-- --> しか除外しない。CommonMark の HTML ブロック（<div> …）内の # 行は生テキストなのに、mmm は見出しにする。sub_end は次の見出しまでなので、閉じタグがそのノードの範囲に入ってしまう。

**再現条件**: 1. "# R\n\n<div>\n\n## x\n\n</div>\n" を開く。2. マップに現れる x を削除。3. 実測: 本文が "# R\n\n<div>\n" になり、</div> が消えて閉じられていない <div> だけが残る。

**確度**: 確定

**検証の根拠**: core/parser.mbt:73-109 excludes only fences and <!-- --> marker lines, so a '#' line inside a raw HTML block is structure. Executed: "# R\n\n<div>\n\n## x\n\n</div>\n" → x at hs=12 with subEnd=25 (EOF), i.e. </div> is inside x's subtree; deleteNodes([x]) leaves "# R\n\n<div>\n" — the closing tag is gone.

**影響**: 生 HTML を含む md でノードを 1 つ消すと閉じタグが道連れになり、以降のレンダリングが崩れる。

**修正方針**: 最低限、<div>/<table> などのブロック開始タグから空行までを構造走査から除外する（フェンスと同じスキップ）。難しければ HTML ブロック内の見出しを hidden 相当にして構造コマンドの対象外にする。

### P5-markdown-16 / CONFIRMED / `core/parser.mbt:47`

**# の直後に全角スペースや NBSP を書くと黙って見出しでなくなる**

```
c == 32 || c == 9
```

**症状**: is_space は ASCII の空白とタブだけ。日本語 IME の全角スペース(U+3000)や Web/Word からのコピペで混入する NBSP(U+00A0) は空白と見なされず、行全体が本文に落ちる。

**再現条件**: 1. md ペインで "##" と打った直後に IME が ON のまま全角スペースを打ち "##　見出し" と書く。2. 実測: "# R\n\n##　x\n" をパースするとノードは R のみ（x はノードにならない）。"## x" も同じ。3. 見た目はマップにノードが出ないだけで、エラーも表示も出ない。

**確度**: 確定

**検証の根拠**: core/parser.mbt:46-48 is_space accepts only 32 and 9, and core/parser.mbt:109 gates the whole heading on it. Executed: initDoc("# R\n\n##　x\n") → nodes [R] only; initDoc("# R\n\n## x\n") → nodes [R] only. No diagnostic exists anywhere on this path.

**影響**: 日本語入力で最も踏みやすい罠。ノードを作ったつもりが何も起きず、原因が本文の見た目からは分からない。

**修正方針**: is_space に U+3000 と U+00A0 を足す（ラベル前後のトリムも同じ関数なので一貫する）。あるいは md ペイン側で警告表示。

### P5-markdown-17 / CONFIRMED / `core/parser.mbt:113`

**CommonMark の閉じ ATX ハッシュがラベルに残る**

```
let mut label_end = l.end
      // also trim a trailing \r (a file ending in "\r" with no final \n)
      while label_end > p &&
            (is_space(cc(text, label_end - 1)) || cc(text, label_end - 1) == 13) {
```

**症状**: 末尾の空白と \r しか落とさないので、CommonMark が見出しから取り除く末尾の # 列がそのままラベルになる。

**再現条件**: 1. "# R\n\n## a ##\n" を開く。2. 実測: ラベルが "a ##"（GitHub 等では "a"）。3. そのノードをリネームすると cmds.mbt:237 で "## " + ラベル に正規化されるので "## a ##" になり、他ツールとの表示差が残り続ける。

**確度**: 確定

**検証の根拠**: core/parser.mbt:113-118 trims only is_space and CR from label_end. Executed: initDoc("# R\n\n## a ##\n") → label "a ##". renameNode(id, "a ##") is a no-op because core/cmds.mbt:237-241 rebuilds exactly "## a ##" and compares equal, so the text stays "# R\n\n## a ##\n" — the round-trip claim holds.

**影響**: 他ツールで書かれた md を開くとラベルにゴミの # が付く。実害は表示のみ。

**修正方針**: label_end のトリムで、空白に囲まれた末尾の # 連鎖も落とす。

### P5-markdown-18 / CONFIRMED / `src/mindmap.ts:121`

**カード mini パーサのリンク/画像の取りこぼし（括弧入り URL・タイトル付き画像・空白入りパス・パーセントエンコード・リスト項目）**

```
const md = /^\[([^\]]*)\]\((https?:\/\/[^\s)]+)\)$/.exec(t);
```

**症状**: （a）URL に ) を含む Wikipedia 形式 [Foo](https://…/Foo_(bar)) は不一致。（b）parseImage(mindmap.ts:145)は <> を許すのに parseLink は許さない。（c）画像のタイトル ![a](p "t") は不一致。（d）パスに空白があると `([^)\s>]+)` で落ちるが、src/main.ts:800 の画像名バリデーション `segs.some((s) => s === ".." || /[\\:*?"<>|]/.test(s))` は空白と括弧を許すので、mmm 自身が "![](./my shot.webp)" を書き出せる。（e）パーセントエンコード済みパス a%20b.png は loadAsset がそのままのファイル名を探すので読めない。（f）"- https://…" のようなリスト項目は先頭の "- " で不一致。（g）カードは 4 行で打ち切り（mindmap.ts:331 `list.length < 4`）で 5 個目以降は無言で消える。

**再現条件**: 1. 画像を貼り付け、名前プロンプトに "my shot" と入力して保存。2. 本文に "![](./my shot.webp)" が書かれるが、実測で parseImage は null を返すのでカードに画像も placeholder も出ない（imageUrl も呼ばれない）。3. 本文に "[Foo](https://en.wikipedia.org/wiki/Foo_(bar))" を書いてもリンクカードにならない（実測 [] ）。

**確度**: 確定

**検証の根拠**: Ran src/mindmap.ts:121 parseLink and src/mindmap.ts:145 parseImage verbatim: "[Foo](https://en.wikipedia.org/wiki/Foo_(bar))" → null (a); parseImage("![](<./x.png>)") → "./x.png" but parseLink("[a](<https://x.com>)") → null (b); '![a](p "t")' → null (c); "![](./my shot.webp)" → null while src/main.ts:797-804 accepts the name "my shot" (only .. and [\\:*?"<>|] are rejected), so src/main.ts:843 writes a line its own parser cannot read and src/mindmap.ts:689 imageUrl is never reached — no image AND no placeholder (d); src/main.ts:663-675 loadAsset splits the path on "/" and calls getFileHandle with the raw segment, no decodeURIComponent, so "a%20b.png" is looked up literally (e); parseLink("- https://example.com") → null (f); src/mindmap.ts:331 caps the loop at `list.length < 4`, and 5 URL lines produced exactly 4 cards with the 5th silently dropped (g).

**影響**: 自分で保存した画像がマップに出ない（保存自体は成功しているので原因が分かりにくい）。よくある形式のリンク・画像がカードにならない。

**修正方針**: saveImageToDisk の許可文字から空白と括弧も外す（または名前をサニタイズ）。parseLink は釣り合った括弧と <> を許す。画像パスは decodeURIComponent してから解決する。

### P5-markdown-19 / CONFIRMED / `src/main.ts:402`

**貼り付けは、見出しがインデントされているか setext 記法の断片だと完全な無反応になる**

```
if (!hasHeadings(normalized)) return; // fence-aware, matches relevel
```

**症状**: relevel.ts:27 の /^(#+)[ \t]/ は先頭スペースを一切許さず、setext も見ない。該当なしだと return するだけでトースト等の通知もない。

**再現条件**: 1. 他所から "   ## Title\n   text"（3 スペースインデント、CommonMark では見出し）をコピー。2. マップでノードを選んで Ctrl+V。3. 何も起きない（本文も変わらず、メッセージも出ない）。setext 記法の "Title\n=====\n本文" も同じ。

**確度**: 確定

**検証の根拠**: src/relevel.ts:27 `/^(#+)[ \t]/` has no leading-space allowance and src/relevel.ts:36-38 hasHeadings is built on it. Ran it: hasHeadings("   ## Title\n   text") === false, hasHeadings("Title\n=====\n本文") === false. src/main.ts:402 then does a bare `return` with no flashFilename/toast — the only user feedback function is flashFilename (src/main.ts:601) and it is not called on this path. Reachable via Mod+V (src/mindmap.ts:1501-1504) and the context menu (src/mindmap.ts:1766).

**影響**: 貼り付けが黙って失敗し、ユーザーはクリップボードが空だと誤解する。

**修正方針**: relevel の見出し正規表現を /^ {0,3}(#+)[ \t]/ に揃え（コア側も同様に緩める）、hasHeadings が false のときは flashFilename 等で理由を出す。

### P5-markdown-20 / CONFIRMED / `src/relevel.ts:54`

**貼り付けた断片は常に LF で結合されるので、CRLF 文書に混在改行が生じる**

```
.join("\n");
```

**症状**: src/main.ts:401 が `clip.replace(/\r\n/g, "\n")` で正規化し、relevel も \n で結合する。一方コアの nl()（cmds.mbt:39-46）は文書の最初の改行を見るので CRLF 文書では "\r\n" を返し、以後の構造コマンドは CRLF を書く。

**再現条件**: 1. CRLF の md を開く（※ 本レポート 1 件目の CRLF 不整合を先に直した前提）。2. 見出しを含む断片を貼り付ける。3. 貼り付け部分だけ LF、周囲は CRLF になる。パース自体は scan_lines が両方扱うので壊れないが、保存後の git diff が行末混在で汚れる。

**確度**: 確定

**検証の根拠**: src/main.ts:401 normalizes \r\n→\n, src/relevel.ts:54 joins with "\n", and src/main.ts:418-420 builds prefix/suffix from "\n", while core/cmds.mbt:39-46 nl() returns "\r\n" for a CRLF document. Executed against the core on "# R\r\n\r\n## a\r\n": the paste yields "# R\r\n\r\n## a\r\n\n### frag\n", and a subsequent addChild writes CRLF → "# R\r\n\r\n## a\r\n\n### frag\n\n\r\n#### \r\n". Parsing survives (core/parser.mbt:19-23 handles both), so the impact really is diff noise only.

**影響**: ファイルの改行が混在する。パース上の実害はない。

**修正方針**: relevel の join を呼び出し側の nl() に合わせるか、貼り付け直前に本文の改行コードへ再変換する。

### P5-markdown-21 / CONFIRMED / `core/parser.mbt:75`

**非表示領域の中でフェンスが開くと --> が飲まれ、再表示しても閉じマーカーが本文に残る**

```
if in_fence {
      if fence_close_len(text, l, fence_char) >= fence_len {
        in_fence = false
      }
      continue
    }
```

**症状**: 走査順が「フェンス優先 → コメントマーカー」なので、コメント領域の内側でフェンスが開くとその中の --> はマーカーとして認識されない。scan_doc は閉じ無し領域を (open, -1, -1) として返し、cmd_toggle_hidden(cmds.mbt:645-653) は c_start == -1 のとき開きマーカーしか消さない。

**再現条件**: 1. md ペインで "# R\n\n## a\n\n```\ncode\n\n## b\n"（``` が閉じていない＝コードブロックを書きかけの状態）を作る。2. マップで a を非表示にする → 本文は "# R\n\n<!--\n## a\n\n```\ncode\n\n## b\n-->\n"。3. もう一度 a を押して再表示する。4. 実測: 本文が "# R\n\n## a\n\n```\ncode\n\n## b\n-->\n" となり、対応する開きの無い "-->" 行が残る。

**確度**: 確定

**検証の根拠**: core/parser.mbt:75-80 handles in_fence before the marker checks at core/parser.mbt:88-98, so a "-->" inside an open fence is invisible; core/parser.mbt:129-131 then records (open, -1, -1) and core/cmds.mbt:645-653 skips the close edit when c_start == -1. Executed on "# R\n\n## a\n\n```\ncode\n\n## b\n": toggleHidden(a) → "# R\n\n<!--\n## a\n\n```\ncode\n\n## b\n-->\n"; toggleHidden(a) again → "# R\n\n## a\n\n```\ncode\n\n## b\n-->\n" — the orphan "-->" stays. Distinct from F-007.

**影響**: 非表示 → 再表示の往復でゴミが増える。既知の F-007（往復で末尾改行が増える）とは別の残留物。

**修正方針**: cmd_toggle_hidden の再表示側で、閉じマーカーが見つからない場合はテキストを走査して対応する --> 行を探して消す。または非表示挿入時にマーカーをフェンスより優先させる（走査順をコメント判定→フェンス判定に変える）。

### P5-markdown-22 / CONFIRMED / `core/cmds.mbt:663`

**一度どこかのマーカーが範囲に入ると、そのノードは無言で非表示にできなくなる**

```
if (o_start >= nd.hs && o_start < nd.sub_end) ||
      (c_start >= nd.hs && c_start < nd.sub_end) {
      return
    }
```

**症状**: 入れ子非表示を禁じるガードだが、<!-- は「直前の兄弟の範囲」に入るので、兄弟を隠した瞬間に自分が隠せなくなる。return するだけで UI には何も出ない。

**再現条件**: 1. "# R\n\n## a\n\n## b\n\n## c\n" を開く。2. b を非表示にする（<!-- は a の範囲 [5,16) に入る）。3. a を非表示にしようとする。4. 何も起きない（本文もマップも不変、通知なし）。

**確度**: 確定

**検証の根拠**: core/cmds.mbt:661-667 returns whenever a region's o_start or c_start falls in [nd.hs, nd.sub_end), and core/cmds.mbt:678 guarantees the "<!--" lands in the previous sibling's range. Executed on "# R\n\n## a\n\n## b\n\n## c\n": after toggleHidden(b), toggleHidden(a) leaves the text byte-identical (changed? false). The caller src/main.ts:368-370 runCmd only acts when snap.focus !== -1, and snapshot() resets focus to -1 (core/api.mbt:94), so there is no UI feedback at all.

**影響**: 隣を隠すと自分が隠せなくなるという説明のつかない挙動になり、しかも無反応なので操作ミスと区別できない。

**修正方針**: マーカーの帰属をノード範囲から切り離す（非表示ノードの hs を <!-- 行に、sub_end を --> の後ろに合わせる）。当面はガードに掛かったとき UI へ理由を通知する。

### P5-markdown-23 / CONFIRMED / `core/parser.mbt:1`

**見出しの深さが 6 を超えても構造として受けるため、書き出した md は他ツールでただの文字列になる**

```
// Line-level scanner. Structure detection is a single rule: ^(#+)\s+(.*)$
// (spec 2.1). Depth is unbounded (spec 2.2), so the standard Markdown parser
// cannot be used for headings; we only need line offsets and fence tracking.
```

**症状**: 仕様どおりの意図的な逸脱だが、Tab を 6 回押すだけで到達する。実測で "####### deep" は depth 7 のノードになる。CommonMark は 7 個以上を見出しと認めないので、GitHub 等では "####### deep" という生テキストとして表示される。

**再現条件**: 1. ルート直下にノードを作り、Tab を繰り返して深さ 7 まで下げる。2. 保存した md を GitHub にアップすると、その行が見出しにならず "####### …" のまま表示される。

**確度**: 確定

**検証の根拠**: core/parser.mbt:1-3 documents unbounded depth as intentional (spec 2.2) and core/parser.mbt:105 has no cap; neither cmd_indent (core/cmds.mbt:351-375) nor cmd_add_child (core/cmds.mbt:143-152) bounds depth. Executed: initDoc("# R\n\n####### deep\n") yields a depth-7 node, and six consecutive addChild calls from the root produce "# R\n\n## \n\n### \n\n#### \n\n##### \n\n###### \n\n####### \n" with depth 7.

**検証による訂正**: 再現手順の言い回しが 1 点ずれている。マップの Tab は「インデント」ではなく addChild（src/mindmap.ts:1466-1470、選択が 2 個以上のときだけ indentSelection）。それでもルートから Tab 6 回で depth 7 に到達するので、結論は変わらない。

**影響**: 「md が唯一の真実」という前提が深い階層で崩れる。mmm 内では一貫しているので実害はマップ外での見え方のみ。

**修正方針**: 仕様どおりなら対処不要。気にするなら深さ 7 以上に UI 警告を出すか、cmd_indent で 6 を上限にする。

### 反証により除外(1 件)

- **UTF-8 BOM が先頭にあるとルート見出しがルートでなくなる（コア側に BOM 除去が無い）** — The parser fact is real — initDoc("﻿# R\n\n## a\n") returns a single node [d2 "a", parent -1] because core/parser.mbt:105 sees U+FEFF instead of '#' — but no code path can deliver a BOM to init_doc. Every text ingress is a Blob/File read: src/main.ts:525, src/main.ts:535 and the drop handler at src/main.ts:874 all use `await f.text()`, which the File API defines as UTF-8 decode and the Encoding Standard's UTF-8 decode strips a leading BOM by definition. The other two sources are localStorage (src/main.ts:1111, written from core.getText() at src/main.ts:105, already BOM-free) and the SAMPLE literal. init_doc is called only from loadText (src/main.ts:478), so there is no remaining route.

---

## 6. XSS・サニタイズ・信頼境界（信頼できない .md を開いたとき何が起きるか）

**調べたもの**

- src/mindmap.ts 全文(1815行)・src/main.ts 全文(1136行)・src/popup.ts・src/editor.ts・src/coreApi.ts・src/relevel.ts 相当箇所・index.html・src/style.css・core/parser.mbt を Read で通読（mindmap.ts は NUL バイトのため Grep ではなく Read を使用）
- HTML/SVG に文字列を入れる全経路の棚卸し: ラベル(mindmap.ts:609 label.textContent)、node の <title>(614)、link-row(635)、code-line(684)、img-name(719)、ctx-menu(1781,1786)、popup の title/label/hint(popup.ts:21,28,67) — すべて textContent。属性は svgEl()/setAttribute 経由で自動エスケープされる。文字列連結で markup を組み立てて DOM に流す経路は無い
- innerHTML の全出現を grep -a で確認 → src 全体で mindmap.ts:250 の 1 箇所のみ、静的な日本語リテラル（外部由来文字列は入らない）。outerHTML / insertAdjacentHTML / document.write / eval / new Function / srcdoc / iframe / createContextualFragment は 0 件
- <svg> ブロック → data:image/svg+xml → <image href> 経路(mindmap.ts:356-368, 649-660)。ブラウザは <image>/<img> 参照の SVG を secure static mode で扱うためスクリプトも外部参照も動かない。加えて .node image { pointer-events: none }(style.css:156) でクリックも取れない → 生ページ内での任意 JS 実行は成立しない（コメントの「static, safe」は正しい）
- リンクカードの URL 検証: parseLink(mindmap.ts:119-140) は /^\[([^\]]*)\]\((https?:\/\/[^\s)]+)\)$/ と /^https?:\/\/\S+$/ の行全体一致のみ。javascript:, data:, vbscript:, file: は正規表現段階で不一致 → data-url に入らない。開くのは nodeLayer の click(1249-1254) の window.open だけ
- showLinkPopup(popup.ts:127-142) の URL 検証: スキーム無しは https:// を前置、new URL() で失敗したら拒否。javascript:alert(1) は https://javascript:alert(1) となりポート不正で throw → 拒否される
- 画像パス検証: parseImage(mindmap.ts:144-153) がスキーム付き(http:/data:/javascript:)を全部弾く → 外部通信は発生しない。href に入るのは URL.createObjectURL 由来の blob: だけ
- 貼り付け経路(main.ts:380-423): navigator.clipboard.read() は image/* のみ、他は readText()。text/html を読む経路は存在しない。CodeMirror はソース編集器で markdown を HTML 描画しない(editor.ts)
- window.open(mindmap.ts:1253) に noopener あり。<a target=_blank> は全ソースに 0 件
- エクスポート経路(mindmap.ts:778-868 / main.ts:1004-1064): XMLSerializer によるシリアライズなので属性・テキストのエスケープは自動。encodeURIComponent 出力に " や < は残らず data URL の属性ブレイクアウトは不可。ラスタライズ用 img.src も data: なので canvas は汚染されない
- index.html に <meta http-equiv="Content-Security-Policy"> は無い。vite.config.* はリポジトリに存在しない（= レスポンスヘッダ設定も無い）
- core/parser.mbt の fence_open/fence_close_len を読み、バッククォート fence の info string にバッククォートがあると fence 扱いされないこと、閉じ fence は開き以上の長さが必要なことを確認（下記 F-3 の根拠）
- exportSvg は <image href="blob:">(833-848) を fetch して data URL に埋め込む。href に xlink:href を併記しないため SVG1.1 のみ対応のビューアでは画像が出ない可能性（機能上の注意、セキュリティではない）

### P5-XSS-1 / CONFIRMED / `src/mindmap.ts:646`

**リンクカードの URL ツールチップが常に無視される（表示名と遷移先の乖離を確認する手段が無い）**

```
g.append(title, tt, open);
```

**症状**: URL を入れた <title> 要素 tt を、既にラベル用 <title>(614行の t) を持つ同じ <g> に 2 個目として append している。SVG では要素のツールチップは最初の <title> 子だけが使われるため、tt は常に無視される。結果、↗ にホバーしても出るのはノードのラベル文字列で、実際に開かれる URL はどこにも表示されない。data-url は属性なので画面には出ず、md ペインを見ない限り遷移先が分からない。

**再現条件**: 1) 適当な .md を開く。2) md ペインで `## テスト` の下の行に `[公式サイト https://example.com](https://evil.example/phish)` と書く（表示名に偽 URL を入れるのが典型）。3) マップ側のノードに link カード行が出る。4) カード右端の ↗ にマウスを乗せてツールチップを見る → 出るのは「テスト」（ノードのラベル）で、evil.example は表示されない。5) ↗ をクリックすると window.open で evil.example が開く。

**確度**: 確定

**検証の根拠**: D:/1.atrium/mmm/src/mindmap.ts:613-615 で `const t = svgEl("title"); t.textContent = n.label; g.append(label, t);` と、ラベル用 <title> を先に g の子として入れている。その後 646 行 `g.append(title, tt, open);` で URL 用 tt を同じ g の 2 個目の <title> として追加している。SVG 仕様「Only the first title child element of a particular element is rendered」および Blink の SVGElement::DefaultToolTip()（Traversal<SVGTitleElement>::FirstChild）により 2 個目は無視される。↗ (open, mindmap.ts:638-645) 自身は <title> を持たないので祖先 g の最初の <title>=ラベルが出る。URL は data-url 属性(645行)にしか無く、画面表示は無い(parseLink は title 非空なら host も出さない: mindmap.ts:138)。

**検証による訂正**: 機構・行番号とも正しい。補強材料として、同じ render 内のコード行は tt を子要素側に付けており正しく動く（mindmap.ts:672-676 `bg.append(tt)`）——link 行だけが g に付けている非対称。修正は `open.append(tt)`。なお「実際に開かれる URL はどこにも表示されない」は map ペイン内での話で、md ペインには生テキストが見える（finding 本文もそう言っている）。唯一残る観測事項: 実ブラウザで ↗ にホバーしてノードラベルが出ることを目視確認すれば完全に決着する。

**影響**: 他人が書いた .md を開いたときのフィッシング経路。表示テキストを完全に攻撃者が決められ、遷移先を事前確認する UI が存在しない。ローカル専用アプリでも「もらった .md を開いてリンクを踏む」は現実的な操作。

**修正方針**: tt を g ではなく open（↗ の <text>）の子として append する（open.append(tt)）。併せて link-row 側にも URL を出すか、ラベルに host を併記して遷移先が読めるようにする。

### P5-XSS-2 / CONFIRMED / `src/main.ts:667`

**画像パスの `..` が許可済みフォルダ直下まで遡れ、その中身がエクスポート SVG に data URL として焼き込まれる**

```
if (segs.length === 0) return; // escapes the granted folder
```

**症状**: loadAsset() は md からの相対パスの `..` を、md のあるフォルダではなく「許可したディレクトリ(dirHandle)のルート」までしか止めない。dirHandle は IndexedDB に永続化され(716行 idbSet("dir", picked))、別のファイルを開いても assetSegs が md を含む限り再利用される(704-718行)。したがって md より上・許可ルート配下の任意の画像を ![](../..) で参照して描画できる。さらに exportSvg(mindmap.ts:833-844) は blob: サムネイルを fetch して base64 data URL としてエクスポート SVG に埋め込むため、参照した画像の中身がエクスポート成果物に入る。加えて「読めた=<image>が出る／読めない=破線プレースホルダ(mindmap.ts:703-720)」の差でファイルの存在有無も判別できる。

**再現条件**: 1) D:/work/notes/a.md を保存する（Ctrl+S）。2) ノードに画像を貼る（Mod+V か D のお絵描き）→ フォルダ選択が出るので **D:/work**（親）を選んで許可する。以後この許可は IndexedDB に残る。3) 攻撃者から受け取った .md を D:/work/notes/ に置き、内容を `# x` + 次行 `![](../secret/photo.png)` にして、開く/D&D で読み込む。4) マップペインを 1 回クリックする（unlockAssets が read 許可を通す）。5) D:/work/secret/photo.png のサムネイルがノードに表示される。6) ツールバーの SVG を押してダウンロードした .svg をテキストで開くと、その画像が data:image/...;base64 として埋め込まれている（WebP/PNG エクスポートでも画素として焼き込まれる）。

**確度**: 確定

**検証の根拠**: D:/1.atrium/mmm/src/main.ts:660-675 の loadAsset が base=assetSegs(dirHandle)（= 許可ルート→md フォルダの相対セグメント, main.ts:646-652）から出発し、`..` は segs.length===0 になるまで pop する(main.ts:665-667)。つまり md より上・許可ルート配下は読める。dirHandle は main.ts:716 `void idbSet("dir", picked)` で永続化され、boot の main.ts:1122-1133 で復元、loadText(main.ts:473-488) は clearAssets するだけで dirHandle を捨てないので別の md でも再利用される（dir.resolve(fileHandle) が非 null＝新しい md が許可ルート配下にあれば成立）。書き込み側 saveImageToDisk は main.ts:798-804 で `segs.some((s) => s === ".." ...)` を明示拒否しており非対称も事実。exportSvg は main.ts の blob: サムネイルを mindmap.ts:833-848 で fetch→FileReader→data URL に置換して埋め込む。placeholder 分岐は mindmap.ts:700-721 で存在有無が視覚的に分かれる。

**検証による訂正**: (1) 引用行は 667 ではなく main.ts:666。667 は `segs.pop();`。(2) 「704-718 行で再利用される」は誤り。704-718 は ensureImageDir（書き込み経路）で、読み取り側の再利用は loadAsset(654-682) と boot の 1122-1133。(3) 再現手順 4「クリック 1 回で read 許可が通る」は楽観的。リロード後の永続ハンドルは通常 prompt 状態で、unlockAssets(main.ts:687-701) の requestPermission はブラウザの許可ダイアログを出すのでユーザーの「許可」クリックが要る（同一セッション内で許可済みならクリック自体が不要で即読める）。(4) 到達範囲は「許可ルート配下」に限定される（任意のファイルシステムではない）——ただしこれは緩和ではなく、ユーザーが一度 D:/work を渡すと配下全部という意味。(5) NEW: 影響は画像に留まらない。parseImage(mindmap.ts:144-153) はスキームの無い相対パスなら拡張子を問わず通し、loadAsset は種別を検査せず objectURL を作る(main.ts:676)ので、`![](../secret/keys.txt)` のような非画像でも <image href="blob:…"> が DOM に入り、exportSvg の blob: 埋め込みループ(mindmap.ts:833-848)が中身を base64 化して .svg に書き出す。マップ上は何も描画されないため、ユーザーが気付かないまま任意ファイルがエクスポート成果物に混入しうる（F-002 等の既知項目とは別の新しい帰結）。

**影響**: 信頼できない .md が、ユーザーが過去に一度だけ許可したフォルダ配下の画像を勝手に読み込み、しかもユーザー自身がエクスポート・共有する成果物にそれを混入させられる。saveImageToDisk 側(main.ts:800)は `..` を明示的に拒否しているのに読み込み側だけ許しており、非対称。

**修正方針**: loadAsset でも `..` を一切許可しない（saveImageToDisk と同じく segs に `..` があれば return）。少なくとも md のあるフォルダ(base)より上に出る `..` を禁止し、許可ルートまで遡れる現仕様をやめる。

### P5-XSS-3 / CONFIRMED / `src/main.ts:441`

**コードポップアップのフェンス生成が言語名・本文を検証せず、md の構造を注入できる**

```
insertContentLine(id, `${fence}${r.lang}\n${r.code}\n${fence}`);
```

**症状**: フェンス長は `r.code.includes("```")` の 2 値判定だけ(439行)で、言語名 r.lang は素通し。core/parser.mbt の fence_open はバッククォート fence の info string にバッククォートがあると「フェンスではない」と判定し、fence_close_len は開き以上の長さを要求する。そのため (a) 言語名に ``` を入れると 6 連バッククォートの開きフェンスになり閉じ ``` では閉じず以降の文書全部を飲み込む、(b) 言語名にバッククォート 1 個を入れると開き行がフェンスと認識されず本文の `# …` 行が本物の見出しになる、(c) 本文に ```` 行を入れると 4 連フェンスが途中で閉じて残りが素の markdown になる。

**再現条件**: (b) が一番分かりやすい: 1) ノードを選んで Shift+C でコードポップアップを開く。2) 「言語」欄に a`b と入力（バッククォート 1 個）。3) 「コード」欄に `# のっとり` と入力。4) Mod+Enter で確定。5) マップに「のっとり」というノードが新規に出現し、md ペインでもコードブロックになっていないことが確認できる。(a) は言語欄に ``` を入れると、以降の見出しがすべてマップから消える。

**確度**: 確定

**検証の根拠**: D:/1.atrium/mmm/src/main.ts:439-441 でフェンス長は `r.code.includes("```")` の 2 値のみ、r.lang は popup.ts:101 の `lang.value.trim()` を素通し。core/parser.mbt:201-209 でバッククォート fence は info string にバッククォートがあると (0,0)＝非フェンス、parser.mbt:76 で閉じは `fence_close_len >= fence_len` を要求。よって (a) lang=``` → 6 連開き＋3 連では閉じない、(b) lang にバッククォート 1 個 → 開き行が非フェンス化、(c) 本文に ```` 行 → 4 連フェンスが途中で閉じる、はいずれも成立。

**検証による訂正**: 再現(b)の「症状」が誤り。挿入後のテキストは 開き行(非フェンス扱い) → `# のっとり` → 閉じ ``` の順になるが、core/doc.mbt:252-261 の rebuild_nodes は 2 個目以降の depth=1 見出しを heads から落とす（seen_root）。既定の SAMPLE(main.ts:39 `# mmm`)を含む「# 見出しが既にある文書」では『のっとり』ノードは出現しない。代わりに、閉じ ``` 行が parser.mbt:179-211 で新規の開きフェンス(len=3)になり、以降に閉じが無いため挿入位置より後ろの見出しが全部 scan_doc から消える＝マップからノードが大量に消滅する（(a) と同じ症状）。したがって (b) の正しい再現結果は「『のっとり』ノードが増える」ではなく「挿入位置以降のノードが全部消える」。加えて mindmap.ts:334 のカード行用フェンス正規表現 /^(`{3,}|~{3,})\s*(\S*)\s*$/ は同じ行を『言語 a`b のフェンス』として受理するため、マップのカード表示と core の構造解釈が食い違う（コアだけがフェンスと見なさない）。「のっとり」を実際にノードとして出したいなら `##` 見出しを注入する必要がある。

**影響**: ユーザー自身の入力が md 構造に化ける。信頼できない .md を開いたケースと違い攻撃者経由ではないが、コードを貼っただけで文書構造（=ノード木）が壊れ、閉じないフェンスの場合は以降の全ノードが消えて見える。

**修正方針**: lang からバッククォート/チルダと空白を除去（または `~~~` フェンスに切り替え）し、フェンス長は本文中の最長バッククォート連の長さ+1 で決める。

### P5-XSS-4 / CONFIRMED / `src/main.ts:430`

**リンクポップアップの title が未エスケープのまま markdown に埋め込まれ、リンク先をすり替えられる**

```
insertContentLine(id, r.title === "" ? r.url : `[${r.title}](${r.url})`);
```

**症状**: showLinkPopup は URL は検証するが title は trim だけ(popup.ts:141)。title に `]` と `(` を含めると出力行の括弧構造が変わり、mindmap.ts:121 の parseLink（行全体一致・URL 部は `[^\s)]+`）が別の URL を拾う。

**再現条件**: 1) ノードを選んで Shift+L。2) URL 欄に https://ok.example、タイトル欄に `Good](https://evil.example/x` と入力。3) 確定すると md に `[Good](https://evil.example/x](https://ok.example)` が入る。4) マップのカードには「Good」とだけ表示され、↗ をクリックすると evil.example が開く（F-1 によりツールチップでも確認できない）。

**確度**: 確定

**検証の根拠**: D:/1.atrium/mmm/src/main.ts:430 で `[${r.title}](${r.url})` を組み立て、popup.ts:127-142 の collect は URL のみ new URL() で検証し title は trim だけ(popup.ts:141)。title=`Good](https://evil.example/x` を入れると行は `[Good](https://evil.example/x](https://ok.example)` になり、mindmap.ts:121 の /^\[([^\]]*)\]\((https?:\/\/[^\s)]+)\)$/ は title="Good" にマッチする。↗ の data-url(mindmap.ts:645) はその URL になり、mindmap.ts:1253 の window.open が evil.example に飛ぶ。

**検証による訂正**: 抽出される URL は `https://evil.example/x` ではなく `https://evil.example/x](https://ok.example`（[^\s)]+ は `(` と `]` を含むので末尾 `)` の直前まで貪欲に食う）。new URL() の hostname は evil.example なので遷移先の主張自体は正しく、ok.example は一切使われない。影響評価も finding の自己申告どおり自傷どまり（ユーザー自身の入力が発端で、外部 .md は最初からこの行を直接書ける）。

**影響**: 単体では自傷でしかないが、F-1（URL が見えない）と組み合わさると、貼り付けた覚えのないドメインに飛ぶ行が生成されうる。信頼できない .md はそもそもこの形の行を直接書けるので、実害の主因は F-1 側。

**修正方針**: title 中の `[` `]` を \ でエスケープするか、`]` を含む title を拒否/除去する。parseLink 側も URL 部から `]` `(` `[` を除外する。

### P5-XSS-5 / CONFIRMED / `index.html:4`

**CSP が一切無い（meta も vite の設定も無い）**

```
<meta charset="UTF-8" />
```

**症状**: index.html の <head> に Content-Security-Policy の meta が無く、vite.config.* もリポジトリに存在しないためレスポンスヘッダでも指定されていない。現状は「全経路で textContent を使っている」「SVG は data URL の <image> 経由」という実装規律だけが防御になっている。

**再現条件**: 再現手順ではなく構成の確認: index.html 全 44 行に csp 文字列が無いこと、ls vite.config.* が空であることを確認する。現時点で悪用可能な注入点は見つかっていない（checked 参照）ので、これは単独の脆弱性ではなく多層防御の欠如。

**確度**: 確定

**検証の根拠**: D:/1.atrium/mmm/index.html 全 44 行に Content-Security-Policy の meta は無く（head は 3-8 行）、`ls vite.config.*` は No such file、package.json(D:/1.atrium/mmm/package.json) にも csp 相当の設定は無い。grep -rin 'content-security|csp' index.html package.json src/ の結果も 0 件。

**検証による訂正**: 事実関係は正しいが 2 点訂正。(1) 「全経路で textContent を使っている」は不正確——src/mindmap.ts:250 に `this.hint.innerHTML = ...` が 1 箇所ある（静的リテラルなので現状は無害だが、『innerHTML が 1 箇所でも増えた瞬間』という前提はすでに崩れている）。(2) 提案ポリシー `default-src 'self'; script-src 'self'; img-src 'self' blob: data:` は現状の機能を壊す。style-src が default-src にフォールバックし、CodeMirror 6 の StyleModule と vite の CSS 注入がランタイムで <style> 要素を生成するため 'unsafe-inline'（またはハッシュ/nonce）が必要。favicon の data: は img-src 側で拾える。脆弱性ではなく多層防御の欠如、という位置付けは finding の自己申告どおり妥当。

**影響**: 将来 innerHTML が 1 箇所でも増えた瞬間、信頼できない .md からの任意 JS 実行が無条件に通る。inline script を使っていない構成なので default-src 'self'; script-src 'self'; img-src 'self' blob: data: 程度なら現状の機能を壊さずに入れられる。

**修正方針**: index.html に <meta http-equiv="Content-Security-Policy" content="default-src 'self'; img-src 'self' blob: data:; style-src 'self' 'unsafe-inline'; object-src 'none'; base-uri 'none'"> を追加（CodeMirror はスタイルを動的注入するので style-src の unsafe-inline は必要）。

### P5-XSS-6 / CONFIRMED / `src/mindmap.ts:658`

**<svg> ブロックはブラウザ内では無害だが、未検証マークアップがそのままエクスポート SVG に残り、かつ毎 render で data URL を作り直す**

```
`data:image/svg+xml;charset=utf-8,${encodeURIComponent(r.markup)}`,
```

**症状**: md の `<svg` で始まる行から `</svg>` までを一切の検証なしに markup として取り込み(356-368行)、data URL 化して <image href> に載せる。ブラウザ内は secure static mode なのでスクリプト実行も外部参照も起きない（コメントの主張は正しい）。ただし (a) exportSvg はこの <image> をクローンするので、エクスポート/クリップボードコピーした SVG には攻撃者由来のマークアップが原文のまま含まれる。(b) render() は F-002 のとおりスナップショット毎に全再構築するので、巨大な <svg> ブロックがあるとキーストローク毎に encodeURIComponent(markup) が走り data URL 文字列が作り直される。

**再現条件**: (b) の再現: 1) 数百 KB 分の 1 行 `<svg ...>…</svg>` を含む .md を開く（ノードの本文行として）。2) md ペインで 1 文字ずつタイプする。3) 1 文字ごとに markup 全体の encodeURIComponent と data URL 割り当てが走り、入力遅延が悪化する（F-002 の実測に上乗せされる分）。(a) は SVG ボタンでエクスポートし、出力 .svg を開いて元のマークアップが data: の中に残っていることを確認する。

**確度**: 確定

**検証の根拠**: 取り込みは D:/1.atrium/mmm/src/mindmap.ts:356-368（`t.startsWith("<svg")` から `</svg>` まで無検証で buf.join）、data URL 化は mindmap.ts:656-659。(a) exportSvg の埋め込みループは mindmap.ts:833-836 で `if (!href.startsWith("blob:")) continue;` としており data: の href は素通しでクローンに残る（mindmap.ts:802 で nodeLayer 丸ごと cloneNode）ため、XMLSerializer(main.ts:1014) の出力に原文が入る。(b) 該当コードは render() 本体のループ内にあり、applySnap(main.ts:198)が毎スナップショットで map.render() を呼ぶので encodeURIComponent(markup) はキーストローク毎に走る。

**検証による訂正**: 自己申告『要確認』は不要——(a)(b) とも上記の行だけでコード上決着する。要確認が残るのは『非ブラウザ消費者に渡したときの安全性』という価値判断の部分だけ。(b) の負荷は encodeURIComponent だけでなく、render() が毎回 doc.slice(cStart,cEnd).split(/\r?\n/)(mindmap.ts:330) と buf.join("\n")(mindmap.ts:364) もやり直す分も乗る。なお (a) 単体は「エクスポートが文書内容を忠実に再現している」だけで、それ自体を欠陥と呼べるかは微妙。

**影響**: (a) は「ブラウザで開く限り安全」だが、エクスポート SVG を Inkscape / 変換ツール / 画像処理ライブラリなど非ブラウザの消費者に渡した場合の安全性はこのコードでは保証されない。(b) は F-002 の新しい増幅要因（ラベル再構築だけでなく巨大文字列の再エンコードが乗る）。

**修正方針**: (a) markup の長さ上限と、script/foreignObject/外部参照を含む場合の取り込み拒否（またはエクスポート時に <image> を落とす）。(b) markup → data URL を Map でキャッシュして render 毎の再エンコードをやめる。要確認事項: (b) の実測遅延、および (a) で想定する配布先ビューアがあるかどうか。

### P5-XSS-7 / CONFIRMED / `src/mindmap.ts:1253`

**外部リンクを開くとき noreferrer を付けていない**

```
if (url) window.open(url, "_blank", "noopener");
```

**症状**: noopener はあるが noreferrer が無いため、Referer ヘッダが送出される。

**再現条件**: 1) 信頼できない .md に `[x](https://attacker.example/)` を含む本文行を書いて開く。2) ↗ をクリック。3) attacker.example 側のアクセスログに Referer: http://localhost:5173/ 等（本番配信時は配信元 URL とパス）が記録される。

**確度**: 確定

**検証の根拠**: D:/1.atrium/mmm/src/mindmap.ts:1253 `if (url) window.open(url, "_blank", "noopener");` に noreferrer は無く、index.html(全 44 行)にも <meta name="referrer"> は無いので既定の referrer policy が効く。noopener は Referer 送出を抑止しないので Referer ヘッダは出る。

**検証による訂正**: 影響が過大。Chrome 85 以降の既定は strict-origin-when-cross-origin なので、クロスオリジンでは URL 全体ではなく**オリジンのみ**（例: `http://localhost:5173/`）が送られる。「本番配信時は配信元 URL とパス」は誤りで、パスは既定では漏れない（明示的に referrer policy を緩めた場合のみ）。修正は windowFeatures を "noopener,noreferrer" にするだけで足りる。

**影響**: ローカル配信なら漏れるのは localhost:ポート程度で軽微。ただし将来どこかにホストした場合、アプリの URL（パス含む）が第三者に渡る。

**修正方針**: window.open(url, "_blank", "noopener,noreferrer") にする。

### P5-XSS-8 / CONFIRMED / `src/mindmap.ts:107`

**measure() の widthCache が無制限に増える（外部由来文字列がキーになる）**

```
const widthCache = new Map<string, number>();
```

**症状**: キーは font+" "+text で、ラベル・コード行・clipLabel の二分探索プレフィックス(737行)がすべて入る。削除も上限も無い。文書を開き直しても（loadText → clearAssets はするが）widthCache はクリアされない。

**再現条件**: 1) ユニークな長い見出しを数千行持つ .md を開く。2) 別の同様の .md を続けて開く、を繰り返す。3) DevTools の Memory でヒープを見ると widthCache のエントリが積み上がり続ける（clipLabel を通る長いラベルは 1 本につき log2(長さ) 個の追加エントリを作る）。

**確度**: 確定

**検証の根拠**: D:/1.atrium/mmm/src/mindmap.ts:107 `const widthCache = new Map<string, number>();` はモジュールスコープで、mindmap.ts:108-116 の measure() は set するだけで delete も上限も無い。clear する箇所はファイル内に無く、loadText(main.ts:473-488) が呼ぶ clearAssets(main.ts:631-634) は assetUrls しか触らない。キー投入元はラベル(mindmap.ts:396)、コード行(404)、リンクタイトル(409)、clipLabel の二分探索プレフィックス(737)、ラベル編集中の入力値(936)。

**検証による訂正**: 『文書を次々開くとき』に限定しているのは過小。通常のタイピングでも増える——md ペインで見出しを 1 文字打つ度に applySnap→render→widthOf で新しいラベル文字列がキーになり、マップのラベル編集中は positionEditor(mindmap.ts:936) が入力値ごとに measure する。一方で影響は finding も認めるとおり未実測で、エントリは (文字列キー, number) なので実害は小さい可能性が高い。決着に必要な観測: 数千ノードの .md を数本開閉した後のヒープ差分と widthCache.size。

**影響**: 信頼できない .md を次々開くとメモリが単調増加する。実測での増加量は未確認。要確認: 実際の 1 文書あたりのエントリ数とヒープ増分。

**修正方針**: LRU 化するか、loadText / initDoc のタイミングで widthCache.clear() する。

### P5-XSS-9 / 要確認 / `src/main.ts:390`

**クリップボード画像の受理が image/* 前方一致で、image/svg+xml など非ラスタ型も通る**

```
const t = item.types.find((x) => x.startsWith("image/"));
```

**症状**: image/ で始まる型を無条件に採用し、saveImageToDisk の拡張子決定は IMG_EXT[out.type] ?? "png"(788行) なので未知の型は中身と無関係に .png として保存される。image/svg+xml が来た場合、WebP 再エンコード(774-787行)が失敗すれば SVG のテキストが x.png という名前でディスクに書かれ、md には ![](./x.png) が入る。

**再現条件**: 要確認: Chrome の navigator.clipboard.read() は既定で text/plain / text/html / image/png 程度しか露出しないため、image/svg+xml が実際に現れるかはブラウザ依存。確認方法は、SVG をクリップボードに載せた状態でコンソールから (await navigator.clipboard.read())[0].types を出力し image/svg+xml が含まれるか見る。含まれるなら 1) ノードを選択 2) Mod+V 3) 名前を入れて保存 4) 生成されたファイルをテキストエディタで開くと SVG マークアップになっている、で再現する。

**確度**: 要確認

**検証の根拠**: コード側は finding のとおり。ただし引用行は D:/1.atrium/mmm/src/main.ts:390 ではなく **389**（390 は `if (t) {`）。main.ts:389 `item.types.find((x) => x.startsWith("image/"))` は前方一致のみ、main.ts:788 `IMG_EXT[out.type] ?? "png"` は未知型を .png にする、main.ts:774-787 の WebP 再エンコード失敗時に out が元 blob のまま残る、はすべて確認できた。決着しないのは入口——Chrome の navigator.clipboard.read() が image/svg+xml を露出するかどうかで、これはこのリポジトリのコードでは判定できない（Chrome のサニタイズ済み read は text/plain・text/html・image/png が中心で、svg は意図的に除外されているはず）。

**検証による訂正**: 悪い結末には条件が 2 つ必要で、finding はそれを 1 つしか挙げていない: (i) clipboard.read() が image/svg+xml を露出し、かつ (ii) createImageBitmap(main.ts:776) がその SVG blob で失敗すること。Chrome は intrinsic サイズを持つ SVG なら createImageBitmap に成功するので、その場合は正しく WebP として保存され問題は起きない。決着させる観測は finding 記載のとおり `(await navigator.clipboard.read())[0].types` の確認＋実保存ファイルの中身確認で、両方が揃って初めて成立する。

**影響**: 拡張子と中身が食い違うファイルがユーザーのフォルダに書かれ、サムネイルは（blob の type が拡張子由来の image/png になるため）デコードできず出ない。SVG は能動的コンテンツなので、拡張子偽装のまま他所へ配布されると受け取り側の扱い次第で問題になりうる。

**修正方針**: 受理する型を IMG_EXT のキー（webp/png/jpeg/gif）に限定し、それ以外は拒否するか、実際の out.type に対応する拡張子が無い場合は保存しない。

### 反証により除外(1 件)

- **faviconSvg が色文字列を SVG に直接連結している（現状は呼び出し側の正規表現だけが防御）** — grep の結果 faviconSvg は D:/1.atrium/mmm/src/main.ts:123（定義）と main.ts:143（唯一の呼び出し）のみ。呼び出し元 applyColor は main.ts:132-134 で `/^#?([0-9a-f]{6})$/i` に通した上で `#${m[1]}` を**再構成**して渡すため、属性値に入るのは常に 7 文字の #RRGGBB。到達経路が存在せず、finding 自身も『再現手順は書けない』と認めている。現時点のコードに欠陥は無く、将来の回帰可能性は所見ではなく単なるメモ。

---

## 7. 永続化 (localStorage / IndexedDB / File System Access) — src/main.ts, src/fs-access.d.ts

**調べたもの**

- src/main.ts 全 1135 行を Read で通読(binary 誤検知なし、wc -l で 1135 行を確認)
- src/fs-access.d.ts 全 64 行(FSA 型宣言。queryPermission/requestPermission/resolve/isSameEntry の有無を確認 → isSameEntry は宣言されておらず、コードでも未使用)
- persistNow / schedulePersist / pagehide の 3 点(main.ts:98-115)と、schedulePersist を呼ぶ唯一の経路 applySnap(main.ts:203)を確認
- applySnap を呼ぶ全経路(onUserEdits / runCmd / rename / insertContentLine / paste / doUndo / doRedo / loadText)を追跡し、テキスト変更が必ず schedulePersist に到達することを確認
- window/document の全リスナーを grep で列挙(main.ts:115,701,850,856,857,882 / mindmap.ts:994,1005,1299,1302)→ storage イベントも visibilitychange も freeze も未登録であることを確認
- localStorage / indexedDB の全アクセス箇所を grep で列挙(main.ts:73,105,146,483,484,515,585,586,716,768,929,1081,1096,1100,1102,1111,1112,1113,1115,1122)→ 書き込みは全て try/catch、読み込みは全て無防備
- LS_TEXT / LS_SAVED / LS_NAME / LS_PANES / LS_COLOR / LS_THEME それぞれの書き込みタイミングと起動時の読み出し順序(main.ts:1095-1134)
- idb() の接続キャッシュ(idbConn ??=)、idbSet/idbGet のトランザクション完了待ち、onblocked ハンドラの不在(main.ts:70-96)
- fileHandle の生成/破棄/永続化の全経路(openFile:518-549, saveFile:551-598, drop:857-878, persistHandle:514-516, 起動時復元:1115-1121)
- dirHandle の許可再取得経路(ensureImageDir:704-718, unlockAssets:687-701, loadAsset:654-682)と、許可拒否時のリスナー解除(697)
- savedText の代入点(525,535,582,875,1113)と updateDirty(206-208) / confirmDiscard(612-615) / beforeunload(850-853) の整合
- 非 FSA フォールバック経路(openFile の <input type=file>、saveFile の <a download>)
- LS_PANES / LS_THEME / LS_COLOR に壊れた値が入った場合のパース挙動(includes / as Theme / 正規表現)
- core/api.mbt:114 get_text() が st.text をそのまま返す O(1) であること(毎キーストロークの再構築ではない)を確認
- src/mindmap.ts:1274-1292 のラベル編集 input ハンドラ → 1文字ごとに host.rename → core → applySnap → schedulePersist に到達するため、編集中ラベルの取りこぼしは無いことを確認
- node_modules/@codemirror/state/dist/index.js:608,972,2693,2761 の DefaultSplit=/\r\n?|\n/ と、editor.ts で EditorState.lineSeparator ファセットが未設定であることを確認

### P5-永続化-1 / CONFIRMED / `src/main.ts:525 (同型: 875, 適用先 480)`

**CRLF ファイルを開くと core と CodeMirror のオフセットが即座にずれる(読み込み経路が改行を正規化していない)**

```
savedText = await f.text();   … loadText 内 479-480: const snap = core.initDoc(text); editor.setText(text);
```

**症状**: Blob.text() は CRLF をそのまま返すので core.initDoc は \r\n を含む生テキストを保持する。一方 editor.setText → view.dispatch({changes:{insert:text}}) は CodeMirror が insert.split(/\r\n?|\n/) で分割し \r を捨てる(node_modules/@codemirror/state/dist/index.js:972、editor.ts は EditorState.lineSeparator を設定していないため DefaultSplit が効く)。結果、同じ文書に対して core の長さ = CM の長さ + CRLF 個数 となり、両ペインのオフセット空間が最初から食い違う。paste 経路(main.ts:401 clip.replace(/\r\n/g,"\n"))だけは正規化しているのに、ファイル読み込み・D&D・localStorage 復元の 3 経路は正規化していない。

**再現条件**: 1) メモ帳や PowerShell の Set-Content で CRLF 改行の crlf.md を作る(例: "# a", "", "## b", "", "### c" の 5 行)。2) mmm で 開く → crlf.md を選ぶ。3) マップで "c" ノードをクリック。md ペインのハイライト範囲が実際の "### c" 行より右に(CRLF 個数分)ずれる。4) マップで "c" をダブルクリックしてラベルを "cc" に変更 → core が返す editSets は core オフセットなので、CM 側では別の位置に適用され md ペインの本文が壊れる(見出しの途中に文字が混入する)。5) DevTools コンソールで比較すると差が確定する: md ペイン長 = document.querySelector('.cm-content').innerText.length 相当、core 長 = localStorage.getItem('mmm.text').length。6) さらに reload しても localStorage に CRLF のまま保存されているので、復元後も同じずれが再現する。

**確度**: 確定

**検証の根拠**: Mechanism verified end to end. node_modules/@codemirror/state/dist/index.js:608 `const DefaultSplit = /\r\n?|\n/;` and :972 `let insText = ... Text.of(insert.split(lineSep || DefaultSplit))` — src/editor.ts never sets EditorState.lineSeparator (checked the whole file), so editor.setText (editor.ts:149-154) drops every \r. core/api.mbt:99-100 `init_doc` does `st.text = text` with no normalization, and core/api.mbt:114 `get_text` returns `st.text` verbatim. core/parser.mbt:21-23 explicitly strips a trailing CR when computing line end, i.e. the core is deliberately CRLF-aware and keeps the \r in its offset space. src/main.ts:401 is indeed the only normalizing path (`clip.replace(/\r\n/g, "\n")`); main.ts:525, 874 and 1114 all feed raw text to both panes.

**検証による訂正**: Line cites are off by one in two places: `savedText = await f.text()` in the drop handler is main.ts:874 (875 is loadText), and inside loadText it is 478 `const snap = core.initDoc(text);` / 479 `editor.setText(text);` (480 is applySnap). More important, the repro understates it: the md pane is corrupted before any map interaction. onUserEdits (main.ts:250-299) forwards CodeMirror offsets straight into core.replaceText (main.ts:296), so the very first keystroke typed in the md pane of a CRLF file is applied at the wrong offset in the core text. Simplest repro: open crlf.md, put the caret at the end of the last line, type one character, and watch the map label change somewhere else. Also worth stating that the core is not the buggy side — core/parser.mbt handles CRLF correctly; the defect is purely that main.ts hands two different strings to the two panes.

**影響**: CRLF の .md(Windows で作られた md はこれが既定)を開いた瞬間から、マップ由来の全編集が md ペインの誤った位置に適用され、文書が静かに破壊される。Ctrl+S でその破壊済みテキストが上書き保存される。

**修正方針**: openFile / drop / 起動復元の 3 経路で読み込み直後に text.replace(/\r\n?/g, "\n") で正規化する(paste 経路と同じ扱いに揃える)。あわせて editor.ts で EditorState.lineSeparator.of("\n") を明示し、将来の分割揺れを封じる。

### P5-永続化-2 / CONFIRMED / `src/main.ts:482-487(書き込み側)/ 110-113(デバウンス)/ 1111-1121(復元側)`

**loadText は mmm.fileName / mmm.savedText を同期書き込みするのに mmm.text は 250ms 後 — この窓でプロセスが死ぬと「別ファイルの中身」を新ファイル名で復元し Ctrl+S が上書きする**

```
try {\n    localStorage.setItem(LS_NAME, name);\n    localStorage.setItem(LS_SAVED, savedText);\n  } catch {
```

**症状**: loadText は LS_NAME と LS_SAVED を同期で書くが LS_TEXT は書かない。LS_TEXT は applySnap(snap,"load") → schedulePersist() 経由で 250ms 後に初めて更新される。この 250ms の間にレンダラが死ぬと、localStorage は「旧ファイルの本文 + 新ファイルの名前 + 新ファイルの savedText」という不整合な組になる。次回起動では storedText(旧本文)が読み込まれ、fileName は新ファイル、しかも 1119 行の名前一致判定が通るので新ファイルの fileHandle まで採用される。

**再現条件**: 1) mmm で a.md を開く(本文 A)。2) DevTools → Sources → src/main.ts の 105 行 localStorage.setItem(LS_TEXT, core.getText()) にブレークポイントを置く。3) 開く で b.md(本文 B)を選ぶ。4) 読み込み直後 250ms でブレークポイントに止まる(= LS_TEXT がまだ A のままの状態で JS が凍結)。5) 止まったまま Chrome のタスクマネージャ(Shift+Esc)で mmm タブのプロセスを「終了」する(pagehide は走らない)。6) mmm を開き直す → タイトルは b.md、ドキュメント本文は A、未保存ドット点灯。7) Ctrl+S を押す → b.md の中身が A で上書きされる(B は消滅)。

**確度**: 確定

**検証の根拠**: src/main.ts:482-487 writes LS_NAME and LS_SAVED synchronously inside loadText; LS_TEXT is not written there. loadText's only persistence of the body is applySnap(snap,"load") at main.ts:480 -> schedulePersist() at main.ts:203 -> setTimeout(persistNow, 250) at main.ts:112. On restart main.ts:1111-1114 reads storedText=LS_TEXT (old body), storedName=LS_NAME (new name), savedText=LS_SAVED (new file's content), and main.ts:1119 `if (h && h.name === fileName) fileHandle = h;` adopts the new file's handle because LS_NAME already matches. dirty is then core.getText() !== savedText (main.ts:206-208) = true, and Ctrl+S (889-891 -> 571-573) writes the old body into the new file. The inconsistent triple is exactly as described.

**検証による訂正**: Scope the trigger honestly: a normal reload or tab close fires pagehide (main.ts:115) which calls persistNow, so the window is only open for an abrupt kill (renderer crash, OOM, task-manager terminate). Also persistHandle (main.ts:514-516) is itself an un-awaited async IDB write, so in a truly abrupt kill the handle may or may not have committed — if it did not, the mismatch is name-only and Ctrl+S falls back to showSaveFilePicker instead of silently overwriting. The finding's debugger-based repro is the reliable way to force it.

**影響**: クラッシュ / タブ破棄 / OS 強制終了のたびに、ファイル名とハンドルだけが新ファイルを指し本文が旧ファイルという状態が作れる。そこから 1 回保存するだけで別ファイルの内容が完全に失われる。

**修正方針**: loadText 内で LS_NAME/LS_SAVED と同じ try ブロックの中で persistNow() を呼び、3 つのキーを必ず同一タイミングで書く(または 3 値を 1 つの JSON キーにまとめて原子的に書く)。

### P5-永続化-3 / CONFIRMED / `src/main.ts:105 / 515 / 1111-1121`

**複数タブで同じ localStorage キーと IndexedDB の単一 handle キーを奪い合う(storage イベント未購読)**

```
localStorage.setItem(LS_TEXT, core.getText());   … void idbSet("handle", fileHandle).catch(() => {});
```

**症状**: mmm.text / mmm.savedText / mmm.fileName と IndexedDB の "handle" "dir" は全てオリジン単位の単一キーで、タブ ID もリビジョンも付いていない。storage イベントも購読していないので、どのタブも他タブの上書きを検知しない。後から書いたタブが常に勝ち、しかも「本文」「保存済みテキスト」「ファイル名」「ハンドル」が別々のタイミングで書かれるため、4 つが別々のタブ由来という組み合わせが容易に成立する。

**再現条件**: A) 単純消失: 1) タブ A で mmm を開き md ペインに "AAA" と入力、1 秒待つ。2) 同じ URL をタブ B で開く("AAA" が復元される)。3) タブ A で "BBB" を追記、1 秒待つ。4) タブ B(まだ AAA しか見えていない)で "CCC" を追記、1 秒待つ → mmm.text は AAA+CCC になり BBB は storage から消える。5) タブ A をリロード → BBB が消えている。\nB) 誤ファイル上書き: 1) D:\\p1\\README.md をタブ A で、D:\\p2\\README.md をタブ B で開く(IndexedDB の "handle" は後に開いた B のものになる。mmm.fileName はどちらも "README.md")。2) タブ A で編集し 1 秒待つ(mmm.text = p1 の内容)。3) 全タブを閉じて mmm を開き直す → 1119 行の h.name === fileName が "README.md" === "README.md" で通り、p2 のハンドルを採用したまま p1 の本文が載る。4) Ctrl+S → D:\\p2\\README.md が p1 の内容で上書きされる。

**確度**: 確定

**検証の根拠**: Verified there is no storage listener: grep -a over src/main.ts shows window listeners are only pagehide (115), pointerdown (701), beforeunload (850), dragover (856), drop (857), keydown (882); no other src/ file touches localStorage at all. All keys are origin-global singletons with no tab id or revision: LS_TEXT/LS_SAVED/LS_NAME (main.ts:64-66) and IDB keys "handle"/"dir" (main.ts:515, 716, 768). LS_TEXT is written only by persistNow (105), LS_NAME/LS_SAVED only by loadText (483-484) and saveFile (585-586), and the handle only by persistHandle (515) — four independent write points, so a cross-tab mix is trivially producible. Repro A is exact.

**検証による訂正**: Repro B step 3 ("全タブを閉じて") is order-dependent and can silently fail: pagehide (main.ts:115) fires persistNow in every tab, so whichever tab closes LAST wins LS_TEXT. To get the p1-body/p2-handle mismatch you must close tab B first and tab A last (or close B, then make one more edit in A, then close A). Everything else in repro B checks out: nothing rewrites IDB "handle" on close, so it stays B's handle, and main.ts:1119's name check passes on "README.md" === "README.md".

**影響**: 2 タブ運用は特別な操作ではない(参照用にもう 1 枚開く等)。無警告で編集が巻き戻り、最悪は無関係なファイルが上書きされる。

**修正方針**: 最低限 window.addEventListener("storage", …) で mmm.text の外部変更を検知し、他タブが編集中なら読み取り専用に落とすかリロードを促す。恒久的には Web Locks API(navigator.locks.request)で「書き手は 1 タブ」を保証し、handle も fileName ではなく世代付きキーで持つ。

### P5-永続化-4 / CONFIRMED / `src/main.ts:104-108`

**QuotaExceededError を握り潰し、しかも文書を 2 重(mmm.text と mmm.savedText)に保存しているため上限に早く当たる**

```
try {\n    localStorage.setItem(LS_TEXT, core.getText());\n  } catch {\n    /* storage full/blocked */\n  }
```

**症状**: quota 超過で setItem が投げても、UI には何の表示も出ず elDirty も変化しない。さらに Chrome は失敗時に既存値をそのまま残すので、localStorage には「古い版」が居座り続ける。ユーザーはクラッシュ保護が効いていると信じたままリロードし、古い版に巻き戻る。localStorage は UTF-16 換算 5MB 前後で、この実装は同じ文書を LS_TEXT と LS_SAVED に二重で持つため実効上限は半分。日本語は 1 文字 2 バイト換算なので体感上限はさらに低い。saveFile 側の LS_SAVED 書き込み(585)も同じ空 catch なので、保存済みテキストだけ古いまま残り dirty 判定も狂う。

**再現条件**: 1) mmm を開く。2) DevTools コンソールで領域を埋める: try{const s='x'.repeat(1000000); for(let i=0;i<4;i++) localStorage.setItem('pad'+i,s);}catch(e){console.log(e.name)}。3) md ペインで "これは消えます" と入力し 1 秒待つ。エラー表示も未保存以外の警告も一切出ない。4) リロード → 入力した文字列が消えている。5) DevTools の Console に例外も出ていないことを確認(catch が空のため)。

**確度**: 確定

**検証の根拠**: src/main.ts:104-108 is exactly the quoted empty catch, and the same empty-catch pattern repeats at 145-149, 482-487, 584-589, 928-932, 1080-1084. Nothing in the file surfaces a quota failure: updateDirty (206-208) compares core text to savedText only, so elDirty is unaffected, and there is no error path to flashFilename (601-610) from persistNow. LS_SAVED (main.ts:65) does hold a second full copy of the document, so the effective budget for LS_TEXT is roughly halved. The comment at main.ts:851 does claim "edits survive reloads via localStorage".

**検証による訂正**: Small precision fix on "二重に保存": LS_SAVED is only rewritten at loadText (484) and saveFile (585), not on every persist, so the two are not written in lockstep — but a full second copy of the document does sit in storage permanently, so the halved-budget conclusion stands. Also note the failure is not merely a lost update: because setItem leaves the previous value intact, the stale LS_TEXT will be restored at boot (1111-1114) as if it were the current document, which is worse than an empty restore.

**影響**: 「編集は localStorage で守られている」という前提(850 行のコメントもそう書いている)が静かに崩れる。大きな文書ほど確実に壊れ、しかもユーザーに知らせる手段が無い。

**修正方針**: catch で err.name === "QuotaExceededError" を判定し flashFilename で明示する。同時に LS_SAVED は本文全体ではなくハッシュ/長さだけ持つ(dirty 判定には十分)ようにして保存量を半減させ、上限超過時は LS_TEXT を消して「復元不可」を明示する方が古い版を復元するより安全。

### P5-永続化-5 / CONFIRMED / `src/main.ts:1096(同型: 1100, 1102, 1111, 1112, 1113)`

**起動時の localStorage 読み出しだけが try/catch 外 — サイトデータをブロックした環境で復元処理が丸ごと実行されない**

```
const stored = localStorage.getItem(LS_THEME) as Theme | null;
```

**症状**: 書き込み側(105,146,483,585,929,1081)は全て try/catch で守られているのに、起動ブロックの読み出しは 1 つも守られていない。Chrome でオリジンのサイトデータをブロックすると window.localStorage の取得自体が SecurityError を投げるため、1096 行でモジュール本体が例外終了する。1096 行より後にある処理 — applyTheme / applyColor / applyPaneVis の復元、loadText(= core.initDoc と editor.setText)、IndexedDB からの handle・dir 復元、mapPane.focus() — が全て実行されない。1095 行より前は実行済みなので、ツールバーもペインも出るが文書は空、という「半分動く」状態になる。

**再現条件**: 1) chrome://settings/content/siteData を開く。2) 「サイトデータの使用が許可されていないサイト」に mmm の配信元(例 http://localhost:5173)を追加する。3) mmm をリロード。4) 画面はツールバーとペイン枠だけ出るが md ペインは空、マップも空、SAMPLE すら表示されない。DevTools コンソールに main.ts 由来の SecurityError が 1 本出る。5) この状態で Ctrl+S を押すと core.getText() が "" なので空ファイルが保存される。

**確度**: 確定

**検証の根拠**: src/main.ts:1096 is verbatim as quoted and is genuinely the FIRST localStorage touch in module-evaluation order — I checked that mindmap.ts, editor.ts, popup.ts, relevel.ts and style.css contain no localStorage/sessionStorage at all, and that persistNow (105) / applyColor (146) are only defined, not called, before 1096. Every write site (105, 146, 483-484, 585-586, 929, 1081) is inside try/catch; none of the boot reads (1096, 1100, 1102, 1111-1113) is. A throw at 1096 aborts module evaluation, so applyTheme (1098), applyColor (1100), applyPaneVis (1104), loadText (1114), both idbGet restores (1115-1133) and mapPane.focus() (1135) never run. The "empty file gets saved" consequence checks out: core/doc.mbt:62-63 initialises `st.text: ""` and core/api.mbt:114 returns it, while btnSave (848) and the Ctrl+S keydown (882-891) were both registered before 1096.

**検証による訂正**: Add two details to the symptom description: elFilename keeps index.html:19's literal default "無題.md", so the toolbar looks completely normal and gives no hint that the restore failed; and because applyColor (1100) never runs, the favicon/--accent stay at the stylesheet defaults. The claim that only theme/color/panes/text are lost is right, but the visible cue is weaker than implied — nothing on screen is obviously broken except the empty document.

**影響**: 復元されないだけでなく、空文書のまま保存操作ができてしまう。プライベート/企業ポリシーでストレージを絞った環境やサンドボックス iframe 埋め込みで再現する。

**修正方針**: 起動ブロック全体を 1 つの try/catch で包み、読み出しヘルパ lsGet(key) を用意して例外時は null を返す。少なくとも loadText(SAMPLE) までは必ず到達させる。

### P5-永続化-6 / CONFIRMED / `src/main.ts:1115-1121`

**復元した fileHandle をベース名だけで照合している(isSameEntry も内容照合もしない)**

```
if (h && h.name === fileName) fileHandle = h;
```

**症状**: 511-513 行のコメントは「stale handle + fresh text で誤ったファイルを上書きするのを防ぐ」と宣言しているが、実際の照合は name の一致だけ。FileSystemFileHandle.name はディレクトリを含まないベース名なので、README.md / index.md / notes.md のような一般的な名前は簡単に衝突する。fs-access.d.ts にも isSameEntry は宣言されておらず、パスやディレクトリの同一性を検証する手段が一切用意されていない。さらに復元後にハンドル経由でファイルを読み直して savedText と突き合わせる処理も無いので、ハンドルが本当にその本文の出所かは最後まで検証されない。

**再現条件**: 上の「複数タブ」項の repro B と同じ手順で確定する(D:\\p1\\README.md と D:\\p2\\README.md)。単一タブでも再現可能: 1) D:\\p1\\README.md を開いて何か編集し 1 秒待つ。2) タブを閉じる。3) mmm を開き直す(p1 のハンドルが復元)。4) 開く で D:\\p2\\README.md を選び、直後に上の F(デバウンス)の手順でプロセスを落とす → 名前が同じなので必ず取り違える。

**確度**: 確定

**検証の根拠**: src/main.ts:1119 is verbatim `if (h && h.name === fileName) fileHandle = h;` and the comment at 511-513 does claim the stronger property. src/fs-access.d.ts:23-30 declares only kind/name/getFile/createWritable/queryPermission/requestPermission on FileSystemFileHandle — no isSameEntry, and FileSystemDirectoryHandle (32-46) exposes resolve() but it is used only for asset paths (main.ts:650, 763), never to validate the restored handle. saveFile (551-598) never re-reads the file before writing.

**検証による訂正**: Overstated as an independent defect — it is an enabler, not a standalone bug. In a single tab with no crash, fileHandle, LS_NAME, LS_TEXT and LS_SAVED are always written from the same load (openFile 524-527 and 536-538, drop 873-876, saveFile 574 and 585-586), so the name check never has a wrong handle to accept. It only causes harm after finding 2 (crash window) or finding 3 (multi-tab) has already de-synced them — and the finding's own "単一タブでも再現可能" repro is literally finding 2's crash repro, not an independent path. Correct framing: the guard at 1119 is too weak to catch the de-sync that 2 and 3 create; fixing 2 and 3 without fixing 1119 leaves the same-basename hazard, and fixing 1119 alone (e.g. persisting a full path/id and comparing, or re-reading the file and comparing to savedText) would convert both into a harmless "handle rejected, picker shown".

**影響**: 同名ファイルを複数ディレクトリで扱う運用(README.md、index.md など)で、Ctrl+S が別ディレクトリのファイルを黙って上書きする。

**修正方針**: handle と一緒に「その handle から読んだテキストのハッシュ」と「ユーザーに見せる用の識別子」を IndexedDB に保存し、復元時に handle.getFile() で読み直してハッシュ一致を確認してから採用する。不一致なら fileHandle は null にして名前を付け替えず、保存時に必ず Save As を出す。

### P5-永続化-7 / CONFIRMED / `src/main.ts:575-583`

**非 FSA 環境(Firefox / Safari)の保存は <a download> の成否を確認せずに savedText を更新するので、保存されていなくても未保存表示が消える**

```
a.href = URL.createObjectURL(new Blob([text], { type: "text/markdown" }));\n      a.download = fileName;\n      a.click();\n      URL.revokeObjectURL(a.href);\n    }\n    savedText = text;
```

**症状**: <a download> はダウンロードの成否を返さない。ユーザーがブラウザの保存ダイアログをキャンセルしても、拡張機能やポリシーでダウンロードがブロックされても、この経路は例外を投げずに 582 行の savedText = text に到達する。以後 updateDirty() で未保存ドットが消え、beforeunload(852)も警告しなくなり、confirmDiscard(613)も true を返して別ファイルを黙って開けるようになる。加えて a は DOM に挿入されておらず、click() の直後に同期で URL.revokeObjectURL しているため、Firefox ではダウンロード自体が始まらないことがある(同じパターンが downloadBlob:996-1002 にもある)。

**再現条件**: 1) Firefox(showOpenFilePicker が無い)で mmm を開く。2) md ペインに何か入力する → 未保存ドットが点灯する。3) 保存 を押す。4) Firefox の「ファイルを保存」ダイアログでキャンセルを押す(または about:preferences で毎回保存先を尋ねる設定にしておく)。5) 未保存ドットが消えている。6) タブを閉じる → beforeunload の警告が出ずにそのまま閉じ、変更は失われる。

**確度**: 確定

**検証の根拠**: src/main.ts:575-581 builds a detached <a download>, clicks it and revokes the URL, with no success signal available; main.ts:582 `savedText = text;` then runs unconditionally on the same path, followed by updateDirty (583) and the LS_SAVED/LS_NAME writes (584-589). The downstream consequences are all real: updateDirty (206-208) hides elDirty, confirmDiscard (612-615) returns true without prompting, and the beforeunload guard (850-853) stops firing. hasFs is `"showOpenFilePicker" in window` (main.ts:505), so Firefox/Safari really do take this branch. The same detached-anchor + immediate-revoke pattern is at downloadBlob (996-1002).

**検証による訂正**: Split the sub-claim about Firefox not starting the download at all. That part (revokeObjectURL called synchronously right after click) cannot be settled from source and is browser/version dependent — treat it as a separate 要確認 needing an actual Firefox run. The load-bearing claim (the dirty indicator is cleared with zero evidence that a file was written, so a cancelled save-dialog silently marks the document saved) is confirmed by the code alone.

**影響**: FSA 非対応ブラウザでは「保存した」表示が保存の証拠にならない。ユーザーが最も信頼する未保存インジケータが嘘をつく。

**修正方針**: 非 FSA 経路では savedText を更新せず、代わりに「ダウンロードしました。保存先を確認してください」という中立の表示にする(または a を document.body に append し、revokeObjectURL を setTimeout(…, 0) 以降に遅らせたうえで dirty は落とさない)。

### P5-永続化-8 / CONFIRMED / `src/main.ts:1113`

**起動時の savedText は localStorage 由来で、ディスク上のファイルと突き合わせない — 外部エディタの変更を無警告で上書きする**

```
savedText = localStorage.getItem(LS_SAVED) ?? storedText ?? SAMPLE;
```

**症状**: savedText は「ディスク上のファイルの現在の内容」を表しているはずの変数だが、起動時は localStorage のスナップショットから復元されるだけで、復元した fileHandle でファイルを読み直す処理がどこにも無い(1115-1121 は handle を代入するだけ)。つまり mmm を閉じている間に他のエディタがそのファイルを変更しても mmm は気付かない。dirty 判定(208)も confirmDiscard(613)も beforeunload(852)も全てこの古い savedText を基準にするため、実際には競合しているのに「変更なし」と判断される。保存時の競合検出(mtime 比較など)も一切無い。

**再現条件**: 1) mmm で notes.md を開く。2) mmm のタブを閉じる。3) VS Code など別エディタで notes.md に "外部から追記" と書いて保存する。4) mmm を開き直す(notes.md が localStorage から復元され、handle も復元される。未保存ドットは消えている = 「ファイルと一致」と主張している)。5) mmm 側で 1 文字だけ編集して Ctrl+S。6) notes.md を開き直すと "外部から追記" が消えている(警告もダイアログも一切出ていない)。

**確度**: 確定

**検証の根拠**: src/main.ts:1113 is verbatim, and the idbGet("handle") continuation at 1115-1121 only assigns fileHandle — it never calls h.getFile() and never compares to savedText. saveFile (551-598) writes via createWritable/write/close (571-573) with no mtime or content check beforehand. So savedText, which dirty (206-208), confirmDiscard (612-615) and beforeunload (850-853) all treat as "what is on disk", is in fact a localStorage snapshot from the previous session.

**検証による訂正**: Step 6 of the repro overstates it slightly: a handle restored from IndexedDB normally comes back in "prompt" state, so main.ts:557-561 will fire requestPermission on the first Ctrl+S and Chrome shows its own "Save changes to notes.md?" grant prompt. That is not a conflict warning and tells the user nothing about the external edit, but it is not literally "ダイアログも一切出ていない". Everything else — no re-read, no mtime comparison, silent full overwrite — is confirmed.

**影響**: mmm と他エディタを併用すると、mmm 側の保存が他方の編集を静かに全消しする。ローカル専用ツールとして README が謳う「git に乗る / 差分がテキストで読める」運用とは相性が悪い。

**修正方針**: 起動時に fileHandle を採用したら handle.getFile() で読み直し、内容が savedText と異なる場合は「ファイルが外部で変更されています」と提示して、復元テキストを使うかディスクを使うかをユーザーに選ばせる。保存直前にも file.lastModified を再確認して差異があれば確認ダイアログを出す。

### P5-永続化-9 / CONFIRMED / `src/main.ts:112-115`

**フラッシュが pagehide だけ — Chrome のタブ破棄、モバイルのバックグラウンド kill、強制終了では 250ms 分が確実に失われる**

```
persistTimer = window.setTimeout(persistNow, 250);\n}\n// don't lose the last debounce window on reload/close\nwindow.addEventListener("pagehide", persistNow);
```

**症状**: pagehide はリロードや通常のタブクローズでは発火するが、(a) Chrome のメモリ逼迫によるタブ破棄(chrome://discards の Discard)、(b) モバイル(特に iOS Safari / Android Chrome)でのバックグラウンドからのプロセス回収、(c) OS/タスクマネージャによる強制終了、では発火が保証されない。Page Lifecycle の推奨は visibilitychange(hidden)でフラッシュすることだが、visibilitychange も freeze も購読していない(grep で確認済み: window の listener は pagehide / pointerdown / beforeunload / dragover / drop / keydown のみ)。

**再現条件**: 1) mmm で md ペインに "消えるかも" と入力し、そのまま 250ms 以内に別タブへ切り替える…では確実性が無いので次の手順を使う。2) DevTools → Sources → main.ts:105 にブレークポイントを置く。3) 入力して 250ms 後にブレークポイントで停止(この時点で LS_TEXT は未更新)。4) 別タブで chrome://discards を開き mmm タブの Discard を押す(または Shift+Esc のタスクマネージャで mmm のプロセスを終了)。5) mmm タブに戻る/開き直すと、入力した "消えるかも" が消えている。pagehide は走っていない。

**確度**: 確定

**検証の根拠**: src/main.ts:112-115 is verbatim, and I re-verified the listener inventory: grep -a over src/main.ts shows the only window listeners are pagehide (115), pointerdown (701), beforeunload (850), dragover (856), drop (857), keydown (882). No visibilitychange and no freeze anywhere in src/. persistNow is reachable only from that pagehide handler and from the 250ms timer, so any termination that skips pagehide loses the pending window.

**検証による訂正**: Repro is a bit heavier than needed. Because schedulePersist (110-113) RESETS the timer on every applySnap (203), the exposure during a fast typing burst is not 250ms of input but everything typed since the last pause — which can be far more than 250ms worth. Practical repro without a debugger: type continuously for several seconds without ever pausing 250ms, then kill the tab from Shift+Esc; nothing typed in that burst is in mmm.text. This also strengthens the finding rather than weakening it.

**影響**: モバイルや低メモリ環境では日常的に 250ms 分の入力が消える。上記のデバウンス不整合(F: 482-487)と組み合わさると本文とファイル名の食い違いにも発展する。

**修正方針**: document.addEventListener("visibilitychange", () => { if (document.visibilityState === "hidden") persistNow(); }) を追加する(pagehide より確実に発火する)。可能なら freeze イベントでもフラッシュする。

### P5-永続化-10 / CONFIRMED / `src/main.ts:691-699`

**unlockAssets は許可が拒否されてもリスナーを外すため、そのセッション中は二度と画像を再取得できない**

```
const ok =\n      q === "granted" ||\n      (q === "prompt" &&\n        (await dh.requestPermission({ mode: "read" })) === "granted");\n    window.removeEventListener("pointerdown", unlockAssets, true);\n    if (ok) for (const p of pending) void loadAsset(p);
```

**症状**: removeEventListener が ok の判定より前・かつ ok に関係なく実行される。ユーザーが誤ってフォルダ許可を拒否した、あるいは q が既に "denied" だった場合、以後どれだけクリックしても再試行は起きない。loadAsset(657-659)は許可が無いと assetUrls の値を null のまま return し、imageUrl(636-642)は「undefined でない」= キャッシュ済みとみなして再ロードしないため、サムネイルは空のまま固定される。リロードしか回復手段が無いが、その旨の表示も出ない。

**再現条件**: 1) FSA 対応ブラウザで md を保存済みにし、画像を 1 枚貼り付けてフォルダ許可を与える(サムネイルが出る)。2) リロードする(handle は IndexedDB から復元、許可は prompt 状態に戻る)。3) 画面のどこかを 1 回クリックするとフォルダ許可のプロンプトが出る → 「許可しない」を選ぶ。4) 以後どこを何回クリックしてもプロンプトは二度と出ず、サムネイルは空のまま。5) DevTools で getEventListeners(window).pointerdown を見ると unlockAssets が消えている。

**確度**: 確定

**検証の根拠**: src/main.ts:691-699 is verbatim: `window.removeEventListener("pointerdown", unlockAssets, true);` at 697 runs after `ok` is computed but is not conditional on it, so a "denied" outcome still unregisters the listener registered at 701. The no-retry consequence checks out: loadAsset (654-659) returns early while permission is not granted, leaving assetUrls[path] === null, and imageUrl (636-642) does `const hit = assetUrls.get(path); if (hit !== undefined) return hit;` — null is not undefined, so it returns null without re-dispatching loadAsset. Nothing else re-arms the listener.

**検証による訂正**: Two refinements. (a) There is one other retry site — the idbGet("dir") continuation at 1122-1131 loops over pending assets and calls loadAsset — but it runs exactly once at boot, before the denial, so it does not help. (b) The listener only leaks away on a clean "denied" resolution; if requestPermission throws (e.g. transient activation already consumed) the async IIFE rejects into the .catch at 699 BEFORE reaching line 697, so the listener survives. That means the failure is specifically "user clicked 許可しない" or the grant was already in "denied" state, which matches the repro.

**影響**: 一度の誤クリックで、そのセッションの画像表示が全滅する。回復方法がユーザーに提示されない。

**修正方針**: removeEventListener を if (ok) { … } の中に移す。拒否された場合はリスナーを残す(または flashFilename で「画像フォルダの許可が必要です」と提示し、再取得のトリガを明示する)。

### P5-永続化-11 / CONFIRMED / `src/main.ts:72-78(キャッシュ)/ 515, 716, 768, 1121, 1133(全て .catch(() => {}))`

**IndexedDB の失敗が完全に無音で、しかも失敗した接続 Promise がセッション中キャッシュされ続ける**

```
idbConn ??= new Promise((resolve, reject) => {\n    const req = indexedDB.open("mmm-store", 1);
```

**症状**: idbConn ??= により、open が一度でも失敗すると同じ拒否済み Promise が以後すべての idbSet/idbGet に返り続ける(セッション中の回復手段が無い)。呼び出し側は 5 箇所すべてが .catch(() => {}) で握り潰すため、ユーザーには何も伝わらない。結果として「Firefox / 一部のプライベートウィンドウ / ストレージがブロックされた環境」では、fileHandle と dirHandle が毎回失われるのに、画面には localStorage 由来の mmm.fileName(例 README.md)が表示され続ける。ユーザーから見ると「ファイル名は出ているのに Ctrl+S を押すたび保存ダイアログが出る」という説明のつかない挙動になる。onblocked ハンドラも無い(現状 version 1 固定なので発火経路は限定的だが、将来スキーマを上げた瞬間に Promise が永久に未解決になる)。

**再現条件**: 1) Firefox のプライベートウィンドウ、または chrome://settings/content/siteData でサイトデータをブロックした状態で mmm を開く(localStorage 例外の件は F: 1096 の修正後を想定)。2) DevTools コンソールで idbGet 相当を直接叩く: indexedDB.open('mmm-store',1).onerror = e => console.log('err', e.target.error) → エラーが出る環境であることを確認。3) mmm で任意のファイルを開き、閉じて開き直す。4) タイトルバーには前回のファイル名が出るのに、Ctrl+S を押すと毎回「名前を付けて保存」になる。エラー表示は一度も出ない。

**確度**: 確定

**検証の根拠**: src/main.ts:70-79: `idbConn ??= new Promise(...)` — a rejected Promise is neither null nor undefined, so ??= never re-assigns it and every later idbSet (80-88) / idbGet (89-96) awaits the same rejection for the life of the page. All five call sites do swallow it: 515, 716, 768, 1121, 1133 are each `.catch(() => {})`. req.onblocked is indeed not handled (72-77).

**検証による訂正**: The repro's environment is wrong and should be replaced. Firefox has no File System Access API at all, so hasFs is false (main.ts:505), fileHandle is permanently null, persistHandle stores null, and saving goes through the <a download> branch (575-581) — the described symptom "ファイル名は出ているのに Ctrl+S で毎回保存ダイアログ" is just normal Firefox behaviour, not an IndexedDB failure. The only environment where the code path actually bites is Chromium with IndexedDB blocked/unavailable, and there localStorage is blocked too, so finding 5 kills the page at 1096 first — this defect is only observable after finding 5 is fixed. Downgrade to a latent robustness issue (silent permanent degradation, no user-visible cause), and drop the "Firefox で再現" claim.

**影響**: ハンドル永続化が効かない環境で、原因が一切ユーザーに伝わらない。ファイル名表示だけが残るので「保存先を覚えているはず」と誤解させ、Save As で別の場所に保存してしまう事故を誘発する。

**修正方針**: idb() の失敗時に idbConn = null に戻して次回再試行できるようにし、handle 復元に失敗したときは elFilename の表示を「無題.md」に戻すか、保存先未確定であることを明示する。req.onblocked も実装しておく。

### P5-永続化-12 / CONFIRMED / `src/main.ts:1111-1114`

**起動時の自動復元にバイパス手段が無く、壊れた/巨大な永続文書から抜け出せない**

```
const storedText = localStorage.getItem(LS_TEXT);\n  const storedName = localStorage.getItem(LS_NAME);\n  savedText = localStorage.getItem(LS_SAVED) ?? storedText ?? SAMPLE;\n  loadText(storedText ?? SAMPLE, storedName ?? "無題.md");
```

**症状**: 起動は無条件に localStorage の本文を core.initDoc + editor.setText + map.render に流す。サイズ上限も、パース/描画に失敗したときのフォールバックも、ユーザーが復元をスキップする手段(URL パラメータ、Shift 押下起動、「新規」ボタン)も無い。localStorage の上限一杯(UTF-16 で ~5MB)の文書が入ると、既知の F-002 の描画コストと相まって起動のたびに長時間フリーズし、ユーザーは DevTools か「閲覧履歴データの削除」でしか脱出できない。

**再現条件**: 1) DevTools コンソールで localStorage.setItem('mmm.text', Array.from({length:40000},(_,i)=>`${'#'.repeat((i%6)+1)} n${i}\\n\\n`).join('')) を実行する(約 4 万ノード)。2) mmm をリロードする。3) 起動時にタブが数秒〜数十秒無反応になる(進捗表示も中断手段も無い)。4) 再度リロードしても同じ文書が復元されるため、UI 操作だけでは回復できないことを確認する。

**確度**: 確定

**検証の根拠**: src/main.ts:1110-1114 restores unconditionally: no length check on storedText, no try/catch around loadText, no URL-parameter or modifier-key opt-out. loadText (473-488) runs core.initDoc + editor.setText + applySnap (which calls map.render() at 198) with no guard. I also confirmed there is no escape hatch in the UI: index.html:22-34 has only 開く / 保存 / undo / redo / SVG / WebP / MD / マップ / theme — no 新規 button, and no keyboard shortcut for one (main.ts:882-910 handles only s, o, /, z, y).

**検証による訂正**: Drop the "壊れた" half — there is no evidence the parser can throw on arbitrary text (core/parser.mbt scan_lines is a plain loop), so the fallback-on-parse-failure argument is speculative. The size half is solid and sufficient. Also soften "起動不能に近い状態で固定": the user can still recover through the browser's own site-data clearing, which the finding does acknowledge; the real complaint is that the app offers no in-app recovery and no indication of what is happening.

**影響**: 一度巨大な文書を扱うと、以後アプリが起動不能に近い状態で固定される。ユーザーには原因も回復方法も提示されない。

**修正方針**: 復元前に storedText.length の閾値チェックを入れ、超えていたら復元せず「前回の文書が大きすぎます。復元しますか?」を出す。あわせて「復元をやめて新規で開く」導線(?fresh=1 など)を用意する。

### P5-永続化-13 / CONFIRMED / `src/main.ts:525 / 571-573`

**UTF-8 BOM 付き md を開いて保存すると BOM が黙って消える**

```
savedText = await f.text();   … const w = await fileHandle.createWritable(); await w.write(text); await w.close();
```

**症状**: Blob.text() は Encoding Standard の UTF-8 decode を使うため先頭の U+FEFF を除去する。一方 createWritable().write(string) は BOM を付けずに UTF-8 で書き出す。したがって BOM 付きの .md(Windows の PowerShell Out-File 既定など)を開いて 1 回保存すると、BOM が失われた別バイト列に置き換わる。savedText は BOM 除去後の文字列なので、mmm 側からはこの差分が永久に見えない(dirty 判定にも出ない)。

**再現条件**: 1) PowerShell で BOM 付きファイルを作る: '# a' | Out-File -Encoding utf8 D:\\tmp\\bom.md(Windows PowerShell 5.1 の utf8 は BOM 付き)。2) certutil -dump または Format-Hex で先頭 EF BB BF を確認する。3) mmm で bom.md を開き、1 文字追記して Ctrl+S。4) 再度 Format-Hex → 先頭の EF BB BF が消えている。5) mmm 側には未保存ドットも警告も出ていない。

**確度**: 確定

**検証の根拠**: src/main.ts:525 (`savedText = await f.text()`) and 874 both use Blob.text(), which per the File API runs UTF-8 decode — that algorithm strips a leading U+FEFF. The write side, src/main.ts:571-573, is `createWritable()` / `write(text)` / `close()`; createWritable defaults keepExistingData:false so the file is truncated and rewritten as plain UTF-8 with no BOM. src/fs-access.d.ts:18-21 confirms write() takes a raw string with no encoding option. Because savedText holds the post-strip string, updateDirty (206-208) can never see the difference, so no dirty indication is produced.

**検証による訂正**: No correction needed to the mechanism. One addition worth recording: the same silent loss applies on the drop path (main.ts:874) and to the non-FSA <a download> path (577), where new Blob([text]) likewise emits no BOM. Severity is correctly called 軽微 — the byte-level diff is one-time, not progressive.

**影響**: 軽微だが、BOM に依存するツールチェーン(このユーザーのメモにある PowerShell の BOM/文字化けの罠)では文字化けや差分ノイズの原因になる。git diff がファイル全体の変更として出る。

**修正方針**: 読み込み時に BOM の有無を記録し(ArrayBuffer で先頭 3 バイトを見る)、保存時に元が BOM 付きだったら書き戻す。少なくとも保存時に「改行コード/BOM を正規化した」ことを一度は表示する。

### P5-永続化-14 / CONFIRMED / `src/main.ts:850-853`

**beforeunload が e.returnValue を設定しておらず、復元直後の dirty 状態ではユーザー操作が無いため警告が出ない**

```
window.addEventListener("beforeunload", (e) => {\n  // edits survive reloads via localStorage, but warn about the real file\n  if (core.getText() !== savedText) e.preventDefault();\n});
```

**症状**: (a) e.preventDefault() のみで e.returnValue = "" を設定していない。Chrome 119 以降は preventDefault だけで動くが、古い Safari / 一部の環境は returnValue を要求するため確認ダイアログが出ない。(b) より実害があるのは sticky user activation の要件で、Chrome はページに一度もユーザー操作が無いと beforeunload ダイアログを出さない。起動直後に localStorage 復元によって dirty(= ディスクと不一致)状態で立ち上がるケース(上の savedText 復元の項)では、ユーザーが何も触らずにタブを閉じると警告なしで閉じる。

**再現条件**: 1) mmm でファイルを開き編集して、保存せずにタブを閉じる(復元用の dirty 状態を作る)。2) mmm を開き直す → 未保存ドットが点灯した状態で起動する。3) ページ内を一切クリック・タイプせずに Ctrl+W でタブを閉じる → 確認ダイアログが出ない。4) 比較として、1 文字でも入力してから閉じるとダイアログが出ることを確認する。

**確度**: 確定

**検証の根拠**: src/main.ts:850-853 is verbatim — only e.preventDefault(), no e.returnValue assignment. The dirty-on-boot precondition is real and comes from the code: main.ts:1113 sets savedText from LS_SAVED while 1114 loads LS_TEXT, so when the previous session ended dirty the two differ and updateDirty (206-208, reached via applySnap:202) shows elDirty immediately at boot with no user input. mapPane.focus() at 1135 is programmatic and does not confer user activation.

**検証による訂正**: Sub-claim (a) is largely moot and should be de-emphasised: preventDefault() alone is sufficient in current Chrome, Firefox and Safari; only quite old engines needed returnValue. The load-bearing part is (b), the sticky-user-activation requirement, and the repro for it is correct as written. Reframe the finding as "the one path that boots straight into dirty state can be closed without any prompt" and drop the returnValue point to a footnote.

**影響**: 未保存の状態でタブを閉じても止められない経路が実在する。localStorage 側は残るので致命的ではないが、上の quota / デバウンスの問題と重なると実データを失う。

**修正方針**: e.preventDefault() に加えて e.returnValue = "" を設定する。加えて、復元直後に dirty な場合は「前回の未保存の変更を復元しました」というバナーを出し、ユーザーに状態を認識させる(バナー操作が activation にもなる)。

### P5-永続化-15 / CONFIRMED / `src/main.ts:551-598(特に 563-570)`

**saveFile に再入ガードが無く、Ctrl+S の連打/オートリピートで保存ピッカーが多重に呼ばれて偽の「保存失敗」が出る**

```
if (!fileHandle) {\n        fileHandle = await window.showSaveFilePicker({\n          suggestedName: fileName,\n          types: [MD_TYPE],\n        });
```

**症状**: saveFile は実行中フラグを持たず、btnSave のクリック(848)と keydown の Ctrl+S(889-892)の両方から何度でも並行起動できる。キーリピートでも呼ばれる(889 行に repeat 判定が無い)。ハンドル未設定時は showSaveFilePicker が二重に呼ばれ、Chrome は 2 回目に「File picker already active」(name は AbortError ではない)を投げるため、593 行の AbortError 除外を素通りして flashFilename("保存失敗") が表示される。ハンドル設定済みの場合は同一ハンドルに対して createWritable が並行し、後勝ちで close される。

**再現条件**: 1) mmm を新規状態(ファイル未保存 = fileHandle が null)で開く。2) Ctrl+S を押しっぱなしにする(キーリピート)。3) 保存ダイアログが 1 枚出た状態で、背後のツールバーに「保存失敗」の赤い表示が出る。4) ダイアログで保存しても「保存失敗」の表示が 4 秒間残る。

**確度**: 確定

**検証の根拠**: All the code-level preconditions hold. src/main.ts:551 saveFile has no in-flight flag and no module-level lock; both entry points are unguarded (btnSave click at 848, Ctrl+S at 889-891); the keydown filter at 885 checks only e.isComposing / keyCode 229 and never e.repeat; and the error filter at 593 excludes ONLY AbortError, so any other DOMException reaches flashFilename("保存失敗") at 595 with its 4-second timeout (605-609). With fileHandle already set, the awaits at 557-559 and 571 let two calls reach createWritable() on the same handle concurrently with no serialisation.

**検証による訂正**: Fix the exception name and temper the repro. A second concurrent showSaveFilePicker rejects with NotAllowedError ("File picker already active" is the message, not the name) — the conclusion that it bypasses the AbortError filter is right, but the finding names it wrongly. The key-repeat window is also narrower than implied, because the OS-modal picker takes keyboard focus as soon as it appears; the more reliably reachable variants are (i) clicking 保存 and pressing Ctrl+S nearly simultaneously, and (ii) the fileHandle-already-set path, where the second createWritable() on a locked handle throws NoModificationAllowedError and flashes 保存失敗 even though the first write succeeded. Whether the flash actually renders is a browser observation; the missing guard itself is settled by the code.

**影響**: 実際には保存できているのに失敗表示が出る(逆の誤解を招く)。並行 createWritable のほうは同じ text を書くため今のところ実害は小さいが、将来の差分書き込みでは競合になる。

**修正方針**: let saving = false; のガードを saveFile の先頭に置き、実行中は即 return する。あわせて 889 行で e.repeat を無視する。

### P5-永続化-16 / CONFIRMED / `src/main.ts:529-542`

**非 FSA 経路の openFile は input.onchange 内の例外を外側 try/catch で拾えず、読み込み失敗が無音になる**

```
input.onchange = async () => {\n        const f = input.files?.[0];\n        if (f) {\n          fileHandle = null;\n          savedText = await f.text();
```

**症状**: onchange は async 関数で、input.click() の後に openFile() の Promise は即座に解決してしまう。したがって f.text() が失敗しても 543-548 行の catch には入らず、unhandled rejection になるだけで flashFilename("読み込み失敗") は表示されない。ユーザーから見ると「ファイルを選んだのに何も起きない」。

**再現条件**: 1) Firefox(または showOpenFilePicker を無効化した環境)で mmm を開く。2) 開く を押してファイル選択ダイアログを出す。3) ダイアログを開いたまま、エクスプローラで対象ファイルを削除(またはロックされた別ドライブへ移動)する。4) ダイアログでそのファイルを選ぶ → NotReadableError が発生するが画面には何も出ず、文書も変わらない。DevTools コンソールにだけ Uncaught (in promise) が出る。

**確度**: 確定

**検証の根拠**: src/main.ts:528-542: the try block opened at 520 contains `input.onchange = async () => { ... }` (532-540) and `input.click()` (541). click() returns synchronously, so openFile's promise settles and the catch at 543-548 is out of scope long before onchange ever runs. Any rejection from `await f.text()` (537) or a throw inside loadText (538 -> 473-488) therefore becomes an unhandled rejection with no path to flashFilename("読み込み失敗") at 546. hasFs at main.ts:505 confirms Firefox/Safari take this branch.

**検証による訂正**: Worth adding that the silence is broader than "読み込み失敗": the confirmDiscard gate at 519 has already been passed and consumed by the time onchange fires, so a failed read leaves the app in exactly its previous state with no signal at all — and since fileHandle is still whatever it was, a subsequent Ctrl+S targets the OLD document, not a stray new one. The finding's "元の文書を別名保存してしまう" is close but the mechanism is that fileHandle was never reassigned (it is set to null at 535 only if `f` exists).

**影響**: 読み込み失敗がユーザーに伝わらない。ユーザーは「開いたつもり」で編集を続け、Ctrl+S で元の文書を別名保存してしまう可能性がある。

**修正方針**: onchange の中身を try/catch で包み、失敗時に flashFilename("読み込み失敗") を呼ぶ。あるいは onchange を Promise でラップして openFile 側で await する。

### P5-永続化-17 / CONFIRMED / `src/main.ts:484`

**loadText が引数ではなくモジュール変数 savedText を localStorage に書いている(呼び出し順序への暗黙依存)**

```
localStorage.setItem(LS_SAVED, savedText);
```

**症状**: loadText(text, name) は text を受け取るのに、LS_SAVED には引数ではなくモジュールスコープの savedText を書く。現在の呼び出し 3 箇所(openFile:526、drop:875-876、起動:1113-1114)はいずれも直前に savedText へ代入しているので偶然正しく動くが、契約としては表現されていない。将来 loadText を「新規文書」用途などで savedText 更新なしに呼ぶと、前の文書の保存済みテキストが新文書の LS_SAVED として書かれ、dirty 判定と confirmDiscard が恒久的に狂う。

**再現条件**: 要確認: 現行コードでは再現経路が無い(3 つの呼び出し全てが直前に savedText を代入している)。これを確定させるには、loadText の第 3 引数として savedText を明示的に渡す形にリファクタしたうえで、全呼び出し元が同じ値を渡していることを型で保証できるか(= 現在の 3 箇所以外に呼び出しが増えないか)を確認すればよい。

**確度**: 確定

**検証の根拠**: src/main.ts:484 is verbatim `localStorage.setItem(LS_SAVED, savedText);` inside loadText(text, name) (473-488), which never reads its own `text` parameter for that write. The finding correctly labels itself as having no live repro, and I could not construct one either.

**検証による訂正**: Two factual fixes. (1) There are FOUR call sites, not three: openFile FSA at 526, openFile non-FSA at 537, drop at 875, boot at 1114. (2) The premise "3 箇所いずれも直前に savedText へ代入しているので偶然正しい" is not true of the boot call — main.ts:1113 sets savedText from LS_SAVED while 1114 passes LS_TEXT, so at boot the argument and savedText deliberately differ whenever the previous session ended dirty. It is harmless only because line 484 then rewrites LS_SAVED with the exact value it was just read from at 1113. That makes the invariant even more fragile than the finding claims: the "argument == savedText" contract is already violated on one of the four paths today, and only a value-identity coincidence keeps it correct.

**影響**: 現時点では潜在的。ただしこのファイルで最も事故りやすい不変条件(savedText / LS_SAVED / LS_TEXT / LS_NAME の 4 つ組の整合)が、コードではなく呼び出し順序という暗黙のルールで守られている。

**修正方針**: loadText(text: string, name: string, saved: string) に変更し、内部で savedText = saved としてから 3 キーをまとめて書く(persistNow も同じブロックで呼ぶ)。

### P5-永続化-18 / 要確認 / `src/main.ts:1115-1121`

**起動時の idbGet("handle") の遅延解決が、その間に確定した新しい fileHandle を上書きしうる**

```
void idbGet<FileSystemFileHandle | null>("handle")\n    .then((h) => {\n      // only adopt a persisted handle that matches the restored file name —\n      // a mismatch would make Ctrl+S write into the wrong file\n      if (h && h.name === fileName) fileHandle = h;\n    })
```

**症状**: この .then は世代チェックを持たず、解決時点の fileHandle を無条件に上書きする。IndexedDB の初回 open は DB 作成を伴うため数十 ms〜(ストレージ逼迫時はさらに)かかりうる。その間に saveFile が完走して同名・別ディレクトリのハンドルを確定させると(showSaveFilePicker で同じファイル名を別フォルダに保存した場合、h.name === fileName が成立する)、新しいハンドルが古いハンドルで置き換えられ、以後の Ctrl+S は元のパスへ書き込む。IndexedDB 側には persistHandle(515)が新ハンドルを書いているので、メモリと永続化の内容も食い違う。

**再現条件**: 要確認: 人間の操作速度では通常 idbGet が先に解決するため自然発生は稀。確定させるには、DevTools → Sources で main.ts:1119 にブレークポイントを置いて解決を保留したまま、(1) 保存 → 別フォルダに同じファイル名で保存 → (2) ブレークポイントを解放、の順で操作し、その後に Ctrl+S がどちらのパスへ書くかを観察すればよい。書き込み先が元のパスなら確定。

**確度**: 要確認

**検証の根拠**: The code fact is confirmed — src/main.ts:1115-1121 has no generation/epoch check and assigns fileHandle unconditionally when the name matches — but the code cannot settle reachability, and every path that could reassign fileHandle in that window requires a user gesture: openFile (524, 536) and drop (873) need a click/drop, and saveFile's showSaveFilePicker (564) needs transient activation. idbGet resolves in single-digit-to-tens of milliseconds after module evaluation, so a human cannot complete a save-as within it. Deciding observation: set a breakpoint on main.ts:1119, hold it, perform 保存 -> 別フォルダに同名で保存, release, then Ctrl+S and check via DevTools which path is written. If the write lands on the OLD path, the race is real; if the picker's handle survives, it is not.

**検証による訂正**: Add the inverse case, which is the same missing guard but with a shorter path and no debugger needed on a slow/first-run IndexedDB open: a drag-and-drop load (main.ts:857-878) is fully async — it awaits confirmDiscard and the handle promise — so a .md dropped onto the window immediately at startup can set fileHandle at 873 and then have it clobbered by the 1119 assignment if the dropped file's basename happens to equal the restored LS_NAME. Same fix (capture a generation counter before the idbGet and bail if it changed); the drop variant is worth mentioning because IDB's very first open creates the database and is measurably slower.

**影響**: 低頻度だが、成立すると「保存先を変えたはずなのに元のファイルが上書きされる」という追跡困難な事故になる。

**修正方針**: 起動時に世代カウンタ(または handleAdopted フラグ)を持ち、.then の中で「その後 fileHandle が一度も変更されていない」ことを確認してからのみ代入する。

### 反証により除外(1 件)

- **persistNow が 250ms ごとに文書全体を同期 setItem する(メインスレッドを塞ぐ)** — The timing claim is contradicted by src/main.ts:110-113: `function schedulePersist() { if (persistTimer !== -1) window.clearTimeout(persistTimer); persistTimer = window.setTimeout(persistNow, 250); }`. This is a RESETTING trailing debounce, and applySnap calls it on every snapshot (main.ts:203), so every keystroke cancels the pending timer. During continuous input faster than one edit per 250ms, persistNow NEVER runs; it runs once, 250ms after typing stops. persistNow is otherwise reachable only from the pagehide handler (115). The repro's step 4 ("Main トラックで 250ms 間隔に現れる Long Task") will therefore not show what it claims — you would see at most one setItem per typing pause.

---

## 8. エクスポート・インポート・貼り付け（SVG/WebP 書き出し、クリップボード copy/cut/paste、ファイル open/save 往復、画像保存、ドラッグ&ドロップ）

**調べたもの**

- src/main.ts 全1136行を精読（exportMap / downloadBlob / saveFile / openFile / drop / paste / pasteImage / saveImageToDisk / insertContentLine / loadText / boot 復元）
- src/mindmap.ts 全1815行を Read ツールで精読（NUL バイト回避）。特に exportSvg(778-868)、render() のカード行生成(313-379, 616-726)、clipLabel、measure キャッシュ
- src/relevel.ts 全55行、src/popup.ts 全237行を精読
- 裏取りのため src/coreApi.ts、src/editor.ts、index.html、src/style.css、core/parser.mbt、core/doc.mbt、core/cmds.mbt、core/api.mbt も精読
- exportSvg の .selected/.drop-child/.dragging 一時除去→復元が await をまたがない同期区間で完結している（794-831 → 833 の fetch は復元後）ことを確認 → 問題なし
- exportSvg 後に外部参照が残らないことを確認：残る href は data: URL（inline svg カード, mindmap.ts:656）と埋め込み済み data URL のみ。http(s) 参照はゼロ（parseImage がスキーム付きパスを弾く, mindmap.ts:148）
- エッジのベジェ制御点 q が始点 a と終点 z の張る矩形の外に出ないこと（mindmap.ts:574-577）を確認 → M=24 の余白でストロークははみ出さない
- マップペインを非表示（.pane-off = display:none）にしたままの書き出しを確認 → boxes は applySnap ごとの render() で常に最新なので書き出し自体は成立する
- relevel の fence 判定（relevel.ts:12-29）と core/parser.mbt の fence_open/fence_close_len（179-237）の規則が一致していることを1つずつ照合 → バッククォート info string、~ フェンス、先頭3スペース、閉じフェンス長すべて一致
- WebP 失敗時の PNG フォールバック（main.ts:1049-1057）と popup.ts:224-227 の toDataURL フォールバックは型判定が正しい
- saveFile(FS API) の createWritable() は既定で truncate されるので旧内容の残骸が末尾に残ることはない
- 画像パスのキャッシュキー整合：saveImageToDisk が返す relPath（"./" なし）と parseImage の "./" 除去（mindmap.ts:149）が一致
- 画像名の ".." と [\\:*?\"<>|] は拒否され、先頭 "/" も segs のフィルタで許可フォルダ内に閉じ込められる（脱出パスなし）
- drop で DataTransferItem のハンドル取得を await 前に同期で掴んでいる点（main.ts:863-869）は正しい
- md ペインへの通常ペーストは CodeMirror が \r を正規化して LF で core に渡すため、そこからは追加のずれは生じない

### P5-エクスポート-1 / CONFIRMED / `src/main.ts:479`

**CRLF ファイルを開くと md ペインと core のオフセットがずれ、最初の1文字入力で本文が壊れる**

```
editor.setText(text);
```

**症状**: CodeMirror 6 は EditorState.lineSeparator が未設定（src/editor.ts:96-104 に設定なし）だと入力文字列を /\r\n?|\n/ で分割して保持するため、setText に CRLF テキストを渡すと \r が全部落ちる。一方 core は init_doc(text) に生の CRLF を保持する（core/api.mbt:99-111、core/cmds.mbt:39-46 の nl() が示す通り core は CRLF を前提に作られている）。結果、2行目以降のすべてのオフセットが「それまでの CRLF 数」だけ食い違う。ずれたまま md ペインで1文字打つと onUserEdits が CM 側オフセットのまま core.replaceText に渡す（main.ts:296）ので、core のテキストの見当違いの位置に文字が入る。逆にマップ側コマンドの editSets（core は \r\n を挿入）を CM に流すと CM は 1 文字として取り込むので、さらにずれが広がる。

**再現条件**: 1) Windows で CRLF の .md を用意する（例: `# a`,空行,`## b` の3行を Notepad か Set-Content で保存＝既定で CRLF）。2) mmm で「開く」からそれを開く。3) md ペインの `## b` の行末（b の直後）をクリックして `X` と入力。4) 期待は `## bX` だが、実際は core 側テキストが `#X# b` のように前方にずれて書き換わり、マップから `b` ノードが消える（`#X` は `^(#+)\s` を満たさず見出しでなくなるため）。5) そのまま Ctrl+S すると壊れたテキストがファイルに書かれる。

**確度**: 確定

**検証の根拠**: src/editor.ts:96-104 の extensions に EditorState.lineSeparator は無く、node_modules/@codemirror/state/dist/index.js:608 の DefaultSplit = /\r\n?|\n/ が index.js:972(ChangeSet 経由の insert)と :2761(EditorState.create)で使われるため setText の \r は必ず落ちる。一方 src/main.ts:478-479 は同じ生テキストを core.initDoc にも渡し、core/api.mbt:99 の `st.text = text` は CRLF をそのまま保持する。core/parser.mbt:19-27 の scan_lines も next = i+1 で \r を数えるので、2行目以降のオフセットは「それまでの CRLF 数」だけ食い違う。main.ts:296 は CM 側オフセットをそのまま core.replaceText に渡す。

**検証による訂正**: 機構は正しいが結果の文字列が違う。`# a␍␊␍␊## b␍␊` の場合 CM 側の b の直後は offset 9、core の index 9 は `## b` の '#' と ' ' の間ではなく「2つ目の # の直後（空白の位置）」なので、挿入結果は `#X# b` ではなく `##X b` になる。`^(#+)\s` を満たさなくなって b ノードが消える、という帰結は変わらない。ずれ幅は「先行する CRLF の個数」で、行が進むほど大きくなる。

**影響**: CRLF の既存 .md を開いて編集すると無音でファイルが破損する。Windows 由来の md はほぼ CRLF なので影響範囲が広い。ハイライト（main.ts:216 の n.hs/n.subEnd）と reveal も同じ理由で2行目以降ずれる。

**修正方針**: editor.ts の EditorState.create に `EditorState.lineSeparator.of("\n")` を入れるだけでは不十分（\r が消える事実は変わらない）。loadText で `text.replace(/\r\n/g, "\n")` して core と CM の両方を LF に統一し、保存時に元の改行種を復元するか、CRLF を一切保持しない方針にする。

### P5-エクスポート-2 / CONFIRMED / `src/main.ts:378`

**非表示（コメントアウト）ノードのカット/コピーで <!-- と --> の対が割れ、以降の文書全体が非表示化する**

```
if (cut) host.deleteSelection();
```

**症状**: cmd_toggle_hidden は `<!--\n` をノードの hs の手前に、`-->\n` を sub_end に挿入する（core/cmds.mbt:678-679）。挿入後ノードの hs は `<!--` 行の「後ろ」を指すので、ノードの範囲 [hs, sub_end) には閉じ側 `-->` だけが入り、開き側 `<!--` は入らない。selection_text も cmd_delete もこの範囲で切るため（core/cmds.mbt:603、同 281）、カットすると文書側に `<!--` が孤立し、コピー先には `-->` だけが紛れ込む。孤立した `<!--` は閉じられないので scan_doc が (open, -1, -1) の未閉領域を作り（core/parser.mbt:129-131）、それ以降の見出しが全部 hidden 扱いになる。外部の Markdown レンダラから見ても以降が丸ごと HTML コメントになる。

**再現条件**: 1) `# r` / 空行 / `## a` / 空行 / `## b` の文書を作る。2) マップで `## a` を選び Shift+H で非表示にする（md ペインに `<!--` と `-->` が出る）。3) `## a` を選んだまま Ctrl+X。4) md ペインを見ると `<!--` 行だけが残り `-->` が消えている。マップでは `## b` が薄いダッシュ枠（hidden）になる。5) 別ノードを選んで Ctrl+V すると、貼り付いたノードの本文に `-->` という行が混入している。

**確度**: 確定

**検証の根拠**: core/cmds.mbt:678 が `<!--`+eol を nd.hs に、:679 が close を nd.sub_end に挿入する。core/parser.mbt:88-92 はマーカー行を continue で読み飛ばすので再構築後のノード hs は `<!--` 行の「後ろ」、sub_end は core/doc.mbt:309-317 の規則で次の同深さ以下見出しの hs＝`-->` 行より後ろ。よって [hs, sub_end) には `-->` だけが入る。selection_text(core/cmds.mbt:603) も cmd_delete(core/cmds.mbt:281) も同じ範囲を使う。孤立した `<!--` は core/parser.mbt:129-131 で (open,-1,-1) の未閉領域になり、以降の見出しは parser.mbt:125 の `hidden: in_comment` で全部 hidden になる。cmds.mbt:105-129 の tidy_del_start も '-' で止まるので `<!--` は救われない。

**影響**: 非表示ノードを1回カットしただけで、その後ろの全ノードが非表示になり、保存した .md も GitHub 等では以降が丸ごとコメントとして消える。混入した孤立 `-->` は、後で別のノードを非表示にしたときにその領域を早期に閉じるので二次被害も出る。既知の F-005 と同型（範囲と構造の不一致）だが対象は <!-- --> マーカーで、帰結（文書全体の非表示化・コメント化）は新しい。

**修正方針**: selection_text / cmd_delete がノード範囲を取るときに、hide_regions の開きマーカーが hs の直前にある場合はそれも範囲に含める（もしくは範囲末尾の閉じマーカーを除外する）。少なくとも対で扱う。

### P5-エクスポート-3 / CONFIRMED / `src/main.ts:402`

**見出しを含まないクリップボードは無言で捨てられる（他ツールの箇条書き mindmap が一切貼れない）**

```
if (!hasHeadings(normalized)) return; // fence-aware, matches relevel
```

**症状**: scanDepths は `^(#+)[ \t]` の ATX 見出ししか見ない（relevel.ts:27）。箇条書き（- / *）、番号付き、setext 見出し（下線 === / ---）、インデント階層のいずれも見出し扱いされないので hasHeadings が false になり、paste は何のフィードバックもなく return する。Workflowy / Dynalist / Obsidian のアウトライン、MindNode や XMind の Markdown 書き出しはほぼ箇条書きなので、そのまま貼ると「何も起きない」。

**再現条件**: 1) 別アプリで `- 親\n  - 子1\n  - 子2` をコピー。2) mmm のマップで任意のノードを選び Ctrl+V。3) 何も起きず、トーストもコンソール出力も出ない。4) 同様に `タイトル\n=====`（setext）でも何も起きない。

**確度**: 確定

**検証の根拠**: src/main.ts:402 の `if (!hasHeadings(normalized)) return;` は src/relevel.ts:27 の `^(#+)[ \t]` しか見ず、paste 経路には flashFilename も console も一切無い（main.ts:380-423）。

**検証による訂正**: 「他ツールから持ってくる導線が事実上存在しない」は言い過ぎ。md ペイン側は CodeMirror の標準ペーストが効き、src/editor.ts:113-141 経由で本文としては入る（ただし箇条書きは core/parser.mbt:1-3 の ATX 見出し専用仕様上ノードにはならない）。実際の欠陥は「マップペインの Ctrl+V が無反応で終わり、理由が一切表示されない」ことに限定される。

**影響**: 「他ツールから持ってくる」導線が事実上存在せず、しかも失敗が可視化されないのでユーザーはアプリのバグかクリップボードの問題か切り分けられない。

**修正方針**: 最低限 flashFilename("見出しのないテキストは貼り付けられません") を出す。可能なら箇条書きのインデント深さ→見出し深さ変換と setext 検出を relevel に足す。

### P5-エクスポート-4 / CONFIRMED / `src/main.ts:423`

**貼り付けの失敗が全経路で無音（権限拒否・非セキュアオリジン・未選択・空クリップボード）**

```
})().catch(() => {});
```

**症状**: paste() の非同期本体は最後の .catch(() => {}) で全例外を握り潰す。navigator.clipboard.readText() の権限拒否、Firefox の貼り付け確認をキャンセルした場合、非セキュアオリジンで navigator.clipboard が undefined の場合、いずれも無音。さらに冒頭の `if (anchorId === -1 && nodes.length > 0) return;`（main.ts:383）で「何も選択していない状態の Ctrl+V」も無音、`if (!clip.trim()) return;`（400）で空クリップボードも無音、画像経路は hasFs 前提（387）なので Firefox で画像を貼ると readText が空文字を返して無音で終わる。

**再現条件**: 1) Chrome でマップペインにフォーカスして Ctrl+V → クリップボード読み取り許可のダイアログで「ブロック」を選ぶ。2) 以後 Ctrl+V を押しても永久に何も起きず、理由もどこにも出ない。3) 何も選択せずに Ctrl+V しても同じ。

**確度**: 確定

**検証の根拠**: src/main.ts:423 の `.catch(() => {})` が async IIFE 全体の例外を吸う。navigator.clipboard が undefined なら main.ts:387 の `"read" in navigator.clipboard` が投げて main.ts:396 の内側 catch に、main.ts:399 の readText() の reject は外側 .catch に落ちる。加えて main.ts:383 の未選択 return、main.ts:400 の空クリップ return、main.ts:387 の hasFs 前提のいずれもユーザーへの通知が無い（この関数内に flashFilename の呼び出しが 1 つも無い）。

**影響**: 貼り付けが動かない状態からユーザーが自力で復帰できない。原因（権限・選択なし・非対応形式）が4種類あるのに全部同じ「無反応」に潰れている。

**修正方針**: catch で err.name を見て flashFilename に出し分ける。anchorId === -1 と空クリップボードも個別にメッセージを出す。

### P5-エクスポート-5 / CONFIRMED / `src/main.ts:377`

**カットはクリップボード書き込みの成否を待たずに削除する**

```
void navigator.clipboard.writeText(text).catch(() => {});
```

**症状**: writeText の Promise を await せず、失敗も握り潰したうえで次行 `if (cut) host.deleteSelection();` が即座に走る。書き込みが拒否された（ドキュメント非フォーカス、Firefox のジェスチャ要件、権限拒否）場合でもノードは消え、クリップボードには何も入らない。

**再現条件**: 1) マップでノードを選ぶ。2) OS の別ウィンドウにフォーカスを移すなどして document.hasFocus() を false にできる状況（例: DevTools を別ウィンドウに切り離してそちらにフォーカス）を作り、コンテキストメニューの「カット」を実行する。3) ノードは削除されるが、他アプリに貼り付けても中身は前のクリップボード内容のまま。

**確度**: 確定

**検証の根拠**: src/main.ts:376-378 が `void navigator.clipboard.writeText(text).catch(() => {})` の直後に無条件で `if (cut) host.deleteSelection();` を実行しており、await も成否分岐も無い。

**検証による訂正**: 再現手順が成立しにくい。コンテキストメニューの「カット」を押す時点でドキュメントはフォーカスされているので document.hasFocus() は true になりやすく、DevTools を切り離しただけでは NotAllowedError を安定して起こせない。コードレベルの欠陥（未 await・例外握り潰し・無条件削除）は無条件に存在する、という形に留めるべき。なお非セキュアオリジンでは main.ts:377 が同期 TypeError を投げるため削除自体が走らない（#33 参照）ので、実際にデータが消えるのは「clipboard は存在するが writeText が reject する」場合に限られる。

**影響**: 「切り取り」したのに切り取れておらず、元も消える。Undo で戻せるが、他アプリに貼りに行ってから気づくため実質データ消失に見える。

**修正方針**: await writeText() を成功させてから deleteSelection() を呼ぶ。失敗時は削除せず flashFilename でエラーを出す。

### P5-エクスポート-6 / CONFIRMED / `src/main.ts:419`

**CRLF 文書では貼り付け・コンテンツ追加のたびに空行が1行ずつ増える**

```
else if (at >= 2 && text[at - 2] !== "\n") prefix = "\n";
```

**症状**: 挿入位置の直前が空行かどうかを text[at-2] === "\n" で判定しているが、CRLF 文書では text[at-2] は "\r" なので、すでに空行があっても「空行なし」と誤判定して余分な "\n" を足す。insertContentLine（main.ts:733）にも同じ式があるので、リンク(L)・コード(Shift+C)・お絵描き(Shift+D)・画像貼り付けでも起きる。core 側の同等判定 preceded_by_blank は \r を正しく飛ばしている（core/cmds.mbt:51-67）ので、JS 側だけ規則が違う。

**再現条件**: 1) CRLF の .md を開く。2) ノードを選んで L でリンクを追加、を2〜3回繰り返す。3) md ペインでその位置に空行が1回ごとに1行ずつ増えていくのが見える（core 経由の addChild では増えない）。

**確度**: 確定

**検証の根拠**: src/main.ts:419（paste）と src/main.ts:733（insertContentLine）の `text[at - 2] !== "\n"` は CRLF の空行では text[at-2] が "\r" になるため必ず真になり、余分な "\n" を足す。core 側の同等判定 core/cmds.mbt:51-67 preceded_by_blank は cc(p-1)==13 を明示的に飛ばしており規則が食い違う。

**検証による訂正**: 「毎回1行ずつ増える（単調増加）」は誤り。挿入される区切りは LF なので、1回目で `\r\n\r\n` 境界が `\n\n` に置き換わり、同じ位置への2回目は text[at-2] が "\n" になって余分な改行を足さない。実際に食い違うのは「挿入点の直前が CRLF の空行のとき1回だけ」で、典型例は『次の兄弟見出しを持つノードにコンテンツを足す』ケース（at = 次見出しの hs）。findings が挙げた「末尾ノードに L を繰り返す」再現は at が EOF になり core の preceded_by_blank も false を返すので、この例では JS と core は一致し余分な空行は出ない。

**影響**: CRLF 文書で編集するたびに空行が単調増加し、git diff が汚れる。上の CRLF 不整合の findings と合わせると CRLF 文書はまともに扱えない。

**修正方針**: 判定を core と同じく \r を読み飛ばす形にする（正規表現 /\n[ \t]*\r?\n$/ 相当）。あるいは文書全体を LF に正規化する方針にする。

### P5-エクスポート-7 / CONFIRMED / `src/relevel.ts:54`

**貼り付けは常に LF を挿入するので CRLF 文書の改行が混在する**

```
.join("\n");
```

**症状**: paste は clip を `clip.replace(/\r\n/g, "\n")` で LF 化し（main.ts:401）、relevel も /\r?\n/ で split して "\n" で join する。core は nl() で文書の改行種を尊重して CRLF を挿入する（core/cmds.mbt:39-46）のに、貼り付けだけが LF を書き込むので、同じファイル内に CRLF 行と LF 行が混ざる。

**再現条件**: 1) CRLF の .md を開く。2) ノードをコピーし、別ノードに貼り付ける。3) 保存して外部エディタ（VS Code など）で開くと「Mixed」改行として表示される。git でも eol 警告や差分ノイズが出る。

**確度**: 確定

**検証の根拠**: src/main.ts:401 が clip を LF 化し、src/relevel.ts:41,54 が /\r?\n/ で split して "\n" で join、main.ts:416-420 の prefix/suffix も "\n" 固定。core は core/cmds.mbt:39-46 の nl() で文書の改行種（CRLF）を尊重して挿入するため、貼り付け部分だけが LF になる。relevel.ts:45,47 の早期 return も既に LF 化済みの文字列を返すので抜け道は無い。

**影響**: 保存ファイルの改行が壊れる。CRLF を前提にした後段ツール（一部の Windows 製ツール、diff、外部レンダラ）で不整合が出る。

**修正方針**: relevel の join を呼び出し側から改行種を受け取る形にするか、貼り付け直前に core の改行種へ再変換する。

### P5-エクスポート-8 / CONFIRMED / `src/relevel.ts:44`

**複数選択のコピー→貼り付けで、無関係な兄弟が親子関係に変わる**

```
for (const d of depths) if (d > 0 && d < minDepth) minDepth = d;
```

**症状**: selection_text は選択された各サブツリーを元の深さのまま連結する（core/cmds.mbt:597-618）。relevel はクリップ全体の最小深さだけを targetDepth に合わせ、それ以外は相対深さのままずらす（relevel.ts:46,52）。したがって深さの違う独立ノードを複数選択してコピーすると、貼り付け後は深い方が浅い方の子孫として入る。

**再現条件**: 1) `# r` / `## a` / `## b` / `### b1` / `#### b1a` という文書を作る。2) マップで `## a` と `#### b1a` を Ctrl+クリックで両方選択し Ctrl+C。3) `## b` を選んで Ctrl+V。4) 貼り付け結果は `### a` の配下に `##### b1a` がぶら下がる。元は互いに無関係な別枝だったのに親子になっている。

**確度**: 確定

**検証の根拠**: core/cmds.mbt:597-618 selection_text は各サブツリーを元の深さのまま連結する（core/doc.mbt:502-527 normalize_selection は範囲包含のみを落とすので別枝の `## a` と `#### b1a` は両方残る）。src/relevel.ts:43-52 はクリップ全体の最小深さ 1 つだけを targetDepth に合わせ、他の行は相対深さのままずらす。よって `## a`(2) と `#### b1a`(4) は `### a`(3) と `##### b1a`(5) になり、core/doc.mbt:472-486 recompute_parents で b1a が a の子孫として再構成される。

**影響**: 複数選択コピーが「選択した構造をそのまま複製する」という期待を裏切り、往復で構造が変わる。ユーザーは貼り付け後に手で解体する必要がある。

**修正方針**: selection_text 側で各サブツリーの深さを正規化（各ブロックの根を同じ深さに揃える）してから連結するか、relevel をブロック単位で適用する。

### P5-エクスポート-9 / CONFIRMED / `core/cmds.mbt:603`

**グループ末尾ノードのコピーには次の兄弟に属する --- が混入し、貼り付けで無関係な兄弟がグループ移動する**

```
let mut block = sub(st.text, nd.hs, nd.sub_end)
```

**症状**: ノードの sub_end は「次の同深さ以下の見出しの hs」なので、そのノードと次の兄弟の間にある `---` セパレータ行はノードの範囲に入る。selection_text は末尾改行しか落とさないので、コピー結果の末尾に `---` が残る。貼り付け時は body の後ろに "\n" と suffix "\n" が付く（main.ts:417-420）ため、その `---` が挿入位置直後の見出しの真上に空行を挟んで並び、rebuild_nodes のグループ判定（core/doc.mbt:266-276）で新しいセパレータとして採用される。

**再現条件**: 1) `# r` / `## a` / 空行 / `text` / 空行 / `## b` / 空行 / `---` / 空行 / `## c` を作る。この時点で a と b は group 0（マップ右側）、c は group 1（左側）。2) `## b` を選んで Ctrl+C（クリップボードは `## b` と `---`）。3) `## a` を選んで Ctrl+V。4) 貼り付いた `### b` の直後の `---` が元の `## b` の真上に来るため、`## b` が group 1 に落ちてマップの右側から左側へ移動する。貼り付けたつもりのない兄弟のレイアウトが変わる。

**確度**: 確定

**検証の根拠**: core/doc.mbt:309-317 で sub_end は次の同深さ以下見出しの hs なので `## b` と `## c` の間の `---` 行は `## b` の範囲に入り、core/cmds.mbt:603-610 は末尾の改行しか削らないのでコピー結果末尾に `---` が残る。貼り付けは src/main.ts:416-421 で body+"\n"+suffix"\n" を anchor.subEnd（＝`## b` の hs）に入れるため、その `---` が `## b` の直上に空行を挟んで並ぶ。core/doc.mbt:266-276 は「空行のみを挟んで見出しの直上にある ---」をセパレータとして採用し、core/doc.mbt:339-388 compute_groups が `## b` の raw group を +1 する。結果 `## b` は group 0→1 になり、src/mindmap.ts:512-516,539-540 の規則で右側から左側へ移動する。

**影響**: コピー&ペーストが選択していないノードのグループ（＝マップの左右配置）を書き換える。既知 F-005 と同じ「範囲と構造の不一致」ファミリだが、対象が --- セパレータで、帰結（無関係な兄弟のグループ移動）は新しい。

**修正方針**: selection_text でブロック末尾の空行＋`---` を落とす（次の見出しに属するセパレータはコピー対象外にする）。

### P5-エクスポート-10 / CONFIRMED / `src/relevel.ts:52`

**深いノードへの貼り付けで 7 個以上の # を生成し、他の Markdown ツールでは見出しでなくなる**

```
return "#".repeat(Math.max(1, d + delta)) + line.slice(d);
```

**症状**: relevel は上限クランプを持たない（下限 1 のみ）。core は深さ無制限を仕様としている（core/parser.mbt:2-3 のコメント）ので mmm 内では動くが、CommonMark / GitHub は `#######` を見出しと認めず段落として描画する。深さ6のノードに貼れば即座に7が出る。

**再現条件**: 1) `# 1` → Tab で子を5回作り深さ6のノードを作る。2) 適当なノードをコピーして深さ6のノードに Ctrl+V。3) md ペインに `####### ...` が現れる。4) その .md を保存して GitHub にプッシュすると、その行は見出しではなくただの本文として表示される。

**確度**: 確定

**検証の根拠**: src/relevel.ts:52 は `Math.max(1, d + delta)` で下限しか持たず上限クランプが無い。core/parser.mbt:1-3 のコメント通り core 側は深さ無制限なので mmm 内では通ってしまう。

**検証による訂正**: 再現手順が1点不正確。addChild 後は src/main.ts:315 → mindmap.ts:899 でラベル編集に入り、mindmap.ts:1280-1288 の editor keydown が Tab を stopPropagation+preventDefault するので Tab 連打では深くならない。各 Tab の後に Enter（コミット）を挟む必要がある。生成される `#######` 自体の指摘は正しい。

**影響**: 「実体は .md ファイルで git に乗る」という本アプリの前提に対し、貼り付け操作だけで外部ツールから見て壊れた md が作られる。警告もない。

**修正方針**: 深さ6を超える貼り付けは警告を出すか、7 以上になる場合は貼り付け先の深さを繰り上げる／クランプして相対構造を潰さない方針を明示する。

### P5-エクスポート-11 / CONFIRMED / `src/main.ts:421`

**貼り付けたテキストに閉じられない <!-- が含まれると、以降の文書全体が非表示になる**

```
const snap = core.replaceText(at, at, prefix + body + suffix, "");
```

**症状**: paste は hasHeadings しか検査せず、HTML コメントの整合性は見ない。core 側は「行全体がちょうど `<!--`」で hide 領域を開き、「行全体がちょうど `-->`」でしか閉じない（core/parser.mbt:88-98, is_marker_line 137-147）。他ツールの md によくある `<!--` 単独行 + `本文 -->` のような閉じ方だと閉じマーカーとして認識されず、未閉領域として EOF まで伸びる（core/parser.mbt:129-131）ため、貼り付け位置以降の全見出しが hidden になる。

**再現条件**: 1) 外部で次の3行をコピー: `<!--` / `# メモ` / `draft -->`（3行目の `-->` の前に文字がある）。2) mmm のマップでノードを選んで Ctrl+V。3) 貼り付け位置以降のノードが全部半透明＋破線（hidden）になり、md を外部レンダラで見ると以降が丸ごとコメントとして消える。

**確度**: 確定

**検証の根拠**: src/main.ts:402 の検査は hasHeadings のみで、コメントの整合性は見ない。core/parser.mbt:88-98 は core/parser.mbt:137-147 is_marker_line（トリム後が「ちょうど」`<!--` / `-->`）でしか開閉しないため `draft -->` は閉じマーカーにならず、core/parser.mbt:129-131 で (open,-1,-1) の未閉領域になる。以降の見出しは core/parser.mbt:125 の `hidden: in_comment` で全部 hidden になり、src/mindmap.ts:590 の hidden-node クラス＋style.css:252-253 で半透明・破線になる。

**影響**: 外部からコピーした一般的な md を貼るだけで文書の後半が丸ごと無効化される。Undo で戻せるが、気づかず保存すると外部から見て内容が消えた .md になる。

**修正方針**: 貼り付け前に body 内の `<!--`/`-->` マーカー行の対応を検査し、不整合なら警告するか、貼り付けブロックの末尾で必ず閉じる。

### P5-エクスポート-12 / CONFIRMED / `src/mindmap.ts:803`

**SVG/WebP 書き出しでコード行のインデントと連続スペースが潰れる**

```
const PROPS = [
```

**症状**: インライン化するプロパティ一覧に white-space が入っていない。style.css では `.node text.label`（131-138）と `.node text.code-line`（239-246）に `white-space: pre` が指定されているが、書き出した SVG は自前の CSS を一切持たないため既定の空白圧縮が適用され、行頭の空白が消えて連続空白が1個に潰れる。

**再現条件**: 1) ノードを選んで Shift+C でコードポップアップを開き、`def f():` 改行 `    return 1` を入力して確定。2) マップ上ではインデント付きで表示される。3) ツールバーの SVG を押してダウンロードし、その .svg をブラウザで開く。4) `return 1` の行頭4スペースが消えて左端に寄っている。WebP でも同様（同じ SVG をラスタライズしているため）。

**確度**: 確定

**検証の根拠**: src/mindmap.ts:803-815 の PROPS に white-space が無く、src/mindmap.ts:823 の `copy.removeAttribute("class")` でクラスも落ちるため、書き出した SVG には src/style.css:137（.node text.label）と :244（.node text.code-line）の `white-space: pre` が一切残らない。コード行の textContent は src/mindmap.ts:343 で raw 行（インデント込み、タブは2スペース化）を保持し src/mindmap.ts:684 でそのまま入る。箱幅は src/mindmap.ts:403-405 でインデント込みの measure から決まるので、幅だけ残って中身が左詰めになる。WebP は src/main.ts:1027-1039 で同じ SVG を <img> 経由でラスタライズするので同症状。

**影響**: コードブロックを載せたマップの書き出しが常に崩れる。ノードの箱幅はインデント込みで計測されている（mindmap.ts:404）ので、余白だけが残った不格好な絵になる。

**修正方針**: PROPS に "white-space" を追加するか、書き出し時に text 要素へ xml:space="preserve" を付ける。

### P5-エクスポート-13 / CONFIRMED / `src/mindmap.ts:809`

**書き出した SVG はフォントを持たないので他環境で文字が箱からはみ出す**

```
"font-family",
```

**症状**: インライン化されるのは font-family の「名前の列挙」だけで、フォント自体は埋め込まれない。しかも箱の幅・ラベルの省略位置は canvas measureText を `13px "Segoe UI", "Hiragino Sans", "Noto Sans JP", Meiryo, sans-serif`（mindmap.ts:96-103）で測った値に固定されている（widthOf 393-414、clipLabel 731-744）。これらのフォントが無い環境で開くと代替フォントの字幅が違い、文字が箱をはみ出す／余白が空く。

**再現条件**: 1) Windows の mmm で日本語ラベルのマップを SVG 書き出しする。2) その .svg を macOS か Linux のブラウザ（Segoe UI / Meiryo なし）で開く。3) ラベルがノード矩形の右端を突き抜ける、または `…` で切った位置と実際の描画幅が合わない。

**確度**: 確定

**検証の根拠**: src/mindmap.ts:809 の PROPS は font-family（名前列挙）と font-size を写すだけで、@font-face もフォントバイト列も埋め込まない（exportSvg 全体 src/mindmap.ts:778-868 に埋め込み処理は画像のみ）。一方で箱幅は src/mindmap.ts:393-414 widthOf、省略位置は src/mindmap.ts:731-744 clipLabel が src/mindmap.ts:96-103 の固定フォント指定で測った canvas measureText 値に焼き付けられている。よって同じフォントが無い環境では実描画幅と幾何が一致しない。

**検証による訂正**: コード上の機構（フォント非埋め込み＋ローカル計測ジオメトリの固定）は確定だが、実際にどれだけはみ出すかは受け手のフォント代替に依存する。なお font-family には "Hiragino Sans" / "Noto Sans JP" も含まれるため macOS/多くの Linux では近い代替が当たることも多く、常に崩れるとまでは言えない。

**影響**: 「書き出して共有する」という用途で、受け取り側の環境次第で絵が崩れる。ラスタライズ（WebP）は書き出した本人の環境で行われるのでこちらは無事、という非対称も分かりにくい。

**修正方針**: 書き出し SVG に汎用スタックへのフォールバックを明示する（font-family を sans-serif 主体にする）か、テキストをパス化する、あるいは WebP を共有用の既定にする旨を UI で示す。

### P5-エクスポート-14 / CONFIRMED / `src/mindmap.ts:796`

**非表示（コメントアウト）ノードと切り離された別ツリーも書き出しに含まれ、余白まで確保される**

```
".selected, .drop-child, .dragging",
```

**症状**: 書き出し前に除去されるのは選択・ドロップ・ドラッグの一時状態だけで、hidden-node は除去されない。バウンディングボックスも this.boxes 全件から計算する（mindmap.ts:780-789）ので、非表示ノードやルートより前に書かれた見出しから生えた別ツリー（mindmap.ts:542-554 でルートの下に積まれる）も画像に入り、その分だけ余白と画像サイズが増える。

**再現条件**: 1) ある枝を選んで Shift+H で非表示にする。2) ツールバーの SVG または WebP を押す。3) 書き出した画像に、非表示にした枝が半透明・破線のまま残っている（style.css:252-253 の opacity 0.45 は PROPS に含まれるので忠実に再現される）。

**確度**: 確定

**検証の根拠**: src/mindmap.ts:795-800 が剥がすのは .selected / .drop-child / .dragging のみで hidden-node は残る。src/mindmap.ts:816-828 の inline() は PROPS に opacity と stroke-dasharray を含むので style.css:252-253 の見た目がそのまま焼き込まれる。バウンディングボックスは src/mindmap.ts:784-789 で this.boxes 全件から取るため、src/mindmap.ts:542-554 でルートの下に積まれる別ツリーも含まれ、ROOT_GAP*2 の空白も画像に入る。

**検証による訂正**: 「使い方ができない」は設計判断寄り。非表示は core/cmds.mbt:621-625 のコメント通り「外部レンダラから見えなくする」機能であって描画から外す機能とは定義されていないので、仕様上の欠落というより export に除外オプションが無い、という指摘に読み替えるのが正確。

**影響**: 「見せたくない枝を隠してから書き出す」という自然な使い方ができない。別ツリーがある文書では主ツリーが縮小されて読めなくなる。

**修正方針**: exportSvg に「非表示ノードを含めるか」の分岐を設け、除外する場合は該当 g 要素を削除したうえでバウンディングボックスを再計算する。

### P5-エクスポート-15 / CONFIRMED / `src/mindmap.ts:689`

**サムネイル未読み込みの画像は、プレースホルダのままエクスポートされる**

```
const url = this.host.imageUrl(r.path);
```

**症状**: imageUrl が null（フォルダ権限が未取得、IndexedDB からのハンドル復元前、ファイル欠損）の間、render は破線矩形＋ファイル名テキストを描く（mindmap.ts:700-721）。exportSvg は nodeLayer をそのままクローンするだけなので、この状態で書き出すと画像の代わりに破線の枠とファイル名が焼き込まれる。埋め込み処理（833-848）は href が blob: のものしか対象にしないため、プレースホルダは何も救われない。

**再現条件**: 1) 画像を含む .md を開き直す（リロード直後、フォルダ権限の再取得前）。2) マップに破線の枠＋ファイル名が出ている状態で、どこもクリックせずにツールバーの SVG を押す。3) 書き出した SVG に画像ではなく破線プレースホルダが入っている。

**確度**: 確定

**検証の根拠**: src/mindmap.ts:689-721 は imageUrl が null の間 rect.img-ph + text.img-name を描く。src/mindmap.ts:801-802 の exportSvg は nodeLayer をそのまま cloneNode するだけで、src/mindmap.ts:833-848 の埋め込みは `href` が blob: で始まるものしか対象にしないためプレースホルダは救われない。src/main.ts:687-701 の unlockAssets は pointerdown で非同期に権限を取りに行くが、export は同じクリックの中で同期的に clone するので間に合わない。

**影響**: 見た目では「まだ読み込み中」と「書き出しても大丈夫」の区別がつかないので、画像抜けに気づかないまま共有してしまう。

**修正方針**: exportSvg の冒頭で未解決の画像行があれば loadAsset を待つ、または未解決がある場合に警告を出して続行可否を確認する。

### P5-エクスポート-16 / CONFIRMED / `src/mindmap.ts:844`

**書き出した <image> は href のみで xlink:href を持たない**

```
img.setAttribute("href", dataUrl);
```

**症状**: 埋め込み後もインライン svg カード（mindmap.ts:656-659）も、SVG2 の href 属性だけを使っている。ブラウザは問題ないが、SVG1.1 前提の消費側（古い Illustrator、一部の変換ツール、librsvg の古い版）は xlink:href しか見ないので画像が空になる。

**再現条件**: 要確認: 画像行を含むマップを SVG 書き出しし、Illustrator や `rsvg-convert` などブラウザ以外のツールで開いて画像が出るか確認する。ブラウザで開くだけでは判別できない。

**確度**: 確定

**検証の根拠**: src/mindmap.ts:844（埋め込み後）、:656-659（インライン svg カード）、:698（サムネイル）のいずれも setAttribute("href", …) だけで xlink:href を設定せず、src/mindmap.ts:849-854 の出力ルートも xmlns:xlink を宣言しない。

**検証による訂正**: タイトルの主張（href のみ）はコードで確定。ただし「Illustrator / librsvg 等で画像が消える」という帰結はリポジトリ内では判定できないので、影響部分は要確認（rsvg-convert 等での実測が必要）。

**影響**: ブラウザ以外へ持ち出したときだけ画像が消えるので、原因の切り分けが難しい。

**修正方針**: 埋め込み時に href と xlink:href（xmlns:xlink 宣言つき）を両方セットする。

### P5-エクスポート-17 / 要確認 / `src/main.ts:1035`

**巨大マップの WebP/PNG 書き出しは canvas の上限で失敗する（scale=2 固定）**

```
cv.width = img.naturalWidth * scale;
```

**症状**: 倍率は 2 固定で上限チェックがない。Chrome の canvas 上限は 1辺 65535px、面積 268,435,456px（Safari はさらに小さい）なので、マップのバウンディングボックスが 8192×8192 CSS px を超えたあたりから 2 倍した canvas が上限を超え、toBlob が null を返して `image encode failed` を投げる（main.ts:1045, 1057）。catch で「エクスポートに失敗しました」とだけ出る（1060-1063）ので、原因が大きさだと分からない。SVG 書き出し側には上限がないため、SVG は成功して WebP だけ失敗するという挙動になる。

**再現条件**: 要確認（閾値はブラウザ依存）: 数千ノード規模の文書を開き、WebP ボタンを押す。失敗するときは DevTools のコンソールに export failed が出る。決め手は書き出し直前に cv.width * cv.height を見て 268435456 を超えているかを確認すること。

**確度**: 要確認

**検証の根拠**: src/main.ts:1033-1036 に scale=2 固定と寸法チェック不在は確認できる（cv.width = img.naturalWidth * scale、上限判定なし）。src/main.ts:1049-1057 で toBlob が null を返せば `image encode failed` を投げ src/main.ts:1060-1063 の汎用文言に潰れることも確認できる。ただし実際に失敗する閾値と挙動（toBlob が null を返すのか例外か、面積上限値）はブラウザ実装依存でコードからは決まらない。決め手: 書き出し直前に cv.width * cv.height をログして 268,435,456 を超えるか、および同条件で toBlob が null になるかを DevTools で観測すること。

**影響**: 大きなマップほど画像で共有したいのに、そこだけ失敗する。エラー文言から原因が分からず、ユーザーは再試行を繰り返す。

**修正方針**: 面積・辺長の上限から scale を自動的に下げる（最低 1 まで）。それでも超える場合はメッセージに理由と実寸を出す。

### P5-エクスポート-18 / 要確認 / `src/main.ts:1046`

**画像のクリップボードコピーはクリック直後ではなく複数の await の後に実行される**

```
await navigator.clipboard.write([new ClipboardItem({ "image/png": png })]);
```

**症状**: Shift+クリックから clipboard.write までに、exportSvg（画像1枚ごとに fetch → FileReader）、img.onload、cv.toBlob と非同期処理が挟まる。ユーザー操作の一時的アクティベーションを要求する実装（Safari、Firefox）ではこの時点で権限が切れて NotAllowedError になる。Safari は ClipboardItem に Promise を渡す形（`new ClipboardItem({"image/png": promise})`）でないと通らない。

**再現条件**: 要確認: Safari または Firefox で、画像行を数枚含むマップを開き WebP ボタンを Shift+クリックする。コンソールに NotAllowedError が出て「エクスポートに失敗しました」になれば該当。Chrome では通ることが多いので Chrome だけでは判定できない。

**確度**: 要確認

**検証の根拠**: src/main.ts:1009（exportSvg、内部で src/mindmap.ts:837-843 の fetch と FileReader を await）、:1028-1032（img.onload）、:1042-1044（toBlob）を経てから src/main.ts:1046 の clipboard.write に到達する、という呼び出し順はコードで確定。しかし「一時的アクティベーションが切れて NotAllowedError になる」かは Safari/Firefox の実装依存で、リポジトリ内では判定できない。決め手: Safari か Firefox で画像行を数枚含むマップを開き WebP ボタンを Shift+クリックして NotAllowedError が出るか観測すること（Chrome では通るので Chrome 単独では判定不可）。

**影響**: Chrome でしか画像コピーが使えない。しかも失敗理由が汎用の「エクスポートに失敗しました」に潰れる。

**修正方針**: ClipboardItem に Blob の Promise を渡し、クリックと同じタスクで write を呼ぶ形に組み替える。

### P5-エクスポート-19 / 要確認 / `src/main.ts:1001`

**downloadBlob と保存フォールバックが click 直後に同期で objectURL を revoke する**

```
URL.revokeObjectURL(a.href);
```

**症状**: a.click() の直後、同じタスク内で revokeObjectURL している。ダウンロードの開始が非同期なブラウザ（Firefox が典型）では URL が先に無効化されてダウンロードが「失敗」になることが知られている。同じパターンが saveFile の File System Access 非対応フォールバック（main.ts:576-580）にもあり、そちらは本文の保存そのものなので影響が重い。アンカーが document に追加されていない点も古い実装で問題になる。

**再現条件**: 要確認: Firefox で（showSaveFilePicker が無いので保存はフォールバック経路になる）Ctrl+S を押し、ダウンロードが完了するか、あるいはダウンロードマネージャに「失敗」が出るかを見る。SVG/WebP ボタンでも同様に確認する。

**確度**: 要確認

**検証の根拠**: src/main.ts:996-1002 と src/main.ts:576-580 が a.click() の直後・同一タスク内で URL.revokeObjectURL を呼び、アンカーを document に追加していないことはコードで確定。ただし現行ブラウザで実際にダウンロードが失敗するかは実装依存（多くのブラウザは click 処理中に URL を解決するため成功する）。決め手: Firefox（showSaveFilePicker が無いので必ずフォールバック経路）で Ctrl+S と SVG/WebP ボタンを実行し、ダウンロードマネージャに「失敗」が出るかを観測すること。

**影響**: Chrome 以外で保存・書き出しが黙って失敗しうる。次項と組み合わさると「保存したつもりで保存されていない」になる。

**修正方針**: revokeObjectURL を setTimeout(…, 60_000) か 'load' 後に遅延させる。

### P5-エクスポート-20 / CONFIRMED / `src/main.ts:582`

**File System Access 非対応ブラウザでは、ダウンロードの成否に関わらず「保存済み」にしてしまう**

```
savedText = text;
```

**症状**: フォールバック経路（main.ts:575-581）は a.click() を呼ぶだけで、ユーザーが保存ダイアログをキャンセルしたか、ダウンロードが失敗したかを知る手段がない。にもかかわらず直後に savedText = text とし、updateDirty() で未保存マークを消し、LS_SAVED も更新する。beforeunload の警告（main.ts:850-853）も解除される。

**再現条件**: 1) Firefox か Safari（showOpenFilePicker 非対応）で mmm を開く。2) 何か編集して未保存の ● が出た状態にする。3) Ctrl+S を押し、ブラウザの保存ダイアログでキャンセルする。4) ● が消えて「保存済み」の見た目になる。5) タブを閉じても警告が出ない。

**確度**: 確定

**検証の根拠**: src/main.ts:575-581 のフォールバックは a.click() を呼ぶだけで成否を知る手段が無く、例外も発生しないため src/main.ts:582-589 の `savedText = text` / updateDirty() / LS_SAVED 更新が必ず実行される。src/main.ts:206-208 の未保存判定と src/main.ts:850-853 の beforeunload はどちらも savedText 比較なので、同時に解除される。

**影響**: 保存できていないのに保存済みに見え、離脱警告も出ないので編集内容を失う。localStorage には残るが、ユーザーは実ファイルが更新されたと信じている。

**修正方針**: フォールバック経路では savedText を更新せず「ダウンロードしました（保存先はブラウザのダウンロード先）」と明示する。または未保存マークを維持する。

### P5-エクスポート-21 / CONFIRMED / `src/main.ts:525`

**UTF-8 BOM 付きファイルは開く→保存の往復で BOM が消える**

```
savedText = await f.text();
```

**症状**: Blob.text() は UTF-8 decode（先頭 BOM の除去を含む）なので、BOM は読み込み時点で落ちる。保存側 `await w.write(text)`（main.ts:572）は文字列を BOM なし UTF-8 で書く。したがって BOM 付き .md を開いて Ctrl+S するだけで BOM が消える。core も savedText も BOM を知らないので、未保存マーク（main.ts:206-208）はバイト差分を検知できない。

**再現条件**: 1) PowerShell で BOM 付き UTF-8 の .md を作る（`Out-File`/`>` の既定）。2) mmm で開き、何も編集せずに Ctrl+S。3) 保存後のファイルの先頭3バイトを確認すると EF BB BF が消えている。

**確度**: 確定

**検証の根拠**: src/main.ts:525（および :535、:874 のドロップ経路）の `await f.text()` は File API 仕様の UTF-8 decode で先頭 BOM を除去する。保存側 src/main.ts:571-573 は `w.write(text)` で BOM 無し UTF-8 を書く。src/main.ts:551-552 の saveFile はダーティ判定を持たないので「無編集で Ctrl+S」でも書き込みが走り、src/main.ts:207 の比較は文字列同士なのでバイト差分を検知しない。

**影響**: BOM を前提にした Windows 側ツールチェーンで文字化けが起きる。何も編集していないのにファイルが変わるので git diff にも出る。プロジェクトの既知の PowerShell BOM 問題と直結する。

**修正方針**: 読み込み時に元データが BOM 付きだったかを ArrayBuffer で判定して保持し、保存時に復元する（もしくは BOM を落とす旨を明示する）。

### P5-エクスポート-22 / CONFIRMED / `src/main.ts:564`

**「名前を付けて保存」で別フォルダを選んでも画像の相対パスと assetUrls キャッシュが追随しない**

```
fileHandle = await window.showSaveFilePicker({
```

**症状**: saveFile が新しい fileHandle を得ても clearAssets() は呼ばれず、dirHandle も更新されない。assetSegs は `dir.resolve(fileHandle)` で md の位置を求める（main.ts:646-652）ので、新しい保存先が許可済みフォルダの外だと以後 null を返し、画像は読めなくなる。saveImageToDisk 側は base === null で許可を破棄して「この md を含むフォルダを選んでください」を出す（main.ts:764-771）。しかも `![](./x.webp)` のパスは新しい保存先の隣を指すので、コピーされていない画像は全部リンク切れになる。

**再現条件**: 1) 画像を貼った .md を、画像と同じフォルダに保存した状態にする。2) 別フォルダに「名前を付けて保存」する（fileHandle を null にしてから Ctrl+S でピッカーを出す）。3) 見た目は変わらない（objectURL がキャッシュに残っているため）。4) リロードするとサムネイルが全部プレースホルダになり、新しい保存先には画像ファイルが無い。

**確度**: 確定

**検証の根拠**: src/main.ts:563-570 で新しい fileHandle を得ても clearAssets()（src/main.ts:631-634）も dirHandle 更新も呼ばれない。src/main.ts:646-652 assetSegs は `dir.resolve(fileHandle)` に依存するので、新しい保存先が許可済みフォルダ外なら null を返し、src/main.ts:660-661 loadAsset は早期 return、src/main.ts:763-771 saveImageToDisk は許可を破棄して「この md を含むフォルダを選んでください」を出す。

**検証による訂正**: 「名前を付けて保存」という導線はアプリに存在しない（saveFile は fileHandle が null のときだけ showSaveFilePicker を出す）。到達経路は (a) 未保存文書の初回保存、(b) src/main.ts:557-561 で既存ハンドルの権限が拒否され fileHandle が null になった後、(c) リロード時に src/main.ts:1119 の名前一致条件を満たさずハンドルが復元されなかった場合、の3つ。再現手順の「fileHandle を null にしてから」は DevTools 操作前提なので、上記のいずれかに置き換える必要がある。

**影響**: 保存先を変えると画像が静かに全部壊れる。壊れたことがリロードまで分からない。

**修正方針**: 保存先が変わったら clearAssets() と dirHandle の再取得を行い、必要なら画像ファイルの移動／コピーを促す。

### P5-エクスポート-23 / CONFIRMED / `src/main.ts:860`

**.md 以外をドロップすると一切のフィードバックなく無視される**

```
if (!f || !/\.(md|markdown|txt)$/i.test(f.name)) return;
```

**症状**: window に dragover の preventDefault が張ってある（main.ts:856）のでブラウザ既定の「ドロップしたファイルを開く」も無効化されている。結果、png/jpg などの画像、フォルダ、拡張子なしファイルを落とすと、ブラウザ既定の動作もアプリの反応も何も起きない。画像を扱うアプリなのに画像ドロップが未対応であることも伝わらない。複数ファイルを落としても files[0] しか見ない。

**再現条件**: 1) mmm のウィンドウに .png を1枚ドラッグ&ドロップする。2) 何も起きない。トーストもコンソールも無し。3) フォルダを落としても同じ。

**確度**: 確定

**検証の根拠**: src/main.ts:856 の dragover で既定動作が止められ、src/main.ts:858 の drop でも preventDefault した上で src/main.ts:859-860 が files[0] のみを見て拡張子不一致なら無言 return する。この経路に flashFilename も console も無い。

**影響**: ユーザーは「壊れている」と受け取る。画像をドロップで配置したいという自然な期待が沈黙で返される。

**修正方針**: 拡張子が合わない場合に flashFilename でメッセージを出す。画像ファイルは pasteImage と同じ経路（saveImageToDisk → insertContentLine）に載せる。

### P5-エクスポート-24 / CONFIRMED / `src/main.ts:857`

**ドロップは window 全体で受けるため、ポップアップ表示中やラベル編集中でも文書を差し替える**

```
window.addEventListener("drop", (e) => {
```

**症状**: ドロップハンドラは対象要素を問わずに loadText を呼ぶ。(a) コード/リンク/お絵描きポップアップ（popup.ts の overlay は position:fixed inset:0）が開いている最中でも背後の文書が入れ替わる。ポップアップ確定時は `byId.has(id)` で弾かれる（main.ts:429, 438, 450）ので、入力したコードや描いた絵は無言で捨てられる。(b) ノードのラベル編集中にドロップすると、editor は blur しないので endEdit が走らず、positionEditor は `this.boxes.get(this.editingId)` が undefined で早期 return する（mindmap.ts:933-934）ため、input が古い位置・古い文字列のまま新しい文書の上に浮いたまま残る。

**再現条件**: （a）1) ノードで Shift+C を押しコードを入力する。2) そのまま .md ファイルをウィンドウにドロップし、確認ダイアログで OK。3) ポップアップは開いたままなので確定を押す。4) 何も挿入されずポップアップだけ閉じ、入力は失われる。（b）1) ノードをダブルクリックしてラベル編集に入る。2) .md をドロップして OK。3) 新しい文書が表示されるが、編集用 input が前の位置に残り続ける（ペインをクリックするまで消えない）。

**確度**: 確定

**検証の根拠**: src/main.ts:857-878 のハンドラは対象要素を問わず loadText を呼ぶ。ポップアップの overlay（src/popup.ts:15-17 + style.css:172-180 の position:fixed inset:0）上でも drop は window までバブルする。ラベル編集中は editor が blur しないので endEdit（src/mindmap.ts:920-925）が走らず editingId が残り、src/mindmap.ts:728 の positionEditor がそのまま実行される。

**検証による訂正**: 帰結の記述が実態より甘い。core/api.mbt:104 の init_doc が `st.next_id = 1` に戻して core/doc.mbt:281-288 が id を 1 から振り直すため、旧 id は新文書でも高確率で存在する。したがって (a) ポップアップ確定時の `byId.has(id)`（src/main.ts:429/438/450）は多くの場合 true になり、入力したコードや絵は「捨てられる」のではなく新文書の無関係なノードに挿入される。(b) ラベル編集の input も src/mindmap.ts:933 の boxes.get が当たって無関係なノードの上に移動し、次のキー入力で src/mindmap.ts:1276 の host.rename がその無関係ノードを改名する。findings が書いた「無言で捨てられる／ゴースト input が残る」は、旧 id が新文書に存在しない場合（セッション中に新規作成したノードなど id が大きいとき）だけの挙動。

**影響**: 入力途中の内容が無言で消える。ゴースト input はアプリが壊れたように見える。

**修正方針**: loadText の先頭で map.endEdit() を呼び、ポップアップが開いている間はドロップを無視する（もしくは先にポップアップを閉じる）。

### P5-エクスポート-25 / CONFIRMED / `src/main.ts:819`

**画像名のキャンセル・不正名・上書き拒否で、描いた絵や貼った画像が復旧不能に失われる**

```
if (exists && !confirm(`${leaf} は既にあります。上書きしますか？`)) {
```

**症状**: saveImageToDisk が null を返す出口が4つある（fileHandle なし 748-751、フォルダ許可失敗 756-761、prompt キャンセル 795、不正名 798-804、上書き拒否 819-821、書き込み失敗 826-830）。いずれの場合も呼び出し側（addDrawing の main.ts:449-456、pasteImage の 838-845）は blob を捨てるだけで、お絵描きポップアップは既に閉じている（popup.ts:38-41 の close が resolve と同時に overlay.remove する）。描いた内容を取り戻す手段がない。

**再現条件**: 1) ノードを選び Shift+D でお絵描きポップアップを開き、絵を描いて確定する。2) 画像名の prompt で、既存ファイルと同じ名前を入力する。3) 「上書きしますか？」で「キャンセル」を選ぶ。4) ポップアップは既に閉じており、描いた絵は完全に失われる。名前の prompt を Esc でキャンセルしても同じ。

**確度**: 確定

**検証の根拠**: src/main.ts:747-835 saveImageToDisk は :748-751 / :756-761 / :764-771 / :795 / :798-804 / :819-821 / :826-830 の各出口で null を返す。呼び出し側 src/main.ts:448-456 addDrawing と src/main.ts:838-845 pasteImage は null のとき blob を捨てるだけで再試行も一時保持もしない。src/popup.ts:38-41 の close() は resolve より先に overlay.remove() するので、prompt が出る時点でキャンバスは既に破棄されている。

**影響**: 数分かけて描いた絵が、名前入力を間違えただけで消える。

**修正方針**: 名前入力と衝突確認をポップアップの確定前（もしくはポップアップ内）に行う。少なくとも失敗時は blob を保持して再入力させる。

### P5-エクスポート-26 / CONFIRMED / `src/main.ts:105`

**localStorage の書き込み失敗が無音で、巨大文書ではリロード時に古いテキストが復元される**

```
localStorage.setItem(LS_TEXT, core.getText());
```

**症状**: catch は `/* storage full/blocked */` として何もしない（main.ts:106-108）。localStorage の上限（おおむね 5MB/オリジン）を超える文書では毎回 QuotaExceededError になり、LS_TEXT は「最後に入りきったときの内容」で止まる。起動時は `loadText(storedText ?? SAMPLE, …)`（main.ts:1114）でその古いテキストを復元し、さらに名前が一致すれば IndexedDB のファイルハンドルまで採用する（1115-1121）。この状態で Ctrl+S すると古い内容で実ファイルを上書きする。

**再現条件**: 1) 5MB を超える .md（あるいは巨大なコードブロックを大量に持つ md）を開く。2) 編集する。3) DevTools の Application → Local Storage で mmm.text の値が更新されていないことを確認する（Console には何も出ない）。4) タブをリロードすると古い内容が復元される。5) そのまま Ctrl+S すると実ファイルが古い内容で上書きされる。

**確度**: 確定

**検証の根拠**: src/main.ts:104-108 の catch は空（コメントのみ）で通知が無い。起動時は src/main.ts:1111-1114 が LS_TEXT をそのまま loadText に渡し、src/main.ts:1115-1121 は名前一致だけで IndexedDB のファイルハンドルを採用する。src/main.ts:551-573 saveFile はダーティ判定なしに core.getText() を書くので、巻き戻った内容で実ファイルを上書きできる。書き込み経路は src/main.ts:203 schedulePersist から必ず通る。

**影響**: 大きな文書でだけ、リロードを挟むと編集内容が巻き戻り、さらにその巻き戻った内容で実ファイルを潰す。警告が一切ない。

**修正方針**: setItem の失敗を検知して未保存マーク/警告を出し、失敗している間はハンドルの自動採用を止める（または IndexedDB に本文を退避する）。

### P5-エクスポート-27 / CONFIRMED / `src/main.ts:422`

**貼り付けた直後のノードが選択もフォーカスもされない**

```
applySnap(snap, "map");
```

**症状**: paste は replaceText の snapshot を applySnap するだけで、setSelection も ensureVisible も呼ばない。core.replaceText は focus を設定しない（core/api.mbt:119-135 は cmd 系と違い focus_node_at を呼ばない）ので、貼り付け後の選択は貼り付け先の親ノードのまま。貼り付け先が画面外なら何が起きたかも見えない。

**再現条件**: 1) ノードをコピーする。2) 子を多数持つノードを選んで Ctrl+V。3) 新しいノードは末尾の子として追加されるが、選択は親のまま。ビューポートも動かないので、末尾が画面外だと追加されたことが分からない。

**確度**: 確定

**検証の根拠**: src/main.ts:421-422 は replaceText の snapshot を applySnap するだけで setSelection も map.ensureVisible も呼ばない。core/api.mbt:119-135 replace_text は cmd 系と違い focus_node_at を呼ばず、core/api.mbt:94 で毎回 st.focus = -1 にリセットされるので snap.focus は -1、src/main.ts:192-195 のプルーニングでも anchorId は生き残るため選択は貼り付け先の親のまま。

**影響**: 貼り付けが成功したかどうかが分かりにくく、「無言で失敗する経路」と見分けがつかない。

**修正方針**: 挿入位置から新しいノード id を特定して setSelection + ensureVisible する。

### P5-エクスポート-28 / CONFIRMED / `src/main.ts:409`

**空文書への貼り付けだけ relevel が適用されず、ルートのない文書ができる**

```
body = normalized.trimEnd();
```

**症状**: anchorId === -1 かつ nodes.length === 0 のときはクリップをそのまま挿入する。クリップの最浅見出しが `##` 以上だと深さ1のルートが存在しない文書になり、mindmap の root（`tops.find(n => n.depth === 1)`、mindmap.ts:306）が null になって全ノードが「別ツリー」扱いで縦に積まれる（mindmap.ts:542-554）。

**再現条件**: 1) 文書を空にする（全選択して削除、またはリロード直後に全消し）。2) `## a` / 空行 / `### b` をコピーして Ctrl+V。3) マップは中央のルートを持たず、左上から縦に積まれた別ツリーとして描画される。

**確度**: 確定

**検証の根拠**: src/main.ts:406-409 は anchorId === -1 かつ nodes.length === 0 のとき `body = normalized.trimEnd()` としており relevel を通さない。最浅が `##` のクリップだと depth 1 が存在せず、src/mindmap.ts:306 の `tops.find(n => n.depth === 1)` が null になって src/mindmap.ts:494-541 のルート配置がスキップされ、全ノードが src/mindmap.ts:542-554 の別ツリー経路で縦に積まれる。core/cmds.mbt:216-227 cmd_add_root は文末に `# ` を足すだけなので、既存の `##` 群は根より前に残り別ツリーのままという指摘も正しい。

**影響**: 空文書への最初の貼り付けだけレイアウトが別物になり、その後ルートを作る導線もない（addRoot はマップ末尾に # を足すので、既存ノードとつながらない）。

**修正方針**: 空文書でも relevel(normalized, 1) を通してルート深さに揃える。

### P5-エクスポート-29 / CONFIRMED / `src/main.ts:776`

**アニメーション GIF を貼ると無言で静止 WebP になる**

```
const bmp = await createImageBitmap(blob);
```

**症状**: createImageBitmap は1フレーム目だけを返し、それを OffscreenCanvas 経由で WebP に再エンコードする（main.ts:774-787）。アニメーションは失われるが警告はない。out.type が image/webp になるので拡張子も .webp になり、元が GIF だったことも残らない。

**再現条件**: 1) アニメーション GIF をクリップボードにコピーする。2) mmm でノードを選び Ctrl+V。3) 名前を付けて保存すると .webp が1枚できるが、開くと静止画になっている。

**確度**: 確定

**検証の根拠**: src/main.ts:774-787 は out.type が image/webp でない限り createImageBitmap → OffscreenCanvas → convertToBlob で再エンコードし、createImageBitmap は1フレーム目しか返さない。src/main.ts:788 で拡張子も .webp になり、通知は無い。

**検証による訂正**: 到達性が狭い。入口は src/main.ts:387-394 の navigator.clipboard.read() だけで、Chrome の非サニタイズ形式制限により image/gif がそのまま ClipboardItem に載ることは稀（通常は image/png の静止画になり、アニメーションはコピー時点で既に失われている）。したがって「mmm がアニメーションを落とした」と言える経路は限定的で、コード上の無通知再エンコードという事実に主張を絞るべき。

**影響**: 元データより情報量が落ちるのに、それが起きたことが分からない。

**修正方針**: image/gif は再エンコードせずそのまま保存する（IMG_EXT にも gif がある）。

### P5-エクスポート-30 / 要確認 / `src/main.ts:788`

**WebP 変換に失敗した形式は、中身と食い違う拡張子で保存されうる**

```
const ext = IMG_EXT[out.type] ?? "png";
```

**症状**: IMG_EXT は webp/png/jpeg/gif の4種のみ。createImageBitmap が失敗して元 blob のまま（774-787 の catch）かつ型が image/svg+xml や image/bmp などのとき、ext は既定の "png" になり、SVG や BMP のバイト列が .png という名前で保存される。その場では assetUrls に元 blob の objectURL を入れる（main.ts:834）ので表示は正しいが、リロード後は loadAsset がファイル拡張子由来の型で objectURL を作るため、画像が表示されなくなる可能性がある。

**再現条件**: 要確認: image/svg+xml をクリップボードに載せられるアプリ（SVG をコピーできるデザインツールなど）から貼り付け、保存されたファイルの拡張子と実際のバイト列（先頭が `<svg` か）を照合する。その後リロードしてサムネイルが出るかを見る。

**確度**: 要確認

**検証の根拠**: src/main.ts:788 の `IMG_EXT[out.type] ?? "png"` に webp/png/jpeg/gif 以外のフォールバックが無いことはコードで確定（src/main.ts:738-743）。しかしこの分岐に入るには clipboard.read() が image/svg+xml や image/bmp を返し、かつ src/main.ts:776 の createImageBitmap が失敗する必要があり、Chrome の非同期クリップボードが公開する画像形式は実装依存でコードからは決まらない。決め手: 対象ブラウザで item.types に image/png 以外の image/* が現れるかを確認し、現れる場合に保存後ファイルの先頭バイト（`<svg` か PNG シグネチャか）と拡張子を照合、さらにリロード後にサムネイルが出るかを観測すること。

**影響**: 貼った直後は正常に見えるのに、リロード後だけ画像が壊れるという再現しにくい不具合になる。

**修正方針**: IMG_EXT に無い型は保存を拒否するか、blob.type から拡張子を導けない場合はユーザーに確認する。

### P5-エクスポート-31 / CONFIRMED / `src/main.ts:800`

**画像名の検証が Windows の予約デバイス名・末尾ドット・大文字小文字違いを見ていない**

```
segs.some((s) => s === ".." || /[\\:*?"<>|]/.test(s))
```

**症状**: 弾いているのは `..` と `\ : * ? " < > |` のみ。CON / PRN / AUX / NUL / COM1..9 / LPT1..9 といった Windows の予約名、末尾のドットやスペース、制御文字は通る。予約名は getFileHandle(create:true) が失敗して「画像の保存に失敗しました」になるだけだが、大文字小文字だけが違う既存ファイル（Foo.webp に対する foo.webp）については、存在チェック（main.ts:813-818）が一致しないのに OS 側では同一ファイルになるため、上書き確認を出さずに既存画像を潰す可能性がある。

**再現条件**: 要確認: Windows 上で `Foo` という名前で画像を保存したあと、別の画像を `foo` という名前で保存する。上書き確認が出ずに Foo.webp の中身が置き換わるかを確認する（Chrome の File System Access の名前解決が大文字小文字を区別するかで決まる）。

**確度**: 確定

**検証の根拠**: src/main.ts:796-804 の検証は拡張子除去 → "/" 分割 → 空/"." 除去 → `..` と /[\\:*?"<>|]/ の拒否のみで、CON/PRN/NUL/COM1..9 等の予約名、末尾のドット・スペース、制御文字を一切見ていない。

**検証による訂正**: 影響の見積もりが過大。予約名は src/main.ts:822 の getFileHandle(create:true) が失敗して src/main.ts:826-830 の「画像の保存に失敗しました」に落ちるだけで、破壊は起きない。大文字小文字違いによる無確認上書きは、src/main.ts:813-818 の存在チェックが Windows の大小文字非依存な名前解決に従えば既存ファイルを検出して確認ダイアログを出すため、成立しない公算が高い（要ブラウザ実測）。実質的な指摘は「検証が不足している」ことに留まる。

**影響**: 既存の画像が確認なしに上書きされるとファイル自体が失われる（Undo の対象外）。

**修正方針**: 存在チェックを大文字小文字を無視した列挙（dir.values()）で行い、予約名と末尾ドット/スペースも拒否する。

### P5-エクスポート-32 / 要確認 / `src/mindmap.ts:1406`

**マップペインで p / P を押すだけでクリップボード読み取りの権限プロンプトが出る**

```
if (key === "p" || key === "P") {
```

**症状**: vim 風の1ストロークキー p が host.paste() に直結しており、paste は navigator.clipboard.read()/readText() を呼ぶ（main.ts:388, 399）。選択モードで p を押しただけで Chrome のクリップボード読み取り許可ダイアログが出る。ここで「ブロック」を選ぶと、以後 Ctrl+V も含めて貼り付けが恒久的に無音で失敗する（前述の無音失敗と合流する）。

**再現条件**: 要確認（ブラウザの権限状態に依存）: クリップボード権限が未設定の状態で、マップペインにフォーカスして p を押す。Chrome の許可ダイアログが出れば該当。

**確度**: 要確認

**検証の根拠**: src/mindmap.ts:1406-1410 が p/P を host.paste() に直結し、src/main.ts:388/399 で navigator.clipboard.read()/readText() を呼ぶことはコードで確定（src/main.ts:383 の未選択ガードを通過する＝ノードを選択している場合に限る）。ただし実際に権限ダイアログが出るかはブラウザの権限状態と実装に依存し、コードでは決まらない。決め手: clipboard-read 権限が未設定の状態で、ノードを1つ選んだうえでマップペインにフォーカスして p を押し、Chrome の許可ダイアログが出るかを観測すること。

**影響**: 意図しない権限プロンプトでユーザーが「ブロック」を選びやすく、その結果まったく別の機能（Ctrl+V）が恒久的に壊れる。

**修正方針**: p は明示的な貼り付け操作としてのみ扱い、権限が拒否されたときはメッセージを出して再許可の導線を示す。

### P5-エクスポート-33 / 要確認 / `src/main.ts:377`

**非セキュアオリジンで開くとコピー操作が未捕捉の TypeError で落ちる**

```
void navigator.clipboard.writeText(text).catch(() => {});
```

**症状**: navigator.clipboard はセキュアコンテキストでのみ定義される。http://192.168.x.x のような LAN 経由（vite --host）で開くと undefined になり、`navigator.clipboard.writeText(...)` の時点で同期的に TypeError が投げられる。.catch はまだ付いていないので握り潰されず、keydown ハンドラの外まで例外が抜ける。一方 paste 側は async IIFE の中なので同じ TypeError が .catch(() => {}) に吸われて無音になる（main.ts:423）。

**再現条件**: 要確認（配信形態に依存）: 開発サーバを --host で立てて別端末から http:// で開き、マップでノードを選んで Ctrl+C。コンソールに TypeError: Cannot read properties of undefined (reading 'writeText') が出れば該当。localhost では secure context なので再現しない。

**確度**: 要確認

**検証の根拠**: src/main.ts:377 が存在チェック無しに navigator.clipboard.writeText を呼ぶこと、paste 側（src/main.ts:387 の `"read" in navigator.clipboard` と :399）は try/catch と :423 の .catch に吸われて無音になることはコードで確定。ただし navigator.clipboard が undefined になるのは非セキュアオリジンで開いた場合だけで、README の想定は `pnpm run dev`（localhost＝secure context）なので、この配信形態が実在するかはコードでは決まらない。決め手: vite を --host で立てて別端末から http:// で開き、ノードを選んで Ctrl+C したときにコンソールに TypeError: Cannot read properties of undefined (reading 'writeText') が出るかを観測すること。なお同じ理由で `if (cut) host.deleteSelection()` には到達しないため、この状況ではカットによる削除は起きない。

**影響**: ローカル専用ツールを LAN 経由で使う場面でコピーがクラッシュし、貼り付けは無音で死ぬ。

**修正方針**: navigator.clipboard の有無を確認し、無ければ flashFilename で「この接続ではクリップボードを使えません」と出す。

---

## 9. 非同期処理（await をまたぐ状態、保存/読み込みの競合、loadAsset と objectURL、popup と Promise、catch 漏れ）

**調べたもの**

- src/main.ts 全 1136 行を通読（永続化 idb/localStorage、applySnap、host 実装、file I/O、画像、export、boot）
- src/popup.ts 全 237 行を通読（shell の Promise 契約、collect() の同期性、キー処理、queueMicrotask のタイミング）
- src/mindmap.ts 全 1814 行を通読（exportSvg の fetch/FileReader、render/positionEditor、ドラッグ状態、ResizeObserver）
- src/editor.ts 全 189 行を通読 — async/Promise は一切なし。dispatch は全て同期（該当なし）
- src/coreApi.ts — 全 API が同期（Promise を返す関数はゼロ）。よって「core 呼び出しが await をまたぐ」経路は存在しない
- node_modules/@codemirror/view/dist/index.js:8022-8040 を実読し、updateListener が updateState=Idle に戻した後で呼ばれる（= applySnap 内からの再入 dispatch は throw しない）ことと、listener 例外が logException で握り潰されることを確認
- core/api.mbt:99-111 の init_doc を実読し、st.next_id = 1 にリセットされる（= 文書を開き直すと id が 1 から再割り当てされる）ことを確認
- await をまたいで読まれるグローバル: fileHandle / dirHandle / fileName / savedText / anchorId / byId / nodes を全参照点で照合
- Promise を作る全箇所の catch 有無を列挙（drop IIFE・addDrawing/addLink/addCode の then・input.onchange に catch なし、他は catch 済み）
- popup.ts の collect() は showDrawPopup を含め全て同期（toBlob を避け toDataURL 使用）。async は混入していない — この点は問題なし

### P5-非同期-1 / CONFIRMED / `src/main.ts:552`

**saveFile が text を await 前に固定し fileHandle/savedText を await 後に書く（保存中に別ファイルを開くと不整合）**

```
const text = core.getText();
```

**症状**: saveFile は先頭で text を固定するが、実際の書き込み先 fileHandle は 571 行目（複数 await の後）に読み直す。さらに完了後 582-588 行で savedText / localStorage[LS_SAVED] / LS_NAME を「開始時のテキスト」と「現在の fileName」という食い違ったペアで書く。保存の途中で文書が差し替わると、旧文書のテキストを savedText として記録し、ファイル名だけ新しいものが localStorage に残る。

**再現条件**: 1) 数十 MB の .md を開く（await w.write(text) が体感で秒単位かかる大きさにする）。2) 1 文字打って Ctrl+S。3) 書き込み中に別の .md をウィンドウにドラッグ&ドロップして開く。4) 保存完了後、B を一切編集していないのに未保存ドット(#dirty)が点灯する。5) リロードすると localStorage には「A の本文 + B のファイル名」が残っており、confirmDiscard が毎回「未保存の変更があります」と聞いてくる。

**確度**: 確定

**検証の根拠**: src/main.ts:552 で text を固定、571 で fileHandle を再読み、582/585-586 で savedText と LS_NAME を書く。drop ハンドラ src/main.ts:873-876 は保存の await 中に fileHandle/savedText/fileName を差し替えられるので、保存完了時に savedText=A本文・fileName=B名 のペアが確定し 583 の updateDirty() で #dirty が点灯する。ガードは存在しない（saveFile 内に実行中フラグ・世代番号なし）。

**検証による訂正**: 再現に「1 文字打つ」は不要。text===savedText でも saveFile は走るので、Ctrl+S 直後にドロップすれば confirmDiscard(614) のダイアログすら出ずに同じ不整合になる（この方が確実）。逆に 1 文字打った場合は confirmDiscard の confirm() が挟まる。fileHandle 差し替え後に 571 が走る「別ファイルへ旧文書を書く」経路も 557-571 の await 区間に限り成立する。

**影響**: 未保存インジケータと LS_SAVED の破壊。さらに fileHandle が await 後読みなので、permission 再取得（requestPermission のバブルは非モーダルでページが操作可能）中に fileHandle が差し替わると、571 行は新しいハンドルに旧文書を書き込む＝別ファイルの内容を静かに上書きする経路が残る。

**修正方針**: 保存開始時に const h = fileHandle と const doc = text をペアで固定し、完了時に「fileHandle === h かつ core.getText() が doc のまま」を確認してから savedText/localStorage を更新する。

### P5-非同期-2 / CONFIRMED / `src/main.ts:873`

**drop ハンドラの async IIFE に catch が無く、fileHandle だけ先に新ファイルへ差し替わる**

```
fileHandle = h?.kind === "file" ? (h as FileSystemFileHandle) : null;
```

**症状**: 873 行で fileHandle を新ファイルに差し替えた「後」に 874 行で await f.text() する。text() が reject すると loadText は走らず、画面は旧文書のまま・ファイル名表示も旧のまま、しかし fileHandle だけ新ファイルを指す。870 行の void (async () => {...})() には .catch が無いので unhandled rejection になり、openFile 側にある flashFilename("読み込み失敗") 相当の通知も一切出ない。

**再現条件**: A) 失敗経路: DevTools のコンソールで File.prototype.text = function(){ return Promise.reject(new Error("x")) } を実行 → 任意の .md をドロップ → 画面は変わらず「Uncaught (in promise)」のみ → その状態で Ctrl+S すると、ドロップしたファイルが表示中の旧文書で上書きされる。B) 競合経路: 2 つの .md を素早く連続でドロップすると、873 の代入と 875 の loadText がインターリーブし、fileHandle=A / 表示=B の組み合わせになりうる（各 IIFE は独立に await するため順序保証がない）。

**確度**: 確定

**検証の根拠**: src/main.ts:870 の void (async () => {...})() は 877 で閉じており .catch が無い。873 で fileHandle=新ハンドル、874 で await f.text()。text() が reject すれば 875 の loadText は走らず、fileHandle だけ B・文書と savedText は A のまま残り、以後の saveFile(571) は B へ A の本文を書く。drop 経路には flashFilename 相当の通知が一切無い（openFile の 543-548 に相当するものが無い）。

**影響**: ドロップしたファイルを旧文書で上書きする無言のデータ破壊。エラー通知も無い。

**修正方針**: text() を先に await して成功してから fileHandle と loadText を同時に更新し、IIFE に .catch を付けて openFile と同じ flashFilename("読み込み失敗") を出す。ドロップ処理中フラグで多重実行も止める。

### P5-非同期-3 / CONFIRMED / `src/main.ts:524`

**openFile も fileHandle を読み込み完了前に代入している**

```
fileHandle = h;
```

**症状**: 524 行で fileHandle を差し替えてから 525 行で savedText = await f.text() する。text() が失敗すると catch に飛んで「読み込み失敗」は出るが、fileHandle は新ファイルのまま残り、savedText と文書は旧のまま。以後の Ctrl+S は選び直したファイルへ旧文書を書く。persistHandle() も呼ばれないので IndexedDB 側は旧ハンドルのままで、511-513 行のコメントが謳う lockstep も崩れる。

**再現条件**: DevTools で File.prototype.text を reject に差し替え、「開く」から別の .md を選択 → 「読み込み失敗」表示、内容は変わらない → Ctrl+S → 選択したファイルが旧文書で上書きされる。

**確度**: 確定

**検証の根拠**: src/main.ts:524 で fileHandle=h、525 で savedText=await f.text()。525 が throw すると 543-547 の catch で「読み込み失敗」は出るが fileHandle は新ファイルのまま、savedText/文書は旧のまま。527 の persistHandle() も飛ぶので IndexedDB は旧ハンドルのままとなり、511-513 のコメントが守ろうとした lockstep が崩れる。

**影響**: 読み込み失敗時にユーザーが選んだ（読めなかった）ファイルを上書きしうる。

**修正方針**: const t = await f.text() を先に済ませ、成功後に fileHandle/savedText/loadText をまとめて更新する。catch では fileHandle を元の値に戻す。

### P5-非同期-4 / CONFIRMED / `src/main.ts:532`

**非 FS フォールバックの input.onchange が async かつ catch 無しで、openFile の try/catch の外**

```
input.onchange = async () => {
```

**症状**: input.click() 後に openFile は即 return するので、532 行のハンドラは 543 行の catch の外側で実行される。await f.text() の失敗は unhandled rejection になり「読み込み失敗」も出ない。加えて confirmDiscard は click() の前に済んでいるため、OS のファイルダイアログ表示中〜選択後に加えられた編集は無確認で破棄される。

**再現条件**: showOpenFilePicker の無い環境（Firefox 等）、または DevTools で delete window.showOpenFilePicker してリロード → 「開く」→ ファイル選択 → text() を reject させると無反応かつコンソールに未処理 rejection のみ。

**確度**: 確定

**検証の根拠**: src/main.ts:532-540 の onchange は async で、541 の input.click() 後 openFile は即 return するため 543 の catch の外で実行される。536 の await f.text() が reject しても誰も受けず、flashFilename も呼ばれない（この経路は hasFs=false のときだけ到達、505 行で決定）。

**検証による訂正**: 「OS のファイルダイアログ表示中〜選択後の編集が無確認で破棄される」は成立しない。input.click() のファイルダイアログは Chrome/Firefox ともウィンドウモーダルで、表示中はページに入力できず、選択直後に onchange が走るため編集の窓が無い。残る実害は「読み込み失敗の完全な無言化」だけ。

**影響**: 非 Chromium 系での読み込み失敗が完全に無言。編集の無確認破棄。

**修正方針**: onchange の中身を try/catch で包み flashFilename を出す。読み込み直前に confirmDiscard を取り直す。

### P5-非同期-5 / CONFIRMED / `src/popup.ts:49`

**popup.ts のモーダル表示中に main.ts の capture フェーズのグローバルショートカットが素通りする**

```
e.stopPropagation(); // keep map/global shortcuts out
```

**症状**: このコメントの主張は成立していない。main.ts:882-910 の keydown は window の capture フェーズ（909 行 { capture: true }）で登録されているため、overlay のバブル段階の stopPropagation より先に必ず実行される。したがってコードポップアップのテキストエリア入力中でも Mod+Z/Mod+Y は doUndo()/doRedo()、Mod+S は saveFile()、Mod+O は openFile()、Mod+/ は togglePane() が発火する。902 行のガードは map.isEditing() だけでポップアップ表示中を見ていない。

**再現条件**: 1) マップ上のノードを選択して Shift+C（コードブロック追加ポップアップ）。2) テキストエリアに「abc」と入力。3) Ctrl+Z を押す → テキストエリアの入力は取り消されず（e.preventDefault で native undo も潰される）、背後の文書がアンドゥされる。4) 同じ状態で Ctrl+O を押すとポップアップの裏でファイルピッカーが開き、別ファイルを読み込める。5) Ctrl+/ を押すとペインが切り替わり、editor.focus() でモーダルからフォーカスが奪われる。

**確度**: 確定

**検証の根拠**: src/popup.ts:48 のリスナは overlay 要素のバブル段階、src/main.ts:882-910 のリスナは window の capture 段階（909 の { capture: true }）なので必ず main.ts が先に走る。overlay は document.body 直下（popup.ts:60）で mapPane の外なので 895 の mapPane.contains(document.activeElement) は false になり Mod+O が openFile を呼ぶ。902 の map.isEditing() は mindmap.ts:927-929 の editingId のみを見ておりポップアップを検知しないので Mod+Z/Y は doUndo/doRedo に流れ、904 の e.preventDefault() で textarea の native undo も潰れる。Mod+/ は 900 の togglePane() でフォーカスを奪う。

**影響**: モーダル入力中に背後の文書が壊れる。次項（id 再割り当て）と連鎖して、確定時に無関係なノードへ挿入される。

**修正方針**: 開いているポップアップ数をモジュール変数で持ち、main.ts の window keydown 冒頭で「ポップアップが開いていれば return」する（map.isEditing() と同列のガード）。

### P5-非同期-6 / CONFIRMED / `src/main.ts:430`

**init_doc が next_id を 1 に戻すため、byId.has(id) は「文書が入れ替わっていない」ことを保証しない**

```
if (r && byId.has(id)) {
```

**症状**: addLink/addCode/addDrawing/pasteImage は await をまたいだ後の妥当性チェックを byId.has(id) だけで行っている。しかし core/api.mbt:104 の init_doc は st.next_id = 1 にリセットするので、loadText（開く/ドロップ/起動）のたびに id は 1 から振り直される。つまり「同じ数値の id が別の文書の別ノードに存在する」ため、チェックは通ってしまい、挿入先だけが全くの別ノードになる。

**再現条件**: 1) 3 個以上ノードのある a.md を開き、2 番目のノードを選択して Shift+C でコードポップアップを開く。2) 前項のとおりポップアップ表示中でも Ctrl+O が効くので、Ctrl+O で b.md（こちらもノード複数）を開く。3) ポップアップに戻って Mod+Enter で確定。4) b.md 側の、a.md で選んでいたノードと同じ id 番号を持つ無関係なノードの下にコードブロックが挿入され、b.md が汚染される（未保存扱いで dirty 点灯）。同じことが Shift+D（お絵描き）→ 画像パス挿入、画像ペーストの pasteImage でも起きる。

**確度**: 確定

**検証の根拠**: core/api.mbt:104 で st.next_id = 1、core/doc.mbt:283-287 で id 未知の見出しに next_id を 1 から順に振り直すことを確認。src/main.ts:429/438/449/842 の妥当性チェックは byId.has(id) だけで、byId は applySnap(181-182)で新文書のものに差し替わるため同じ id 値が別ノードとして必ず存在する。ポップアップ表示中に Ctrl+O が通る（項目 6 が CONFIRMED）ので経路も実在し、insertContentLine(722-736) が新文書の別ノード配下へ書き込む。

**影響**: 別文書の無関係なノードへコード/リンク/画像行を書き込む。id の一致は偶然なので、ユーザーには原因が分からない。

**修正方針**: loadText 側で docEpoch を ++ し、非同期を開始した時点の epoch を捕まえて、継続側で epoch 一致も確認する（id 単独では不十分）。

### P5-非同期-7 / 要確認 / `src/main.ts:448`

**addDrawing の then に catch が無く、saveImageToDisk の assetSegs は try の外**

```
void showDrawPopup().then(async (blob) => {
```

**症状**: 448 行の then コールバックは async だが .catch が繋がっていない。中で呼ぶ saveImageToDisk は 763 行 const base = await assetSegs(dir); を try/catch の外で実行しており、assetSegs は dir.resolve(fileHandle) を await する（ハンドルが無効化されていれば reject する）。reject すると未処理 rejection になるだけでなく、455 行の mapPane.focus() が実行されないためフォーカスが body に残り、マップのキーボード操作が全部死んだように見える（クリックするまで復帰しない）。addLink/addCode の then も同様に catch 無しで、insertContentLine→applySnap→map.render() が投げれば同じくフォーカス復帰が飛ぶ。

**再現条件**: 要確認: 実機で resolve() を確実に reject させる手段が要る。DevTools で FileSystemDirectoryHandle.prototype.resolve = () => Promise.reject(new Error("x")) を差し込み、ノード選択 → Shift+D → 描画 → 確定 → (a) コンソールに未処理 rejection、(b) その後 j/k/Tab などマップのキー操作が効かない、の 2 点を観測すれば確定。

**確度**: 要確認

**検証の根拠**: コード構造は記述どおり（src/main.ts:448-456 の then に .catch 無し、455 の mapPane.focus() は reject でスキップ、src/main.ts:763 の await assetSegs(dir) は 754-762 の try/catch の外）。ただし唯一の未捕捉 reject 源である dir.resolve()（src/main.ts:650）は Chromium ではパス比較のみで I/O を伴わず、実運用で reject する経路をコードから示せない（prompt キャンセル・上書き confirm は null 返し、書き込みは 806-830 の try 内）。決着させる観測: FileSystemDirectoryHandle.prototype.resolve をパッチして reject させ、(a) Uncaught (in promise) が出ること、(b) 確定後に j/k/Tab などマップのキー操作が効かず document.activeElement が body になっていること、の 2 点。より現実的な引き金は insertContentLine→applySnap→map.render() が投げるケースだが、それ自体が仮定。

**影響**: 未処理 rejection とフォーカス喪失（操作不能に見える）。エラー通知も無い。

**修正方針**: assetSegs の呼び出しを try/catch に入れて flashFilename を出し、3 つの popup 呼び出し全てに .catch(() => {}) と finally 相当の mapPane.focus() を付ける。

### P5-非同期-8 / CONFIRMED / `src/main.ts:377`

**cut がクリップボード書き込みの完了を待たずに削除し、失敗も握り潰す**

```
void navigator.clipboard.writeText(text).catch(() => {});
```

**症状**: 377 行で書き込みを投げっぱなしにし、378 行で同期的に deleteSelection() する。writeText が reject（ドキュメント非フォーカス、権限ポリシー、Firefox のユーザー操作要件など）してもノードは削除済みで、クリップボードには前の内容が残る。catch(() => {}) なので通知も無い。コピー（cut=false）も同様に、成功したように見えて何もコピーされていない状態になりうる。

**再現条件**: 1) DevTools コンソールで navigator.clipboard.writeText = () => Promise.reject(new DOMException("no","NotAllowedError")) を実行。2) マップでノードを選択して Ctrl+X。3) ノードは消えるが、他所に貼り付けると以前のクリップボード内容が出る。エラー表示は一切無い。

**確度**: 確定

**検証の根拠**: src/main.ts:376-378 で writeText を投げっぱなし（.catch(() => {}) で無言）にしたまま 378 で同期的に host.deleteSelection() を呼ぶ。書き込み結果を待つコードも通知も無く、コピー(cut=false)側も同様に失敗が無言。deleteSelection(345-354) は core.deleteNodes → 通常の undo エントリなので、復旧手段は undo のみという影響記述も正しい。

**影響**: 切り取り内容の消失（アンドゥでしか戻せない）。コピー失敗が無言。

**修正方針**: cut は await writeText().then(() => deleteSelection()) にし、reject 時は削除せず flashFilename で通知する。

### P5-非同期-9 / CONFIRMED / `src/main.ts:677`

**loadAsset が clearAssets() を跨いで完走し、旧文書の画像を新文書のキャッシュに書き込む**

```
assetUrls.set(path, url);
```

**症状**: loadText は clearAssets() で assetUrls を revoke+clear するが、実行中の loadAsset は止められない。await（queryPermission / resolve / getDirectoryHandle / getFile）から戻った後に 677 行が、既に新文書用になった assetUrls へ旧文書のパスと objectURL を書き込む。新文書が同じ相対パス（例 ./pic.webp）を参照していれば、imageUrl() はそのキャッシュを返すので、別フォルダの別画像がサムネイルとして表示され続ける。参照していなければ、そのエントリは次の clearAssets まで誰にも使われない objectURL として残る。

**再現条件**: 要確認（タイミング依存）: フォルダ A に a.md と大きめの pic.webp、フォルダ B に b.md と別絵柄の pic.webp を用意し、双方の md に ![](./pic.webp) を書く。DevTools の Network を Slow 3G 相当にするか pic.webp を数十 MB にして、a.md を開いた直後（サムネイルがプレースホルダのうち）に b.md を開く。b.md のノードに A の絵が出れば確定。

**確度**: 確定

**検証の根拠**: src/main.ts:654-678 に世代トークンもキャンセルも無く、677 の assetUrls.set(path, url) は clearAssets(631-634) の後でも無条件に実行される。ここで url は 660 の assetSegs(=その時点の fileHandle) で決まるので、660 通過後に文書が入れ替われば旧フォルダの画像が新文書のキャッシュへ入り、678 の render() で表示される。

**検証による訂正**: 再現手順が誤り。loadAsset はファイル本体を読まない（675-676 は getFile()+createObjectURL で O(1)。実際の復号は <image> 描画時）ので、pic.webp を数十 MB にしても Slow 3G にしても窓は広がらない。競合窓は 660 の dir.resolve 完了から 677 までの数 ms の IPC 区間だけで、手動で当てるのはネットワークドライブ等で getDirectoryHandle/getFileHandle/getFile が遅延する場合に限られる。逆に 660 到達前に切り替わった場合は新 fileHandle 基準になるので誤表示は起きない。

**影響**: 別文書の画像が表示され続ける（ユーザーには原因不明）。使われない objectURL の滞留。

**修正方針**: clearAssets 時に世代カウンタを進め、loadAsset は開始時の世代と一致する場合のみ set/render する（不一致なら生成した URL を revoke する）。

### P5-非同期-10 / CONFIRMED / `src/main.ts:697`

**unlockAssets が拒否・却下時にもリスナを外すので、以後サムネイルが永久に再試行されない**

```
window.removeEventListener("pointerdown", unlockAssets, true);
```

**症状**: 697 行の removeEventListener は ok の判定と無関係に無条件で実行される。queryPermission が "denied" を返した場合も、requestPermission のバブルをユーザーが×で閉じた（dismiss）場合も、リスナは外れて二度と戻らない。その結果 658 行のコメント「retried on the next user gesture (see unlockAssets)」は 1 回きりしか成立せず、以後どれだけクリックしてもサムネイルはプレースホルダのまま、UI 上の説明も出ない。

**再現条件**: 1) 画像を含む md を保存し、フォルダ許可を与えた状態でリロード（dirHandle は prompt 状態で復元される）。2) 画面のどこかをクリック → 許可バブルが出る → ×で閉じる（またはブロック）。3) 以降いくらクリックしても、画像リンク行はファイル名だけのプレースホルダのまま。4) DevTools の getEventListeners(window).pointerdown を見るとリスナが消えている。

**確度**: 確定

**検証の根拠**: src/main.ts:697 の removeEventListener は ok(693-696) の値と無関係に無条件実行。denied/dismiss で ok=false でも 698 の再試行は走らずリスナも消える。復帰経路も無い: imageUrl(636-642) は assetUrls に null エントリがある限り hit!==undefined で再ロードしないし、IDB からの再試行は起動時(1122-1133)の一回だけ。658 のコメント「retried on the next user gesture」は一度きりしか成立しない。

**影響**: 1 回の誤操作でセッション中ずっと画像が表示されなくなり、回復手段がユーザーに提示されない。

**修正方針**: removeEventListener を if (ok) の中に入れる。拒否時はリスナを残す（または flashFilename で「画像フォルダの許可が必要」と通知して再試行導線を出す）。

### P5-非同期-11 / CONFIRMED / `src/main.ts:629`

**assetUrls の objectURL は文書から画像行が消えても revoke されない**

```
const assetUrls = new Map<string, string | null>();
```

**症状**: objectURL が revoke されるのは clearAssets()（ファイル読み込み時）と saveImageToDisk の同一パス上書き（832-833 行）だけ。ノードを削除したり画像行を消したりして参照が無くなっても、Map にエントリと Blob が残り続ける。1 つのファイルを開いたまま画像を貼っては消す作業を繰り返すと、画像 1 枚ぶんのメモリが解放されないまま積み上がる。

**再現条件**: 1) md を開き、画像を 10 枚ペーストする（毎回 saveImageToDisk が createObjectURL する）。2) 10 枚ぶんの画像行をエディタから全部消す。3) chrome://blob-internals/ を開くと 10 個の Blob が生存したまま。assetUrls.size もコンソールから 10 のまま確認できる。

**確度**: 確定

**検証の根拠**: revoke は clearAssets(src/main.ts:632)と saveImageToDisk の同一パス上書き(832-833)の 2 箇所のみ。画像行やノードを消しても assetUrls からエントリを外す処理はどこにも無く、834 で作った objectURL は次のファイル読み込みまで生存する。

**検証による訂正**: 再現手順のうち「assetUrls.size をコンソールから確認」は不可（assetUrls は src/main.ts:629 のモジュールスコープ変数で window に露出していない）。chrome://blob-internals で Blob の生存を見る方法だけが有効。影響も「ファイルを開き直すまで解放されない」上限付きのリークで、セッション永続ではない。

**影響**: 長時間セッションでのメモリ増大（1 枚数 MB のスクリーンショットなら顕著）。

**修正方針**: render 時に「現文書が参照しているパス集合」を作り、そこに無い assetUrls エントリを revoke して削除する（LRU 上限でも可）。

### P5-非同期-12 / CONFIRMED / `src/main.ts:679`

**loadAsset の catch が map.render() の例外まで飲み込む**

```
} catch {
```

**症状**: 678 行の map.render() が try ブロックの内側にあるため、レンダリング中の例外が「missing file — the placeholder row stays」というコメントの意図とは無関係に握り潰される。assetUrls には URL が入った状態でレンダリングだけが中断するので、マップの DOM が中途半端（edgeLayer/nodeLayer を replaceChildren した直後で止まる）なまま放置されうる。

**再現条件**: 要確認: DevTools で MindMap.prototype.render を 1 回だけ throw するようパッチし、画像読み込み完了時にマップが空になったままコンソールにも何も出ないことを確認すれば確定。

**確度**: 確定

**検証の根拠**: src/main.ts:678 の map.render() は 655 で始まる try の内側にあり、679-681 の catch（コメントは missing file 用）が rendering 例外まで飲む。半端な DOM が残るという記述も裏付けられる: src/mindmap.ts:558-559 で edgeLayer/nodeLayer を replaceChildren した後に全ノードを再構築するので、その後に投げれば空のマップが残る。

**検証による訂正**: 実害は「render が例外を投げたときに完全無言になる」という条件付きのもので、render が投げる具体的経路は本監査では示せていない。優先度は低い（マスクされるバグが存在して初めて表面化する）。

**影響**: 描画不具合の完全な無言化（原因調査が不可能になる）。

**修正方針**: map.render() を try の外に出し、catch は getFileHandle/getFile の失敗のみを対象にする。

### P5-非同期-13 / CONFIRMED / `src/main.ts:678`

**画像 1 枚のロード完了ごとに render() 全再構築が走る（F-002 の非同期側の新しい帰結）**

```
map.render();
```

**症状**: imageUrl() は未知パスを見つけるたびに loadAsset を起動し、loadAsset は完了時に必ず map.render() を呼ぶ。render() は F-002 のとおり全 SVG 要素を破棄・再構築するので、画像 N 枚の文書を開くと、完了タイミングがばらけるぶんだけ最大 N 回の全再描画が直列に発生する。しかも各 render() が新たな未知パスを発見して次の loadAsset を起こすため、初回表示は N 回ぶんのレイアウト計算を必ず通る。

**再現条件**: 1) 画像行を 10 個持ち、ノード数 2000 程度の md を用意する。2) Performance タブを録画しながらそのファイルを開く。3) loadAsset の resolve ごとに 1 本ずつ、F-002 で計測された 66ms 級の render タスクが 10 本並ぶ。読み込み中はマップ操作が断続的に固まる。

**確度**: 確定

**検証の根拠**: src/main.ts:678 で loadAsset の完了ごとに map.render() を呼ぶ。src/mindmap.ts:689 の host.imageUrl(r.path) は render 中に未知パスごとに imageUrl→loadAsset(src/main.ts:640) を起動するので、画像 N 枚なら N 回の全再構築（F-002 の 66ms 級）が発生する。

**検証による訂正**: 「各 render が新たな未知パスを発見して次の loadAsset を起こす（直列の連鎖）」は不正確。render(src/mindmap.ts:290,561) は全ノードを走査するので未知パスは初回 render で一斉に発見され、N 本の loadAsset が並行して走る。N 回の全再描画は各完了ごとに 1 回ずつ起きるだけで、連鎖的な直列化ではない（合計回数は同じ）。

**影響**: 画像つき大規模文書のオープン直後に、画像枚数×全再描画ぶんの操作不能時間が発生する。

**修正方針**: loadAsset 完了時は該当 <image> の href 差し替えだけ行う。全再描画が必要ならマイクロタスク/rAF で合流させて 1 回にまとめる。

### P5-非同期-14 / CONFIRMED / `src/mindmap.ts:837`

**exportSvg の blob: fetch はキャンセル不能で、revoke 済みなら画像が無言で消える**

```
const b = await (await fetch(href)).blob();
```

**症状**: AbortController を持たないので、エクスポートを開始したら画像枚数ぶんの fetch+FileReader が最後まで走る。この間に clearAssets()（別ファイルを開く）が objectURL を revoke すると fetch が reject し、846 行 img.remove() で「その画像だけ黙って消えた SVG」が出力される。ユーザーにはエクスポート成功として提示される（exportMap は例外にならない）。

**再現条件**: 要確認: 画像を 5 枚以上含む大きめのマップで「SVG」ボタンを押し、直後に別の .md をドロップして開く。出力された .svg を開いて、画像が抜け落ちているのに何のエラーも出ていないことを確認すれば確定。

**確度**: 確定

**検証の根拠**: src/mindmap.ts:833-848 のループに AbortController は無く、837 の fetch が失敗すると 846 の img.remove() で画像だけが黙って落ちる。clearAssets(src/main.ts:632) は loadText(476) から呼ばれ blob: を revoke するので、エクスポート中に別ファイルを開けば revoke 済み URL への fetch が TypeError で reject する。exportMap(src/main.ts:1004-1064) は例外にならないまま downloadBlob まで進むため、欠損した出力が成功として提示される。

**検証による訂正**: 引き金は事実上この競合のみ（クローンは 801-802 で先に取るので通常の再描画では壊れない）。エクスポートは画像枚数ぶんの fetch+FileReader なので窓は数百 ms 程度、手動での再現は「大きめのマップでエクスポート直後にドロップ」に限られる。

**影響**: 欠損したエクスポート結果を成功として渡す。

**修正方針**: AbortController を持ち、clearAssets/loadText 時に abort する。1 枚でも失敗したら flashFilename で「一部の画像を埋め込めませんでした」と通知する。

### P5-非同期-15 / CONFIRMED / `src/main.ts:1015`

**exportMap が await の後で fileName を読むため、出力名と中身がずれる**

```
const base = fileName.replace(/\.(md|markdown|txt)$/i, "") || "mmm";
```

**症状**: 1009 行の await map.exportSvg() の後に fileName を読むので、エクスポート中に別ファイルを開くと「新しいファイル名 + 古いマップ」の組で保存/コピーされる。クリップボード書き込み（1018 行 / 1046 行）も await をいくつも跨いだ後に実行されるため、その間にウィンドウのフォーカスが外れると NotAllowedError（Document is not focused）で 1060 行の catch に落ち、実際には画像生成に成功していても「エクスポートに失敗しました」と表示される。

**再現条件**: A) 画像入りの大きなマップで webp エクスポートを開始し、すぐ別の .md をドロップ → ダウンロードされるファイル名が新ファイル由来なのに中身は旧マップ。B) Shift+クリックでクリップボードエクスポートを開始し、すぐ別アプリのウィンドウをクリックしてフォーカスを外す → 「エクスポートに失敗しました」。

**確度**: 確定

**検証の根拠**: src/main.ts:1009 の await map.exportSvg() の後、1015 で初めて fileName を読む。exportSvg は画像埋め込みで実際に await する（src/mindmap.ts:837-843）ので、その間に drop/openFile が loadText(474) で fileName を書き換えれば「新ファイル名 + 旧マップ」の組で保存・コピーされる。

**検証による訂正**: クリップボード側は誤エラーではない。1018/1046 の write が NotAllowedError(Document is not focused) で失敗すれば、実際にコピーは行われていないので 1062 の「エクスポートに失敗しました」は正しい表示。問題は「生成し終えた成果物を捨てて何も残らない」ことであって誤報告ではない。また名前ずれは画像を含むマップでのみ成立する（画像が無ければ exportSvg に実 await が無く、drop が割り込めない）。

**影響**: 出力ファイル名と内容の不一致、および成功したエクスポートの誤エラー表示。

**修正方針**: exportMap の先頭で base をローカルに固定する。クリップボード書き込みは ClipboardItem に Promise を渡す形にしてユーザー操作直後に予約する。

### P5-非同期-16 / CONFIRMED / `src/main.ts:423`

**paste の catch-all が applySnap/render の例外まで飲み込む**

```
})().catch(() => {});
```

**症状**: paste の async IIFE は 421-422 行で core.replaceText と applySnap を実行するが、その例外も 423 行の catch-all に吸われる。core 側のテキストは既に変更済み、applySnap は nodes/byId を代入した後で render() に入るため、失敗すると「文書は変わったのにマップだけ古い」半適用状態がコンソール出力すら無しで残る。

**再現条件**: 要確認: MindMap.prototype.render を 1 回 throw させたうえで Ctrl+V（見出しを含むテキスト）を実行し、md ペインには貼り付き・マップは更新されず・コンソールは無言、の 3 点を観測すれば確定。

**確度**: 確定

**検証の根拠**: src/main.ts:384 の async IIFE は 423 の .catch(() => {}) で閉じており、421 の core.replaceText と 422 の applySnap の例外もここに吸われる。core のテキストは replaceText 時点で確定済み、applySnap(180-198) は nodes/byId 代入後に render() へ入るので、投げれば「文書は変わったのにマップだけ古い」半適用が無言で残る。

**検証による訂正**: 仮定に頼らない到達可能な実害を追加すべき: 399 の await navigator.clipboard.readText() は 386-398 の try の外にあるため、権限拒否や document 非フォーカスで reject すると 423 の catch-all に落ち、Ctrl+V が何の表示も無く完全に無反応になる（こちらは render が投げる前提を必要としない）。

**影響**: ペースト失敗が完全に無言化し、両ペインの不整合が残る。

**修正方針**: catch でエラー種別を見て、AbortError/権限拒否のみ黙殺し、それ以外は console.error + flashFilename にする。

### P5-非同期-17 / CONFIRMED / `src/main.ts:839`

**画像/テキストペーストの貼り付け先が await 完了時点の anchorId で決まる**

```
const targetId = anchorId;
```

**症状**: paste() は 383 行で anchorId を「チェック」するだけで捕まえておらず、実際の対象は clipboard.read()/readText() の await が解決した後に読み直される（pasteImage は 839 行、テキスト経路は 412 行の byId.get(anchorId)）。Chrome のクリップボード読み取り許可バブルは非モーダルでページが操作可能なので、許可を押すまでの間に別ノードを選び直すと、Ctrl+V を押したときのノードではなく「許可した瞬間」のノードに貼られる。

**再現条件**: 1) クリップボード権限を未許可状態にする（chrome://settings のサイト設定でクリップボードをリセット）。2) ノード A を選んで Ctrl+V。3) 許可バブルが出ている間にノード B をクリックして選択。4) 「許可」を押す → 内容がノード B の下に入る。

**確度**: 確定

**検証の根拠**: src/main.ts:383 の anchorId チェックは値を捕まえておらず、実対象は 388 の await navigator.clipboard.read() 解決後に読み直される（画像経路は 839 の const targetId = anchorId、テキスト経路は 411 の byId.get(anchorId)）。Chrome のクリップボード読み取り許可プロンプトは非モーダルでページが操作可能なため、許可を押すまでの間にノードを選び直せば別ノードへ入る。Mod+V は src/mindmap.ts:1502 の onKeydown 経由で host.paste() を呼ぶだけで、押下時のノードを引数として渡していない。

**検証による訂正**: テキスト経路の行番号は 412 ではなく 411（412 は if (!n) return;）。また実用的な窓は許可プロンプト（もしくは巨大画像の item.getType()）に限られ、許可済み環境ではマイクロタスク程度の窓しか無い。

**影響**: ユーザーの意図と違うノードに貼り付く。画像経路では保存ダイアログまで進んでから気付く。

**修正方針**: paste() の同期部分で targetId = anchorId を確定し、以後は再読み込みしない（無効化されていたら中止する）。

### P5-非同期-18 / 要確認 / `src/main.ts:1001`

**ダウンロード用 objectURL を click() 直後に revoke している**

```
URL.revokeObjectURL(a.href);
```

**症状**: ダウンロードの取得は非同期に開始されるのに、同じタスク内で即座に revoke している。saveFile の非 FS 経路（580 行）も同じ形。Chromium では click() 時点で参照が取られるため実害が出にくいが、Firefox/Safari では取得前に URL が無効化されてダウンロードが失敗する既知の形。

**再現条件**: 要確認: showOpenFilePicker の無いブラウザ（Firefox）で「SVG」ボタンを押し、ダウンロードが開始されるか（もしくは「ファイルが見つかりません」で落ちるか）を確認すれば決まる。

**確度**: 要確認

**検証の根拠**: コードは記述どおり（src/main.ts:996-1002 の downloadBlob、および 576-580 の非 FS 保存経路とも click() の直後に URL.revokeObjectURL）。ただし取得前に無効化されるかは完全にブラウザ実装依存で、コードからは決まらない。決着させる観測: showOpenFilePicker を持たないブラウザ（Firefox / Safari）で「SVG」「webp」ボタンと Ctrl+S を実行し、ダウンロードが完了するか、ダウンロードマネージャが失敗（ファイルが見つかりません）になるかを見る。Chromium では click() 時点で参照が取られるため実害なし。

**影響**: 非 Chromium ブラウザでエクスポート/保存のダウンロードが無言で失敗しうる。

**修正方針**: revoke を setTimeout(..., 0) もしくは 1 分後に遅延させる。

### P5-非同期-19 / CONFIRMED / `src/main.ts:72`

**idb() が失敗した接続 Promise を永久にキャッシュし、onblocked も未処理**

```
idbConn ??= new Promise((resolve, reject) => {
```

**症状**: open が失敗（プライベートモード、ストレージ不許可）すると reject 済みの Promise が idbConn に残り続け、以後の idbGet/idbSet は全て即 reject する。呼び出し側は全て .catch(() => {}) なので、ファイルハンドルとフォルダ許可の永続化が「静かに全機能停止」する。また onblocked ハンドラが無いため、別タブが古いコネクションを保持していると onsuccess も onerror も来ず、起動時 1115/1122 行の then が永久に解決しない（fileHandle/dirHandle が復元されないまま）。

**再現条件**: 要確認: シークレットウィンドウ + サイトデータのブロック設定で起動し、フォルダ許可やハンドルの復元が一切効かないこと、かつ画面上に何の表示も出ないことを確認する。onblocked のほうは、DevTools で req.onblocked を仕込んで別タブから version 2 で open して観測する。

**確度**: 確定

**検証の根拠**: 前半は成立: src/main.ts:72 の idbConn ??= new Promise(...) は reject 済み Promise も truthy なので二度と作り直されず、以後 idbSet/idbGet(80-96) は即 reject する。呼び出し側は 515・716・768・1121・1133 の全てが .catch(() => {}) なので、ハンドルとフォルダ許可の永続化が完全に無言で停止する。

**検証による訂正**: onblocked の話は落とすべき。indexedDB.open("mmm-store", 1) はバージョンが常に 1 で昇格しないため、通常運用では onblocked は発火しえない（blocked は古いバージョンの接続が開いたままの upgrade 時のみ）。仮に発火しても 1115/1122 の then が解決しないだけで、fileHandle/dirHandle が復元されず Ctrl+S が名前を付けて保存になるにとどまる。

**影響**: 永続化の全面的な無言失敗。最悪ケースで起動時の復元処理が完了しない。

**修正方針**: reject 時に idbConn = null に戻して再試行可能にし、onblocked を reject に繋ぐ。失敗は 1 度だけ flashFilename で通知する。

### P5-非同期-20 / CONFIRMED / `src/main.ts:614`

**ダイアログ抑止にチェックされると confirmDiscard/上書き確認が無言で false になる**

```
return confirm("未保存の変更があります。破棄して続行しますか？");
```

**症状**: confirm/prompt が短時間に繰り返されるとブラウザが「このページでこれ以上ダイアログを表示しない」を提示し、チェックされると以後 confirm() は常に false、prompt() は常に null を返す。その結果 confirmDiscard は常に false となり「開く」もドロップも完全に無反応になる（エラーも出ない）。819 行の上書き確認と 794 行の画像名 prompt も同様に、キャンセル扱いで静かに何も起きなくなる。

**再現条件**: 1) 未保存の変更がある状態で「開く」→ キャンセル、を数回素早く繰り返す。2) ブラウザが提示するチェックボックスをオンにする。3) 以後「開く」ボタンを押してもピッカーすら出ず、何のメッセージも出ない。

**確度**: 確定

**検証の根拠**: src/main.ts:614 の confirm() の戻り値がそのまま confirmDiscard の結果になり、false なら openFile は 519 で、drop は 871 で通知も無く return する。ブラウザの「追加のダイアログを表示しない」が有効化されると confirm は常に false / prompt は常に null を返すため、819 の画像上書き確認（常に false → 保存中止）と 794 の画像名 prompt（常に null → 中止）も同時に無言化する。抑止状態を検出したりフォールバック UI に切り替えるコードは存在しない。

**影響**: 主要な操作が原因不明で無反応になる。

**修正方針**: 破棄確認と画像名入力を popup.ts のアプリ内モーダルに置き換える（既に shell() がある）。少なくとも confirm が false を返したときにログか表示を残す。

### P5-非同期-21 / CONFIRMED / `src/main.ts:714`

**ensureImageDir に同時実行ガードが無く、2 個目のディレクトリピッカーが失敗する**

```
const picked = await window.showDirectoryPicker({ mode: "readwrite" });
```

**症状**: 貼り付け経路が同時に 2 本走ると showDirectoryPicker が 2 回呼ばれ、2 個目は「File picker already active」で reject する。754-761 行の catch は AbortError 以外を失敗扱いにするので「フォルダの許可を取得できませんでした」が誤表示される。

**再現条件**: 要確認: 画像をクリップボードに入れた状態でフォルダ未許可のまま Ctrl+V を素早く 2 回押す。1 回目のピッカーが開いている間に 2 回目の分岐が走れば赤い失敗メッセージが出る（ネイティブピッカーがモーダルのため、2 回目の keydown が到達するかは環境依存 — DevTools から ensureImageDir() を 2 回並列に呼べば確実に再現できる）。

**確度**: 確定

**検証の根拠**: src/main.ts:704-718 に実行中フラグは無く、714 の showDirectoryPicker が並行 2 回呼ばれうる。2 本目は「File picker already active」もしくは user activation 不足で reject し、いずれも AbortError ではないので 756-761 の分岐に落ちて「フォルダの許可を取得できませんでした」が赤表示される。到達性も確認: Mod+V は src/mindmap.ts:1500-1504 の onKeydown 経由で host.paste() を呼び、1325-1326 に e.repeat のガードが無いため Ctrl+V 押しっぱなしのキーリピートで paste() の async IIFE が複数本走る。

**検証による訂正**: 「DevTools からしか確実に再現できない」は不要。Ctrl+V の押しっぱなし（キーリピート）で 2 本目以降が走るのが最も自然な再現経路。なお成立条件は dirHandle 未取得かつ fileHandle 有り（保存済み文書）で、影響は誤った赤表示のみ（データ破壊は無い）。

**影響**: 誤った失敗表示。

**修正方針**: 進行中の ensureImageDir の Promise をモジュール変数にキャッシュして共有する。

### P5-非同期-22 / CONFIRMED / `src/main.ts:605`

**flashFilename の 4 秒タイマーがファイル切り替えを跨ぎ、新しいファイル名が赤いまま残る**

```
flashTimer = window.setTimeout(() => {
```

**症状**: loadText（476 行 elFilename.textContent = name）は flashTimer もクリアせず error クラスも外さない。「保存失敗」などの表示中に別ファイルを開くと、新しいファイル名が最大 4 秒間エラー色で表示され、あたかも新ファイルで失敗したかのように見える。

**再現条件**: 1) 保存を失敗させる（読み取り専用ファイルを選ぶ、または DevTools で createWritable を throw させて Ctrl+S）→ 赤い「— 保存失敗」。2) すぐに別の .md をドロップして開く。3) 新しいファイル名が数秒間そのまま赤で表示される。

**確度**: 確定

**検証の根拠**: flashFilename(src/main.ts:600-610) は 4 秒後にしか error クラスを外さず、loadText(473-488) は flashTimer のクリアも classList.remove("error") も行わない。したがって「保存失敗」表示中に別ファイルを開くと、新しいファイル名が残り時間ぶん赤いまま表示される。

**検証による訂正**: 行番号と挙動を微修正: ファイル名の書き換えは 476 ではなく 475（elFilename.textContent = name）。「— 保存失敗」の文字列自体は loadText が消すので、残るのはエラー色だけ（最大 4 秒）。

**影響**: 軽微だが、無関係なファイルに失敗が起きたと誤解させる。

**修正方針**: loadText の先頭で flashTimer をクリアし error クラスを外す。

### P5-非同期-23 / CONFIRMED / `src/editor.ts:140`

**onUserEdits の例外は CodeMirror の updateListener が握り潰す（両ペインが無言で乖離する）**

```
onUserEdits(edits, userEvent);
```

**症状**: この呼び出しは CodeMirror の updateListener の内側にあり、node_modules/@codemirror/view/dist/index.js:8032-8040 で listener 呼び出しは try/catch + logException に包まれている。したがって onUserEdits → core.replaceText → applySnap → map.render() のどこで throw しても、CM は例外を飲んでエディタの更新だけを完了させる。core のテキストは既に更新済みなので、md ペインだけが進み、nodes/byId/マップは古いまま残る（以後のオフセット計算が全部ずれる）。なお同 8022 行で updateState は listener 実行前に Idle に戻されているため、applySnap 内の editor.highlight() による再入 dispatch は throw しない（この点は問題なし）。

**再現条件**: 要確認: MindMap.prototype.render を 1 回だけ throw するようパッチし、md ペインで 1 文字入力する。文字は入るがマップが更新されず、コンソールには CM の logException 由来の出力しか出ないことを観測すれば確定。

**確度**: 確定

**検証の根拠**: node_modules/@codemirror/view/dist/index.js:8031-8039 で updateListener の呼び出しが try/catch + logException に包まれていること、および 8021-8023 の finally で updateState が listener 実行前に Idle へ戻ることを実物で確認した。src/editor.ts:140 の onUserEdits はその内側なので、core.replaceText 後の applySnap(src/main.ts:180-198)→map.render() が投げても CM は例外を飲んでエディタ側の更新だけを完了させ、core のテキストだけが進んで nodes/byId とマップが取り残される。

**検証による訂正**: 「無言化」は言い過ぎ。logException(index.js:1371-1379) は exceptionSink 未設定なら console.error("update listener:", e) を出す（本プロジェクトは exceptionSink を設定していない）。したがってコンソールには記録が残り、UI にだけ何も出ない。実害の発生には編集パイプラインのどこかが実際に throw する必要があり、その具体経路は未特定。

**影響**: 編集パイプラインの例外が無言化し、両ペインの不整合が蓄積する。

**修正方針**: onUserEdits 全体を自前の try/catch で包み、失敗時は core の状態から強制的に再同期（initDoc し直すか applySnap をやり直す）してユーザーに通知する。

### 反証により除外(3 件)

- **saveFile / openFile / exportMap に多重起動ガードが無く、Ctrl+S 連打が「保存失敗」を誤表示する** — 多重起動ガードが無いのは事実（src/main.ts:847-848, 889-891 とも void saveFile() のみ）だが、症状の機構が誤り。createWritable(src/main.ts:571) は WHATWG File System 仕様・Chromium 実装とも entry に対して shared ロック（mode 既定 "siloed"）を取るため、同一ハンドルに対する 2 本目の createWritable は NoModificationAllowedError にならず成功する（exclusive ロックを取るのは createSyncAccessHandle）。よって 593-595 の分岐に落ちて「保存失敗」が誤表示されるという結論は導けない。同一テキストを 2 回書くだけで内容も壊れない。なお fileHandle が null（無題）のときに限り 564 の showSaveFilePicker が 2 回呼ばれて "File picker already active" で reject し 保存失敗 が出る余地はあるが、それは引用行(571)とは別機構で、しかもピッカーはモーダルなので 2 発目の keydown が届くかは環境依存。エクスポートボタンを 2 回押せば 2 回ダウンロードされるのはユーザ操作どおりの挙動で欠陥ではない。
- **loadAsset が dirHandle と fileHandle を別のタイミングで読む** — 「旧 dirHandle と新 fileHandle の食い違った組」は起こらない。src/main.ts:660 の assetSegs(dirHandle) はローカルに捕まえた値ではなくその時点のグローバル dirHandle を読み、assetSegs は 649-650 で同じ同期区間内に fileHandle を読む（間に await が無い）。したがって base 計算に使われる 2 つのハンドルは常に同一タイミングの組。657 の await を挟むのは「存在チェック」だけで、null になれば 660/649 側で return する。残る本当の食い違いは path キー（旧文書由来）と base（現 fileHandle 由来）のずれで、それは項目 10 の内容。提案された観測（656 と 649 の fileHandle.name 比較）はこの主張の可否を決められない。
- **起動時の idbGet("handle") が名前一致だけで、後から fileHandle を上書きする** — src/main.ts:1119 の照合がベース名のみなのは事実だが、被害の経路が示せていない。IDB のハンドル(persistHandle:514-516) と LS_NAME(483, 586) は openFile(526-527)・drop(875-876)・saveFile(574,586) のいずれでも同じイベント内で一緒に書かれるため、「同名別フォルダのハンドル」と「別ファイルの本文/名前」が対になる状態がそもそも作れない（作れるのは idbSet が失敗して無言で捨てられた場合＝項目 21 の派生ケースのみで、その場合はハンドル自体が保存されない）。後勝ち上書きの方も、1115 の idbGet は起動直後に数 ms で解決するのに対し、ユーザが「開く」を完了するにはファイルピッカー操作が必要で、割り込みは現実的に成立しない。1117-1118 のコメントはこの名前チェックが意図的なガードであることを示している。

