
-- if client IP is in whitelist, pass
local whitelist = ngx.shared.nla_whitelist
in_whitelist = whitelist:get(ngx.var.remote_addr)
if in_whitelist then
    return
end

local config = require("config")
local anticc = ngx.shared.nla_anticc
local search_bot = "search:bot:count:request:per:10:s"
local app_requests = "app:request:count:per:10:s"
-- headers
local headers = ngx.req.get_headers();
-- cookies
local cookie = require("cookie")
local cookies = cookie.get()

-- identify if request is page or resource
local is_page
if ngx.re.find(ngx.var.uri, "\\/.*?\\.[a-z]+($|\\?|#)", "ioj")
    and not ngx.re.find(ngx.var.uri, "\\/.*?\\.(" .. config.app_ext .. ")($|\\?|#)", "ioj") then
    ngx.ctx.nla_rtype = "resource"
    is_page = false
else
    is_page = true
    local count, err = anticc:incr(app_requests, 1)
    if not count then
        anticc:set(app_requests, 1, 10)
        count = 1
    end
    if count >= config.pages_per_ten_second then
        ngx.ctx.nla_rtype = "page"
        anticc:set("ddos", true, 60)
        -- ngx.log(ngx.ERR, "ddos mode on next 60s")
    else
        ngx.ctx.nla_rtype = "resource"
    end
end


local ROTATE_AFTER_SECOND
local ddos = anticc:get("ddos")
if ddos == true then
    ROTATE_AFTER_SECOND = config.rotate_after_second_ddos
else
    if config.always then
        ROTATE_AFTER_SECOND = config.rotate_after_second
    else
        -- Отключаем режим защиты
        return
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
    local count, err = anticc:incr(search_bot, 1)
    if not count then
        anticc:set(search_bot, 1, 30)
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

-- config options
local COOKIE_NAME = config.cookie_name
local COOKIE_SID_NAME = config.cookie_sid_name
local REQUESTS_PER_TEN_SECOND = config.requests_per_ten_second
local PAGES_PER_TEN_SECOND = config.pages_per_ten_second
local COOKIE_KEY = config.cookie_key .. math.floor(os.time() / ROTATE_AFTER_SECOND)

-- get or set client seed
local sid
if cookies[COOKIE_SID_NAME] == nil then
    sid = ngx.md5(ngx.var.remote_addr .. ngx.var.hostname .. (headers["User-Agent"] or "") .. (os.time() + os.clock()))
else
    sid = cookies[COOKIE_SID_NAME]
end

-- session tokens
local user_id = ngx.encode_base64(ngx.sha1_bin(ngx.var.remote_addr .. ngx.var.hostname .. (headers["User-Agent"] or "") .. COOKIE_KEY .. sid))
local network_id = ngx.md5(ngx.var.remote_addr .. ngx.var.hostname .. (headers["User-Agent"] or ""))
local remote_id = ngx.md5(ngx.var.remote_addr)

local count, err = anticc:incr(user_id, 1)
if not count then
    anticc:set(user_id, 1, 10)
    count = 1
end

-- counter from ip
if not cookies[COOKIE_NAME] then
   local count, err = anticc:incr(remote_id, 1)
    if not count then
        anticc:set(remote_id, 1, 60)
        count = 1
    end
    if count >= 256 then
        if count == 256 then
            ngx.log(ngx.ERR, "client banned by remote address")
        end
        ngx.exit(444)
        return
    end
    count, err = anticc:incr(network_id, 1)
    if not count then
        anticc:set(network_id, 1, 3600)
        count = 1
    end
    if count >= 1024 then
        if count == 1024 then
            ngx.log(ngx.ERR, "client banned by network")
        end
        ngx.exit(444)
        return
    end
    cookie.challenge(COOKIE_NAME, user_id, COOKIE_SID_NAME, sid)
    return
end

-- counter from sid
if cookies[COOKIE_NAME] ~= ngx.md5(user_id) then
    ngx.log(ngx.ERR, cookies[COOKIE_NAME])
    ngx.log(ngx.ERR, ngx.md5(user_id))

    local count, err = anticc:incr(cookies[COOKIE_NAME], 1)
    if not count then
        anticc:set(cookies[COOKIE_NAME], 1, ROTATE_AFTER_SECOND * 2)
        count = 1
    end
    if count >= 1024 then
        if count == 1024 then
            ngx.log(ngx.ERR, "client banned by bad sid")
        end
        ngx.exit(444)
        return
    end
    cookie.challenge(COOKIE_NAME, user_id, COOKIE_SID_NAME, sid)
    return
end

if (count > REQUESTS_PER_TEN_SECOND) then
    cookie.challenge(COOKIE_NAME, user_id, COOKIE_SID_NAME, sid)
    return
end
