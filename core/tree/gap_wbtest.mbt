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
  let out = StringBuilder::new()
  let mut one = 0
  let mut many = 0
  for k in keys {
    let m = seen.get(k).unwrap()
    let gs = m.keys().collect()
    gs.sort()
    if gs.length() == 1 {
      one = one + 1
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
      #|H3 → S
      #|    空行0  ×2
      #|    空行1  ×4
      #|H4 → S
      #|    空行0  ×1
      #|    空行1  ×2
      #|I1 → C
      #|    空行0  ×2
      #|    空行1  ×5
      #|H2 → H3
      #|    空行0  ×1
      #|    空行1  ×4
      #|I1 → I2
      #|    空行0  ×7
      #|    空行1  ×4
      #|I2 → I3
      #|    空行0  ×4
      #|    空行1  ×4
      #|I3 → I4
      #|    空行0  ×1
      #|    空行1  ×1
      #|
    ),
  )
}
