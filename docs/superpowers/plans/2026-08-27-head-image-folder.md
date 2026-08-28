# 画像フォルダの場所を .md の頭に書く — 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 画像フォルダの宣言を `window.prompt` + IndexedDB から `.md` の YAML frontmatter へ移し、宣言を書き換えたら本文の画像パスが追従するようにする。

**Architecture:** core は「どこからどこまでが文書の頭か」だけを答える非構造区間を 1 つ増やす（中は走査しないので、他ツールの frontmatter がノード化しなくなる）。`image-folder` という綴りの解釈と本文の一括置換は TS の新しい純粋層 `src/app/head.ts` が持つ。宣言は .md、許可（フォルダハンドル）は IndexedDB、という 2 つの持ち主を言い切る。

**Tech Stack:** MoonBit（core、`moon test`）/ TypeScript（src、`node --test`）/ CodeMirror 6 / File System Access API

**Spec:** `docs/superpowers/specs/2026-08-27-head-image-folder.md`

## Global Constraints

- **設定名は `image-folder`**。frontmatter のトップレベルキー。値は `.md` から見たフォルダの相対パス
- **頭は先頭行がちょうど `---` で、後続にちょうど `---` の行があるときだけ成立**。開きも閉じもダッシュ 3 本ちょうど（`----` も `...` も閉じない）。閉じなければ頭ではない
- **頭の中は一切走査しない。** 見出しもリスト項目も作らず、`list_from` にも数えない
- **YAML パーサは入れない。** 読むのは 1 キー、書くのも 1 行。他ツールが書いたコメント・引用符・キーの順序は触らない
- **本文の書き換え対象は「直前の宣言フォルダの下にある画像リンク」だけ。** 頭とフェンスの中は見ない。外部 URL は見ない
- **書き換えは Undo 1 回で全部戻る**（同じ tag で `core.replaceText`、後ろから適用）
- **`as T` も `!` も書かない**（`test/assertions.test.ts` が見張る）。`instanceof` / 型ガード / 既定値のどれかで確かめる
- テストコマンド: `pnpm run core`（コア再生成）/ `pnpm run test:core` / `pnpm test` / `pnpm run check`
- コミットは Semantic Commit Message（`<Type>: <Emoji> <Title>`）

---

## File Structure

| ファイル | 役割 | Task |
|---|---|---|
| `core/parser.mbt` | `Head` 区間の判定を `scan_doc` に足す | 1 |
| `core/doc.mbt` | `st.head` を持つ | 1 |
| `core/api.mbt` | snapshot に `head` を載せる | 1 |
| `core/head_wbtest.mbt` | **新規** 頭が非構造区間であることの検証 | 1 |
| `src/coreApi.ts` | `HeadSpan` を `Snapshot` / `DocView` へ通す | 2 |
| `src/main.ts` | `doc` に `head` を足す | 2 |
| `test/_helpers.ts` | `loadDoc` が `head` を返す | 2 |
| `src/app/head.ts` | **新規** 文書の頭の設定（読む・書く・パスの綴り・本文の追従） | 3, 4 |
| `test/head.test.ts` | **新規** 上記の純関数の検証 | 3, 4 |
| `src/map/cards.ts` | `parseImage` が行内の位置も返す | 4 |
| `src/app/handles.ts` | `AssetBinding` から `path` を落とす | 5 |
| `src/app/assets.ts` | 宣言を外から受け取る。`prompt` を消す | 5 |
| `README.md` | 構成表に `app/head.ts` | 3 |

---

## Task 1: core — 頭を非構造区間にする

**Files:**
- Modify: `core/parser.mbt`（`Fence` struct の直後、`scan_doc`、`Scan` struct）
- Modify: `core/doc.mbt:36-70`（`St` の宣言と初期値）、`rebuild_nodes`
- Modify: `core/api.mbt:114-137`（`take_snapshot` の末尾）
- Test: `core/head_wbtest.mbt`（新規）

**Interfaces:**
- Consumes: なし（最初のタスク）
- Produces: snapshot JSON に `"head": {"from":Int,"to":Int,"bodyFrom":Int,"bodyTo":Int}` または `"head": null`

- [ ] **Step 1: 失敗するテストを書く**

`core/head_wbtest.mbt` を新規作成する。`st` を直接見たいので whitebox テスト（`core/list_wbtest.mbt` と同じ書き方）。

```moonbit
// 文書の頭（YAML frontmatter）は非構造区間、の検証。
// st.head / st.nodes を直接見たいので whitebox テスト。

///|
/// 頭の区間を 1 本の文字列に畳む（無ければ "none"）。
/// Head は Eq を持たないので、比べられる形に落とす。
fn head_sig() -> String {
  match st.head {
    Some(h) => {
      let sb = StringBuilder::new()
      sb.write_string(h.start.to_string())
      sb.write_string(":")
      sb.write_string(h.body_start.to_string())
      sb.write_string(":")
      sb.write_string(h.body_end.to_string())
      sb.write_string(":")
      sb.write_string(h.end.to_string())
      sb.to_string()
    }
    None => "none"
  }
}

///|
test "頭の中のリスト項目はノードにならない" {
  ignore(init_doc("---\ntags:\n  - 設計\n  - web\n---\n\n# r\n\n## a\n"))
  assert_eq(st.nodes.length(), 2)
  assert_eq(st.nodes[0].label, "r")
  assert_eq(st.nodes[1].label, "a")
}

///|
test "頭の中の見出し行もノードにならない" {
  ignore(init_doc("---\n# YAML のコメント\nimage-folder: ./img/\n---\n\n# r\n"))
  assert_eq(st.nodes.length(), 1)
  assert_eq(st.nodes[0].label, "r")
}

///|
test "頭の区間は開きの行頭から閉じの行末まで" {
  ignore(init_doc("---\nimage-folder: ./img/\n---\n\n# r\n"))
  // `---\n` = 0..3 (next 4) / `image-folder: ./img/\n` = 4..24 (next 25)
  // / `---\n` = 25..28
  assert_eq(head_sig(), "0:4:24:28")
}

///|
test "中身の無い頭も頭（body_end が body_start より手前）" {
  ignore(init_doc("---\n---\n\n# r\n"))
  assert_eq(head_sig(), "0:4:3:7")
  assert_eq(st.nodes.length(), 1)
}

///|
test "閉じない `---` は頭ではない" {
  ignore(init_doc("---\n- a\n\n# r\n"))
  assert_eq(head_sig(), "none")
  // 頭が成立しないので `- a` は今までどおりリスト項目
  assert_eq(st.nodes.length(), 2)
  assert_eq(st.nodes[0].label, "a")
  assert_eq(st.nodes[1].label, "r")
}

///|
test "先頭でない `---` は頭ではない" {
  ignore(init_doc("# r\n\n---\n\n## a\n"))
  assert_eq(head_sig(), "none")
  assert_eq(st.nodes.length(), 2)
}

///|
test "ダッシュ 4 本は頭を開かない" {
  ignore(init_doc("----\n- a\n----\n\n# r\n"))
  assert_eq(head_sig(), "none")
}

///|
test "頭を含む文書の往復がバイト同一" {
  let src = "---\nimage-folder: ./img/\ntags:\n  - a\n---\n\n# r\n\n![](./img/a.webp)\n"
  ignore(init_doc(src))
  assert_eq(get_text(), src)
}

///|
test "貼り付け断片の頭も構造に数えない" {
  assert_eq(has_headings("---\ntags:\n  - a\n---\n\ntext\n"), false)
  assert_eq(has_headings("---\ntags:\n  - a\n---\n\n# r\n"), true)
}
```

- [ ] **Step 2: 失敗を確認する**

```bash
pnpm run test:core
```

Expected: FAIL。`st.head` も `Head` 型も無いのでコンパイルエラー（`The value identifier head is undefined` 等）。

- [ ] **Step 3: `core/parser.mbt` に `Head` と判定を足す**

`Fence` struct の定義の直後（`FenceOpen` の手前）に足す:

```moonbit
///|
/// 文書の頭 — 先頭の `---` から次の `---` まで（YAML frontmatter）。
///
/// **中は一切走査しない。** 他所の md が持つ `tags:` 配下の `- 設計` は、
/// 走査すればリスト項目としてノードになる（`^\s*[-*+]\s` は構造なので）。
/// 頭は文書の設定であって木ではないので、区間ごと外す。
///
/// 開きも閉じも**ちょうど 3 本**の `---` の行。閉じないまま文書が終われば
/// 頭ではない（先頭の `---` はただの区切り線に戻る）。
priv struct Head {
  start : Int // 開き `---` 行の行頭
  end : Int // 閉じ `---` 行の行末（改行の手前）
  body_start : Int // 中身の最初の行頭
  body_end : Int // 中身の最後の行末。中身が無ければ body_start より手前
}
```

`Scan` struct に 1 つ足す（`fences` の次）:

```moonbit
  head : Head? // 文書の頭。無ければ None
```

`is_comment_close` の定義の直後に、判定を足す:

```moonbit
///|
/// ちょうど 3 本の `-` だけの行か。前後の空白は落として見る。
/// `----` は開きも閉じもしない（Jekyll と同じ）。
fn is_head_marker(text : String, l : Line) -> Bool {
  let (a, b) = trimmed_span(text, l)
  b - a == 3 &&
  code_at(text, a) == 45 &&
  code_at(text, a + 1) == 45 &&
  code_at(text, a + 2) == 45
}

///|
/// 先頭の頭を読む。区間と「次に走査を始める行の添字」を返す。
/// 先頭が `---` でない / 閉じが無い なら None。
fn scan_head(text : String, lines : Array[Line]) -> (Head, Int)? {
  if lines.length() == 0 || !is_head_marker(text, lines[0]) {
    return None
  }
  for i = 1; i < lines.length(); i = i + 1 {
    if is_head_marker(text, lines[i]) {
      return Some(
        (
          Head::{
            start: lines[0].start,
            end: lines[i].end,
            body_start: lines[0].next,
            body_end: lines[i - 1].end,
          },
          i + 1,
        ),
      )
    }
  }
  None
}
```

`scan_doc` の本体を 2 か所直す。`let mut c_open_next = 0` の次の行、`for idx = 0; …` を次に差し替える:

```moonbit
  // 頭は行走査より先に決める。中は見ないので、走査はその次の行から始める
  let (head, first) = match scan_head(text, lines) {
    Some((h, next)) => (Some(h), next)
    None => (None, 0)
  }
  for idx = first; idx < lines.length(); idx = idx + 1 {
```

`scan_doc` の末尾の戻り値を差し替える:

```moonbit
  Scan::{ heads: out, hides: regions, fences, head, list_from }
```

- [ ] **Step 4: `core/doc.mbt` に `st.head` を足す**

`St` struct の `mut fences : Array[Fence]` の次に足す:

```moonbit
  mut head : Head? // 文書の頭（YAML frontmatter）の区間。無ければ None
```

`let st : St = { … }` の `fences: [],` の次に足す:

```moonbit
  head: None,
```

`rebuild_nodes` の `st.fences = scan.fences` の次に足す:

```moonbit
  st.head = scan.head
```

- [ ] **Step 5: `core/api.mbt` の snapshot に載せる**

`take_snapshot` の末尾、`fences` の配列を閉じている `sb.write_string("]}")` を次に差し替える:

```moonbit
  sb.write_string("],")
  // 頭は 1 つしか無いので配列にしない。**位置だけ**で、中身の解釈はしない
  // （`image-folder` という綴りをコアは知らない）
  match st.head {
    Some(h) => {
      sb.write_string("\"head\":{")
      put_int(sb, "from", h.start)
      sb.write_string(",")
      put_int(sb, "to", h.end)
      sb.write_string(",")
      put_int(sb, "bodyFrom", h.body_start)
      sb.write_string(",")
      put_int(sb, "bodyTo", h.body_end)
      sb.write_string("}")
    }
    None => sb.write_string("\"head\":null")
  }
  sb.write_string("}")
```

- [ ] **Step 6: テストが通ることを確認する**

```bash
pnpm run test:core
```

Expected: PASS（新しい 9 本を含め、既存のコアテストもすべて）。

- [ ] **Step 7: コミット**

```bash
git add core/parser.mbt core/doc.mbt core/api.mbt core/head_wbtest.mbt
git commit -m "feat: 🌱 文書の頭を非構造区間として読む"
```

---

## Task 2: TS — `HeadSpan` を `DocView` まで通す

**Files:**
- Modify: `src/coreApi.ts:39-75`（`FenceSpan` の次に `HeadSpan`、`Snapshot`、`DocView`）
- Modify: `src/main.ts:67`（`doc` の初期値）、`src/main.ts:107`（`applySnap` の `doc` 再構築）
- Modify: `test/_helpers.ts:28-32`（`loadDoc`）
- Test: `test/head.test.ts`（新規、この Task では 1 本だけ）

**Interfaces:**
- Consumes: Task 1 の snapshot JSON `head`
- Produces:
  - `export interface HeadSpan { from: number; to: number; bodyFrom: number; bodyTo: number }`
  - `Snapshot.head: HeadSpan | null`
  - `DocView.head: HeadSpan | null`
  - `loadDoc(md: string): DocView`（`head` を含む）

- [ ] **Step 1: 失敗するテストを書く**

`test/head.test.ts` を新規作成する:

```ts
// 文書の頭（YAML frontmatter）— 区間の受け取りと、その中の 1 行の綴り。
//
// 実行: pnpm test

import { test } from "node:test";
import assert from "node:assert/strict";
import { loadDoc } from "./_helpers.ts";

test("DocView.head: 頭の区間がコアから届く", () => {
  const doc = loadDoc("---\nimage-folder: ./img/\n---\n\n# r\n");
  assert.deepEqual(doc.head, { from: 0, to: 28, bodyFrom: 4, bodyTo: 24 });
});

test("DocView.head: 頭が無ければ null", () => {
  assert.equal(loadDoc("# r\n\n---\n\n## a\n").head, null);
});
```

- [ ] **Step 2: 失敗を確認する**

```bash
pnpm run core && pnpm test
```

Expected: FAIL。`loadDoc` の戻り値に `head` が無い（`undefined` と `{from:0,…}` の比較で落ちる）。

- [ ] **Step 3: `src/coreApi.ts` に `HeadSpan` を足す**

`FenceSpan` の定義の直後に足す:

```ts
/**
 * 文書の頭（YAML frontmatter）の一区間。
 * **どこからどこまでが頭かを決めるのはコアだけ**（core/parser.mbt）— この
 * 境界の内側は走査されないので、`tags:` 配下の `- a` がノードになるか
 * どうかがここで決まる。中身の綴りは解釈しない。
 */
export interface HeadSpan {
  /** 開き `---` 行の行頭 */
  from: number;
  /** 閉じ `---` 行の行末（改行の手前） */
  to: number;
  /** 中身の最初の行頭 */
  bodyFrom: number;
  /** 中身の最後の行末。中身が無ければ bodyFrom より手前 */
  bodyTo: number;
}
```

`Snapshot` の `fences: FenceSpan[];` の次に足す:

```ts
  /** 文書の頭。無ければ null */
  head: HeadSpan | null;
```

`DocView` の `fences: FenceSpan[];` の次に足す:

```ts
  head: HeadSpan | null;
```

- [ ] **Step 4: `src/main.ts` の `doc` に足す**

`src/main.ts:67` を差し替える:

```ts
let doc: DocView = { text: "", nodes: [], fences: [], head: null };
```

`applySnap` の中（`src/main.ts:107` あたり）を差し替える:

```ts
  doc = { text: core.getText(), nodes: snap.nodes, fences: snap.fences, head: snap.head };
```

- [ ] **Step 5: `test/_helpers.ts` の `loadDoc` に足す**

```ts
/** initDoc して、いまの文書をテキスト・ノード・フェンス・頭の組で返す。 */
export function loadDoc(md: string): DocView {
  const snap = core.initDoc(md);
  return {
    text: core.getText(),
    nodes: snap.nodes,
    fences: snap.fences,
    head: snap.head,
  };
}
```

- [ ] **Step 6: テストと型が通ることを確認する**

```bash
pnpm test && pnpm run check
```

Expected: PASS。

- [ ] **Step 7: コミット**

```bash
git add src/coreApi.ts src/main.ts test/_helpers.ts test/head.test.ts
git commit -m "feat: 🌱 頭の区間を DocView まで通す"
```

---

## Task 3: `src/app/head.ts` — 頭の設定を読む・書く

**Files:**
- Create: `src/app/head.ts`
- Modify: `src/map/cards.ts:20`（`bare` を export する — 「裸の綴り」の唯一の定義）
- Modify: `src/app/assets.ts:20`（`bare` を削除して import に）、`src/app/assets.ts:76-82`（`normalizePath` を削除して import に）、`src/app/assets.ts:57-75`（`assetTarget` が `under` を使う）
- Modify: `README.md`（構成表の `app/` の行）
- Test: `test/head.test.ts`（Task 2 で作ったファイルに追記）

**Interfaces:**
- Consumes: Task 2 の `HeadSpan` / `DocView` / `loadDoc`
- Produces（`src/app/head.ts` から export）:
  - `IMAGE_FOLDER: "image-folder"`
  - `imageFolder(text: string, head: HeadSpan | null): string | null`
  - `setImageFolder(text: string, head: HeadSpan | null, value: string): TextEdit`
  - `normalizePath(value: string): string | null`
  - `under(path: string, folder: string): string | null`
- Produces（`src/map/cards.ts` から export）:
  - `bare(path: string): string`

**依存の向き:** `app/head.ts` → `map/cards.ts`。`cards.ts` は `../coreApi.ts`
しか import しないので循環しない（`app/export.ts` が既に `map/` を使っていて、
この向きは通っている）。「裸の綴り」を作るのは `parseImage` なので、定義は
`cards.ts` に 1 つだけ置き、`head.ts` と `assets.ts` はそれを借りる。

- [ ] **Step 1: 失敗するテストを書く**

`test/head.test.ts` の import を差し替え、末尾に足す:

```ts
import {
  IMAGE_FOLDER,
  imageFolder,
  normalizePath,
  setImageFolder,
  under,
} from "../src/app/head.ts";

/** md を読み込んで、頭から宣言を引く小道具 */
const folderOf = (md: string): string | null => {
  const doc = loadDoc(md);
  return imageFolder(doc.text, doc.head);
};

/** md を読み込んで、宣言を書き換えた後のテキストを返す小道具 */
function written(md: string, value: string): string {
  const doc = loadDoc(md);
  const e = setImageFolder(doc.text, doc.head, value);
  return doc.text.slice(0, e.from) + e.insert + doc.text.slice(e.to);
}

test("imageFolder: 頭から値を読む", () => {
  assert.equal(folderOf("---\nimage-folder: ./img/\n---\n\n# r\n"), "./img/");
});

test("imageFolder: 他のキーが並んでいても読む", () => {
  const md = "---\ntitle: メモ\nimage-folder: ./img/\ntags:\n  - a\n---\n\n# r\n";
  assert.equal(folderOf(md), "./img/");
});

test("imageFolder: キーが無い / 頭が無い なら null", () => {
  assert.equal(folderOf("---\ntitle: メモ\n---\n\n# r\n"), null);
  assert.equal(folderOf("# r\n"), null);
  assert.equal(folderOf("---\n---\n\n# r\n"), null);
});

test("imageFolder: 引用符は剥がす", () => {
  assert.equal(folderOf('---\nimage-folder: "./My Images/"\n---\n\n# r\n'), "./My Images/");
  assert.equal(folderOf("---\nimage-folder: './img/'\n---\n\n# r\n"), "./img/");
});

test("imageFolder: 裸の値は ` #` からがコメント", () => {
  assert.equal(folderOf("---\nimage-folder: ./img/ # ここ\n---\n\n# r\n"), "./img/");
});

test("imageFolder: 入れ子のキーは読まない（トップレベルだけ）", () => {
  assert.equal(folderOf("---\nmmm:\n  image-folder: ./img/\n---\n\n# r\n"), null);
});

test("setImageFolder: キーがあればその行だけ差し替える", () => {
  const md = "---\ntitle: メモ\nimage-folder: ./img/\ntags:\n  - a\n---\n\n# r\n";
  assert.equal(
    written(md, "./assets/"),
    "---\ntitle: メモ\nimage-folder: ./assets/\ntags:\n  - a\n---\n\n# r\n",
  );
});

test("setImageFolder: キーが無ければ閉じ `---` の直前に足す", () => {
  assert.equal(
    written("---\ntitle: メモ\n---\n\n# r\n", "./img/"),
    "---\ntitle: メモ\nimage-folder: ./img/\n---\n\n# r\n",
  );
});

test("setImageFolder: 中身の無い頭にも足せる", () => {
  assert.equal(
    written("---\n---\n\n# r\n", "./img/"),
    "---\nimage-folder: ./img/\n---\n\n# r\n",
  );
});

test("setImageFolder: 頭が無ければ先頭に作る", () => {
  assert.equal(
    written("# r\n", "./img/"),
    "---\nimage-folder: ./img/\n---\n\n# r\n",
  );
});

test("setImageFolder: 空白・#・: を含む値は囲む", () => {
  assert.equal(written("# r\n", "./My Images/"), '---\nimage-folder: "./My Images/"\n---\n\n# r\n');
  assert.equal(written("# r\n", "./a#b/"), '---\nimage-folder: "./a#b/"\n---\n\n# r\n');
});

test("setImageFolder: 囲む必要が無ければ裸で書く", () => {
  assert.equal(written("# r\n", "./img/"), "---\nimage-folder: ./img/\n---\n\n# r\n");
});

test("setImageFolder → imageFolder は往復する", () => {
  for (const value of ["./img/", "../pics/", "./My Images/", './a"b/']) {
    assert.equal(folderOf(written("# r\n", value)), value, value);
  }
});

test("IMAGE_FOLDER: 設定名は 1 か所でしか綴られない", () => {
  assert.equal(IMAGE_FOLDER, "image-folder");
  assert.ok(written("# r\n", "./img/").includes(`${IMAGE_FOLDER}: `));
});

test("normalizePath: 末尾に / を足し、空と . は ./ にする", () => {
  assert.equal(normalizePath("img"), "img/");
  assert.equal(normalizePath("./img/"), "./img/");
  assert.equal(normalizePath(""), "./");
  assert.equal(normalizePath("."), "./");
  assert.equal(normalizePath("..\\pics"), "../pics/");
});

test("normalizePath: 相対でないものは null", () => {
  assert.equal(normalizePath("/abs/img"), null);
  assert.equal(normalizePath("https://example.com/img"), null);
});

test("under: 宣言の下なら残りを返し、外なら null", () => {
  assert.equal(under("./img/a.webp", "./img/"), "a.webp");
  assert.equal(under("img/sub/a.webp", "./img/"), "sub/a.webp");
  assert.equal(under("a.webp", "./"), "a.webp");
  assert.equal(under("./other/b.webp", "./img/"), null);
  assert.equal(under("./img/", "./img/"), null);
});
```

- [ ] **Step 2: 失敗を確認する**

```bash
pnpm test
```

Expected: FAIL。`Cannot find module '../src/app/head.ts'`。

- [ ] **Step 3: `src/app/head.ts` を書く**

```ts
// 文書の頭（YAML frontmatter）に置く設定。
//
// **宣言の持ち主は .md 自身**。以前は window.prompt で聞いて IndexedDB に
// 置いていたので、別マシンで開くと「その md の画像がどこにあるか」だけが
// 消えていた（実体はただの .md、と言い切っているのに）。
//
// ここは純関数だけ。DOM もコアも知らない。「どこからどこまでが頭か」は
// コアが答える（DocView.head）。ここが答えるのは、その中の 1 行の綴りだけ。
//
// **YAML パーサは入れない。** 読んで書き戻すと、他ツールが書いたコメント・
// 引用符・キーの順序が消える。「未編集行のバイト列は決して再整形されない」
// というコアの約束を、TS 側で破ることになる。読むのは 1 キー、書くのも 1 行。

import type { HeadSpan } from "../coreApi.ts";
import type { TextEdit } from "../edits.ts";
import { bare } from "../map/cards.ts";

/** 頭に置く「画像フォルダの場所」の設定名。**綴りはここ 1 つ** */
export const IMAGE_FOLDER = "image-folder";

// トップレベルのキーだけを見る。字下げされた `  image-folder:` は
// 別のキーの子なので、この文書の設定ではない
const KEY_LINE = new RegExp(`^${IMAGE_FOLDER}[ \\t]*:(.*)$`);

/** 中身の範囲。中身が無い頭では bodyTo が bodyFrom より手前にある */
const bodyEnd = (head: HeadSpan): number => Math.max(head.bodyFrom, head.bodyTo);

/** YAML の値 1 つ。囲まれていれば剥がし、裸なら ` #` から後ろを落とす。 */
function unquote(raw: string): string {
  const v = raw.trim();
  const q = v[0];
  if (v.length >= 2 && (q === '"' || q === "'") && v[v.length - 1] === q) {
    const inner = v.slice(1, -1);
    return q === '"' ? inner.replace(/\\(["\\])/g, "$1") : inner;
  }
  const hash = v.search(/\s#/);
  return (hash === -1 ? v : v.slice(0, hash)).trim();
}

/** 値を YAML の 1 行として書く形。囲む必要が無ければ裸で書く。 */
function quote(value: string): string {
  if (!/[\s#:]/.test(value)) return value;
  return `"${value.replace(/(["\\])/g, "\\$1")}"`;
}

/** 頭から画像フォルダの宣言を読む。無ければ null */
export function imageFolder(text: string, head: HeadSpan | null): string | null {
  if (!head) return null;
  for (const line of text.slice(head.bodyFrom, bodyEnd(head)).split("\n")) {
    const m = KEY_LINE.exec(line);
    if (m) return unquote(m[1]);
  }
  return null;
}

/**
 * 宣言を書き換える編集を 1 つ返す。3 つの場合がある。
 * - キーがある → **その行だけ**差し替える（他のキー・コメント・順序は不変）
 * - 頭はあるがキーが無い → 閉じ `---` の直前に 1 行足す
 * - 頭が無い → 文書の先頭に頭を作る
 */
export function setImageFolder(
  text: string,
  head: HeadSpan | null,
  value: string,
): TextEdit {
  const line = `${IMAGE_FOLDER}: ${quote(value)}`;
  if (!head) return { from: 0, to: 0, insert: `---\n${line}\n---\n\n` };
  let at = head.bodyFrom;
  for (const raw of text.slice(head.bodyFrom, bodyEnd(head)).split("\n")) {
    if (KEY_LINE.test(raw)) return { from: at, to: at + raw.length, insert: line };
    at += raw.length + 1;
  }
  // 中身の無い頭は、開きの次の行がそのまま閉じの行。1 行だけ入れる
  if (head.bodyTo < head.bodyFrom) {
    return { from: head.bodyFrom, to: head.bodyFrom, insert: `${line}\n` };
  }
  // 最後の中身の行末（改行の手前）。ここから改行込みで足せば閉じの手前に入る
  return { from: head.bodyTo, to: head.bodyTo, insert: `\n${line}` };
}

/**
 * 宣言の綴りを決める唯一の場所。末尾に `/` を足し、空と `.` は `./` にする。
 * 絶対パスと URL は md からの相対ではないので null（呼び出し側は何もしない）。
 */
export function normalizePath(value: string): string | null {
  let path = value.trim().replace(/\\/g, "/");
  if (path === "" || path === ".") path = "./";
  if (path.startsWith("/") || /^[a-z]+:\/\//i.test(path)) return null;
  return path.endsWith("/") ? path : `${path}/`;
}

/**
 * `path` が `folder` の下にあるなら、フォルダからの残りを返す。外なら null。
 *
 * 同じ場所を指す綴りが `./x` と `x` の 2 通りあるので、**必ず裸に寄せてから**
 * 比べる。md に書くのは `./x`、カード側が持つのは `x` と非対称なため、
 * どちらか片方だけを見ると既定の `./` で必ず外れる。
 */
export function under(path: string, folder: string): string | null {
  const prefix = bare(folder);
  const rest = bare(path);
  if (!rest.startsWith(prefix)) return null;
  const tail = rest.slice(prefix.length);
  return tail === "" ? null : tail;
}
```

- [ ] **Step 4: `src/map/cards.ts` の `bare` を唯一の定義にする**

`parseImage` の中に埋まっている `path.startsWith("./") ? path.slice(2)` を、
名前のある関数として外へ出す。`LINK_ROW` などの定数の手前に足す:

```ts
/**
 * 先頭の `./` を落とした形。`./x` と `x` は同じ場所を指すので、比べる前に
 * 必ずこの形へ寄せる。**カードが持つのも、画像の鍵になるのもこの形**
 * （md へ書き戻すときだけ `app/assets.ts` の `mdPath` が `./` を付け直す）。
 */
export const bare = (path: string): string => path.replace(/^\.\//, "");
```

`parseImage` の中の `if (path.startsWith("./")) path = path.slice(2);` を差し替える
（`scheme` の判定は**生の綴りに対して**行うので、順序は変えない）:

```ts
  path = bare(path);
```

- [ ] **Step 5: `src/app/assets.ts` から二重の定義を消す**

import 行の下に足す:

```ts
import { bare } from "../map/cards.ts";
import { normalizePath, under } from "./head.ts";
```

`bare` の定義（`src/app/assets.ts:20-21` の `const bare = …`）と `normalizePath` の定義（`src/app/assets.ts:76-82`）を削除する。

`assetTarget` を差し替える（前半の裸寄せを `under` に委ねる）:

```ts
/**
 * md に書かれたパスが、宣言した保存パスの下に収まるか。
 * 収まればフォルダからの相対を断片で返し、外れていれば null。
 *
 * 「その綴りは宣言の下か」の判定は app/head.ts の `under` が唯一の持ち主。
 * ここが足すのは、**フォルダの中として受け取ってよいか**の柵だけ。
 */
export function assetTarget(declared: string, path: string): string[] | null {
  const rest = under(path, declared);
  if (rest === null) return null;
  const parts = rest.split("/").filter(Boolean);
  if (parts.length === 0) return null;
  // フォルダの外へ出る綴りは受け取らない（宣言の外は見に行かない）
  if (parts.some((part) => part === "." || part === "..")) return null;
  // **絵でないものは読みに行かない。** `![](notes.txt)` と書けば、マップに
  // 何も出ないまま中身が読まれ、書き出した SVG に base64 で載ってしまう
  // （`<image>` は描けなくてもデータは埋まる）。宣言したフォルダの中に
  // 限られるとはいえ、絵を置く場所として渡したフォルダなので、絵だけ見る
  if (!imageType(parts[parts.length - 1] ?? "")) return null;
  return parts;
}
```

`saveToDisk` の中の `assetUrls.set(bare(rel), …)` は**そのまま**。`bare` の出所が
ローカル定義から `map/cards.ts` の import に変わるだけで、意味は変わらない。

- [ ] **Step 6: `README.md` の構成表に 1 行足す**

`src/` の `app/` の行、`assets(画像)` の手前に `head(文書の頭の設定)` を足す。差し替え後:

```
  app/         その子系統 — name(文書の名前) / persist(テーマと色) /
               theme(テーマ・ブランドカラー・ロゴ) / panes(ペイン) /
               head(文書の頭の設定。画像フォルダの場所はここが宣言) /
               assets(画像) / io(File System Access API の窓口) /
```

- [ ] **Step 7: テストと型が通ることを確認する**

```bash
pnpm test && pnpm run check
```

Expected: PASS。`test/assets.test.ts` の既存 8 本と `test/cards.test.ts` も変わらず通る（`assetTarget` も `parseImage` も振る舞いは同じ）。

- [ ] **Step 8: コミット**

```bash
git add src/app/head.ts src/app/assets.ts src/map/cards.ts test/head.test.ts README.md
git commit -m "feat: ✨ 文書の頭に画像フォルダの場所を書けるようにする"
```

---

## Task 4: 本文の追従 — `parseImage` が位置を返し、`retarget` が編集を組む

**Files:**
- Modify: `src/map/cards.ts:113-131`（`parseImage`）
- Modify: `src/app/head.ts`（`retarget` を追記）
- Test: `test/head.test.ts`（追記）、`test/cards.test.ts`（`parseImage` の位置）

**Interfaces:**
- Consumes: Task 3 の `under`、Task 2 の `DocView`
- Produces:
  - `src/map/cards.ts`: `export interface ImageRef { path: string; name: string; raw: string; from: number; to: number }`、`parseImage(line: string): ImageRef | null`
  - `src/app/head.ts`: `retarget(doc: DocView, from: string, to: string): TextEdit[]`（文書順。**後ろから**適用する）

- [ ] **Step 1: 失敗するテストを書く**

`test/head.test.ts` の import に足す:

```ts
import { retarget } from "../src/app/head.ts";
import { parseImage } from "../src/map/cards.ts";
```

`test/head.test.ts` の末尾に足す:

```ts
/** retarget の結果を後ろから当てて、書き換え後のテキストを返す小道具 */
function moved(md: string, from: string, to: string): string {
  const doc = loadDoc(md);
  const edits = retarget(doc, from, to);
  let out = doc.text;
  for (let i = edits.length - 1; i >= 0; i--) {
    const e = edits[i];
    out = out.slice(0, e.from) + e.insert + out.slice(e.to);
  }
  return out;
}

test("parseImage: 行内の destination の位置を返す", () => {
  const img = parseImage("![alt](./img/a.webp)");
  assert.ok(img);
  assert.equal(img.raw, "./img/a.webp");
  assert.equal("![alt](./img/a.webp)".slice(img.from, img.to), "./img/a.webp");
  assert.equal(img.path, "img/a.webp");
  assert.equal(img.name, "a.webp");
});

test("parseImage: 字下げされた行でも位置が合う", () => {
  const line = "  ![](<./my img/a.webp>)";
  const img = parseImage(line);
  assert.ok(img);
  assert.equal(line.slice(img.from, img.to), "./my img/a.webp");
});

test("retarget: 宣言の下だけ接頭辞を差し替える", () => {
  const md = "# r\n\n![](./img/a.webp)\n\n![](./img/sub/b.png)\n";
  assert.equal(
    moved(md, "./img/", "./assets/"),
    "# r\n\n![](./assets/a.webp)\n\n![](./assets/sub/b.png)\n",
  );
});

test("retarget: 宣言の外は触らない", () => {
  const md = "# r\n\n![](./img/a.webp)\n\n![](./other/b.webp)\n";
  assert.equal(
    moved(md, "./img/", "./assets/"),
    "# r\n\n![](./assets/a.webp)\n\n![](./other/b.webp)\n",
  );
});

test("retarget: 外部 URL は触らない", () => {
  const md = "# r\n\n![](https://example.com/a.png)\n\n![](data:image/png;base64,AA)\n";
  assert.equal(moved(md, "./", "./img/"), md);
});

test("retarget: フェンスの中は触らない", () => {
  const md = "# r\n\n```md\n![](./img/a.webp)\n```\n\n![](./img/b.webp)\n";
  assert.equal(
    moved(md, "./img/", "./assets/"),
    "# r\n\n```md\n![](./img/a.webp)\n```\n\n![](./assets/b.webp)\n",
  );
});

test("retarget: 頭の中は触らない", () => {
  // 頭の 2 行目は YAML として意味を持たないが、**画像リンクとして完全に成立
  // した行**でないと「区間ごと飛ばしている」ことの証明にならない（頭の外に
  // 同じ行があれば必ず書き換わる、というのが下の比較の意味）
  const md = "---\n![](./img/a.webp)\n---\n\n![](./img/b.webp)\n";
  assert.equal(
    moved(md, "./img/", "./assets/"),
    "---\n![](./img/a.webp)\n---\n\n![](./assets/b.webp)\n",
  );
});

test("retarget: 裸の綴りも `./` 付きも同じ場所として動かす", () => {
  const md = "# r\n\n![](img/a.webp)\n";
  assert.equal(moved(md, "./img/", "./assets/"), "# r\n\n![](./assets/a.webp)\n");
});

test("retarget: 同じ宣言なら編集は 0 件", () => {
  const doc = loadDoc("# r\n\n![](./img/a.webp)\n");
  assert.deepEqual(retarget(doc, "./img/", "./img/"), []);
});

test("retarget: 返す編集は文書順で、範囲が重ならない", () => {
  const doc = loadDoc("# r\n\n![](./img/a.webp)\n\n![](./img/b.webp)\n");
  const edits = retarget(doc, "./img/", "./assets/");
  assert.equal(edits.length, 2);
  assert.ok(edits[0].to <= edits[1].from);
});
```

`test/cards.test.ts` の末尾に足す（カード側の契約が変わらないことの固定）:

```ts
test("parseImage: 位置が増えても path/name の意味は変わらない", () => {
  const img = parseImage("![](sub/a.PNG)");
  assert.ok(img);
  assert.equal(img.path, "sub/a.PNG");
  assert.equal(img.name, "a.PNG");
  assert.equal(parseImage("![](https://example.com/a.png)"), null);
  assert.equal(parseImage("just text"), null);
});
```

`test/cards.test.ts` の import 行に `parseImage` を足す:

```ts
import { cardRows, contentEnd, linkLine, parseImage } from "../src/map/cards.ts";
```

- [ ] **Step 2: 失敗を確認する**

```bash
pnpm test
```

Expected: FAIL。`retarget` が export されておらず、`parseImage` の戻り値に `raw` / `from` / `to` が無い。

- [ ] **Step 3: `src/map/cards.ts` の `parseImage` を広げる**

`parseImage` の定義（`src/map/cards.ts:113-131`）を差し替える:

```ts
/** 1 行から読み取った、ローカル画像の指し方。 */
export interface ImageRef {
  /** 先頭の `./` を落とした形。カードの鍵になる */
  path: string;
  /** 拡張子込みのファイル名 */
  name: string;
  /** md に書かれているままの綴り */
  raw: string;
  /** 行頭から見た `raw` の範囲。`line.slice(from, to)` が `raw` になる */
  from: number;
  to: number;
}

// `d` フラグは捕獲の位置を返させるため。宣言フォルダの引っ越しで
// **destination だけ**を差し替えるのに要る（app/head.ts の retarget）
const IMG_LINE = /^!\[[^\]]*\]\((?:<([^>]+)>|([^)\s]+))\)$/d;

/** Content line of the form `![alt](path)` with a LOCAL (relative) path.
 * External images (http/data URLs) are ignored — no external traffic.
 * `<path with space>` is CommonMark's escape for a destination containing
 * whitespace, so only the unescaped form forbids spaces. */
export function parseImage(line: string): ImageRef | null {
  const lead = line.length - line.trimStart().length;
  const m = IMG_LINE.exec(line.trim());
  if (!m) return null;
  const raw = m[1] ?? m[2];
  // A real URI scheme (http:, data:, ...) is always 2+ letters before the
  // colon; a single letter is a Windows drive (`C:\...`), which is a local
  // path, not an external one.
  const scheme = /^([a-z][a-z0-9+.-]*):/i.exec(raw);
  if (scheme && scheme[1].length > 1) return null;
  // 位置は捕獲した組の側にある。`<…>` で囲まれていれば 1、裸なら 2
  const span = m.indices?.[1] ?? m.indices?.[2];
  if (!span) return null;
  const path = bare(raw);
  if (path === "") return null;
  // Windows のパスは `\` 区切りでも来る（ドライブレターや `..\..\x.png`）
  // split は必ず 1 つ以上返すが、型は言い切らないので素直に受ける
  const name = path.split(/[\\/]/).pop() ?? path;
  return { path, name, raw, from: lead + span[0], to: lead + span[1] };
}
```

- [ ] **Step 4: `src/app/head.ts` に `retarget` を足す**

import を差し替える（Task 3 で入れた `bare` を落とさないこと — `under` が使っている）:

```ts
import type { DocView, HeadSpan } from "../coreApi.ts";
import type { TextEdit } from "../edits.ts";
import { bare, parseImage } from "../map/cards.ts";
```

ファイル末尾に足す:

```ts
/**
 * 宣言フォルダの引っ越しに、本文の画像リンクを追従させる。
 *
 * 対象は「**いま宣言しているフォルダの下にある**画像リンク」だけ。`./img/`
 * から動かすなら `./other/b.webp` は動かない。宣言が `./` のときだけ全部が
 * 対象になるが、それは「画像は md と同じ場所にある」と宣言している状態
 * なので、意味のとおり。
 *
 * 頭とフェンスの中は見ない（どちらも区間はコアが答える）。外部 URL は
 * `parseImage` が弾く。
 *
 * 返す編集は文書順。**後ろから**適用すること — 前から当てると、後続の
 * オフセットが挿入ぶんだけずれる。
 */
export function retarget(doc: DocView, from: string, to: string): TextEdit[] {
  const out: TextEdit[] = [];
  if (from === to) return out;
  const inSkipped = (at: number): boolean =>
    (doc.head !== null && at >= doc.head.from && at < doc.head.to) ||
    doc.fences.some((f) => at >= f.from && at < f.to);
  let at = 0;
  for (const line of doc.text.split("\n")) {
    const start = at;
    at += line.length + 1;
    if (inSkipped(start)) continue;
    const img = parseImage(line);
    if (!img) continue;
    const rest = under(img.raw, from);
    if (rest === null) continue;
    out.push({ from: start + img.from, to: start + img.to, insert: `${to}${rest}` });
  }
  return out;
}
```

- [ ] **Step 5: テストと型が通ることを確認する**

```bash
pnpm test && pnpm run check
```

Expected: PASS。`test/cards.test.ts` の既存テストも変わらず通る。

- [ ] **Step 6: コミット**

```bash
git add src/map/cards.ts src/app/head.ts test/head.test.ts test/cards.test.ts
git commit -m "feat: ✨ 宣言フォルダの引っ越しに本文の画像パスを追従させる"
```

---

## Task 5: 宣言の持ち主を頭にする（`prompt` を消す）

**Files:**
- Modify: `src/app/handles.ts:9-13`（`AssetBinding`）、`src/app/handles.ts:73-83`（`isBinding`）
- Modify: `src/app/assets.ts`（`initAssets` の deps、`selectBinding`、`loadAsset`、`saveToDisk`）
- Modify: `src/main.ts:708-712`（`initAssets` の呼び出し）、`src/main.ts:757`（Files メニューの caption）
- Test: `test/assets.test.ts`（追記）

**Interfaces:**
- Consumes: Task 3 の `imageFolder` / `normalizePath`
- Produces:
  - `src/app/handles.ts`: `interface AssetBinding { doc: FileSystemFileHandle; directory: FileSystemDirectoryHandle }`
  - `src/app/assets.ts`: `export function folderFromDoc(segments: string[]): string`
  - `src/app/assets.ts`: `initAssets(deps: { hasFile: () => boolean; warn: (msg: string) => void; refresh: () => void; declared: () => string | null; declare: (value: string) => void }): Assets`

- [ ] **Step 1: 失敗するテストを書く**

`test/assets.test.ts` の import に足し、末尾に足す:

```ts
import { assetTarget, folderFromDoc, imageType, mdPath } from "../src/app/assets.ts";

// `directory.resolve(md)` が返すのは「フォルダ → md」の断片。md から見た
// フォルダはその逆なので、**末尾のファイル名を除いた数**だけ上へ戻る。
test("folderFromDoc: md がフォルダ直下なら ./", () => {
  assert.equal(folderFromDoc(["a.md"]), "./");
});

test("folderFromDoc: md が 1 段深ければ ../", () => {
  assert.equal(folderFromDoc(["notes", "a.md"]), "../");
  assert.equal(folderFromDoc(["a", "b", "c.md"]), "../../");
});

test("folderFromDoc: 断片が空でも ./ に倒す", () => {
  assert.equal(folderFromDoc([]), "./");
});
```

- [ ] **Step 2: 失敗を確認する**

```bash
pnpm test
```

Expected: FAIL。`folderFromDoc` が export されていない。

- [ ] **Step 3: `src/app/handles.ts` から `path` を落とす**

`AssetBinding` を差し替える:

```ts
/**
 * 画像フォルダの結び付け。**持つのは許可だけ** — 「md から見てどこか」は
 * .md の頭が宣言する（app/head.ts）。以前はここが `path` も持っていて、
 * 別マシンで開くと宣言ごと消えていた。
 */
export interface AssetBinding {
  doc: FileSystemFileHandle;
  directory: FileSystemDirectoryHandle;
}
```

`isBinding` から `path` の検査を落とす（古いレコードは余分な `path` を持ったまま読める）:

```ts
const isBinding = (v: unknown): v is AssetBinding =>
  typeof v === "object" &&
  v !== null &&
  "doc" in v &&
  v.doc instanceof FileSystemFileHandle &&
  "directory" in v &&
  v.directory instanceof FileSystemDirectoryHandle;
```

- [ ] **Step 4: `src/app/assets.ts` を宣言の受け手にする**

ファイル先頭のコメントを差し替える:

```ts
// Markdown からの相対パスで画像を読み書きする。
//
// **宣言（md から見てどこか）は .md の頭が持ち、許可（そのフォルダを読み書き
// してよい）だけをここが持つ。** ブラウザはパス文字列からフォルダハンドルを
// 作れないので、2 つに分かれること自体は避けられない — どちらが何の真実かを
// 言い切ることで、食い違いを事故にしない。
```

`folderFromDoc` を `mdPath` の次に足す:

```ts
/**
 * 選んだフォルダから md までの断片を、md から見たフォルダの相対に読み替える。
 * `FileSystemDirectoryHandle.resolve` が返すのは「フォルダ → md」なので、
 * **末尾のファイル名を除いた数**だけ上へ戻る（`["notes","a.md"]` なら md は
 * 1 段深いところに居るので `../`）。
 */
export function folderFromDoc(segments: string[]): string {
  const up = Math.max(0, segments.length - 1);
  return up === 0 ? "./" : "../".repeat(up);
}
```

`normalizePath` を import から落とす（下で `selectBinding` を書き直すと、
assets.ts に使い手がいなくなる。宣言の正規化は `main.ts` の `declaredFolder` が
持つ。`noUnusedLocals` が付いているので、残すと型チェックが落ちる）:

```ts
import { under } from "./head.ts";
```

`initAssets` のシグネチャを差し替える:

```ts
export function initAssets(deps: {
  hasFile: () => boolean;
  warn: (msg: string) => void;
  refresh: () => void;
  /** いま頭が言っている宣言（正規化済み）。無ければ null */
  declared: () => string | null;
  /** 頭に宣言を書き込む */
  declare: (value: string) => void;
}): Assets {
```

`initAssets` の中、`const assetUrls = …` の手前に足す:

```ts
  // 宣言が無いのは「md と同じ場所」— prompt の既定値がずっと `./` だった
  // のと同じ意味。頭を持たない古い文書がそのまま読めるように、ここで倒す
  const declaredPath = (): string => deps.declared() ?? "./";
```

`selectBinding` を差し替える（`prompt` が消え、宣言が無いときだけ書き込む）:

```ts
  async function selectBinding(): Promise<AssetBinding | null> {
    const file = io.currentFile();
    if (!file) return null;
    let directory: FileSystemDirectoryHandle;
    try {
      directory = await window.showDirectoryPicker({ startIn: file, mode: "readwrite" });
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") return null;
      throw error;
    }
    // 宣言はもう頭が持つ。まだ何も言っていない文書にだけ、ここで書き込む。
    // md がそのフォルダの中に居れば正確に逆算でき、居なければ md の隣に
    // 置いた `img/` という、いちばん普通の形を書く
    if (deps.declared() === null) {
      const segments = await directory.resolve(file);
      deps.declare(segments ? folderFromDoc(segments) : `./${directory.name}/`);
    }
    const binding = { doc: file, directory };
    await handles.saveAssets(binding);
    cachedBinding = binding;
    releaseUrls();
    deps.refresh();
    return binding;
  }
```

`loadAsset` の中の `assetTarget(binding.path, path)` を差し替える:

```ts
      const parts = assetTarget(declaredPath(), path);
```

`saveToDisk` の中の `const rel = \`${binding.path}${parts.join("/")}\`;` を差し替える:

```ts
        const rel = `${declaredPath()}${parts.join("/")}`;
```

- [ ] **Step 5: `src/main.ts` を繋ぐ**

**app state の並び**（`src/main.ts` の `let drawingOpen = false;` の次、`// ---------- sync ----------` の手前）に足す。**`initAssets` の隣ではない** — 次の Task で `applySnap` がここの値を読むので、モジュールの評価順で先に居る必要がある（`applySnap` は起動時の読み込みで走る）:

```ts
// ---------- 画像フォルダの宣言（文書の頭） ----------
//
// 宣言の持ち主は .md の頭（app/head.ts）。ここは「頭が何を言っているか」を
// 一言で引ける場所。実際の読み書きは app/assets.ts が持つ。

/** いま頭が言っている宣言。読めない綴り（絶対パス・URL）なら null */
function declaredFolder(): string | null {
  const raw = imageFolder(doc.text, doc.head);
  return raw === null ? null : normalizePath(raw);
}
```

`initAssets` の呼び出し（`src/main.ts:708-712`）を差し替える:

```ts
const assets = initAssets({
  hasFile: () => savedName !== null,
  warn: (m) => flashFilename(m),
  refresh: () => map.render(),
  declared: () => declaredFolder(),
  declare: (value) => {
    const e = setImageFolder(doc.text, doc.head, value);
    applySnap(core.replaceText(e.from, e.to, e.insert, nextTag()), "core");
  },
});
```

`src/main.ts` の import に足す:

```ts
import { imageFolder, normalizePath, setImageFolder } from "./app/head.ts";
```

Files メニューの caption（`src/main.ts:757`）を差し替える。宣言と許可が食い違っている — 頭は言っているのにフォルダを結んでいない — ことが、そこだけで分かるように:

```ts
  {
    caption:
      assets.folderName() ??
      (declaredFolder() === null ? "none" : "folder not linked"),
  },
```

- [ ] **Step 6: テストと型が通ることを確認する**

```bash
pnpm test && pnpm run check
```

Expected: PASS。

- [ ] **Step 7: コミット**

```bash
git add src/app/handles.ts src/app/assets.ts src/main.ts test/assets.test.ts
git commit -m "feat: ✨ 画像フォルダの宣言を .md の頭に移す"
```

---

## Task 6: 追従を発火させる（入力が止まったら 1 回）

**Files:**
- Modify: `src/main.ts`（`declaredFolder` の周り、`applySnap`、`loadText`）
- Test: 手で確かめる（下の Step 5）。純粋な部分は Task 4 の `retarget` が既に押さえている

**Interfaces:**
- Consumes: Task 4 の `retarget`、Task 5 の `declaredFolder` / `assets`
- Produces: なし（main.ts の中で閉じる）

- [ ] **Step 1: 追従の係を書く**

`src/main.ts` の `declaredFolder` の定義の直後（Task 5 で作った「画像フォルダの宣言」の節の中）に足す。**`applySnap` より手前に居ること** — `appliedFolder` は `let` なので、`applySnap` が先に評価されると初期化前アクセスで落ちる:

```ts
// 頭の宣言が変わったら、本文の画像パスをそれに追従させる。
//
// **打鍵のたびには走らせない。** 消して打ち直す途中の中途半端な値をすべて
// 経由すると、宣言が一瞬 `./` に落ちた隙にフォルダの外の画像まで巻き込む。
// 入力が止まってから 1 回だけ当てる（Undo も 1 回で全部戻る）。

const FOLLOW_MS = 400;

/** 本文がいま映している宣言。文書を開いた時点の値から始まる */
let appliedFolder: string | null = null;
let followTimer = -1;

function cancelFollow(): void {
  if (followTimer === -1) return;
  window.clearTimeout(followTimer);
  followTimer = -1;
}

/**
 * 宣言の引っ越しに本文を追従させ、フォルダを結び直す。
 *
 * ここが触る `assets` / `nextTag` はこの下で作られるが、呼ばれるのは
 * タイマーが落ちたとき＝モジュールを読み終えた後なので届く。
 */
function followDeclaration(): void {
  const next = declaredFolder();
  if (next === null) return; // 読めない綴りでは何もしない
  const prev = appliedFolder;
  // **当てる前に進める。** 下の replaceText が applySnap を呼び返すので、
  // ここが古いままだと自分の書き換えを見てもう一度予約してしまう
  appliedFolder = next;
  if (prev !== null && prev !== next) {
    const edits = retarget(doc, prev, next);
    const tag = nextTag();
    // 後ろから。前から当てると後続のオフセットが挿入ぶんだけずれる
    for (let i = edits.length - 1; i >= 0; i--) {
      const e = edits[i];
      applySnap(core.replaceText(e.from, e.to, e.insert, tag), "core");
    }
  }
  assets.clear(); // 宣言が変わった。画像を読み直す
}
```

`src/main.ts` の import に足す:

```ts
import { imageFolder, normalizePath, retarget, setImageFolder } from "./app/head.ts";
```

（Task 5 で足した import 行に `retarget` を加える）

- [ ] **Step 2: `applySnap` から予約する**

`applySnap` の末尾、`if (wasEmpty && doc.nodes.length > 0) map.fitView();` の手前に足す:

```ts
  // 文書ごと入れ替わったなら、本文はもうその宣言を映している（追従は不要）
  if (origin === "load") {
    cancelFollow();
    appliedFolder = declaredFolder();
  } else if (declaredFolder() !== appliedFolder) {
    cancelFollow();
    followTimer = window.setTimeout(() => {
      followTimer = -1;
      followDeclaration();
    }, FOLLOW_MS);
  }
```

`declare` は書き込んだ直後にこの経路を通る。`appliedFolder` は書き込む前の値のままなので、**頭に初めて宣言を書いた場合は `prev === null` で本文を触らない**（どこから動かすか分からないため）。既に宣言があるところへ `declare` は走らない（`selectBinding` が `deps.declared() === null` のときだけ呼ぶ）。

- [ ] **Step 3: 型が通ることを確認する**

```bash
pnpm run check
```

Expected: PASS。

- [ ] **Step 4: 既存のテストが壊れていないことを確認する**

```bash
pnpm run test:core && pnpm test
```

Expected: PASS。

- [ ] **Step 5: 実機で確かめる**

```bash
pnpm run dev
```

ブラウザ（Chromium 系）で `http://localhost:13131` を開き、順に確かめる:

1. 適当な .md を新規保存し、Files → Images Folder でフォルダを選ぶ。**パスを聞くダイアログが出ない**こと、md の頭に `---\nimage-folder: …\n---` が書かれることを見る
2. 画像をドロップして `![](./…/x.webp)` が入り、マップにサムネイルが出ることを見る
3. md ペインで `image-folder` の値を書き換え、手を止める。**本文の `![]()` が追従して書き換わる**ことを見る
4. `Mod+Z` を 1 回押して、**書き換えが全部戻る**ことを見る
5. `tags:\n  - a` を頭に足して、**マップにノードが増えない**ことを見る

- [ ] **Step 6: コミット**

```bash
git add src/main.ts
git commit -m "feat: ✨ 頭の宣言が止まったら本文を追従させる"
```

---

## Self-Review

**Spec coverage:**

| spec の節 | Task |
|---|---|
| 頭 — 先頭の `---` … `---` | 1 |
| 設定の名前 — `image-folder` | 3 |
| 誰が何の真実を持つか | 5 |
| core の変更（parser / api / 貼り付けへの副産物） | 1 |
| `src/app/head.ts` | 3, 4 |
| 値の引用符 | 3 |
| `parseImage` が位置も返す | 4 |
| 本文の一括書き換え・巻き込みの柵 | 4 |
| 発火 — 入力が止まったら 1 回 | 6 |
| 入口 — メニューは許可だけ | 5 |
| テスト | 1, 3, 4, 5 |
| 移行（`isBinding` / README） | 3, 5 |
