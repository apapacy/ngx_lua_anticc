# ngx_lua_anticc
**ngx_lua_anticc** is a CC(ChallengeCollapsar) attack mitigation tool for Nginx. CC attack (i.e. HTTP request flood) is kind of layer 7 DDoS attack. ngx_lua_anticc is an extension of Nginx based on [ngx_lua](https://github.com/openresty/lua-nginx-module). With it, you can easily add CC attack protection for your web server.

# Forked from

[leeyiw/ngx_lua_anticc](https://github.com/leeyiw/ngx_lua_anticc)

# Download

git clone https://github.com/apapacy/ngx_lua_anticc.git

# Configure && Install

## 1. Prepare your nginx

Install nginx-extras or openresty with Lua module

## 2. Prepare resty.exec dependencies

https://github.com/jprjr/lua-resty-exec
https://github.com/skarnet/skalibs
https://github.com/jprjr/sockexec
Success compile with version 2.6.4

## 2. Deploy ngx_lua_anticc with your nginx

1. Edit your `nginx.conf`, add `include ngx_lua_anticc/nla.conf;` into the *http* section.

## 3. Configure ngx_lua_anticc

1. Copy from *.dist and edit the config file `ngx_lua_anticc/nla.conf`.

2. Copy from *.dist and edit the config file `ngx_lua_anticc/wl.lua`.
  ```
  whitelist:add("127.0.0.1", true)
  ```

## 4. Restart nginx

After you restart nginx, the Anti-CC protection is automatically enabled. Enjoy your web service without CC attacks!
