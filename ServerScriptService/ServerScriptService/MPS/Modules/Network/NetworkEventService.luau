local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Registry = require(
	ReplicatedStorage
		:WaitForChild("MPS")
		:WaitForChild("Modules")
		:WaitForChild("Network")
		:WaitForChild("NetworkRegistry")
)
local EventSchema = require(
	ReplicatedStorage
		:WaitForChild("MPS")
		:WaitForChild("Modules")
		:WaitForChild("Network")
		:WaitForChild("NetworkEventSchema")
)
local ProfileService = require(
	ServerScriptService
		:WaitForChild("MPS")
		:WaitForChild("Modules")
		:WaitForChild("Network")
		:WaitForChild("PlayerProfileService")
)
local pushRemote = ReplicatedStorage
	:WaitForChild("MPS")
	:WaitForChild("Remotes")
	:WaitForChild("NetworkPush")
local NetworkEventService = {}
local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in pairs(value) do
		copy[deepCopy(key)] = deepCopy(child)
	end
	return copy
end
local function trim(array, maximum)
	while #array > maximum do
		table.remove(array)
	end
end
local function countUnread(notifications)
	local total = 0
	for _, notification in ipairs(notifications) do
		if notification.Read ~= true then
			total += 1
		end
	end
	return total
end
function NetworkEventService:Emit(player, eventType, payload)
	local eventId = HttpService:GenerateGUID(false)
	local event, err = EventSchema.Build(
		eventId,
		eventType,
		payload
	)
	if not event then
		return false, err
	end
	local definition = Registry.GetEventDefinition(eventType)
	local notification = nil
	local success, mutationError = ProfileService:Mutate(player, function(profile)
		table.insert(profile.Network.ActivityFeed, 1, event)
		trim(profile.Network.ActivityFeed, Registry.Limits.MaxActivityFeed)
		if definition.Notify then
			notification = {
				NotificationId = HttpService:GenerateGUID(false),
				EventId = event.EventId,
				Type = event.Type,
				Category = event.Category,
				Title = event.Title,
				Body = event.Body,
				Timestamp = event.Timestamp,
				Priority = event.Priority,
				SourceType = event.SourceType,
				SourceId = event.SourceId,
				Read = false,
			}
			table.insert(profile.Network.Notifications, 1, notification)
			trim(profile.Network.Notifications, Registry.Limits.MaxNotifications)
		end
		profile.Network.UnreadNotifications =
			countUnread(profile.Network.Notifications)
	end)
	if not success then
		return false, mutationError
	end
	if player.Parent then
		pushRemote:FireClient(player, {
			Event = deepCopy(event),
			Notification = deepCopy(notification),
		})
	end
	return true, deepCopy(event)
end
function NetworkEventService:GetFeed(player)
	local profile = ProfileService:Get(player)
	return deepCopy(profile.Network.ActivityFeed)
end
function NetworkEventService:GetNotifications(player)
	local profile = ProfileService:Get(player)
	return deepCopy(profile.Network.Notifications)
end
function NetworkEventService:GetActivity(player)
	local profile = ProfileService:Get(player)
	return {
		Feed = deepCopy(profile.Network.ActivityFeed),
		Notifications = deepCopy(profile.Network.Notifications),
		UnreadNotifications = math.max(
			0,
			math.floor(tonumber(profile.Network.UnreadNotifications) or 0)
		),
	}
end
function NetworkEventService:MarkNotificationRead(player, notificationId)
	if type(notificationId) ~= "string" then
		return false, "BAD_NOTIFICATION_ID", nil
	end
	local found = false
	local unread = 0
	local success, err = ProfileService:Mutate(player, function(profile)
		for _, notification in ipairs(profile.Network.Notifications) do
			if notification.NotificationId == notificationId then
				found = true
				notification.Read = true
				break
			end
		end
		profile.Network.UnreadNotifications =
			countUnread(profile.Network.Notifications)
		unread = profile.Network.UnreadNotifications
	end)
	if not success then
		return false, err, nil
	end
	if not found then
		return false, "NOT_FOUND", unread
	end
	return true, nil, unread
end
function NetworkEventService:MarkAllNotificationsRead(player)
	local unread = 0
	local success, err = ProfileService:Mutate(player, function(profile)
		for _, notification in ipairs(profile.Network.Notifications) do
			notification.Read = true
		end
		profile.Network.UnreadNotifications = 0
		unread = 0
	end)
	return success, err, unread
end
return NetworkEventService
