// Op が値として JSON になり、JSON から起こせることを固定する。ts はこの形で送る。

///|
/// Op は ToJson の形をそのまま FromJson で受ける。席の side の None は鍵ごと落ちる
test "Op は JSON の値になり、JSON から起こせる" {
  let ops : Array[Op] = [
    MoveNode(ids=[3, 5], at=NodePlace::In(node=2, side=Some(Left))),
    Delete(ids=[4]),
    AddBlock(
      at=BlockPlace::Before(block=7),
      content=Some(Code(info="js", text="x")),
      source=None,
    ),
    AddNode(at=NodePlace::In(node=2, side=None), labels=["n"]),
    AddNode(at=NodePlace::In(node=2, side=Some(Left)), labels=["n"]),
    MoveBlock(ids=[3, 4], at=Before(block=5)),
    AddBlock(
      at=BlockPlace::In(node=2),
      content=Some(Code(info="js", text="1\n")),
      source=None,
    ),
    Fold(id=2, open=false),
  ]
  for op in ops {
    let back : Op = @json.from_json(op.to_json())
    assert_eq(back, op)
  }
  json_inspect(ops[0], content=[
    "MoveNode",
    { "ids": [3, 5], "at": ["In", { "node": 2, "side": "Left" }] },
  ])
  json_inspect(ops[1], content=["Delete", { "ids": [4] }])
  json_inspect(ops[2], content=[
    "AddBlock",
    {
      "at": ["Before", { "block": 7 }],
      "content": ["Code", { "info": "js", "text": "x" }],
    },
  ])
  json_inspect(ops[3], content=[
    "AddNode",
    { "at": ["In", { "node": 2 }], "labels": ["n"] },
  ])
  json_inspect(ops[4], content=[
    "AddNode",
    { "at": ["In", { "node": 2, "side": "Left" }], "labels": ["n"] },
  ])
  json_inspect(ops[6], content=[
    "AddBlock",
    {
      "at": ["In", { "node": 2 }],
      "content": ["Code", { "info": "js", "text": "1\n" }],
    },
  ])
}
