# APISIX plugin

```
cd /opt
git clone https://github.com/kingluo/lua-resty-inspect
```

## start apisix with customized config.yaml

```
apisix start -c /opt/lua-resty-inspect/apisix/conf/config.yaml
```

## setup a test route

```
curl http://127.0.0.1:9180/apisix/admin/routes/test_limit_req -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '
{
    "methods": ["GET"],
    "uri": "/get",
    "plugins": {
        "limit-req": {
            "rate": 100,
            "burst": 0,
            "rejected_code": 503,
            "key_type": "var",
            "key": "remote_addr"
        }
    },
    "upstream": {
        "type": "roundrobin",
        "nodes": {
            "httpbin.org": 1
        }
    }
}'
```

## link hooks file

```
ln -sf /opt/lua-resty-inspect/apisix/hooks.lua /var/run/resty_inspect_hooks.lua
```

**Check the error.log:**

```
2022/09/01 00:55:38 [info] 2754534#2754534: *3700 [lua] init.lua:29: setup_hooks(): set hooks: err=nil, hooks=["limit-req.lua#88"], context: ngx.timer
```

## access the route

```
curl -i http://127.0.0.1:9080/get
```

**Check the error.log:**

```
2022/09/01 00:55:52 [info] 2754534#2754534: *4070 [lua] resty_inspect_hooks.lua:4: foo traceback
stack traceback:
        /opt/lua-resty-inspect/lib/resty/inspect/dbg.lua:50: in function </opt/lua-resty-inspect/lib/resty/inspect/dbg.lua:17>
        /opt/apisix.fork/apisix/plugins/limit-req.lua:88: in function 'phase_func'
        /opt/apisix.fork/apisix/plugin.lua:900: in function 'run_plugin'
        /opt/apisix.fork/apisix/init.lua:456: in function 'http_access_phase'
        access_by_lua(nginx.conf:303):2: in main chunk, client: 127.0.0.1, server: _, request: "GET /get HTTP/1.1", host: "127.0.0.1:9080"
2022/09/01 00:55:52 [info] 2754534#2754534: *4070 [lua] resty_inspect_hooks.lua:5: /opt/apisix.fork/apisix/plugins/limit-req.lua:88 (phase_func), client: 127.0.0.1, server: _, request: "GET /get HTTP/1.1", host: "127.0.0.1:9080"
2022/09/01 00:55:52 [info] 2754534#2754534: *4070 [lua] resty_inspect_hooks.lua:6: conf_key=remote_addr, client: 127.0.0.1, server: _, request: "GET /get HTTP/1.1", host: "127.0.0.1:9080"
```

## delete the hooks

```
rm -f /var/run/resty_inspect_hooks.lua
```

**Check the error.log:**

```
2022/09/01 01:04:26 [info] 2754534#2754534: *17539 [lua] init.lua:43: cannot obtain information from file '/var/run/resty_inspect_hooks.lua': No such file or directory, disable all hooks, context: ngx.timer
```

## stop apisix

```
apisix stop
```
