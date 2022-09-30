--!strict
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StudioService = game:GetService("StudioService")

type RojoApi = {
	ConnectAsync: (self: RojoApi, host: string, port: number) -> (),
	DisconnectAsync: (self: RojoApi) -> (),
	Connected: boolean,
	Changed: RBXScriptSignal<string, any?, any?>,
}

local function getRojoAPI(): RojoApi?
	return _G.Rojo
end

local toolbar = plugin:CreateToolbar("Studio Wally")

local tooltips = {
	editManifest = "Opens the script where you define your packages",
	installPackages = "Installs the packages you defined into your project",
}
local editManifestButton: PluginToolbarButton =
	toolbar:CreateButton("Edit", tooltips.editManifest, "rbxassetid://6124828331", "Edit Packages")
editManifestButton.ClickableWhenViewportHidden = true

local installPackagesButton: PluginToolbarButton =
	toolbar:CreateButton("Install", tooltips.installPackages, "rbxassetid://6124828331", "Install Packages")
installPackagesButton.ClickableWhenViewportHidden = true

local manifestTemplate = [[
-- This is the manifest file for the Studio Wally plugin.
-- In this file, you define all the packages you want
-- the plugin to install.
return {
	-- The server is where the plugin connects to via rojo
	-- to pull packages from. For info on hosting your own
	-- server, see https://github.com/fewkz/studio-wally/tree/main/server
	studioWallyServer = "https://studio-wally.fewkz.com",
	-- Packages are defined in the standard wally format of
	-- Name = "user/package@version"
	-- Visit https://wally.run/ to find available packages
	packages = {
		-- Promise = "evaera/promise@4.0.0",
	}
}
]]

editManifestButton.Click:Connect(function()
	local source = ServerStorage:FindFirstChild("StudioWallyManifest")
	if source then
		assert(source:IsA("ModuleScript"), "StudioWallyManifest was not a ModuleScript")
	elseif not source then
		source = Instance.new("ModuleScript")
		source.Name = "StudioWallyManifest"
		source.Source = manifestTemplate
	end
	assert(source and source:IsA("ModuleScript"))
	source.Parent = ServerStorage
	plugin:OpenScript(source)
end)

local packagePattern = "^.+/.+@.+$"
local function loadManifest(): { status: "ok", url: string, packages: { string } } | { status: "manifest_not_found" }
	local source = ServerStorage:FindFirstChild("StudioWallyManifest")
	if source then
		assert(source:IsA("ModuleScript"), "StudioWallyManifest was not a ModuleScript")
		local manifest = require(source:Clone())
		assert(typeof(manifest.studioWallyServer) == "string", "Manifest is missing valid studioWallyServer field")
		if manifest.dependencies then
			error("Dependencies field was renamed to packages, you must rename it in the manifest.")
		end
		assert(typeof(manifest.packages) == "table", "Manifest is missing valid packages field.")
		local packageStrings = {}
		for name, package in manifest.packages do
			assert(typeof(name) == "string", "Package had key " .. tostring(name) .. ", must be a string.")
			assert(typeof(package) == "string" and string.match(package, packagePattern), "Invalid package " .. package)
			table.insert(packageStrings, name .. ' = "' .. package .. '"')
		end
		return {
			status = "ok",
			url = manifest.studioWallyServer,
			packages = packageStrings,
		}
	else
		return { status = "manifest_not_found" }
	end
end

type Result = { status: "ok", ip: string, port: number } | { status: "failed", reason: string }
local function request(url, packages: { string }): Result
	local userId = StudioService:GetUserId()
	local userName = Players:GetNameFromUserIdAsync(userId)
	local res = HttpService:RequestAsync({
		Method = "POST",
		Url = url,
		-- Send a bunch of info about who's making the request.
		-- Could possibly remove this for privacy reasons, but
		-- the server doesn't keep logs forever anyways.
		Body = HttpService:JSONEncode({
			dependencies = packages,
			placeName = game:GetFullName(),
			placeId = game.PlaceId,
			gameId = game.GameId,
			userName = userName,
			userId = userId,
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
		return { status = "failed", reason = "Http request failed: " .. res.StatusMessage }
	end
end

local function hasNonManagedPackages()
	local commonPackages = ReplicatedStorage:FindFirstChild("Packages")
	local serverPackages = ServerStorage:FindFirstChild("Packages")

	return (
		(commonPackages and commonPackages:GetAttribute("StudioWallyManaged") ~= true)
		or (serverPackages and serverPackages:GetAttribute("StudioWallyManaged") ~= true)
	)
end

local function afterInitialSync()
	local commonPackages = ReplicatedStorage:WaitForChild("Packages", 1)
	local serverPackages = ServerStorage:WaitForChild("Packages", 1)
	assert(commonPackages, "Common packages didn't exist after initial sync")
	assert(serverPackages, "Server packages didn't exist after initial sync")
	serverPackages:SetAttribute("StudioWallyManaged", true)
	commonPackages:SetAttribute("StudioWallyManaged", true)
end

local function detectInitialSync(api: RojoApi)
	if api.Changed then
		local conn
		conn = api.Changed:Connect(function(prop)
			if prop == "Connected" then
				api:DisconnectAsync()
				conn:Disconnect()
				afterInitialSync()
			end
		end)
	else
		-- Is there a better way to code this race condition?
		local thread2
		local thread = task.spawn(function()
			repeat
				task.wait()
			until api.Connected
			api:DisconnectAsync()
			afterInitialSync()
			task.cancel(thread2)
		end)
		thread2 = task.delay(10, function()
			task.cancel(thread)
			api:DisconnectAsync()
			error("Initial sync never went through")
		end)
	end
end

installPackagesButton.Click:Connect(function()
	local manifest = loadManifest()
	if manifest.status ~= "ok" then
		error("Failed to load manifest: " .. manifest.status)
		return
	end
	assert(manifest.status == "ok")
	local api = getRojoAPI()
	assert(api, "Rojo Headless API not found. Make sure you have a version of the Rojo plugin with it available.")
	if not api.Connected then
		local nonManagedPackagesWarning = "This place has a Packages folder that wasn't made by studio wally."
			.. " Please delete it yourself to make sure studio wally won't override anything."
		assert(not hasNonManagedPackages(), nonManagedPackagesWarning)
		local res = request(manifest.url, manifest.packages)
		if res.status == "ok" then
			api:ConnectAsync(res.ip, res.port)
			detectInitialSync(api)
		elseif res.status == "failed" then
			warn("Request to wally server failed:", res)
			error("Request to wally server failed")
		end
	else
		error("Please disconnect from rojo before connecting")
	end
end)
