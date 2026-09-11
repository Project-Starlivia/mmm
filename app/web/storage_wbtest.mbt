// localStorage の包み。happy-dom の窓から辿る

///|
test "storage: 置く・読む・鍵を並べる・消す。無い鍵は None" {
  let w = @test_utils.create_happy_window()
  defer w.close()
  let doc = w.document()
  assert_eq(storage_get(doc, "mmm.x"), None)
  storage_set(doc, "mmm.x", "1")
  storage_set(doc, "other", "2")
  assert_eq(storage_get(doc, "mmm.x"), Some("1"))
  let keys = Array::from_fixed_array(storage_keys(doc))
  keys.sort()
  assert_eq(keys, ["mmm.x", "other"])
  storage_remove(doc, "mmm.x")
  assert_eq(storage_get(doc, "mmm.x"), None)
}
