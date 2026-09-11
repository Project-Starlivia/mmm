// md を木にする入口と、木の住所（id・番号・地番）。
//
// **裁定は `deem.mbt`、組み立ては `assemble.mbt`。** ここに在るのは 2 つを繋ぐ 1 行と、
// 出てきた木のどこに何が在るかを言う型。地番は Doc に載せず並べて返す — 載せると
// Doc が特定の原文に縛られ、手で組む木に在り得ない欄が生える。

///|
/// md を木にする。
pub fn parse(md : String) -> Doc {
  build(md).0
}

///|
/// 地番。ノードが原文のどこに書かれているか。`label` はラベルの頭（マーカーの後ろ）で、
/// 地図の選択の位置（ts の anchors）に使うラベルの頭。位置は CodeMirror が編集で写す。
/// Implicit と文書の散文は行を持たないので None。
pub(all) struct Spot {
  from : Int
  label : Int?
  to : Int
} derive(Eq, Debug, ToJson)

///|
/// md を木にする。**読みが裁定を下し、組み立てがひと切れの列から枠を積む。**
pub fn build(md : String) -> (Doc, Map[Int, Spot]) {
  assemble(notation(md))
}

///|
/// 地番の指紋。`id[from,label,to]` を id 順に並べる。
pub fn spans_sig(md : String) -> String {
  let (_, spans) = build(md)
  let ids = spans.keys().collect()
  ids.sort()
  ids
  .map(id => {
    match spans.get(id) {
      Some(s) => {
        let label = match s.label {
          Some(l) => l.to_string()
          None => "-"
        }
        "\{id}[\{s.from},\{label},\{s.to}]"
      }
      None => ""
    }
  })
  .join(" ")
}

///|
/// 文書そのものの id。親を指すときの番兵。
pub let doc_id : Int = 1

///|
/// id のノード・中身が、文書順に振り直されたら得る番号。読みと同じ振り方
/// （文書の中身 → 根ごとに ノード → その中身 → 子）なので、木を書き戻して
/// 読み直したときの id を先に言える。操作の後の focus を読み替えるのに使う。
/// 無い id は None。
pub fn number(doc : Doc, id : Int) -> Int? {
  if id == doc_id {
    return Some(doc_id)
  }
  let next : Ref[Int] = { val: doc_id + 1, }
  fn blocks(body : Array[Block]) -> Int? {
    for b in body {
      if b.id == id {
        return Some(next.val)
      }
      next.val = next.val + 1
    }
    None
  }

  fn node(x : Node) -> Int? {
    if x.id == id {
      return Some(next.val)
    }
    next.val = next.val + 1
    match blocks(x.body) {
      Some(n) => return Some(n)
      None => ()
    }
    for k in x.children {
      match node(k) {
        Some(n) => return Some(n)
        None => ()
      }
    }
    None
  }

  match blocks(doc.body) {
    Some(n) => return Some(n)
    None => ()
  }
  for r in doc.roots {
    match node(r.node) {
      Some(n) => return Some(n)
      None => ()
    }
  }
  None
}
