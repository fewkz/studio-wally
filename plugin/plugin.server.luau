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
	server = "https://studio-wally.fewkz.com",
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

local function findStudioWallyLock(): StringValue?
	local lock = ServerStorage:FindFirstChild("StudioWallyLock")
	if lock then 
		if lock:IsA("StringValue") then
			return lock
		else
			warn(`StudioWallyLock was not a StringValue, ignoring`)
			return nil
		end
	else
		return nil
	end
end

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

type Manifest = { url: string, packages: { string }, serverPackages: { string } }
local function loadManifest(): ({ status: "ok" } & Manifest) | { status: "manifest_not_found" }
	local source = ServerStorage:FindFirstChild("StudioWallyManifest")
	if source then
		assert(source:IsA("ModuleScript"), "StudioWallyManifest was not a ModuleScript")
		local manifest = require(source:Clone())
		local server = manifest.server
		if manifest.studioWallyServer then
			warn("The studioWallyServer field was renamed to server, you should rename it in the manifest.")
			server = server or manifest.studioWallyServer
		end
		assert(typeof(server) == "string", "Manifest is missing valid server field")
		if manifest.dependencies then
			error("The dependencies field was renamed to packages, you must rename it in the manifest.")
		end
		assert(typeof(manifest.packages) == "table", "Manifest is missing valid packages field.")
		return {
			status = "ok",
			url = server,
			packages = makePackageStrings(manifest.packages),
			-- Manifests written before server packages existed won't have this.
			serverPackages = makePackageStrings(manifest.serverPackages or {})
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

local function installPackages(manifest: Manifest, lock: StringValue?)
	local res = HttpService:RequestAsync({
		Method = "POST",
		Url = manifest.url,
		Headers = { ["Content-Type"] = "application/json" },
		Body = HttpService:JSONEncode({
			version = pluginVersion,
			packages = manifest.packages,
			serverPackages = manifest.serverPackages,
			lock = if lock then lock.Value else nil,
		}),
	})
	assert(res.Success, `Request to wally server failed: {res.StatusCode} {res.StatusMessage}: {res.Body}`)

	local serverVersion = tonumber(res.Headers["studio-wally-version"])
	if serverVersion and serverVersion ~= pluginVersion then
		error("This version of Studio Wally is out of date, please update the plugin.")
	end

	local warning = res.Headers["studio-wally-warning"]
	if warning then
		warn(`Studio Wally: {warning}`)
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

	if lock then
		local newLock = root:FindFirstChild("StudioWallyLock")
		if newLock and newLock:IsA("StringValue") then
			lock.Value = newLock.Value
		end
	end
end

local function install()
	local manifest = loadManifest()
	if manifest.status ~= "ok" then
		error("Failed to load manifest: " .. manifest.status)
	end
	assert(manifest.status == "ok")

	local nonManagedPackagesWarning = "This place has a Packages folder that wasn't made by studio wally."
		.. " Please delete it yourself to make sure studio wally won't override anything."
	assert(not hasNonManagedPackages(), nonManagedPackagesWarning)

	local lock = findStudioWallyLock()

	if #manifest.packages == 0 and #manifest.serverPackages == 0 then
		for _, service in destinations do
			local existing = service:FindFirstChild("Packages")
			if existing then
				existing:Destroy()
			end
		end
		if lock then
			lock.Value = ""
		end
		print("Studio Wally: Manifest has no packages to install, cleared all existing packages.")
		return
	end

	installPackages(manifest, lock)
	print(`Studio Wally: Installed {#manifest.packages} packages into ReplicatedStorage and {#manifest.serverPackages} packages into ServerStorage`)
end

local installing = false
installPackagesButton.Click:Connect(function()
	if installing then
		return
	end
	installing = true
	installPackagesButton:SetActive(true)
	local ok, err = pcall(install)
	installPackagesButton:SetActive(false)
	installing = false
	if not ok then
		error(err, 0)
	end
end)
