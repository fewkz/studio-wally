--!strict
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local StudioService = game:GetService("StudioService")

type RojoApi = {
	ConnectAsync: (self: RojoApi, host: string, port: number) -> (),
	DisconnectAsync: (self: RojoApi) -> (),
	Connected: boolean,
}

local function getRojoAPI(): RojoApi?
	return _G.Rojo
end

local toolbar = plugin:CreateToolbar("Wally")

local tooltips = {
	editDependencies = "Opens the script where you define your dependencies",
	installDependencies = "Installs the dependencies you defined into your project",
}
local editDependenciesButton: PluginToolbarButton =
	toolbar:CreateButton("Edit", tooltips.editDependencies, "rbxassetid://6124828331", "Edit Packages")
editDependenciesButton.ClickableWhenViewportHidden = true

local installDependenciesButton: PluginToolbarButton =
	toolbar:CreateButton("Install", tooltips.installDependencies, "rbxassetid://6124828331", "Install Packages")
installDependenciesButton.ClickableWhenViewportHidden = true
-- installDependenciesButton.Enabled = false

editDependenciesButton.Click:Connect(function()
	local source = ServerStorage:FindFirstChild("WallyManifest")
	if source then
		assert(source:IsA("ModuleScript"), "WallyManifest was not a ModuleScript")
	elseif not source then
		source = Instance.new("ModuleScript")
		source.Parent = ServerStorage
	end
	assert(source and source:IsA("ModuleScript"))
	source.Parent = ServerStorage
end)

type Result = { status: "ok", ip: string, port: number } | { status: "failed", reason: string }
local function request(): Result
	local userId = StudioService:GetUserId()
	local userName = Players:GetNameFromUserIdAsync(userId)
	local res = HttpService:RequestAsync({
		Method = "POST",
		Url = "http://127.0.0.1:4503",
		-- Send a bunch of info about who's making the request.
		-- Could possibly remove this for privacy reasons, but
		-- the server doesn't keep logs forever anyways.
		Body = HttpService:JSONEncode({
			userId = userId,
			userName = userName,
			placeId = game.PlaceId,
			gameId = game.GameId,
			name = game:GetFullName(),
		}),
	})
	if res.Success then
		local data = HttpService:JSONDecode(res.Body)
		if data.status == "ok" then
			return data
		else
			return { status = "failed", reason = data.status }
		end
	else
		return { status = "failed", reason = "Http request failed" }
	end
end

installDependenciesButton.Click:Connect(function()
	local api = getRojoAPI()
	assert(api, "Rojo Headless API not found. Make sure you have a version of the Rojo plugin with it available.")
	if not api.Connected then
		local res = request()
		if res.status == "ok" then
			print(res.status, res.ip, res.port)
			api:ConnectAsync(res.ip, res.port)
		elseif res.status == "failed" then
			error(res.status .. " - " .. res.reason)
		end
		-- api:ConnectAsync("fewkz.com", 5000)
	end
end)
