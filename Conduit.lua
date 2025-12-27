--[[
    ✦ Continuance // Conduit ✦
]]

if _G.ConduitRunning then return end
_G.ConduitRunning = true

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local TeleportService = game:GetService("TeleportService")
local GuiService = game:GetService("GuiService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

local PORT = 7963
local BASE_URL = "http://localhost:" .. PORT .. "/"
local CONDUIT_KEY = "CONTINUANCE_AUTH"

local Conduit = {
    LastCommandId = "",
    PerformanceMode = false
}

local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function base64Decode(data)
    if not data then return "" end
    data = string.gsub(data, '[^'..b..'=]', '')
    return (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r,f='',(b:find(x)-1)
        for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
        return r;
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (#x ~= 8) then return '' end
        local c=0
        for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
        return string.char(c)
    end))
end

local function sendBridge(action, data)
    if not request then return end
    pcall(function()
        request({
            Url = BASE_URL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["Conduit-Auth"] = CONDUIT_KEY
            },
            Body = HttpService:JSONEncode({
                Action = action,
                Data = tostring(data or ""),
                UserId = LocalPlayer.UserId,
                Username = LocalPlayer.Name,
                JobId = game.JobId,
                FPS = math.floor(Stats.WorkspaceResources.FPS:GetValue() or 60),
                Memory = math.floor(Stats:GetTotalMemoryUsageMb())
            })
        })
    end)
end

local Commands = {
    ["kick"] = function() LocalPlayer:Kick("[Conduit] Disconnected by Manager") end,
    ["rejoin"] = function() 
        sendBridge("Status", "Rejoining...")
        if #Players:GetPlayers() <= 1 then
            TeleportService:Teleport(game.PlaceId, LocalPlayer)
        else
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
        end
    end,
    ["performance"] = function(args)
        Conduit.PerformanceMode = (args == "on")
        RunService:Set3dRenderingEnabled(not Conduit.PerformanceMode)
        if Conduit.PerformanceMode then setfpscap(10) else setfpscap(60) end
        sendBridge("Status", "Performance Mode: " .. tostring(args))
    end,
    ["chat"] = function(msg)
        local TextChatService = game:GetService("TextChatService")
        if TextChatService.ChatInputBarConfiguration.TargetTextChannel then
            TextChatService.ChatInputBarConfiguration.TargetTextChannel:SendAsync(msg)
        else
            game:GetService("ReplicatedStorage").DefaultChatSystemChatEvents.SayMessageRequest:FireServer(msg, "All")
        end
    end
}

task.spawn(function()
    print("[Conduit] Polling Service Started.")
    while task.wait(1) do
        local success, response = pcall(function()
            return request({
                Url = BASE_URL .. "?uid=" .. LocalPlayer.UserId,
                Method = "GET",
                Headers = { ["Conduit-Auth"] = CONDUIT_KEY }
            })
        end)

        if success and response.Success then
            local decodeSuccess, data = pcall(HttpService.JSONDecode, HttpService, response.Body)
            
            if decodeSuccess and data and data.command and data.command ~= "idle" then
                if data.id ~= Conduit.LastCommandId then
                    Conduit.LastCommandId = data.id
                    local cmd = tostring(data.command)
                    
                    print("[Conduit] Executing:", cmd)

                    if string.sub(cmd, 1, 8) == "execute:" then
                        local code = base64Decode(string.sub(cmd, 9))
                        local func, err = loadstring(code)
                        if func then 
                            task.spawn(func) 
                        else 
                            sendBridge("Error", "Script Compile Error: " .. tostring(err)) 
                        end
                    else
                        local found = false
                        for name, func in pairs(Commands) do
                            if string.sub(cmd, 1, #name) == name then
                                local args = string.sub(cmd, #name + 2)
                                task.spawn(func, args)
                                found = true
                                break
                            end
                        end
                        if not found then
                            sendBridge("Error", "Unknown Command: " .. cmd)
                        end
                    end
                end
            end
        end
    end
end)

GuiService.ErrorMessageChanged:Connect(function(msg)
    if msg and #msg > 0 then
        sendBridge("Error", "Kicked/Crashed: " .. msg)
    end
end)

sendBridge("Status", "Conduit // Initialized")
print("[Conduit] Active.")
