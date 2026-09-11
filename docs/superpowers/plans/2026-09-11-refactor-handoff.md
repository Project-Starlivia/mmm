# refactor — 引き継ぎ

2026-09-11 に測って決めたところまでの記録と、次に手を動かす人への申し送り。
**決めは各 issue のコメントに在る**（このファイルはその索引と段取り）。

## いま在る場所

main は `e60c551`。今日入った 6 本:

```
e60c551  docs: web.md を落とす (#237)
073bea2  perf: 控えるのは字ではなく数 (#236)
ffc1fef  perf: クラスの付け外しも値が変わったときだけ (#235)
5363083  fix: 木が抱える字は LF だけ (#234)
c7a0309  fix: details のカードも押して選べる (#233)
d58a87c  refactor: build.mbt を仕事ごとに割る (#231)
```

`core/tree` の科はこうなった。**触る前にこの地図を頭に入れること。**

| ファイル | 仕事 |
|---|---|
| `md.mbt` | ライブラリとの境界、方言（span の直し） |
| `fold.mbt` | 畳みを裁いてひと切れの列に（`sift`） |
| `deem.mbt` | **md を読んで裁定を下す。** mmm の解釈はここにしか無い |
| `notation.mbt` | 裁定を、原文を隙間なく覆うひと切れの列に |
| `assemble.mbt` | その列から木と地番を組む。**裁定は 1 つも下さない** |
| `measure.mbt` | 記法がどこまでかを原文から測る |
| `build.mbt` | 入口（`build(md) = assemble(notation(md))`）と木の住所 |
| `check.mbt` | md に書けない並びを見つける |
| `unbuild.mbt` | 木 → mdAst。`parted`（階層が言う隙間）もここ |
| `merge.mbt` | 前後の木の差を原文 md への編集列に |

---

## 段 1 — #204 桁 0 の塊の持ち主（**次にやるのはこれ**）

[#204](https://github.com/Project-Starlivia/mmm/issues/204) のコメント 2026-09-11 が決めと検証。

### 決め

**桁 0 の塊は md に揃える。一番内側の見出しが持つ。** `head > listitem` と `head body` が
両方成り立つ形。塊が手前の兄弟より上へ動くのは受け入れる。空行が往復で減ることも
破れに数えない（#232 と同じ線）。

### 型は 1 行も変えない

`body : Array[Block], children : Array[Node]` で足りる。案 C（`tail`）も案 D（`limbs`）も要らない。
理由は 3 つ、全部コードで確かめた。

- `unbuild.mbt:318-322` は例外なく 行 → body ぜんぶ → children の順に書く。**あいだの順序は
  今も型のどこにも無い**
- 合流は木の並びを原文の席に使っていない。位置は全部 `spans` / `gap` の **id 引き**
  （`spot` merge.mbt:446-448、`gap` merge.mbt:105-107）
- 見せる側は body を縦積み・children を左右の別の軸に翻訳する
  （`cards(n.body)` layout.mbt:160、`kids_of` layout.mbt:117-121）

### 直す所は 2 つ

```
core/tree/assemble.mbt:116-130   Card を l.stack の頂上へ無条件に push している。
                                 桁を 1 行も見ていない。「桁 0 なら開いている項目を
                                 閉じてから座らせる」に替える。
                                 桁は column(md, p.at.from)（text.mbt:62-68）で測れる。
                                 落とす先を選ぶ Frame.mark は assemble.mbt:13 に在る。
                                 列 0 の見出しが deem.mbt:459-464 でやっているのと同じ規則

core/read/caret.mbt:56-73 owns   「自身の文 = 地番の頭から最初の子の頭まで」が前提
                                 （同ファイル :4 が「中身は子より前に書かれる」と書いている）。
                                 子の後ろに書かれた塊は誰の own にも入らず、md でそこに
                                 カーソルを置いても地図が光らない。子の地番を差し引く形に直す
```

**`deem.mbt` と `notation.mbt` は 0 行。** pieces は原文順で隙間なく覆い `at` は絶対 offset
なので、桁も並びももう持っている。

### 動く golden

`core/tree/corpus_wbtest.mbt` の 3 通り。

- `:42` の `"- a\n\n  - b\n\n  text\n\n  - c\n"` → `:134-135` の正規形が動く（塊が `b` に付いて桁 2 → 4）
- `:70` / `:72` は**良くなる方向** — `</details>` の後ろの桁 0 の塊が中の見出しに吸われて
  部分木が領域を超え、畳みが立たず領域ごと Details カードになっていた見本。持ち主が外へ移れば
  範囲が領域に収まって**畳みが立つ**

`moon test -u` は `inspect` を黙って埋め直すうえ、**多行の JSON golden を 1 行に潰す**。
潰れたら手で整形し直すこと（`grep -n 'content=({"' core/tree/*_wbtest.mbt` で見つかる）。

### やらないと決めたこと

`Doc.body` を落とすことと `mark` を落とすことは、**この段に入れない。** 測った結果:

- **`mark` は落とせない。** `unbuild.mbt:307-326` はノードを書くこと全体が mark の 3 枝なので
  1 ノードも綴れない。`parted`（unbuild.mbt:76-91）も出ないので合流は base / theirs を失い、
  **毎回全文へ落ちる**（merge.mbt:127-129）。木の外の読み手も宙に浮く（`sign_of` を op が
  14 か所、splice / keys / survey が各 1 か所）。落とせる最大は綴りの 5 欄で `sign : Sign?` まで
- **`Doc.body` は今は落とせない。** 骨格の行が 1 本も無い md（散文だけのメモ）に書く席が
  無くなり、全文の唯一の出口（md.mbt:416 → unbuild.mbt:15-18）が空文字を出す。貼り付けの
  主機能（app/app.mbt:650-657 → apply.mbt:709 `pieces(sub.body)`）も入口を失う
- **body の内側の順序は要る。** `Alt+↑↓` の `MoveBlock(Before/After)`（map/keys.mbt:386-394、
  出荷済み）、カードの積み順（map/card.mbt:165-173 → metric.mbt:274-280）、
  `trailing` の `bs.last()`（check.mbt:149-154）が並びを見ている
- **桁 0 の塊をノード（`Verdict::Line`）にする案は落ちた。** 一時の試験で 3 通り測った —
  飛びの body は `unbuild.mbt:323-324` が書かないので塊が消える / 綴られたノードにすると
  md の意味が変わる / 飛びの根にすると冒頭の散文が消える。行を持たないノードは今 Implicit
  ただ 1 つで、check（`unmarked` / `barren`）が「中身を持てない」と決めている。**mark を
  増やす方向になるので提案と逆**。地図に散文が箱として出るので `docs/pictures.md:16-18` とも衝突

---

## 段 2 — #24 の調査 → #86 / #68

[#24](https://github.com/Project-Starlivia/mmm/issues/24) の決め: **上げ方を決める前に傾向を調べる。**
他のリポジトリと MoonBit 公式が版をどう扱っているか（固定か latest か、上げる間隔、
破壊的変更の告知）。

CI は今 moonc の版を直書きで固定している（`.github/workflows/ci.yml:35`、
`0.10.11+6ff76a5f9`）。上げると**既定で切れている診断の数が動く** — 実例として
`missing_doc` が 3 件 → 114 件になった。だから #24 が先。

その後:

```
#86  既定で切れている診断     230 件 → 505 件（2026-09-11 に測り直し）
#68  derive の行              26 か所 → 49 か所。E0079 は 81 → 152
```

測り方: `cd core && moon check --warn-list "+a" --output-json`。
多いファイルは `op/apply_wbtest.mbt` 78 / `tree/types.mbt` 30 / `map/metric.mbt` 20。

---

## 段 3 — #78 外から呼ばれない export

34 個 → **8 個**（2026-09-11 に測り直し）。`src/` が 20 ファイル以上から 6 ファイルになった。

```
src/app.ts    7   AnchorsAt / Blocked / Editor / Failed / Field / More / Spot
src/state.ts  1   caretOf
```

**7 つは全部型**で、自分のファイルの中で構造的に使われている。`Editor` は
`main(editor: Editor)` の引数の型。**境界の語彙として `export` を残すか、印を外すかは
per-symbol の判断**なので、まとめて外さないこと。`caretOf` だけは明らかに内輪。

---

## 段 4 — #88 fixtures の組み替え

[#88](https://github.com/Project-Starlivia/mmm/issues/88) のコメント 2026-09-11 に覆いの測りが在る。
md の記法 28 種のうち **fixtures が足しているのは 3 種だけ**（`~~~` フェンス・表・素の URL）。

提案した段取り:

```
1  gnarly.md / gnarly-crlf.md（297 / 351 字）を corpus_wbtest.mbt の literal に吸わせる
   → 記法の変化（~~~ / タブ / 閉じの # / setext / CRLF）が全部 MoonBit 側で言える
2  表・素の URL の短い見本を 1 通りずつ足す → 覆いが 27 / 28
3  残る 5 本（deep / fat / mixed / rich / wide）を「大きさの見本」と名前を付け直し、
   大きさについて主張する試験を書く
```

3 の中身は未決。**時間を測るのは CI で揺れる**ので構造で言う案がある（`deep` は深さ N、
`wide` は兄弟 M、`mixed` はノード数 K の指紋）。時間は #64 の実測が別に持つ。

脚注（1 種）はどちらにも無い。mmm が読み解かない記法なので Raw に落ちるはずだが、
確かめた記録が無い。

---

## 段 5 — #64 の残り（構造の話。安い部分は取り切った）

打鍵 1 回（5,001 ノード、`pnpm dev`、中央値）:

| 編集 | 元 | #235 | #236 |
|---|---:|---:|---:|
| 根のラベルに 1 字（全ノードが動く） | 114.3 | 61.4 | 60.8 |
| 末尾の子のラベルに 1 字（1 箱だけ動く） | 79.9 | 32.2 | **26.3** |
| 末尾に見出しを 1 本（1 つ増える） | 102.7 | 54.0 | 49.9 |

残る 26 ms の内訳は core の読み 約 10ms・配置の計算 約 4.5ms・`draw` の歩き。**3 つとも
構造の話。**

- core の読みは「打鍵ごとに md を読み直す」の代償（`docs/core.md`「core は状態を持たない」）。
  削るなら決めを変える
- `draw` の歩きは「変わった箱だけ歩く」にする話で、**レイアウトが差分を言えるようになる
  必要がある**。設計から要る

#55 は測ったら**フレーム予算に収まっていた**（pointermove 1 回 3.0〜6.7 ms）。残る宿題は
「N 個選んだときを測る」だけ。#77 も #235 / #236 で 1 回の値段が下がったので優先度が落ちた。

**測り方（再現手順）:**

```
1  .claude/launch.json に一時の設定を足し（pnpm --dir .worktrees/<枝> run dev --port 空き番）
   preview_start で開く。終わったら launch.json は git checkout で戻す
2  .cm-content の cmTile.view が CodeMirror の view
3  view.dispatch({changes:{from:0,to:doc.length,insert: 5,001 ノードの md}}) で文書を作る
4  Element.prototype.setAttribute / DOMTokenList.prototype.toggle / document.createElementNS を
   包んで数える
5  view.state.update(...) で state を作る所と view.dispatch(tr) を別に測り、
   最後に document.body.offsetHeight を読んでブラウザの払いを分ける
```

MoonBit 側の段を測るには使い捨ての計器を置く（`performance.now()` の extern を
`app/mindmap/probe.mbt` に置き、`Mindmap::render` と `App::cycle` の段を包む）。
**PR には入れない。**

---

## 罠（踏んだもの）

- **Bash heredoc でバックスラッシュが潰れる。** `"\n"` を含む文字列の置換を
  `bash <<'PY'` の Python で書くと `\n` が改行になって一致しない。**Write / Edit を使う**
- **`moon test -u` は多行の JSON golden を 1 行に潰す。** 潰れたら手で整形し直す
- **`moon test -p mmm/core` の `-f` はファイル名だけ**（`-f tree/x.mbt` ではなく `-f x.mbt`）。
  package 名は `mmm/core`（`mmm/core/tree` は存在しない）
- **tree package だけ回すと op の失敗を見落とす。** 必ず `moon test`（workspace 全部、661 件）
- **`pnpm run check` は `pnpm run core` の後でないと落ちる**（`_build/js/release/…/js.js` が要る）
- **worktree の枝を squash でマージする前に、上に積んだ PR の base を main へ付け替える。**
  付け替えずに土台を消すと上の PR が未マージのまま CLOSED になる（`mmm-lost-branch-recovery`）
- **`Renderer` が `pub` なので、欄の型も `pub` が要る**（`Marks` を `priv` にすると E4046）

## 確かめの手順（毎回）

```
export PATH="$HOME/.moon/bin:$PATH"
moon fmt && moon check          # 警告 0
moon test                       # 661 / 661
moon info                       # .mbti の差が出ないこと（出たらコミットに含める）
pnpm run core && pnpm run check # tsc 3 本
pnpm test                       # 35 / 35
```
