--!strict
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SerializationService = game:GetService("SerializationService")
local ServerStorage = game:GetService("ServerStorage")

local toolbar = plugin:CreateToolbar("Studio Wally")

local tooltips = {
	editManifest = "Opens the script where you define your packages",
	installPackages = "Installs the packages you defined into your project",
}
local editManifestButton: PluginToolbarButton =
	toolbar:CreateButton("Edit", tooltips.editManifest, "rbxassetid://121050972869021", "Edit Packages")
editManifestButton.ClickableWhenViewportHidden = true

local installPackagesButton: PluginToolbarButton =
	toolbar:CreateButton("Install", tooltips.installPackages, "rbxassetid://94249622653524", "Install Packages")
installPackagesButton.ClickableWhenViewportHidden = true

local manifestTemplate = [[
-- This is the manifest file for the Studio Wally plugin.
-- In this file, you define all the packages you want
-- the plugin to install.
return {
	-- The server is where the plugin pulls built packages
	-- from. For info on hosting your own
	-- server, see https://github.com/fewkz/studio-wally/tree/main/server
	studioWallyServer = "https://studio-wally.fewkz.com",
	-- Packages are defined in the standard wally format of
	-- Name = "user/package@version"
	-- Visit https://wally.run/ to find available packages
	packages = {
		-- Promise = "evaera/promise@4.0.0",
	},
	-- Packages listed here are installed into ServerStorage
	-- instead, so the client never sees them.
	serverPackages = {
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
local function makePackageStrings(packages)
	local packageStrings = {}
	for name, package in packages do
		assert(typeof(name) == "string", "Package had key " .. tostring(name) .. ", must be a string.")
		assert(typeof(package) == "string" and string.match(package, packagePattern), "Invalid package " .. package)
		table.insert(packageStrings, name .. ' = "' .. package .. '"')
	end
	return packageStrings
end

type Manifest =
	{ status: "ok", url: string, packages: { string }, serverPackages: { string } }
	| { status: "manifest_not_found" }
local function loadManifest(): Manifest
	local source = ServerStorage:FindFirstChild("StudioWallyManifest")
	if source then
		assert(source:IsA("ModuleScript"), "StudioWallyManifest was not a ModuleScript")
		local manifest = require(source:Clone())
		assert(typeof(manifest.studioWallyServer) == "string", "Manifest is missing valid studioWallyServer field")
		if manifest.dependencies then
			error("Dependencies field was renamed to packages, you must rename it in the manifest.")
		end
		assert(typeof(manifest.packages) == "table", "Manifest is missing valid packages field.")
		return {
			status = "ok",
			url = manifest.studioWallyServer,
			packages = makePackageStrings(manifest.packages),
			-- Manifests written before server packages existed won't have this.
			serverPackages = makePackageStrings(manifest.serverPackages or {}),
		}
	else
		return { status = "manifest_not_found" }
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

local destinations: { [string]: Instance } = {
	Packages = ReplicatedStorage,
	ServerPackages = ServerStorage,
}

local pluginVersion = 2

local function installPackages(url: string, packages: { string }, serverPackages: { string })
	local res = HttpService:RequestAsync({
		Method = "POST",
		Url = url,
		Headers = { ["Content-Type"] = "application/json" },
		Body = HttpService:JSONEncode({
			version = pluginVersion,
			packages = packages,
			serverPackages = serverPackages,
		}),
	})
	assert(res.Success, `Request to wally server failed: {res.StatusCode} {res.StatusMessage}: {res.Body}`)

	local serverVersion = tonumber(res.Headers["studio-wally-version"])
	if serverVersion and serverVersion ~= pluginVersion then
		error("This version of Studio Wally is out of date, please update the plugin.")
	end

	local root = SerializationService:DeserializeInstancesAsync(buffer.fromstring(res.Body))[1]
	assert(root, "Server sent back an empty model")

	for name, service in destinations do
		local folder = root:FindFirstChild(name)
		assert(folder, `Server didn't send back a {name} folder`)
		local existing = service:FindFirstChild("Packages")
		if existing then
			existing:Destroy()
		end
		folder.Name = "Packages"
		folder:SetAttribute("StudioWallyManaged", true)
		folder.Parent = service
	end
end

installPackagesButton.Click:Connect(function()
	local manifest = loadManifest()
	if manifest.status ~= "ok" then
		error("Failed to load manifest: " .. manifest.status)
	end
	assert(manifest.status == "ok")

	local nonManagedPackagesWarning = "This place has a Packages folder that wasn't made by studio wally."
		.. " Please delete it yourself to make sure studio wally won't override anything."
	assert(not hasNonManagedPackages(), nonManagedPackagesWarning)

	installPackages(manifest.url, manifest.packages, manifest.serverPackages)
	print("Studio Wally installed packages into ReplicatedStorage and ServerStorage")
end)
