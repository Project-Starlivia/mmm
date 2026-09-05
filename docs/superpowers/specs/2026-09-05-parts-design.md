# parts — 部品を状態ごとに並べて見る（設計）

見た目を詰めるための道具。lab に「部品 × 状態 × テーマ」を 1 ページに敷き詰め、
似た部品や隣り合う状態を横に並べて比べながら CSS を直せるようにする。

**見るための道具なので、見た目を 1 つも持たない。** 部品の見た目は `src/`
（builder と `style.css`）にしか無く、ここはそれを呼んで置くだけ。ここに見た目を
書いた瞬間、本体と食い違う。

## 決めたこと

### 1 ページに div で並べる。iframe にしない

最初は「見本 1 つ = 小さなページ 1 枚を iframe で敷き詰める」で作った（本物の
骨格・id・`:root.light`・`fixed` をそのまま出せるため）。触り心地が悪く、
やめた。Storybook も Canvas は iframe だが Docs は inline が既定で、iframe は
「高さを明示しないとスクロールバー」「数が増えると重い」と欠点を列挙している。
living style guide の流儀も「HTML の断片を 1 枚に並べる」。

div で並べるには、**部品が「置き場所を知らない断片」として作れる**ことが要る。
それを本体に入れたのが下の 3 つで、これは道具の都合ではなく本体の質の話
（Storybook を入れても同じだけ要る）。

### 見た目の切り替えは、祖先の class

- ライトは `:root.light` ではなく **`.light`**。トークンは継承する custom property
  なので、どの祖先に付けてもその下だけがライトになる（Shoelace の
  `sl-theme-dark` と同じ流儀）。
- 狭さは道具に持たない。`@media (max-width: 720px)` と `.narrow` が変えるのは
  骨格（帯・ペイン）だけで、部品の見た目は変わらない。帯が builder になったら
  そのときに考える。

### 何個も出しうるものは class、1 個しか無い骨格だけ id

決め方は**個数**。`#app` `#topbar` `#panes` `#md-pane` `#splitter` は 1 個しか無い
ので id のまま。しらせ・カードの印・その場編集の欄・針・矩形・落とし先の線・
マップの SVG・隅の道具・**マップの器**は class に（`.notice` `.card-pick`
`.label-editor` `.card-editor` `.map-indicator` `.rubber` `.drop-line` `.map-svg`
`.pane-switch` `.map-center` `.map-pane`）。

マップの器だけは 2 つに割れる: `#map-pane` は骨格の割り付け（`flex` と
`min-width`、`data-show` で隠す）、`.map-pane` は器の見た目（地の点・
`position: relative`・`touch-action`・焦点の輪）で、`Mindmap` が自分の pane に
付ける。道具は `.map-pane` の div を作って `Mindmap` を立てるだけでよい。

### 作ると置くを分ける

置き場所に結びついていた 4 つを、**中身を組む関数**と**アプリの置き方**に割った。
どちらも本体（`src/`）に居て、道具は前者だけを呼ぶ。

| 部品 | 中身を組む | アプリの置き方 |
|---|---|---|
| しらせ | `notice(mark, msg, sorry)` → `.notice` | `show` が body に 1 個置き、4 秒で消す |
| たずね | `askForm(a, cancel)` → `<form>` | `ask` が `<dialog class="ask">` に載せて `showModal` |
| お絵描き | `drawBoard()` → `.draw`（道具と紙、`undo` / `picture`） | `showDrawing` が同じ窓に載せ、キーと確定を持つ |
| メニュー | `fillMenu(el, items, host)` が行を組み、`menu(items)` は行だけの `.menu` | `ContextMenu` が位置・開閉・焦点・キーを持つ（`MenuHost` として行に応える） |

`<dialog>` の modal は top layer なので枠に閉じ込められない。道具は `<dialog
class="ask" open>` を枠の中に置く（modal でない `open` は流れの中に描かれる）。
`fixed` の部品（しらせ・メニュー）は枠に `contain: paint` を付けると枠が
containing block になり、CSS を触らずに枠の中のその位置へ出る。

### 表 1 つがすべてを動かす

```ts
interface Part {
  name: string;
  /** 状態の名前 → その状態の要素。1 状態 1 行で、呼び方がそのまま見える */
  states: Record<string, () => Element>;
}
export const PARTS: Part[];
```

- 状態は**要素を返す関数**。Storybook の CSF（story = 要素を返す名前付き関数）と
  同じ形にしておく — その日が来たら story ファイルへ機械的に写せる。
- テーマは部品の話ではないので表に持たない。一覧の側が **行 = 部品 × 状態、
  列 = dark / light** に振り、light の列は枠に `.light` を付ける。
- ノード・カードは手で `Box` を組まず、見本の md を `coreApi.survey` に読ませ、
  代役の `MapHost` で本物の `Mindmap` を `.map-pane` の div に立てる。
  `.selected` は host の選択、`.folded` は md の `<details>`、その場編集と
  カードの印は `beginEdit` / `editCard` / `setPicked` の公開の口で開く。

### 置き場所

```
lab/parts/
  index.html   1 ページ。敷き詰めるためだけの最小の CSS
  index.ts     表 → 枠の敷き詰め
  parts.ts     表（PARTS）。DOM の部品
  map.ts       本物の Mindmap を通す部品
  kind.ts      Part の型
```

## 段（stacked PR）

- **refactor/parts-anywhere → main** — 上の「祖先の class」「class と id」
  「作ると置く」。挙動は変えない。この spec もここに入る。
- **feat/parts → refactor/parts-anywhere** — 道具そのもの。
- **その先** — 帯を builder に切り出して載せる。一覧を見ながらの見た目の修正。

## 検証

- `pnpm run check` / `pnpm test`。DOM の組み立ては目で見る（それがこの道具の役）。
- 下の段は、アプリを立ててしらせ・メニュー・たずね・ライトが動くことを目で見る。

## 見送ったもの

- Storybook などの部品カタログ基盤。道具が肩代わりするのは一覧の 100 行だけで、
  本当に要る「断片に直す」仕事は入れても減らない。**見た目の回帰を機械で
  見張りたくなった日**が境目で、そのときは `@storybook/html-vite`。
- iframe。上のとおり。
- 狭さの軸。骨格の話なので、帯が載る段で。
