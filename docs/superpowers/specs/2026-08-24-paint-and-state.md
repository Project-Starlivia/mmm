# 描画と、いまの操作の状態

## なぜ

「CSS と SVG を組む部分が、制御と密になっていて膨大」という引っかかりから。

調べて測った結果、**密になっていたのは CSS ↔ 制御ではなかった**。
`render` が「制御がすでに知っている状態」を毎回導出し直していた。

```ts
cls = "node" + root + link-card + hidden-node + selected + dragging + dropMark
```

`selected` も `dragging` も `dropMark` も、それを変えた本人が知っている。
なのに render が 6 ビットを文字列に畳み直し、`nodeCls` にキャッシュして差分を
取っていた。だから:

- `refreshSelection` に「クラスを直接触ったらキャッシュも合わせる」という
  同期の注意書きが要った
- `dropMarks` は「render のクラス計算にも合流させてある」という二重管理だった
- クラスを付ける経路が `markNode`（直接 classList）と render（文字列組み立て）の
  **2 本**あった

## 測ったこと

**`mindmap.ts` は 1 つの物か。** メソッド 46 個がどのフィールドに触るかを出し、
フィールドの連結成分を取った（constructor は全部に触るので除外）:

```
37 個: cardDrag cardDrop cardEditor composing dragCand dragging drop*
       edit* host hoverId k layout menu order pane panning polyOf
       renderer rubber* spaceDown suppressClick tx ty viewport …
 1 個: fitPending
```

**38 のうち 37 が 1 つの塊**。分けると状態が国境をまたぐので、
ファイル分割は複雑さを増やすだけ（Ousterhout の classitis）。
**割らずに、関心事をまたぐ「橋」を減らす**のが正しい方向だった。

**`render.ts` の `draw()` 300 行の内訳:**

| | |
|---|---|
| カード 4 種の**形**を組む部分 | 151 行（50%） |
| `String(...)` 変換 | 47 回 |
| `svgEl(...)` | 22 回 |

「膨大」の実体はカードの形と、数値→文字列の儀式だった。

## 決めたこと

### 1. 構造は描画、状態はそれを変えた本人（A）

`draw()` が触るクラスは、**文書から決まるもの**だけ:

- `node` / `root` / `hidden-node`

`selected` / `dragging` / `drop-child` / `drop-parent` は、変えた本人が
`classList` で付ける。描き直しで要素が作り直されたときのために、
`MindMap.paintState()` が **`draw()` の直後に同じ印を被せ直す**。

`Scene`（描画に渡すもの）は 6 項目 → **2 項目**（レイアウトと画像 URL）。
`nodeCls` キャッシュも、その同期の注意書きも消えた。

**重要**: `draw()` は `setAttribute("class", …)` を使ってはいけない。
まるごと書くと、付けた本人しか知らない印を巻き添えで消す。
1 つずつ `classList.toggle` する。

### 2. 選択の枠と × は「1 個だけの印」（B）

**選ばれているカードは常に高々 1 枚**。なのに枠と × をそのノードの子要素として
作っていたため、選ぶ / 外すたびに `NodeShape.picked` が変わり、そのノードの
中身が丸ごと作り直されていた。つまり:

> **コードカードをクリックして選ぶだけで、そのコードが再トークナイズされていた**
> （`tokenize` に memo は無い）

落とし先の線（`#drop-line`）と同じく、world 座標に浮かぶ 1 個の印
（`src/map/pick.ts` の `CardPick` / `#card-pick`）にした。

副産物:
- `render` はカードの選択を**一切知らなくなった**
- `main.ts` の「選択のために地図を描き直す」経路が消えた
- `toSvg` の「書き出しから選択枠を要素ごと落とす」処理が要らなくなった
  （そもそも写す 2 層に入っていない）

枠は `pointer-events: none`。素通りさせないと、もう一度押して外せない。

### 3. 状態で変わるだけの定数は CSS（C）

線引きはこう:

> **レイアウトが計算した数だけが TS。状態で変わるだけの定数は CSS。**

SVG2 で `x` / `y` / `width` / `height` / `rx` / `ry` は CSS プロパティ
（`rx`/`ry` は Baseline 2024）。**属性より CSS が勝つ**ことを実機で確認した
（Chrome 148: 属性 `rx="8"` があっても `.node.hidden-node rect.box { rx: 4px }`
が効く）。

```css
.node rect.box { rx: 8px }
.node.hidden-node rect.box { rx: 4px; stroke-dasharray: 4 3 }
```

`code-bg` の 5px、`img-ph` と `card-picked` の 6px も同様に CSS へ。

なお `link-card` クラスは**誰も読んでいなかった**ので落とした。

## 見送ったこと

### `<template>` でカードの形を宣言する（D） → **不採用**（2026-08-25 に決着）

`draw()` の半分を占めるカード 4 種の形を `index.html` の `<template>` に置き、
`cloneNode(true)` して変わる値だけ埋める案。当初「保留」としていたが、
手段を一通り調べ直して**採らないと決めた**。

**当初の売り文句のうち、速度は嘘だった。** Chrome 148 で 2000 ノード
（= 24000 要素）を組む時間を測った:

| 組み方 | 中央値 |
|---|---|
| `createElementNS` + `setAttribute`（現状） | 95.3ms |
| `<template>` clone + `querySelector` で埋める | 83.2ms |
| `<template>` clone + 子の位置で辿って埋める | 72.2ms |

13〜24% 速いが、**実負荷は 1 打鍵で作り直すノードが 1 個**なので、
0.048ms が 0.036ms になるだけ。差し引きゼロ。

残る理由は損のほうだけになる:

- 埋める側が `querySelector` で clone に入るので、**形と埋め方の対応を型が
  守らない**
- **`<svg>` で包まないと中身が XHTML 名前空間になり**、エラーも出さずに
  何も描かれない（実測。`<svg>` で包めば正しく SVG 名前空間になる）
- 形が `index.html` へ出ていくと **CSS の隣には来るが、数を出している TS から
  離れる**。Locality of Behaviour として差し引きで負ける

### 同時に調べて落とした手段

| 手段 | 落とした理由 |
|---|---|
| `<symbol>` + `<use>` | use の中は shadow tree でスタイルが届かない。**値を持たない固定の絵**にしか効かず、mmm の ↗ × ＋ は文字なので困っていない |
| `<foreignObject>` + HTML/CSS | flexbox にレイアウトを任せられる唯一の案だが、**`toSvg.ts` の書き出しが壊れる**（ブラウザ以外で開けない SVG になる）。描画コストの報告も多い |
| Web Components | **SVG では定義できない**。custom element は HTML 名前空間のみ（W3C で議論中の未実装） |
| タグ付きテンプレート（自作 / uhtml / lit-html） | いちばん宣言的だが、依存か 100 行超の機構を足すことになる。**膨大を減らすために膨大を足す**形 |
| CSS `attr()` 型付き | Chromium 133+ で前提には合うが、**数を出すのは結局 TS**。経由地が増えるだけ |
| DOM Parts / Template Instantiation | TAG レビュー保留、Gecko/WebKit のシグナル無し。待つ対象ですらない |

### 代わりに採ったこと（2026-08-25）

機構を足さずに同じ観点を満たす 3 つ。

1. **`svgEl` が数を受け取る** — `String(...)` が 44 か所消えた。SVG の属性は
   ほとんどが数で、文字にするのは `setAttribute` に渡す 1 行だけの仕事
2. **`map/drawCard.ts`** — カード 1 行を SVG にする層。種類ごとに形・クラス・
   埋め方が縦に並ぶ。`render.ts` は「どこに置くか」だけを決める（399 → 265 行）。
   同時に、置き場所を描画とマップが別々に数えていた重複を `layout.cardRect`
   1 本に畳んだ
3. **CSS のネスト** — ブラウザ自身の機能で、部品ごとの塊にした。487 行が
   フラットで区切りも無く、`.node` の規則が `#card-pick` を挟んで散っていた

いずれも**出力が変わっていないことを実測で確かめている**。2 は構造・幾何・
計算済みスタイルが baseline と完全一致。3 は旧 CSS と新 CSS を同じページに
順に当てて、ダーク / ライト × 3 状態 × 全要素 × 63 プロパティが完全一致。

### Signals / 細粒度リアクティビティ

TC39 Signals は **Stage 1**（API 未確定）。それ以前に、mmm は
「テキストが唯一の真実 → 毎回全部導出」なので**購読元がそもそも無い**。
いまの差分レンダラが実質同じ役割を果たしている。追わない。

### `mindmap.ts` の分割

測定が否定した（37/38 が 1 塊）。行数ではなく橋の本数を見る。

## 参照

- [htmx — Locality of Behaviour](https://htmx.org/essays/locality-of-behaviour/)
  … 「振る舞いはそのコードだけを見て分かるべき」。技術で分けた結果 1 機能の
  理解に 3 ファイル往復するなら偽の分離。ただし**宣言**は明白に / **実装**は
  抽象化してよい、と線を引いている
- [A Philosophy of Software Design（Ousterhout）](https://milkov.tech/assets/psd.pdf)
  … deep module と classitis。小さいクラスはインターフェースが累積して
  系全体を複雑にする
- [Geometry Properties — SVG 2](https://svgwg.org/svg2-draft/geometry.html) /
  [MDN `rx`](https://developer.mozilla.org/en-US/docs/Web/CSS/rx)
- [MDN — data 属性](https://developer.mozilla.org/en-US/docs/Web/HTML/How_to/Use_data_attributes)
  … 状態を `data-*` で出すのは Radix / Headless UI 系の定石。今回は既存の
  セレクタが `.node.selected` で読めているので**クラスのまま**にした。
  得られるもの（独立して付け外しできる）は同じ
- [tc39/proposal-signals](https://github.com/tc39/proposal-signals)
- [Template in a SVG context does not have any content — WICG/webcomponents #744](https://github.com/WICG/webcomponents/issues/744)
  … `<svg>` の中に `<template>` は置けない（SVGTemplateElement が無い）。
  HTML の `<template>` の中に `<svg>` ごと書くのが唯一の道
- [Styling SVG `<use>` Content with CSS — Codrops](https://tympanus.net/codrops/2015/07/16/styling-svg-use-content-css/)
  / [w3c/svgwg #504](https://github.com/w3c/svgwg/issues/504) … use の shadow tree
- [Don't use foreignObject HTML for text in SVG output — drawio #3350](https://github.com/jgraph/drawio/issues/3350)
- [Proposal: Allow custom elements to be in any namespace — WICG/webcomponents #634](https://github.com/WICG/webcomponents/issues/634)
- [CSS attr() gets an upgrade — Chrome for Developers](https://developer.chrome.com/blog/advanced-attr)
- [Template-Instantiation.md — WICG/webcomponents](https://github.com/WICG/webcomponents/blob/gh-pages/proposals/Template-Instantiation.md)

## この作業で見つけた別の不具合

`Mod+クリック`で**文書順と逆**にノードを追加選択すると、MD ペインの
ハイライトが例外で丸ごと死んでいた（`Ranges must be added sorted by from`）。
選択は `Set` で**入れた順**なのに、CodeMirror は昇順を要求する。
今回の変更より前から在ったもので、`Decoration.set(…, true)` で直した。
