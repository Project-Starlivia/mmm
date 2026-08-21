// 区切り（`---`）の掃除。
//
// `---` は「そこから下の左右が入れ替わる」印。ノードを動かす/消すことで
// 中身の無くなった区間の区切りは宙に浮くが、**1 本消すとそこから下の
// 左右が全部反転してしまう**。だから掃除は「下に残るノードから見た
// 区切りの本数の偶奇が変わらないように」**偶数本ずつ**消す。
//
// 規則（空になった連続区間ごとに）:
//   - 下に何も残らない（文書末尾まで空く）: その区間の区切りを全部消す
//   - 下が残る: 消せる区切りが偶数本なら全部、奇数本なら最後の 1 本を
//     残して消す（残った 1 本が上下の境目になる）
//   - 先頭の区間（右側の頭）が空いたときに残る「タイトル直後の `---`」は
//     「全部左」の正しい表現なので、消さない

///|
/// 動かす/消すことで空になる区間の、区切りの掃除の編集を作る。
fn dangling_sep_edits(order : Array[Int]) -> Array[Edit] {
  let ranges : Array[(Int, Int)] = []
  for id in order {
    let i = find_node(id)
    if i >= 0 {
      ranges.push((st.nodes[i].hs, st.nodes[i].sub_end))
    }
  }
  let moving = fn(hs : Int) -> Bool {
    for r in ranges {
      if hs >= r.0 && hs < r.1 {
        return true
      }
    }
    false
  }
  // nd.group と st.seps は文書全体で通し番号（compute_groups）なので、
  // ルートと無関係な別ツリー（2 つ目以降の `#` とその子孫、そこに書かれた
  // 区切り）がルート直下の区間と同じ番号を踏むことがある。区切りの生死は
  // **ルート自身の部分木だけ**で数え直す — でなければ、無関係なツリーが
  // 同じ番号にいるだけで「まだ使われている」と誤判定して掃除が漏れたり、
  // 逆に無関係なツリー内の区切りまで巻き込んで消してしまったりする。
  let ri = root_index()
  if ri < 0 {
    return []
  }
  let root_lo = st.nodes[ri].hs
  let root_hi = st.nodes[ri].sub_end
  let local_seps : Array[Int] = []
  for s in st.seps {
    if s >= root_lo && s < root_hi {
      local_seps.push(s)
    }
  }
  let n_groups = local_seps.length() + 1
  let any : Array[Bool] = Array::make(n_groups, false)
  let survives : Array[Bool] = Array::make(n_groups, false)
  for nd in st.nodes {
    if nd.hs >= root_lo && nd.hs < root_hi {
      let mut lg = 0
      for s in local_seps {
        if s < nd.hs {
          lg = lg + 1
        }
      }
      any[lg] = true
      if !moving(nd.hs) {
        survives[lg] = true
      }
    }
  }
  // 消す区切りの添字を集める。区切り s は区間 s+1 を始める
  // （区間 g の手前の区切り = s[g-1]、後ろの区切り = s[g]）
  let kill : Array[Int] = []
  let mut g = 0
  while g < n_groups {
    if !(any[g] && !survives[g]) {
      g = g + 1
      continue
    }
    let a = g
    let mut b = g
    while b + 1 < n_groups && any[b + 1] && !survives[b + 1] {
      b = b + 1
    }
    let list : Array[Int] = []
    if a >= 1 {
      list.push(a - 1)
    }
    for x = a; x < b; x = x + 1 {
      list.push(x)
    }
    let below = b < n_groups - 1 // 下にノードが残るか（区間は極大なので生存）
    if !below {
      for x in list {
        kill.push(x)
      }
    } else {
      // 後ろの区切り s[b] も候補。偶数本になるように選ぶ
      if (list.length() + 1) % 2 == 0 {
        for x in list {
          kill.push(x)
        }
        kill.push(b)
      } else {
        for x in list {
          kill.push(x)
        }
      }
    }
    g = b + 1
  }
  // 区切り行と、その後ろに続く空白行を消す
  let out : Array[Edit] = []
  let n = st.text.length()
  for si in kill {
    let p = local_seps[si]
    let mut q = p
    while q < n && cc(st.text, q) != 10 {
      q = q + 1
    }
    if q < n {
      q = q + 1
    }
    while q < n {
      let mut r = q
      // 空白行は空白と CR だけで出来ている（CRLF 文書では \r\n）
      while r < n &&
            cc(st.text, r) != 10 &&
            (is_space(cc(st.text, r)) || cc(st.text, r) == 13) {
        r = r + 1
      }
      if r < n && cc(st.text, r) == 10 {
        q = r + 1
      } else {
        break
      }
    }
    out.push(Edit::{ from: p, to: q, insert: "", removed: sub(st.text, p, q) })
  }
  out
}
