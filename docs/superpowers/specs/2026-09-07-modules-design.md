# modules — core と app に割り、科を名付け直す（設計）

#143 の続き。TS を core に回し終えて、`core` が「CodeMirror 以外ぜんぶ」を指すようになった。
名前が中身を言っていない。ここで module の切り方と科（package）の名を決め直す。

## なぜ

「core が意味、TS が見せ方」の線で `core` と名付けた。#143 で見せ方も帯もファイルも core に
入り、いま本当に残っている線は 2 本しか無い。

1. CodeMirror（TS）と、それ以外（MoonBit）
2. MoonBit の中の、**DOM を知らない半分**（試験が数と字だけで書ける）と **DOM を触る半分**（happy-dom が要る）

2 本目は、この repo で一貫して効いてきた作法（純粋な側は数で試験する）そのものなので、
言葉でなく型で言う — module の境界にする。

## 決め

**2 module。`mmm/core` は純粋、`mmm/app` は DOM。app は core に依存し、逆は無い。**

```
core/   module mmm/core — DOM を知らない。mizchi/js* も moonbitlang/async も import しない
  tree/   md ↔ 木（Doc）
  view/   map が見る木。tree に畳もうとしたが、`Root` / `Node` が tree の同名の型と別物で衝突する —
          自分の型を持つ package なので残す
  op/     操作（Op）と、それを md に映す edit.mbt
  read/   読み（Survey）と、そこから導くもの — 選択の規則・名前・宣言・写し
  map/    置く・当たる・視点・意図の表

app/    module mmm/app — DOM。core に依存し、試験は happy-dom
  app.mbt        App — 束ねる場所（1 トランザクション = 1 サイクルの出口、操作の入口、起動）
  panes.mbt      枠。2 つのペインと分割線
  prefs.mbt      持ち物（theme / color / way / grab）
  shortcuts.mbt  全体のキー
  link.mbt       本文を URL に載せる / 戻す
  bar/           帯（index.html の `#bar`）
    files.mbt    Files の並び
    more.mbt     ⋯ の並び
    export.mbt   書き出し — ボタンと出し方・出し口
    theme.mbt    ロゴ（アクセントカラーの入口）・ライト/ダーク・favicon
    name.mbt     名乗り — ファイル名と改名の入口、未保存の印
  disk/          ディスク
    disk.mbt     Disk — ディスクの上の .md を開く・保存する・改名する
    recent.mbt   覚えている文書と画像フォルダ（IndexedDB の台帳。帯の Recent に並ぶもの）
    images.mbt   画像 — 宣言と許可、置く名前、webp の書き込み
    drop.mbt     落とされたファイルの振り分け
  mindmap/       地図のペイン
    mindmap.mbt  Mindmap そのもの — new・寸法・視点の当て方・render / fit / center / refresh
    input.mbt    入ってくるもの — ホイール・ポインタ・クリック・長押し・キー・右クリックを判断（core/map）に繋ぐ
    act.mbt      出ていくもの — Intent → host の操作、右クリックの行
    marks.mbt    印 — 選択の塗り・輪・矩形・針・落とし先の線
    render.mbt   Layout → SVG の差分（Renderer）
    card.mbt / field.mbt / pick.mbt / host.mbt / measure.mbt
    svg.mbt      1 枚の svg に写す
  parts/         器 — 文書を知らず、値を返す
    icons / notice / hint / tool / menu / ask / asks / draw
  web/           browser の API を 1 行ずつ包む。`_get` / `_call` と extern はここにしか書かない
    dom / svg / fs / canvas / out / drag / clip
  js/            browser への出口（foreign_library。ts が import する）

src/    TypeScript — CodeMirror だけ。app.ts（出口の形）/ state / editor / highlight / main
```

## 名前の原則

当たった資産（Elm の "Life of a File" と guide の Structure、Dave Cheney の Practical Go、
CodeMirror `view` と tldraw `editor` の並び）から 3 つ。

1. **型（概念）の周りに置く。層で割らない。** Model / Update / View で割らない。割るのは
   「helper を何個か持つ型が生まれたとき」。ファイルの長さは理由にならない。
2. **package の名は「何を提供するか」を 1 語で。** `util` / `common` は無い。少数の大きい
   package。中のファイルは持つ型の名（`net/http` の client.go / server.go）。
3. **中心の型は package の名を負ってよい。** `view/EditorView`、`editor/Editor.ts` と同じで、
   `mindmap/mindmap.mbt` の `Mindmap`、`disk/disk.mbt` の `Disk`、`app/app.mbt` の `App`。
   入ってくるものは 1 ファイル（CodeMirror の `input.ts`）。

これで決まったこと:

- `edit`（28 行の 1 関数）は op に畳む。`view` は型が衝突するので残す（上）
- `persist` → `prefs`（動詞でなく物の名）、`share` → `link`（提供するのはリンク）、
  `io` → `disk`・`Io` → `Disk`（Io は何も言わない）、`handles` → `recent`（使う人の言葉）、
  `assets` → `images`（この app の asset は画像だけ）、`dnd` → `drop`、web の `disk` → `fs`
- draw は parts — 窓を開いて絵（Blob）を返すだけで、文書を知らない。ask と同じ側
- link は root — 器ではなく、文書そのものの話。UI が無い
- `spawn`（fire-and-forget の 3 行）は 1 つ、web に

## 却下した案

- **1 module + 純粋/DOM の線はスクリプトが守る** — module は「配る単位」で純粋/DOM は
  「試験の単位」だから軸が違う、と考えたが、配る予定は無く、2 つに割る方が素直。
- **`frame`（帯と枠）** — 中身が場所（帯 / 枠）と機能（書き出し・お絵描き・リンク）と器（たずね）と
  根の都合（キー・持ち物）の混ざり物で、1 語で覆えない。
- **`header`** — この repo では frontmatter を「頭」= `read/head.mbt` と呼ぶ。`head` と `header` が
  並ぶと読むたびに止まる。帯は 1 つなので `bar`。
- **`Pane`（Mindmap の改名）** — 何も言っていない。package が提供するものそれ自体なら名は重なってよい。
- **全部を平らに** — `web` の柵（FFI をここにしか書かない）と `mindmap` の 11 本の塊は package で
  言う価値がある。

## 段取り

3 PR。docs は各 PR で追従する。

1. core を `mmm/core` と `mmm/app` に割る（moon.work の workspace）。edit → op。`check:core` は workspace 全体を回し、
   core の `moon.pkg` に `mizchi/js*` / `moonbitlang/async` が無いことも見る（test/tools/pure.ts）
2. app の科を組み替える。bar / disk / mindmap（input・act・marks に割る）/ parts に draw・ask、root を平らに
3. 改名。prefs / link / disk・Disk / recent / images / drop / fs、`spawn` を web へ、
   `coreApi.ts` → `app.ts`、`map/highlight.ts` → `highlight.ts`、`#topbar` → `#bar`
