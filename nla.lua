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

-- identify if request is app or resource
if ngx.re.find(ngx.var.uri, "\\/.*?\\.[a-z]+($|\\?|#)", "ioj")
    and not ngx.re.find(ngx.var.uri, "\\/.*?\\.(" .. config.app_ext .. ")($|\\?|#)", "ioj") then
    if not config.check_static and ngx.re.find(ngx.var.uri, "\\/.*?\\.(" .. config.ext_static .. ")($|\\?|#)", "ioj") then
        return
    end
    ngx.ctx.nla_rtype = "resource"
else
    local count, err = anticc:incr("app_requests", 1)
    if not count then
        anticc:set("app_requests", 1, 10)
        count = 1
    end
    if count >= config.pages_per_ten_second then
        ngx.ctx.nla_rtype = "app"
        anticc:set("ddos", true, 60)
        if count == config.pages_per_ten_second then
            ngx.log(ngx.ERR, "ddos mode on next 60s")
        end
    else
        ngx.ctx.nla_rtype = "resource"
    end
end

local network_id = ngx.var.remote_addr .. ngx.var.hostname .. (headers["User-Agent"] or "")
local remote_id = ngx.var.remote_addr
local count, err = anticc:incr("request" .. network_id, 1)
if not count then
    anticc:set("request" .. network_id, 1, 10)
    count = 1
end

local rotate_after_second
local ddos = anticc:get("ddos")
if ddos == true then
    rotate_after_second = config.rotate_after_second_ddos
else
    if config.always then
        rotate_after_second = config.rotate_after_second
    else
        -- Отключаем режим защиты
        if count < config.requests_per_ten_second then
            return
        end
    end
end

-- wp ddos and simple bots
if type(headers["User-Agent"]) ~= "string"
    or headers["User-Agent"] == ""
    or ngx.re.find(headers["User-Agent"], "^PHP", "ioj")
    or ngx.re.find(headers["User-Agent"], "^WordPress", "ioj") then
    ngx.log(ngx.ERR, "ddos")
    ngx.exit(444)
    return
end

if ngx.re.find(headers["User-Agent"],config.white_bots , "ioj") then
    local count, err = anticc:incr("search_bot", 1)
    if not count then
        anticc:set("search_bot", 1, 60)
        count = 1
    end
    if count >= config.bot_requests_per_minute then
        if count == config.bot_requests_per_minute then
            ngx.log(ngx.ERR, "bot banned")
        end
        ngx.exit(444)
        return
    end
    return
end

local cookie_key = config.cookie_key .. math.floor(os.time() / rotate_after_second)

-- get or set client seed
local sid
if cookies[config.cookie_sid_name] == nil then
    sid = ngx.md5(network_id .. (os.time() + os.clock()))
else
    sid = cookies[config.cookie_sid_name]
end

-- session tokens
local user_id = ngx.encode_base64(ngx.sha1_bin(cookie_key .. network_id .. sid))  -- у реаьного киента sid не меняется network_id - может

-- counter from ip
if not cookies[config.cookie_name] then
   local count, err = anticc:incr("nocookie" .. remote_id, 1)
    if not count then
        anticc:set("nocookie" .. remote_id, 1, 60)
        count = 1
    end
    if count >= 256 then
        if count == 256 then
            ngx.log(ngx.ERR, "client banned by remote address")
        end
        ngx.exit(444)
        return
    end
    count, err = anticc:incr("nocookie" .. network_id, 1)
    if not count then
        anticc:set("nocookie" .. network_id, 1, 3600)
        count = 1
    end
    if count >= 1024 then
        if count == 1024 then
            ngx.log(ngx.ERR, "client banned by network")
        end
        ngx.exit(444)
        return
    end
    cookie.challenge(config.cookie_name, user_id, config.cookie_sid_name, sid)
    return
end

-- counter from sid
if cookies[config.cookie_name] ~= ngx.md5(user_id) then
    ngx.log(ngx.ERR, cookies[config.cookie_name])
    ngx.log(ngx.ERR, ngx.md5(user_id))

    local count, err = anticc:incr("bad_cookie" .. cookies[config.cookie_name], 1)
    if not count then
        anticc:set("bad_cookie" .. cookies[config.cookie_name], 1, rotate_after_second * 2)
        count = 1
    end
    if count >= 1024 then
        if count == 1024 then
            ngx.log(ngx.ERR, "client banned by bad sid")
        end
        ngx.exit(444)
        return
    end
    cookie.challenge(config.cookie_name, user_id, config.cookie_sid_name, sid)
    return
end

count, err = anticc:incr(user_id, 1)
if not count then
    anticc:set(user_id, 1, 10)
    count = 1
end

if count >= config.requests_per_ten_second then
    cookie.challenge(config.cookie_name, user_id, config.cookie_sid_name, sid)
    return
end
