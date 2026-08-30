# T5 — 操作 3 種と反映 v0（Task 40〜50）

## この群の概要

**担当範囲**: `core/doc/edit.mbt` / `diff.mbt` / `reflect.mbt` / `form.mbt` / `op.mbt` / `delete.mbt` / `side.mbt` / `move.mbt` と、その `*_wbtest.mbt`、`test/doc-ops.test.ts`、そして `docs/superpowers/specs/2026-08-29-recover-reject.md` / `2026-08-29-kill-check.md`。

**前提（正誤表 A〜H に従う。逸脱しない）**

1. `core/doc/moon.pkg` / `ast.mbt` / `spell.mbt` は **T1 Task 1 の所有物**。T5 は **T1 Task 1 のコミット `feat: ✨ 新 core のパッケージと文書の木の型を置く` を待って着手する**。写して先に置くことはしない
2. 手で木を組む道具（`node` / `heading` / `item` / `slot` / `doc_of` / `ast_of` / `chain` / `chain_ast`）は **T1 Task 2 の `core/doc/fixture_wbtest.mbt`**。T5 は**自前で定義しない**。`tree_wbtest.mbt` は作らない
3. **T5 に許された唯一の他人のファイルへの書き込みは、Task 43 で `fixture_wbtest.mbt` の末尾に `done` / `rejected` の 2 関数を追記すること**だけ
4. `test/_doc.ts` は **T4 の所有物**。T5 は import するだけで、自前の型も自前の `applyEdits` も定義しない（正誤表 D-3 の export 名だけが存在する）
5. 綴りの規律: `pub type Path = Array[Int]`（`typealias` は無い）／否定は `!x`（`not(x)` は使わない）／ラベル付き引数の呼び出しは `=`／`derive(Show)` は使わない／`rev_in_place`・`to_owned`
6. `<REPO>` = `D:/1.atrium/mmm/.claude/worktrees/doc-model`。コマンドは `moon -C <REPO>/core …` / `git -C <REPO> …`、ファイルパスは絶対パス
7. **環境変数の前置き（`VAR=値 コマンド`）は使わない**（PowerShell で構文エラーになる）。ファズの回数は定数を書き替えて切り替える

**この群が従う統括の裁定**

- **裁定 A（単調性は parse の attach で強制する）**: `- a` + `## h` は `doc.children = [a(Item), implied(1)[h]]` になる。実装は T2 Task 13 の `push_skel`。T5 の木はすべて手で組むので、この裁定は T5 のテストの期待値を動かさない（動くのは T2・T4 のカタログ側）
- **裁定 B（implied の位置制約の一般化）**: 不変条件 8 は「implied ⇒ 親の children の先頭」ではなく「**implied ⇒ その前に見出しの兄弟が居ない**」。見出しが居ると飛びを吸収してしまうので綴れないが、**項目の後ろは吸収されないので置ける**。違反メッセージは `implied の前に見出しが居る: <id>`。T5 では **Task 44 の `spellable`** がこれに従う（`at == 0` ではない）
- **裁定 E（文書頭の `---` は「中身の形」でも裁定する）**: T1 Task 7 の `scan_head` に「**開き `---` の直後が空行なら封筒ではない**（先頭トグル・左開始と読む）」の 1 条件が入る。mmm が書く先頭トグルは空行規律により必ず直後が空行になるので、封筒と先頭トグルは綴りで分かれる。**T5 の期待値は 1 つも動かない** — Task 40〜47 の木はすべて手で組んで `sig` だけを見るので md を読まないし、`---` を含む md リテラルは T5 に 1 つも無い（Task 40 の diff / 反映のテストも `# r` と `## a` だけ）。影響が出るのは Task 48 のファズだけで、そこでは**落ちていたものが落ちなくなる**側に効く（先頭トグルを 2 本持つ木が封筒に飲まれなくなり、法則 1・2 が立つ）

**着手順**

```
T1 Task 1 ─┬─> Task 40(edit/diff) ──> Task 41(reflect) ※ T3 Task 26 も待つ
           ├─> Task 42(form) ─┬─> Task 44(normalize) ──> Task 45 ──> Task 46 ──> Task 47
           └─> Task 43(op)  ──┘
T1 Task 2(fixture_wbtest) ──> Task 41〜48 の全テスト
T5 Task 45・46・47 ──> T4 Task 37(操作の受け口) ──> Task 48(TS ファズ)
Task 48 ──> Task 49(回復と拒否の文書) ──> Task 50(殺す条件の判定と記録)
```

Task 40・42・43・44・45・46・47 は **T2 / T3 / T4 を 1 つも待たない**（手で組んだ `Ast` だけで完結する）。待つのは Task 41（`serialize` が要る）と Task 48（JS 出力と `test/_doc.ts` が要る）の 2 つだけなので、**40 → 42 → 43 → 44 → 45 → 46 → 47 を先に走らせ、41 と 48 を最後に回して合流する**のが最短である。

**テスト本数の読み方**: `moon -C <REPO>/core test -p mmm-app/core/doc` はパッケージ内の全テストを走らせるので、`Total tests: N` の N は他群の進捗で動く。各 Step 4 では **`failed: 0.` であることと、T5 の累計本数がそこに含まれること**を見る（T5 単独の累計を各タスクに明記した）。**`Total tests: 0` が出たら緑ではない — `-p` の綴りを疑う**（正誤表 E-1-2。`-p` を書き損じると黙って EXIT=0 になる）。

---

## Task 40: 反映の最小部品 — Edit を当てる／行境界で刈る

**Files:**
- Create: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/edit.mbt`
- Create: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/diff.mbt`
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/diff_wbtest.mbt`

**Interfaces:**
- Consumes: なし（文字列だけを見る。`ast.mbt` にも依存しない）。パッケージが存在すること（T1 Task 1 のコミット）だけが前提
- Produces:
  - `pub struct Edit { from : Int; to : Int; insert : String } derive(Eq, Debug)`
  - `pub fn apply(text : String, edits : Array[Edit]) -> String`
  - `pub fn diff(old : String, new_ : String) -> Array[Edit]`
  - （非公開）`fn at_line_start(s : String, i : Int) -> Bool`

- [ ] **Step 1: 失敗するテストを書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/diff_wbtest.mbt` を新規作成する。

```moonbit
// Edit・diff は private な行境界の刈り込みを含む。中の刻み方を直接見たいので whitebox テスト。

///|
/// 備考 R146 — 旧全文上の UTF-16 オフセットで置き換わる。
test "当てると置き換わる" {
  assert_eq(apply("abc", [Edit::{ from: 1, to: 2, insert: "XY" }]), "aXYc")
}

///|
/// 備考 R146 — 編集ゼロなら原文のまま。
test "当てるものが無ければ原文のまま" {
  assert_eq(apply("abc", []), "abc")
}

///|
/// 備考 R146 — v0 の diff は行境界で刈った 1 ハンクだけ。
test "差は行境界の 1 ハンクになる" {
  let old = "# r\n\n## a\n\n## b\n"
  let new_ = "# r\n\n## a2\n\n## b\n"
  assert_eq(diff(old, new_), [Edit::{ from: 5, to: 10, insert: "## a2\n" }])
}

///|
/// 備考 R208 / C15 — 無操作は無編集。
test "同じ全文なら差は空" {
  assert_eq(diff("# r\n", "# r\n").length(), 0)
}

///|
/// 備考 R148 — 当てて戻ることが自己検査の土台。
test "差を当てれば新全文になる" {
  let old = "# r\n\n## a\n\n## b\n"
  let new_ = "# r\n\n## b\n"
  assert_eq(apply(old, diff(old, new_)), new_)
}

///|
/// 備考 R146 — 行境界で刈るのはサロゲートペアを割らないためでもある。
test "CRLF の差も行境界で刈られる" {
  let old = "# r\r\n\r\n## a\r\n"
  let new_ = "# r\r\n\r\n## b\r\n"
  assert_eq(apply(old, diff(old, new_)), new_)
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc`
Expected: `Error: [4032]` / `The type Edit is undefined.` と `Error: [4021]` / `The value identifier apply is unbound.`（`diff` も同じく `[4021]`）。EXIT=1

- [ ] **Step 3: 最小の実装を書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/edit.mbt`:

```moonbit
// 反映が境界を渡すただ 1 つの形。オフセットは旧全文上の UTF-16 コード単位。

///|
/// 1 つの置き換え。
pub struct Edit {
  from : Int
  to : Int
  insert : String
} derive(Eq, Debug)

///|
/// 当てる。列は昇順・非重複でなければならない（自己検査とテストが使う）。
/// from / to は必ず行境界に落ちている（diff がそう刈る）ので、
/// `text[a:b]` がサロゲートペアの途中で切れることはない。
pub fn apply(text : String, edits : Array[Edit]) -> String {
  let sb = StringBuilder::new()
  let mut at = 0
  for e in edits {
    sb.write_string(text[at:e.from].to_owned())
    sb.write_string(e.insert)
    at = e.to
  }
  sb.write_string(text[at:text.length()].to_owned())
  sb.to_string()
}
```

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/diff.mbt`:

```moonbit
///|
/// 行の頭か（0 か、直前が改行）。
fn at_line_start(s : String, i : Int) -> Bool {
  i == 0 || s[i - 1].to_int() == 10
}

///|
/// 2 つの全文の差。**v0 は行境界で共通接頭辞・接尾辞を刈った 1 ハンクだけ**。
/// 仕様が「diff は間違えても壊れない部品（正しさは serialize が保証。最悪カーソルが跳ぶ）」と
/// 定めているので、行単位 Myers は後日ドロップインする。
/// 文字単位でなく行境界で刈るのは、サロゲートペアを割らないためでもある。
pub fn diff(old : String, new_ : String) -> Array[Edit] {
  if old == new_ {
    return []
  }
  let on = old.length()
  let nn = new_.length()
  let min = if on < nn { on } else { nn }
  let mut c = 0
  while c < min && old[c].to_int() == new_[c].to_int() {
    c = c + 1
  }
  let mut p = c
  while p > 0 && !at_line_start(old, p) {
    p = p - 1
  }
  let mut d = 0
  while d < min - c && old[on - 1 - d].to_int() == new_[nn - 1 - d].to_int() {
    d = d + 1
  }
  let mut q = on - d
  while q < on && !at_line_start(old, q) {
    q = q + 1
  }
  [Edit::{ from: p, to: q, insert: new_[p:nn - (on - q)].to_owned() }]
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc`
Expected: `Total tests: N, passed: N, failed: 0.`（EXIT=0）。**T5 の累計は 6 本**（`diff_wbtest.mbt` の 6 本）。N には他群のテストも含まれる。**`Total tests: 0` なら `-p` の綴りを疑う**

- [ ] **Step 5: コミット**

```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/edit.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/diff.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/diff_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ 反映の Edit と、行境界で刈る差を置く"
```

---

## Task 41: 反映 v0 — 全文正規形と自己検査

**Files:**
- Create: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/reflect.mbt`
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/diff_wbtest.mbt`（末尾に 3 本追記）

**Interfaces:**
- Consumes: `pub fn diff(old : String, new_ : String) -> Array[Edit]` / `pub fn apply(text : String, edits : Array[Edit]) -> String`（Task 40）、`pub fn serialize(ast : Ast) -> String`（T3 Task 26）、`Ast` / `Node` / `empty`（T1 Task 1）、`node` / `heading` / `ast_of`（T1 Task 2 の `fixture_wbtest.mbt`）
- Produces: `pub fn reflect(old : String, ast : Ast) -> Array[Edit]`

**依存**: このタスクは T3 の `serialize` が居ないとリンクできない。**T3 Task 26 のコミットを待って着手する**（依存図どおり `T3 Task 26 → T5 Task 41`）。T3 が未着なら Task 42 へ進み、後でここへ戻る。

- [ ] **Step 1: 失敗するテストを書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/diff_wbtest.mbt` の末尾に追記する。手で木を組む道具は `fixture_wbtest.mbt`（T1 Task 2）のものを使う — **自前で定義しない**。

```moonbit
///|
/// 備考 R208 / C15 — 読みだけでは md が 1 バイトも変わらない。
test "無操作は無編集" {
  let ast = ast_of([heading(2, "r", [heading(3, "a", [])])])
  assert_eq(reflect(serialize(ast), ast).length(), 0)
}

///|
/// 備考 R143 / R148 — 反映 v0 は「当てれば正規形になる」ことが全部。
test "反映を当てると全文が正規形になる" {
  let ast = ast_of([heading(2, "r", [heading(3, "a", [])])])
  let old = "# r\n\n## z\n"
  assert_eq(apply(old, reflect(old, ast)), serialize(ast))
}

///|
/// 備考 R143 — 空文書からでも当たる。
test "空の原文へも反映できる" {
  let ast = ast_of([heading(2, "r", [])])
  assert_eq(apply("", reflect("", ast)), serialize(ast))
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc`
Expected: `Error: [4021]` / `The value identifier reflect is unbound.`。EXIT=1

- [ ] **Step 3: 最小の実装を書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/reflect.mbt`:

```moonbit
///|
/// 反映 v0 = 全文正規形。旧全文と変異後の木から Edit の列を作る。
/// 自己検査（仕様 §5 段階 6）: 当てて反映文にならなければ全文置換 1 ハンクへ落とす
/// （正しさは保たれ、カーソルだけ跳ぶ）。すげ替え（v1）はこの上に足す。
pub fn reflect(old : String, ast : Ast) -> Array[Edit] {
  let want = serialize(ast)
  let edits = diff(old, want)
  if apply(old, edits) == want {
    edits
  } else {
    [Edit::{ from: 0, to: old.length(), insert: want }]
  }
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc`
Expected: `Total tests: N, passed: N, failed: 0.`（EXIT=0）。**T5 の累計は 9 本**。**`Total tests: 0` なら `-p` の綴りを疑う**

- [ ] **Step 5: コミット**

```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/reflect.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/diff_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ 反映 v0（全文正規形と自己検査）を置く"
```

---

## Task 42: form は行き先に従う

**Files:**
- Create: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/form.mbt`
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/form_wbtest.mbt`

**Interfaces:**
- Consumes: `Node` / `Form` / `pub fn promote(nd : Node, label : String) -> Node` / `pub fn sig(ast : Ast) -> String`（T1 Task 1）、`node` / `ast_of`（T1 Task 2）
- Produces:
  - `pub fn to_item(nd : Node) -> Node`
  - `pub fn refit(nd : Node, parent : Form, siblings : Array[Node], at : Int) -> Node`

**仕様 §4「form の決定」の ③④ は今回作らない**（欠落ではなく範囲）:

> 仕様 §4 は form を**新しく決める瞬間**の優先順位を ①単調性 → ②順序法則 → ③兄弟の真似 → ④policy（Hybrid(N)・リアルタイム推定）と定めるが、**③④ が要るのは `add` / `setForm` であり、どちらも範囲外**（正誤表 §A-5「範囲外」）。**move が ①② だけで足りるのは、動かす対象の form が既に決まっているから**である — ③④ は「まだ form が無いものに form を与える」規則で、既に持っているものを行き先に合わせ直す move には出番が無い。仕様 §5 が move に課す規則も「Item 親の下 → サブツリーごと Item ／ Heading 兄弟の間 → そのノードだけ Heading」の 2 つだけで閉じている。**policy は保存されない値なので、実装しないことで欠ける状態は存在しない。** ③④ は `add` / `setForm` と一緒に次の計画で入る。

- [ ] **Step 1: 失敗するテストを書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/form_wbtest.mbt` を新規作成する。

```moonbit
// 転形はノード単体に効く純関数。木に挿す前の姿を直接見たいので whitebox テスト。

///|
/// 備考 R122 / C14 — 単調性は下向きに伝播する。
test "Item のサブツリー化は下向きに伝播する" {
  let h = node(2, Heading, "a", [node(3, Heading, "b", [])])
  assert_eq(sig(ast_of([to_item(h)])), "head:-\nlf\n[H[Ia[Ib]]]")
}

///|
/// 備考 R044 — 親が Item なら問答無用で Item。
test "Item 親の下では form はサブツリーごと Item になる" {
  let fit = refit(node(2, Heading, "a", [node(3, Heading, "b", [])]), Item, [], 0)
  assert_eq(sig(ast_of([fit])), "head:-\nlf\n[H[Ia[Ib]]]")
}

///|
/// 備考 R045 / R123 / C14 — 順序法則。子は Item のままで合法。
test "Heading 兄弟の後ろへ挿すとそのノードだけ Heading になる" {
  let sibs = [node(3, Heading, "x", [])]
  let fit = refit(node(2, Item, "a", [node(4, Item, "b", [])]), Heading, sibs, 1)
  assert_eq(sig(ast_of([fit])), "head:-\nlf\n[H[Ha[Ib]]]")
}

///|
/// 備考 R041 — 後ろに Item が居る位置は Item の領土。
test "後ろに Item が居る位置へ挿すとサブツリーごと Item になる" {
  let sibs = [node(3, Item, "x", [])]
  let fit = refit(
    node(2, Heading, "a", [node(4, Heading, "b", [])]),
    Heading,
    sibs,
    0,
  )
  assert_eq(sig(ast_of([fit])), "head:-\nlf\n[H[Ia[Ib]]]")
}

///|
/// 備考 R121 — 転形は最小限。どれでもなければ触らない。
test "資格が無ければ form はそのまま" {
  let fit = refit(node(2, Item, "a", []), Heading, [], 0)
  assert_eq(sig(ast_of([fit])), "head:-\nlf\n[H[Ia]]")
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc`
Expected: `Error: [4021]` / `The value identifier to_item is unbound.` と `Error: [4021]` / `The value identifier refit is unbound.`。EXIT=1

- [ ] **Step 3: 最小の実装を書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/form.mbt`:

```moonbit
///|
/// サブツリーごと Item にする（単調性は下向きに伝播する）。
pub fn to_item(nd : Node) -> Node {
  let kids : Array[Node] = []
  for k in nd.children {
    kids.push(to_item(k))
  }
  // 飛びは絶対記法でしか綴れないので、Item 化はそのまま昇格の引き金になる。
  // promote は骨格行を持つノードには無害（同じ label を書き直すだけ）。
  { ..promote(nd, nd.label), form: Item, children: kids }
}

///|
/// 行き先に合わせて form を直す。`siblings` は**挿す前の**兄弟、`at` は挿す添字。
///   (a) 親が Item → サブツリーごと Item（単調性 = 仕様 §4 の ①）
///   (b) 挿す位置より前に Heading が居る → **そのノードだけ** Heading（順序法則 = ②）
///   (c) 挿す位置より後に Item が居る → サブツリーごと Item（順序法則の裏面）
///   (d) どれでもなければ form はそのまま
/// 仕様 §4 の ③兄弟の真似・④policy（Hybrid(N)・リアルタイム推定）は実装しない。
/// あれは form を**新しく決める**瞬間の規則で、add / setForm（範囲外）と一緒に
/// 次の計画で入る。move が ①② だけで足りるのは、動かす対象の form が既に
/// 決まっているからである。
pub fn refit(nd : Node, parent : Form, siblings : Array[Node], at : Int) -> Node {
  if parent is Item {
    return to_item(nd)
  }
  for i = 0; i < at; i = i + 1 {
    if siblings[i].form is Heading {
      return { ..nd, form: Heading }
    }
  }
  for i = at; i < siblings.length(); i = i + 1 {
    if siblings[i].form is Item {
      return to_item(nd)
    }
  }
  nd
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc`
Expected: `Total tests: N, passed: N, failed: 0.`（EXIT=0）。**T5 の累計は 14 本**。**`Total tests: 0` なら `-p` の綴りを疑う**

- [ ] **Step 5: コミット**

```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/form.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/form_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ form が行き先に従う規則（単調性・順序法則）を置く"
```

---

## Task 43: 操作の共通の道具 — 結果・道・頂点集合

**Files:**
- Create: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/op.mbt`
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/op_wbtest.mbt`
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/fixture_wbtest.mbt`（**末尾に `done` / `rejected` の 2 関数だけを追記**。他は 1 バイトも触らない）

**Interfaces:**
- Consumes: `Ast` / `Node` / `sig`（T1 Task 1）、`node` / `heading` / `ast_of`（T1 Task 2）
- Produces:
  - `pub enum Outcome { Done(Ast); Reject(Reject) }`
  - `pub enum Reject { Missing; Cycle; Ineligible } derive(Eq, Debug)`
  - `pub type Path = Array[Int]`
  - `pub fn path_of(ast : Ast, id : Int) -> Path?`
  - `pub fn tops(ast : Ast, ids : Array[Int]) -> Array[Path]`
  - （非公開・Task 44〜47 が使う）`seek` / `precedes` / `under` / `at_path` / `amend` / `pluck`
  - （`fixture_wbtest.mbt`）`fn done(o : Outcome) -> Ast` / `fn rejected(o : Outcome) -> Reject`

**名前の注意**（正誤表 C-1）: `before` は T3 `serialize.mbt` の引数名と衝突するので **`precedes`** に改名済み。`spell` はファイル名 `spell.mbt` と衝突するので Task 44 で **`spellable`** として置く。

- [ ] **Step 1: 失敗するテストを書く**

まず `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/fixture_wbtest.mbt` の**末尾に**追記する（`Outcome` はこのタスクで初めて存在するので、T1 Task 2 の時点では書けなかった 2 本）。

```moonbit
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

次に `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/op_wbtest.mbt` を新規作成する。

```moonbit
// 道と頂点集合は private な走査の結果。木の中を直接見たいので whitebox テスト。

///|
/// 備考 R112 — 文書そのものは空の道。
test "文書の道は空" {
  let ast = ast_of([heading(2, "r", [])])
  assert_eq(path_of(ast, 1), Some([]))
}

///|
/// 備考 R112 — 道は children の添字の列。
test "道は children の添字の列" {
  let ast = ast_of([heading(2, "r", [heading(3, "a", []), heading(4, "b", [])])])
  assert_eq(path_of(ast, 4), Some([0, 1]))
}

///|
/// 備考 R112 — 居ないものは道を持たない（拒否 Missing の根拠）。
test "居ない id は道を持たない" {
  let ast = ast_of([heading(2, "r", [])])
  assert_eq(path_of(ast, 99), None)
}

///|
/// 備考 R130 — 子孫の選択は祖先に吸収される。
test "頂点集合は子孫を祖先に吸収する" {
  let ast = ast_of([heading(2, "r", [heading(3, "a", [])])])
  assert_eq(tops(ast, [3, 2]), [[0]])
}

///|
/// 備考 R131 — 頂点集合は文書順に並ぶ。
test "頂点集合は文書順に並ぶ" {
  let ast = ast_of([heading(2, "r", [heading(3, "a", []), heading(4, "b", [])])])
  assert_eq(tops(ast, [4, 3]), [[0, 0], [0, 1]])
}

///|
/// 備考 R130 — 同じものを 2 回選んでも 1 つ。
test "同じ id を重ねても頂点は 1 つ" {
  let ast = ast_of([heading(2, "r", [])])
  assert_eq(tops(ast, [2, 2]), [[0]])
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc`
Expected: `Error: [4032]` / `The type Outcome is undefined.` と `Error: [4021]` / `The value identifier path_of is unbound.`（`tops` も同じく `[4021]`）。EXIT=1

- [ ] **Step 3: 最小の実装を書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/op.mbt`:

```moonbit
///|
/// 操作の結果。拒否は例外ではなく値（Result も raise も使わない — 旧 core に前例が無く、
/// 拒否は異常ではなく通常の答えだから）。
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
pub type Path = Array[Int]

///|
/// id からの道。居なければ None。
pub fn path_of(ast : Ast, id : Int) -> Path? {
  let acc : Array[Int] = []
  if seek(ast.doc, id, acc) {
    Some(acc)
  } else {
    None
  }
}

///|
/// 道を acc に積みながら id を探す。
fn seek(nd : Node, id : Int, acc : Array[Int]) -> Bool {
  if nd.id == id {
    return true
  }
  for i = 0; i < nd.children.length(); i = i + 1 {
    acc.push(i)
    if seek(nd.children[i], id, acc) {
      return true
    }
    ignore(acc.unsafe_pop())
  }
  false
}

///|
/// 頂点集合への正規化（子孫の選択は祖先に吸収され、文書順に並ぶ）。
pub fn tops(ast : Ast, ids : Array[Int]) -> Array[Path] {
  let paths : Array[Path] = []
  for id in ids {
    match path_of(ast, id) {
      Some(p) => paths.push(p)
      None => ()
    }
  }
  for i = 1; i < paths.length(); i = i + 1 {
    let p = paths[i]
    let mut j = i - 1
    while j >= 0 && precedes(p, paths[j]) {
      paths[j + 1] = paths[j]
      j = j - 1
    }
    paths[j + 1] = p
  }
  let out : Array[Path] = []
  for p in paths {
    if out.length() == 0 || !under(out[out.length() - 1], p) {
      out.push(p)
    }
  }
  out
}

///|
/// 道 a は道 b より文書順で前か（辞書順）。
fn precedes(a : Path, b : Path) -> Bool {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i = 0; i < n; i = i + 1 {
    if a[i] != b[i] {
      return a[i] < b[i]
    }
  }
  a.length() < b.length()
}

///|
/// 道 b は a と同じか、その子孫か。
fn under(a : Path, b : Path) -> Bool {
  if b.length() < a.length() {
    return false
  }
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
/// 道の先のノード。
fn at_path(nd : Node, p : Path, k : Int) -> Node {
  if k == p.length() {
    nd
  } else {
    at_path(nd.children[p[k]], p, k + 1)
  }
}

///|
/// 道の先のノードを f で置き換える。
fn amend(nd : Node, p : Path, k : Int, f : (Node) -> Node) -> Node {
  if k == p.length() {
    return f(nd)
  }
  let kids : Array[Node] = []
  for i = 0; i < nd.children.length(); i = i + 1 {
    if i == p[k] {
      kids.push(amend(nd.children[i], p, k + 1, f))
    } else {
      kids.push(nd.children[i])
    }
  }
  { ..nd, children: kids }
}

///|
/// 道の先のノードを 1 つ抜く。
fn pluck(nd : Node, p : Path, k : Int) -> Node {
  let last = k == p.length() - 1
  let kids : Array[Node] = []
  for i = 0; i < nd.children.length(); i = i + 1 {
    if i != p[k] {
      kids.push(nd.children[i])
    } else if !last {
      kids.push(pluck(nd.children[i], p, k + 1))
    }
  }
  { ..nd, children: kids }
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc`
Expected: `Total tests: N, passed: N, failed: 0.`（EXIT=0）。**T5 の累計は 20 本**。`at_path` / `amend` / `pluck` は Task 45〜47 まで使われないので `Warning (unused_value)` が出るが、ビルドは止まらない。**`Total tests: 0` なら `-p` の綴りを疑う**

- [ ] **Step 5: コミット**

```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/op.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/op_wbtest.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/fixture_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ 操作の結果・道・頂点集合を置く"
```

---

## Task 44: 不変条件の回復（normalize）

**Files:**
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/op.mbt`（末尾に `normalize` / `fix` / `spellable` を足す）
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/op_wbtest.mbt`（末尾に 10 本足す）

**Interfaces:**
- Consumes: `to_item`（Task 42）、`is_implied` / `promote` / `empty` / `sig` / `Side`（T1 Task 1）、`node` / `heading` / `item` / `ast_of`（T1 Task 2）
- Produces: `pub fn normalize(ast : Ast) -> Ast`、（非公開）`fn fix(nd : Node, depth : Int) -> Node` / `fn spellable(nd : Node, heading_before : Bool, depth : Int, prev : Side) -> Node`

これが T5 の心臓であり、**仕様 §9「殺す条件」の観測点**（Task 50）でもある。操作ごとの場合分けはここへ集める。

**裁定 1 の実装点**: 不変条件 11「implied ⇒ side = Right」の回復は `spellable` が担う。深さ 2 のスロットで**トグルを要する**（直前の兄弟と側が違う）implied は、飛びに側を書く場所が無いので**昇格する**。これで「側を持たされた implied」が serialize に到達しない。

**裁定 B の実装点**: 不変条件 8 は「implied ⇒ 親の children の先頭」ではなく「**implied ⇒ その前に見出しの兄弟が居ない**」である。飛びを吸収してしまうのは見出しだけで、項目は吸収しない（単調性より Item は Heading の子を持てない）。よって `spellable` の第 1 の引き金は `at == 0` ではなく **`!heading_before`** であり、`fix` は順序法則で並べ替えた**後**の列を走りながら `seen_heading` を持ち回ってそれを渡す。項目 root の後ろに立った implied（裁定 A で `- a` + `## h` から生まれる形）を、`normalize` を通すたびに無用に昇格させないための綴りである。

- [ ] **Step 1: 失敗するテストを書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/op_wbtest.mbt` の末尾に追記する。

```moonbit
///|
/// 備考 R024 / R025 — implied は子を持つ限りにおいて存在する。
test "子の居ない implied は導出されなくなる" {
  let g = { ..empty(3, Heading), implied: true }
  let ast = ast_of([heading(2, "r", [g])])
  assert_eq(sig(normalize(ast)), "head:-\nlf\n[H[Hr]]")
}

///|
/// 備考 R024 — 子が居る implied はそのまま（飛びが綴り）。
test "子の居る implied は残る" {
  let g = { ..empty(3, Heading), implied: true, children: [heading(4, "x", [])] }
  let ast = ast_of([heading(2, "r", [g])])
  assert_eq(sig(normalize(ast)), "head:-\nlf\n[H[Hr[H~[Hx]]]]")
}

///|
/// 備考 R124 / 裁定 B — 前に見出しが居ると飛びが吸収されて綴れないので昇格する（不変条件 8）。
test "見出しの後ろの implied は昇格する" {
  let g = { ..empty(4, Heading), implied: true, children: [heading(5, "x", [])] }
  let ast = ast_of([heading(2, "r", [heading(3, "a", []), g])])
  assert_eq(sig(normalize(ast)), "head:-\nlf\n[H[Hr[Ha][H[Hx]]]]")
}

///|
/// 備考 裁定 B / C17 — 項目は飛びを吸収しない（Item は Heading の子を持てない）ので、
/// 項目 root の後ろに立った implied は綴れる。昇格させない。
test "項目 root のあとの implied は昇格しない" {
  let g = { ..empty(3, Heading), implied: true, children: [heading(4, "h", [])] }
  let ast = ast_of([item(2, "a", []), g])
  assert_eq(sig(normalize(ast)), "head:-\nlf\n[H[Ia][H~[Hh]]]")
}

///|
/// 備考 R039 — 単調性: Item の子孫はすべて Item。
test "Item の下は全部 Item になる" {
  let ast = ast_of([
    node(2, Item, "a", [node(3, Heading, "b", [node(4, Heading, "c", [])])]),
  ])
  assert_eq(sig(normalize(ast)), "head:-\nlf\n[H[Ia[Ib[Ic]]]]")
}

///|
/// 備考 R041 — 順序法則: 同じ親の子は Item が先、Heading が後。
test "同じ親の子は Item が先、Heading が後に並ぶ" {
  let ast = ast_of([
    heading(2, "r", [
      node(3, Heading, "a", []),
      node(4, Item, "x", []),
      node(5, Heading, "b", []),
    ]),
  ])
  assert_eq(sig(normalize(ast)), "head:-\nlf\n[H[Hr[Ix][Ha][Hb]]]")
}

///|
/// 備考 R042 — 順序法則は doc（深さ 0）直下にも同じく効く。
test "文書直下でも Item root が Heading root より前に並ぶ" {
  let ast = ast_of([node(2, Heading, "r", []), node(3, Item, "c", [])])
  assert_eq(sig(normalize(ast)), "head:-\nlf\n[H[Ic][Hr]]")
}

///|
/// 備考 R055 — 側は深さ 2 のスロットだけが持つ（不変条件 10）。
test "深さ 2 でない側は落とされる" {
  let x = { ..node(4, Heading, "x", []), side: Left }
  let ast = ast_of([heading(2, "r", [heading(3, "a", [x])])])
  assert_eq(sig(normalize(ast)), "head:-\nlf\n[H[Hr[Ha[Hx]]]]")
}

///|
/// 備考 裁定 1 / 不変条件 11 / C16 — 飛びには側を書く場所が無い。
/// トグルを要する深さ 2 の implied スロットは骨格行を書いて昇格する。
test "側のトグルを要する implied スロットは昇格する" {
  let inner = {
    ..empty(4, Heading),
    implied: true,
    children: [heading(5, "b", [])],
  }
  // 名前は `slot` を避ける — fixture_wbtest.mbt の `fn slot(id, label, left)` を
  // 影にしてしまい、読む側が関数か手組みかで一度止まるため
  let left_slot = {
    ..empty(3, Heading),
    implied: true,
    side: Left,
    children: [inner],
  }
  let ast = ast_of([heading(2, "r", [left_slot])])
  assert_eq(sig(normalize(ast)), "head:-\nlf\n[H[Hr[H<[H~[Hb]]]]]")
}

///|
/// 備考 R003 — 回復は決定的・冪等。
test "不変条件の回復は冪等" {
  let g = { ..empty(3, Heading), implied: true, children: [node(4, Item, "x", [])] }
  let ast = ast_of([heading(2, "r", [heading(5, "a", []), g])])
  let once = normalize(ast)
  assert_eq(sig(normalize(once)), sig(once))
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc`
Expected: `Error: [4021]` / `The value identifier normalize is unbound.`。EXIT=1

- [ ] **Step 3: 最小の実装を書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/op.mbt` の末尾に追記する。

```moonbit
///|
/// 不変条件の回復。**すべての操作の最後に必ず通す**。
/// implied の消滅・昇格・単調性・順序法則・側の落とし込みを 1 度に行う。
pub fn normalize(ast : Ast) -> Ast {
  { ..ast, doc: fix(ast.doc, 0) }
}

///|
/// ノード 1 つを直す。子から先に直すので、implied の消滅は下から上へ伝わる。
fn fix(nd : Node, depth : Int) -> Node {
  let kids : Array[Node] = []
  for k in nd.children {
    let f = fix(k, depth + 1)
    // 存在条件: 子を失った implied は導出されなくなる（削除という出来事ではない）
    if !is_implied(f) || f.children.length() > 0 {
      // 単調性: Item の子孫はすべて Item
      kids.push(if nd.form is Item { to_item(f) } else { f })
    }
  }
  // 順序法則: Item が先、Heading が後（それぞれ元の順を保つ）。doc 直下にも効く
  let sorted : Array[Node] = []
  for k in kids {
    if k.form is Item {
      sorted.push(k)
    }
  }
  for k in kids {
    if k.form is Heading {
      sorted.push(k)
    }
  }
  // 綴れるかを、前に見出しが居るか（不変条件 8）と直前の兄弟の側（不変条件 11）まで
  // 見て決める。並べ替えた後の列を走るので、項目は seen_heading を立てない
  let out : Array[Node] = []
  let mut prev : Side = Right
  let mut seen_heading = false
  for k in sorted {
    let s = spellable(k, seen_heading, depth + 1, prev)
    if s.form is Heading {
      seen_heading = true
    }
    prev = s.side
    out.push(s)
  }
  { ..nd, side: if depth == 2 { nd.side } else { Right }, children: out }
}

///|
/// 綴りは行き先に従う — 飛びで綴れない位置の implied は骨格行を書いて昇格する。
/// 飛びが読み戻せるのは、**前に見出しの兄弟が居らず**（居ると飛びがそちらに
/// 吸収される。項目は吸収しないので後ろに立ってよい。不変条件 8）、
/// 子がすべて Heading で、**側のトグルを要さない**ときだけ
/// （飛びには側を書く行が無い。不変条件 11）。
fn spellable(
  nd : Node,
  heading_before : Bool,
  depth : Int,
  prev : Side,
) -> Node {
  if !is_implied(nd) {
    return nd
  }
  let mut ok = !heading_before &&
    nd.form is Heading &&
    nd.label == "" &&
    nd.body.length() == 0 &&
    !nd.folded
  for k in nd.children {
    if k.form is Item {
      ok = false
    }
  }
  // 深さ 2 のスロットで側が直前と違えば区切りが 1 本要る。飛びはそれを書けない
  if depth == 2 && nd.side != prev {
    ok = false
  }
  if ok {
    nd
  } else {
    promote(nd, nd.label)
  }
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc`
Expected: `Total tests: N, passed: N, failed: 0.`（EXIT=0）。**T5 の累計は 30 本**。**`Total tests: 0` なら `-p` の綴りを疑う**

- [ ] **Step 5: コミット**

```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/op.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/op_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ 不変条件の回復を 1 か所に集める"
```

---

## Task 45: 消す

**Files:**
- Create: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/delete.mbt`
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/delete_wbtest.mbt`

**Interfaces:**
- Consumes: `Outcome` / `Reject` / `Path` / `path_of` / `tops` / `normalize` と非公開の `pluck`（Task 43・44）、`empty` / `sig`（T1 Task 1）、`node` / `heading` / `ast_of` / `done` / `rejected`（`fixture_wbtest.mbt`）
- Produces: `pub fn delete_nodes(ast : Ast, ids : Array[Int]) -> Outcome`

- [ ] **Step 1: 失敗するテストを書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/delete_wbtest.mbt` を新規作成する。

```moonbit
// 側の列と implied の存在条件は木の中の値。直接見たいので whitebox テスト。

///|
/// 備考 C3 / R183 — 側の列が (右, 右) になり、区切りは導出されなくなる。
test "C3: 左の枝を消すと側の列が (右, 右) になる" {
  let b = { ..heading(3, "b", []), side: Left }
  let ast = ast_of([
    heading(2, "r", [heading(4, "a", []), b, heading(5, "c", [])]),
  ])
  let out = done(delete_nodes(ast, [3]))
  assert_eq(sig(out), "head:-\nlf\n[H[Hr[Ha][Hc]]]")
}

///|
/// 備考 R133 — delete はサブツリー削除で統一（段差詰めはしない）。
test "消すのはサブツリーごと" {
  let ast = ast_of([heading(2, "r", [heading(3, "a", [heading(4, "x", [])])])])
  let out = done(delete_nodes(ast, [3]))
  assert_eq(sig(out), "head:-\nlf\n[H[Hr]]")
}

///|
/// 備考 R025 — 最後の子を失った implied は同時に居なくなる。
test "子を失った implied は導出されなくなる" {
  let g = { ..empty(3, Heading), implied: true, children: [heading(4, "x", [])] }
  let ast = ast_of([heading(2, "r", [g])])
  let out = done(delete_nodes(ast, [4]))
  assert_eq(sig(out), "head:-\nlf\n[H[Hr]]")
}

///|
/// 備考 R130 — 複数選択は頂点集合に正規化してから当てる。
test "祖先と子孫を一緒に選んでも 1 回だけ消える" {
  let ast = ast_of([
    heading(2, "r", [
      heading(3, "a", [heading(4, "x", [])]),
      heading(5, "b", []),
    ]),
  ])
  let out = done(delete_nodes(ast, [4, 3]))
  assert_eq(sig(out), "head:-\nlf\n[H[Hr[Hb]]]")
}

///|
/// 備考 R112 — 居ない id は Missing。
test "居ない id を指した delete は Missing" {
  let ast = ast_of([heading(2, "r", [])])
  assert_eq(rejected(delete_nodes(ast, [99])), Missing)
}

///|
/// 備考 不変条件 1 — 文書は消せない。
test "文書そのものは消せない" {
  let ast = ast_of([heading(2, "r", [])])
  assert_eq(rejected(delete_nodes(ast, [1])), Ineligible)
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc`
Expected: `Error: [4021]` / `The value identifier delete_nodes is unbound.`。EXIT=1

- [ ] **Step 3: 最小の実装を書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/delete.mbt`:

```moonbit
///|
/// 選んだもののサブツリーを消す（段差詰めはしない）。
pub fn delete_nodes(ast : Ast, ids : Array[Int]) -> Outcome {
  for id in ids {
    if path_of(ast, id) is None {
      return Reject(Missing)
    }
  }
  let ps = tops(ast, ids)
  if ps.length() == 0 {
    return Reject(Ineligible)
  }
  for p in ps {
    if p.length() == 0 {
      return Reject(Ineligible) // 文書そのものは消せない（不変条件 1）
    }
  }
  // 後ろから抜く（前の道の添字がずれない）
  let mut doc = ast.doc
  for i = ps.length() - 1; i >= 0; i = i - 1 {
    doc = pluck(doc, ps[i], 0)
  }
  Done(normalize({ ..ast, doc, }))
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc`
Expected: `Total tests: N, passed: N, failed: 0.`（EXIT=0）。**T5 の累計は 36 本**。**`Total tests: 0` なら `-p` の綴りを疑う**

- [ ] **Step 5: コミット**

```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/delete.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/delete_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ 消す操作を置く"
```

---

## Task 46: 側を返す

**Files:**
- Create: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/side.mbt`
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/side_wbtest.mbt`

**Interfaces:**
- Consumes: `Outcome` / `Reject` / `path_of` / `tops` / `normalize` と非公開の `amend`（Task 43・44）、`promote` / `empty` / `sig`（T1 Task 1）、`heading` / `ast_of` / `done` / `rejected`（`fixture_wbtest.mbt`）
- Produces: `pub fn flip_side(ast : Ast, ids : Array[Int]) -> Outcome`、（非公開）`fn turn(nd : Node) -> Node` / `fn mirror(nd : Node) -> Node`

**裁定 1 の実装点**: `turn` は**骨格行を書いてから反転する**。`promote(nd, nd.label)` は骨格行を持つノードには無害（同じ label を書き直すだけ）なので、**分岐なしで無条件に呼ぶ**。これで side.mbt に `implied` / `is_implied` というリテラルが 1 つも現れず、Task 50 の判定 3（implied の専用分岐がゼロ）が守られる。

- [ ] **Step 1: 失敗するテストを書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/side_wbtest.mbt` を新規作成する。

```moonbit
// 側はノードの値（深さ 2 だけが意味を持つ）。直接見たいので whitebox テスト。

///|
/// 備考 C4 / R185 — 先頭の枝も反転できる（先頭トグルが左開始を綴る）。
test "C4: 先頭の枝の flipSide は側の列を (左, 右) にする" {
  let ast = ast_of([heading(2, "r", [heading(3, "a", []), heading(4, "b", [])])])
  let out = done(flip_side(ast, [3]))
  assert_eq(sig(out), "head:-\nlf\n[H[Hr[H<a][Hb]]]")
}

///|
/// 備考 R127 — root は鏡像（全スロット一括反転）。木全体 = root のサブツリーなので比例的。
test "root の flipSide は鏡像になる" {
  let a = { ..heading(3, "a", []), side: Left }
  let ast = ast_of([heading(2, "r", [a, heading(4, "b", [])])])
  let out = done(flip_side(ast, [2]))
  assert_eq(sig(out), "head:-\nlf\n[H[Hr[Ha][H<b]]]")
}

///|
/// 備考 R118 / R128 — 深いノードには資格が無い（委譲は却下）。
test "深いノードの flipSide は資格が無い" {
  let ast = ast_of([heading(2, "r", [heading(3, "a", [heading(4, "x", [])])])])
  assert_eq(rejected(flip_side(ast, [4])), Ineligible)
}

///|
/// 備考 R129 — 複数選択では資格のあるものだけに効き、他はスキップする。
test "資格のあるものだけに効く" {
  let a = heading(3, "a", [heading(4, "x", [])])
  let ast = ast_of([heading(2, "r", [a, heading(5, "b", [])])])
  let out = done(flip_side(ast, [4, 5]))
  assert_eq(sig(out), "head:-\nlf\n[H[Hr[Ha[Hx]][H<b]]]")
}

///|
/// 備考 裁定 1 / C16 — implied スロットへの flipSide は昇格してから反転する。
/// `# r` + `#### b` の r 直下スロットを左へ返すと、空ラベルの `## ` が生えてトグルが立つ。
test "C16: implied スロットの flipSide は昇格してから反転する" {
  let inner = {
    ..empty(4, Heading),
    implied: true,
    children: [heading(5, "b", [])],
  }
  // 名前は `slot` を避ける（fixture_wbtest.mbt の `fn slot` を影にしないため）
  let implied_slot = { ..empty(3, Heading), implied: true, children: [inner] }
  let ast = ast_of([heading(2, "r", [implied_slot])])
  let out = done(flip_side(ast, [3]))
  assert_eq(sig(out), "head:-\nlf\n[H[Hr[H<[H~[Hb]]]]]")
}

///|
/// 備考 R112 — 居ない id は Missing。
test "居ない id を指した flipSide は Missing" {
  let ast = ast_of([heading(2, "r", [])])
  assert_eq(rejected(flip_side(ast, [99])), Missing)
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc`
Expected: `Error: [4021]` / `The value identifier flip_side is unbound.`。EXIT=1

- [ ] **Step 3: 最小の実装を書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/side.mbt`:

```moonbit
///|
/// スロット 1 つの側を返す。
/// 側の変わり目は区切り 1 本で綴られるので、**骨格行を書いてから**反転する
/// （飛びには区切りの帰属先が無い。裁定 1・不変条件 11）。
/// promote は骨格行を持つノードには無害 — 同じ label を書き直すだけ。
fn turn(nd : Node) -> Node {
  let seen = promote(nd, nd.label)
  { ..seen, side: if seen.side is Left { Right } else { Left } }
}

///|
/// root の鏡像（配下の全スロット一括反転）。
fn mirror(nd : Node) -> Node {
  let kids : Array[Node] = []
  for k in nd.children {
    kids.push(turn(k))
  }
  { ..nd, children: kids }
}

///|
/// 側を返す。root（深さ 1）なら鏡像（配下の全スロット一括反転）、
/// 深さ 2 のスロットならそれ 1 つ。他は資格が無い。
/// 複数選択では資格のあるものだけに効き、資格が 1 つも無ければ Reject(Ineligible)。
pub fn flip_side(ast : Ast, ids : Array[Int]) -> Outcome {
  for id in ids {
    if path_of(ast, id) is None {
      return Reject(Missing)
    }
  }
  let mut doc = ast.doc
  let mut hit = false
  for p in tops(ast, ids) {
    if p.length() == 1 {
      doc = amend(doc, p, 0, mirror)
      hit = true
    } else if p.length() == 2 {
      doc = amend(doc, p, 0, turn)
      hit = true
    }
  }
  if hit {
    Done(normalize({ ..ast, doc, }))
  } else {
    Reject(Ineligible)
  }
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc`
Expected: `Total tests: N, passed: N, failed: 0.`（EXIT=0）。**T5 の累計は 42 本**。**`Total tests: 0` なら `-p` の綴りを疑う**

- [ ] **Step 5: コミット**

```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/side.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/side_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ 側を返す操作を置く"
```

---

## Task 47: 動かす

**Files:**
- Create: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/move.mbt`
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/move_wbtest.mbt`

**Interfaces:**
- Consumes: `refit` / `to_item`（Task 42）、`Outcome` / `Reject` / `Path` / `path_of` / `tops` / `normalize` と非公開の `at_path` / `amend` / `pluck` / `under`（Task 43・44）、`empty` / `sig` / `Block`（T1 Task 1）、`node` / `heading` / `ast_of` / `done` / `rejected`（`fixture_wbtest.mbt`）
- Produces: `pub fn move_nodes(ast : Ast, ids : Array[Int], parent : Int, at : Int) -> Outcome`、（非公開）`fn moving(picked : Array[Node], id : Int) -> Bool` / `fn seat_in(host : Node, picked : Array[Node], slot : Int) -> Node`

**文書を親とする move**（R059 / R060）: root 専用の操作語彙は存在しない。root 化も root の並べ替えも「parent = doc の id（1）」の move で表現する。テストを 2 本置いて固定する。

- [ ] **Step 1: 失敗するテストを書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/move_wbtest.mbt` を新規作成する。

```moonbit
// 転形・深さの付け直し・implied の昇格は木の中の値。直接見たいので whitebox テスト。

///|
/// 備考 C5 / R187 / R188 — 中身は運ばれ、深さは移動先で付け直される（level は木の深さそのもの）。
test "C5: 中身は運ばれ、深さは付け直される" {
  let head = { ..heading(3, "head", []), body: [Opaque("content01"), Rule] }
  let ast = ast_of([heading(2, "r", [head, heading(4, "head2", [])])])
  let out = done(move_nodes(ast, [3], 4, 0))
  assert_eq(sig(out), "head:-\nlf\n[H[Hr[Hhead2[Hhead|o:content01|rule]]]]")
}

///|
/// 備考 C14 / R123 — Heading 兄弟の間へ落ちた Item はそのノードだけ Heading 化（子は Item のまま）。
test "C14: Heading 兄弟の間へ落ちた Item はそのノードだけ Heading になる" {
  let a = heading(3, "a", [node(5, Item, "x", [node(6, Item, "y", [])])])
  let ast = ast_of([heading(2, "r", [a, heading(4, "b", [])])])
  let out = done(move_nodes(ast, [5], 2, 1))
  assert_eq(sig(out), "head:-\nlf\n[H[Hr[Ha][Hx[Iy]][Hb]]]")
}

///|
/// 備考 R122 — Item 親の下へ来た Heading はサブツリーごと Item 化（単調性・下向きで比例的）。
test "Item 親の下へ来た Heading はサブツリーごと Item になる" {
  let a = node(3, Item, "a", [])
  let b = heading(4, "b", [heading(5, "c", [])])
  let ast = ast_of([heading(2, "r", [a, b])])
  let out = done(move_nodes(ast, [4], 3, 0))
  assert_eq(sig(out), "head:-\nlf\n[H[Hr[Ia[Ib[Ic]]]]]")
}

///|
/// 備考 R116 — 子孫への move は循環。
test "自分の中へは動かせない" {
  let ast = ast_of([heading(2, "r", [heading(3, "a", [heading(4, "x", [])])])])
  assert_eq(rejected(move_nodes(ast, [3], 4, 0)), Cycle)
}

///|
/// 備考 R120 — 同位置への move は許可し、編集ゼロ。
test "同じ位置への move は木を変えない" {
  let ast = ast_of([heading(2, "r", [heading(3, "a", []), heading(4, "b", [])])])
  let out = done(move_nodes(ast, [3], 2, 0))
  assert_eq(sig(out), sig(ast))
}

///|
/// 備考 R131 — 複数選択は文書順を保って連続挿入する。
test "複数選択は文書順を保って連続挿入される" {
  let ast = ast_of([
    heading(2, "r", [
      heading(3, "a", []),
      heading(4, "b", []),
      heading(5, "c", []),
    ]),
  ])
  let out = done(move_nodes(ast, [5, 3], 4, 0))
  assert_eq(sig(out), "head:-\nlf\n[H[Hr[Hb[Ha][Hc]]]]")
}

///|
/// 備考 R120 — at は操作前の children の添字。末尾なら最後の子。
test "末尾への move は最後の子になる" {
  let ast = ast_of([
    heading(2, "r", [heading(3, "a", [heading(5, "x", [])]), heading(4, "b", [])]),
  ])
  let out = done(move_nodes(ast, [4], 3, 1))
  assert_eq(sig(out), "head:-\nlf\n[H[Hr[Ha[Hx][Hb]]]]")
}

///|
/// 備考 R124 / 裁定 B — 綴りは行き先に従う。前に見出しが来た implied は飛びで綴れないので昇格する。
test "見出しの後ろへ回った implied は昇格する" {
  let g = { ..empty(4, Heading), implied: true, children: [heading(5, "x", [])] }
  let ast = ast_of([heading(2, "r", [g, heading(3, "a", [])])])
  let out = done(move_nodes(ast, [3], 2, 0))
  assert_eq(sig(out), "head:-\nlf\n[H[Hr[Ha][H[Hx]]]]")
}

///|
/// 備考 R059 / R060 — root 専用の操作語彙は無い。root 化は「文書を親とする move」で表す。
/// 深さが 1 に付け直され、側も Right へ落ちる（不変条件 10）。
test "枝を文書の子へ move すると root になる" {
  let a = { ..heading(3, "a", []), side: Left }
  let ast = ast_of([heading(2, "r", [a])])
  let out = done(move_nodes(ast, [3], 1, 1))
  assert_eq(sig(out), "head:-\nlf\n[H[Hr][Ha]]")
}

///|
/// 備考 R060 — root の並べ替えも「文書を親とする move」で表す。
test "root は文書を親とする move で並べ替わる" {
  let ast = ast_of([heading(2, "r1", []), heading(3, "r2", [])])
  let out = done(move_nodes(ast, [3], 1, 0))
  assert_eq(sig(out), "head:-\nlf\n[H[Hr2][Hr1]]")
}

///|
/// 備考 R112 — 居ない id は Missing。
test "居ない親を指した move は Missing" {
  let ast = ast_of([heading(2, "r", [heading(3, "a", [])])])
  assert_eq(rejected(move_nodes(ast, [3], 99, 0)), Missing)
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc`
Expected: `Error: [4021]` / `The value identifier move_nodes is unbound.`。EXIT=1

- [ ] **Step 3: 最小の実装を書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/move.mbt`:

```moonbit
///|
/// 動かすものの中に居る id か。
fn moving(picked : Array[Node], id : Int) -> Bool {
  for nd in picked {
    if nd.id == id {
      return true
    }
  }
  false
}

///|
/// 抜いた後の host の slot 番目へ、picked を文書順のまま連続で挿す。
/// 連続した 1 塊なので、どれも同じ兄弟・同じ添字で form を決める。
fn seat_in(host : Node, picked : Array[Node], slot : Int) -> Node {
  let kids : Array[Node] = []
  for i = 0; i < host.children.length(); i = i + 1 {
    if i == slot {
      for nd in picked {
        kids.push(refit(nd, host.form, host.children, slot))
      }
    }
    kids.push(host.children[i])
  }
  if slot >= host.children.length() {
    for nd in picked {
      kids.push(refit(nd, host.form, host.children, slot))
    }
  }
  { ..host, children: kids }
}

///|
/// 選んだものを `parent` の子の `at` 番目へ動かす。
/// `parent` には**文書の id（1）も渡せる** — root 化も root の並べ替えも、
/// 「文書を親とする move」で表す（root 専用の操作語彙は無い。R059 / R060）。
/// `at` は**操作前の** parent.children における添字（`at` に居たノードの直前へ挿す。
/// children.length() なら末尾）。文書順を保って連続挿入する。
/// 同じ位置への move は Done（編集ゼロ）。
pub fn move_nodes(
  ast : Ast,
  ids : Array[Int],
  parent : Int,
  at : Int,
) -> Outcome {
  for id in ids {
    if path_of(ast, id) is None {
      return Reject(Missing)
    }
  }
  let pp : Path = match path_of(ast, parent) {
    Some(p) => p
    None => return Reject(Missing)
  }
  let ps = tops(ast, ids)
  if ps.length() == 0 {
    return Reject(Ineligible)
  }
  for p in ps {
    if p.length() == 0 {
      return Reject(Ineligible) // 文書そのものは動かせない
    }
    if under(p, pp) {
      return Reject(Cycle)
    }
  }
  // 抜くと添字がずれるので、挿し先は「錨」のノードの id で覚える
  let picked : Array[Node] = []
  for p in ps {
    picked.push(at_path(ast.doc, p, 0))
  }
  let host = at_path(ast.doc, pp, 0)
  let mut want = at
  if want < 0 {
    want = 0
  }
  if want > host.children.length() {
    want = host.children.length()
  }
  let mut anchor = -1
  for i = host.children.length() - 1; i >= want; i = i - 1 {
    if !moving(picked, host.children[i].id) {
      anchor = host.children[i].id
    }
  }
  let mut doc = ast.doc
  for i = ps.length() - 1; i >= 0; i = i - 1 {
    doc = pluck(doc, ps[i], 0)
  }
  let seat : Path = match path_of({ ..ast, doc, }, parent) {
    Some(p) => p
    None => return Reject(Missing)
  }
  let rest = at_path(doc, seat, 0)
  let mut slot = rest.children.length()
  for i = rest.children.length() - 1; i >= 0; i = i - 1 {
    if rest.children[i].id == anchor {
      slot = i
    }
  }
  doc = amend(doc, seat, 0, fn(h) { seat_in(h, picked, slot) })
  Done(normalize({ ..ast, doc, }))
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc`
Expected: `Total tests: N, passed: N, failed: 0.`（EXIT=0）。**T5 の累計は 53 本**。**`Total tests: 0` なら `-p` の綴りを疑う**

- [ ] **Step 5: コミット**

```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/move.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/move_wbtest.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ 動かす操作（転形と挿し直し）を置く"
```

---

## Task 48: 操作の性質のファズ（TS 側）

**Files:**
- Create: `D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-ops.test.ts`

**Interfaces:**
- Consumes（**正誤表 D-3 の export 名だけ**。`doc` 名前空間・`randomDoc`・`ApplyResult` は存在しない）:
  - `test/_doc.ts`（T4 所有）: `sig(md: string): string` / `check(md: string): string[]` / `tree(md: string): DocTree` / `flatten(nd: DocNode): DocNode[]` / `applyOp(md: string, op: string, ids: number[], parent: number, at: number): OpResult` / `applyEdits(text: string, edits: OpEdit[]): string` / `randomMd(seed: number): string` / `shrink(md: string, fails: (s: string) => boolean, rounds?: number): string` / 型 `DocNode` / `OpResult`
  - 既存 `test/_helpers.ts`: `brief(md: string, max?: number): string`
- Produces: なし（検証だけ）

**依存**: T2 Task 17（parse）・T3 Task 26（serialize）・T4 Task 37（`applyOp` と `shrink` の受け口）・T5 Task 45〜47（3 操作）が全部揃ってから着手する。`pnpm install` と `pnpm run core` は T4 Task 30 / 31 が踏んでいる。

**規律**: `check` は `string[]` を返す（`!== ""` で判定しない）。`OpResult` は判別可能ユニオンなので `if (!r.ok) continue;` の後で `r.text` / `r.sig` / `r.edits` が読める。`tsconfig` の `noUnusedLocals` があるので、**使わない import を 1 個も残さない**（`fuzzCases` は使わないので import しない）。ファズの回数は**定数 `CASES` を書き替えて**切り替える — 環境変数の前置きは使わない。

- [ ] **Step 1: 失敗するテストを書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-ops.test.ts` を新規作成する。

```ts
// 操作の性質（意味保全・法則 2 の実地検証・edits の自己検査）。
// 木の中は core/doc/*_wbtest.mbt が見る。ここは JS 境界を越えた後の面だけを見る。
import test from "node:test";
import assert from "node:assert/strict";
import {
  sig,
  check,
  tree,
  flatten,
  applyOp,
  applyEdits,
  randomMd,
  shrink,
  type DocNode,
  type OpResult,
} from "./_doc.ts";
import { brief } from "./_helpers.ts";

const CASES = 120; // 深掘りするときはこの数を上げ、終わったら 120 に戻す

/** doc も含めた全ノードを文書順に。doc の id は parent 候補に要る（R059 / R060）。 */
function nodesOf(md: string): DocNode[] {
  const t = tree(md);
  return [t.doc, ...flatten(t.doc)];
}

/** 空でないラベルの多重集合。implied の昇格・消滅はどれも空ラベルなのでここに現れない。 */
function labels(md: string): string[] {
  return flatten(tree(md).doc)
    .map((n) => n.label)
    .filter((s) => s !== "")
    .sort();
}

/** 操作 1 個ぶんの定義。全ノード × 全操作の直積を関数の配列で作る。 */
function opsFor(md: string): [string, () => OpResult][] {
  const ids = nodesOf(md).map((n) => n.id);
  const mid = ids[Math.floor(ids.length / 2)];
  const last = ids[ids.length - 1];
  const out: [string, () => OpResult][] = [];
  for (const id of ids) {
    out.push([`flip(${id})`, () => applyOp(md, "flip", [id], 0, 0)]);
    out.push([`delete(${id})`, () => applyOp(md, "delete", [id], 0, 0)]);
    // ids[0] は doc の id（1）。文書を親とする move = root 化・root の並べ替え（R059 / R060）
    for (const p of [ids[0], mid, last]) {
      if (p === id) continue;
      for (const at of [0, 1]) {
        out.push([
          `move(${id}->${p},${at})`,
          () => applyOp(md, "move", [id], p, at),
        ]);
      }
    }
  }
  return out;
}

/**
 * この md の上で最初に壊れた性質を返す（無ければ null）。
 * `pick` で操作を絞り、`bad` が壊れた理由を返す。
 */
function firstFailure(
  md: string,
  pick: (name: string) => boolean,
  bad: (md: string, r: OpResult & { ok: true }) => string | null,
): string | null {
  for (const [name, fn] of opsFor(md)) {
    if (!pick(name)) continue;
    const r = fn();
    if (!r.ok) continue;
    const why = bad(md, r);
    if (why !== null) return `${name}: ${why}`;
  }
  return null;
}

/** 反例を縮める。`shrink` の述語は総関数でなければならないので例外は「まだ落ちる」と読む。 */
function narrow(
  md: string,
  pick: (name: string) => boolean,
  bad: (md: string, r: OpResult & { ok: true }) => string | null,
): string {
  return shrink(md, (s) => {
    try {
      return firstFailure(s, pick, bad) !== null;
    } catch {
      return true;
    }
  });
}

/** 種を回して壊れたものを集める共通の骨格。 */
function sweep(
  pick: (name: string) => boolean,
  bad: (md: string, r: OpResult & { ok: true }) => string | null,
): string[] {
  const failures: string[] = [];
  for (let seed = 1; seed <= CASES && failures.length < 6; seed++) {
    const md = randomMd(seed);
    const why = firstFailure(md, pick, bad);
    if (why === null) continue;
    const small = narrow(md, pick, bad);
    failures.push(`seed=${seed} ${why}\n    最小反例=${brief(small, 140)}`);
  }
  return failures;
}

const notDelete = (name: string): boolean => !name.startsWith("delete");
const onlyDelete = (name: string): boolean => name.startsWith("delete");
const anyOp = (): boolean => true;

test("操作の後もラベルは 1 つも失われない（move / flipSide）", () => {
  const failures = sweep(notDelete, (md, r) =>
    labels(md).join("\u0000") === labels(r.text).join("\u0000")
      ? null
      : "ラベルの多重集合が変わった",
  );
  assert.deepEqual(failures, [], `意味保全が破れた:\n  ${failures.join("\n  ")}`);
});

test("delete は選んだ枝のぶんだけラベルを減らす", () => {
  const failures = sweep(onlyDelete, (md, r) => {
    const before = labels(md);
    const after = labels(r.text);
    const grew = after.filter((s) => !before.includes(s));
    return after.length > before.length || grew.length > 0
      ? "delete でラベルが増えた"
      : null;
  });
  assert.deepEqual(failures, [], `delete が増やした:\n  ${failures.join("\n  ")}`);
});

test("反映後の全文を読み直すと、変異後の木と指紋が一致する", () => {
  // 仕様 §5 の「操作後の parse 結果は変異後の木と構造同一」= 法則 2 の実地検証。
  const failures = sweep(anyOp, (_md, r) => {
    const again = sig(r.text);
    return again === r.sig ? null : `変異後=${r.sig} / 読み直し=${again}`;
  });
  assert.deepEqual(failures, [], `法則 2 が破れた:\n  ${failures.join("\n  ")}`);
});

test("edits を旧全文へ当てると反映後の全文になる", () => {
  const failures = sweep(anyOp, (md, r) =>
    applyEdits(md, r.edits) === r.text ? null : "自己検査が落ちた",
  );
  assert.deepEqual(failures, [], `自己検査が落ちた:\n  ${failures.join("\n  ")}`);
});

test("操作後の全文は不変条件を破らない", () => {
  const failures = sweep(anyOp, (_md, r) => {
    const bad = check(r.text);
    return bad.length > 0 ? bad.join(" / ") : null;
  });
  assert.deepEqual(failures, [], `不変条件の違反:\n  ${failures.join("\n  ")}`);
});

test("無操作は無編集（同じ位置への move は編集ゼロ）", () => {
  const stuck = (md: string): string | null => {
    const want = sig(md);
    for (const p of nodesOf(md)) {
      for (let i = 0; i < p.children.length; i++) {
        const r = applyOp(md, "move", [p.children[i].id], p.id, i);
        if (!r.ok) continue;
        if (r.sig !== want) {
          return `move(${p.children[i].id}->${p.id},${i}) が木を変えた`;
        }
      }
    }
    return null;
  };
  const failures: string[] = [];
  for (let seed = 1; seed <= CASES && failures.length < 6; seed++) {
    const md = randomMd(seed);
    const why = stuck(md);
    if (why === null) continue;
    const small = shrink(md, (s) => {
      try {
        return stuck(s) !== null;
      } catch {
        return true;
      }
    });
    failures.push(`seed=${seed} ${why}\n    最小反例=${brief(small, 140)}`);
  }
  assert.deepEqual(failures, [], `同位置 move が動いた:\n  ${failures.join("\n  ")}`);
});
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `node --test D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-ops.test.ts`
Expected: T4 Task 32 / 37 が未着なら `SyntaxError: The requested module './_doc.ts' does not provide an export named 'applyOp'`（EXIT=1）。T4 が揃っていれば 6 test が走り、壊れた性質だけが `✖ <テスト名>` + `AssertionError [ERR_ASSERTION]` + `ℹ fail N` で出る（EXIT=1）

- [ ] **Step 3: 落ちた性質を直す**

**まず MoonBit 側へ落とす。** 失敗メッセージの `最小反例=` を写し、その md が表す木を手で組んで、対応する `*_wbtest.mbt` に最小の再現テストを 1 本足す（TS 側のファズは執行機関であって、修正の場ではない）。そのうえで原因別に次を当てる。**TS 側の期待値は緩めない。**

**(a) 意味保全が落ちた** — 抜き差しでノードを落としている。`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/op.mbt` の `pluck` の `last` 判定が誤っていると、道の途中で枝ごと落ちる。次の形であることを確かめ、違っていたら差し替える:

```moonbit
fn pluck(nd : Node, p : Path, k : Int) -> Node {
  let last = k == p.length() - 1
  let kids : Array[Node] = []
  for i = 0; i < nd.children.length(); i = i + 1 {
    if i != p[k] {
      kids.push(nd.children[i])
    } else if !last {
      kids.push(pluck(nd.children[i], p, k + 1))
    }
  }
  { ..nd, children: kids }
}
```

**(b) 法則 2 が落ちた（`sig(r.text) !== r.sig`）** — 綴れない木を作っている。`op.mbt` の `spellable` に引き金が足りていない。**引き金は 4 つ**（前に見出しが居る／中身を持つ／Item が絡む／側のトグルを要する）。次の 4 つが全部揃っているかを見て、欠けている腕を足す:

```moonbit
  let mut ok = !heading_before &&
    nd.form is Heading &&
    nd.label == "" &&
    nd.body.length() == 0 &&
    !nd.folded
  for k in nd.children {
    if k.form is Item {
      ok = false
    }
  }
  if depth == 2 && nd.side != prev {
    ok = false
  }
```

`heading_before` は `fix` が並べ替えた**後**の列を走りながら持ち回る（項目は立てない。裁定 B）。ここを `at == 0` に戻すと、項目 root の後ろの implied が毎回昇格して木が動く。

**最小反例が `---` で始まっていて、読み直しの木が丸ごと消えている（`sig` から枝が失せる／`head:` に飲まれている）なら、疑うのは T5 でも T2 でもなく T1 の `scan_head`** である（裁定 E の「開き `---` の直後が空行なら封筒ではない」の 1 条件が入っていない。先頭トグルで始まりトグルをもう 1 本持つ木が、封筒として飲まれる）。T5 側に足すものは無いので、そのまま T1 へ渡す。

それでも落ちるなら原因は T5 ではない。`最小反例` を `format(md)` で潰して、`parse` が復元しない綴りなら T2（`build.mbt` / `block.mbt`）、`serialize` が書けない綴りなら T3（`serialize.mbt`）へ、失敗メッセージ全文を写して渡す。

**(c) 自己検査が落ちた（`applyEdits(md, r.edits) !== r.text`）** — `reflect` のフォールバックが働いていない。`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/reflect.mbt` が次のとおりであることを確かめる（`diff` の刈り込みが間違っても、この 1 本で正しさは保たれる）:

```moonbit
pub fn reflect(old : String, ast : Ast) -> Array[Edit] {
  let want = serialize(ast)
  let edits = diff(old, want)
  if apply(old, edits) == want {
    edits
  } else {
    [Edit::{ from: 0, to: old.length(), insert: want }]
  }
}
```

**(d) 不変条件が破れた** — `check` のメッセージが `implied が側を持つ: <id>` なら裁定 1 の回復漏れ。`spellable` の `depth == 2 && nd.side != prev` の腕と、`side.mbt` の `turn` が `promote(nd, nd.label)` を通っていることの両方を確かめる。`implied の前に見出しが居る: <id>` なら裁定 B の回復漏れで、`fix` が `seen_heading` を並べ替えた後の列で持ち回っているかを確かめる。

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `node --test D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-ops.test.ts`
Expected: `ℹ tests 6` / `ℹ pass 6` / `ℹ fail 0`（EXIT=0）

深掘り: `test/doc-ops.test.ts` の `const CASES` を 5000 に書き替えて同じコマンドを回し、**終わったら 120 に戻す**（環境変数の前置きは使わない — PowerShell で構文エラーになる）。

型検査も通すこと（`noUnusedLocals` があるので未使用 import 1 個で赤になる）:
Run: `pnpm -C D:/1.atrium/mmm/.claude/worktrees/doc-model run check`
Expected: 出力なし・EXIT=0

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-ops.test.ts
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "test: 🧪 操作の性質（意味保全・法則 2・自己検査）をファズで押さえる"
```

---

## Task 49: 回復と拒否・アンカーの注意（文書）

**Files:**
- Create: `D:/1.atrium/mmm/.claude/worktrees/doc-model/docs/superpowers/specs/2026-08-29-recover-reject.md`

**Interfaces:**
- Consumes: `core/doc/op.mbt` の `normalize` / `fix` / `spellable`（Task 44）、`Reject` の 3 変種（Task 43）、`delete.mbt` / `side.mbt` / `move.mbt` の拒否の返し方（Task 45〜47）
- Produces: R138（reshape / reject の一覧）・R176（rename とアンカー）・R139（参照定義と脚注の距離）の成果物となる文書 1 本

**触らないもの**: `2026-08-29-doc-model-design.md`（憲法）と `2026-08-29-op-cases.md`（カタログ）は統括の所有物。**1 バイトも書き換えない**（C16・C17 は統括が追加済み）。

- [ ] **Step 1: 節の見出しと箇条の骨格を書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/docs/superpowers/specs/2026-08-29-recover-reject.md` を新規作成し、まず骨格だけを置く。

```md
# 新 core — 回復と拒否

仕様（`2026-08-29-doc-model-design.md`）とカタログ（`2026-08-29-op-cases.md`）の補遺。
実装は `core/doc/op.mbt` の `normalize` と、各操作の `Reject`。

## 1. 回復 — normalize が直すもの

（表）

## 2. 拒否 — 操作が断るもの

（表）

## 3. 注意 — rename と GitHub の見出しアンカー

（本文）

## 4. 引き受けるもの — 参照定義と脚注の距離

（本文）
```

- [ ] **Step 2: 実装を読んで、実際の回復・拒否と突き合わせる**

Run:
```
grep -n "ok = false\|promote\|to_item\|sorted.push\|side: if depth" D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/op.mbt
grep -n "Reject(" D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/delete.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/side.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/move.mbt
```
Expected: 回復は `normalize` / `fix` / `spellable` の中だけに現れる（6 種）。拒否は `Missing` が 3 ファイル、`Ineligible` が 3 ファイル、`Cycle` が `move.mbt` だけ。**この出力と食い違う項目を書かない** — 実装に無い回復・拒否を文書に書いたら、それは仕様ではなく願望である。食い違いを見つけたら、その場で列挙して Step 3 の表から落とす。

- [ ] **Step 3: 本文を書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/docs/superpowers/specs/2026-08-29-recover-reject.md` の全文:

```md
# 新 core — 回復と拒否

仕様（`2026-08-29-doc-model-design.md`）とカタログ（`2026-08-29-op-cases.md`）の補遺。
R138（reshape / reject の列挙）・R176（rename とアンカー）・R139（参照の距離）の置き場。

## 1. 回復 — normalize が直すもの

操作（move / flipSide / delete）はどれも最後に `normalize`（`core/doc/op.mbt`）を通る。
法則 1 を破る木は、ここで**必ず**次の 8 つに畳み直される。操作ごとの例外は 1 つも無い。

| # | 直すもの | 引き金 | 直し方 |
|---|---|---|---|
| 1 | implied の消滅 | children が空になった | 木から落ちる（削除という出来事ではなく、導出されなくなるだけ） |
| 2 | implied の昇格（位置） | 前に見出しの兄弟が来た（項目の後ろは吸収されないので昇格しない） | 骨格行を書く。空ラベルの見出しが生える |
| 3 | implied の昇格（中身） | label・body・folded を持たされた | 同上 |
| 4 | implied の昇格（単調性） | Item 親の下へ来た／Item の子を持った | 同上。飛びは絶対記法でしか綴れない |
| 5 | 単調性 | Item の子孫に Heading が居る | サブツリーごと Item にする（下向きに伝播） |
| 6 | 順序法則 | 同じ親の中で Heading が Item より前に居る | Item を先、Heading を後へ並べ替える（**doc 直下にも効く**） |
| 7 | 側の落とし込み | 深さ 2 以外のノードが Left を持つ | Right へ落とす |
| 8 | implied の昇格（側） | 側のトグルを要する深さ 2 のスロットが implied | 骨格行を書いてから側を持たせる |

2・3・4・8 は同じ 1 つの規則の 4 つの顔である —— **綴りは行き先に従う**。
飛びで綴れない状態を持たされた implied は、その場で骨格行を書いて普通のノードになる。
2 が「先頭でない」ではなく「前に見出しが居る」なのは、飛びを吸収するのが見出しだけで、
項目は吸収しないからである（単調性より Item は Heading の子を持てない）。
8 だけは飛びの側に「区切りを書く行が無い」ことが理由で、他の 3 つとは引き金の出所が違う
（カタログ C16 がこの唯一の例）。

回復は決定的・冪等である（`normalize(normalize(x))` は `normalize(x)` と等しい）。

## 2. 拒否 — 操作が断るもの

拒否は例外ではなく値（`Outcome::Reject`）。種類は 3 つで、増やさない。

| 種類 | 意味 | 返す操作と条件 |
|---|---|---|
| `Missing` | 指された id が木に居ない | move（動かすものか parent）／flipSide／delete のすべて |
| `Cycle` | 自分か自分の子孫の中へ動かそうとした | move だけ |
| `Ineligible` | その操作の資格があるノードが 1 つも無い | delete: 文書そのものを指した／選択が空<br>move: 文書そのものを動かそうとした／選択が空<br>flipSide: 深さ 3 以上のノードだけを選んだ |

**資格のあるものが 1 つでもあれば通る。** flipSide の複数選択は、資格のあるものだけに効き、
残りは黙ってスキップする（部分適用を拒否に格上げしない）。

JS の受け口（`core/doc/wire.mbt`）はもう 1 つ `"unknown-op"` を返すが、これは
`op` の文字列が `"move"` / `"flip"` / `"delete"` のどれでもないときの**境界の答え**であり、
`Reject` の変種ではない。モデルの語彙は 3 つのままである。

## 3. 注意 — rename と GitHub の見出しアンカー

見出しのラベルを書き替えると、**GitHub が見出しから自動生成するアンカー（`#見出し名`）が変わる**。
その文書の中の `[…](#古い見出し)` も、外部から張られたリンクも、黙って行き先を失う。

これは mmm の欠陥ではなく md の宿命である。アンカーは見出しの本文から導出される値であって、
文書が持つ識別子ではない。mmm 側で救う手立て（旧アンカーの `<a name>` を自動で残すなど）は
綴りを増やすので**採らない**。rename は綴りを変える操作である、と受け入れる。

rename そのものは v0 の範囲外である（`add` / `fold` / `setForm` などと同じ後日箱）。
この注意書きは、実装する日に読み落とさないために先に置いてある。

## 4. 引き受けるもの — 参照定義と脚注の距離

`[x]: https://…` の参照定義や脚注の定義を含む部分木を delete すると、
文書の遠くに残った `[x]` や `[^1]` は解決先を失い、ただの文字列として表示される。
mmm は消していない（消えたのは定義であって参照ではない）ので R001 は破れていない。

遠くの参照を追いかけて一緒に消す／警告するといった救済は**作らない**。
参照は文書全体に散る値であり、比例性の原則（操作の効果は選択したもののサブツリー内に収まる）
と正面から衝突する。ユーザーの削除の帰結として引き受ける（仕様 §6 / N40）。
```

- [ ] **Step 4: 文書を読み返して、実装に無いものが書かれていないことを確かめる**

Run: `grep -c "|" D:/1.atrium/mmm/.claude/worktrees/doc-model/docs/superpowers/specs/2026-08-29-recover-reject.md`
Expected: 表が 2 つ（回復 8 行 + 見出し 2 行、拒否 3 行 + 見出し 2 行）だけ。§1 の各行の「直し方」が Step 2 の `grep` 出力（`promote` / `to_item` / `sorted.push` / `side: if depth`）のどれかに対応していること、§2 の各行が `Reject(` の grep 出力に対応していることを 1 行ずつ突き合わせる。対応の無い行が 1 つでもあれば**その行を消す**（仕様は実装より先を書かない）。**§3 と §4 は表を持たず、実装に対応する grep も持たない** — どちらも「作らないこと」の記録であって振る舞いではないので、この突き合わせの対象外である。

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add D:/1.atrium/mmm/.claude/worktrees/doc-model/docs/superpowers/specs/2026-08-29-recover-reject.md
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "docs: 📝 新 core の回復・拒否の一覧とアンカーの注意を残す"
```

---

## Task 50: 殺す条件の判定と、その記録

**Files:**
- Create: `D:/1.atrium/mmm/.claude/worktrees/doc-model/docs/superpowers/specs/2026-08-29-kill-check.md`

**Interfaces:**
- Consumes: Task 40〜48 で書いた `core/doc/{form,op,move,side,delete,edit,diff,reflect}.mbt` の全文と `test/doc-ops.test.ts`
- Produces: 「続行」か「設計を疑う」の判定 1 つと、判定の根拠となった数値を残した文書 1 本

仕様 §9 は「**法則を守るために操作側の場合分けが増え続けたら、この設計は死んでいる**」と定める。3 操作が揃った今が最初の観測点であり、観測する場所は契約が指定したとおり **`normalize` の行数**である。

- [ ] **Step 1: 静的な判定 1〜6 を回して数値を採る**

`awk` / `grep` は Bash（Git Bash）で回す。

Run:
```
awk '/^pub fn normalize/{f=1} f' D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/op.mbt | grep -c ""
grep -c "if \|match " D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/move.mbt
grep -c "if \|match " D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/side.mbt
grep -c "if \|match " D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/delete.mbt
grep -n "implied\|is_implied" D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/move.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/side.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/delete.mbt
grep -n "Missing\|Cycle\|Ineligible" D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/op.mbt
grep -n "Heading\|Item" D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/move.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/side.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/delete.mbt
grep -n -- "---\|\"#\"\|<details>" D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/op.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/move.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/side.mbt D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/delete.mbt
```
Expected:
- 1 行目（`normalize` の宣言行から EOF まで = `normalize` + `fix` + `spellable`）が **70〜80 行**（doc コメントと空行を含む。`moon fmt` の折り返しで数行動く）。**op.mbt 全体の行数ではない** — 全体には Task 43 の道具（`path_of` / `tops` / `amend` / `pluck` ほか）が入っていて 180 行を超えるが、判定 1 の対象ではない。この値は判定 1 の緑帯（60 以下）には収まらず**黄帯の下側**に入る。黄は「増分が新しい不変条件なら可」であり、ここでの増分は不変条件 8（`!heading_before`）と 11（`depth == 2 && nd.side != prev`）そのものなので、続行してよい
- `move.mbt` の `if`/`match` は **13**（`moving` 1 + `seat_in` 2 + `move_nodes` 10）、`side.mbt` は 8 以下、`delete.mbt` は 8 以下
- `implied` の grep がヒット 0 件（`turn` は `promote` を無条件に呼ぶので `implied` を書かない）
- `Reject` の変種が 3 つ（`op.mbt` の enum 宣言の 3 行）
- `Heading` / `Item` のヒット 0 件、綴り（`---` / `"#"` / `<details>`）のヒット 0 件
- **ヒット 0 件の `grep` は EXIT=1 を返す。これが緑の姿である**（出力が空であることを見る）

- [ ] **Step 2: 動的な判定 7 を回す**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-ops.test.ts` の `const CASES` を一時的に `5000` へ書き替えてから回す（環境変数の前置きは使わない）。

Run: `node --test D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-ops.test.ts`
Expected: `ℹ tests 6` / `ℹ pass 6` / `ℹ fail 0`（EXIT=0）

測り終えたら `CASES` を **120 に戻す**。戻し忘れると Task 48 のコミットとの差分が残る。

Run: `git -C D:/1.atrium/mmm/.claude/worktrees/doc-model diff --stat D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-ops.test.ts`
Expected: 出力なし（EXIT=0）

- [ ] **Step 3: 判定基準に当てて、緑／黄／赤を決める**

Step 1・2 の数値を次の基準に当てる。**1 つでも赤なら、次の操作（indent / outdent / add / setForm）を 1 行も書かずに設計へ戻る。**

| # | 判定 | 緑 | 黄 | 赤 |
|---|---|---|---|---|
| 1 | `normalize` + `fix` + `spellable` の行数（`awk '/^pub fn normalize/{f=1} f' op.mbt \| grep -c ""`。op.mbt 全体ではない） | 60 行以下 | 61〜90 行（増分が「新しい不変条件」なら可） | 91 行以上、または `fix` / `spellable` の中に操作の名前（move / delete / flip）が出る |
| 2 | 操作ごとの場合分け（`if` と `match` の腕） | `move.mbt` は 13 以下、`side.mbt` / `delete.mbt` は 8 以下 | move が 14〜19、side / delete が 9〜19 | 1 ファイルでも 20 超、または**同じ条件式が 2 ファイルに現れる**（共通の規則が normalize へ集まっていない証拠） |
| 3 | `implied` の専用分岐 | `move.mbt` / `side.mbt` / `delete.mbt` でヒット 0 件 | — | 1 件でもヒット。implied の裁定は `op.mbt` の `spellable` と `fix` の 2 か所だけに居るべき（**裁定 1 の昇格も `normalize` 側と `promote` の無条件呼び出しなので、ここは守られる**） |
| 4 | 拒否の種類 | `Missing` / `Cycle` / `Ineligible` の 3 つ | — | 4 つ目が増えている（`wire.mbt` の `"unknown-op"` は境界の答えであって変種ではない） |
| 5 | form の裁定 | 3 ファイルで `Heading` / `Item` のヒット 0 件 | — | 操作側が form を直接書いている |
| 6 | 綴りの知識 | 3 ファイル + `op.mbt` で `---` / `"#"` / `<details>` のヒット 0 件 | — | 操作が綴りを知っている。側の列から区切りを導出する規則（C3）が壊れかけている |
| 7 | ファズ（`CASES = 5000`） | 6 test 全 pass | 落ちるが原因が T2 / T3（parse / serialize）側 | 落ちる原因が「操作にもう 1 つ場合分けを足せば直る」形をしている。**これが殺す条件そのもの** |

判定 2 の緑帯を操作ごとに分けてあるのは、3 操作を同じ閾値で括るといちばん複雑な move が常に黄になり、物差しが鈍るからである。判定 1 は初回の実測（70〜80）が黄帯に入る見込みで、その増分は不変条件 8 と 11 の 2 つに対応が付く。**次の操作を足す人は、この初回の実測値を基準線にして「増えた行数が新しい不変条件に対応するか」を見る。**

判定 1〜7 のほかに、**この物差しでは測れないが次の人が最初に踏む穴を 1 行だけ記録に残す** — label の逃がしが未実装であること（下の Step 4 の文書に書く）。数値ではないので緑／黄／赤は付けない。

- [ ] **Step 4: 判定の結果を文書に書き残す**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/docs/superpowers/specs/2026-08-29-kill-check.md` を新規作成する。**残すのは Why（判定基準と数値）だけで、How の苦闘は残さない。** 数値は Step 1・2 の実測に差し替える。

```md
# 新 core — 殺す条件の判定（3 操作が揃った時点）

仕様 §9 の「操作側の場合分けが増え続けたら、この設計は死んでいる」の最初の観測。
基準は下表。次の操作（indent / outdent / add / setForm）を足す人は、同じ物差しで測り直すこと。

| # | 判定 | 基準（緑） | 実測 | 結果 |
|---|---|---|---|---|
| 1 | `normalize` + `fix` + `spellable` の行数（`awk '/^pub fn normalize/{f=1} f' op.mbt \| grep -c ""`） | 60 以下 | <実測> | <緑/黄/赤> |
| 2 | `if`/`match` の腕（move / side / delete） | move 13 以下 / side・delete 8 以下 | <実測> / <実測> / <実測> | <緑/黄/赤> |
| 3 | 3 ファイルの `implied` 出現 | 0 | <実測> | <緑/黄/赤> |
| 4 | `Reject` の変種 | 3 | <実測> | <緑/黄/赤> |
| 5 | 3 ファイルの `Heading`/`Item` 出現 | 0 | <実測> | <緑/黄/赤> |
| 6 | 3 ファイル + op.mbt の綴り出現 | 0 | <実測> | <緑/黄/赤> |
| 7 | `CASES = 5000` の doc-ops | 6 test 全 pass | <実測> | <緑/黄/赤> |

判定 1 が黄のときは、増分がどの不変条件に対応するかを 1 行で書く
（初回は不変条件 8「implied の前に見出しが居ない」と 11「implied は側を持たない」の 2 つ）。

**label の逃がしは未実装。** モデル側には前後空白・末尾 `#` を持つ label を書けるが、
それは範囲外の rename が入るまで生成経路が無い（parse は `atx_writable` で弾き、
ファズの `labels` も持たない）。書けてしまった日は法則 1 が必ず落ちる —
serialize は逃がさず、読み直しの `atx_at` が trim するからである。
rename を足すときは、逃がし方（`spell.mbt` の綴り）を先に決めること。

判定: **<続行 / 設計を疑う>**。
```

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add D:/1.atrium/mmm/.claude/worktrees/doc-model/docs/superpowers/specs/2026-08-29-kill-check.md
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "docs: 📝 殺す条件の判定結果を残す"
```

---

## T5 が他へ渡すもの（申し送り）

- **`fixture_wbtest.mbt` への追記は Task 43 の `done` / `rejected` の 2 本だけ。** それ以外は T1 の所有物のまま
- `flip_side` の `turn` は **`promote(nd, nd.label)` を無条件に呼ぶ**。裁定 1（implied は昇格してから反転）を満たしつつ、`side.mbt` に `implied` のリテラルを 1 つも書かないための綴りである。**この 1 行を「無駄な呼び出し」として削らないこと** — 削ると C16 が落ち、Task 50 の判定 3 も同時に赤になる
- `normalize` の `spellable` は**引き金 4 つ**（前に見出しが居る／中身を持つ／Item が絡む／側のトグルを要する）を持つ。5 つ目を足したくなったら、それは仕様の穴か設計の死のどちらかである。足す前に統括へ上げる
- **`spellable` の第 1 の引き金は `!heading_before` であって `at == 0` ではない**（裁定 B・不変条件 8）。項目は飛びを吸収しないので、項目 root の後ろの implied は綴れる。`fix` が並べ替えた後の列を走りながら `seen_heading` を持ち回るのが対になる実装で、この 2 つは同時に直すこと
- **`refit` は仕様 §4 の ①単調性・②順序法則だけを実装する。③兄弟の真似・④policy（Hybrid(N)・リアルタイム推定）は `add` / `setForm` と一緒に次の計画で入る** — 網羅漏れではない。**move が ①② だけで足りるのは、動かす対象の form が既に決まっているから**であり、③④ は「まだ form が無いものに form を与える」規則である。policy は保存されない値なので、実装しないことで欠ける状態は存在しない。`add` を作る者が §4 の ③④ をそこで実装する
- **裁定 E（`scan_head` の「開き `---` の直後が空行なら封筒ではない」）は T5 の期待値を 1 つも動かさない。** T5 の木はすべて手組みで `sig` しか見ないため。Task 48 のファズで「最小反例が `---` で始まり木が消える」形が出たら、直す場所は T1 の `scan_head` である
- `move_nodes` の `parent` には**文書の id（1）も渡せる**。root 化も root の並べ替えもこれで表す（R059 / R060）。UI 接続の日に「root 専用の操作」を足さないこと
- `test/doc-ops.test.ts` は `test/_doc.ts`（T4）の export だけを使う。T4 が export 名を変えたら、**このファイルを直すのは T5 ではなく、正誤表 D-3 を先に改訂すること**
- ファズの回数は `const CASES` の書き替えで切り替える（環境変数の前置きは使わない）。深掘りしたら **120 に戻してからコミットする**
