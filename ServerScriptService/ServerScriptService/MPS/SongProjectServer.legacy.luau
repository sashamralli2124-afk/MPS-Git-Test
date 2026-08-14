local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local request = ReplicatedStorage
	:WaitForChild("MPS")
	:WaitForChild("Remotes")
	:WaitForChild("SongProjectRequest")
local service = require(
	ServerScriptService
		:WaitForChild("MPS")
		:WaitForChild("Modules")
		:WaitForChild("SongProjectService")
)
request.OnServerInvoke = function(player, action, payload)
	if action == "List" then
		return {
			Success = true,
			Projects = service:List(player),
			PersistenceMode = service:GetPersistenceMode(),
		}
	end
	if action == "Load" then
		local project = service:Load(player, payload)
		if not project then
			return {
				Success = false,
				Error = "PROJECT_NOT_FOUND",
			}
		end
		return {
			Success = true,
			Project = project,
			PersistenceMode = service:GetPersistenceMode(),
		}
	end
	if action == "Save" then
		return service:SaveProject(player, payload, "Draft")
	end
	if action == "Finish" then
		return service:SaveProject(player, payload, "Finished")
	end
	if action == "Release" then
		return service:ReleaseProject(player, payload)
	end
	return {
		Success = false,
		Error = "UNKNOWN_ACTION",
	}
end
print("MPS SongProjectServer ready - projects + frozen releases")
