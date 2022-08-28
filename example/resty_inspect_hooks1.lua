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
