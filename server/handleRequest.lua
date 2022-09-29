local http = require("resty.http").new()

http:set_timeout(4000)

-- Read the default service account token (https://kubernetes.io/docs/tasks/run-application/access-api-from-pod/#without-using-a-proxy)
-- Update, upon reading the documentation, I realize I could of just ran a sidecar with the command `kubectl proxy` and avoid having to
-- do all the complicated certificate stuff and authorization entirely. Damn it.
local file = io.open("/var/run/secrets/kubernetes.io/serviceaccount/token", "r")
local token = file:read()

ngx.log(ngx.INFO, "Sending request to kubernetes api")

local body = [[{
"kind": "Job",
"metadata": { "name": "lol" },
"spec": { "ttlSecondsAfterFinished": 100, "template": { "spec": {
	"containers": [ {
		"name": "test",
		"image": "ghcr.io/fewkz/studio-wally/wally-server",
		"command": ["sh", "-c", "timeout 20 ./wally-server-startup.sh || test $? -eq 124"]
	}],
	"restartPolicy": "Never"
} } }
}]]
local res, err = http:request_uri("http://127.0.0.1:81/apis/batch/v1/namespaces/default/jobs", {
	method = "POST",
	headers = {
		Authorization = "Bearer " .. token,
	},
	body = body,
})
ngx.log(ngx.INFO, "Received response from kubernetes api")
if not res then
	ngx.log(ngx.ERR, "request failed: ", err)
	return
end
for i, v in pairs(res) do
	ngx.say(tostring(i) .. " " .. tostring(v))
end
