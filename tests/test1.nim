# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.
import std/[deques, os, random]
import chronos, httputils, chronos/apps/http/[httpserver, httpclient], chronos/timer
import stashtable
import unittest

import workers
import workers/utils

randomize()

test "init worker":
  initWorkers(wrks, seq[string], 20, false,
    block before:
      var
        session: HttpSessionRef = HttpSessionRef.new(maxRedirections = HttpMaxRedirections)
        fResp: Future[HttpResponseTuple]
      var response: HttpResponseTuple
    ,
    block inLoop:
      let
          uriTxt = "https://dns.google/query?name=8.8.8.8"
          #uriTxt = "https://m2414.de"
      let uri = uriTxt.parseUri
      fResp = fetchUrl(session, uri)
      response = waitFor fResp
      let data = cast[string](response.data)
      echo("geoLine:data:", data)
    ,
    block after:
      waitFor session.closeWait()
      session = nil
      response.reset()
      fResp = nil
  )


  initWorkers(wrksB, string, 20, false,
    block before:
      (sleep rand(50..80))
    ,
      #var xx = 0,
    block inLoop:
      var y = 0
      #sleep rand(50..80)
      let x = 0
    ,
    block after:
      var z = 0
  )
  echo "wrks:", wrks
  for i in 1..1_000:
    wrks.sendData(@[$i & "test"])
  when true:
    for i in 1..1_000:
      wrksB.sendData($i & "test222")
  sleep 5_000
  #echo "wrksB:", wrksB
  check true
