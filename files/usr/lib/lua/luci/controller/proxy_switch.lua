module("luci.controller.proxy_switch", package.seeall)

function index()
	entry({"admin", "services", "proxy_switch"},
		cbi("proxy_switch"),
		_("Proxy Switch"), 60)
end
