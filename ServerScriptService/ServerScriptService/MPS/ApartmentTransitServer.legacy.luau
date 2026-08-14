local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local worldMPS = Workspace:WaitForChild("MPS")
local complex = worldMPS:WaitForChild("ApartmentComplex")
local navigation = complex:WaitForChild("Navigation")

local lobbyPanel = navigation:WaitForChild("LobbyElevatorCallPanel")
local apartmentPanel = navigation:WaitForChild("ApartmentElevatorCallPanel")

local goHomePrompt = lobbyPanel:WaitForChild("GoHomePrompt")
local goLobbyPrompt = apartmentPanel:WaitForChild("ReturnToLobbyPrompt")

local homeArrival = navigation:WaitForChild("ApartmentArrival")
local lobbyArrival = navigation:WaitForChild("LobbyArrival")

local debounce = {}

local function teleportPlayer(player, target)
	if not player or not player.Parent then
		return
	end

	local now = os.clock()
	local last = debounce[player.UserId] or 0

	if now - last < 0.8 then
		return
	end

	debounce[player.UserId] = now

	local character = player.Character

	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end

	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	character:PivotTo(
		target.CFrame * CFrame.new(0, 2.5, 0)
	)
end

goHomePrompt.Triggered:Connect(function(player)
	teleportPlayer(player, homeArrival)
end)

goLobbyPrompt.Triggered:Connect(function(player)
	teleportPlayer(player, lobbyArrival)
end)

Players.PlayerRemoving:Connect(function(player)
	debounce[player.UserId] = nil
end)

print("MPS apartment transit ready")
