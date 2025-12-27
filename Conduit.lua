local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local TeleportService = game:GetService("TeleportService")
local GuiService = game:GetService("GuiService")

local PORT = 7963
local URL = "http://localhost:" .. PORT .. "/"

print("[Conduit] Initializing")

local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

local function base64Decode(data)
    data = string.gsub(data, '[^'..b..'=]', '')
    return (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r, f = '', (b:find(x) - 1)
        for i = 6, 1, -1 do r = r .. (f % 2^i - f % 2^(i - 1) > 0 and '1' or '0') end
        return r;
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (#x ~= 8) then return '' end
        local c = 0
        for i = 1, 8 do c = c + (x:sub(i, i) == '1' and 2^(8 - i) or 0) end
        return string.char(c)
    end))
end

local function sendStatus(action, data)
    if not request then return end
    pcall(function()
        request({
            Url = URL, 
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode({ Action = action, Data = data, UserId = LocalPlayer.UserId })
        })
    end)
end

GuiService.ErrorMessageChanged:Connect(function(msg)
    if msg and msg ~= "" then
        warn("[Conduit] Error Detected:", msg)
        sendStatus("Error", msg)

        task.wait(2)
        
        local success, result = pcall(function() 
            return game:HttpGet("https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Desc&limit=10")
        end)

        if success then
            local servers = HttpService:JSONDecode(result)
            if servers and servers.data then
                for _, s in ipairs(servers.data) do
                    if s.id ~= game.JobId and s.playing < s.maxPlayers then
                        TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, LocalPlayer)
                        return
                    end
                end
            end
        end
        
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end
end)

local function pollCommands()
    while task.wait(2) do
        pcall(function()
            if not request then return end
            local response = request({ Url = URL, Method = "GET" })
            if response.Success then
                local data = HttpService:JSONDecode(response.Body)
                local cmd = data.command
                if cmd and cmd ~= "idle" then
                    print("[Conduit] Cmd:", cmd)
                    if cmd == "kick" then 
                        LocalPlayer:Kick("Conduit Disconnect")
                    elseif cmd == "rejoin" then 
                        TeleportService:Teleport(game.PlaceId, LocalPlayer)
                    elseif string.sub(cmd, 1, 5) == "chat:" then
                        local msg = string.sub(cmd, 6)
              
                        if game:GetService("ReplicatedStorage"):FindFirstChild("DefaultChatSystemChatEvents") then
                            game:GetService("ReplicatedStorage").DefaultChatSystemChatEvents.SayMessageRequest:FireServer(msg, "All")
                        elseif game:GetService("TextChatService").ChatInputBarConfiguration.TargetTextChannel then
                             game:GetService("TextChatService").ChatInputBarConfiguration.TargetTextChannel:SendAsync(msg)
                        end
                    elseif string.sub(cmd, 1, 8) == "execute:" then
                         local func = loadstring(base64Decode(string.sub(cmd, 9)))
                         if func then task.spawn(func) end
                    end
                end
            end
        end)
    end
end

if not game:IsLoaded() then game.Loaded:Wait() end

sendStatus("Status", "Game Loaded")
sendStatus("JobId", game.JobId)

task.spawn(pollCommands)
print("[Conduit] Active.")
