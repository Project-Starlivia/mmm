# G2 — 読み（parse）

確定版の契約（`scratchpad/v2/contract2.md`）の §19「G2 — 読み」の実装計画。Task 20 から Task 26 まで 7 本。
**契約と本書が食い違ったら契約が正。**

## この群の概要

### 担当範囲

**触るファイルは 2 つだけ。**

- `core/tree/parse.mbt`（新規）— Token の列 → Doc
- `core/tree/parse_wbtest.mbt`（新規）— その見張り

他群のファイルは 1 バイトも触らない（契約 §2）。`doc.mbt` / `check.mbt` / `sig.mbt` / `scan.mbt` /
`spell.mbt` / `make_wbtest.mbt` は G1、`serialize.mbt` は G3、`tool.mbt` / `op.mbt` / `diff.mbt` / `docs/ops.md` は G5、
`json.mbt` / `project.mbt` / `laws_wbtest.mbt` / `js/` / `test/` / `package.json` / `ci.yml` は G4。
**スタブも、投機的な追加も、警告を消すための小細工も禁止。** 他群のファイルに直しが要ると分かったら、
書かずにその群へ差し戻す。

### 前提

1. **G1 が終わっていること。** `Doc` / `Root` / `Branch` / `Node` / `Skeleton` / `Form` / `Side` / `Eol` /
   `Block` / `Content` / `doc_id` / `first_id`（契約 §6）、`Token` / `Scan` / `scan`（契約 §10）、
   `check`（契約 §7）、`sig`（契約 §8）が揃っていること。
   **テストは `sig` と `check` を比較子に使う**ので、この 2 つが無いと 1 本も書けない。
2. **G1 Task 10.5 が済んでいること。** `core/tree/spell.mbt`（契約 §12）は **G1 の所有**で、G2 は読むだけ。
   parse は `spell.hash`（Task 22）と `spell.fold_open` / `spell.fold_close` / `spell.label_open` /
   `spell.label_close`（Task 25）を読む — 綴り定数をコード上 1 か所に括る憲法 §4 の規律に、読み側も従うため。

### G1 と共有する前提（Token の意味）

契約 §6「走査の前提」の 3 つ。**G1 の `scan_wbtest.mbt` と G2 の `parse_wbtest.mbt` の両方がこれを固定する。**

| # | 前提 | 例 |
|---|---|---|
| 1 | `col` = **行頭の空白を除いた最初の非空白の列**（トークン自身の書き出し位置）。タブは 4 で数える | `  - a` の Bullet は `col = 2`、`## a` の Head は `col = 0` |
| 2 | `Bullet.hang` = **ラベルの始まる列**（マーカーと後ろの空白を食べた後）。子の字下げと領土の境目はこれ | `  - a` は `hang = 4`、`- a` は `hang = 2`、`10. a` は `hang = 4` |
| 3 | `Fence.text` と `Verse.text` の**改行は LF、行頭の字下げは剥がしてある**。Verse は物理行 1 本で 1 枚（綴じるのは parse の仕事） | CRLF の文書でも `Fence.text` は `"a\nb"` |

前提 3 の理由: モデルの中の改行は常に LF で、`Eol` は Doc が持つ綴りのダイヤル（serialize が履かせる）。
ここが揃っていないと CRLF 文書で法則 1 が破れる。

### 着手順

Task 20 → 26 の一直線。各タスクは前のタスクの上に足す（前のテストは全部残る）。

### 新しく置く名前（契約 §4 の G2 の行と一致）

| 名前 | 種 | 役 | 入る Task |
|---|---|---|---|
| `Frame` | priv struct | 組み立て中の 1 段。木そのものを兼ねる | 20 |
| `Build` | priv struct | 読みの途中経過（開いている段の道と、行き先の決まらないもの） | 20 |
| `Pend` | priv struct | 隙間に溜めた区切り | 24 |
| `parse` | pub fn | 契約 §10 の入口 | 20 |
| `read` | fn | parse の本体（Token の列だけを食う） | 20 |
| `top` / `item` | fn | 開いている一番深い段 / その段は項目か | 20 |
| `bud` | fn | 段を 1 つ生やす（id はここで配る） | 20 |
| `to_root` / `to_node` / `bone` | fn | Frame の木 → Doc の木 | 20 |
| `grow` | fn | 足りない段を Implicit で埋めてから積む | 21 |
| `hashes` | fn | 領土に落ちた見出しの逐語（`(level : Int, label : String) -> String`） | 22 |
| `shed` / `knit` / `card` / `pair` | fn | 領土から出る / 散文を綴じる / 正体を見る / `[…](…)` を割る | 23 |
| `spill` / `spill_at` | fn | 溜めた区切りを飾りとして落とす / トグルとして配る | 24 |
| `is_summary` | fn | `<summary>…</summary>` の行か（契約 §9） | 25 |
| `parse_sig` / `parse_ids` / `parse_walk` | fn (test) | 指紋 / 文書順の id / その走査 | 20 |
| `parse_faults` | fn (test) | 破れを 1 本に綴じる | 26 |

wbtest のヘルパ名は全部 `parse_` で始める（契約 §16 — 同一パッケージの `*_wbtest.mbt` は名前空間を共有し、
同名は `Error: [4051]`）。

**`hashes` は G2 の所有。** 同名の `hashes(line, at) -> Int` を G4 が置く案は契約 §4 で削除された
（7 個以上の `#` の読みは G1 の `head_at` が既に持つ）。

### 設計の要点（なぜこの形か）

- **木は `Frame` で建て、最後に 1 回だけ Doc の型へ写す。** `Root` / `Branch` / `Node` は不変 struct なので、
  育ちながら建てるには可変の足場が要る。struct は参照（契約 §6）なので、`bud` が親の `kids` に挿してから
  中身を足せる — 木を組み直す処理は 1 つも要らない。
- **`stack` の添字 = 深さ。** 底に「文書の器」（level 0・`form: None`）を置いたので、道は常に空でなく、
  `b.stack[1]` が root、`b.stack[2]` が root 直下のスロットになる（憲法 §2「level 0 の文書に錨を打ったので
  木ごとの原点ずれが無い」がそのまま座標系になっている）。
- **順序法則（項目が先・見出しが後）と、Implicit の位置（前の兄弟はすべて項目）を強制するコードは 1 行も無い。**
  閉じる規則（見出しは開いている項目を閉じてから積む・リストは開いている段の子になる）の帰結として、
  破れる並びが**そもそも作れない**。見張りは Task 26 の `check` の網に任せる。
- **`shed` は root の項目を閉じない。** 領土の外へ出た散文は項目を閉じて親へ置くのが md の読みだが、
  root の項目を閉じると行き場が文書になり、`Doc.body`（＝最初の骨格より**前**の散文）へ後ろの散文が混ざって
  順序が壊れる。そこで **root の項目だけは閉じず、その body に置く**。serialize は領土の中に字下げして書き、
  読み直せば同じ木になる（法則 1・2 は保たれる）。
- **区切り（`---`）の行き先は、次の骨格を見るまで決まらない。** 「隙間 = 空白と区切りしか無い末尾区間」
  （憲法 §4 の先頭トグルの規則の一般形）を実装に落とすと、Bar は**溜める**しかない。溜めるときに
  「そのとき開いていた段」を一緒に持つ（`Pend.owner`）ので、後から飾りに落ちても書かれた場所へ正しく戻る。
- **トグルの資格は 2 つだけ**: `dash`（`***` は飾り確定）と `col <= root.hang`（root の中身の列より深い `---`
  は子の飾り — C15 備考）。この 2 つを満たし、かつ**深さ 2 の新顔が生まれた**ときだけ側になる。
  占有者が Implicit でも成立する（C16）。
- **`<summary>` は「`<details>` の直後の 1 行」だけを無条件に読み飛ばす**（契約 §9・裁定 1）。
  serialize は畳んだノードに `<summary>label</summary>` を毎回書くので、body に積むと 2 回目の serialize で
  1 枚増え、法則 1 も法則 2 も破れる。**内容が label と一致するかは見ない** — 一致判定にすると手書きの別内容が
  Opaque として残り、serialize が label 版と合わせて 2 枚書いて増殖する。**位置は「直後」に限る** —
  位置を問わないと、body の途中に手で置かれた `<summary>` まで消え、意味の損失が広がる。
  判定に要る状態は `Build` の 1 ビット（`mut fresh`）だけ。

### 実測の裏付け

この計画のコードは、契約 §17 の使い捨てモジュールを写した `scratchpad/v2/g2/` と、
裁定 1（`<summary>` の読み飛ばし）を載せた `scratchpad/v2/g2s/` で**全段階を実際にコンパイル・実行**した
（`lock` モジュールの `core/tree` に parse.mbt と parse_wbtest.mbt を置いたもの）。各 Task の終わりの
テスト本数は実測値:

```
Task 20: 3   Task 21: 6   Task 22: 9   Task 23: 12
Task 24: 17  Task 25: 20  Task 26: 23
```

裁定 1 を載せた終わりの姿（g2s）の実測:

```
$ moon -C <g2s>/core test tree/parse_wbtest.mbt
Total tests: 23, passed: 23, failed: 0.        EXIT=0

$ moon -C <g2s>/core check tree
Finished. moon: ran 3 tasks, now up to date (1 warnings, 0 errors)   EXIT=0
（警告は他群の `Unused function 'amend'` 1 本だけ。parse.mbt 由来の警告は 0）

$ moon -C <g2s>/core fmt --check tree
Finished. moon: ran 15 tasks, now up to date   EXIT=0
```

Task 25 の赤（Open / Close の腕がまだ `_ => ()` の状態）も実測した:

```
Total tests: 20, passed: 17, failed: 3.        EXIT=2
```

行数の実測: `parse.mbt` 356 行 / `parse_wbtest.mbt` 321 行。

### スコープ外

serialize（G3）/ 投影（G4）/ 操作（G5）/ id の写し（打鍵の道）/ すげ替え v1 /
setext・`<!---`・`#######` の認定（**G1 の scan の仕事**。parse は Token を信じる）。

### コマンドの形（契約 §17）

Step 2 / 4 は**ファイル 1 本を指定**する形を使う（他群と並行していても本数が動かない）:

```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/parse_wbtest.mbt
```

ファイル指定は綴りを間違えると `Error: Failed to canonicalize input filter directory` で **EXIT=127** になり、
黙って緑にはならない（`Total tests: 0` で緑になるのは `-p` の綴り間違いだけ。契約 §17 の罠）。
群の締め（Task 26 Step 3）だけ `-p mmm-app/core -p mmm-app/core/tree` を使い、
そこでは `Total tests:` が 0 でないことを目で見る。

**Run 行は全部絶対パス。** 実行エージェントの cwd はツール呼び出しごとに戻るので、隣の `D:/1.atrium/mmm`
から叩くと旧 core を測ってしまう。

---

## Task 20: 読みの器と骨格の積み上げ

**Files:**
- Create: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/parse.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/parse_wbtest.mbt`

**Interfaces:**
- Consumes: `pub fn scan(text : String) -> Scan`（G1）/ `pub(all) enum Token`（G1）/ `pub(all) struct Scan { frontmatter : String?; eol : Eol; tokens : Array[Token] }`（G1）/ `pub(all) struct Doc / Root / Branch / Node`・`pub(all) enum Skeleton / Form / Side / Block`・`pub let doc_id : Int`・`pub let first_id : Int`（G1）/ `pub fn sig(doc : Doc) -> String`（G1）
- Produces: `pub fn parse(text : String) -> Doc` / `fn read(scanned : Scan) -> Doc` / `fn top(b : Build) -> Frame` / `fn item(f : Frame) -> Bool` / `fn bud(b : Build, level : Int, form : Form?, label : String, hang : Int) -> Unit` / `fn to_root(f : Frame) -> Root` / `fn to_node(f : Frame) -> Node` / `fn bone(f : Frame) -> Skeleton` / `priv struct Frame` / `priv struct Build` / (test) `fn parse_sig(md : String) -> String` / `fn parse_ids(md : String) -> String` / `fn parse_walk(node : Node, out : Array[String]) -> Unit`

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/parse_wbtest.mbt` を新規に作る（全文）:

```moonbit
// 読みの見張り。骨格・飛び・単調性・中身・側・畳み・summary の 7 つを md で固定する。
// ヘルパ名は `parse_` で始める（wbtest は名前空間を共有する）。

///|
/// 木の指紋。id を含まないので、期待は形だけを書けばよい。
fn parse_sig(md : String) -> String {
  sig(parse(md))
}

///|
/// 文書順に並べた id。飛びの Implicit も本物のノードとして番号を持つ。
fn parse_ids(md : String) -> String {
  let out : Array[String] = []
  for r in parse(md).roots {
    out.push(r.id.to_string())
    for b in r.branches {
      parse_walk(b.node, out)
    }
  }
  let sb = StringBuilder::new()
  for i, s in out {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string(s)
  }
  sb.to_string()
}

///|
fn parse_walk(node : Node, out : Array[String]) -> Unit {
  out.push(node.id.to_string())
  for c in node.children {
    parse_walk(c, out)
  }
}

// --- 骨格の積み上げ（Task 20） ----------------------------------------------

///|
test "見出しは level のとおりの深さに積まれる" {
  assert_eq(parse_sig("# r\n\n## a\n"), "D-n()[Reh_1:r()[>Neh_1:a()[]]]")
  assert_eq(
    parse_sig("# r\n\n## a\n\n## b\n"),
    "D-n()[Reh_1:r()[>Neh_1:a()[]>Neh_1:b()[]]]",
  )
  assert_eq(
    parse_sig("# r\n\n## a\n\n### x\n"),
    "D-n()[Reh_1:r()[>Neh_1:a()[Neh_1:x()[]]]]",
  )
}

///|
test "リストは置かれた場所から埋まる（相対記法）" {
  assert_eq(parse_sig("# r\n\n- b\n"), "D-n()[Reh_1:r()[>Nel_1:b()[]]]")
  assert_eq(
    parse_sig("# r\n\n- b\n  - c\n"),
    "D-n()[Reh_1:r()[>Nel_1:b()[Nel_1:c()[]]]]",
  )
  assert_eq(parse_sig("- a\n\n- b\n"), "D-n()[Rel_1:a()[]Rel_1:b()[]]")
}

///|
test "id は first_id から文書順に配られる" {
  assert_eq(parse_ids("# r\n\n## a\n\n### x\n\n## b\n"), "2,3,4,5")
}
```

備考: 期待値の綴りは契約 §8 の指紋。`Reh_1:r()[…]` = root・Explicit・Heading・畳んでいない・ラベル `r`・body 空。
憲法 §2「深さ = level で全域一致」と「top-level の Item は level 1 の root」（C15）の読み side を固定する。

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/parse_wbtest.mbt`
Expected: `parse` がまだ無いのでビルドが止まる。EXIT=1。

```
Error: [4021]
   ╭─[ ...\core\doc\parse_wbtest.mbt:7:7 ]
   │
 7 │   sig(parse(md))
   │       ──┬──
   │         ╰──── The value identifier parse is unbound.
───╯
```

- [ ] **Step 3: 最小の実装を書く**

`core/tree/parse.mbt` を新規に作る（全文）:

```moonbit
// Token の列 → Doc。骨格を積み、飛びから Implicit を導き、隙間の区切りを側に変える。
// md の自由はここで受け止める（どう書いても読める）。書かれたとおりに読み、直さない。

///|
/// 組み立て中の 1 段。struct は参照なので、親の kids に挿してから中身を足せる。
priv struct Frame {
  id : Int
  level : Int // 深さ。0 = 文書
  form : Form? // None = Implicit（文書の器も None）
  label : String
  hang : Int // 項目の中身の列。見出しと文書は 0
  body : Array[Block]
  kids : Array[Frame]
}

///|
/// 読みの途中経過。開いている段の道（stack）と、次に配る id。
priv struct Build {
  stack : Array[Frame]
  mut next : Int
}

///|
pub fn parse(text : String) -> Doc {
  read(scan(text))
}

///|
/// parse の本体。テストは Token を直に食わせる。
fn read(scanned : Scan) -> Doc {
  let doc : Frame = {
    id: doc_id,
    level: 0,
    form: None,
    label: "",
    hang: 0,
    body: [],
    kids: [],
  }
  let b : Build = { stack: [doc], next: first_id }
  for token in scanned.tokens {
    match token {
      Head(level~, label~, ..) => {
        while top(b).level >= level {
          ignore(b.stack.unsafe_pop())
        }
        bud(b, level, Some(Heading), label, 0)
      }
      Bullet(col~, hang~, label~) => {
        // リストは相対記法。開いている項目の中身の列で親を決める
        while item(top(b)) && col < top(b).hang {
          ignore(b.stack.unsafe_pop())
        }
        bud(b, top(b).level + 1, Some(Item), label, hang)
      }
      _ => ()
    }
  }
  {
    frontmatter: scanned.frontmatter,
    eol: scanned.eol,
    body: doc.body,
    roots: doc.kids.map(to_root),
  }
}

///|
/// 開いている一番深い段。文書の器が底にあるので、空にはならない。
fn top(b : Build) -> Frame {
  b.stack[b.stack.length() - 1]
}

///|
fn item(f : Frame) -> Bool {
  match f.form {
    Some(Item) => true
    _ => false
  }
}

///|
/// 段を 1 つ生やし、親の子に挿してから道に積む。id は文書順に配る。
fn bud(
  b : Build,
  level : Int,
  form : Form?,
  label : String,
  hang : Int,
) -> Unit {
  let f : Frame = { id: b.next, level, form, label, hang, body: [], kids: [] }
  b.next = b.next + 1
  top(b).kids.push(f)
  b.stack.push(f)
}

///|
fn to_root(f : Frame) -> Root {
  let branches : Array[Branch] = []
  for k in f.kids {
    branches.push({ side: Right, node: to_node(k) })
  }
  { id: f.id, skeleton: bone(f), branches }
}

///|
fn to_node(f : Frame) -> Node {
  { id: f.id, skeleton: bone(f), children: f.kids.map(to_node) }
}

///|
fn bone(f : Frame) -> Skeleton {
  match f.form {
    None => Implicit
    Some(form) => Explicit(form~, label=f.label, folded=false, body=f.body)
  }
}
```

注意 2 つ（実測）:
- **`mut` はまだ 1 つも書かない。** 定義パッケージ内で一度も書かない `mut` フィールドは
  `Error: [0015] unused_mut` で**ビルドが止まる**。`folded` と `folds` と `fresh` は Task 25、
  `toggles` は Task 24 で、書く側と一緒に足す。
- `Head(level~, label~, ..)` の `..` は「残りのラベルは見ない」。`col` は Task 22 で使い始める。

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/parse_wbtest.mbt`
Expected: `Total tests: 3, passed: 3, failed: 0.` EXIT=0

- [ ] **Step 5: コミット**

```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/parse.mbt core/tree/parse_wbtest.mbt
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 読みの器と骨格の積み上げを置く"
```

（Issue 番号が決まっていれば `feat: ✨ #NN 読みの器と…` と差し込む。以下同じ。）

---

## Task 21: 飛びは Implicit が埋める

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/parse.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/parse_wbtest.mbt`

**Interfaces:**
- Consumes: Task 20 の `bud` / `top` / `read`
- Produces: `fn grow(b : Build, level : Int, form : Form?, label : String, hang : Int) -> Unit`

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/parse_wbtest.mbt` の末尾に足す:

```moonbit
// --- 飛びは Implicit（Task 21・憲法 §2・C6） --------------------------------

///|
test "level の飛びは Implicit が埋める" {
  assert_eq(
    parse_sig("# r\n\n## a\n\n#### b\n"),
    "D-n()[Reh_1:r()[>Neh_1:a()[Ni[Neh_1:b()[]]]]]",
  )
  assert_eq(
    parse_sig("# r\n\n#### b\n"),
    "D-n()[Reh_1:r()[>Ni[Ni[Neh_1:b()[]]]]]",
  )
}

///|
test "最初の見出しが level 2 以上なら implied の root が生える" {
  assert_eq(parse_sig("## a\n"), "D-n()[Ri[>Neh_1:a()[]]]")
  assert_eq(parse_sig("## a\n\n# r\n"), "D-n()[Ri[>Neh_1:a()[]]Reh_1:r()[]]")
}

///|
test "Implicit も文書順に id を持つ" {
  assert_eq(parse_ids("# r\n\n#### b\n"), "2,3,4,5")
}
```

備考: C6（`#### b` の飛びから implied が導出され、md には何も書かれない）と、憲法 §2「最初の `#` より前に
level 2+ があれば level 0 との段差から implied(1) が導出される（特例ではなく帰結）」。

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/parse_wbtest.mbt`
Expected: 飛びが埋まらないので指紋が合わない。`Total tests: 6, passed: 3, failed: 3.` EXIT=2

```
[mmm-app/core] test tree/parse_wbtest.mbt:… ("level の飛びは Implicit が埋める") failed: doc/parse_wbtest.mbt:…@mmm-app/core FAILED: `"D-n()[Reh_1:r()[>Neh_1:a()[Neh_1:b()[]]]]" != "D-n()[Reh_1:r()[>Neh_1:a()[Ni[Neh_1:b()[]]]]]"`
```

- [ ] **Step 3: 最小の実装を書く**

`parse.mbt` の 3 箇所を直す。

(1) `read` の Head の腕: `bud(b, level, Some(Heading), label, 0)` を `grow(b, level, Some(Heading), label, 0)` に。

(2) `read` の Bullet の腕: `bud(b, top(b).level + 1, Some(Item), label, hang)` を
`grow(b, top(b).level + 1, Some(Item), label, hang)` に。

(3) `fn bud` の直前に `grow` を足す:

```moonbit
///|
/// 足りない段を Implicit で埋めてから、書かれた段を積む。
/// リストは相対記法なので飛びを作らない（呼ぶ側が親 + 1 を渡す）。
fn grow(
  b : Build,
  level : Int,
  form : Form?,
  label : String,
  hang : Int,
) -> Unit {
  let start = top(b).level + 1
  for l in start..<level {
    bud(b, l, None, "", 0)
  }
  bud(b, level, form, label, hang)
}
```

注意（実測）: `let start` を挟むこと。`for l in top(b).level + 1..<level` と直に書くと `+` が範囲より弱く結び、
`Error: [4015] Type Int has no method iter.` と
`Error: [4137] Range operators are currently only supported in 'for .. in' loops.` の 2 本で落ちる。

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/parse_wbtest.mbt`
Expected: `Total tests: 6, passed: 6, failed: 0.` EXIT=0

- [ ] **Step 5: コミット**

```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/parse.mbt core/tree/parse_wbtest.mbt
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ level の飛びから Implicit を導く"
```

---

## Task 22: 単調性 — 項目を閉じてから見出しを積む

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/parse.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/parse_wbtest.mbt`

**Interfaces:**
- Consumes: Task 21 の `grow` / `item` / `top`、G1 の `spell.hash`（`core/tree/spell.mbt`・契約 §12）
- Produces: `fn hashes(level : Int, label : String) -> String`

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/parse_wbtest.mbt` の末尾に足す:

```moonbit
// --- 単調性（Task 22・憲法 §2・C17） ----------------------------------------

///|
test "項目の後ろの見出しは項目の子にならない" {
  assert_eq(parse_sig("- a\n\n## h\n"), "D-n()[Rel_1:a()[]Ri[>Neh_1:h()[]]]")
  assert_eq(
    parse_sig("- a\n  - b\n## h\n"),
    "D-n()[Rel_1:a()[>Nel_1:b()[]]Ri[>Neh_1:h()[]]]",
  )
}

///|
test "項目の領土の中の見出しは Opaque" {
  assert_eq(parse_sig("- a\n\n  ## h\n"), "D-n()[Rel_1:a(o4:## h)[]]")
  assert_eq(
    parse_sig("- a\n  - b\n\n  ### h\n"),
    "D-n()[Rel_1:a(o5:### h)[>Nel_1:b()[]]]",
  )
  assert_eq(parse_sig("- a\n\n  ##\n"), "D-n()[Rel_1:a(o2:##)[]]")
}

///|
test "見出しの節の中のリストは節の子になる" {
  assert_eq(
    parse_sig("# r\n\n- x\n\n### y\n"),
    "D-n()[Reh_1:r()[>Nel_1:x()[]>Ni[Neh_1:y()[]]]]",
  )
}
```

備考: 1 本目が C17（木が 2 本になる。implied がそこに置けるのは直前の兄弟 a が Item だから）。
2 本目が憲法 §2「項目の領土（content indent）内の見出しは Opaque」— 逐語は `## h`（字下げは持たない。
serialize が履かせる）。3 本目は `### y` が x の領土の外（col 0 < hang 2）なので x を閉じ、r の 2 本目の
スロットとして飛びごと積まれること。

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/parse_wbtest.mbt`
Expected: 領土の判定がまだ無いので、見出しが項目の子になる／Opaque にならない。
`Total tests: 9, passed: 6, failed: 3.` EXIT=2

```
[mmm-app/core] test tree/parse_wbtest.mbt:… ("項目の後ろの見出しは項目の子にならない") failed: … FAILED: `"D-n()[Rel_1:a()[Neh_1:h()[]]]" != "D-n()[Rel_1:a()[]Ri[>Neh_1:h()[]]]"`
```

（Step 1 で足すのはテストだけなので、この時点で `hashes` を参照するコードはまだ無い。
`Error: [4021]` ではなく指紋の食い違いで落ちる。）

- [ ] **Step 3: 最小の実装を書く**

`parse.mbt` の 2 箇所を直す。

(1) `read` の Head の腕を、まるごと次に置き換える:

```moonbit
      Head(col~, level~, label~) => {
        // 単調性 — 見出しを積む前に、領土の外に出た項目を閉じる
        while item(top(b)) && col < top(b).hang {
          ignore(b.stack.unsafe_pop())
        }
        if item(top(b)) {
          // 項目の領土の中。絶対記法が嘘になるので逐語で body へ落とす
          top(b).body.push(Opaque(hashes(level, label)))
        } else {
          while top(b).level >= level {
            ignore(b.stack.unsafe_pop())
          }
          grow(b, level, Some(Heading), label, 0)
        }
      }
```

(2) `fn to_root` の直前に `hashes` を足す:

```moonbit
///|
/// 項目の領土に落ちた見出しの逐語。字下げは serialize が履かせるので持たない。
fn hashes(level : Int, label : String) -> String {
  let sb = StringBuilder::new()
  for _ in 0..<level {
    sb.write_string(spell.hash)
  }
  if label != "" {
    sb.write_string(" ")
    sb.write_string(label)
  }
  sb.to_string()
}
```

なぜ 2 段構えか: 先に「領土の外の項目」を閉じると、残る項目は必ず `hang <= col`（＝この見出しを飲み込む領土）
になる。だから 2 つ目の `if item(top(b))` が「領土の中か」の判定そのものになり、
**そこを抜けたときスタックに項目は 1 つも残っていない**（見出しが項目の子になる道が構造ごと無い＝単調性）。

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/parse_wbtest.mbt`
Expected: `Total tests: 9, passed: 9, failed: 0.` EXIT=0

- [ ] **Step 5: コミット**

```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/parse.mbt core/tree/parse_wbtest.mbt
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 項目の領土と単調性を読みで守る"
```

---

## Task 23: 中身の認定 — 散文を綴じて正体を見る

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/parse.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/parse_wbtest.mbt`

**Interfaces:**
- Consumes: Task 22 までの `read` / `top` / `item`、G1 の `Block` / `Content`
- Produces: `fn shed(b : Build, col : Int) -> Unit` / `fn knit(b : Build) -> Unit` / `fn card(text : String) -> Block` / `fn pair(text : String, start : Int) -> (String, String)?` / `Build.verse : Array[String]`

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/parse_wbtest.mbt` の末尾に足す:

```moonbit
// --- 中身の認定（Task 23・憲法 §2「疑わしきは Opaque」） ---------------------

///|
test "絵になるのは 4 つだけで、疑わしきは Opaque" {
  assert_eq(
    parse_sig("# r\n\n![alt](./img/a.png)\n"),
    "D-n()[Reh_1:r(ci3:alt11:./img/a.png)[]]",
  )
  assert_eq(
    parse_sig("# r\n\n[t](https://e.com)\n"),
    "D-n()[Reh_1:r(cl1:t13:https://e.com)[]]",
  )
  assert_eq(parse_sig("# r\n\n```js\n1\n```\n"), "D-n()[Reh_1:r(cc2:js1:1)[]]")
  assert_eq(
    parse_sig("# r\n\n<svg>\n<rect/>\n</svg>\n"),
    "D-n()[Reh_1:r(cs20:<svg>\n<rect/>\n</svg>)[]]",
  )
  assert_eq(parse_sig("# r\n\n***\n"), "D-n()[Reh_1:r(r)[]]")
  assert_eq(
    parse_sig("# r\n\n> quote\nmore\n"),
    "D-n()[Reh_1:r(o12:> quote\nmore)[]]",
  )
  assert_eq(
    parse_sig("# r\n\n[a](b) [c](d)\n"),
    "D-n()[Reh_1:r(o13:[a](b) [c](d))[]]",
  )
}

///|
test "最初の骨格より前の散文は文書の body" {
  assert_eq(parse_sig("intro\n\n# r\n"), "D-n(o5:intro)[Reh_1:r()[]]")
  assert_eq(parse_sig("intro\n"), "D-n(o5:intro)[]")
}

///|
test "領土の外へ出た中身は項目を閉じてから置く" {
  assert_eq(
    parse_sig("# r\n\n- x\n\ntext\n"),
    "D-n()[Reh_1:r(o4:text)[>Nel_1:x()[]]]",
  )
  assert_eq(
    parse_sig("# r\n\n- x\n\n  text\n"),
    "D-n()[Reh_1:r()[>Nel_1:x(o4:text)[]]]",
  )
}
```

備考: 憲法 §2「Block = Content(Image | Code | Svg | Link) | Rule | Opaque」と「Opaque の中身は逐語 —
例外は単独の水平線だけ」。`[a](b) [c](d)` が Opaque なのは、割り方が一意に決まらないものを Content に
しないため（疑わしきは Opaque）。`> quote\nmore` は続く行が 1 枚に綴じられること（改行は LF）。

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/parse_wbtest.mbt`
Expected: 散文が 1 枚も拾われていないので指紋が合わない。`Total tests: 12, passed: 9, failed: 3.` EXIT=2

```
[mmm-app/core] test tree/parse_wbtest.mbt:… ("絵になるのは 4 つだけで、疑わしきは Opaque") failed: … FAILED: `"D-n()[Reh_1:r()[]]" != "D-n()[Reh_1:r(ci3:alt11:./img/a.png)[]]"`
```

- [ ] **Step 3: 最小の実装を書く**

`parse.mbt` の 5 箇所を直す。

(1) `Build` に散文の溜め場を足す:

```moonbit
///|
/// 読みの途中経過。開いている段の道（stack）と、まだ行き先の決まらないもの。
priv struct Build {
  stack : Array[Frame]
  verse : Array[String]
  mut next : Int
}
```

(2) `read` の `let b : Build = …` を `let b : Build = { stack: [doc], verse: [], next: first_id }` に。

(3) `read` の `match token {` の直後（Head の腕の**前**）に 4 本の腕を足し、Head と Bullet の腕の頭に
`knit(b)` を 1 行ずつ足す:

```moonbit
      Blank => knit(b)
      Verse(col~, text~) => {
        if b.verse.is_empty() {
          shed(b, col)
        }
        b.verse.push(text)
      }
      Fence(col~, info~, text~) => {
        knit(b)
        shed(b, col)
        top(b).body.push(Content(Code(info~, text~)))
      }
      Bar(col~, ..) => {
        knit(b)
        shed(b, col)
        top(b).body.push(Rule)
      }
      Head(col~, level~, label~) => {
        knit(b)
        // 単調性 — 見出しを積む前に、領土の外に出た項目を閉じる
        while item(top(b)) && col < top(b).hang {
          ignore(b.stack.unsafe_pop())
        }
        if item(top(b)) {
          // 項目の領土の中。絶対記法が嘘になるので逐語で body へ落とす
          top(b).body.push(Opaque(hashes(level, label)))
        } else {
          while top(b).level >= level {
            ignore(b.stack.unsafe_pop())
          }
          grow(b, level, Some(Heading), label, 0)
        }
      }
      Bullet(col~, hang~, label~) => {
        knit(b)
        // リストは相対記法。開いている項目の中身の列で親を決める
        while item(top(b)) && col < top(b).hang {
          ignore(b.stack.unsafe_pop())
        }
        grow(b, top(b).level + 1, Some(Item), label, hang)
      }
      _ => ()
```

（`_ => ()` は残す。Open と Close は Task 25 で置き換える。）

(4) `read` の `for` を抜けた直後、返り値の直前に `knit(b)` を 1 行:

```moonbit
  knit(b)
  {
    frontmatter: scanned.frontmatter,
    eol: scanned.eol,
    body: doc.body,
    roots: doc.kids.map(to_root),
  }
}
```

(5) `fn hashes` の直前に 4 本足す:

```moonbit
///|
/// 領土の外へ出た中身は、項目を閉じてから置く。
/// root の項目だけは閉じない（文書には散文の席が無い）。
fn shed(b : Build, col : Int) -> Unit {
  while item(top(b)) && top(b).level > 1 && col < top(b).hang {
    ignore(b.stack.unsafe_pop())
  }
}

///|
/// 溜めた散文の行を 1 枚に綴じる。中身が何であるかの判定はここ 1 か所。
fn knit(b : Build) -> Unit {
  if b.verse.is_empty() {
    return
  }
  let sb = StringBuilder::new()
  for i, line in b.verse {
    if i > 0 {
      // 中身の改行は常に LF。eol は Doc の綴りダイヤルで、書くときに履かせる
      sb.write_string("\n")
    }
    sb.write_string(line)
  }
  b.verse.clear()
  top(b).body.push(card(sb.to_string()))
}

///|
/// 散文 1 枚の正体。絵になるのは 4 つだけで、疑わしきは Opaque。
fn card(text : String) -> Block {
  if text.has_prefix("<svg") && text.has_suffix("</svg>") {
    return Content(Svg(text))
  }
  if !text.contains("\n") && text.has_suffix(")") {
    if text.has_prefix("![") {
      if pair(text, 2) is Some((alt, src)) {
        return Content(Image(alt~, src~))
      }
    } else if text.has_prefix("[") {
      if pair(text, 1) is Some((text2, href)) {
        return Content(Link(text=text2, href~))
      }
    }
  }
  Opaque(text)
}

///|
/// `[…](…)` をちょうど 1 つだけ含むか。区切りが中に混じれば諦める。
fn pair(text : String, start : Int) -> (String, String)? {
  guard text.find("](") is Some(i) else { return None }
  guard i >= start else { return None }
  let left = text[start:i].to_owned()
  let right = text[i + 2:text.length() - 1].to_owned()
  if left.contains("[") ||
    left.contains("]") ||
    right.contains("(") ||
    right.contains(")") {
    return None
  }
  Some((left, right))
}
```

注意（実測）: `text[a:b]` は端が下位サロゲートだと panic する（契約 §18）。ここで切る位置は
`find("](")` が返した ASCII の境目と末尾の `)` の手前だけなので、コードポイントの途中には落ちない。

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/parse_wbtest.mbt`
Expected: `Total tests: 12, passed: 12, failed: 0.` EXIT=0

- [ ] **Step 5: コミット**

```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/parse.mbt core/tree/parse_wbtest.mbt
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 散文を綴じて中身の正体を見分ける"
```

---

## Task 24: 側の割り当て — 隙間の区切りはトグル

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/parse.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/parse_wbtest.mbt`

**Interfaces:**
- Consumes: Task 23 までの `read` / `grow` / `top`、G1 の `Side`
- Produces: `priv struct Pend` / `fn spill(b : Build) -> Unit` / `fn spill_at(b : Build, root : Frame, slot : Frame?) -> Unit` / `Frame.toggles : Int`（mut）/ `Build.pend : Array[Pend]`

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/parse_wbtest.mbt` の末尾に足す:

```moonbit
// --- 側の割り当て（Task 24・憲法 §2・C4 / C15 / C16） -----------------------

///|
test "隙間の `---` は次のスロットの側を裏返す" {
  assert_eq(
    parse_sig("# r\n\n## a\n\n---\n\n## b\n"),
    "D-n()[Reh_1:r()[>Neh_1:a()[]<Neh_1:b()[]]]",
  )
  assert_eq(
    parse_sig("# r\n\n---\n\n## a\n\n---\n\n## b\n"),
    "D-n()[Reh_1:r()[<Neh_1:a()[]>Neh_1:b()[]]]",
  )
  assert_eq(
    parse_sig("# r\n\n---\n\n---\n\n## a\n"),
    "D-n()[Reh_1:r()[>Neh_1:a()[]]]",
  )
}

///|
test "トグルは隙間に付き、スロットの占有者を問わない" {
  assert_eq(
    parse_sig("# r\n\n---\n\n#### b\n"),
    "D-n()[Reh_1:r()[<Ni[Ni[Neh_1:b()[]]]]]",
  )
}

///|
test "項目 root のトグルは root の中身の列に置く" {
  assert_eq(
    parse_sig("- center\n\n  - a\n\n  - b\n\n  ---\n\n  - c\n"),
    "D-n()[Rel_6:center()[>Nel_1:a()[]>Nel_1:b()[]<Nel_1:c()[]]]",
  )
  assert_eq(
    parse_sig("- center\n\n  - a\n\n    ---\n\n  - b\n"),
    "D-n()[Rel_6:center()[>Nel_1:a(r)[]>Nel_1:b()[]]]",
  )
}

///|
test "後ろに中身が続く `---` は隙間ではなく飾り" {
  assert_eq(
    parse_sig("# r\n\n## a\n\ntext\n\n---\n\nmore\n\n## b\n"),
    "D-n()[Reh_1:r()[>Neh_1:a(o4:textro4:more)[]>Neh_1:b()[]]]",
  )
  assert_eq(
    parse_sig("# r\n\n## a\n\n---\n\n### x\n"),
    "D-n()[Reh_1:r()[>Neh_1:a(r)[Neh_1:x()[]]]]",
  )
}

///|
test "木と木の間の区切りは側にならない" {
  assert_eq(parse_sig("# r\n\n---\n\n# s\n"), "D-n()[Reh_1:r(r)[]Reh_1:s()[]]")
}
```

備考: 1 本目が C4 の読み戻し（先頭トグル = 左開始。2 本連続は元へ戻る）。2 本目が C16（占有者が Implicit でも
隙間は実在する）。3 本目が C15（root の content indent の `---` はトグル、より深い `---` は子の body の飾り）。
4 本目が C7（後ろに `more` が居るので隙間ではなく a の body）と、root 直下でないスロットの前の `---`
（＝側になれない位置）。5 本目は憲法 §2「木と木の間（doc 直下の隙間）の区切りは無意味のまま」。

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/parse_wbtest.mbt`
Expected: 区切りが全部その場の飾りになっているので、側が立たず body に Rule が増える。
`Total tests: 17, passed: 12, failed: 5.` EXIT=2

```
[mmm-app/core] test tree/parse_wbtest.mbt:… ("隙間の `---` は次のスロットの側を裏返す") failed: … FAILED: `"D-n()[Reh_1:r()[>Neh_1:a(r)[]>Neh_1:b()[]]]" != "D-n()[Reh_1:r()[>Neh_1:a()[]<Neh_1:b()[]]]"`
```

- [ ] **Step 3: 最小の実装を書く**

`parse.mbt` の 13 箇所を直す。

(1) `Frame` に `mut toggles` を足す（`hang` の次の行）:

```moonbit
  hang : Int // 項目の中身の列。見出しと文書は 0
  mut toggles : Int // 直前の隙間にあった `---` の本数（深さ 2 でだけ意味を持つ）
  body : Array[Block]
```

(2) `Build` の直前に `Pend` を足し、`Build` に溜め場を足す:

```moonbit
///|
/// 隙間に溜めた区切り。トグルか飾りかは、次の骨格を見るまで決まらない。
priv struct Pend {
  dash : Bool
  col : Int
  owner : Frame
}

///|
/// 読みの途中経過。開いている段の道（stack）と、まだ行き先の決まらないもの。
priv struct Build {
  stack : Array[Frame]
  pend : Array[Pend]
  verse : Array[String]
  mut next : Int
}
```

(3) `read` の文書の器の literal に `toggles: 0,` を足す（`hang: 0,` の次の行）。

(4) `read` の `let b : Build = …` を
`let b : Build = { stack: [doc], pend: [], verse: [], next: first_id }` に。

(5) Verse の腕の `if b.verse.is_empty() {` の中に `spill(b)` を 1 行足す（`shed(b, col)` の前）。

(6) Fence の腕の `knit(b)` の次に `spill(b)` を 1 行足す。

(7) Bar の腕をまるごと置き換える:

```moonbit
      Bar(col~, dash~) => {
        knit(b)
        shed(b, col)
        b.pend.push({ dash, col, owner: top(b) })
      }
```

(8) Head の腕の「領土の中」の枝に `spill(b)` を 1 行足す:

```moonbit
        if item(top(b)) {
          // 項目の領土の中。絶対記法が嘘になるので逐語で body へ落とす
          spill(b)
          top(b).body.push(Opaque(hashes(level, label)))
        } else {
```

(9) `read` の末尾の `knit(b)` の次に `spill(b)` を 1 行足す。

(10) `grow` の末尾に 2 行足す:

```moonbit
  bud(b, level, form, label, hang)
  // 開いた道の添字は深さと一致する（底が文書）。深さ 2 の新顔がスロット
  let slot = if start <= 2 && level >= 2 { Some(b.stack[2]) } else { None }
  spill_at(b, b.stack[1], slot)
}
```

(11) `bud` の Frame の literal に `toggles: 0,` を足す（`hang,` の次の行。fmt が縦に割る）:

```moonbit
  let f : Frame = {
    id: b.next,
    level,
    form,
    label,
    hang,
    toggles: 0,
    body: [],
    kids: [],
  }
```

(12) `fn shed` の直前に 2 本足す:

```moonbit
///|
/// 溜まった区切りを配る。root 直下の新しいスロットの前の隙間にある
/// `---` だけがトグルで、残りは書かれた場所の飾り（Rule）。
fn spill_at(b : Build, root : Frame, slot : Frame?) -> Unit {
  for p in b.pend {
    let mut done = false
    if p.dash && p.col <= root.hang {
      match slot {
        Some(f) => {
          f.toggles = f.toggles + 1
          done = true
        }
        None => ()
      }
    }
    if !done {
      p.owner.body.push(Rule)
    }
  }
  b.pend.clear()
}

///|
/// 次に来たのが骨格でなければ、溜まった区切りはすべて飾り。
fn spill(b : Build) -> Unit {
  for p in b.pend {
    p.owner.body.push(Rule)
  }
  b.pend.clear()
}
```

(13) `to_root` をまるごと置き換える:

```moonbit
///|
/// スロットの側は、隙間のトグルの積み上げ。先頭のトグルが左開始を表す。
fn to_root(f : Frame) -> Root {
  let branches : Array[Branch] = []
  let mut side = Right
  for k in f.kids {
    for _ in 0..<k.toggles {
      side = match side {
        Right => Left
        Left => Right
      }
    }
    branches.push({ side, node: to_node(k) })
  }
  { id: f.id, skeleton: bone(f), branches }
}
```

**`Pend.owner` を持つ理由**: 区切りは書かれた瞬間に行き先が決まらないので、飾りに落ちたときの帰り先
（そのとき開いていた段）を一緒に持ち歩く。これが無いと、`- x` の後の `---` が x を閉じた後に配られ、
文書に散文の席が無いまま宙に浮く。

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/parse_wbtest.mbt`
Expected: `Total tests: 17, passed: 17, failed: 0.` EXIT=0

- [ ] **Step 5: コミット**

```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/parse.mbt core/tree/parse_wbtest.mbt
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 隙間の区切りをスロットの側にする"
```

---

## Task 25: 畳み — details を読み取り、`<summary>` を読み飛ばす

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/parse.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/parse_wbtest.mbt`

**Interfaces:**
- Consumes: Task 24 までの `read` / `top` / `knit` / `spill` / `shed`、G1 の `spell.fold_open` / `spell.fold_close` / `spell.label_open` / `spell.label_close`（`core/tree/spell.mbt`・契約 §12）
- Produces: `fn is_summary(text : String) -> Bool` / `Frame.folded : Bool`（mut）/ `Build.folds : Int`（mut）/ `Build.fresh : Bool`（mut）

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/parse_wbtest.mbt` の末尾に足す:

```moonbit
// --- 畳み（Task 25・憲法 §4・C8・契約 §9） ----------------------------------

///|
test "details は骨格行の外側を包む" {
  assert_eq(
    parse_sig("# r\n\n## a\n\n<details>\n\n### b\n\n</details>\n"),
    "D-n()[Reh_1:r()[>Neh^1:a()[Neh_1:b()[]]]]",
  )
  assert_eq(
    parse_sig(
      "# r\n\n## a\n\n<details>\n\n### b\n\n<details>\n\n#### c\n\n</details>\n\n</details>\n",
    ),
    "D-n()[Reh_1:r()[>Neh^1:a()[Neh^1:b()[Neh_1:c()[]]]]]",
  )
}

///|
test "対応しない details は逐語のまま残す" {
  assert_eq(
    parse_sig("</details>\n\n# r\n"),
    "D-n(o10:</details>)[Reh_1:r()[]]",
  )
  assert_eq(
    parse_sig("# r\n\n<details>\n\n<details>\n\n</details>\n"),
    "D-n()[Reh^1:r(o9:<details>)[]]",
  )
}

///|
test "summary は details の直後の 1 枚だけ読み飛ばす（法則 1・2 の要）" {
  assert_eq(
    parse_sig(
      "# r\n\n## a\n\n<details>\n\n<summary>a</summary>\n\n### b\n\n</details>\n",
    ),
    "D-n()[Reh_1:r()[>Neh^1:a()[Neh_1:b()[]]]]",
  )
  assert_eq(
    parse_sig(
      "# r\n\n## a\n\n<details>\n\n### b\n\n<summary>x</summary>\n\n</details>\n",
    ),
    "D-n()[Reh_1:r()[>Neh^1:a()[Neh_1:b(o20:<summary>x</summary>)[]]]]",
  )
}
```

備考:
- 1・2 本目は C8。`<details>` は**直前の骨格の持ち物**（骨格行は外、本文と子だけ包む）なので、
  `## a` の後の `<details>` は a を畳み、その中の `### b` の後の `<details>` は b を畳む。
  ネストは吸収されずに残る。2 本目は憲法 §0「意味を 1 ビットも失わない」— 対応の付かない
  `<details>` / `</details>` は捨てずに逐語の Opaque にする（畳みは Bool なので、2 本目の開きは意味を持てない）。
- 3 本目が**裁定 1 の本体**（契約 §9）。1 つ目の assert が「`<details>` の直後の 1 枚は捨てる」
  （捨てないと serialize のたびに summary が 1 枚ずつ増え、法則 1 も法則 2 も破れる）。
  2 つ目の assert が「直後でない `<summary>` は Opaque のまま残る」（位置を問わない実装にすると、
  body の途中に手で置かれた `<summary>` まで消えて意味の損失が広がる）。
  `o20:` の 20 は `<summary>x</summary>` の UTF-16 長。

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/parse_wbtest.mbt`
Expected: `<details>` も `<summary>` も `_ => ()` と Verse の腕に落ちて何も起きない。
`Total tests: 20, passed: 17, failed: 3.` EXIT=2（実測）

```
[mmm-app/core] test tree/parse_wbtest.mbt:… ("details は骨格行の外側を包む") failed: … FAILED: `"D-n()[Reh_1:r()[>Neh_1:a()[Neh_1:b()[]]]]" != "D-n()[Reh_1:r()[>Neh^1:a()[Neh_1:b()[]]]]"`
[mmm-app/core] test tree/parse_wbtest.mbt:… ("対応しない details は逐語のまま残す") failed: … FAILED: `"D-n()[Reh_1:r()[]]" != "D-n(o10:</details>)[Reh_1:r()[]]"`
[mmm-app/core] test tree/parse_wbtest.mbt:… ("summary は details の直後の 1 枚だけ読み飛ばす（法則 1・2 の要）") failed: … FAILED: `"D-n()[Reh_1:r()[>Neh_1:a(o20:<summary>a</summary>)[Neh_1:b()[]]]]" != "D-n()[Reh_1:r()[>Neh^1:a()[Neh_1:b()[]]]]"`
```

3 本目の左辺が、裁定 1 を実装しないと起きることそのもの — `<summary>a</summary>` が a の body に
Opaque として積まれている。

- [ ] **Step 3: 最小の実装を書く**

`parse.mbt` の 9 箇所を直す。

(1) `Frame` に `mut folded` を足す（`hang` の次の行、`mut toggles` の前）:

```moonbit
  hang : Int // 項目の中身の列。見出しと文書は 0
  mut folded : Bool
  mut toggles : Int // 直前の隙間にあった `---` の本数（深さ 2 でだけ意味を持つ）
```

(2) `Build` に 2 つ足す（`mut next : Int` の次の行）:

```moonbit
  mut next : Int
  mut folds : Int
  mut fresh : Bool // 直前が <details>（間の空行は数えない）
```

(3) `read` の文書の器の literal に `folded: false,` を足す（`hang: 0,` の次の行）。

(4) `read` の `let b : Build = …` を置き換える（fmt が縦に割る）:

```moonbit
  let b : Build = {
    stack: [doc],
    pend: [],
    verse: [],
    next: first_id,
    folds: 0,
    fresh: false,
  }
```

(5) `read` の Verse の腕をまるごと置き換える（裁定 1・契約 §9）:

```moonbit
      Verse(col~, text~) =>
        // <details> の直後の 1 枚は serialize が label から作る飾り。捨てる（裁定 1）
        if b.fresh && is_summary(text) {
          b.fresh = false
        } else {
          b.fresh = false
          if b.verse.is_empty() {
            spill(b)
            shed(b, col)
          }
          b.verse.push(text)
        }
```

（`{ … }` ではなく `if … else …` を直に置く。`moon fmt` はこの形をそのまま残す — 実測。）

(6) `Fence` / `Bar` / `Head` / `Bullet` の 4 本の腕の**先頭**に `b.fresh = false` を 1 行ずつ足す
（それぞれ `knit(b)` の前）。**`Blank` の腕には足さない** — `<details>` と `<summary>` の間の空行を
跨ぐために、`Blank` は `fresh` を変えない。

(7) `read` の `_ => ()` を、Open と Close の 2 本の腕に置き換える:

```moonbit
      Open(col~) => {
        knit(b)
        spill(b)
        shed(b, col)
        let f = top(b)
        if f.level > 0 && !f.folded {
          f.folded = true
          b.folds = b.folds + 1
        } else {
          f.body.push(Opaque(spell.fold_open))
        }
        b.fresh = true
      }
      Close(col~) => {
        b.fresh = false
        knit(b)
        spill(b)
        shed(b, col)
        if b.folds > 0 {
          b.folds = b.folds - 1
        } else {
          top(b).body.push(Opaque(spell.fold_close))
        }
      }
```

(8) `bud` の Frame の literal に `folded: false,` を足す（`hang,` の次の行）、そして `bone` の
`folded=false` を `folded=f.folded` に:

```moonbit
///|
fn bone(f : Frame) -> Skeleton {
  match f.form {
    None => Implicit
    Some(form) => Explicit(form~, label=f.label, folded=f.folded, body=f.body)
  }
}
```

(9) `fn hashes` の直前に `is_summary` を足す:

```moonbit
///|
/// `<summary>…</summary>` は serialize が label から毎回作る飾り（憲法 §4）。
fn is_summary(text : String) -> Bool {
  text.has_prefix(spell.label_open) && text.has_suffix(spell.label_close)
}
```

読み方:

- `f.level > 0` の条件は「文書の器は畳めない」。`b.folds` は開きの本数だけを数える
  （閉じの位置はモデルに無い情報なので、対応が付くかどうかだけが要る）。
- `b.fresh` は「直前が `<details>`」の 1 ビット。`Open` の末尾で立て、`Blank` 以外のすべての腕で倒す。
  だから読み飛ばしの窓は「`Open` のあと、次に来た最初の非空行 1 枚」ちょうどになる。
- **内容は見ない。** label と照らし合わせないので、手で書いた別内容の `<summary>` も捨てられる
  （その帰結＝爆風半径は契約 §9 が定め、`docs/ops.md` へ書くのは G5 Task 94）。
  照らし合わせる実装にすると、一致しなかった 1 枚が Opaque として残り、serialize が label 版と合わせて
  2 枚書いて増殖する。
- **冪等性**: 1 回目の parse で捨て → serialize が label 版を `<details>` の直後に書き →
  2 回目の parse がその 1 枚を捨てる。3 回目以降も不動なので、法則 1・2 が保たれる（契約 §9）。

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/parse_wbtest.mbt`
Expected: `Total tests: 20, passed: 20, failed: 0.` EXIT=0

- [ ] **Step 5: コミット**

```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt tree
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/parse.mbt core/tree/parse_wbtest.mbt
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ details の畳みを読み、summary の飾りを読み飛ばす"
```

---

## Task 26: 網 — 封筒・流儀・健全性と、Token を直に食わせる口

**このタスクだけ形が違う。** 実装の追加は無い（Task 20〜25 で満たされている）。ここで張るのは
**後から破れたときに鳴る網**なので、Step 2 は「失敗の確認」ではなく「最初から通ることの確認」になる。
通らなければ Task 20〜25 のどれかが間違っている（下の対応表を読む）。

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/parse_wbtest.mbt`

**Interfaces:**
- Consumes: `pub fn check(doc : Doc) -> Array[String]`（G1・契約 §7）/ `fn read(scanned : Scan) -> Doc`（Task 20）/ `pub(all) struct Scan`・`pub(all) enum Token`（G1）
- Produces: (test) `fn parse_faults(md : String) -> String`

- [ ] **Step 1: 網のテストを書く**

`core/tree/parse_wbtest.mbt` のヘルパ（`parse_sig` の次）に 1 本足す:

```moonbit
///|
/// 破れを 1 本に綴じる。健全なら空。
fn parse_faults(md : String) -> String {
  let faults = check(parse(md))
  let sb = StringBuilder::new()
  for i, f in faults {
    if i > 0 {
      sb.write_string(" / ")
    }
    sb.write_string(f)
  }
  sb.to_string()
}
```

そしてファイルの末尾に 3 本足す:

```moonbit
// --- 封筒・流儀・健全性（Task 26） ------------------------------------------

///|
test "封筒と改行の流儀は走査の結果をそのまま持つ" {
  assert_eq(
    parse_sig("---\nimage-folder: img\n---\n\n# r\n"),
    "D+17:image-folder: imgn()[Reh_1:r()[]]",
  )
  assert_eq(parse_sig("# r\r\n\r\n## a\r\n"), "D-r()[Reh_1:r()[>Neh_1:a()[]]]")
}

///|
test "parse の結果は必ず check を通る" {
  let corpus = [
    "", "# r\n", "## a\n", "- a\n\n## h\n", "# r\n\n#### b\n", "# r\n\n- x\n\n### y\n",
    "- a\n  - b\n## h\n", "# r\n\n## a\n\n---\n\n## b\n", "- center\n\n  - a\n\n  ---\n\n  - b\n",
    "intro\n\n# r\n\n***\n", "## a\n\n# r\n\n#### z\n", "# r\n\n<details>\n\n- x\n\n</details>\n\n## b\n",
    "- a\n\n  ## h\n\n- b\n", "#\n\n#####\n\n- \n",
    "# r\n\n## a\n\n<details>\n\n<summary>a</summary>\n\n### b\n\n</details>\n",
  ]
  for md in corpus {
    assert_eq(parse_faults(md), "")
  }
}

// --- 通しの固定（Task 26） --------------------------------------------------

///|
test "read は Token の列だけで木を建てる" {
  let scanned : Scan = {
    frontmatter: Some("k: v"),
    eol: Crlf,
    tokens: [
      Head(col=0, level=1, label="r"),
      Blank,
      Bar(col=0, dash=true),
      Blank,
      Head(col=0, level=4, label="b"),
    ],
  }
  assert_eq(sig(read(scanned)), "D+4:k: vr()[Reh_1:r()[<Ni[Ni[Neh_1:b()[]]]]]")
}
```

備考:
- 1 本目は C11（封筒は parse の前段で切り出された逐語。parse は写すだけ）と、憲法 §4
  「EOL は原文の流儀を保存するダイヤル」。
- 2 本目が**この群の本体の見張り**。契約 §7 の 6 条件（id 一意 / Implicit の存在条件 /
  Implicit の前の兄弟はすべて項目 / Implicit の子に項目は居ない / 順序法則 / 単調性）を、
  parse がどんな md からも破らないことを掃く。**parse には順序法則を強制するコードが 1 行も無い** —
  閉じる規則の帰結として破れないので、その帰結が本当かをここで測る。
  最後の 1 本（`<summary>` 入りの畳み）は、裁定 1 の読み飛ばしが木を壊していないことを掃く。
- 3 本目は `read` が Token だけで建つこと（scan の作りに依らない口）。C16 の木を Token で直に書いている。

- [ ] **Step 2: テストを走らせて、最初から通ることを確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/parse_wbtest.mbt`
Expected: `Total tests: 23, passed: 23, failed: 0.` EXIT=0

破れたときの読み方（違反の逐語は契約 §7）:

| 出た破れ | 疑う場所 |
|---|---|
| `id が重なっている (id=…)` | `bud` の `b.next` の増やし忘れ（Task 20） |
| `Implicit に子が無い (id=…)` | `grow` が `level` まで届かず Implicit を積んで終わっている（Task 21） |
| `Implicit の前に項目でない兄弟が居る (id=…)` | Head の腕の閉じ順（Task 22）。項目を閉じる前に `while top(b).level >= level` を回していないか |
| `Implicit の子が項目 (id=…)` | Bullet が Implicit の子になっている＝道の先頭が Implicit のまま body / 骨格を受けている（Task 21・23） |
| `見出しの後ろに項目が居る (id=…)` | Bullet の腕が項目を閉じすぎて文書まで戻っている（Task 23 の `shed` の `top(b).level > 1` が抜けた） |
| `項目の子孫が項目でない (id=…)` | Head の「領土の中」の判定（Task 22）が効いていない |

- [ ] **Step 3: 群の出口をまとめて確かめる**

Run:

```
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core check tree
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt --check tree
moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test -p mmm-app/core -p mmm-app/core/tree
```

Expected:
- `moon … check tree` → `Finished. moon: ran N tasks, now up to date (M warnings, 0 errors)` EXIT=0
  （警告は他群の未使用（例: `Warning: [0001] Warning (unused_value): Unused function 'amend'`）だけ。
  parse.mbt 由来の警告は 0 であること）
- `moon … fmt --check tree` → `Finished. moon: ran N tasks, now up to date` EXIT=0（失敗は **EXIT=127**）
- `moon … test -p …` → `failed: 0.` EXIT=0。**`Total tests:` が 0 でないことを目で見る**
  （`-p` の綴り間違いは黙って緑になる）。他群と並行しているので総数は動く — **G2 の取り分は 23 本**。

- [ ] **Step 4: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/parse_wbtest.mbt
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "test: ✅ 読みの網（封筒・流儀・健全性・Token 直入れ）を張る"
```

---

## 群の終わりの状態

- `core/tree/parse.mbt` — 356 行。外へ出るのは `pub fn parse` 1 本だけで、あとは priv な足場 3 型と関数 16 本
- `core/tree/parse_wbtest.mbt` — 321 行・**23 テスト**（ヘルパ 4 本）
- `moon … check tree` 0 errors / `moon … fmt --check tree` 0 差分 / G2 のテスト 23/23

**受け入れ条件**: `parse` が出した Doc は**必ず `check` が空**（Task 26 の網で確かめる）。

### 次の群への申し送り

1. **G3（書き）へ** — parse が作る Opaque の逐語には**字下げが入っていない**（項目の領土の見出しも `## h`
   のまま）。serialize が領土へ書くときに字下げを履かせること。中身の改行も常に LF なので、`eol` はそこで
   履かせる。
2. **G3 へ** — `Rule` は `---` と `***` の両方から来る（読みは区別しない）。書きは常に `***`
   （憲法 §4 のチャンネル分離）。トグルの `---` は側の列から導出されるので、body の Rule とは別の口から書くこと。
3. **G3 へ** — serialize は畳んだノードの `<details>` の**直後**に `<summary>label</summary>` を置くこと。
   parse が読み飛ばす窓は「`Open` のあと、間の空行を跨いだ最初の非空行 1 枚」ちょうど（契約 §9）。
   ここに別の行を先に挟むと、summary が Opaque として残って増殖する。
4. **G4（法則）へ** — 法則 1 の比較子は `sig`。parse は `check` を必ず通る木しか作らないので、ファズで
   `check` が空でない木が出たら**それは parse のバグ**（serialize でも sig でもない）。`randomDoc` が
   落ちたときの一次切り分けに使える。指紋に `o…:<summary>…` が増えたら、それは Task 25 の読み飛ばしの
   破れ（契約 §19 の差し戻し表と同じ）。
5. **G5（操作・文書）へ** — 「手で書いた `<summary>` は残らない」は意味の損失なので、契約 §9 の爆風半径の
   1 行を `docs/ops.md` に置くのは G5 Task 94。その文言が Task 25 の実装（**直後の 1 枚だけ**・内容は見ない）
   と食い違ったら、実装ではなく文言のほうを G5 で直すか、G2 へ差し戻すこと。
