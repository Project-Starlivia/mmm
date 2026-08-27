// `---` の境界と、グループ・左右。
//
// **どの区切り行が構造として効くかを決めるのはここだけ。** 行の並び（連続した
// かたまり）はパーサが数え、木の形を見た有効性の判定と、グループ番号・左右の
// 割り当てをここが持つ。
//
// 記法: `---` 1 本 = 分割（同じ側に次のグループ）、2 本以上 = 分割 + 切り替え
// （そこから先は反対側）。本数の偶奇に意味を持たせないのは、手で 1 本足した
// だけで遠くの表示が変わる形を避けるため。

///|
/// 有効な境界 1 つ。`flip` なら、ここから先のグループは反対側へ伸びる。
priv struct Bound {
  start : Int // かたまりの最初の区切り行の行頭
  end : Int // 最後の区切り行の次の行頭
  flip : Bool // 区切り行が 2 本以上
}

///|
/// 区切りのかたまりのうち、**構造として効くもの**だけ。
///
/// 有効なのは「直前にノード P があり、直後の最初のノード F が P の木のルートの
/// 直下」であるとき。この 1 つの判定だけで
///   - front matter の `---`（P が無い）
///   - 木をまたぐ `---`（F が別の木のルート = 親なし）
///   - 深い階層の `---`（F の親がルートでない）
/// が、特別扱い無しに全部落ちる。
fn valid_bounds(
  seps : Array[SepRun],
  heads : Array[Heading],
  pidx : Array[Int],
) -> Array[Bound] {
  let out : Array[Bound] = []
  let hn = heads.length()
  let mut k = 0
  for r in seps {
    // k = そのかたまりより後ろの最初のノード。区切りもノードも文書順なので
    // 巻き戻らない(両方を 1 度ずつ歩けば足りる)
    while k < hn && heads[k].from < r.start {
      k = k + 1
    }
    if k == 0 || k >= hn {
      continue
    }
    let mut root = k - 1
    while pidx[root] >= 0 {
      root = pidx[root]
    }
    if pidx[k] != root {
      continue
    }
    out.push(Bound::{ start: r.start, end: r.end, flip: r.lines >= 2 })
  }
  out
}

///|
/// 境界で範囲を切る。**切るのは「その境界の直前で終わるノード」だけ** —
/// 一律に切ると、子を全部含むはずのルートの範囲まで切れて、境界の後ろの
/// グループがルートの子でなくなる（v1 で実際に踏んだ）。
///
/// 切る相手は、境界の直後のノード F の行頭でちょうど終わっているノード。
/// 後ろから辿り、境界を越えて伸びるノード（ルート）に当たったら止める。
fn cut_ranges(
  bounds : Array[Bound],
  heads : Array[Heading],
  range_end : Array[Int],
) -> Unit {
  let hn = heads.length()
  let mut k = 0
  for b in bounds {
    while k < hn && heads[k].from < b.start {
      k = k + 1
    }
    if k >= hn {
      continue
    }
    let f = heads[k].from
    for i = k - 1; i >= 0; i = i - 1 {
      if range_end[i] > f {
        break // 境界を越えて伸びる = この境界で終わっていない
      }
      if range_end[i] == f {
        range_end[i] = b.start
      }
    }
  }
}

///|
/// 木ごとにグループ番号と左右を割る。
///
/// **グループはルート直下の話**だが、値は枝の中の全ノードに配る — UI が
/// 「この枝はどっち側か」を導き直さなくていいように（同じ規則が 2 か所に
/// あると、片方だけ直したときに静かに食い違う）。
fn assign_groups(bounds : Array[Bound]) -> Unit {
  let mut bi = 0
  let mut group = 0
  let mut left = false
  for i = 0; i < st.nodes.length(); i = i + 1 {
    let nd = st.nodes[i]
    while bi < bounds.length() && bounds[bi].start < nd.from {
      group = group + 1
      if bounds[bi].flip {
        left = !left
      }
      bi = bi + 1
    }
    if nd.parent == -1 {
      // 新しい木。番号も側も振り出しに戻る（各木が自分の区切りを読む）
      group = 0
      left = false
    }
    nd.group = group
    nd.left = left
  }
}
