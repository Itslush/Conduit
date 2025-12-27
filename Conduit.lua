if _G.ConduitRunning then return end
_G.ConduitRunning = true

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

local PORT = 7963
local BASE_URL = "http://localhost:" .. PORT .. "/"
local CONDUIT_KEY = "CONTINUANCE_AUTH"

local Conduit = {
    CommandHistory = {},
    LastCommandId = "",
    PerformanceMode = false
}

local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
function base64Decode(data)
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
                Data = tostring(data),
                UserId = LocalPlayer.UserId,
                Username = LocalPlayer.Name,
                JobId = game.JobId,
                FPS = math.floor(1/RunService.RenderStepped:Wait()),
                Memory = math.floor(Stats:GetTotalMemoryUsageMb())
            })
        })
    end)
end

local oldPrint; oldPrint = hookfunction(print, function(...)
    local args = {...}
    sendBridge("Log", table.concat(args, " "))
    return oldPrint(...)
end)

local Commands = {
    ["kick"] = function() LocalPlayer:Kick("[Conduit] Disconnected by Manager") end,
    ["rejoin"] = function() game:GetService("TeleportService"):Teleport(game.PlaceId, LocalPlayer) end,
    ["performance"] = function(state)
        Conduit.PerformanceMode = (state == "on")
        RunService:Set3dRenderingEnabled(not Conduit.PerformanceMode)
        if Conduit.PerformanceMode then setfpscap(10) else setfpscap(60) end
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
    while task.wait(1) do
        local success, response = pcall(function()
            return request({
                Url = BASE_URL .. "?uid=" .. LocalPlayer.UserId,
                Method = "GET",
                Headers = { ["Conduit-Auth"] = CONDUIT_KEY }
            })
        end)

        if success and response.Success then
            local data = HttpService:JSONDecode(response.Body)
            if data.id and data.id ~= Conduit.LastCommandId then
                Conduit.LastCommandId = data.id
                local cmd = data.command
                
                if cmd:sub(1,8) == "execute:" then
                    local code = base64Decode(cmd:sub(9))
                    local func, err = loadstring(code)
                    if func then task.spawn(func) else sendBridge("Error", err) end
                else
                    for name, func in pairs(Commands) do
                        if cmd:sub(1, #name) == name then
                            local args = cmd:sub(#name + 2)
                            task.spawn(func, args)
                        end
                    end
                end
            end
        end
    end
end)

task.spawn(function()
    while task.wait(5) do
        sendBridge("Heartbeat", "Active")
    end
end)

sendBridge("Status", "Conduit Initialized")
