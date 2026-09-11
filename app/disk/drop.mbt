// 落とされたファイルの振り分け。`.md` はその文書を開き、画像はノードの上に
// 落ちたときだけ受け取る — どこに付いたか分からない貼り方はしない。
//
// ここが知っているのは「何が落ちたか」までで、開く / 置くの中身は呼び出し側。

///|
pub(all) struct Drop {
  /// `.md` が落ちた
  open_markdown : async (@web.FileHandle) -> Unit
  /// 画像がノードの上に落ちた（ノードの外なら呼ばれない）
  add_image : async (@core.Any, Int) -> Unit
  /// 着地点を予告する。None で消す。落ちる先のノード（無ければ None）を返す
  mark_drop : ((Double, Double)?) -> Int?
  /// 果たせなかった
  failed : (String) -> Unit
}

///|
fn point_of(e : @core.Any) -> (Double, Double)? {
  let m = @web.mouse(e)
  Some((m.clientX, m.clientY))
}

///|
pub fn init_drop(doc : @dom.Document, deps : Drop) -> Unit {
  // **ドラッグしている間ずっと答えが見えている。** 落ちる先が決まっていれば
  // その行に線を引き、置けないところではブラウザのカーソルがそう言う。
  // 落としてから「ノードの上へ」と言い直す必要がそもそも無くなる。
  //
  // ドラッグ中に読めるのは**種類（MIME）まで**で、名前も中身も `drop` まで
  // 伏せられている。だが絵かどうかはそれで足りる — 絵だけを掴んでいるなら
  // 行き先はノードの上に限られ、外では受けないと言い切れる。
  // 1 つでも絵でないもの（`.md`）が混ざるなら、どこへ落としても開くので受ける
  @web.on_window(doc, "dragover", e => {
    let types = @web.drag_files(e)
    if types.length() == 0 {
      return
    }
    let on_node = (deps.mark_drop)(point_of(e)) is Some(_)
    let only_images = types.iter().all(t => t.has_prefix("image/"))
    if only_images && !on_node {
      // **受けないと言う。** preventDefault を呼ばなければブラウザが既定の
      // 扱いに戻し、カーソルが拒否の形になって drop も来ない
      @web.set_drop_effect(e, "none")
      return
    }
    @web.prevent(e) // これを言わないと drop が来ない
    @web.set_drop_effect(e, "copy")
  })

  // 窓から出ていったら予告は消す（戻ってくれば dragover がまた点ける）
  @web.on_window(doc, "dragleave", e => {
    if @web.left_window(e) {
      (deps.mark_drop)(None) |> ignore
    }
  })
  @web.on_window(doc, "drop", e => {
    @web.prevent(e)
    // 行き先はこの点で決まる。読んでから予告を畳む
    let node = (deps.mark_drop)(point_of(e))
    (deps.mark_drop)(None) |> ignore
    let files = @web.dropped_files(e)
    // **落ちた数は待つ前に数える。** 最初の await で drop の出来事が終わり、
    // 以後 items は空に見える（web/drag.mbt）
    let dropped = @web.drag_files(e).length()
    @js_async.Promise::from_async(async fn() {
      (async fn() -> Unit {
        let list = Array::from_fixed_array(files.wait())
        // **落ちたのに 1 つも札にならなかった。黙って捨てない。**
        // ピッカーを持たないブラウザには `getAsFileSystemHandle` が無いので
        // 項目が全部こぼれる（docs/browsers.md の (b′)）。フォルダを落とした
        // ときも札はフォルダのもので、ファイルとしては残らない
        if list.is_empty() && dropped > 0 {
          (deps.failed)(
            if @web.can_open() {
              "Couldn't open the dropped file"
            } else {
              @parts.no_file_access
            },
          )
          return
        }
        match list.search_by(f => @read.is_markdown(f.name())) {
          Some(i) => {
            (deps.open_markdown)(list[i])
            return
          }
          None => ()
        }
        // ノードの外へ落ちた絵は、そもそもここまで来ない（dragover が受けて
        // いない）。来るのは `.md` に混ざって落ちた分だけなので、黙って置かない
        guard node is Some(id) else { return }
        for f in list {
          if image_type(f.name()) is Some(_) {
            (deps.add_image)(@web.file_of(f).wait(), id)
          }
        }
      })() catch {
        _ => (deps.failed)("Couldn't open the dropped file")
      }
    })
    |> ignore
  })
}
