local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(
	ReplicatedStorage
		:WaitForChild("MPS")
		:WaitForChild("Modules")
		:WaitForChild("SongPerformanceConfig")
)

local PerformanceService = require(
	ServerScriptService
		:WaitForChild("MPS")
		:WaitForChild("Modules")
		:WaitForChild("SongPerformanceService")
)

local runningForUser = {}

local function safeUpdate(player)
	if runningForUser[player.UserId] then
		return
	end

	runningForUser[player.UserId] = true

	local ok, success, err = pcall(function()
		return PerformanceService:UpdatePlayer(player)
	end)

	runningForUser[player.UserId] = nil

	if not ok then
		warn(
			"Song performance update crashed for "
				.. player.Name
				.. ": "
				.. tostring(success)
		)
	elseif success == false and err ~= "PLAYER_GONE" then
		warn(
			"Song performance update failed for "
				.. player.Name
				.. ": "
				.. tostring(err)
		)
	end
end

Players.PlayerRemoving:Connect(function(player)
	runningForUser[player.UserId] = nil
end)

task.spawn(function()
	-- Let the existing centralized profile loader initialize first.
	task.wait(2)

	while true do
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(safeUpdate, player)
		end

		task.wait(Config.TickSeconds)
	end
end)

print("MPS song performance server ready")
