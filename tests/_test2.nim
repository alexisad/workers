import micros
import std/[macros, unittest]

suite "Apply":
  test"Easy Impl":
    proc matchesArgAux(prc: RoutineSym, t: NimNode): bool =
      for myProc in prc.routines:
        if myProc.param(0).typ.sameType(t.getType):
          return true

    macro matchesArg(myProc, t: typed): untyped = newLit matchesArgAux(routineSym myProc, t)

    proc makeWhen(args, call: NimNode): WhenStmt =
      result = whenStmt()
      for arg in args:
        result.add:
          elifBranch:
            newCall(bindSym"matchesArg", call[0], arg)
          do:
            newCall(call[0], @[arg] & call[1..^1])
      result.add:
        elseBranch:
          newCall(call[0], call[1..^1])

    macro apply(args: varargs[typed], body: untyped) =
      result = newStmtList()
      for stmt in body:
        case stmt.kind
        of nnkCall, nnkCommand:
          result.add NimNode makeWhen(args, stmt)
        else:
          result.add stmt

    type Drawing = object
      data: int

    proc uses(d: Drawing, param: int) =
      echo "The addition: ", d.data + param

    proc doesnt(param: int) =
      echo "The square: ", (param * param)

    proc doesnt(param: Drawing, other: int) =
      echo "Hmmm", (param, other)



    let d = Drawing(data: 50)

    d.uses 10
    apply d:
      uses 5
      let toUse = 10
      doesnt(toUse)