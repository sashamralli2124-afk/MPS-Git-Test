local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local IntegrityCheck = {}

local REQUIRED_AUDIO = {
	"Kick",
	"Snare",
	"ClosedHat",
	"Clap",
}

function IntegrityCheck.Run()
	local passed = 0
	local failed = 0
	local warnings = 0

	local function pass(label)
		passed += 1
		print("[PASS] " .. label)
	end

	local function fail(label)
		failed += 1
		warn("[FAIL] " .. label)
	end

	local function warning(label)
		warnings += 1
		warn("[WARN] " .. label)
	end

	local function check(condition, label)
		if condition then
			pass(label)
		else
			fail(label)
		end
	end

	print("")
	print("==============================================")
	print("MPS PROJECT INTEGRITY CHECK")
	print("==============================================")

	local sharedMPS = ReplicatedStorage:FindFirstChild("MPS")
	check(sharedMPS ~= nil, "ReplicatedStorage > MPS")

	local modules = sharedMPS and sharedMPS:FindFirstChild("Modules")
	check(modules ~= nil, "ReplicatedStorage > MPS > Modules")

	local remotes = sharedMPS and sharedMPS:FindFirstChild("Remotes")
	check(remotes ~= nil, "ReplicatedStorage > MPS > Remotes")

	check(modules and modules:FindFirstChild("GameConfig") ~= nil, "GameConfig module")
	check(modules and modules:FindFirstChild("SequencerConfig") ~= nil, "SequencerConfig module")
	check(modules and modules:FindFirstChild("SequencerEngine") ~= nil, "SequencerEngine module")
	check(modules and modules:FindFirstChild("ProjectRegistry") ~= nil, "ProjectRegistry module")

	local worldMPS = Workspace:FindFirstChild("MPS")
	check(worldMPS ~= nil, "Workspace > MPS")

	local room = worldMPS and worldMPS:FindFirstChild("StarterBedroom")
	check(room and room:IsA("Model"), "Starter apartment model")

	local monitor = room and room:FindFirstChild("Monitor")
	check(monitor and monitor:IsA("BasePart"), "Music computer monitor")

	local prompt = monitor and monitor:FindFirstChild("UseComputerPrompt")
	check(prompt and prompt:IsA("ProximityPrompt"), "Computer E interaction")

	if monitor then
		check(CollectionService:HasTag(monitor, "MPS_MusicComputer"), "Music computer tag")
	end

	local gui = StarterGui:FindFirstChild("MPS_DAW")
	check(gui and gui:IsA("ScreenGui"), "MPS_DAW ScreenGui")
	check(gui and gui:FindFirstChild("MainFrame") ~= nil, "DAW MainFrame")

	local clientFolder = StarterPlayer
		:FindFirstChild("StarterPlayerScripts")
		and StarterPlayer.StarterPlayerScripts:FindFirstChild("MPS")

	check(clientFolder ~= nil, "StarterPlayerScripts > MPS")

	local controller = clientFolder and clientFolder:FindFirstChild("DAWController")
	check(controller and controller:IsA("LocalScript"), "DAWController LocalScript")

	if controller and controller.Disabled then
		fail("DAWController is enabled")
	else
		pass("DAWController is enabled")
	end

	local serverFolder = ServerScriptService:FindFirstChild("MPS")
	check(serverFolder ~= nil, "ServerScriptService > MPS")
	check(serverFolder and serverFolder:FindFirstChild("ServerMain") ~= nil, "ServerMain")
	check(serverFolder and serverFolder:FindFirstChild("IntegrityCheck") ~= nil, "IntegrityCheck module")

	local audio = SoundService:FindFirstChild("MPSAudio")
	check(audio and audio:IsA("Folder"), "SoundService > MPSAudio")

	if audio then
		for _, name in ipairs(REQUIRED_AUDIO) do
			local sound = audio:FindFirstChild(name)
			check(sound and sound:IsA("Sound"), "Audio sample: " .. name)

			if sound and sound:IsA("Sound") then
				if sound.SoundId == "" then
					fail(name .. " has an assigned SoundId")
				else
					pass(name .. " has an assigned SoundId")
				end
			end
		end
	end

	local taggedComputers = CollectionService:GetTagged("MPS_MusicComputer")
	if #taggedComputers == 1 then
		pass("Exactly 1 tagged music computer")
	elseif #taggedComputers == 0 then
		fail("Exactly 1 tagged music computer")
	else
		warning("Found " .. #taggedComputers .. " tagged music computers. This is allowed later, but Phase 1 expects one.")
	end

	if room then
		local buriedScripts = 0

		for _, descendant in ipairs(room:GetDescendants()) do
			if descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("ModuleScript") then
				buriedScripts += 1
				warning("Script buried inside apartment: " .. descendant:GetFullName())
			end
		end

		if buriedScripts == 0 then
			pass("No scripts buried inside apartment content")
		end
	end

	print("----------------------------------------------")
	print("PASSED: " .. passed)
	print("FAILED: " .. failed)
	print("WARNINGS: " .. warnings)

	if failed == 0 then
		print("PROJECT HEALTH: GOOD")
	else
		warn("PROJECT HEALTH: NEEDS ATTENTION")
	end

	print("==============================================")
	print("")

	return {
		Passed = passed,
		Failed = failed,
		Warnings = warnings,
		Healthy = failed == 0,
	}
end

return IntegrityCheck
