import std/[locks, strutils]
import chronos, httputils, chronos/apps/http/[httpserver, httpclient], chronos/timer

var echoLock*: Lock

template logLock*(txt: varargs[string, `$`]) =
    if defined(loglock):
        withLock(echoLock):
            echo txt.join""

template logLock1*(txt: varargs[string, `$`]) =
    if defined(loglock):
        withLock(echoLock):
            echo txt.join""



proc fetchUrl*(session: HttpSessionRef, url: Uri): Future[HttpResponseTuple] {.
         async.} =
    ## Fetch resource pointed by ``url`` using HTTP GET method and ``session``
    ## parameters.
    ##
    ## This procedure supports HTTP redirections.
    let address =
        block:
            let res = session.getAddress(url)
            if res.isErr():
                raiseHttpAddressError(res.error())
            res.get()

    var
        request = HttpClientRequestRef.new(session, address)
        response: HttpClientResponseRef = nil
        redirect: HttpClientRequestRef = nil
        was429: bool

    while true:
        try:
            if was429:
                logLock1 "was429"
            response = await request.send()
            if response.status >= 300 and response.status < 400:
                redirect =
                    block:
                        if "location" in response.headers:
                            let location = response.headers.getString("location")
                            if len(location) > 0:
                                let res = request.redirect(parseUri(location))
                                if res.isErr():
                                    raiseHttpRedirectError(res.error())
                                res.get()
                            else:
                                raiseHttpRedirectError("Location header with an empty value")
                        else:
                            raiseHttpRedirectError("Location header missing")
                discard await response.consumeBody()
                await response.closeWait()
                response = nil
                await request.closeWait()
                request = nil
                request = redirect
                redirect = nil
            elif response.status == 429:
                await sleepAsync(milliseconds 10)
                request = HttpClientRequestRef.new(session, address)
                was429 = true
            else:
                if was429:
                    logLock1 "resolved 429"
                let data = await response.getBodyBytes()
                let code = response.status
                await response.closeWait()
                response = nil
                await request.closeWait()
                request = nil
                return (code, data)
        except CancelledError as exc:
            if not(isNil(response)): await closeWait(response)
            if not(isNil(request)): await closeWait(request)
            if not(isNil(redirect)): await closeWait(redirect)
            raise exc
        except HttpError as exc:
            if not(isNil(response)): await closeWait(response)
            if not(isNil(request)): await closeWait(request)
            if not(isNil(redirect)): await closeWait(redirect)
            raise exc
