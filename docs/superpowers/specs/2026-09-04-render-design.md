# render — View を map に映す（設計）

feat/tree で作り直した core（読み → Doc → View）を、`src/` の map に繋ぐ。
**描くだけ。** 選択・ドラッグ・その場編集・ノード操作は含めない（操作の API が
まだ無い。span も無いので、誠実に埋められない）。

## 決めたこと

### 境界

- **core が意味、TS が見せ方。** TS が持つ木は core の View 1 つだけで、形を変えない
  （平らな列に潰さない、種類の旗を足さない）
- **操作系は消す。** `main.ts` / `mindmap.ts` のうち core の操作 API と NodeInfo の
  span に依るもの（3,600 行）は、`notYet` で残さず git に預ける。リポジトリの今は
  動くものだけを表す。span と操作 API が揃った段で戻す
- **id は差分キャッシュの鍵にだけ使う。** render の id → DOM の Map は残すが、
  id は文書順の位置なので、上に 1 つ足せば以降が作り直されるだけ。正しさは壊れない
  （docs/core.md「id は読みのサイクルを越えて持たない」）

### 層

「何を入力に何を出すか」と「どの語彙で話すか」で切る。

```
md ──parse──> Doc ──project──> View          core: 意味。語彙は Tree / Node / Side / Fold / Block
                                 │
                            coreApi.view       境界: JSON の形を整えるだけ。語彙は core のまま
                                 │
      ┌──── cards ────┐   Block → CardRow      分類: 何をカードとして見せるか。寸法も DOM も知らない
      │               │
      └─── metrics ───┘   label + CardRow → w/h   寸法: フォント計測を知る唯一の場所
                                 │
                              layout           配置: View + 寸法 → Box。畳みの埋没もここ
                                 │
                       render + drawCard        描画: Box → SVG の差分。画像 URL は関数で外から受ける
                                 │
                              camera            視点: world ↔ screen。木を知らない
```

横から刺さるのは **assets**（frontmatter → フォルダ → path → URL。render には `imageUrl`
として渡すだけ）と **shell**（editor / file / theme / panes / export / share。
サイクル `text → view → layout → render` を回す本人）。

**語彙の規則**

- **core の語（View / Tree / Node / Side / Fold / Block）は読むだけ。書き換えも言い換えも
  しない。** Box が `node` を持つのは参照であって再符号化ではない
- **TS では必ず持ち主を付けて `core.View` / `core.Node` と書く。** `import * as core from
  "./coreApi.ts"`（型だけなら `import type * as core`）。裸の `View` はフロントに出ない
  （フロントの view は画面を意味する。`Node` は DOM のグローバル型とも衝突する）。
  MoonBit の `@view.Tree` と同じ形
- **map の語（CardRow / Box / Edge / Camera）は cards / layout から先にしか出ない。**
  core は「カード」も「箱」も知らない
- **見せ方の裁定は 1 か所ずつ**: fold → layout（埋める）、Block → cards（カードにするか）、
  Implicit → 裁定なし（`label` が null なら字が無いだけ。metrics と render は
  `label ?? ""` で読む）、`sides` → layout の zip 1 か所、`Side` → 符号は geometry の
  `dirOf` 1 か所
- **id を鍵にするのは Map だけ**（layout の boxes、render のキャッシュ）

**改名**

- `src/map/view.ts` の `View { k, tx, ty }` → **`Camera`**、ファイルは `map/camera.ts`。
  world を画面へ写す変換（位置と倍率）で、graphics の viewport（見えている矩形）は
  `Pane` のほう。core の View と同名では mindmap で両方を import できない
- `app/panes.ts` の `project` → core の `project` と被る。改名候補（この段では触らない）

**寸法を metrics に寄せる**: `rowH` / `cardInset` / `cardBleed` / `IMG_MIN_W` /
`CODE_LINE` / `CODE_PAD` は cards.ts から metrics.ts へ。cards は分類だけを持つ。
drawCard は metrics を見る。

### core: View に frontmatter を足す

画像フォルダの宣言 `image-folder:` は frontmatter にあり、画像カードの解決に要る。
今の `project` は `Array[Tree]` を返し、文書単位の欄を置く場所が無い。

```moonbit
pub(all) struct View {
  frontmatter : String?
  trees : Array[Tree]
}
pub fn project(doc : Doc) -> View
```

「削るだけ」は変わらない。frontmatter は Doc が持っていて、落とすのをやめるだけ。
`project_wbtest` の期待値が 1 段深くなる。**これが唯一の core 変更。**

### TS の受け口（coreApi.ts）

```ts
export type Side = "Right" | "Left";
export interface Fold { open: boolean; summary: string | null }
export type Block =
  | { kind: "image"; alt: string; src: string; title: string }
  | { kind: "link"; text: string; href: string; title: string }
  | { kind: "code"; info: string; text: string }
  | { kind: "svg"; markup: string }
  | { kind: "thematicBreak" }
  | { kind: "details"; id: number; text: string };
export interface Node {
  id: number;
  label: string | null;      // Implicit は null。空の見出しは ""
  fold: Fold | null;
  blocks: Block[];
  children: Node[];
}
export interface Tree { node: Node; sides: Side[] }
export interface View { frontmatter: string | null; trees: Tree[] }
export function view(md: string): View;   // mmmViewJson を読む唯一の場所
```

使う側は `import * as core` で `core.View` / `core.view(md)` と書く。

MoonBit の ToJson は `Option` の None を鍵ごと落とし、enum を `["Image", {…}]` /
`"ThematicBreak"` の形で出す。**その形を整えるのはここ 1 か所**で、以降の TS は
`kind` で分岐する。JSON の信頼境界は旧 coreApi と同じくここだけ。

### layout: 木をそのまま歩く

入力は `Tree[]`。再帰で `children` を辿り、幾何だけを足す。

```ts
interface Box {
  node: Node;             // View のノードそのまま。label / fold / blocks はここから読む
  parent: Edge | null;    // 根は null。側は「親との繋がり」の性質
  buried: number;         // 畳んで埋もれた子孫の数（全部の子孫。種類で除かない）
  fan: number;            // 親の辺の上での付け根のずらし(px)。兄弟と出口が重ならないように。幾何
  x: number; y: number; w: number; h: number;
  rows: CardRow[];        // node.blocks から組んだもの。寸法に要るので持つ
}
interface Edge { id: number; side: Side }
interface Layout {
  order: number[];        // 描くノードの id、文書順（= 重なり順）
  boxes: Map<number, Box>;
}
```

- **側**は根の子が `sides[i]` から受け、孫以降は親の Edge から継ぐ。長さが足りなければ
  `Right`（check が見る不変条件。TS は既定値で受ける）
- **符号 `1 | -1` は geometry.ts の中だけ。** `dirOf(side)` を置く場所はそこ 1 つ
- **グループの継ぎ目は消える**（`seams` / `GAP.group` / `sideGroups` / `.group-seam`）。
  spec「グループという概念は無い」
- **畳み（`fold` が在る）はここで埋める。** 子孫を `order` にも `boxes` にも入れず、
  `buried` に数を残す。project で落とさないのは、数を core が足すことになり
  「削るだけ」が崩れ、map で開く道も閉じるため
- `root` / `folded` / `left` / `depth` の欄は持たない。`node` と `parent` から出る

### Implicit と fold の見え方

- **Implicit は「ラベルの無いノード」。** 空の見出し（`""`）と同じ `.empty` の箱で、
  render に Implicit の分岐は 1 つも入らない。core.md「ノードの種類は無い。描く側には
  1 つも要らない」のとおり。行があるか無いかは書く側の関心
- **fold**: 字は `node.label`（`fold.summary` は書き戻す綴りで、古くなりうる）。
  小さく薄く `+N`。自分のカードも出さない（body ごと包まれている）。
  `open` は見ない（spec「今は隠すだけ」）。Box は `node.fold` をそのまま持つので、
  後で見ると決めても形は変わらない

### cards: Block から組む。from/to は持たない

```ts
export type CardRow =
  | { kind: "link"; title: string; url: string }
  | { kind: "img";  path: string; name: string }
  | { kind: "svg";  markup: string }
  | { kind: "code"; lang: string; lines: string[] };
export function cardRows(blocks: Block[]): CardRow[];
```

- `image` は相対パス（scheme 無し。1 文字はドライブ）のときだけ img。外部の画像は出さない
- `link` は `http(s)` のときだけ。題が空ならホスト名
- `code` は行に割り、6 行を超えたら `…`。`svg` はそのまま
- `thematicBreak` / `details` はカードにしない（Details は spec「今は隠すだけ」）
- TS 側の md 読み（`parseLink` / `parseImage` / フェンス走査 / `linkLine` /
  `imageDest`）は消える。`bare` だけ残す（画像の鍵）
- カードは表示専用。pick / その場編集 / 移動 / 削除は無い

### 残す / 落とす

**残す**

- `editor.ts` — 打鍵 → `view(text)` → 描画の 1 本。`applySets`（差分適用）と
  `highlight`（カーソル同期）は外す
- file I/O 一式: `io` / `handles` / recent / `name`（最初の根のラベル）/ dirty / favicon
- `theme` / `panes` / `paneTool` / `hint` / `share`（URL ハッシュ）/ `persist` / `logo` / `icons` /
  `map/menu.ts`（export の出し方メニューの器）
- `export` — 全体だけ（枝の選択が無い）。SVG / WebP / PNG コピー / SVG コピー
- `assets` — フォルダの接続と `imageUrl`。`retarget`（宣言の引っ越し）と
  `attachImage`（貼り付け）と**宣言の書き込み**（`settle` / `saveToDisk`）は操作なので
  落とす。宣言が無い文書は `./`（md と同じ場所）として読み、指したフォルダが宣言と
  食い違っても直さない。`head.ts` は `imageFolder(frontmatter)` だけになる
- map の純粋層: geometry / camera（← view）/ edge / metrics / drawCard / render / highlight /
  svg / toSvg / indicator / gesture
- mindmap: pan・zoom・pinch・fitView・根へ寄せる・画面外の針（的は根）・書き出し

**落とす**（git に残る）

- `edits.ts` / `caret.ts` / `map/drop.ts` / `map/navigate.ts` / `map/overlay.ts` /
  `map/pick.ts` / `map/addButtons.ts` / `map/radialMenu.ts` / `app/form.ts` /
  `app/paste.ts` / `app/dnd.ts` /
  `app/draw.ts` / `app/shortcuts.ts` のうち操作のキー
- `test/edits.test.ts` / `test/addButtons.test.ts`
- style.css の対応する塊（選択・ドラッグ・落とし先・入力欄・メニュー・継ぎ目）

### scripts / CI / docs

- `dev` / `build` / `test` / `check` / `preview` / `deploy` / `deploy:dry` を戻す。
  `check` は `tsc --noEmit && tsc -p test --noEmit && pnpm run check:lab`
- `test/tsconfig.json` の include から消えたファイルを外す
- CI に型検査・UI テスト・vite build・dist の受け渡しを戻す（ci.yml の注記のとおり）
- spec.md「構成」を今の形に直す（「core が揃うまで触らない」を外す、消えたファイルを
  消す、`View` の欄を足す）。core.md「View」に frontmatter を足す

## 段

feat/render（`.worktrees/feat/render`、feat/tree から）に 1 段 1 コミット。
最後に 1 PR で feat/tree に squash。

1. core: `View` に frontmatter、`project_wbtest` を直す。scripts を戻す
2. `coreApi.ts`（JSON の整形）と `cards.ts`（Block → CardRow）、寸法を metrics へ。単体テスト。
   `map/view.ts` → `map/camera.ts`
3. `layout.ts` を木に。単体テスト（sides の zip・畳みの埋没・複数の木・Implicit が
   空の箱になる・`parent` の側の継承）
4. `metrics` / `render` / `toSvg` を Box に付け替え
5. `mindmap` / `main` / `editor` / `assets` / `head` を削って配線。死んだファイルと
   style を消す。docs と CI。ブラウザで確認

## 決めていないこと（この段では触らない）

- fold の `open` をどう出すか
- Implicit に打ったとき何を書くか（操作の段）
- 打鍵ごとの parse + project + JSON 往復の性能。lab に fixtures を流して測る
