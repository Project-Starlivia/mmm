// 画像フォルダの状態の一言。宣言と許可の 2 つから言う — 純粋

///|
test "folder_caption: 言葉は宣言と許可の 2 つだけ。許可が無いときは宣言のパスを出す" {
  assert_eq(folder_caption(None, None), "no folder")
  assert_eq(folder_caption(None, Some("pics/")), "pics/, no access")
  assert_eq(folder_caption(Some("pics"), Some("pics/")), "pics")
  assert_eq(folder_caption(Some("pics"), None), "pics, not declared")
}

// ---- 置く ----
//
// フォルダの札は、掘れば書き口を返すだけの object で代用する。書けるかは `broken` で決める

///|
extern "js" fn folder(broken : Bool) -> @web.DirHandle =
  #| (broken) => ({
  #|   name: "pics",
  #|   getFileHandle: async () => ({
  #|     createWritable: async () => {
  #|       if (broken) throw new Error("gone");
  #|       return { write: async () => {}, close: async () => {} };
  #|     },
  #|   }),
  #| })

///|
/// 種類だけ名乗る絵
extern "js" fn picture(mime : String) -> @core.Any =
  #| (mime) => new Blob(["x"], { type: mime })

///|
/// `directory` を握った Images と、出たしらせ
fn holding(
  w : @dom.Window,
  directory : @web.DirHandle,
) -> (Images, Array[String]) {
  let said = []
  let store = shelf(Map([]))
  let images = Images::new(
    w.document(),
    Disk::new(Recent::new(store), Drafts::new(store)),
    {
      failed: msg => said.push(msg),
      refresh: () => (),
      declared: () => None,
      set_declared: _ => (),
    },
  )
  images.cached = Some(Some({ doc: @core.new_object().cast(), directory, }))
  images.live = true
  (images, said)
}

///|
async test "put: 焼き直せなければそう言い、握りは保つ — フォルダは無事" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let pics = folder(false)
  let (images, said) = holding(w, pics)
  // 絵ではないので焼けない
  assert_eq(images.put(pics, ["shot.webp"], picture("text/plain")), None)
  assert_eq(said, ["Couldn't convert the image"])
  assert_true(images.cached is Some(Some(_)))
  assert_true(images.readable())
}

///|
async test "put: 書けなければ握りは腐っている。捨てて繋ぎ直しの駅へ落とす" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let pics = folder(true)
  let (images, said) = holding(w, pics)
  assert_eq(images.put(pics, ["shot.webp"], picture("image/webp")), None)
  assert_eq(said, ["Couldn't save the image"])
  assert_true(images.cached is Some(None))
  assert_true(!images.readable())
}

///|
async test "put: 書ければ md に書くパスを返し、握りは保つ" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let pics = folder(false)
  let (images, said) = holding(w, pics)
  assert_eq(
    images.put(pics, ["shot.webp"], picture("image/webp")),
    Some("./shot.webp"),
  )
  assert_eq(said, [])
  assert_true(images.cached is Some(Some(_)))
}
