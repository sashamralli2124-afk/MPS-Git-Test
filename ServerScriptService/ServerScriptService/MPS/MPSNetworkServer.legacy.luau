local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local request = ReplicatedStorage
	:WaitForChild("MPS")
	:WaitForChild("Remotes")
	:WaitForChild("NetworkRequest")
local ProfileService = require(
	ServerScriptService
		:WaitForChild("MPS")
		:WaitForChild("Modules")
		:WaitForChild("Network")
		:WaitForChild("PlayerProfileService")
)
local EventService = require(
	ServerScriptService
		:WaitForChild("MPS")
		:WaitForChild("Modules")
		:WaitForChild("Network")
		:WaitForChild("NetworkEventService")
)
local OpportunityService = require(
	ServerScriptService
		:WaitForChild("MPS")
		:WaitForChild("Modules")
		:WaitForChild("Network")
		:WaitForChild("OpportunityService")
)
local lastRequestAt = {}
local function allowedRequest(player)
	local now = os.clock()
	local last = lastRequestAt[player.UserId] or 0
	if now - last < 0.08 then
		return false
	end
	lastRequestAt[player.UserId] = now
	return true
end
request.OnServerInvoke = function(player, action, payload)
	if not allowedRequest(player) then
		return {
			Success = false,
			Error = "RATE_LIMITED",
		}
	end
	if action == "GetSnapshot" then
		return {
			Success = true,
			Snapshot = ProfileService:GetOwnSnapshot(player),
			PersistenceMode = ProfileService:GetPersistenceMode(),
		}
	end
	if action == "GetActivity" then
		local activity = EventService:GetActivity(player)
		return {
			Success = true,
			Feed = activity.Feed,
			Notifications = activity.Notifications,
			UnreadNotifications = activity.UnreadNotifications,
			PersistenceMode = ProfileService:GetPersistenceMode(),
		}
	end
	if action == "GetFeed" then
		return {
			Success = true,
			Feed = EventService:GetFeed(player),
		}
	end
	if action == "GetNotifications" then
		local activity = EventService:GetActivity(player)
		return {
			Success = true,
			Notifications = activity.Notifications,
			UnreadNotifications = activity.UnreadNotifications,
		}
	end
	if action == "MarkNotificationRead" then
		local success, err, unread =
			EventService:MarkNotificationRead(player, payload)
		return {
			Success = success,
			Error = err,
			UnreadNotifications = unread,
		}
	end
	if action == "MarkAllNotificationsRead" then
		local success, err, unread =
			EventService:MarkAllNotificationsRead(player)
		return {
			Success = success,
			Error = err,
			UnreadNotifications = unread or 0,
		}
	end
	if action == "GetOpportunities" then
		return {
			Success = true,
			Opportunities = OpportunityService:List(player),
		}
	end
	return {
		Success = false,
		Error = "UNKNOWN_ACTION",
	}
end
local function loadPlayer(player)
	local success, err = pcall(function()
		ProfileService:LoadPlayer(player)
	end)
	if success then
		print(
			"MPS profile ready for "
				.. player.Name
				.. " ["
				.. ProfileService:GetPersistenceMode()
				.. "]"
		)
	else
		warn(
			"MPS profile failed for "
				.. player.Name
				.. ": "
				.. tostring(err)
		)
	end
end
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(loadPlayer, player)
end
Players.PlayerAdded:Connect(loadPlayer)
Players.PlayerRemoving:Connect(function(player)
	lastRequestAt[player.UserId] = nil
	ProfileService:ReleasePlayer(player)
end)
task.spawn(function()
	while true do
		task.wait(180)
		ProfileService:SaveDirtyPlayers()
	end
end)
game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		ProfileService:SavePlayer(player, true)
	end
end)
print("==============================================")
print("MPS NETWORK BACKBONE V2 READY")
print("PlayerProfile ........ READY")
print("Activity Events ...... READY")
print("Notifications ........ READY")
print("GetActivity .......... READY / ONE REQUEST")
print("Rewards .............. READY")
print("Opportunities ........ READY")
print("Song Integration ..... READY")
print("Client Reward Writes . BLOCKED")
print("==============================================")
