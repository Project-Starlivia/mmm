///|
/// **隙間は階層で決まる。** 隣り合うひと切れの関係（綴り・深さ・裁定）だけで、
/// 間に入る空行の数が決まるか。字下げは容器の桁、改行コードは文書のものなので、
/// どちらも数えない。
///
/// 決まらないのは 7 つだけで、**全部が「容器とその最初の中身」の関係**
/// （親の行 → 最初の子、項目 → その中身、行 → 畳みの閉じ）。そこは容器が息を
/// するかどうかという書き手の流儀で、規則が勝手に決めてよいものではない。
///
/// **差す piece の隙間はここから出す** — 階層で決まる関係はその答えを使い、
/// 決まらない 7 つは同じ文書の中の同じ関係を真似る（無ければ空行 1）。
/// 8 つ目がぶれ始めたらここが鳴る。

///|
/// ひと切れの構造上の顔。骨格は綴りと深さ、あとは裁定の種類
fn sig_of(p : Piece) -> String {
  match p.verdict {
    None => "gap"
    Some(Line(depth~, mark~, ..)) =>
      match mark {
        Some(Heading(..)) => "H\{depth}"
        Some(Item(loose~, ..)) =>
          if loose {
            "I\{depth}loose"
          } else {
            "I\{depth}"
          }
        None => "X\{depth}"
      }
    Some(Border(..)) => "B"
    Some(FoldOpen(..)) => "F"
    Some(FoldClose) => "S"
    Some(Card(..)) => "C"
  }
}

///|
test "見本 — 隙間は階層で決まる。決まらないのは 7 つの関係だけ" {
  let seen : Map[String, Map[String, Int]] = Map([])
  for md in read_corpus {
    let ps = notation(md).pieces
    let mut i = 0
    while i < ps.length() {
      guard sig_of(ps[i]) != "gap" else {
        i = i + 1
        continue
      }
      // 次の非隙間までの隙間
      let mut j = i + 1
      let mut gap = ""
      while j < ps.length() && sig_of(ps[j]) == "gap" {
        gap = gap + slice(md, ps[j].at.from, ps[j].at.to)
        j = j + 1
      }
      guard j < ps.length() else { break }
      let key = "\{sig_of(ps[i])} → \{sig_of(ps[j])}"
      let by = match seen.get(key) {
        Some(m) => m
        None => {
          let m : Map[String, Int] = Map([])
          seen[key] = m
          m
        }
      }
      // 空行の数だけを見る。字下げ（容器の桁）と改行コードは別のもの
      let mut nl = 0
      for c in gap {
        if c == '\n' {
          nl = nl + 1
        }
      }
      let g = "空行\{nl}"
      by[g] = by.get(g).unwrap_or(0) + 1
      i = j
    }
  }
  let keys = seen.keys().collect()
  keys.sort()
  let out = StringBuilder()
  let mut one = 0
  let mut many = 0
  for k in keys {
    let m = seen.get(k).unwrap()
    let gs = m.keys().collect()
    gs.sort()
    if gs.length() == 1 {
      one = one + 1
      out.write_string("\{k}  \{gs[0]}\n")
    } else {
      many = many + 1
      out.write_string("\{k}\n")
      for g in gs {
        out.write_string("    \{g}  ×\{m.get(g).unwrap()}\n")
      }
    }
  }
  inspect(
    "1 通りの鍵 \{one} / ぶれる鍵 \{many}\n\{out}",
    content=(
      #|1 通りの鍵 56 / ぶれる鍵 7
      #|B → F  空行1
      #|C → B  空行1
      #|C → C  空行1
      #|C → S  空行1
      #|S → B  空行1
      #|S → F  空行1
      #|S → S  空行1
      #|B → H2  空行1
      #|B → H3  空行1
      #|B → I2  空行1
      #|C → H1  空行1
      #|C → H2  空行1
      #|C → H3  空行1
      #|C → I2  空行1
      #|F → H2  空行1
      #|F → H3  空行1
      #|F → H4  空行1
      #|F → I2  空行1
      #|H1 → B  空行1
      #|H1 → C  空行1
      #|H1 → F  空行1
      #|H2 → B  空行1
      #|H2 → C  空行1
      #|H2 → F  空行1
      #|H2 → S  空行1
      #|H3 → B  空行1
      #|H3 → F  空行1
      #|H3 → S
      #|    空行0  ×2
      #|    空行1  ×4
      #|H4 → S
      #|    空行0  ×1
      #|    空行1  ×2
      #|I1 → C
      #|    空行0  ×2
      #|    空行1  ×5
      #|I1 → F  空行1
      #|I2 → B  空行1
      #|I2 → C  空行1
      #|I2 → F  空行1
      #|I2 → S  空行1
      #|I3 → S  空行1
      #|S → H2  空行1
      #|S → H3  空行1
      #|S → I2  空行1
      #|H1 → H1  空行1
      #|H1 → H2  空行1
      #|H1 → H3  空行1
      #|H1 → I2  空行1
      #|H2 → H2  空行1
      #|H2 → H3
      #|    空行0  ×1
      #|    空行1  ×4
      #|H2 → H4  空行1
      #|H2 → I3  空行1
      #|H3 → H2  空行1
      #|H3 → H3  空行1
      #|I1 → H1  空行1
      #|I1 → H2  空行0
      #|I1 → H3  空行1
      #|I1 → I1  空行0
      #|I1 → I2
      #|    空行0  ×7
      #|    空行1  ×4
      #|I2 → H2  空行1
      #|I2 → H3  空行1
      #|I2 → I2  空行0
      #|I2 → I3
      #|    空行0  ×4
      #|    空行1  ×4
      #|I3 → H3  空行1
      #|I3 → I4
      #|    空行0  ×1
      #|    空行1  ×1
      #|B → I2loose  空行1
      #|I1loose → I1loose  空行1
      #|I2loose → I2loose  空行1
      #|
    ),
  )
}

///|
/// **正規形の隙間も、階層だけで言える。** 合流の base / theirs は `parted` が木から
/// 直に答え、正規形を書いて読み直さない。ここはその答えを、実際に書いて読み直した
/// 字（`spelt`）と突き合わせる — 我々が塊を分ける規則を変えても、ライブラリが
/// 変えても鳴る。
///
/// 見本 166 通りと、**合流が実際に使う後の木** — 見本 11 通り × 全ノード × 全部の
/// 変え方（`merge_law_wbtest` と同じ総当たり）。
test "見本 — 階層が言う隙間は、正規形の字と一致する" {
  let bad : Array[String] = []
  let mut trees = 0
  let mut asked = 0
  fn look(doc : Doc, what : String) {
    guard spelt(doc) is Some(want) else { return }
    guard parted(doc) is Some(got) else {
      bad.push("\{what}: parted が折れた")
      return
    }
    trees = trees + 1
    let keys = want.keys().collect()
    keys.sort()
    for id in keys {
      asked = asked + 1
      if got.get(id) != Some(want.get(id).unwrap()) {
        bad.push(
          "\{what}: id \{id} は 正規形 \{want.get(id).unwrap()} / 階層 \{got.get(id).to_json().stringify()}",
        )
      }
    }
  }

  for md in read_corpus {
    look(build(md).0, md.escape())
  }
  for md in corpus {
    let (before, _) = build(md)
    look(before, md.escape())
    for id in all_ids(before) {
      for how in [Relabel, Delete, Adopt, AddBlock, DropBlock, SetBlock, Swap] {
        let after = changed(before, id, how)
        if after == before || !check(after).is_empty() {
          continue
        }
        look(after, "\{name(how)} \{id} in \{md.escape()}")
      }
    }
  }
  inspect(
    "木 \{trees} / 要素 \{asked} / 違い \{bad.length()}\n" + bad.join("\n"),
    content=(
      #|木 310 / 要素 972 / 違い 0
      #|
    ),
  )
}

///|
/// 正規形の隙間を**字で**測る（試験の物差し）。木を正規形に書いて読み直し、要素ごとに
/// 手前に空行が有るかを見る。要素は文書順に 1 対 1 で並ぶので順に組にする。
/// 並ばなければ None — 合流もそこは全文へ落ちるので、突き合わせる相手が居ない。
fn spelt(doc : Doc) -> Map[Int, Bool]? {
  let canon = serialize(doc)
  let (read, spans) = build(canon)
  let mine = spelt_elements(doc)
  let theirs = spelt_elements(read)
  guard mine.length() == theirs.length() else { return None }
  let out : Map[Int, Bool] = Map([])
  for i, id in mine {
    let s = spans.get(theirs[i]).unwrap()
    let head = line_start(canon, s.from)
    out[id] = blank_start(canon, head) < head
  }
  Some(out)
}

///|
/// 要素（Implicit でないノードと中身）の id を文書順に。
fn spelt_elements(doc : Doc) -> Array[Int] {
  let out : Array[Int] = []
  fn node(x : Node) {
    if x.mark is Some(_) {
      out.push(x.id)
    }
    for b in x.body {
      out.push(b.id)
    }
    for k in x.children {
      node(k)
    }
  }

  for b in doc.body {
    out.push(b.id)
  }
  for r in doc.roots {
    node(r.node)
  }
  out
}
