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

### `<template>` でカードの形を宣言する（D）

`draw()` の半分を占めるカード 4 種の形を `index.html` の `<template>` に置き、
`cloneNode(true)` して変わる値だけ埋める案。

- 得: **形が宣言として見える**（CSS の隣に形がある = Locality of Behaviour）。
  生成も clone のほうが速い
- 損: 埋める側が `querySelector` で clone に入るので、**形と埋め方の対応を
  型が守らない**

**保留。** 上の 1〜3 で `draw()` から状態の分岐が抜けたので、残る形の記述が
どう見えるかを見てから判断するほうが安い。テンプレートエンジンの導入とは
別物（ブラウザの素の機能）だが、手段は慎重に選ぶ。

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

## この作業で見つけた別の不具合

`Mod+クリック`で**文書順と逆**にノードを追加選択すると、MD ペインの
ハイライトが例外で丸ごと死んでいた（`Ranges must be added sorted by from`）。
選択は `Set` で**入れた順**なのに、CodeMirror は昇順を要求する。
今回の変更より前から在ったもので、`Decoration.set(…, true)` で直した。
