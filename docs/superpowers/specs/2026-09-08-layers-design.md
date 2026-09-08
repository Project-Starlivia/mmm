# layers — 文書の処理を、言い切れる語彙とその上の段に割り直す（設計）

#188。`pieces` の名を考えていて、名前の前に粒度、粒度の前に段の定義が要ると分かった。
md → Doc の読みだけでなく、書き・検め・操作・合流まで、文書を扱う処理ぜんぶを
同じ物差しで割り直す。map/（配置と判断）と read/ の問い合わせ（caret / copy / name /
head）は別の領分なので、ここでは触れない。

**動きは変えない。** 段の切り方も、md の裁定も、既存の試験も 1 つも変わらない。
変わるのは関数の粒度と名前だけで、既存の wbtest が全部の網になる。

## 規則 — 二段

**下段は語彙。1 関数 = 1 文で言い切れる。** 入出力は core の型（原文 / mdAst / Piece /
Frame / Doc / Spot / View / Edit / Flaw / Op）で、分岐はその 1 文の中に閉じる。private。

**上段は段。1 語の動詞で、中身は語彙の合成だけ。** 判断（if）を持たない。段の入出力が
段の型で、pub なのは段と型だけ。段の名は read / build / project のように、何をするか
ではなく**何から何へ**が読める語。

**純粋なのは段。** 語彙の中に可変を回すものが 1 群ある — build の積む群（`lay` / `take` / `put`）は
可変の `Build` を回す fold で、深さを stack の高さで持つ設計と引き換え。段としての
`build(md, ast)` は同じ入力に同じ出力を返す。ほかの語彙は引数だけを見る。

**段は一方向。相互再帰は段の中に閉じる。** build の中で畳みの判定が積みの空打ちを呼ぶ
（`standing` ↔ `depths`）のは、build 1 段の中の話なので許す。段をまたぐ再帰は作らない。

## 流れ

```
            read             build                project
md ───────> mdAst ─────────> Doc + Spot ────────> View          survey    = read → build → project
            write            unbuild
md <─────── mdAst <───────── Doc                                serialize = unbuild → write
                              │ check    Doc → [Flaw]
                              │ apply    Doc × Op → Doc + focus  = attempt → cap → mend
md × Doc × Spot × Doc ──merge──> [Edit]                          = plan → verified（違えば全文）
md × Op ──edit──> [Edit] + focus                                 = survey → apply → merge → number
```

段は 9 つ。read / build / project / unbuild / write / check / apply / merge / edit。
survey と serialize は段の合成に名を付けただけ（段ではない）。

## 段ごとの語彙

「今」は現状の関数名。「→」は分ける・改める・消す。名前が無い欄は据え置き。

### read — md → mdAst（md.mbt）

| 語彙 | 1 文 | 今 |
|---|---|---|
| `@markdown.parse` | ライブラリが md を mdAst にする | |
| `stretch` | 塊の尻を行末の改行まで伸ばす | `dialect`。方言と言うほど意味は無い |
| `stretch_block` | 塊 1 つの span を伸ばす。容器は中まで歩く | `dialect_block` |
| `closed` | 閉じのフェンスの行の尻。閉じが無ければそのまま | |
| `after_newline` | 改行の次の位置 | |
| `unswallow` | 伸ばした span に丸ごと飲まれた塊を落とす | `dialect_blocks` の中に埋まっている → 出す |

`read = parse |> stretch`。今もそう。

### build — mdAst → Doc + Spot（build.mbt / fold.mbt / content.mbt）

段の本体は `sift` で切って `lay` で積み、`number` で振って `chart` で地番を写す。
今の `build()` は 60 行で、文書の散文の地番の計算まで inline で持つ → 合成だけにする。

**綴りを裁く（fold.mbt）** — 今の `pieces` 154 行を 6 つに割る。

| 語彙 | 1 文 | 今 |
|---|---|---|
| `sift` | 塊の列から綴りを落とし、中身と畳みの印を残したひと切れの列にする | `pieces` → 下 5 つの合成 |
| `spell_of` | 塊 1 つのタグを読む。生の HTML の塊だけ | `read_spell`。read の語を避け、`fold_of` / `content_of` に揃える |
| `pairs` | タグの並びで開きと閉じを対にする | |
| `standing` | 固定点で、立つ対。`depths` を呼ぶのはここだけ | `pieces` の中の 55 行 → 出す |
| `fallen` | 立つ対から、落ちる塊（開きと閉じの塊で、タグが全部その対のもの） | 同じループの中 → 出す |
| `stands` | 対 1 つが畳みとして立つか | `folds` |
| `covers` | 領域が 1 つの部分木を過不足なく覆うか | |
| `arrange` | 塊の列と裁定から Plain / Folded / Capsule を並べる | `pieces` の中の 65 行 → 出す |
| `restore` | どのひと切れの範囲にも入らない定義行を、位置順に Text として差す | `pieces` の `flush` / `carried` → 出す |
| `capsule` | 原文のまま持つ領域の読み取り（open / summary / body） | |
| `fold_of` | 開きの塊が言う Fold | |
| `ahead_of` | 各塊の手前に、塊にならない定義行が在るか | |
| `next` / `beyond` / `lands` | 空行を飛ばした次 / 落ちる綴りも飛ばした次 / 保留中の水平線の行き先 | |
| `tag_at` / `elem_end` / `opaque_end` / `raw_end` | タグ 1 つの字句 | |

`restore` は畳みの話ではない。分けた後で build の `lay` の側へ動かす道が開く
（判定が要るのは `ahead_of` の位置だけで、Text を出す仕事とは別）。

**積む（build.mbt）** — 今のまま。1 つ 1 つが言い切れている。

| 語彙 | 1 文 |
|---|---|
| `lay` | ひと切れを積む |
| `take` | 塊 1 枚を積む（見出し・項目・水平線・中身に振り分ける） |
| `items_take` | 項目の列を積む。最初の段落がラベル |
| `put` | 深さ level にノードを置く。浅ければ落とし、飛べば Implicit で埋める |
| `seat` | 積んである親の子にする。深さ 2 なら側と境界の綴りを付ける |
| `sink` | これから座る枠の深さを控える |
| `spill` | 境界になれなかった水平線を中身に落とす |
| `fill` | 中身をいま積んでいるノードに足す |
| `spine` | 列 0 の項目が座る枠の深さ |
| `depths` | 畳みを見ずに積んで、塊ごとの深さを測る（空打ち） |

**字を切る** — 今のまま。build.mbt と content.mbt に散っている → 1 ファイル（仮 `label.mbt`）。

| 語彙 | 1 文 |
|---|---|
| `head_label` / `head_start` / `head_end` | 見出しの中身を原文から切る |
| `item_label` / `item_start` / `item_marker` / `item_gaps` | 項目のラベル・頭・マーカー・詰め |
| `content_of` / `sole` / `bare` | 塊 1 枚の意味。段落まるごと 1 枚の絵か |
| `verbatim` / `carve` | 原文の切り出し（字下げを剥ぐ） |

**番号と地番** — 今のまま。

| 語彙 | 1 文 |
|---|---|
| `number_frame` / `number_blocks` | 文書順に id を振る |
| `number` | id が読み直しで得る番号を先に言う（edit が使う。pub） |
| `chart` | Frame の地番を id で引ける表に写す |
| `to_root` / `to_node` | Frame を Root / Node にする |

`Frame` の可変の欄は 5 つ（`side` / `rule` / `id` / `from` / `to`）で、どれも「座る時・振る時・
子が揃った時にしか分からない」から後書きにしている。`side` と `rule` は `put` が枠を
作った直後の `seat` で決まるので、枠を作る前に決めて渡せば要らない。`id` は `to_node` が
番号を配りながら写せば要らない。`from` / `to` は `chart` が子の和を返り値で言えば要らない。
PR 1 で `put` を割るついでに 5 つとも落とし、`Frame` を「作ったら変えない」にする。
残る可変は `kids` / `body` の配列（積む先）だけ。

**所属違い（content.mbt）** — `line_start` / `line_end` / `blank_start` / `column` は
原文の行の算術で、merge も使う → `text.mbt`。`bare_path` は画像のパスの話で、
tree の外（read/head・app/disk・map/card）が使う → read/head へ。`lines` は
op の graft が「段落なら行ごと」に割るための問い → op へ。

### project — Doc → View（view/）

| 語彙 | 1 文 | 今 |
|---|---|---|
| `project` | Doc から削るだけで View を作る | |
| `cast` | Node 1 つ。mark を落とし、Implicit の label を None に | |
| `meant` | 読み解いた中身だけ | `read`。段の名と衝突 |

### unbuild — Doc → mdAst（unbuild.mbt）

今のまま。`unbuild` / `unbuild_node` / `unbuild_prose` が pub（merge の断片が使う）。
語彙は `nodes` / `node` / `wrap`（畳み）/ `bullets`（項目の列を生の塊に）/ `list_item` /
`heading` / `underlined`（setext）/ `paragraph` / `html` / `content` / `marker_of` / `kind_of`。

### write — mdAst → md（md.mbt）

| 語彙 | 1 文 |
|---|---|
| `write` | ライブラリが mdAst を md にする。改行は LF |
| `serialize` | `unbuild |> write`。frontmatter と本文の間に空行 1 つ |
| `fragment` / `prose` | 部分木 1 つ / 散文の正規形（merge の断片） |

### check — Doc → [Flaw]（check.mbt）

今は 110 行の 1 関数に 11 の規則が閉包で埋まっている → **規則 1 つ = 関数 1 つ**。
`check` は歩いて集めるだけ。

| 語彙 | 1 文 |
|---|---|
| `dupe_id` | 同じ id が 2 度出た |
| `barren` | 子を持たない Implicit |
| `side_count` | 側の本数が根の子と合わない |
| `border_break` | 中身の尻の水平線に骨格が続く |
| `swallowed` | 見出しに境界なしで続く項目・Implicit |
| `list_side` | 項目の根の子に Left |
| `gapped_item` | Implicit の先頭の子が項目 |
| `too_deep` | 深さ 7 以上の見出し |
| `deep_setext` | 深さ 3 以上で名前に改行 |
| `unmarked` | Implicit が名前・畳み・中身を持つ |
| `wordless` | 書き戻す字が無い中身 |

規則が見る相手は 4 段階で、歩きは 1 回。

| 相手 | 規則 | 要る文脈 |
|---|---|---|
| 文書 | `dupe_id` | id の集合（歩き全体） |
| 根 | `side_count` / `list_side` | Root だけ |
| ノード | `swallowed` / `too_deep` / `deep_setext` / `barren` / `unmarked` / `gapped_item` / `border_break` | 席（仮 `Site`）— ノード・深さ・base（列を抱える項目の深さ）・直前の兄弟とその側・文書順で 1 つ前のノードの中身の尻 |
| 中身 | `wordless` | Block だけ |

`Site` を 1 つの struct にして規則は `(Site) -> Flaw?`、`check` は歩きながら席を組んで
全部の規則に当てるだけ。今の閉包（`border` の Ref、`after_heading` / `bordered` の算術）は
席の欄になる。`border_break` だけは「文書順で 1 つ前」を要るので、歩きが前のノードを
持ち回る（文書の散文は根の 1 つ目の「前」）。

### apply — Doc × Op → Done?（op/apply.mbt / splice.mbt / walk.mbt）

段は `attempt → cap → mend` で、今もそう。語彙も揃っている。

| 群 | 語彙 |
|---|---|
| 操作 12 | `rename` / `fold` / `unfold` / `delete` / `add_node` / `wrap` / `move_node` / `flip` / `add_block` / `set_block` / `move_block` / `graft` |
| 綴り | `respell`（部分木を綴り替える）/ `cap`（天井を越えた見出しを項目に）/ `mend`（Implicit で直る破れを直す）/ `spell`（Implicit を綴る）/ `sign_at` / `spell_at`（席が決める綴り） |
| 道具 | `splice` / `append` / `body` / `rebuild_*` / `with_kids` / `sides_for` / `rules_for` |
| 歩き | `each` / `find` / `seat` / `parent` / `owner` / `above` / `pick` / `within` / `fresh` / `has` / `siblings` / `ancestors` |

### merge — md × Doc × Spot × Doc → Merged（merge.mbt）

段は `plan → verified`（違えば全文の正規形）で、今もそう。

| 語彙 | 1 文 | 今 |
|---|---|---|
| `plan` | 前後の木を id で突き合わせ、編集列を組む | |
| `elements` / `head_element` | ノードを行・中身・子の要素に割る | |
| `gaps` / `canon_gaps` | ours の隙間（原文の字）/ base・theirs の隙間（正規形） | |
| `merge_node` / `merge_children` / `merge_body` | ノード 1 つ / 子の列 / 中身の列 | |
| `merge_seq` | 列の合流 | 137 行 → 消える並び / 残る物の隙間 / 増える並び の 3 つに割る（列の頭の境目は 3 つに通る関心事で、関数ではない） |
| `settle` / `mid_line` / `pad` / `indent` | 編集列を整える | |
| `shape` / `faceless` | id と綴りを消した形 | |
| `verified` | 当てて読み直した形が後の木と同じか | |
| `patched` | 編集列を md に当てる | `apply` と 2 つ在る（同じ仕事） → 1 つに。`apply` は op の段の名 |

### edit — md × Op → Edited（op/edit.mbt）

`survey → apply → merge → number` の合成だけ。今のまま。

## 段と衝突している名

| 語 | どこ | どうする |
|---|---|---|
| `read` | 段（md.mbt）/ view の `read(body)` / fold の `read_spell` | 段だけに。`meant` / `spell_of` |
| `spell` | op の `spell`（Implicit を綴る）と、fold の `read_spell`（綴りを読む） | 向きが逆の同じ語は作らない。fold は `spell_of`（`Spell` を返す） |
| `apply` | 段（op）/ tree の `apply(md, edits)` | tree の方は `patched` と統合 |
| `survey` | tree の `survey(md) -> (Doc, spans)` / read の `survey(md) -> Survey` | 同じ名で返りが違う。tree の方は中身が `build(md, read(md))` の 1 行なので消し、2 か所の呼び元でそう書く |
| `read` | package `core/read`（Survey と問い合わせ）/ 段の read | 一番重い衝突。package が提供するのは `Survey` なので `survey/` に（modules-design「提供するもの 1 語」） |
| `parse` | tree の `parse(md) -> Doc` / ライブラリ | 2026-09-05 に許容と決めた。据え置き |
| `seat` / `take` / `put` | build（Frame を置く）と op（席を引く・抜く・差す） | 段が違えば同じ語でよい。意味が同じ方向かだけ確かめる |

## 切るもの

長さでなく、継ぎ目が 1 文で言えるかで決める。実測（2026-09-08）で 40 行を越える関数を
全部読み、継ぎ目のあるものだけ。

| 関数 | 行 | 切り方 | 手間 |
|---|---|---|---|
| `pieces` | 154 | `sift = spell_of → pairs → standing → fallen → arrange → restore`（上） | 中 |
| `put` | 86 | 「どの深さに座るか」（境界 / 列 0 の見出し / 新しい木）を純粋な関数に。落とす・Implicit で埋める・枠を作る・座らせる を小さい動作に。可変に触るのは push / pop / seat だけ | 中 |
| `items_take` | 75 | 「項目の顔（ラベル・頭・範囲）」と「中身を owner / base を替えて読む」 | 小 |
| `merge_seq` | 137 | doc の 3 箇条どおり — 消える並び / 残る物の隙間 / 増える並び（列の頭・途中・尻）。共有は `inherited` と `pend` | 中 |
| `check` | 111 | 規則 1 つ = 関数 1 つ（11） | 小 |
| `dialect_block` | 150 | 「伸ばす（フェンス 3 種）」「中まで歩く（容器）」。長さは enum の欄の書き写し | 小 |
| `depths` + `build` | 49 + 63 | 17 欄の `Build` リテラルが 2 か所 → `Build::new(md, defs, dry~)`。文書の散文の地番を出す | 小 |
| `flip` | 50 | 3 段（根を鏡像 / 根の子を反転 / 深いノードを反対側へ）を 3 関数に | 小 |
| `graft` | 51 | 「散文を行のノードと中身に分ける」「番号を寄せる」を出す | 小 |
| `plan` | 53 | 「側が変わった根を落とす」を出す | 小 |
| `merge_children` | 59 | 「列の流儀（詰まっているか）」を出す | 小 |

切らないもの — `covers` / `spell_of`（`read_spell`）/ `stands`（`folds`）/ `cap` / `mend` / `append` / `list_item` /
`nodes` は 40〜50 行だが 1 文で言い切れていて継ぎ目が無い。unbuild の `content` は
コンストラクタの欄が長いだけ。

**可変を純粋にはしない。** build の `Build` を毎歩コピーして返しても、stack を持ち回る
だけで分岐は減らない（配列は可変 — ai-docs/moonbit.md）。切り出すのは判断で、可変に
触る動作を 3 つに絞る。

## 進め方

段は変えず、語彙を切り出す PR を段ごとに。動きは変えないので、既存の wbtest が全部の網。

1. build — `pieces` → `sift`、`put` / `items_take` の判断、`Build::new`、`build()` を合成に
2. check — 規則 1 つ = 関数 1 つ
3. merge — `merge_seq` を 3 つに、`plan` / `merge_children` の切り出し。`apply` と `patched` を 1 つに
4. op — `flip` を 3 段に、`graft` の切り出し
5. read — `dialect_block` を 2 つに
6. 名 — 段と衝突する語（`read` / `apply` / `survey`、package `read/` → `survey/`）。所属違いの移動（text / bare_path / lines）
7. docs — core.md のパイプライン図を 9 段に。各段の項に語彙の表。「作り直している最中」の断りを消す

## 触らないもの

- map/（配置・当たり・視点・意図）— 別の領分。同じ物差しで見るのは後
- read/ の問い合わせ（caret / copy / name / head）— Survey への問いで、段ではない
- app/ — DOM
