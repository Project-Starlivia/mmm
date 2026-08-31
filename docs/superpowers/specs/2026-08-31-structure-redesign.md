# 構造の再設計 — 役割型への転換（引き継ぎ）

2026-08-31。実装計画（2026-08-30-doc-core）の完成後、型の設計を再検討した記録。
flat な Node（計画が前提とする形）から**役割型 + Skeleton enum**へ転換することを決定した。
憲法 §2 は改訂済み。**詳細の詰めと計画の改訂は次のセッションで行う** — この文書はその引き継ぎ。

## 決定した大枠

```moonbit
pub struct Doc {
  frontmatter : String?      // 封筒の逐語（旧名 head — 見出しとの衝突を嫌って改名）
  eol : Eol
  body : Array[Block]        // 最初の骨格より前の散文
  centers : Array[Center]
}

pub struct Center {
  id : Int
  skeleton : Skeleton
  branches : Array[Branch]
}

pub struct Branch {          // スロット = 場所。占有者を問わず側を持つ（id は持たない）
  side : Side
  node : Node
}

pub struct Node {
  id : Int
  skeleton : Skeleton
  children : Array[Node]     // 深さ 3 以降は一様
}

pub enum Skeleton {
  Implicit                   // 骨格行なし。飛びが綴り。label も body も型ごと無い
  Explicit(form~ : Form, label~ : String, folded~ : Bool, body~ : Array[Block])
}

pub enum Form { Heading; Item }   // Implicit は入れない — setForm の引数型なので
pub enum Side { Right; Left }
pub enum Eol { Lf; Crlf }

pub enum Block {
  Content(Content)
  Rule                       // 飾りの水平線（*** チャンネル）
  Opaque(String)
}
pub enum Content {
  Image(alt~ : String, src~ : String)
  Link(text~ : String, href~ : String)
  Code(info~ : String, text~ : String)
  Svg(String)
}
```

- doc の id は番兵 1（親指定用）。Branch は id を持たない（スロットは占有者の id で指す）
- 命名の裁定: `Implicit / Explicit`（暗黙に/明示に表現されている — 「飛びが綴り」の教義に
  一番忠実。Present/Absent が次点、Written/Unwritten は教義と半衝突で却下）、
  `frontmatter`（head は見出しと衝突）、`Skeleton`（略さない）、`form` は据え置き

### 型で死んだもの（旧 check の住人）

doc の汚れ / 深いノードの side / 側つきで綴り無し / implicit×label / implicit×body /
implicit×folded / implicit×Item / setForm(Implicit) / **sides と children の整合**
（Branch が side と占有者を同じ要素で持つのでスプライスが原子的 — 並行配列問題は型で消滅）。

### check に残る関係的不変条件

id 一意 / implicit の存在条件（子を持つ限り在る）/ implicit の位置（前に見出しの兄弟が
居ない）/ implicit の子は Heading / 順序法則（Item が先）/ 単調性（Item の子孫は Item）。

## 操作の設計（抗うゲーム）

> 公開 API は id で語る。型の異種性は**道具 4 つに幽閉**し、操作には腕を生やさない。

```
Path = Array[Int]     // [] = doc、[i] = center、[i, j] = スロット、それ以深 = children
Sub  = Whole(Center) | Limb(Node)   // 運搬の通貨。op.mbt の外に出ない

resolve(doc, id) -> Path?        // 腕なし
pluck(doc, path) -> Sub          // 3 腕（centers / branches / children から抜く）
graft(doc, parent, at, sub, side) -> Unit
                                 // 3 腕 + 変換の唯一の住所:
                                 //   doc へ: Limb → Center 化（children を Branch(Right) で包む）
                                 //   center へ: Whole → 解体（sides は深さの物理で消滅）/ Limb → Branch(side) で包む
                                 //   node へ: Whole → 解体 / Limb → そのまま
amend(doc, path, f : Skeleton -> Skeleton)   // fold / setForm 用（rename は読みの道なので通らない）
```

- **殺す条件の観測点**: 道具 4 つの腕が 3 で止まらなくなったら負け
- Whole は center 位置間では無変換（center の並べ替えで sides が無傷で旅する）
- **枝の並べ替えで side は運ばれない** — pluck で残置、graft が行き先（ドロップした列 /
  隣の側）で決め直す。「側は場所の属性」の帰結。仕様に明記すること
- implicit を綴れない位置への graft は昇格（既存の「綴りは行き先に従う」）
- 全 API 掃引済み: move（9 組合せ）/ delete / flipSide（center=鏡像・スロット・深部 reject）/
  add / fold / setForm / serialize / parse / sig / project / id 写し — 全部この道具の合成で通る

## project と境界

```typescript
type Mindmap  = { trees: MapTree[]; buried: number };
type MapTree  = { node: MapNode; right: MapBranch[]; left: MapBranch[] };
type MapBranch = { node: MapNode; children: MapBranch[] };
type MapNode  = { id: number; label: string; implied: boolean;
                  folded: boolean; form: "heading" | "item";
                  cards: Card[]; buried: number };
```

- project は mbt（法則 3）。バケツ分けは branches の filter — 側をまたぐ読み順はここで
  意図的に落ちる（絵に出ない情報）
- **hollow は境界から削除** — implied と label の 2 事実を渡し、中空に描くかは render の自由
  （implied と空ラベルは md ペインで見た目が違うので、境界で潰してはならない）
- render の入口は統一サイクルの 1 本だけ（md が変わった → projectJson → render）

## 型探索の記録（全部の角を踏んだ消去法）

| 試した形 | 却下理由 |
|---|---|
| sideToggle bits（符号保存） | move/delete に非局所被害（触ってない兄弟の側が飛ぶ）・法則をすり抜ける |
| right/left バケツを MmmTree に | 順序が死ぬ（R,L,R と R,R,L が同一視）。バケツは MindmapTree の母語 |
| id→表（ECS 分離） | 宙ぶらりんの id・孤児プロップ・join。B 時代の却下が再確認された |
| Branch をノード型にした連鎖 | children の型が段ごとに違い trait で書けない・move が変換表 |
| SidedBranch / SidedImplied | 当初却下 → **トグル帰属の裁定反転で正当化**（側は隙間に付く） |
| Form.Implied | 当初却下 → **Skeleton enum で解決**（Form は 2 値のまま、状態は Skeleton が持つ） |

- **判定のリトマス**: 型分割を思いついたら move のシグネチャを書く。move が汚れる分割は
  操作の腹を横切っている。今回の採用形が通ったのは、Branch が「ノードの型」でなく
  「包み」で、深さ 3 以降が一様な Node だから（変換は center 化/降格の 1 ペアだけ）
- trait は「OR の代わり」ではない: データの分岐 = enum、振る舞いの契約 = trait。
  trait が刺さる席は反映戦略（v0/v1）と TS のカード描画

## 次のセッションでやること（未完の債務）

1. **probe（着手前 5 分）**: 配列パターン `match path { [] / [i] / [i, j] }`・
   `guard x is Some(y) else`・`Array::filter` — 代表関数が使っている未実測構文 3 種
2. **契約（plans/2026-08-30-doc-core/contract.md）の全面改訂** — 型・所有権・指紋の形式
3. **計画 T1〜T5 の型改訂 + 再査読 1 巡** — flat 前提のコード片の書き替え。
   C16 反転の差し替え（README に警告済み）もこのバッチに畳む
4. **殺す条件（Task 50）の物差しの移設** — op.mbt の関数行数 → 道具 4 つの腕数
5. **sig（指紋）の形式再設計** — Doc/Center/Branch/Node の走査に合わせる
6. **UI 翻訳層に 1 件追加** — バケツの index（左列の 2 番目）→ branches の index の写像
7. 保留事項なし — 「Center の複数列挙」は centers 配列 + Whole のままの splice で解決済み
