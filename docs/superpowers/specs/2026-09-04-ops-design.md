# ops — 操作を戻す（設計）

UI の段 3〜5 をまとめて 1 本にする。**木の形を変える・枝を掴んで動かす・カードを
扱う・貼る/落とす/描く**。core（Op と境界）はもう固まっていて、この段は spec.md に
書いてある挙動を Op に写す作業。新しい仕組みは足さない — キーは `keys.ts` の表に
行を足し、Op は `apply` に流し、選択の引き直しは段 1 の目印に任せる。

```
段 1  選択            済（PR #39）
段 2  名前と新規      済（PR #40）
段 3  構造  ┐
段 4  ドラッグ ├ ← この設計（A〜D）
段 5  カード ┘
```

決めの根拠は spec.md「Mindmap 側」「右クリックメニュー」「コンテンツカード」「画像」
「畳む / 消す」、shortcuts.md。Op の意味は core.md「操作の決め」。

## 範囲

| 塊 | 中身 | 旧コードから戻すもの |
|---|---|---|
| A 構造 | Delete / Alt+↑↓ / 複数選択の Tab・Shift+Tab / Shift+H / Flip side / 右クリック / 長押し | menuItems の並び |
| B ドラッグ | ノードの D&D（上 = 子、間 = 兄弟、根の脇 = 側の末尾） | `drop.ts`（`resolveDrop` は純粋。Mod のグループと Shift の割り込みを削る） |
| C カード | カードの選択・キー・×・その場編集・`Shift+L` / `Shift+C` | `pick.ts`、`overlay.ts` の `cardPlacement`、`highlight.ts` の色付き層 |
| D 貼る・落とす・描く | `Mod+V`、ファイルの投下（`.md` と画像）、`Shift+D` | `paste.ts` の判定、`dnd.ts`、`draw.ts`、`assets.saveToDisk` |

**範囲に入れないもの**（理由つき）
- ノードの周りの `+` ボタン — 後でまとめて整備する（ユーザー決）。spec.md の記述は残す
- `Shift+ドラッグ` の割り込み（A→C→B）— `Interpose` が core に後回し
- `Mod+ドロップ` の新しいグループ — グループという概念は無くなった（側だけ）
- 「消す」（`<!-- -->`）— 入口が未決
- 画像フォルダの**宣言の書き込み**（`images:` を frontmatter へ）— frontmatter を書く Op が
  core に無い。画像は宣言があればそこへ、無ければ md の隣（`./`）へ置く。宣言を直す
  のは md で
- カードのドラッグ（別ノードへ / 順番）— `Alt+↑↓` で足りるので後
- 枝の Export（右クリック）— 段の外
- 中身を消した後に選ぶものの決め方 — 持ち主を返すのは core の focus（TS は `keep` を
  持たない。下記「C カード」）

## 共通の決め

- **宛先は anchor、動かすのは選択。** `Delete` / `MoveNode` は選んでいる ids ぜんぶ、
  `Fold` / `Unfold` / `FlipSide` / 編集 / カード追加は anchor 1 つ。祖先と子孫を両方
  選んでいれば子孫は親と一緒に動く（op の決め。TS は何もしない）
- **入口が何であれ意味は 1 つ。** キー・右クリック・長押し・ドラッグの終わり・貼り付け・
  投下・描き終わりのどれも `Intent` を作り、地図（または main）の `act` が実行する。
  メニューの行は Intent の表で、沈む行は理由の字を持つ
- **できない操作は `failed`**（段 2 のまま）。キーの端（前の兄弟が無い等）は null で
  拾わないだけ。core が断る（書けない木）ときだけしらせ
- **選び直しは目印に任せる。** 消す前に隣を選択に据えて `apply` すると、編集列で
  目印が写って消した後の id に引き直される（段 1）。core の focus が在る操作は focus
- **ノードの選択とカードの選択は片方だけ。** カードを選べばノードの選択は外れ、逆も
  同じ（spec.md）。カードの選択は `picked: number | null`（中身の id）で main が持つ

## A 構造

| キー | Intent |
|---|---|
| `Delete` / `Backspace` | 選択が空 → null。`op(Delete(ids), keep = neighbor(L, ids))` |
| `Alt+↑` / `Alt+↓` | 先頭の前の兄弟 / 末尾の次の兄弟が無い → null。`op(MoveNode(ids, Before(prev)))` / `After(next)` |
| `Tab` / `Shift+Tab`（2 つ以上） | 先頭に前の兄弟が無い / 先頭が根 → null。`MoveNode(ids, In(prev))` / `MoveNode(ids, After(親))` |
| `Shift+H` | anchor が無い・Implicit → null。畳んでいれば `Unfold(anchor)`、なければ `Fold(anchor, open=false)` |

- **畳みは 2 状態**（ユーザー決）。`open` は見せない。畳んでいるかは `node.fold !== null`
- **並べ替え・段下げの基準は文書順の先頭と末尾**（ユーザー決）。飛び飛びでも別の
  親からでも Op 1 つ。1 つ選んでいるときの `Tab` / `Shift+Tab` は段 2 のまま
- **消した後は隣**（ユーザー決）: 消す並びの次の見えているノード、無ければ前、無ければ
  先頭の親、無ければ何も選ばない。`neighbor(L, ids)` は `select.ts` の純粋関数で、
  消える部分木（選んだものの子孫）は隣に数えない
- `Intent.op` に `keep?: number`（操作をまたいで選んでおく id）。`apply(op, edit, keep)
  -> number | null` は keep が在れば先に選択に据えてから編集を当て、返った focus を
  ノードの選択かカードの `picked` に振り分ける（`main.ts`）

**右クリック / 長押し** — 押した場所のノードが選択に無ければ単独で選んでから開く。
背景なら閉じる。行は純粋関数 `contextItems(L, sel) -> Entry[]`（`map/context.ts`。
`Entry = Item | "sep"`）で、地図が `MenuEntry` に写す。行の Intent は `keys.ts` と
同じ作り方を引く。

| 行 | キー | 沈む理由（hover で読める） |
|---|---|---|
| **Add ▸**（押せば Child。開けば Child / Below / Above / Parent） | Tab / Enter / Shift+Enter / Shift+Tab | 2 つ以上: "Select one node" |
| Rename | Mod+Enter | 同上 |
| — | | |
| Hide (fold) / Show (unfold) | Shift+H | Implicit: "Nothing to fold here" |
| Flip side | | 根: "The root has no side" |
| — | | |
| Link / Code / Draw | Shift+L / Shift+C / Shift+D | 2 つ以上: "Select one node" |
| — | | |
| Delete | Del | — |

指の長押し（`HOLD_MS`）で同じメニュー。ネイティブの `contextmenu` と二重に開かない
（届いたほうが勝ち）。長押しで開いたジェスチャーは使い切り — 離した `pointerup` で
タップ選択しない。

## B ドラッグ

ノードを掴んで動かす。`pointerdown` で掴む候補を覚え、slop を越えたら始まる。
掴んだのが選択の中ならその全部、外なら単独で選び直してそれ。

**落とし先は純粋関数 `resolveDrop(scene) -> Drop | null`**（`map/drop.ts`。旧コードを
削って戻す）。`Drop` を Op にするのは同じファイルの `dropOp(drop, ids) -> Op`。

```
Drop = { kind: "node", id, pos: 0 | 1 | 2 }   // 0 = 子の末尾 / 1 = 直前 / 2 = 直後
     | { kind: "side", root, left }            // 根の脇。その側の末尾
```

| Drop | Op |
|---|---|
| node, 0 | `MoveNode(ids, In(id, side: null))` |
| node, 1 / 2 | `MoveNode(ids, Before(id))` / `After(id)` |
| side | `MoveNode(ids, In(root, side: left ? Left : Right))` |

- 落とし先の優先順は旧コードのまま（箱の中 → 前後の帯 → 外側ゾーン → 列の上端・下端）。
  Shift の線への割り込みと Mod のグループは削る（Op が無い）
- **掴んでいる部分木は落とし先から外す**（自分の中へは落とせない。core も `None` と言う）
- 予告: 落ちる先の箱に印（`drop-parent`）、兄弟挿入なら間に線（`drop-line`）。
  ノードの外ではブラウザのカーソルが受けないと言う（旧コードの絵をそのまま）
- 離したら Op。`Escape` でやめる。指では「なぞれば動かす」（spec.md「指で使う」）—
  長押しがメニューを開いたらドラッグにしない

## C カード

**選ぶ**: カードをクリックで選ぶ、もう一度で外す。`picked` は中身の id。ノードの
選択は外れる。枠と右上の × は world に浮かぶ 1 つの印（`pick.ts`）。md 側では
その中身の範囲が薄く塗られる（中身の地番。下記「core に足すもの」）。

持ち主（中身がぶら下がるノード）を探すのは `ownerOf(L, block)`（`map/layout.ts`）。
表は純粋関数 `keyedCard(L, picked, key) -> Intent | null`（`map/keys.ts`）:

| 入力 | Intent |
|---|---|
| `Delete` / `Backspace` / × | `op(Delete([picked]))` — focus（持ち主）は core が返すので `keep` は持たない |
| `↑` / `↓` | 隣のカード（端で null）。`{ kind: "pick", id }` |
| `←` | 持ち主のノードを選ぶ（`select`） |
| `Alt+↑` / `Alt+↓` | `MoveBlock([picked], Before(前)/After(次))`（端で null） |
| `Mod+Enter` | その場編集（`{ kind: "editCard", id }`） |
| `Esc` | 外す |

ダブルクリックも同じその場編集を開くが、`keyedCard` の表ではなく `mindmap.ts` の
クリック処理が直に開く（キーではないので）。

**その場編集**: カードに重ねた `<textarea>`（裏に色付きの層。`highlight.ts` の
`tokenizeBlock`）。値は**その中身の原文**（地番で md から切り出す）。閉じるのは
`Esc` / `Mod+Enter` / 他所を押す。確定は `SetBlock(id, Opaque(値))` 1 回 — 原文を
そのまま書き戻し、読みが種類を決め直す。ラベルと違って**閉じるときに書く**
（コードは打っている途中の中間状態が md に流れると、フェンスが割れて木が壊れる）。
`Mod+Z` は欄の中では欄のもの（段 2 の決めと同じ）

**足す**（anchor に対して。段 2 の「足してそのまま編集」と同じ形）:

| 入力 | Op | その後 |
|---|---|---|
| `Shift+L` | クリップボードの URL → `AddBlock(In(anchor), Link(text: "", href: url, title: ""))` | 足したカードを題の上で編集 |
| `Shift+C` | `AddBlock(In(anchor), Code(info: "", text: ""))` | 本文行で編集 |
| `Shift+D` | 描く窓 → 保存 → `AddBlock(In(anchor), Image(alt: "", src: 相対パス, title: ""))` | — |

URL でなければ `failed("Couldn't read that as a link")`。

## D 貼る・落とす・描く

**`Mod+V`**（anchor に対して。無ければ文書へ）。判定は純粋関数
`decidePaste(clip, hasSkeleton) -> Paste`（`app/paste.ts`）。`hasSkeleton` は
呼び出す側（`main.ts`）が渡す関数で、「見出しや項目があるか」は **core に読ませて
決める**（`core.survey(clip, [], []).view.trees` が空かどうか。読みの規則を TS で
書き直さない）。画像はテキストより先にクリップボードを覗いて main.ts が別に処理する
（`decidePaste` には来ない）。

| クリップボード | Op |
|---|---|
| 画像 | 保存 → `AddBlock(In(anchor), Image)` |
| URL 1 つ | `AddBlock(In(anchor), Link)` |
| 骨格の無い字（木が空） | 行ごとに子: `AddNode(In(anchor), labels)`。anchor が無ければ `AddNode(In(doc), labels)` |
| 骨格のある md | `Graft(In(anchor), md)`。anchor が無ければ `Graft(In(doc), md)` |

**ファイルの投下**（`app/dnd.ts` を戻す）: `.md` はその文書を開く（保存の確認は今の
`confirmDiscard`）。画像はノードの上に落ちたときだけ受け、保存 → `AddBlock(Image)`。
ドラッグ中はノードの上で落ちる先に印、外ではカーソルが受けないと言う。

**描く**（`app/draw.ts` を戻す）: `Shift+D` で窓。確定で `Blob` → 保存 → `AddBlock(Image)`。

**保存**（`assets.saveToDisk(blob)` を戻す）: 置き場所は宣言があればそこ、無ければ md の
隣。保存していない文書は `ensurePlace` の駅（今の Choose folder と同じ）。WebP への
変換と名前の決め方は旧コードのまま。**宣言は書かない**（上の範囲外）。

## core に足すもの

- **中身の地番。** `survey` の表に中身（Block）の行も載せる（`from` = 原文の範囲、
  `label` は None）。`number_blocks` の隣で範囲を控え、`chart` が出す。指紋
  `spans_sig` に中身の行が増える。使い道: カードを選んだときの md 側の薄塗り、
  その場編集の原文の切り出し
- **`Opaque` を ts から送れるように。** `Content` に `{ kind: "opaque"; text }` を足し、
  `encode` は `Svg` と同じく位置で渡す（`Opaque(String)`）。View には今までどおり来ない

`Delete(ids)` は中身の id も受ける（op の決め）。`MoveBlock` / `SetBlock` / `AddBlock` は
#35 で在る。core の変更はこの 2 つだけ。

## 構成

```
core/tree/build.mbt          中身の地番（Frame.body_at、doc の body_at）
core/tree/spans_wbtest.mbt   指紋に中身の行
src/coreApi.ts               Content.opaque、encode の位置渡し
src/map/select.ts            neighbor(L, ids)、parentOf / prevSibling / nextSibling、solo
src/map/keys.ts              Intent に keep / pick / editCard。keyed に A・C の行、
                              keyedCard(L, picked, key) を足す
src/map/context.ts           contextItems(L, sel) -> Entry[]（純粋）
src/map/drop.ts              resolveDrop、dropOp（戻す。Shift / Mod を削る）
src/map/pick.ts              CardPick（戻す）
src/map/card.ts              cardPlacement（純粋）と CardEditor（<textarea> + 色付き層）
src/map/layout.ts            ownerOf(L, block)（中身の持ち主を探す）
src/app/paste.ts             decidePaste（core に読ませる）
src/app/dnd.ts               initDrop（戻す）
src/app/draw.ts              showDrawing（戻す）
src/app/assets.ts            saveToDisk（戻す）
src/mindmap.ts               contextmenu / 長押し / ドラッグ / カードの選択と編集 / act の増分
src/main.ts                  apply(op, edit, keep) -> number | null、picked、
                              貼り付け・投下・描く・保存の配線
src/style.css                drop-line / drop-parent / card-picked / card-kill / #card-editor
test/select.test.ts          neighbor / siblings
test/keys.test.ts            A・C の行
test/context.test.ts         行と沈み方
test/drop.test.ts            落とし先（旧試験を削って戻す）
test/card.test.ts            cardPlacement
test/paste.test.ts           decidePaste（core を通す）
```

## 試験

- core: 中身の地番の指紋（spans_wbtest）
- 純粋層は表で固定: `neighbor` / `siblings`、`keyed` の行、`contextItems`、`resolveDrop`、
  `cardPlacement`、`decidePaste`
- DOM の配線は `pnpm run check` と煙試験。**レビューはこの段では core と純粋層だけ**に
  付け、配線は最後の枝全体のレビュー 1 回で見る（ユーザー決）
- 煙試験: Delete の連打 / Alt+↑↓ / 複数 Tab / Shift+H で +N / 右クリックの各行と沈み /
  ドラッグで子・兄弟・側 / カードを選んで × ・↑↓・Alt+↑↓・その場編集 / Shift+L・C・D /
  貼り付けの 4 種 / `.md` と画像の投下。指の長押しと IME は手で

## 段

`feat/ops`（`.worktrees/feat/ops`、feat/tree から）。1 塊 1 コミット以上、最後に 1 PR で squash。

1. core — 中身の地番、ts — `Content.opaque`
2. A — select の道具 / keys の行と keep / context / メニューと長押しの配線
3. B — drop.ts と試験 / ドラッグの配線と予告
4. C — pick / card.ts / カードのキーと編集 / Shift+L・C
5. D — saveToDisk / paste / dnd / draw / 配線
6. docs — spec.md「構成」、core.md「地番」 → 煙試験 → PR
