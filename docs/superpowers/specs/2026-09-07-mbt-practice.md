# mbt — MoonBit の作法（調べたこと）

Issue: #143 の続き。段 3 まで（地図・部品・帯と枠）を core に移した時点で、残り
（share / io / handles / assets / dnd / draw / export / files / more / main.ts）は
**ブラウザの非同期 API** が中心になる。先に MoonBit の js backend の作法を調べ、
実験で確かめた。数字と挙動は 2026-09-07、moon 0.1.20260827 / MoonBit 0.10.11 /
mizchi/js 0.12.2 / moonbitlang/async 0.20.5 のもの。

## 境界の型（言い切れること）

`.d.ts` に約束が出るのは **数・文字列・真偽・`FixedArray[T]`・`T?`（`T | undefined`）**
だけ。それ以外は `any`。

- **struct はそのまま JS の object**（`pub(all) struct` は identity）。渡すのは自由だが
  `.d.ts` は `any` なので、ts に読ませる形にはしない。ts から受ける object（host・
  メニューの行・たずね）は出口で `_get` して組み直す（`host_of` / `entry_of` / `ask_of`）
- **タプルは `{_0, _1}`**。数の組は `FixedArray[Double]` で渡し、ts が長さを確かめる
- **`Array[T]` を FFI の署名に書くのは deprecated**（本家の docs）。出口の引数・返り値は
  `FixedArray`。閉包の引数・返り値としてなら `Array` はそのまま JS の配列
- **null は `T?` にしない** — `Some(null)` になりうる。JS から来る値は
  `@core.identity_option` で None に、出すときは `@core.from_option` で null に
- **`T?` が `T | undefined` になるのは数・文字列など unboxed のときだけ。** `#external` や
  `@core.Any` の `T?` は箱（`None` が `{}` に見える object）で、そのまま JS に渡すと壊れる。
  JS に置く object（IndexedDB の行・host へ返す値）は `new_object` + `from_option` で組み直す
  （app/disk/handles.mbt の `row_of`。試験で見つけた）
- **JS の関数は MoonBit の閉包としてそのまま呼べる**。打鍵ごとに何千回も呼ぶものは
  `_call("name", [...])` の名前引きでなく、`_get("name").cast()` で関数そのものを取って
  直に呼ぶ（measure で 5000 ノード +15 ms の差）
- 型の無い呼び出し（style・矩形・捕捉・欄の値・約束）は **`app/web` にだけ**書く。
  他の package は `_get` / `_call` を書かない — 綴りの間違いはそこでしか起きない

## 非同期

**`async fn` を export しない。** export すると `.d.ts` は
`f(args, _cont, _err_cont) -> Result` の CPS の形になり、JS からは呼べない（実験で確認）。

使うのは **`moonbitlang/async/js_async`**（本家。`moon.mod` に `moonbitlang/async` を足す）:

```moonbit
///|
/// 同期の export が Promise を返す。中の async fn が待つ
#export_name("mmmOpen")
pub fn mmm_open(p : @js_async.Promise[String]) -> @js_async.Promise[String] {
  @js_async.Promise::from_async(async fn() {
    let text = p.wait()                       // JS の Promise を待つ
    let next = later(text, 5).wait()          // extern "js" が返す Promise も同じ
    text + next
  })
}
```

- **JS の reject は MoonBit の `Error` になる**（`catch { e => "\{e}" }` で `Error: nope`）。
  MoonBit 側の `fail("boom")` は JS 側で **reject**（値は `Failure(...)` の文字列）
- `async test` は `moon.pkg` の `for "wbtest"` に `moonbitlang/async` を足せば書ける。
  3 つ同じファイルに並べても通る
- mizchi/js の `Promise::wait` / `run_async`（コンパイラ組み込みの `%async.suspend` /
  `%async.run`）は単体では動くが、**`async test` を複数並べると panic することがある**
  （原因は追っていない）。js_browser の `requestAnimationFrame` がこれを使っているので
  残るが、**新しく書くものは js_async に揃える**
- 結び付けの無い API（File System Access・`navigator.clipboard`・`CompressionStream` の
  `Response` 経由）は `extern "js"` の 1 行で Promise を返す関数を書く:

  ```moonbit
  ///|
  extern "js" fn pick_file(types : @core.Any) -> @js_async.Promise[@core.Any] =
    #| (types) => window.showOpenFilePicker({ types })
  ```

  mizchi/js が持つもの（`Blob` / `File` / `TextEncoder` / `CompressionStream` /
  `IDBObjectStore` …）はそちらを使う。無いものだけ 1 行で書き、`app/web` に置く

## エラー

- 出口で壊れた JSON を受けたら `abort` — ts 側のバグで、静かに断らない（`raise` にすると
  JS 側が `Result` を受け取る）
- JS の例外が飛びうる同期の呼び出し（localStorage）は `@core.try_sync` で包む。
  `catch { _ => None } noraise { v => Some(v) }` の形
- 続きを閉包で受ける形（`(Bool) -> Unit`）は、**JS の Promise が出口に見えない**ときの
  手。Promise を返せるなら `from_async` のほうが ts が読みやすい（`await`）

## 予約語と罠（0.10.11）

- 予約語: `local` `move` `extend` `derive` `where` `export` `method` `ref` `type`。
  引数名・欄名に使えない（警告ではなく後で壊れる）
- `Ref::new` は deprecated → `let r : Ref[Int] = { val: 0 }`
- `s[i]` は UInt16。`1e-9` は不可（`1.0e-9`）。`Map([])` / `Set([])`（`::new()` でない）。
  `trim(chars=" ")` は StringView（`.to_owned()`）。`@strconv.parse_int` は deprecated
  （`@string.parse_int`。`raise` なので `catch`）
- `///` の doc comment は式の中（配列の要素の間）に置けない。`//` にする
- 同じ package の enum の構築子名は衝突する（`Link` / `Code` → `AddLink` / `AddCode`）
- happy-dom: `WheelEvent` は init の修飾キーを落とす（出来事に直に `_set`）。
  `ResizeObserver` は window にしか無い（`ownerDocument.defaultView` から取る）。
  `getBoundingClientRect` は全部 0。`<dialog>` の `close` は実機（Claude の埋め込み Chrome）で
  届かないが happy-dom では届く

## パッケージと道具

- 科（package）: `tree`（読み・書き戻し）/ `view` / `op` / `edit` / `map`（配置と判断。
  DOM を知らない）/ `read`（読みの持ち手と木の判断）/ `web`（DOM の道具）/ `parts`
  （部品）/ `render`（地図のペイン）/ `app`（帯と枠）/ `main`（束ねる場所）/ `js`（出口）。
  DOM を知る科は `supported_targets = "js"`
- 見せ方: 持ち手になる struct は `pub struct`（欄は外から見えない）、値は
  `pub(all) struct`。`priv` は同じ科の中だけ
- **`moon info`** が科ごとに `pkg.generated.mbti`（公開 API の一覧）を吐く。
  mizchi はこれを commit している。こちらも `check:core` に `moon info` を足して
  commit する — API の変更が diff に出る（この spec の PR で始める）
- `moon fmt --check` / `moon check` は `check:core`。`moon test PATH -i N` でその
  ファイルの N 番目だけ走る（`-f` は名前の glob）。`inspect(x, content=...)` は
  `moon test -u` で埋まる
- 試験は当面 `_wbtest.mbt`（同じ科の中）。API が落ち着いた科から `_test.mbt`
  （外から見える形だけ）に移す

## 大きさ

core の JS は 1.8 MB（素）/ 536 KB（min）/ 144 KB（gzip）。mizchi の計測では `Map` が
6 KB、`Json` が 7 KB、`HashSet` が 5 KB を足す（1 回入れば以後は増えない）。
打鍵の道に JSON を残さないのは速さの話で、大きさは気にする段ではない。

## 段 4 の順（非同期が要るもの）

小さいものから、js_async の道を 1 本通してから広げる:

1. **share**（gzip → base64url。`CompressionStream` + `TextEncoder` + `btoa`）
2. **io + handles**（File System Access + IndexedDB。ハンドルは `@core.Any` の持ち手のまま
   IndexedDB に置く）
3. **assets**（画像の読み書き。io と handles の上）
4. **dnd / draw / export**（落とす・描く・出す。canvas と clipboard）
5. **files / more の並び**（メニューの行を core で組む。ts の object の橋が消える）
6. **main.ts**（束ねる場所。最後）

ts に残るのは CodeMirror（editor.ts / state.ts / highlight.ts）と、字の実測（canvas の
`measureText`。CSS の字の綴りを読む）と、`coreApi.ts`（持ち手の皮）。
