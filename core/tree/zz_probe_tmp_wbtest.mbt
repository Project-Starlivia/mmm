///|
test "probe" {
  let with_fold = parse(
    "- item\n\n  <details>\n  <summary>h</summary>\n\n  ## h\n\n  </details>\n",
  )
  json_inspect(with_fold, content={})
  inspect(written(with_fold), content="")
  inspect(serialize(with_fold), content="")
}
