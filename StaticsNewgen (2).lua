-- StaticsNewgen.client.luau
-- Place in StarterPlayer > StarterPlayerScripts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local VRService = game:GetService("VRService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local playerScripts = player:WaitForChild("PlayerScripts")
local camera = Workspace.CurrentCamera
local originalFOV = camera and camera.FieldOfView or 70
local isVR = VRService.VREnabled
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not isVR
local device = isVR and "VR" or (isMobile and "Mobile" or "PC")

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if Workspace.CurrentCamera then
		camera = Workspace.CurrentCamera
		originalFOV = camera.FieldOfView
	end
end)

local remoteFolder = ReplicatedStorage:FindFirstChild("StaticsNewgenRemotes")
	or ReplicatedStorage:WaitForChild("StaticsNewgenRemotes", 8)
local Remotes = {
	Hello = remoteFolder and remoteFolder:FindFirstChild("Hello"),
	RoleSync = remoteFolder and remoteFolder:FindFirstChild("RoleSync"),
	Reset = remoteFolder and remoteFolder:FindFirstChild("ResetCharacter"),
	Hop = remoteFolder and remoteFolder:FindFirstChild("ServerHop"),
	Status = remoteFolder and remoteFolder:FindFirstChild("ActionStatus"),
	VerifyVR = remoteFolder and remoteFolder:FindFirstChild("VerifyVRAimCode"),
	Preferences = remoteFolder and remoteFolder:FindFirstChild("Preferences"),
}
if Remotes.Hello then
	Remotes.Hello:FireServer({ vr = isVR, mobile = isMobile, device = device })
end

local DEFAULTS = {
	ActiveProfile = "Universal",
	Theme = "DarkDock",
	LayoutStyle = "Newgen",
	AimEnabled = false,
	StickyAim = true,
	WallCheck = true,
	TeamCheck = true,
	AimStrength = 0.35,
	AimRadius = 210,
	Prediction = true,
	PredictionTime = 0.08,
	MaxAimDistance = 650,
	CameraAssist = true,
	CameraFOVEnabled = false,
	CameraFOV = 78,
	ShowFOVCircle = true,
	FOVCircleOpacity = 0.75,
	FOVCircleThickness = 1.5,
	FOVCircleHue = 0.75,
	ESPEnabled = false,
	HighlightESP = true,
	NameESP = true,
	DistanceESP = true,
	RoleESP = true,
	VRESP = true,
	SkeletonESP = false,
	BoxESP = false,
	TracerESP = false,
	HealthESP = true,
	ESPTeamCheck = false,
	ThroughWalls = true,
	ESPMaxDistance = 850,
	ESPTextSize = isVR and 18 or 14,
	ESPFill = 0.28,
	EnemyColorHue = 0.98,
	TeammateColorHue = 0.48,
	PerformanceMode = isMobile and "Balanced" or "Off",
	CustomBackground = false,
	BackgroundHue = 0.75,
	BackgroundSaturation = 0.82,
	BackgroundValue = 0.85,
	BackgroundIntensity = 0.65,
	HitPart = "Body",
}
local Config = table.clone(DEFAULTS)
if Remotes.Preferences and Remotes.Preferences:IsA("RemoteFunction") then
	local ok, saved = pcall(function()
		return Remotes.Preferences:InvokeServer("load")
	end)
	if ok and typeof(saved) == "table" then
		for key in pairs(DEFAULTS) do
			if saved[key] ~= nil then Config[key] = saved[key] end
		end
	end
end
-- Standard right-click assist never targets through geometry. This is enforced
-- after loading so an older saved preference cannot turn line-of-sight off.
Config.WallCheck = true

-- VR settings are intentionally session-only and always start off.
local VRConfig = {
	Enabled = false,
	Sticky = false,
	WallCheck = false,
	TeamCheck = false,
	Strength = 0.18,
	Cone = 15,
	MaxDistance = 500,
}

local State = {
	menuOpen = false,
	aimHeld = false,
	target = nil,
	weaponTarget = nil,
	lockedParts = {},
	lastTargetSeen = 0,
	roles = {},
	visuals = {},
	connections = {},
	profileChosen = false,
	dirty = false,
	vrUnlocked = player:GetAttribute("VRAimAuthorized") == true,
	sessionStarted = os.clock(),
}
local UI = { pages = {}, nav = {}, refreshers = {}, bindings = {} }

local Themes = {
	DarkDock = { bg = Color3.fromRGB(10,10,13), panel = Color3.fromRGB(24,24,29), row = Color3.fromRGB(40,40,49), accent = Color3.fromRGB(139,92,246), accent2 = Color3.fromRGB(34,211,238), text = Color3.fromRGB(244,244,247), muted = Color3.fromRGB(148,150,166) },
	Skeet = { bg = Color3.fromRGB(17,15,18), panel = Color3.fromRGB(25,23,27), row = Color3.fromRGB(34,31,35), accent = Color3.fromRGB(112,170,54), accent2 = Color3.fromRGB(157,206,76), text = Color3.fromRGB(235,233,237), muted = Color3.fromRGB(136,132,141) },
	Emerald = { bg = Color3.fromRGB(15,18,18), panel = Color3.fromRGB(29,33,32), row = Color3.fromRGB(43,48,46), accent = Color3.fromRGB(52,211,153), accent2 = Color3.fromRGB(92,224,180), text = Color3.fromRGB(242,244,242), muted = Color3.fromRGB(142,150,146) },
}
local Theme = Themes[Config.Theme] or Themes.DarkDock

local function corner(parent, radius)
	local object = Instance.new("UICorner")
	object.CornerRadius = UDim.new(0, radius)
	object.Parent = parent
end
local function outline(parent, color, transparency, thickness)
	local object = Instance.new("UIStroke")
	object.Color = color
	object.Transparency = transparency or 0
	object.Thickness = thickness or 1
	object.Parent = parent
	return object
end
local function bindTheme(object, property, role)
	table.insert(UI.bindings, { object = object, property = property, role = role })
end
local function panel(parent, size, position, role)
	local object = Instance.new("Frame")
	object.Size = size
	object.Position = position or UDim2.new()
	object.BackgroundColor3 = Theme[role or "panel"]
	object.BorderSizePixel = 0
	object.Parent = parent
	corner(object, 12)
	local border = outline(object, Theme[role == "accent" and "accent2" or "row"], .68, 1)
	bindTheme(border, "Color", role == "accent" and "accent2" or "row")
	bindTheme(object, "BackgroundColor3", role or "panel")
	return object
end
local function label(parent, value, size, position, font, role, textSize)
	local object = Instance.new("TextLabel")
	object.BackgroundTransparency = 1
	object.Size = size
	object.Position = position or UDim2.new()
	object.Font = font or Enum.Font.Gotham
	object.Text = value
	object.TextColor3 = Theme[role or "text"]
	object.TextSize = textSize or 13
	object.TextXAlignment = Enum.TextXAlignment.Left
	object.Parent = parent
	bindTheme(object, "TextColor3", role or "text")
	return object
end
local function button(parent, value, size, position, role)
	local object = Instance.new("TextButton")
	object.Size = size
	object.Position = position or UDim2.new()
	object.BackgroundColor3 = Theme[role or "row"]
	object.BorderSizePixel = 0
	object.AutoButtonColor = false
	object.Font = Enum.Font.GothamBold
	object.Text = value
	object.TextColor3 = Theme.text
	object.TextSize = 11
	object.Parent = parent
	corner(object, 9)
	bindTheme(object, "BackgroundColor3", role or "row")
	bindTheme(object, "TextColor3", "text")
	object.MouseEnter:Connect(function()
		TweenService:Create(object, TweenInfo.new(.12), { BackgroundTransparency = .12 }):Play()
	end)
	object.MouseLeave:Connect(function()
		TweenService:Create(object, TweenInfo.new(.12), { BackgroundTransparency = 0 }):Play()
	end)
	return object
end
local function markDirty() State.dirty = true end

local function setAvatar(imageLabel, userId)
	task.spawn(function()
		local ok, image = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
		end)
		if ok and imageLabel.Parent then imageLabel.Image = image end
	end)
end

local function formatDuration(seconds)
	seconds = math.max(math.floor(seconds), 0)
	return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function shadow(parent, transparency)
	local image = Instance.new("ImageLabel")
	image.Name = "Shadow"
	image.BackgroundTransparency = 1
	image.Image = "rbxassetid://1316045217"
	image.ImageColor3 = Color3.new()
	image.ImageTransparency = transparency or .45
	image.ScaleType = Enum.ScaleType.Slice
	image.SliceCenter = Rect.new(10, 10, 118, 118)
	image.Size = UDim2.new(1, 34, 1, 34)
	image.Position = UDim2.fromOffset(-17, -17)
	image.ZIndex = math.max(parent.ZIndex - 1, 0)
	image.Parent = parent
	return image
end

local function pageHeader(page, titleText, subtitleText, accentRole)
	local accent = Theme[accentRole or "accent"]
	local line = Instance.new("Frame")
	line.Size = UDim2.fromOffset(4, 44)
	line.Position = UDim2.fromOffset(14, 15)
	line.BackgroundColor3 = accent
	line.BorderSizePixel = 0
	line.Parent = page
	corner(line, 2)
	local titleLabel = label(page, titleText, UDim2.new(1, -44, 0, 28), UDim2.fromOffset(28, 12), Enum.Font.GothamBlack, "text", 22)
	local subtitleLabel = label(page, subtitleText, UDim2.new(1, -44, 0, 21), UDim2.fromOffset(28, 40), Enum.Font.Gotham, "muted", 10)
	subtitleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	return titleLabel, subtitleLabel
end

local oldGui = playerGui:FindFirstChild("StaticsNewgenUI")
if oldGui then oldGui:Destroy() end
local gui = Instance.new("ScreenGui")
gui.Name = "StaticsNewgenUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 150
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local loading = Instance.new("CanvasGroup")
loading.Name = "StaticsLoader"
loading.Size = UDim2.fromScale(1,1)
loading.BackgroundColor3 = Color3.fromRGB(70,46,135)
loading.BorderSizePixel = 0
loading.Parent = gui
local loadingGradient = Instance.new("UIGradient")
loadingGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(136, 83, 235)),
	ColorSequenceKeypoint.new(.46, Color3.fromRGB(72, 56, 148)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(24, 139, 164)),
})
loadingGradient.Rotation = 25
loadingGradient.Parent = loading

local loaderCard = Instance.new("CanvasGroup")
loaderCard.AnchorPoint = Vector2.new(.5, .5)
loaderCard.Position = UDim2.fromScale(.5, .5)
loaderCard.Size = UDim2.fromOffset(isMobile and 470 or 520, 350)
loaderCard.BackgroundColor3 = Color3.fromRGB(23, 20, 43)
loaderCard.BackgroundTransparency = .08
loaderCard.BorderSizePixel = 0
loaderCard.Parent = loading
corner(loaderCard, 24)
outline(loaderCard, Color3.fromRGB(220, 207, 255), .45, 1.5)
shadow(loaderCard, .42)

local loaderLogo = Instance.new("Frame")
loaderLogo.AnchorPoint = Vector2.new(.5, 0)
loaderLogo.Position = UDim2.new(.5, 0, 0, 30)
loaderLogo.Size = UDim2.fromOffset(82, 82)
loaderLogo.BackgroundColor3 = Theme.accent
loaderLogo.BorderSizePixel = 0
loaderLogo.Parent = loaderCard
corner(loaderLogo, 24)
outline(loaderLogo, Color3.fromRGB(225, 217, 255), .22, 2)
local loaderLogoGradient = Instance.new("UIGradient")
loaderLogoGradient.Color = ColorSequence.new(Theme.accent, Theme.accent2)
loaderLogoGradient.Rotation = 35
loaderLogoGradient.Parent = loaderLogo
local loaderLogoScale = Instance.new("UIScale")
loaderLogoScale.Scale = .6
loaderLogoScale.Parent = loaderLogo
local loaderLetter = label(loaderLogo, "S", UDim2.fromScale(1,1), nil, Enum.Font.GothamBlack, "text", 39)
loaderLetter.TextXAlignment = Enum.TextXAlignment.Center

local loadingTitle = label(loaderCard, "STATICS NEWGEN", UDim2.new(1,-40,0,45), UDim2.fromOffset(20,126), Enum.Font.GothamBlack, "text", 28)
loadingTitle.TextXAlignment = Enum.TextXAlignment.Center
local loadingStage = label(loaderCard, "Loading clean systems...", UDim2.new(1,-40,0,25), UDim2.fromOffset(20,170), Enum.Font.GothamBold, "text", 12)
loadingStage.TextXAlignment = Enum.TextXAlignment.Center
local loadingDiscord = label(loaderCard, "discord.gg/rXxwRtaCQ", UDim2.new(1,-40,0,22), UDim2.fromOffset(20,199), Enum.Font.GothamBold, "accent2", 11)
loadingDiscord.TextXAlignment = Enum.TextXAlignment.Center
local loadingBar = Instance.new("Frame")
loadingBar.Size = UDim2.new(1, -72, 0, 7)
loadingBar.Position = UDim2.fromOffset(36, 239)
loadingBar.BackgroundColor3 = Color3.fromRGB(66, 61, 91)
loadingBar.BorderSizePixel = 0
loadingBar.Parent = loaderCard
corner(loadingBar, 4)
local loadingFill = Instance.new("Frame")
loadingFill.Size = UDim2.fromScale(0, 1)
loadingFill.BackgroundColor3 = Theme.accent
loadingFill.BorderSizePixel = 0
loadingFill.Parent = loadingBar
corner(loadingFill, 4)
local loadingFillGradient = Instance.new("UIGradient")
loadingFillGradient.Color = ColorSequence.new(Theme.accent, Theme.accent2)
loadingFillGradient.Parent = loadingFill
local loadingTip = label(loaderCard, "Smooth aim. Clear information. Your game stays authoritative.", UDim2.new(1,-54,0,42), UDim2.fromOffset(27,269), Enum.Font.Gotham, "muted", 10)
loadingTip.TextWrapped = true
loadingTip.TextXAlignment = Enum.TextXAlignment.Center

local loadingSpin = RunService.RenderStepped:Connect(function(dt)
	loaderLogoGradient.Rotation = (loaderLogoGradient.Rotation + dt * 36) % 360
end)

local dim = panel(gui, UDim2.fromScale(1,1), nil, "bg")
dim.BackgroundColor3 = Color3.new()
dim.BackgroundTransparency = .45
dim.Visible = false
local defaultBaseSize = isMobile and Vector2.new(640,760) or Vector2.new(860,550)
UI.layoutBaseSize = defaultBaseSize
UI.layoutFitWidth = defaultBaseSize.X + 24
local main = panel(gui, UDim2.fromOffset(defaultBaseSize.X,defaultBaseSize.Y), UDim2.fromScale(.5,.5), "bg")
main.AnchorPoint = Vector2.new(.5,.5)
main.Visible = false
local mainStroke=outline(main, Theme.accent, .28, 1.5)
shadow(main, .28)
local scale = Instance.new("UIScale")
scale.Parent = main
local function fitWindow()
	local viewport = camera and camera.ViewportSize or Vector2.new(1280,720)
	local size = UI.layoutBaseSize or defaultBaseSize
	scale.Scale = math.clamp(math.min(viewport.X/(UI.layoutFitWidth or(size.X+24)), viewport.Y/(size.Y+24)), isMobile and .42 or .55, 1)
end
fitWindow()

local top = panel(main, UDim2.new(1,0,0,58), nil, "panel")
local topSquare=Instance.new("Frame")
topSquare.Size=UDim2.new(1,0,0,14)
topSquare.Position=UDim2.new(0,0,1,-14)
topSquare.BackgroundColor3=Theme.panel
topSquare.BorderSizePixel=0
topSquare.Parent=top
bindTheme(topSquare,"BackgroundColor3","panel")
local topGradient = Instance.new("UIGradient")
topGradient.Color = ColorSequence.new(Theme.panel:Lerp(Theme.accent, .12), Theme.panel)
topGradient.Rotation = 12
topGradient.Parent = top
local logo = panel(top, UDim2.fromOffset(36,36), UDim2.fromOffset(14,11), "accent")
local logoText = label(logo, "S", UDim2.fromScale(1,1), nil, Enum.Font.GothamBlack, "bg", 18)
logoText.TextXAlignment = Enum.TextXAlignment.Center
label(top, "Statics Newgen", UDim2.fromOffset(190,24), UDim2.fromOffset(61,7), Enum.Font.GothamBold, "text", 16)
label(top, "discord.gg/rXxwRtaCQ", UDim2.fromOffset(210,18), UDim2.fromOffset(61,31), Enum.Font.Gotham, "muted", 10)
UI.saveStatus = label(top, "Ready", UDim2.fromOffset(150,20), UDim2.new(1,-240,0,19), Enum.Font.GothamBold, "muted", 10)
UI.saveStatus.TextXAlignment = Enum.TextXAlignment.Right
UI.saveStatus.Visible = not isMobile
local close = button(top, "X", UDim2.fromOffset(34,30), UDim2.new(1,-42,0,14), "row")
local minimize = button(top, "-", UDim2.fromOffset(34,30), UDim2.new(1,-82,0,14), "row")

do
	local dragging=false
	local dragStart=nil
	local startPosition=nil
	top.InputBegan:Connect(function(input)
		if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
			dragging=true;dragStart=input.Position;startPosition=main.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then
			local delta=input.Position-dragStart
			main.Position=UDim2.new(startPosition.X.Scale,startPosition.X.Offset+delta.X/scale.Scale,startPosition.Y.Scale,startPosition.Y.Offset+delta.Y/scale.Scale)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dragging=false end
	end)
end

local sidebar = panel(main, isMobile and UDim2.new(1,0,0,62) or UDim2.new(0,116,1,-58), isMobile and UDim2.new(0,0,1,-62) or UDim2.fromOffset(0,58), "panel")
local content = Instance.new("Frame")
content.Size = isMobile and UDim2.new(1,0,1,-120) or UDim2.new(1,-116,1,-58)
content.Position = isMobile and UDim2.fromOffset(0,58) or UDim2.fromOffset(116,58)
content.BackgroundTransparency = 1
content.ClipsDescendants = true
content.Parent = main

UI.rightRail = panel(main, UDim2.fromOffset(150,330), UDim2.new(1,14,0,78), "panel")
UI.rightRail.Visible = false
shadow(UI.rightRail,.55)
label(UI.rightRail,"STATICS NEWGEN",UDim2.new(1,-20,0,24),UDim2.fromOffset(10,13),Enum.Font.GothamBlack,"text",12).TextXAlignment=Enum.TextXAlignment.Center
label(UI.rightRail,"SESSION",UDim2.new(1,-20,0,18),UDim2.fromOffset(10,54),Enum.Font.GothamBold,"accent2",9)
UI.layoutStatus = label(UI.rightRail,"READY",UDim2.new(1,-20,0,28),UDim2.fromOffset(10,76),Enum.Font.GothamBlack,"text",14)
UI.layoutStatus.TextXAlignment=Enum.TextXAlignment.Center
label(UI.rightRail,"DEVICE",UDim2.new(1,-20,0,18),UDim2.fromOffset(10,124),Enum.Font.GothamBold,"accent",9)
local railDevice=label(UI.rightRail,string.upper(device),UDim2.new(1,-20,0,28),UDim2.fromOffset(10,146),Enum.Font.GothamBlack,"text",14);railDevice.TextXAlignment=Enum.TextXAlignment.Center
label(UI.rightRail,"COMMUNITY",UDim2.new(1,-20,0,18),UDim2.fromOffset(10,197),Enum.Font.GothamBold,"accent2",9)
local railDiscord=label(UI.rightRail,"discord.gg/\nrXxwRtaCQ",UDim2.new(1,-20,0,44),UDim2.fromOffset(10,222),Enum.Font.GothamBold,"text",10);railDiscord.TextWrapped=true;railDiscord.TextXAlignment=Enum.TextXAlignment.Center
local launcher = button(gui, "STATICS", UDim2.fromOffset(122,46), UDim2.new(0,16,1,-64), "accent")
launcher.Visible = false
launcher.TextColor3 = Color3.new(1,1,1)
launcher.TextSize = 13
local launcherGradient = Instance.new("UIGradient")
launcherGradient.Color = ColorSequence.new(Color3.fromRGB(165, 88, 247), Color3.fromRGB(104, 45, 214))
launcherGradient.Rotation = 18
launcherGradient.Parent = launcher
outline(launcher, Color3.fromRGB(218, 199, 255), .35, 1.5)
shadow(launcher, .45)
local showPage
local applyLayout

local toast=Instance.new("CanvasGroup")
toast.AnchorPoint=Vector2.new(1,0)
toast.Position=UDim2.new(1,-18,0,18)
toast.Size=UDim2.fromOffset(310,66)
toast.BackgroundColor3=Theme.panel
toast.BorderSizePixel=0
toast.GroupTransparency=1
toast.Visible=false
toast.ZIndex=500
toast.Parent=gui
corner(toast,12)
outline(toast,Theme.accent2,.3,1.5)
local toastTitle=label(toast,"STATICS",UDim2.new(1,-24,0,20),UDim2.fromOffset(12,8),Enum.Font.GothamBlack,"accent2",10);toastTitle.ZIndex=501
local toastMessage=label(toast,"",UDim2.new(1,-24,0,28),UDim2.fromOffset(12,29),Enum.Font.GothamMedium,"text",11);toastMessage.TextWrapped=true;toastMessage.ZIndex=501
local toastToken=0
local function notify(message,good)
	toastToken+=1
	local token=toastToken
	toast.Visible=true;toast.GroupTransparency=1;toast.Position=UDim2.new(1,20,0,18)
	toastTitle.Text=good==false and"ATTENTION"or"STATICS NEWGEN"
	toastTitle.TextColor3=good==false and Color3.fromRGB(248,75,90)or Theme.accent2
	toastMessage.Text=tostring(message)
	TweenService:Create(toast,TweenInfo.new(.22,Enum.EasingStyle.Quart),{GroupTransparency=0,Position=UDim2.new(1,-18,0,18)}):Play()
	task.delay(2.6,function()if token~=toastToken then return end;TweenService:Create(toast,TweenInfo.new(.2),{GroupTransparency=1,Position=UDim2.new(1,20,0,18)}):Play();task.wait(.22);if token==toastToken then toast.Visible=false end end)
end
UI.notify=notify
local mobileAimButton = nil
if isMobile then
	mobileAimButton = button(gui, "HOLD AIM", UDim2.fromOffset(150,58), UDim2.new(1,-168,1,-78), "accent")
	mobileAimButton.Visible = false
	mobileAimButton.TextSize = 15
	mobileAimButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch and Config.AimEnabled then State.aimHeld = true; State.target = nil end
	end)
	mobileAimButton.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then State.aimHeld = false; State.target = nil end
	end)
end

local function applyTheme(themeName)
	local nextTheme = Themes[themeName]
	if not nextTheme then return end
	Theme = nextTheme
	Config.Theme = themeName
	for _, binding in ipairs(UI.bindings) do
		if binding.object.Parent and not binding.object:GetAttribute("ThemeLocked") and Theme[binding.role] then
			binding.object[binding.property] = Theme[binding.role]
		end
	end
	for _,refresh in ipairs(UI.refreshers)do refresh()end
	if Config.CustomBackground then
		local custom = Color3.fromHSV(Config.BackgroundHue, Config.BackgroundSaturation, Config.BackgroundValue)
		main.BackgroundColor3 = Theme.bg:Lerp(custom, Config.BackgroundIntensity)
	end
	mainStroke.Color=Theme.accent
	topGradient.Color=ColorSequence.new(Theme.panel:Lerp(Theme.accent,.12),Theme.panel)
	launcherGradient.Color=ColorSequence.new(Theme.accent:Lerp(Color3.new(1,1,1),.2),Theme.accent:Lerp(Color3.new(0,0,0),.18))
	if UI.fovStroke then UI.fovStroke.Color=Color3.fromHSV(Config.FOVCircleHue,.75,1)end
	State.dirty = true
	if UI.notify then UI.notify(Themes[themeName] and themeName.." theme applied"or"Theme applied",true)end
	if showPage and State.currentPage then showPage(State.currentPage) end
end
UI.applyTheme = applyTheme

local menuAnimationToken=0
local function setMenu(open)
	menuAnimationToken+=1
	local token=menuAnimationToken
	State.menuOpen = open
	local currentSize=UI.layoutBaseSize or defaultBaseSize
	if open then
		main.Visible=true;dim.Visible=true;launcher.Visible=false
		main.Size=UDim2.fromOffset(currentSize.X*.96,currentSize.Y*.96)
		dim.BackgroundTransparency=1
		TweenService:Create(main,TweenInfo.new(.26,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),{Size=UDim2.fromOffset(currentSize.X,currentSize.Y)}):Play()
		TweenService:Create(dim,TweenInfo.new(.2),{BackgroundTransparency=.45}):Play()
	else
		TweenService:Create(main,TweenInfo.new(.18,Enum.EasingStyle.Quart),{Size=UDim2.fromOffset(currentSize.X*.97,currentSize.Y*.97)}):Play()
		TweenService:Create(dim,TweenInfo.new(.18),{BackgroundTransparency=1}):Play()
		task.delay(.19,function()if token==menuAnimationToken then main.Visible=false;dim.Visible=false;launcher.Visible=true end end)
	end
	if UI.quickBar then UI.quickBar.Visible = Config.ActiveProfile == "The Final Letter" and not open end
	if mobileAimButton then mobileAimButton.Visible = not open and Config.AimEnabled and Config.ActiveProfile ~= "The Final Letter" end
end
close.Activated:Connect(function() setMenu(false) end)
minimize.Activated:Connect(function() setMenu(false) end)
launcher.Activated:Connect(function() setMenu(true) end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.RightShift then setMenu(not State.menuOpen) end
end)

local function newPage(name)
	local page = Instance.new("Frame")
	page.Name = name
	page.Size = UDim2.fromScale(1,1)
	page.BackgroundTransparency = 1
	page.Visible = false
	page.Parent = content
	UI.pages[name] = page
	return page
end
local function scrollingPanel(parent,size,position,canvasHeight)
	local object=Instance.new("ScrollingFrame")
	object.Size=size;object.Position=position;object.BackgroundColor3=Theme.panel;object.BorderSizePixel=0;object.ScrollBarThickness=3;object.ScrollBarImageColor3=Theme.accent;object.CanvasSize=UDim2.fromOffset(0,canvasHeight);object.Parent=parent;corner(object,10);bindTheme(object,"BackgroundColor3","panel");return object
end
local navigation = {
	{ "Hub", "Game Hub" }, { "Home", "Overview" }, { "Aim", "Aim Assist" }, { "VRAim", "VR Assist" },
	{ "Words", "Final Letter", "The Final Letter" }, { "Visuals", "Visuals" }, { "Performance", "Performance" },
	{ "Themes", "Themes" }, { "Colors", "Colors" }, { "Session", "Session" }, { "Players", "Players" },
}
UI.navVisuals = {}

local function navLine(parent, size, position, rotation)
	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(.5,.5)
	line.Size = size
	line.Position = position
	line.Rotation = rotation or 0
	line.BackgroundColor3 = Theme.muted
	line.BorderSizePixel = 0
	line.Parent = parent
	corner(line, 3)
	return line
end

local function createNavIcon(parent, pageName)
	local icon = Instance.new("Frame")
	icon.Size = UDim2.fromOffset(24,24)
	icon.Position = UDim2.fromOffset(8,5)
	icon.BackgroundTransparency = 1
	icon.Parent = parent
	local pieces = {}
	local function add(size, position, rotation)
		local piece = navLine(icon, size, position, rotation)
		table.insert(pieces, piece)
		return piece
	end
	if pageName == "Hub" then
		for x=0,1 do for y=0,1 do add(UDim2.fromOffset(8,8),UDim2.fromOffset(7+x*10,7+y*10)) end end
	elseif pageName == "Home" then
		add(UDim2.fromOffset(15,3),UDim2.fromOffset(7,9),-42);add(UDim2.fromOffset(15,3),UDim2.fromOffset(17,9),42);add(UDim2.fromOffset(16,11),UDim2.fromOffset(12,16))
	elseif pageName == "Aim" then
		local ring=add(UDim2.fromOffset(17,17),UDim2.fromOffset(12,12));ring.BackgroundTransparency=1;local s=outline(ring,Theme.muted,0,2);table.insert(pieces,s);add(UDim2.fromOffset(23,2),UDim2.fromOffset(12,12));add(UDim2.fromOffset(2,23),UDim2.fromOffset(12,12))
	elseif pageName == "VRAim" then
		local headset=add(UDim2.fromOffset(22,13),UDim2.fromOffset(12,11));headset.BackgroundTransparency=1;local s=outline(headset,Theme.muted,0,2);table.insert(pieces,s);add(UDim2.fromOffset(7,5),UDim2.fromOffset(7,12));add(UDim2.fromOffset(7,5),UDim2.fromOffset(17,12));add(UDim2.fromOffset(8,2),UDim2.fromOffset(12,20))
		UI.vrNavBadge=Instance.new("Frame");UI.vrNavBadge.Size=UDim2.fromOffset(12,12);UI.vrNavBadge.Position=UDim2.new(1,-6,0,-4);UI.vrNavBadge.BackgroundColor3=Color3.fromRGB(248,75,90);UI.vrNavBadge.BorderSizePixel=0;UI.vrNavBadge.Parent=icon;corner(UI.vrNavBadge,6);outline(UI.vrNavBadge,Color3.new(1,1,1),.35,1)
	elseif pageName == "Words" then
		local left=add(UDim2.fromOffset(9,17),UDim2.fromOffset(7,12));left.BackgroundTransparency=1;table.insert(pieces,outline(left,Theme.muted,0,2));local right=add(UDim2.fromOffset(9,17),UDim2.fromOffset(17,12));right.BackgroundTransparency=1;table.insert(pieces,outline(right,Theme.muted,0,2))
	elseif pageName == "Visuals" then
		local eye=add(UDim2.fromOffset(23,14),UDim2.fromOffset(12,12));eye.BackgroundTransparency=1;table.insert(pieces,outline(eye,Theme.muted,0,2));add(UDim2.fromOffset(7,7),UDim2.fromOffset(12,12))
	elseif pageName == "Performance" then
		add(UDim2.fromOffset(4,9),UDim2.fromOffset(5,16));add(UDim2.fromOffset(4,15),UDim2.fromOffset(12,13));add(UDim2.fromOffset(4,21),UDim2.fromOffset(19,10))
	elseif pageName == "Themes" then
		local a=add(UDim2.fromOffset(14,13),UDim2.fromOffset(9,9));a.BackgroundTransparency=1;table.insert(pieces,outline(a,Theme.muted,0,2));local b=add(UDim2.fromOffset(14,13),UDim2.fromOffset(15,15));b.BackgroundTransparency=1;table.insert(pieces,outline(b,Theme.muted,0,2))
	elseif pageName == "Colors" then
		local ring=add(UDim2.fromOffset(20,20),UDim2.fromOffset(12,12));ring.BackgroundTransparency=1;table.insert(pieces,outline(ring,Theme.muted,0,2));add(UDim2.fromOffset(5,5),UDim2.fromOffset(8,8));add(UDim2.fromOffset(5,5),UDim2.fromOffset(16,8));add(UDim2.fromOffset(5,5),UDim2.fromOffset(12,16))
	elseif pageName == "Session" then
		add(UDim2.fromOffset(18,3),UDim2.fromOffset(10,8));add(UDim2.fromOffset(8,3),UDim2.fromOffset(19,5),45);add(UDim2.fromOffset(18,3),UDim2.fromOffset(14,16));add(UDim2.fromOffset(8,3),UDim2.fromOffset(5,19),45)
	else
		add(UDim2.fromOffset(8,8),UDim2.fromOffset(8,8));add(UDim2.fromOffset(7,7),UDim2.fromOffset(17,9));add(UDim2.fromOffset(16,8),UDim2.fromOffset(9,18));add(UDim2.fromOffset(10,7),UDim2.fromOffset(18,18))
	end
	return icon,pieces
end
local function refreshNavigation()
	local visible = {}
	for _, spec in ipairs(navigation) do
		local show = not spec[3] or (State.profileChosen and Config.ActiveProfile == spec[3])
		UI.nav[spec[1]].Visible = show
		if show then table.insert(visible, spec) end
	end
	for index, spec in ipairs(visible) do
		local navButton = UI.nav[spec[1]]
		if isMobile or Config.LayoutStyle == "Horizon" then
			navButton.Size = UDim2.new(1/#visible,-4,0,48)
			navButton.Position = UDim2.new((index-1)/#visible,2,0,7)
			UI.navVisuals[spec[1]].title.Visible = false
			UI.navVisuals[spec[1]].icon.Position = UDim2.new(.5,-12,0,11)
		elseif Config.LayoutStyle == "Lynen" then
			local step=math.min(43,math.floor(406/#visible))
			local height=math.clamp(step-5,30,38)
			navButton.Size = UDim2.new(1,-14,0,height)
			navButton.Position = UDim2.fromOffset(7,7+(index-1)*step)
			UI.navVisuals[spec[1]].title.Visible = true
			UI.navVisuals[spec[1]].icon.Position = UDim2.fromOffset(8,7)
		else
			navButton.Size = UDim2.new(1,-16,0,34)
			navButton.Position = UDim2.fromOffset(8,7+(index-1)*38)
			UI.navVisuals[spec[1]].title.Visible = true
			UI.navVisuals[spec[1]].icon.Position = UDim2.fromOffset(8,5)
		end
	end
end
showPage=function(name)
	if name == "VRAim" and not State.vrUnlocked then UI.openVRGate(); return end
	State.currentPage=name
	for pageName, page in pairs(UI.pages) do
		local active = pageName == name
		page.Visible = active
		if active then
			page.Position = UDim2.fromOffset(12,0)
			TweenService:Create(page,TweenInfo.new(.22,Enum.EasingStyle.Quart),{Position=UDim2.new()}):Play()
		end
	end
	for pageName, navButton in pairs(UI.nav) do
		local active = pageName == name
		navButton.BackgroundColor3 = active and Theme.accent or Theme.row
		local visual = UI.navVisuals[pageName]
		visual.title.TextColor3 = active and Theme.text or Theme.muted
		for _,piece in ipairs(visual.pieces) do
			if piece:IsA("UIStroke") then piece.Color=active and Theme.text or Theme.muted else piece.BackgroundColor3=active and Theme.text or Theme.muted end
		end
	end
end
for _, spec in ipairs(navigation) do
	local name = spec[1]
	local navButton = button(sidebar, "", UDim2.new(1,-16,0,34), nil, "row")
	local icon,pieces=createNavIcon(navButton,name)
	local title=label(navButton,spec[2],UDim2.new(1,-43,1,0),UDim2.fromOffset(38,0),Enum.Font.GothamBold,"muted",10)
	UI.nav[name] = navButton
	UI.navVisuals[name]={icon=icon,pieces=pieces,title=title}
	navButton.Activated:Connect(function() showPage(name) end)
end

applyLayout=function(layoutName,animate)
	if layoutName~="Newgen"and layoutName~="Lynen"and layoutName~="Horizon"then layoutName="Newgen"end
	Config.LayoutStyle=layoutName
	main.Position=UDim2.fromScale(.5,.5)
	local size
	if isMobile then
		size=Vector2.new(640,760)
		UI.layoutFitWidth=size.X+20
		top.Size=UDim2.new(1,0,0,58);top.Position=UDim2.new()
		sidebar.Size=UDim2.new(1,0,0,62);sidebar.Position=UDim2.new(0,0,1,-62)
		content.Size=UDim2.new(1,0,1,-120);content.Position=UDim2.fromOffset(0,58)
		UI.rightRail.Visible=false
		main.BackgroundTransparency=0
	elseif layoutName=="Lynen"then
		size=Vector2.new(760,560)
		UI.layoutFitWidth=1080
		top.Size=UDim2.new(1,0,0,58);top.Position=UDim2.new()
		sidebar.Size=UDim2.fromOffset(148,420);sidebar.Position=UDim2.fromOffset(-160,76)
		content.Size=UDim2.new(1,0,1,-58);content.Position=UDim2.fromOffset(0,58)
		UI.rightRail.Position=UDim2.new(1,12,0,76);UI.rightRail.Visible=true
		main.BackgroundTransparency=.08;sidebar.BackgroundTransparency=.08;UI.rightRail.BackgroundTransparency=.08
	elseif layoutName=="Horizon"then
		size=Vector2.new(1080,640)
		UI.layoutFitWidth=1110
		top.Size=UDim2.new(1,0,0,56);top.Position=UDim2.new()
		sidebar.Size=UDim2.fromOffset(720,62);sidebar.Position=UDim2.new(.5,-360,1,-70)
		content.Size=UDim2.new(1,0,1,-132);content.Position=UDim2.fromOffset(0,56)
		UI.rightRail.Visible=false
		main.BackgroundTransparency=.32;sidebar.BackgroundTransparency=.04
	else
		size=Vector2.new(860,550)
		UI.layoutFitWidth=884
		top.Size=UDim2.new(1,0,0,58);top.Position=UDim2.new()
		sidebar.Size=UDim2.new(0,116,1,-58);sidebar.Position=UDim2.fromOffset(0,58)
		content.Size=UDim2.new(1,-116,1,-58);content.Position=UDim2.fromOffset(116,58)
		UI.rightRail.Visible=false
		main.BackgroundTransparency=0;sidebar.BackgroundTransparency=0
	end
	UI.layoutBaseSize=size
	if animate then TweenService:Create(main,TweenInfo.new(.32,Enum.EasingStyle.Quart),{Size=UDim2.fromOffset(size.X,size.Y)}):Play()else main.Size=UDim2.fromOffset(size.X,size.Y)end
	fitWindow();refreshNavigation();State.dirty=true
	if UI.layoutStatus then UI.layoutStatus.Text=string.upper(layoutName)end
	if UI.overviewLayout then UI.overviewLayout.Text="LAYOUT  /  "..string.upper(layoutName)end
	if UI.notify and animate then UI.notify(layoutName.." interface loaded",true)end
end
UI.applyLayout=applyLayout

local function makeToggle(parent, title, y, getter, setter)
	local row = panel(parent, UDim2.new(1,-20,0,40), UDim2.fromOffset(10,y), "row")
	label(row, title, UDim2.new(1,-72,1,0), UDim2.fromOffset(10,0), Enum.Font.GothamMedium, "text", 12)
	local switch = button(row, "", UDim2.fromOffset(42,22), UDim2.new(1,-52,.5,-11), "row")
	local dot = panel(switch, UDim2.fromOffset(16,16), UDim2.fromOffset(3,3), "text")
	corner(switch,11); corner(dot,8)
	local function refresh()
		local enabled = getter()
		switch.BackgroundColor3 = enabled and Theme.accent or Color3.fromRGB(65,66,79)
		dot.Position = enabled and UDim2.fromOffset(23,3) or UDim2.fromOffset(3,3)
	end
	switch.Activated:Connect(function() setter(not getter()); State.dirty = true; refresh() end)
	refresh(); table.insert(UI.refreshers,refresh); return refresh
end
local function makeSlider(parent,title,y,minimum,maximum,getter,setter)
	local row = panel(parent, UDim2.new(1,-20,0,58), UDim2.fromOffset(10,y), "row")
	label(row,title,UDim2.new(1,-80,0,24),UDim2.fromOffset(10,3),Enum.Font.GothamMedium,"text",12)
	local valueLabel = label(row,"",UDim2.fromOffset(70,24),UDim2.new(1,-80,0,3),Enum.Font.GothamBold,"accent2",11)
	valueLabel.TextXAlignment=Enum.TextXAlignment.Right
	local bar=button(row,"",UDim2.new(1,-20,0,8),UDim2.fromOffset(10,39),"row")
	local fill=panel(bar,UDim2.fromScale(0,1),nil,"accent")
	local dragging=false
	local function refresh() local n=getter();fill.Size=UDim2.fromScale(math.clamp((n-minimum)/(maximum-minimum),0,1),1);valueLabel.Text=tostring(math.floor(n*100+.5)/100) end
	local function setX(x) local a=math.clamp((x-bar.AbsolutePosition.X)/math.max(bar.AbsoluteSize.X,1),0,1);setter(minimum+(maximum-minimum)*a);State.dirty=true;refresh() end
	bar.InputBegan:Connect(function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dragging=true;setX(input.Position.X) end end)
	UserInputService.InputChanged:Connect(function(input) if dragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then setX(input.Position.X) end end)
	UserInputService.InputEnded:Connect(function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dragging=false end end)
	refresh()
end

local function buildHub()
	local page=newPage("Hub")
	pageHeader(page,"Game Hub","Choose a profile. Only its dedicated tools are added to navigation.","accent")
	local profiles={
		{"Universal","Core tools, device detection, aim, visuals, and performance.","accent"},
		{"The Final Letter","Keyboard capture, real-time recommendations, and one-tap filling.","accent2"},
		{"Mystery Showdown","Role-aware presentation preset for your own mystery game.","accent"},
	}
	for index,spec in ipairs(profiles) do
		local profileName=spec[1]
		local chosenProfile=profileName
		local card=panel(page,UDim2.new(1/3,-16,1,-104),UDim2.new((index-1)/3,10,0,78),"panel")
		shadow(card,.62)
		local accentLine=Instance.new("Frame");accentLine.Size=UDim2.new(1,0,0,5);accentLine.BackgroundColor3=Theme[spec[3]];accentLine.BorderSizePixel=0;accentLine.Parent=card;corner(accentLine,3)
		label(card,string.format("0%d",index),UDim2.new(1,-24,0,24),UDim2.fromOffset(12,17),Enum.Font.GothamBlack,spec[3],12).TextXAlignment=Enum.TextXAlignment.Right
		label(card,profileName,UDim2.new(1,-24,0,42),UDim2.fromOffset(12,47),Enum.Font.GothamBlack,"text",17).TextWrapped=true
		local description=label(card,spec[2],UDim2.new(1,-24,0,95),UDim2.fromOffset(12,98),Enum.Font.Gotham,"muted",10);description.TextWrapped=true;description.TextYAlignment=Enum.TextYAlignment.Top
		local load=button(card,"LOAD PROFILE",UDim2.new(1,-24,0,42),UDim2.new(0,12,1,-54),spec[3])
		load.Activated:Connect(function()
			Config.ActiveProfile=chosenProfile;State.profileChosen=true;refreshNavigation();State.dirty=true
			if UI.notify then UI.notify(chosenProfile.." profile loaded",true)end
			if UI.overviewProfile then UI.overviewProfile.Text="PROFILE  /  "..string.upper(chosenProfile)end
			if chosenProfile=="The Final Letter" then Config.AimEnabled=false;Config.ESPEnabled=false;for _,refresh in ipairs(UI.refreshers)do refresh()end;showPage("Words");task.delay(.2,function()setMenu(false)end)
			elseif chosenProfile=="Mystery Showdown" then showPage("Visuals") else showPage("Home") end
		end)
	end
end
local function buildHome()
	local page=newPage("Home")
	pageHeader(page,"Overview","A live view of this client, server session, and active Statics systems.","accent")

	local identity=panel(page,UDim2.new(1,-28,0,92),UDim2.fromOffset(14,76),"panel")
	shadow(identity,.65)
	local avatar=Instance.new("ImageLabel");avatar.Size=UDim2.fromOffset(64,64);avatar.Position=UDim2.fromOffset(14,14);avatar.BackgroundColor3=Theme.row;avatar.BorderSizePixel=0;avatar.Parent=identity;corner(avatar,14);outline(avatar,Theme.accent2,.35,1.5);setAvatar(avatar,player.UserId)
	label(identity,player.DisplayName,UDim2.new(1,-320,0,28),UDim2.fromOffset(94,15),Enum.Font.GothamBlack,"text",19)
	label(identity,"@"..player.Name.."  /  "..string.upper(device),UDim2.new(1,-320,0,20),UDim2.fromOffset(94,45),Enum.Font.Gotham,"muted",10)
	UI.overviewRole=label(identity,"ROLE: WAITING",UDim2.fromOffset(150,34),UDim2.new(1,-316,.5,-17),Enum.Font.GothamBold,"accent2",10);UI.overviewRole.TextXAlignment=Enum.TextXAlignment.Center;UI.overviewRole.BackgroundTransparency=0;UI.overviewRole.BackgroundColor3=Theme.row;corner(UI.overviewRole,9)
	local runtimeBadge=label(identity,RunService:IsStudio()and"ROBLOX STUDIO"or"ROBLOX PLAYER",UDim2.fromOffset(140,34),UDim2.new(1,-154,.5,-17),Enum.Font.GothamBold,"text",10);runtimeBadge.TextXAlignment=Enum.TextXAlignment.Center;runtimeBadge.BackgroundTransparency=0;runtimeBadge.BackgroundColor3=Theme.row;corner(runtimeBadge,9)

	local serverCard=panel(page,UDim2.new(.52,-20,0,214),UDim2.fromOffset(14,182),"panel")
	local systemsCard=panel(page,UDim2.new(.48,-8,0,214),UDim2.new(.52,0,0,182),"panel")
	label(serverCard,"SERVER SESSION",UDim2.new(1,-24,0,20),UDim2.fromOffset(12,12),Enum.Font.GothamBold,"accent2",10)
	local grid=Instance.new("Frame");grid.Size=UDim2.new(1,-24,1,-50);grid.Position=UDim2.fromOffset(12,38);grid.BackgroundTransparency=1;grid.Parent=serverCard
	local gridLayout=Instance.new("UIGridLayout");gridLayout.CellPadding=UDim2.fromOffset(8,8);gridLayout.CellSize=UDim2.new(.5,-4,.5,-4);gridLayout.Parent=grid
	local function stat(titleText)
		local box=panel(grid,UDim2.new(),nil,"row");label(box,titleText,UDim2.new(1,-16,0,17),UDim2.fromOffset(8,6),Enum.Font.Gotham,"muted",9);local value=label(box,"-",UDim2.new(1,-16,0,27),UDim2.fromOffset(8,23),Enum.Font.GothamBlack,"text",14);return value
	end
	UI.overviewPlayers=stat("PLAYERS")
	UI.overviewPing=stat("NETWORK")
	UI.overviewPlace=stat("PLACE ID")
	UI.overviewTime=stat("SESSION")

	label(systemsCard,"STATICS SYSTEMS",UDim2.new(1,-24,0,20),UDim2.fromOffset(12,12),Enum.Font.GothamBold,"accent",10)
	UI.homeStatus=label(systemsCard,"Aim OFF / ESP OFF",UDim2.new(1,-24,0,32),UDim2.fromOffset(12,39),Enum.Font.GothamBlack,"text",18)
	UI.overviewProfile=label(systemsCard,"PROFILE  /  "..string.upper(Config.ActiveProfile),UDim2.new(1,-24,0,22),UDim2.fromOffset(12,80),Enum.Font.GothamBold,"muted",10)
	UI.overviewLayout=label(systemsCard,"LAYOUT  /  "..string.upper(Config.LayoutStyle),UDim2.new(1,-24,0,22),UDim2.fromOffset(12,108),Enum.Font.GothamBold,"muted",10)
	UI.overviewWall=label(systemsCard,"WALL CHECK  /  ALWAYS ENFORCED",UDim2.new(1,-24,0,22),UDim2.fromOffset(12,136),Enum.Font.GothamBold,"accent2",10)
	UI.overviewSave=label(systemsCard,"PREFERENCES  /  READY",UDim2.new(1,-24,0,22),UDim2.fromOffset(12,164),Enum.Font.GothamBold,"muted",10)

	local community=panel(page,UDim2.new(1,-28,0,65),UDim2.fromOffset(14,408),"panel")
	local communityGradient=Instance.new("UIGradient");communityGradient.Color=ColorSequence.new(Theme.accent:Lerp(Theme.panel,.35),Theme.panel);communityGradient.Rotation=12;communityGradient.Parent=community
	label(community,"STATICS COMMUNITY",UDim2.fromOffset(180,20),UDim2.fromOffset(14,10),Enum.Font.GothamBold,"accent2",9)
	label(community,"discord.gg/rXxwRtaCQ",UDim2.new(1,-210,0,25),UDim2.fromOffset(14,31),Enum.Font.GothamBlack,"text",13)
	local communityStatus=label(community,"OFFICIAL EXPERIENCE RUNTIME",UDim2.fromOffset(190,34),UDim2.new(1,-204,.5,-17),Enum.Font.GothamBold,"text",9);communityStatus.TextXAlignment=Enum.TextXAlignment.Center;communityStatus.BackgroundTransparency=0;communityStatus.BackgroundColor3=Theme.row;corner(communityStatus,9)
end
local function buildAim()
	local page=newPage("Aim")
	pageHeader(page,"Aim Assist","Smooth right-click assistance with optional weapon-direction correction.","accent")
	local left=scrollingPanel(page,UDim2.new(.58,-20,1,-82),UDim2.fromOffset(14,70),980)
	local right=panel(page,UDim2.new(.42,-8,1,-82),UDim2.new(.58,0,0,70),"panel")
	UI.refreshAim=makeToggle(left,"Master aim assist",10,function()return Config.AimEnabled end,function(v)Config.AimEnabled=v;if not v then State.target=nil end end)
	makeToggle(left,"Sticky target",58,function()return Config.StickyAim end,function(v)Config.StickyAim=v end)
	makeToggle(left,"Wall check (always on)",106,function()return true end,function()Config.WallCheck=true;if UI.notify then UI.notify("Wall Check is always enforced",true)end end)
	makeToggle(left,"Team check",154,function()return Config.TeamCheck end,function(v)Config.TeamCheck=v end)
	makeToggle(left,"Prediction",202,function()return Config.Prediction end,function(v)Config.Prediction=v end)
	makeToggle(left,"Camera assist",250,function()return Config.CameraAssist end,function(v)Config.CameraAssist=v end)
	makeToggle(left,"Show FOV circle",298,function()return Config.ShowFOVCircle end,function(v)Config.ShowFOVCircle=v end)
	makeToggle(left,"Custom camera FOV",346,function()return Config.CameraFOVEnabled end,function(v)Config.CameraFOVEnabled=v end)
	makeSlider(left,"Strength",398,.02,.85,function()return Config.AimStrength end,function(v)Config.AimStrength=v end)
	makeSlider(left,"FOV radius",462,40,500,function()return Config.AimRadius end,function(v)Config.AimRadius=v end)
	makeSlider(left,"FOV opacity",526,.05,1,function()return Config.FOVCircleOpacity end,function(v)Config.FOVCircleOpacity=v end)
	makeSlider(left,"FOV thickness",590,.5,4,function()return Config.FOVCircleThickness end,function(v)Config.FOVCircleThickness=v end)
	makeSlider(left,"FOV color hue",654,0,1,function()return Config.FOVCircleHue end,function(v)Config.FOVCircleHue=v end)
	makeSlider(left,"Prediction time",718,0,.2,function()return Config.PredictionTime end,function(v)Config.PredictionTime=v end)
	makeSlider(left,"Max range",782,100,1800,function()return Config.MaxAimDistance end,function(v)Config.MaxAimDistance=v end)
	makeSlider(left,"Camera FOV",846,50,130,function()return Config.CameraFOV end,function(v)Config.CameraFOV=v end)
	local hitPart=button(left,"HIT PART: "..string.upper(Config.HitPart),UDim2.new(1,-20,0,42),UDim2.fromOffset(10,910),"row")
	hitPart.Activated:Connect(function()local modes={"Body","Head","Random"};local index=table.find(modes,Config.HitPart)or 1;Config.HitPart=modes[index%#modes+1];hitPart.Text="HIT PART: "..string.upper(Config.HitPart);State.lockedParts={};State.dirty=true end)
	UI.aimTarget=label(right,"No target",UDim2.new(1,-24,0,36),UDim2.fromOffset(12,40),Enum.Font.GothamBlack,"text",18);UI.aimTarget.TextXAlignment=Enum.TextXAlignment.Center
	local reticle=Instance.new("Frame");reticle.AnchorPoint=Vector2.new(.5,.5);reticle.Position=UDim2.new(.5,0,.48,0);reticle.Size=UDim2.fromOffset(132,132);reticle.BackgroundTransparency=1;reticle.Parent=right;corner(reticle,66);outline(reticle,Theme.accent2,.18,2)
	local h=Instance.new("Frame");h.Size=UDim2.fromOffset(160,2);h.Position=UDim2.new(.5,-80,.48,-1);h.BackgroundColor3=Theme.accent2;h.BorderSizePixel=0;h.Parent=right
	local v=Instance.new("Frame");v.Size=UDim2.fromOffset(2,160);v.Position=UDim2.new(.5,-1,.48,-80);v.BackgroundColor3=Theme.accent2;v.BorderSizePixel=0;v.Parent=right
	UI.aimReason=label(right,"Enable Aim Assist",UDim2.new(1,-30,0,72),UDim2.new(0,15,1,-112),Enum.Font.Gotham,"muted",11);UI.aimReason.TextWrapped=true;UI.aimReason.TextXAlignment=Enum.TextXAlignment.Center
end
local function buildVRAim()
	local page=newPage("VRAim")
	pageHeader(page,"VR Aim Assist","Code-protected muzzle assistance. Every VR toggle starts off each execution.","accent2")
	local left=scrollingPanel(page,UDim2.new(.58,-20,1,-82),UDim2.fromOffset(14,70),500)
	local right=panel(page,UDim2.new(.42,-8,1,-82),UDim2.new(.58,0,0,70),"panel")
	UI.refreshVR=makeToggle(left,"VR player assist",10,function()return VRConfig.Enabled end,function(v)VRConfig.Enabled=v end)
	makeToggle(left,"Sticky VR",58,function()return VRConfig.Sticky end,function(v)VRConfig.Sticky=v end)
	makeToggle(left,"VR wall check",106,function()return VRConfig.WallCheck end,function(v)VRConfig.WallCheck=v end)
	makeToggle(left,"VR team check",154,function()return VRConfig.TeamCheck end,function(v)VRConfig.TeamCheck=v end)
	makeSlider(left,"Strength",206,.02,.8,function()return VRConfig.Strength end,function(v)VRConfig.Strength=v end)
	makeSlider(left,"Cone",270,4,35,function()return VRConfig.Cone end,function(v)VRConfig.Cone=v end)
	makeSlider(left,"Range",334,40,900,function()return VRConfig.MaxDistance end,function(v)VRConfig.MaxDistance=v end)
	local visor=panel(right,UDim2.fromOffset(150,94),UDim2.new(.5,-75,0,62),"row");corner(visor,28);outline(visor,Theme.accent2,.18,2)
	local leftLens=panel(visor,UDim2.fromOffset(52,38),UDim2.fromOffset(17,26),"bg");local rightLens=panel(visor,UDim2.fromOffset(52,38),UDim2.fromOffset(81,26),"bg")
	UI.vrStatus=label(right,"LOCKED",UDim2.new(1,-24,0,36),UDim2.fromOffset(12,180),Enum.Font.GothamBlack,"muted",19);UI.vrStatus.TextXAlignment=Enum.TextXAlignment.Center
	local vrInfo=label(right,"Open this category and enter one creator code to enable the session-only controls.",UDim2.new(1,-32,0,70),UDim2.fromOffset(16,226),Enum.Font.Gotham,"muted",10);vrInfo.TextWrapped=true;vrInfo.TextXAlignment=Enum.TextXAlignment.Center
end
local function buildVisuals()
	local page=newPage("Visuals")
	pageHeader(page,"Visuals","Rig-safe highlights, labels, roles, distance, VR badges, and skeletons.","accent2")
	local left=scrollingPanel(page,UDim2.new(.58,-20,1,-82),UDim2.fromOffset(14,70),930)
	UI.refreshESP=makeToggle(left,"Master ESP",10,function()return Config.ESPEnabled end,function(v)Config.ESPEnabled=v end)
	makeToggle(left,"Highlight",58,function()return Config.HighlightESP end,function(v)Config.HighlightESP=v end)
	makeToggle(left,"Nameplates",106,function()return Config.NameESP end,function(v)Config.NameESP=v end)
	makeToggle(left,"Distance",154,function()return Config.DistanceESP end,function(v)Config.DistanceESP=v end)
	makeToggle(left,"Known roles",202,function()return Config.RoleESP end,function(v)Config.RoleESP=v end)
	makeToggle(left,"VR badge",250,function()return Config.VRESP end,function(v)Config.VRESP=v end)
	makeToggle(left,"Skeleton",298,function()return Config.SkeletonESP end,function(v)Config.SkeletonESP=v end)
	makeToggle(left,"2D boxes",346,function()return Config.BoxESP end,function(v)Config.BoxESP=v end)
	makeToggle(left,"Screen tracers",394,function()return Config.TracerESP end,function(v)Config.TracerESP=v end)
	makeToggle(left,"Health bars",442,function()return Config.HealthESP end,function(v)Config.HealthESP=v end)
	makeToggle(left,"ESP team filter",490,function()return Config.ESPTeamCheck end,function(v)Config.ESPTeamCheck=v end)
	makeToggle(left,"Through walls",538,function()return Config.ThroughWalls end,function(v)Config.ThroughWalls=v end)
	makeSlider(left,"ESP range",590,100,2200,function()return Config.ESPMaxDistance end,function(v)Config.ESPMaxDistance=v end)
	makeSlider(left,"Text size",654,10,24,function()return Config.ESPTextSize end,function(v)Config.ESPTextSize=v end)
	makeSlider(left,"Fill visibility",718,.05,.9,function()return Config.ESPFill end,function(v)Config.ESPFill=v end)
	makeSlider(left,"Enemy color hue",782,0,1,function()return Config.EnemyColorHue end,function(v)Config.EnemyColorHue=v end)
	makeSlider(left,"Teammate color hue",846,0,1,function()return Config.TeammateColorHue end,function(v)Config.TeammateColorHue=v end)
	local right=panel(page,UDim2.new(.42,-8,1,-82),UDim2.new(.58,0,0,70),"panel")
	label(right,"LIVE PREVIEW",UDim2.new(1,-24,0,20),UDim2.fromOffset(12,13),Enum.Font.GothamBold,"accent2",10)
	local body=panel(right,UDim2.fromOffset(112,198),UDim2.new(.5,-56,.52,-80),"row");corner(body,44);outline(body,Theme.accent2,.1,2)
	local head=panel(body,UDim2.fromOffset(70,70),UDim2.new(.5,-35,0,-30),"row");corner(head,35);outline(head,Theme.accent2,.1,2)
	local preview=label(right,"PLAYER [VR]\nUNKNOWN | 42st",UDim2.new(1,-24,0,48),UDim2.fromOffset(12,45),Enum.Font.GothamBold,"accent2",12);preview.TextXAlignment=Enum.TextXAlignment.Center
end
local function buildWords()
	local page=newPage("Words")
	pageHeader(page,"The Final Letter","Global keyboard capture with chat exclusion and instant recommendations.","accent2")
	UI.wordLabel=label(page,"TYPE LETTERS ANYWHERE",UDim2.new(1,-28,0,42),UDim2.fromOffset(14,62),Enum.Font.GothamBlack,"accent2",18);UI.wordLabel.TextXAlignment=Enum.TextXAlignment.Center
	UI.wordList=panel(page,UDim2.new(1,-28,1,-126),UDim2.fromOffset(14,112),"panel")
	local layout=Instance.new("UIListLayout");layout.Padding=UDim.new(0,6);layout.Parent=UI.wordList
	UI.wordButtons={};for index=1,6 do local b=button(UI.wordList,"-",UDim2.new(1,-16,0,42),nil,"row");b.LayoutOrder=index;UI.wordButtons[index]=b end
end
local function buildUtilities()
	local performance=newPage("Performance")
	pageHeader(performance,"Performance","Local render profiles. No map objects are deleted.","accent2")
	local perfCard=panel(performance,UDim2.new(1,-28,0,106),UDim2.fromOffset(14,76),"panel")
	UI.fpsLabel=label(perfCard,"0 FPS",UDim2.fromOffset(180,48),UDim2.fromOffset(18,12),Enum.Font.GothamBlack,"accent2",30)
	label(perfCard,"LIVE PERFORMANCE",UDim2.fromOffset(180,18),UDim2.fromOffset(20,63),Enum.Font.GothamBold,"muted",9)
	UI.performanceMode=label(perfCard,"MODE: "..string.upper(Config.PerformanceMode),UDim2.fromOffset(220,32),UDim2.new(1,-240,.5,-16),Enum.Font.GothamBold,"text",14);UI.performanceMode.TextXAlignment=Enum.TextXAlignment.Right
	local modeCard=panel(performance,UDim2.new(1,-28,0,92),UDim2.fromOffset(14,196),"panel")
	for index,name in ipairs({"Off","Low","Balanced","Aggressive"})do local mode=name;local b=button(modeCard,string.upper(mode),UDim2.new(.25,-10,0,48),UDim2.new((index-1)*.25,8,0,22),"row");b.Activated:Connect(function()Config.PerformanceMode=mode;UI.performanceMode.Text="MODE: "..string.upper(mode);State.dirty=true;for _,o in ipairs(Lighting:GetChildren())do if o:IsA("PostEffect")then o.Enabled=mode=="Off"end end;Lighting.GlobalShadows=mode=="Off"end)end
	local perfInfo=panel(performance,UDim2.new(1,-28,1,-318),UDim2.fromOffset(14,302),"panel")
	label(perfInfo,"LOW",UDim2.fromOffset(100,22),UDim2.fromOffset(14,18),Enum.Font.GothamBold,"accent2",11);label(perfInfo,"Post-processing only",UDim2.new(1,-126,0,22),UDim2.fromOffset(112,18),Enum.Font.Gotham,"text",11)
	label(perfInfo,"BALANCED",UDim2.fromOffset(100,22),UDim2.fromOffset(14,53),Enum.Font.GothamBold,"accent",11);label(perfInfo,"Post effects and shadows",UDim2.new(1,-126,0,22),UDim2.fromOffset(112,53),Enum.Font.Gotham,"text",11)

	local themes=newPage("Themes")
	pageHeader(themes,"Interface Studio","Choose a color system and a structural layout inspired by your references.","accent")
	for index,name in ipairs({"DarkDock","Skeet","Emerald"})do
		local themeName=name;local previewTheme=Themes[name]
		local chosenTheme=themeName
		local card=panel(themes,UDim2.new(1/3,-16,0,230),UDim2.new((index-1)/3,10,0,76),"panel")
		local stripe=Instance.new("Frame");stripe.Size=UDim2.new(1,0,0,5);stripe.BackgroundColor3=previewTheme.accent;stripe.BorderSizePixel=0;stripe.Parent=card;corner(stripe,3)
		local mini=Instance.new("Frame");mini.Size=UDim2.new(1,-20,0,120);mini.Position=UDim2.fromOffset(10,18);mini.BackgroundColor3=previewTheme.bg;mini.BorderSizePixel=0;mini.Parent=card;corner(mini,9)
		local miniTop=Instance.new("Frame");miniTop.Size=UDim2.new(1,0,0,28);miniTop.BackgroundColor3=previewTheme.panel;miniTop.BorderSizePixel=0;miniTop.Parent=mini;corner(miniTop,9)
		for row=0,2 do local strip=Instance.new("Frame");strip.Size=UDim2.new(1,-16,0,20);strip.Position=UDim2.fromOffset(8,36+row*25);strip.BackgroundColor3=previewTheme.row;strip.BorderSizePixel=0;strip.Parent=mini;corner(strip,6)end
		label(card,string.upper(name),UDim2.new(1,-20,0,24),UDim2.fromOffset(10,146),Enum.Font.GothamBlack,"text",13).TextXAlignment=Enum.TextXAlignment.Center
		local apply=button(card,"APPLY THEME",UDim2.new(1,-20,0,36),UDim2.new(0,10,1,-44),"row");apply.Activated:Connect(function()UI.applyTheme(chosenTheme)end)
	end
	label(themes,"INTERFACE LAYOUT",UDim2.new(1,-28,0,20),UDim2.fromOffset(14,316),Enum.Font.GothamBold,"muted",10)
	local layoutData={
		{"Newgen","Sidebar workspace"},
		{"Lynen","Floating module rails"},
		{"Horizon","Wide canvas and bottom dock"},
	}
	for index,data in ipairs(layoutData)do
		local layoutName=data[1]
		local chosenLayout=layoutName
		local card=panel(themes,UDim2.new(1/3,-16,0,138),UDim2.new((index-1)/3,10,0,342),"panel")
		local preview=Instance.new("Frame");preview.Size=UDim2.new(1,-20,0,65);preview.Position=UDim2.fromOffset(10,10);preview.BackgroundColor3=Theme.bg;preview.BorderSizePixel=0;preview.Parent=card;corner(preview,8)
		if layoutName=="Newgen"then local side=Instance.new("Frame");side.Size=UDim2.new(0,28,1,0);side.BackgroundColor3=Theme.panel;side.BorderSizePixel=0;side.Parent=preview;local body=Instance.new("Frame");body.Size=UDim2.new(1,-34,1,-10);body.Position=UDim2.fromOffset(32,5);body.BackgroundColor3=Theme.row;body.BorderSizePixel=0;body.Parent=preview;corner(body,5)
		elseif layoutName=="Lynen"then local left=Instance.new("Frame");left.Size=UDim2.new(0,27,1,-8);left.Position=UDim2.fromOffset(2,4);left.BackgroundColor3=Theme.panel;left.BorderSizePixel=0;left.Parent=preview;local middle=Instance.new("Frame");middle.Size=UDim2.new(1,-68,1,-4);middle.Position=UDim2.fromOffset(34,2);middle.BackgroundColor3=Theme.row;middle.BorderSizePixel=0;middle.Parent=preview;local right=Instance.new("Frame");right.Size=UDim2.new(0,27,1,-8);right.Position=UDim2.new(1,-29,0,4);right.BackgroundColor3=Theme.panel;right.BorderSizePixel=0;right.Parent=preview
		else local canvas=Instance.new("Frame");canvas.Size=UDim2.new(1,-8,1,-22);canvas.Position=UDim2.fromOffset(4,3);canvas.BackgroundColor3=Theme.row;canvas.BorderSizePixel=0;canvas.Parent=preview;corner(canvas,5);local dock=Instance.new("Frame");dock.Size=UDim2.new(.62,0,0,14);dock.Position=UDim2.new(.19,0,1,-17);dock.BackgroundColor3=Theme.panel;dock.BorderSizePixel=0;dock.Parent=preview;corner(dock,6)end
		label(card,layoutName.." / "..data[2],UDim2.new(1,-20,0,22),UDim2.fromOffset(10,80),Enum.Font.GothamBold,"text",10).TextXAlignment=Enum.TextXAlignment.Center
		local apply=button(card,"USE LAYOUT",UDim2.new(1,-20,0,30),UDim2.new(0,10,1,-37),"row");apply.Activated:Connect(function()UI.applyLayout(chosenLayout,true)end)
	end

	local colors=newPage("Colors")
	pageHeader(colors,"Color Studio","Blend a custom hue into the active theme background.","accent2")
	local wheel=panel(colors,UDim2.fromOffset(300,300),UDim2.fromOffset(18,82),"panel")
	local colorPreview=panel(wheel,UDim2.fromOffset(106,106),UDim2.new(.5,-53,.5,-53),"row");colorPreview:SetAttribute("ThemeLocked",true);colorPreview.BackgroundColor3=Color3.fromHSV(Config.BackgroundHue,Config.BackgroundSaturation,Config.BackgroundValue);corner(colorPreview,53);outline(colorPreview,Color3.new(1,1,1),.25,2)
	local previewText=label(colorPreview,"LIVE\nCOLOR",UDim2.fromScale(1,1),nil,Enum.Font.GothamBlack,"text",12);previewText.TextXAlignment=Enum.TextXAlignment.Center;previewText.TextYAlignment=Enum.TextYAlignment.Center
	for index=1,20 do local hue=(index-1)/20;local h=hue;local angle=h*math.pi*2-math.pi/2;local swatch=button(wheel,"",UDim2.fromOffset(32,32),UDim2.fromOffset(134+math.cos(angle)*116,134+math.sin(angle)*116),"row");swatch:SetAttribute("ThemeLocked",true);swatch.BackgroundColor3=Color3.fromHSV(h,.82,1);corner(swatch,16);swatch.Activated:Connect(function()Config.CustomBackground=true;Config.BackgroundHue=h;local selected=Color3.fromHSV(h,Config.BackgroundSaturation,Config.BackgroundValue);colorPreview.BackgroundColor3=selected;main.BackgroundColor3=Theme.bg:Lerp(selected,Config.BackgroundIntensity);State.dirty=true end)end
	local colorInfo=panel(colors,UDim2.new(1,-340,0,220),UDim2.fromOffset(326,82),"panel")
	label(colorInfo,"BACKGROUND BLEND",UDim2.new(1,-24,0,22),UDim2.fromOffset(12,14),Enum.Font.GothamBold,"muted",10)
	makeToggle(colorInfo,"Custom background",44,function()return Config.CustomBackground end,function(v)Config.CustomBackground=v;if not v then main.BackgroundColor3=Theme.bg end end)
	makeSlider(colorInfo,"Intensity",96,0,1,function()return Config.BackgroundIntensity end,function(v)Config.BackgroundIntensity=v;if Config.CustomBackground then local selected=Color3.fromHSV(Config.BackgroundHue,Config.BackgroundSaturation,Config.BackgroundValue);main.BackgroundColor3=Theme.bg:Lerp(selected,v)end end)
	local resetColor=button(colorInfo,"RESET COLOR",UDim2.new(1,-24,0,40),UDim2.new(0,12,1,-52),"row");resetColor.Activated:Connect(function()Config.CustomBackground=false;main.BackgroundColor3=Theme.bg;State.dirty=true end)

	local session=newPage("Session")
	pageHeader(session,"Session","Server-authoritative session actions with cooldown feedback.","accent2")
	UI.sessionStatus=label(session,"Session actions ready",UDim2.new(1,-28,0,30),UDim2.fromOffset(14,73),Enum.Font.GothamBold,"muted",11)
	local hopCard=panel(session,UDim2.new(.5,-20,1,-130),UDim2.fromOffset(14,112),"panel");local resetCard=panel(session,UDim2.new(.5,-20,1,-130),UDim2.new(.5,6,0,112),"panel")
	label(hopCard,"HOP SERVER",UDim2.new(1,-24,0,30),UDim2.fromOffset(12,18),Enum.Font.GothamBlack,"accent2",17);local hopInfo=label(hopCard,"Find another live server or create a fresh instance.",UDim2.new(1,-24,0,60),UDim2.fromOffset(12,59),Enum.Font.Gotham,"muted",10);hopInfo.TextWrapped=true
	label(resetCard,"RESET CHARACTER",UDim2.new(1,-24,0,30),UDim2.fromOffset(12,18),Enum.Font.GothamBlack,"accent",17);local resetInfo=label(resetCard,"Eliminate and respawn only your current character.",UDim2.new(1,-24,0,60),UDim2.fromOffset(12,59),Enum.Font.Gotham,"muted",10);resetInfo.TextWrapped=true
	local hop=button(hopCard,"HOP SERVER",UDim2.new(1,-24,0,48),UDim2.new(0,12,1,-60),"accent2");local reset=button(resetCard,"RESET CHARACTER",UDim2.new(1,-24,0,48),UDim2.new(0,12,1,-60),"accent")
	hop.Activated:Connect(function()hop.Text="SEARCHING...";if Remotes.Hop then Remotes.Hop:FireServer()else UI.sessionStatus.Text="Server unavailable"end;task.delay(12,function()if hop.Parent then hop.Text="HOP SERVER"end end)end)
	reset.Activated:Connect(function()reset.Text="RESETTING...";if Remotes.Reset then Remotes.Reset:FireServer()else UI.sessionStatus.Text="Server unavailable"end;task.delay(5,function()if reset.Parent then reset.Text="RESET CHARACTER"end end)end)
	local playersPage=newPage("Players");pageHeader(playersPage,"Players","Inspect connected players, known roles, and device status.","accent")
	UI.playerList=Instance.new("ScrollingFrame");UI.playerList.Size=UDim2.new(1,-28,1,-84);UI.playerList.Position=UDim2.fromOffset(14,68);UI.playerList.BackgroundColor3=Theme.panel;UI.playerList.BorderSizePixel=0;UI.playerList.AutomaticCanvasSize=Enum.AutomaticSize.Y;UI.playerList.CanvasSize=UDim2.new();UI.playerList.Parent=playersPage;corner(UI.playerList,10);local listLayout=Instance.new("UIListLayout");listLayout.Padding=UDim.new(0,6);listLayout.Parent=UI.playerList;UI.playerRows={}
end

buildHub();buildHome();buildAim();buildVRAim();buildVisuals();buildWords();buildUtilities()
if State.vrUnlocked then
	UI.vrStatus.Text="UNLOCKED"
	UI.vrStatus.TextColor3=Theme.accent2
	if UI.vrNavBadge then UI.vrNavBadge.BackgroundColor3=Color3.fromRGB(52,211,153)end
end

-- VR access modal
do
	local gate=Instance.new("Frame")
	gate.Size=UDim2.fromScale(1,1)
	gate.BackgroundColor3=Color3.fromRGB(8,5,20)
	gate.BackgroundTransparency=.08
	gate.BorderSizePixel=0
	gate.Visible=false
	gate.ZIndex=300
	gate.Parent=main
	local gateGradient=Instance.new("UIGradient")
	gateGradient.Color=ColorSequence.new(Color3.fromRGB(72,37,135),Color3.fromRGB(12,58,70))
	gateGradient.Rotation=25
	gateGradient.Parent=gate

	local card=Instance.new("CanvasGroup")
	card.AnchorPoint=Vector2.new(.5,.5)
	card.Position=UDim2.fromScale(.5,.5)
	card.Size=UDim2.fromOffset(450,455)
	card.BackgroundColor3=Color3.fromRGB(38,31,67)
	card.BorderSizePixel=0
	card.ZIndex=301
	card.Parent=gate
	corner(card,22)
	outline(card,Theme.accent2,.14,2)
	shadow(card,.34)
	local cardScale=Instance.new("UIScale");cardScale.Parent=card

	local title=label(card,"UNLOCK VR AIM",UDim2.new(1,-40,0,32),UDim2.fromOffset(20,20),Enum.Font.GothamBlack,"text",20);title.TextXAlignment=Enum.TextXAlignment.Center;title.ZIndex=302
	local info=label(card,"Enter one creator code to open the session-only VR controls.",UDim2.new(1,-50,0,40),UDim2.fromOffset(25,55),Enum.Font.Gotham,"muted",10);info.TextWrapped=true;info.TextXAlignment=Enum.TextXAlignment.Center;info.ZIndex=302

	local slotRow=Instance.new("Frame");slotRow.Size=UDim2.fromOffset(272,54);slotRow.Position=UDim2.new(.5,-136,0,105);slotRow.BackgroundTransparency=1;slotRow.ZIndex=302;slotRow.Parent=card
	local slotLayout=Instance.new("UIListLayout");slotLayout.FillDirection=Enum.FillDirection.Horizontal;slotLayout.Padding=UDim.new(0,8);slotLayout.Parent=slotRow
	local slots={}
	for index=1,4 do local slot=label(slotRow,"",UDim2.fromOffset(62,54),nil,Enum.Font.GothamBlack,"text",23);slot.BackgroundTransparency=0;slot.BackgroundColor3=Color3.fromRGB(63,56,94);slot.TextXAlignment=Enum.TextXAlignment.Center;slot.ZIndex=303;corner(slot,12);outline(slot,Theme.accent2,.65,1.5);slots[index]=slot end

	local input=Instance.new("TextBox");input.Size=UDim2.fromOffset(272,54);input.Position=UDim2.new(.5,-136,0,105);input.BackgroundTransparency=1;input.ClearTextOnFocus=false;input.Text="";input.TextTransparency=1;input.ZIndex=304;input.Parent=card
	local status=label(card,"4 DIGITS REQUIRED",UDim2.new(1,-40,0,22),UDim2.fromOffset(20,165),Enum.Font.GothamBold,"muted",10);status.TextXAlignment=Enum.TextXAlignment.Center;status.ZIndex=302
	local scan=Instance.new("Frame");scan.Size=UDim2.new(1,-50,0,4);scan.Position=UDim2.fromOffset(25,192);scan.BackgroundColor3=Color3.fromRGB(72,66,101);scan.BorderSizePixel=0;scan.ZIndex=302;scan.Parent=card;corner(scan,2)
	local scanFill=Instance.new("Frame");scanFill.Size=UDim2.fromScale(0,1);scanFill.BackgroundColor3=Theme.accent2;scanFill.BorderSizePixel=0;scanFill.ZIndex=303;scanFill.Parent=scan;corner(scanFill,2)

	local keypad=Instance.new("Frame");keypad.Size=UDim2.fromOffset(312,146);keypad.Position=UDim2.new(.5,-156,0,211);keypad.BackgroundTransparency=1;keypad.ZIndex=302;keypad.Parent=card
	local keyLayout=Instance.new("UIGridLayout");keyLayout.CellPadding=UDim2.fromOffset(7,7);keyLayout.CellSize=UDim2.fromOffset(99,31);keyLayout.FillDirectionMaxCells=3;keyLayout.Parent=keypad
	local entered=""
	local localCodes={ ["2015"]=true,["2014"]=true,["8591"]=true,["7878"]=true }
	local function render()
		for index,slot in ipairs(slots)do slot.Text=index<=#entered and"*"or"" end
		TweenService:Create(scanFill,TweenInfo.new(.15),{Size=UDim2.fromScale(#entered/4,1)}):Play()
	end
	local function setCode(value)entered=tostring(value or""):gsub("%D",""):sub(1,4);if input.Text~=entered then input.Text=entered end;render()end
	for order,keyValue in ipairs({"1","2","3","4","5","6","7","8","9","CLR","0","<"})do local value=keyValue;local key=button(keypad,value,UDim2.fromOffset(99,31),nil,value=="CLR"and"accent"or"row");key.LayoutOrder=order;key.ZIndex=303;key.Activated:Connect(function()if value=="CLR"then setCode("")elseif value=="<"then setCode(entered:sub(1,math.max(#entered-1,0)))elseif#entered<4 then setCode(entered..value)end end)end

	local verify=button(card,"VERIFY ACCESS",UDim2.new(1,-144,0,44),UDim2.fromOffset(20,390),"accent");verify.ZIndex=303
	local cancel=button(card,"CANCEL",UDim2.fromOffset(96,44),UDim2.new(1,-116,0,390),"row");cancel.ZIndex=303
	local function submit()
		if#entered~=4 then status.Text="ENTER ALL FOUR DIGITS";return end
		if not localCodes[entered]then status.Text="INCORRECT CODE";status.TextColor3=Color3.fromRGB(248,75,90);setCode("");return end
		status.Text="VERIFYING...";status.TextColor3=Theme.accent2
		local accepted=true;if Remotes.VerifyVR and Remotes.VerifyVR:IsA("RemoteFunction")then local ok,result=pcall(function()return Remotes.VerifyVR:InvokeServer(entered)end);accepted=not ok or result==true end
		if accepted then State.vrUnlocked=true;UI.vrStatus.Text="UNLOCKED";UI.vrStatus.TextColor3=Theme.accent2;if UI.vrNavBadge then UI.vrNavBadge.BackgroundColor3=Color3.fromRGB(52,211,153)end;status.Text="ACCESS GRANTED";scanFill.BackgroundColor3=Color3.fromRGB(52,211,153);if UI.notify then UI.notify("VR Aim Assist unlocked for this session",true)end;task.wait(.35);gate.Visible=false;showPage("VRAim")end
	end
	verify.Activated:Connect(submit);cancel.Activated:Connect(function()gate.Visible=false end);input:GetPropertyChangedSignal("Text"):Connect(function()setCode(input.Text)end);input.FocusLost:Connect(function(enter)if enter then submit()end end)
	UI.openVRGate=function()gate.Visible=true;card.GroupTransparency=1;cardScale.Scale=.9;setCode("");status.Text="4 DIGITS REQUIRED";status.TextColor3=Theme.muted;scanFill.BackgroundColor3=Theme.accent2;TweenService:Create(card,TweenInfo.new(.2),{GroupTransparency=0}):Play();TweenService:Create(cardScale,TweenInfo.new(.3,Enum.EasingStyle.Back),{Scale=1}):Play();if not isMobile then task.defer(function()input:CaptureFocus()end)end end
end

UI.applyLayout(Config.LayoutStyle,false);showPage("Hub")

-- One resolver is used by both aim and ESP.
local function characterFor(target)
	local model=target.Character
	for _,folderName in ipairs({"VRCharacters","VRPlayers","VRRigs"})do local folder=Workspace:FindFirstChild(folderName);if folder then local vrModel=folder:FindFirstChild(target.Name)or folder:FindFirstChild(tostring(target.UserId));if vrModel and vrModel:IsA("Model")then model=vrModel end end end
	return model
end
local function rootPart(model)
	if not model then return nil end
	return model:FindFirstChild("HumanoidRootPart",true)or model:FindFirstChild("VRRoot",true)or model:FindFirstChild("UpperTorso",true)or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart",true)
end
local function living(target)
	local model=characterFor(target);local humanoid=model and model:FindFirstChildWhichIsA("Humanoid",true);if not humanoid and target.Character then humanoid=target.Character:FindFirstChildWhichIsA("Humanoid",true)end;local rootPartValue=rootPart(model)
	if model and rootPartValue and(not humanoid or humanoid.Health>0)then return model,humanoid,rootPartValue end;return nil,nil,nil
end
local function targetPart(target,vrOnly)
	local model=living(target);if not model then return nil end
	local mode=vrOnly and"Head"or Config.HitPart
	if mode=="Random"then State.lockedParts[target]=State.lockedParts[target]or(math.random(1,2)==1 and"Head"or"Body");mode=State.lockedParts[target]end
	local names=mode=="Head"and{"Head","VRHead"}or{"UpperTorso","Torso","HumanoidRootPart"}
	for _,name in ipairs(names)do local part=model:FindFirstChild(name,true);if part and part:IsA("BasePart")then return part end end;return rootPart(model)
end
local function eligible(target,vrOnly)
	local teamCheck=vrOnly and VRConfig.TeamCheck or Config.TeamCheck
	if target==player or(vrOnly and not target:GetAttribute("UsingVR"))or(teamCheck and player.Team and target.Team and player.Team==target.Team)then return false end
	return living(target)~=nil
end
local rayParams=RaycastParams.new();rayParams.FilterType=Enum.RaycastFilterType.Exclude;rayParams.IgnoreWater=true
local function visible(origin,position,target)
	local filter={};if player.Character then table.insert(filter,player.Character)end;rayParams.FilterDescendantsInstances=filter;local hit=Workspace:Raycast(origin,position-origin,rayParams);local model=characterFor(target);return not hit or(model and hit.Instance:IsDescendantOf(model))
end
local function predicted(part)
	local position=part.Position;if Config.Prediction then local velocity=part.AssemblyLinearVelocity;if velocity.Magnitude>150 then velocity=velocity.Unit*150 end;position+=velocity*Config.PredictionTime end;return position
end

local function findCameraTarget()
	if not camera then return nil end;local best,bestScore=nil,Config.AimRadius;local _,_,myRoot=living(player)
	for _,target in ipairs(Players:GetPlayers())do if eligible(target,false)then local part=targetPart(target,false);if part and myRoot and(part.Position-myRoot.Position).Magnitude<=Config.MaxAimDistance then local point,onScreen=camera:WorldToViewportPoint(predicted(part));if onScreen and point.Z>0 then local score=(Vector2.new(point.X,point.Y)-camera.ViewportSize/2).Magnitude;if score<bestScore and visible(camera.CFrame.Position,part.Position,target)then best=target;bestScore=score end end end end end;return best
end
local function validCameraTarget(target)
	if not target or not eligible(target,false)or not camera then return false end
	local part=targetPart(target,false);if not part then return false end
	local point,onScreen=camera:WorldToViewportPoint(predicted(part));local _,_,myRoot=living(player)
	local valid=onScreen and point.Z>0 and myRoot and(part.Position-myRoot.Position).Magnitude<=Config.MaxAimDistance
		and(Vector2.new(point.X,point.Y)-camera.ViewportSize/2).Magnitude<=Config.AimRadius*(Config.StickyAim and 1.75 or 1)
		and visible(camera.CFrame.Position,part.Position,target)
	if valid then State.lastTargetSeen=os.clock();return true end
	return Config.StickyAim and os.clock()-State.lastTargetSeen<.45
end
local fovCircle=panel(gui,UDim2.fromOffset(1,1),nil,"bg");fovCircle.AnchorPoint=Vector2.new(.5,.5);fovCircle.BackgroundTransparency=1;fovCircle.Visible=false;corner(fovCircle,1000);local fovStroke=outline(fovCircle,Color3.fromHSV(Config.FOVCircleHue,.75,1),1-Config.FOVCircleOpacity,Config.FOVCircleThickness);UI.fovStroke=fovStroke
local marker=panel(gui,UDim2.fromOffset(22,22),nil,"bg");marker.AnchorPoint=Vector2.new(.5,.5);marker.BackgroundTransparency=1;marker.Visible=false;corner(marker,11);outline(marker,Theme.accent2,0,2)
UserInputService.InputBegan:Connect(function(input)if input.UserInputType==Enum.UserInputType.MouseButton2 or input.KeyCode==Enum.KeyCode.ButtonL2 then if Config.AimEnabled then State.aimHeld=true;State.target=nil end end end)
UserInputService.InputEnded:Connect(function(input)if input.UserInputType==Enum.UserInputType.MouseButton2 or input.KeyCode==Enum.KeyCode.ButtonL2 then State.aimHeld=false;State.target=nil end end)
RunService:BindToRenderStep("StaticsAim",Enum.RenderPriority.Camera.Value+1,function(dt)
	if not camera then return end;camera.FieldOfView=Config.CameraFOVEnabled and Config.CameraFOV or originalFOV;fovCircle.Size=UDim2.fromOffset(Config.AimRadius*2,Config.AimRadius*2);fovCircle.Position=UDim2.fromScale(.5,.5);fovCircle.Visible=Config.AimEnabled and Config.ShowFOVCircle and not State.menuOpen;fovStroke.Transparency=1-Config.FOVCircleOpacity;fovStroke.Thickness=Config.FOVCircleThickness;fovStroke.Color=Color3.fromHSV(Config.FOVCircleHue,.75,1)
	if not Config.AimEnabled or not State.aimHeld then marker.Visible=false;return end;if State.target and not validCameraTarget(State.target)then State.target=nil end;if not State.target then State.target=findCameraTarget();if State.target then State.lastTargetSeen=os.clock()end end;local part=State.target and targetPart(State.target,false);if not part then marker.Visible=false;return end;local point,onScreen=camera:WorldToViewportPoint(predicted(part));if not onScreen then marker.Visible=false;return end;marker.Visible=true;marker.Position=UDim2.fromOffset(point.X,point.Y)
	if Config.CameraAssist and not isVR then local desired=CFrame.lookAt(camera.CFrame.Position,predicted(part),camera.CFrame.UpVector);camera.CFrame=camera.CFrame:Lerp(desired,math.clamp(1-math.exp(-(2.5+Config.AimStrength*25)*dt),0,.88))end
end)

-- Weapon direction adapters.
local lastAdapterCall=0
local function normalize(origin,direction)
	if typeof(origin)=="Instance"then if origin:IsA("Attachment")then direction=direction or origin.WorldCFrame.LookVector;origin=origin.WorldPosition elseif origin:IsA("BasePart")then direction=direction or origin.CFrame.LookVector;origin=origin.Position end elseif typeof(origin)=="CFrame"then direction=direction or origin.LookVector;origin=origin.Position end
	return origin,direction
end
local function correctedDirection(origin,raw,vrOnly)
	local strength=vrOnly and VRConfig.Strength or Config.AimStrength;local cone=math.rad(vrOnly and VRConfig.Cone or math.clamp(Config.AimRadius/math.max(camera.ViewportSize.X,1)*Config.CameraFOV*1.6,3,45));local range=vrOnly and VRConfig.MaxDistance or Config.MaxAimDistance;local best,bestScore=nil,math.huge
	for _,target in ipairs(Players:GetPlayers())do if eligible(target,vrOnly)then local part=targetPart(target,vrOnly);if part then local position=predicted(part);local offset=position-origin;if offset.Magnitude>0 and offset.Magnitude<=range then local direction=offset.Unit;local dot=math.clamp(raw.Unit:Dot(direction),-1,1);local wallCheck=vrOnly and VRConfig.WallCheck or true;if dot>=math.cos(cone)and(not wallCheck or visible(origin,position,target))then local score=(1-dot)*1000+offset.Magnitude*.002;if score<bestScore then best=direction;bestScore=score;State.weaponTarget=target end end end end end end
	return best and raw.Unit:Lerp(best,math.clamp(strength,0,.9)).Unit or raw.Unit
end
local function installAdapter(name,vrOnly)
	local old=playerScripts:FindFirstChild(name);if old then old:Destroy()end;local adapter=Instance.new("BindableFunction");adapter.Name=name;adapter.OnInvoke=function(origin,raw)lastAdapterCall=os.clock();local o,d=normalize(origin,raw);if not o or not d or d.Magnitude==0 then return raw end;if vrOnly then if not State.vrUnlocked or not VRConfig.Enabled then return d.Unit end else if not Config.AimEnabled or not State.aimHeld then return d.Unit end end;return correctedDirection(o,d,vrOnly)end;adapter.Parent=playerScripts
end
installAdapter("StaticsAimDirection",false);installAdapter("StaticsVRAimDirection",true)

-- ESP lifecycle.
local function removeVisual(target)
	local data=State.visuals[target]
	if not data then return end
	for _,line in ipairs(data.skeleton or{})do if line.a then line.a:Destroy()end;if line.b then line.b:Destroy()end end
	for _,object in pairs(data)do if typeof(object)=="Instance"then object:Destroy()end end
	State.visuals[target]=nil
end
local function getVisual(target)
	if State.visuals[target]then return State.visuals[target]end
	local highlight=Instance.new("Highlight");highlight.Enabled=false;highlight.Parent=Workspace
	local billboard=Instance.new("BillboardGui");billboard.Size=UDim2.fromOffset(220,52);billboard.AlwaysOnTop=true;billboard.Enabled=false;billboard.Parent=playerGui
	local textLabel=label(billboard,"",UDim2.fromScale(1,1),nil,Enum.Font.GothamBold,"text",Config.ESPTextSize);textLabel.TextXAlignment=Enum.TextXAlignment.Center;textLabel.TextStrokeTransparency=0
	local box=Instance.new("Frame");box.BackgroundTransparency=1;box.BorderSizePixel=0;box.Visible=false;box.Parent=gui;local boxStroke=outline(box,Theme.accent,0,1.5)
	local tracer=Instance.new("Frame");tracer.AnchorPoint=Vector2.new(.5,.5);tracer.BackgroundColor3=Theme.accent;tracer.BorderSizePixel=0;tracer.Visible=false;tracer.Parent=gui
	local health=Instance.new("Frame");health.BackgroundColor3=Color3.fromRGB(20,21,27);health.BorderSizePixel=0;health.Visible=false;health.Parent=gui;corner(health,2)
	local healthFill=Instance.new("Frame");healthFill.AnchorPoint=Vector2.new(0,1);healthFill.Position=UDim2.fromScale(0,1);healthFill.Size=UDim2.fromScale(1,1);healthFill.BackgroundColor3=Color3.fromRGB(52,211,153);healthFill.BorderSizePixel=0;healthFill.Parent=health;corner(healthFill,2)
	local data={highlight=highlight,billboard=billboard,label=textLabel,box=box,boxStroke=boxStroke,tracer=tracer,health=health,healthFill=healthFill,skeleton={},skeletonModel=nil,show=false,model=nil,root=nil,humanoid=nil,color=Theme.accent};State.visuals[target]=data;return data
end
local skeletonPairs={{"Head","UpperTorso"},{"UpperTorso","LowerTorso"},{"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"}}
local function clearSkeleton(data)
	for _,line in ipairs(data.skeleton)do if line.a then line.a:Destroy()end;if line.b then line.b:Destroy()end end
	data.skeleton={};data.skeletonModel=nil
end
local function updateSkeleton(data,model,color,enabled)
	if enabled and data.skeletonModel~=model then
		clearSkeleton(data)
		local pairsToUse=skeletonPairs
		if not model:FindFirstChild("UpperTorso",true)then
			pairsToUse={{"Head","Torso"},{"Torso","Left Arm"},{"Torso","Right Arm"},{"Torso","Left Leg"},{"Torso","Right Leg"}}
		end
		for _,pair in ipairs(pairsToUse)do
			local first=model:FindFirstChild(pair[1],true);local second=model:FindFirstChild(pair[2],true)
			if first and first:IsA("BasePart")and second and second:IsA("BasePart")then
				local a=Instance.new("Attachment");a.Parent=first;local b=Instance.new("Attachment");b.Parent=second
				local beam=Instance.new("Beam");beam.Attachment0=a;beam.Attachment1=b;beam.FaceCamera=true;beam.Width0=.035;beam.Width1=.035;beam.Transparency=NumberSequence.new(.08);beam.Parent=a
				table.insert(data.skeleton,{a=a,b=b,beam=beam})
			end
		end
		data.skeletonModel=model
	elseif not enabled and #data.skeleton>0 then clearSkeleton(data)end
	for _,line in ipairs(data.skeleton)do line.beam.Enabled=enabled;line.beam.Color=ColorSequence.new(color)end
end
local function updateESP()
	local _,_,myRoot=living(player)
	for _,target in ipairs(Players:GetPlayers())do
		if target~=player then
			local data=getVisual(target);local model,_,targetRoot=living(target)
			local sameTeam=player.Team and target.Team and player.Team==target.Team
			local show=Config.ESPEnabled and model and targetRoot and myRoot and(targetRoot.Position-myRoot.Position).Magnitude<=Config.ESPMaxDistance and(not Config.ESPTeamCheck or not sameTeam)
			local color=sameTeam and Color3.fromHSV(Config.TeammateColorHue,.72,1)or Color3.fromHSV(Config.EnemyColorHue,.78,1)
			data.show=show;data.model=model;data.root=targetRoot;data.humanoid=model and model:FindFirstChildWhichIsA("Humanoid",true);data.color=color
			data.highlight.Adornee=model;data.highlight.Enabled=show and Config.HighlightESP;data.highlight.FillColor=color;data.highlight.OutlineColor=color;data.highlight.FillTransparency=1-Config.ESPFill;data.highlight.DepthMode=Config.ThroughWalls and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
			local anchor=model and(model:FindFirstChild("Head",true)or model:FindFirstChild("VRHead",true)or targetRoot);data.billboard.Adornee=anchor;data.billboard.Enabled=show and Config.NameESP and anchor~=nil
			if show then local upper={target.DisplayName};if Config.VRESP and target:GetAttribute("UsingVR")then table.insert(upper,"[VR]")end;local lower={};if Config.RoleESP then table.insert(lower,string.upper(State.roles[target.Name]or"Unknown"))end;if Config.DistanceESP then table.insert(lower,math.floor((targetRoot.Position-myRoot.Position).Magnitude).."st")end;data.label.Text=table.concat(upper," ").."\n"..table.concat(lower," | ");data.label.TextSize=Config.ESPTextSize end
			if model then updateSkeleton(data,model,color,show and Config.SkeletonESP)end
			if not show then data.box.Visible=false;data.tracer.Visible=false;data.health.Visible=false end
		end
	end
end

local function updateScreenESP()
	if State.menuOpen or not camera or not(Config.BoxESP or Config.TracerESP or Config.HealthESP)then
		for _,data in pairs(State.visuals)do data.box.Visible=false;data.tracer.Visible=false;data.health.Visible=false end
		return
	end
	local bottomCenter=Vector2.new(camera.ViewportSize.X*.5,camera.ViewportSize.Y-8)
	for _,data in pairs(State.visuals)do
		local model=data.model;local root=data.root
		if not data.show or not model or not root then data.box.Visible=false;data.tracer.Visible=false;data.health.Visible=false;continue end
		local center,size=model:GetBoundingBox();local topPoint,onTop=camera:WorldToViewportPoint(center.Position+Vector3.new(0,size.Y*.5,0));local bottomPoint,onBottom=camera:WorldToViewportPoint(center.Position-Vector3.new(0,size.Y*.5,0))
		local onScreen=onTop or onBottom
		local height=math.abs(bottomPoint.Y-topPoint.Y);local width=math.max(height*.52,18);local left=topPoint.X-width*.5;local top=math.min(topPoint.Y,bottomPoint.Y)
		data.box.Visible=Config.BoxESP and onScreen and height>2
		if data.box.Visible then data.box.Position=UDim2.fromOffset(left,top);data.box.Size=UDim2.fromOffset(width,height);data.boxStroke.Color=data.color end
		local rootPoint,rootOn=camera:WorldToViewportPoint(root.Position)
		data.tracer.Visible=Config.TracerESP and rootOn and rootPoint.Z>0
		if data.tracer.Visible then local finish=Vector2.new(rootPoint.X,rootPoint.Y);local delta=finish-bottomCenter;data.tracer.Size=UDim2.fromOffset(delta.Magnitude,2);data.tracer.Position=UDim2.fromOffset((finish.X+bottomCenter.X)*.5,(finish.Y+bottomCenter.Y)*.5);data.tracer.Rotation=math.deg(math.atan2(delta.Y,delta.X));data.tracer.BackgroundColor3=data.color end
		data.health.Visible=Config.HealthESP and data.box.Visible and data.humanoid~=nil
		if data.health.Visible then local ratio=math.clamp(data.humanoid.Health/math.max(data.humanoid.MaxHealth,1),0,1);data.health.Size=UDim2.fromOffset(4,height);data.health.Position=UDim2.fromOffset(left-8,top);data.healthFill.Size=UDim2.fromScale(1,ratio);data.healthFill.BackgroundColor3=Color3.fromRGB(248,75,90):Lerp(Color3.fromRGB(52,211,153),ratio)end
	end
end
Players.PlayerRemoving:Connect(removeVisual)
Players.PlayerAdded:Connect(function(target)if target~=player then target.CharacterAdded:Connect(function()removeVisual(target)end)end end)
for _,target in ipairs(Players:GetPlayers())do if target~=player then target.CharacterAdded:Connect(function()removeVisual(target)end)end end

-- Final Letter keyboard helper.
local WORDS=[[ability abstract academy accept access account acoustic action active adapt admire advance advice afraid agency agree ahead alarm album alert alien alike alive allow almost alone alpha amazing ancient angle animal answer apology appear apple approve arena argue arise armor around arrange arrest arrive arrow artist aspect assist assume athlete attack attend audio author autumn awake award balance bamboo banner bargain basket battle beach beauty become before begin believe benefit bicycle biology blanket blossom board bonus border bottle bounce brain branch brave bread breeze bridge bright bronze brother bubble budget build butter cable cactus camera campaign captain carbon career carpet carry castle category caution center century chair chalk champion change chaos chapter charge chase cheap check cheese cherry chest choice circle citizen claim classic clean clever client climate clock close cloud coach coast collect color combat comfort comic common company concert confirm connect control copper corner correct cotton couch country course cousin craft crane crash crawl crazy cream credit cricket crystal culture curious custom damage dance daring dawn dealer debate decade decide decline decorate deep degree deliver demand desert design detail device diamond diary dinner direct discover doctor domain double dragon drama dream dress drift drink eager early earth easy echo edit educate effect effort eight elder electric elegant element elite embark embrace emerge emotion employ empty enable enemy energy engine enjoy enough enter entire entry equal escape estate ethics event every exact example excite exercise exist expand expect expert explain explore express extra fabric face faith famous fantasy fashion fault feature federal fence festival field figure filter final finance finger finish fire flame flash flavor flight flower focus forest forget formal fortune forward frame fresh friend frost fruit future galaxy game garden garlic general gentle giant ginger glance glass globe glory golden grace grain grape gravity green grid group growth guard guess guitar habit hammer happy harbor harmony hazard heart heavy hero hidden highway history hobby honey honor hotel house human humble humor hybrid icon idea identify image impact improve include index indoor industry infant inform inherit initial input insect inspire install intact interest into invite island issue ivory jacket jewel journey judge juice jungle junior keen keep keyboard kingdom kitten ladder language large laser later launch layer leader learn legend lemon letter library light limit liquid listen little lobby local logic lonely lunar machine magic major mango manual maple marble market master medal memory metal method midnight mobile model modern moment money month moral motion mountain mouse movie museum music mystery narrow native nature never night noble normal notice novel number object ocean offer often olive online open option orange orbit order origin output oxygen paint panda panel paper parent party peace pearl pencil people pepper phrase piano piece pilot planet player point police popular portal power practice prefix pretty pride prime print prize profile program project prompt purple puzzle quality quantum queen query quick quiet rabbit radar random range rapid rare raven reach ready reason record red region relax remote render repeat reply rescue result ribbon right river robot rocket role round royal ruby safe sample scale school score search season second select server shadow shape share shield short signal silver simple skill sky smart smooth social solid solve sound space speak speed spell spider spirit spring square stable stage start static steam steel stone story stream strong studio style submit sugar summer switch system table target teach team temple text theme tiger title today token tool touch tower track train travel tree trial trust tunnel turtle unique universe update useful valid valley value vector velvet version video violet virtual visual voice volume water weapon whale wheel white window winner winter wonder word world write yellow young zebra zero zone erect erected erecting erection erectile erectness erector erectable erectility eremite eremitic eremitical eremitism erethism erethitic erelong erewhile xylophone xerophyte xenolith quartz zoology]]
local wordSet,wordList={},{}
for word in string.gmatch(WORDS,"%a+")do wordSet[word]=true end
for word in pairs(wordSet)do table.insert(wordList,word)end
table.sort(wordList,function(a,b)if#a==#b then return a<b end return#a>#b end)
local wordBuffer=""
local function recommend(prefix)local result={};for _,word in ipairs(wordList)do if word:sub(1,#prefix)==prefix and word~=prefix then table.insert(result,word);if#result>=6 then break end end end;return result end
local quick=panel(gui,isMobile and UDim2.new(1,-16,0,180)or UDim2.fromOffset(760,114),isMobile and UDim2.new(0,8,1,-188)or UDim2.new(.5,-380,1,-128),"panel");UI.quickBar=quick;quick.Visible=false;local quickStatus=label(quick,"KEYBOARD READY / CHAT IGNORED",UDim2.new(1,-20,0,22),UDim2.fromOffset(10,8),Enum.Font.GothamBold,"accent2",10);quickStatus.TextXAlignment=Enum.TextXAlignment.Center;local quickArea=Instance.new("Frame");quickArea.Size=UDim2.new(1,-20,1,-42);quickArea.Position=UDim2.fromOffset(10,34);quickArea.BackgroundTransparency=1;quickArea.Parent=quick;local quickGrid=Instance.new("UIGridLayout");quickGrid.CellPadding=UDim2.fromOffset(6,6);quickGrid.CellSize=isMobile and UDim2.new(.5,-3,0,42)or UDim2.new(.2,-5,0,58);quickGrid.FillDirectionMaxCells=isMobile and 2 or 5;quickGrid.Parent=quickArea;local quickButtons,quickResults={},{};local registeredInput=nil
local refreshWords
local function fillWord(word)
	if registeredInput and registeredInput.Parent then registeredInput.Text=word;task.defer(function()registeredInput:CaptureFocus()end)end
	wordBuffer=""
	if refreshWords then refreshWords()end
end
refreshWords=function()
	quickResults=recommend(wordBuffer)
	quickStatus.Text=wordBuffer~=""and("KEYBOARD: "..string.upper(wordBuffer).." / BACKSPACE")or"KEYBOARD READY / CHAT IGNORED"
	UI.wordLabel.Text=wordBuffer~=""and string.upper(wordBuffer)or"TYPE LETTERS ANYWHERE"
	for index,b in ipairs(quickButtons)do local word=quickResults[index];b.Visible=word~=nil;b.Text=word and string.upper(word)or"-";b:SetAttribute("Word",word)end
	for index,b in ipairs(UI.wordButtons)do local word=quickResults[index];b.Visible=word~=nil;b.Text=word and string.upper(word)or"-";b:SetAttribute("Word",word)end
end
for index=1,4 do local b=button(quickArea,"-",UDim2.new(),nil,"row");table.insert(quickButtons,b);b.Activated:Connect(function()local word=b:GetAttribute("Word");if word then fillWord(word)end end)end
for _,b in ipairs(UI.wordButtons)do b.Activated:Connect(function()local word=b:GetAttribute("Word");if word then fillWord(word)end end)end
local best=button(quickArea,"AUTO TYPE BEST",UDim2.new(),nil,"accent");best.Activated:Connect(function()if quickResults[1]then fillWord(quickResults[1])end end)
UserInputService.TextBoxFocused:Connect(function(box)if Config.ActiveProfile=="The Final Letter"and box:IsDescendantOf(playerGui)and not box:IsDescendantOf(gui)and not string.find(string.lower(box:GetFullName()),"chat",1,true)then registeredInput=box end end)
UserInputService.InputBegan:Connect(function(input)if Config.ActiveProfile~="The Final Letter"or not quick.Visible or input.UserInputType~=Enum.UserInputType.Keyboard or UserInputService:GetFocusedTextBox()then return end;local name=input.KeyCode.Name;if#name==1 and name:match("^[A-Z]$")then wordBuffer=(wordBuffer..name:lower()):sub(1,32)elseif input.KeyCode==Enum.KeyCode.Backspace then wordBuffer=wordBuffer:sub(1,math.max(#wordBuffer-1,0))elseif input.KeyCode==Enum.KeyCode.Delete or input.KeyCode==Enum.KeyCode.Return then wordBuffer=""end;refreshWords()end)

if Remotes.RoleSync then Remotes.RoleSync.OnClientEvent:Connect(function(value)if typeof(value)=="table"then State.roles=value end end)end
if Remotes.Status then Remotes.Status.OnClientEvent:Connect(function(message,ok)if UI.sessionStatus then UI.sessionStatus.Text=tostring(message);UI.sessionStatus.TextColor3=ok and Theme.accent2 or Color3.fromRGB(248,75,90)end;if UI.notify then UI.notify(message,ok)end end)end

local function snapshot()local result={}for key in pairs(DEFAULTS)do result[key]=Config[key]end;return result end
local savedJson=HttpService:JSONEncode(snapshot())
task.spawn(function()while gui.Parent do task.wait(4);if State.dirty and Remotes.Preferences and Remotes.Preferences:IsA("RemoteFunction")then local value=snapshot();local encoded=HttpService:JSONEncode(value);if encoded~=savedJson then UI.saveStatus.Text="Saving...";local ok,saved=pcall(function()return Remotes.Preferences:InvokeServer("save",value)end);if ok and saved then savedJson=encoded;State.dirty=false;UI.saveStatus.Text="Saved"else UI.saveStatus.Text="Save failed"end end end end end)

local elapsed=0
local fpsElapsed=0
local fpsFrames=0
local measuredFPS=0
RunService.RenderStepped:Connect(function(dt)
	updateScreenESP()
	fpsElapsed+=dt;fpsFrames+=1;if fpsElapsed>=.5 then measuredFPS=math.floor(fpsFrames/fpsElapsed+.5);fpsElapsed=0;fpsFrames=0 end
	elapsed+=dt;if elapsed<.2 then return end;elapsed=0;updateESP();UI.homeStatus.Text=(Config.AimEnabled and"Aim ON"or"Aim OFF").." / "..(Config.ESPEnabled and"ESP ON"or"ESP OFF");if UI.layoutStatus then UI.layoutStatus.Text=(Config.AimEnabled and"AIM "or"")..(Config.ESPEnabled and"ESP"or(Config.AimEnabled and"ON"or"READY"))end;if UI.fpsLabel then UI.fpsLabel.Text=tostring(measuredFPS).." FPS"end
	if UI.overviewPlayers then UI.overviewPlayers.Text=tostring(#Players:GetPlayers()).." ONLINE"end
	if UI.overviewPing then UI.overviewPing.Text=math.floor(player:GetNetworkPing()*1000).." MS"end
	if UI.overviewPlace then UI.overviewPlace.Text=tostring(game.PlaceId)end
	if UI.overviewTime then UI.overviewTime.Text=formatDuration(os.clock()-State.sessionStarted)end
	if UI.overviewRole then UI.overviewRole.Text="ROLE: "..string.upper(State.roles[player.Name]or"Waiting")end
	if UI.overviewProfile then UI.overviewProfile.Text="PROFILE  /  "..string.upper(Config.ActiveProfile)end
	if UI.overviewLayout then UI.overviewLayout.Text="LAYOUT  /  "..string.upper(Config.LayoutStyle)end
	if UI.overviewSave then UI.overviewSave.Text="PREFERENCES  /  "..(State.dirty and"PENDING"or"SAVED")end
	if State.target then UI.aimTarget.Text=State.target.DisplayName;UI.aimReason.Text="Target acquired"else UI.aimTarget.Text="No target";UI.aimReason.Text=Config.AimEnabled and"Put another player in the FOV circle and hold right mouse"or"Enable Aim Assist"end
	if UI.playerList then
		for target,row in pairs(UI.playerRows)do if not target.Parent then row:Destroy();UI.playerRows[target]=nil end end
		for _,target in ipairs(Players:GetPlayers())do local row=UI.playerRows[target];if not row then row=button(UI.playerList,"",UDim2.new(1,-8,0,36),nil,"row");row.TextXAlignment=Enum.TextXAlignment.Left;UI.playerRows[target]=row end;row.Text=target.DisplayName.." / "..string.upper(State.roles[target.Name]or"Unknown")end
	end
end)

refreshNavigation();showPage("Hub")
task.spawn(function()
	TweenService:Create(loaderLogoScale,TweenInfo.new(.65,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
	local stages={
		{"Building interface modules...","Assembling the Statics workspace."},
		{"Loading saved preferences...","Restoring your themes and settings."},
		{"Preparing aim systems...","Calibrating FOV, prediction, and rig resolution."},
		{"Preparing visual systems...","Connecting highlights, labels, and skeletons."},
		{"Finalizing profiles...","Universal, Final Letter, and Mystery are ready."},
	}
	for index,data in ipairs(stages)do
		loadingStage.Text=data[1]
		loadingTip.Text=data[2]
		TweenService:Create(loadingFill,TweenInfo.new(.42,Enum.EasingStyle.Quart),{Size=UDim2.fromScale(index/#stages,1)}):Play()
		task.wait(.5)
	end
	loadingTitle.Text="LOADED!"
	loadingStage.Text="Please join our Discord"
	loadingTip.Text="Choose a Game Hub profile to begin."
	loadingDiscord.Text="discord.gg/rXxwRtaCQ"
	TweenService:Create(loaderLogoScale,TweenInfo.new(.25,Enum.EasingStyle.Back),{Scale=1.08}):Play()
	task.wait(.85)
	TweenService:Create(loading,TweenInfo.new(.35),{GroupTransparency=1}):Play()
	task.wait(.37)
	if loadingSpin then loadingSpin:Disconnect()end
	loading.Visible=false
	setMenu(true)
end)
print("[StaticsNewgen] clean rewrite loaded")