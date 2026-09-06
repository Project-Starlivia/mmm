// 親子をつなぐラインの形。DOM を知らない、経路（SVG の d）を作るだけの層。
//
//   親の縁 --曲線--> 子の縁
//
// 座標はすべて u・v のローカル座標（親の出口が原点）で組む。
//
// 経路は「制御点 2 つをそのまま持つ三次ベジェ」1 種類のみ。かつては経路の種類
// (quad/cubic/sweep/arc/line/diagonal/elbow/spine) や見た目の修飾
// (先細り・手描き風ゆらぎ・破線・階層別の太さ・下線)を選べる調整パネルが
// あったが、2026-08-15 にパネルごと撤去した。実際に選ばれ続けているのは
// この 1 本だけだったので、生きている式だけへ畳んだ。

///|
/// 曲線の形。実文書の上で詰めた値（出発点は見本 Vector.svg）。
/// ハンドル 2 つをそのまま持つ三次ベジェで、子を (1,1) とする正規化座標。
/// h1 は親から、h2 は子から測る（親側は縦に立ち上がり、子側は横から入る）。
///
/// 太さはここに持たない。CSS の `.edge` が唯一の宣言
priv struct Curve {
  h1u : Double
  h1v : Double
  h2u : Double
  h2v : Double
}

///|
let curve : Curve = { h1u: 0.08, h1v: 0.27, h2u: 0.58, h2v: 0.05, }

///|
/// 経路の一区間。座標は u, v の並び
pub(all) enum Seg {
  /// 直線。終点
  L(Double, Double)
  /// 三次ベジェ。制御点 2 つ + 終点
  C(Double, Double, Double, Double, Double, Double)
} derive(Eq, Debug)

///|
/// 親 → 子 の経路をローカル座標で組み立てる。du = 成長軸方向の距離、
/// dv = 兄弟軸方向の段差。始点は常に (0,0)
pub fn edge_segs(du : Double, dv : Double) -> Array[Seg] {
  if dv.abs() < 0.5 {
    return [L(du, dv)] // 真横に並ぶ親子は直線
  }
  [
    C(
      du * curve.h1u,
      dv * curve.h1v,
      du - du * curve.h2u,
      dv - dv * curve.h2v,
      du,
      dv,
    ),
  ]
}

///|
/// 折れ線に落とす（線分距離判定などに使う）。始点 (0,0) を含む
pub fn flatten(segs : Array[Seg], per : Int) -> Array[Pt] {
  let pts : Array[Pt] = [{ x: 0, y: 0, }]
  let mut cu = 0.0
  let mut cv = 0.0
  for s in segs {
    match s {
      L(u, v) => {
        pts.push({ x: u, y: v, })
        cu = u
        cv = v
      }
      C(au, av, bu, bv, eu, ev) => {
        for i in 1..<=per {
          let t = i.to_double() / per.to_double()
          let m = 1.0 - t
          pts.push({
            x: m * m * m * cu +
            3.0 * m * m * t * au +
            3.0 * m * t * t * bu +
            t * t * t * eu,
            y: m * m * m * cv +
            3.0 * m * m * t * av +
            3.0 * m * t * t * bv +
            t * t * t * ev,
          })
        }
        cu = eu
        cv = ev
      }
    }
  }
  pts
}

///|
/// 数の綴り。JS の `${n}` と同じ — 整数なら小数点を出さず、-0 は 0
pub fn num(v : Double) -> String {
  if v == 0.0 {
    "0"
  } else {
    v.to_string()
  }
}

///|
/// 経路を d 属性の文字列にする。a は始点（world）
pub fn segs_to_d(segs : Array[Seg], a : Pt) -> String {
  let at = (u : Double, v : Double) => {
    "\{num(round2(a.x + u))} \{num(round2(a.y + v))}"
  }
  let d = StringBuilder()
  d.write_string("M \{at(0, 0)}")
  for s in segs {
    match s {
      L(u, v) => d.write_string(" L \{at(u, v)}")
      C(au, av, bu, bv, eu, ev) =>
        d.write_string(" C \{at(au, av)}, \{at(bu, bv)}, \{at(eu, ev)}")
    }
  }
  d.to_string()
}

///|
/// 点 a から点 z へのラインの d 属性。箱ではなく点を受けるのは、ドロップの
/// 予告のように「まだノードが無いところ」へも同じ形で引きたいため
pub fn edge_path(a : Pt, z : Pt) -> String {
  segs_to_d(edge_segs(z.x - a.x, z.y - a.y), a)
}
