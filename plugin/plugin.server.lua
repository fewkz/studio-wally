--!strict
local ServerStorage = game:GetService("ServerStorage")

type RojoApi = {
	ConnectAsync: (self: RojoApi, host: string?, port: number?) -> (),
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
installDependenciesButton.Enabled = false

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

installDependenciesButton.Click:Connect(function()
	local api = getRojoAPI()
	assert(api, "Rojo Headless API not found. Make sure you have a version of the Rojo plugin with it available.")
	if not api.Connected then
		api:ConnectAsync("fewkz.com", 5000)
	end
end)
