// 枠。分割線の居場所は数だけの話なので、出来事無しで並びを総当たりする

///|
let md_only : Vis = { md: true, map: false, }

///|
let both : Vis = { md: true, map: true, }

///|
let map_only : Vis = { md: false, map: true, }

///|
test "spots_for: 広いときは 3 つ、狭いときは 2 つ。左から右へ並ぶ順は狭くても変わらない" {
  assert_eq(spots_for(false), [map_only, both, md_only])
  assert_eq(spots_for(true), [map_only, md_only])
  for narrow in [false, true] {
    let list = spots_for(narrow)
    assert_eq(list[0], map_only)
    assert_eq(list[list.length() - 1], md_only)
  }
}

///|
test "project: 居場所にある形はそのまま。狭いところへ「両方」が来たらマップを残す。「両方消えた」は作らない" {
  assert_eq(project(both, spots_for(false)), both)
  assert_eq(project(md_only, spots_for(true)), md_only)
  assert_eq(project(both, spots_for(true)), map_only)
  // 名指しの要求を BOTH のまま渡すと map に丸められる（だから toggled が先に行き先を決める）
  let want_md : Vis = { md: true, map: true, }
  assert_eq(project(want_md, spots_for(true)), map_only)
  let none : Vis = { md: false, map: false, }
  assert_eq(project(none, spots_for(false)), both)
  assert_eq(project(none, spots_for(true)), map_only)
}

///|
test "toggled: 隠れているペインを出す / 指名した 1 枚だけ消える / 最後の 1 枚は消せずもう片方が出る" {
  assert_eq(toggled(map_only, Md, spots_for(false)), both)
  assert_eq(toggled(md_only, Map, spots_for(false)), both)
  assert_eq(toggled(map_only, Md, spots_for(true)), md_only)
  assert_eq(toggled(md_only, Map, spots_for(true)), map_only)
  assert_eq(toggled(both, Md, spots_for(false)), map_only)
  assert_eq(toggled(both, Map, spots_for(false)), md_only)
  assert_eq(toggled(md_only, Md, spots_for(false)), map_only)
  assert_eq(toggled(map_only, Map, spots_for(false)), md_only)
  assert_eq(toggled(md_only, Md, spots_for(true)), map_only)
  assert_eq(toggled(map_only, Map, spots_for(true)), md_only)
}

///|
test "toggled: 狭いときは、出す / 引っ込めるをどう繰り返しても「両方」にならない" {
  let list = spots_for(true)
  let mut v = map_only
  for which in [Md, Md, Map, Map, Md, Map] {
    v = toggled(v, which, list)
    assert_false(v.md && v.map)
  }
}

///|
test "show と vis_of は往復する。知らない綴りは覚えていないのと同じ" {
  for v in [both, md_only, map_only] {
    assert_eq(vis_of(Some(v.show())), Some(v))
  }
  json_inspect([both.show(), md_only.show(), map_only.show()], content=[
    "both", "md", "map",
  ])
  assert_eq(vis_of(None), None)
  assert_eq(vis_of(Some("")), None)
  assert_eq(vis_of(Some("none")), None)
}

///|
/// 枠を組む。覚えは毎回まっさらから
fn stage(w : @dom.Window, show? : String) -> (Panes, @dom.Element, Ref[Int]) {
  let d = w.document()
  let body = d.body().unwrap()
  let mk = (id : String) => {
    let e = d.createElement("div")
    e.setAttribute("id", id)
    body.append(e.as_node())
    e
  }
  let md = mk("md-pane")
  let map = mk("map-pane")
  let panes = mk("panes")
  let splitter = mk("splitter")
  match show {
    Some(x) => @prefs.store(d, "panes", x)
    None => @web.storage_remove(d, "mmm.panes")
  }
  let focused : Ref[Int] = { val: 0, }
  (Panes::new(md, map, panes, splitter, () => focused.val += 1), panes, focused)
}

///|
test "Panes: 覚えた姿から始まる。覚えが無ければ両方" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  for show in ["md", "map", "both"] {
    let (_, panes, _) = stage(w, show~)
    assert_eq(panes.getAttribute("data-show"), Some(show))
  }
  let (_, panes, _) = stage(w)
  assert_eq(panes.getAttribute("data-show"), Some("both"))
}

///|
test "Panes: 人が動かした姿だけを覚える" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let d = w.document()
  let (p, _, _) = stage(w)
  // 組んだだけでは書かない — まだ誰も動かしていない
  assert_eq(@prefs.load(d, "panes"), None)
  p.toggle_vis(Md)
  assert_eq(@prefs.load(d, "panes"), Some("map"))
  p.slide(1)
  assert_eq(@prefs.load(d, "panes"), Some("both"))
}

///|
test "Panes: 矢印は分割線を左右に動かし、端で沈む。名前は着く先" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let (p, panes, _) = stage(w)
  assert_eq(panes.getAttribute("data-show"), Some("both"))
  assert_eq(p.go_left.getAttribute("aria-label"), Some("Mindmap only"))
  assert_eq(p.go_right.getAttribute("aria-label"), Some("Markdown only"))
  p.slide(1)
  assert_eq(panes.getAttribute("data-show"), Some("md"))
  assert_eq(p.go_right.as_any()._get("disabled").cast(), true)
  p.slide(1)
  assert_eq(panes.getAttribute("data-show"), Some("md"))
  p.toggle_vis(Md)
  assert_eq(panes.getAttribute("data-show"), Some("map"))
  p.toggle_vis(Md)
  assert_eq(panes.getAttribute("data-show"), Some("both"))
}
