# This is just an example to get you started. A typical library package
# exports the main API in this file. Note that you cannot rename this file
# but you can remove it if you wish.

import std/[macros, deques, os, random, sequtils]
import stashtable
import workers/utils


const maxThrs = 2048

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
      WorkerInfo = object
        cntWrkThrs: int
      SharedData = StashTable[string, ThreadData, 10]
      SharedWait = StashTable[string, Deque[string], 10]
      SharedWorkerInfo = StashTable[string, WorkerInfo, 1]
    
    let shareddataB = newStashTable[string, ThreadData, 10]()
    let sharedWaitB = newStashTable[string, Deque[string], 10]()
    let sharedWrkInfoB = newStashTable[string, WorkerInfo, 1]()
    shareddataB.insert("prcsData", ThreadData(data: initDeque[dataType]()))
    sharedWaitB.insert("thrInWait", initDeque[string]())
    sharedWaitB.insert("thrBreak", initDeque[string]())
    sharedWrkInfoB.insert("wInfo", WorkerInfo())
    sharedWrkInfoB.withValue("wInfo"):
      value[].cntWrkThrs = cntThrs
    
    type
      Workers = object
    var wrks = Workers()
    var
      threads: array[1..maxThrs, Thread[tuple[t: int, shareddata: SharedData, sharedWait: SharedWait, sharedWrkInfo: SharedWorkerInfo]]]
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

    proc clearData(wrks: Workers) =
      shareddataB.withValue("prcsData"):
        value[].data.clear()
      unblockWaits(sharedWaitB, 0)
    

    proc worker(d: tuple[t: int, shareddata: SharedData, sharedWait: SharedWait, sharedWrkInfo: SharedWorkerInfo]) {.thread.} =
      before
      var
        runThr = true
        needToWait = false
        prcsData {.inject.}: dataType
      while runThr:
        d.sharedWait.withValue("thrBreak"):
          if value[].len != 0:
            var nSeq = newSeq[string]()
            while value[].len != 0:
              let iT = value[].popFirst()
              if iT == $d.t:
                runThr = false
              else:
                nSeq.add iT
            value[] = nSeq.toDeque
        if not runThr:
          break

        d.shareddata.withValue("prcsData"):
          if value[].data.len != 0:
            prcsData = value[].data.popFirst()
            logLock "data:", $prcsData, "->", d.t, "<"
          else:
            needToWait = true
        if needToWait:
          d.sharedWait.withValue("thrInWait"):
            value[].addLast($d.t)
          logLock "start wait:", "->", d.t, "<"
          wait(cnd, cndLocks[d.t])
          logLock "end wait:", "->", d.t, "<"
          needToWait = false
          continue
        else:
          unblockWaits(d.sharedWait, d.t)
        #here heavy proccess data from value[].popFirst()
        #sleep rand(50..80)#...
        logLock "loop body:", "->", d.t, "<"
        body
      after
      d.sharedWrkInfo.withValue("wInfo"):
        dec (value[].cntWrkThrs)
    
    proc setThrsCnt(it: Workers, newCnt: int): int =
      var r: int
      sharedWrkInfoB.withValue("wInfo"):
        if newCnt != value[].cntWrkThrs:
          for i,thr in threads.mpairs:
            if newCnt > value[].cntWrkThrs and not thr.running:
              createThread(threads[i], worker, (i, shareddataB, sharedWaitB, sharedWrkInfoB))
              cndLocks[i].initLock()
              inc value[].cntWrkThrs
            elif newCnt < value[].cntWrkThrs and thr.running:
              sharedWaitB.withValue("thrBreak"):
                value[].addLast($i)
        r = value[].cntWrkThrs
      unblockWaits(sharedWaitB, 0)
      r

    sharedWrkInfoB.withValue("wInfo"):
      for i in 1..value[].cntWrkThrs:
        createThread(threads[i], worker, (i, shareddataB, sharedWaitB, sharedWrkInfoB))
        cndLocks[i].initLock()
    #wrks.setThrsCnt(1)
    
    if isThreadsJoin:
      joinThreads(threads)

  result = newStmtList()
  result.add getAst(skeletWorker(wrks, dataType, cntThrs, isThreadsJoin, beforeBody, inLoopBody, afterBody))
  #echo "ast:", result.repr
  