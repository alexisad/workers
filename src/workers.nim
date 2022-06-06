# This is just an example to get you started. A typical library package
# exports the main API in this file. Note that you cannot rename this file
# but you can remove it if you wish.

import std/[macros, deques, os, random, sequtils]
import stashtable
import workers/utils


const maxThrs = 1024

macro initWorkers*(wrks: untyped, dataType: typedesc, cntThrs: int, isThreadsJoin: bool,
         before, inLoop, after: untyped): untyped =
  #echo "before.treeRepr:", before.treeRepr
  let beforeBody =
    if before[1].isNil:
      newStmtList()
    else:
      before[1]
  let inLoopBody =
    if inLoop[1].isNil:
      newStmtList()
    else:
      inLoop[1]
  let afterBody =
    if after[1].isNil:
      newStmtList()
    else:
      after[1]
  template skeletWorker(wrks, dataType, cntThrs, isThreadsJoin, before, body, after): untyped =
    type
      ThreadData = object
        data: Deque[dataType]
      SharedData = StashTable[string, ThreadData, 10]
      SharedWait = StashTable[string, Deque[string], 10]
    
    let shareddataB = newStashTable[string, ThreadData, 10]()
    let sharedWaitB = newStashTable[string, Deque[string], 10]()
    shareddataB.insert("prcsData", ThreadData(data: initDeque[dataType]()))
    sharedWaitB.insert("thrInWait", initDeque[string]())
    
    type
      Workers = object
    var wrks = Workers()
    var
      threads: array[1..maxThrs, Thread[tuple[t: int, shareddata: SharedData, sharedWait: SharedWait]]]
      cnd: Cond
      cndLocks: array[1..maxThrs, Lock]
    cnd.initCond()
    

    proc unblockWaits(shData: SharedWait, t: int) {.gensym.} =
      shData.withValue("thrInWait"):
        while value[].len != 0:
          discard value[].popFirst()
          broadcast cnd

    proc sendData(wrks: Workers, data: dataType) =
      shareddataB.withValue("prcsData"):
        value[].data.addLast(data)
      unblockWaits(sharedWaitB, 0)


    proc worker(d: tuple[t: int, shareddata: SharedData, sharedWait: SharedWait]) {.thread.} =
      before
      var
        runThr = true
        needToWait = false
      while runThr:
        d.shareddata.withValue("prcsData"):
          if value[].data.len != 0:
            let data = value[].data.popFirst()
            logLock "data:", $data, "->", d.t, "<"
          else:
            needToWait = true
        if needToWait:
          d.sharedWait.withValue("thrInWait"):
            value[].addLast($d.t)
          logLock "start wait:", "->", d.t, "<"
          wait(cnd, cndLocks[d.t])
          logLock "end wait:", "->", d.t, "<"
          needToWait = false
        else:
          unblockWaits(d.sharedWait, d.t)
        #here heavy proccess data from value[].popFirst()
        #sleep rand(50..80)#...
        body
      after
    
    for i in 1..cntThrs:
      createThread(threads[i], worker, (i, shareddataB, sharedWaitB))
      cndLocks[i].initLock()
    if isThreadsJoin:
      joinThreads(threads)

  result = newStmtList()
  result.add getAst(skeletWorker(wrks, dataType, cntThrs, isThreadsJoin, beforeBody, inLoopBody, afterBody))
  #echo "ast:", result.repr
  