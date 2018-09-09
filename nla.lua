-- if client IP is in whitelist, pass
local whitelist = ngx.shared.nla_whitelist
in_whitelist = whitelist:get(ngx.var.remote_addr)
if in_whitelist then
    return
end

-- HTTP headers
local headers = ngx.req.get_headers();

-- wp ddos
if type(headers["User-Agent"]) ~= "string"
    or headers["User-Agent"] == ""
    or ngx.re.find(headers["User-Agent"], "^WordPress", "ioj") then
    ngx.log(ngx.ERR, "ddos")
    ngx.exit(444)
    return
end

local banlist = ngx.shared.nla_banlist
local search_bot = "search:bot:count:request:per:10:s"
local app_requests = "app:request:count:per:10:s"
if ngx.re.find(headers["User-Agent"], "Google Page Speed Insights|Googlebot|baiduspider|twitterbot|facebookexternalhit|rogerbot|linkedinbot|embedly|quora link preview|showyoubot|outbrain|pinterest|slackbot|vkShare|W3C_Validator|YandexBot|AdsBot-Google|bingbot|UptimeRobot|PrivatMarket|COMODO DCV", "ioj") then
    local count, err = banlist:incr(search_bot, 1)
    if not count then
        banlist:set(search_bot, 1, 10)
        count = 1
    end
    if count >= 50 then
        if count == 50 then
            ngx.log(ngx.ERR, "bot banned")
        end
        ngx.exit(444)
        return
    end
    return
end

-- cookies
local cookie = require("cookie")
local cookies = cookie.get()

-- global shared dict
local config = ngx.shared.nla_config
local req_count = ngx.shared.nla_req_count
local net_count = ngx.shared.nla_net_count
local page_count = ngx.shared.nla_page_count

-- config options
local ROTATE_AFTER_SECOND = config:get("rotate_after_second")
local COOKIE_NAME = config:get("cookie_name")
local COOKIE_SID = config:get("cookie_sid")
-- local COOKIE_KEY = config:get("cookie_key") .. math.floor(os.time() / ROTATE_AFTER_SECOND)
local REQUESTS_PER_TEN_SECOND = config:get("requests_per_ten_second")
local PAGES_PER_TEN_SECOND = config:get("pages_per_ten_second")

-- identify if request is page or resource
local is_page
if ngx.re.find(ngx.var.uri, "\\/.*?\\.[a-z]+($|\\?|#)", "ioj") 
    and not ngx.re.find(ngx.var.uri, "\\/.*?\\.(html|htm|php|py|pl|asp|aspx|ashx)($|\\?|#)", "ioj") then
    ngx.ctx.nla_rtype = "resource"
    is_page = false
else
    is_page = true
    local count, err = banlist:incr(app_requests, 1)
    if not count then
        banlist:set(app_requests, 1, 10)
        count = 1
    end
    if count >= PAGES_PER_TEN_SECOND then
        ngx.ctx.nla_rtype = "page"
        config:set("ddos", true, 60)
        ngx.log(ngx.ERR, "ddos mode on next 60s")
    else
        ngx.ctx.nla_rtype = "resource"
    end
end


local ddos = config:get("ddos")
if not (ddos == true) then
    ROTATE_AFTER_SECOND = 600
end

local COOKIE_KEY = config:get("cookie_key") .. math.floor(os.time() / ROTATE_AFTER_SECOND)


-- init random
-- math.randomseed(os.time() + os.clock())

-- get or set client seed
local sid
if cookies[COOKIE_SID] == nil then
    sid = ngx.md5(ngx.var.remote_addr .. ngx.var.hostname .. (headers["User-Agent"] or "") .. (os.time() + os.clock()))
else
    sid = cookies[COOKIE_SID]
end

-- session tokens
local user_id = ngx.encode_base64(ngx.sha1_bin(ngx.var.remote_addr .. ngx.var.hostname .. (headers["User-Agent"] or "") .. COOKIE_KEY .. sid))
local network_id = ngx.md5(ngx.var.remote_addr .. ngx.var.hostname .. (headers["User-Agent"] or ""))

local count, err = req_count:incr(ngx.md5(user_id), 1)
if not count then
    req_count:set(ngx.md5(user_id), 1, 10)
    count = 1
end

-- counter from ip
if not cookies[COOKIE_NAME] then
    local count, err = net_count:incr(network_id, 1)
    if not count then
        net_count:set(network_id, 1, 3600)
        count = 1
    end
    if count >= 1024 then
        if count == 1024 then
            ngx.log(ngx.ERR, "client banned by network")
        end
        ngx.exit(444)
        return
    end
    cookie.challenge(COOKIE_NAME, user_id, COOKIE_SID, sid)
    return
end

-- counter from sid
if cookies[COOKIE_NAME] ~= ngx.md5(user_id) then
    local count, err = banlist:incr(cookies[COOKIE_NAME], 1)
    if not count then
        banlist:set(cookies[COOKIE_NAME], 1, ROTATE_AFTER_SECOND * 2)
        count = 1
    end
    if count >= 1024 then
        if count == 1024 then
            ngx.log(ngx.ERR, "client banned by bad sid")
        end
        ngx.exit(444)
        return
    end
    cookie.challenge(COOKIE_NAME, user_id, COOKIE_SID, sid)
    return
end

if is_page then
    local count, err = page_count:incr(network_id, 1)
    if not count then
        page_count:set(network_id, 1, 1)
        count = 1
    end
    if count >= 16 then
        if count == 16 then
            ngx.log(ngx.ERR, "client banned by network on page")
        end
        ngx.exit(444)
        return
    end
end


-- counter from sid
-- if count >= 512 then
--    local count, err = banlist:incr(sid, 1)
--    if not count then
--        banlist:set(sid, 1, 3600 + math.random(0, 600))
--        count = 1
--    end
--    if count >= 9999999 then
--        if count == 9999999 then
--            ngx.log(ngx.ERR, "client banned by retry")
--        end
--        ngx.exit(444)
--        return
--    end
--    cookie.challenge(COOKIE_NAME, user_id, COOKIE_SID, sid)
--    return
-- end

if (count > REQUESTS_PER_TEN_SECOND) then
    cookie.challenge(COOKIE_NAME, user_id, COOKIE_SID, sid)
    return
end
