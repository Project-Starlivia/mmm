# 新 core 実装計画 — 正誤表（修復する 5 人の唯一の参照元）

この文書は、査読 3 本（致命 18 / 重大 18 / 軽微 16）と統括の裁定 1〜10、および実測結果を突き合わせて確定させた**改訂版の契約**である。
以後、`plan/contract.md` と `plan/t1.md`〜`t5.md` の記述がこの文書と食い違ったら、**この文書が勝つ**。

以下、`<REPO>` = `D:/1.atrium/mmm/.claude/worktrees/doc-model` と書く。実際のコマンド・Files 欄には**必ず展開した絶対パス**を書くこと。

---

# A. 改訂後の設計契約（全文）

## A-0. 版と、前の契約からの変更点（読み飛ばし禁止）

| # | 変更 | 根拠 |
|---|---|---|
| 1 | `pub typealias Path = Array[Int]` → **`pub type Path = Array[Int]`** | 実測 1（`typealias` は `[3002]` パースエラー） |
| 2 | **境界を struct が跨がない**。`core/doc/wire.mbt` を新設し、`core/doc/js/exports.mbt` は String / Int / Bool / Array[Int] しか触らない | 裁定 3 |
| 3 | 不変条件に **11 番「implied ⇒ side = Right」**を追加。`flip_side` は implied を**昇格させてから**反転する | 裁定 1（仕様 §2 と カタログ C16 は統括が改訂済み） |
| 4 | `- - -` は **飾りの水平線（Rule）**。旧 core の「前から箇条書き」方言は**捨てる** | 裁定 2 |
| 5 | `spell.mbt` の所有者は **T1**（11 定数の完全版）。`block.mbt` は **T1 が仮置きを Create、T2 が Modify で本実装** | 裁定 4 |
| 6 | `tree_wbtest.mbt` を**廃し**、`fixture_wbtest.mbt`（T1 所有）に wbtest の共有ヘルパを全部集約する | 裁定 4 |
| 7 | 指紋 `sig` の `esc` に **`~` `^` `<` `\r` を追加**（フラグと label の取り違えで別の木が同じ指紋になる穴を塞ぐ） | 本正誤表 §A-4 |
| 8 | `pub(all)` は**一切使わない**。`not(x)` は**使わない**（`!x`）。`rev_inplace` / ArrayView の `to_array` は**使わない**（`rev_in_place` / `to_owned`） | 実測 3・6・11 |
| 9 | `check` は 10 → **11 条件**。`spell.mbt` は 8 → **11 定数** | 裁定 1・4 |

## A-1. ファイル構成

パッケージ名 **`mmm-app/core/doc`**（モジュール `mmm-app/core` の下）。モジュールは足さない。

```
core/doc/
  moon.pkg              pkgtype(kind: "library")
  ast.mbt               木の型・指紋・不変条件の検査
  spell.mbt             正規形の綴りの定数（11 個。綴りのリテラルはここにしか置かない）
  line.mbt              行の走査。文字と空白の道具
  scan.mbt              行 → かたまり（Chunk）の並び
  block.mbt             かたまり 1 つの中身の認定（Content か Rule か Opaque か）
  build.mbt             かたまりの並び → 木
  parse.mbt             読みの入口（scan → build）
  serialize.mbt         木 → 正規形の md
  form.mbt              form が行き先に従う規則
  op.mbt                操作の共通の道具（結果・道・頂点集合・不変条件の回復）
  move.mbt              動かす
  side.mbt              側を返す
  delete.mbt            消す
  edit.mbt              Edit の型と、当てる関数
  diff.mbt              2 つの全文 → Edit の列
  reflect.mbt           反映 v0
  wire.mbt              外と文字列だけでやり取りする面（木は JSON 文字列にする）
  js/
    moon.pkg            pkgtype(kind: "foreign_library") + import { "mmm-app/core/doc", }
    exports.mbt         #export_name の薄い層。String / Int / Bool / Array[Int] だけ
```

`core/doc/js/moon.pkg` は**別名を書かない**（実測 7-2 — `moon fmt` は最終パスセグメントと同じ別名を剥がすので `@doc` と書くと必ず差分が出る。既定の別名が `doc` なので、コードからは `@doc.…` で参照できる）:

```
pkgtype(kind: "foreign_library")

import {
  "mmm-app/core/doc",
}
```

`core/doc/moon.pkg`:

```
pkgtype(kind: "library")
```

生成物は `core/_build/js/release/build/doc/js/js.js`。旧 `.../build/js/js.js` と**同じ 1 回の `pnpm run core`** で並んで出るので `package.json` の `"core"` は無変更。足すのは 1 行だけ:

```json
"test:doc": "moon -C core test -p mmm-app/core/doc"
```

**`"test:core"` は触らない**（旧 core は無変更の原則）。通しで回すときは `pnpm run test:core && pnpm run test:doc`。

**表に無いファイルを作ってはならない。** 必要になったら、作る前に §B の表に足すことを全員へ共有する。

## A-2. 型の全文（`core/doc/ast.mbt`）

**そのまま写して着手してよい。T1 Task 1 の成果物。**

```moonbit
// 文書の木。綴りは持たない — 綴りは serialize が所有する。
// オフセットも持たない（法則 1 の比較対象を増やさないため）。
// 反映 v1 のすげ替えで骨格スパンが要るようになったら `implied : Bool` を
// `skel : Span?` に替えるが、読みは常に `is_implied` を通すので呼ぶ側は変わらない。

///|
/// 文書ひとつ。head は封筒（中は解釈しない）、doc は木そのもの（深さ 0）。
pub struct Ast {
  head : String? // frontmatter の逐語。開き `---` 行頭から閉じ `---` 行末まで（末尾改行を含まない・改行は "\n" に畳む）
  eol : Eol // 原文の流儀。serialize が全行をこれで書く
  doc : Node // 深さ 0 のノード。body = 最初の骨格行より前、children = 木の列
}

///|
pub enum Eol {
  Lf
  Crlf
} derive(Eq, Debug)

///|
/// ノード。**level は持たない — level は木の深さそのもの**（飛びは implied が埋めるので
/// 親子の差は常に 1）。持つと深さと食い違う状態が書けてしまう。
pub struct Node {
  id : Int // セッション限り。parse が文書順に 1 から振る（doc が 1）
  form : Form // 意味。見出しか項目か
  label : String // 骨格行の中身。implied は必ず ""
  implied : Bool // 骨格行を持たない（level 飛びが綴り）。存在条件は §A-3 の不変条件
  folded : Bool // 畳み。綴りは details
  side : Side // **深さ 2（root 直下のスロット）だけが意味を持つ**。他は必ず Right。
  //           **implied は深さによらず必ず Right**（飛びには側を書く場所が無い）
  body : Array[Block] // 骨格行の後・最初の子の前の中身
  children : Array[Node] // 子。Item が先、Heading が後（順序法則）
}

///|
pub enum Form {
  Heading
  Item
} derive(Eq, Debug)

///|
pub enum Side {
  Right
  Left
} derive(Eq, Debug)

///|
/// 中身のかたまり 1 つ。
pub enum Block {
  Content(Content) // 認定ブロック。serialize が同じ綴りを書き戻せる形だけがここへ来る
  Rule // 飾りの水平線。綴りは `***` に正規化（トグルの `---` とはチャンネルが違う）
  Opaque(String) // 散文・引用・表・HTML・謎。逐語
} derive(Eq, Debug)

///|
/// 認定ブロック。**疑わしきは Opaque** — ここに来るのは
/// 「serialize が書き戻した綴りを parse すると同じ値に戻る」形だけ。
pub enum Content {
  Image(alt~ : String, src~ : String) // ![alt](src)
  Link(text~ : String, href~ : String) // [text](href)
  Code(info~ : String, text~ : String) // ```info … ```（インデントコードもここへ読む）
  Svg(String) // <svg …>…</svg> 逐語
} derive(Eq, Debug)

///|
/// 骨格行を持たないか。**implied の判定は必ずこれを通す**（v1 で中身が替わる）。
pub fn is_implied(nd : Node) -> Bool {
  nd.implied
}

///|
/// 空のノード 1 つ。
pub fn empty(id : Int, form : Form) -> Node {
  {
    id,
    form,
    label: "",
    implied: false,
    folded: false,
    side: Right,
    body: [],
    children: [],
  }
}

///|
/// 骨格行を書く = 昇格。implied はこの瞬間に普通のノードになる。
pub fn promote(nd : Node, label : String) -> Node {
  { ..nd, label, implied: false }
}
```

**綴りの規律（全員）**

- `pub(all)` は使わない。境界を跨ぐのは String / Int / Bool / Array[Int] だけなので不要（実測 3）
- ラベル付き enum ペイロードは **定義と `match` は `~`、呼び出しは `=`**（実測 4）
  - 定義: `Image(alt~ : String, src~ : String)`
  - match: `Content(Image(alt~, src~)) => …`
  - 呼び出し: `Content(Image(alt="a", src="b.png"))` — **`alt~="a"` は `Error: [3016]`**
- 論理否定は `!x`。`not(x)` は deprecated（実測 6）
- 型の別名は `pub type X = Array[Int]`。`typealias` は無い（実測 1）
- パッケージ内の struct は `priv struct`（既存 repo の綴りに合わせる）。`pub` を付けるのは §A-2 / §A-5 に挙げた型だけ
- `mut` フィールドは**定義パッケージ内で必ず一度は書く**（書かないと `Error: [0015] unused_mut` でビルドが止まる。実測 3-e）
- `derive(Show)` は使わない（deprecated）。`derive(Debug)` は `to_string` を生やさないので、文字列にしたければ `match` で書く
- 文字列のスライス `s[a:b]` は**サロゲートの途中で切ると panic する**（実測 8）。オフセットは常に行境界／コードポイント境界であることを前提にすること。検査なしが要るなら `String::unsafe_substring(s, start~, end~)`
- `s[i]` の型は **`UInt16`**（`Char` ではない）。`Char` が要るなら `.iter()` / `.to_array()`。`String::charcodes` は存在しない
- deprecated な Array API を書かない: `rev_inplace` → **`rev_in_place`**、ArrayView の `to_array` → **`to_owned`**

## A-3. 不変条件（`check` が返すメッセージも、この文字列で固定する）

```moonbit
///|
/// 不変条件の違反。空なら健全。テストと debug の assert がこれを見る。
pub fn check(ast : Ast) -> Array[String]
```

| # | 条件 | 違反時のメッセージ（逐語） |
|---|---|---|
| 1 | doc は form=Heading・label=""・implied=false・folded=false | `doc が汚れている` |
| 2 | id は木の中で一意 | `id が重複: <id>` |
| 3 | Item の子孫はすべて Item（単調性） | `Item の下に Heading: <id>` |
| 4 | 同じ親の children は Item が先・Heading が後（順序法則） | `順序法則の違反: <id>` |
| 5 | implied ⇒ form=Heading | `implied が Item: <id>` |
| 6 | implied ⇒ label=""・body=[]・folded=false | `implied が中身を持つ: <id>` |
| 7 | implied ⇒ children.length() > 0（存在条件） | `implied に子が居ない: <id>` |
| 8 | implied ⇒ 親の children の先頭 | `implied が先頭でない: <id>` |
| 9 | implied ⇒ 子はすべて Heading | `implied が Item の子を持つ: <id>` |
| 10 | 深さ 2 以外のノードは side=Right | `深さ 2 でない側: <id>` |
| **11** | **implied ⇒ side=Right（裁定 1）** | **`implied が側を持つ: <id>`** |

- `<id>` は `id.to_string()` をそのまま埋める。前後に空白を入れない
- 4 は **doc 直下にも効く**（R042）。doc も「同じ親」の 1 つである
- 11 は 10 と独立である（深さ 2 の implied が Left を持つ場合は 10 を通り 11 で落ちる）。**この穴が法則 1 を破っていた**（査読 1 の致命）
- 違反メッセージは**改行を含まない**。`wire.mbt` の `check_of` が `"\n"` で綴じ、TS 側が `split("\n")` で戻す

**11 の帰結（裁定 1、全員が守る）**
- `flip_side` は、対象が implied なら `promote(nd, nd.label)` してから反転する（`side.mbt`。T5 Task 46）
- `normalize` の `spellable` は「飛びで綴れない位置の implied を昇格させる」の一般化としてこれを含む（`op.mbt`。T5 Task 44）
- 木の生成器 `gen_ast` は **implied に Left を割り当てない**（`law_wbtest.mbt`。T4 Task 33）
- serialize / parse の区切りの帰属規則は**現状のまま**でよい（穴が閉じるので変更不要）
- カタログのケース **C16 は統括が追加済み**（`2026-08-29-op-cases.md:701`）。**5 人は仕様とカタログを書き換えない**

## A-4. 指紋 `sig` の形（1 文字も曖昧さを残さない）

```moonbit
///|
/// 木の指紋。**id を含まない** — 法則 1・2 の比較子はこれ 1 本。
pub fn sig(ast : Ast) -> String
```

**逃がし（`esc`。`ast.mbt` の private 関数。T1 所有）**

`s.iter()`（コードポイント）で回し、次だけを置き換える。それ以外はそのまま書く。

| 入力 | 出力（2 文字） |
|---|---|
| `\` | `\\` |
| `\|` | `\\|` |
| `[` | `\[` |
| `]` | `\]` |
| `~` | `\~` |
| `^` | `\^` |
| `<` | `\<` |
| U+000A | `\n` |
| U+000D | `\r` |

> `~` `^` `<` を逃がすのは**必須**である。逃がさないと、label が `^x` の畳んでいないノードと、label が `x` の畳んだノードが**同じ指紋 `[H^x]` になる**（`<` も同様、`~` も「label が `~` のノード」と implied が衝突する）。法則 1 の比較子が別の木を同一と見なす穴になる。
> `\r` は落とさず**見えるようにする**。逐語文字列に `\r` は入らない（§A-7 前提 1）ので、出たら T1 の畳みの漏れが即座に分かる。

**全体の形**

```
sig(ast) = "head:" + H + "\n" + E + "\n" + node_sig(ast.doc)
  H = ast.head が None なら "-"、Some(h) なら esc(h)
      （head は必ず `---` で始まり 7 文字以上なので、"-" と衝突しない）
  E = ast.eol が Lf なら "lf"、Crlf なら "crlf"

node_sig(nd) = "[" + F + G + esc(nd.label) + B + C + "]"
  F = nd.form が Heading なら "H"、Item なら "I"
  G = フラグ。この順で、立っているものだけを書く:
        nd.implied なら "~"
        nd.folded  なら "^"
        nd.side が Left なら "<"
  B = nd.body の各要素 b について "|" + block_sig(b) を順に連結（body が空なら空文字列）
  C = nd.children の各要素 k について node_sig(k) を順に連結（children が空なら空文字列）

block_sig(b) =
  Opaque(t)                     → "o:"    + esc(t)
  Rule                          → "rule"
  Content(Image(alt~, src~))    → "img:"  + esc(alt)  + "|" + esc(src)
  Content(Link(text~, href~))   → "link:" + esc(text) + "|" + esc(href)
  Content(Code(info~, text~))   → "code:" + esc(info) + "|" + esc(text)
  Content(Svg(t))               → "svg:"  + esc(t)
```

**固定の例（テストがこの逐語を焼き込む）**

| 木 | 指紋 |
|---|---|
| 空文書 | `head:-\nlf\n[H]` |
| `# r` | `head:-\nlf\n[H[Hr]]` |
| `# r` + `## a` | `head:-\nlf\n[H[Hr[Ha]]]` |
| `# r` + `#### b`（implied 2 段） | `head:-\nlf\n[H[Hr[H~[H~[Hb]]]]]` |
| `# r` + `- x`（左・画像 1 枚） | `head:-\nlf\n[H[Hr[I<x\|img:a\|b.png]]]` |
| 裁定 1 の C16 の結果（implied が昇格して Left） | `head:-\nlf\n[H[Hr[H<[H~[Hb]]]]]` |

## A-5. 公開関数のシグネチャ（全部）

### 読みと書き

```moonbit
// core/doc/parse.mbt
///|
/// md を木にする。**この関数は決して書かない**。id は文書順に 1 から振る（doc が 1）。
pub fn parse(md : String) -> Ast

// core/doc/scan.mbt
///|
/// 走査の結果。行の並びだけで分かることの全部。
pub struct Scan {
  head : String? // frontmatter の封筒（逐語。改行は "\n"、末尾改行なし）
  eol : Eol // 最初に見つかった改行の流儀
  chunks : Array[Chunk] // 文書順
}

///|
/// かたまり 1 つ。**空行は落とす**（空行の本数はモデルに存在しない情報）。
pub struct Chunk {
  depth : Int // 骨格行なら自分の深さ。それ以外は「所属する構造の深さ」（文書直下は 0）
  kind : Kind
}

///|
pub enum Kind {
  Skel(Form, String) // 骨格行。form と label（深さは Chunk.depth）
  Break(Bool) // 水平線。true = 空白を 1 つも含まない `---`（トグル候補）／false = それ以外（必ず飾り）
  Fold(Bool) // true = <details> ／ false = </details>
  Body(Block) // 中身のかたまり 1 つ
}

///|
/// 行から区間へ。**md の読みの全部がここに居る**（木は知らない）。
pub fn scan(md : String) -> Scan

// core/doc/build.mbt
///|
/// かたまりの並びを木にする。implied の導出・側の割り当て・畳みの対応付けはここ。
pub fn build(sc : Scan) -> Ast

// core/doc/block.mbt
///|
/// 逐語のかたまり 1 つを Block にする。**疑わしきは Opaque**。
pub fn classify(text : String) -> Block

// core/doc/serialize.mbt
///|
/// 木を正規形の md にする。**mmm のフォーマッタそのもの**。決定的・冪等。
pub fn serialize(ast : Ast) -> String

// core/doc/ast.mbt
pub fn sig(ast : Ast) -> String
pub fn check(ast : Ast) -> Array[String]
pub fn is_implied(nd : Node) -> Bool
pub fn empty(id : Int, form : Form) -> Node
pub fn promote(nd : Node, label : String) -> Node
```

### 操作

```moonbit
// core/doc/op.mbt
///|
/// 操作の結果。拒否は例外ではなく値。
pub enum Outcome {
  Done(Ast)
  Reject(Reject)
}

///|
pub enum Reject {
  Missing // 指された id が木に居ない
  Cycle // 自分（か自分の子孫）の中へ動かそうとした
  Ineligible // その操作の資格があるノードが 1 つも無い
} derive(Eq, Debug)

///|
/// 木の中の道（children の添字の列。doc は空の列）。
/// **`pub type`。`pub typealias` は存在しない**（実測 1）。
pub type Path = Array[Int]

pub fn path_of(ast : Ast, id : Int) -> Path?
pub fn tops(ast : Ast, ids : Array[Int]) -> Array[Path]

///|
/// 不変条件の回復。**すべての操作の最後に必ず通す**。
pub fn normalize(ast : Ast) -> Ast

// core/doc/move.mbt
pub fn move_nodes(ast : Ast, ids : Array[Int], parent : Int, at : Int) -> Outcome

// core/doc/side.mbt
///|
/// 側を返す。root（深さ 1）なら鏡像、深さ 2 のスロットならそれ 1 つ。他は資格が無い。
/// **対象が implied なら promote してから反転する**（裁定 1）。
pub fn flip_side(ast : Ast, ids : Array[Int]) -> Outcome

// core/doc/delete.mbt
pub fn delete_nodes(ast : Ast, ids : Array[Int]) -> Outcome

// core/doc/form.mbt
pub fn to_item(nd : Node) -> Node
pub fn refit(nd : Node, parent : Form, siblings : Array[Node], at : Int) -> Node
```

### 反映

```moonbit
// core/doc/edit.mbt
///|
/// 1 つの置き換え。オフセットは**旧全文上の UTF-16 コード単位**。
pub struct Edit {
  from : Int
  to : Int
  insert : String
} derive(Eq, Debug)

pub fn apply(text : String, edits : Array[Edit]) -> String

// core/doc/diff.mbt
///|
/// **v0 は行境界で共通接頭辞・接尾辞を刈った 1 ハンクだけ。**
pub fn diff(old : String, new_ : String) -> Array[Edit]

// core/doc/reflect.mbt
pub fn reflect(old : String, ast : Ast) -> Array[Edit]
```

### 外との面（`core/doc/wire.mbt`。**裁定 3**）

**struct は境界を跨がない。** 木を外へ出すときは JSON 文字列にする。JSON の組み立ては `mmm-app/core/doc` の内側（この 1 ファイル）で完結し、`js/exports.mbt` は String / Int / Bool / Array[Int] しか触らない。

```moonbit
// 外と文字列だけでやり取りする面。UI 接続の公開 API ではない —
// テスト（TS 側のコーパス・ファズ）の受け口としてだけ在る。

pub fn sig_of(md : String) -> String // parse して指紋
pub fn format_of(md : String) -> String // serialize(parse(md))
pub fn check_of(md : String) -> String // 不変条件の違反を "\n" 区切りで。空なら健全
pub fn tree_of(md : String) -> String // 木の JSON（§D で鍵を固定）
pub fn apply_op(
  md : String,
  op : String, // "move" / "flip" / "delete"
  ids : Array[Int],
  parent : Int,
  at : Int,
) -> String // 操作 1 回の JSON（§D で形を固定）
```

内部の道具（同じファイル。private）: `json_str` / `json_block` / `json_node` / `form_tag` / `side_tag` / `eol_tag` / `bool_lit` / `reject_tag`。JSON は `StringBuilder` で手組みする（依存ゼロを保つ）。

### JS の受け口（`core/doc/js/exports.mbt`）

```moonbit
///|
#export_name("docSig")
pub fn doc_sig(md : String) -> String {
  @doc.sig_of(md)
}

///|
#export_name("docFormat")
pub fn doc_format(md : String) -> String {
  @doc.format_of(md)
}

///|
#export_name("docCheck")
pub fn doc_check(md : String) -> String {
  @doc.check_of(md)
}

///|
#export_name("docTree")
pub fn doc_tree(md : String) -> String {
  @doc.tree_of(md)
}

///|
#export_name("docApply")
pub fn doc_apply(
  md : String,
  op : String,
  ids : Array[Int],
  parent : Int,
  at : Int,
) -> String {
  @doc.apply_op(md, op, ids, parent, at)
}
```

**`#export_name` はこの 5 本だけ。増やさない。** `Array[Int]` を境界に置くのは旧 `core/js/exports.mbt` に前例がある（`delete_nodes(ids : Array[Int])` 他）。

### 範囲外（今回作らない。名前だけ予約）

`project` ／ `format` / `convert` コマンド ／ `add` / `rename` / `fold` / `setForm` / `indent` / `outdent` / content 系 ／ すげ替え v1 ／ 旧 core の削除。**触らないこと。**

## A-6. `spell.mbt` の全文（11 定数。T1 Task 1 が作る完全版）

**綴りのリテラルはこのファイルにだけ置く。** Image / Link の `![` `](` `)` は綴りの選択肢が無い記法そのものなので定数化しない（ここは「選べる綴り」の置き場）。

```moonbit
// 正規形の綴りの定数。**綴りのリテラルはこのファイルにだけ置く。**

///|
let item_mark : String = "-" // 項目のマーカー（`*` `+` は読みのみ）

///|
let heading_mark : String = "#" // 見出しの印（setext は書かない）

///|
let nest_step : Int = 2 // 入れ子 1 段の字下げ

///|
let fence_mark : String = "`" // コードのフェンス（`~` は読みのみ）

///|
let fence_min : Int = 3 // フェンスの最小の本数

///|
let rule_mark : String = "***" // 飾りの水平線

///|
let toggle_mark : String = "---" // 側の変わり目

///|
let fold_open : String = "<details>"

///|
let fold_close : String = "</details>"

///|
let summary_open : String = "<summary>"

///|
let summary_close : String = "</summary>"
```

Task 1 の時点ではどれも未使用なので `Warning (unused_value)` が並ぶ。**警告でビルドは止まらない**（`--deny-warn` は付けない）。

## A-7. serialize の規則（T3 が満たすもの）

**統合の前提（全員で共有する取り決め）**

1. **逐語の文字列（`Ast.head` / `Opaque` / `Code.text` / `Svg`）の改行は `"\n"` に畳んで保持し、末尾改行を含まない。** CRLF 文書でも `\r` を残さない（**T1 の責務**。`scan_head` と `dedent` が行ごとに `\r` を落として `"\n"` で綴じる）。serialize が `ast.eol` の流儀で書き戻す
2. **parse は `<summary>` 行を落とす**（R107）。ただし**落とすのは `<details>` の直後に置かれた 1 行だけ**（裁定 7。本文の `<summary>…</summary>` は消さない）。serialize は毎回 label から作り直す

**規則**

1. head があれば逐語で書き、空行 1 本を挟む
2. 改行は `ast.eol` の流儀で全行。文書は必ず改行で終わる（空文書は `""`）
3. 見出し: `heading_mark` × 深さ + 半角空白 + label。**空ラベルでも空白 1 つを書く**（`### `）
4. 項目: 字下げ + `item_mark` + 半角空白 + label。字下げ = 祖先の連続する Item の数 × `nest_step`（親が Item でなければ 0）
5. 見出しの継ぎ目は空行 1 本。リストは**常に tight**。例外は「リスト形ノードの body に段落系（Image / Link / Opaque）がある」ときだけ（Code はフェンスが段落を中断できるので tight のまま）
6. body は骨格行の後、children の前。リスト形ノードの body はそのノードの中身の列まで字下げする
7. `Rule` は `rule_mark`。トグルはスロットの側の変わり目にちょうど 1 本 `toggle_mark`（先頭スロットの前に置けば左開始）
8. `Code` は常にフェンス。本数は「中身に現れる最長の連続バッククォート + 1」と `fence_min` の大きい方
9. 畳みは骨格行の**外側**に `fold_open` / `fold_close` を置き、body と children だけを包む。項目形なら中身の列まで字下げする。`<summary>` に label を書く
10. **段落の直後に `toggle_mark` を置かない**（setext に化けるため。空行 1 本を必ず挟む）
11. **implied は骨格行を書かない**。implied が side を持つことは §A-3 の 11 で禁じられているので、「側を書く場所が無い implied」は serialize に到達しない

## A-8. 設計判断（変更なし。理由の要約だけ再掲）

① implied は `Bool`（変種にも Option スパンにもしない）— 場合分けの増殖を型で強制しない。網はファズが張る
② `level` フィールドを持たない（深さがそのまま level）— move で付け直しが要らなくなる
③ `side` は `Node` のフィールド 1 つ（root だけ型の違う子を持たせない）
④ **区切りの帰属は「次のかたまり」で決める**: `Break(true)` の極大の連なりの直後が「深さ 2 の `Skel`」なら全部トグル（本数のパリティで側が決まる）。そうでなければ直前のノードの body の `Rule`
⑤ 飾りの水平線は `Block::Rule`（`Opaque` の例外にしない）
⑥ Content の認定は「書き戻せる形」だけ — 少しでも外れたら `Opaque`
⑦ implied の綴れる位置 — 不変条件 8・9・11 の根拠。**昇格の引き金は 3 つ**（label/body/folded を持たされた／親の children の先頭でなくなった／Item 親の下へ来た・Item の子を持った）に加え、**裁定 1 の 4 つ目「側を持たされた」**。**消える引き金は 1 つだけ**（children が空になった）
⑧ 木は再帰で書く。`test/fixtures/deep.md` の 200 段を法則テストの入力に必ず含める
⑨ 既存 `parser.mbt` からの持ち込みは契約 §4-⑨ のとおり。**書き直す**のは: 単一変数 `content_col` → コンテナのスタック／`SepRun` のチャンネル併合 → `Break(Bool)` の分離／`HideRegion` と `in_comment` → `Fold` の深さスタック／`prev_text` の setext 抑制 → setext の読み／`Heading` をテキスト区間として持つ設計 → 木
⑩ オフセットは UTF-16 コード単位（変換層は要らない）
⑪ 可変フィールドを 1 つも持たない（`{ ..nd, children: kids }` の構造体更新で組み直す）

---

# B. ファイル所有権の表

**所有者だけが Create / Modify できる。表に無いファイルを作ってはならない。**
「読むだけ」= import / 呼び出しはしてよいが 1 バイトも書き換えない。

## B-1. `core/doc/`（実装）

| ファイル | 所有 | Create | 他タスクの権限 |
|---|---|---|---|
| `moon.pkg` | T1 | T1 Task 1 | 読むだけ |
| `ast.mbt` | T1 | T1 Task 1 | 読むだけ（型は 5 人の共有物。変えるなら**書き換える前に全員へ共有**） |
| `spell.mbt` | **T1** | T1 Task 1 | 読むだけ。**T2・T3 は作らない**（裁定 4） |
| `line.mbt` | T1 | T1 Task 4 | 読むだけ。`indent_of` / `is_blank` / `lead_spaces` / `blank_line` は T1 の所有名 |
| `scan.mbt` | T1 | T1 Task 5 | 読むだけ |
| `block.mbt` | **T2** | **T1 Task 8**（仮置き `classify` 1 本だけ） | T2 が Modify で本実装。**T2 は Create しない**（裁定 4） |
| `build.mbt` | T2 | T2 Task 12 | 読むだけ |
| `parse.mbt` | T2 | T2 Task 17 | 読むだけ |
| `serialize.mbt` | T3 | T3 Task 20 | 読むだけ |
| `form.mbt` | T5 | T5 Task 42 | 読むだけ |
| `op.mbt` | T5 | T5 Task 43 | 読むだけ |
| `delete.mbt` | T5 | T5 Task 45 | 読むだけ |
| `side.mbt` | T5 | T5 Task 46 | 読むだけ |
| `move.mbt` | T5 | T5 Task 47 | 読むだけ |
| `edit.mbt` | T5 | T5 Task 40 | 読むだけ |
| `diff.mbt` | T5 | T5 Task 40 | 読むだけ |
| `reflect.mbt` | T5 | T5 Task 41 | 読むだけ |
| `wire.mbt` | **T4** | T4 Task 31 | 読むだけ |
| `js/moon.pkg` | T4 | T4 Task 31 | 読むだけ |
| `js/exports.mbt` | T4 | T4 Task 31 | 読むだけ |

## B-2. `core/doc/`（テスト）

| ファイル | 所有 | Create | 他タスクの権限 |
|---|---|---|---|
| `fixture_wbtest.mbt` | **T1** | T1 Task 2 | **T5 Task 43 だけが、`done` / `rejected` の 2 関数を末尾に追記してよい**（`Outcome` は T5 Task 43 で初めて存在するため）。それ以外は読むだけ |
| `ast_wbtest.mbt` | T1 | T1 Task 1 | 読むだけ |
| `line_wbtest.mbt` | T1 | T1 Task 4 | 読むだけ |
| `scan_wbtest.mbt` | T1 | T1 Task 5 | 読むだけ。**T2 は触らない**（裁定 5 により T1 の期待値は classify に依存しなくなった） |
| `block_wbtest.mbt` | T2 | T2 Task 10 | 読むだけ |
| `build_wbtest.mbt` | T2 | T2 Task 12 | 読むだけ |
| `serialize_wbtest.mbt` | T3 | T3 Task 20 | 読むだけ |
| `law_wbtest.mbt` | T4 | T4 Task 33 | 読むだけ |
| `form_wbtest.mbt` | T5 | T5 Task 42 | 読むだけ |
| `op_wbtest.mbt` | T5 | T5 Task 43 | 読むだけ |
| `delete_wbtest.mbt` | T5 | T5 Task 45 | 読むだけ |
| `side_wbtest.mbt` | T5 | T5 Task 46 | 読むだけ |
| `move_wbtest.mbt` | T5 | T5 Task 47 | 読むだけ |
| `diff_wbtest.mbt` | T5 | T5 Task 40 | 読むだけ |

**`tree_wbtest.mbt` は作らない**（`fixture_wbtest.mbt` に統合。裁定 4）。
ブラックボックス（`*_test.mbt`）は 1 本も書かない。

## B-3. TS 側とその他

| ファイル | 所有 | Create | 他タスクの権限 |
|---|---|---|---|
| `test/_doc.ts` | **T4** | T4 Task 32 | **T5 は import するだけ。自前の型・自前の `applyEdits` を定義しない**（裁定 4） |
| `test/doc-law.test.ts` | T4 | T4 Task 30 | 読むだけ |
| `test/doc-dialect.test.ts` | T4 | T4 Task 36 | 読むだけ |
| `test/doc-ops.test.ts` | T5 | T5 Task 48 | 読むだけ |
| `test/_helpers.ts` | 既存 | — | **T4 Task 30 が `corpus()` の除外名 1 行（`:171`）だけ Modify**。他は誰も触らない |
| `package.json` | 既存 | — | **T4 Task 33 が `"test:doc"` の 1 行だけ追加**。`"test:core"` を含め他は触らない |
| `docs/superpowers/specs/2026-08-29-doc-model-design.md` | 統括 | — | **5 人とも触らない**（憲法。裁定 1 の改訂は反映済み） |
| `docs/superpowers/specs/2026-08-29-op-cases.md` | 統括 | — | **5 人とも触らない**（C16 は追加済み） |
| `docs/superpowers/specs/2026-08-29-recover-reject.md` | T5 | T5 Task 49 | R138 / R176 の成果物 |
| `docs/superpowers/specs/2026-08-29-kill-check.md` | T5 | T5 Task 50 | 殺す条件の判定結果（裁定 10） |
| 旧 core（`core/*.mbt`・`core/js/`）・`src/`・既存 `test/*.test.ts` 26 本 | — | — | **1 バイトも触らない** |

---

# C. 名前の割り当て表（パッケージ内で一意）

`mmm-app/core/doc` は**すべての `.mbt`（`*_wbtest.mbt` を含む）でトップレベルの名前空間を 1 つ共有する**（実測 2）。同名のトップレベル定義は `Error: [4051] The toplevel identifier X is declared twice` でビルドが止まり、**テストが 1 本も走らなくなる**。

## C-1. 衝突していたもの — 確定した割り当て

| 名前 | 衝突していた 2 者 | 裁定 | 書き換える側 |
|---|---|---|---|
| `indent_of` | T1 `line.mbt` `(text, l) -> (Int, Int)` ／ T2 `block.mbt` `(line) -> Int` | **T1 の綴りを正**とし、T1 が String 版も所有する（裁定 4「T2 は再定義せず使う」） | **T2**: `block.mbt` の定義を削除し、`line.mbt` の `lead_spaces(s : String) -> Int` を呼ぶ。呼び出し 3 か所（`is_rule_text` の `let mut i = indent_of(text)` ／ `is_fence_close` の `let mut i = indent_of(line)` ／ `indented_code` の `indent_of(l) >= 4`）を `lead_spaces(...)` に置換 |
| `is_blank` | T1 `line.mbt` `(text, l) -> Bool` ／ T2 `block.mbt` `(line) -> Bool` | 同上 | **T2**: 定義を削除し `blank_line(s : String) -> Bool` を呼ぶ。`indented_code` の 3 か所（`is_blank(ls[0])` ／ `is_blank(ls[ls.length() - 1])` ／ `if is_blank(l)`）を `blank_line(...)` に置換 |
| `doc_of` | T3 `serialize_wbtest` `-> Node` ／ T5 `tree_wbtest` `-> Ast` | **両方を `fixture_wbtest.mbt` に別名で置く**（T1 所有） | `doc_of(kids) -> Node` と `ast_of(kids) -> Ast` の 2 本にする。**T5 は `doc_of(...)` → `ast_of(...)` に一括置換**（Task 41〜48 の全テスト本文） |
| `chain` | T3 `serialize_wbtest` `-> Node` ／ T4 `law_wbtest` `-> Ast` | 同上 | `chain(n) -> Node` と `chain_ast(n) -> Ast` の 2 本。**T4 は `chain(200)` → `chain_ast(200)`** |
| `sig_of` | T2 `build_wbtest` `(chunks) -> String` ／ `wire.mbt` `(md) -> String` | `wire.mbt` の `sig_of(md)` を正とする | **T2**: `build_wbtest.mbt` の `sig_of(chunks)` を **`built_sig(chunks : Array[Chunk]) -> String`** に改名し、Task 12〜17 の全テスト本文を置換 |
| `nd` | T5 `tree_wbtest` の `fn nd(...)` ／ `ast.mbt` の全関数の**引数名** | 引数名を正とする | **T5**: 関数を **`node(id, form, label, kids) -> Node`** に改名（`fixture_wbtest.mbt` へ移動）。Task 41〜48 の全テスト本文を置換 |
| `spell` | T5 `op.mbt` の `fn spell(nd, at)` ／ ファイル `spell.mbt`（綴り定数の置き場） | ファイル名を正とする | **T5**: 関数を **`spellable(nd : Node, at : Int) -> Node`** に改名 |
| `before` | T5 `op.mbt` の `fn before(a, b)` ／ T3 `serialize.mbt` の `feed(o, before : Bool)` の引数名 | 引数名を正とする | **T5**: 関数を **`precedes(a : Path, b : Path) -> Bool`** に改名 |
| `spell.mbt` の 8 定数 | T2 Task 16 が「まだ無ければ作る」／ T3 Task 20 が Create | **T1 が Task 1 で 11 定数版を作る**（裁定 4） | **T2・T3 とも Files から `spell.mbt` を外す**。Consumes に「`spell.mbt` の定数（T1 Task 1）」と書く |
| `block.mbt` | T1 Task 5 が Create（仮置き）／ T2 Task 10 が Create | **T1 が Create、T2 が Modify**（裁定 4） | **T2 Task 10 の Files を `Modify:` に直す**。Step 2 の Expected も §F-3 の形へ |

## C-2. `fixture_wbtest.mbt` の全文（T1 Task 2 が作る。T5 Task 43 が末尾 2 本を追記）

```moonbit
// wbtest が共有する、手で木を組む道具。
// *_wbtest.mbt はパッケージ内で 1 つの名前空間を共有するので、
// **手組みのヘルパはこのファイルにだけ置く**（各 wbtest で作り直さない）。

///|
/// ノード 1 つ。
fn node(id : Int, form : Form, label : String, kids : Array[Node]) -> Node {
  { ..empty(id, form), label, children: kids }
}

///|
/// 見出し 1 つ。
fn heading(id : Int, label : String, kids : Array[Node]) -> Node {
  node(id, Heading, label, kids)
}

///|
/// 項目 1 つ。
fn item(id : Int, label : String, kids : Array[Node]) -> Node {
  node(id, Item, label, kids)
}

///|
/// 深さ 2 のスロット 1 つ（側を指定できる）。
fn slot(id : Int, label : String, left : Bool) -> Node {
  { ..empty(id, Heading), label, side: if left { Left } else { Right } }
}

///|
/// 深さ 0 の文書ノード（id 1・Heading・空ラベル）に木を吊るす。
fn doc_of(kids : Array[Node]) -> Node {
  { ..empty(1, Heading), children: kids }
}

///|
/// 文書ひとつ（head 無し・LF）。
fn ast_of(kids : Array[Node]) -> Ast {
  { head: None, eol: Lf, doc: doc_of(kids) }
}

///|
/// 深さ n の見出しの一本鎖。返すのは鎖の頭（深さ 1 のノード）。
fn chain(n : Int) -> Node

///|
/// 深さ n の一本鎖を吊るした文書。`ast_of([chain(n)])`。
fn chain_ast(n : Int) -> Ast {
  ast_of([chain(n)])
}

// ↓ ここから下は T5 Task 43 が追記する（`Outcome` はそのとき初めて存在する）

///|
/// 通った結果を剥がす（拒否されたらテストを落とす）。
fn done(o : Outcome) -> Ast {
  match o {
    Done(a) => a
    Reject(_) => abort("拒否された")
  }
}

///|
/// 拒否の理由を剥がす（通ってしまったらテストを落とす）。
fn rejected(o : Outcome) -> Reject {
  match o {
    Done(_) => abort("拒否されなかった")
    Reject(r) => r
  }
}
```

T1 Task 2 の時点では `done` / `rejected` は**書かない**（未定義の `Outcome` を参照して落ちる）。
T3 の `ser(doc : Node) -> String`（`serialize_wbtest.mbt`）は T3 のまま。`ser(doc_of([...]))` の形で使う。

## C-3. トップレベルの名前 — 全一覧（この表に無い名前を新設したら、まず全員へ共有）

### T1 所有

| ファイル | 名前とシグネチャ |
|---|---|
| `ast.mbt` | `pub struct Ast` / `pub struct Node` / `pub enum Eol` / `pub enum Form` / `pub enum Side` / `pub enum Block` / `pub enum Content` / `pub fn is_implied(nd : Node) -> Bool` / `pub fn empty(id : Int, form : Form) -> Node` / `pub fn promote(nd : Node, label : String) -> Node` / `pub fn sig(ast : Ast) -> String` / `pub fn check(ast : Ast) -> Array[String]` / `fn esc(s : String) -> String` / `fn block_sig(b : Block, sb : StringBuilder) -> Unit` / `fn node_sig(nd : Node, sb : StringBuilder) -> Unit` / `fn visit(...)` |
| `spell.mbt` | `item_mark` / `heading_mark` / `nest_step` / `fence_mark` / `fence_min` / `rule_mark` / `toggle_mark` / `fold_open` / `fold_close` / `summary_open` / `summary_close` |
| `line.mbt` | `priv struct Line` / `fn scan_lines(text : String) -> Array[Line]` / `fn code_at(s : String, i : Int) -> Int` / `fn slice(s : String, a : Int, b : Int) -> String` / `fn is_space(c : Int) -> Bool` / `fn trim_range(text : String, a : Int, b : Int) -> (Int, Int)` / `fn trimmed_span(text : String, l : Line) -> (Int, Int)` / `fn is_blank(text : String, l : Line) -> Bool` / `fn indent_of(text : String, l : Line) -> (Int, Int)` / `fn eol_of(text : String) -> Eol` / `fn dedent(text : String, l : Line, drop : Int) -> String` / **`fn lead_spaces(s : String) -> Int`** / **`fn blank_line(s : String) -> Bool`** |
| `scan.mbt` | `pub struct Scan` / `pub struct Chunk` / `pub enum Kind` / `pub fn scan(md : String) -> Scan` / `fn is_head_marker(...)` / `fn scan_head(text : String, lines : Array[Line]) -> (String, Int)?` / `fn atx_at(text : String, l : Line) -> (Int, String)?` / `fn bullet_at(text : String, l : Line) -> (Int, Int, String)?` / `fn break_at(text : String, l : Line, base : Int) -> Int` / `fn setext_at(text : String, l : Line, base : Int) -> Int` / `fn is_tag(text : String, l : Line, tag : String) -> Bool` / `fn is_summary(text : String, l : Line) -> Bool` / `fn fence_open(text : String, l : Line, base : Int) -> (Int, Int)?` / `fn fence_close_len(text : String, l : Line, ch : Int, base : Int) -> Int` / `priv struct Sc` / `fn flush(sc : Sc) -> Unit` / `fn keep(...)` / `fn settle(sc : Sc, col : Int) -> Int` / `fn owner_depth(sc : Sc) -> Int` |
| `block.mbt`（仮置きのみ） | `pub fn classify(text : String) -> Block` |
| `fixture_wbtest.mbt` | `node` / `heading` / `item` / `slot` / `doc_of` / `ast_of` / `chain` / `chain_ast`（+ T5 が `done` / `rejected`） |
| `ast_wbtest.mbt` | `fn sample() -> Ast` |
| `line_wbtest.mbt` | `fn lines_sig(text : String) -> String` |
| `scan_wbtest.mbt` | `fn first_line(md : String) -> Line` / `fn chunks_sig(md : String) -> String` / `fn body_text(md : String, at : Int) -> String` |

### T2 所有

| ファイル | 名前 |
|---|---|
| `block.mbt` | `pub fn classify`（Modify で本実装） / `fn content_of` / `fn is_rule_text` / `fn image_of` / `fn link_of` / `fn link_parts` / `fn starts` / `fn ends` / `fn code_of` / `fn fence_head` / `fn is_fence_close` / `fn indented_code` / `fn lines_of` / `fn join` / `fn trim` / `fn svg_of` ／ **`indent_of` と `is_blank` は定義しない**（`lead_spaces` / `blank_line` を呼ぶ） |
| `build.mbt` | `pub fn build(sc : Scan) -> Ast` / `priv struct Frame` / `priv struct Ctx` / `fn close_frame` / `fn top` / `fn close_to` / `fn push_skel` / `fn push_frame` / `fn owner` / `fn next_is_slot` / `fn in_deep_item` / `fn fold_at` |
| `parse.mbt` | `pub fn parse(md : String) -> Ast` |
| `block_wbtest.mbt` | （ヘルパ無し） |
| `build_wbtest.mbt` | `fn skel(d, f, label) -> Chunk` / `fn body(d, b) -> Chunk` / `fn brk(d, hard) -> Chunk` / `fn fold(d, open) -> Chunk` / **`fn built_sig(chunks : Array[Chunk]) -> String`** / `fn md_sig(md : String) -> String` |

### T3 所有

| ファイル | 名前 |
|---|---|
| `serialize.mbt` | `pub fn serialize(ast : Ast) -> String` / `priv struct Out` / `fn repeat` / `fn indent` / `fn push_text` / `fn join_lines` / `fn feed` / `fn hashes` / `fn inner_pad` / `fn write_node` / `fn write_children` / `fn write_body` / `fn write_block` / `fn fence_len` / `fn write_code` / `fn is_left` / `fn write_toggle` / `fn open_fold` / `fn close_fold` / `fn nl_count` |
| `serialize_wbtest.mbt` | `fn ser(doc : Node) -> String` ／ **`doc_of` / `chain` / `heading` / `item` / `slot` は定義しない**（`fixture_wbtest.mbt` のものを使う） |

### T4 所有

| ファイル | 名前 |
|---|---|
| `wire.mbt` | `pub fn sig_of` / `pub fn format_of` / `pub fn check_of` / `pub fn tree_of` / `pub fn apply_op` / `fn json_str` / `fn json_block` / `fn json_node` / `fn form_tag` / `fn side_tag` / `fn eol_tag` / `fn bool_lit` / `fn reject_tag` |
| `js/exports.mbt` | `pub fn doc_sig` / `doc_format` / `doc_check` / `doc_tree` / `doc_apply`（**別パッケージ**。`mmm-app/core/doc` の名前とは衝突しない） |
| `law_wbtest.mbt` | `priv struct Rand` / `priv struct Gen` / `let labels : Array[String]` / `fn sample_block` / `fn side_for` / `fn gen_implied` / `fn gen_children` / `fn gen_node` / `fn gen_ast(seed : Int) -> Ast` ／ **`chain` は定義しない**（`chain_ast` を使う） |

### T5 所有

| ファイル | 名前 |
|---|---|
| `edit.mbt` | `pub struct Edit` / `pub fn apply(text : String, edits : Array[Edit]) -> String` |
| `diff.mbt` | `pub fn diff(old : String, new_ : String) -> Array[Edit]` / `fn at_line_start` |
| `reflect.mbt` | `pub fn reflect(old : String, ast : Ast) -> Array[Edit]` |
| `form.mbt` | `pub fn to_item` / `pub fn refit` |
| `op.mbt` | `pub enum Outcome` / `pub enum Reject` / `pub type Path = Array[Int]` / `pub fn path_of` / `pub fn tops` / `pub fn normalize` / `fn seek` / **`fn precedes(a : Path, b : Path) -> Bool`** / `fn under` / `fn at_path` / `fn amend` / `fn pluck` / `fn fix(nd : Node, depth : Int) -> Node` / **`fn spellable(nd : Node, at : Int) -> Node`** |
| `delete.mbt` | `pub fn delete_nodes` |
| `side.mbt` | `pub fn flip_side` / `fn turn` / `fn mirror` |
| `move.mbt` | `pub fn move_nodes` / `fn moving` / `fn seat_in` |
| 各 `*_wbtest.mbt` | ヘルパは定義しない（`fixture_wbtest.mbt` のものを使う） |

---

# D. `test/_doc.ts` の API 定義（全文）

**所有者は T4。T5 は import するだけで、自前の型も自前の `applyEdits` も定義しない。**
`tsconfig` は `strict: true` / `noUnusedLocals: true` / `isolatedModules: true`。`test/tsconfig.json` の `include` が `"."` なので、`_doc.ts` も `doc-ops.test.ts` も `pnpm run check`（`tsc -p test --noEmit`）の対象である。**未使用の import があるだけで赤になる。**

## D-1. `wire.mbt` が返す JSON の形（この鍵で固定）

### `tree_of(md)`

```json
{"eol":"lf","head":null,
 "doc":{"id":1,"depth":0,"form":"H","label":"","implied":false,"folded":false,"side":"R",
        "body":[{"k":"opaque","text":"…"}],"children":[]}}
```

- `eol` は `"lf"` / `"crlf"`。`head` は `null` か文字列
- `form` は `"H"` / `"I"`、`side` は `"R"` / `"L"`
- `depth` は導出値（doc = 0）だが、TS のテストが読むので書き出す
- `body` の要素: `{"k":"opaque","text":…}` / `{"k":"rule"}` / `{"k":"image","alt":…,"src":…}` / `{"k":"link","text":…,"href":…}` / `{"k":"code","info":…,"text":…}` / `{"k":"svg","text":…}`
- 鍵の順序も上のとおりに固定する（比較を目で追えるようにするため。TS は順序に依存しない）

### `apply_op(md, op, ids, parent, at)`

```json
{"ok":true,"text":"…","sig":"…","edits":[{"from":0,"to":3,"insert":"…"}]}
{"ok":false,"reject":"missing"}
```

`reject` は `"missing"` / `"cycle"` / `"ineligible"` / `"unknown-op"` の 4 つだけ。`"unknown-op"` は `op` が `"move"` / `"flip"` / `"delete"` のいずれでもないときに返す（`Reject` の変種は 3 つのまま — 判定 4 を汚さない）。

## D-2. `test/_doc.ts` 全文

```ts
// 新 core（mmm-app/core/doc）の受け口。`*.test.ts` ではないので単体では走らない。
//
// 生成物を **動的に** 読むのは、無かったときに「読める理由」で落とすため
// （静的 import はリンク時に解決されるので、existsSync の案内より先に
// ERR_MODULE_NOT_FOUND が出てしまう）。
//
// 境界を跨ぐのは String / Int / Bool / Array[Int] だけ。木は JSON 文字列で来る。

import { existsSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { REPO, rng } from "./_helpers.ts";

const DOC_JS = join(REPO, "core/_build/js/release/build/doc/js/js.js");
if (!existsSync(DOC_JS)) {
  throw new Error(
    `新コアの JS 出力が無い: ${DOC_JS}\n先に \`pnpm run core\` を実行すること。`,
  );
}

type DocCore = {
  docSig: (md: string) => string;
  docFormat: (md: string) => string;
  docCheck: (md: string) => string;
  docTree: (md: string) => string;
  docApply: (
    md: string,
    op: string,
    ids: number[],
    parent: number,
    at: number,
  ) => string;
};

const mbt: DocCore = await import(pathToFileURL(DOC_JS).href);

// ---------------------------------------------------------------
// 木の形（wire.mbt の JSON と 1 対 1）
// ---------------------------------------------------------------

export type DocBlock =
  | { k: "opaque"; text: string }
  | { k: "rule" }
  | { k: "image"; alt: string; src: string }
  | { k: "link"; text: string; href: string }
  | { k: "code"; info: string; text: string }
  | { k: "svg"; text: string };

export type DocNode = {
  id: number;
  depth: number;
  form: "H" | "I";
  label: string;
  implied: boolean;
  folded: boolean;
  side: "R" | "L";
  body: DocBlock[];
  children: DocNode[];
};

export type DocTree = { eol: "lf" | "crlf"; head: string | null; doc: DocNode };

export type OpEdit = { from: number; to: number; insert: string };

/** 操作 1 回の結果。**判別可能ユニオン** — `ok` を見れば絞り込める。 */
export type OpResult =
  | { ok: true; text: string; sig: string; edits: OpEdit[] }
  | { ok: false; reject: string };

// ---------------------------------------------------------------
// 読み
// ---------------------------------------------------------------

/** 木の指紋（id を含まない。法則 1・2 の比較子はこれ 1 本）。 */
export const sig = (md: string): string => mbt.docSig(md);

/** 正規形。`serialize(parse(md))` = mmm のフォーマッタそのもの。 */
export const format = (md: string): string => mbt.docFormat(md);

/** 不変条件の違反。空配列なら健全。 */
export function check(md: string): string[] {
  const s = mbt.docCheck(md);
  return s === "" ? [] : s.split("\n");
}

/** 木そのもの（id 付き）。 */
export function tree(md: string): DocTree {
  return JSON.parse(mbt.docTree(md)) as DocTree;
}

/** doc を除く全ノードを文書順に並べる。 */
export function flatten(nd: DocNode): DocNode[] {
  const out: DocNode[] = [];
  const walk = (n: DocNode): void => {
    for (const k of n.children) {
      out.push(k);
      walk(k);
    }
  };
  walk(nd);
  return out;
}

/** 骨格の並び（`<form>:<label>`）。implied は綴りを持たないので落とす。 */
export function skeleton(md: string): string[] {
  return flatten(tree(md).doc)
    .filter((n) => !n.implied)
    .map((n) => `${n.form}:${n.label}`);
}

/** かたまり 1 つを 1 本の文字列に畳む（MoonBit 側の指紋と同じ語彙）。 */
export function blockSig(b: DocBlock): string {
  switch (b.k) {
    case "opaque":
      return `o:${b.text}`;
    case "rule":
      return "rule";
    case "image":
      return `img:${b.alt}|${b.src}`;
    case "link":
      return `link:${b.text}|${b.href}`;
    case "code":
      return `code:${b.info}|${b.text}`;
    case "svg":
      return `svg:${b.text}`;
  }
}

/** doc も含めた全ノードの body を、文書順に 1 本の配列へ。 */
export function blocksOf(md: string): string[] {
  const out: string[] = [];
  const walk = (n: DocNode): void => {
    for (const b of n.body) out.push(blockSig(b));
    for (const k of n.children) walk(k);
  };
  walk(tree(md).doc);
  return out;
}

// ---------------------------------------------------------------
// 操作
// ---------------------------------------------------------------

/** 操作 1 回。`op` は "move" / "flip" / "delete"。 */
export function applyOp(
  md: string,
  op: string,
  ids: number[],
  parent: number,
  at: number,
): OpResult {
  return JSON.parse(mbt.docApply(md, op, ids, parent, at)) as OpResult;
}

/** 編集の列を当てる（昇順・非重複が前提。自己検査で使う）。 */
export function applyEdits(text: string, edits: OpEdit[]): string {
  let out = "";
  let at = 0;
  for (const e of edits) {
    out += text.slice(at, e.from) + e.insert;
    at = e.to;
  }
  return out + text.slice(at);
}

// ---------------------------------------------------------------
// 生成と縮小
// ---------------------------------------------------------------

const LABELS = [
  "a", "b", "見出し", "with space", "  leading", "trailing  ",
  "記号 #!$%", "https://example.com/x", "[md](https://e.com)", "###",
  "very ".repeat(12) + "long", "タブ\tあり", "", "-", "--",
  "😀𝔘𝔫𝔦", "🇯🇵 旗", "[x] done", "1. 番号に見える",
];

const BLOCKS = [
  "本文テキスト",
  "段落の 1 行目\n2 行目",
  "https://example.com/link",
  "[タイトル](https://example.com/t)",
  "![](./img.webp)",
  "![alt](./sub/deep.png)",
  "| a | b |\n|---|---|\n| 1 | 2 |",
  "```ts\nconst x = 1;\n```",
  "````\n```\n入れ子っぽいフェンス\n```\n````",
  "```\n# fenced heading\n---\n```",
  "~~~\n## tilde fenced\n~~~",
  '<svg xmlns="http://www.w3.org/2000/svg"><circle r="5"/></svg>',
  "> 引用\n> の続き",
  "    インデントされたコード",
  "<div>生 HTML</div>",
  "***",
  "___",
  "- - -",
];

/**
 * 病的な markdown を種 1 つから決定的に生成する（text-first）。
 * 木を組んでから serialize する model-first の生成は MoonBit 側
 * （`core/doc/law_wbtest.mbt` の `gen_ast`）が持つ。あちらが法則 1、こちらが法則 2。
 */
export function randomMd(seed: number): string {
  // 本文は T4 Task 35 の草稿のまま（LABELS / BLOCKS を使う）。
  // 踏む軸は doc-law.test.ts の「生成器は決定的で、狙った軸を実際に踏んでいる」が検算する。
  const rand = rng(seed);
  const pick = <T,>(a: T[]): T => a[Math.floor(rand() * a.length)];
  const nl = rand() < 0.25 ? "\r\n" : "\n";
  const out: string[] = [];
  const blank = (): void => {
    out.push("");
    if (rand() < 0.15) out.push("");
  };
  if (rand() < 0.2) out.push("---", "image-folder: img", "key: [1, 2]", "---", "");
  if (rand() < 0.15) out.push("---", "");
  let listDepth = 0;
  let headLevel = 1;
  const n = 2 + Math.floor(rand() * 16);
  for (let i = 0; i < n; i++) {
    const r = rand();
    if (listDepth > 0 && r < 0.4) {
      if (rand() < 0.3 && listDepth < 4) listDepth++;
      else if (rand() < 0.3 && listDepth > 1) listDepth--;
      const marker = pick(["-", "*", "+", "1.", "1)", "2."]);
      const pad = " ".repeat((listDepth - 1) * 2 + (rand() < 0.15 ? 1 : 0));
      out.push(`${pad}${marker} ${pick(LABELS)}`.trimEnd());
      if (rand() < 0.25) blank();
      continue;
    }
    if (r < 0.55) {
      if (rand() < 0.3) headLevel += 1 + Math.floor(rand() * 3);
      else if (rand() < 0.3 && headLevel > 1) headLevel--;
      if (headLevel > 9) headLevel = 1 + Math.floor(rand() * 3);
      const lead = " ".repeat(rand() < 0.12 ? 1 + Math.floor(rand() * 3) : 0);
      const close =
        rand() < 0.12 && headLevel <= 6 ? " " + "#".repeat(1 + Math.floor(rand() * 3)) : "";
      out.push(`${lead}${"#".repeat(headLevel)} ${pick(LABELS)}${close}`.trimEnd());
      listDepth = 0;
      blank();
      continue;
    }
    if (r < 0.65) {
      out.push(pick(LABELS) || "setext", rand() < 0.5 ? "===" : "---");
      listDepth = 0;
      blank();
      continue;
    }
    if (r < 0.72) {
      listDepth = 1;
      out.push(`${pick(["-", "*", "+", "1."])} ${pick(LABELS)}`.trimEnd());
      blank();
      continue;
    }
    if (r < 0.8) {
      out.push(pick(["---", "***", "___"]));
      blank();
      continue;
    }
    if (r < 0.88) {
      out.push("<details>", "");
      if (rand() < 0.5) out.push(`<summary>${pick(LABELS)}</summary>`, "");
      continue;
    }
    if (r < 0.93) {
      if (rand() < 0.8) out.push("</details>", "");
      continue;
    }
    out.push(pick(BLOCKS));
    blank();
  }
  let text = out.join(nl);
  if (rand() < 0.25) text = text.replace(/[\r\n]+$/, "");
  return text;
}

/**
 * 反例を縮める。**行を落として、まだ失敗するなら採用する**。
 * `fails` は総関数であること（例外は呼ぶ側で捕まえて true / false にする）。
 */
export function shrink(
  md: string,
  fails: (s: string) => boolean,
  rounds = 600,
): string {
  if (!fails(md)) return md;
  const nl = md.includes("\r\n") ? "\r\n" : "\n";
  let cur = md;
  let budget = rounds;
  let changed = true;
  while (changed && budget > 0) {
    changed = false;
    const lines = cur.split(/\r?\n/);
    for (let size = Math.max(1, lines.length >> 1); size >= 1 && budget > 0; size >>= 1) {
      for (let at = 0; at + size <= lines.length && budget > 0; at++) {
        budget--;
        const next = lines.slice(0, at).concat(lines.slice(at + size)).join(nl);
        if (next !== cur && fails(next)) {
          cur = next;
          changed = true;
          break;
        }
      }
      if (changed) break;
    }
  }
  return cur;
}
```

## D-3. export の一覧（**この名前だけが存在する**）

| 種別 | 名前 |
|---|---|
| 型 | `DocBlock` / `DocNode` / `DocTree` / `OpEdit` / `OpResult` |
| 読み | `sig` / `format` / `check` / `tree` / `flatten` / `skeleton` / `blockSig` / `blocksOf` |
| 操作 | `applyOp` / `applyEdits` |
| 生成 | `randomMd` / `shrink` |

**存在しないもの（T5 が書いていた名前）**: `doc` 名前空間 ／ `randomDoc`（それは `test/_helpers.ts` の**旧**生成器） ／ `ApplyResult`。
**`check` は `string[]` を返す。** `!== ""` で判定しない。`check(x).length > 0` で判定する。

`OpResult` が判別可能ユニオンなので、`if (!r.ok) { … }` の後で `r.text` / `r.sig` / `r.edits` が `undefined` なしで読める。`assert.equal(res.ok, true)` では絞り込めないので、**`if (!res.ok) assert.fail(res.reject);`** と書くこと。

---

# E. コマンドの綴り（実測で確定したものだけ。全タスクがこれを使う）

`<REPO>` = `D:/1.atrium/mmm/.claude/worktrees/doc-model`

| 目的 | 綴り（これ 1 つ） |
|---|---|
| MoonBit テスト（新パッケージ） | `moon -C <REPO>/core test -p mmm-app/core/doc` |
| MoonBit テスト（旧 + 新の通し） | `moon -C <REPO>/core test -p mmm-app/core -p mmm-app/core/doc` |
| MoonBit 型検査（全体） | `moon -C <REPO>/core check` |
| MoonBit 型検査（新パッケージだけ） | `moon -C <REPO>/core check doc` |
| 整形（当てる） | `moon -C <REPO>/core fmt doc` |
| 整形（確認だけ） | `moon -C <REPO>/core fmt --check doc` |
| JS 出力 | `pnpm run core`（= `cd core && moon build --target js --release`） |
| TS テスト（1 本） | `node --test <REPO>/test/doc-law.test.ts` |
| TS テスト（新 core の 3 本） | `node --test "<REPO>/test/doc-*.test.ts"` |
| TS テスト（全部） | `pnpm test`（= `node --test "test/*.test.ts"`） |
| TS 型検査 | `pnpm run check`（= `tsc --noEmit && tsc -p test --noEmit`） |
| git（追加） | `git -C <REPO> add <絶対パス or リポジトリ相対パス>` |
| git（コミット） | `git -C <REPO> commit -m "<Type>: <Emoji> <Title>"` |

裁定 6 の `moon -C core test -p mmm-app/core/doc` と `git -C D:/... ...` は同じコマンドである。**`-C` の引数を絶対パスに展開したものを正**とする（cwd 依存を消すため。ファイルパスも全タスクで絶対パス）。

## E-1. 必ず守る注意（実測）

1. **`moon test` を `-p` 無しで書かない。** この repo では `core/js` の `#export_name` が `Error: [4219]` で必ず落ちる（EXIT=1）。`moon check` は `-p` 無しで通る
2. **`-p` の綴り間違いは exit 0 で「成功」する。** `Warning: package ... not found` + `Total tests: 0, passed: 0, failed: 0.` が出て EXIT=0。**Step 4 の Expected には必ず具体的な `Total tests: N` を書き、`Total tests: 0` を見たら綴りを疑う**
3. **`moon fmt` は `moon.pkg` も整形対象。** `js` を対象に含めると `core/js/moon.pkg` の `@core` が剥がされて必ず差分が出る。**対象は `doc` だけ**にする。新パッケージの `moon.pkg` にも冗長な別名を書かない
4. **`moon fmt --check` の失敗は EXIT=127**（0 でも 1 でもない）。差分は `git diff` の色付き出力として本文に出て、末尾は `Error: failed when formatting project`
5. **環境変数の前置き（`VAR=値 コマンド`）は禁止。** PowerShell では `CommandNotFoundException` になる。ファズの回数を上げるときは両方併記する:
   - PowerShell: `$env:MMM_FUZZ = '5000'; node --test <REPO>/test/doc-law.test.ts; Remove-Item Env:MMM_FUZZ`
   - Bash: `MMM_FUZZ=5000 node --test <REPO>/test/doc-law.test.ts`
6. `node --test` のグロブは **Node 自身が展開する**（PowerShell は展開しない）ので `"test/doc-*.test.ts"` は引用符付きでそのまま動く
7. このワークツリーには `node_modules` も `core/_build` も無い。**T4 Task 30 が最初に `pnpm install` と `pnpm run core` を踏む**

---

# F. 期待するエラー文言（実測。「Step 2 の Expected」にこの形で書く）

## F-1. MoonBit — コンパイル

| 状況 | 逐語 |
|---|---|
| 値が未定義 | `Error: [4021]` ／ 本文 `The value identifier <名前> is unbound.` |
| 型が未定義 | `Error: [4032]` ／ 本文 `The type <名前> is undefined.` |
| 型の不一致 | `Error: [4014]` ／ 本文 `Expr Type Mismatch` + `has type : <T>` + `wanted   : <U>` |
| メソッドが無い | `Error: [4015]` ／ 本文 `Type <T> has no method <名前>.` |
| パッケージ別名の誤り | `Error: [4020]` ／ 本文 `Package "<名前>" not found in the loaded packages.` |
| トップレベルの二重定義 | `Error: [4051]` ／ 本文 `The toplevel identifier <名前> is declared twice: it was previously defined at <パス>:<行>:<列>.` |
| ラベル引数の綴り誤り | `Error: [3016]` ／ 本文 ``The syntax `alt~=..` for supplying labelled argument is invalid, the correct syntax is `alt=..`.`` |
| `pub` の値を外から構築 | `Error: [4036]` ／ 本文 `Cannot create values of the read-only type: <型>.` |
| `pub` の `mut` を外から書く | `Error: [4094]` ／ 本文 `Cannot modify a read-only field: <名前>` |
| 使われない `mut` | `Error: [0015]` ／ 本文 ``Warning (unused_mut): The mutability of field '<名前>' is never used, try remove `mut`.`` |
| library で `#export_name` | `Error: [4219]` ／ 本文 `#export_name "<名前>" can only be used in a foreign library. Add `pkgtype(kind: "foreign_library")` to the package's moon.pkg.` |

**書き方の統一**: `Error: [4021]` は 1 行目、本文は診断枠の中に出る。Expected には
`Expected: Error: [4021] / The value identifier build is unbound.`
の形で**コードと文面を両方**書く。

**削除する誤り**: `Error [4014] The value X is undefined.` は**二重に誤り**（`[4014]` は `Expr Type Mismatch`、`is undefined.` は**型**側の文言）。T5 の草稿にあるこの綴りを全部 F-1 の形へ直す。

## F-2. MoonBit — テストの実行

| 状況 | 逐語 | EXIT |
|---|---|---|
| 全通過 | 最終行 1 行だけ `Total tests: 15, passed: 15, failed: 0.` | 0 |
| 失敗あり | 1 件ごとに `[<モジュール>] test <ファイル>:<行> ("<テスト名>") failed: Error` + JS スタック 10 行前後、最終行 `Total tests: 9, passed: 7, failed: 2.` | **2** |
| パッケージ名の綴り誤り | `Warning: package ... not found, ...` + `Warning: no test entry found.` + `Total tests: 0, passed: 0, failed: 0.` | **0（緑に見える）** |
| build 成功 | `Finished. moon: ran 3 tasks, now up to date` | 0 |
| check 成功（警告あり） | `Finished. moon: ran 3 tasks, now up to date (3 warnings, 0 errors)` | 0 |
| fmt 差分あり | `git diff` の色付き出力 + `Failed with 0 warnings, 0 errors.` + `Error: failed when formatting project` | **127** |

## F-3. 「値の差で落ちる」ときの Expected の書き方

コンパイルが通ってしまう場合（T2 Task 10 のように、T1 の仮置きが既にある）、Expected に「未定義」と書いてはならない。次の形にする:

> Expected: コンパイルは通り、`Total tests: N, passed: P, failed: F.`（EXIT=2）。仮置きの `classify` は常に `Opaque` を返すので、`assert_eq` が `Opaque("![a](b.png)")` と `Content(Image(alt="a", src="b.png"))` の差を出す。落ちるのは <具体的なテスト名> の F 本。

## F-4. Node（TS 側）

| 状況 | 逐語 |
|---|---|
| モジュールが無い | `Error [ERR_MODULE_NOT_FOUND]: Cannot find module '<絶対パス>'` |
| export が無い | `SyntaxError: The requested module './_doc.ts' does not provide an export named '<名前>'` |
| 全通過 | `ℹ tests 15` / `ℹ pass 15` / `ℹ fail 0` ／ EXIT=0 |
| 失敗 | `✖ <テスト名>` + `AssertionError [ERR_ASSERTION]` + `ℹ fail 1` ／ EXIT=1 |
| 型検査の失敗 | `error TS2339: Property 'text' does not exist on type ...` など。`pnpm run check` が EXIT=1 |

---

# G. 各タスク群への個別指示

査読の指摘は**致命 18 / 重大 18 / 軽微 16 を 1 件も落とさず**振り分けてある。各行の末尾 〔致命〕〔重大〕〔軽微〕がその指摘の重さ。

## G-1. T1（Task 1〜9）— 型と、行から区間へ

### 全体

1. **Task 番号を 1〜9 に振り直す**（§H）。旧 Task 4 は 5・6・7 に、旧 Task 5 は 8 に、旧 Task 6 は 7・8・9 に分配する 〔重大 ×2 — 粒度過大〕
2. **全 Step 4 の Expected のテスト総数を +1 する。** Task 1 で書いた 1 本を数え落としている（旧 Task 2 は 13→**14**、Task 3 は 24→**25**、Task 4 は 55→**56**、Task 5 は 72→**73**、Task 6 は 79→**80**）。振り直したあとは、各 Task の Expected を「そのパッケージの累計 N 本」で書き直し、**`Total tests: N, passed: N, failed: 0.` の逐語**にする 〔軽微〕
3. **全 git ステップを `git -C <REPO> add …` / `git -C <REPO> commit -m "…"` に統一**、`moon` は `moon -C <REPO>/core …` に統一、Files のパスは全部絶対パス 〔軽微 ×2〕
4. Step 2 の Expected は §F-1 の `Error: [4021] / The value identifier X is unbound.` の形に統一する

### Task 1: パッケージ・木の型・綴りの定数

- Files: Create `core/doc/moon.pkg` / `core/doc/ast.mbt`（§A-2 の全文）/ **`core/doc/spell.mbt`（§A-6 の 11 定数）** / Test `core/doc/ast_wbtest.mbt`（1 本）
- **`spell.mbt` の所有者は T1。** T2・T3 は作らない 〔致命 ×2〕
- `moon.pkg` は `pkgtype(kind: "library")` の 1 行だけ
- **Step 4 に「`pub struct` のクロスパッケージ読みを試す」プローブは要らない**（裁定 3 により境界を struct が跨がなくなったため）。査読 3 が求めたプローブは**不要になった** 〔重大〕
- コミット: `feat: ✨ 新 core のパッケージと文書の木の型を置く`
- **このコミットが T2・T3・T5 の着手条件**である（依存図に `T1 Task 1 → T2 Task 10 / T3 Task 20 / T5 Task 40` を明記）。「まだ無ければ §2 を写す」という記述は T3・T5 から削除させる 〔軽微〕

### Task 2: 手で木を組む道具と、指紋

- Files: Create **`core/doc/fixture_wbtest.mbt`**（§C-2 の全文。`done` / `rejected` は**書かない**）/ Modify `core/doc/ast.mbt`（`esc` / `block_sig` / `node_sig` / `sig` を追記）/ Modify `core/doc/ast_wbtest.mbt`
- **`esc` は `~` `^` `<` `\r` も逃がす**（§A-4）。テストを 1 本足す:
  `assert_eq(sig(ast_of([heading(2, "^x", [])])), "head:-\nlf\n[H[H\\^x]]")` — 逃がさないと、畳んだ `x` と label `^x` が同じ指紋になる
- 指紋は §A-4 の形で 1 文字も違わないこと。固定の例 6 つを全部テストにする
- コミット: `feat: ✨ 木の指紋を、手で組んだ木で確かめる`

### Task 3: 不変条件の検査

- Modify `core/doc/ast.mbt`（`check` / `visit`）、Modify `core/doc/ast_wbtest.mbt`
- **条件は 11 個。** §A-3 の表のメッセージを逐語で固定する。**11 番「implied が側を持つ: `<id>`」が裁定 1 の本体**である 〔致命 — 法則 1 の穴〕
- 4 番（順序法則）は **doc 直下でも効く**ことをテスト 1 本で押さえる 〔軽微 R042〕
- コミット: `feat: ✨ 木の不変条件を 11 個ぶん見張る`

### Task 4: 行の走査と、文字・空白の道具

- Create `core/doc/line.mbt` / `core/doc/line_wbtest.mbt`
- `priv struct Line`（`struct Line` ではなく `priv` を付ける。既存 repo の綴り）
- **`lead_spaces(s : String) -> Int` と `blank_line(s : String) -> Bool` を T1 が所有して置く** 〔致命 ×4 — `indent_of` / `is_blank` の二重定義〕
  - `lead_spaces`: 先頭から半角空白（32）を数える
  - `blank_line`: 空白（32）とタブ（9）だけなら true
  - **T2 はこの 2 本を呼ぶ。自分で定義しない**
- `slice(s, a, b)` のコメントに「**a・b は行境界かコードポイント境界であること。サロゲートの途中で切ると `String::sub` の guard で panic する**」と書く 〔実測 8〕
- コミット: `feat: ✨ 行の走査と、文字と空白の道具を移す`

### Task 5: 見出しと項目の行

- Create `core/doc/scan.mbt`（`Scan` / `Chunk` / `Kind` の型 + `atx_at` + `bullet_at`）/ Create `core/doc/scan_wbtest.mbt`（`first_line` と ATX 7 本 + 箇条書き 8 本）
- **`- - -` のテストはここに書かない**（`break_at` が Task 6 で入るまで判定できない）
- コミット: `feat: ✨ 見出しと項目の行を認定する`

### Task 6: 水平線と setext の行、そして `- - -` の裁定

- Modify `core/doc/scan.mbt`（`break_at` / `setext_at` を足し、**`bullet_at` に guard を 1 つ挿す**）/ Modify `core/doc/scan_wbtest.mbt`（6 本）
- **裁定 2 を実装する** 〔致命 ×2 — `- - -` の裁定矛盾〕:
  - `break_at` を「**同じ印が、空白を挟んでもよいので 3 つ以上。印と空白以外が現れたら 0**」まで広げる
  - `bullet_at` の、印を読んだ直後（`let c = code_at(text, p)` の次の行）に挿す:
    ```moonbit
      if break_at(text, l, col) != 0 {
        return None
      }
    ```
  - チャンネルは「**空白を 1 つも含まない `---` だけが `Break(true)`**、それ以外（`- - -` を含む）は `Break(false)`」
- テストを差し替える 〔致命〕:
  ```moonbit
  ///|
  test "`- - -` は水平線であって箇条書きではない" {
    assert_eq(bullet_at("- - -", first_line("- - -")), None)
    assert_eq(break_at("- - -", first_line("- - -"), 0), 45)
  }
  ```
  旧テスト「`- - -` は前から箇条書きとして読む（旧 core の方言）」は**削除する**
- 「カバーする要件」に **R081** を追記する
- コミット: `feat: ✨ 水平線の 2 チャンネルと setext を認定する`

### Task 7: フェンス・畳み・封筒の行

- Modify `core/doc/scan.mbt`（`fence_open` / `fence_close_len` / `is_tag` / `is_summary` / `is_head_marker` / `scan_head`）/ Modify `core/doc/scan_wbtest.mbt`（10 本）
- **`scan_head` の EOL を正規化する** 〔重大 — 法則 2 が破れる〕:
  - `slice(text, lines[0].start, lines[i].end)` で原文を切ると CRLF 文書の head に `\r` が残る。serialize が `\n` でしか行を割らないので各行末に `\r` が居残り、`join_lines` が `\r\n` を足して `---\r\r\n…` を吐く。**次の parse でまた積まれ、回数ごとに文字列が伸びる**
  - 実装を「`lines[0]`〜`lines[i]` を `dedent(text, l, 0)`（行末の `\r` を落とす）で取り、`"\n"` で綴じる」に直す
  - テストを 1 本足す: `scan_head("---\r\nk: v\r\n---\r\n\r\n# r\r\n", …) == Some(("---\nk: v\n---", 3))`
- **封筒の結線（`scan` から `scan_head` を呼び、`{ head, eol, chunks }` を返す）もここでやる**（旧 Task 6 の (a) を前倒し）。テスト 3 本（封筒あり／閉じない封筒は None／封筒の後ろはふつうに読む）
- コミット: `feat: ✨ フェンス・details・封筒を認定する`

### Task 8: かたまりの駆動 — コンテナのスタック

- Modify `core/doc/scan.mbt`（`Sc` / `flush` / `keep` / `settle` / `owner_depth` / `scan` の駆動部）/ **Create `core/doc/block.mbt`**（仮置き `classify` 1 本だけ）/ Modify `core/doc/scan_wbtest.mbt`
- **駆動部は `break_at` を `bullet_at` より先に見る**（裁定 2） 〔致命〕
- **インデントコードの読み（`keep` の `code : Bool` 引数、`if col - base >= 4 { keep(…); continue }`）もここでやる**（旧 Task 6 の (b) を前倒し）
- **`chunks_sig` は Body の中身を展開しない**（裁定 5） 〔重大 ×3 — T1 の期待値が仮置き classify に依存していた〕:
  ```moonbit
      Body(_) => sb.write_string("body")
  ```
  これで T2 が `classify` を本実装しても T1 のテストは落ちない。**T2 は `scan_wbtest.mbt` を触らない**
- **期待値の差し替え（逐語）**:

  | テスト | 旧 | 新 |
  |---|---|---|
  | 列 0 に戻った散文は項目の領土を閉じる | `"1I:a\|0o:prose\|0o:    ---\|"` | `"1I:a\|0body\|0body\|"` |
  | フェンスの中の見出しは構造にならない | `"1H:a\|1o:```\\n## inside\\n```\|"` | `"1H:a\|1body\|"` |
  | 閉じないフェンスは文書末まで飲み込む | `"1H:a\|1o:```\\n## inside\|"` | `"1H:a\|1body\|"` |
  | 散文は 1 つのかたまりに畳まれる | `"1H:a\|1o:one\\ntwo\|"` | `"1H:a\|1body\|"` |
  | 項目の中身の散文は中身の列まで字下げを落として持つ | `"1I:a\|1o:text\|"` | **下記の `body_text` に差し替える** |

- 「字下げを落として持つ」ことは `chunks_sig` では見えなくなるので、**`body_text(md : String, at : Int) -> String`**（`scan(md).chunks[at].kind` が `Body(Opaque(t))` なら `t`、それ以外は `abort`）を `scan_wbtest.mbt` に置き、`assert_eq(body_text("- a\n\n  text\n", 1), "text")` で押さえる。散文は本実装でも `Opaque` のままなので、この期待値は T2 の後も動かない
- コミット: `feat: ✨ かたまりの駆動をコンテナのスタックで書く`

### Task 9: 方言の仕上げ

- Modify `core/doc/scan.mbt`（3 か所の**局所的な Edit**。`scan` の全文差し替えは禁止）/ Modify `core/doc/scan_wbtest.mbt`（3 本）
- (a) **項目の領土の中の見出しは Opaque**: `match atx_at` を `if sc.items.length() == 0 { … }` で包む。期待 `chunks_sig("- a\n\n  # h\n") == "1I:a|1body|"`
- (b) **setext**: `if sc.buf.length() > 0 && sc.items.length() == 0 { … }` ブロック。期待 `chunks_sig("# r\n\na\n---\n") == "1H:r|2H:a|"`
- (c) **summary の読み捨ては details の直後の行だけ** 〔重大 — 本文が消える〕:
  - `Sc` に `mut after_fold : Bool` を足し、`Fold(true)` を積んだ直後だけ true、他のかたまりを積んだら false にする
  - `if sc.after_fold && is_summary(md, l) { continue }`
  - テスト 2 本: `chunks_sig("# r\n\n<details>\n<summary>r</summary>\n\n</details>\n") == "1H:r|1F+|1F-|"` と **`chunks_sig("# r\n\n<summary>x</summary>\n") == "1H:r|1body|"`（本文の summary は消えない）**
- コミット: `feat: ✨ 項目の領土・setext・summary の裁定を仕上げる`

### T1 が他へ渡すもの（申し送りに書くこと）

- `- - -` は **`Break(false)` = 飾り**（裁定 2）
- `sig` の綴りは §A-4。`doc-law.test.ts` の受け口テストが `"head:-\nlf\n[H[Hr[Ha]]]"` で固定する
- `head` / `Opaque` / `Code.text` / `Svg` の**改行は `"\n"`、末尾改行なし、`\r` を含まない**（§A-7 前提 1 の履行者は T1）
- `lead_spaces` / `blank_line` は T1 の所有名。T2 は呼ぶだけ

## G-2. T2（Task 10〜17）— 区間から木へ

1. **Task 10 の Files を `Modify: <REPO>/core/doc/block.mbt`（T1 Task 8 の仮置きを本実装に差し替える）に直す。Create しない** 〔致命 ×2〕
2. **Task 10 Step 2 の Expected を §F-3 の形に書き直す。** 「`Error: The value identifier classify is unbound.`（block.mbt がまだ無い）」は誤り。仮置きがあるのでコンパイルは通り、**値の差で落ちる**（`Rule` の 4 件と Image / Link の 2 件が FAIL、散文の 1 本だけ PASS） 〔致命〕
3. **`indent_of(line : String) -> Int` を定義しない。** `line.mbt` の `lead_spaces(s : String) -> Int` を呼ぶ。置換 3 か所: `is_rule_text` の `let mut i = indent_of(text)` ／ `is_fence_close` の `let mut i = indent_of(line)` ／ `indented_code` の `} else if indent_of(l) >= 4 {` 〔致命 ×2〕
4. **`is_blank(line : String) -> Bool` を定義しない。** `blank_line(s : String)` を呼ぶ。置換 3 か所: `if is_blank(ls[0]) || is_blank(ls[ls.length() - 1]) {` ／ `if is_blank(l) {` 〔致命 ×2〕
5. **Task 16 の Files から `core/doc/spell.mbt` を外す。** 8 定数の全文も削除。Interfaces を `Consumes: fold_open / fold_close（T1 Task 1 の spell.mbt）` にし、Step 5 のコミット対象を `core/doc/build.mbt core/doc/build_wbtest.mbt` だけにする 〔致命 ×2〕
6. **`build_wbtest.mbt` の `sig_of(chunks)` を `built_sig(chunks : Array[Chunk]) -> String` に改名**し、Task 12〜17 の全テスト本文を置換する（`wire.mbt` の `pub fn sig_of(md)` と同名衝突するため） 〔軽微〕
7. **`scan_wbtest.mbt` を触らない。** 裁定 5 により T1 の期待値は `classify` に依存しなくなった。査読が求めた「T2 が T1 の 3 本を書き換える」は**不要になった** 〔重大 ×2〕
8. **Task 12 Step 3 の `match ch.kind` の `_ => ()` をやめ、腕を明示的に列挙する** 〔軽微〕:
   ```moonbit
         Body(_) => i = i + 1 // Task 14 で読む
         Break(_) => i = i + 1 // Task 14 で読む
         Fold(_) => i = i + 1 // Task 16 で読む
   ```
   Task 14・16 の Step 3 は**該当の腕だけを差し替える Edit** として書く（`build` の全文差し替えをやめる）
9. **Task 12 / 13 / 17 の Step 2 の Expected を §F-1 の形に直す** 〔軽微〕: `Error: [4021] / The value identifier build is unbound.` ／ `Error: [4021] / The value identifier parse is unbound.`
10. **各 Step 4 の Expected を「新規 N 本が緑・既存は無傷」に統一する**（`moon test -p mmm-app/core/doc` はパッケージ内の全テストを走らせるため）。「PASS（block の 11 test）」のような書き方をやめ、逐語の `Total tests: N, passed: N, failed: 0.` を書く 〔軽微〕
11. `classify("- - -") == Rule` を固定する（裁定 2 と一致。**T1 Task 6 の `bullet_at` guard が先に入っている前提**）
12. ラベル付き引数の呼び出しは `Content(Image(alt="a", src="b.png"))`（`~=` は `Error: [3016]`）
13. **`build` が `check` を満たす木しか作らないこと**を Task 17 の通しテストで押さえる。特に**深さ 2 の implied に Left を付けない**（裁定 1 の不変条件 11） 〔致命〕
14. Task 16 の冒頭に「**依存: T1 Task 1（`spell.mbt`）のコミット後に着手する**」と明記

## G-3. T3（Task 20〜26）— 綴り

1. **Task 20 の Files から `Create: core/doc/spell.mbt` を外す。** 所有者は T1（§A-6 の 11 定数は T1 が作る）。Interfaces の Consumes に「`spell.mbt` の 11 定数（T1 Task 1）」と書き、Step 5 のコミット対象から外す 〔致命 ×2〕
2. **前提 5 の「T1 の所有物だが、まだ無ければ §2 をそのまま写して着手する」を削除**し、「**T1 Task 1 のコミット `feat: ✨ 新 core のパッケージと文書の木の型を置く` を待って着手する**」に置き換える 〔軽微〕
3. **`serialize_wbtest.mbt` の `doc_of` / `chain` / `heading` / `item` / `slot` を定義しない。** `fixture_wbtest.mbt`（T1 Task 2）のものを使う。`doc_of(kids) -> Node` はそのままの意味で使えるので、**Task 21〜26 のテスト本文は書き換え不要**（`ser(doc_of([...]))` / `ser(doc_of([chain(7)]))` / `ser(doc_of([chain(200)]))`）。`ser(doc : Node) -> String` だけは T3 が `serialize_wbtest.mbt` に置く 〔致命 ×2〕
4. **前提 1 に 1 行足す**: 「head も**行ごとに `\r` を落として `\n` で綴じる**（T1 Task 7 の責務）」 〔重大〕
5. **Task 22 に「コードは常にフェンスで書く」を前倒しする** 〔軽微〕:
   - Task 23 Step 1 の 1 本目のテストを Task 22 Step 1 の末尾へ移す
   - Task 22 Step 3 の `Content(Code(info~, text~))` の腕を `Content(Code(info~, text~)) => write_code(o, pad, info, text)` にし、`fence_len` と `write_code`（Task 23 Step 3 の全文）をここで書く
   - Task 23 は残り 3 本（フェンスの本数・tight・中身の無いコード）に絞り、Step 3 を「実装は Task 22 で出そろっている。落ちたら `fence_len` の走り数えを直す」と書く
   - **意図的に誤った実装を入れて次のタスクで捨てる、をやめる**（赤→緑のサイクルの外に嘘のコードを残さない）
6. **Task 24 にテストを 1 本足す** 〔軽微 R092〕:
   「段落の直後のトグルは必ず空行を挟む」— root の body に `Opaque("text")` を持たせ、先頭スロットを Left にして
   `ser(...) == "# r\n\ntext\n\n---\n\n## a\n"` を assert する（空行が無ければ `text\n---` が setext に化ける）
7. **`moon fmt` の綴りを全 7 か所で `moon -C <REPO>/core fmt doc` に統一する**（`moon fmt <絶対パス>` はモジュール root の外から呼ぶ形で、他の 4 人と違う） 〔軽微 ×2〕
8. **git を `git -C <REPO> add …` / `git -C <REPO> commit -m "…"` に統一**、Files のパスを全部絶対パスに 〔軽微〕
9. **implied には側を書かない**（§A-7 規則 11）。裁定 1 により「深さ 2 の implied が Left」は `check` が禁じるので、serialize 側の区切りの帰属規則は**現状のままでよい** 〔致命 — 対応済みの確認〕
10. `priv struct Out { lines : Array[String]; mut gap : Bool }` の `mut gap` は**このパッケージ内で必ず書く**こと（`feed` が書く。書かないと `Error: [0015]`）

## G-4. T4（Task 30〜37）— 法則

### 全体

1. **裁定 3 に従い、JSON の組み立てを `core/doc/wire.mbt`（新設・T4 所有）へ移す。** `core/doc/js/exports.mbt` は §A-5 の 5 本の 1 行ラッパだけにする。**`@doc.Node` / `@doc.Block` / `@doc.Ast` / `@doc.Reject` を別パッケージから触らない** 〔重大 — `pub struct` のクロスパッケージ読みが未検証だった問題への回答〕
2. `core/doc/js/moon.pkg` は `import { "mmm-app/core/doc", }`（**別名を書かない**。`moon fmt` が剥がす）
3. 全 `MMM_FUZZ=…` を PowerShell / Bash の両方併記に直す（§E-1-5） 〔軽微〕

### Task 30: テスト基盤の地ならし

- **Step 2 の再現コマンドを直す** 〔重大〕。`test/doc-law.test.ts` はワークツリー側で新規作成するファイルなので、main リポには存在しない。次に置き換える:
  ```
  cp <REPO>/test/doc-law.test.ts D:/1.atrium/mmm/test/doc-law.test.ts
  cd D:/1.atrium/mmm && node --test --test-name-pattern="ワークツリー" test/doc-law.test.ts
  rm D:/1.atrium/mmm/test/doc-law.test.ts
  ```
  「main の `test/_helpers.ts` は未修正なので `.worktrees` のまま = ここで `AssertionError: ワークツリー配下の md が混ざっている` が出る。確認したらコピーを消し、**修正はワークツリー側だけに入れる**」と書き添える
- 直す 3 件: ① `pnpm install`（`@lezer/markdown` が symlink されていない）② `test/_helpers.ts:171` の除外名 `.worktrees` → **`worktrees`**（実レイアウトは `.claude/worktrees/<name>`）③ `pnpm run core`

### Task 31: MoonBit の受け口（読みの 3 本）

- Create `core/doc/wire.mbt`（`json_str` / `form_tag` / `side_tag` / `eol_tag` / `bool_lit` / `sig_of` / `format_of` / `check_of` まで）/ Create `core/doc/js/moon.pkg` / Create `core/doc/js/exports.mbt`（`doc_sig` / `doc_format` / `doc_check`）
- 検証: `pnpm run core` が通り、
  `node -e "import('file:///<REPO>/core/_build/js/release/build/doc/js/js.js').then(m => console.log(m.docSig('# r\n')))"` が `head:-\nlf\n[H[Hr]]` を出すこと
- コミット: `feat: ✨ 新 core の JS 受け口を開ける`
- **旧 Task 31（3 ファイル同時作成）の解体その 1** 〔重大〕

### Task 32: 木の JSON と TS ラッパ

- Modify `core/doc/wire.mbt`（`json_block` / `json_node` / `tree_of`）/ Modify `core/doc/js/exports.mbt`（`doc_tree`）/ Create `test/_doc.ts`（§D-2 の読み側まで）/ Modify `test/doc-law.test.ts`
- Step 1 の 3 本の受け口テストはここに置く
- コミット: `test: 🧪 新 core の読みを TS から見る受け口を開ける`
- **旧 Task 31 の解体その 2** 〔重大〕

### Task 33: 木の生成器と法則 1 のファズ

- Create `core/doc/law_wbtest.mbt` / Modify `package.json`（`"test:doc"` の 1 行だけ）
- **`sample_block` のラベル付き引数を `=` に直す** 〔重大 + 軽微〕:
  ```moonbit
    5 => Content(Image(alt="図", src="./img/a.png"))
    6 => Content(Link(text="題", href="https://example.com/t"))
    _ => Content(Code(info="ts", text="const x = `1`;"))
  ```
- **`chain(n) -> Ast` を定義しない。** `fixture_wbtest.mbt` の **`chain_ast(n)`** を使い、「深さ 200 の一本鎖でも法則 1 が立つ」の `let m = chain(200)` を `let m = chain_ast(200)` に置換 〔致命 ×2〕
- **`side_for` が implied に Left を割り当てないようにする**（裁定 1）。`gen_implied` は必ず `side: Right` で作る。実装コメントに「implied は側を持てない（不変条件 11）」と書く 〔致命〕
- `"test:doc": "moon -C core test -p mmm-app/core/doc"`。**`"test:core"` は触らない**
- コミット: `test: 🧪 木をばら撒いて、読み書きの往復を殴る`

### Task 34: 法則 2 — 実在コーパスとカタログ

- **裁定 9 に従い、Step 3 を実装のある形にする** 〔重大〕。見出し直下に「**依存**: T1（Task 1〜9）・T2（Task 10〜17）・T3（Task 20〜26）の完了後に着手する」を追加し、Step 3 の見出しを「**Step 3: 落ちた行を担当へ渡す（このタスクに実装は無い）**」に変え、本文を次にする:
  > 失敗メッセージの `path` / `期待` / `実際` を逐語で写して T2（`block.mbt` / `build.mbt`）または T3（`serialize.mbt`）へ渡す。**このファイルの期待値は緩めない。** 表が古い場合だけ、表の行と `why` を書き替える。
  そのうえで **Step 3 に「表の行を書き替える」具体的な差し替え手順**（どの行の `want` をどう直すか、`why` に何を書くか）を書く
- **CATALOG C7 の owner 欄を書き替える** 〔軽微〕:
  `"手書きの --- が残るのは すげ替え v1（後日箱 X06）。v0 では *** に正規化されるのが正しい"`
  （C7 の `want` は v0 の期待として正しいのでそのまま）

### Task 35: 病的な md のランダム生成器

- Modify `test/_doc.ts`（`randomMd`）/ Modify `test/doc-law.test.ts`
- 軸の自己検査（`axes`）はそのまま。`- - -` の軸は**飾りの水平線**として残す（裁定 2）

### Task 36: 法則 4 — 方言表と外部審判

- Create `test/doc-dialect.test.ts`
- **Step 3 を Task 34 と同じ形に直す**（実装は他タスク持ち。「落ちた行を担当へ渡す」+ 表の書き替え手順） 〔重大〕
- **DIALECT に `- - -` の行を「捨てた方言」として明記する** 〔致命〕:
  `{ id: "`- - -` は飾りの水平線（旧 core の「前から箇条書き」方言は捨てた）", md: "# r\n\n- - -\n", nodes: ["H:r"], blocks: ["rule"], lezer: <実測値>, verdict: "same", why: "CommonMark の thematic break。裁定 2" }`
  「この決定を T1 へ伝えること」は「**T1 Task 6 で実装済み**」に直す
- **R109 の 2 行を足す** 〔軽微〕:
  ① `{ id: "文書頭の --- は閉じ delimiter が有れば frontmatter", md: "---\nk: v\n---\n\n# r\n", nodes: ["H:r"], blocks: [], lezer: <実測値>, verdict: <実測に合わせる>, why: "封筒として切り出し、head に逐語で持つ（§4）" }`
  ② `{ id: "閉じが無ければ先頭トグル（左開始）", md: "---\n\n## a\n", nodes: ["H:a"], blocks: [], lezer: ["a"], verdict: "same", why: "R109 の裁定。implied root の先頭スロットが左になる" }`
  `lezer` 欄は「審判の読みも表のとおり」テストが検算するので**実測値**を入れる

### Task 37: 最小反例の縮小と、操作の受け口

- Modify `test/_doc.ts`（`shrink` / `applyOp` / `applyEdits` / `OpEdit` / `OpResult`）/ Modify `core/doc/wire.mbt`（`reject_tag` / `apply_op`）/ Modify `core/doc/js/exports.mbt`（`doc_apply`）/ Modify `test/doc-law.test.ts`
- **`OpResult` を判別可能ユニオンにする** 〔重大〕:
  ```ts
  export type OpResult =
    | { ok: true; text: string; sig: string; edits: OpEdit[] }
    | { ok: false; reject: string };
  ```
- 受け口テストの `applyEdits(md, res.edits ?? [])` を `applyEdits(md, res.edits)` に戻し、直前を **`if (!res.ok) assert.fail(res.reject);`** にして絞り込みを効かせる（`assert.equal(res.ok, true)` では TS が絞り込まない）
- 依存: **T5（`move.mbt` / `side.mbt` / `delete.mbt` / `edit.mbt` / `diff.mbt` / `reflect.mbt`）が揃った後**に着手する。前半（`shrink`）だけは T5 を待たずに実行できる
- Step 4 の Expected に `pnpm run check` を入れる（`noUnusedLocals` があるので未使用 import 1 個で赤になる）

### T4 が他へ渡すもの

- `docApply` の JSON は `{"ok":true,"text":…,"sig":…,"edits":[…]}` / `{"ok":false,"reject":"missing"|"cycle"|"ineligible"|"unknown-op"}`
- `test/doc-ops.test.ts` は `applyOp` / `applyEdits` / `shrink` / `sig` / `check` / `tree` / `flatten` / `randomMd` を `test/_doc.ts` から import して使う（**写経しない**）

## G-5. T5（Task 40〜50）— 操作と反映

### 全体

1. **Task 番号を振り直す**（§H）。旧 Task 45（delete と flipSide の同居・Step 9 個）を **45（消す）と 46（側を返す）**に割り、旧 46 → 47、旧 47 → 48、旧 48 → 50 とし、**49 に文書タスク**を新設する 〔重大 ×2 + 重大 1〕
2. **`tree_wbtest.mbt` を作らない。** `fixture_wbtest.mbt`（T1 Task 2）を使う。`doc_of(...)`（Ast を返していたもの）を **`ast_of(...)`** に、`nd(...)` を **`node(...)`** に、Task 41〜48 の全テスト本文で一括置換する 〔致命 ×3〕
3. **`done` / `rejected` は Task 43 で `fixture_wbtest.mbt` の末尾に追記する**（`Outcome` がそこで初めて存在する）。これが T5 に許された唯一の他人のファイルへの書き込みである
4. **`spell(nd, at)` → `spellable(nd, at)`、`before(a, b)` → `precedes(a, b)`** に改名 〔軽微〕
5. **契約への申し送りの誤りを直す** 〔軽微〕: `Error [4014] The value X is undefined.` は誤り。§F-1 の `Error: [4021] / The value identifier X is unbound.` に統一する。`pub type Path = Array[Int]` の指摘は**正しく、契約に取り込み済み**（§A-5） 〔重大〕
6. 前提の「`core/doc/ast.mbt` と `moon.pkg` はまだ無ければ §2 を写す」を削除し、「**T1 Task 1 のコミットを待って着手する**」に置き換える 〔軽微〕
7. 全 git を `git -C <REPO> …`、全 moon を `moon -C <REPO>/core …` に統一 〔軽微〕

### Task 43: 操作の共通の道具

- Create `core/doc/op.mbt` / `core/doc/op_wbtest.mbt` / **Modify `core/doc/fixture_wbtest.mbt`（`done` / `rejected` の 2 本だけを末尾に追記）**
- `pub type Path = Array[Int]`（`typealias` ではない）
- `precedes` / `under` / `at_path` / `amend` / `pluck` / `seek`

### Task 44: 不変条件の回復（normalize）

- Modify `core/doc/op.mbt`（`normalize` / `fix` / `spellable`）/ Modify `core/doc/op_wbtest.mbt`
- **`spellable` に裁定 1 の 4 つ目の引き金を実装する** 〔致命 — 法則 1 の穴〕。親の視点（深さと直前の兄弟の側）が要るので、`fix` から
  `spellable(sorted[i], i, depth + 1, prev_side)` の形で渡し、
  **`depth + 1 == 2 && (nd.side is Left || 直前の兄弟と側が違う)` なら `promote(nd, nd.label)`** する
- テストを 1 本足す:「側のトグルを要する implied スロットは昇格する」期待 `head:-\nlf\n[H[Hr[H<[H~[Hb]]]]]`
- **doc 直下の順序法則のテストを 1 本足す** 〔軽微 R042〕:
  `ast_of([node(2, Heading, "r", []), node(3, Item, "c", [])])` を normalize して `head:-\nlf\n[H[Ic][Hr]]` を期待する

### Task 45: 消す

- Create `core/doc/delete.mbt` / `core/doc/delete_wbtest.mbt`
- 旧 Task 45 の Step 1〜4 をそのまま使い、**Step 5 を足す**: `git -C <REPO> add core/doc/delete.mbt core/doc/delete_wbtest.mbt && git -C <REPO> commit -m "feat: ✨ 消す操作を置く"` 〔重大〕

### Task 46: 側を返す

- Create `core/doc/side.mbt` / `core/doc/side_wbtest.mbt`
- 旧 Task 45 の Step 5〜8 を Step 1〜4 に繰り上げ、Step 5 を `feat: ✨ 側を返す操作を置く` にする 〔重大〕
- **`flip_side` は対象が implied なら `promote` してから反転する**（裁定 1）。テスト 1 本: `# r` + `#### b` の implied スロットへの flipSide が C16 の結果になること 〔致命〕

### Task 47: 動かす

- Create `core/doc/move.mbt` / `core/doc/move_wbtest.mbt`
- **文書を親とする move のテストを 2 本足す** 〔重大 R059 / R060〕:
  - ①「枝を文書の子へ move すると root になる」— `# r` 下の `a` を `move_nodes(ast, [3], 1, 1)` して `head:-\nlf\n[H[Hr][Ha]]` を期待（深さが 1 に付け直され、side が Right へ落ちることも同時に押さえる）
  - ②「root は文書を親とする move で並べ替わる」— 2 本の root を入れ替えて順序が変わること

### Task 48: 操作の性質のファズ（TS 側）

- Create `test/doc-ops.test.ts`
- **import を T4 の export に合わせて全面的に書き直す** 〔致命 ×2〕:
  ```ts
  import { sig, check, tree, flatten, applyOp, applyEdits, randomMd, shrink,
           type DocNode, type OpResult } from "./_doc.ts";
  import { fuzzCases, brief } from "./_helpers.ts";
  ```
  - `doc.sig(x)` → `sig(x)` ／ `doc.tree(x)` → `tree(x)` ／ `doc.apply(md, op, ids, p, at)` → `applyOp(md, op, ids, p, at)` ／ `randomDoc(seed)` → `randomMd(seed)` ／ `ApplyResult` → `OpResult`
  - `const bad = doc.check(r.text); if (bad !== "")` → `const bad = check(r.text); if (bad.length > 0) { failures.push(\`seed=${seed} ${name}: ${bad.join(" / ")}\`); }`
  - **ローカルの `applyEdits` 定義を削除**して import 版を使う（写経しない）
  - Interfaces 節の型名を `OpResult` / `OpEdit` に統一
  - **`noUnusedLocals` があるので、使わない import は 1 個も残さない**
- **`opsFor` の parent 候補に doc を含める** 〔重大〕: `for (const p of [ids[0], mid, last])`（`ids[0]` = doc の id 1）
- 性質は 3 つのまま（意味保全 ／ 法則 2 の実地検証 ／ 自己検査 `applyEdits(旧全文, r.edits) === r.text`）
- `MMM_FUZZ` は PowerShell / Bash の両方併記 〔軽微〕

### Task 49: 回復と拒否・アンカーの注意（文書）〔重大 R138 / R176〕

- Create `docs/superpowers/specs/2026-08-29-recover-reject.md`
- **憲法（`2026-08-29-doc-model-design.md`）とカタログ（`2026-08-29-op-cases.md`）は触らない。** C16 は統括が追加済み
- 2 節を書く:
  ① **「回復と拒否」** — reshape = `normalize` が回復する 5 つ（implied の消滅・implied の昇格・単調性・順序法則・側の落とし込み）と、**裁定 1 で足した 6 つ目（側を持たされた implied の昇格）**。reject = `Missing` / `Cycle` / `Ineligible` と、それぞれが起きる操作
  ② **「注意」** — rename は見出しから生成される GitHub のアンカーを壊す（md の宿命）
- Step 1〜5 を持たせる。Step 1 = 節の見出しと箇条の骨格を書く／Step 2 = `normalize` と `Reject` の実装を読んで実際の回復・拒否と突き合わせ、食い違いを列挙する／Step 3 = 本文を書く／Step 4 = 文書を読み返して、実装に無い回復・拒否が書かれていないことを確かめる／Step 5 = コミット `docs: 📝 新 core の回復・拒否の一覧とアンカーの注意を残す`

### Task 50: 殺す条件の判定と、その記録 〔重大 + 裁定 10〕

**旧 Task 48 を、他タスクと同じ Step 1〜5 の形に再構成する。**

- Files: Create `docs/superpowers/specs/2026-08-29-kill-check.md`
- **Step 1: 判定 1〜6 を実行する具体コマンドを書く**
  ```
  grep -c "if \|match " <REPO>/core/doc/move.mbt
  grep -n "implied\|is_implied" <REPO>/core/doc/move.mbt <REPO>/core/doc/side.mbt <REPO>/core/doc/delete.mbt
  grep -n "Heading\|Item" <REPO>/core/doc/move.mbt <REPO>/core/doc/side.mbt <REPO>/core/doc/delete.mbt
  grep -n -- "---\|\"#\"\|<details>" <REPO>/core/doc/op.mbt <REPO>/core/doc/move.mbt <REPO>/core/doc/side.mbt <REPO>/core/doc/delete.mbt
  ```
- **Step 2: 判定 7 を回す**
  - PowerShell: `$env:MMM_FUZZ = '5000'; node --test <REPO>/test/doc-ops.test.ts; Remove-Item Env:MMM_FUZZ`
  - Bash: `MMM_FUZZ=5000 node --test <REPO>/test/doc-ops.test.ts`
- **Step 3: 赤が 1 つでもあれば次の操作に着手せず設計へ戻る**（判定基準は旧 Task 48 の 1〜7 をそのまま使う。判定 3 は「`spellable` と `fix` の 2 か所以外に `implied` が出ない」ことを見る — **裁定 1 の昇格も `normalize` 側なので判定 3 は守られる**）
- **Step 4: `docs/superpowers/specs/2026-08-29-kill-check.md` に判定 1〜7 の数値と緑／黄／赤を 10 行以内で書く**（残すのは Why = 判定基準と数値だけ。How の苦闘は残さない）
- **Step 5: コミット** `git -C <REPO> add docs/superpowers/specs/2026-08-29-kill-check.md && git -C <REPO> commit -m "docs: 📝 殺す条件の判定結果を残す"`

---

# H. タスク番号の割り当て（衝突しないこと）

| 群 | 帯 | 使う番号 | 数 |
|---|---|---|---|
| T1 | 1〜9 | **1, 2, 3, 4, 5, 6, 7, 8, 9** | 9 |
| T2 | 10〜19 | **10, 11, 12, 13, 14, 15, 16, 17** | 8 |
| T3 | 20〜29 | **20, 21, 22, 23, 24, 25, 26** | 7 |
| T4 | 30〜39 | **30, 31, 32, 33, 34, 35, 36, 37** | 8 |
| T5 | 40〜50 | **40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50** | 11 |

T5 だけ帯を 50 まで広げた（隣が居ないので衝突しない。裁定 8 の「帯を広げて隣と衝突しない範囲で振る」に従う）。**小数（10.5）も英字（45b）も使わない。**

## H-1. 各群の内訳（確定）

| # | 主題 | 主な成果物 |
|---|---|---|
| **1** | パッケージ・木の型・綴りの定数 | `moon.pkg` / `ast.mbt` / `spell.mbt` / `ast_wbtest.mbt` |
| **2** | 手で木を組む道具と、指紋 | `fixture_wbtest.mbt` / `ast.mbt`(`esc`,`sig`) |
| **3** | 不変条件の検査（11 個） | `ast.mbt`(`check`) |
| **4** | 行の走査と、文字・空白の道具 | `line.mbt` / `line_wbtest.mbt` |
| **5** | 見出しと項目の行 | `scan.mbt`(型,`atx_at`,`bullet_at`) / `scan_wbtest.mbt` |
| **6** | 水平線と setext の行、`- - -` の裁定 | `scan.mbt`(`break_at`,`setext_at`,`bullet_at` の guard) |
| **7** | フェンス・畳み・封筒の行（+ 封筒の結線・CRLF） | `scan.mbt`(`fence_*`,`is_tag`,`is_summary`,`scan_head`) |
| **8** | かたまりの駆動 — コンテナのスタック（+ インデントコード） | `scan.mbt`(駆動部) / `block.mbt`(仮置き) |
| **9** | 方言の仕上げ（項目内見出し・setext・summary） | `scan.mbt`(3 か所の局所 Edit) |
| **10** | かたまり 1 つを Block に読む | `block.mbt`(**Modify**) / `block_wbtest.mbt` |
| **11** | コードと svg の認定 | `block.mbt` |
| **12** | かたまりの並びを木にする（深さ・id） | `build.mbt` / `build_wbtest.mbt` |
| **13** | 深さの飛びから implied を導く | `build.mbt` |
| **14** | 中身と区切りの帰属 | `build.mbt` |
| **15** | 側の割り当て | `build.mbt` |
| **16** | 畳みの対応付け | `build.mbt`（`spell.mbt` は読むだけ） |
| **17** | 読みの入口と、通しの固定テスト | `parse.mbt` |
| **20** | 封筒・改行・空文書 | `serialize.mbt` / `serialize_wbtest.mbt` |
| **21** | 骨格行 — 見出しと項目、implied、空行の継ぎ目 | `serialize.mbt` |
| **22** | 中身のかたまり（+ コードのフェンス化を前倒し） | `serialize.mbt` |
| **23** | フェンスの本数・tight・空のコード | `serialize.mbt` |
| **24** | 側のトグル（+ 段落直後の回帰テスト） | `serialize.mbt` |
| **25** | 畳み | `serialize.mbt` |
| **26** | 正規形の全文（C9・C5・C11・深さ 200） | `serialize_wbtest.mbt` |
| **30** | テスト基盤の 3 件を直す | `test/_helpers.ts:171` / `test/doc-law.test.ts` |
| **31** | MoonBit の受け口（読みの 3 本） | `wire.mbt` / `js/moon.pkg` / `js/exports.mbt` |
| **32** | 木の JSON と TS ラッパ | `wire.mbt`(`tree_of`) / `test/_doc.ts` |
| **33** | 木の生成器と法則 1 のファズ | `law_wbtest.mbt` / `package.json`(`test:doc`) |
| **34** | 法則 2 — 実在コーパスとカタログ | `test/doc-law.test.ts` |
| **35** | 病的な md のランダム生成器 | `test/_doc.ts`(`randomMd`) |
| **36** | 法則 4 — 方言表と外部審判 | `test/doc-dialect.test.ts` |
| **37** | 最小反例の縮小と、操作の受け口 | `test/_doc.ts`(`shrink`,`applyOp`) / `wire.mbt`(`apply_op`) |
| **40** | Edit を当てる／行境界で刈る | `edit.mbt` / `diff.mbt` / `diff_wbtest.mbt` |
| **41** | 反映 v0 | `reflect.mbt` |
| **42** | form は行き先に従う | `form.mbt` / `form_wbtest.mbt` |
| **43** | 操作の共通の道具（+ `done` / `rejected` の追記） | `op.mbt` / `op_wbtest.mbt` / `fixture_wbtest.mbt` |
| **44** | 不変条件の回復（裁定 1 の昇格を含む） | `op.mbt`(`normalize`,`fix`,`spellable`) |
| **45** | 消す | `delete.mbt` / `delete_wbtest.mbt` |
| **46** | 側を返す（implied は昇格してから反転） | `side.mbt` / `side_wbtest.mbt` |
| **47** | 動かす（+ 文書を親とする move） | `move.mbt` / `move_wbtest.mbt` |
| **48** | 操作の性質のファズ（TS 側） | `test/doc-ops.test.ts` |
| **49** | 回復と拒否・アンカーの注意 | `docs/…/2026-08-29-recover-reject.md` |
| **50** | 殺す条件の判定と、その記録 | `docs/…/2026-08-29-kill-check.md` |

## H-2. 依存図（着手の順）

```
T1 Task 1 ──┬─> T1 Task 2〜9
            ├─> T2 Task 10（block.mbt は T1 Task 8 の仮置きを待つ）
            ├─> T3 Task 20〜26（spell.mbt を読むだけ）
            └─> T5 Task 40・42・43・44・45・46・47（手で組んだ Ast で完結）

T1 Task 2（fixture_wbtest） ──> T3 Task 21〜26 ／ T4 Task 33 ／ T5 Task 41〜48
T1 Task 8（scan の駆動）    ──> T2 Task 12〜17
T2 Task 17（parse）─┬─> T4 Task 31・32
T3 Task 26（serialize）┤
T3 Task 26 ──────────> T5 Task 41（reflect）
T4 Task 32 ──> T4 Task 33 ──> T4 Task 34 ──> T4 Task 35 ──> T4 Task 36
T5 Task 45・46・47 ──> T4 Task 37（操作の受け口）──> T5 Task 48（TS ファズ）
T5 Task 48 ──> T5 Task 49 ──> T5 Task 50
T4 Task 30 ──────────────────> 単独で先行できる（誰も待たない）
```

**統合の順は仕様 §9 のとおり**: parse + serialize + 法則 1・2 が立つ（操作ゼロで土台を証明）→ 3 操作 + 反映 v0。

---

## 最後に — 全員が守る 5 行

1. **表に無いファイルを作らない。**他人のファイルを書き換えない（例外は T5 Task 43 の `fixture_wbtest.mbt` への 2 関数の追記だけ）
2. **`ast.mbt` の型を変えたくなったら、書き換える前に全員へ共有する。**5 人の共有物である
3. **旧 core（`core/*.mbt`・`core/js/`）・`src/`・既存 `test/*.test.ts` 26 本・仕様・カタログは 1 バイトも触らない**
4. **Step 2 の Expected は §F の逐語で書く。**「たぶんこう落ちる」を書かない
5. **`Total tests: 0` を見たら緑ではない。**`-p` の綴りを疑う