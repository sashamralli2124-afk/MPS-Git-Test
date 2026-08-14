local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(
	ReplicatedStorage.MPS.Modules.GameConfig
)

print("MPS server started")
print("Default BPM:", GameConfig.DefaultBPM)