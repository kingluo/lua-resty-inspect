local dbg = require "resty.inspect.dbg"

dbg.set_hook("limit-req.lua", 88, require("apisix.plugins.limit-req").access, function(info)
    ngx.log(ngx.INFO, debug.traceback("foo traceback", 3))
    ngx.log(ngx.INFO, dbg.getname(info.finfo))
    ngx.log(ngx.INFO, "conf_key=", info.vals.conf_key)
    return true
end)
