// 書き出し。出し方の表と、ヘッダのボタンの言い分を固定する。
// 実際に出す口（ダウンロード・クリップボード）はブラウザのもので、ここでは通らない

///|
fn deps(
  empty : Bool,
  svg? : @dom.Element? = None,
  failed? : Array[String] = [],
  blocked? : Array[String] = [],
) -> ExportDeps {
  {
    svg: fn() { svg },
    name: () => "Notes.MD",
    failed: m => failed.push(m),
    blocked: m => blocked.push(m),
    empty: () => empty,
  }
}

///|
test "way_of: 覚えていた出し方。知らなければ既定（SVG を落とす）" {
  assert_eq(way_of(Some("png-copy")).label, "Copy PNG")
  assert_eq(way_of(Some("nope")).id, "svg-file")
  assert_eq(way_of(None).id, "svg-file")
  assert_eq(ways.map(w => w.mark), ["download", "download", "copy", "copy"])
}

///|
test "export_ways: 落とすと写すのあいだに線。空なら全部沈み、理由は 1 つの言葉。header に選ばれた出し方が渡る" {
  let chosen = []
  let rows = export_ways(deps(false), Some(w => chosen.push(w.id)))
  assert_eq(rows.length(), 5)
  assert_true(rows[2] is Sep)
  guard rows[3] is Run(row, go) else { fail("行でない") }
  assert_eq(row.label, "Copy PNG")
  assert_true(row.disabled is No)
  go()
  assert_eq(chosen, ["png-copy"])
  guard export_ways(deps(true), None)[0] is Run(row, _) else {
    fail("行でない")
  }
  assert_eq(row.disabled, Why("Nothing to export yet"))
}

///|
/// 非同期の中なので、窓は `with_doc` を通らず手で持つ（閉じる閉包は async を呼べない）
async test "export_once: 出すものが無ければ blocked、出し口がしくじれば failed。どちらも投げない" {
  let blocked = []
  assert_false(export_once(deps(true, blocked~), ways[0]))
  assert_eq(blocked, ["Nothing to export yet"])
  let w = @test_utils.create_happy_window()
  defer w.close()
  let svg = @web.el(w.document(), "svg", [("width", "0"), ("height", "0")])
  let failed = []
  // 大きさが読めない（0）ので raster が投げる → failed
  assert_false(export_once(deps(false, svg=Some(svg), failed~), ways[1]))
  assert_eq(failed, ["Couldn't export"])
}

///|
test "Export: ボタンはいまの出し方（字 + 行き先の絵）を言う。空なら `▾` も一緒に沈み、理由は title" {
  with_doc(doc => {
    let button = doc.createElement("button")
    let way_button = doc.createElement("button")
    let mut empty = true
    let d : ExportDeps = {
      svg: fn() { None },
      name: () => "n.md",
      failed: _ => (),
      blocked: _ => (),
      empty: () => empty,
    }
    let e = Export::new(doc, d, button, way_button)
    assert_eq(button.textContent(), "SVG")
    assert_eq(button.querySelectorAll("svg").length(), 1)
    assert_eq(button.getAttribute("title"), Some("Nothing to export yet"))
    assert_eq(way_button.getAttribute("title"), Some("Nothing to export yet"))
    assert_eq(way_button.querySelectorAll("svg").length(), 1)
    empty = false
    e.refresh()
    assert_eq(
      button.getAttribute("title"),
      Some("Export the whole Mindmap — Download SVG"),
    )
    assert_eq(
      way_button.getAttribute("aria-label"),
      Some("Choose how to export"),
    )
  })
}

// ══════════════════════════════════════════════════════════════════
// 上限に収める — canvas は超えた分を黙って切るか null を返すだけ
// ══════════════════════════════════════════════════════════════════

///|
let png = "image/png"

///|
let webp = "image/webp"

///|
test "上限に当たらない大きさは、頼んだ倍率のまま" {
  assert_eq(fit(800.0, 600.0, 2.0, png), 2.0)
  assert_eq(fit(800.0, 600.0, 2.0, webp), 2.0)
}

///|
/// WebP の 1 辺は 16,383。倍率 2 倍のままだと 8,192 px を超える地図が欠ける
test "WebP は 1 辺 16,383 に収める" {
  assert_eq(fit(1000.0, 8191.0, 2.0, webp), 2.0)
  assert_eq(fit(1000.0, 16383.0, 2.0, webp), 1.0)
  assert_eq(fit(1000.0, 32766.0, 2.0, webp), 0.5)
  // PNG はここでは落とさない
  assert_eq(fit(1000.0, 16383.0, 2.0, png), 2.0)
}

///|
test "PNG は 1 辺 65,535 に収める" {
  assert_eq(fit(1000.0, 65535.0, 2.0, png), 1.0)
  assert_eq(fit(1000.0, 131070.0, 2.0, png), 0.5)
}

///|
/// 1 辺が収まっても、面積で落ちることがある（16,384 の正方形がちょうど上限）
test "面積の上限にも収める" {
  assert_eq(fit(16384.0, 16384.0, 1.0, png), 1.0)
  assert_eq(fit(32768.0, 32768.0, 1.0, png), 0.5)
}

///|
/// 上限ちょうどの倍率で 1 px はみ出さない
test "px は切り上げない。0 にもしない" {
  assert_eq(pixels(65535.0, fit(1000.0, 65535.0, 2.0, png)), 65535)
  assert_eq(pixels(16383.0, fit(1000.0, 16383.0, 2.0, webp)), 16383)
  assert_eq(pixels(0.4, 1.0), 1)
}
