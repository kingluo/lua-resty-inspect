local sock = require "socket"
local s = string.rep("a", 64) .. "ll"

local _M = {}

function _M.foo()
    for i=1,100 do
        for j=1,100 do
            string.find(s, "ll", 1, true)
        end
    end
end

local function bar()
    for i=1,100 do
        for j=1,100 do
            string.find(s, "ll", 1, true)
        end
    end
end

function _M.timeit(func, name, ...)
    local t1 = sock.gettime() * 1000
    func(...)
    local t2 = sock.gettime() * 1000
    ngx.log(ngx.INFO, string.format("timeit %s: %.2f msecs", name, t2-t1))
end

function _M.run_bar()
    _M.timeit(bar, "bar")
end

return _M
