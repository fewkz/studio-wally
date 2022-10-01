local http = require("resty.http").new()
local json = require("cjson").new()
local uuid = require("resty.jit-uuid")

http:set_timeout(4000)

local function getJsonBody()
	ngx.req.read_body()
	local request_body = ngx.req.get_body_data()
	local suc, body = pcall(json.decode, request_body)
	if suc then
		return { status = "ok", data = body }
	else
		return { status = "err", msg = body }
	end
end

local body = getJsonBody()
if body.status ~= "ok" then
	ngx.say(json.encode(body))
	return
end

-- Read the default service account token (https://kubernetes.io/docs/tasks/run-application/access-api-from-pod/#without-using-a-proxy)
-- Update, upon reading the documentation, I realize I could of just ran a sidecar with the command `kubectl proxy` and avoid having to
-- do all the complicated certificate stuff and authorization entirely. Damn it.
local file = io.open("/var/run/secrets/kubernetes.io/serviceaccount/token", "r")
local token = file:read()

-- Get the external ip of any node in the cluster.
-- Read the comment about NodePorts near the bottom of the code for reasoning why we do this.
local function getExternalIP()
	local res, err = http:request_uri("http://127.0.0.1:81/api/v1/nodes", {
		method = "GET",
		headers = { Authorization = "Bearer " .. token },
	})
	ngx.log(ngx.INFO, "Received response from kubernetes api")
	if not res then
		ngx.log(ngx.ERR, "request failed: ", err)
		return { status = "request_failed" }
	end
	for i, v in pairs(json.decode(res.body).items[1].status.addresses) do
		if v.type == "ExternalIP" then
			return { status = "ok", address = v.address }
		end
	end
	return { status = "failed" }
end

local externalIP = getExternalIP()

if externalIP.status == "failed" then
	ngx.say(json.encode({ status = "failed_to_get_external_ip" }))
	return
end

local function createNamespacedObject(group, version, namespace, noun, data)
	local suc, body = pcall(json.encode, data)
	if not suc then
		return { status = "invalid_body" }
	end
	ngx.log(ngx.INFO, "Sending request to kubernetes api")
	local url
	if group == nil then
		url = string.format("http://127.0.0.1:81/api/%s/namespaces/%s/%s", version, namespace, noun)
	else
		url = string.format("http://127.0.0.1:81/apis/%s/%s/namespaces/%s/%s", group, version, namespace, noun)
	end
	local res, err = http:request_uri(url, {
		method = "POST",
		headers = { Authorization = "Bearer " .. token },
		body = body,
	})
	ngx.log(ngx.INFO, "Received response from kubernetes api")
	if not res then
		ngx.log(ngx.ERR, "request failed: ", err)
		return { status = "request_failed" }
	end
	if res.status == 201 then
		return { status = "created", resource = json.decode(res.body) }
	elseif res.status == 409 then
		return { status = "conflict", resource = json.decode(res.body) }
	else
		return { status = "failed_" .. res.status, resource = json.decode(res.body) }
	end
end

-- Probably a better way to generate a unique id
uuid.seed()
local id = string.sub(uuid(), 1, 8)
ngx.log(ngx.INFO, id)

local timeout = 240

local dependencies = body.data.dependencies
assert(dependencies, "Request didn't include a dependencies field")
ngx.log(
	ngx.INFO,
	"Received request from " .. body.data.userName .. " to install dependencies " .. table.concat(dependencies, ", ")
)

-- This is to prevent shell injection
local command = {
	"sh",
	"-c",
	string.format("timeout %d ./wally-server-startup.sh $0 $@ || test $? -eq 124", timeout),
}
for _, dependency in pairs(dependencies) do
	local noSpaces = string.gsub(dependency, " ", "")
	table.insert(command, noSpaces)
end

local job = createNamespacedObject("batch", "v1", "default", "jobs", {
	kind = "Job",
	metadata = {
		name = id,
		annotations = {
			placeName = tostring(body.data.placeName),
			placeId = tostring(body.data.placeId),
			gameId = tostring(body.data.gameId),
			userName = tostring(body.data.userName),
			userId = tostring(body.data.userId),
		},
	},
	spec = {
		ttlSecondsAfterFinished = 100,
		template = {
			spec = {
				restartPolicy = "Never",
				containers = {
					{
						name = "wally-server",
						image = "ghcr.io/fewkz/studio-wally/wally-server",
						command = command,
						ports = { {
							containerPort = 34872,
							name = "rojo-port",
						} },
					},
				},
			},
		},
	},
})
if job.status ~= "created" then
	ngx.log(ngx.ERR, "failed to create job because creating job had status ", job.status)
	ngx.say(json.encode({ status = "failed", reason = job }))
	return
end

-- Create a service for the job
local service = createNamespacedObject(nil, "v1", "default", "services", {
	kind = "Service",
	metadata = {
		name = "server-" .. id,
		ownerReferences = {
			{
				apiVersion = "batch/v1",
				kind = "Job",
				name = job.resource.metadata.name,
				uid = job.resource.metadata.uid,
			},
		},
	},
	spec = {
		-- A NodePort type service picks a random port and exposes it on
		-- all nodes on the cluster. I originally thought that it only exposed
		-- it on the same node as the pod is running on, but that's not the case.
		-- I should probably switch to a different method of exposing the port, since
		-- this limits up to a hard limit of ports 30000-32767 across our entire cluster
		type = "NodePort",
		selector = { ["job-name"] = id },
		ports = { {
			name = "rojo-port",
			protocol = "TCP",
			port = 34872,
		} },
	},
})
if service.status ~= "created" then
	ngx.log(ngx.ERR, "failed to create service because creating service had status ", service.status)
	ngx.say(json.encode({ status = "failed", reason = service }))
	return
end

ngx.say(json.encode({
	status = "ok",
	ip = externalIP.address,
	port = tostring(service.resource.spec.ports[1].nodePort),
	id = id, -- Eventually we should have the plugin tell the server to stop serving once it's finished syncing.
}))
