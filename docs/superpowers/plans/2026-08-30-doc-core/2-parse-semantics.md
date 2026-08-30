# T2 — parse の意味の解釈（Task 10〜17）

## この群の概要

**担当範囲（Task 10〜17）** — かたまりの並び（`Scan`）を木（`Ast`）にする層。`block.mbt`（かたまり 1 つの認定）・`build.mbt`（並び → 木）・`parse.mbt`（読みの入口）の 3 ファイルと、その白箱テスト 2 本を持つ。

**所有ファイル（正誤表 §B-1・§B-2）**

| ファイル | 権限 |
|---|---|
| `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/block.mbt` | **Modify のみ**（Create は T1 Task 8。仮置きの `classify` を本実装に差し替える） |
| `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/build.mbt` | Create（Task 12） |
| `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/parse.mbt` | Create（Task 17） |
| `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/block_wbtest.mbt` | Create（Task 10） |
| `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/build_wbtest.mbt` | Create（Task 12） |

**1 バイトも触らないもの**: `ast.mbt` / `spell.mbt` / `line.mbt` / `scan.mbt` / `scan_wbtest.mbt` / `fixture_wbtest.mbt`（すべて T1 所有）、旧 core（`core/*.mbt`・`core/js/`）、`src/`、既存 `test/*.test.ts` 26 本、仕様とカタログ。

**着手の前提（正誤表 §H-2 の依存図）**

- Task 10・11 — **T1 Task 8 のコミット `feat: ✨ かたまりの駆動をコンテナのスタックで書く` を待つ**（`block.mbt` の仮置きと、`line.mbt` の `lead_spaces` / `blank_line` がそこまでに揃う）
- Task 12〜16 — T1 Task 5 のコミット（`Scan` / `Chunk` / `Kind` の型）以降なら着手できる。テストは手で組んだ `Scan` を入力にするので `scan` の完成を待たない
- Task 16 — **T1 Task 1 のコミット `feat: ✨ 新 core のパッケージと文書の木の型を置く` が必須**（`spell.mbt` の `fold_open` / `fold_close` を読む）
- Task 17 — **T1 Task 9 のコミット `feat: ✨ 項目の領土・setext・summary の裁定を仕上げる` を待つ**（ここで初めて `scan` を通す）

**名前の約束（正誤表 §C。破ると `Error: [4051] ... is declared twice` でテストが 1 本も走らなくなる）**

- **`indent_of` と `is_blank` を定義しない。** T1 `line.mbt` の **`lead_spaces(s : String) -> Int`**（先頭の半角空白を数える）と **`blank_line(s : String) -> Bool`**（空白とタブだけなら true）を呼ぶ
- **`spell.mbt` を作らない。** 11 定数の所有者は T1 Task 1。T2 は `fold_open` / `fold_close` を読むだけ
- `build_wbtest.mbt` の指紋ヘルパは **`built_sig(chunks : Array[Chunk]) -> String`**（`wire.mbt` の `pub fn sig_of(md)` と衝突するため）
- 手で木を組むヘルパ（`node` / `heading` / `item` / `doc_of` / `ast_of` / `chain`）は `fixture_wbtest.mbt`（T1 Task 2）にある。T2 は木を手で組まない（かたまりを組む）ので使わない

**整形の綴り**

各 Step 4 の `moon -C <REPO>/core fmt doc` は**整形を当てる**コマンドである（`--check` ではない）。**この計画に載っているコードは `moon fmt` を通す前の姿**なので、80 桁を超える `||` 連鎖・struct リテラル・`assert_eq` は `fmt` が複数行へ展開する。**展開後の姿でコミットする**（Step 5 の `git add` は `fmt` の後に打つ）。

**テスト本数の読み方**

`moon test -p mmm-app/core/doc` はパッケージ内の全テストを走らせるので、`Total tests:` には T1（Task 1〜9）ぶんが必ず加算される。**判定は「新規 N 本が緑・`failed: 0`・既存が 1 本も落ちない」**で行う。T2 ぶんの累計は Task 10 から順に **6 / 11 / 14 / 20 / 27 / 33 / 37 / 46** 本。
**`Total tests: 0` を見たら緑ではない**（正誤表 §E-1-2 — `-p` の綴りを疑う）。

**T1 の `scan` への前提**（Task 12〜16 は手組みの `Scan` で書くので、食い違いは Task 17 の通しテストで初めて出る）

- `Body` の逐語は改行 `"\n"` で綴じ、末尾改行を含まず、`\r` を 1 文字も含まない（正誤表 §A-7 前提 1。履行者は T1）
- `Body` の逐語から**コンテナ（項目）の字下げを落とす**。ただし**インデントコードの 4 スペースは残す**
- 空行は落とす。`<summary>…</summary>` の行は **`<details>` の直後の 1 行だけ**落とす（裁定 7）
- `Chunk.depth` は、骨格行なら自分の深さ、それ以外は所属コンテナの深さ（文書直下は 0）
- 項目の骨格の深さは「親の深さ + 1」を超えない（相対記法。飛びは絶対記法だけ）
- 項目の**領土内**（字下げの中）の見出しは `Skel` ではなく `Body(Opaque)` で渡す。**逆に、項目のあとに列 0 で書かれた見出しは領土の外なので `Skel(Heading, …)` で届く**（md では見出しがリストを終わらせる）。この形を項目の子にしないのは `build` の仕事である（下の申し送り 6）
- frontmatter は封筒として切り出し、頭でない `---` は `Break(true)` で渡す。**封筒なのは「閉じの `---` があり、かつ開きの `---` の直後が空行でない」ときだけ**（裁定 E・仕様 §4 の方言表）。該当しなければ先頭トグル（左開始）として `Break(true)` で届く — mmm が書く先頭トグルは空行規律により必ず直後が空行になるので、両者は綴りで分かれる
- **`Break(true)` は「空白を 1 つも含まない `---`」だけ。`- - -` も `***` も `___` も `Break(false)`**（裁定 2。T1 Task 6 で `bullet_at` に guard が入っている）

**契約への申し送り（着手前に全員へ共有する。契約の型・シグネチャは 1 つも変えていない）**

1. **正誤表 §A-8-④ の区切りの規則に「領土」の条件を 1 つ足す。** 1 行規則（「`Break(true)` の極大の連なりの直後が深さ 2 の `Skel` ならトグル」）だけだと、C15 の**より深い** `---` を誤ってトグルにする（`- center` / `  - a` / `    ---` / `  - c` — カタログは「より深い位置の `---` は子の body の飾り」と言う）。足す条件は「その区切りが、深さ 2 以上の**項目**の領土に居ないこと」。見出しは領土（字下げ）を持たないので、見出し root の下では今までどおり全部トグルになる
2. **裁定 1（不変条件 11「implied ⇒ side = Right」）を `build` は「側を配らない」ことで守る。** 側の割り当ては `push_frame` の深さ 2 の分岐にしかなく、そこに `!implied` の条件を置く。飛びで生まれた implied には側を書く綴りが無いので、持たせると serialize が書けず法則 2 が破れる
3. **C8 の mermaid とは食い違う。** カタログ C8 の元 map は `c` に `〔畳〕` を描くが、`<details>` は `### b` の直後にあり、仕様 §4 の「骨格行は外、本文と子だけ包む」に従えば折れているのは **b** である。仕様本文を正とし、テストは b に対して書いた。**カタログは統括の持ち物なので触らない** — mermaid の訂正を提案するに留める
4. **対を欠く畳みのタグは `Opaque` に落とす**（意味を捨てない）。doc 直下の `<details>` も同じ（不変条件 1「doc は folded=false」を守るため）
5. **`classify` も水平線を `Rule` に読む。** 通常は `scan` が `Break` で捕まえるのでここへは来ないが、`Opaque("***")` という**法則 1 を破れる値**を作らせないための門である（serialize は `***` を書き、parse は `Rule` に戻すので、`Opaque` のまま持つと往復が破れる）。裁定 2 により `- - -` もここで `Rule` になる
6. **順序法則・単調性は「並べ替えないこと」と「見出しで項目を閉じること」で守る。** `build` は並べ替えない。項目の**領土内**の見出しは `scan` が `Opaque` にするので木に入らないが、**項目のあとに列 0 で書かれた見出し**（`- a` + `## h`）は `Skel(Heading, …)` で届く。これをそのまま積むと見出しが項目の子になり、不変条件 3（Item の下に Heading）が parse の時点で破れる。よって `push_skel` は**見出しを積む前に開いている項目を全部閉じる**（裁定 A・仕様 §2「項目の後ろに列 0 で書かれた見出しは、その項目の子にはならない。読みは開いている項目をすべて閉じ、直近の見出し（または doc）に付ける。level の飛びはそこで implied が埋める」）。結果は `doc.children = [a(Item), implied(1)[h]]` で、順序法則（項目が先・見出しが後）も満たす。破れたら `check`（T1）が言う
7. **`classify` を本実装にしても T1 の `scan_wbtest.mbt` は無傷**（裁定 5 により `chunks_sig` は Body の中身を `body` としか出さない。T1 Task 8 の C9 のテストも `chunks_sig` で書かれており、`body_text` は「散文＝本実装でも `Opaque` のまま残る形」にしか使われない）。**T2 は `scan_wbtest.mbt` を 1 バイトも触らない**
8. **不変条件 8 は「implied ⇒ その前に見出しの兄弟が居ない」に一般化される**（裁定 B・違反メッセージは `implied の前に見出しが居る: <id>`）。申し送り 6 が生む `[a(Item), implied[h]]` は綴りが一意に読み戻せる健全な木であり、「implied ⇒ 親の children の先頭」のままでは `check` が誤って弾く。見出しは飛びを飲み込むが項目は飲み込まないので、**直前の兄弟が項目なら implied は置ける**。T1 の `check` の `visit` と T5 の `spellable` がこの言葉に揃っている前提で Task 15・17 の `check(...).length() == 0` を書く

---

## Task 10: かたまり 1 つを Block に読む（Opaque・Rule・画像・リンク）

**Files:**
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/block.mbt`（T1 Task 8 が置いた仮置きの `classify` を本実装に差し替える。**Create しない**）
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/block_wbtest.mbt`（Create）

**Interfaces:**
- Consumes: `fn code_at(s : String, i : Int) -> Int` / `fn slice(s : String, a : Int, b : Int) -> String` / **`fn lead_spaces(s : String) -> Int`**（T1 `line.mbt`）、`enum Block` / `enum Content`（T1 `ast.mbt`）
- Produces: `pub fn classify(text : String) -> Block`（T1 の `scan` の `flush` が呼ぶ。Task 12〜17 の通しがこれを通る）、`fn content_of(text : String) -> Content?` / `fn is_rule_text(text : String) -> Bool` / `fn image_of(text : String) -> Content?` / `fn link_of(text : String) -> Content?` / `fn link_parts(text : String, start : Int) -> (String, String)?` / `fn starts(s : String, p : String) -> Bool` / `fn ends(s : String, p : String) -> Bool`

**カバーする要件:** R016・R017（Content の割り）、R018（疑わしきは Opaque）、R081（水平線の綴り。裁定 2）、R110（散文は逐語）。正誤表 §A-8-⑤・⑥。

- [ ] **Step 1: 失敗するテストを書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/block_wbtest.mbt` を作る:

```moonbit
// 認定の境目（Content と Opaque の差）を Block の値で直接見たいので whitebox テスト。

///|
test "散文は逐語の Opaque になる" {
  // R018 R110
  assert_eq(classify("ふつうの散文\n2 行目"), Opaque("ふつうの散文\n2 行目"))
}

///|
test "水平線は綴りの銘柄によらず Rule になる" {
  // R081 正誤表 §A-8-⑤・裁定 2（`- - -` は CommonMark どおり飾りの水平線）
  assert_eq(classify("***"), Rule)
  assert_eq(classify("- - -"), Rule)
  assert_eq(classify("___"), Rule)
  assert_eq(classify("--"), Opaque("--"))
}

///|
test "画像は alt と src に割れる" {
  // R016 R017
  assert_eq(classify("![a](b.png)"), Content(Image(alt="a", src="b.png")))
}

///|
test "title 付きの画像は書き戻せないので Opaque" {
  // R018 正誤表 §A-8-⑥
  assert_eq(classify("![a](b.png \"t\")"), Opaque("![a](b.png \"t\")"))
}

///|
test "リンクは text と href に割れる" {
  // R016 R017
  assert_eq(
    classify("[x](https://e.com)"),
    Content(Link(text="x", href="https://e.com")),
  )
}

///|
test "行き先に空白があるリンクは Opaque" {
  // R018 正誤表 §A-8-⑥
  assert_eq(classify("[a](b c)"), Opaque("[a](b c)"))
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected（正誤表 §F-3 — **コンパイルは通る**。T1 Task 8 の仮置き `classify` が既に居るので「unbound」にはならない）:

> `Total tests: N, passed: N-3, failed: 3.`（EXIT=2）。仮置きは常に `Opaque(text)` を返すので、`assert_eq` が値の差を出す。落ちるのは **「水平線は綴りの銘柄によらず Rule になる」**（`Opaque("***")` と `Rule` の差）・**「画像は alt と src に割れる」**（`Opaque("![a](b.png)")` と `Content(Image(alt="a", src="b.png"))` の差）・**「リンクは text と href に割れる」**の 3 本。逐語の `Opaque` を期待する 3 本（散文・title 付きの画像・行き先に空白があるリンク）は仮置きでも通る。

> **正誤表 §G-2-2 の括弧内（「`Rule` の 4 件と Image / Link の 2 件が FAIL、散文の 1 本だけが PASS」）は 7 本ある前提の古い数え方である。** Step 1 のテストは 6 本で、`Rule` を見る 4 つの `assert_eq` は 1 本のテストに入っている。**この Step の正は「3 本 FAIL / 3 本 PASS」**（再査読 1 の軽微。正誤表側の括弧内も同じ文言に直っている）。

- [ ] **Step 3: 最小の実装を書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/block.mbt` の全文を、次に差し替える:

```moonbit
// 逐語のかたまりを Block にする層。認定の唯一の基準は
// 「serialize が書く綴りを parse し直すと同じ値に戻ること」。

///|
/// 逐語のかたまり 1 つを Block にする。**疑わしきは Opaque**。
pub fn classify(text : String) -> Block {
  if is_rule_text(text) {
    Rule
  } else {
    match content_of(text) {
      Some(c) => Content(c)
      None => Opaque(text)
    }
  }
}

///|
fn content_of(text : String) -> Content? {
  let readers : Array[(String) -> Content?] = [image_of, link_of]
  for f in readers {
    let c = f(text)
    if c is Some(_) {
      return c
    }
  }
  None
}

///|
/// 水平線 1 行か。飾りの `***` も トグルの `---` も、印の間に空白を挟む
/// `- - -` も、ここでは同じ Rule（裁定 2 — CommonMark の thematic break）。
fn is_rule_text(text : String) -> Bool {
  if text.contains("\n") {
    return false
  }
  let n = text.length()
  let mut i = lead_spaces(text)
  if i > 3 || i >= n {
    return false
  }
  let mark = code_at(text, i)
  if mark != 45 && mark != 42 && mark != 95 {
    return false
  }
  let mut runs = 0
  while i < n {
    let c = code_at(text, i)
    if c == mark {
      runs = runs + 1
    } else if c != 32 && c != 9 {
      return false
    }
    i = i + 1
  }
  runs >= 3
}

///|
/// `![alt](src)`。書き戻した綴りを読み直すと同じ値に戻る形だけ通す。
fn image_of(text : String) -> Content? {
  if !starts(text, "![") {
    return None
  }
  match link_parts(text, 2) {
    Some((a, s)) => Some(Image(alt=a, src=s))
    None => None
  }
}

///|
/// `[text](href)`。
fn link_of(text : String) -> Content? {
  if !starts(text, "[") {
    return None
  }
  match link_parts(text, 1) {
    Some((t, h)) => Some(Link(text=t, href=h))
    None => None
  }
}

///|
/// `…](…)` を割る。ラベルに括弧記号、行き先に空白・括弧があれば認定しない
/// （どちらも書き戻した綴りを読み直すと同じ値に戻らない）。
fn link_parts(text : String, start : Int) -> (String, String)? {
  if text.contains("\n") {
    return None
  }
  let n = text.length()
  if !ends(text, ")") {
    return None
  }
  let mut i = start
  let mut cut = -1
  while i < n - 1 {
    if code_at(text, i) == 93 && code_at(text, i + 1) == 40 {
      cut = i
      break
    }
    i = i + 1
  }
  if cut < 0 {
    return None
  }
  let label = slice(text, start, cut)
  let dest = slice(text, cut + 2, n - 1)
  for ch in label.iter() {
    let c = ch.to_int()
    if c == 91 || c == 93 {
      return None
    }
  }
  for ch in dest.iter() {
    let c = ch.to_int()
    if c == 32 || c == 9 || c == 40 || c == 41 {
      return None
    }
  }
  Some((label, dest))
}

///|
fn starts(s : String, p : String) -> Bool {
  s.length() >= p.length() && slice(s, 0, p.length()) == p
}

///|
fn ends(s : String, p : String) -> Bool {
  s.length() >= p.length() && slice(s, s.length() - p.length(), s.length()) == p
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected: `fmt` は EXIT=0（整形が当たった差分はそのままコミットする）。`test` は最終行が `Total tests: N, passed: N, failed: 0.`（EXIT=0）で、Step 2 で落ちていた 3 本が緑に変わり、既存は 1 本も落ちない。**T2 ぶんの累計は 6 本。** `Total tests: 0` は緑ではない（§E-1-2）。

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/block.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/block_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ かたまり 1 つを Block に読む（疑わしきは Opaque）"
```

---

## Task 11: コードと svg の認定

**Files:**
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/block.mbt`（`content_of` を丸ごと置き換え、末尾に道具を足す）
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/block_wbtest.mbt`（末尾へ追記）

**Interfaces:**
- Consumes: `classify` / `content_of` / `starts` / `ends`（Task 10）、`fn code_at` / `fn slice` / **`fn lead_spaces(s : String) -> Int`** / **`fn blank_line(s : String) -> Bool`**（T1 `line.mbt`）
- Produces: `fn code_of(text : String) -> Content?` / `fn fence_head(line : String) -> (Int, Int, String)?` / `fn is_fence_close(line : String, mark : Int, len : Int) -> Bool` / `fn indented_code(ls : Array[String]) -> Content?` / `fn svg_of(text : String) -> Content?` / `fn lines_of(text : String) -> Array[String]` / `fn join(ls : Array[String], from : Int, to : Int) -> String` / `fn trim(s : String) -> String`

**カバーする要件:** R017（Code の割り）、R088（フェンス）、R105（インデントコード）、R018（疑わしきは Opaque）。カタログ C9。

- [ ] **Step 1: 失敗するテストを書く**

`block_wbtest.mbt` の末尾に足す:

```moonbit
///|
test "フェンスのコードは info と中身に割れる" {
  // R017 R088
  assert_eq(
    classify("```ts\nlet x = 1\n```"),
    Content(Code(info="ts", text="let x = 1")),
  )
}

///|
test "インデントコードも同じ Code に読む" {
  // R105 C9
  assert_eq(classify("    code"), Content(Code(info="", text="code")))
}

///|
test "info にバッククォートがあるフェンスは Opaque" {
  // R018 正誤表 §A-8-⑥（serialize は常にバッククォートのフェンスを書くので戻せない）
  assert_eq(classify("```a`b\nx\n```"), Opaque("```a`b\nx\n```"))
}

///|
test "閉じないフェンスは Opaque" {
  // R018
  assert_eq(classify("```\nx"), Opaque("```\nx"))
}

///|
test "svg は逐語で認定する" {
  // R017
  assert_eq(
    classify("<svg><circle r=\"5\"/></svg>"),
    Content(Svg("<svg><circle r=\"5\"/></svg>")),
  )
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected（正誤表 §F-3 — コンパイルは通り、**値の差で落ちる**）:

> `Total tests: N, passed: N-3, failed: 3.`（EXIT=2）。Task 10 の `classify` は Code も Svg も知らないので、`assert_eq` が `Opaque("```ts\nlet x = 1\n```")` と `Content(Code(info="ts", text="let x = 1"))` の差を出す。落ちるのは **「フェンスのコードは info と中身に割れる」「インデントコードも同じ Code に読む」「svg は逐語で認定する」**の 3 本。`Opaque` を期待する 2 本（info にバッククォート・閉じないフェンス）は今でも通る。

- [ ] **Step 3: 最小の実装を書く**

`block.mbt` の `content_of` を丸ごと置き換える:

```moonbit
///|
fn content_of(text : String) -> Content? {
  let readers : Array[(String) -> Content?] = [
    image_of, link_of, code_of, svg_of,
  ]
  for f in readers {
    let c = f(text)
    if c is Some(_) {
      return c
    }
  }
  None
}
```

同じファイルの末尾（`ends` の後）に足す:

```moonbit
///|
/// フェンス（``` / ~~~）とインデントコード。どちらも同じ Code に読む。
fn code_of(text : String) -> Content? {
  let ls = lines_of(text)
  match fence_head(ls[0]) {
    Some((mark, len, info)) => {
      if ls.length() < 2 {
        return None
      }
      if !is_fence_close(ls[ls.length() - 1], mark, len) {
        return None
      }
      if info.contains("`") {
        return None
      }
      Some(Code(info~, text=join(ls, 1, ls.length() - 1)))
    }
    None => indented_code(ls)
  }
}

///|
/// 開きのフェンス。字下げ 0 だけ受ける（コンテナの字下げは scan が落としている）。
fn fence_head(line : String) -> (Int, Int, String)? {
  let n = line.length()
  if n < 3 {
    return None
  }
  let mark = code_at(line, 0)
  if mark != 96 && mark != 126 {
    return None
  }
  let mut i = 0
  while i < n && code_at(line, i) == mark {
    i = i + 1
  }
  if i < 3 {
    return None
  }
  Some((mark, i, trim(slice(line, i, n))))
}

///|
fn is_fence_close(line : String, mark : Int, len : Int) -> Bool {
  let n = line.length()
  let mut i = lead_spaces(line)
  if i > 3 {
    return false
  }
  let mut runs = 0
  while i < n && code_at(line, i) == mark {
    runs = runs + 1
    i = i + 1
  }
  if runs < len {
    return false
  }
  while i < n {
    let c = code_at(line, i)
    if c != 32 && c != 9 {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// 4 スペースの字下げコード。タブは受けない（疑わしきは Opaque）。
fn indented_code(ls : Array[String]) -> Content? {
  if blank_line(ls[0]) || blank_line(ls[ls.length() - 1]) {
    return None
  }
  let out : Array[String] = []
  for l in ls {
    if blank_line(l) {
      out.push("")
    } else if lead_spaces(l) >= 4 {
      out.push(slice(l, 4, l.length()))
    } else {
      return None
    }
  }
  Some(Code(info="", text=join(out, 0, out.length())))
}

///|
/// `<svg …>…</svg>` 逐語。空行を挟むと 1 つのかたまりに戻らないので認定しない。
fn svg_of(text : String) -> Content? {
  if !starts(text, "<svg") || !ends(text, "</svg>") {
    return None
  }
  if text.contains("\n\n") {
    return None
  }
  Some(Svg(text))
}

///|
fn lines_of(text : String) -> Array[String] {
  let out : Array[String] = []
  let n = text.length()
  let mut start = 0
  let mut i = 0
  while i < n {
    if code_at(text, i) == 10 {
      out.push(slice(text, start, i))
      start = i + 1
    }
    i = i + 1
  }
  out.push(slice(text, start, n))
  out
}

///|
fn join(ls : Array[String], from : Int, to : Int) -> String {
  let sb = StringBuilder::new()
  for i = from; i < to; i = i + 1 {
    if i > from {
      sb.write_string("\n")
    }
    sb.write_string(ls[i])
  }
  sb.to_string()
}

///|
fn trim(s : String) -> String {
  let n = s.length()
  let mut a = 0
  let mut b = n
  while a < b && (code_at(s, a) == 32 || code_at(s, a) == 9) {
    a = a + 1
  }
  while b > a && (code_at(s, b - 1) == 32 || code_at(s, b - 1) == 9) {
    b = b - 1
  }
  slice(s, a, b)
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected: `fmt` は EXIT=0。`test` は `… failed: 0.`（EXIT=0）で、Step 2 で落ちていた 3 本が緑に変わり、既存は 1 本も落ちない。**T2 ぶんの累計は 11 本。**

> **`indented_code` が入るとインデントコードの `Body` の中身が `Opaque` でなくなる。** T1 Task 8 の C9 のテストは `chunks_sig("# r\n\n    code\n") == "1H:r|1body|"` の形（Body の中身を覗かない）で書かれており、`body_text` は散文にしか使われないので、この Step で `scan_wbtest.mbt` は 1 本も落ちない。**もし `Body(Opaque) ではない` で abort するテストが T1 側に残っていたら、それは T1 Task 8 が再査読の致命を取りこぼしている**ということなので、`block.mbt` を疑わずに逐語のメッセージを T1 へ渡すこと（T2 は `scan_wbtest.mbt` を触れない）。

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/block.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/block_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ コードと svg を認定する（インデントコードも Code へ）"
```

---

## Task 12: かたまりの並びを木にする（深さ・id）

**Files:**
- Create: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/build.mbt`
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/build_wbtest.mbt`（Create）

**Interfaces:**
- Consumes: `pub struct Scan` / `pub struct Chunk` / `pub enum Kind`（T1 `scan.mbt`）、`struct Ast` / `struct Node` / `enum Form` / `enum Side` / `enum Block` / `enum Eol` / `pub fn sig(ast : Ast) -> String`（T1 `ast.mbt`）
- Produces: `pub fn build(sc : Scan) -> Ast`、`priv struct Frame` / `priv struct Ctx`、`fn close_frame(fr : Frame) -> Node` / `fn top(cx : Ctx) -> Frame` / `fn close_to(cx : Ctx, d : Int) -> Unit` / `fn push_skel(cx : Ctx, want : Int, form : Form, label : String) -> Unit` / `fn push_frame(cx : Ctx, form : Form, label : String, implied : Bool) -> Unit`、テストの道具 `fn skel(d : Int, f : Form, label : String) -> Chunk` / `fn built_sig(chunks : Array[Chunk]) -> String`

**カバーする要件:** R020（id は文書順に 1 から。doc が 1）、R038（リストは相対記法）、R052・R053（深さ = level の全域一致）。

- [ ] **Step 1: 失敗するテストを書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/build_wbtest.mbt` を作る:

```moonbit
// build はかたまりの並び（走査の中間表現）を入力に取る。並びを手で組んで
// 木を直接見たいので whitebox テスト。scan を通さないので T1 と独立に落ちる。
//
// 指紋のヘルパを `built_sig` と綴るのは、`wire.mbt`（T4）の
// `pub fn sig_of(md : String)` と同じ名前空間に居るため（正誤表 §C-1）。

///|
fn skel(d : Int, f : Form, label : String) -> Chunk {
  { depth: d, kind: Skel(f, label) }
}

///|
fn built_sig(chunks : Array[Chunk]) -> String {
  sig(build({ head: None, eol: Lf, chunks }))
}

///|
test "骨格の深さがそのまま親子になる" {
  // R052 R053
  assert_eq(
    built_sig([
      skel(1, Heading, "r"),
      skel(2, Heading, "a"),
      skel(2, Heading, "b"),
    ]),
    "head:-\nlf\n[H[Hr[Ha][Hb]]]",
  )
}

///|
test "項目は飛べないので、いま開いている枝の子になる" {
  // R038（リストは相対記法。implied を作らない）
  assert_eq(
    built_sig([skel(1, Heading, "r"), skel(4, Item, "x")]),
    "head:-\nlf\n[H[Hr[Ix]]]",
  )
}

///|
test "id は文書順に 1 から振られる" {
  // R020 正誤表 §A-2（doc が 1）
  let ast = build({
    head: None,
    eol: Lf,
    chunks: [skel(1, Heading, "r"), skel(2, Heading, "a")],
  })
  assert_eq(ast.doc.id, 1)
  assert_eq(ast.doc.children[0].id, 2)
  assert_eq(ast.doc.children[0].children[0].id, 3)
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected（正誤表 §F-1）: コンパイルが通らず、テストは 1 本も走らない。

```
Error: [4021]
The value identifier build is unbound.
```

- [ ] **Step 3: 最小の実装を書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/build.mbt` を作る:

```moonbit
// かたまりの並び → 木。implied の導出・側の割り当て・畳みの対応付けはここ。
// stack の索引がそのまま深さ（stack[0] = doc）なので、level を持つ必要が無い。

///|
/// 組み立て中のノード 1 つ。木は不変なので、閉じるときに Node へ畳む。
priv struct Frame {
  id : Int
  form : Form
  label : String
  implied : Bool
  side : Side
  folded : Bool
  body : Array[Block]
  kids : Array[Node]
}

///|
/// 組み立ての状態。stack の索引がそのまま深さ（stack[0] = doc）。
priv struct Ctx {
  stack : Array[Frame]
  mut next_id : Int
}

///|
/// かたまりの並びを木にする。
pub fn build(sc : Scan) -> Ast {
  let cx = {
    stack: [
      {
        id: 1,
        form: Heading,
        label: "",
        implied: false,
        side: Right,
        folded: false,
        body: [],
        kids: [],
      },
    ],
    next_id: 2,
  }
  let cs = sc.chunks
  let mut i = 0
  while i < cs.length() {
    let ch = cs[i]
    match ch.kind {
      Skel(form, label) => {
        push_skel(cx, ch.depth, form, label)
        i = i + 1
      }
      Body(_) => i = i + 1 // Task 14 で読む
      Break(_) => i = i + 1 // Task 14 で読む
      Fold(_) => i = i + 1 // Task 16 で読む
    }
  }
  close_to(cx, 1)
  { head: sc.head, eol: sc.eol, doc: close_frame(cx.stack[0]) }
}

///|
fn close_frame(fr : Frame) -> Node {
  {
    id: fr.id,
    form: fr.form,
    label: fr.label,
    implied: fr.implied,
    folded: fr.folded,
    side: fr.side,
    body: fr.body,
    children: fr.kids,
  }
}

///|
fn top(cx : Ctx) -> Frame {
  cx.stack[cx.stack.length() - 1]
}

///|
/// 深さ d まで閉じる（stack の長さを d にする）。
fn close_to(cx : Ctx, d : Int) -> Unit {
  while cx.stack.length() > d && cx.stack.length() > 1 {
    let fr = cx.stack.unsafe_pop()
    top(cx).kids.push(close_frame(fr))
  }
}

///|
/// 骨格を 1 つ積む。
fn push_skel(cx : Ctx, want : Int, form : Form, label : String) -> Unit {
  let mut d = if want < 1 { 1 } else { want }
  // 項目は相対記法なので飛べない。飛んで見えたら いま開いている枝の子にする
  if form is Item && d > cx.stack.length() {
    d = cx.stack.length()
  }
  close_to(cx, d)
  push_frame(cx, form, label, false)
}

///|
/// 1 つ積む。
fn push_frame(cx : Ctx, form : Form, label : String, implied : Bool) -> Unit {
  cx.stack.push({
    id: cx.next_id,
    form,
    label,
    implied,
    side: Right,
    folded: false,
    body: [],
    kids: [],
  })
  cx.next_id = cx.next_id + 1
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected: `fmt` は EXIT=0。`test` は `… failed: 0.`（EXIT=0）で、新規 3 本が緑になり、既存は 1 本も落ちない（`Frame.implied` はまだ常に false）。**T2 ぶんの累計は 14 本。**

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/build.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/build_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ かたまりの深さから木を組む"
```

---

## Task 13: 深さの飛びから implied を導く（見出しは項目を閉じる）

**Files:**
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/build.mbt`（`push_skel` を丸ごと置き換え）
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/build_wbtest.mbt`（末尾へ追記）

**Interfaces:**
- Consumes: `push_skel` / `push_frame` / `close_to` / `top`（Task 12）
- Produces: 正誤表 §A-3 の不変条件 3（Item の下に Heading は無い）・5〜9 を満たす implied を含む `Ast`（T1 の `check` と T5 の `normalize` が前提にする）

**カバーする要件:** R022・R023（implied は id を持つ普通のノード）、R029・R030（最初の `#` より前の深い見出し）、R039（単調性）、R041・R042、R052（深さ = level）、R057（項目 root）。カタログ C6・**C17**。仕様 §2 の改訂（裁定 A）。

- [ ] **Step 1: 失敗するテストを書く**

`build_wbtest.mbt` の末尾に足す:

```moonbit
///|
test "深さの飛びは implied が埋める" {
  // R022 R052 C6
  assert_eq(
    built_sig([
      skel(1, Heading, "r"),
      skel(2, Heading, "a"),
      skel(4, Heading, "b"),
    ]),
    "head:-\nlf\n[H[Hr[Ha[H~[Hb]]]]]",
  )
}

///|
test "最初の # より前の深い見出しは implied root の下に入る" {
  // R029 R030（特例ではなく level 0 との段差の帰結）
  assert_eq(
    built_sig([skel(2, Heading, "a"), skel(2, Heading, "b")]),
    "head:-\nlf\n[H[H~[Ha][Hb]]]",
  )
}

///|
test "implied の前に見出しの兄弟は居ない" {
  // 正誤表 §A-3 不変条件 8（裁定 B で一般化 — 見出しが居ると飛びを飲み込むので
  // 書いても読み戻せない。違反は `implied の前に見出しが居る: <id>`）
  assert_eq(
    built_sig([
      skel(1, Heading, "p"),
      skel(3, Heading, "x"),
      skel(2, Heading, "y"),
    ]),
    "head:-\nlf\n[H[Hp[H~[Hx]][Hy]]]",
  )
}

///|
test "implied は id を持つ普通のノードである" {
  // R023 R020
  let ast = build({
    head: None,
    eol: Lf,
    chunks: [skel(1, Heading, "r"), skel(3, Heading, "b")],
  })
  assert_eq(ast.doc.children[0].children[0].id, 3)
  assert_eq(ast.doc.children[0].children[0].children[0].id, 4)
}

///|
test "項目 root のあとの深い見出しは implied root の下に入る" {
  // R039 R042 R057 C17。仕様 §2「項目の後ろに列 0 で書かれた見出しは、その項目の
  // 子にはならない（md では見出しがリストを終わらせる）。読みは開いている項目を
  // すべて閉じ、直近の見出し（または doc）に付ける。level の飛びはそこで
  // implied が埋める」。Item の下に Heading は置けない（不変条件 3）
  assert_eq(
    built_sig([skel(1, Item, "a"), skel(2, Heading, "h")]),
    "head:-\nlf\n[H[Ia][H~[Hh]]]",
  )
}

///|
test "項目 root のあとの `#` は素直に root になる" {
  // C17 の対。閉じたあと深さ 1 が空くので implied は要らない
  assert_eq(
    built_sig([skel(1, Item, "a"), skel(1, Heading, "h")]),
    "head:-\nlf\n[H[Ia][Hh]]",
  )
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected（正誤表 §F-3 — コンパイルは通り、**値の差で落ちる**）:

> `Total tests: N, passed: N-5, failed: 5.`（EXIT=2）。Task 12 の `push_skel` は飛びを埋めず、見出しが来ても項目を閉じないので、深さが 1 段浅い木や、見出しが項目の子になった木が出る。落ちるのは新規 6 本のうち 5 本:
>
> - 「深さの飛びは implied が埋める」→ `"head:-\nlf\n[H[Hr[Ha[Hb]]]]"`（`~` が無い）
> - 「最初の # より前の深い見出しは implied root の下に入る」→ `"head:-\nlf\n[H[Ha[Hb]]]"`（飛びを埋めないので a が深さ 1 に落ち、b がその子になる）
> - 「implied の前に見出しの兄弟は居ない」→ `"head:-\nlf\n[H[Hp[Hx][Hy]]]"`
> - 「implied は id を持つ普通のノードである」→ `ast.doc.children[0].children[0].children[0]` が存在せず添字が範囲外で落ちる
> - 「項目 root のあとの深い見出しは implied root の下に入る」→ `"head:-\nlf\n[H[Ia[Hh]]]"`（見出しが項目の子になっている。**これが再査読 3 の致命 R039**）
>
> **「項目 root のあとの `#` は素直に root になる」だけは PASS する**（深さ 1 の見出しは `close_to(1)` が項目を閉じるので、この時点でも期待どおりになる） — Step 3 で足す「項目を閉じるループ」がこの素直な形を壊さないことを見張る回帰の網である。

- [ ] **Step 3: 最小の実装を書く**

`build.mbt` の `push_skel` を丸ごと置き換える:

```moonbit
///|
/// 骨格を 1 つ積む。深さの飛びは implied（見出しだけ）が埋める。
fn push_skel(cx : Ctx, want : Int, form : Form, label : String) -> Unit {
  let mut d = if want < 1 { 1 } else { want }
  // 項目は相対記法なので飛べない。飛んで見えたら いま開いている枝の子にする
  if form is Item && d > cx.stack.length() {
    d = cx.stack.length()
  }
  close_to(cx, d)
  // 見出しは絶対記法で、項目の領土の外に居る（領土の中の見出しは scan が
  // Opaque にする）。よって開いている項目は全部閉じる — Item の下に Heading は
  // 置けない（単調性）。scan の items.clear() と対になる処理である
  if form is Heading {
    while cx.stack.length() > 1 && top(cx).form is Item {
      close_to(cx, cx.stack.length() - 1)
    }
  }
  while cx.stack.length() < d {
    push_frame(cx, Heading, "", true)
  }
  push_frame(cx, form, label, false)
}
```

これで `- a` + `## h` は「項目 a を閉じる → 深さ 1 が空くので implied root を立てる → h を深さ 2 へ」となり、`doc.children = [a(Item), implied(1)[h]]`（順序法則も満たす）になる。**level が 2 のまま保存される**ので R001 も守られ、serialize は `- a` / 空行 / `## h` を書き戻すので法則 1・2 も立つ。

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected: `fmt` は EXIT=0。`test` は `… failed: 0.`（EXIT=0）で、Step 2 の 5 本が緑に変わり、6 本目（「項目 root のあとの `#` は素直に root になる」）は緑のまま、既存は 1 本も落ちない。**T2 ぶんの累計は 20 本。**

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/build.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/build_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ 深さの飛びから implied を導き、見出しで項目を閉じる"
```

---

## Task 14: 中身と区切りの帰属（領土の規則・飾りとトグルの裁定）

**Files:**
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/build.mbt`（`Ctx` の置き換え・`build` の初期値に 1 行・`Body` と `Break` の腕の差し替え・末尾に 3 関数）
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/build_wbtest.mbt`（先頭の道具と末尾へ追記）

**Interfaces:**
- Consumes: `top` / `close_to` / `push_skel`（Task 12・13）、`Kind::Body(Block)` / `Kind::Break(Bool)`（T1 `scan.mbt`）
- Produces: `fn owner(cx : Ctx, d : Int) -> Frame` / `fn next_is_slot(cs : Array[Chunk], j : Int) -> Bool` / `fn in_deep_item(cx : Ctx) -> Bool`、`Ctx.pending`（Task 15 の側が食う）、テストの道具 `fn body(d : Int, b : Block) -> Chunk` / `fn brk(d : Int, hard : Bool) -> Chunk`

**カバーする要件:** R011・R012（body は骨格行の後・最初の子の前）、R040（領土）、R056（木と木の間の区切り）、R080・R081（2 チャンネル）、R191。カタログ C7・C15。

- [ ] **Step 1: 失敗するテストを書く**

`build_wbtest.mbt` の先頭の道具に足す（`skel` の下）:

```moonbit
///|
fn body(d : Int, b : Block) -> Chunk {
  { depth: d, kind: Body(b) }
}

///|
/// hard = true は「空白を 1 つも含まない `---`」だけ（トグル候補）。
/// `- - -` も `***` も `___` も hard = false（必ず飾り。裁定 2）。
fn brk(d : Int, hard : Bool) -> Chunk {
  { depth: d, kind: Break(hard) }
}
```

末尾に足す:

```moonbit
///|
test "中身は直前の見出しに付く（字下げは見出しを閉じない）" {
  // R011 R012
  assert_eq(
    built_sig([
      skel(1, Heading, "r"),
      skel(2, Heading, "a"),
      skel(3, Item, "x"),
      body(0, Opaque("text")),
    ]),
    "head:-\nlf\n[H[Hr[Ha|o:text[Ix]]]]",
  )
}

///|
test "中身は領土の深さまで項目を閉じてから付く" {
  // R040 C15（字下げを飲み込んでいる いちばん内側のコンテナが持ち主）
  assert_eq(
    built_sig([skel(1, Item, "a"), skel(2, Item, "b"), body(1, Opaque("text"))]),
    "head:-\nlf\n[H[Ia|o:text[Ib]]]",
  )
}

///|
test "次が中身なら区切りは飾りになる" {
  // C7 R191（後ろに本文が続く `---` は body の飾り）
  assert_eq(
    built_sig([
      skel(1, Heading, "r"),
      skel(2, Heading, "a"),
      body(0, Opaque("text")),
      brk(0, true),
      body(0, Opaque("more")),
      skel(2, Heading, "b"),
    ]),
    "head:-\nlf\n[H[Hr[Ha|o:text|rule|o:more][Hb]]]",
  )
}

///|
test "木と木の間の区切りは飾りになる" {
  // R056（doc 直下の隙間の区切りは無意味）
  assert_eq(
    built_sig([skel(1, Heading, "r1"), brk(0, true), skel(1, Heading, "r2")]),
    "head:-\nlf\n[H[Hr1|rule][Hr2]]",
  )
}

///|
test "空白を含む区切りと *** は常に飾り" {
  // R081 裁定 2（`- - -` は CommonMark どおり飾りの水平線）
  assert_eq(
    built_sig([skel(1, Heading, "r"), brk(0, false), skel(2, Heading, "a")]),
    "head:-\nlf\n[H[Hr|rule[Ha]]]",
  )
}

///|
test "深さ 2 の骨格の直前の区切りは body に残らない" {
  // R080（トグルは側の列になる。飾りではない）
  assert_eq(
    built_sig([skel(1, Heading, "r"), brk(0, true), skel(2, Heading, "a")]),
    "head:-\nlf\n[H[Hr[Ha]]]",
  )
}

///|
test "より深い項目の領土の区切りは飾り" {
  // C15 備考（より深い位置の `---` は子の body の飾り）
  assert_eq(
    built_sig([
      skel(1, Item, "center"),
      skel(2, Item, "a"),
      brk(2, true),
      skel(2, Item, "c"),
    ]),
    "head:-\nlf\n[H[Icenter[Ia|rule][Ic]]]",
  )
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected（正誤表 §F-3 — コンパイルは通り、**値の差で落ちる**）:

> `Total tests: N, passed: N-6, failed: 6.`（EXIT=2）。Task 12 の `build` は `Body` と `Break` を読み捨てるので、`|o:text` も `|rule` も 1 つも木に入らない（例: 「次が中身なら区切りは飾りになる」は `"head:-\nlf\n[H[Hr[Ha][Hb]]]"` が出る）。落ちるのは新規 7 本のうち 6 本。**「深さ 2 の骨格の直前の区切りは body に残らない」だけは偶然 PASS する**（読み捨てても結果が同じ）。

- [ ] **Step 3: 最小の実装を書く**

**(a) `build.mbt` の `Ctx` を丸ごと置き換える:**

```moonbit
///|
/// 組み立ての状態。stack の索引がそのまま深さ（stack[0] = doc）。
priv struct Ctx {
  stack : Array[Frame]
  mut next_id : Int
  mut pending : Int // まだスロットに当てていないトグルの本数
}
```

**(b) `build` の `cx` の初期値に 1 行足す**（`next_id: 2,` の次の行）:

```moonbit
    pending: 0,
```

**(c) `build` の `Body(_)` の腕を差し替える:**

```moonbit
      Body(b) => {
        owner(cx, ch.depth).body.push(b)
        i = i + 1
      }
```

**(d) `build` の `Break(_)` の腕を差し替える**（連なりを先に測ってから、次のかたまりで帰属を決める。**`owner` を先に呼ぶ順序が本質** — 領土を閉じた後の stack を `in_deep_item` が見る）:

```moonbit
      Break(hard) =>
        if hard {
          let mut j = i
          while j < cs.length() && cs[j].kind is Break(true) {
            j = j + 1
          }
          let ow = owner(cx, ch.depth)
          if next_is_slot(cs, j) && !in_deep_item(cx) {
            cx.pending = cx.pending + (j - i)
          } else {
            for k = i; k < j; k = k + 1 {
              ow.body.push(Rule)
            }
          }
          i = j
        } else {
          owner(cx, ch.depth).body.push(Rule)
          i = i + 1
        }
```

**(e) `build.mbt` の末尾に足す:**

```moonbit
///|
/// 中身の行の持ち主。字下げが閉じるのは項目の領土だけ（見出しは領土を持たない）。
fn owner(cx : Ctx, d : Int) -> Frame {
  while cx.stack.length() - 1 > d &&
        cx.stack.length() > 1 &&
        top(cx).form is Item {
    close_to(cx, cx.stack.length() - 1)
  }
  top(cx)
}

///|
/// 連なりの直後が「深さ 2 の骨格」か。
fn next_is_slot(cs : Array[Chunk], j : Int) -> Bool {
  if j >= cs.length() {
    return false
  }
  match cs[j].kind {
    Skel(_, _) => cs[j].depth == 2
    Body(_) => false
    Break(_) => false
    Fold(_) => false
  }
}

///|
/// いま深さ 2 以上の項目の領土に居るか（そこの `---` は root のスロットの
/// 変わり目ではなく、その項目の中身の飾りである）。**owner を通した後に見る**。
fn in_deep_item(cx : Ctx) -> Bool {
  cx.stack.length() - 1 > 1 && top(cx).form is Item
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected: `fmt` は EXIT=0。`test` は `… failed: 0.`（EXIT=0）で、Step 2 の 6 本が緑に変わり、既存は 1 本も落ちない。**T2 ぶんの累計は 27 本。**

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/build.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/build_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ 中身と区切りの持ち主を領土で決める"
```

---

## Task 15: 側の割り当て（先頭トグルとパリティ、implied は側を持たない）

**Files:**
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/build.mbt`（`Ctx` の置き換え・`build` の初期値に 1 行・`push_frame` を丸ごと置き換え）
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/build_wbtest.mbt`（末尾へ追記）

**Interfaces:**
- Consumes: `Ctx.pending`（Task 14）、`push_frame`（Task 12）、`pub fn check(ast : Ast) -> Array[String]`（T1 `ast.mbt`）
- Produces: 深さ 2 のノード**で、かつ骨格行を持つもの**だけが意味を持つ `Node.side`（正誤表 §A-3 不変条件 10・**11**。T3 の serialize が側の列から区切りを導出する入力）

**カバーする要件:** R032（implied root のスロット）、R057・R058（項目 root の中身の列のトグル）、R080（変わり目にちょうど 1 本）、R082・R185（側の列）、R207。正誤表 §A-3 不変条件 10・11（裁定 1）。カタログ C4・C15。

- [ ] **Step 1: 失敗するテストを書く**

`build_wbtest.mbt` の末尾に足す:

```moonbit
///|
test "先頭のトグルは左開始を表す" {
  // C4 R082 R185（側の列 (左, 右)）
  assert_eq(
    built_sig([
      skel(1, Heading, "r"),
      brk(0, true),
      skel(2, Heading, "a"),
      brk(0, true),
      skel(2, Heading, "b"),
    ]),
    "head:-\nlf\n[H[Hr[H<a][Hb]]]",
  )
}

///|
test "トグルは変わり目なので、以降のスロットに効き続ける" {
  // R080（側の変わり目にちょうど 1 本）
  assert_eq(
    built_sig([
      skel(1, Heading, "r"),
      skel(2, Heading, "a"),
      brk(0, true),
      skel(2, Heading, "b"),
      skel(2, Heading, "c"),
    ]),
    "head:-\nlf\n[H[Hr[Ha][H<b][H<c]]]",
  )
}

///|
test "項目 root の中身の列に置いた区切りはトグル" {
  // C15 R057 R058 R207
  assert_eq(
    built_sig([
      skel(1, Item, "center"),
      skel(2, Item, "a"),
      skel(2, Item, "b"),
      brk(1, true),
      skel(2, Item, "c"),
    ]),
    "head:-\nlf\n[H[Icenter[Ia][Ib][I<c]]]",
  )
}

///|
test "implied root の木でも側は深さ 2 のスロットに当たる" {
  // R032
  assert_eq(
    built_sig([brk(0, true), skel(2, Heading, "a")]),
    "head:-\nlf\n[H[H~[H<a]]]",
  )
}

///|
test "深さ 2 以外のノードは必ず右" {
  // 正誤表 §A-3 不変条件 10
  assert_eq(
    built_sig([
      skel(1, Heading, "r"),
      brk(0, true),
      skel(2, Heading, "a"),
      skel(3, Heading, "d"),
    ]),
    "head:-\nlf\n[H[Hr[H<a[Hd]]]]",
  )
}

///|
test "飛びで生まれた implied は側を持たない" {
  // 裁定 1・正誤表 §A-3 不変条件 11（飛びには側を書く場所が無い）
  let chunks = [brk(0, true), skel(2, Heading, "a"), skel(4, Heading, "b")]
  assert_eq(built_sig(chunks), "head:-\nlf\n[H[H~[H<a[H~[Hb]]]]]")
  assert_eq(check(build({ head: None, eol: Lf, chunks })).length(), 0)
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected（正誤表 §F-3 — コンパイルは通り、**値の差で落ちる**）:

> `Total tests: N, passed: N-6, failed: 6.`（EXIT=2）。Task 14 の `push_frame` は側を配らないので `<` が 1 つも付かず、**新規 6 本すべてが値の差で落ちる**（例: 「先頭のトグルは左開始を表す」は `"head:-\nlf\n[H[Hr[Ha][Hb]]]"`、「飛びで生まれた implied は側を持たない」は `"head:-\nlf\n[H[H~[Ha[H~[Hb]]]]]"` が出る）。ただし「飛びで生まれた implied は側を持たない」の 2 本目の assert（`check(...).length() == 0`）はこの時点でも通っており、**Step 3 の実装が不変条件 11 を壊さないことを見張る回帰の網**として置いてある。

- [ ] **Step 3: 最小の実装を書く**

**(a) `build.mbt` の `Ctx` を丸ごと置き換える:**

```moonbit
///|
/// 組み立ての状態。stack の索引がそのまま深さ（stack[0] = doc）。
priv struct Ctx {
  stack : Array[Frame]
  mut next_id : Int
  mut pending : Int // まだスロットに当てていないトグルの本数
  mut flips : Int // いまの root のスロット列で数えた変わり目の総数
}
```

**(b) `build` の `cx` の初期値に 1 行足す**（`pending: 0,` の次の行）:

```moonbit
    flips: 0,
```

**(c) `push_frame` を丸ごと置き換える:**

```moonbit
///|
/// 1 つ積む。側は深さ 2（root 直下のスロット）だけが意味を持つ。
/// **implied には側を配らない**（裁定 1・不変条件 11 — 飛びには側を書く綴りが
/// 無いので、持たせると serialize が書けず法則 2 が破れる）。トグルは
/// pending に残り、次に骨格行を持つスロットへ効く。
fn push_frame(cx : Ctx, form : Form, label : String, implied : Bool) -> Unit {
  let depth = cx.stack.length()
  if depth == 1 {
    cx.flips = cx.pending
    cx.pending = 0
  }
  let mut side : Side = Right
  if depth == 2 && !implied {
    cx.flips = cx.flips + cx.pending
    cx.pending = 0
    if cx.flips % 2 == 1 {
      side = Left
    }
  }
  cx.stack.push({
    id: cx.next_id,
    form,
    label,
    implied,
    side,
    folded: false,
    body: [],
    kids: [],
  })
  cx.next_id = cx.next_id + 1
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected: `fmt` は EXIT=0。`test` は `… failed: 0.`（EXIT=0）で、Step 2 の 6 本すべてが緑に変わり（「飛びで生まれた implied は側を持たない」は `<` が `a` にだけ付き、`check` は空を返し続ける）、既存も 1 本も落ちない。**T2 ぶんの累計は 33 本。**

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/build.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/build_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ 区切りの本数から root 直下のスロットの側を決める"
```

---

## Task 16: 畳みの対応付け（details のネスト）

**依存: T1 Task 1 のコミット `feat: ✨ 新 core のパッケージと文書の木の型を置く` の後に着手する**（`spell.mbt` の `fold_open` / `fold_close` を読むため。**`spell.mbt` は T1 の所有物なので作らない・触らない**）。

**Files:**
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/build.mbt`（`Frame` の `folded` を `mut` に・`Ctx` の置き換え・`build` の初期値に 1 行・`Fold` の腕の差し替え・末尾に `fold_at`）
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/build_wbtest.mbt`（先頭の道具と末尾へ追記）

**Interfaces:**
- Consumes: `owner`（Task 14）、`let fold_open : String` / `let fold_close : String`（**T1 Task 1 の `spell.mbt`**）
- Produces: `fn fold_at(cx : Ctx, d : Int, open : Bool) -> Unit`、`Node.folded`（T3 の serialize が details を書く入力）、テストの道具 `fn fold(d : Int, open : Bool) -> Chunk`

**カバーする要件:** R001（意味は 1 ビットも失わない）、R083・R084（骨格行は外、本文と子だけ包む）、R087・R195（入れ子の畳み）。正誤表 §A-3 不変条件 1（doc は folded=false）。カタログ C8。

- [ ] **Step 1: 失敗するテストを書く**

`build_wbtest.mbt` の先頭の道具に足す（`brk` の下）:

```moonbit
///|
fn fold(d : Int, open : Bool) -> Chunk {
  { depth: d, kind: Fold(open) }
}
```

末尾に足す（**`<` は指紋で `\<` に逃げる** — 正誤表 §A-4 の `esc` は `\` `|` `[` `]` `~` `^` `<` を逃がす。MoonBit のソース上は `\\<` と綴る）:

```moonbit
///|
test "details は直前の骨格のノードを畳む" {
  // R083 R084 C8（骨格行は外、本文と子だけ包む）
  assert_eq(
    built_sig([
      skel(1, Heading, "r"),
      skel(2, Heading, "a"),
      skel(3, Heading, "b"),
      fold(0, true),
      skel(4, Heading, "c"),
      fold(0, false),
    ]),
    "head:-\nlf\n[H[Hr[Ha[H^b[Hc]]]]]",
  )
}

///|
test "details の入れ子は両方に効く" {
  // R087 R195 C8（内側の畳みは吸収されず残る）
  assert_eq(
    built_sig([
      skel(1, Heading, "r"),
      skel(2, Heading, "a"),
      fold(0, true),
      skel(3, Heading, "b"),
      fold(0, true),
      skel(4, Heading, "c"),
      fold(0, false),
      fold(0, false),
    ]),
    "head:-\nlf\n[H[Hr[H^a[H^b[Hc]]]]]",
  )
}

///|
test "対を欠く閉じタグは逐語で残る" {
  // R001（意味は 1 ビットも失わない）。`<` は sig が逃がす（T1 Task 2 の esc）
  assert_eq(
    built_sig([skel(1, Heading, "r"), fold(0, false)]),
    "head:-\nlf\n[H[Hr|o:\\</details>]]",
  )
}

///|
test "文書に畳みは無いので、doc 直下の開きタグは逐語で残る" {
  // 正誤表 §A-3 不変条件 1（doc は folded=false）。`<` は sig が逃がす
  assert_eq(
    built_sig([fold(0, true), skel(1, Heading, "r")]),
    "head:-\nlf\n[H|o:\\<details>[Hr]]",
  )
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected（正誤表 §F-3 — コンパイルは通り、**値の差で落ちる**）:

> `Total tests: N, passed: N-4, failed: 4.`（EXIT=2）。Task 12 の `Fold(_)` の腕が読み飛ばしているので `^` も `o:\<details>` も出ない（「details は直前の骨格のノードを畳む」は `"head:-\nlf\n[H[Hr[Ha[Hb[Hc]]]]]"`、「対を欠く閉じタグは逐語で残る」は `"head:-\nlf\n[H[Hr]]"` が出る）。新規 4 本すべてが FAIL。
>
> **注**: 逐語で残るタグの期待値に `\` が入っているのは指紋の逃がしである（`esc` が `<` を `\<` にする。正誤表 §A-4）。実装が `Opaque("</details>")` を作れていれば指紋は `o:\</details>` になる — **`\` を取ってはならない**（取ると実装が正しくても落ちる）。

- [ ] **Step 3: 最小の実装を書く**

**(a) `build.mbt` の `Frame` を丸ごと置き換える**（`folded` を `mut` にする。**この `mut` は同じパッケージ内の `fold_at` が書くので `Error: [0015] unused_mut` にはならない**）:

```moonbit
///|
/// 組み立て中のノード 1 つ。木は不変なので、閉じるときに Node へ畳む。
priv struct Frame {
  id : Int
  form : Form
  label : String
  implied : Bool
  side : Side
  mut folded : Bool
  body : Array[Block]
  kids : Array[Node]
}
```

**(b) `Ctx` を丸ごと置き換える:**

```moonbit
///|
/// 組み立ての状態。stack の索引がそのまま深さ（stack[0] = doc）。
priv struct Ctx {
  stack : Array[Frame]
  mut next_id : Int
  mut pending : Int // まだスロットに当てていないトグルの本数
  mut flips : Int // いまの root のスロット列で数えた変わり目の総数
  mut folds : Int // 開いている details の数
}
```

**(c) `build` の `cx` の初期値に 1 行足す**（`flips: 0,` の次の行）:

```moonbit
    folds: 0,
```

**(d) `build` の `Fold(_)` の腕を差し替える:**

```moonbit
      Fold(open) => {
        fold_at(cx, ch.depth, open)
        i = i + 1
      }
```

**(e) `build.mbt` の末尾に足す:**

```moonbit
///|
/// 畳みの対応付け。対を欠くタグは逐語の Opaque に落とす（意味を捨てない）。
/// doc に畳みは無い（不変条件 1）ので、doc 直下の開きタグも逐語で残す。
fn fold_at(cx : Ctx, d : Int, open : Bool) -> Unit {
  let ow = owner(cx, d)
  if open {
    if cx.stack.length() == 1 {
      ow.body.push(Opaque(fold_open))
    } else {
      ow.folded = true
      cx.folds = cx.folds + 1
    }
  } else if cx.folds > 0 {
    cx.folds = cx.folds - 1
  } else {
    ow.body.push(Opaque(fold_close))
  }
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected: `fmt` は EXIT=0。`test` は `… failed: 0.`（EXIT=0）で、Step 2 の 4 本が緑に変わり、既存は 1 本も落ちない。**T2 ぶんの累計は 37 本。**

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/build.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/build_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ details の開閉を対応付けて畳みを読む"
```

---

## Task 17: 読みの入口と、通しの固定テスト

**依存: T1 Task 9 のコミット `feat: ✨ 項目の領土・setext・summary の裁定を仕上げる` の後に着手する**（ここで初めて `scan` を通すため）。

**Files:**
- Create: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/parse.mbt`
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/build_wbtest.mbt`（先頭の道具と末尾へ追記）

**Interfaces:**
- Consumes: `pub fn scan(md : String) -> Scan`（T1 `scan.mbt`）、`pub fn build(sc : Scan) -> Ast`（Task 12〜16）、`pub fn check(ast : Ast) -> Array[String]` / `pub fn sig(ast : Ast) -> String`（T1 `ast.mbt`）
- Produces: `pub fn parse(md : String) -> Ast` — **T3 の法則テスト・T4 の `wire.mbt`（`sig_of` / `format_of` / `check_of` / `tree_of` / `apply_op`）・T5 の `reflect` がこれ 1 本を通る**。テストの道具 `fn md_sig(md : String) -> String`

**カバーする要件:** R010・R093・R105・R108・R109・R189・R200、R039・R042・R057・R058・R206・R207、R084・R087。正誤表 §A-3 不変条件 1〜11（`build` は `check` を満たす木しか作らない）。カタログ C6・C8・C9・C11・C15・C4・**C17**。

- [ ] **Step 1: 失敗するテストを書く**

`build_wbtest.mbt` の先頭の道具に足す（`built_sig` の下）:

```moonbit
///|
fn md_sig(md : String) -> String {
  sig(parse(md))
}
```

末尾に足す（**ここから先は T1 の `scan` を通る。落ちたら `build` ではなく「T1 の `scan` への前提」（この群の概要）のどれが食い違ったかを疑うこと**）:

```moonbit
///|
test "C6: 階層の飛びは implied として読まれる" {
  // C6 R189
  assert_eq(md_sig("# r\n\n## a\n\n#### b\n"), "head:-\nlf\n[H[Hr[Ha[H~[Hb]]]]]")
}

///|
test "C11: frontmatter は封筒として頭に載る" {
  // C11 R010 R108 R200
  assert_eq(
    md_sig("---\nimage-folder: img\n---\n\n# r\n\n## a\n"),
    "head:---\\nimage-folder: img\\n---\nlf\n[H[Hr[Ha]]]",
  )
}

///|
test "C15: 全リストの木と、中身の列のトグル" {
  // C15 R057 R058 R206 R207
  assert_eq(
    md_sig("- center\n\n  - a\n\n  - b\n\n  ---\n\n  - c\n"),
    "head:-\nlf\n[H[Icenter[Ia][Ib][I<c]]]",
  )
}

///|
test "C8: details は骨格行の外にあり、内側の畳みも残る" {
  // C8 R084 R087
  assert_eq(
    md_sig("# r\n\n## a\n\n### b\n\n<details>\n\n#### c\n\n</details>\n"),
    "head:-\nlf\n[H[Hr[Ha[H^b[Hc]]]]]",
  )
}

///|
test "頭でない先頭の --- は先頭トグルとして読まれる" {
  // R109 C4（frontmatter と裁定できなければ左開始）
  assert_eq(md_sig("---\n\n## a\n"), "head:-\nlf\n[H[H~[H<a]]]")
}

///|
test "CRLF の流儀は木ではなくダイヤルに載る" {
  // R093
  assert_eq(md_sig("# r\r\n\r\n## a\r\n"), "head:-\ncrlf\n[H[Hr[Ha]]]")
}

///|
test "読んだ木は不変条件を 1 つも破らない" {
  // 正誤表 §A-3 の 1〜11（T1 の check が見張る）
  assert_eq(check(parse("# r\n\n## a\n\n#### b\n")).length(), 0)
  assert_eq(check(parse("- center\n\n  - a\n\n  ---\n\n  - c\n")).length(), 0)
  assert_eq(check(parse("---\n\n## a\n\n### d\n")).length(), 0)
  assert_eq(
    check(parse("---\nk: v\n---\n\n# r\n\n<details>\n\n## a\n\n</details>\n")).length(),
    0,
  )
  // C17。項目 root のあとの見出しは項目の子にならず、implied root の下に入る
  //（不変条件 3 と、裁定 B で一般化した不変条件 8 の両方を満たす）
  assert_eq(check(parse("1. a\n\n## h\n")).length(), 0)
}

///|
test "先頭トグルと深さの飛びが重なっても implied は側を持たない" {
  // 裁定 1・正誤表 §A-3 不変条件 11
  assert_eq(
    md_sig("---\n\n## a\n\n#### b\n"),
    "head:-\nlf\n[H[H~[H<a[H~[Hb]]]]]",
  )
  assert_eq(check(parse("---\n\n## a\n\n#### b\n")).length(), 0)
}

///|
test "インデントコードは字下げを保ったまま Code に読まれる" {
  // R105 C9。scan が 4 スペースを落とすと block.mbt が Code と認定できない
  assert_eq(md_sig("# r\n\n    code\n"), "head:-\nlf\n[H[Hr|code:|code]]")
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected（正誤表 §F-1）: コンパイルが通らず、テストは 1 本も走らない。

```
Error: [4021]
The value identifier parse is unbound.
```

- [ ] **Step 3: 最小の実装を書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/parse.mbt` を作る:

```moonbit
///|
/// md を木にする。**この関数は決して書かない**（読みのサイクルは書き戻さない）。
/// id は文書順に 1 から振る（doc が 1）。
pub fn parse(md : String) -> Ast {
  build(scan(md))
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core
```
Expected: `fmt` は EXIT=0。新パッケージの `test` は `… failed: 0.`（EXIT=0）で、新規 9 本が緑になり、既存は 1 本も落ちない（**T2 ぶんの累計は 46 本**）。旧 core は `Total tests: 192, passed: 192, failed: 0.` のまま無傷。

落ちた場合、**直すのは `build` ではなく「T1 の `scan` への前提」（この群の概要）のどれが食い違ったか**である。次の 4 つを最初に疑う: ① `Chunk.depth` の定義（所属コンテナの深さか、直前の骨格の深さか）② 空行の落とし ③ `Body` の逐語の字下げ（コンテナの字下げは落とす／インデントコードの 4 スペースは残す — 「インデントコードは字下げを保ったまま Code に読まれる」が落ちたらこれ）④ 項目のあとの列 0 の見出しが `Skel(Heading, …)` で届いているか（`Body(Opaque)` で届くと C17 の 2 本が別の木になる）。失敗メッセージの期待値と実際値を逐語で写して T1 へ渡すこと。

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/parse.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/build_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ md を木にする入口を開ける"
```

---

## T2 が他へ渡すもの（申し送り）

| 渡すもの | 受け取る側 |
|---|---|
| `pub fn classify(text : String) -> Block`（本実装。`- - -` を含む水平線は `Rule`） | T1 の `scan` の `flush`（呼び出し側は無変更） |
| `pub fn build(sc : Scan) -> Ast` | T2 内部（`parse`）。他は `parse` を通る |
| `pub fn parse(md : String) -> Ast` | T3（法則テスト）／T4（`wire.mbt` の 5 本すべて）／T5（`reflect`） |
| `fn lines_of` / `fn join` / `fn trim` / `fn starts` / `fn ends`（`block.mbt` の道具） | T3 の `serialize` が再利用してよい（同じパッケージ内。**再定義しないこと**） |

- **`parse` が返す木は必ず `check` を満たす**（Task 17 の 2 本が見張る）。特に **implied は深さによらず `side = Right`**（裁定 1・不変条件 11）。T5 の `normalize` は「parse 直後の木は健全」を前提にしてよい
- **項目 root のあとの列 0 の見出しは、項目の子にならない**（裁定 A・仕様 §2・C17）。`push_skel` が見出しを積む前に開いている項目を全部閉じるので、`- a` + `## h` は `doc.children = [a(Item), implied(1)[h]]` になる。**T3 の serialize はこの木から `- a` / 空行 / `## h` を書き戻すこと**（implied は骨格行を書かないので、`h` は `##` で出る）。T4 のファズ（`gen_ast` が項目 root の後ろに見出し root を並べる形）もこの木を前提にしてよい
- **不変条件 8 は「implied ⇒ その前に見出しの兄弟が居ない」**（裁定 B）。違反メッセージは `implied の前に見出しが居る: <id>`。`build` はこの一般化された条件に依存している（`[a(Item), implied[h]]` を作る）ので、T1 の `check` と T5 の `spellable` が旧文言（「親の children の先頭」）のままだと Task 15・17 の `check(...).length() == 0` が落ちる
- **封筒の裁定には「開きの `---` の直後が空行でないこと」が要る**（裁定 E・仕様 §4）。T1 の `scan_head` がこの 1 条件を持つ前提だが、**T2 の期待値は 1 つも動かない** — Task 17 の「頭でない先頭の `---` は先頭トグルとして読まれる」（`---\n\n## a\n`）は閉じの `---` が無いので元から封筒ではなく、「C11: frontmatter は封筒として頭に載る」と Task 17 の `check(parse("---\nk: v\n---\n…"))` は 2 行目が空行でないので封筒のまま。条件が T1 側に無いと、serialize が書く「先頭トグル + もう 1 本のトグル」の文書（`---` / 空行 / `## a` / 空行 / `---` / 空行 / `## b`）で木が丸ごと head に飲まれる — **その形で落ちたら疑うのは `build` ではなく T1 の `scan_head`**
- **`- - -` は飾りの水平線**（裁定 2）。`scan` は `Break(false)`、`classify` は `Rule` を返す。旧 core の「前から箇条書き」方言は捨てた
- **区切りの帰属には正誤表 §A-8-④ に無い条件が 1 つ足してある**（「深さ 2 以上の項目の領土に居ないこと」）。C15 のより深い `---` を飾りにするために必要。T3 の serialize はこれと対称に書くこと — 深さ 2 のスロット列の変わり目にだけトグルを書き、より深い項目の body の `Rule` は `***` で書く
- **T2 は `scan_wbtest.mbt` を 1 バイトも触っていない**（裁定 5 により、`classify` の本実装は T1 の期待値に影響しない）。ただし **T1 Task 8 の C9 のテストが `chunks_sig` で書かれていること**が前提である（`body_text` でインデントコードを覗くと Task 11 で abort する）
