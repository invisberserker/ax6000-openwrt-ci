local m, s, o
local sys = require "luci.sys"

m = Map("proxy_switch", translate("Proxy Switch"),
	translate("Select exactly one active proxy. Switching stops both, " ..
		"restarts dnsmasq and firewall, then starts the selected one."))

s = m:section(NamedSection, "main", "proxy_switch", translate("Active proxy"))
s.addremove = false

o = s:option(ListValue, "mode", translate("Mode"))
o:value("off", translate("Off (direct internet)"))
o:value("openclash", translate("OpenClash (mihomo)"))
o:value("xray", translate("Xray (ssr-plus)"))
o.rmempty = false

function m.on_after_commit(self)
	local mode = self.uci:get("proxy_switch", "main", "mode") or "off"
	local rc = sys.call("/usr/bin/proxy-switch " .. mode)
	if rc ~= 0 then
		sys.call("logger -t proxy-switch 'LuCI switch to " .. mode .. " failed rc=" .. tostring(rc) .. "'")
	end
end

return m
