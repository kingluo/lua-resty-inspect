local dbg = require 'resty.inspect.dbg'
local lfs = require 'lfs'
local cjson = require "cjson"

local _M = {}

local last_modified = 0

local stop = false

local running = false

local last_report_time = 0

local function is_file_exists(file)
   local f = io.open(file, "r")
   if f then io.close(f) return true else return false end
end

local function setup_hooks(file)
    if is_file_exists(file) then
        dbg.unset_all()
        local chunk = loadfile(file)
        local ok, err = pcall(chunk)
        local hooks = {}
        for _, hook in ipairs(dbg.hooks()) do
            table.insert(hooks, hook.key)
        end
        ngx.log(ngx.INFO, "set hooks: err=", err, ", hooks=", cjson.encode(hooks))
    end
end

local function reload_hooks(premature, delay, file)
    if premature or stop then
        stop = false
        running = false
        return
    end

    local time, err = lfs.attributes(file, 'modification')
    if err then
        if last_modified ~= 0 then
            ngx.log(ngx.INFO, err, ", disable all hooks")
            dbg.unset_all()
            last_modified = 0
        end
    elseif time ~= last_modified then
        setup_hooks(file)
        last_modified = time
    else
        local ts = os.time()
        if ts - last_report_time >= 5 then
            local hooks = {}
            for _, hook in ipairs(dbg.hooks()) do
                table.insert(hooks, hook.key)
            end
            ngx.log(ngx.INFO, "alive hooks: ", cjson.encode(hooks))
            last_report_time = ts
        end
    end

    local ok, err = ngx.timer.at(delay, reload_hooks, delay, file)
    if not ok then
        ngx.log(ngx.ERR, "failed to create the timer: ", err)
        running = false
    end
end

function _M.init(delay, file)
    if not running then
        file = file or "/var/run/resty_inspect_hooks.lua"
        delay = delay or 3

        setup_hooks(file)

        local ok, err = ngx.timer.at(delay, reload_hooks, delay, file)
        if not ok then
            ngx.log(ngx.ERR, "failed to create the timer: ", err)
            return
        end
        running = true
    end
end

function _M.destroy()
    stop = true
end

return _M
