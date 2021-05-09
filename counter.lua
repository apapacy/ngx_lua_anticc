-- local exec = require 'resty.exec'
-- if client IP is in whitelist, pass
local whitelist = ngx.shared.nla_whitelist
in_whitelist = whitelist:get(ngx.var.remote_addr)
if in_whitelist then
    return
end

local config = require("config")
local anticc = ngx.shared.nla_anticc
-- headers
local headers = ngx.req.get_headers();
-- cookies
local cookie = require("cookie")
local cookies = cookie.get()

-- wp ddos and simple bots
if headers["User-Agent"] == nil
    or type(headers["User-Agent"]) ~= "string"
    or headers["User-Agent"] == ""
    or ngx.re.find(headers["User-Agent"], "^PHP", "ioj")
    or ngx.re.find(headers["User-Agent"], "^WordPress", "ioj") then
    ngx.log(ngx.WARN, "ddos")
    ngx.exit(444)
    return
end

-- identify if request is app or resource
local nla_rtype
if ngx.re.find(ngx.var.uri, "\\/.*?\\.[a-z]+($|\\?|#)", "ioj")
    and not ngx.re.find(ngx.var.uri, "\\/.*?\\.(" .. config.app_ext .. ")($|\\?|#)", "ioj") then
    nla_rtype = "resource"
else
    nla_rtype = "app"
    local count, err = anticc:incr("app_requests", 1)
    if not count then
        anticc:set("app_requests", 1, 10)
        count = 1
    end
    if count >= config.pages_per_ten_second then
        anticc:set("ddos", true, 60)
        if count == config.pages_per_ten_second then
            ngx.log(ngx.WARN, "ddos mode on next 60s")
        end
    end
end

local network_id = ngx.encode_base64(ngx.sha1_bin(ngx.var.remote_addr .. ngx.var.hostname .. (headers["User-Agent"] or "")))
local remote_id = ngx.var.remote_addr
local count, err = anticc:incr("network:id:" .. nla_rtype .. ":" .. network_id, 1)
if not count then
    anticc:set("network:id:" .. nla_rtype .. ":" .. network_id, 1, 60 * 60 * 1)
    count = 1
end

local rotate_after_second
local ddos = anticc:get("ddos")
if ddos == true then
    rotate_after_second = config.rotate_after_second_ddos
else
    rotate_after_second = config.rotate_after_second
end

if ngx.re.find(headers["User-Agent"],config.white_bots , "ioj") then
    local count, err = anticc:incr("search_bot", 1)
    if not count then
        anticc:set("search_bot", 1, 60)
        count = 1
    end
    if count >= config.bot_requests_per_minute then
        if count == config.bot_requests_per_minute then
            ngx.log(ngx.WARN, "bot banned")
        end
        ngx.exit(444)
        return
    end
    return
end

local app_count = anticc:get("network:id:app:" .. network_id)
local resource_count = anticc:get("network:id:resource:" .. network_id)
if (nla_rtype == "app" and app_count and app_count > 10) then
  if (not resource_count or resource_count/app_count < 10 and resource_count < 100) then
    ngx.log(ngx.ERR, "client banned by request count " .. app_count .. "/" .. (resource_count or ""))
    ngx.exit(444)
  end
end
