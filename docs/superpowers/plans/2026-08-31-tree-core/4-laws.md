# G4 — 境界・法則・カタログ

新 core 実装計画の第 4 群。**唯一の参照元は確定版の契約**
（`scratchpad/v2/contract2.md`）で、この計画と契約が食い違ったら契約が正。
とくに §2（所有権）/ §3（依存順）/ §4（名前）/ §9（`<summary>`）/ §13（境界）/
§15（方言）/ §16（テストの本数）/ §17（コマンド）/ §19 の G4 の節に従う。

## この群の概要

### 担当範囲

**境界と、そこに立てる法則。** 木は境界を跨げないので、G4 は 2 つの場所に住む —
mbt 側（`json` / `project` / `#export_name` / 木を種にする法則 1）と、
TS 側（md を種にする法則 1・2・3、外部審判による法則 4、カタログ C1〜C17、操作の性質）。

| ファイル | 新規 / 変更 | 中身 |
|---|---|---|
| `core/tree/json.mbt` | 新規 | `quote` / `strings` / `hex` / `reflect_json` |
| `core/tree/json_wbtest.mbt` | 新規 | 逃がし規則と境界の JSON |
| `core/tree/project.mbt` | 新規 | `project` / `map_bucket` / `map_branch` / `map_node` / `map_card` |
| `core/tree/project_wbtest.mbt` | 新規 | バケツ分け・buried・implied |
| `core/tree/laws_wbtest.mbt` | 新規 | **木の生成器**と法則 1 の本丸 |
| `core/tree/js/moon.pkg` | 新規 | `foreign_library` + import 1 本 |
| `core/tree/js/exports.mbt` | 新規 | `#export_name` 7 本 |
| `test/_tree.ts` | 新規 | 窓口・生成器・コーパス・縮小器 |
| `test/treeLaws.test.ts` | 新規 | 法則 1・2・3 |
| `test/treeDialect.test.ts` | 新規 | 法則 4（`DIALECT` + `READING`） |
| `test/treeCases.test.ts` | 新規 | カタログ C1〜C17 |
| `test/treeOps.test.ts` | 新規 | 操作の性質のファズ（設計は G5 由来） |
| `test/tsconfig.json` | 変更 | 死んだ 2 行を掃く |
| `package.json` | 変更 | `test:core` / `fmt:doc` |
| `.github/workflows/ci.yml` | 変更 | 新パッケージのテスト・整形・`Total tests: 0` の検知 |

**この表に無いファイルには 1 バイトも書かない**（契約 §2）。とくに
`core/tree/scan.mbt`（G1）/ `core/tree/parse.mbt`（G2）/ `core/tree/serialize.mbt`（G3）/
`core/tree/tool.mbt` `op.mbt` `diff.mbt`（G5）は**読むだけ**。スタブも、投機的な追加も、
警告を消すための小細工も禁止。直しが要ると分かったら、下の差し戻し表で該当群へ戻す。

### 前提

- **G1 / G2 / G3 / G5 が全部緑になっていること**（契約 §3 の依存順
  `G1 → (G2 / G3) → G5 → G4`）。**G4 は最後に走る検証群**で、
  自分の所有ファイルの中にだけ実装を書く
- 作業場所は `D:/1.atrium/mmm/.worktrees/feat/tree-core`（ブランチ `feat/tree-core`）
- ツールチェイン: `moon 0.1.20260803` / `moonc v0.10.6+80dc50f24` / Branch `v24.16.0` /
  pnpm `11.21.0` / TypeScript `^5.6.0` / `@lezer/markdown` `1.7.2`（devDependencies）
- **Run 行は絶対パス**。`pnpm` を使う Step は cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`
- **Step 2 / Step 4 の mbt テストはファイル指定**、群の締め（Task 71）だけ `-p`（契約 §17）

### 着手順

```
60 json.mbt → 61 project.mbt → 62 境界 → 63 _tree.ts → 64 生成器 → 65 縮小器
  → 66 法則2 → 67 法則1(md)+check → 68 法則1(木・mbt) → 69 法則4
  → 70 カタログ → 71 CI → 72 操作の性質
```

一直線。Task 60 の `reflect_json` は G5 の `Reflection` を受けるので、
G5 が終わっていない状態では着手できない（契約 §3）。

### 新設する名前の一覧（契約 §4 の逐語）

| 名前 | 住所 | 何 |
|---|---|---|
| `quote` / `strings` / `hex` / `reflect_json` | `core/tree/json.mbt` | JSON の綴り |
| `project` / `map_bucket` / `map_branch` / `map_node` / `map_card` | `core/tree/project.mbt` | 投影 |
| （新設なし） | — | 木の組み立ては G1 の `make_*` を呼ぶ（契約 §4） |
| `Law` / `law_pick` / `law_id` / `law_head_label` / `law_item_label` / `law_block` / `law_side` / `law_node` / `law_branches` / `law_branch` / `law_wings` / `law_implicit_root` / `law_doc` | `core/tree/laws_wbtest.mbt` | 木の生成器 |
| `sig` / `format` / `check` / `project` / `move_nodes` / `flip_side` / `delete_nodes` | `core/tree/js/exports.mbt` | 境界 7 本（別パッケージ） |
| `Edit` / `Reflection` / `Card` / `MapNode` / `MapBranch` / `MapTree` / `Mindmap` / `doc` / `mbt` / `apply` / `cardText` / `rng` / `randomDoc` / `pathological` / `shrink` / `corpus` / `fuzzCases` / `brief` | `test/_tree.ts` | TS の窓口 |
| `outerNodes` / `mmmNodes` / `DIALECT` / `READING` | `test/treeDialect.test.ts` | 外部審判 |
| `idOf` | `test/treeCases.test.ts` | ラベル → id |
| `idsOf` / `holds` | `test/treeOps.test.ts` | 操作の性質 |
| `fmt:doc` | `package.json` | 新パッケージだけの整形検査 |

**作らない名前**（契約 §4）:

- **`same` は作らない。** 側の等値は G3 の `same_side`（`serialize.mbt`）1 本。
  `map_bucket` はそれを呼ぶ（`Side` に `Eq` は無い）
- **`hashes(line, at) -> Int` は作らない。** 7 個以上の `#` は G1 の `head_at`
  （level に上限なし）が既に読む。同名を置くと `Error: [4051] declared twice` でビルドが止まる
- `gap` / `trim_tail` / `spellable` / `fold_owner` / `close_items` — **どれも G4 は書かない**
  （G3 の `put` / G5 の `conform` / G2 の Head の腕が既に持っている）

### 赤の差し戻し表（Task 66〜70・72 で共通に使う）

G4 のテストが赤になったら、**落ちたアサーションのメッセージが担当群を名指す**。
G4 は自分の所有ファイル以外を直さない。

| 赤の見え方 | 差し戻し先 |
|---|---|
| 指紋の `e` の後の `^` / `_` が違う | 畳み — G3 Task 44 / G2 Task 25 |
| `>` / `<` が違う | 側 — G3 Task 43 / G2 Task 24 |
| `i` が増減する | Implicit の導出 — G2 Task 21 |
| `i` が `eh_` に化けた | **serialize が勝手に昇格している**。G3 Task 41 へ差し戻す（昇格は G5 の `conform` が model 側で済ませている） |
| `(...)` の中身が違う | 中身の認定 — G2 Task 23 |
| 末尾改行・空行の本数 | G3 Task 41 の `put` |
| `o…:<summary>…` が増える | **`<summary>` の読み飛ばし** — G2 Task 25（契約 §9） |
| `check` が空でない木が出た | **parse のバグ**（serialize でも sig でもない）— G2 |
| 「適用後も健全」が落ちた | `conform` / `prune` — G5 Task 85 / 87 |
| 「当てれば一致」が落ちた | `diff` / `apply` — G5 Task 90 / 91 |
| 「拒否は無編集」が落ちた | `reflect` — G5 Task 92 |

差し戻すときは**該当群の wbtest に固定を 1 本足してもらってから**この Task に戻る。
**G4 はテストを 1 行も緩めない。**

### カタログを読むときの注意（Task 70 で使う）

- **C8 の md は `<summary>` 行を含む形が正**（契約 §9）。serialize は畳んだノードに
  `<details>` + `<summary>label</summary>` を必ず書き、parse は `<details>` の直後の
  `<summary>…</summary>` 行を**内容を見ずに 1 枚だけ**読み飛ばす。
  `docs/superpowers/specs/2026-08-29-op-cases.md` の C8 は **G3 Task 46 が先に直す**
- **手で書いた `<summary>` は残らない。** これは意味の損失で、爆風半径として
  `docs/ops.md`（G5 Task 94 の所有）に 1 行載る。G4 はその文書を書かない
- **C7 は v0 と v1 で新 md が違う。** v0（この計画の範囲）は全文正規形なので、
  a の body にある飾りの `---` はチャンネル分離で `***` になる。
  カタログの新 md（`---` のまま）はすげ替え v1 が入ってから成立する
- **C15 の「無操作は無編集」も、`format` を通せば綴りは正規形へ寄る**（指紋は不動）
- **C1 / C2 / C6 / C10 / C12 / C13 の操作（add / rename / 打鍵）はこの計画のスコープ外。**
  読み（指紋）と正規形だけを固定する。C8 の fold も同じ
- **指紋の逐語は契約 §8 の文法から導いたもの。** 実装と食い違ったら、
  どちらが正しいかを §8 に照らして決めること（テストを黙って書き換えない）

### この群のテスト本数（契約 §16）

| 場所 | ファイル | 本数 |
|---|---|---|
| mbt | `core/tree/json_wbtest.mbt` | 5 |
| mbt | `core/tree/project_wbtest.mbt` | 3 |
| mbt | `core/tree/laws_wbtest.mbt` | 2 |
| mbt | （G4 合計） | **10** |
| TS | `test/treeLaws.test.ts` | 12 |
| TS | `test/treeDialect.test.ts` | 3 |
| TS | `test/treeCases.test.ts` | 17 |
| TS | `test/treeOps.test.ts` | 5 |
| TS | （G4 合計） | **37** |

新パッケージの mbt 合計は 111 本（G1 25 / G2 23 / G3 21 / G5 32 / G4 10）。
旧 core が 192 本なので、`pnpm run test:core` の締めは **303 本**。

---

## Task 60: JSON の綴り（`quote` / `strings` / `reflect_json`）

**Files:**
- Create: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/json.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/json_wbtest.mbt`

**Interfaces:**
- Consumes: `Reflection` / `Edit`（G5 `diff.mbt`・契約 §10）
- Produces: `pub fn quote(s : String) -> String` / `pub fn strings(xs : Array[String]) -> String` /
  `pub fn reflect_json(r : Reflection) -> String` / `fn hex(n : Int) -> String`

**なぜ G4 が `reflect_json` を持つのか**: `reflect_json` は `quote` を呼ぶ。
G5 に置くと G5 → G4 の依存が生まれて依存順が輪になる。G4 へ移せば
G5 の `reflect` は `Reflection` を返す純関数で済み、依存が 1 本道になる（契約 §3）。

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/json_wbtest.mbt` を新規作成する。

```moonbit
// JSON の綴りの固定。境界を渡るのは文字列だけなので、逃がしの規則をここで守る。
// 反映の JSON（契約 §13）もこの 1 か所が吐く。

///|
test "quote は引用符・逆斜線・改行・タブを逃がす" {
  assert_eq(quote("a\"b"), "\"a\\\"b\"")
  assert_eq(quote("a\\b"), "\"a\\\\b\"")
  assert_eq(quote("a\nb"), "\"a\\nb\"")
  assert_eq(quote("a\rb"), "\"a\\rb\"")
  assert_eq(quote("a\tb"), "\"a\\tb\"")
}

///|
test "quote は制御文字を \\u00XX へ逃がす" {
  assert_eq(quote("a\u{0}b"), "\"a\\u0000b\"")
  assert_eq(quote("\u{1f}"), "\"\\u001f\"")
}

///|
test "quote は非 ASCII とサロゲートペアをそのまま通す" {
  assert_eq(quote("日本語🙂"), "\"日本語🙂\"")
}

///|
test "strings は文字列の列を JSON の配列にする" {
  assert_eq(strings([]), "[]")
  assert_eq(strings(["a"]), "[\"a\"]")
  assert_eq(strings(["a", "b\"c"]), "[\"a\",\"b\\\"c\"]")
}

///|
test "reflect_json は境界の形をちょうど 1 つ吐く" {
  assert_eq(
    reflect_json({
      ok: false,
      reason: "見つからない (id=7)",
      text: "#  r  \n\n## a\n",
      edits: [],
    }),
    "{\"ok\":false,\"reason\":\"見つからない (id=7)\",\"text\":\"#  r  \\n\\n## a\\n\",\"edits\":[]}",
  )
  assert_eq(
    reflect_json({
      ok: true,
      reason: "",
      text: "# r\n",
      edits: [{ from: 0, to: 3, insert: "x" }],
    }),
    "{\"ok\":true,\"reason\":\"\",\"text\":\"# r\\n\",\"edits\":[{\"from\":0,\"to\":3,\"insert\":\"x\"}]}",
  )
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/json_wbtest.mbt`
Expected: `Error: [4021]` / `The value identifier quote is unbound.`
（`strings` と `reflect_json` も同じ）。EXIT=1

- [ ] **Step 3: 最小の実装を書く**

`core/tree/json.mbt` を新規作成する。

```moonbit
// JSON の綴り。境界を渡るのは文字列だけなので、逃がし規則はここに 1 か所。

///|
/// 文字列を JSON の `"..."` にする。制御文字は `\u00XX` へ逃がす。
pub fn quote(s : String) -> String {
  let sb = StringBuilder::new()
  sb.write_string("\"")
  for c in s.iter() {
    match c {
      '"' => sb.write_string("\\\"")
      '\\' => sb.write_string("\\\\")
      '\n' => sb.write_string("\\n")
      '\r' => sb.write_string("\\r")
      '\t' => sb.write_string("\\t")
      _ =>
        if c.to_int() < 0x20 {
          sb.write_string("\\u00")
          sb.write_string(hex(c.to_int() / 16))
          sb.write_string(hex(c.to_int() % 16))
        } else {
          sb.write_char(c)
        }
    }
  }
  sb.write_string("\"")
  sb.to_string()
}

///|
/// 文字列の列を JSON の配列にする（check の破れが通る道）。
pub fn strings(xs : Array[String]) -> String {
  let sb = StringBuilder::new()
  sb.write_string("[")
  for k, x in xs {
    if k > 0 {
      sb.write_string(",")
    }
    sb.write_string(quote(x))
  }
  sb.write_string("]")
  sb.to_string()
}

///|
/// 境界を渡る唯一の形。struct は跨がず、文字列 1 本で渡す。
pub fn reflect_json(r : Reflection) -> String {
  let sb = StringBuilder::new()
  sb.write_string("{\"ok\":")
  sb.write_string(if r.ok { "true" } else { "false" })
  sb.write_string(",\"reason\":")
  sb.write_string(quote(r.reason))
  sb.write_string(",\"text\":")
  sb.write_string(quote(r.text))
  sb.write_string(",\"edits\":[")
  for k, e in r.edits {
    if k > 0 {
      sb.write_string(",")
    }
    sb.write_string("{\"from\":")
    sb.write_string(e.from.to_string())
    sb.write_string(",\"to\":")
    sb.write_string(e.to.to_string())
    sb.write_string(",\"insert\":")
    sb.write_string(quote(e.insert))
    sb.write_string("}")
  }
  sb.write_string("]}")
  sb.to_string()
}

///|
fn hex(n : Int) -> String {
  String::unsafe_substring("0123456789abcdef", start=n, end=n + 1)
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/json_wbtest.mbt`
Expected: `Total tests: 5, passed: 5, failed: 0.` EXIT=0

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt --check tree`
Expected: `Finished. moon: ran N tasks, now up to date` EXIT=0

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/json.mbt core/tree/json_wbtest.mbt
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ JSON の綴りを 1 か所に置く"
```

---

## Task 61: 投影（Doc → MindmapTree）

**Files:**
- Create: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/project.mbt`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/project_wbtest.mbt`

**Interfaces:**
- Consumes: `Doc` / `Root` / `Wing` / `Branch` / `Node` / `Sign` / `Side` / `Eol` /
  `Block` / `Content`（G1・契約 §6）、`quote`（Task 60）、
  **`same_side`（G3 `serialize.mbt`）**
- Produces: `pub fn project(doc : Doc) -> String`（契約 §14 の JSON）/
  `map_bucket` / `map_branch` / `map_node` / `map_card`

**`same` を作らない理由**: 同じ判定が 2 か所に割れる負債。`Side` に `Eq` は無いので
判定関数は要るが、G3 が既に `same_side(a : Side, b : Side) -> Bool` を同一パッケージに
置いている（契約 §4）。G4 はそれを呼ぶ。

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/project_wbtest.mbt` を新規作成する。ヘルパの接頭辞は `proj_`
（`project.mbt` が `map_node` 等を名乗るので `map_` は使えない。契約 §4）。

```moonbit
// 投影の固定。バケツ分け・buried・implied の 3 点だけを見る（描き方は render の自由）。
// 接頭辞が proj_ なのは、project.mbt が既に map_node / map_branch を名乗っているから。

// 葉と文書の組み立ては G1 の `make_wbtest.mbt`（`make_branch` / `make_head` / `make_doc`）を使う。
// 同じ木を組む道具を 2 セット持たない（契約 §4 の「`make_*` に統一」）。

///|
test "バケツ分けは wings の filter — 側ごとに順序を保つ" {
  let root : Root = {
    id: 2,
    node: Explicit(sign=Heading, label="r", folded=false, body=[]),
    wings: [
      { side: Right, branch: make_branch(3, make_head("a"), []) },
      { side: Left, branch: make_branch(4, make_head("b"), []) },
      { side: Right, branch: make_branch(5, make_head("c"), []) },
    ],
  }
  assert_eq(
    project(make_doc([root])),
    "{\"trees\":[{\"branch\":{\"id\":2,\"label\":\"r\",\"implied\":false," +
    "\"folded\":false,\"sign\":\"heading\",\"cards\":[],\"buried\":0}," +
    "\"right\":[{\"branch\":{\"id\":3,\"label\":\"a\",\"implied\":false," +
    "\"folded\":false,\"sign\":\"heading\",\"cards\":[],\"buried\":0}," +
    "\"children\":[]},{\"branch\":{\"id\":5,\"label\":\"c\",\"implied\":false," +
    "\"folded\":false,\"sign\":\"heading\",\"cards\":[],\"buried\":0}," +
    "\"children\":[]}],\"left\":[{\"branch\":{\"id\":4,\"label\":\"b\"," +
    "\"implied\":false,\"folded\":false,\"sign\":\"heading\",\"cards\":[]," +
    "\"buried\":0},\"children\":[]}]}],\"buried\":0}",
  )
}

///|
test "buried は絵に出ない Block の数。cards は Content と 1 対 1" {
  let root : Root = {
    id: 2,
    node: Explicit(sign=Item, label="r", folded=true, body=[
      Opaque("> quote"),
      Content(Image(alt="a", src="./x.png")),
      Rule,
      Content(Code(info="js", text="1")),
    ]),
    wings: [],
  }
  assert_eq(
    project(make_doc([root])),
    "{\"trees\":[{\"branch\":{\"id\":2,\"label\":\"r\",\"implied\":false," +
    "\"folded\":true,\"sign\":\"item\",\"cards\":[{\"kind\":\"image\"," +
    "\"alt\":\"a\",\"src\":\"./x.png\"},{\"kind\":\"code\",\"info\":\"js\"," +
    "\"text\":\"1\"}],\"buried\":2},\"right\":[],\"left\":[]}],\"buried\":0}",
  )
}

///|
test "implied は空ラベルの見出しとして出る。文書の散文は trees の外で数える" {
  let doc : Doc = {
    frontmatter: None,
    eol: Lf,
    body: [Opaque("intro"), Rule],
    roots: [
      {
        id: 2,
        node: Implicit,
        wings: [{ side: Right, branch: make_branch(3, "b") }],
      },
    ],
  }
  assert_eq(
    project(doc),
    "{\"trees\":[{\"branch\":{\"id\":2,\"label\":\"\",\"implied\":true," +
    "\"folded\":false,\"sign\":\"heading\",\"cards\":[],\"buried\":0}," +
    "\"right\":[{\"branch\":{\"id\":3,\"label\":\"b\",\"implied\":false," +
    "\"folded\":false,\"sign\":\"heading\",\"cards\":[],\"buried\":0}," +
    "\"children\":[]}],\"left\":[]}],\"buried\":2}",
  )
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/project_wbtest.mbt`
Expected: `Error: [4021]` / `The value identifier project is unbound.` EXIT=1

- [ ] **Step 3: 最小の実装を書く**

`core/tree/project.mbt` を新規作成する。

```moonbit
// Doc → MindmapTree。map への矢印はこの 1 本だけ（法則 3）。
// バケツ分けは wings の filter — 側をまたぐ読み順はここで意図的に落ちる。
// 側の等値は G3 の same_side を呼ぶ（Side に Eq は無い。判定を 2 か所に割らない）。

///|
pub fn project(doc : Doc) -> String {
  let sb = StringBuilder::new()
  sb.write_string("{\"trees\":[")
  for k, r in doc.roots {
    if k > 0 {
      sb.write_string(",")
    }
    sb.write_string("{\"branch\":")
    map_node(sb, r.id, r.node)
    sb.write_string(",\"right\":")
    map_bucket(sb, r.wings, Right)
    sb.write_string(",\"left\":")
    map_bucket(sb, r.wings, Left)
    sb.write_string("}")
  }
  sb.write_string("],\"buried\":")
  sb.write_string(doc.body.length().to_string())
  sb.write_string("}")
  sb.to_string()
}

///|
fn map_bucket(
  sb : StringBuilder,
  wings : Array[Wing],
  side : Side,
) -> Unit {
  sb.write_string("[")
  let mut first = true
  for b in wings {
    if same_side(b.side, side) {
      if !first {
        sb.write_string(",")
      }
      first = false
      map_branch(sb, b.branch)
    }
  }
  sb.write_string("]")
}

///|
fn map_branch(sb : StringBuilder, branch : Branch) -> Unit {
  sb.write_string("{\"branch\":")
  map_node(sb, branch.id, branch.node)
  sb.write_string(",\"children\":[")
  for k, c in branch.children {
    if k > 0 {
      sb.write_string(",")
    }
    map_branch(sb, c)
  }
  sb.write_string("]}")
}

///|
/// implied は見出しの飛びからしか生まれないので sign は heading、
/// label は空、folded は false、cards も buried も 0。
fn map_node(sb : StringBuilder, id : Int, node : Node) -> Unit {
  sb.write_string("{\"id\":")
  sb.write_string(id.to_string())
  match node {
    Implicit =>
      sb.write_string(
        ",\"label\":\"\",\"implied\":true,\"folded\":false," +
        "\"sign\":\"heading\",\"cards\":[],\"buried\":0}",
      )
    Explicit(sign~, label~, folded~, body~) => {
      sb.write_string(",\"label\":")
      sb.write_string(quote(label))
      sb.write_string(",\"implied\":false,\"folded\":")
      sb.write_string(if folded { "true" } else { "false" })
      sb.write_string(",\"sign\":")
      sb.write_string(
        match sign {
          Heading => "\"heading\""
          Item => "\"item\""
        },
      )
      sb.write_string(",\"cards\":[")
      let mut first = true
      let mut buried = 0
      for b in body {
        match b {
          Content(c) => {
            if !first {
              sb.write_string(",")
            }
            first = false
            map_card(sb, c)
          }
          _ => buried = buried + 1
        }
      }
      sb.write_string("],\"buried\":")
      sb.write_string(buried.to_string())
      sb.write_string("}")
    }
  }
}

///|
fn map_card(sb : StringBuilder, content : Content) -> Unit {
  match content {
    Image(alt~, src~) => {
      sb.write_string("{\"kind\":\"image\",\"alt\":")
      sb.write_string(quote(alt))
      sb.write_string(",\"src\":")
      sb.write_string(quote(src))
      sb.write_string("}")
    }
    Link(text~, href~) => {
      sb.write_string("{\"kind\":\"link\",\"text\":")
      sb.write_string(quote(text))
      sb.write_string(",\"href\":")
      sb.write_string(quote(href))
      sb.write_string("}")
    }
    Code(info~, text~) => {
      sb.write_string("{\"kind\":\"code\",\"info\":")
      sb.write_string(quote(info))
      sb.write_string(",\"text\":")
      sb.write_string(quote(text))
      sb.write_string("}")
    }
    Svg(s) => {
      sb.write_string("{\"kind\":\"svg\",\"svg\":")
      sb.write_string(quote(s))
      sb.write_string("}")
    }
  }
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/project_wbtest.mbt`
Expected: `Total tests: 3, passed: 3, failed: 0.` EXIT=0

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt --check tree`
Expected: EXIT=0

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/project.mbt core/tree/project_wbtest.mbt
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ Doc から MindmapTree への矢印を 1 本だけ引く"
```

---

## Task 62: 境界（JS へ出す 7 本）

**Files:**
- Create: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/js/moon.pkg`
- Create: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/js/exports.mbt`
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/package.json`

**Interfaces:**
- Consumes: `parse`（G2）/ `serialize`（G3）/ `sig` `check`（G1）/
  `project` `strings` `reflect_json`（Task 60・61）/
  `reflect` `move_nodes` `flip_side` `delete_nodes`（G5）/ `Side`（G1）
- Produces: JS の 7 関数 `sig` / `format` / `check` / `project` / `moveNodes` /
  `flipSide` / `deleteNodes`。生成物は `core/_build/js/release/build/tree/js/js.js`

- [ ] **Step 1: 失敗するテストを書く**

テストは JS 生成そのもの。まず `core/tree/js/moon.pkg` を新規作成する
（**別名は書かない** — `moon fmt` が最終パスセグメントと同じ別名を剥がす。契約 §13）。

```
pkgtype(kind: "foreign_library")

import {
  "mmm-app/core/tree",
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `pnpm run core`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`。別のワークツリーから叩くと旧 core を測る）
Expected: `Finished.` EXIT=0（`exports.mbt` がまだ無いので中身は空）

Run: `branch -e "import('./core/_build/js/release/build/tree/js/js.js').then(m=>console.log(Object.keys(m))).catch(e=>console.log('ERR', e.code))"`
（**この 2 行の Expected は未実測**。空の foreign_library に対して `pnpm run core` が通るか、生成物が出るかは moon の版に依る。実際の出力を見てから Expected を確定させ、落ちる場合は `exports.mbt` を置く順を先に回すこと。合格条件は次の Step 4 の緑）
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: `[]`

- [ ] **Step 3: 最小の実装を書く**

`core/tree/js/exports.mbt` を新規作成する（契約 §13 の逐語）。

```moonbit
// mmm-app/core/tree の薄い JS 層。struct は 1 つも跨がず、出入りは String だけ。
// library パッケージを `moon test` で叩けるように、ここだけ分けてある。

///|
#export_name("sig")
pub fn sig(md : String) -> String {
  @tree.sig(@tree.parse(md))
}

///|
#export_name("format")
pub fn format(md : String) -> String {
  @tree.serialize(@tree.parse(md))
}

///|
#export_name("check")
pub fn check(md : String) -> String {
  @tree.strings(@tree.check(@tree.parse(md)))
}

///|
#export_name("project")
pub fn project(md : String) -> String {
  @tree.project(@tree.parse(md))
}

///|
#export_name("moveNodes")
pub fn move_nodes(
  md : String,
  ids : Array[Int],
  parent : Int,
  at : Int,
  left : Bool,
) -> String {
  @tree.reflect_json(
    @tree.reflect(md, fn(d) {
      @tree.move_nodes(
        d,
        ids,
        parent,
        at,
        if left {
          @tree.Left
        } else {
          @tree.Right
        },
      )
    }),
  )
}

///|
#export_name("flipSide")
pub fn flip_side(md : String, ids : Array[Int]) -> String {
  @tree.reflect_json(@tree.reflect(md, fn(d) { @tree.flip_side(d, ids) }))
}

///|
#export_name("deleteNodes")
pub fn delete_nodes(md : String, ids : Array[Int]) -> String {
  @tree.reflect_json(@tree.reflect(md, fn(d) { @tree.delete_nodes(d, ids) }))
}
```

`package.json` の scripts を差し替える。

```
"test:core": "cd core && moon test -p mmm-app/core",
```
を
```
"test:core": "cd core && moon test -p mmm-app/core -p mmm-app/core/tree",
"fmt:doc": "cd core && moon fmt --check tree tree/js",
```
に変える（`fmt:doc` は新規行。**対象は新パッケージのディレクトリだけ** —
旧 `core/js` を含めた瞬間に赤になる。契約 §17 の罠）。

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `pnpm run core`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: `Finished. moon: ran N tasks, now up to date (M warnings, 0 errors)` EXIT=0。
`core/_build/js/release/build/tree/js/js.d.ts` が契約 §13 の逐語になる:

```ts
import type * as MoonBit from "./moonbit.d.ts";

export function deleteNodes(md: MoonBit.String,
                            ids: any): MoonBit.String;

export function flipSide(md: MoonBit.String,
                         ids: any): MoonBit.String;

export function moveNodes(md: MoonBit.String,
                          ids: any,
                          parent: MoonBit.Int,
                          at: MoonBit.Int,
                          left: MoonBit.Bool): MoonBit.String;

export function project(md: MoonBit.String): MoonBit.String;

export function check(md: MoonBit.String): MoonBit.String;

export function format(md: MoonBit.String): MoonBit.String;

export function sig(md: MoonBit.String): MoonBit.String;
```

Run: `pnpm run test:core`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: `Total tests: 301, passed: 301, failed: 0.` EXIT=0
（旧 core 192 + G1 25 + G2 23 + G3 21 + G5 32 + G4 の json 5・project 3 = 301。
`laws_wbtest` の 2 本は Task 68 で足すので、締めの Task 71 で 303 になる。
**`Total tests: 0` なら `-p` の綴りを疑う** — 契約 §17 の罠）

Run: `pnpm run fmt:doc`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: `Finished. moon: ran N tasks, now up to date` EXIT=0

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/js package.json
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "feat: ✨ 新 core の境界を建てる（struct は 1 つも跨がせない）"
```

---

## Task 63: TS の窓口

**Files:**
- Create: `D:/1.atrium/mmm/.worktrees/feat/tree-core/test/_tree.ts`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/test/treeLaws.test.ts`
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/test/tsconfig.json`

**Interfaces:**
- Consumes: `core/_build/js/release/build/tree/js/js.js` の 7 関数（Task 62）
- Produces: `mbt` / `doc`（7 メソッド）/ `apply` / `cardText` / `rng` / `randomDoc` /
  `corpus` / `fuzzCases` / `brief` と、型 `Edit` / `Reflection` / `Card` /
  `MapNode` / `MapBranch` / `MapTree` / `Mindmap`

**型は全フィールド `readonly`**（契約 §14）。MindmapTree は絶対に変異させない
（投影の逆写像を作らない = 法則 3）ので、**逆写像を書いた瞬間 tsc が止まる**ようにしておく。
実行時コストはゼロ（`JSON.parse` の戻りに型を付けるだけ）。

- [ ] **Step 1: 失敗するテストを書く**

`test/treeLaws.test.ts` を新規作成する。まずは窓口が生きていることと、法則 3 を見る。

```typescript
// 法則 1・2・3 のファズ。土台の証明はここ（操作ゼロ）。
//
// 法則 1: parse(serialize(M)) = M   … 木を種にする本丸は core/tree/laws_wbtest.mbt。
//   ここは md を種にした版（sig(format(md)) == sig(md)）で、実文書とコーパスを食わせる。
// 法則 2: serialize(parse(md)) は 2 回目から不動 … これがフォーマットの定義。
// 法則 3: map へ出る口は project 1 本 … 境界の輸出そのものを数えて固定する。

import { test } from "branch:test";
import assert from "branch:assert/strict";
import { apply, doc, mbt } from "./_tree.ts";

test("境界: 反映は ok / reason / text / edits の 4 つを返し、edits は text へ届く", () => {
  const md = "# r\n\n## a\n";
  const bad = doc.flipSide(md, [99]);
  assert.equal(bad.ok, false);
  assert.equal(bad.reason, "側を変えられるのは root と root 直下の枝だけ (id=99)");
  assert.equal(bad.text, md);
  assert.deepEqual(bad.edits, []);
  assert.equal(apply(md, bad.edits), bad.text);
});

test("境界: check は破れの配列、project は trees と buried を返す", () => {
  assert.deepEqual(doc.check("# r\n"), []);
  const m = doc.project("# r\n");
  assert.equal(m.trees.length, 1);
  assert.equal(m.trees[0]!.branch.label, "r");
  assert.equal(m.buried, 0);
});

test("法則 3: 境界から木の形で出る口は project だけ", () => {
  assert.deepEqual(Object.keys(mbt).sort(), [
    "check",
    "deleteNodes",
    "flipSide",
    "format",
    "moveNodes",
    "project",
    "sig",
  ]);
});
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `pnpm test`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: `ERR_MODULE_NOT_FOUND` / `Cannot find module` … `test/_tree.ts`。
`ℹ fail` が 0 でない。EXIT=1

- [ ] **Step 3: 最小の実装を書く**

`test/_tree.ts` を新規作成する（契約 §13 の逐語。生成器の強化は Task 64、縮小器は Task 65）。

```typescript
// 新 core の窓口。JSON の形（フィールド名・並び）を決めるのは
// core/tree/project.mbt と core/tree/json.mbt で、この `JSON.parse` が唯一の信頼境界。
//
// 重要: 新 core は純関数。モジュールグローバルな状態を持たないので、
// どのテストも md 文字列から始めてよい（initDoc に当たるものは無い）。
//
// 出力が無いと ERR_MODULE_NOT_FOUND で落ちる。先に `pnpm run core` を実行すること。

import { readdirSync, readFileSync, statSync } from "branch:fs";
import { join } from "branch:path";
import * as mbt from "../core/_build/js/release/build/tree/js/js.js";

/** 法則 3（map への矢印は project 1 本）を数えるために名前空間ごと出す */
export { mbt };

/** 旧文書上の UTF-16 オフセット。境界を渡る唯一の編集の形 */
export interface Edit {
  readonly from: number;
  readonly to: number;
  readonly insert: string;
}

/** 操作 1 回ぶんの往復。ok が false なら text は元のまま・edits は空 */
export interface Reflection {
  readonly ok: boolean;
  readonly reason: string;
  readonly text: string;
  readonly edits: readonly Edit[];
}

/** ノードの箱に積む 1 枚。Block の Content と 1 対 1 */
export type Card =
  | { readonly kind: "image"; readonly alt: string; readonly src: string }
  | { readonly kind: "link"; readonly text: string; readonly href: string }
  | { readonly kind: "code"; readonly info: string; readonly text: string }
  | { readonly kind: "svg"; readonly svg: string };

/** 判別可能ユニオンの絞り込み。kind で分岐すれば各腕のフィールドが型で見える */
export function cardText(card: Card): string {
  switch (card.kind) {
    case "image":
      return card.alt;
    case "link":
      return card.text;
    case "code":
      return card.text;
    case "svg":
      return card.svg;
  }
}

export interface MapNode {
  readonly id: number;
  readonly label: string;
  /** 骨格行を持たない（飛びが綴り）。中空に描くかは render の自由 */
  readonly implied: boolean;
  readonly folded: boolean;
  readonly sign: "heading" | "item";
  readonly cards: readonly Card[];
  /** 絵に描かれない Block の数（Rule と Opaque）。cards.length + buried = body の数 */
  readonly buried: number;
}

export interface MapBranch {
  readonly branch: MapNode;
  readonly children: readonly MapBranch[];
}

export interface MapTree {
  readonly branch: MapNode;
  readonly right: readonly MapBranch[];
  readonly left: readonly MapBranch[];
}

export interface Mindmap {
  readonly trees: readonly MapTree[];
  /** 最初の骨格より前の散文の数。箱が無いので 1 枚も絵にならない */
  readonly buried: number;
}

export const doc = {
  /** id を含まない木の綴り。法則 1・2 の比較子 */
  sig: (md: string): string => mbt.sig(md),
  /** parse → serialize。法則 2 はこれの冪等性 */
  format: (md: string): string => mbt.format(md),
  /** 破れの一覧。空なら健全 */
  check: (md: string): string[] => JSON.parse(mbt.check(md)),
  project: (md: string): Mindmap => JSON.parse(mbt.project(md)),
  /** parent は id（文書は 1）。left は行き先の側で、root 直下でだけ効く */
  moveNodes: (
    md: string,
    ids: number[],
    parent: number,
    at: number,
    left: boolean,
  ): Reflection => JSON.parse(mbt.moveNodes(md, ids, parent, at, left)),
  flipSide: (md: string, ids: number[]): Reflection =>
    JSON.parse(mbt.flipSide(md, ids)),
  deleteNodes: (md: string, ids: number[]): Reflection =>
    JSON.parse(mbt.deleteNodes(md, ids)),
};

/** edits を旧文書へ当てる。core の自己検査と同じ算術を TS 側でもう一度踏む */
export function apply(text: string, edits: readonly Edit[]): string {
  let out = "";
  let at = 0;
  for (const e of edits) {
    out += text.slice(at, e.from) + e.insert;
    at = e.to;
  }
  return out + text.slice(at);
}

/** 決定論的な乱数（xorshift）。seed が同じなら必ず同じ文書が出る */
export function rng(seed: number): () => number {
  let s = seed | 0 || 1;
  return () => {
    s ^= s << 13;
    s ^= s >>> 17;
    s ^= s << 5;
    return (s >>> 0) / 4294967296;
  };
}

const LABELS = [
  "a",
  "",
  "  spaced  ",
  "日本語",
  "🙂",
  "### not a heading",
  "[x] done",
  "1. numbered",
  "--",
  "a\tb",
];

const BODIES = [
  "text",
  "***",
  "---",
  "```js\ncode\n```",
  "```\n```` inner\n```",
  "![alt](./img/a.png)",
  "[title](https://example.com)",
  "<svg><rect/></svg>",
  "> quote",
  "| a | b |\n| - | - |",
  "<!-- comment -->",
];

/** 法則のファズが食わせる文書。飛び・区切り・畳み・CRLF・末尾改行なしを狙って踏む */
export function randomDoc(seed: number): string {
  const r = rng(seed);
  const pick = <T>(xs: T[]): T => xs[Math.floor(r() * xs.length)]!;
  const out: string[] = [];
  if (r() < 0.15) out.push("---\nimage-folder: img\n---\n");
  if (r() < 0.15) out.push("---\n");
  let level = 1;
  const n = 1 + Math.floor(r() * 12);
  for (let i = 0; i < n; i++) {
    level = Math.max(1, Math.min(7, level + Math.floor(r() * 5) - 2));
    const label = pick(LABELS);
    out.push(
      r() < 0.35
        ? `${"  ".repeat(level - 1)}- ${label}\n`
        : `${"#".repeat(level)} ${label}\n`,
    );
    out.push("\n");
    if (r() < 0.4) out.push(`${pick(BODIES)}\n\n`);
    if (r() < 0.1) out.push("---\n\n");
    if (r() < 0.1) out.push("<details>\n\n<summary>x</summary>\n\n");
    if (r() < 0.1) out.push("</details>\n\n");
  }
  let text = out.join("");
  if (r() < 0.2) text = text.replace(/\n/g, "\r\n");
  if (r() < 0.25) text = text.replace(/\n$/, "");
  return text;
}

/** リポジトリ内の実文書。docs/ の md がそのまま法則 1・2 の入力になる */
export function corpus(root = "."): { path: string; text: string }[] {
  const skip = new Set([
    "node_modules",
    "_build",
    ".git",
    "target",
    ".worktrees",
  ]);
  const out: { path: string; text: string }[] = [];
  const walk = (dir: string, depth: number): void => {
    if (depth > 3) return;
    for (const name of readdirSync(dir)) {
      if (skip.has(name)) continue;
      const p = join(dir, name);
      if (statSync(p).isDirectory()) walk(p, depth + 1);
      else if (name.endsWith(".md"))
        out.push({ path: p, text: readFileSync(p, "utf8") });
    }
  };
  walk(root, 0);
  return out;
}

/** ケース数のダイヤル。PowerShell では `$env:MMM_FUZZ = '5000'; pnpm test` */
export function fuzzCases(fallback: number): number {
  const v = Number(process.env["MMM_FUZZ"]);
  return Number.isFinite(v) && v > 0 ? v : fallback;
}

/** 失敗したときに何を食わせたかを 1 行で見せる */
export function brief(md: string): string {
  return JSON.stringify(md.length > 200 ? md.slice(0, 200) + "…" : md);
}
```

同時に `test/tsconfig.json` の死んだ 2 行を掃く。`include` を

```json
  "include": [
    ".",
    "../src/coreApi.ts",
    "../src/relevel.ts",
    "../src/app/assets.ts",
    "../src/app/externalChange.ts"
  ],
```

から

```json
  "include": [".", "../src/coreApi.ts", "../src/app/assets.ts"],
```

に変える（`src/relevel.ts` は `core/relevel.mbt` へ移って消滅、
`src/app/externalChange.ts` は存在しない。glob が当たらないだけでエラーにならない負債）。
`test/_tree.ts` は `include` の `"."` が拾うので、追加は要らない。

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `pnpm test`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: `test/treeLaws.test.ts` の **3 本**が緑（`ℹ pass` が 3 増え、`ℹ fail 0`）。EXIT=0

Run: `pnpm run check`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: 出力なし EXIT=0

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add test/_tree.ts test/treeLaws.test.ts test/tsconfig.json
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "test: ✅ 新 core の窓口を置き、死んだ include を掃く"
```

---

## Task 64: 病的な md の生成器

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/test/_tree.ts`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/test/treeLaws.test.ts`

**Interfaces:**
- Consumes: `rng`（Task 63）
- Produces: 強化した `randomDoc(seed : number) => string` /
  `pathological() => { name: string; md: string }[]`

Task 63 が置いた `randomDoc` は骨格の綴りが `#` と `- ` の 2 種しかない。
法則 1・2 が本当に効くのは方言の角なので、**骨格の銘柄・字下げの揺れ・
setext・インデントコード・未閉じフェンス・手書きの `<summary>` まで踏ませる**。

- [ ] **Step 1: 失敗するテストを書く**

`test/treeLaws.test.ts` の import を差し替え、生成器の自己確認を 1 本足す。

```typescript
import { apply, doc, mbt, pathological, randomDoc } from "./_tree.ts";
```

```typescript
test("生成器: 同じ seed は同じ md。狙った角を全部踏む", () => {
  assert.equal(randomDoc(7), randomDoc(7));
  assert.notEqual(randomDoc(7), randomDoc(8));
  assert.ok(pathological().length >= 29, "手で選んだケースが少なすぎる");
  const all = Array.from({ length: 400 }, (_, i) => randomDoc(i + 1)).join("");
  const corners = [
    "####### ", // 7 個以上の #
    "* ", // マーカー混在
    "+ ",
    "1. ", // 順序リスト
    "1) ",
    "\t- ", // 字下げの揺れ
    "```", // フェンス
    "~~~",
    "    indented code", // インデントコード
    "setext\n---", // setext
    "<details>", // 畳み
    "<summary>", // 畳みの飾り（読みで捨てられる 1 枚）
    "</details>",
    "\r\n", // CRLF
    "🙂𝔘", // 非 ASCII とサロゲートペア
    "- - -", // 捨てた方言
    "___",
    "image-folder", // 封筒
    "| a | b |", // table
    "<!---", // 許容するコメント
  ];
  for (const c of corners) {
    assert.ok(all.includes(c), `生成器が ${JSON.stringify(c)} を一度も出していない`);
  }
});
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `pnpm test`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: `SyntaxError` … `The requested module './_tree.ts' does not provide an export named 'pathological'`。EXIT=1

- [ ] **Step 3: 最小の実装を書く**

`test/_tree.ts` の `LABELS` / `BODIES` / `randomDoc` を次に**差し替え**、
`SKELETONS` と `pathological` を足す（置き場所は `rng` の下、`corpus` の上）。

```typescript
/** 骨格行の綴り。マーカーの銘柄・字下げの揺れ・sign の混在をここで踏む */
const SKELETONS = [
  "# ",
  "## ",
  "####### ",
  "######## ",
  "- ",
  "* ",
  "+ ",
  "1. ",
  "1) ",
];

const LABELS = [
  "a",
  "",
  "  spaced  ",
  "日本語",
  "🙂𝔘",
  "### not a heading",
  "[x] done",
  "1. numbered",
  "--",
  "a\tb",
  "b   ##",
];

const BODIES = [
  "text",
  "***",
  "---",
  "___",
  "- - -",
  "setext\n---",
  "setext\n===",
  "```js\ncode\n```",
  "```\n```` inner\n```",
  "~~~\n## tilde\n~~~",
  "    indented code",
  "![alt](./img/a.png)",
  "[title](https://example.com)",
  "<svg><rect/></svg>",
  "> quote",
  "| a | b |\n| - | - |",
  "<!-- comment -->",
  "<!---\nlong comment\n--->",
  "<details>",
  "<summary>x</summary>",
  "</details>",
  "\n\n\n",
];

/**
 * 病的な md を組む。狙って踏むのは
 * 見出しの飛び / 7 個以上の `#` / マーカー混在 / 字下げの揺れ / sign 混在 /
 * トグルと飾り / details のネストと未閉じ / 手書きの summary / 封筒 / setext /
 * インデントコード / フェンス / CRLF / 空行の連続 / 非 ASCII とサロゲートペア。
 */
export function randomDoc(seed: number): string {
  const r = rng(seed);
  const pick = <T>(xs: T[]): T => xs[Math.floor(r() * xs.length)]!;
  const out: string[] = [];
  if (r() < 0.15) out.push("---\nimage-folder: img\n---\n\n");
  else if (r() < 0.1) out.push("---\n\n");
  const n = 1 + Math.floor(r() * 12);
  let indent = 0;
  for (let i = 0; i < n; i++) {
    indent = Math.max(0, Math.min(6, indent + Math.floor(r() * 5) - 2));
    out.push(`${" ".repeat(indent)}${pick(SKELETONS)}${pick(LABELS)}\n`);
    out.push("\n");
    if (r() < 0.4) out.push(`${pick(BODIES)}\n\n`);
    if (r() < 0.12) out.push("---\n\n");
    if (r() < 0.08) out.push("\t- tab indented\n\n");
  }
  let text = out.join("");
  if (r() < 0.2) text = text.replace(/\n/g, "\r\n");
  if (r() < 0.25) text = text.replace(/\n$/, "");
  return text;
}

/** 手で選んだ病的な md。生成器が当てにくい角を名前つきで置く */
export function pathological(): { name: string; md: string }[] {
  return [
    ["空文書", ""],
    ["改行だけ", "\n"],
    ["空行の連続", "\n\n\n\n"],
    ["CR だけ", "\r"],
    ["CRLF 混在", "# a\r\n## b\n### c\r\n"],
    ["末尾改行なし", "# a\n\n## b"],
    ["見出しの飛び", "# r\n\n#### b\n"],
    ["7 個以上の #", "# r\n\n####### seven\n\n######## eight\n"],
    ["マーカー混在", "- a\n* b\n+ c\n"],
    ["順序リスト", "1. a\n2) b\n"],
    ["字下げの揺れ", "- a\n   - b\n\t- c\n"],
    ["sign 混在", "# r\n\n- x\n\n## h\n\n- y\n"],
    ["トグルと飾り", "# r\n\n## a\n\ntext\n\n---\n\nmore\n\n---\n\n## b\n"],
    [
      "details のネスト",
      "# r\n\n<details>\n\n## a\n\n<details>\n\n</details>\n\n</details>\n",
    ],
    ["details 未閉じ", "# r\n\n<details>\n\n## a\n"],
    [
      "手書きの summary",
      '# r\n\n<details>\n\n<summary class="x">old</summary>\n\n## a\n\n</details>\n',
    ],
    [
      "details の直後でない summary",
      "# r\n\n<details>\n\n## a\n\n<summary>stray</summary>\n\n</details>\n",
    ],
    ["封筒", "---\nimage-folder: img\n---\n\n# r\n"],
    ["封筒に見える先頭トグル", "---\n\n# r\n\n---\n\n## a\n"],
    ["setext", "# r\n\na\n---\n\nb\n===\n"],
    ["インデントコード", "# r\n\n    code\n"],
    ["未閉じフェンス", "# r\n\n```\n## inside\n"],
    ["フェンスの入れ子", "# r\n\n````\n```\ninner\n```\n````\n"],
    ["閉じ # と余白", "#   b   ##\n"],
    ["`- - -` は水平線", "# r\n\n- - -\n\n## a\n"],
    ["非 ASCII とサロゲートペア", "# 😀𝔘𝔫𝔦\n\n## 🇯🇵\n\n### が\n"],
    ["項目の後ろの見出し", "- a\n\n## h\n"],
    ["項目領土内の見出し", "- a\n\n  ## inner\n"],
    ["空白だけの行", "# a\n\n \n"],
    ["NUL", "# a\n\n\u0000\n"],
    ["巨大な 1 行", "# " + "x".repeat(50000) + "\n"],
  ].map(([name, md]) => ({ name: name!, md: md! }));
}
```

**「手書きの summary」と「details の直後でない summary」を置く理由**（契約 §9）:
前者は読みで捨てられ、書き出しでラベル版へ作り直される（意味の損失。爆風半径）。
後者は `Open` の直後ではないので `Opaque` として残る。**この 2 本が別々に不動である**
ことが、`<summary>` の読み飛ばしが「位置つき・1 枚だけ」である証拠になる。

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `pnpm test`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: `test/treeLaws.test.ts` が **4 本**すべて緑（`ℹ pass` が 1 増える）。EXIT=0

Run: `pnpm run check`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: 出力なし EXIT=0

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add test/_tree.ts test/treeLaws.test.ts
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "test: ✅ 病的な md の生成器を置く"
```

---

## Task 65: 最小反例の縮小

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/test/_tree.ts`
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/test/treeLaws.test.ts`

**Interfaces:**
- Consumes: なし
- Produces: `shrink(md : string, fails : (s: string) => boolean) => string`

- [ ] **Step 1: 失敗するテストを書く**

`test/treeLaws.test.ts` の import に `shrink` を足し、テストを 1 本足す。

```typescript
import { apply, doc, mbt, pathological, randomDoc, shrink } from "./_tree.ts";
```

```typescript
test("最小反例の縮小 — 落ちたまま小さくなる", () => {
  const md = "# a\n\n## b\n\nBAD\n\n## c\n";
  assert.equal(shrink(md, (s) => s.includes("BAD")), "BAD");
  // 落ちていない入力は 1 文字も削らない
  assert.equal(shrink(md, () => false), md);
});
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `pnpm test`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: `SyntaxError` … `does not provide an export named 'shrink'`。EXIT=1

- [ ] **Step 3: 最小の実装を書く**

`test/_tree.ts` の末尾（`brief` の下）に足す。

```typescript
/**
 * 落ちた md を、落ちたまま小さくする。手は 2 つだけ —
 * 行を 1 本抜く / 末尾を切る。どちらも失敗が消えたら戻す。
 * 打ち手が尽きたところが最小反例。
 */
export function shrink(md: string, fails: (s: string) => boolean): string {
  if (!fails(md)) return md;
  let best = md;
  let moved = true;
  while (moved) {
    moved = false;
    const lines = best.split("\n");
    for (let i = 0; i < lines.length; i++) {
      const cut = [...lines.slice(0, i), ...lines.slice(i + 1)].join("\n");
      if (cut !== best && fails(cut)) {
        best = cut;
        moved = true;
        break;
      }
    }
    if (moved) continue;
    for (const n of [best.length >> 1, best.length - 1]) {
      const cut = best.slice(0, n);
      if (cut !== best && fails(cut)) {
        best = cut;
        moved = true;
        break;
      }
    }
  }
  return best;
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `pnpm test`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: `test/treeLaws.test.ts` が **5 本**すべて緑（`ℹ pass` が 1 増える）。EXIT=0

Run: `pnpm run check`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: 出力なし EXIT=0

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add test/_tree.ts test/treeLaws.test.ts
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "test: ✅ 落ちた md を落ちたまま小さくする道具を置く"
```

---

## Task 66: 法則 2 — serialize は 2 回目から不動

**Files:**
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/test/treeLaws.test.ts`

**Interfaces:**
- Consumes: `doc.format`（Task 63）/ `randomDoc` `pathological`（Task 64）/
  `shrink`（Task 65）/ `corpus` `fuzzCases` `brief`（Task 63）
- Produces: なし（法則の固定）

- [ ] **Step 1: 失敗するテストを書く**

`test/treeLaws.test.ts` の import を最終形にし、法則 2 の 3 本を足す。

```typescript
import {
  apply,
  brief,
  corpus,
  doc,
  fuzzCases,
  mbt,
  pathological,
  randomDoc,
  shrink,
} from "./_tree.ts";

const CASES = fuzzCases(400);
```

```typescript
test("法則 2: 病的な md でも format は 2 回目から不動", () => {
  for (const { name, md } of pathological()) {
    const once = doc.format(md);
    assert.equal(doc.format(once), once, `「${name}」で不動でない`);
  }
});

test("法則 2: ランダム生成入力で format は 2 回目から不動", () => {
  for (let seed = 1; seed <= CASES; seed++) {
    const md = randomDoc(seed);
    const once = doc.format(md);
    if (doc.format(once) === once) continue;
    const small = shrink(md, (s) => doc.format(doc.format(s)) !== doc.format(s));
    assert.fail(`seed=${seed} で不動でない。最小反例=${brief(small)}`);
  }
});

test("法則 2: リポジトリ内の実 .md で format は 2 回目から不動", () => {
  const docs = corpus();
  assert.ok(docs.length > 0, "対象の .md が 1 つも無い");
  for (const { path, text } of docs) {
    const once = doc.format(text);
    assert.equal(doc.format(once), once, `${path} で不動でない`);
  }
});
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `pnpm test`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: G3 の `serialize` が正規形を吐けていなければ
`AssertionError [ERR_ASSERTION]: 「<ケース名>」で不動でない` が出る。EXIT=1

**G4 は最後に走る検証群なので、最初から緑になることがある。**
その場合は `assert.fail("わざと")` を 3 本の先頭に 1 行ずつ入れて赤を見てから外し、
**テストが本当に走っていること**を確かめる（`ℹ pass` が 3 増えることを目で見る）。

- [ ] **Step 3: 赤の差し戻し**

**この Task では実装を 1 行も書かない。** 法則 2 の実装は G3 の `serialize` が持つ。
`core/tree/serialize.mbt` / `parse.mbt` / `scan.mbt` には 1 バイトも書かない（契約 §2）。

落ちた最小反例（`shrink` が出す）を持って、概要の**赤の差し戻し表**で担当群を決め、
G2 / G3 へ差し戻す。とくに踏みやすい 2 つ:

- **空行の本数が 2 回目で増える** → G3 Task 41 の `put`。空行の判断は `put` 1 本だけが持つ
  （G3 の受け入れ条件が「`pen.sb.write_string(pen.eol)` が `put` 以外に現れない」なので、
  出口に後処理を足す直しは受け入れない）
- **`<summary>` 行が 1 枚ずつ増える** → G2 Task 25。`<details>` の直後の 1 枚を
  読み飛ばしていない（契約 §9）

差し戻したら、**G2 / G3 の wbtest に固定を 1 本足してもらってから**この Task に戻る。

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `pnpm test`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: `test/treeLaws.test.ts` が **8 本**すべて緑（`ℹ pass` が 3 増え、`ℹ fail 0`）。EXIT=0

Run: `pnpm run check`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: 出力なし EXIT=0

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add test/treeLaws.test.ts
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "test: ✅ 法則 2（format は 2 回目から不動）を立てる"
```

---

## Task 67: 法則 1（md を種にした版）と check

**Files:**
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/test/treeLaws.test.ts`

**Interfaces:**
- Consumes: `doc.sig` / `doc.format` / `doc.check`（Task 63）、Task 64・65 の道具
- Produces: なし（法則の固定）

- [ ] **Step 1: 失敗するテストを書く**

`test/treeLaws.test.ts` に 4 本足す。

```typescript
test("法則 1: 正規形を読み直しても指紋が変わらない（病的な md）", () => {
  for (const { name, md } of pathological()) {
    assert.equal(doc.sig(doc.format(md)), doc.sig(md), `「${name}」で指紋が動いた`);
  }
});

test("法則 1: 正規形を読み直しても指紋が変わらない（ランダム）", () => {
  for (let seed = 1; seed <= CASES; seed++) {
    const md = randomDoc(seed);
    if (doc.sig(doc.format(md)) === doc.sig(md)) continue;
    const small = shrink(md, (s) => doc.sig(doc.format(s)) !== doc.sig(s));
    assert.fail(`seed=${seed} で指紋が動いた。最小反例=${brief(small)}`);
  }
});

test("法則 1: 実 .md でも指紋が変わらない", () => {
  const docs = corpus();
  assert.ok(docs.length > 0, "対象の .md が 1 つも無い");
  for (const { path, text } of docs) {
    assert.equal(doc.sig(doc.format(text)), doc.sig(text), `${path} で指紋が動いた`);
  }
});

test("parse が出した木は必ず check を通る", () => {
  for (const { name, md } of pathological()) {
    assert.deepEqual(doc.check(md), [], `「${name}」で不変条件が破れている`);
  }
  for (let seed = 1; seed <= CASES; seed++) {
    const md = randomDoc(seed);
    assert.deepEqual(doc.check(md), [], `seed=${seed} で破れ。入力=${brief(md)}`);
  }
});
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `pnpm test`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: 指紋が動くケースがあれば
`AssertionError [ERR_ASSERTION]: 「<ケース名>」で指紋が動いた`、
check が破れていれば `AssertionError` に `id が重なっている (id=N)` などの
契約 §7 の 6 文言のどれかが載る。EXIT=1

最初から緑なら、Task 66 と同じ手で `assert.fail("わざと")` を 4 本に入れて
赤を見てから外し、テストが走っていることを確かめる。

- [ ] **Step 3: 赤の差し戻し**

**この Task では実装を 1 行も書かない。** 赤の出どころは G2 の `parse` か G3 の `serialize`。
概要の**赤の差し戻し表**で担当群を決めて戻す。

- **`i` が `eh_` に化けた** → **serialize が Implicit を勝手に昇格させている**。
  G3 Task 41 へ差し戻す。**「飛びが表現できない位置の implied」は
  G5 Task 87 の `conform`（`raised(s, true)`）が操作の側で潰している。**
  ここで serialize に安全弁を二重に置かない — serialize が model と違うものを書いたら、
  `sig` は id を含まない木の綴りなので**法則 1 が定義ごと壊れる**
- **`check` が空でない木が出た** → **parse のバグ**。serialize でも sig でもないので G2 へ戻す。
  法則 1 が落ちたときは、まず落ちた md が `doc.check` を通っているかを見ること
  （通っていなければ原因は parse で、serialize は無罪）

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `pnpm test`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: `test/treeLaws.test.ts` が **12 本**すべて緑（`ℹ pass` が 4 増え、`ℹ fail 0`）。EXIT=0

Run: `pnpm run check`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: 出力なし EXIT=0

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add test/treeLaws.test.ts
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "test: ✅ 法則 1 を md 側から立て、check を毎回踏ませる"
```

---

## Task 68: 法則 1 の本丸 — 木の生成器

**Files:**
- Test: `D:/1.atrium/mmm/.worktrees/feat/tree-core/core/tree/laws_wbtest.mbt`

**Interfaces:**
- Consumes: `Doc` / `Root` / `Wing` / `Branch` / `Node` / `Sign` / `Side` / `Eol` /
  `Block` / `Content` / `first_id` / `check` / `sig`（G1）、`parse`（G2）、
  `serialize`（G3）、`strings`（Task 60）
- Produces: なし（法則の固定）

**なぜ mbt に置くのか**: `Doc` は境界を跨げない（契約 §13「struct を 1 つも跨がせない」）。
TS 側のファズは md から始まるので、**parse が読めない木を一度も踏まない**。
法則 1（`parse(serialize(M)) = M`）を M 側から掃くには、木の生成器が mbt に要る。

**生成器の掟**: **parse が作り得る木しか作らない。**
端の空白を持つラベル・行頭がマーカーに見える Item ラベル・水平線に見える Opaque を
出した瞬間、法則 1 は生成器の罪で落ちる。だからラベル集合は sign ごとに分かれている。

- [ ] **Step 1: 失敗するテストを書く**

`core/tree/laws_wbtest.mbt` を新規作成する。

```moonbit
// 法則 1（parse(serialize(D)) = D）。木そのものを種にする唯一の場所 —
// 境界を struct が跨げないので、md を種にする TS 側のファズはここへ届かない。
//
// 生成器の掟: **parse が作り得る木しか作らない**。
// 端の空白を持つラベル・行頭がマーカーに見える Item ラベル・
// 水平線に見える Opaque を出した瞬間、法則 1 は生成器の罪で落ちる。

///|
/// 決定論的な擬似乱数（線形合同法）と id の採番を 1 つに束ねたもの。
struct Law {
  mut seed : Int
  mut next_id : Int
}

///|
/// 0 以上 n 未満。
fn law_pick(r : Law, n : Int) -> Int {
  r.seed = (r.seed * 1103515245 + 12345) & 0x3FFFFFFF
  r.seed % n
}

///|
/// 文書内で一意な id（番兵 doc_id は first_id が避けている）。
fn law_id(r : Law) -> Int {
  let id = r.next_id
  r.next_id = id + 1
  id
}

///|
/// 見出しのラベル。端の空白と改行は parse が作れないので出さない。
fn law_head_label(r : Law) -> String {
  match law_pick(r, 6) {
    0 => ""
    1 => "a"
    2 => "日本語"
    3 => "🙂"
    4 => "### not a heading"
    _ => "a\tb"
  }
}

///|
/// 項目のラベル。行頭がマーカーや番号に見えるものは入れ子に化けるので出さない。
fn law_item_label(r : Law) -> String {
  match law_pick(r, 4) {
    0 => ""
    1 => "x"
    2 => "日本語"
    _ => "[x] done"
  }
}

///|
/// 骨格に貼り付く 1 枚。水平線に見える Opaque は Rule に化けるので出さない。
fn law_block(r : Law) -> Block {
  match law_pick(r, 6) {
    0 => Rule
    1 => Opaque("text")
    2 => Opaque("> quote")
    3 => Content(Image(alt="a", src="./x.png"))
    4 => Content(Link(text="t", href="https://example.com"))
    _ => Content(Code(info="js", text="1"))
  }
}

///|
fn law_side(r : Law) -> Side {
  if law_pick(r, 2) == 0 {
    Right
  } else {
    Left
  }
}

///|
fn law_node(r : Law, sign : Sign) -> Node {
  let body : Array[Block] = []
  for _ in 0..<law_pick(r, 3) {
    body.push(law_block(r))
  }
  let label = match sign {
    Heading => law_head_label(r)
    Item => law_item_label(r)
  }
  Explicit(sign~, label~, folded=law_pick(r, 4) == 0, body~)
}

///|
/// 兄弟の列。項目が先・見出しが後（順序法則）で、Implicit は
/// 項目の走りの直後に高々 1 つ（前の兄弟がすべて項目という位置の条件）。
/// 項目の親の下は項目だけ（単調性）。
fn law_branches(r : Law, parent : Sign, depth : Int) -> Array[Branch] {
  let out : Array[Branch] = []
  if depth <= 0 {
    return out
  }
  for _ in 0..<law_pick(r, 3) {
    out.push(law_branch(r, Item, depth - 1))
  }
  if parent is Heading {
    if law_pick(r, 3) == 0 {
      let kids : Array[Branch] = []
      for _ in 0..<(1 + law_pick(r, 2)) {
        kids.push(law_branch(r, Heading, depth - 1))
      }
      out.push({ id: law_id(r), node: Implicit, children: kids })
    }
    for _ in 0..<law_pick(r, 3) {
      out.push(law_branch(r, Heading, depth - 1))
    }
  }
  out
}

///|
fn law_branch(r : Law, sign : Sign, depth : Int) -> Branch {
  {
    id: law_id(r),
    node: law_node(r, sign),
    children: law_branches(r, sign, depth),
  }
}

///|
/// 翼の列。側は場所の属性なので、ここで初めて付く。
fn law_wings(r : Law, parent : Sign, depth : Int) -> Array[Wing] {
  let out : Array[Wing] = []
  for n in law_branches(r, parent, depth) {
    out.push({ side: law_side(r), branch: n })
  }
  out
}

///|
/// Implicit の root は子を持つ限りにおいて存在し、その子はすべて見出し。
fn law_implicit_root(r : Law, depth : Int) -> Root {
  let wings : Array[Wing] = []
  for _ in 0..<(1 + law_pick(r, 2)) {
    wings.push({ side: law_side(r), branch: law_branch(r, Heading, depth - 1) })
  }
  { id: law_id(r), node: Implicit, wings }
}

///|
/// 文書 1 通。doc 直下にも順序法則が効く（項目の root が先、見出しの root が後）。
fn law_doc(seed : Int, depth : Int) -> Doc {
  let r : Law = { seed: seed * 2 + 1, next_id: first_id }
  let body : Array[Block] = []
  for _ in 0..<law_pick(r, 3) {
    body.push(law_block(r))
  }
  let roots : Array[Root] = []
  for _ in 0..<law_pick(r, 3) {
    roots.push({
      id: law_id(r),
      node: law_node(r, Item),
      wings: law_wings(r, Item, depth),
    })
  }
  if law_pick(r, 3) == 0 {
    roots.push(law_implicit_root(r, depth))
  }
  for _ in 0..<(1 + law_pick(r, 3)) {
    roots.push({
      id: law_id(r),
      node: law_node(r, Heading),
      wings: law_wings(r, Heading, depth),
    })
  }
  {
    frontmatter: if law_pick(r, 4) == 0 {
      Some("k: v")
    } else {
      None
    },
    eol: if law_pick(r, 4) == 0 {
      Crlf
    } else {
      Lf
    },
    body,
    roots,
  }
}

///|
test "生成器が作る木は必ず check を通る（不変条件の破れは生成器の罪）" {
  for seed in 1..<200 {
    let d = law_doc(seed, 3)
    assert_eq(strings(check(d)), "[]")
  }
}

///|
test "法則 1: parse(serialize(D)) = D（指紋が比較子）" {
  for seed in 1..<200 {
    let d = law_doc(seed, 3)
    assert_eq(sig(parse(serialize(d))), sig(d))
  }
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/laws_wbtest.mbt`
Expected: 2 本目が落ちるなら逐語の形は

```
[mmm-app/core] test tree/laws_wbtest.mbt:196 ("法則 1: parse(serialize(D)) = D（指紋が比較子）") failed: doc/laws_wbtest.mbt:199:5-199:48@mmm-app/core FAILED: `"<parse が読んだ指紋>" != "<生成した木の指紋>"`
```

EXIT=2。**1 本目（check）は必ず緑になること** — 赤なら生成器が
契約 §7 の不変条件を破っている（**実装ではなく生成器を直す**。生成器は G4 の所有）。

2 本とも最初から緑なら、2 本目の `assert_eq` の期待側を一時的に
`sig(d) + "x"` に変えて赤を見てから戻し、テストが走っていることを確かめる。

- [ ] **Step 3: 赤の差し戻し**

**この Task では実装を 1 行も書かない。** `core/tree/parse.mbt` / `serialize.mbt` /
`scan.mbt` には 1 バイトも書かない（契約 §2）。

**指紋の食い違いを 1 文字ずつ読んで、どの部分が落ちたかで担当を決める**
（概要の赤の差し戻し表と同じ）:

- `e` の後の `^`/`_` が違う → 畳みの綴り（G3 Task 44 の `<details>` / G2 Task 25 の `Open`・`Close`）
- `>`/`<` が違う → 側（G3 Task 43 のトグル / G2 Task 24 の翼前の隙間）
- `i` が消える／増える → Implicit の導出（G2 Task 21 の level 飛び）
- `i` が `eh_` に化けた → serialize が勝手に昇格している（G3 Task 41）
- `(...)` の中身が違う → 中身の認定（G2 Task 23 の `Rule` と `Opaque` の分かれ目）
- `o…:<summary>…` が増える → `<summary>` の読み飛ばし（G2 Task 25。契約 §9）

差し戻したら、**該当群の wbtest に固定を 1 本足してもらってから**この Task に戻る。

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test tree/laws_wbtest.mbt`
Expected: `Total tests: 2, passed: 2, failed: 0.` EXIT=0

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core fmt --check tree`
Expected: EXIT=0

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add core/tree/laws_wbtest.mbt
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "test: ✅ 木を種にして法則 1 を掃く"
```

---

## Task 69: 法則 4 — 外部審判（@lezer/markdown）と読みの裁定

**Files:**
- Create: `D:/1.atrium/mmm/.worktrees/feat/tree-core/test/treeDialect.test.ts`

**Interfaces:**
- Consumes: `doc.project` / `doc.sig` / `MapBranch`（Task 63）、
  `@lezer/markdown` の `parser`（devDependencies 1.7.2）
- Produces: なし（方言の面の固定）

**表は 2 つ要る。**

- `DIALECT` — **骨格の数**を lezer と比べる。面の広さを固定する
- `READING` — **md → 指紋**。数は合うが読んだ中身が違う差（契約 §15 の読みの裁定 9 件）は
  数では原理的に捕まらないので、こちらで中身を固定する

**アダプタは作らない** — 食い違う行だけを表に書き、表そのものを固定する。

- [ ] **Step 1: 失敗するテストを書く**

`test/treeDialect.test.ts` を新規作成する。

```typescript
// 法則 4: parse の骨格判定 = @lezer/markdown のブロック木 + 方言表。
//
// lezer は外部の審判。アダプタは作らず、**食い違う行だけを表に書く**。
// 表に無い食い違いが出たら、それは方言ではなく parse のバグ。
//
// 表は 2 つ。DIALECT は骨格の「数」、READING は「読んだ中身」（指紋）。
// 数だけでは、契約 §15 の読みの裁定 1・2 のような「数は合うが中身が違う」差が
// 原理的に捕まらないので、2 枚目が要る。
//
// 封筒について: 法則 4 の照合は封筒を剥がした後の本文に掛かる（申し送り S10）。
// lezer は封筒の柵を HorizontalRule + SetextHeading2 に読むので、
// DIALECT の封筒の行は必ず食い違う（下の 4 行のうちの 1 行）。コーパス全体へ
// この比較を広げるときは、先に封筒を剥がしてから lezer に食わせること。
//
// READING の期待指紋は契約 §8 の文法と §15 の裁定から導いたもの。実装と食い違ったら、
// どちらが正しいかを §8・§15 に照らして決める（テストを黙って書き換えない）。

import { test } from "branch:test";
import assert from "branch:assert/strict";
import { parser } from "@lezer/markdown";
import { doc, type MapBranch } from "./_tree.ts";

/** 外の CommonMark が骨格と認めた数（見出し + リスト項目） */
function outerNodes(md: string): number {
  const tree = parser.parse(md);
  let n = 0;
  tree.iterate({
    enter: (x) => {
      if (
        x.name.startsWith("ATXHeading") ||
        x.name.startsWith("SetextHeading") ||
        x.name === "ListItem"
      ) {
        n++;
      }
    },
  });
  return n;
}

/** mmm が骨格と認めた数（implied は骨格行を持たないので数えない） */
function mmmNodes(md: string): number {
  let n = 0;
  const walk = (b: MapBranch): void => {
    if (!b.branch.implied) n++;
    for (const c of b.children) walk(c);
  };
  const m = doc.project(md);
  for (const t of m.trees) {
    if (!t.branch.implied) n++;
    for (const b of t.right) walk(b);
    for (const b of t.left) walk(b);
  }
  return n;
}

/** 方言表。mmm と外の審判が何個の骨格を見るか、行ごとに固定する */
const DIALECT: { md: string; mmm: number; outer: number; why: string }[] = [
  { md: "# r\n\n## a\n", mmm: 2, outer: 2, why: "素の見出しは一致する" },
  { md: "###### six\n", mmm: 1, outer: 1, why: "6 個までは CommonMark と同じ" },
  {
    md: "####### seven\n",
    mmm: 1,
    outer: 0,
    why: "7 個以上も見出しとして読む（憲法 §4 の方言）",
  },
  {
    md: "######## eight\n",
    mmm: 1,
    outer: 0,
    why: "8 個も同じ。GitHub で段落に見えるのは方言の対価",
  },
  { md: "   # indented\n", mmm: 1, outer: 1, why: "行頭 3 スペースまでは飾り" },
  { md: "a\n---\n", mmm: 1, outer: 1, why: "setext は読む（書かない）" },
  {
    md: "- - -\n",
    mmm: 0,
    outer: 0,
    why: "`- - -` は CommonMark どおり水平線（旧 core は項目と読んでいた）",
  },
  {
    md: "---\nk: v\n---\n\n# r\n",
    mmm: 1,
    outer: 2,
    why: "封筒は parse の前段で剥がす。外は柵を水平線と setext に読む",
  },
  {
    md: "- a\n\n  ## inner\n",
    mmm: 1,
    outer: 2,
    why: "項目の領土内の見出しは Opaque（絶対記法を相対容器に入れない）",
  },
  {
    md: "- a\n\n## h\n",
    mmm: 2,
    outer: 2,
    why: "列 0 の見出しはリストを終わらせる。h は a の子にならない（C17）",
  },
  { md: "1. a\n2) b\n", mmm: 2, outer: 2, why: "順序リストは構造として読む" },
  { md: "> quote\n", mmm: 0, outer: 0, why: "blockquote は Opaque" },
  { md: "| a | b |\n| - | - |\n", mmm: 0, outer: 0, why: "table は Opaque" },
  { md: "<!---\nx\n--->\n", mmm: 0, outer: 0, why: "`<!---`/`--->` を許容する" },
  { md: "    code\n", mmm: 0, outer: 0, why: "インデントコードは読むが書かない" },
];

/** 読みの裁定 9 件（契約 §15）。数ではなく読んだ中身を指紋で固定する */
const READING: { md: string; sig: string; why: string }[] = [
  {
    md: "x\ny\n---\n",
    sig: "D-n(o1:x)[Ri[>Neh_1:y()[]]]",
    why: "裁定 1: setext の複数行段落は最後の 1 行だけが見出し。手前は散文のまま残す（憲法 §0）",
  },
  {
    md: "- a\ntext\n",
    sig: "D-n()[Rel_1:a(o4:text)[]]",
    why: "裁定 2: 怠惰な継続は読まない。列が浅い行は項目の領土から出る",
  },
  {
    md: "# r\n\np\n    q\n",
    sig: "D-n()[Reh_1:r(o3:p\nq)[]]",
    why: "裁定 3: インデントコードは空行の直後だけ開く（段落の続きを巻き込まない）",
  },
  {
    md: "# r\n\n    code\n",
    sig: "D-n()[Reh_1:r(cc0:4:code)[]]",
    why: "裁定 4: インデントコードは info 無しの Fence Token に落ちる（読めるが書かない。Token の固定は G1 の scan_wbtest.mbt）",
  },
  {
    md: "# r\n\n## a\n\n<details>\n\n<summary>a</summary>\n\n### b\n\n</details>\n",
    sig: "D-n()[Reh_1:r()[>Neh^1:a()[Neh_1:b()[]]]]",
    why: "裁定 5: <summary> 行は Verse として parse へ渡り、details の直後の 1 枚だけが捨てられる（契約 §9。Token の固定は G1 の scan_wbtest.mbt）",
  },
  {
    md: "# r\n\n<details open>\n\n## a\n\n</details>\n",
    sig: "D-n()[Reh^1:r()[>Neh_1:a()[]]]",
    why: "裁定 6: <details> は属性つきの形も受ける（読みは書きより広い。Token の固定は G1 の scan_wbtest.mbt）",
  },
  {
    md: "1. a\n",
    sig: "D-n()[Rel_1:a()[]]",
    why: "裁定 7: 順序リストは Bullet に落ち、番号は Token に残らない（Token の固定は G1 の scan_wbtest.mbt）",
  },
  {
    md: "-     a\n",
    sig: "D-n()[Rel_1:a()[]]",
    why: "裁定 8: マーカーの後ろの空白が 5 桁以上でも hang は 1 桁ぶん。余りはラベルに入らない（Token の固定は G1 の scan_wbtest.mbt）",
  },
  {
    md: "# r\n\n<!--\n# x\n-->\n",
    sig: "D-n()[Reh_1:r(o12:<!--\n# x\n-->)[]]",
    why: "裁定 9: HTML コメントの中の # は見出しにならない",
  },
];

test("法則 4: 方言表の各行で mmm と外の審判の骨格数が固定どおり", () => {
  for (const row of DIALECT) {
    assert.equal(
      mmmNodes(row.md),
      row.mmm,
      `mmm 側が表と違う: ${row.why} / ${JSON.stringify(row.md)}`,
    );
    assert.equal(
      outerNodes(row.md),
      row.outer,
      `外の審判が表と違う: ${row.why} / ${JSON.stringify(row.md)}`,
    );
  }
});

test("法則 4: 外の審判と食い違うのは方言表の 4 行だけ", () => {
  // 方言が増えるのは設計の変更。黙って増えないよう、面そのものを固定する
  assert.deepEqual(
    DIALECT.filter((r) => r.mmm !== r.outer).map((r) => r.md),
    [
      "####### seven\n",
      "######## eight\n",
      "---\nk: v\n---\n\n# r\n",
      "- a\n\n  ## inner\n",
    ],
  );
});

test("法則 4: 読みの裁定 9 件は指紋まで固定どおり", () => {
  assert.equal(READING.length, 9, "契約 §15 の裁定は 9 件");
  for (const row of READING) {
    assert.equal(doc.sig(row.md), row.sig, `${row.why} / ${JSON.stringify(row.md)}`);
  }
});
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `pnpm test`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: parse が方言を持っていない行で
`AssertionError [ERR_ASSERTION]: mmm 側が表と違う: 7 個以上も見出しとして読む（憲法 §4 の方言） / "####### seven\n"`
のように落ちる。EXIT=1

（**外の審判側の数（`outer`）はこの計画の外で実測済み**。
`@lezer/markdown` 1.7.2 で
`####### seven\n` → 0（Paragraph）、`######## eight\n` → 0（Paragraph）、
`---\nk: v\n---\n\n# r\n` → 2（HorizontalRule + SetextHeading2 + ATXHeading1）、
`- a\n\n  ## inner\n` → 2（ListItem + ATXHeading2）。ここが赤なら lezer の版を疑う）

3 本とも最初から緑なら、`DIALECT` の 1 行目の `mmm` を一時的に `99` にして
赤を見てから戻し、テストが走っていることを確かめる。

- [ ] **Step 3: 赤の差し戻し**

**新しい実装は書かない。** この Task で `core/tree/scan.mbt` と `core/tree/parse.mbt` に
手を入れてはならない（契約 §2。同名の `hashes` を置くと
`Error: [4051] The toplevel identifier hashes is declared twice` でビルドが止まる）。

方言は既に実装済みなので、赤は差し戻す:

- **7 個以上の `#`** → G1 の `head_at`（level に上限なし）。G1 Task 5 へ
- **項目の領土内の見出しの Opaque 化** → G2 Task 22 の Head の腕へ
- **`READING` の裁定 1・2・3・9** → G2（読みの意味の判断）
- **`READING` の裁定 4・5・6・7・8** → G1 の `scan`（Token の段階で固定済み。
  `scan_wbtest.mbt` の対応する固定と食い違っていないかを先に見る）
- **封筒の行** → G1 の `envelope`（封筒は parse の前段で剥がす）

差し戻したら、**該当群の wbtest に固定を 1 本足してもらってから**この Task に戻る。

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `pnpm test`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: `test/treeDialect.test.ts` が **3 本**とも緑（`ℹ pass` が 3 増え、`ℹ fail 0`）。EXIT=0

Run: `pnpm run check`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: 出力なし EXIT=0

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add test/treeDialect.test.ts
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "test: ✅ 方言の面と読みの裁定を外部審判で固定する"
```

---

## Task 70: カタログ C1〜C17 の固定

**Files:**
- Create: `D:/1.atrium/mmm/.worktrees/feat/tree-core/test/treeCases.test.ts`

**Interfaces:**
- Consumes: `doc`（7 メソッド全部）/ `cardText`（Task 63）
- Produces: なし（挙動の固定）

**固定するもの 3 つ**: 読み（元 md の指紋）/ 操作（実装済み op の反映 v0 の全文）/
正規形（新 md を `format` が動かさないこと）。

**C8 の md は `<summary>` 込みが正**（契約 §9）。`docs/superpowers/specs/2026-08-29-op-cases.md`
の C8 は **G3 Task 46 が先に直す**ので、この Task はその後に走る（着手順は一直線なので自然に満たされる）。

- [ ] **Step 1: 失敗するテストを書く**

`test/treeCases.test.ts` を新規作成する。

```typescript
// 操作ケースカタログ C1〜C17 の固定（docs/superpowers/specs/2026-08-29-op-cases.md）。
//
// 固定するのは 3 つ。
//   読み  : 元 md の指紋（parse が何を読んだか）
//   操作  : 実装済みの op（move / flipSide / delete）の反映 v0 の全文
//   正規形: 新 md が正規形であること（format が動かさない）
//
// **反映 v0 は全文正規形**なので、カタログの「新 md」がすげ替え（v1）を
// 前提にしている行（C7）だけは期待が異なる。差は備考に書く。
// 操作が未実装のケース（add / rename / fold / 打鍵）は読みだけを固定する。
//
// 指紋の逐語は契約 §8 の文法から導いたもの。実装と食い違ったら、
// どちらが正しいかを §8 に照らして決めること（テストを黙って書き換えない）。

import { test } from "branch:test";
import assert from "branch:assert/strict";
import { cardText, doc } from "./_tree.ts";

/** ラベルから id を引く。無ければ分かりやすく落とす */
function idOf(md: string, label: string): number {
  const m = doc.project(md);
  let found = -1;
  const walk = (n: {
    branch: { id: number; label: string };
    children: readonly unknown[];
  }): void => {
    if (n.branch.label === label && found < 0) found = n.branch.id;
    for (const c of n.children) {
      walk(
        c as {
          branch: { id: number; label: string };
          children: readonly unknown[];
        },
      );
    }
  };
  for (const t of m.trees) {
    if (t.branch.label === label && found < 0) found = t.branch.id;
    for (const b of t.right) walk(b);
    for (const b of t.left) walk(b);
  }
  assert.ok(found >= 0, `ラベル ${JSON.stringify(label)} のノードが無い`);
  return found;
}

test("C1: add — 形は正規形が決める（読みの固定。add は後日）", () => {
  const md = "# r\n\n## a\n\n- b\n- c\n";
  assert.equal(
    doc.sig(md),
    "D-n()[Reh_1:r()[>Neh_1:a()[Nel_1:b()[]Nel_1:c()[]]]]",
  );
  assert.equal(doc.format(md), md);
});

test("C2: add — 兄弟が居なければ親に従う（読みの固定。add は後日）", () => {
  const md = "# r\n\n## a\n";
  assert.equal(doc.sig(md), "D-n()[Reh_1:r()[>Neh_1:a()[]]]");
  assert.equal(doc.format(md), md);
});

test("C3: delete — 側の列から区切りが再導出される", () => {
  const md = "# r\n\n## a\n\n---\n\n## b\n\n---\n\n## c\n";
  assert.equal(
    doc.sig(md),
    "D-n()[Reh_1:r()[>Neh_1:a()[]<Neh_1:b()[]>Neh_1:c()[]]]",
  );
  const r = doc.deleteNodes(md, [idOf(md, "b")]);
  assert.equal(r.ok, true, r.reason);
  assert.equal(r.text, "# r\n\n## a\n\n## c\n");
  assert.equal(doc.format(r.text), r.text);
});

test("C4: flipSide — 先頭の枝も反転できる（先頭トグル）", () => {
  const md = "# r\n\n## a\n\n## b\n";
  assert.equal(doc.sig(md), "D-n()[Reh_1:r()[>Neh_1:a()[]>Neh_1:b()[]]]");
  const r = doc.flipSide(md, [idOf(md, "a")]);
  assert.equal(r.ok, true, r.reason);
  assert.equal(r.text, "# r\n\n---\n\n## a\n\n---\n\n## b\n");
  assert.equal(doc.sig(r.text), "D-n()[Reh_1:r()[<Neh_1:a()[]>Neh_1:b()[]]]");
});

test("C5: move — 散文は中身ごと運ばれ、level は付け直される", () => {
  const md = "# r\n\n## head\n\ncontent01\n\n***\n\ncontent02\n\n## head2\n";
  assert.equal(
    doc.sig(md),
    "D-n()[Reh_1:r()[>Neh_4:head(o9:content01ro9:content02)[]>Neh_5:head2()[]]]",
  );
  const r = doc.moveNodes(md, [idOf(md, "head")], idOf(md, "head2"), 0, false);
  assert.equal(r.ok, true, r.reason);
  assert.equal(
    r.text,
    "# r\n\n## head2\n\n### head\n\ncontent01\n\n***\n\ncontent02\n",
  );
});

test("C6: 階層飛びは構造なので正規形でも残る（読みの固定。rename は読みの道）", () => {
  const md = "# r\n\n## a\n\n#### b\n";
  assert.equal(doc.sig(md), "D-n()[Reh_1:r()[>Neh_1:a()[Ni[Neh_1:b()[]]]]]");
  assert.equal(doc.format(md), md);
  // 飛びは implied として map に居る（md には何も書かれない）
  const m = doc.project(md);
  assert.equal(m.trees[0]!.right[0]!.children[0]!.branch.implied, true);
});

test("C7: 飾りの水平線 — v0 は全文正規形なので `***` へ寄る", () => {
  const md = "# r\n\n## a\n\ntext\n\n---\n\nmore\n\n## b\n";
  assert.equal(
    doc.sig(md),
    "D-n()[Reh_1:r()[>Neh_1:a(o4:textro4:more)[]>Neh_1:b()[]]]",
  );
  const r = doc.flipSide(md, [idOf(md, "b")]);
  assert.equal(r.ok, true, r.reason);
  // カタログの新 md（`---` のまま）はすげ替え v1 の姿。v0 はチャンネル分離が効く
  assert.equal(r.text, "# r\n\n## a\n\ntext\n\n***\n\nmore\n\n---\n\n## b\n");
  assert.equal(
    doc.sig(r.text),
    "D-n()[Reh_1:r()[>Neh_1:a(o4:textro4:more)[]<Neh_1:b()[]]]",
  );
});

test("C8: fold — details で畳む。ネストは保存される（読みの固定。fold は後日）", () => {
  // details は骨格行の外・本文と子を包むので、畳まれているのは b（カタログの
  // mermaid は 〔畳〕 を c に付けているが、憲法 §4 に従えば持ち主は b）。
  // <summary> は serialize が label から毎回書き、parse は details の直後の
  // 1 枚を内容を見ずに読み飛ばす（契約 §9）。だから md には必ず居る。
  const md =
    "# r\n\n## a\n\n### b\n\n<details>\n\n<summary>b</summary>\n\n#### c\n\n</details>\n";
  assert.equal(
    doc.sig(md),
    "D-n()[Reh_1:r()[>Neh_1:a()[Neh^1:b()[Neh_1:c()[]]]]]",
  );
  assert.equal(doc.format(md), md);
  const after =
    "# r\n\n## a\n\n<details>\n\n<summary>a</summary>\n\n### b\n\n<details>\n\n<summary>b</summary>\n\n#### c\n\n</details>\n\n</details>\n";
  assert.equal(
    doc.sig(after),
    "D-n()[Reh_1:r()[>Neh^1:a()[Neh^1:b()[Neh_1:c()[]]]]]",
  );
  assert.equal(doc.format(after), after);
});

test("C9: format — 明示の全文正規化。意味は 1 ビットも変わらない", () => {
  const md = "# r\n\na\n---\n\n##   b   ##\n\n    code\n";
  assert.equal(
    doc.sig(md),
    "D-n()[Reh_1:r()[>Neh_1:a()[]>Neh_1:b(cc0:4:code)[]]]",
  );
  const out = "# r\n\n## a\n\n## b\n\n```\ncode\n```\n";
  assert.equal(doc.format(md), out);
  assert.equal(doc.sig(out), doc.sig(md));
  assert.equal(doc.format(out), out);
  // インデントコードは info 無しの Code カードとして箱に載る
  assert.equal(
    cardText(doc.project(md).trees[0]!.right[1]!.branch.cards[0]!),
    "code",
  );
});

test("C10: task list はラベルの一部（読みの固定。rename は読みの道）", () => {
  const md = "# r\n\n- [x] done\n- [ ] todo\n";
  assert.equal(
    doc.sig(md),
    "D-n()[Reh_1:r()[>Nel_8:[x] done()[]>Nel_8:[ ] todo()[]]]",
  );
  assert.equal(doc.format(md), md);
});

test("C11: frontmatter は封筒のまま", () => {
  const md = "---\nimage-folder: img\n---\n\n# r\n\n## a\n";
  assert.equal(
    doc.sig(md),
    "D+17:image-folder: imgn()[Reh_1:r()[>Neh_1:a()[]]]",
  );
  const r = doc.flipSide(md, [idOf(md, "a")]);
  assert.equal(r.ok, true, r.reason);
  assert.equal(r.text, "---\nimage-folder: img\n---\n\n# r\n\n---\n\n## a\n");
});

test("C12: 打鍵の道 — テキストが権威（core は走らない）", () => {
  const before = "# r\n\n## a\n\n## b\n";
  const after = "# r\n\n## a2\n\n## b\n";
  assert.equal(doc.sig(before), "D-n()[Reh_1:r()[>Neh_1:a()[]>Neh_1:b()[]]]");
  assert.equal(doc.sig(after), "D-n()[Reh_1:r()[>Neh_2:a2()[]>Neh_1:b()[]]]");
  assert.equal(doc.format(after), after);
});

test("C13: 読みの道 — 文字列は md として解釈される", () => {
  const after = "# r\n\n## 1. x\n\ny\n";
  assert.equal(doc.sig(after), "D-n()[Reh_1:r()[>Neh_4:1. x(o1:y)[]]]");
  assert.equal(doc.format(after), after);
});

test("C14: sign は行き先に従う — Item を節の間へ drop", () => {
  const md = "# r\n\n## a\n\n- x\n\n## b\n";
  assert.equal(
    doc.sig(md),
    "D-n()[Reh_1:r()[>Neh_1:a()[Nel_1:x()[]]>Neh_1:b()[]]]",
  );
  const r = doc.moveNodes(md, [idOf(md, "x")], idOf(md, "r"), 1, false);
  assert.equal(r.ok, true, r.reason);
  assert.equal(r.text, "# r\n\n## a\n\n## x\n\n## b\n");
  assert.deepEqual(doc.check(r.text), []);
});

test("C15: 全リストの map — Item root と content indent のトグル", () => {
  const md = "- root\n\n  - a\n\n  - b\n\n  ---\n\n  - c\n";
  assert.equal(
    doc.sig(md),
    "D-n()[Rel_6:root()[>Nel_1:a()[]>Nel_1:b()[]<Nel_1:c()[]]]",
  );
  // 無操作は無編集。format を通すと綴りは正規形へ寄るが、指紋は動かない
  assert.equal(doc.sig(doc.format(md)), doc.sig(md));
  assert.equal(doc.format(doc.format(md)), doc.format(md));
});

test("C16: implied 翼への flipSide — 昇格は不要", () => {
  const md = "# r\n\n#### b\n";
  assert.equal(doc.sig(md), "D-n()[Reh_1:r()[>Ni[Ni[Neh_1:b()[]]]]]");
  const wing = doc.project(md).trees[0]!.right[0]!.branch.id;
  const r = doc.flipSide(md, [wing]);
  assert.equal(r.ok, true, r.reason);
  assert.equal(r.text, "# r\n\n---\n\n#### b\n");
  assert.equal(doc.sig(r.text), "D-n()[Reh_1:r()[<Ni[Ni[Neh_1:b()[]]]]]");
});

test("C17: 項目 root の後ろの見出し — Item の子にはならない", () => {
  const md = "- a\n\n## h\n";
  assert.equal(doc.sig(md), "D-n()[Rel_1:a()[]Ri[>Neh_1:h()[]]]");
  assert.equal(doc.format(md), md);
  const m = doc.project(md);
  assert.equal(m.trees.length, 2);
  assert.equal(m.trees[0]!.branch.implied, false);
  assert.equal(m.trees[1]!.branch.implied, true);
});
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `pnpm test`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: `test/treeCases.test.ts` の 17 本のうち、実装が届いていないものが赤。
逐語の形は

```
AssertionError [ERR_ASSERTION]: Expected values to be strictly equal:
+ actual - expected

+ 'D-n(o10:- a\n\n## h\n)[]'
- 'D-n()[Rel_1:a()[]Ri[>Neh_1:h()[]]]'
```

EXIT=1

17 本とも最初から緑なら、C1 の指紋の期待値の末尾に `"x"` を足して
赤を見てから戻し、テストが走っていることを確かめる。

- [ ] **Step 3: 赤の差し戻し**

**この Task では実装を 1 行も書かない。** `core/tree/parse.mbt` / `serialize.mbt` /
`scan.mbt` には 1 バイトも書かない（契約 §2）。

赤の大半は G2 の `parse`。概要の**赤の差し戻し表**で担当群を決めて戻す。踏みやすい 3 つ:

- **C17 の「項目 root の後ろの見出し」** → G2 Task 22。列 0 の見出しは開いている項目を
  すべて閉じる（md ではリストが終わる）
- **C8 の `format(md) != md`** → `<summary>` を body に積んでいる。G2 Task 25（契約 §9）
- **C7 / C9 の綴りが正規形にならない** → G3 Task 41〜45（`spell` の値と `put`）

差し戻したら、**該当群の wbtest に固定を 1 本足してもらってから**この Task に戻る。

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `pnpm test`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: `test/treeCases.test.ts` が **17 本**すべて緑（`ℹ pass` が 17 増え、`ℹ fail 0`）。EXIT=0

Run: `pnpm run check`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: 出力なし EXIT=0

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add test/treeCases.test.ts
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "test: ✅ 操作ケースカタログ C1〜C17 を固定する"
```

---

## Task 71: CI に新パッケージを乗せる

**Files:**
- Modify: `D:/1.atrium/mmm/.worktrees/feat/tree-core/.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `pnpm run test:core` / `pnpm run fmt:doc`（Task 62）
- Produces: なし

**なぜ**: `moon test -p` の綴りを間違えると `Warning: package ... not found` +
`Total tests: 0, passed: 0, failed: 0.` で **EXIT=0 の緑**になる（契約 §17 の罠）。
CI が `Total tests: 0` を検知しないと、新パッケージのテストが 1 本も走らないまま
ずっと緑であり続ける。

- [ ] **Step 1: 失敗するテストを書く**

`.github/workflows/ci.yml` の `Core tests（MoonBit）` を差し替える。
**代入で失敗を握り潰さない形にする** — GitHub Actions の Linux 既定シェルは `bash -e` なので、
`out=$(...)` が非ゼロで終わった瞬間にステップが打ち切られ、`echo "$out"` に到達しない
（一番見たい失敗の逐語が消える）。

```yaml
      # `-p` の綴りを間違えると `Total tests: 0` で緑になる。数えていることを確かめる
      - name: Core tests（MoonBit）
        run: |
          set +e
          out=$(pnpm run test:core 2>&1)
          status=$?
          set -e
          echo "$out"
          if [ $status -ne 0 ]; then exit $status; fi
          if echo "$out" | grep -q "Total tests: 0,"; then
            echo "テストが 1 本も走っていない（-p の綴りを疑う）"
            exit 1
          fi
```

- [ ] **Step 2: テストを走らせて失敗を確認**

手元で検知の仕掛けだけを確かめる。`package.json` の `test:core` を
`-p mmm-app/core/nope` に**一時的に**差し替えて

Run: `pnpm run test:core`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: `Warning: package \`mmm-app/core/nope\` not found` /
`Total tests: 0, passed: 0, failed: 0.` EXIT=0（**赤にならないことがバグ**。
上の `grep` がこれを拾う）

確かめたら `package.json` を Task 62 の形へ戻す。

- [ ] **Step 3: 最小の実装を書く**

`.github/workflows/ci.yml` に整形の検査を 1 段足す（`Install MoonBit` の後、
`pnpm install --frozen-lockfile` の後ならどこでもよいが、`pnpm run core` の前に置く）。

```yaml
      - name: Format check（新パッケージのみ）
        run: |
          cd core
          moon fmt --check tree tree/js
```

`cd core` を挟むのは、`pnpm run fmt:doc` が `pnpm install` の後でないと使えないため。
**旧 `core/js` を対象に含めてはならない**（別名 `@core` が剥がされる差分で必ず赤になる。
契約 §17 の罠）。

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `pnpm run test:core`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: `Total tests: 303, passed: 303, failed: 0.` EXIT=0
（旧 core 192 + 新パッケージ 111 = G1 25 + G2 23 + G3 21 + G5 32 + G4 10）

Run: `moon -C D:/1.atrium/mmm/.worktrees/feat/tree-core/core test -p mmm-app/core -p mmm-app/core/tree`
Expected: 同じく `Total tests: 303, passed: 303, failed: 0.` EXIT=0（群の締めだけ `-p`）

Run: `pnpm run fmt:doc`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: `Finished. moon: ran N tasks, now up to date` EXIT=0

Run: `pnpm run core` → `pnpm run check` → `pnpm test`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: 3 つとも EXIT=0。`pnpm test` の末尾が `ℹ fail 0`

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add .github/workflows/ci.yml
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "ci: 👷 新 core のテストと整形を CI に乗せ、Total tests: 0 を検知する"
```

---

## Task 72: 操作の性質のファズ

**Files:**
- Create: `D:/1.atrium/mmm/.worktrees/feat/tree-core/test/treeOps.test.ts`

**Interfaces:**
- Consumes: `test/_tree.ts` の `doc` / `apply` / `randomDoc` / `fuzzCases` / `brief` /
  `Mindmap` / `MapBranch` / `Reflection`（Task 63〜65）。
  境界の `moveNodes` / `flipSide` / `deleteNodes` / `check` / `project` / `format` / `sig`（Task 62）
- Produces: なし（操作の性質の固定）

**設計は G5 由来、所有は G4**（契約 §2。`test/` は G4 の所有）。
G5 は着手しない。見る性質は 5 つ:

1. **拒否は無編集** — `ok:false` なら `text` は元のまま・`edits` は空
2. **適用後も健全** — `check` が空（回復が効いている）
3. **当てれば一致** — `apply(md, edits) === text`（自己検査の外側での再確認）
4. **反映の先は不動** — `format(text) === text`（法則 2 が操作の後でも立つ）
5. **側の反転は対合** — 同じ id へ 2 回 flipSide で指紋が戻る

- [ ] **Step 1: 失敗するテストを書く**

`test/treeOps.test.ts` を新規作成する。

```typescript
// 操作の性質。ランダムな文書に木の道を通し、法則が操作の後でも立つことを見る。
// 期待出力は 1 つも手書きしない — 見るのは「操作と法則の関係」だけ。

import { test } from "branch:test";
import assert from "branch:assert/strict";
import {
  apply,
  brief,
  doc,
  fuzzCases,
  randomDoc,
  type MapBranch,
  type Mindmap,
  type Reflection,
} from "./_tree.ts";

/** 絵に出ているノードの id を文書順に集める */
function idsOf(map: Mindmap): number[] {
  const out: number[] = [];
  const walk = (b: MapBranch): void => {
    out.push(b.branch.id);
    for (const c of b.children) walk(c);
  };
  for (const t of map.trees) {
    out.push(t.branch.id);
    for (const b of t.right) walk(b);
    for (const b of t.left) walk(b);
  }
  return out;
}

/** 反映 1 回ぶんの不変。ok の真偽で見るものが分かれる */
function holds(md: string, r: Reflection, why: string): void {
  if (!r.ok) {
    assert.equal(r.text, md, `拒否は無編集: ${why} ${brief(md)}`);
    assert.equal(r.edits.length, 0, `拒否は無編集: ${why} ${brief(md)}`);
    return;
  }
  assert.equal(apply(md, r.edits), r.text, `当てれば一致: ${why} ${brief(md)}`);
  assert.deepEqual(doc.check(r.text), [], `適用後も健全: ${why} ${brief(md)}`);
  assert.equal(
    doc.format(r.text),
    r.text,
    `反映の先は不動: ${why} ${brief(md)}`,
  );
}

test("拒否は無編集 — 居ないノードは 1 バイトも書き替えない", () => {
  for (let i = 0; i < fuzzCases(200); i++) {
    const md = randomDoc(i);
    for (const r of [
      doc.moveNodes(md, [999999], 1, 0, false),
      doc.flipSide(md, [999999]),
      doc.deleteNodes(md, [999999]),
    ]) {
      assert.equal(r.ok, false, `居ない id は拒否: ${brief(md)}`);
      assert.equal(r.text, md, `拒否は無編集: ${brief(md)}`);
      assert.equal(r.edits.length, 0, `拒否は無編集: ${brief(md)}`);
    }
  }
});

test("delete — 消したサブツリーのぶんだけ絵が減り、木は健全なまま", () => {
  for (let i = 0; i < fuzzCases(200); i++) {
    const md = randomDoc(i);
    const ids = idsOf(doc.project(md));
    if (ids.length === 0) continue;
    const victim = ids[i % ids.length]!;
    // id は parse が first_id から振り直すので、消した id を次のノードが名乗る。
    // 同一性ではなくノード数で見る
    const before = ids.length;
    const r = doc.deleteNodes(md, [victim]);
    holds(md, r, "delete");
    if (r.ok) {
      assert.ok(
        idsOf(doc.project(r.text)).length < before,
        `delete でノードが減っていない: ${brief(md)}`,
      );
    }
  }
});

test("move — 文書を親にしても、ノードを親にしても法則が立つ", () => {
  for (let i = 0; i < fuzzCases(200); i++) {
    const md = randomDoc(i);
    const ids = idsOf(doc.project(md));
    if (ids.length < 2) continue;
    const from = ids[i % ids.length]!;
    const to = ids[(i + 1) % ids.length]!;
    holds(md, doc.moveNodes(md, [from], to, 0, false), "move→branch");
    holds(md, doc.moveNodes(md, [from], 1, 0, true), "move→doc");
  }
});

test("flipSide — 2 回かければ指紋が戻る（対合）", () => {
  for (let i = 0; i < fuzzCases(200); i++) {
    const md = randomDoc(i);
    const ids = idsOf(doc.project(md));
    if (ids.length === 0) continue;
    const target = ids[i % ids.length]!;
    const once = doc.flipSide(md, [target]);
    holds(md, once, "flipSide");
    if (!once.ok) continue;
    const twice = doc.flipSide(once.text, [target]);
    assert.equal(twice.ok, true, `2 回目が拒否された: ${brief(md)}`);
    assert.equal(
      doc.sig(twice.text),
      doc.sig(once.text === md ? md : doc.format(md)),
      `側の反転は対合: ${brief(md)}`,
    );
  }
});

test("無操作は無編集 — 正規形の文書を同じ場所へ動かしても編集は出ない", () => {
  for (let i = 0; i < fuzzCases(200); i++) {
    const md = doc.format(randomDoc(i));
    const map = doc.project(md);
    if (map.trees.length === 0) continue;
    const root = map.trees[0]!;
    if (root.right.length === 0) continue;
    if (root.left.length > 0) continue; // at は wings の index。バケツの index ではない
    const first = root.right[0]!.branch.id;
    const r = doc.moveNodes(md, [first], root.branch.id, 0, false);
    holds(md, r, "同位置への move");
    if (r.ok) {
      assert.equal(r.text, md, `同位置への move は無編集: ${brief(md)}`);
      assert.equal(r.edits.length, 0, `同位置への move は無編集: ${brief(md)}`);
    }
  }
});
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run: `pnpm run check`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: 出力なし EXIT=0（型が通らないなら `_tree.ts` の輸出が足りていない）

Run: `pnpm test`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: 落ちたアサーションのメッセージが、どの性質
（拒否は無編集 / 適用後も健全 / 当てれば一致 / 反映の先は不動 / 側の反転は対合）が
破れたかを名指す。EXIT=1

5 本とも最初から緑なら、1 本目の `assert.equal(r.ok, false, ...)` を
`assert.equal(r.ok, true, ...)` に一時的に変えて赤を見てから戻し、
テストが走っていることを確かめる。

- [ ] **Step 3: 赤の差し戻し**

**この Task では実装を 1 行も書かない。** `core/tree/op.mbt` / `diff.mbt` /
`serialize.mbt` には 1 バイトも書かない（契約 §2）。落ちた場合の差し戻し先は 1 つに決まる:

- **「適用後も健全」が落ちた** → `conform` か `prune`（G5 Task 85 / 87）。
  `doc.check(r.text)` が返した破れの文言（契約 §7 の 6 つ）がそのまま原因を名指す
- **「当てれば一致」が落ちた** → `diff`（G5 Task 91）。ただし `safe_edits` が全文置換へ
  落としているはずなので、ここが落ちたら `apply` の算術（G5 Task 90）
- **「反映の先は不動」が落ちた** → **G3 の serialize**（法則 2）
- **「拒否は無編集」が落ちた** → `reflect`（G5 Task 92）
- **「側の反転は対合」が落ちた** → `flip_side` が頂点集合の正規化（`crown`）を
  通っているかを見る（G5 Task 86。契約 §10 の裁定 4）

- [ ] **Step 4: テストを走らせて通過を確認**

Run: `pnpm test`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）
Expected: `test/treeOps.test.ts` が **5 本**とも緑（`ℹ pass` が 5 増え、`ℹ fail 0`）。EXIT=0

Run: `$env:MMM_FUZZ = '5000'; pnpm test; Remove-Item Env:MMM_FUZZ`
（cwd = `D:/1.atrium/mmm/.worktrees/feat/tree-core`。PowerShell）
Expected: 同じく `ℹ fail 0` EXIT=0

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core add test/treeOps.test.ts
git -C D:/1.atrium/mmm/.worktrees/feat/tree-core commit -m "test: ✅ 操作の後でも法則が立つことをファズで見張る"
```

---

## この群が終わったときの状態

```
moon -C <root>/core check                                     0 errors
moon -C <root>/core test -p mmm-app/core -p mmm-app/core/tree  Total tests: 303, failed: 0.
moon -C <root>/core fmt --check tree tree/js                    EXIT=0
pnpm run core                                                 0 errors
pnpm run check                                                出力なし
pnpm run test:core                                            Total tests: 303, failed: 0.
pnpm test                                                     ℹ fail 0
```

（`<root>` = `D:/1.atrium/mmm/.worktrees/feat/tree-core`）

新しく緑になっている mbt のテスト本数: `json_wbtest` 5 / `project_wbtest` 3 /
`laws_wbtest` 2 = **10 本**（新パッケージ全体で 111 本）。
新しく緑になっている TS のテスト本数: `treeLaws` 12 / `treeDialect` 3 /
`treeCases` 17 / `treeOps` 5 = **37 本**。

### スコープ外（この群では触らない）

`src/coreApi.ts` / `src/main.ts` / `src/app/paste.ts` / 旧 core の削除 / render の接続 /
すげ替え v1 / `docs/spec.md` の書き替え / `docs/ops.md`（G5 Task 94 の所有）。

### 引き継ぎの注意

- **`docs/` に置く .md は往復テストの入力になる。** 旧 core の P1（バイト同一・
  `test/roundtrip.test.ts`）と、この群が足した法則 1・2 の両方が食う。
  この計画を `docs/superpowers/plans/` に置くなら、それも往復すること
- **`$env:MMM_FUZZ` でケース数を上げられる**（PowerShell: `$env:MMM_FUZZ = '5000'; pnpm test` /
  後始末 `Remove-Item Env:MMM_FUZZ`）。マージ前に一度 5000 で回すこと
- **法則 1 の本丸は `core/tree/laws_wbtest.mbt`。** TS 側の法則 1 は md を種にした
  影であって、木の生成器の代わりにはならない
- **G4 は他群のファイルに 1 バイトも書かない。** 赤は必ず差し戻し表を通す。
  差し戻した先が直ったら、その群の wbtest に固定が 1 本増えているはず —
  増えていなければ、同じ赤がまた出る
