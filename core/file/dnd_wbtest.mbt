// 落とすものの振り分け。ドラッグ中の答え（受ける / 断る）を固定する。
// 札の取り出し（getAsFileSystemHandle）はブラウザだけのものなので、drop の先は通らない

///|
fn drag(
  w : @dom.Window,
  name : String,
  types : Array[String],
  x : Double,
) -> @core.Any {
  let dt = @core.new(w.as_any()._get("DataTransfer"), [])
  for t in types {
    let opts = @core.new_object()
    opts._set("type", @core.any(t))
    let file = @core.new(w.as_any()._get("File"), [
      @core.any(["x"]),
      @core.any("f"),
      opts,
    ])
    dt._get("items")._call("add", [file]) |> ignore
  }
  let init = @core.new_object()
  init._set("cancelable", @core.any(true))
  init._set("clientX", @core.any(x))
  init._set("clientY", @core.any(0.0))
  let ev = @core.new(w.as_any()._get("DragEvent"), [@core.any(name), init])
  // happy-dom は init の dataTransfer と座標を落とす。出来事に直に載せる
  ev._set("dataTransfer", dt)
  ev._set("clientX", @core.any(x))
  ev._set("clientY", @core.any(0.0))
  w.as_any()._call("dispatchEvent", [ev]) |> ignore
  ev
}

///|
test "dragover: 絵だけならノードの上でだけ受ける。.md が混ざれば どこでも受ける。ファイルが無ければ黙る" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let marks = []
  init_drop(w.document(), {
    open_markdown: fn(_) {  },
    add_image: fn(_, _) {  },
    // x が 100 より右ならノードの上
    mark_drop: at => {
      marks.push(at)
      match at {
        Some((x, _)) => if x > 100.0 { Some(7) } else { None }
        None => None
      }
    },
    failed: _ => (),
  })
  let prevented = (e : @core.Any) => e._get("defaultPrevented").cast()
  let effect = (e : @core.Any) => {
    e._get("dataTransfer")._get("dropEffect").cast()
  }
  let off = drag(w, "dragover", ["image/png"], 10)
  assert_false(prevented(off))
  assert_eq(effect(off), "none")
  let on = drag(w, "dragover", ["image/png"], 200)
  assert_true(prevented(on))
  assert_eq(effect(on), "copy")
  let mixed = drag(w, "dragover", ["image/png", "text/markdown"], 10)
  assert_true(prevented(mixed))
  assert_eq(marks, [Some((10.0, 0.0)), Some((200.0, 0.0)), Some((10.0, 0.0))])
  let none = drag(w, "dragover", [], 200)
  assert_false(prevented(none))
  assert_eq(marks.length(), 3)
  // 窓から出たら予告は消える（relatedTarget が無い）
  drag(w, "dragleave", [], 0) |> ignore
  assert_eq(marks.length(), 4)
  assert_eq(marks[3], None)
}
