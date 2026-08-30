# T4 — 法則の検証基盤（Task 30〜36）

## この群の概要

**担当範囲（T4 = 法則の検証基盤。Task 30〜37 の 8 本）**

新 core が本当に正しいかを外から殴る足場を作る。実装（読み・書き・操作）は 1 行も書かない代わりに、**法則 1（`parse(serialize(M)) = M`）・法則 2（`serialize(parse(md))` の冪等）・法則 4（外部審判 @lezer/markdown との方言表）**の 3 本を、実在コーパス・カタログ・2 種のランダム生成器で立てる。

所有ファイル（正誤表 §B より。ここに無いものは作らない・触らない）:

| ファイル | 役割 |
|---|---|
| `<REPO>/core/doc/wire.mbt` | 外と**文字列だけ**でやり取りする面。木は JSON 文字列にする（裁定 3） |
| `<REPO>/core/doc/js/moon.pkg` / `js/exports.mbt` | `#export_name` の薄い層。**5 本だけ**。String / Int / Bool / Array[Int] しか触らない |
| `<REPO>/core/doc/law_wbtest.mbt` | 木の生成器 `gen_ast` と法則 1 のファズ |
| `<REPO>/test/_doc.ts` | TS 側の受け口。**T5 はこれを import する**（自前の型を定義しない） |
| `<REPO>/test/doc-law.test.ts` / `doc-dialect.test.ts` | 法則 2・法則 4 |
| `<REPO>/test/_helpers.ts:171` の除外名 1 行 / `package.json` の `"test:doc"` 1 行 | 既存ファイルへの**1 行だけ**の変更 |

以下 `<REPO>` = `D:/1.atrium/mmm/.claude/worktrees/doc-model`（本文では必ず展開して書く）。

**前提（着手条件）**

1. **Task 30 は誰も待たない。**最初に踏む（`pnpm install` / `pnpm run core` / コーパスの除外名）
2. Task 31・32 は **T2 Task 17（`parse`）と T3 Task 26（`serialize`）のコミット後**
3. Task 33 は Task 32 の後（`fixture_wbtest.mbt` の `chain_ast` を使うので T1 Task 2 も要る）
4. Task 34 → 35 → 36 はこの順（34 が表、35 が生成器、36 が審判）
5. Task 37 は **T5 Task 45・46・47（delete / side / move）と Task 40・41（edit / diff / reflect）の後**。前半（`shrink`）だけは先行できる

**着手順**

```
Task 30 ──> （T1・T2・T3 の完了）──> Task 31 ──> Task 32 ──> Task 33 ──> Task 34 ──> Task 35 ──> Task 36
                                                                （T5 の操作が揃う）──> Task 37 ──> T5 Task 48
```

**この群が守る規律**

- `core/doc/js/exports.mbt` は **`@doc.Node` / `@doc.Block` / `@doc.Ast` / `@doc.Reject` を一切触らない**（裁定 3）。JSON の組み立ては `core/doc/wire.mbt`（パッケージの内側）で完結する
- ラベル付き enum ペイロードの呼び出しは **`Image(alt="図", src="./a.png")`**（`alt~=` は `Error: [3016]`。実測 4）
- **`chain` を自前定義しない**。`fixture_wbtest.mbt`（T1 Task 2）の `chain_ast(n)` を使う
- **環境変数の前置き（`VAR=値 コマンド`）を書かない**（裁定 6）。**TS 側のファズの回数も定数**（`RANDOM_CASES` / `DIALECT_CASES`）で切り替える。`fuzzCases`（`process.env.MMM_FUZZ` を読む既存ヘルパ）は import しない
- `gen_ast` は **implied に Left を割り当てない**（裁定 1・不変条件 11）
- `gen_children` の implied は **children の先頭**に置く。不変条件 8 は裁定 B により「**implied の前に見出しの兄弟が居ない**」へ一般化されたので、先頭に置けば必ず満たす（違反メッセージは `implied の前に見出しが居る: <id>`）
- **単調性は parse の attach が強制する**（裁定 A）。`- a` + `## h` は「項目 a」と「implied root の下の h」の**木 2 本**になる。カタログ C17 がこれを 1 行で固定する
- テスト総数の Expected は逐語で書く。**`Total tests: 0` は緑ではない**（`-p` の綴りを疑う）
- **文書頭の `---` の裁定（裁定 E）を持つのは T1 の `scan_head`**（封筒なのは「閉じの `---` があり、かつ開きの直後が空行でない」とき）。T4 はそれを 2 か所で見張るだけ — 方言表の 1 行（Task 36）と、法則 1 ファズの **seed 199**（Task 33 の `gen_ast` が先頭トグル + トグルもう 1 本の木を吐く）。**落ちても直す先は T4 ではない**

**`law_wbtest.mbt` が置くトップレベル名は 12 個**: `fuzz_seeds`（ファズの回数）／`Rand`・`Rand::new`・`Rand::pick`（決定的な擬似乱数）／`Gen`（生成の状態）／`labels`（ラベルの見本）／`sample_block`・`side_for`・`gen_implied`・`gen_children`・`gen_node`・`gen_ast`（木の生成器）。
うち**正誤表 §C-3 の表に無いのは `fuzz_seeds` / `Rand::new` / `Rand::pick` の 3 個**なので、着手前に T4 の行へ足すこと（残り 9 個は既に表にある）。**とくに `labels` は総称的なので、他群は同名を置かないこと**（`*_wbtest.mbt` は名前空間を共有し、二重定義は `Error: [4051]` でパッケージのテストが 1 本も走らなくなる）。

TS 側で表に無い export を 1 つ増やす: `test/_doc.ts` の **`atxWritable`**（Task 35）。Task 36 の番人が同じ規則で審判への入力を絞るので、`export` を付けて import させる（規則の写しを MoonBit の `atx_writable` とこの 1 つより増やさない）。**着手前に §D-3 の表へ 1 行足すこと。**`LABELS` / `SETEXT_LABELS` / `BLOCKS` は生成器の内側のままで export しない。

---

## Task 30: テスト基盤の 3 件を直す（着手前の地ならし）

**Files:**
- Create: `D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-law.test.ts`
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/test/_helpers.ts`（171 行目の除外名 **1 行だけ**）
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-law.test.ts`

**Interfaces:**
- Consumes: `corpus() : { path: string; md: string }[]`（既存 `test/_helpers.ts:159`）
- Produces: 兄弟ワークツリーの md が混ざらない `corpus()`。以後の法則 2・法則 4 の入力集合はこれ 1 本。`test/doc-law.test.ts` というファイル自体（Task 32・34・35・37 が追記していく）

- [ ] **Step 1: 失敗するテストを書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-law.test.ts` を新規作成する。この時点では `_doc.ts`（新 core のラッパ）はまだ無いので、入力集合そのものの健全性だけを見る。

```ts
// 法則 1・2 の検証。入力は「実在コーパス + fixtures + ランダム生成」の 3 点セット。
//
// このファイルの先頭 3 本は入力集合そのものの検査 — コーパスがローカルの
// ワークツリー状況で増減すると、法則の検証が「今日は 40 本、明日は 68 本」に
// なってしまい、落ちた/落ちないの再現性が失われる。

import test from "node:test";
import assert from "node:assert/strict";
import { corpus } from "./_helpers.ts";

test("コーパスに兄弟ワークツリーの md が混ざらない", () => {
  // 実レイアウトは `.claude/worktrees/<name>`。除外名が `.worktrees` だと
  // 一致せず、main リポで回したときだけ入力が増えていた。
  const leaked = corpus()
    .map((d) => d.path)
    .filter((p) => p.includes("/worktrees/"));
  assert.deepEqual(
    leaked,
    [],
    `ワークツリー配下の md が混ざっている:\n  ${leaked.join("\n  ")}`,
  );
});

test("コーパスは空でなく、決定的である", () => {
  const a = corpus().map((d) => d.path);
  const b = corpus().map((d) => d.path);
  assert.ok(a.length > 0, "対象の .md が 1 つも見つからない");
  assert.deepEqual(a, b, "2 回呼ぶと結果が違う");
});

test("コーパスは fixtures を含む（深さ 200 が入力から落ちない）", () => {
  const paths = corpus().map((d) => d.path);
  const want = [
    "/test/fixtures/deep.md",
    "/test/fixtures/gnarly.md",
    "/test/fixtures/gnarly-crlf.md",
  ];
  const missing = want.filter((w) => !paths.includes(w));
  assert.deepEqual(
    missing,
    [],
    `fixtures がコーパスから落ちている: ${missing.join(", ")}`,
  );
});
```

- [ ] **Step 2: テストを走らせて失敗を確認**

このワークツリーには `node_modules` も `core/_build` も無い（実測 10）。テストを走らせる前に一度だけ踏む:

Run:
```
pnpm -C D:/1.atrium/mmm/.claude/worktrees/doc-model install
pnpm -C D:/1.atrium/mmm/.claude/worktrees/doc-model run core
node --test D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-law.test.ts
```

Expected:
- `pnpm install` を踏むまでは `@lezer/markdown` が解決できない（Task 36 で要る）。`pnpm run core` を踏むまでは `test/_helpers.ts` が `Error: コアの JS 出力が無い: …core/_build/js/release/build/js/js.js` で落ちる
- 両方踏んだ後、**このワークツリーの中では 3 本とも通ってしまう**（`REPO` 自身がワークツリーの中なので、相対パスに `/worktrees/` が現れない）。**欠陥は main リポを歩いたときにしか見えない**

赤は main リポで見せる。ただし **main リポジトリには 1 バイトも書き込まない**（計画自身の規律であり、main には `node_modules` も `core/_build` も無いので `test/_helpers.ts` は別の理由で落ちる）。`test/_helpers.ts:159-186` の `walk` と同じ規則をその場で再現する node ワンライナーで、歩いて数えるだけにする。**`\` を 1 文字も書かない綴り**にしてあるので、PowerShell でも Bash でもそのまま動く（`path.sep` を使うので逃がしの違いを踏まない）。

Run（いまの除外名 `.worktrees` を再現する）:
```
node -e "const {readdirSync}=require('fs');const {join,sep}=require('path');const REPO='D:/1.atrium/mmm';const skip=new Set(['node_modules','_build','.git','target','.worktrees']);const out=[];const walk=(d,dep=0)=>{if(dep>3)return;let e;try{e=readdirSync(d,{withFileTypes:true})}catch{return}for(const x of e){if(skip.has(x.name))continue;const p=join(d,x.name);if(x.isDirectory())walk(p,dep+1);else if(x.name.endsWith('.md'))out.push(p.split(sep).join('/').replace(REPO,''))}};walk(REPO);console.log('総数',out.length,'漏れ',out.filter(p=>p.includes('/worktrees/')).length)"
```
Expected: `総数 <N> 漏れ <M>` の 1 行が出て、**`M` が 0 より大きい**（`/.claude/worktrees/<name>/CLAUDE.md` などが混ざっている）。これが期待どおりの赤である。

Run（除外名を `worktrees` に替えた場合。**直す前後の差を見るためだけ**に回す）:
```
node -e "const {readdirSync}=require('fs');const {join,sep}=require('path');const REPO='D:/1.atrium/mmm';const skip=new Set(['node_modules','_build','.git','target','worktrees']);const out=[];const walk=(d,dep=0)=>{if(dep>3)return;let e;try{e=readdirSync(d,{withFileTypes:true})}catch{return}for(const x of e){if(skip.has(x.name))continue;const p=join(d,x.name);if(x.isDirectory())walk(p,dep+1);else if(x.name.endsWith('.md'))out.push(p.split(sep).join('/').replace(REPO,''))}};walk(REPO);console.log('総数',out.length,'漏れ',out.filter(p=>p.includes('/worktrees/')).length)"
```
Expected: `漏れ 0`。**修正はワークツリー側の `test/_helpers.ts` だけに入れる。**

- [ ] **Step 3: 最小の実装を書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/test/_helpers.ts` の 171 行目を、実レイアウトに合わせる。**この 1 行だけ**を変える。

変更前:
```ts
        e.name === "target" || // Rust のビルド出力 (src-tauri/target)
        e.name === ".worktrees" // CLAUDE.md の並行作業用ワークツリー置き場
```

変更後:
```ts
        e.name === "target" || // Rust のビルド出力 (src-tauri/target)
        e.name === "worktrees" // 並行作業用ワークツリー置き場（.claude/worktrees/<name>）
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
node --test D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-law.test.ts
```
Expected: `ℹ tests 3` / `ℹ pass 3` / `ℹ fail 0` / EXIT=0。
main リポを歩き直したときも同じ判定が立つ。**本数は手元のワークツリーの数で動くので数えない** — 見るのは「`/worktrees/` を含む path が 0 本であること」と「`fixtures` の 3 本が入っていること」の 2 点だけである（確かめるなら Step 2 の 2 本目のワンライナーで `漏れ 0` を見る。main には何も書かない）。

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add test/_helpers.ts test/doc-law.test.ts
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "test: 🧪 コーパスから兄弟ワークツリーの md を締め出す"
```

---

## Task 31: MoonBit の受け口（読みの 3 本）

**依存**: T1 Task 1〜9・T2 Task 10〜17（`parse`）・T3 Task 20〜26（`serialize`）の完了後に着手する。

**Files:**
- Create: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/wire.mbt`
- Create: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/js/moon.pkg`
- Create: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/js/exports.mbt`
- Test: なし（このタスクの赤は node の疎通で取る。TS 側のテストは Task 32）

**Interfaces:**
- Consumes: `parse(md : String) -> Ast`（T2 Task 17）／`serialize(ast : Ast) -> String`（T3 Task 26）／`sig(ast : Ast) -> String`・`check(ast : Ast) -> Array[String]`（T1 Task 2・3）／型 `Form` / `Side` / `Eol`（T1 Task 1）
- Produces:
  - MoonBit: `pub fn sig_of(md : String) -> String` / `pub fn format_of(md : String) -> String` / `pub fn check_of(md : String) -> String`（`core/doc/wire.mbt`）と private の `json_str` / `form_tag` / `side_tag` / `eol_tag` / `bool_lit`
  - JS: `docSig(md: string): string` / `docFormat(md: string): string` / `docCheck(md: string): string`（`core/_build/js/release/build/doc/js/js.js`）

- [ ] **Step 1: 受け口が無いことを、これから使う綴りで確認する（赤）**

このタスクは境界の層なので、赤はテストファイルではなく **JS の生成物を読む疎通**で取る。Task 32 以降の `test/_doc.ts` が読むのと同じパスを、同じ綴りで叩く。

Run:
```
node -e "import('file:///D:/1.atrium/mmm/.claude/worktrees/doc-model/core/_build/js/release/build/doc/js/js.js').then(m => console.log(m.docSig('# r\n')))"
```
Expected: `Error [ERR_MODULE_NOT_FOUND]: Cannot find module 'D:\1.atrium\mmm\.claude\worktrees\doc-model\core\_build\js\release\build\doc\js\js.js'` / EXIT=1。
（`core/doc/js` パッケージがまだ無いので、`pnpm run core` を踏んでもこのファイルは出ない。）

- [ ] **Step 2: JS パッケージの宣言を置く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/js/moon.pkg` を新規作成する。**別名を書かない** — `moon fmt` は最終パスセグメントと同じ別名を剥がすので、`@doc` と書くと必ず差分が出る（実測 7-2）。既定の別名が `doc` なので、コードからは `@doc.…` で参照できる。

```
pkgtype(kind: "foreign_library")

import {
  "mmm-app/core/doc",
}
```

- [ ] **Step 3: 外と文字列だけでやり取りする面を書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/wire.mbt` を新規作成する。**このファイルは `mmm-app/core/doc` の内側**なので `@doc.` は付けない。

```moonbit
// 外と文字列だけでやり取りする面。UI 接続の公開 API ではない —
// テスト（TS 側のコーパス・ファズ）の受け口としてだけ在る。
//
// **struct は境界を跨がない**（裁定 3）。木を外へ出すときは JSON 文字列にする。
// JSON の組み立てはこのファイルで完結し、`js/exports.mbt` は
// String / Int / Bool / Array[Int] しか触らない。

///|
/// JSON の文字列リテラル 1 つ。依存を足さないので手組み。
/// `s.iter()` はコードポイント単位なので、サロゲートペアは 1 文字として
/// そのまま書き出される（JSON は UTF-8 でよい）。
fn json_str(s : String) -> String {
  let hex = "0123456789abcdef".to_array()
  let sb = StringBuilder::new()
  sb.write_string("\"")
  for ch in s.iter() {
    let c = ch.to_int()
    if c == 34 {
      sb.write_string("\\\"")
    } else if c == 92 {
      sb.write_string("\\\\")
    } else if c == 10 {
      sb.write_string("\\n")
    } else if c == 13 {
      sb.write_string("\\r")
    } else if c == 9 {
      sb.write_string("\\t")
    } else if c < 32 {
      sb.write_string("\\u00")
      sb.write_char(hex[c / 16])
      sb.write_char(hex[c % 16])
    } else {
      sb.write_char(ch)
    }
  }
  sb.write_string("\"")
  sb.to_string()
}

///|
fn form_tag(f : Form) -> String {
  match f {
    Heading => "H"
    Item => "I"
  }
}

///|
fn side_tag(s : Side) -> String {
  match s {
    Right => "R"
    Left => "L"
  }
}

///|
fn eol_tag(e : Eol) -> String {
  match e {
    Lf => "lf"
    Crlf => "crlf"
  }
}

///|
fn bool_lit(b : Bool) -> String {
  if b {
    "true"
  } else {
    "false"
  }
}

///|
/// 読んで指紋を取る。法則 1・2 の比較子はこれ 1 本。
pub fn sig_of(md : String) -> String {
  sig(parse(md))
}

///|
/// 正規形。`serialize(parse(md))` = mmm のフォーマッタそのもの。
pub fn format_of(md : String) -> String {
  serialize(parse(md))
}

///|
/// 不変条件の違反を "\n" 区切りで。空なら健全。
/// 違反メッセージは改行を含まない（§A-3）ので、TS 側は split("\n") で戻せる。
pub fn check_of(md : String) -> String {
  let vs = check(parse(md))
  let sb = StringBuilder::new()
  for i = 0; i < vs.length(); i = i + 1 {
    if i > 0 {
      sb.write_string("\n")
    }
    sb.write_string(vs[i])
  }
  sb.to_string()
}
```

- [ ] **Step 4: JS の受け口を書き、疎通が通ることを確認する（緑）**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/js/exports.mbt` を新規作成する。**1 行ラッパだけ**。ここに判断を書かない。

```moonbit
// mmm-app/core/doc の薄い受け口。**テストの受け口としてだけ**在る
// （UI 接続は範囲外 — 公開 API は接続する日に決める）。
//
// 境界を跨ぐのは String / Int / Bool / Array[Int] だけ（裁定 3）。
// 木は JSON 文字列で渡す。組み立ては `core/doc/wire.mbt` が持つ。

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
```

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core check doc
pnpm -C D:/1.atrium/mmm/.claude/worktrees/doc-model run core
node -e "import('file:///D:/1.atrium/mmm/.claude/worktrees/doc-model/core/_build/js/release/build/doc/js/js.js').then(m => { console.log(JSON.stringify(m.docSig('# r\n'))); console.log(JSON.stringify(m.docFormat('#  r  \n'))); console.log(JSON.stringify(m.docCheck('# r\n'))); })"
```
Expected:
- `moon fmt` / `moon check` が `Finished. moon: ran N tasks, now up to date` で EXIT=0（`fmt` が EXIT=127 を返したら差分があるということなので、出た差分をそのまま取り込む）
- `pnpm run core` が通り、`core/_build/js/release/build/doc/js/js.js` が旧 `.../build/js/js.js` と**並んで**出る（`package.json` の `"core"` は無変更）
- node の出力が 3 行:
  ```
  "head:-\nlf\n[H[Hr]]"
  "# r\n"
  ""
  ```

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add core/doc/wire.mbt core/doc/js/moon.pkg core/doc/js/exports.mbt
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "feat: ✨ 新 core の JS 受け口を開ける"
```

---

## Task 32: 木の JSON と TS ラッパ

**Files:**
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/wire.mbt`（`json_block` / `json_node` / `tree_of` を追記）
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/js/exports.mbt`（`doc_tree` を追記）
- Create: `D:/1.atrium/mmm/.claude/worktrees/doc-model/test/_doc.ts`
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-law.test.ts`
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-law.test.ts`

**Interfaces:**
- Consumes: `docSig` / `docFormat` / `docCheck`（Task 31）／`Ast` / `Node` / `Block` / `Content`（T1）／`is_implied(nd : Node) -> Bool`（T1）
- Produces:
  - JS: `docTree(md: string): string`（§D-1 の鍵で固定した JSON）
  - TS（`test/_doc.ts`。**T5 はこれを import する。自前の型を定義しない**）: 型 `DocBlock` / `DocNode` / `DocTree`、関数 `sig` / `format` / `check` / `tree` / `flatten` / `skeleton` / `blockSig` / `blocksOf`
  - **`blockSig` は逃がさない**（MoonBit の `block_sig` と綴りが違う）。MoonBit 側は `esc` が `\` `|` `[` `]` `~` `^` `<` を `\` で逃がすので、同じ木でも指紋の綴りが一致しない。**両者の期待値を写し合わないこと**

- [ ] **Step 1: 失敗するテストを書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-law.test.ts` の import 行の直後に 1 行足す。

```ts
import { format, check, sig, tree, flatten, skeleton, blocksOf } from "./_doc.ts";
```

ファイル末尾に受け口の疎通テストを 3 本追加する。

```ts
// ---------------------------------------------------------------
// 受け口の疎通 — TS から新 core の読みが 1 本の道で見えること。
// 木は JSON 文字列で来る（境界を struct が跨がない。裁定 3）。
// ---------------------------------------------------------------

test("受け口: 正規形の md は format で不動、指紋が取れ、不変条件を満たす", () => {
  const md = "# r\n\n## a\n";
  assert.equal(format(md), md);
  assert.equal(check(md).length, 0, `不変条件の違反: ${check(md).join(" / ")}`);
  assert.equal(sig(md), "head:-\nlf\n[H[Hr[Ha]]]");
});

test("受け口: 木の JSON は doc(id=1, depth=0) から始まり、深さが導出値として入る", () => {
  const t = tree("# r\n\n- x\n");
  assert.equal(t.eol, "lf");
  assert.equal(t.head, null);
  assert.equal(t.doc.id, 1);
  assert.equal(t.doc.depth, 0);
  assert.deepEqual(
    flatten(t.doc).map((n) => [n.form, n.label, n.depth, n.implied]),
    [
      ["H", "r", 1, false],
      ["I", "x", 2, false],
    ],
  );
});

test("受け口: 中身のかたまりは指紋と同じ語彙で読める", () => {
  assert.deepEqual(skeleton("# r\n\n## a\n"), ["H:r", "H:a"]);
  assert.deepEqual(blocksOf("# r\n\n![図](./a.png)\n\n***\n"), [
    "img:図|./a.png",
    "rule",
  ]);
});
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
node --test D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-law.test.ts
```
Expected: `Error [ERR_MODULE_NOT_FOUND]: Cannot find module 'D:\1.atrium\mmm\.claude\worktrees\doc-model\test\_doc.ts'` でファイルごと落ちる（Task 30 の 3 本も巻き込まれる）。EXIT=1。

- [ ] **Step 3: 木の JSON を組み立てる**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/wire.mbt` の末尾（`check_of` の後）に追記する。鍵の順序も §D-1 のとおりに固定する（比較を目で追えるようにするため。TS は順序に依存しない）。

```moonbit
///|
/// 中身のかたまり 1 つの JSON。鍵は §D-1 で固定。
fn json_block(b : Block) -> String {
  match b {
    Rule => "{\"k\":\"rule\"}"
    Opaque(t) => "{\"k\":\"opaque\",\"text\":" + json_str(t) + "}"
    Content(Image(alt~, src~)) =>
      "{\"k\":\"image\",\"alt\":" +
      json_str(alt) +
      ",\"src\":" +
      json_str(src) +
      "}"
    Content(Link(text~, href~)) =>
      "{\"k\":\"link\",\"text\":" +
      json_str(text) +
      ",\"href\":" +
      json_str(href) +
      "}"
    Content(Code(info~, text~)) =>
      "{\"k\":\"code\",\"info\":" +
      json_str(info) +
      ",\"text\":" +
      json_str(text) +
      "}"
    Content(Svg(t)) => "{\"k\":\"svg\",\"text\":" + json_str(t) + "}"
  }
}

///|
/// ノード 1 つの JSON。**depth は導出値**だが、TS のテストが読むので書き出す。
/// implied の判定は必ず `is_implied` を通す（v1 で中身が替わる）。
fn json_node(nd : Node, depth : Int) -> String {
  let sb = StringBuilder::new()
  sb.write_string("{\"id\":")
  sb.write_string(nd.id.to_string())
  sb.write_string(",\"depth\":")
  sb.write_string(depth.to_string())
  sb.write_string(",\"form\":")
  sb.write_string(json_str(form_tag(nd.form)))
  sb.write_string(",\"label\":")
  sb.write_string(json_str(nd.label))
  sb.write_string(",\"implied\":")
  sb.write_string(bool_lit(is_implied(nd)))
  sb.write_string(",\"folded\":")
  sb.write_string(bool_lit(nd.folded))
  sb.write_string(",\"side\":")
  sb.write_string(json_str(side_tag(nd.side)))
  sb.write_string(",\"body\":[")
  for i = 0; i < nd.body.length(); i = i + 1 {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string(json_block(nd.body[i]))
  }
  sb.write_string("],\"children\":[")
  for i = 0; i < nd.children.length(); i = i + 1 {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string(json_node(nd.children[i], depth + 1))
  }
  sb.write_string("]}")
  sb.to_string()
}

///|
/// 木そのものの JSON（id 付き）。
pub fn tree_of(md : String) -> String {
  let ast = parse(md)
  let head = match ast.head {
    Some(h) => json_str(h)
    None => "null"
  }
  "{\"eol\":" +
  json_str(eol_tag(ast.eol)) +
  ",\"head\":" +
  head +
  ",\"doc\":" +
  json_node(ast.doc, 0) +
  "}"
}
```

- [ ] **Step 4: JS の受け口に 1 本足して、生成物を作り直す**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/js/exports.mbt` の末尾に追記する。

```moonbit
///|
#export_name("docTree")
pub fn doc_tree(md : String) -> String {
  @doc.tree_of(md)
}
```

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
pnpm -C D:/1.atrium/mmm/.claude/worktrees/doc-model run core
node -e "import('file:///D:/1.atrium/mmm/.claude/worktrees/doc-model/core/_build/js/release/build/doc/js/js.js').then(m => console.log(m.docTree('# r\n')))"
```
Expected: `pnpm run core` が `Finished. moon: ran N tasks, now up to date` で EXIT=0。node の出力が逐語で
```
{"eol":"lf","head":null,"doc":{"id":1,"depth":0,"form":"H","label":"","implied":false,"folded":false,"side":"R","body":[],"children":[{"id":2,"depth":1,"form":"H","label":"r","implied":false,"folded":false,"side":"R","body":[],"children":[]}]}}
```

- [ ] **Step 5: TS 側の受け口を作る**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/test/_doc.ts` を新規作成する。**このファイルの export だけが存在する名前**であり、T5 の `test/doc-ops.test.ts` はここから import する（写経しない）。

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
import { REPO } from "./_helpers.ts";

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

/** かたまり 1 つを 1 本の文字列に畳む。
 *  **MoonBit 側の `block_sig` とは違い逃がし（`\\` `|` `[` `]` `~` `^` `<`）をしない** —
 *  TS 側は木の同一性判定に使わない（比較子は `sig` 1 本）ので読みやすさを取る。
 *  MoonBit の指紋と期待値を写し合わないこと。 */
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
```

- [ ] **Step 6: テストを走らせて通過を確認**

Run:
```
node --test D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-law.test.ts
pnpm -C D:/1.atrium/mmm/.claude/worktrees/doc-model run check
```
Expected: `ℹ tests 6` / `ℹ pass 6` / `ℹ fail 0` / EXIT=0（Task 30 の 3 本 + 本タスクの 3 本）。
`pnpm run check` も EXIT=0（`test/tsconfig.json` の `include` が `"."` なので `_doc.ts` も型検査の対象。`noUnusedLocals` があるので未使用の import が 1 つでもあれば `error TS6133` で赤になる）。

- [ ] **Step 7: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add core/doc/wire.mbt core/doc/js/exports.mbt test/_doc.ts test/doc-law.test.ts
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "test: 🧪 新 core の読みを TS から見る受け口を開ける"
```

---

## Task 33: 木の生成器と法則 1 のファズ

**Files:**
- Create: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/law_wbtest.mbt`
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/package.json`（`"test:doc"` の **1 行だけ**追加。`"test:core"` は触らない）
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/law_wbtest.mbt`

**Interfaces:**
- Consumes: `Ast` / `Node` / `Block` / `Content` / `Form` / `Side` / `Eol`（T1 Task 1）、`sig(ast) -> String`・`check(ast) -> Array[String]`（T1 Task 2・3）、**`chain_ast(n : Int) -> Ast`（T1 Task 2 の `fixture_wbtest.mbt`）**、`parse(md) -> Ast`（T2 Task 17）、`serialize(ast) -> String`（T3 Task 26）
- Produces: このファイルが新設するトップレベル名は 12 個 — `fuzz_seeds` / `Rand` / `Rand::new` / `Rand::pick` / `Gen` / `labels` / `sample_block` / `side_for` / `gen_implied` / `gen_children` / `gen_node` / `gen_ast(seed : Int) -> Ast`。**着手前に §C-3 の T4 の行へ全部足すこと**（`*_wbtest.mbt` は名前空間を共有し、二重定義は `Error: [4051]`）。加えて `pnpm run test:doc` の綴り

- [ ] **Step 1: 失敗するテストを書く**

まず現状の本数を控える（Step 4 の Expected をここで確定させるため）。

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected: `Total tests: B, passed: B, failed: 0.`（B = T1〜T3 の累計。**この B を控える**。`Total tests: 0` が出たら `-p` の綴りを疑う — 実測 7-1 の罠 A で、綴り違いは EXIT=0 の緑に見える）

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/law_wbtest.mbt` を新規作成し、**テストだけ**を書く（生成器は Step 3）。

```moonbit
// 木をランダムに組んで法則 1（parse(serialize(M)) = M）を殴る。
// 生成器・sig・check はいずれも同パッケージの private なので whitebox テスト。
//
// 手で木を組む道具（node / heading / item / slot / doc_of / ast_of / chain /
// chain_ast）は `fixture_wbtest.mbt`（T1 Task 2）が持つ。ここで作り直さない。

///|
/// ファズの回数。深掘りするときはこの数を上げる
/// （環境変数の前置きは PowerShell で構文エラーになるので使わない）。
let fuzz_seeds : Int = 300

///|
test "生成した木は不変条件を満たす（生成器そのものの検査）" {
  // 生成側で不変条件を満たすので、ここが落ちたら生成器のバグ。木の検査ではない。
  let mut bad = ""
  for seed = 1; seed <= fuzz_seeds; seed = seed + 1 {
    let vs = check(gen_ast(seed))
    if vs.length() > 0 && bad == "" {
      bad = "seed=" + seed.to_string() + " " + vs[0]
    }
  }
  assert_eq(bad, "")
}

///|
test "生成した木は parse(serialize(M)) で戻る（法則 1）" {
  let mut bad = ""
  for seed = 1; seed <= fuzz_seeds; seed = seed + 1 {
    let m = gen_ast(seed)
    let md = serialize(m)
    let back = parse(md)
    if sig(back) != sig(m) && bad == "" {
      bad = "seed=" +
        seed.to_string() +
        "\n md=" +
        md +
        "\n 元=" +
        sig(m) +
        "\n 戻=" +
        sig(back)
    }
  }
  assert_eq(bad, "")
}

///|
test "書き戻した md はもう一度書いても動かない（法則 2 の生成側）" {
  let mut bad = ""
  for seed = 1; seed <= fuzz_seeds; seed = seed + 1 {
    let once = serialize(gen_ast(seed))
    let twice = serialize(parse(once))
    if once != twice && bad == "" {
      bad = "seed=" +
        seed.to_string() +
        "\n 1 回目=" +
        once +
        "\n 2 回目=" +
        twice
    }
  }
  assert_eq(bad, "")
}

///|
test "深さ 200 の一本鎖でも法則 1 が立つ" {
  // 木を再帰で書いた判断（§A-8 の ⑧）の見張り。`test/fixtures/deep.md` と同じ深さ。
  let m = chain_ast(200)
  assert_eq(sig(parse(serialize(m))), sig(m))
}
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core test -p mmm-app/core/doc
```
Expected: `Error: [4021]` / `The value identifier gen_ast is unbound.`（`law_wbtest.mbt` の 3 か所）。EXIT=1。

- [ ] **Step 3: 最小の実装を書く**

`law_wbtest.mbt` の `let fuzz_seeds` の直後（テスト群の前）に、生成器を書く。**implied には Left を割り当てない**（裁定 1・不変条件 11）。

```moonbit
///|
/// 決定的な擬似乱数（32bit LCG。Int は 32bit で巻き戻る）。
priv struct Rand {
  mut s : Int
}

///|
fn Rand::new(seed : Int) -> Rand {
  { s: if seed == 0 { 1 } else { seed } }
}

///|
/// 0 以上 n 未満。上位ビットだけを使い、符号は落とす。
fn Rand::pick(r : Rand, n : Int) -> Int {
  r.s = r.s * 1664525 + 1013904223
  ((r.s >> 8) & 0x7fffff) % n
}

///|
/// 生成の状態。id を文書順に振るための番号だけを持つ。
priv struct Gen {
  r : Rand
  mut next_id : Int
}

///|
/// ラベルの見本。**綴りを素通しする文字列だけ**を置く —
/// 前後の空白・改行・行頭の記号は serialize が書くと読みが変わるので、
/// 逃がし方が決まるまで生成しない。広げるときは
/// 「広げた瞬間に法則 1 が落ちる」ことを確かめてから逃がし方を足す。
///
/// **ここに前後空白・末尾 `#` を入れると法則 1 は必ず落ちる**
/// （serialize は逃がさず、`atx_at` が読み直しで trim するため）。
/// その形が要る日が来たら、逃がし方（`spell.mbt` の綴り）を決めてから
/// 広げること — 広げてから直すのではなく、広げた瞬間に落ちることを
/// 確かめてから足す。
/// なお **モデルにはその label を書けてしまう**（`Node.label` はただの String）。
/// v0 でそこへ辿り着く道が無いのは、parse が `atx_writable` で弾き、
/// T5 の `normalize` がラベルを一切触らないからである（rename は範囲外）。
/// つまりこの見本の狭さは「網の穴」ではなく、**入口が無いことの写し**である。
let labels : Array[String] = [
  "a", "b", "見出し", "with space", "記号 !$%", "https://example.com/x",
  "[md](https://e.com)", "タブ\tあり", "😀𝔘𝔫𝔦", "",
]

///|
/// 中身の見本。**parse し直すと同じ 1 つの Block に戻る形だけ**（§A-8 の ⑥）。
/// ラベル付き引数の呼び出しは `=`（`alt~=` は `Error: [3016]`。実測 4）。
fn sample_block(g : Gen) -> Block {
  match g.r.pick(9) {
    0 => Opaque("本文テキスト")
    1 => Opaque("段落の 1 行目\n2 行目")
    2 => Opaque("> 引用")
    3 => Opaque("| a | b |\n|---|---|\n| 1 | 2 |")
    4 => Rule
    5 => Content(Image(alt="図", src="./img/a.png"))
    6 => Content(Link(text="題", href="https://example.com/t"))
    7 =>
      Content(
        Svg("<svg xmlns=\"http://www.w3.org/2000/svg\"><circle r=\"5\"/></svg>"),
      )
    _ => Content(Code(info="ts", text="const x = `1`;"))
  }
}

///|
/// 側。**深さ 2 だけが意味を持つ**（不変条件 10）。
/// implied には決して呼ばない — implied は側を持てない（不変条件 11・裁定 1）。
fn side_for(g : Gen, depth : Int) -> Side {
  if depth == 2 && g.r.pick(2) == 0 {
    Left
  } else {
    Right
  }
}

///|
/// implied 1 つ。label・body・folded は空、子（すべて Heading）を必ず 1 つ以上持つ
/// （不変条件 5〜7・9）。子がまた implied になれば深い飛びの鎖になる。
/// **side は必ず Right**（不変条件 11。飛びには側を書く場所が無い）。
fn gen_implied(g : Gen, depth : Int, budget : Int) -> Node {
  let id = g.next_id
  g.next_id = g.next_id + 1
  let kids : Array[Node] = []
  if budget > 1 && depth < 5 && g.r.pick(3) == 0 {
    kids.push(gen_implied(g, depth + 1, budget - 1))
  } else {
    let n = 1 + g.r.pick(2)
    for i = 0; i < n; i = i + 1 {
      kids.push(gen_node(g, depth + 1, Heading, budget - 1))
    }
  }
  {
    id,
    form: Heading,
    label: "",
    implied: true,
    folded: false,
    side: Right,
    body: [],
    children: kids,
  }
}

///|
/// 子の列。単調性（Item の下は Item）と順序法則（Item が先・Heading が後）を
/// **生成側で満たす**ので、そもそも不正な木を作らない。
fn gen_children(
  g : Gen,
  depth : Int,
  self_form : Form,
  budget : Int,
) -> Array[Node] {
  let kids : Array[Node] = []
  if budget <= 0 || depth >= 6 {
    return kids
  }
  let n = g.r.pick(3)
  if n == 0 {
    return kids
  }
  if self_form is Item {
    // 単調性: Item の下はすべて Item。implied は Heading なので現れない
    for i = 0; i < n; i = i + 1 {
      kids.push(gen_node(g, depth + 1, Item, budget - 1))
    }
    return kids
  }
  if g.r.pick(5) == 0 {
    // 不変条件 8（裁定 B）: implied の前に見出しの兄弟が居てはいけない。
    // children の先頭に置けば必ず満たす。implied は Heading なので、
    // 順序法則により兄弟も全部 Heading になる（Item は先に来られない）
    kids.push(gen_implied(g, depth + 1, budget - 1))
    for i = 1; i < n; i = i + 1 {
      kids.push(gen_node(g, depth + 1, Heading, budget - 1))
    }
    return kids
  }
  let items = g.r.pick(n + 1) // 先頭 items 人が Item、残りが Heading
  for i = 0; i < n; i = i + 1 {
    let form = if i < items { Item } else { Heading }
    kids.push(gen_node(g, depth + 1, form, budget - 1))
  }
  kids
}

///|
/// ノード 1 つ（とその子）。id は文書順に振る。
fn gen_node(g : Gen, depth : Int, form : Form, budget : Int) -> Node {
  let id = g.next_id
  g.next_id = g.next_id + 1
  let label = labels[g.r.pick(labels.length())]
  let blocks : Array[Block] = []
  let bn = g.r.pick(3)
  for i = 0; i < bn; i = i + 1 {
    blocks.push(sample_block(g))
  }
  let kids = gen_children(g, depth, form, budget)
  {
    id,
    form,
    label,
    implied: false,
    folded: g.r.pick(4) == 0,
    side: side_for(g, depth),
    body: blocks,
    children: kids,
  }
}

///|
/// 種 1 つから木を 1 本。doc は深さ 0・id 1（不変条件 1・2）。
///
/// **裁定 E（文書頭の `---`）の回帰は、この生成器がすでに踏んでいる。**
/// `gen_children` が children の先頭に implied root を置く枝（`pick(5) == 0`）と、
/// その先頭スロットが左になる枝（`side_for` の `pick(2) == 0`）が重なり、
/// かつ head が無く doc.body が空のとき、serialize は文書の 1 行目に `---` を書く。
/// 生成器を逐語で写して数えた結果（この計画を書いた時点の実測）:
///   - 種 1〜300 … 先頭 `---` の木が **6 本**（seed 48・60・123・199・256・268）
///   - そのうちトグルをもう 1 本持つ木が **1 本**（**seed 199**）
///   - 種 1〜5000 … 先頭 `---` が 114 本、うちトグル 2 本以上が 34 本
/// `scan_head` に「開き `---` の直後が空行なら封筒ではない」の条件が無いと、
/// seed 199 で 1 本目から 2 本目までが head に飲まれ、
/// `sig(parse(serialize(m))) != sig(m)` になって法則 1 が落ちる。
/// **この覆いを痩せさせないこと** — 先頭 implied の枝と `side_for` の左を消すと、
/// 裁定 E の見張りが黙って消える。
fn gen_ast(seed : Int) -> Ast {
  let g = { r: Rand::new(seed), next_id: 2 }
  let blocks : Array[Block] = []
  if g.r.pick(3) == 0 {
    blocks.push(sample_block(g))
  }
  let kids = gen_children(g, 0, Heading, 6)
  let head = if g.r.pick(4) == 0 {
    Some("---\nimage-folder: img\n---")
  } else {
    None
  }
  let eol = if g.r.pick(4) == 0 { Crlf } else { Lf }
  let root : Node = {
    id: 1,
    form: Heading,
    label: "",
    implied: false,
    folded: false,
    side: Right,
    body: blocks,
    children: kids,
  }
  { head, eol, doc: root }
}
```

- [ ] **Step 4: 走らせる綴りを 1 行足して、通過を確認**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/package.json` の 13 行目（`"test:core"`）の**直後に 1 行**足す。`"test:core"` は触らない（旧 core は無変更の原則）。

```json
    "test:core": "cd core && moon test -p mmm-app/core",
    "test:doc": "moon -C core test -p mmm-app/core/doc",
```

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
pnpm -C D:/1.atrium/mmm/.claude/worktrees/doc-model run test:doc
```
Expected: `Total tests: B+4, passed: B+4, failed: 0.`（B = Step 1 で控えた本数）／EXIT=0。
落ちた場合（EXIT=2）は `bad` に seed・md・両側の指紋が丸ごと出るので、その逐語を担当へ渡す — 指紋が違えば T2（`build.mbt`）か T3（`serialize.mbt`）、`check` の違反なら生成器（このファイル）のバグ。
とくに `Item の下に Heading: <id>` が出たら、**疑うのは生成器ではなく T2 の `push_skel`** である（裁定 A。見出しを積む前に開いている項目を全部閉じているか）。生成器は Item の下に Heading を作らないので、この違反は必ず読み側から来る。
**`md=` が `---` で始まっていて、`戻=` の側だけ木が丸ごと消えている**（`head` に本文が飲まれ、指紋の木が痩せる）ときは、疑うのは生成器ではなく **T1 の `scan_head`** である（裁定 E。封筒の「中身の形」= **開き `---` の直後が空行なら封筒ではない**、の条件が抜けている）。seed 1〜300 でこの形を吐くのは **seed 199** だけなので、落ちるのも 1 件だけになる（`gen_ast` の doc コメントに実測を残してある）。
深掘りするときは `fuzz_seeds` の値（`let fuzz_seeds : Int = 300`）を 5000 などに書き換えて同じコマンドを回し、**終わったら 300 に戻す**。

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add core/doc/law_wbtest.mbt package.json
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "test: 🧪 木をばら撒いて、読み書きの往復を殴る"
```

---

## Task 34: 法則 2 — 実在コーパスとカタログ

**依存**: T1（Task 1〜9）・T2（Task 10〜17）・T3（Task 20〜26）の完了後に着手する。

**Files:**
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-law.test.ts`
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-law.test.ts`

**Interfaces:**
- Consumes: `format(md): string` / `check(md): string[]` / `sig(md): string` / `tree(md): DocTree`（Task 32 の `test/_doc.ts`）、`corpus()` / `brief(md, max)` / `reason(e)`（`test/_helpers.ts`）
- Produces: 法則 2 の言明（`format(format(md)) === format(md)`）とカタログ C1〜C17 の覆いの表 `CATALOG`。以後 T2/T3/T5 の固定テストはこの表の `owner` 欄を根拠に置き場所を決める

- [ ] **Step 1: 失敗するテストを書く**

`test/doc-law.test.ts` の `_helpers.ts` の import 行を更新する。

```ts
import { corpus, brief, reason } from "./_helpers.ts";
```

ファイル末尾に追記する。

```ts
// ---------------------------------------------------------------
// 法則 2: serialize(parse(md)) は冪等（2 回目から不動）。
// これが「フォーマット」の定義そのもの。旧 P1（バイト同一）の後継 —
// 仕様 §0 が綴りのバイト保全を手放したので `format(md) === md` は成り立たない。
// **移行で唯一意味が反転する箇所**。取り違えないこと。
// ---------------------------------------------------------------

test("法則 2: リポジトリ内の実 .md すべてで format が冪等", () => {
  const failures: string[] = [];
  for (const { path, md } of corpus()) {
    try {
      const once = format(md);
      const twice = format(once);
      if (once !== twice) {
        failures.push(
          `${path}: 2 回目で動いた\n    1回目=${brief(once, 160)}\n    2回目=${brief(twice, 160)}`,
        );
      }
    } catch (e) {
      failures.push(`${path}: 例外 ${reason(e)}`);
    }
  }
  assert.deepEqual(failures, [], `法則 2 が破れた:\n  ${failures.join("\n  ")}`);
});

test("不変条件: 実 .md を読んだ木も、正規形を読み直した木も健全", () => {
  const failures: string[] = [];
  for (const { path, md } of corpus()) {
    try {
      const a = check(md);
      if (a.length > 0) failures.push(`${path}: 原文 → ${a.join(" / ")}`);
      const b = check(format(md));
      if (b.length > 0) failures.push(`${path}: 正規形 → ${b.join(" / ")}`);
    } catch (e) {
      failures.push(`${path}: 例外 ${reason(e)}`);
    }
  }
  assert.deepEqual(failures, [], `不変条件の違反:\n  ${failures.join("\n  ")}`);
});

test("法則 2: 正規形をもう一度読んでも木が動かない", () => {
  // 冪等がバイトで立っていても、木が動いていたら意味を失っている。
  const failures: string[] = [];
  for (const { path, md } of corpus()) {
    const once = format(md);
    if (sig(once) !== sig(md)) {
      failures.push(
        `${path}: 整形で木が変わった\n    原文=${sig(md)}\n    正規=${sig(once)}`,
      );
    }
  }
  assert.deepEqual(failures, [], `整形が意味を変えた:\n  ${failures.join("\n  ")}`);
});

// ---------------------------------------------------------------
// カタログ C1〜C17 の覆い。
// **逐語で正規形を固定できるのは「操作なしで format が答えを与える」ケースだけ。**
// 操作を伴うケース（新 md が操作の結果であるもの）は担当が MoonBit 側に持つので、
// ここでは冪等と不変条件だけを見て、担当を表に残す（覆いが黙って抜けないため）。
// ---------------------------------------------------------------

const CATALOG: { id: string; md: string; want: string | null; owner: string }[] =
  [
    {
      id: "C1 add — 兄弟の真似",
      md: "# r\n\n## a\n\n- b\n- c\n",
      want: "# r\n\n## a\n\n- b\n- c\n",
      owner: "add は範囲外。ここでは元 md の綴りが正規形であることだけ固定",
    },
    {
      id: "C2 add — 親に従う",
      md: "# r\n\n## a\n",
      want: "# r\n\n## a\n",
      owner: "add は範囲外",
    },
    {
      id: "C3 delete — 側の列から区切りが再導出される",
      md: "# r\n\n## a\n\n---\n\n## b\n\n---\n\n## c\n",
      want: "# r\n\n## a\n\n---\n\n## b\n\n---\n\n## c\n",
      owner: "delete 後の新 md は T5 Task 45 の delete_wbtest.mbt",
    },
    {
      id: "C4 flipSide — 先頭トグル",
      md: "# r\n\n## a\n\n## b\n",
      want: "# r\n\n## a\n\n## b\n",
      owner: "flip 後の新 md は T5 Task 46 の side_wbtest.mbt",
    },
    {
      id: "C5 move — 散文は中身ごと運ばれる",
      md: "# r\n\n## head\n\ncontent01\n\n***\n\ncontent02\n\n## head2\n",
      want: "# r\n\n## head\n\ncontent01\n\n***\n\ncontent02\n\n## head2\n",
      owner: "move 後の新 md は T5 Task 47 の move_wbtest.mbt",
    },
    {
      id: "C6 階層飛びは正規形でも残る",
      md: "# r\n\n## a\n\n#### b\n",
      want: "# r\n\n## a\n\n#### b\n",
      owner: "飛びからの implied 導出は T2 Task 13 の build_wbtest.mbt",
    },
    {
      id: "C7 飾りの水平線は `***` に書かれる",
      md: "# r\n\n## a\n\ntext\n\n---\n\nmore\n\n## b\n",
      want: "# r\n\n## a\n\ntext\n\n***\n\nmore\n\n## b\n",
      owner:
        "手書きの --- が残るのは すげ替え v1（後日箱 X06）。v0 では *** に正規化されるのが正しい",
    },
    {
      id: "C8 fold — details のネスト",
      md: "# r\n\n## a\n\n### b\n\n<details>\n\n#### c\n\n</details>\n",
      want: null,
      owner:
        "畳みの帰属（骨格行の外）は T2 Task 16 の build_wbtest.mbt と T3 Task 25 の serialize_wbtest.mbt",
    },
    {
      id: "C9 format — 明示の全文正規化",
      md: "# r\n\na\n---\n\n##   b   ##\n\n    code\n",
      want: "# r\n\n## a\n\n## b\n\n```\ncode\n```\n",
      owner: "setext → ATX・閉じ `#` の除去・インデントコード → フェンス（T3 Task 22）",
    },
    {
      id: "C10 task list はラベルの一部",
      md: "# r\n\n- [x] done\n- [ ] todo\n",
      want: "# r\n\n- [x] done\n- [ ] todo\n",
      owner: "—",
    },
    {
      id: "C11 frontmatter は封筒のまま",
      md: "---\nimage-folder: img\n---\n\n# r\n\n## a\n",
      want: "---\nimage-folder: img\n---\n\n# r\n\n## a\n",
      owner: "封筒の切り出しは T1 Task 7 の scan_wbtest.mbt",
    },
    {
      id: "C12 打鍵の道",
      md: "# r\n\n## a\n\n## b\n",
      want: "# r\n\n## a\n\n## b\n",
      owner: "id の継ぎ目は UI 接続の話で範囲外",
    },
    {
      id: "C13 読みの道 — 文字列は md",
      md: "# r\n\n## 1. x\n\ny\n",
      want: "# r\n\n## 1. x\n\ny\n",
      owner: "rename は範囲外。ここでは rename の結果 md が正規形であることを固定",
    },
    {
      id: "C14 form は行き先に従う",
      md: "# r\n\n## a\n\n- x\n\n## b\n",
      want: "# r\n\n## a\n\n- x\n\n## b\n",
      owner: "move 後の Heading 化は T5 Task 47 の move_wbtest.mbt",
    },
    {
      id: "C15 Item root と content indent のトグル",
      md: "- center\n\n  - a\n\n  - b\n\n  ---\n\n  - c\n",
      want: null,
      owner: "tight 化の綴りは T3 Task 24、読みは T2 Task 15。ここでは側の割り当てだけ見る",
    },
    {
      id: "C16 implied スロットへの flipSide は昇格させてから反転する",
      md: "# r\n\n#### b\n",
      want: "# r\n\n#### b\n",
      owner:
        "flip の結果（`## ` が生えて左になる）は T5 Task 46 の side_wbtest.mbt。裁定 1・不変条件 11",
    },
    {
      id: "C17 項目 root の後ろの見出しは木 2 本になる",
      md: "- a\n\n## h\n",
      want: "- a\n\n## h\n",
      owner:
        "裁定 A。md では見出しがリストを終わらせるので、h は a の子にならず implied root の下へ落ちる（`[H[Ia][H~[Hh]]]`）。読みの固定は T2 Task 13 の build_wbtest.mbt。implied が先頭でなくても綴れるのは裁定 B（不変条件 8 =「implied の前に見出しが居ない」）",
    },
  ];

test("カタログ: 逐語で固定できる正規形が期待どおり", () => {
  const failures: string[] = [];
  for (const c of CATALOG) {
    if (c.want === null) continue;
    const got = format(c.md);
    if (got !== c.want) {
      failures.push(
        `${c.id}\n    期待=${brief(c.want, 200)}\n    実際=${brief(got, 200)}`,
      );
    }
  }
  assert.deepEqual(
    failures,
    [],
    `カタログの正規形が違う:\n  ${failures.join("\n  ")}`,
  );
});

test("カタログ: 全 17 件で法則 2 と不変条件が立つ", () => {
  const failures: string[] = [];
  for (const c of CATALOG) {
    const once = format(c.md);
    if (format(once) !== once) {
      failures.push(`${c.id}: 冪等でない（担当: ${c.owner}）`);
    }
    const v = check(c.md);
    if (v.length > 0) {
      failures.push(`${c.id}: ${v.join(" / ")}（担当: ${c.owner}）`);
    }
  }
  assert.deepEqual(
    failures,
    [],
    `カタログが法則を破った:\n  ${failures.join("\n  ")}`,
  );
});

test("カタログ C15: root の content indent の `---` は side トグル", () => {
  // より深い位置の `---` は子の body の飾り。ここが分かれることが C15 の主題。
  const t = tree("- center\n\n  - a\n\n  - b\n\n  ---\n\n  - c\n");
  const roots = t.doc.children;
  assert.equal(roots.length, 1, "top-level の Item は深さ 1 の root 1 本");
  assert.deepEqual(
    roots[0].children.map((n) => [n.label, n.side]),
    [
      ["a", "R"],
      ["b", "R"],
      ["c", "L"],
    ],
  );
});
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
node --test D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-law.test.ts
```
Expected: T1〜T3 の読み書きに穴が残っていれば、`✖ 法則 2: リポジトリ内の実 .md すべてで format が冪等` にコーパスの path が並び、`✖ カタログ: 逐語で固定できる正規形が期待どおり` に C9 などの `期待=` / `実際=` が並ぶ。`ℹ fail N` / EXIT=1。
すべて揃っていれば `ℹ tests 12` / `ℹ pass 12` / `ℹ fail 0` になる（そのときは Step 3 を飛ばして Step 4 へ）。

- [ ] **Step 3: 落ちた行を最小差分に絞って担当へ渡す**

失敗メッセージの `path` / `期待` / `実際` を**逐語で写して**担当へ渡す。振り分けは 2 つだけ:

| 症状 | 担当 |
|---|---|
| 骨格・implied・側・畳みの読みが違う（`sig` が原文と正規形で食い違う／`check` が違反を出す） | T2（`core/doc/block.mbt` / `core/doc/build.mbt`） |
| 読みは合っていて綴りが違う（`format` の出力が `want` と違う／2 回目で動く） | T3（`core/doc/serialize.mbt`） |

**このタスクは実装を書かないが、「どこを直すか」までは絞って渡す。**落ち方は 2 種類しかないので、それぞれ突き合わせる先を逐語で置く。

**① 冪等が破れた（`2 回目で動いた`）とき — `serialize.mbt` の `feed` の判定表と突き合わせる。**空行の本数だけが 2 回目で動くのが冪等の破れの正体なので、次の表と実装が食い違っている行を特定して T3 へ渡す（表は T3 Task 26 Step 3 (a) の逐語）:

```moonbit
///|
/// 単位を書く直前に呼ぶ。前後どちらかが空行を求めていれば 1 本だけ挟む。
fn feed(o : Out, before : Bool) -> Unit {
  if o.lines.length() > 0 && (o.gap || before) {
    o.lines.push("")
  }
}
```

| 単位 | `feed` の `before` | 書いた後の `o.gap` |
|---|---|---|
| 見出しの骨格行 | `true` | `true` |
| 項目の骨格行 | `false` | `false` |
| `Rule` / `Opaque` / `Svg` / `Image` / `Link` | `true` | `true` |
| コード（`write_code`） | `false` | `false` |
| トグル / `<details>` / `</details>` | `true` | `true` |

渡す言葉は「`<path>` で `<単位>` の前後の空行が表と食い違う。`before` / `o.gap` のどちらが表と違うかを見てほしい」。**表のほうを実装に合わせて緩めない。**

**② `整形が意味を変えた`（`sig(format(md)) != sig(md)`）とき — `build.mbt` の区切りの帰属を疑う。**この差は「`---` がスロットの変わり目になるか、中身の飾りになるか」でしか起きない。判断はこの 2 関数だけが持つ（T2 Task 14 Step 3 (e) の逐語）:

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

渡す言葉は「`<path>` の `---` が `<スロット/飾り>` に倒れた。`next_is_slot` の深さ 2 判定と `in_deep_item` の領土判定のどちらが曲がったか特定してほしい」。`Item の下に Heading: <id>` が出た場合だけは別で、**`push_skel` が見出しを積む前に開いている項目を閉じているか**を見る（裁定 A。カタログ C17 が同じ形を持っているので、C17 も一緒に落ちているはず）。

**表の期待値を緩めるのは、表のほうが古いと確かめられたときだけである。**その場合の書き替え手順（例として C9 を挙げる。実際に直す行に読み替える）:

1. 仕様（`docs/superpowers/specs/2026-08-29-doc-model-design.md` の §4 と §A-7 の綴り規則）を読み、実際の出力のほうが規則に従っていることを確かめる
2. その行の `want` を実際の出力に差し替え、**`owner` に「なぜその綴りが正しいか」の根拠（規則の番号）を書き足す**。表は実装の写しではなく「なぜその形を選んだか」の記録である

差し替えの具体形（`want` と `owner` の 2 か所だけを触る。`id` と `md` は動かさない）:

```ts
    {
      id: "C9 format — 明示の全文正規化",
      md: "# r\n\na\n---\n\n##   b   ##\n\n    code\n",
      want: "# r\n\n## a\n\n## b\n\n```\ncode\n```\n",
      owner:
        "setext → ATX・閉じ `#` の除去・インデントコード → フェンス（T3 Task 22）。§A-7 規則 3・8",
    },
```

3. 書き替えたら、その行を**担当にも通知する**（T3 の `serialize_wbtest.mbt` に同じ期待値の固定テストが居る場合、片方だけ直すと両者が黙って食い違う）

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
node --test D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-law.test.ts
```
Expected: `ℹ tests 12` / `ℹ pass 12` / `ℹ fail 0` / EXIT=0（Task 30 の 3 本 + Task 32 の 3 本 + 本タスクの 6 本）

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add test/doc-law.test.ts
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "test: 🧪 実在の md とカタログ全件で、整形が動かないことを確かめる"
```

---

## Task 35: 病的な md のランダム生成器

**Files:**
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/test/_doc.ts`（`atxWritable` / `LABELS` / `SETEXT_LABELS` / `BLOCKS` / `randomMd` を追記）
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-law.test.ts`
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-law.test.ts`

**Interfaces:**
- Consumes: `rng(seed): () => number` / `brief(md, max)` / `reason(e)`（`test/_helpers.ts`。**写経せず import**）。**`fuzzCases` は使わない**（裁定 6。回数は定数 `RANDOM_CASES` で切り替える）
- Produces: `randomMd(seed: number): string`（`test/_doc.ts`）。Task 36 の方言テストと Task 37 の縮小器、T5 Task 48 の操作ファズがこれを入力に使う。あわせて **`atxWritable(s: string): boolean` を export する**（Task 36 の番人が同じ規則で入力を絞る。写しを 3 つに増やさないため）。**表に無い export なので、着手前に正誤表 §D-3 の表へ 1 行足すこと**（`LABELS` / `SETEXT_LABELS` / `BLOCKS` は生成器の内側のまま export しない）

- [ ] **Step 1: 失敗するテストを書く**

`test/doc-law.test.ts` の import 2 行を更新する。

```ts
import { corpus, brief, reason } from "./_helpers.ts";
import {
  format,
  check,
  sig,
  tree,
  flatten,
  skeleton,
  blocksOf,
  randomMd,
} from "./_doc.ts";
```

ファイル末尾に追記する。

```ts
// ---------------------------------------------------------------
// ランダム生成の md（text-first）。既存 randomDoc は見出しと `---` に偏り、
// 新モデルの語彙（リスト・字下げ・details・setext・飛び）をほとんど踏まない。
// 木を組んでから serialize する model-first の生成は MoonBit 側
// （`core/doc/law_wbtest.mbt` の `gen_ast`）が持つ。あちらが法則 1、こちらが法則 2。
// ---------------------------------------------------------------

// 深掘りするときはこの数を上げ、終わったら 600 に戻す（裁定 6 —
// 環境変数の前置きは PowerShell で構文エラーになるので使わない）。
const RANDOM_CASES = 600;

test("法則 2: ランダム生成の md で format が冪等", () => {
  const failures: string[] = [];
  for (let seed = 1; seed <= RANDOM_CASES && failures.length < 6; seed++) {
    const md = randomMd(seed);
    try {
      const once = format(md);
      const twice = format(once);
      if (once !== twice) {
        failures.push(
          `seed=${seed}\n    入力=${brief(md, 200)}\n    1回目=${brief(once, 200)}\n    2回目=${brief(twice, 200)}`,
        );
      }
    } catch (e) {
      failures.push(`seed=${seed}: 例外 ${reason(e)}\n    入力=${brief(md, 200)}`);
    }
  }
  assert.deepEqual(failures, [], `法則 2 が破れた:\n  ${failures.join("\n  ")}`);
});

test("不変条件: ランダム生成の md を読んだ木が常に健全", () => {
  const failures: string[] = [];
  for (let seed = 1; seed <= RANDOM_CASES && failures.length < 6; seed++) {
    const md = randomMd(seed);
    const v = check(md);
    if (v.length > 0) {
      failures.push(`seed=${seed}: ${v.join(" / ")}\n    入力=${brief(md, 200)}`);
    }
  }
  assert.deepEqual(
    failures,
    [],
    `parse が不正な木を作った:\n  ${failures.join("\n  ")}`,
  );
});

test("ランダム生成の md でも、整形は意味を変えない", () => {
  const failures: string[] = [];
  for (let seed = 1; seed <= RANDOM_CASES && failures.length < 6; seed++) {
    const md = randomMd(seed);
    if (sig(format(md)) !== sig(md)) {
      failures.push(
        `seed=${seed}\n    原文=${sig(md)}\n    正規=${sig(format(md))}\n    入力=${brief(md, 200)}`,
      );
    }
  }
  assert.deepEqual(failures, [], `整形が意味を変えた:\n  ${failures.join("\n  ")}`);
});

test("生成器は決定的で、狙った軸を実際に踏んでいる", () => {
  // 生成器が痩せたまま「全部通る」になるのを防ぐ自己検査。
  assert.equal(randomMd(7), randomMd(7));
  const all = Array.from({ length: 400 }, (_, i) => randomMd(i + 1)).join("\n");
  const axes: [string, RegExp][] = [
    ["frontmatter", /^---\r?\nimage-folder/m],
    ["7 個以上の見出し", /^#{7,} /m],
    ["setext", /^\S.*\r?\n(===|---)$/m],
    ["リストのマーカー混在", /^\s*[*+] /m],
    ["順序リスト", /^\s*\d[.)] /m],
    ["ネスト字下げ", /^ {2,}[-*+] /m],
    ["details", /<details>/],
    ["details の閉じ", /<\/details>/],
    ["飾りの水平線", /^(\*\*\*|___|- - -)$/m],
    ["インデントコード", /^ {4}\S/m],
    ["フェンス（言語付き）", /^```ts$/m],
    ["入れ子っぽいフェンス", /^````$/m],
    ["CRLF", /\r\n/],
    ["サロゲートペア", /\u{1F600}/u],
    ["閉じシーケンス", /^#{1,6} .* #+$/m],
    ["飾り字下げ", /^ {1,3}#{1,6} /m],
  ];
  const missing = axes.filter(([, re]) => !re.test(all)).map(([name]) => name);
  assert.deepEqual(missing, [], `生成器が踏んでいない軸: ${missing.join(", ")}`);
});
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
node --test D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-law.test.ts
```
Expected: `SyntaxError: The requested module './_doc.ts' does not provide an export named 'randomMd'` でファイルごと落ちる。EXIT=1。

- [ ] **Step 3: 最小の実装を書く**

`test/_doc.ts` の `_helpers.ts` の import 行に `rng` を足す。

```ts
import { REPO, rng } from "./_helpers.ts";
```

ファイル末尾に追記する。

```ts
// ---------------------------------------------------------------
// 生成
// ---------------------------------------------------------------

/**
 * ATX の骨格行として書き戻せる文字列か
 * （`core/doc/scan.mbt` の `atx_writable`（T1 Task 9）と同じ規則）。
 *
 * 前後に空白がある行は再読みの `trim_range` で消え、末尾が `#` の連なり
 * （直前が空白）だと閉じシーケンスとして落ちる。どちらも label が変わるので、
 * scan はそういう行に setext の下線が付いても見出しにしない。
 * **生成器も同じ条件を守る** — 弾かれる形に下線を付けても setext の軸を
 * 踏んだことにならず、「踏んだつもりの穴」だけが残るからである。
 *
 * **export するのは Task 36 の法則 4 の番人が同じ規則で入力を絞るため。**
 * 審判（lezer）は `  a  ` + `---` を素直に setext 見出しと読むので、この条件を
 * 番人にも渡さないと、正しい実装のまま赤になる。写しは MoonBit の
 * `atx_writable` とこの 1 つだけに留める（3 つ目を作らない）。
 */
export function atxWritable(s: string): boolean {
  if (s.length === 0) return false;
  if (/^\s/.test(s) || /\s$/.test(s)) return false;
  const e = s.replace(/#+$/, "");
  return e !== "" && !/\s$/.test(e);
}

const LABELS = [
  "a", "b", "見出し", "with space", "  leading", "trailing  ",
  "記号 #!$%", "https://example.com/x", "[md](https://e.com)", "###",
  "very ".repeat(12) + "long", "タブ\tあり", "", "-", "--",
  "😀𝔘𝔫𝔦", "🇯🇵 旗", "[x] done", "1. 番号に見える",
];

/** setext の下線を付けてよいラベルだけ（`  leading` / `trailing  ` / `###` / `` が落ちる）。 */
const SETEXT_LABELS = LABELS.filter(atxWritable);

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
 *
 * 踏む軸: 見出しの飛びと 7 個以上・閉じシーケンス・飾り字下げ /
 * リストのマーカー混在と字下げ揺れとネスト / form の混在 /
 * 区切り（トグルの位置にも飾りの位置にも落ちる）/ details のネストと未閉じ /
 * frontmatter / setext / インデントコード / フェンス（言語付き・入れ子っぽい）/
 * CRLF / 末尾改行の有無 / 空行の連続 / 非 ASCII とサロゲートペア。
 * `- - -` は **飾りの水平線**として撒く（裁定 2。旧 core の箇条書き方言は捨てた）。
 *
 * 木を組んでから serialize する model-first の生成は MoonBit 側
 * （`core/doc/law_wbtest.mbt` の `gen_ast`）が持つ。あちらが法則 1、こちらが法則 2。
 */
export function randomMd(seed: number): string {
  const rand = rng(seed);
  const pick = <T,>(a: T[]): T => a[Math.floor(rand() * a.length)];
  const nl = rand() < 0.25 ? "\r\n" : "\n";
  const out: string[] = [];
  const blank = (): void => {
    out.push("");
    if (rand() < 0.15) out.push("");
  };

  if (rand() < 0.2) {
    out.push("---", "image-folder: img", "key: [1, 2]", "---", "");
  }
  if (rand() < 0.15) out.push("---", ""); // 先頭トグル（左開始）

  let listDepth = 0; // 0 = リストの外
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
        rand() < 0.12 && headLevel <= 6
          ? " " + "#".repeat(1 + Math.floor(rand() * 3))
          : "";
      out.push(
        `${lead}${"#".repeat(headLevel)} ${pick(LABELS)}${close}`.trimEnd(),
      );
      listDepth = 0;
      blank();
      continue;
    }
    if (r < 0.65) {
      // 下線を付けるのは ATX で書き戻せるラベルだけ（`atxWritable`）。
      // 前後空白・末尾 `#` の行は scan が段落のまま残すので setext にならない。
      out.push(pick(SETEXT_LABELS), rand() < 0.5 ? "===" : "---");
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
      if (rand() < 0.8) out.push("</details>", ""); // 未閉じ・単独閉じの両方が出る
      continue;
    }
    out.push(pick(BLOCKS));
    blank();
  }
  let text = out.join(nl);
  if (rand() < 0.25) text = text.replace(/[\r\n]+$/, ""); // 末尾改行なし
  return text;
}
```

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
node --test D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-law.test.ts
pnpm -C D:/1.atrium/mmm/.claude/worktrees/doc-model run check
```
Expected: `ℹ tests 16` / `ℹ pass 16` / `ℹ fail 0` / EXIT=0（Task 34 の 12 本 + 本タスクの 4 本）。`pnpm run check` も EXIT=0。

`Item の下に Heading: <id>` が並んで落ちたときは T4 ではなく **T2 の `push_skel`（裁定 A）**を見る。生成器は `1. a` → 空行 → `## a` の形（seed 1〜600 のうち 14 seed。最小は seed 85）を吐くので、見出しを積む前に開いている項目を閉じていないと必ずここで捕まる。**期待どおりの木は「項目 a」と「implied root の下の a」の 2 本**であり、生成器を痩せさせて避けてはならない（実 .md コーパスにこの形が無いので、Task 34 は緑のまま通ってしまう）。

深掘り（時間だけ伸び、結果は同じであること）: `test/doc-law.test.ts` の `const RANDOM_CASES = 600;` を `5000` に書き替えて同じコマンドを回し、**終わったら 600 に戻す**（環境変数の前置きは使わない — 裁定 6）。

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add test/_doc.ts test/doc-law.test.ts
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "test: 🧪 新しい語彙を踏む md をばら撒いて、整形の不動点を殴る"
```

---

## Task 36: 法則 4 — 方言表と外部審判

**Files:**
- Create: `D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-dialect.test.ts`
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-dialect.test.ts`

**Interfaces:**
- Consumes: `parser` from `@lezer/markdown`（1.7.2。**既定は素の CommonMark**。`configure(Table)` は入れない）、`skeleton(md)` / `blocksOf(md)` / `randomMd(seed)` / **`atxWritable(s)`**（`test/_doc.ts`。Task 35 で export したもの。**写経しない**）、`corpus()` / `brief()`（`test/_helpers.ts`）。**`fuzzCases` は使わない**（裁定 6。回数は定数 `DIALECT_CASES`）
- Produces: 方言表 `DIALECT`（逐語のテーブル 18 行。lezer と**意図的に**食い違う点の一覧）と、その外側で差分が出たら落ちる番人

- [ ] **Step 1: 失敗するテストを書く**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-dialect.test.ts` を新規作成する。`lezer` 欄はすべて **@lezer/markdown 1.7.2 の実測値**である。

```ts
// 法則 4: parse の骨格判定 = @lezer/markdown のブロック木 + 方言表。
//
// lezer は**パイプラインの段ではなく外部の審判**。アダプタは作らない。
// 期待出力を手で書くのは、この方言表のテーブルだけ。
// **表に無い差分が出たらテストが落ちる** — これが唯一の運用。

import test from "node:test";
import assert from "node:assert/strict";
import { parser } from "@lezer/markdown";
import { corpus, brief } from "./_helpers.ts";
import { skeleton, blocksOf, randomMd, atxWritable } from "./_doc.ts";

// 深掘りするときはこの数を上げ、終わったら 300 に戻す（裁定 6 —
// 環境変数の前置きは PowerShell で構文エラーになるので使わない）。
const DIALECT_CASES = 300;

/** 見出し行から中身だけを取る（閉じシーケンスと前後の空白を落とす）。 */
function headingText(src: string): string {
  const first = src.split(/\r?\n/)[0];
  const atx = /^\s{0,3}#{1,6}\s*(.*?)\s*#*\s*$/.exec(first);
  return atx === null ? first.trim() : atx[1];
}

/**
 * lezer が「文書の直下」で見つけた見出しを、文書順にテキストで返す。
 * 項目・引用・フェンスの中の見出しは、祖先に Document 以外が居るので落ちる
 * （＝ mmm が Opaque と読む領域と、審判の側でも一致する）。
 *
 * **複数行の段落に付いた setext の下線は方言表が持つ**（mmm は最終行だけを
 * 見出しにする）ので、法則 4 の番人はこの形を `withoutMultilineSetext` で
 * 入力から外してからここへ渡す。
 */
function lezerTopHeadings(md: string): string[] {
  const tree = parser.parse(md);
  const out: string[] = [];
  const stack: string[] = [];
  tree.iterate({
    enter: (n) => {
      const nested = stack.some((s) => s !== "Document");
      if (!nested && /^(ATXHeading[1-6]|SetextHeading[12])$/.test(n.name)) {
        out.push(headingText(md.slice(n.from, n.to)));
      }
      stack.push(n.name);
      return true;
    },
    leave: () => {
      stack.pop();
    },
  });
  return out;
}

/**
 * 封筒（frontmatter）を落とす。
 * mmm は文書頭の `---` … `---` を封筒として切り出し、中を一切解釈しない（R109）。
 * 素の CommonMark にその概念は無く、`---` / `k: v` / `---` を
 * 「水平線 + setext 見出し」と読む（実測: lezer は `k: v` を SetextHeading2 と読む）。
 * 審判に同じ本文を見せるため、法則 4 の番人だけはここで封筒を外す。
 * **方言表の frontmatter の行は生の md のまま**当てる（食い違いそのものが主題なので）。
 */
function withoutHead(md: string): string {
  const lines = md.split(/\r?\n/);
  if (lines.length === 0 || lines[0].trim() !== "---") return md;
  for (let i = 1; i < lines.length; i++) {
    if (lines[i].trim() === "---") {
      return lines.slice(i + 1).join("\n");
    }
  }
  return md;
}

/** その行が段落ではなく別のブロックを始めるか（後ろ向きの段落走査を止める印）。 */
function startsBlock(line: string): boolean {
  return /^ {0,3}(#{1,6}[ \t]|>|[-*+][ \t]|\d{1,9}[.)][ \t]|```|~~~|<)/.test(
    line,
  );
}

/**
 * 「2 行以上の段落 + setext の下線」の形を、段落ごと空行に置き換えて落とす。
 *
 * mmm の label は 1 行の文字列なので、段落の**最終行だけ**が見出しになり
 * 残りは Opaque に落ちる（方言表「複数行の段落の setext は最終行だけが見出しになる」）。
 * 審判は段落全体を 1 つの見出しと読むため、この形を番人に掛けると必ず食い違う。
 * 意図的な差分は方言表が 1 行で持っているので、番人の入力からは丸ごと外す。
 * 落とすのは審判に見せる側だけなので、mmm の骨格が減ることはない。
 */
function withoutMultilineSetext(md: string): string {
  const lines = md.split(/\r?\n/);
  const out: string[] = [];
  for (const line of lines) {
    if (!/^ {0,3}(=+|-+)[ \t]*$/.test(line)) {
      out.push(line);
      continue;
    }
    let n = 0;
    while (n < out.length) {
      const prev = out[out.length - 1 - n];
      if (prev.trim() === "") break;
      n++;
      if (startsBlock(prev)) break;
    }
    const top = n === 0 ? "" : out[out.length - n];
    if (n < 2 || startsBlock(top)) {
      out.push(line);
      continue;
    }
    out.length -= n;
    out.push("");
  }
  return out.join("\n");
}

/**
 * 「ATX で書き戻せない 1 行 + setext の下線」の形を、その行ごと落とす。
 *
 * mmm は前後に空白がある行・末尾が空白 + `#` の行を setext と認めない
 * （T1 Task 9 の `atx_writable`。裁定 D）が、審判はそれを素直に
 * SetextHeading と読む。意図的な差分は方言表の
 * 「ATX で書き戻せない行は setext にしない」の行が 1 行で持っているので、
 * 番人の入力からは外す。**`withoutMultilineSetext` の後に掛ける**
 * （2 行以上の段落はあちらが先に落とすので、ここへは 1 行の段落だけが来る）。
 * 判定は `test/_doc.ts` の `atxWritable` を import して使う — 規則の写しを
 * MoonBit とこの 1 つより増やさない。
 */
function withoutUnwritableSetext(md: string): string {
  const lines = md.split(/\r?\n/);
  const out: string[] = [];
  for (const line of lines) {
    const prev = out.length === 0 ? "" : out[out.length - 1];
    if (
      /^ {0,3}(=+|-+)[ \t]*$/.test(line) &&
      prev.trim() !== "" &&
      !startsBlock(prev) &&
      !atxWritable(prev)
    ) {
      out.length -= 1;
      out.push("");
      continue;
    }
    out.push(line);
  }
  return out.join("\n");
}

/** a が b の部分列か（順序を保った包含）。 */
function isSubsequence(a: string[], b: string[]): boolean {
  let i = 0;
  for (const x of b) {
    if (i < a.length && a[i] === x) i++;
  }
  return i === a.length;
}

// ---------------------------------------------------------------
// 方言表 — lezer と食い違う点、および食い違わないと決めた点の一覧。
// `same` は「審判と同じ読み」の宣言。`diff` の行だけが意図的な差分。
// `lezer` 欄は @lezer/markdown 1.7.2 の実測値。
// ---------------------------------------------------------------

const DIALECT: {
  id: string;
  md: string;
  nodes: string[]; // mmm の骨格（implied を除く。`<form>:<label>`）
  blocks: string[]; // mmm の中身のかたまり（文書順）
  lezer: string[]; // lezer が文書直下で見つけた見出し
  verdict: "same" | "diff";
  why: string;
}[] = [
  {
    id: "`#######`（7 個以上）は見出し",
    md: "####### x\n",
    nodes: ["H:x"],
    blocks: [],
    lezer: [],
    verdict: "diff",
    why: "lezer は Paragraph と読む。level 無制限は §4 の裁定で、GitHub で段落になる対価は受け入れる",
  },
  {
    id: "setext は読む",
    md: "a\n===\n",
    nodes: ["H:a"],
    blocks: [],
    lezer: ["a"],
    verdict: "same",
    why: "lezer も SetextHeading1 と読む。書きは常に ATX（C9）",
  },
  {
    id: "複数行の段落の setext は最終行だけが見出しになる",
    md: "one\ntwo\n---\n",
    nodes: ["H:two"],
    blocks: ["o:one"],
    lezer: ["one"],
    verdict: "diff",
    why: "label は 1 行の文字列なので段落全体を中身にできない。mmm は最終行 two を昇格させ、残りの one は Opaque で残す（R001 のとおり意味は失われない）。書きは常に ATX（C9）なので法則 1・2 も立つ。CommonMark／lezer は段落全体を見出しの中身にするため見出しテキストが one になる — 法則 4 の番人はこの形を `withoutMultilineSetext` で入力から外す",
  },
  {
    id: "ATX で書き戻せない行は setext にしない",
    md: "# r\n\n  a  \n---\n",
    nodes: ["H:r"],
    blocks: ["o:  a  ", "rule"],
    lezer: ["r", "a"],
    verdict: "diff",
    why: "前後に空白がある行・末尾が空白 + `#` の行を setext と認めると、serialize が `##   a  ` を書き、読み直しで `atx_at` の trim と閉じシーケンス落としが label を変える（法則 1・2 が同時に破れる）。よって段落のまま残す（T1 Task 9 の `atx_writable`。裁定 D）。法則 4 の番人はこの形を `withoutUnwritableSetext` で入力から外す",
  },
  {
    id: "`<!---` / `--->` を許容する",
    md: "# r\n\n<!--- memo --->\n",
    nodes: ["H:r"],
    blocks: ["o:<!--- memo --->"],
    lezer: ["r"],
    verdict: "same",
    why: "コメントは Opaque。旧 `<!--` 包みの畳みには対応しない",
  },
  {
    id: "項目内の見出しは Opaque",
    md: "- a\n\n  # inner\n",
    nodes: ["I:a"],
    blocks: ["o:# inner"],
    lezer: [],
    verdict: "same",
    why: "絶対記法を相対容器に入れると level が嘘になる（単調性）。lezer 側も ListItem の中なので落ちる",
  },
  {
    id: "blockquote は Opaque",
    md: "> # inner\n",
    nodes: [],
    blocks: ["o:> # inner"],
    lezer: [],
    verdict: "same",
    why: "引用は中身ごと逐語",
  },
  {
    id: "table は Opaque",
    md: "| a | b |\n|---|---|\n| 1 | 2 |\n",
    nodes: [],
    blocks: ["o:| a | b |\n|---|---|\n| 1 | 2 |"],
    lezer: [],
    verdict: "same",
    why: "既定の lezer は table 拡張を持たず Paragraph と読むが、どちらも骨格を作らないので審判の対象外。`configure(Table)` は入れない",
  },
  {
    id: "一般 HTML は Opaque",
    md: "<div>x</div>\n",
    nodes: [],
    blocks: ["o:<div>x</div>"],
    lezer: [],
    verdict: "same",
    why: "HTMLBlock は逐語。**この `blocks` 欄は TS の `blockSig`（逃がさない）の綴りである** — MoonBit の `block_sig` は `<` を逃がすので `o:\\<div>x</div>` になる。両者を写し合わないこと",
  },
  {
    id: "リストマーカー `*` `+` は読みのみ",
    md: "* a\n+ b\n",
    nodes: ["I:a", "I:b"],
    blocks: [],
    lezer: [],
    verdict: "same",
    why: "書きは `-` に正規化（§4）。lezer も ListItem として読む",
  },
  {
    id: "順序リストは構造として読む",
    md: "1. a\n2) b\n",
    nodes: ["I:a", "I:b"],
    blocks: [],
    lezer: [],
    verdict: "same",
    why: "兄弟の順序は構造として完全保存。番号の見た目は綴りとして失われる",
  },
  {
    id: "行頭の飾り字下げ（0〜3）は読み飛ばす",
    md: "   ## x\n",
    nodes: ["H:x"],
    blocks: [],
    lezer: ["x"],
    verdict: "same",
    why: "書かない。lezer も 3 個までは見出しと読む",
  },
  {
    id: "閉じシーケンス `## b ##` は落とす",
    md: "##   b   ##\n",
    nodes: ["H:b"],
    blocks: [],
    lezer: ["b"],
    verdict: "same",
    why: "CommonMark どおり。書きは `## b`（C9）",
  },
  {
    id: "インデントコードは読める",
    md: "# r\n\n    code\n",
    nodes: ["H:r"],
    blocks: ["code:|code"],
    lezer: ["r"],
    verdict: "same",
    why: "書きは常にフェンス（C9）。lezer も CodeBlock と読む",
  },
  {
    id: "`- - -` は飾りの水平線（旧 core の「前から箇条書き」方言は捨てた）",
    md: "# r\n\n- - -\n",
    nodes: ["H:r"],
    blocks: ["rule"],
    lezer: ["r"],
    verdict: "same",
    why: "CommonMark の thematic break。裁定 2。トグルは空白を 1 つも含まない `---` だけ（`Break(true)`）で、`- - -` は常に `Break(false)` = 飾り。T1 Task 6 で実装済み",
  },
  {
    id: "文書頭の `---` は閉じ delimiter が有れば frontmatter",
    md: "---\nk: v\n---\n\n# r\n",
    nodes: ["H:r"],
    blocks: [],
    lezer: ["k: v", "r"],
    verdict: "diff",
    why: "封筒として切り出し、head に逐語で持つ（R109・§A-7 前提 1）。封筒の条件は**閉じの `---` があること**と**開きの直後が空行でないこと**の 2 つ（裁定 E。次の 2 行が残りの半分を持つ）。素の CommonMark に封筒の概念は無く、`---` を水平線、`k: v` + `---` を SetextHeading2 と読む。法則 4 の番人は `withoutHead` で封筒を外してから審判に見せる",
  },
  {
    id: "閉じが無ければ先頭トグル（左開始）",
    md: "---\n\n## a\n",
    nodes: ["H:a"],
    blocks: [],
    lezer: ["a"],
    verdict: "same",
    why: "R109 の裁定。implied root の先頭スロットが左になる。lezer は `---` を HorizontalRule と読むだけなので骨格は一致する",
  },
  {
    id: "開き `---` の直後が空行なら封筒ではなく先頭トグル",
    md: "---\n\n## a\n\n---\n\n## b\n",
    nodes: ["H:a", "H:b"],
    blocks: [],
    lezer: ["a", "b"],
    verdict: "same",
    why: "封筒は『閉じ delimiter と中身の形』で裁定する（仕様 §2）。開き直後が空行なら封筒ではない — serialize は先頭トグルの直後に必ず空行を挟むので、この 1 条件で先頭トグルと封筒が一意に分かれる。素の CommonMark も `---` を HorizontalRule と読むだけなので骨格は一致する。**この行が無いと、閉じ `---` だけで裁定する実装が「先頭トグル 2 本の文書を丸ごと封筒に飲む」まま緑になる**（裁定 E。T1 Task 7 の `scan_head`、T4 Task 33 の seed 199）",
  },
];

test("方言表: mmm の読みが表のとおり", () => {
  const failures: string[] = [];
  for (const d of DIALECT) {
    const gotNodes = skeleton(d.md);
    if (JSON.stringify(gotNodes) !== JSON.stringify(d.nodes)) {
      failures.push(
        `${d.id}: 骨格が違う\n    期待=${JSON.stringify(d.nodes)}\n    実際=${JSON.stringify(gotNodes)}`,
      );
    }
    const gotBlocks = blocksOf(d.md);
    if (JSON.stringify(gotBlocks) !== JSON.stringify(d.blocks)) {
      failures.push(
        `${d.id}: 中身が違う\n    期待=${JSON.stringify(d.blocks)}\n    実際=${JSON.stringify(gotBlocks)}`,
      );
    }
  }
  assert.deepEqual(
    failures,
    [],
    `方言表と読みが食い違う:\n  ${failures.join("\n  ")}`,
  );
});

test("方言表: 審判（lezer）の読みも表のとおり", () => {
  // 表の lezer 欄が古びたら、差分が方言由来か lezer の版由来か区別できなくなる。
  const failures: string[] = [];
  for (const d of DIALECT) {
    const got = lezerTopHeadings(d.md);
    if (JSON.stringify(got) !== JSON.stringify(d.lezer)) {
      failures.push(
        `${d.id}\n    期待=${JSON.stringify(d.lezer)}\n    実際=${JSON.stringify(got)}`,
      );
    }
  }
  assert.deepEqual(
    failures,
    [],
    `審判の読みが表と違う（lezer の版を確かめること）:\n  ${failures.join("\n  ")}`,
  );
});

test("方言表: 意図的な差分は表に挙げた分だけ", () => {
  // 表の中で `diff` と宣言した行だけが、実際に食い違っていること。
  const failures: string[] = [];
  for (const d of DIALECT) {
    const mmmHeads = skeleton(d.md)
      .filter((s) => s.startsWith("H:"))
      .map((s) => s.slice(2));
    const agree = JSON.stringify(mmmHeads) === JSON.stringify(d.lezer);
    if (agree && d.verdict === "diff") {
      failures.push(`${d.id}: diff と宣言したのに一致した`);
    }
    if (!agree && d.verdict === "same") {
      failures.push(
        `${d.id}: same と宣言したのに食い違った\n    mmm=${JSON.stringify(mmmHeads)}\n    lezer=${JSON.stringify(d.lezer)}`,
      );
    }
  }
  assert.deepEqual(
    failures,
    [],
    `方言表の宣言が実態と合わない:\n  ${failures.join("\n  ")}`,
  );
});

test("法則 4: 審判が文書直下で見つけた見出しは、mmm の骨格に必ず全部ある", () => {
  // 反対向き（mmm にあって lezer に無い）は方言表が持つ — `#######` がその全部。
  // こちらは「読み落とし」の番人で、実在コーパスとランダム md の両方に当てる。
  // 審判に見せる前に、封筒・「複数行段落 + setext の下線」・
  // 「ATX で書き戻せない行 + 下線」の 3 つを外す（どれも表が 1 行で持つ差分）。
  const failures: string[] = [];
  const targets = corpus().map((d) => ({ tag: d.path, md: d.md }));
  for (let seed = 1; seed <= DIALECT_CASES; seed++) {
    targets.push({ tag: `seed=${seed}`, md: randomMd(seed) });
  }
  for (const { tag, md } of targets) {
    if (failures.length >= 6) break;
    const want = lezerTopHeadings(
      withoutUnwritableSetext(withoutMultilineSetext(withoutHead(md))),
    );
    const got = skeleton(md)
      .filter((s) => s.startsWith("H:"))
      .map((s) => s.slice(2));
    if (!isSubsequence(want, got)) {
      failures.push(
        `${tag}: 審判の見出しが mmm に無い\n    lezer=${JSON.stringify(want.slice(0, 12))}\n    mmm  =${JSON.stringify(got.slice(0, 12))}\n    入力=${brief(md, 160)}`,
      );
    }
  }
  assert.deepEqual(failures, [], `法則 4 が破れた:\n  ${failures.join("\n  ")}`);
});
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
node --test D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-dialect.test.ts
```
Expected: T2 の読みに穴が残っていれば `✖ 方言表: mmm の読みが表のとおり` に行 id と `期待=` / `実際=` が並ぶ。`ℹ fail N` / EXIT=1。
（`@lezer/markdown` が `ERR_MODULE_NOT_FOUND` で落ちるなら Task 30 の `pnpm install` を踏んでいない。先にそちらを済ませる。）
すべて揃っていれば `ℹ tests 4` / `ℹ pass 4` / `ℹ fail 0`。

- [ ] **Step 3: 落ちた行を最小差分に絞って担当へ渡す**

落ちた行は 3 通りに分かれる。扱いを分けること:

| 症状 | 扱い |
|---|---|
| **表が正しく、実装が間違っている** | 行 id と `期待=` / `実際=` を逐語で T2（`core/doc/block.mbt` / `core/doc/build.mbt`）または T1（`core/doc/scan.mbt`）へ渡す。**表は緩めない** |
| **実装が正しく、表が古い** | 表の行を書き替える。**`why` を必ず更新する**（表は「なぜその差分を選んだか」の記録であって、実装の写しではない） |
| **`審判の読みが表と違う`** | @lezer/markdown の版が上がった。`lezer` 欄を実測値で更新し、`verdict` を実態に合わせ直す |

**このタスクは実装を書かないが、「どこを直すか」までは絞って渡す。**方言表が落ちるのは行の認定（`scan.mbt`）でしかありえないので、次の 2 か所と突き合わせてから渡す。

**① 見出しのラベルが違う（`## b ##` / `   ## x` / 前後空白の行）— `atx_at` の閉じシーケンス判定。**T1 Task 5 の逐語:

```moonbit
  let (a, b0) = trim_range(text, q, l.end)
  let mut b = b0
  // 閉じシーケンス: 空白に前置きされた `#` の連なりが行末まで続く形だけ
  let mut e = b
  while e > a && code_at(text, e - 1) == 35 {
    e = e - 1
  }
  if e < b && (e == a || is_space(code_at(text, e - 1))) {
    b = e
    while b > a && is_space(code_at(text, b - 1)) {
      b = b - 1
    }
  }
  Some((q - p, slice(text, a, b)))
```

渡す言葉は「`<id>` の label が `<実際>` になる。閉じシーケンスの判定（空白に前置きされているか／`e == a` の全部 `#` の行）のどちらが曲がったか」。

**② `- - -` や `***` が項目として読まれた — `bullet_at` の `break_at` guard。**T1 Task 6 の逐語（`let c = code_at(text, p)` の直後に居る 3 行）:

```moonbit
  let c = code_at(text, p)
  // 裁定 2。`- - -` も `***` も CommonMark の thematic break であって
  // 箇条書きではない。base はこの行自身の字下げ（自分の列から数える）
  if break_at(text, l, col) != 0 {
    return None
  }
  let mut q = p
  if c == 45 || c == 42 || c == 43 {
```

渡す言葉は「`<id>` で `- - -` が `I:` になる。guard が消えているか、`break_at` の `base` に `col` ではない値が渡っている」。

表を書き替えるときの具体形（例として `- - -` の行。実際に直す行に読み替える）。**触ってよいのは `nodes` / `blocks` / `lezer` / `verdict` / `why` で、`id` と `md` は動かさない**:

```ts
  {
    id: "`- - -` は飾りの水平線（旧 core の「前から箇条書き」方言は捨てた）",
    md: "# r\n\n- - -\n",
    nodes: ["H:r"],
    blocks: ["rule"],
    lezer: ["r"],
    verdict: "same",
    why: "CommonMark の thematic break。裁定 2。トグルは空白を 1 つも含まない `---` だけ（`Break(true)`）で、`- - -` は常に `Break(false)` = 飾り。T1 Task 6 で実装済み",
  },
```

`lezer` 欄を測り直すときの綴り（審判だけを単独で叩く）:

```
node -e "import('@lezer/markdown').then(m => { const t = m.parser.parse('# r\n\n- - -\n'); const out = []; t.iterate({ enter: n => { out.push(n.name); return true; } }); console.log(out.join(',')); })"
```

`法則 4 が破れた` が出た場合は、表を増やす前に**外し忘れ**を疑う。**多行段落の setext は表の行が拾う**（`withoutMultilineSetext` が入力から外す）ので、そこで落ちているなら番人の前処理の側のバグである。**前後空白・末尾 `#` の setext（`  a  ` + `---`）も表の行が拾う**（`withoutUnwritableSetext` が外す）ので、同じく前処理を見る — 実在コーパスには「行末に空白を残した段落の直後の `---`」が普通に居るので、ここは実装が正しくても踏む。封筒（`withoutHead` が落とし損ねた形、または mmm が封筒と読んだのに審判には本文に見えている形）も同じ扱い。**それ以外で落ちたら本物の読み落とし**なので、縮めた md（Task 37 の `shrink`）を 1 行として `DIALECT` に足し、`verdict: "diff"` と `why` を書く。

- [ ] **Step 4: テストを走らせて通過を確認**

Run:
```
node --test D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-dialect.test.ts
pnpm -C D:/1.atrium/mmm/.claude/worktrees/doc-model run check
```
Expected: `ℹ tests 4` / `ℹ pass 4` / `ℹ fail 0` / EXIT=0。`pnpm run check` も EXIT=0。
深掘りするときは `const DIALECT_CASES = 300;` を 5000 に書き替えて同じコマンドを回し、**終わったら 300 に戻す**（環境変数の前置きは使わない — 裁定 6）。

- [ ] **Step 5: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add test/doc-dialect.test.ts
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "test: 🧪 外の審判と読み比べ、意図した差分だけを表に残す"
```

---

## Task 37: 最小反例の縮小と、操作の受け口

**依存**: **T5 Task 40（`edit.mbt` / `diff.mbt`）・41（`reflect.mbt`）・45（`delete.mbt`）・46（`side.mbt`）・47（`move.mbt`）の完了後**に着手する。前半（`shrink` の 4 本）だけは T5 を待たずに実行できる。

**Files:**
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/wire.mbt`（`reject_tag` / `apply_op` を追記）
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/js/exports.mbt`（`doc_apply` を追記）
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/test/_doc.ts`（`OpEdit` / `OpResult` / `applyOp` / `applyEdits` / `shrink`）
- Modify: `D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-law.test.ts`
- Test: `D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-law.test.ts`

**Interfaces:**
- Consumes: `move_nodes(ast, ids, parent, at) -> Outcome` / `flip_side(ast, ids) -> Outcome` / `delete_nodes(ast, ids) -> Outcome` / `reflect(old, ast) -> Array[Edit]` / `apply(text, edits) -> String` / `Outcome` / `Reject` / `Edit`（すべて T5）
- Produces:
  - JS: `docApply(md, op, ids, parent, at): string`（§D-1 の形の JSON）
  - TS: `shrink(md, fails, rounds?)` / `applyOp(md, op, ids, parent, at): OpResult` / `applyEdits(text, edits): string` と型 `OpEdit` / `OpResult`（**判別可能ユニオン**）
- **T5 Task 48（`test/doc-ops.test.ts`）はこの 3 本を import して使う。写経しない。**

- [ ] **Step 1: 失敗するテストを書く**

`test/doc-law.test.ts` の `_doc.ts` の import 行を更新する。

```ts
import {
  format,
  check,
  sig,
  tree,
  flatten,
  skeleton,
  blocksOf,
  randomMd,
  shrink,
  applyOp,
  applyEdits,
} from "./_doc.ts";
```

ファイル末尾に追記する。

```ts
// ---------------------------------------------------------------
// ファズが落ちたときの手順 —
// ① 失敗メッセージの seed で `randomMd(seed)` を再現する（生成器は決定的）
// ② `shrink` にかけて、まだ落ちる最小の md まで行を削り込む
// ③ 縮んだ md を方言表か固定テストの 1 行として写し、担当へ渡す
// 縮小器そのものが壊れていたら手順が全部嘘になるので、ここで検査しておく。
// ---------------------------------------------------------------

test("縮小器: まだ落ちる最小の反例まで削り込む", () => {
  const md = "# r\n\n## a\n\ntext\n\n## BOOM\n\nmore\n\n## b\n";
  const fails = (s: string): boolean => s.includes("BOOM");
  assert.equal(shrink(md, fails), "## BOOM");
});

test("縮小器: 落ちない入力はそのまま返す", () => {
  const md = "# r\n\n## a\n";
  assert.equal(
    shrink(md, () => false),
    md,
  );
});

test("縮小器: CRLF の反例は CRLF のまま縮む", () => {
  // 改行の流儀が原因の失敗を、縮小の途中で取り落とさない。
  const md = "# r\r\n\r\n## a\r\n\r\n## BOOM\r\n\r\n## b\r\n";
  assert.equal(
    shrink(md, (s) => s.includes("BOOM") && s.includes("\r\n")),
    "## BOOM\r\n",
  );
});

test("縮小器: 常に落ちる述語を渡しても止まる（暴走しない）", () => {
  const got = shrink(randomMd(3), () => true);
  assert.ok(got.length <= randomMd(3).length, "縮小で伸びた");
});

// ---------------------------------------------------------------
// 操作の受け口。ここでは疎通だけを見る（操作の性質は T5 Task 48 の doc-ops.test.ts）。
// ---------------------------------------------------------------

test("受け口: 資格の無い flip は理由付きで拒否される", () => {
  const md = "# r\n\n## a\n\n### deep\n";
  const deep = flatten(tree(md).doc).filter((n) => n.label === "deep")[0];
  const res = applyOp(md, "flip", [deep.id], 0, 0);
  assert.deepEqual(res, { ok: false, reject: "ineligible" });
});

test("受け口: delete は反映後の全文と指紋と編集の列を返す", () => {
  const md = "# r\n\n## a\n\n## b\n";
  const b = flatten(tree(md).doc).filter((n) => n.label === "b")[0];
  const res = applyOp(md, "delete", [b.id], 0, 0);
  // `ok` を見て絞り込む。`assert.equal(res.ok, true)` では TS が絞り込まない。
  if (!res.ok) assert.fail(res.reject);
  assert.equal(res.text, "# r\n\n## a\n");
  assert.equal(res.sig, sig("# r\n\n## a\n"));
  assert.equal(applyEdits(md, res.edits), res.text);
});
```

- [ ] **Step 2: テストを走らせて失敗を確認**

Run:
```
node --test D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-law.test.ts
```
Expected: `SyntaxError: The requested module './_doc.ts' does not provide an export named 'shrink'` でファイルごと落ちる。EXIT=1。

- [ ] **Step 3: 操作 1 回を JSON にする**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/wire.mbt` の末尾に追記する。**`Reject` の変種は 3 つのまま**で、`"unknown-op"` は文字列として返すだけ（判定 4 を汚さない）。

```moonbit
///|
fn reject_tag(r : Reject) -> String {
  match r {
    Missing => "missing"
    Cycle => "cycle"
    Ineligible => "ineligible"
  }
}

///|
/// 操作 1 回。木を変異させ、反映 v0 の Edit の列と反映後の全文を返す。
/// 形は §D-1 で固定:
///   {"ok":true,"text":…,"sig":…,"edits":[{"from":…,"to":…,"insert":…}]}
///   {"ok":false,"reject":"missing"|"cycle"|"ineligible"|"unknown-op"}
pub fn apply_op(
  md : String,
  op : String,
  ids : Array[Int],
  parent : Int,
  at : Int,
) -> String {
  if op != "move" && op != "flip" && op != "delete" {
    return "{\"ok\":false,\"reject\":\"unknown-op\"}"
  }
  let ast = parse(md)
  let outcome = if op == "move" {
    move_nodes(ast, ids, parent, at)
  } else if op == "flip" {
    flip_side(ast, ids)
  } else {
    delete_nodes(ast, ids)
  }
  match outcome {
    Reject(r) => "{\"ok\":false,\"reject\":" + json_str(reject_tag(r)) + "}"
    Done(next) => {
      let edits = reflect(md, next)
      let text = apply(md, edits)
      let sb = StringBuilder::new()
      sb.write_string("{\"ok\":true,\"text\":")
      sb.write_string(json_str(text))
      sb.write_string(",\"sig\":")
      sb.write_string(json_str(sig(next)))
      sb.write_string(",\"edits\":[")
      for i = 0; i < edits.length(); i = i + 1 {
        if i > 0 {
          sb.write_string(",")
        }
        sb.write_string("{\"from\":")
        sb.write_string(edits[i].from.to_string())
        sb.write_string(",\"to\":")
        sb.write_string(edits[i].to.to_string())
        sb.write_string(",\"insert\":")
        sb.write_string(json_str(edits[i].insert))
        sb.write_string("}")
      }
      sb.write_string("]}")
      sb.to_string()
    }
  }
}
```

- [ ] **Step 4: JS の受け口に最後の 1 本を足して、生成物を作り直す**

`D:/1.atrium/mmm/.claude/worktrees/doc-model/core/doc/js/exports.mbt` の末尾に追記する。**`#export_name` はこれで 5 本。増やさない。**

```moonbit
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

Run:
```
moon -C D:/1.atrium/mmm/.claude/worktrees/doc-model/core fmt doc
pnpm -C D:/1.atrium/mmm/.claude/worktrees/doc-model run core
node -e "import('file:///D:/1.atrium/mmm/.claude/worktrees/doc-model/core/_build/js/release/build/doc/js/js.js').then(m => console.log(m.docApply('# r\n\n## a\n', 'nope', [], 0, 0)))"
```
Expected: `pnpm run core` が EXIT=0。node の出力が `{"ok":false,"reject":"unknown-op"}`。

- [ ] **Step 5: TS 側に操作と縮小を足す**

`test/_doc.ts` の `DocCore` 型に 1 本足す。

```ts
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
```

型の節（`DocTree` の直後）に 2 つ足す。

```ts
export type OpEdit = { from: number; to: number; insert: string };

/** 操作 1 回の結果。**判別可能ユニオン** — `ok` を見れば絞り込める。 */
export type OpResult =
  | { ok: true; text: string; sig: string; edits: OpEdit[] }
  | { ok: false; reject: string };
```

ファイル末尾に追記する。

```ts
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
// 縮小
// ---------------------------------------------------------------

/**
 * 反例を縮める。**行を落として、まだ失敗するなら採用する**。
 * 大きい塊（半分）から始めて 1 行まで細かくするので、
 * 数十行の md でも数十回の試行で最小の形まで落ちる。
 *
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
    for (
      let size = Math.max(1, lines.length >> 1);
      size >= 1 && budget > 0;
      size >>= 1
    ) {
      for (let at = 0; at + size <= lines.length && budget > 0; at++) {
        budget--;
        const next = lines
          .slice(0, at)
          .concat(lines.slice(at + size))
          .join(nl);
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

- [ ] **Step 6: ランダムファズの失敗メッセージを、縮小済みの反例に差し替える**

Task 35 で書いた 2 本の `failures.push` を書き替える（テストの本数は変わらない）。

`test/doc-law.test.ts` の「法則 2: ランダム生成の md で format が冪等」の中:

```ts
      if (once !== twice) {
        const min = shrink(md, (s) => {
          try {
            return format(format(s)) !== format(s);
          } catch {
            return true;
          }
        });
        failures.push(
          `seed=${seed}\n    最小=${brief(min, 200)}\n    1回目=${brief(format(min), 200)}\n    2回目=${brief(format(format(min)), 200)}`,
        );
      }
```

「不変条件: ランダム生成の md を読んだ木が常に健全」の中:

```ts
    if (v.length > 0) {
      const min = shrink(md, (s) => {
        try {
          return check(s).length > 0;
        } catch {
          return true;
        }
      });
      failures.push(
        `seed=${seed}: ${check(min).join(" / ")}\n    最小=${brief(min, 200)}`,
      );
    }
```

- [ ] **Step 7: テストを走らせて通過を確認**

Run:
```
pnpm -C D:/1.atrium/mmm/.claude/worktrees/doc-model run core
node --test "D:/1.atrium/mmm/.claude/worktrees/doc-model/test/doc-*.test.ts"
pnpm -C D:/1.atrium/mmm/.claude/worktrees/doc-model run test:doc
pnpm -C D:/1.atrium/mmm/.claude/worktrees/doc-model test
pnpm -C D:/1.atrium/mmm/.claude/worktrees/doc-model run check
```
Expected:
- `test/doc-law.test.ts` が `ℹ tests 22` / `ℹ pass 22` / `ℹ fail 0`、`test/doc-dialect.test.ts` が `ℹ tests 4` / `ℹ pass 4` / `ℹ fail 0`（`node --test` はファイルごとに集計を出す）／EXIT=0
- `pnpm run test:doc` が `Total tests: N, passed: N, failed: 0.`（N = Task 33 Step 4 の B+4。MoonBit 側は本タスクでテストを増やしていない）／EXIT=0
- `pnpm test`（旧 core を含む全 TS テスト）が **311 + 新規 26 本**で通り、既存 26 ファイルは 1 本も落ちない／EXIT=0
- `pnpm run check` が EXIT=0（`test/tsconfig.json` の `include` が `"."` なので `_doc.ts` も対象。`noUnusedLocals` があるので未使用の import が 1 つでも残れば `error TS6133`）

- [ ] **Step 8: コミット**

```
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model add core/doc/wire.mbt core/doc/js/exports.mbt test/_doc.ts test/doc-law.test.ts
git -C D:/1.atrium/mmm/.claude/worktrees/doc-model commit -m "test: 🧪 落ちた反例を最小まで削り、操作の受け口を開ける"
```

---

## 依存と、他の担当へ渡すもの

```
Task 30 ────────────────────────────────────> 単独で先行できる（誰も待たない）
T1(1〜9) + T2(10〜17) + T3(20〜26) ──> Task 31 ──> Task 32 ──> Task 33 ──> Task 34 ──> Task 35 ──> Task 36
T5(40・41・45・46・47) ────────────────────────────────────────────────────────> Task 37 ──> T5 Task 48
```

- **T1 へ**: `sig` の綴りは `doc-law.test.ts` の受け口テストが `"head:-\nlf\n[H[Hr[Ha]]]"` で逐語固定する（§A-4 の固定の例と一致させること）。`- - -` は **`Break(false)` = 飾りの水平線**（裁定 2）で、方言表にも「捨てた方言」として明記した（T1 Task 6 で実装済み）
- **T1 へ**: `atx_writable`（Task 9）は T4 の生成器にも写してある（`test/_doc.ts` の `atxWritable`。Task 36 の番人はそれを import して使うので、写しは 2 つのまま）。**規則を変えるときは 2 か所を同時に直す** — 前後空白・末尾 `#` の行に setext の下線を付けるのをやめる、という同じ判断を、読み側と生成側の両方で守っている。方言表にも「ATX で書き戻せない行は setext にしない」の行を置いた（`verdict: "diff"`。lezer は `  a  ` + `---` を setext 見出しと読む）
- **T1 へ**: **裁定 E（封筒の「中身の形」）が `scan_head` に入っていないと、Task 33 が seed 199 で落ちる。**先頭スロットが左の implied root を先頭に持つ木は文書の 1 行目に `---` が出るので、トグルがもう 1 本あると 1 本目〜2 本目が丸ごと head に飲まれる。`gen_ast` は種 1〜300 で先頭 `---` の木を 6 本（48・60・123・199・256・268）、うちトグル 2 本以上を 1 本（**seed 199**）吐く（5000 まで広げると 114 本 / 34 本）。方言表にも「開き `---` の直後が空行なら封筒ではなく先頭トグル」の行を置いた。**直す場所は `scan.mbt` の `scan_head`**（開き `---` の直後が空行なら封筒ではない）であって、生成器ではない
- **T1 へ**: `head` / `Opaque` / `Code.text` / `Svg` の改行が `"\n"` で `\r` を含まないこと（§A-7 前提 1）は、Task 34 の「法則 2: リポジトリ内の実 .md すべてで format が冪等」が `test/fixtures/gnarly-crlf.md` で毎回検算する
- **T2 へ**: 方言表（`test/doc-dialect.test.ts` の `DIALECT` 18 行）が `block.mbt` / `build.mbt` の読みを 1 行ずつ固定する。落ちたら行 id と `期待=` / `実際=` が逐語で出る
- **T2 へ**: **裁定 A（`push_skel` が見出しを積む前に開いている項目を全部閉じる）が入っていないと、Task 35 が着手した瞬間に赤になる。**Task 35 の 600 seed のうち 14 seed（最小は seed 85 の `1. a` + `## a`）がこの形を吐き、`check` が `Item の下に Heading: <id>` を返す。**実 .md コーパスにはこの形が無いので Task 34 は緑のまま通る** — 原因が T4 に見えるが、直す場所は `build.mbt` の `push_skel` である。カタログ C17（`- a` + `## h` → `[H[Ia][H~[Hh]]]`）がこの形を 1 行で固定する
- **T3 へ**: カタログの逐語期待（C1〜C7・C9〜C14・C16・C17）は `doc-law.test.ts` の `CATALOG` に置いた。C8・C15 は `want: null` のまま（逐語は T2/T3 が決める）。**C7 は v0 の期待として正しい** — 手書きの `---` が残るのは すげ替え v1（後日箱 X06）の話で、v0 では `***` に正規化されるのが正しい
- **T5 へ**: `docApply` の JSON は `{"ok":true,"text":…,"sig":…,"edits":[…]}` / `{"ok":false,"reject":"missing"|"cycle"|"ineligible"|"unknown-op"}`。`test/doc-ops.test.ts` は `applyOp` / `applyEdits` / `shrink` / `sig` / `check` / `tree` / `flatten` / `randomMd` を `test/_doc.ts` から import して使う（**写経しない。自前の型も自前の `applyEdits` も定義しない**）。`OpResult` は判別可能ユニオンなので `if (!res.ok) assert.fail(res.reject);` で絞り込むこと。`check` は `string[]` を返すので `check(x).length > 0` で判定する
- **T5 へ**: `test/_doc.ts` に存在する名前は §D-3 の 17 個 + Task 35 で足す `atxWritable` の **18 個**だけ（§D-3 の表へ 1 行足すこと）。`doc` 名前空間・`randomDoc`・`ApplyResult` は**存在しない**。`LABELS` / `SETEXT_LABELS` / `BLOCKS` は export しない（生成器の内側）
- **T5 へ**: MoonBit 側の `labels`（Task 33）は**綴りを素通しする 10 個だけ**で、前後空白・末尾 `#` のような「往復で変わるラベル」を持たない。これは網の穴ではなく**入口が無いことの写し**である — parse は `atx_writable` でそういう行を見出しにせず、`normalize` はラベルを一切触らないので、操作からモデルへ不正なラベルは入らない。**`normalize` にラベルを触らせないこと**が前提で、rename（範囲外）を足す日には「逃がし方（`spell.mbt` の綴り）を決める → `labels` を広げる」の順で進める
- **T5 へ**: 不変条件 8 は裁定 B により「**implied の前に見出しの兄弟が居ない**」へ一般化された（違反メッセージは `implied の前に見出しが居る: <id>`）。`spellable` の判定も同じ言葉に揃えること — 項目 root の後ろの implied（カタログ C17 の形）は綴れるので昇格させない
- **全員へ**: `core/doc/law_wbtest.mbt` が新設するトップレベル名は 12 個（`fuzz_seeds` / `Rand` / `Rand::new` / `Rand::pick` / `Gen` / `labels` / `sample_block` / `side_for` / `gen_implied` / `gen_children` / `gen_node` / `gen_ast`）。§C-3 の T4 の行に全部足すこと。**`labels` は総称的なので他群は同名を置かない**（`*_wbtest.mbt` は名前空間を共有し、二重定義は `Error: [4051]` でパッケージのテストが 1 本も走らなくなる）
- **全員へ**: ファズの回数は**定数**で切り替える（裁定 6）。MoonBit は `fuzz_seeds`、TS は `RANDOM_CASES`（`doc-law.test.ts`）と `DIALECT_CASES`（`doc-dialect.test.ts`）。**環境変数の前置きは書かない。`fuzzCases` も import しない**
