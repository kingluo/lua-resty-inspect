# lua-resty-inspect

It's useful to set arbitrary breakpoint in any lua file to inspect the context information,
e.g. print local variables if some condition satisfied.

In this way, you don't need to modify the source code of your project, and just get diagnose information
on demand, i.e. dynamic logging.

This library supports setting breakpoints within both interpretd function and jit compiled function.
The breakpoint could be at any position within the function. The function could be global/local/module/ananymous.

It works for luajit2.1 or lua5.1.

This library has been used to implement inspect plugin of APISIX:

https://apisix.apache.org/zh/docs/apisix/plugins/inspect/

## Features

* set breakpoint at any position
* dynamic breakpoint
* Customized breakpoint handler
* you could define one-shot breakpoint
* work for jit compiled function
* if function reference specified, then performance impact is only bound to that function (JIT compiled code will not trigger debug hook, so they would run fast even if hook is enabled)
* if all breakpoints deleted, jit could recover

## Operation Graph

![1666251376616](https://user-images.githubusercontent.com/4401042/196885851-d883a7fb-0ab5-45b1-987f-7b6d810748f5.png)

## API

### require("resty.inspect.dbg").set_hook(file, line, func, filter_func)

The breakpoint is specified by `file` (full qualified or short file name) and the `line` number.

The `func` specified the scope (which function or global) of jit cache to flush:
* If the breakpoint is related to a module function or
global function, you should set it that function reference, then only the jit cache of that function would
be flushed, and it would not affect other caches to avoid slowing down other parts of the program.
* If the breakpointis related to local function or anonymous function,
then you have to set it to `nil` (because no way to get function reference), which would flush the whole jit cache of lua vm.

You attach a `filter_func` function of the breakpoint, the function takes the `info` as argument and returns
true of false to determine whether the breakpoint would be removed. You could setup one-shot breakpoint
at ease.

The `info` is a hash table which contains below keys:

* `finfo`: `debug.getinfo(level, "nSlf")`
* `uv`: upvalues hash table
* `vals`: local variables hash table

### require("resty.inspect.dbg").unset_hook(file, line)

remove the specific breakpoint.

### require("resty.inspect").init(delay, file)

Setup a timer (in `delay` interval, in seconds) to monitor specific `file` to setup the needed breakpoints. You could modify that file
to configure breakpoints on-the-fly. Delete that file would unset all breakpoints. It's recommanded to use soft link file trick.

### require("resty.inspect").destroy()

Destroy the monitor timer.

## Synopsis

```lua
# hooks.lua
local dbg = require "resty.inspect.dbg"

dbg.set_hook("limit-req.lua", 88, require("apisix.plugins.limit-req").access,
function(info)
    ngx.log(ngx.INFO, debug.traceback("foo traceback", 3))
    ngx.log(ngx.INFO, dbg.getname(info.finfo))
    ngx.log(ngx.INFO, "conf_key=", info.vals.conf_key)
    return true
end)

dbg.set_hook("t/lib/demo.lua", 31, require("t.lib.demo").hot2, function(info)
    if info.vals.i == 222 then
        ngx.timer.at(0, function(_, body)
            local httpc = require("resty.http").new()
            httpc:request_uri("http://127.0.0.1:9080/upstream1", {
                method = "POST",
                body = body,
            })
        end, ngx.var.request_uri .. "," .. info.vals.i)
        return true
    end
    return false
end)

--- more breakpoints ...
```

## Caveats

To setup breakpoint within jit compiled function, it needs to flush the jit cache first.

Depending on the scope of jit cache flush, if you only flush the specific function cache, then it only
slows down that function execution, otherwise, it would slow down the whole jit cache of lua vm.

When the breakpoints are enabled, the lua vm could not trace new hot paths and compile them.

But when the breakpoints disappear, the lua vm would recover jit tracing.

So this library is only useful for functional debug without stress.

## Example

### 1. example/nginx.conf

```nginx
error_log /dev/stderr info;
worker_processes auto;

events {}

http {
    lua_package_path '/opt/lua-resty-inspect/example/?.lua;/opt/lua-resty-inspect/lib/?.lua;/opt/lua-resty-inspect/lib/?/init.lua;/usr/local/lib/lua/5.1/?.lua;/usr/local/share/lua/5.1/?.lua;;';
    lua_package_cpath '/usr/local/lib/lua/5.1/?.so;;';

    init_worker_by_lua_block {
        local inspect = require "resty.inspect"
        inspect.init(1, "/opt/lua-resty-inspect/example/resty_inspect_hooks.lua")
    }

    server {
        listen 10000;

        location / {
            content_by_lua_block {
                local hot = require("hot")

                -- hook enabled, jit flush, slow
                hot.timeit(hot.foo, "foo")
                hot.run_bar()

                -- hook removed, tracing
                hot.timeit(hot.foo, "foo")
                hot.run_bar()

                -- jit, fast
                hot.timeit(hot.foo, "foo")
                hot.run_bar()

                ngx.say("ok")
            }
        }
    }
}

```

### 2. example/resty_inspect_hooks1.lua

```lua
local dbg = require "resty.inspect.dbg"
local cjson = require "cjson"
local hot = require "hot"

-- short file name
-- foo is module function, so here we just flush jit cache of foo function
dbg.set_hook("hot.lua", 9, hot.foo, function(info)
    if info.vals.i == 100 then
        ngx.log(ngx.INFO, debug.traceback("foo traceback", 3))
        ngx.log(ngx.INFO, dbg.getname(info.finfo))
        ngx.log(ngx.INFO, cjson.encode(info.vals))
        ngx.log(ngx.INFO, cjson.encode(info.uv))
        return true
    end
    return false
end)

```

### 3. example/resty_inspect_hooks2.lua

```lua
local dbg = require "resty.inspect.dbg"
local cjson = require "cjson"
local hot = require "hot"

-- short file name
-- foo is module function, so here we just flush jit cache of foo function
dbg.set_hook("hot.lua", 9, hot.foo, function(info)
    if info.vals.i == 100 then
        ngx.log(ngx.INFO, debug.traceback("foo traceback", 3))
        ngx.log(ngx.INFO, dbg.getname(info.finfo))
        ngx.log(ngx.INFO, cjson.encode(info.vals))
        ngx.log(ngx.INFO, cjson.encode(info.uv))
        return true
    end
    return false
end)

-- more specific file name
-- bar is local function, so it have to flush the whole jit cache
dbg.set_hook("example/hot.lua", 17, nil, function(info)
    if info.vals.i == 99 then
        ngx.log(ngx.INFO, debug.traceback("bar traceback", 3))
        ngx.log(ngx.INFO, dbg.getname(info.finfo))
        return true
    end
    return false
end)

```

### 4. test

**Setup the test env:**

```bash
luarocks install cjson socket lfs
cd /opt
git clone https://github.com/kingluo/lua-resty-inspect
cd /opt/lua-resty-inspect
/usr/local/openresty-debug/nginx/sbin/nginx -p /opt/lua-resty-inspect/example/ -c nginx.conf -g "daemon off;"
```

**Nginx log output explanation:**

```bash
### no breakpoints initially, because the breakpoints file resty_inspect_hooks.lua not exist

### setup foo breakpoint

ln -sf /opt/lua-resty-inspect/example/resty_inspect_hooks1.lua /opt/lua-resty-inspect/example/resty_inspect_hooks.lua

2022/08/28 21:44:12 [info] 2688226#2688226: *31 [lua] init.lua:29: setup_hooks(): set hooks: err=nil, hooks=["hot.lua#9"], context: ngx.timer

### trigger the hot.lua execution

curl localhost:10000/get

### breakpoint on foo() function triggered
### print related information around the breakpoint

2022/08/28 21:44:28 [info] 2688226#2688226: *47 [lua] resty_inspect_hooks.lua:9: foo traceback
stack traceback:
         /opt/lua-resty-inspect/lib/resty/inspect/dbg.lua:50: in function '__index'
         /opt/lua-resty-inspect/example/hot.lua:9: in function 'func'
         /opt/lua-resty-inspect/example/hot.lua:24: in function 'timeit'
         content_by_lua(nginx.conf:35):5: in main chunk, client: 127.0.0.1, server: , request: "GET /get HTTP/1.1", host: "localhost:10000"
2022/08/28 21:44:28 [info] 2688226#2688226: *47 [lua] resty_inspect_hooks.lua:10: /opt/lua-resty-inspect/example/hot.lua:9 (func), client: 127.0.0.1, server: , request:
  "GET /get HTTP/1.1", host: "localhost:10000"
2022/08/28 21:44:28 [info] 2688226#2688226: *47 [lua] resty_inspect_hooks.lua:11: {"i":100,"j":1}, client: 127.0.0.1, server: , request: "GET /get HTTP/1.1", host: "localhost:10000"
2022/08/28 21:44:28 [info] 2688226#2688226: *47 [lua] resty_inspect_hooks.lua:12: {"s":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaall"}, client: 127.0.0.1, server: , request: "GET /get HTTP/1.1", host: "localhost:10000"


### the breakpoint only affect the jit cache of foo, so you could see that the foo execution is slow,
### but the bar function is still fast

2022/08/28 21:44:28 [info] 2688226#2688226: *47 [lua] hot.lua:26: timeit(): timeit foo: 81.11 msecs, client: 127.0.0.1, server: , request: "GET /get HTTP/1.1", host: "l
ocalhost:10000"
2022/08/28 21:44:28 [info] 2688226#2688226: *47 [lua] hot.lua:26: timeit(): timeit bar: 0.12 msecs, client: 127.0.0.1, server: , request: "GET /get HTTP/1.1", host: "lo
calhost:10000"


### the breakpoint is setup to be one-shot, so you could see that the latter foo would redo the jit tracing, and becomes fast again


2022/08/28 21:44:28 [info] 2688226#2688226: *47 [lua] hot.lua:26: timeit(): timeit foo: 0.56 msecs, client: 127.0.0.1, server: , request: "GET /get HTTP/1.1", host: "localhost:10000"
2022/08/28 21:44:28 [info] 2688226#2688226: *47 [lua] hot.lua:26: timeit(): timeit bar: 0.04 msecs, client: 127.0.0.1, server: , request: "GET /get HTTP/1.1", host: "localhost:10000"
2022/08/28 21:44:28 [info] 2688226#2688226: *47 [lua] hot.lua:26: timeit(): timeit foo: 0.05 msecs, client: 127.0.0.1, server: , request: "GET /get HTTP/1.1", host: "localhost:10000"
2022/08/28 21:44:28 [info] 2688226#2688226: *47 [lua] hot.lua:26: timeit(): timeit bar: 0.04 msecs, client: 127.0.0.1, server: , request: "GET /get HTTP/1.1", host: "localhost:10000"
2022/08/28 21:44:28 [info] 2688226#2688226: *48 [lua] init.lua:57: alive hooks: {}, context: ngx.timer
2022/08/28 21:44:33 [info] 2688226#2688226: *53 [lua] init.lua:57: alive hooks: {}, context: ngx.timer
2022/08/28 21:44:38 [info] 2688226#2688226: *58 [lua] init.lua:57: alive hooks: {}, context: ngx.timer
2022/08/28 21:44:43 [info] 2688226#2688226: *63 [lua] init.lua:57: alive hooks: {}, context: ngx.timer
2022/08/28 21:44:48 [info] 2688226#2688226: *68 [lua] init.lua:57: alive hooks: {}, context: ngx.timer


##
## setup two breakpoints again
##

ln -sf /opt/lua-resty-inspect/example/resty_inspect_hooks2.lua /opt/lua-resty-inspect/example/resty_inspect_hooks.lua

##
## breakpoints enabled
##

2022/08/28 21:44:49 [info] 2688226#2688226: *69 [lua] init.lua:29: setup_hooks(): set hooks: err=nil, hooks=["hot.lua#9","example\/hot.lua#17"], context: ngx.timer

##
## The bar breakpoint clears the whole jit cache, so you could see that it slows down everything
##

2022/08/28 21:45:03 [info] 2688226#2688226: *84 [lua] resty_inspect_hooks.lua:9: foo traceback
stack traceback:
        /opt/lua-resty-inspect/lib/resty/inspect/dbg.lua:50: in function '__index'
        /opt/lua-resty-inspect/example/hot.lua:9: in function 'func'
        /opt/lua-resty-inspect/example/hot.lua:24: in function 'timeit'
        content_by_lua(nginx.conf:35):5: in main chunk, client: 127.0.0.1, server: , request: "GET /get HTTP/1.1", host: "localhost:10000"
2022/08/28 21:45:03 [info] 2688226#2688226: *84 [lua] resty_inspect_hooks.lua:10: /opt/lua-resty-inspect/example/hot.lua:9 (func), client: 127.0.0.1, server: , request:
 "GET /get HTTP/1.1", host: "localhost:10000"
2022/08/28 21:45:03 [info] 2688226#2688226: *84 [lua] resty_inspect_hooks.lua:11: {"i":100,"j":1}, client: 127.0.0.1, server: , request: "GET /get HTTP/1.1", host: "loc
alhost:10000"
2022/08/28 21:45:03 [info] 2688226#2688226: *84 [lua] resty_inspect_hooks.lua:12: {"s":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaall"}, client: 12
7.0.0.1, server: , request: "GET /get HTTP/1.1", host: "localhost:10000"
2022/08/28 21:45:03 [info] 2688226#2688226: *84 [lua] hot.lua:26: timeit(): timeit foo: 68.49 msecs, client: 127.0.0.1, server: , request: "GET /get HTTP/1.1", host: "l
ocalhost:10000"
2022/08/28 21:45:03 [info] 2688226#2688226: *84 [lua] resty_inspect_hooks.lua:22: bar traceback
stack traceback:
        /opt/lua-resty-inspect/lib/resty/inspect/dbg.lua:50: in function '__index'
        /opt/lua-resty-inspect/example/hot.lua:17: in function 'func'
        /opt/lua-resty-inspect/example/hot.lua:24: in function 'timeit'
        /opt/lua-resty-inspect/example/hot.lua:30: in function 'run_bar'
        content_by_lua(nginx.conf:35):6: in main chunk, client: 127.0.0.1, server: , request: "GET /get HTTP/1.1", host: "localhost:10000"
2022/08/28 21:45:03 [info] 2688226#2688226: *84 [lua] resty_inspect_hooks.lua:23: /opt/lua-resty-inspect/example/hot.lua:17 (func), client: 127.0.0.1, server: , request
: "GET /get HTTP/1.1", host: "localhost:10000"
2022/08/28 21:45:03 [info] 2688226#2688226: *84 [lua] hot.lua:26: timeit(): timeit bar: 63.60 msecs, client: 127.0.0.1, server: , request: "GET /get HTTP/1.1", host: "l
ocalhost:10000"
2022/08/28 21:45:03 [info] 2688226#2688226: *84 [lua] hot.lua:26: timeit(): timeit foo: 0.64 msecs, client: 127.0.0.1, server: , request: "GET /get HTTP/1.1", host: "lo
calhost:10000"
2022/08/28 21:45:03 [info] 2688226#2688226: *84 [lua] hot.lua:26: timeit(): timeit bar: 0.11 msecs, client: 127.0.0.1, server: , request: "GET /get HTTP/1.1", host: "lo
calhost:10000"
2022/08/28 21:45:03 [info] 2688226#2688226: *84 [lua] hot.lua:26: timeit(): timeit foo: 0.07 msecs, client: 127.0.0.1, server: , request: "GET /get HTTP/1.1", host: "lo
calhost:10000"
2022/08/28 21:45:03 [info] 2688226#2688226: *84 [lua] hot.lua:26: timeit(): timeit bar: 0.03 msecs, client: 127.0.0.1, server: , request: "GET /get HTTP/1.1", host: "lo
calhost:10000"
2022/08/28 21:45:08 [info] 2688226#2688226: *89 [lua] init.lua:57: alive hooks: {}, context: ngx.timer

##
## remove hooks
##

rm -f /opt/lua-resty-inspect/example/resty_inspect_hooks.lua

```
