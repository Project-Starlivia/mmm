// 反映 — 前後の木を比べ、変わった所だけを原文 md に映す。
//
// 受け取るのは原文・前の Doc とその場所・後の Doc の 4 つで、返すのは編集列と
// その検証の答え。後の Doc が誰にどう作られたか（操作・undo のスナップショット）は知らない。
//
// 突き合わせるのは 3 つ:
//
//   原文     ユーザーが書いた md（書き方の流儀はここに在る）。要素ごとの居場所は場所
//   前の木   操作の前。要素ごとに、手前が空行で分かれるか（`parted`）
//   後の木   操作の後。同上
//
// **隙間は階層で決まる**（`gap_wbtest`）ので、前の木の隙間も後の木の隙間も木から直に言える。
// **前の木 → 後の木の差（操作がしたこと）だけを原文に写す。** 原文と前の木の差（流儀の差）は
// 写さないので、触っていない所の書き方は残る。要素はノードの行（ラベル）と中身 1 枚で、
// 位置合わせは id。**要素は手前の隙間（空行）を持つ** — 消えるときは隙間ごと消え、
// 増えるときは後の木の隙間を連れてきて、残る要素の隙間は後の木で変わったときだけ
// 書き換える。隙間そのものは原文の字で測る（空白だけの行 = 空行。読みと同じ）。
// 出来た文章を読み直して後の木と形が一致しなければ全文を正規形に落とす —
// **正しさはこの検証が持つ**ので、比較がどれだけ雑でも壊れない。ただし
// **正規形に落としても同じ形に読まれる**なら落とさない（形を md が決める木）。
// 答えは返り値に載せる（`same_shape`）— 呼ぶ側も同じことを知りたいので、二度読み直さない。
// 決めは docs/core.md「反映」。

///|
/// 編集 1 つ。from..to を insert に置き換える（CodeMirror の changes と同じ形）。
pub(all) struct Edit {
  from : Int
  to : Int
  insert : String
} derive(Eq, Debug, ToJson, FromJson)

///|
/// derive が作る `to_json` を method 形（`x.to_json()`）で呼ぶための宣言。
/// **上流は「derive のメソッドが暗黙に昇格する挙動を将来やめる」と言っている**ので、
/// 昇格に頼らず明示する — 無いと呼び出し側に非推奨の印が出る（#68）
pub extend Edit with ToJson::{to_json}

///|
/// 編集列（前の座標・from 順・重ならない）を md に当てた後の全文。
/// 続けて操作を映すとき、次の操作が読む md はこれ
pub fn patched(md : String, edits : Array[Edit]) -> String {
  let out = StringBuilder()
  let mut at = 0
  for e in edits {
    out.write_string(slice(md, at, e.from))
    out.write_string(e.insert)
    at = e.to
  }
  out.write_string(slice(md, at, md.length()))
  out.to_string()
}

///|
/// 反映の結果。
pub(all) struct Reflected {
  /// 後の木を映す編集列。from 順で、範囲は重ならない
  edits : Array[Edit]
  /// 当てて読み直した形が後の木と同じか。書けない木のときだけ偽で、
  /// そのとき文書順の番号（focus）は別のものを指す
  same_shape : Bool
} derive(Eq, Debug, ToJson)

///|
/// 後の木を映す編集列と、その検証。断片で書けなければ全文を正規形に落とす。
pub fn reflect(
  md : String,
  before : Doc,
  spots : Map[Int, Spot],
  after : Doc,
) -> Reflected {
  let planned = if before == after {
    Some([])
  } else {
    plan(md, before, spots, after)
  }
  if planned is Some(edits) && verified(md, edits, after) is Some(same_shape) {
    return { edits, same_shape, }
  }
  // 全文の正規形は断片と字が違うので、検証もやり直す
  let edits = [{ from: 0, to: md.length(), insert: serialize(after), }]
  { edits, same_shape: verified(md, edits, after) is Some(true), }
}

///|
/// 編集を当てて読み直した形の答え。**反映の正しさはこれが持つ。**
///
/// `Some(true)` は後の木そのもの。`Some(false)` は木とは違うが、**木を正規形に
/// 書いて読み直した形とは同じ** — 木が md に書けない形（中身の尻の水平線に骨格が
/// 続く `BorderBreak`）を持つときで、正規形に落としても同じ字に読まれるのだから
/// 全文へ落とす理由が無い。そのとき文書順の番号は別のものを指すので `same_shape` は偽。
/// `None` は断片で書けていない。
fn verified(md : String, edits : Array[Edit], after : Doc) -> Bool? {
  let read = shape(parse(patched(md, edits)))
  if read == shape(after) {
    Some(true)
  } else if read == shape(parse(serialize(after))) {
    Some(false)
  } else {
    None
  }
}

///|
/// 比較の途中。
priv struct Reflect {
  md : String
  spots : Map[Int, Spot]
  /// 前の木のノードを id で引く
  old : Map[Int, Node]
  /// 前の木の根を、根のノードの id で引く。根かどうかを見る
  roots_before : Map[Int, Root]
  /// 後の木の根を、根のノードの id で引く。断片に側と境界の綴りを書くのに要る
  roots_after : Map[Int, Root]
  /// 根の子ごとの、手前に書かれた境界の綴り（`turns`）を子の id で引く — 前の木
  turns_before : Map[Int, String]
  /// 同じ表の後の木
  turns_after : Map[Int, String]
  /// 原文の隙間 — 要素の手前の隙間の頭（空行が無ければ行頭）。前の木の id で引く
  gaps : Map[Int, Int]
  /// 前の木の隙間 — 階層が言う「手前は空行で分かれる」。前の木の id で引く
  parted_before : Map[Int, Bool]
  /// 後の木の隙間 — 同じ問いの、後の木の答え。後の木の id で引く
  parted_after : Map[Int, Bool]
  out : Array[Edit]
}

///|
/// 触った所だけの編集列。断片で書けない変化（frontmatter・根の並べ替え）
/// は None — 全文へ落ちる。
fn plan(
  md : String,
  before : Doc,
  spots : Map[Int, Spot],
  after : Doc,
) -> Array[Edit]? {
  guard before.frontmatter == after.frontmatter else { return None }
  // 木だけで分かる落ちは先に
  let olds_n = before.roots.map(x => x.node)
  let news_n = after.roots.map(x => x.node)
  guard aligned(ids(olds_n), ids(news_n)) else { return None }
  guard parted(before) is Some(parted_before) &&
    parted(after) is Some(parted_after) else {
    return None
  }
  let r : Reflect = {
    md,
    spots,
    old: Map([]),
    roots_before: Map::from_array(before.roots.map(x => (x.node.id, x))),
    roots_after: Map::from_array(after.roots.map(x => (x.node.id, x))),
    turns_before: turn_table(before.roots),
    turns_after: turn_table(after.roots),
    gaps: gaps_of(md, spots),
    parted_before,
    parted_after,
    out: [],
  }
  for root in before.roots {
    index(r.old, root.node)
  }
  // 文書の散文。容器の自分の尻は散文の頭（frontmatter の尻）
  reflect_body(r, before.body, after.body, spots.get(doc_id).unwrap().from, 0)
  reflect_children(r, spots.get(doc_id).unwrap().to, 0, olds_n, news_n, 1)
  Some(settle(r))
}

///|
/// 根の子ごとの、手前に書く境界の綴り（`turns`）を子の id で引く表。**根にしか要らない
/// 側と境界は、ここで 1 度だけ引いておく** — 反映の歩きに引数で持ち回らない
fn turn_table(roots : Array[Root]) -> Map[Int, String] {
  let out : Map[Int, String] = Map([])
  for root in roots {
    for i, t in turns(root) {
      if t is Some(rule) {
        out[root.node.children[i].id] = rule
      }
    }
  }
  out
}

///|
/// 部分木の断片。根なら側と境界の綴りも書く。
fn subtree(r : Reflect, x : Node, depth : Int) -> String {
  match r.roots_after.get(x.id) {
    Some(root) => fragment(x, depth, root.sides, root.rules)
    None => fragment(x, depth, [], [])
  }
}

///|
/// 原文の隙間 — 場所を持つものごとに、手前に続く空行の頭。**境界の直後の根の子は、
/// 手前の境界の水平線ごと隙間**（`Spot.border`）— その線は子の側の綴りなので、子を消せば
/// 一緒に消え、子の手前に差す要素は線より前に入る。Implicit の範囲の頭は最初の子の頭なので、
/// Implicit の隙間はその子の隙間（境界は Implicit が持つ）。
fn gaps_of(md : String, spots : Map[Int, Spot]) -> Map[Int, Int] {
  let out : Map[Int, Int] = Map([])
  for id, s in spots {
    out[id] = blank_start(md, line_start(md, s.border.unwrap_or(s.from)))
  }
  out
}

///|
/// 要素の頭の行 — 手前に境界の水平線が在ればその行、無ければ要素の行。隙間（`gaps`）は
/// この行の手前の空行で、要素を消す・差すときの行の頭もこれ。
fn lead(r : Reflect, id : Int) -> Int {
  let s = spot(r, id)
  line_start(r.md, s.border.unwrap_or(s.from))
}

///|
/// 前の木の同じ id と比べる。種類・畳み・子の並びが変わっていれば部分木ごと書く。
/// そうでなければ、行（ラベル）・中身・子の 3 つの列をそれぞれ差分にする —
/// 行が同じなら行には触らない（そこに選択の目印が在る）。
fn reflect_node(r : Reflect, x : Node, depth : Int) -> Unit {
  match r.old.get(x.id) {
    // 畳みは `<details>` が部分木を包むので、自分か子列が変わればそこから丸ごと
    Some(old) if sign_of(old) == sign_of(x) &&
      aligned(ids(old.children), ids(x.children)) &&
      (
        !(old.fold is Some(_) || x.fold is Some(_)) ||
        (same_self(old, x) && ids(old.children) == ids(x.children))
      ) => {
      let s = r.spots.get(x.id).unwrap()
      // 項目の中身と子は容器のラベルの桁（読んだ字下げ幅の右）に居る
      let col = match x.mark {
        Some(Item(offset~, ..)) => column(r.md, s.from) + offset
        _ => 0
      }
      // Implicit は行も中身も持たない（範囲は子の和）
      match x.mark {
        None => ()
        Some(_) => {
          let line_to = line_end(r.md, s.from)
          if !same_line(old, x) {
            let inner = label_end(r.md, r.spots, old)
            r.out.push({
              from: s.from,
              to: inner,
              insert: indent(
                fragment({ ..x, body: [], children: [], }, depth, [], []),
                column(r.md, s.from),
              ) +
              (if inner < line_to { pad(column(r.md, inner)) } else { "" }),
            })
          }
          reflect_body(r, old.body, x.body, line_to, col)
        }
      }
      // **根なら、境界の行も要素。** 側が変わった所の `---` の行だけを書き換える
      // （増える子は断片の頭に自分の境界を書く — `reflect_children`）
      if r.roots_before.contains(x.id) {
        turned(r, col, old, x)
      }
      // 元から子の無い容器に差す位置は前の木の自分の尻。そのとき場所の尻は
      // 自分の尻そのもの（setext の 2 行目も含む）
      reflect_children(
        r,
        spot(r, old.id).to,
        col,
        old.children,
        x.children,
        // 項目の中は、その項目の深さを 0 とした文書（書く側の `list_item` と同じ）
        if x.mark is Some(Item(..)) {
          1
        } else {
          depth + 1
        },
      )
    }
    // **名前の無い行に名前が付いただけ**（Implicit を綴った見出し）なら、行を 1 本差して子へ降りる。
    // 部分木ごと書くと、触っていない中身の位置が正規形へ動く
    Some(old) if old.mark is None &&
      sign_of(x) is Some(Heading) &&
      x.fold is None &&
      x.body.is_empty() &&
      ids(old.children) == ids(x.children) => {
      let s = spot(r, old.id)
      let at = line_start(r.md, s.from)
      r.out.push({
        from: at,
        to: at,
        insert: pad(column(r.md, s.from)) +
        fragment({ ..x, children: [], }, depth, [], [])
        .trim_end(chars="\n")
        .to_owned() +
        "\n",
      })
      reflect_node(r, { ..x, mark: None, label: "", }, depth)
    }
    _ => replace(r, x, depth)
  }
}

///|
/// ノードの行の尻（改行の次）。**名前の無い項目は、中身か子がマーカーの行に乗る**
/// （`- # h`）ので、行はその手前まで。
fn label_end(md : String, spots : Map[Int, Spot], x : Node) -> Int {
  [..x.body.map(b => b.id), ..x.children.map(k => k.id)]
  .iter()
  .filter_map(id => spots.get(id).map(sp => sp.from))
  .fold(init=line_end(md, spots.get(x.id).unwrap().from), (a, b) => {
    if b < a {
      b
    } else {
      a
    }
  })
}

///|
/// 根の子の手前の境界の行を、前後の側の違いだけ書き換える（`turns_before` と `turns_after`）。
/// **消すのは残る子で要らなくなった行だけ、足すのは残る子の手前に要るようになった行だけ** —
/// 消える子の行は子の隙間ごと消え（`gaps`）、増える子は断片の頭に自分の境界を書く
/// （`reflect_children`）。
/// 子の差分より先に積む — 同じ位置に隙間の書き換えが来ても、境界が手前に並ぶように
fn turned(r : Reflect, col : Int, old : Node, x : Node) -> Unit {
  let kept : Set[Int] = Set::from_array(ids(x.children))
  for k in old.children {
    guard kept.contains(k.id) &&
      r.turns_before.contains(k.id) &&
      !r.turns_after.contains(k.id) else {
      continue
    }
    if border_line(r, k.id) is Some((from, to)) {
      r.out.push({ from, to, insert: "", })
    }
  }
  let was : Set[Int] = Set::from_array(ids(old.children))
  for k in x.children {
    guard was.contains(k.id) &&
      !r.turns_before.contains(k.id) &&
      r.turns_after.get(k.id) is Some(rule) else {
      continue
    }
    let at = r.gaps.get(k.id).unwrap()
    r.out.push({ from: at, to: at, insert: "\n" + pad(col) + rule + "\n", })
  }
}

///|
/// 前の木で子 `id` の手前に書かれた境界の行と、その手前の空行 — 子の隙間の頭から、
/// 子の行の手前の空行まで。**行の頭は読みが控えた**（`Spot.border`）— 原文を読み直して
/// 水平線を探さない。境界が無ければ None（消さない）
fn border_line(r : Reflect, id : Int) -> (Int, Int)? {
  let s = spot(r, id)
  guard s.border is Some(_) else { return None }
  Some((r.gaps.get(id).unwrap(), blank_start(r.md, line_start(r.md, s.from))))
}

///|
/// 残る要素の順が前後で同じか。違えば並べ替えで、容器（列）ごと書く。
fn aligned(olds : Array[Int], news : Array[Int]) -> Bool {
  let now = Map::from_array(news.map(id => (id, ())))
  let was = Map::from_array(olds.map(id => (id, ())))
  olds.filter(id => now.contains(id)) == news.filter(id => was.contains(id))
}

///|
/// 列 1 つの差分に要るもの。
priv struct Seq {
  olds : Array[Int]
  news : Array[Int]
  /// 元から空の列に差す位置 — 容器の自分の尻
  own : Int
  /// 列の桁
  col : Int
  /// 増える要素の手前に空行を置くか。parted_after の答え（項目の列は 原文の兄弟の流儀が先）
  parted : (Int) -> Bool
  /// 残る要素に降りる
  keep : (Int) -> Unit
  /// 増える要素の断片
  make : (Int) -> String
}

///|
/// 列の差分。子の列と中身の列で共用する。
///
/// 列の頭の境目（列の手前の隙間）は要素でなく**列のもの** — 頭の要素が消えても、
/// 頭に要素が増えても、境目の字は原文のまま残る。頭より後ろの隙間は要素のもの。
///
/// - 消える並び（連続して消える要素は 1 つ）は、手前の隙間から最後の尻まで消す。
///   列の頭の並びで後ろに残る要素が居れば、境目を残してその要素の行頭まで消す
///   （parted_after がその要素を文書の頭と言うなら、境目ごと）
/// - 残る要素には降りる。手前の隙間が parted_before と parted_after で違えば（文書の頭になった /
///   頭でなくなった、列が詰まった / 空いた）、隙間だけ書き換える。列の頭で消し差しが
///   あった要素は境目を引き継いでいるので触らない
/// - 増える並びは、次に残る要素の隙間の頭か、前に残る要素の尻か、容器の自分の尻に差し、
///   1 つずつ parted_after の隙間を連れてくる。列の頭に差すなら境目の後ろに置き、隙間は
///   次に残る要素との間に付ける
fn reflect_seq(r : Reflect, q : Seq) -> Unit {
  placed(r, q, erased(r, q))
}

///|
/// 消える並びを消す。連続して消える要素は 1 つにまとめ、**手前の隙間から最後の尻まで**。
/// 列の頭の並びで後ろに残る要素が居れば、境目を残してその要素の行頭まで消す
/// （parted_after がその要素を文書の頭と言うなら、境目ごと）。
/// 返すのは**境目を引き継いだ要素** — その隙間は `placed` が書き換えない。
fn erased(r : Reflect, q : Seq) -> Int? {
  let now = Map::from_array(q.news.map(id => (id, ())))
  // 列の頭に新しい要素が来るか（頭の並びを消すとき、境目を残すかに要る）
  // 列ごと消えるとき、生まれ直すなら境目を残す（全部消えたなら news の頭は必ず新しい）
  let head_born = !q.news.is_empty()
  let mut seam : Int? = None
  let mut i = 0
  let mut kept_before = false
  while i < q.olds.length() {
    if now.contains(q.olds[i]) {
      kept_before = true
      i = i + 1
      continue
    }
    let start = i
    while i < q.olds.length() && !now.contains(q.olds[i]) {
      i = i + 1
    }
    let first = q.olds[start]
    let last = spot(r, q.olds[i - 1]).to
    let head = !kept_before
    let (from, to, insert) = if head && i < q.olds.length() {
      let next = q.olds[i]
      seam = Some(next)
      // 後ろに残る要素が後の列の頭になるなら、境目の空行は parted_after に合わせる — 文書の頭なら
      // 境目ごと消し、頭の要素が空行を要るのに境目に無ければ足す（境界の `---` を持つ子が
      // 頭になれば、名前の行の直下の線は setext の下線に読まれる）。そうでなければ境目は残す
      let now_head = q.news.get(0) == Some(next)
      let had = r.parted_before.get(first).unwrap_or(true)
      let has = r.parted_after.get(next).unwrap_or(had)
      (
        if now_head && headless(r, next) {
          r.gaps.get(first).unwrap()
        } else {
          lead(r, first)
        },
        lead(r, next),
        if now_head && has && !had {
          "\n"
        } else {
          ""
        },
      )
    } else if head && head_born {
      (lead(r, first), last, "")
    } else if head &&
      r.gaps.get(first) == Some(spot(r, doc_id).from) &&
      stale_head(r, last) {
      // 文書の頭の列が丸ごと消え、後ろに続く要素（列の外）が頭になる。その要素の隙間は
      // 誰も書き換えないので、列の境目を引き継がせ、消す要素の後ろの空行ごと消す
      (lead(r, first), blank_end(r.md, last), "")
    } else {
      (r.gaps.get(first).unwrap(), last, "")
    }
    r.out.push({ from, to, insert, })
  }
  seam
}

///|
/// 位置 `at` のすぐ後ろに書かれた要素を、parted_before がもう文書の頭と言うか。**中身が根の
/// 後ろに書かれた文書**（`- a / ---`）では、正規形は中身を先に書くので parted_before は頭と言うが、
/// 原文では前に要素が居る。そのとき parted_before と parted_after は同じなので、`gapped` は隙間を書き換えない
fn stale_head(r : Reflect, at : Int) -> Bool {
  let next = if column(r.md, at) == 0 { at } else { line_end(r.md, at) }
  r.gaps.iter().any(p => p.1 == next && r.parted_before.get(p.0) == Some(false))
}

///|
/// 残る要素と増える要素を並べる。残る要素には降りて、手前の隙間が parted_before と parted_after で
/// 違えば（`gapped`）隙間だけ書き換える。増える並びは**次に残る要素の隙間の頭か、
/// 前に残る要素の尻か、容器の自分の尻**に差す。列の頭に差すなら境目の後ろに置き、
/// 隙間は次に残る要素との間に付ける。
fn placed(r : Reflect, q : Seq, seam : Int?) -> Unit {
  let was = Map::from_array(q.olds.map(id => (id, ())))
  let pend : Array[Int] = []
  let mut seam = seam
  let mut kept : Int? = None
  for id in q.news {
    guard was.contains(id) else {
      pend.push(id)
      continue
    }
    if !pend.is_empty() {
      match kept {
        // 列の頭。境目の後ろに置き、隙間は次に残る要素との間に。
        // 差す要素が文書の頭なら（手前に何も残らない）、境目ごと置き換える
        None => {
          let head = lead(r, id)
          r.out.push({
            from: if headless(r, pend[0]) {
              r.gaps.get(id).unwrap()
            } else {
              head
            },
            to: head,
            insert: grown(q, pend, lead=false) + gap_text(q, id),
          })
          seam = Some(id)
        }
        Some(_) => {
          let pos = r.gaps.get(id).unwrap()
          r.out.push({ from: pos, to: pos, insert: grown(q, pend, lead=true), })
        }
      }
      pend.clear()
    }
    if seam != Some(id) {
      gapped(r, id)
    }
    (q.keep)(id)
    kept = Some(id)
  }
  guard !pend.is_empty() else { return }
  let (pos, lead) = match (kept, q.olds.get(0)) {
    (Some(k), _) => (spot(r, k).to, true)
    // 列ごと消えて生まれ直す。境目は残してあるので頭の隙間は要らない
    (None, Some(first)) => (lead(r, first), false)
    // 元から空の列。境目は無いので parted_after の隙間から
    (None, None) => (q.own, true)
  }
  r.out.push({ from: pos, to: pos, insert: grown(q, pend, lead~), })
}

///|
/// 残る要素の手前の隙間。parted_before と parted_after で違えば（文書の頭になった / 頭でなくなった、
/// 列が詰まった / 空いた）、**隙間だけ**書き換える。
fn gapped(r : Reflect, id : Int) -> Unit {
  let had = r.parted_before.get(id).unwrap_or(false)
  let has = r.parted_after.get(id).unwrap_or(had)
  guard had != has else { return }
  r.out.push({
    from: r.gaps.get(id).unwrap(),
    to: lead(r, id),
    insert: if has {
      "\n"
    } else {
      ""
    },
  })
}

///|
/// 増える並びの字。**1 つずつ parted_after の隙間を連れてくる。**
/// `lead` が偽なら先頭の隙間は付けない（列の頭の境目は原文のまま残る）。
fn grown(q : Seq, pend : Array[Int], lead~ : Bool) -> String {
  pend
  .mapi((k, x) => {
    (if k == 0 && !lead { "" } else { gap_text(q, x) }) +
    pad(q.col) +
    indent((q.make)(x), q.col)
  })
  .join("")
}

///|
/// 増える要素の手前の隙間の字。
fn gap_text(q : Seq, id : Int) -> String {
  if (q.parted)(id) {
    "\n"
  } else {
    ""
  }
}

///|
/// 文書の頭に来る要素（parted_after が「手前に隙間は無い」と言う）。その手前の境目は消す。
fn headless(r : Reflect, id : Int) -> Bool {
  !r.parted_after.get(id).unwrap_or(true)
}

///|
/// その要素の場所。
fn spot(r : Reflect, id : Int) -> Spot {
  r.spots.get(id).unwrap()
}

///|
/// 子列の差分。残った子には降りる。項目の列は 原文の兄弟の流儀（詰まっているか）を
/// 増える要素にも写す — 正規形は流儀を知らないので、ここだけは原文が先。
/// 増える根の子は、断片の頭に手前の境界の綴りを書く（`turns_after`）。
fn reflect_children(
  r : Reflect,
  own : Int,
  col : Int,
  olds : Array[Node],
  news : Array[Node],
  depth : Int,
) -> Unit {
  let now = Map::from_array(news.map(x => (x.id, x)))
  let old_ids = ids(olds)
  let style = loosened(r, news, old_ids)
  reflect_seq(r, {
    olds: old_ids,
    news: ids(news),
    own,
    col,
    parted: id => {
      match style {
        Some(loose) => loose
        None => r.parted_after.get(id).unwrap_or(true)
      }
    },
    keep: id => reflect_node(r, now.get(id).unwrap(), depth),
    make: id => {
      let text = subtree(r, now.get(id).unwrap(), depth)
      match r.turns_after.get(id) {
        Some(line) => line + "\n\n" + text
        None => text
      }
    },
  })
}

///|
/// 読んだ列の流儀 — 項目の間が空いているか。**正規形は流儀を知らない**ので、
/// 項目の列だけは増える要素にも 原文の兄弟の流儀を写す。2 つ目からの兄弟の隙間で
/// 測る（先頭の隙間は列の手前のもの）。項目でない列と、兄弟が 1 つしかない列は
/// 流儀を持たないので None — そのときは parted_after に従う。
fn loosened(r : Reflect, news : Array[Node], olds : Array[Int]) -> Bool? {
  guard news.get(0).map(sign_of) is Some(Some(Item)) && olds.length() >= 2 else {
    return None
  }
  Some(olds[1:].iter().any(id => r.gaps.get(id).unwrap() < lead(r, id)))
}

///|
/// 中身の列の差分。内容だけ変わった中身はその範囲を置き換える。
/// 並びが変われば列ごと — 全部消して全部差す（同じ規則で隙間が付く）。
fn reflect_body(
  r : Reflect,
  olds : Array[Block],
  news : Array[Block],
  own : Int,
  col : Int,
) -> Unit {
  if olds == news {
    return
  }
  let was = Map::from_array(olds.map(b => (b.id, b)))
  let now = Map::from_array(news.map(b => (b.id, b)))
  let old_ids = olds.map(b => b.id)
  let new_ids = news.map(b => b.id)
  let make = (id : Int) => prose([now.get(id).unwrap()])
  let parted = (id : Int) => r.parted_after.get(id).unwrap_or(true)
  if !aligned(old_ids, new_ids) {
    reflect_seq(r, {
      olds: old_ids,
      news: [],
      own,
      col,
      parted,
      keep: _ => (),
      make,
    })
    reflect_seq(r, {
      olds: [],
      news: new_ids,
      own: r.gaps.get(old_ids[0]).unwrap(),
      col,
      parted,
      keep: _ => (),
      make,
    })
    return
  }
  reflect_seq(r, {
    olds: old_ids,
    news: new_ids,
    own,
    col,
    parted,
    keep: id => {
      let b = now.get(id).unwrap()
      let old = was.get(id).unwrap()
      // 書き戻す字は意味と原文の両方で決まるので、両方を見る
      if old.content != b.content || old.source != b.source {
        let s = r.spots.get(id).unwrap()
        r.out.push({
          from: s.from,
          to: s.to,
          insert: indent(make(id), column(r.md, s.from)),
        })
      }
    },
    make,
  })
}

///|
/// 編集列を整える。from 順（同じ from なら幅の狭い順 — 差し込みが置き換えより先、
/// 同じなら出た順）に並べ、隣り合う編集は 1 つに繋ぎ、行の途中（改行の無い末尾）に
/// 字を書く編集は改行から始める。繋いでから見るので、消した後に何が残るかで決まる。
fn settle(r : Reflect) -> Array[Edit] {
  let order = Array::makei(r.out.length(), i => i)
  order.sort_by((a, b) => {
    let (x, y) = (r.out[a], r.out[b])
    if x.from != y.from {
      x.from - y.from
    } else if x.to != y.to {
      x.to - y.to
    } else {
      a - b
    }
  })
  let out : Array[Edit] = []
  for i in order {
    let e = r.out[i]
    match out.last() {
      Some(p) if p.to == e.from =>
        out[out.length() - 1] = { ..p, to: e.to, insert: p.insert + e.insert, }
      _ => out.push(e)
    }
  }
  out.map(e => {
    if e.insert != "" && mid_line(r.md, e.from) {
      { ..e, insert: "\n" + e.insert, }
    } else {
      e
    }
  })
}

///|
/// その位置が行の途中か — 直前が空白でない字。行頭の字下げの後ろ（項目のマーカーの
/// 手前）も、マーカーの後ろ（`- # h` の見出しの頭）も、書いてよい行の頭。
fn mid_line(md : String, at : Int) -> Bool {
  at > line_start(md, at) && md[at - 1] != ' ' && md[at - 1] != '\t'
}

///|
/// 部分木ごと断片にして、場所に差す。
fn replace(r : Reflect, x : Node, depth : Int) -> Unit {
  r.out.push(patch(r, x.id, subtree(r, x, depth)))
}

///|
/// 場所 id の範囲を text で置き換える編集。項目の入れ子は列 0 で出るので、
/// 容器の桁に揃える（1 行目はもう容器が字下げしている）。
fn patch(r : Reflect, id : Int, text : String) -> Edit {
  // 前の木に無い id はここへ来ない — 親の子 id 列が違うので親が書かれる
  let s = r.spots.get(id).unwrap()
  { from: s.from, to: s.to, insert: indent(text, column(r.md, s.from)), }
}

///|
/// 行が同じか — 種類・ラベル・畳み。綴りの書き方と、中身と子は見ない。
fn same_line(a : Node, b : Node) -> Bool {
  sign_of(a) == sign_of(b) && a.label == b.label && a.fold == b.fold
}

///|
/// ノード自身が同じか — 行（ラベル・畳み）と中身。子は見ない。
fn same_self(a : Node, b : Node) -> Bool {
  same_line(a, b) && a.body == b.body
}

///|
fn index(into : Map[Int, Node], x : Node) -> Unit {
  into[x.id] = x
  for k in x.children {
    index(into, k)
  }
}

///|
fn ids(xs : Array[Node]) -> Array[Int] {
  xs.map(x => x.id)
}
