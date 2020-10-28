# toml-serialization
# Copyright (c) 2020 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license: [LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT
#   * Apache License, Version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or http://www.apache.org/licenses/LICENSE-2.0)
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  unittest, os, options,
  ../toml_serialization,
  ../toml_serialization/lexer

type
  Owner = object
    name: string
    dob: TomlDateTime
    cap: float64
    dobString: string
    dobToml: TomlValueRef

  Database = object
    server: string
    ports: array[3, int]
    connection_max: int
    enabled: bool
    negative: int

  ConfigCap = enum
    TomlCap
    JsonCap

  Fruits = enum
    Apple = "apple"
    Banana = "banana"

  Example = object
    title: string
    owner: Owner
    database: Database
    hosts: seq[string]
    configcap: ConfigCap
    cc: ConfigCap
    fruit: Fruits

  GrandChild = object
    name: string
    age: int

  ChildObject = object
    name: string
    child: GrandChild

  NestedObject = object
    child: ChildObject
    son: GrandChild

proc testDecoder() =
  suite "test decoder":
    let rawToml = readFile("tests" / "tomls" / "example.toml")
    var ex = Toml.decode(rawToml, Example)

    var x: TomlDateTime
    x.date = some(TomlDate(
      year: 1979, month: 5, day:27
      ))
    x.time = some(TomlTime(hour: 7, minute: 32, second: 0, subsecond: 0))
    x.zone = some(TomlTimeZone(
      positiveShift: false,
      hourShift: 8,
      minuteShift: 0
      ))

    test "basic example":
      check:
        ex.title == "TOML Example"
        ex.owner.name == "Tom Preston-Werner"
        ex.owner.dob == x
        ex.owner.dobString == "1979-05-27T07:32:00-08:00"
        ex.owner.dobToml.kind == TomlKind.DateTime
        ex.database.server == "192.168.1.1"
        ex.database.ports[0] == 8001
        ex.database.ports[1] == 8002
        ex.database.ports[2] == 8003
        ex.database.connection_max == 5000
        ex.database.enabled == true
        ex.database.negative == -3
        ex.hosts[0] == "alpha"
        ex.hosts[1] == "omega"
        ex.configCap == JsonCap
        ex.cc == TomlCap
        ex.fruit == Banana

    test "spec example":
      discard Toml.loadFile("tests" / "tomls" / "example.toml", TomlValueRef)
      discard Toml.loadFile("tests" / "tomls" / "spec.toml", TomlValueRef)

    test "nested object":
      var x = Toml.loadFile("tests" / "tomls" / "nested_object.toml", NestedObject)
      check:
        x.child.name == "TOML"
        x.child.child.name == "CHILD"
        x.child.child.age == 10
        x.son.name == "SON"

    type
      NoField = object
        name: string
        weight: int
        age: int

      OptionalField = object
        name: string
        age: Option[int]

    test "nofield":
      var x = Toml.decode("name=\"X\" \n age=10", NoField)
      check x.age == 10
      check x.name == "X"
      check x.weight == 0

      expect TomlError:
        discard Toml.decode("name=\"X\" \n age=10 \n banana = 10", NoField)

      var z = Toml.decode("name=\"X\" \n age=10", OptionalField)
      check z.name == "X"
      check z.age.isSome
      check z.age.get() == 10

      var w = Toml.decode("name=\"X\"", OptionalField)
      check w.name == "X"
      check w.age.isNone

    test "bad toml":
      type
        SubObject = object
          name: string

        TopObject = object
          child: SubObject

      expect TomlError:
        discard Toml.decode("child = name = \"Toml\"",  TopObject)

    test "trailing comma in array":
      type
        XX = array[3, int]
        YY = seq[int]

      let x = Toml.decode("x = [1, 2, 3]", XX, "x")
      check x == [1, 2, 3]

      let y = Toml.decode("x = [1, 2, 3]", YY, "x")
      check y == @[1, 2, 3]

      let xx = Toml.decode("x = [1, 2, 3, ]", XX, "x")
      check xx == [1, 2, 3]

      let yy = Toml.decode("x = [1, 2, 3, ]", YY, "x")
      check yy == @[1, 2, 3]

    test "case object":
      type
        CaseObject = object
          case kind: Fruits
          of Apple: appleVal: int
          of Banana: bananaVal: string

      let toml = """
      [apple]
        kind = "Apple"
        appleVal = 123

      [banana]
        kind = "Banana"
        bananaVal = "Hello Banana"
      """

      let apple = Toml.decode(toml, CaseObject, "apple")
      check apple.appleVal == 123

      # TODO: this still fails
      #let banana = Toml.decode(toml, CaseObject, "banana")
      #check banana.bananaVal == "Hello Banana"

proc testTableArray() =
  suite "table array test suite":
    type
      Disc = object
        sector: int
        cylinder: int

      TableArray = object
        disc: seq[Disc]
        cd: array[3, Disc]

    const taFile = "tests" / "tomls" / "table-array.toml"

    test "table array basic decoder":
      let ta = Toml.loadFile(taFile, TableArray)
      check:
        ta.disc.len == 3
        ta.disc[2].sector == 7
        ta.disc[2].cylinder == 8
        ta.cd[0].sector == 9
        ta.cd[0].cylinder == 10

      type
        WantCD = object
          cd: seq[Disc]

      let cds = """
        [[cx]]
          sector = 11
          cylinder = 12

        [[cd]]
          sector = 13
          cylinder = 14
      """

      expect TomlError:
        discard Toml.decode(cds, WantCD)

      let z = Toml.decode(cds, WantCD, flags = {TomlUnknownFields})
      check:
        z.cd.len == 1
        z.cd[0].sector == 13
        z.cd[0].cylinder == 14

    test "table array keyed mode":
      let rawTa = readFile(taFile)
      let x = Toml.decode(rawTa, seq[Disc], "cd")
      check:
        x.len == 2
        x[0].sector == 9
        x[0].cylinder == 10
        x[1].sector == 11
        x[1].cylinder == 12

      let y = Toml.decode(rawTa, array[3, Disc], "disc")
      check:
        y[0].sector == 3
        y[0].cylinder == 4
        y[1].sector == 5
        y[1].cylinder == 6
        y[2].sector == 7
        y[2].cylinder == 8

      let z = Toml.loadFile(taFile, seq[Disc], "cd")
      check:
        z.len == 2
        z[0].sector == 9
        z[0].cylinder == 10
        z[1].sector == 11
        z[1].cylinder == 12

type
  ValidIpAddress {.requiresInit.} = object
    value: string

  TestObject = object
    address: Option[ValidIpAddress]

proc readValue(r: var TomlReader, value: var ValidIpAddress) =
  value.value = r.parseAsString()

proc testOptionalFields() =
  suite "optional fields test suite":
    test "optional field with requiresInit pragma":
      var x = Toml.decode("address = '1.2.3.4'", TestObject)
      check x.address.isSome
      check x.address.get().value == "1.2.3.4"

testDecoder()
testTableArray()
testOptionalFields()
