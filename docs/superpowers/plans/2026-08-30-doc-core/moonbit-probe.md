## 1. `pub typealias X = Array[Int]` — **通らない。正しい綴りは `pub type X = Array[Int]`**

```
$ moon -C <scratchpad>/probe2 check
```
```
Warning: [0027]
 2 │ pub typealias Ints = Array[Int]
   │                ╰───────────────── Warning (deprecated_syntax): The syntax `typealias Type as Alias` for creating type alias is deprecated. Use `type Alias = Type` instead.
Error: [4032]
 2 │ pub typealias Ints = Array[Int]
   │                 ╰─── The type Ints is undefined.
Error: [3002]
 2 │ pub typealias Ints = Array[Int]
   │                    ╰── Parse error, unexpected token `=`, you may expect `as`.
Error: [4032]
 5 │ pub fn sum(xs : Ints) -> Int {
   │                   ╰─── The type Ints is undefined.
Failed with 1 warnings, 3 errors.
Error: failed when checking project
```

正しい形（`moon check` → `Finished. moon: ran 2 tasks, now up to date`、`moon test` → `Total tests: 1, passed: 1, failed: 0.`）:

```moonbit
///|
pub type Ints = Array[Int]
```

透過であることも実測（`sum([1, 2, 3]) == 6` が通る＝`Array[Int]` リテラルをそのまま渡せる。ラッパ型ではなく別名）。

旧形 `pub typealias Array[Int] as Ints`（**型が後・別名が先・`as`**）も *コンパイルは通る* が deprecated 警告つき:

```
Warning: [0027] Warning (deprecated_syntax): The syntax `typealias Type as Alias` for creating type alias is deprecated. Use `type Alias = Type` instead.
Finished. moon: ran 3 tasks, now up to date (3 warnings, 0 errors)
```

→ **契約の `typealias` は誤り。T5 の申し送り（`pub type` に直せ）が正しい。**

---

## 2. 同一パッケージの複数 `*_wbtest.mbt` — **名前空間は共有する。同名定義は再定義エラー**

`lib/a_wbtest.mbt` に `fn helper_a`、`lib/b_wbtest.mbt` からそれを呼ぶ:

```
$ moon -C <scratchpad>/probe2 test
Total tests: 3, passed: 3, failed: 0.
```

`b_wbtest.mbt` にも同名 `fn helper_a` を置くと:

```
Error: [4051]
 3 │ fn helper_a(n : Int) -> Int {
   │        ╰───── The toplevel identifier helper_a is declared twice: it was previously defined at ...\lib\b_wbtest.mbt:3:4.
Warning: [0001]
 3 │ fn helper_a(n : Int) -> Int {
   │        ╰───── Warning (unused_value): Unused function 'helper_a'
```
exit 1。

→ **wbtest ファイルを機能ごとに割るなら、ヘルパ名（`tree_sig` / `sides_of` 等）は全 wbtest 横断で一意にしなければならない。** 既存 repo が `tree_sig`（list）と `sides_of`（seps）を別名にしているのは偶然ではなく必然。

---

## 3. 別パッケージからの `pub struct` — **読めるが作れない。構築には `pub(all)` が要る**

実験配置: `probe2/lib`（library, 定義側）/ `probe2/user`（library, 読む側）/ `probe2/ffi`（foreign_library, 読む側）。

**(a) フィールド読み — `pub` で通る**
```moonbit
let p = @lib.make_plain()   // pub struct Plain { a : Int; b : String }
assert_eq(p.a, 1)
assert_eq(p.b, "x")
```
```
Total tests: 2, passed: 2, failed: 0.
```

**(b) 構築 — `pub` だけでは不可**
```moonbit
let p : @lib.Plain = { a: 3, b: "z" }
```
```
Error: [4036]
 3 │   let p : @lib.Plain = { a: 3, b: "z" }
   │                                ╰───────── Cannot create values of the read-only type: @probe2/lib.Plain.
Error: [4033]
   │                                ╰───────── There is no record definition with the fields: a, b.
```

**(c) `pub(all)` なら構築できる**
```moonbit
let w : @lib.Wide = { a: 3, b: "z" }   // pub(all) struct Wide
```
```
Total tests: 2, passed: 2, failed: 0.
```

**(d) `mut` フィールドへの書き込み — `pub` では不可**
```
Error: [4094]
 4 │   p.n = 5
   │      ╰───── Cannot modify a read-only field: n
```

**(e) 併せて踏んだ罠**: `pub struct` の `mut` フィールドを **定義パッケージ内で一度も書かない**と、別パッケージで書いていても

```
Error: [0015]
39 │   mut n : Int
   │       ╰── Error Warning (unused_mut): The mutability of field 'n' is never used, try remove `mut`.
```
となりビルドが止まる（`unused_mut` の判定はパッケージ単位）。

**(f) foreign_library から** — `probe2/ffi`（`pkgtype(kind: "foreign_library")` + `import { "probe2/lib" @lib, }`）でも規則は同じ。`pub` の読みも `pub(all)` の構築も通り、`moon build --target js --release` は成功、`_build/js/release/build/ffi/ffi.js` に

```js
export { _M0FP26probe23ffi11read__plain as readPlain, _M0FP26probe23ffi10make__wide as makeWide }
```

**(g) enum も同じ規則**（設計 §2 の `Block = Content(...) | Opaque(text)` に直結）:
- `pub enum` — 別パッケージから **`match` はできる**（`Content(t) => …` / `Opaque(text~) => …`、15/15 pass）
- `pub enum` — 別パッケージから **構築はできない**:
  ```
  Error: [4036]
   3 │   let b : @lib.Blk = @lib.Opaque(text="o")
     │                           ╰─────── Cannot create values of the read-only type: Opaque.
  ```
- `pub(all) enum` に変えると通る（`Total tests: 1, passed: 1, failed: 0.`）

---

## 4. ラベル付き enum ペイロードの呼び出し側 — **`Image(alt="a", src="b")` が正。`~=` は構文エラー**

定義側は `~` を使う（`Image(alt~ : String, src~ : String)`）、`match` 側も `~`（`Image(alt~, src~) => …`）。**呼び出し側だけ `=`**。

```
$ moon test   # Image(alt="a", src="b")
Total tests: 3, passed: 3, failed: 0.
```

```
$ moon test   # Image(alt~="a", src~="b")
Error: [3016]
17 │   assert_eq(render(Image(alt~="a", src~="b")), "![a](b)")
   │                            ╰─── The syntax `alt~=..` for supplying labelled argument is invalid, the correct syntax is `alt=..`.
Error: [3016]
   │                                      ╰─── The syntax `src~=..` for supplying labelled argument is invalid, the correct syntax is `src=..`.
```
exit 1。

---

## 5. 未定義の値のエラー文言 — **契約 / T2 が正しい。T5 は誤り**

```moonbit
fn caller() -> Int { missing_helper(1) }
```
```
Error: [4021]
 3 │   missing_helper(1)
   │          ╰──────── The value identifier missing_helper is unbound.
Error: failed when checking project
```

テスト本文でも同じ（`assert_eq(no_such_fn(5), 15)` → `Error: [4021]` / `The value identifier no_such_fn is unbound.`）。

- **正確な形式**: `Error: [4021]` が 1 行目、本文 `The value identifier X is unbound.` は診断枠の中。契約 / T2 の `Error: The value identifier X is unbound.` は**文面は合っているが、コード `[4021]` が抜けており「`Error:` の直後に文が続く」形ではない**。
- **T5 の `Error [4014] The value X is undefined.` は二重に誤り**:
  - `[4014]` は実際には **`Expr Type Mismatch`**（実測: `let c : Char = s[1]` → `Error: [4014] Expr Type Mismatch / has type : UInt16 / wanted : Char`）
  - `is undefined.` は**型**側の文言（`[4032] The type Ints is undefined.`）
- 参考: パッケージ別名の誤りは `Error: [4020] Package "nosuchpkg" not found in the loaded packages.`

---

## 6. 論理否定 — **両方通る。`not(x)` は deprecated、`!x` が正**

```
$ moon test   # assert_eq(not(t), false)
Warning: [0020]
 4 │   assert_eq(not(t), false)
   │              ╰─── Warning (deprecated): Use !expr instead
Total tests: 3, passed: 3, failed: 0.
```
```
$ moon test   # assert_eq(!t, false)
Total tests: 3, passed: 3, failed: 0.
```

---

## 7. コマンドの実地確定

すべて `--target-dir` を scratchpad へ逃がして実行。**doc-model リポジトリは 1 バイトも変更していない**（末尾に確認結果）。

### 7-1. `moon -C core test -p <package>` — 動く。ただし致命的な罠が 2 つ

```
$ moon -C <repo>/core test -p mmm-app/core --target-dir <scratch>/o1
Total tests: 192, passed: 192, failed: 0.        EXIT=0
```

**罠 A: `-p` の綴りを間違えても exit 0 で「成功」する。**
```
$ moon -C <repo>/core test -p mmm-app/core/doc --target-dir <scratch>/o1
Warning: package `mmm-app/core/doc` not found, make sure you have spelled it correctly, e.g. `moonbitlang/core/hashmap`(exact match) or `hashmap`(fuzzy match)
Warning: no test entry found.
Total tests: 0, passed: 0, failed: 0.            EXIT=0
```
→ 新パッケージのテストコマンドを CI に足すとき、**綴り間違いは黙って緑になる**。`Total tests: 0` を検知する仕掛けが要る。

**罠 B: `-p` を省いた `moon test` は、この repo では**必ず失敗**する。**
```
$ moon -C <repo>/core test --target-dir <scratch>/o3
Error: [4219]
166 │ #export_name("hasHeadings")
    │              ╰─────────────── #export_name "hasHeadings" can only be used in a foreign library. Add `pkgtype(kind: "foreign_library")` to the package's moon.pkg.
Error: [4219]
172 │ #export_name("relevelText")
    │              ╰─────────────── ...
EXIT=1
```
`core/js/moon.pkg` は正しく `foreign_library` なのに、`moon test` はこれを別扱いでビルドしようとして落ちる（scratchpad の使い捨てモジュールでも同じ挙動を再現）。`package.json` の `test:core` が `-p mmm-app/core` を付けているのはこのため。
一方 **`moon check`（`-p` 無し）は通る**: `Finished. moon: ran 5 tasks, now up to date` EXIT=0。

**複数パッケージ指定は `-p` を並べる**（実測 15 test、EXIT=0）:
```
moon -C core test -p mmm-app/core -p mmm-app/core/<新パッケージ>
```

その他確認済み: `-p` は**短縮名でも当たる**（`-p lib` で `probe2/lib` にヒット）／`moon test <ディレクトリ>` のパス指定も等価に動く／`-f "Array:*"` のグロブ絞り込みは動く（5 test）。
**`moon check` に `-p` は無い**（PATH を取る）:
```
$ moon check -p probe2/lib
Error: Failed to calculate build plan
Caused by:
    0: Failed to canonicalize input filter directory `...\probe2\probe2/lib`
    1: 指定されたパスが見つかりません。 (os error 3)
```
→ 型検査だけを新パッケージに絞るなら `moon -C core check doc`（パス）。

### 7-2. `moon fmt` 系 — 3 形とも動く。exit code は **0 / 127**

| 綴り | 結果 |
|---|---|
| `moon -C <mod> fmt --check <パッケージディレクトリ>` | 動く。差分なし → `Finished. moon: ran 6 tasks, now up to date` EXIT=0 |
| `moon -C <mod> fmt --check <絶対パスの .mbt>` | 動く（同上の判定） |
| `moon -C <mod> fmt <絶対パスの .mbt>` | 動く。**その場で書き換わる** → `Finished. moon: ran 6 tasks, now up to date` EXIT=0 |

差分があるときの出力（逐語、末尾）:
```
failed to execute `git --no-pager diff --color=always --no-index <src> <targetdir>\wasm-gc\release\format\...`
Failed with 0 warnings, 0 errors.
Error: failed when formatting project
```
**EXIT=127**（0 ではない。ただし 1 でもない）。差分そのものは `git diff` の色付き出力として本文に出る。

注意点 2 つ:
- `moon fmt` は **`preferred_target = "js"` を無視して `<target-dir>/wasm-gc/release/format/` に整形結果を書く**。
- **`moon fmt` は `moon.pkg` も整形対象**。既存 `core/js/moon.pkg` は落ちる:
  ```
  @@ -1,5 +1,5 @@
   import {
  -  "mmm-app/core" @core,
  +  "mmm-app/core",
   }
  ```
  （別名が最終パスセグメントと同じなら剥がす。新パッケージの `moon.pkg` を `"mmm-app/core/doc" @doc,` と書くと同じく剥がされる。）
  `core/js/exports.mbt` も 1 箇所落ちる（`pub fn replace_text(from : Int, to : Int, insert : String, tag : String) -> String {` の 4 引数を縦に割る）。
  → **`moon -C core fmt --check js` は現状 EXIT=127。** 新パッケージだけを対象にする運用は成立するが、`js` を巻き込むと即座に赤になる。

### 7-3. `moon test` の出力形式

- 成功: 最終行 1 行だけ `Total tests: 15, passed: 15, failed: 0.` EXIT=0
- 失敗: 1 件ごとに
  ```
  [probe2] test lib/str_wbtest.mbt:65 ("String: s[0:2] はサロゲート途中なので落ちる") failed: Error
      at $panic (...\_build\js\debug\test\lib\lib.whitebox_test.js:13:9)
      at String::sub.inner (C:\Users\taker\.moon\lib\core\builtin\stringview.mbt:938:5)
      ...
  ```
  （JS スタックが 10 行ほど）＋ 最終行 `Total tests: 9, passed: 7, failed: 2.` **EXIT=2**
- `moon build` 成功: `Finished. moon: ran 3 tasks, now up to date`
- `moon check` 成功（警告あり）: `Finished. moon: ran 3 tasks, now up to date (3 warnings, 0 errors)`
- 生成された内部テストファイル名から、テスト種別は 3 つと確認: `lib.blackbox_test.js` / `lib.internal_test.js` / `lib.whitebox_test.js`

---

## 8. String の文字アクセスと部分取得 — **UTF-16 コード単位。ただし `s[a:b]` はサロゲート境界を検査して落ちる**

**添字は UTF-16 コード単位で、要素の型は `Char` ではなく `UInt16`**（型注釈で確定させた）:
```
Error: [4014]
48 │   let c : Char = s[1]
   │                    ╰─── Expr Type Mismatch
       has type : UInt16
       wanted   : Char
```

実測（`let s = "a😀b"`、全 pass）:
```moonbit
assert_eq(s.length(), 4)          // UTF-16 コード単位
assert_eq(s[0].to_int(), 97)      // 'a'
assert_eq(s[1].to_int(), 0xD83D)  // 上位サロゲート
assert_eq(s[2].to_int(), 0xDE00)  // 下位サロゲート
assert_eq(s[3].to_int(), 98)      // 'b'
assert_eq(s[1:3].to_owned(), "😀")
assert_eq(s.char_length(), 3)
assert_eq(s.code_units().length(), 4)
assert_eq(s.to_array().length(), 3)   // Array[Char]
// iter() / view() はコードポイント単位 = 3 周
```

**新発見（計画に無い致命的な罠）: `s[a:b]` は端がサロゲートペアの途中だと panic する。**
```
[probe2] test lib/str_wbtest.mbt:65 ("String: s[0:2] はサロゲート途中なので落ちる") failed: Error
    at $panic (...)
    at String::sub.inner (C:\Users\taker\.moon\lib\core\builtin\stringview.mbt:938:5)
[probe2] test lib/str_wbtest.mbt:71 ("String: s[2:4] もサロゲート途中なので落ちる") failed: Error
Total tests: 9, passed: 7, failed: 2.
```
標準ライブラリの実装が逐語でそう書いてある（`C:\Users\taker\.moon\lib\core\builtin\stringview.mbt:928-941`）:
```moonbit
#alias("_[_:_]")
pub fn String::sub(self : String, start? : Int = 0, end? : Int) -> StringView {
  ...
  guard start >= 0 && start <= end && end <= len
  if start < len { guard !self.unsafe_get(start).is_trailing_surrogate() }
  if end < len { guard !self.unsafe_get(end).is_trailing_surrogate() }
  StringView::make_view(self, start, end)
}
```
→ **既存 `core/doc.mbt` の `fn slice(s, a, b) { s[a:b].to_owned() }` は「任意の UTF-16 オフセットで安全に切れる」関数ではない。** 検査なしの生スライスが要るなら:
```moonbit
String::unsafe_substring(s, start=0, end=2)   // 実測 pass。half.length() == 2、half[1] == 0xD83D
```
（`String::substring` は `#deprecated("Use `str[:]` or `str[:].to_string()` instead")`。`StringView::to_string()` も deprecated で `to_owned()` が正。）

その他: `.find("b") == Some(3)` / `.rev_find("a") == Some(0)` / `.contains("😀") == true`（いずれも UTF-16 オフセット）。**`String::charcodes` は存在しない**（`Error: [4015] Type String has no method charcodes.`）— コード単位で回すなら添字ループか `.code_units()`。

---

## 9. `Array[T]` の主要 API — **計画で使うものは全て実在（14/14 pass）**

`moon test -p probe2/lib` で全通過を確認したもの:

| 分類 | 確認済み |
|---|---|
| 生成 | `[]`（型注釈付き）、`[1, 2, 3]`、`Array::make(n, v)` |
| 基本 | `.length()` / `a[i]` / `a[i] = v` / `.is_empty()` |
| 破壊的 | `.push()` / `.unsafe_pop()` / `.clear()` / `.append()` / `.insert(i, v)` / `.remove(i)` / `.sort()` / `.rev_in_place()` |
| 非破壊 | `.rev()` / `.copy()` / `.map()` / `.filter()` / `.fold(init=, f)` / `.contains()` |
| 走査 | `.iter()` / `for i, v in a`（インデックス付き for-in） |
| 切り出し | `a[1:3].to_owned()` → `ArrayView` から `Array` |

**deprecated が 2 つ**（計画で綴りを固定すべき）:
```
44 │   b.rev_inplace()
   │        ╰─────── Warning (deprecated): `rev_inplace` is deprecated, use `rev_in_place` instead
53 │   assert_eq(a[1:3].to_array(), [2, 3])
   │                     ╰───── Warning (deprecated): `to_array` is deprecated, use `to_owned` instead
```

---

## 10. TS 側のテスト実行 — **`node --test` は動く。環境変数の前置きは PowerShell で通らない**

doc-model ワークツリーには `node_modules` も `core/_build` も無く、`pnpm install` / `pnpm run core` を踏めばリポジトリを変更してしまうため、**同じ内容の別ワークツリー**（`D:/1.atrium/mmm/.claude/worktrees/dnd-ux-improvement-1ebfc6`、`node_modules` と `core/_build` あり）で実行した。読み取り専用の実行のみ。

```
$ node --test test/edits.test.ts
✔ moveLine: 上へ動かす (0.0688ms)
...
ℹ tests 15
ℹ suites 0
ℹ pass 15
ℹ fail 0
ℹ cancelled 0
ℹ skipped 0
ℹ todo 0
ℹ duration_ms 84.5224
EXIT=0
```
Node は `v24.16.0`。**グロブは Node 自身が展開する**（PowerShell は展開しない）ので `node --test "test/*.test.ts"` はそのまま動く（`node --test "test/e*.test.ts"` で `edits.test.ts` のみに当たることを確認）。

**環境変数の前置きは PowerShell で構文エラー**（recon-tests.md の `MMM_FUZZ=5000 pnpm test` はそのままでは使えない）:
```
PS> MMM_FUZZ=5 node --test test/edits.test.ts
MMM_FUZZ=5 : The term 'MMM_FUZZ=5' is not recognized as the name of a cmdlet, function, script file, or operable program.
Check the spelling of the name, or if a path was included, verify that the path is correct and try again.
    + CategoryInfo          : ObjectNotFound: (MMM_FUZZ=5:String) [], CommandNotFoundException
    + FullyQualifiedErrorId : CommandNotFoundException
```
PowerShell での正しい綴り（実測で `process.env` に届く）:
```powershell
$env:MMM_FUZZ = '5000'; pnpm test        # → MMM_FUZZ=5000
Remove-Item Env:MMM_FUZZ                  # 後始末（セッションに残る）
```
Git Bash 側なら `MMM_FUZZ=5000 pnpm test` がそのまま通る。**計画に載せるコマンドはシェルを明示すること。**

---

# 計画の記述を訂正すべき点

1. **`typealias` を全廃する** — 契約の `pub typealias X = Array[Int]` は Parse error（`[3002]`）＋ `[4032]`。`pub type X = Array[Int]` に直す。T5 の申し送りが正しい。旧形 `typealias 型 as 別名` も deprecated なので採用しない。
2. **未定義値のエラー文言を `Error: [4021]` / `The value identifier X is unbound.` に統一する** — T5 の `Error [4014] The value X is undefined.` は削除。`[4014]` は `Expr Type Mismatch`、`is undefined.` は型側（`[4032]`）の文言。
3. **ラベル付き enum ペイロードは「定義と match は `~`、呼び出しは `=`」と明記する** — `Image(alt~="a")` は `Error: [3016]`。契約が `~=` を書いているなら誤り。
4. **`pub` と `pub(all)` の使い分けを設計 §2 の型ごとに決める** — `pub` は別パッケージから**読み・match のみ**、構築と `mut` 書き込みは不可（`[4036]` / `[4094]`）。JS エクスポート層や別パッケージのブラックボックステストが `Doc` / `Node` / `Block` を**組み立てる**なら `pub(all)` が必須。`pub` で足りるのは「core が作って外は読むだけ」の場合に限る。
5. **`moon test` を `-p` 無しで書かない** — この repo では `core/js` の `#export_name` が `Error: [4219]` で必ず落ちる（EXIT=1）。新パッケージを足したら `moon -C core test -p mmm-app/core -p mmm-app/core/<新>` と**両方を並べる**形にする。`moon check` は `-p` 無しで通るので型検査だけは全体でよい。
6. **`-p` の綴り間違いが exit 0 で緑になることを計画に明記し、対策を書く** — `Total tests: 0, passed: 0, failed: 0.` が出ても成功扱い。CI では出力の `Total tests: 0` を検知するか、`moon test` の PATH 指定（`moon -C core test <dir>`）を使う。
7. **`moon fmt` の運用方針を「新パッケージのディレクトリのみ」に限定し、`moon.pkg` も整形対象だと書く** — `moon fmt --check` の失敗は **EXIT=127**（1 ではない）。`core/js/moon.pkg` の `"mmm-app/core" @core,` は別名が剥がされる差分を出すので、`js` を対象に含めた瞬間に赤になる。新パッケージの `moon.pkg` も `@doc` のような冗長別名は最初から書かない。
8. **`s[a:b]` を「任意の UTF-16 オフセットで安全なスライス」と書いてはならない** — 端が下位サロゲートに落ちると `String::sub` の `guard` で **panic**（`stringview.mbt:938`）。既存 `slice()` ヘルパをそのまま新 core に持ち込むなら、この前提（オフセットは常に行境界／コードポイント境界）を計画に明文化する。検査なしが必要なら `String::unsafe_substring(s, start~, end~)` を使う。
9. **文字アクセスの型を `UInt16` と書く** — `s[i]` は `Char` ではない（`[4014] has type : UInt16`）。`Char` が要るなら `.iter()` / `.to_array()`。`String::charcodes` は存在しない（`[4015]`）ので使わない。
10. **`not(x)` を書かない** — deprecated（`Warning (deprecated): Use !expr instead`）。計画・契約とも `!x` に統一。
11. **deprecated な Array API を計画から追い出す** — `rev_inplace` → `rev_in_place`、ArrayView の `to_array` → `to_owned`。それ以外（`push` / `length` / `iter` / `rev` / `copy` / `contains` / `map` / `filter` / `fold` / `sort` / `insert` / `remove` / `append` / `is_empty` / `for i, v in`）は全て実在。
12. **wbtest のヘルパ名の一意性を制約として書く** — 同一パッケージの `*_wbtest.mbt` は名前空間を共有し、同名トップレベル定義は `Error: [4051] ... is declared twice`。機能別にファイルを割る計画なら、ヘルパ名の衝突回避を明示する。
13. **`pub struct` の `mut` フィールドは定義パッケージ内で必ず一度は書く** — 別パッケージでの書き込みは `unused_mut` 判定に数えられず、`Error: [0015]` でビルドが止まる。
14. **TS 側コマンドはシェルを明示する** — `MMM_FUZZ=5000 pnpm test` は PowerShell では `CommandNotFoundException`。PowerShell 版 `$env:MMM_FUZZ = '5000'; pnpm test` を併記する。

---

**検証に使った使い捨てモジュール**: `C:\Users\taker\AppData\Local\Temp\claude\D--1-atrium-mmm--claude-worktrees-dnd-ux-improvement-1ebfc6\37dbb858-eda4-49d1-b4e7-c65ff5c6f8c5\scratchpad\probe2\`（`moon.mod` + `lib/`（library）+ `user/`（library）+ `ffi/`（foreign_library））。リポジトリ出力の逃がし先は同 `scratchpad\o1`〜`o4`。

**リポジトリ無変更の確認**:
```
$ git -C D:/1.atrium/mmm/.claude/worktrees/doc-model status --porcelain
（出力なし）
$ ls -d .../doc-model/core/_build .../doc-model/node_modules
ls: cannot access '.../core/_build': No such file or directory
ls: cannot access '.../node_modules': No such file or directory
```