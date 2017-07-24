-- Copyright (c) 2017 by Canh Ngo (canhnt@gmail.com)
-- sticky_session.lua

local _M = {}

function _M.init(self, servers)
    local resty_roundrobin = require "resty.roundrobin"

    -- create ready_server_list containing only *ready* servers, looks up from address to the server weight
    -- create all_servers contains all servers that looks up from hash(server addr) to the server record

    local ready_server_list = {}
    local all_servers = {}
    for _, serv in ipairs(servers) do
        if serv.mode == "ready" then
            ready_server_list[serv.address] = serv.weight
        end
        local id = ngx.md5(serv.address)
        all_servers[id] = serv
    end

    self.my_servers = all_servers
    local rr_up = resty_roundrobin:new(ready_server_list)
    self.my_rr_up = rr_up

    print("loaded upstream list")
end

function _M.balancer(self)
    local servers = self.my_servers
    for _, serv in pairs(servers) do
        print(serv.address, "==>", serv.mode)
    end

    local balancer, err = require "ngx.balancer"
    if not balancer then
        ngx.log(ngx.ERR, err)
    end

    local rr_up = self.my_rr_up

    local server = ""
    local serverid = ngx.var.cookie_SERVERID
    print("SERVERID", "=>", serverid)
    if serverid then
        server = servers[serverid].address
    else
        -- round-robin
        server = rr_up:find()
        self.serverid = ngx.md5(server)
        self.set_serverid = true
    end

    print("Forwarding request to ", server)
    balancer.set_current_peer(server)
end

function _M.set_cookie(self)
    -- set SERVERID cookie if needed
    if not self.set_serverid then
        return
    end

    local ck = require "resty.cookie"
    local cookie, err = ck:new()
    if not cookie then
        ngx.log(ngx.ERR, err)
        return
    end

    local ok, err = cookie:set({
        key = "SERVERID",
        value = self.serverid,
        path = "/",
        httponly = true
    })
    if not ok then
        ngx.log(ngx.ERR, err)
    end
    self.set_serverid = false
end

return _M