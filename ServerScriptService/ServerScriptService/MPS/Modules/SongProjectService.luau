local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Schema = require(
	ReplicatedStorage
		:WaitForChild("MPS")
		:WaitForChild("Modules")
		:WaitForChild("SongProjectSchema")
)
local ReleaseSchema = require(
	ReplicatedStorage
		:WaitForChild("MPS")
		:WaitForChild("Modules")
		:WaitForChild("SongReleaseSchema")
)
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
local SongProjectService = {}
local function findProject(projects, projectId)
	for index, project in ipairs(projects) do
		if project.ProjectId == projectId then
			return project, index
		end
	end
	return nil, nil
end
local function findReleaseForProject(releases, projectId)
	for index, release in ipairs(releases) do
		local sourceProjectId = release.SourceProjectId or release.ProjectId
		if sourceProjectId == projectId then
			return release, index
		end
	end
	return nil, nil
end
local function cloneForClient(project)
	return Schema.ToClient(project)
end
local function cloneReleaseForClient(release)
	return ReleaseSchema.ToClient(release)
end
local function deepEqual(a, b)
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	for key, value in pairs(a) do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key, value in pairs(b) do
		if not deepEqual(value, a[key]) then
			return false
		end
	end
	return true
end
local function countActiveSteps(project)
	local total = 0
	if type(project.Tracks) ~= "table" then
		return total
	end
	for _, steps in pairs(project.Tracks) do
		if type(steps) == "table" then
			total += #steps
		end
	end
	return total
end
function SongProjectService:GetPersistenceMode()
	return ProfileService:GetPersistenceMode()
end
function SongProjectService:LoadPlayer(player)
	local profile = ProfileService:Get(player)
	return {
		Version = 1,
		Projects = profile.Music.Projects,
		Releases = profile.Music.Releases,
	}
end
function SongProjectService:SavePlayer(player)
	return ProfileService:SavePlayer(player, false)
end
function SongProjectService:List(player)
	local profile = ProfileService:Get(player)
	local result = {}
	for _, project in ipairs(profile.Music.Projects) do
		table.insert(result, cloneForClient(project))
	end
	table.sort(result, function(a, b)
		return (a.UpdatedAt or 0) > (b.UpdatedAt or 0)
	end)
	return result
end
function SongProjectService:ListReleases(player)
	local profile = ProfileService:Get(player)
	local result = {}
	for _, release in ipairs(profile.Music.Releases) do
		local cleaned = cloneReleaseForClient(release)
		if cleaned then
			table.insert(result, cleaned)
		end
	end
	table.sort(result, function(a, b)
		return (a.ReleasedAt or 0) > (b.ReleasedAt or 0)
	end)
	return result
end
function SongProjectService:Load(player, projectId)
	if type(projectId) ~= "string" then
		return nil
	end
	local profile = ProfileService:Get(player)
	local project = findProject(profile.Music.Projects, projectId)
	return cloneForClient(project)
end
function SongProjectService:SaveProject(player, payload, requestedStatus)
	local cleaned = Schema.CleanProjectPayload(payload)
	local desiredStatus = requestedStatus == "Finished" and "Finished" or "Draft"
	local now = os.time()
	local outputProject = nil
	local shouldEmit = false
	local success, err = ProfileService:Mutate(player, function(profile)
		local projects = profile.Music.Projects
		local project = nil
		if cleaned.ProjectId then
			project = findProject(projects, cleaned.ProjectId)
		end
		if not project then
			project = {
				Version = Schema.Version,
				ProjectId = HttpService:GenerateGUID(false),
				CreatedAt = now,
			}
			table.insert(projects, 1, project)
			shouldEmit = true
		else
			shouldEmit =
				tostring(project.Name or "") ~= tostring(cleaned.Name or "")
					or tonumber(project.BPM) ~= tonumber(cleaned.BPM)
					or not deepEqual(project.Tracks or {}, cleaned.Tracks or {})
					or not deepEqual(project.DAW or {}, cleaned.DAW or {})
					or tostring(project.Status or "Draft") ~= desiredStatus
		end
		project.Version = Schema.Version
		project.Name = cleaned.Name
		project.BPM = cleaned.BPM
		project.Tracks = cleaned.Tracks
		project.DAW = cleaned.DAW
		project.Status = desiredStatus
		project.UpdatedAt = now
		if #projects > Schema.MaxProjects then
			table.sort(projects, function(a, b)
				return (a.UpdatedAt or 0) > (b.UpdatedAt or 0)
			end)
			while #projects > Schema.MaxProjects do
				table.remove(projects)
			end
		end
		outputProject = cloneForClient(project)
	end)
	if not success then
		return {
			Success = false,
			Error = tostring(err),
		}
	end
	local eventEmitted = false
	local eventError = nil
	if shouldEmit and outputProject then
		local eventType = desiredStatus == "Finished"
			and "Music.ProjectFinished"
			or "Music.ProjectSaved"
		local title = desiredStatus == "Finished"
			and ("Finished: " .. tostring(outputProject.Name or "Untitled Beat"))
			or ("Saved: " .. tostring(outputProject.Name or "Untitled Beat"))
		local body = desiredStatus == "Finished"
			and ("Ready to release // BPM " .. tostring(outputProject.BPM or 120))
			or ("Draft saved // BPM " .. tostring(outputProject.BPM or 120))
		local emitted, emittedResult = EventService:Emit(player, eventType, {
			Title = title,
			Body = body,
			SourceType = "SongProject",
			SourceId = tostring(outputProject.ProjectId or ""),
			Data = {
				ProjectId = outputProject.ProjectId,
				Name = outputProject.Name,
				BPM = outputProject.BPM,
				Status = outputProject.Status,
				ActiveSteps = countActiveSteps(outputProject),
			},
		})
		eventEmitted = emitted == true
		if not emitted then
			eventError = tostring(emittedResult)
			warn(
				"Song project saved but activity event failed: "
					.. tostring(emittedResult)
			)
		end
	end
	local persisted, modeOrError = ProfileService:SavePlayer(player, false)
	return {
		Success = true,
		Project = outputProject,
		Persisted = persisted,
		PersistenceMode = self:GetPersistenceMode(),
		SaveMessage = modeOrError,
		EventEmitted = eventEmitted,
		EventError = eventError,
	}
end
function SongProjectService:ReleaseProject(player, projectId)
	if type(projectId) ~= "string" or projectId == "" then
		return {
			Success = false,
			Error = "BAD_PROJECT_ID",
		}
	end
	-- Fast validation before mutating the profile.
	local profile = ProfileService:Get(player)
	local project = findProject(profile.Music.Projects, projectId)
	if not project then
		return {
			Success = false,
			Error = "PROJECT_NOT_FOUND",
		}
	end
	if tostring(project.Status or "") ~= "Finished" then
		return {
			Success = false,
			Error = "PROJECT_NOT_FINISHED",
		}
	end
	local existing = findReleaseForProject(profile.Music.Releases, projectId)
	if existing then
		return {
			Success = true,
			AlreadyReleased = true,
			Release = cloneReleaseForClient(existing),
			PersistenceMode = self:GetPersistenceMode(),
		}
	end
	local now = os.time()
	local outputRelease = nil
	local releaseError = nil
	local alreadyReleased = false
	local success, mutationError = ProfileService:Mutate(player, function(currentProfile)
		local currentProject = findProject(currentProfile.Music.Projects, projectId)
		if not currentProject then
			releaseError = "PROJECT_NOT_FOUND"
			return
		end
		if tostring(currentProject.Status or "") ~= "Finished" then
			releaseError = "PROJECT_NOT_FINISHED"
			return
		end
		local duplicate = findReleaseForProject(currentProfile.Music.Releases, projectId)
		if duplicate then
			alreadyReleased = true
			outputRelease = cloneReleaseForClient(duplicate)
			return
		end
		local release, buildError = ReleaseSchema.FromProject(
			currentProject,
			HttpService:GenerateGUID(false),
			now
		)
		if not release then
			releaseError = tostring(buildError or "RELEASE_BUILD_FAILED")
			return
		end
		table.insert(currentProfile.Music.Releases, 1, release)
		while #currentProfile.Music.Releases > ReleaseSchema.MaxReleases do
			table.remove(currentProfile.Music.Releases)
		end
		outputRelease = cloneReleaseForClient(release)
	end)
	if not success then
		return {
			Success = false,
			Error = tostring(mutationError),
		}
	end
	if releaseError then
		return {
			Success = false,
			Error = releaseError,
		}
	end
	if not outputRelease then
		return {
			Success = false,
			Error = "RELEASE_NOT_CREATED",
		}
	end
	if alreadyReleased then
		return {
			Success = true,
			AlreadyReleased = true,
			Release = outputRelease,
			PersistenceMode = self:GetPersistenceMode(),
		}
	end
	local emitted, emittedResult = EventService:Emit(player, "Music.Released", {
		Title = "Released: " .. tostring(outputRelease.Name or "Untitled Beat"),
		Body = "Your song is live // BPM " .. tostring(outputRelease.BPM or 120),
		SourceType = "SongRelease",
		SourceId = tostring(outputRelease.ReleaseId or ""),
		Data = {
			ReleaseId = outputRelease.ReleaseId,
			ProjectId = outputRelease.SourceProjectId,
			Name = outputRelease.Name,
			BPM = outputRelease.BPM,
			Status = "Released",
			ActiveSteps = countActiveSteps(outputRelease),
		},
	})
	local eventEmitted = emitted == true
	local eventError = nil
	if not emitted then
		eventError = tostring(emittedResult)
		warn("Song released but Music.Released event failed: " .. tostring(emittedResult))
	end
	-- Save after event emission so the frozen release + real activity
	-- are persisted together whenever possible.
	local persisted, modeOrError = ProfileService:SavePlayer(player, false)
	return {
		Success = true,
		AlreadyReleased = false,
		Release = outputRelease,
		Persisted = persisted,
		PersistenceMode = self:GetPersistenceMode(),
		SaveMessage = modeOrError,
		EventEmitted = eventEmitted,
		EventError = eventError,
	}
end
-- Kept for compatibility. Central lifecycle is MPSNetworkServer-owned.
function SongProjectService:ReleasePlayer(player)
	return ProfileService:SavePlayer(player, false)
end
return SongProjectService
