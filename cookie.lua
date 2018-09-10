local _M = {}

_M.challenge_code_tmpl = [[
<html>
<head>
    <script src="/md5.js"></script>
    <script>
      var begin = (new Date()).getTime();
      while((new Date()).getTime() - begin < 500);
      var cookie_name = "%s";
      var cookie_value = "%s";
      var cookie_sid = "%s";
      var sid = "%s";
      document.cookie = cookie_name + "=" + md5(cookie_value) + ";Path=/;Max-age=99999999";
      document.cookie = cookie_sid + "=" + sid + ";Path=/;Max-age=99999999";
      try {
        if (window.top.location.hostname === window.location.hostname) {
          window.location.reload();
        } else {
          window.top.location.href = "javascript:while(1);;";
        }
      } catch(ex) {
        window.top.location.href = "javascript:while(1);;";
      }
    </script>
</head>
<body>
</body>
]]

function _M.get()
    local headers = ngx.req.get_headers()
    local ret = {}
    if not headers["Cookie"] then
        return ret
    end
    if type(headers["Cookie"]) ~= "string" then
       return ret
    end
    for k, v in string.gmatch(headers["Cookie"], "([^=]+)=([^;]+);?%s*") do
        ret[k] = v
    end
    return ret
end

function _M.challenge(cookie_name, cookie_value, cookie_sid, sid)
    local headers = ngx.req.get_headers()
    -- if static resource is requested, use Set-Cookie and 302 to challenge
    if ngx.ctx.nla_rtype == "resource"
        or ngx.var.request_method ~= "GET"
        or ngx.re.find(ngx.var.uri, "\\/.*?\\.(json|xml)($|\\?|#)", "ioj")
        or headers["X-Requested-With"] == "XMLHttpRequest" then
        add_cookie(cookie_name .. "=" .. ngx.md5(cookie_value) .. ";Path=/;Max-age=99999999")
        add_cookie(cookie_sid .. "=" .. sid .. ";Path=/;Max-age=99999999")
        ngx.redirect(ngx.var.request_uri, ngx.HTTP_TEMPORARY_REDIRECT)
        return
    end

    -- use JS set cookie to challenge
    local challenge_code = string.format(_M.challenge_code_tmpl,
        cookie_name, cookie_value, cookie_sid, sid)
    ngx.header["Content-Type"] = "text/html;charset='utf-8'"
    ngx.say(challenge_code)
end

function get_cookies()
    local cookies = ngx.header["Set-Cookie"] or {}
    if type(cookies) == "string" then
        cookies = {cookies}
    end
    return cookies
end

function add_cookie(cookie)
    local cookies = get_cookies()
    table.insert(cookies, cookie)
    ngx.header['Set-Cookie'] = cookies
end

return _M
