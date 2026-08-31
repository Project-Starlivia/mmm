# G1 — 型と走査

新 core の土台。**この群だけが単独で完結する**（G2/G3/G5 は G1 の型の上に建つ）。

---

## この群の概要

### 担当範囲

契約 §19 の G1。新パッケージ `mmm-app/core/tree` を建て、**型・指紋・不変条件・行の走査・正規形の綴り**の
5 つを置く。
意味の判断（骨格の認定・Implicit の導出・側の割り当て）は 1 つも書かない — それは G2 の仕事。

| 作るもの | ファイル | 契約 |
|---|---|---|
| パッケージと型の全文 | `core/tree/moon.pkg` / `core/tree/doc.mbt` | §13（moon.pkg の逐語）/ §6（型の全文） |
| 手で木を組むテスト用ヘルパ | `core/tree/make_wbtest.mbt` | §2（所有）/ §4（名前）/ §16（テスト表） |
| 指紋 sig | `core/tree/sig.mbt` / `core/tree/sig_wbtest.mbt` | §8 |
| 不変条件 check | `core/tree/check.mbt` / `core/tree/check_wbtest.mbt` | §7 |
| 行の走査 scan | `core/tree/scan.mbt` / `core/tree/scan_wbtest.mbt` | §6（走査の前提）/ §10（Token の全文） |
| 正規形の綴り spell | `core/tree/spell.mbt` | §12 |

`spell.mbt` は前版で所有が G3 と二重になっていた（査読 R1-04 / R2-02 / R3-05）。
契約 §2 が **G1 の所有**と定めたので、この群が Task 10.5 で置く。値の見張り（テスト 2 本）は
G3 Task 40 が持つ — **G1 はテストを足さない**（契約 §19 G1）。

### 前提

- 作業ディレクトリ: `D:/1.atrium/mmm/.worktrees/feat/tree-core`（ブランチ `feat/tree-core`）。
  ワークツリーが無ければ先に切る（CLAUDE.md の Branch・Worktree 規約）
- **既存ファイルは 1 行も触らない。** `package.json` の scripts と `.github/workflows/ci.yml` と
  `test/tsconfig.json` は G4 が触る（契約 §2）。G1 は `core/tree/` に足すだけ
- 旧 core（`mmm-app/core` と `mmm-app/core/js`）は同じディレクトリツリーに同居する。
  `moon.mod` にも上位の `moon.pkg` にも登録は要らない（契約 §2）
- ツールチェイン: `moon 0.1.20260803` / `moonc v0.10.6+80dc50f24`
- **他群の所有ファイルには 1 バイトも書かない**（契約 §2）。直しが要ると分かったら差し戻す

### 着手順

```
Task 1 (型とヘルパ)
   ├── Task 2 (sig)
   ├── Task 3 (check)
   └── Task 4 (走査の骨)
          └── Task 5 (見出し) → Task 6 (水平線と setext) → Task 7 (項目)
                 → Task 8 (フェンスとインデントコード) → Task 9 (畳みとコメント)
                 → Task 10 (封筒) → Task 10.5 (spell) → Task 11 (締め)
```

Task 2 と Task 3 は Task 1 の後なら並行してよい。**Task 5〜10 は順番に依存する**
（走査の枝分かれの順序そのものが意味を持つ — setext は水平線より先、水平線は項目より先）。
Task 10.5 は他のどの Task にも依存しないが、**G2 Task 22 が `spell` を待っている**ので
群を抜ける前に必ず置く。

### テストの内訳（Step 4 の本数の根拠）

Step 2 / Step 4 は**ファイル指定**で走らせる（契約 §17）ので、期待する本数は**そのファイルの本数**。

| ファイル | 本数 | 置いた Task |
|---|---|---|
| `make_wbtest.mbt` | 1 | Task 1 |
| `sig_wbtest.mbt` | 4 | Task 2 |
| `check_wbtest.mbt` | 8 | Task 3 |
| `scan_wbtest.mbt` | 12 | Task 4〜10（2→3→5→7→9→11→12） |
| **合計** | **25** | 締め（Task 11）の `-p` で数える |

契約 §16 の G1 合計 **25 本**と一致する（同表の `make_wbtest.mbt` の「0」は合計 25 と合わない。
`make_wbtest.mbt` は型の全構成要素を触るテストを 1 本持つ — 内訳は上の表が正）。

### 新設する名前（契約 §4 に登録済み。1 バイトも変えない）

**契約 §4 の表に無い名前をトップレベルに置いてはならない。** 足したくなったら、まず契約を直す。

| 住所 | 名前 |
|---|---|
| `doc.mbt`（型） | `Doc` `Root` `Branch` `Node` `Skeleton` `Form` `Side` `Eol` `Block` `Content` `Verdict` |
| `doc.mbt`（構築子） | `Implicit` `Explicit` `Heading` `Item` `Right` `Left` `Lf` `Crlf` `Content` `Rule` `Opaque` `Image` `Link` `Code` `Svg` `Applied` `Rejected` |
| `doc.mbt`（定数） | `doc_id`（= 1）`first_id`（= 2） |
| `check.mbt` | `check`（pub）`fault` `check_node` `check_one` `check_kin` `is_item` |
| `sig.mbt` | `sig`（pub）`sig_root` `sig_node` `sig_skeleton` `sig_blocks` `sig_content` `sig_text` |
| `scan.mbt`（型） | `Token`（構築子 `Blank` `Head` `Bullet` `Bar` `Fence` `Open` `Close` `Verse`）`Scan` |
| `scan.mbt` | `scan`（pub）`Row` `rows_of` `row_of` `envelope` `is_front` `head_at` `setext_at` `setext` `bar_at` `bullet_at` `fence_at` `fenced` `close_len` `indented` `is_fold_open` `is_fold_close` `opens_comment` `closes_comment` `starts` `strip` `trim_end` `is_blank` `cut` `joined` |
| `spell.mbt` | `Spell` `spell`（pub）`eol_text`（pub） |
| `make_wbtest.mbt` | `make_doc` `make_root` `make_branch` `make_node` `make_head` `make_item` |
| `scan_wbtest.mbt` | `scan_sig` `scan_flat` |
| `sig_wbtest.mbt` / `check_wbtest.mbt` | ヘルパを持たない（`sig_` は `sig.mbt` が使い切っている。木は `make_*` で組む） |

- **`make_item`**（前版の `make_list` から改名）。型は `Form::Item` で、G3 も独立に `write_item` と
  名乗った。同じものを 2 つの語彙（Item / list）で呼ばない（査読 R1-12 / R3-16）
- `make_wbtest.mbt` の役割は「**G1 が置き、G3・G4・G5 のテストが葉の組み立てに使う**」。
  契約 §4 が G3 の `write_of` / `write_slot`、G5 の `op_head` / `op_item` を削って
  `make_*` へ寄せたので、この記述はそのまま事実になる
- 同一パッケージの `*_wbtest.mbt` は名前空間を共有する（`Error: [4051]`）。
  ヘルパ名はそのファイルの接頭辞（`make_` / `scan_`）で始める

### 契約 §15 の読みの裁定 9 件（この群が固定する）

憲法・契約の隙間を埋めた読みの裁定は、契約 §15 に取り込まれている。
**G1 は 9 件のうち 8 件を `scan_wbtest.mbt` で固定する**（残り 1 件は parse の仕事）。

| # | 裁定 | 固定する場所 |
|---|---|---|
| 1 | setext の下線が付いた段落が複数行なら、最後の 1 行だけが見出しになる。手前の行は散文（Opaque）のまま残る | Task 6 のテスト + G4 の `READING` 表 |
| 2 | 怠惰な継続（lazy continuation）は読まない。列が浅い行は項目の領土から出る | Task 7 のテスト + G4 の `READING` 表 |
| 3 | インデントコードは空行の直後だけ開く。段落の続きを巻き込まない | Task 8 のテスト + G4 の `READING` 表 |
| 4 | インデントコードは `Fence` Token（`info` 無し）に落ちる | Task 8 のテスト |
| 5 | `<summary>` 行は Verse として parse へ渡る。捨てるのは parse の仕事（契約 §9） | Task 9 のテスト（+ G2 の `parse_wbtest.mbt`） |
| 6 | `<details>` は属性つきの形も受ける。読みは書きより広い | Task 9 のテスト |
| 7 | 順序リスト（`1.` `1)`）は Bullet に落ち、番号は Token に残らない | Task 7 のテスト |
| 8 | マーカーの後ろの空白が 5 桁以上でも hang は 1 桁ぶん。余りはラベルに入らない | Task 7 のテスト |
| 9 | HTML コメント（`<!--` 〜 `-->`）の中の行はすべて Verse。中の `#` は見出しにならない | Task 9 のテスト + G4 の `READING` 表 |

裁定 1・2・3・9 は「骨格の数は lezer と合うが読んだ中身が違う」ので、G4 の `DIALECT`（数の表）では
捕まらない。だから G4 は 2 つ目の表 `READING`（md → 指紋）を持つ（契約 §15）。**G1 は G4 の表を書かない。**

### コマンド（契約 §17。すべて実測済み）

```
型検査   moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core check tree
テスト   moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/<file>_wbtest.mbt
締め     moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test -p mmm-app/core -p mmm-app/core/tree
整形確認 moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt --check tree
整形適用 moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt tree
```

- **Step 2 / Step 4 はファイル指定**（本数が他群と独立して固定できる）。綴りを間違えると
  `Error: Failed to canonicalize input filter directory` で **EXIT=127** になり、黙って緑にならない
- **`-p` を使うのは締め（Task 11）と Task 10.5 だけ。** `-p` の綴りを間違えると
  `Total tests: 0` のまま **EXIT=0 で緑になる**（契約 §17 の罠）ので、`Total tests:` の数を目で見る
- **`moon check` に `-p` は無い**。絞るなら `moon -C <root>/core check tree`
- `moon fmt --check` の失敗は EXIT=127（PowerShell 経由では -1 と出る）
- `moon fmt` の対象は **`doc` だけ**。既存の `js` を巻き込んだ瞬間に赤になる（契約 §17）。
  `doc tree/js` は G4 の締めが持つ
- テスト失敗の逐語（契約 §18）:
  ```
  [mmm-app/core] test tree/scan_wbtest.mbt:44 ("...") failed: doc/scan_wbtest.mbt:46:3-46:40@mmm-app/core FAILED: `"x" != "y"`
  diff:
  -"x" +"y"
  Total tests: 14, passed: 13, failed: 1.
  ```
  EXIT=2

### 期待する警告

Task 4〜7 の間だけ、`moon check` が 1 本出す:

```
Warning: [0007]
 24 │   start : Int
    │   ──┬──
    │     ╰──── Warning (unused_field): Field 'start' is never read
```

`Row.start` を読むのは Task 8 の `strip` だけなので、そこまでは正直に出る。
**`Row` から `start` を消して逃げないこと** — Task 8 で必ず要る。
Task 8 以降は **0 warnings / 0 errors**。

Task 10.5 の直後は `spell` の読み手（G2・G3）がまだ居ないので警告が出うる。
**合格条件は `0 errors`**（契約 §11）。可視性を下げたり読み捨てのコードを足したりして黙らせない。

### コミット

CLAUDE.md の規約 `<Type>: <Emoji> #<Issue Number> <Title>`。Issue 番号が採れているなら
各コミットの `:` の後に `#NN ` を足す（Type と Title は必須、Issue は強く推奨）。

---

## Task 1: パッケージの新設と型の全文

**Files:**
- Create: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/moon.pkg`
- Create: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/doc.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/make_wbtest.mbt`

**Interfaces:**
- Consumes: なし（この群の起点）
- Produces:
  - パッケージ `mmm-app/core/tree`
  - `pub(all) struct Doc { frontmatter : String?; eol : Eol; body : Array[Block]; roots : Array[Root] }`
  - `pub(all) struct Root { id : Int; skeleton : Skeleton; branches : Array[Branch] }`
  - `pub(all) struct Branch { side : Side; node : Node }`
  - `pub(all) struct Node { id : Int; skeleton : Skeleton; children : Array[Node] }`
  - `pub(all) enum Skeleton { Implicit; Explicit(form~ : Form, label~ : String, folded~ : Bool, body~ : Array[Block]) }`
  - `pub(all) enum Form { Heading; Item }` / `pub(all) enum Side { Right; Left }` / `pub(all) enum Eol { Lf; Crlf }`
  - `pub(all) enum Block { Content(Content); Rule; Opaque(String) }`
  - `pub(all) enum Content { Image(alt~ : String, src~ : String); Link(text~ : String, href~ : String); Code(info~ : String, text~ : String); Svg(String) }`
  - `pub(all) enum Verdict { Applied; Rejected(String) }`
  - `pub let doc_id : Int = 1` / `pub let first_id : Int = 2`
  - `fn make_doc(roots : Array[Root]) -> Doc`
  - `fn make_root(id : Int, skeleton : Skeleton, branches : Array[Branch]) -> Root`
  - `fn make_branch(side : Side, node : Node) -> Branch`
  - `fn make_node(id : Int, skeleton : Skeleton, children : Array[Node]) -> Node`
  - `fn make_head(label : String) -> Skeleton` / `fn make_item(label : String) -> Skeleton`

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/moon.pkg` を作る（**別名は書かない** — `moon fmt` が剥がす。契約 §13）:

```
pkgtype(kind: "library")
```

`core/tree/make_wbtest.mbt`:

```moonbit
// 手で木を組む道具。テストの本文が「何を守っているか」だけになるように、
// 既定（封筒なし・Lf・散文なし・畳まない・中身なし）を 1 か所へ寄せる。
// G1 が置き、G3・G4・G5 のテストが葉の組み立てに使う
// （wbtest は名前空間を共有するので接頭辞は `make_`）。
//
// 既定から外れるもの（畳み・body・封筒・Crlf）は素の構築子で書く —
// ヘルパに腕を生やさない。

///|
fn make_doc(roots : Array[Root]) -> Doc {
  { frontmatter: None, eol: Lf, body: [], roots }
}

///|
fn make_root(id : Int, skeleton : Skeleton, branches : Array[Branch]) -> Root {
  { id, skeleton, branches }
}

///|
fn make_branch(side : Side, node : Node) -> Branch {
  { side, node }
}

///|
fn make_node(id : Int, skeleton : Skeleton, children : Array[Node]) -> Node {
  { id, skeleton, children }
}

///|
fn make_head(label : String) -> Skeleton {
  Explicit(form=Heading, label~, folded=false, body=[])
}

///|
fn make_item(label : String) -> Skeleton {
  Explicit(form=Item, label~, folded=false, body=[])
}

///|
test "型の全構成要素が 1 本の木として組める" {
  let doc : Doc = {
    frontmatter: Some("image-folder: img"),
    eol: Crlf,
    body: [Rule, Opaque("intro"), Content(Svg("<svg/>"))],
    roots: [
      make_root(
        2,
        Explicit(form=Item, label="c", folded=true, body=[
          Content(Image(alt="a", src="./a.png")),
          Content(Link(text="t", href="https://example.com")),
          Content(Code(info="js", text="1")),
        ]),
        [
          make_branch(Right, make_node(3, make_item("x"), [])),
          make_branch(
            Left,
            make_node(4, Implicit, [make_node(5, make_head("y"), [])]),
          ),
        ],
      ),
    ],
  }
  assert_eq(doc.body.length(), 3)
  assert_eq(doc.roots[0].branches.length(), 2)
  assert_eq(doc.roots[0].branches[1].node.children.length(), 1)
  assert_eq(doc_id, 1)
  assert_eq(first_id, 2)
}
```

備考: 憲法 §2 の型の全構成要素を 1 本の木で触る（構築子を 1 つでも落とすと `unused_constructor` が出る）。

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/make_wbtest.mbt`

Expected: `Error: [4032]` / `The type Doc is undefined.`（`Root` `Branch` `Node` `Skeleton` `Side` `Eol` も同じ）
+ `Error: [4021]` / `The value identifier doc_id is unbound.`。EXIT=1

- [ ] **Step 3: 最小の実装を書く**

`core/tree/doc.mbt`（契約 §6 の逐語。1 バイトも変えない）:

```moonbit
// 型の定義。md が表現できる構造だけを、md の語彙で持つ木。
// 綴り（空行の数・マーカーの銘柄）は持たないので Ast ではない。

///|
/// 文書は深さ 0 の器。frontmatter と eol は綴りのダイヤルで、意味は body と roots。
pub(all) struct Doc {
  frontmatter : String? // 封筒の逐語（`---` の柵は含まない）
  eol : Eol
  body : Array[Block] // 最初の骨格より前の散文
  roots : Array[Root]
}

///|
/// 親が文書のノード。root 専用の操作語彙は無い（文書を親とする move / add）。
pub(all) struct Root {
  id : Int
  skeleton : Skeleton
  branches : Array[Branch]
}

///|
/// スロット = 場所。占有者を問わず側を持ち、id は持たない。
/// side が「root 直下のスロット → 側」の部分写像であることが、そのまま型になっている。
pub(all) struct Branch {
  side : Side
  node : Node
}

///|
/// 深さ 3 以降は一様。
pub(all) struct Node {
  id : Int
  skeleton : Skeleton
  children : Array[Node]
}

///|
/// 骨格行の有無。Implicit は「飛びが綴り」なので label も body も型ごと無い。
pub(all) enum Skeleton {
  Implicit
  Explicit(form~ : Form, label~ : String, folded~ : Bool, body~ : Array[Block])
}

///|
/// 見出しか項目か。Implicit を入れないのは setForm の引数型だから。
pub(all) enum Form {
  Heading
  Item
}

///|
pub(all) enum Side {
  Right
  Left
}

///|
pub(all) enum Eol {
  Lf
  Crlf
}

///|
/// 骨格に貼り付く中身。Content だけが絵になる（Rule と Opaque は buried）。
pub(all) enum Block {
  Content(Content)
  Rule
  Opaque(String)
}

///|
pub(all) enum Content {
  Image(alt~ : String, src~ : String)
  Link(text~ : String, href~ : String)
  Code(info~ : String, text~ : String)
  Svg(String)
}

///|
/// 操作の結果。拒否の理由は文字列 1 本（境界では reason に載る）。
pub(all) enum Verdict {
  Applied
  Rejected(String)
}

///|
/// 文書の id。親を指すときの番兵で、どのノードも名乗ってはならない。
pub let doc_id : Int = 1

///|
/// parse が配る最初の id。文書順に 1 つずつ増える。
pub let first_id : Int = 2
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/make_wbtest.mbt`

Expected: `Total tests: 1, passed: 1, failed: 0.` EXIT=0

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 新 core のパッケージと型を置く"
```

---

## Task 2: 指紋 sig

**Files:**
- Create: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/sig.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/sig_wbtest.mbt`

**Interfaces:**
- Consumes: `Doc` `Root` `Branch` `Node` `Skeleton` `Form` `Side` `Eol` `Block` `Content`（Task 1）/
  `make_doc` `make_root` `make_branch` `make_node` `make_head`（Task 1）
- Produces: `pub fn sig(doc : Doc) -> String` — id を含まない木の綴り。法則 1・2 の唯一の比較子

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/sig_wbtest.mbt`:

```moonbit
// 指紋。法則 1・2 の唯一の比較子なので、綴りを 1 文字も動かさないよう固定する。
// ヘルパは持たない（`sig_` は sig.mbt が使い切っている。木は `make_*` で組む）。

///|
test "例 1: `# r` + `## a`" {
  let doc = make_doc([
    make_root(2, make_head("r"), [
      make_branch(Right, make_node(3, make_head("a"), [])),
    ]),
  ])
  assert_eq(sig(doc), "D-n()[Reh_1:r()[>Neh_1:a()[]]]")
}

///|
test "例 2: `# r` + `---` + `#### b`（C16。先頭スロットが左、占有者は Implicit 2 段）" {
  let doc = make_doc([
    make_root(2, make_head("r"), [
      make_branch(
        Left,
        make_node(3, Implicit, [
          make_node(4, Implicit, [make_node(5, make_head("b"), [])]),
        ]),
      ),
    ]),
  ])
  assert_eq(sig(doc), "D-n()[Reh_1:r()[<Ni[Ni[Neh_1:b()[]]]]]")
}

///|
test "例 3: 封筒・CRLF・doc の散文・畳んだ項目 root・飾りの水平線・コードカード" {
  let doc : Doc = {
    frontmatter: Some("image-folder: img"),
    eol: Crlf,
    body: [Opaque("intro")],
    roots: [
      make_root(2, Explicit(form=Item, label="c", folded=true, body=[Rule]), [
        make_branch(
          Right,
          make_node(
            3,
            Explicit(form=Heading, label="x", folded=false, body=[
              Content(Code(info="js", text="1")),
            ]),
            [],
          ),
        ),
      ]),
    ],
  }
  assert_eq(
    sig(doc),
    "D+17:image-folder: imgr(o5:intro)[Rel^1:c(r)[>Neh_1:x(cc2:js1:1)[]]]",
  )
}

///|
test "長さ前置なので、区切り文字が中身に混ざっても曖昧さが出ない" {
  let plain = make_doc([make_root(2, make_head("a"), [])])
  let tricky = make_doc([make_root(2, make_head("a()[]>2:"), [])])
  assert_eq(sig(plain), "D-n()[Reh_1:a()[]]")
  assert_eq(sig(tricky), "D-n()[Reh_8:a()[]>2:()[]]")
  // 中身が構造の綴りを真似ても、長さが先に来るので読み違えようがない
  assert_eq(sig(plain) == sig(tricky), false)
}
```

備考: 例 1〜3 は契約 §8 の 3 例そのもの。4 本目は長さ前置（`<10進の長さ>:<中身>`）が
逃がし規則を要らなくしていることの実演。

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/sig_wbtest.mbt`

Expected: `Error: [4021]` / `The value identifier sig is unbound.` EXIT=1

- [ ] **Step 3: 最小の実装を書く**

`core/tree/sig.mbt`（契約 §8 の逐語）:

```moonbit
// 指紋 — id を含まない木の綴り。法則 1・2 の唯一の比較子。
// 文字列は長さ前置（`<10進の長さ>:<中身>`）なので、逃がし規則が要らない。

///|
pub fn sig(doc : Doc) -> String {
  let sb = StringBuilder::new()
  sb.write_string("D")
  match doc.frontmatter {
    None => sb.write_string("-")
    Some(s) => {
      sb.write_string("+")
      sig_text(sb, s)
    }
  }
  sb.write_string(
    match doc.eol {
      Lf => "n"
      Crlf => "r"
    },
  )
  sig_blocks(sb, doc.body)
  sb.write_string("[")
  for r in doc.roots {
    sig_root(sb, r)
  }
  sb.write_string("]")
  sb.to_string()
}

///|
fn sig_root(sb : StringBuilder, root : Root) -> Unit {
  sb.write_string("R")
  sig_skeleton(sb, root.skeleton)
  sb.write_string("[")
  for b in root.branches {
    sb.write_string(
      match b.side {
        Right => ">"
        Left => "<"
      },
    )
    sig_node(sb, b.node)
  }
  sb.write_string("]")
}

///|
fn sig_node(sb : StringBuilder, node : Node) -> Unit {
  sb.write_string("N")
  sig_skeleton(sb, node.skeleton)
  sb.write_string("[")
  for c in node.children {
    sig_node(sb, c)
  }
  sb.write_string("]")
}

///|
fn sig_skeleton(sb : StringBuilder, skeleton : Skeleton) -> Unit {
  match skeleton {
    Implicit => sb.write_string("i")
    Explicit(form~, label~, folded~, body~) => {
      sb.write_string("e")
      sb.write_string(
        match form {
          Heading => "h"
          Item => "l"
        },
      )
      sb.write_string(if folded { "^" } else { "_" })
      sig_text(sb, label)
      sig_blocks(sb, body)
    }
  }
}

///|
fn sig_blocks(sb : StringBuilder, blocks : Array[Block]) -> Unit {
  sb.write_string("(")
  for b in blocks {
    match b {
      Rule => sb.write_string("r")
      Opaque(s) => {
        sb.write_string("o")
        sig_text(sb, s)
      }
      Content(c) => {
        sb.write_string("c")
        sig_content(sb, c)
      }
    }
  }
  sb.write_string(")")
}

///|
fn sig_content(sb : StringBuilder, content : Content) -> Unit {
  match content {
    Image(alt~, src~) => {
      sb.write_string("i")
      sig_text(sb, alt)
      sig_text(sb, src)
    }
    Link(text~, href~) => {
      sb.write_string("l")
      sig_text(sb, text)
      sig_text(sb, href)
    }
    Code(info~, text~) => {
      sb.write_string("c")
      sig_text(sb, info)
      sig_text(sb, text)
    }
    Svg(s) => {
      sb.write_string("s")
      sig_text(sb, s)
    }
  }
}

///|
/// 長さ前置の文字列。長さは UTF-16 コード単位（`String::length()`）。
fn sig_text(sb : StringBuilder, s : String) -> Unit {
  sb.write_string(s.length().to_string())
  sb.write_string(":")
  sb.write_string(s)
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/sig_wbtest.mbt`

Expected: `Total tests: 4, passed: 4, failed: 0.` EXIT=0

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 木の指紋を置く（法則 1・2 の比較子）"
```

---

## Task 3: 不変条件 check

**Files:**
- Create: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/check.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/check_wbtest.mbt`

**Interfaces:**
- Consumes: `Doc` `Root` `Branch` `Node` `Skeleton` `Form` `doc_id`（Task 1）/ `make_*`（Task 1）
- Produces: `pub fn check(doc : Doc) -> Array[String]` — 破れを全部集めて返す（空 = 健全）

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/check_wbtest.mbt`:

```moonbit
// 6 つの関係的な不変条件。破れは全部集まり、健全な木では空になる。
// ヘルパは持たない（木は `make_*` で組む）。

///|
test "健全な木では破れが 1 つも出ない" {
  let doc = make_doc([
    make_root(2, make_head("r"), [
      make_branch(
        Right,
        make_node(3, make_item("x"), [make_node(4, make_item("y"), [])]),
      ),
      make_branch(
        Left,
        make_node(5, Implicit, [make_node(6, make_head("b"), [])]),
      ),
    ]),
  ])
  assert_eq(check(doc), [])
}

///|
test "条件 1: id は文書内で一意。文書 id を名乗ったノードも落ちる" {
  let twice = make_doc([
    make_root(2, make_head("a"), []),
    make_root(2, make_head("b"), []),
  ])
  assert_eq(check(twice), ["id が重なっている (id=2)"])
  let sentinel = make_doc([make_root(doc_id, make_head("a"), [])])
  assert_eq(check(sentinel), ["id が重なっている (id=1)"])
}

///|
test "条件 2: Implicit は子を持つ限りにおいて存在する" {
  let doc = make_doc([
    make_root(2, make_head("r"), [
      make_branch(Right, make_node(7, Implicit, [])),
    ]),
  ])
  assert_eq(check(doc), ["Implicit に子が無い (id=7)"])
}

///|
test "条件 3: Implicit の前の兄弟はすべて項目" {
  let doc = make_doc([
    make_root(2, make_head("r"), [
      make_branch(Right, make_node(3, make_head("a"), [])),
      make_branch(
        Right,
        make_node(7, Implicit, [make_node(8, make_head("b"), [])]),
      ),
    ]),
  ])
  assert_eq(check(doc), [
    "Implicit の前に項目でない兄弟が居る (id=7)",
  ])
}

///|
test "条件 4: Implicit の子に項目は居ない" {
  let doc = make_doc([
    make_root(2, make_head("r"), [
      make_branch(
        Right,
        make_node(6, Implicit, [make_node(7, make_item("x"), [])]),
      ),
    ]),
  ])
  assert_eq(check(doc), ["Implicit の子が項目 (id=7)"])
}

///|
test "条件 4: Implicit の連鎖は合法（C16）" {
  let doc = make_doc([
    make_root(2, make_head("r"), [
      make_branch(
        Left,
        make_node(3, Implicit, [
          make_node(4, Implicit, [make_node(5, make_head("b"), [])]),
        ]),
      ),
    ]),
  ])
  assert_eq(check(doc), [])
}

///|
test "条件 5: 同じ親の子は項目が先、見出しが後" {
  let ok = make_doc([
    make_root(2, make_item("x"), []),
    make_root(3, make_head("h"), []),
  ])
  let ng = make_doc([
    make_root(3, make_head("h"), []),
    make_root(7, make_item("x"), []),
  ])
  assert_eq(check(ok), [])
  assert_eq(check(ng), ["見出しの後ろに項目が居る (id=7)"])
}

///|
test "条件 6: 項目の子孫はすべて項目" {
  let doc = make_doc([
    make_root(2, make_head("r"), [
      make_branch(
        Right,
        make_node(3, make_item("x"), [make_node(7, make_head("h"), [])]),
      ),
    ]),
  ])
  assert_eq(check(doc), ["項目の子孫が項目でない (id=7)"])
}
```

備考: 契約 §7 の 6 条件と 6 つの違反メッセージ（憲法 §2 の「check に残る関係的不変条件」）。
条件 5 は doc 直下（roots の列）にも効くことを、同じテストで確かめている。
条件 4 は破れの実体（子が項目）を名指す文言に揃えてあり、**Implicit の連鎖は合法**である
（C16 の `Ni[Ni[Neh_1:b()[]]]` が通らないと読み戻せない）ことを 2 本目のテストで固定する。

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/check_wbtest.mbt`

Expected: `Error: [4021]` / `The value identifier check is unbound.` EXIT=1

- [ ] **Step 3: 最小の実装を書く**

`core/tree/check.mbt`:

```moonbit
// 型で殺せなかった関係的な不変条件だけの検査。破れを全部集めて返す（空 = 健全）。
// 型で死んだもの（doc の汚れ / 深い side / implicit×label,body,folded,Item /
// setForm(Implicit) / sides と children の整合）はここに住まない。

///|
/// 破れの一覧。空なら健全。parse が出した Doc は必ずこれが空になる。
pub fn check(doc : Doc) -> Array[String] {
  let faults : Array[String] = []
  // 番兵を先に登録するので、文書 id を名乗ったノードは条件 1 で落ちる
  let seen : Array[Int] = [doc_id]
  check_kin(faults, doc.roots.map(fn(r) { (r.id, r.skeleton) }))
  for r in doc.roots {
    check_one(
      faults,
      seen,
      r.id,
      r.skeleton,
      r.branches.map(fn(b) { (b.node.id, b.node.skeleton) }),
    )
    for b in r.branches {
      check_node(faults, seen, b.node, is_item(r.skeleton))
    }
  }
  faults
}

///|
/// item = 祖先に項目が居るか（単調性の見張り）。
fn check_node(
  faults : Array[String],
  seen : Array[Int],
  node : Node,
  item : Bool,
) -> Unit {
  // 条件 6: 項目の子孫はすべて項目（Implicit も違反）
  if item && !is_item(node.skeleton) {
    faults.push(fault("項目の子孫が項目でない", node.id))
  }
  check_one(
    faults,
    seen,
    node.id,
    node.skeleton,
    node.children.map(fn(c) { (c.id, c.skeleton) }),
  )
  let deep = item || is_item(node.skeleton)
  for c in node.children {
    check_node(faults, seen, c, deep)
  }
}

///|
/// 1 つのノードと、その子の列に効く条件をまとめて見る。
fn check_one(
  faults : Array[String],
  seen : Array[Int],
  id : Int,
  skeleton : Skeleton,
  kids : Array[(Int, Skeleton)],
) -> Unit {
  // 条件 1: id は文書内で一意（番兵 doc_id を含む）
  if seen.contains(id) {
    faults.push(fault("id が重なっている", id))
  } else {
    seen.push(id)
  }
  if skeleton is Implicit {
    // 条件 2: Implicit は子を持つ限りにおいて存在する
    if kids.is_empty() {
      faults.push(fault("Implicit に子が無い", id))
    }
    // 条件 4: Implicit の子に項目は居ない（子は見出しか Implicit）
    for k in kids {
      if is_item(k.1) {
        faults.push(fault("Implicit の子が項目", k.0))
      }
    }
  }
  check_kin(faults, kids)
}

///|
/// 条件 3: Implicit の前の兄弟はすべて項目（見出しは飛びを飲み込むので読み戻せない）。
/// 条件 5: 同じ親の子は項目が先、見出しが後（Implicit は見出しの側）。
fn check_kin(faults : Array[String], kin : Array[(Int, Skeleton)]) -> Unit {
  let mut head = false
  for k in kin {
    let item = is_item(k.1)
    if k.1 is Implicit && head {
      faults.push(
        fault("Implicit の前に項目でない兄弟が居る", k.0),
      )
    }
    if item && head {
      faults.push(fault("見出しの後ろに項目が居る", k.0))
    }
    if !item {
      head = true
    }
  }
}

///|
fn is_item(skeleton : Skeleton) -> Bool {
  match skeleton {
    Explicit(form~, ..) => form is Item
    Implicit => false
  }
}

///|
/// 違反の綴りは 1 つ。`<破れ> (id=<n>)`。
fn fault(what : String, id : Int) -> String {
  what + " (id=" + id.to_string() + ")"
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/check_wbtest.mbt`

Expected: `Total tests: 8, passed: 8, failed: 0.` EXIT=0

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 型で殺せない不変条件 6 つの検査を置く"
```

---

## Task 4: 走査の骨 — 行・列・改行の流儀

**Files:**
- Create: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/scan.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/scan_wbtest.mbt`

**Interfaces:**
- Consumes: `Eol`（Task 1）
- Produces:
  - `pub(all) enum Token { Blank; Head(col~, level~, label~); Bullet(col~, hang~, label~); Bar(col~, dash~); Fence(col~, info~, text~); Open(col~); Close(col~); Verse(col~, text~) }`
  - `pub(all) struct Scan { frontmatter : String?; eol : Eol; tokens : Array[Token] }`
  - `pub fn scan(text : String) -> Scan`
  - `priv struct Row { start : Int; end : Int; col : Int; from : Int }`
  - `fn rows_of(text : String) -> Array[Row]` / `fn row_of(text : String, start : Int, end : Int) -> Row`
  - `fn cut(text : String, a : Int, b : Int) -> String`
  - `fn scan_sig(text : String) -> String` / `fn scan_flat(text : String) -> String`（wbtest 側）

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/scan_wbtest.mbt`:

```moonbit
// 行の走査。読める綴りの全部と、方言の 1 つずつ。
// ヘルパ名は `scan_` で始める（wbtest は名前空間を共有する）。

///|
/// Token の列を 1 行に畳む。`;` 区切り、改行は `\n` の 2 文字に逃がす。
fn scan_sig(text : String) -> String {
  let sb = StringBuilder::new()
  for i, t in scan(text).tokens {
    if i > 0 {
      sb.write_string(";")
    }
    sb.write_string(
      match t {
        Blank => "_"
        Head(col~, level~, label~) =>
          "H" + col.to_string() + "," + level.to_string() + "," + label
        Bullet(col~, hang~, label~) =>
          "B" + col.to_string() + "," + hang.to_string() + "," + label
        Bar(col~, dash~) => (if dash { "-" } else { "*" }) + col.to_string()
        Fence(col~, info~, text~) =>
          "F" + col.to_string() + "," + info + "," + scan_flat(text)
        Open(col~) => "(" + col.to_string()
        Close(col~) => ")" + col.to_string()
        Verse(col~, text~) => "V" + col.to_string() + "," + scan_flat(text)
      },
    )
  }
  sb.to_string()
}

///|
fn scan_flat(text : String) -> String {
  let sb = StringBuilder::new()
  for c in text {
    if c == '\n' {
      sb.write_string("\\n")
    } else {
      sb.write_char(c)
    }
  }
  sb.to_string()
}

///|
test "行に切り、改行の流儀を測る。行末の `\\r` は綴りなので Token に残らない" {
  assert_eq(scan("p\n").eol is Lf, true)
  assert_eq(scan("p\r\n\r\nq\r\n").eol is Crlf, true)
  assert_eq(scan_sig("p\r\n\r\nq\r\n"), "V0,p;_;V0,q")
  assert_eq(scan_sig("p\n\nq"), "V0,p;_;V0,q")
  // 末尾の改行が無くても最後の行は読む
  assert_eq(scan_sig("p"), "V0,p")
  assert_eq(scan_sig(""), "")
}

///|
test "行頭の空白は列として測り、Token の中身からは落ちる。タブは 4 の桁" {
  assert_eq(scan_sig(" p\n"), "V1,p")
  assert_eq(scan_sig("  p\n"), "V2,p")
  assert_eq(scan_sig("p\n\tq\n"), "V0,p;V4,q")
  assert_eq(scan_sig("p\n \tq\n"), "V0,p;V4,q")
  assert_eq(scan_sig("   \n"), "_")
}
```

備考: 憲法 §4 の EOL（原文の流儀を保存するダイヤル）と、契約 §6「走査の前提」の
「`col` はタブを 4 で数えた中身の始まる列」。この 2 本は以後どの Task でも真のまま。

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/scan_wbtest.mbt`

Expected: `Error: [4032]` / `The type Token is undefined.` +
`Error: [4021]` / `The value identifier scan is unbound.` EXIT=1

- [ ] **Step 3: 最小の実装を書く**

`core/tree/scan.mbt`:

```moonbit
// md → Token の列。封筒を剥がし、改行の流儀を測り、行を綴りの語彙へ落とす。
// 方言（setext・`#######`・`- - -`・HTML コメント・インデントコード）はここで吸収する。
//
// **意味の判断はしない。** 項目の領土内の見出しを Opaque にするか、飛びから
// Implicit を導出するか、隙間の `---` がトグルかは、すべて parse の仕事。
// ここが答えるのは「この行はどう綴られているか」だけ。

///|
/// 走査の 1 単位。物理行 1 本と 1 対 1 だが、フェンスだけは開きから閉じまでで 1 枚。
/// col はタブを 4 で数えた「中身の始まる列」。
pub(all) enum Token {
  Blank
  Head(col~ : Int, level~ : Int, label~ : String)
  Bullet(col~ : Int, hang~ : Int, label~ : String)
  Bar(col~ : Int, dash~ : Bool)
  Fence(col~ : Int, info~ : String, text~ : String)
  Open(col~ : Int)
  Close(col~ : Int)
  Verse(col~ : Int, text~ : String)
}

///|
/// 走査の全部。封筒と改行の流儀は Doc へそのまま渡る。
pub(all) struct Scan {
  frontmatter : String?
  eol : Eol
  tokens : Array[Token]
}

///|
/// 物理行 1 本。col と from は行頭の空白を読み飛ばした先で、
/// 空行は `from == end` で見分ける。
priv struct Row {
  start : Int
  end : Int
  col : Int
  from : Int
}

///|
pub fn scan(text : String) -> Scan {
  let rows = rows_of(text)
  let eol = if text.contains("\r\n") { Crlf } else { Lf }
  let tokens : Array[Token] = []
  let mut i = 0
  while i < rows.length() {
    let r = rows[i]
    if r.from >= r.end {
      tokens.push(Blank)
    } else {
      tokens.push(Verse(col=r.col, text=cut(text, r.from, r.end)))
    }
    i = i + 1
  }
  { frontmatter: None, eol, tokens }
}

///|
/// 物理行に切る。行末の `\r` は測るときに落とす（流儀は eol が 1 つ持つ）。
fn rows_of(text : String) -> Array[Row] {
  let out : Array[Row] = []
  let n = text.length()
  let mut start = 0
  let mut i = 0
  while i < n {
    if text[i].to_int() == 10 {
      let mut e = i
      if e > start && text[e - 1].to_int() == 13 {
        e = e - 1
      }
      out.push(row_of(text, start, e))
      start = i + 1
    }
    i = i + 1
  }
  if start < n {
    out.push(row_of(text, start, n))
  }
  out
}

///|
fn row_of(text : String, start : Int, end : Int) -> Row {
  let mut p = start
  let mut col = 0
  while p < end {
    let c = text[p].to_int()
    if c == 32 {
      col = col + 1
    } else if c == 9 {
      col = col + 4 - col % 4
    } else {
      break
    }
    p = p + 1
  }
  { start, end, col, from: p }
}

///|
/// 任意の UTF-16 オフセットで切る。`text[a:b]` はサロゲート途中で panic するので使わない。
fn cut(text : String, a : Int, b : Int) -> String {
  if a >= b {
    ""
  } else {
    String::unsafe_substring(text, start=a, end=b)
  }
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/scan_wbtest.mbt`

Expected: `Total tests: 2, passed: 2, failed: 0.` EXIT=0
+ `Warning: [0007]` / `Warning (unused_field): Field 'start' is never read`（Task 8 まで出る。消さない）

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 行の走査の骨（行・列・改行の流儀）を置く"
```

---

## Task 5: 見出し

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/scan.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/scan_wbtest.mbt`

**Interfaces:**
- Consumes: `Row` `Token` `cut`（Task 4）
- Produces:
  - `fn head_at(text : String, r : Row) -> (Int, String)?` — ATX なら（level, label）
  - `fn trim_end(text : String, r : Row) -> Int` / `fn is_blank(c : Int) -> Bool`
  - `scan` の中の**容器のスタック** `hangs : Array[Int]` と `base : Int`（Task 7 が押す）

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/scan_wbtest.mbt` の末尾に足す:

```moonbit

///|
test "見出しは ATX。level に上限は無く、閉じの `#` と余白は飾り" {
  assert_eq(scan_sig("# r\n\n## a\n"), "H0,1,r;_;H0,2,a")
  assert_eq(scan_sig("# r\r\n\r\n## a\r\n"), "H0,1,r;_;H0,2,a")
  assert_eq(scan_sig("####### deep\n"), "H0,7,deep")
  assert_eq(scan_sig("##   spaced   ##  \n"), "H0,2,spaced")
  assert_eq(scan_sig("## ###\n"), "H0,2,")
  assert_eq(scan_sig("#hashtag\n"), "V0,#hashtag")
  // 行頭の飾り字下げ（0〜3）は読み飛ばす
  assert_eq(scan_sig("   # a\n"), "H3,1,a")
}
```

備考: 憲法 §4 の「level は無制限 — `#######`（7 個以上）も書く」と契約 §15 の方言表
「`#######` も見出しとして読む」（lezer は段落と読むので法則 4 の期待差分）。
閉じ `#` と余白の除去は C9。**7 個以上の `#` の読みはここが唯一の実装**で、
G4 は同じ判定を作らない（契約 §4）。

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/scan_wbtest.mbt`

Expected: `FAILED: `"V0,# r;_;V0,## a" != "H0,1,r;_;H0,2,a"`` +
`Total tests: 3, passed: 2, failed: 1.` EXIT=2

- [ ] **Step 3: 最小の実装を書く**

`scan.mbt` の `scan` を、次の全文へ置き換える（`hangs` と `base` と枝分かれの箱を入れる）:

```moonbit
///|
pub fn scan(text : String) -> Scan {
  let rows = rows_of(text)
  let eol = if text.contains("\r\n") { Crlf } else { Lf }
  let tokens : Array[Token] = []
  // 開いている項目の中身の列。深い容器はこの列で閉じる
  let hangs : Array[Int] = []
  let mut i = 0
  while i < rows.length() {
    let r = rows[i]
    if r.from >= r.end {
      tokens.push(Blank)
      i = i + 1
      continue
    }
    // 深い容器を閉じる。怠惰な継続（列 0 に書かれた項目の続き）は読まない —
    // 中身は字下げで書く、が mmm の綴り
    while hangs.length() > 0 && r.col < hangs[hangs.length() - 1] {
      ignore(hangs.unsafe_pop())
    }
    let base = if hangs.length() > 0 { hangs[hangs.length() - 1] } else { 0 }
    if r.col <= base + 3 {
      if head_at(text, r) is Some((level, label)) {
        tokens.push(Head(col=r.col, level~, label~))
        i = i + 1
        continue
      }
    }
    tokens.push(Verse(col=r.col, text=cut(text, r.from, r.end)))
    i = i + 1
  }
  { frontmatter: None, eol, tokens }
}
```

`scan.mbt` の `cut` の直前に足す:

```moonbit
///|
/// ATX 見出しなら level とラベル。level に上限は無い（`#######` も見出し）。
/// 閉じの `#` は空白に前置されているときだけ飾りとして落とす。
fn head_at(text : String, r : Row) -> (Int, String)? {
  let mut p = r.from
  while p < r.end && text[p].to_int() == 35 {
    p = p + 1
  }
  let level = p - r.from
  if level == 0 {
    return None
  }
  if p < r.end && !is_blank(text[p].to_int()) {
    return None
  }
  let mut a = p
  while a < r.end && is_blank(text[a].to_int()) {
    a = a + 1
  }
  let mut b = trim_end(text, r)
  let mut c = b
  while c > a && text[c - 1].to_int() == 35 {
    c = c - 1
  }
  if c < b && (c == a || is_blank(text[c - 1].to_int())) {
    b = c
    while b > a && is_blank(text[b - 1].to_int()) {
      b = b - 1
    }
  }
  Some((level, cut(text, a, b)))
}

///|
/// 行末の空白を落とした位置。
fn trim_end(text : String, r : Row) -> Int {
  let mut b = r.end
  while b > r.from && is_blank(text[b - 1].to_int()) {
    b = b - 1
  }
  b
}

///|
fn is_blank(c : Int) -> Bool {
  c == 32 || c == 9
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/scan_wbtest.mbt`

Expected: `Total tests: 3, passed: 3, failed: 0.` EXIT=0

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 見出しを読む（level 無制限・閉じの # は飾り）"
```

---

## Task 6: 水平線と setext

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/scan.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/scan_wbtest.mbt`

**Interfaces:**
- Consumes: `Row` `Token` `trim_end` `is_blank`（Task 4・5）
- Produces:
  - `fn bar_at(text : String, r : Row) -> Bool?` — 水平線なら「印が `-` か」
  - `fn setext_at(text : String, r : Row) -> Int?` — 下線なら level
  - `fn setext(tokens : Array[Token], level : Int) -> Unit` — 直前の Verse を Head へ差し替える
  - `scan` の中の `verse : Bool`（直前の行が段落か）

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/scan_wbtest.mbt` の末尾に足す:

```moonbit

///|
test "`- - -` は水平線。`---` はトグルの候補として dash が立つ" {
  assert_eq(scan_sig("---\n"), "-0")
  assert_eq(scan_sig("- - -\n"), "-0")
  assert_eq(scan_sig("***\n"), "*0")
  assert_eq(scan_sig("___\n"), "*0")
  assert_eq(scan_sig("--\n"), "V0,--")
  assert_eq(scan_sig("   ---\n"), "-3")
}

///|
test "setext は読む。段落が複数行なら最後の 1 行だけが見出しになる" {
  assert_eq(scan_sig("a\n---\n"), "H0,2,a")
  assert_eq(scan_sig("a\n===\n"), "H0,1,a")
  assert_eq(scan_sig("x\ny\n---\n"), "V0,x;H0,2,y")
  // 空行で段落が切れていれば下線ではなく水平線
  assert_eq(scan_sig("a\n\n---\n"), "V0,a;_;-0")
  // `***` は段落の直後でも水平線（setext の下線は `-` と `=` だけ）
  assert_eq(scan_sig("a\n***\n"), "V0,a;*0")
}
```

備考: 憲法 §4 の方言表「setext は読む」と「捨てた方言: `- - -` は CommonMark どおり水平線」。
`x\ny\n---` の行は契約 §15 の読みの裁定 1（複数行段落は最後の 1 行だけが見出し）を固定する
（G4 の `READING` 表が md → 指紋で二重に見張る）。
`dash` は G2 が「トグルか飾りか」を決めるための材料（憲法 §4 のチャンネル分離）。

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/scan_wbtest.mbt`

Expected: `FAILED: `"V0,---" != "-0"`` + `Total tests: 5, passed: 3, failed: 2.` EXIT=2

- [ ] **Step 3: 最小の実装を書く**

`scan.mbt` の `scan` の中、`let mut i = 0` の**直前**に足す:

```moonbit
  let mut verse = false // 直前の行が段落（setext の下線が効く条件）
```

`scan` の中、`tokens.push(Blank)` の**直後**に足す:

```moonbit
      verse = false
```

`scan` の中、`head_at` の枝の `tokens.push(Head(col=r.col, level~, label~))` の**直後**に足す:

```moonbit
        verse = false
```

`scan` の中、`head_at` の枝（`}` で閉じたところ）の**直後**、`}` で `if r.col <= base + 3 {` を
閉じる**手前**に足す:

```moonbit
      if verse && setext_at(text, r) is Some(level) {
        setext(tokens, level)
        verse = false
        i = i + 1
        continue
      }
      if bar_at(text, r) is Some(dash) {
        tokens.push(Bar(col=r.col, dash~))
        verse = false
        i = i + 1
        continue
      }
```

`scan` の中、末尾の `tokens.push(Verse(col=r.col, text=cut(text, r.from, r.end)))` の**直後**に足す:

```moonbit
    verse = true
```

`scan.mbt` の `head_at` の**直前**に足す:

```moonbit
///|
/// setext の下線なら level。`=` が 1、`-` が 2。間に空白を挟む形は下線ではない。
fn setext_at(text : String, r : Row) -> Int? {
  let b = trim_end(text, r)
  let c = text[r.from].to_int()
  if c != 61 && c != 45 {
    return None
  }
  for p = r.from; p < b; p = p + 1 {
    if text[p].to_int() != c {
      return None
    }
  }
  Some(if c == 61 { 1 } else { 2 })
}

///|
/// 直前の Verse を見出しに差し替える。段落が複数行なら最後の 1 行だけが
/// 見出しになり、手前の行は散文のまま残る（意味を落とさない側に倒す）。
fn setext(tokens : Array[Token], level : Int) -> Unit {
  let last = tokens.unsafe_pop()
  match last {
    Verse(col~, text~) => tokens.push(Head(col~, level~, label=text))
    _ => tokens.push(last)
  }
}

///|
/// 水平線なら、その印が `-` かどうか。同じ印が 3 つ以上で、間は空白だけ
/// （`- - -` は CommonMark どおり水平線であって項目ではない）。
fn bar_at(text : String, r : Row) -> Bool? {
  let c = text[r.from].to_int()
  if c != 45 && c != 42 && c != 95 {
    return None
  }
  let b = trim_end(text, r)
  let mut n = 0
  for p = r.from; p < b; p = p + 1 {
    let d = text[p].to_int()
    if d == c {
      n = n + 1
    } else if !is_blank(d) {
      return None
    }
  }
  if n < 3 {
    return None
  }
  Some(c == 45)
}
```

**枝分かれの順序は動かしてはならない** — setext は水平線より先（段落の直後の `---` は下線）、
水平線は項目より先（`- - -` は項目ではない）。

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/scan_wbtest.mbt`

Expected: `Total tests: 5, passed: 5, failed: 0.` EXIT=0

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 水平線と setext を読む（`- - -` は水平線）"
```

---

## Task 7: リスト項目と容器のスタック

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/scan.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/scan_wbtest.mbt`

**Interfaces:**
- Consumes: `Row` `Token` `trim_end` `is_blank` `cut`（Task 4・5）/ `hangs`（Task 5）
- Produces: `fn bullet_at(text : String, r : Row) -> (Int, String)?` — 項目なら（hang, label）

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/scan_wbtest.mbt` の末尾に足す:

```moonbit

///|
test "項目はマーカー 3 種と順序リスト。hang が中身の列" {
  assert_eq(scan_sig("- a\n"), "B0,2,a")
  assert_eq(scan_sig("* a\n"), "B0,2,a")
  assert_eq(scan_sig("+ a\n"), "B0,2,a")
  assert_eq(scan_sig("1. a\n"), "B0,3,a")
  assert_eq(scan_sig("12) a\n"), "B0,4,a")
  assert_eq(scan_sig("-\n"), "B0,2,")
  // 空白が 5 桁以上でも中身は 1 桁ぶんだけ下がる（余りは綴りのパディング）
  assert_eq(scan_sig("-      a\n"), "B0,2,a")
  assert_eq(scan_sig("- a\n  - b\n"), "B0,2,a;B2,4,b")
  assert_eq(scan_sig("-\ta\n"), "B0,4,a")
  // 項目の領土の中の水平線も、列を付けてそのまま渡す（C15）
  assert_eq(scan_sig("- c\n\n  ---\n"), "B0,2,c;_;-2")
}

///|
test "怠惰な継続は読まない。列が浅ければ項目の領土から出る（C17）" {
  assert_eq(scan_sig("- a\n\n## h\n"), "B0,2,a;_;H0,2,h")
  assert_eq(scan_sig("- a\ntext\n"), "B0,2,a;V0,text")
  assert_eq(scan_sig("- a\n\n  text\n"), "B0,2,a;_;V2,text")
}
```

備考: 憲法 §4「マーカーは `-`（`*` `+` は読みのみ）」「順序リストは構造として読み `-` に正規化」。
C15（`- center` の content indent に置いた `---`）と C17（項目の後ろの列 0 の見出し）。
契約 §15 の読みの裁定 2（怠惰な継続）・7（順序リストの番号）・8（空白 5 桁以上の hang）を
ここで固定する。`hang` の定義は契約 §6 の走査の前提 2 のとおり「ラベルの始まる列」。

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/scan_wbtest.mbt`

Expected: `FAILED: `"V0,- a" != "B0,2,a"`` + `Total tests: 7, passed: 5, failed: 2.` EXIT=2

- [ ] **Step 3: 最小の実装を書く**

`scan.mbt` の `scan` の中、`bar_at` の枝の**直後**、`}` で `if r.col <= base + 3 {` を
閉じる**手前**に足す:

```moonbit
      if bullet_at(text, r) is Some((hang, label)) {
        tokens.push(Bullet(col=r.col, hang~, label~))
        hangs.push(hang)
        verse = false
        i = i + 1
        continue
      }
```

`scan.mbt` の `head_at` の**直後**に足す:

```moonbit
///|
/// リスト項目なら中身の列とラベル。順序リスト（`1.` `1)`）も構造として読む
/// （番号の見た目は綴りなので、Token には残さない）。
fn bullet_at(text : String, r : Row) -> (Int, String)? {
  let c = text[r.from].to_int()
  let mut width = 0
  if c == 45 || c == 42 || c == 43 {
    width = 1
  } else if c >= 48 && c <= 57 {
    let mut q = r.from
    while q < r.end && q - r.from < 9 {
      let d = text[q].to_int()
      if d < 48 || d > 57 {
        break
      }
      q = q + 1
    }
    if q >= r.end {
      return None
    }
    let d = text[q].to_int()
    if d != 46 && d != 41 {
      return None
    }
    width = q - r.from + 1
  } else {
    return None
  }
  let mut q = r.from + width
  if q < r.end && !is_blank(text[q].to_int()) {
    return None
  }
  // 中身の列。空白が 0 桁（行末）か 5 桁以上のときは 1 桁ぶんだけ下げる
  let mut col = r.col + width
  while q < r.end && is_blank(text[q].to_int()) {
    col = if text[q].to_int() == 9 { col + 4 - col % 4 } else { col + 1 }
    q = q + 1
  }
  let hang = if q >= r.end || col - r.col - width >= 5 {
    r.col + width + 1
  } else {
    col
  }
  let mut b = trim_end(text, r)
  if b < q {
    b = q
  }
  Some((hang, cut(text, q, b)))
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/scan_wbtest.mbt`

Expected: `Total tests: 7, passed: 7, failed: 0.` EXIT=0

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ リスト項目と容器の列を読む（順序リストも構造）"
```

---

## Task 8: フェンスとインデントコード

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/scan.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/scan_wbtest.mbt`

**Interfaces:**
- Consumes: `Row` `Token` `trim_end` `is_blank` `cut`（Task 4・5）/ `Row.start`（Task 4）
- Produces:
  - `fn fence_at(text : String, r : Row) -> (Int, Int, String)?` — 開きなら（印, 本数, 情報文字列）
  - `fn fenced(text : String, rows : Array[Row], at : Int, ch : Int, len : Int, info : String, tokens : Array[Token]) -> Int`
  - `fn close_len(text : String, r : Row, ch : Int, base : Int) -> Int`
  - `fn indented(text : String, rows : Array[Row], at : Int, col : Int, tokens : Array[Token]) -> Int`
  - `fn strip(text : String, r : Row, col : Int) -> Int` / `fn joined(lines : Array[String]) -> String`
  - `scan` の中の `blank : Bool`（直前が空行か）

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/scan_wbtest.mbt` の末尾に足す:

```moonbit

///|
test "フェンスは開きから閉じまでで 1 枚。閉じなければ文書末まで" {
  assert_eq(scan_sig("```js\n1\n```\n"), "F0,js,1")
  assert_eq(scan_sig("~~~\na\nb\n~~~\n"), "F0,,a\\nb")
  assert_eq(scan_sig("```\n# not a heading\n```\n"), "F0,,# not a heading")
  assert_eq(scan_sig("````\n``` inner\n````\n"), "F0,,``` inner")
  assert_eq(scan_sig("```js\n1\n"), "F0,js,1")
  // 項目の中のフェンスは、項目の中身の列から字下げを落とす
  assert_eq(scan_sig("- a\n\n  ```\n  x\n  ```\n"), "B0,2,a;_;F2,,x")
}

///|
test "インデントコードは読めるのでフェンスと同じ 1 枚に落ちる（書くのはフェンス）" {
  assert_eq(scan_sig("    code\n"), "F4,,code")
  assert_eq(scan_sig("    a\n\n    b\n"), "F4,,a\\n\\nb")
  // 段落の続きは字下げてもコードにならない（空行の直後だけが開く条件）
  assert_eq(scan_sig("p\n    q\n"), "V0,p;V4,q")
}
```

備考: 憲法 §4「コードは常にフェンス（インデントコードは読めるが書かない）」。
インデントコードを `Fence` Token に落とすことで、書く側に選択肢が残らない（C9）。
契約 §15 の読みの裁定 3（空行の直後だけ開く）・4（Fence Token に落ちる）をここで固定する。

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/scan_wbtest.mbt`

Expected: ``FAILED: `"V0,```js;V0,1;V0,```" != "F0,js,1"`` +
`Total tests: 9, passed: 7, failed: 2.` EXIT=2

- [ ] **Step 3: 最小の実装を書く**

`scan.mbt` の `scan` の中、`let mut verse = false ...` の**直後**に足す:

```moonbit
  let mut blank = true // 直前が空行（インデントコードが開ける条件）
```

`scan` の中、`tokens.push(Blank)` の枝の `verse = false` の**直後**に足す:

```moonbit
      blank = true
```

`scan` の中、`let base = ...` の**直後**、`if r.col <= base + 3 {` の**手前**に足す:

```moonbit
    // インデントコード。空行の直後だけ開く（段落の続きを巻き込まない）
    if blank && r.col >= base + 4 {
      i = indented(text, rows, i, base + 4, tokens)
      verse = false
      blank = false
      continue
    }
```

`scan` の中、**`head_at` / setext / `bar_at` / `bullet_at` の 4 つの枝それぞれの
`verse = false` の直後**、そして末尾の `verse = true` の**直後**に足す（計 5 か所）:

```moonbit
        blank = false
```

（末尾の `verse = true` の直後だけは字下げが 4 つ: `    blank = false`）

`scan` の中、`bullet_at` の枝の**直後**、`}` で `if r.col <= base + 3 {` を閉じる**手前**に足す:

```moonbit
      if fence_at(text, r) is Some((ch, len, info)) {
        i = fenced(text, rows, i, ch, len, info, tokens)
        verse = false
        blank = false
        continue
      }
```

`scan.mbt` の `strip` を置く場所（`trim_end` の直前）と、コードの塊 4 本を足す。
`bullet_at` の**直後**に:

```moonbit
///|
/// 開きフェンスなら（印・本数・情報文字列）。バッククォートの情報文字列に
/// バッククォートは入れない。
fn fence_at(text : String, r : Row) -> (Int, Int, String)? {
  let c = text[r.from].to_int()
  if c != 96 && c != 126 {
    return None
  }
  let mut q = r.from
  while q < r.end && text[q].to_int() == c {
    q = q + 1
  }
  if q - r.from < 3 {
    return None
  }
  let mut a = q
  while a < r.end && is_blank(text[a].to_int()) {
    a = a + 1
  }
  let b = trim_end(text, r)
  if c == 96 {
    for p = a; p < b; p = p + 1 {
      if text[p].to_int() == 96 {
        return None
      }
    }
  }
  Some((c, q - r.from, cut(text, a, b)))
}

///|
/// 開きから閉じまでを 1 枚の Fence にする。閉じないまま終われば文書末まで。
/// 中身は開きフェンスの列ぶん字下げを落とす。次に読む行の添字を返す。
fn fenced(
  text : String,
  rows : Array[Row],
  at : Int,
  ch : Int,
  len : Int,
  info : String,
  tokens : Array[Token],
) -> Int {
  let open = rows[at]
  let lines : Array[String] = []
  let mut i = at + 1
  while i < rows.length() {
    let r = rows[i]
    if close_len(text, r, ch, open.col) >= len {
      i = i + 1
      break
    }
    lines.push(cut(text, strip(text, r, open.col), r.end))
    i = i + 1
  }
  tokens.push(Fence(col=open.col, info~, text=joined(lines)))
  i
}

///|
/// 閉じフェンスの本数。閉じでなければ 0。
fn close_len(text : String, r : Row, ch : Int, base : Int) -> Int {
  if r.from >= r.end || r.col > base + 3 {
    return 0
  }
  let mut q = r.from
  while q < r.end && text[q].to_int() == ch {
    q = q + 1
  }
  let len = q - r.from
  if len < 3 {
    return 0
  }
  while q < r.end {
    if !is_blank(text[q].to_int()) {
      return 0
    }
    q = q + 1
  }
  len
}

///|
/// インデントコードの塊。読めるが書かないので、フェンスと同じ 1 枚に落とす
/// （情報文字列は無い）。末尾の空行は塊の外。次に読む行の添字を返す。
fn indented(
  text : String,
  rows : Array[Row],
  at : Int,
  col : Int,
  tokens : Array[Token],
) -> Int {
  let lines : Array[String] = []
  let mut i = at
  let mut last = at
  while i < rows.length() {
    let r = rows[i]
    if r.from >= r.end {
      lines.push("")
    } else if r.col >= col {
      lines.push(cut(text, strip(text, r, col), r.end))
      last = i
    } else {
      break
    }
    i = i + 1
  }
  while lines.length() > last - at + 1 {
    ignore(lines.unsafe_pop())
  }
  tokens.push(Fence(col~, info="", text=joined(lines)))
  last + 1
}

///|
/// 行頭から col 列ぶんの空白を落とした位置。空白が尽きればそこで止まる。
fn strip(text : String, r : Row, col : Int) -> Int {
  let mut p = r.start
  let mut c = 0
  while p < r.end && c < col {
    let ch = text[p].to_int()
    if ch == 32 {
      c = c + 1
    } else if ch == 9 {
      c = c + 4 - c % 4
    } else {
      break
    }
    p = p + 1
  }
  p
}
```

`scan.mbt` の末尾（`cut` の直後）に足す:

```moonbit
///|
/// 行の列を `\n` でつなぐ（末尾の改行は付けない）。
fn joined(lines : Array[String]) -> String {
  let sb = StringBuilder::new()
  for i, line in lines {
    if i > 0 {
      sb.write_string("\n")
    }
    sb.write_string(line)
  }
  sb.to_string()
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/scan_wbtest.mbt`

Expected: `Total tests: 9, passed: 9, failed: 0.` EXIT=0
（`Row.start` を `strip` が読むようになったので、`Warning: [0007]` はここで消える）

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ コードの塊を読む（インデントコードもフェンスと同じ 1 枚）"
```

---

## Task 9: 畳みの開閉と HTML コメント

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/scan.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/scan_wbtest.mbt`

**Interfaces:**
- Consumes: `Row` `Token` `trim_end` `is_blank` `cut`（Task 4・5）
- Produces:
  - `fn is_fold_open(text : String, r : Row) -> Bool` / `fn is_fold_close(text : String, r : Row) -> Bool`
  - `fn opens_comment(text : String, r : Row) -> Bool` / `fn closes_comment(text : String, from : Int, end : Int) -> Bool`
  - `fn starts(text : String, at : Int, end : Int, lit : String) -> Bool`
  - `scan` の中の `comment : Bool`

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/scan_wbtest.mbt` の末尾に足す:

```moonbit

///|
test "畳みは details。中の行は素通しで、`<summary>` は散文のまま parse へ渡る" {
  assert_eq(
    scan_sig("<details>\n\n<summary>a</summary>\n\n## b\n\n</details>\n"),
    "(0;_;V0,<summary>a</summary>;_;H0,2,b;_;)0",
  )
  assert_eq(scan_sig("<details open>\n"), "(0")
  assert_eq(scan_sig("<detailsish>\n"), "V0,<detailsish>")
}

///|
test "HTML コメントの中の見出しは構造にならない（`<!---` も `--->` も許容）" {
  assert_eq(scan_sig("<!--\n# x\n-->\n"), "V0,<!--;V0,# x;V0,-->")
  assert_eq(scan_sig("<!--- a --->\n# x\n"), "V0,<!--- a --->;H0,1,x")
  assert_eq(scan_sig("<!-- one line -->\n# x\n"), "V0,<!-- one line -->;H0,1,x")
}
```

備考: 憲法 §4 の畳み（`<details>` 〜 `</details>`）と、方言表の「`<!---`/`--->` 許容」。
契約 §15 の読みの裁定 5・6・9 をここで固定する。
**`<summary>` は Verse のまま parse へ渡す** — 捨てるのは parse の仕事で、
「`<details>` の直後の 1 枚だけを内容を見ずに読み飛ばす」という規則は契約 §9（G2 Task 25）が持つ。
`scan` は位置も内容も判断しない。C8 のネストは G2 が組む。

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/scan_wbtest.mbt`

Expected: `FAILED: `"V0,<details>;..." != "(0;..."`` +
`Total tests: 11, passed: 9, failed: 2.` EXIT=2

- [ ] **Step 3: 最小の実装を書く**

`scan.mbt` の `scan` の中、`let mut blank = true ...` の**直後**に足す:

```moonbit
  let mut comment = false
```

`scan` の中、空行の枝（`continue` で閉じたところ）の**直後**、
`// 深い容器を閉じる。` の**手前**に足す:

```moonbit
    if comment {
      tokens.push(Verse(col=r.col, text=cut(text, r.from, r.end)))
      comment = !closes_comment(text, r.from, r.end)
      verse = true
      blank = false
      i = i + 1
      continue
    }
```

`scan` の中、`fence_at` の枝の**直後**、`}` で `if r.col <= base + 3 {` を閉じる**手前**に足す:

```moonbit
      if opens_comment(text, r) {
        tokens.push(Verse(col=r.col, text=cut(text, r.from, r.end)))
        comment = !closes_comment(text, r.from + 4, r.end)
        verse = true
        blank = false
        i = i + 1
        continue
      }
      if is_fold_open(text, r) {
        tokens.push(Open(col=r.col))
        verse = false
        blank = false
        i = i + 1
        continue
      }
      if is_fold_close(text, r) {
        tokens.push(Close(col=r.col))
        verse = false
        blank = false
        i = i + 1
        continue
      }
```

`scan.mbt` の `strip` の**直前**に足す:

```moonbit
///|
/// 畳みの開き。`<details>` に属性が付いた形も受ける（読みは書きより広い —
/// 書く側の綴りは spell が 1 か所で持つ）。
fn is_fold_open(text : String, r : Row) -> Bool {
  let b = trim_end(text, r)
  if !starts(text, r.from, b, "<details") || text[b - 1].to_int() != 62 {
    return false
  }
  let c = text[r.from + 8].to_int()
  c == 62 || is_blank(c)
}

///|
fn is_fold_close(text : String, r : Row) -> Bool {
  let b = trim_end(text, r)
  starts(text, r.from, b, "</details>") && b - r.from == 10
}

///|
/// HTML コメントの開き。`<!---` も開き（余分な `-` は中身）。
fn opens_comment(text : String, r : Row) -> Bool {
  starts(text, r.from, r.end, "<!--")
}

///|
/// `-->` が [from, end) に在るか。`--->` も閉じ。
fn closes_comment(text : String, from : Int, end : Int) -> Bool {
  let mut p = from
  while p + 3 <= end {
    if text[p].to_int() == 45 &&
      text[p + 1].to_int() == 45 &&
      text[p + 2].to_int() == 62 {
      return true
    }
    p = p + 1
  }
  false
}

///|
fn starts(text : String, at : Int, end : Int, lit : String) -> Bool {
  if at + lit.length() > end {
    return false
  }
  for k = 0; k < lit.length(); k = k + 1 {
    if text[at + k] != lit[k] {
      return false
    }
  }
  true
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/scan_wbtest.mbt`

Expected: `Total tests: 11, passed: 11, failed: 0.` EXIT=0

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 畳みの開閉と HTML コメントを読む"
```

---

## Task 10: 封筒の裁定

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/scan.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/scan_wbtest.mbt`

**Interfaces:**
- Consumes: `Row` `trim_end` `cut` `joined`（Task 4・5・8）
- Produces:
  - `fn envelope(text : String, rows : Array[Row]) -> (String?, Int)` — 封筒の逐語と、走査を始める行
  - `fn is_front(text : String, r : Row) -> Bool`

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/scan_wbtest.mbt` の末尾に足す:

```moonbit

///|
test "封筒は「直後が空行でなく、閉じがある」ときだけ。外れたら先頭トグル" {
  let front = scan("---\nimage-folder: img\n---\n\n# r\n")
  assert_eq(front.frontmatter, Some("image-folder: img"))
  assert_eq(scan_sig("---\nimage-folder: img\n---\n\n# r\n"), "_;H0,1,r")
  // 直後が空行 = mmm が書く先頭トグルの綴り（C4）
  assert_eq(scan("---\n\n## a\n").frontmatter, None)
  assert_eq(scan_sig("---\n\n## a\n"), "-0;_;H0,2,a")
  // 閉じが無ければ封筒ではない
  assert_eq(scan("---\nx\n").frontmatter, None)
  assert_eq(scan_sig("---\nx\n"), "-0;V0,x")
}
```

備考: 憲法 §4 の frontmatter の 1 条件そのもの
（「文書頭の `---` が封筒の開きなのは、直後が空行でなく、かつ閉じの `---` があるとき」）。
この条件が無いと、先頭トグルで始まりもう 1 本トグルを持つ文書が丸ごと封筒に飲まれて法則 1 が破れる。C4・C11。
封筒を剥がした後の本文だけが法則 4 の照合対象になる（契約 §15）。

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/scan_wbtest.mbt`

Expected: `FAILED: `None != Some("image-folder: img")`` +
`Total tests: 12, passed: 11, failed: 1.` EXIT=2

- [ ] **Step 3: 最小の実装を書く**

`scan.mbt` の `scan` の中、`let eol = ...` の**直後**に足す:

```moonbit
  let (frontmatter, first) = envelope(text, rows)
```

`scan` の中、`let mut i = 0` を次へ置き換える:

```moonbit
  let mut i = first
```

`scan` の中、末尾の `{ frontmatter: None, eol, tokens }` を次へ置き換える:

```moonbit
  { frontmatter, eol, tokens }
```

`scan.mbt` の `setext_at` の**直前**に足す:

```moonbit
///|
/// 封筒の裁定。文書頭の `---` が開きなのは、**直後が空行でなく、かつ閉じがある**とき。
/// 該当しなければ先頭トグル（左開始）として Bar に落ちる。
fn envelope(text : String, rows : Array[Row]) -> (String?, Int) {
  if rows.length() < 2 || !is_front(text, rows[0]) {
    return (None, 0)
  }
  if rows[1].from >= rows[1].end {
    return (None, 0)
  }
  for i = 1; i < rows.length(); i = i + 1 {
    if is_front(text, rows[i]) {
      let lines : Array[String] = []
      for k = 1; k < i; k = k + 1 {
        lines.push(cut(text, rows[k].start, rows[k].end))
      }
      return (Some(joined(lines)), i + 1)
    }
  }
  (None, 0)
}

///|
/// 封筒の柵。ちょうど 3 本の `-` だけの行（`----` は柵ではない）。
fn is_front(text : String, r : Row) -> Bool {
  r.col == 0 && trim_end(text, r) - r.from == 3 && text[r.from].to_int() == 45
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/scan_wbtest.mbt`

Expected: `Total tests: 12, passed: 12, failed: 0.` EXIT=0

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 封筒を剥がす（直後が空行なら先頭トグル）"
```

---

## Task 10.5: 正規形の綴りを 1 か所に括る

**Files:**
- Create: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/spell.mbt`

**Interfaces:**
- Consumes: `Eol`（Task 1）
- Produces:
  - `pub(all) struct Spell`（15 フィールド）
  - `pub let spell : Spell` — 正規形の綴りの唯一の住所（G2・G3・G4 が読む）
  - `pub fn eol_text(eol : Eol) -> String`

**この Task だけテストを足さない。** 値の見張り（`spell` の逐語を固定する 2 本）は
**G3 Task 40** が持つ（契約 §19 G1）。ファイルとテストを割らないための取り決めなので、
G1 は `spell_wbtest.mbt` を作らない。よって赤→緑の往復は無く、Step は
「置く → 型検査 → 本数が動いていないことの確認 → コミット」の 4 つになる。

- [ ] **Step 1: 綴りの定数を置く**

`core/tree/spell.mbt`（契約 §12 の逐語。1 バイトも変えない）:

```moonbit
// 正規形の綴り。将来の lint 的な設定化に備えて 1 か所に括る（設定 UI は作らない）。

///|
pub(all) struct Spell {
  marker : String // リストのマーカー
  step : String // ネスト 1 段の字下げ
  hash : String // 見出しの刻み
  toggle : String // 側の変わり目（トグル専用）
  rule : String // 飾りの水平線（チャンネル分離）
  fence : String // コードの囲いの 1 文字
  fence_min : Int // 囲いの最短の長さ
  fold_open : String // 畳みの開き
  fold_close : String // 畳みの閉じ
  label_open : String // 畳みの中に書くラベルの飾りの開き
  label_close : String // 同じく閉じ
  front : String // 封筒の柵
  gap : Int // 継ぎ目の空行の本数
  lf : String
  crlf : String
}

///|
pub let spell : Spell = {
  marker: "-",
  step: "  ",
  hash: "#",
  toggle: "---",
  rule: "***",
  fence: "`",
  fence_min: 3,
  fold_open: "<details>",
  fold_close: "</details>",
  label_open: "<summary>",
  label_close: "</summary>",
  front: "---",
  gap: 1,
  lf: "\n",
  crlf: "\r\n",
}

///|
/// 改行の逐語。
pub fn eol_text(eol : Eol) -> String {
  match eol {
    Lf => spell.lf
    Crlf => spell.crlf
  }
}
```

読みの側の受け入れ（`scan` が読むが `serialize` は書かない綴り）は定数にしない —
`*` `+` のマーカー、順序リスト、4 スペース字下げ、setext、インデントコード、閉じ `#`、
`___` の水平線、`- - -`。これらは契約 §15 の方言表の側の話で、Task 5〜10 の走査が持つ。

- [ ] **Step 2: 型検査**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core check tree`

Expected: `Finished. moon: ran N tasks, now up to date (M warnings, 0 errors)` EXIT=0。
**合格条件は 0 errors**（契約 §11）。`spell` の読み手（G2 Task 22 / G3 Task 40）はまだ居ないので
警告が出うるが、可視性を下げたり読み捨てのコードを足したりして黙らせない。

- [ ] **Step 3: テストの本数が動いていないことを確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test -p mmm-app/core/tree`

Expected: `Total tests: 25, passed: 25, failed: 0.` EXIT=0

（この Task はテストファイルを持たないので、ここだけ `-p` で数える。
`Total tests: 0` が出たら `-p` の綴りを疑う — 契約 §17 の罠）

- [ ] **Step 4: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 正規形の綴りを 1 か所に括る"
```

---

## Task 11: 群の締め — 整形・全体の型検査・旧 core の無傷

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/scan.mbt`（`moon fmt` の結果のみ）
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/check.mbt` / `sig.mbt` / `doc.mbt` /
  `spell.mbt` / `make_wbtest.mbt` / `sig_wbtest.mbt` / `check_wbtest.mbt` / `scan_wbtest.mbt`（同上）
- Test: 既存の `core/*_test.mbt` と `core/*_wbtest.mbt`（旧 core。**1 行も変えない**）

**Interfaces:**
- Consumes: Task 1〜10.5 の全部
- Produces: G2・G3・G5 が建てられる土台
  - `pub fn scan(text : String) -> Scan`（G2 が食う）
  - `pub fn check(doc : Doc) -> Array[String]`（G2 の wbtest と G4 の境界が食う）
  - `pub fn sig(doc : Doc) -> String`（G4 の法則 1・2 が食う）
  - `pub let spell` / `pub fn eol_text`（G2・G3・G4 が食う）
  - 型 11 個と定数 2 つ（G2・G3・G5 の全部が食う）

- [ ] **Step 1: 整形の差分を出す**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt --check tree`

Expected: 差分があれば `git diff` の色付き出力 + `Error: failed when formatting project` EXIT≠0
（契約 §17 は 127。PowerShell 経由では -1 と出る）。
差分が無ければ `Finished. moon: ran N tasks, now up to date` EXIT=0

**`doc` 以外を対象にしないこと。** 既存の `js` を含めた瞬間に赤になる（契約 §17）。
`doc tree/js` は G4 の締めが持つ（この時点で `core/tree/js/` はまだ存在しない）。

- [ ] **Step 2: 整形を当てる**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt tree`

Expected: `Finished. moon: ran N tasks, now up to date` EXIT=0。ファイルがその場で書き換わる

- [ ] **Step 3: 整形が落ち着いたことを確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt --check tree`

Expected: `Finished. moon: ran N tasks, now up to date` EXIT=0

- [ ] **Step 4: 新パッケージのテストが緑のままであることを確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test -p mmm-app/core/tree`

Expected: `Total tests: 25, passed: 25, failed: 0.` EXIT=0
（内訳: make 1 / sig 4 / check 8 / scan 12。`Total tests: 0` なら `-p` の綴りを疑う）

- [ ] **Step 5: 旧 core が無傷であることを確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test -p mmm-app/core -p mmm-app/core/tree`

Expected: `Total tests: 217, passed: 217, failed: 0.` EXIT=0
（旧 core 192 + 新 25。**192 が減っていたら旧 core を壊している**）

- [ ] **Step 6: 全体の型検査**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core check`

Expected: `Finished. moon: ran N tasks, now up to date (N warnings, 0 errors)` EXIT=0。**合格条件は `0 errors`**（G1 単独の時点では `spell` / `eol_text` の読み手がまだ居ないので `unused` 系の警告が残る。読み手は G2 Task 22・G3 Task 40）
（`spell` の読み手がまだ居ないぶんの警告は許容。**合格条件は 0 errors**）

- [ ] **Step 7: JS が今までどおり建つことを確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core build --target js --release`

Expected: `Finished. moon: ran N tasks, now up to date` EXIT=0。
`core/_build/js/release/build/js/js.js` が今までどおり生成される
（新パッケージは library なので `core/tree/js/` は G4 が建てるまで生まれない）

- [ ] **Step 8: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "style: 🎨 新 core の整形を moon fmt に揃える"
```

- [ ] **Step 9: 読みの裁定 9 件が契約に載っていることを確認する**

契約 §15 の「読みの裁定 9 件」の表と、この群が固定したテストが 1 対 1 であることを目で確かめる
（この群の概要の表がその対応）。**申し送りは書かない** — 前版の 3 件（テストファイルの表・
方言表への掲載・G2 への引き継ぎ）は契約 §2・§4・§6・§9・§15・§16 に取り込み済み。

食い違いを見つけたら、**契約を直すのが先**（契約が後続 5 群の唯一の参照元）。
G4 の `READING` 表は G4 が書く — G1 は `test/` に 1 バイトも書かない。

---

## この群を終えたときに立っている旗

- `mmm-app/core/tree` が建ち、憲法 §2 の型が 1 バイトも違わずに置かれている
- **法則 1・2 の比較子（`sig`）が先に在る** — G3 が serialize を書いた瞬間、G4 がファズを回せる
- **`check` が先に在る** — G2 が parse を書くとき、「parse の出力は必ず check が空」を
  その場で確かめられる（契約 §19 の G2 の受け入れ条件）
- **`scan` が md の自由を全部受け止めている** — G2 は「行がどう綴られているか」を
  二度と考えなくてよく、意味の判断だけに集中できる
- **`spell` が先に在る** — G2 Task 22（`spell.hash`）と Task 25（`spell.fold_open` /
  `fold_close` / `label_open` / `label_close`）が待たずに走れる
- 道具の腕数（契約 §11 の殺す条件の観測点）に、G1 は 1 本も足していない
