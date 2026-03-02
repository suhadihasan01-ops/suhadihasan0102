-- =================================================================
-- Script  : SAMBUNG KATA AUTO PLAY
-- Author  : PrawiraXLIV
-- Support : PC & Mobile (HP)
-- =================================================================

local Players           = game:GetService("Players")
local CoreGui           = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VIM               = game:GetService("VirtualInputManager")
local HttpService       = game:GetService("HttpService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local VirtualUser       = game:GetService("VirtualUser")
local LocalPlayer       = Players.LocalPlayer

local guiParent = (gethui and gethui()) or CoreGui
if guiParent:FindFirstChild("SambungKataGUI") then guiParent.SambungKataGUI:Destroy() end
if guiParent:FindFirstChild("PrawiraAntiAfk") then guiParent.PrawiraAntiAfk:Destroy() end

local scriptConnections = {}

-- ============================================================
-- SYSTEM FOLDER BUILDER
-- ============================================================
local function SetupFolders()
    if makefolder then
        pcall(function()
            if not isfolder("PrawiraHubSambungKata") then makefolder("PrawiraHubSambungKata") end
            if not isfolder("PrawiraHubSambungKata/Database") then makefolder("PrawiraHubSambungKata/Database") end
            if not isfolder("PrawiraHubSambungKata/Database/LocalDB") then makefolder("PrawiraHubSambungKata/Database/LocalDB") end
            if not isfolder("PrawiraHubSambungKata/Database/Blacklist") then makefolder("PrawiraHubSambungKata/Database/Blacklist") end
        end)
    end
end
SetupFolders()

local DB_FILENAME        = "PrawiraHubSambungKata/Database/LocalDB/SambungKata_LocalDB.json"
local BLACKLIST_FILENAME = "PrawiraHubSambungKata/Database/Blacklist/SambungKata_Blacklist.json"

-- ============================================================
-- OUTPUT CONSOLE LOGIC
-- ============================================================
local OutputLogs = {}
local isOutputOn = false
local OutLabel = nil
local OutScroll = nil

local function RefreshOutputUI()
    if OutLabel and OutScroll then
        OutLabel.Text = table.concat(OutputLogs, "\n")
        OutScroll.CanvasPosition = Vector2.new(0, 999999)
    end
end

local function AddLog(msg)
    if not isOutputOn then return end
    table.insert(OutputLogs, os.date("%H:%M:%S") .. " | " .. tostring(msg))
    if #OutputLogs > 150 then table.remove(OutputLogs, 1) end
    RefreshOutputUI()
end

-- ============================================================
-- DATABASE (SINGLE GITHUB LINK)
-- ============================================================
local URLS = {
    "https://raw.githubusercontent.com/suhadihasan01-ops/suhadihasan0102/refs/heads/main/KBBI-SuhadiHasan"
}

local KamusDict    = {}
local WordCache    = {}
local LocalDB      = {}
local BlacklistDB  = {}
local GithubDict   = {}   
local UsedWords    = {}
local TempIgnored  = {}
local scriptActive     = true
local autoTypeEnabled  = false
local mainThread       = nil
local dbLoaded         = false
local isTyping         = false
local totalDuplicates  = 0

local currentPlayerTurn  = nil
local lastValidSpiedWord = ""
local currentTurnDelay   = 0.7
local turnDelayEnd       = 0
local lastRiwayatWord    = "-"   

-- AUTO JOIN
local isAutoJoin   = false
local TableList    = {
    "Table_2P_1","Table_2P_2","Table_2P_3","Table_2P_4",
    "Table_2P_5","Table_2P_6","Table_2P_7",
    "Table_4P_1","Table_4P_2","Table_4P_3","Table_8P"
}
local selectedTable = TableList[1]

local function RegisterWord(w)
    if type(w) ~= "string" then return false end
    local wl = w:lower()
    
    if #wl < 3 then
        BlacklistDB[wl] = true
        if LocalDB[wl] then LocalDB[wl] = nil end
        return false
    end
    
    if BlacklistDB[wl] then return false end
    
    if not KamusDict[wl] then
        KamusDict[wl] = true
        for i = 1, math.min(3, #wl) do
            local p = wl:sub(1, i)
            if not WordCache[p] then WordCache[p] = {} end
            table.insert(WordCache[p], wl)
        end
        return true
    end
    return false
end

-- ============================================================
-- UI LABEL REFERENCES
-- ============================================================
local LblDBStat, LblInfo, LblStatus, LblTyping, LblJoin, LblPre, LblGiliran, LblSpy
local LblNama, LblRiwayatValue, LblAutoJoinStatus, LblAutoJoinTarget
local TriggerListRefresh

local function CountTable(tbl)
    local c = 0; for _ in pairs(tbl) do c = c + 1 end; return c
end

local function UpdateDBStatUI()
    if LblDBStat then
        LblDBStat.Text = "DB:"..CountTable(LocalDB).." Dup:"..totalDuplicates.." Use:"..CountTable(UsedWords).." Blk:"..CountTable(BlacklistDB)
    end
end

local function UpdateRiwayatUI()
    if LblRiwayatValue then
        LblRiwayatValue.Text = "Riwayat: " .. tostring(lastRiwayatWord):upper()
    end
end

local function SaveDatabases()
    if writefile then
        pcall(function() writefile(DB_FILENAME, HttpService:JSONEncode(LocalDB)) end)
        pcall(function() writefile(BLACKLIST_FILENAME, HttpService:JSONEncode(BlacklistDB)) end)
    end
end

local function LoadDatabases()
    if readfile and isfile then
        if isfile(DB_FILENAME) then
            local ok, res = pcall(function() return HttpService:JSONDecode(readfile(DB_FILENAME)) end)
            if ok and type(res) == "table" then LocalDB = res end
        end
        if isfile(BLACKLIST_FILENAME) then
            local ok, res = pcall(function() return HttpService:JSONDecode(readfile(BLACKLIST_FILENAME)) end)
            if ok and type(res) == "table" then BlacklistDB = res end
        end
        for k, _ in pairs(LocalDB) do RegisterWord(k) end
        for k, _ in pairs(BlacklistDB) do BlacklistDB[k] = true end
    end
end
LoadDatabases()

-- ============================================================
-- CONFIG & FILTER
-- ============================================================
local TypingSpeed    = 0.05
local MIN_SPEED      = 0.01; local MAX_SPEED      = 1.00
local DeleteSpeed    = 0.05
local MIN_DEL_SPEED  = 0.01; local MAX_DEL_SPEED  = 1.00
local MIN_TURN_DELAY = 0.1;  local MAX_TURN_DELAY = 2.0
local EnterDelay     = 0.10  

local filterModes = {
    "Tanpa Filter (None)","KIAMAT (W,X,Z,V,F,Q,UZ)","9 JEBAKAN MAUT",
    "SME-IF-AH-EX","EH-IA-MEO-AEK","SME-IF-AH",
    "SME-IF-EX","SME-AH-EX","IF-AH-EX",
    "SME+IF","SME+AH","SME+EX",
    "IF+AH","IF+EX","AH+EX",
    "Medis/Kedokteran","Nasional/Indo"
}
local currentFilterIndex = 1
local sortModes = {"Normal","Terpanjang","Terpendek","Acak"}
local currentSortIndex = 3 -- DEFAULT TERPENDEK

local medicalKeywords = {"fobia","ologi","itis","oma","osis","sindrom","terapi","medis","obat","virus","bakteri","sakit","nyeri","luka","kanker","tumor","darah","jantung","paru","hati","ginjal","otak","saraf","gigi","tulang","kulit","mata","telinga","hidung","klinik","dokter","perawat","bidan","apotek","resep","dosis","injeksi","vaksin","infeksi","alergi","imun","gizi","vitamin","protein","diet","hamil","janin","lahir","bayi","bedah","bius","pingsan","koma","kritis","pulih","sembuh","sehat","bugar","pusing","mual","muntah","diare","demam","panas","batuk","pilek","flu","sesak","asma","hipertensi","anemia","diabetes","kolesterol","stroke","lumpuh","kista","polip","amandel","ambeien","wasir","maag","lambung","usus","hepatitis","katarak","glaukoma","buta","tuli","bisu","eksim","jerawat","psikolog","biologi","mental","stres","depresi","cemas","trauma","autis","genetik","sel","dna","kapsul","pil","sirup","kuman","toksin","racun","antibiotik","anatomi","fisiologi","patologi","diagnos","gejala"}
local nationalKeywords  = {"indonesia","nusantara","bhinneka","tunggal","ika","pancasila","merdeka","republik","bangsa","negara","garuda","merah","putih","bendera","pusaka","pertiwi","proklamasi","pahlawan","patriot","sumpah","pemuda","gotong","royong","musyawarah","mufakat","toleransi","adat","suku","budaya","jawa","sumatra","kalimantan","sulawesi","papua","bali","maluku","sabang","merauke","tni","polri","polisi","tentara","rupiah","monas","presiden","menteri","gubernur","bupati","walikota","rakyat","adil","makmur","sentosa","jaya","abadi","ketuhanan","kemanusiaan","persatuan","kerakyatan","keadilan","sosial","adab","hikmat","reformasi","demokrasi","konstitusi","uud","nkri","soekarno","hatta","sudirman","kartini"}

local function isMedicalWord(w) for _,kw in ipairs(medicalKeywords) do if w:find(kw) then return true end end return false end
local function isNationalWord(w) for _,kw in ipairs(nationalKeywords) do if w:find(kw) then return true end end return false end

local function UpdateInfoUI()
    if LblInfo then
        local m  = autoTypeEnabled and "AUTO" or "MANUAL"
        local aj = isAutoJoin and " | AJ:ON" or ""
        LblInfo.Text = "Mode: "..m..aj.." | Auto-Save DB Aktif"
    end
end

-- ============================================================
-- THEME
-- ============================================================
local THEME = {
    MainBackground = Color3.fromRGB(20,20,25),
    Transparency   = 0.05,
    StrokeColor    = Color3.fromRGB(60,60,70),
    TitleColor     = Color3.fromRGB(0,255,170),
    TextColor      = Color3.new(1,1,1),
    TextWhite      = Color3.fromRGB(255,255,255),
    BtnStart       = Color3.fromRGB(0,160,80),
    BtnStop        = Color3.fromRGB(200,50,50),
    BtnDelete      = Color3.fromRGB(180,40,40),
    BtnExport      = Color3.fromRGB(20,80,120),
    BtnImport      = Color3.fromRGB(100,60,120),
    BtnReset       = Color3.fromRGB(50,50,80),
    BoxBg          = Color3.fromRGB(15,15,15),
    SlotBg         = Color3.fromRGB(35,35,40),
    Font           = Enum.Font.GothamBold,
    Neon           = Color3.fromRGB(57,255,20),
    Cyan           = Color3.fromRGB(50,220,255),
    Yellow         = Color3.fromRGB(255,220,50),
    Red            = Color3.fromRGB(255,70,70),
    Pink           = Color3.fromRGB(255,100,180),
    Nasional       = Color3.fromRGB(255,80,80),
    Kiamat         = Color3.fromRGB(255,0,50),
}
local tweenBounce = TweenInfo.new(0.35, Enum.EasingStyle.Back,  Enum.EasingDirection.Out)
local tweenFast   = TweenInfo.new(0.2,  Enum.EasingStyle.Quad,  Enum.EasingDirection.In)

local function AddStyle(inst, r)
    local c = Instance.new("UICorner", inst); c.CornerRadius = UDim.new(0, r)
    local s = Instance.new("UIStroke", inst); s.Color = THEME.StrokeColor
    s.Thickness = 2; s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end

local function ApplyHover(btn, base, isTransparent)
    local ti = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    if isTransparent then
        local bc = btn.TextColor3
        btn.MouseEnter:Connect(function() TweenService:Create(btn, ti, {TextColor3=THEME.TitleColor}):Play() end)
        btn.MouseLeave:Connect(function() TweenService:Create(btn, ti, {TextColor3=bc}):Play() end)
    else
        btn.MouseEnter:Connect(function()
            local h,s,v = Color3.toHSV(btn.BackgroundColor3)
            TweenService:Create(btn, ti, {BackgroundColor3=Color3.fromHSV(h,s,math.clamp(v+0.15,0,1))}):Play()
        end)
        btn.MouseLeave:Connect(function()
            TweenService:Create(btn, ti, {BackgroundColor3=base}):Play()
        end)
    end
end

-- ============================================================
-- MAIN SCREEN GUI
-- ============================================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name        = "SambungKataGUI"
ScreenGui.Parent      = guiParent
ScreenGui.ResetOnSpawn = false

local ResponsiveScale = Instance.new("UIScale", ScreenGui)
local camera = workspace.CurrentCamera
local BASE_RES = Vector2.new(1600, 900)
local function UpdateScale()
    if not camera then return end
    local v = camera.ViewportSize
    ResponsiveScale.Scale = math.clamp(math.min(v.X/BASE_RES.X, v.Y/BASE_RES.Y), 0.30, 1.0)
end
table.insert(scriptConnections, camera:GetPropertyChangedSignal("ViewportSize"):Connect(UpdateScale))
UpdateScale()

local Frame = Instance.new("Frame", ScreenGui)
Frame.Name                   = "MainFrame"
Frame.Size                   = UDim2.new(0, 950, 0, 490)
Frame.AnchorPoint            = Vector2.new(0.5, 0.5)
Frame.Position               = UDim2.new(0.5, 0, 0.5, 0)
Frame.BackgroundColor3       = THEME.MainBackground
Frame.BackgroundTransparency = THEME.Transparency
Frame.BorderSizePixel        = 0
AddStyle(Frame, 12)

local MainScale = Instance.new("UIScale", Frame); MainScale.Scale = 1

-- ── HEADER ───────────────────────────────────────────────────
local HdrFrame = Instance.new("Frame", Frame)
HdrFrame.Size = UDim2.new(1,-30,0,30); HdrFrame.Position = UDim2.new(0,15,0,10)
HdrFrame.BackgroundTransparency = 1

local CloseBtn = Instance.new("TextButton", HdrFrame)
CloseBtn.Size = UDim2.new(0,28,0,28); CloseBtn.AnchorPoint = Vector2.new(1,0)
CloseBtn.Position = UDim2.new(1,0,0,0); CloseBtn.BackgroundColor3 = THEME.BtnStop
CloseBtn.Text = "X"; CloseBtn.Font = THEME.Font; CloseBtn.TextSize = 13
CloseBtn.TextColor3 = THEME.TextColor; AddStyle(CloseBtn, 6); ApplyHover(CloseBtn, THEME.BtnStop, false)

local MinBtn = Instance.new("TextButton", HdrFrame)
MinBtn.Size = UDim2.new(0,28,0,28); MinBtn.AnchorPoint = Vector2.new(1,0)
MinBtn.Position = UDim2.new(1,-36,0,0); MinBtn.BackgroundColor3 = Color3.fromRGB(80,80,90)
MinBtn.Text = "-"; MinBtn.Font = THEME.Font; MinBtn.TextSize = 18
MinBtn.TextColor3 = THEME.TextColor; AddStyle(MinBtn, 6); ApplyHover(MinBtn, Color3.fromRGB(80,80,90), false)

local Title = Instance.new("TextLabel", HdrFrame)
Title.Size = UDim2.new(1,-80,1,0); Title.BackgroundTransparency = 1
Title.Text = "PrawiraHub - Sambung Kata V2"; Title.TextColor3 = THEME.TitleColor
Title.Font = THEME.Font; Title.TextSize = 14; Title.TextXAlignment = Enum.TextXAlignment.Left

local HdrLine = Instance.new("Frame", Frame)
HdrLine.Size = UDim2.new(1,-20,0,1); HdrLine.Position = UDim2.new(0,10,0,44)
HdrLine.BackgroundColor3 = THEME.Neon; HdrLine.BackgroundTransparency = 0.55
HdrLine.BorderSizePixel = 0

-- ── POSISI KOLOM ─────────────
local LX = 15;  local LW = 325
local MX = 355; local MW = 210
local RX = 580; local RW = 355

local function makeVDiv(x)
    local d = Instance.new("Frame", Frame)
    d.Size = UDim2.new(0,1,1,-52); d.Position = UDim2.new(0,x,0,48)
    d.BackgroundColor3 = THEME.StrokeColor; d.BackgroundTransparency = 0.3
    d.BorderSizePixel = 0
end
makeVDiv(347); makeVDiv(572)

-- ========================================================================
-- 1. KOLOM KIRI (SLIDERS, DROPDOWNS, IMPORT/EXPORT, OUTPUT)
-- ========================================================================
local LY = 52
local function makeLSep(y, col)
    local s = Instance.new("Frame", Frame)
    s.Size = UDim2.new(0,LW,0,1); s.Position = UDim2.new(0,LX,0,y)
    s.BackgroundColor3 = col or THEME.Neon; s.BackgroundTransparency = 0.5; s.BorderSizePixel = 0
end

local function makeSlider(posY, labelText, initVal, minVal, maxVal, fillColor, onChanged)
    local con = Instance.new("Frame", Frame)
    con.Size = UDim2.new(0,LW,0,22); con.Position = UDim2.new(0,LX,0,posY); con.BackgroundTransparency = 1
    local lbl = Instance.new("TextLabel", con)
    lbl.Size = UDim2.new(0,110,1,0); lbl.BackgroundTransparency = 1; lbl.Text = labelText
    lbl.TextColor3 = THEME.TextColor; lbl.Font = Enum.Font.GothamSemibold; lbl.TextSize = 10
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    local line = Instance.new("Frame", con)
    line.Size = UDim2.new(1,-110,0,5); line.Position = UDim2.new(0,110,0.5,-2)
    line.BackgroundColor3 = Color3.fromRGB(50,50,60); line.ZIndex = 5
    Instance.new("UICorner", line).CornerRadius = UDim.new(1,0)
    local pct0 = ((initVal or 0)-(minVal or 0))/((maxVal or 1)-(minVal or 0))
    local fill = Instance.new("Frame", line)
    fill.Size = UDim2.new(pct0,0,1,0); fill.BackgroundColor3 = fillColor; fill.ZIndex = 6
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1,0)
    local knob = Instance.new("Frame", line)
    knob.Size = UDim2.new(0,14,0,14); knob.Position = UDim2.new(pct0,-7,0.5,-7)
    knob.BackgroundColor3 = THEME.TextWhite; knob.ZIndex = 7
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1,0)
    local hit = Instance.new("TextButton", con)
    hit.Size = UDim2.new(1,-110,1,0); hit.Position = UDim2.new(0,110,0,0)
    hit.BackgroundTransparency = 1; hit.Text = ""; hit.ZIndex = 10
    local dragging = false
    local function upd(ix)
        local rel = (ix or 0) - (line.AbsolutePosition.X or 0)
        local pct = math.clamp(rel/(line.AbsoluteSize.X or 1), 0, 1)
        fill.Size = UDim2.new(pct,0,1,0); knob.Position = UDim2.new(pct,-7,0.5,-7)
        onChanged((minVal or 0)+(pct*((maxVal or 1)-(minVal or 0))), lbl)
    end
    hit.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=true; upd(i.Position.X) end
    end)
    table.insert(scriptConnections, UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then upd(i.Position.X) end
    end))
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=false end
    end)
end

makeSlider(LY,    "Delay Turn: 0.7s",  currentTurnDelay, MIN_TURN_DELAY, MAX_TURN_DELAY, THEME.Neon,
    function(v,l) currentTurnDelay=v; l.Text="Delay Turn: "..string.format("%.1f",v).."s" end)
makeSlider(LY+28, "Ketik: 0.05s", TypingSpeed, MIN_SPEED, MAX_SPEED, THEME.TitleColor,
    function(v,l) TypingSpeed=v; l.Text="Ketik: "..string.format("%.2f",v).."s" end)
makeSlider(LY+56, "Hapus: 0.05s", DeleteSpeed, MIN_DEL_SPEED, MAX_DEL_SPEED, THEME.Red,
    function(v,l) DeleteSpeed=v; l.Text="Hapus: "..string.format("%.2f",v).."s" end)
makeSlider(LY+84, "Delay Enter: 0.10s", EnterDelay, 0.00, 2.00, THEME.Yellow,
    function(v,l) EnterDelay=v; l.Text="Delay Enter: "..string.format("%.2f",v).."s" end)

makeLSep(LY+112)

local dropdowns = {}
local function CreateDropdown(w, xPos, yPos, items, defaultIdx, onSel)
    local con = Instance.new("Frame", Frame)
    con.Size = UDim2.new(0,w,0,24); con.Position = UDim2.new(0,xPos,0,yPos)
    con.BackgroundColor3 = Color3.fromRGB(40,30,60); con.ZIndex = 20; AddStyle(con, 6)
    local disp = Instance.new("TextLabel", con)
    disp.Size = UDim2.new(1,-22,1,0); disp.Position = UDim2.new(0,6,0,0); disp.BackgroundTransparency = 1
    disp.Text = items[defaultIdx]; disp.TextColor3 = THEME.TitleColor; disp.Font = THEME.Font
    disp.TextSize = 9; disp.TextXAlignment = Enum.TextXAlignment.Left
    disp.TextTruncate = Enum.TextTruncate.AtEnd; disp.ZIndex = 21
    local arr = Instance.new("TextLabel", con)
    arr.Size = UDim2.new(0,20,1,0); arr.Position = UDim2.new(1,-20,0,0); arr.BackgroundTransparency = 1
    arr.Text = "▼"; arr.TextColor3 = THEME.TextColor; arr.Font = THEME.Font; arr.TextSize = 11; arr.ZIndex = 21
    local trigBtn = Instance.new("TextButton", con)
    trigBtn.Size = UDim2.new(1,0,1,0); trigBtn.BackgroundTransparency = 1; trigBtn.Text = ""; trigBtn.ZIndex = 22
    local sc = Instance.new("ScrollingFrame", Frame)
    sc.Size = UDim2.new(0,w,0,0)
    sc.AnchorPoint = Vector2.new(0,1); sc.Position = UDim2.new(0,xPos,0,yPos)
    sc.BackgroundColor3 = THEME.SlotBg; sc.ScrollBarThickness = 4; sc.ZIndex = 60; sc.Visible = false
    AddStyle(sc, 6)
    local ly = Instance.new("UIListLayout", sc); ly.SortOrder = Enum.SortOrder.LayoutOrder; ly.Padding = UDim.new(0,2)
    local isOpen = false; local isAnim = false
    local function Toggle(fc)
        if isAnim then return end
        if fc and not isOpen then return end
        if not fc and not isOpen then for _,t in ipairs(dropdowns) do if t~=Toggle then t(true) end end end
        isAnim = true; isOpen = fc and false or not isOpen
        if isOpen then
            sc.Visible = true; arr.Text = "▲"
            local th = math.min(#items*25, 180)
            local t = TweenService:Create(sc, tweenFast, {Size=UDim2.new(0,w,0,th)})
            t:Play(); t.Completed:Connect(function() isAnim=false end)
        else
            arr.Text = "▼"
            local t = TweenService:Create(sc, tweenFast, {Size=UDim2.new(0,w,0,0)})
            t:Play(); t.Completed:Connect(function() sc.Visible=false; isAnim=false end)
        end
    end
    table.insert(dropdowns, Toggle); trigBtn.MouseButton1Click:Connect(function() Toggle() end)
    for i, m in ipairs(items) do
        local opt = Instance.new("TextButton", sc)
        opt.Size = UDim2.new(1,-8,0,23); opt.BackgroundColor3 = Color3.fromRGB(50,40,70)
        opt.Text = "  "..m; opt.TextColor3 = THEME.TextColor; opt.Font = THEME.Font; opt.TextSize = 9
        opt.TextXAlignment = Enum.TextXAlignment.Left; opt.ZIndex = 61; AddStyle(opt, 4)
        ApplyHover(opt, Color3.fromRGB(50,40,70), false)
        opt.MouseButton1Click:Connect(function() disp.Text=m; Toggle(true); onSel(i) end)
    end
    sc.CanvasSize = UDim2.new(0,0,0,#items*25)
    return Toggle
end

CreateDropdown(200, LX, LY+120, filterModes, currentFilterIndex, function(idx)
    currentFilterIndex=idx; UpdateInfoUI()
    if TriggerListRefresh then TriggerListRefresh() end
end)
CreateDropdown(115, LX+210, LY+120, sortModes, currentSortIndex, function(idx)
    currentSortIndex=idx; UpdateInfoUI()
    if TriggerListRefresh then TriggerListRefresh() end
end)

local ImportBox = Instance.new("TextBox", Frame)
ImportBox.Size = UDim2.new(0,LW,0,22); ImportBox.Position = UDim2.new(0,LX,0,LY+150)
ImportBox.BackgroundColor3 = THEME.BoxBg; ImportBox.TextColor3 = THEME.TextColor
ImportBox.Font = Enum.Font.Gotham; ImportBox.TextSize = 10
ImportBox.PlaceholderText = "Paste JSON database di sini..."
ImportBox.Text = ""; ImportBox.ClearTextOnFocus = false; AddStyle(ImportBox, 6)

local BtnRow = Instance.new("Frame", Frame)
BtnRow.Size = UDim2.new(0,LW,0,24); BtnRow.Position = UDim2.new(0,LX,0,LY+180)
BtnRow.BackgroundTransparency = 1
local BtnRowLayout = Instance.new("UIListLayout", BtnRow)
BtnRowLayout.FillDirection = Enum.FillDirection.Horizontal; BtnRowLayout.SortOrder = Enum.SortOrder.LayoutOrder; BtnRowLayout.Padding = UDim.new(0,5)

local function makeSmBtn(w, txt, bg, ord)
    local b = Instance.new("TextButton", BtnRow)
    b.Size = UDim2.new(0,w,1,0); b.BackgroundColor3 = bg; b.Text = txt
    b.TextColor3 = THEME.TextColor; b.Font = THEME.Font; b.TextSize = 9; b.LayoutOrder = ord
    AddStyle(b, 5); ApplyHover(b, bg, false); return b
end
local BtnExpComb = makeSmBtn(105, "Exp DB & Blk", THEME.BtnExport, 1)
local BtnImpComb = makeSmBtn(105, "Imp DB & Blk", THEME.BtnImport, 2)
local BtnClrAll  = makeSmBtn(105, "Clr All",      THEME.BtnDelete, 3)

makeLSep(LY+212)

LblInfo = Instance.new("TextLabel", Frame)
LblInfo.Size = UDim2.new(0,LW,0,14); LblInfo.Position = UDim2.new(0,LX,0,LY+220)
LblInfo.BackgroundTransparency = 1; LblInfo.Text = "Mode: MANUAL | Auto-Save DB Aktif"
LblInfo.TextColor3 = Color3.fromRGB(120,120,120); LblInfo.Font = Enum.Font.GothamSemibold
LblInfo.TextSize = 9; LblInfo.TextXAlignment = Enum.TextXAlignment.Center
UpdateInfoUI()

local BtnOutputToggle = Instance.new("TextButton", Frame)
BtnOutputToggle.Size = UDim2.new(0, 155, 0, 24); BtnOutputToggle.Position = UDim2.new(0, LX, 0, LY+240)
BtnOutputToggle.BackgroundColor3 = THEME.BtnStop; BtnOutputToggle.Text = "Output: OFF"
BtnOutputToggle.TextColor3 = THEME.TextColor; BtnOutputToggle.Font = THEME.Font; BtnOutputToggle.TextSize = 10
AddStyle(BtnOutputToggle, 5)

local BtnCopyOutput = Instance.new("TextButton", Frame)
BtnCopyOutput.Size = UDim2.new(0, 165, 0, 24); BtnCopyOutput.Position = UDim2.new(0, LX+160, 0, LY+240)
BtnCopyOutput.BackgroundColor3 = THEME.BtnExport; BtnCopyOutput.Text = "Copy Output"
BtnCopyOutput.TextColor3 = THEME.TextColor; BtnCopyOutput.Font = THEME.Font; BtnCopyOutput.TextSize = 10
AddStyle(BtnCopyOutput, 5); ApplyHover(BtnCopyOutput, THEME.BtnExport, false)

OutScroll = Instance.new("ScrollingFrame", Frame)
OutScroll.Size = UDim2.new(0,LW,0,160); OutScroll.Position = UDim2.new(0,LX,0,LY+270)
OutScroll.BackgroundColor3 = THEME.BoxBg; OutScroll.BorderSizePixel = 0
OutScroll.ScrollBarThickness = 4; OutScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
OutScroll.CanvasSize = UDim2.new(0,0,0,0)
AddStyle(OutScroll, 6)
local OutLayout = Instance.new("UIListLayout", OutScroll)
OutLayout.SortOrder = Enum.SortOrder.LayoutOrder
local OutPad = Instance.new("UIPadding", OutScroll)
OutPad.PaddingLeft = UDim.new(0,5); OutPad.PaddingTop = UDim.new(0,2)

OutLabel = Instance.new("TextLabel", OutScroll)
OutLabel.Size = UDim2.new(1,-5,0,0); OutLabel.AutomaticSize = Enum.AutomaticSize.Y
OutLabel.BackgroundTransparency = 1; OutLabel.Text = "Console Output Here..."
OutLabel.TextColor3 = THEME.TextWhite; OutLabel.TextWrapped = true
OutLabel.TextXAlignment = Enum.TextXAlignment.Left; OutLabel.TextYAlignment = Enum.TextYAlignment.Top
OutLabel.Font = Enum.Font.Code; OutLabel.TextSize = 9

BtnOutputToggle.MouseButton1Click:Connect(function()
    isOutputOn = not isOutputOn
    if isOutputOn then
        BtnOutputToggle.Text = "Output: ON"
        TweenService:Create(BtnOutputToggle, TweenInfo.new(0.2), {BackgroundColor3=THEME.BtnStart}):Play()
        AddLog("Output Logger Started")
    else
        BtnOutputToggle.Text = "Output: OFF"
        TweenService:Create(BtnOutputToggle, TweenInfo.new(0.2), {BackgroundColor3=THEME.BtnStop}):Play()
    end
end)
BtnCopyOutput.MouseButton1Click:Connect(function()
    if setclipboard then
        setclipboard(table.concat(OutputLogs, "\n"))
        if LblStatus then LblStatus.Text = "Output Copied!"; LblStatus.TextColor3 = THEME.Neon end
    else
        if LblStatus then LblStatus.Text = "Cannot Copy!"; LblStatus.TextColor3 = THEME.Red end
    end
end)


-- ========================================================================
-- 2. KOLOM TENGAH (INFO & STATUS LABELS)
-- ========================================================================
local MY = 52
local function makeLbl(y, txt, col, fs)
    local l = Instance.new("TextLabel", Frame)
    l.Size = UDim2.new(0,MW,0,17); l.Position = UDim2.new(0,MX,0,y)
    l.BackgroundTransparency = 1; l.Text = txt; l.TextColor3 = col
    l.Font = Enum.Font.GothamSemibold; l.TextSize = fs or 11
    l.TextXAlignment = Enum.TextXAlignment.Left; l.ZIndex = 5
    l.TextTruncate = Enum.TextTruncate.AtEnd
    return l
end
local function makeMSep2(y, col)
    local s = Instance.new("Frame", Frame)
    s.Size = UDim2.new(0,MW,0,1); s.Position = UDim2.new(0,MX,0,y)
    s.BackgroundColor3 = col or THEME.Neon; s.BackgroundTransparency = 0.6
    s.BorderSizePixel = 0
end

LblJoin    = makeLbl(MY,      "● Belum join meja",        THEME.Red,    11)
LblGiliran = makeLbl(MY+19,   "Giliran: -",               Color3.fromRGB(200,150,255), 11)
LblNama    = makeLbl(MY+38,   "Nama: -",                  THEME.Yellow, 11)
LblSpy     = makeLbl(MY+57,   "Ngetik: -",                THEME.Cyan,   11)
makeMSep2(MY+78)
LblPre     = makeLbl(MY+83,   "HURUF AWAL: -",            THEME.Yellow, 12)
LblTyping  = makeLbl(MY+102,  "TARGET: -",                THEME.Cyan,   11)
LblStatus  = makeLbl(MY+121,  "Status: Booting...",       THEME.Yellow, 11)
LblDBStat  = makeLbl(MY+140,  "DB:0 Dup:0 Use:0 Blk:0",   Color3.fromRGB(150,255,150), 10)
makeMSep2(MY+160, THEME.TitleColor)
LblRiwayatValue = makeLbl(MY+165, "Riwayat: -",           THEME.Pink,   11)
makeMSep2(MY+186, THEME.StrokeColor)

LblAutoJoinTarget = makeLbl(MY+191, "Target: "..selectedTable,  THEME.Yellow, 11)
LblAutoJoinStatus = makeLbl(MY+210, "AJ Status: IDLE",          THEME.Cyan,   11)

local function makeRiwBtn(y, txt, bg)
    local b = Instance.new("TextButton", Frame)
    b.Size = UDim2.new(0,MW,0,25); b.Position = UDim2.new(0,MX,0,y)
    b.BackgroundColor3 = bg; b.Text = txt; b.TextColor3 = THEME.TextColor
    b.Font = THEME.Font; b.TextSize = 10; AddStyle(b, 6); ApplyHover(b, bg, false)
    return b
end
local BtnRiwayatDB        = makeRiwBtn(MY+242, "📚 Riwayat New Local DB",  THEME.BtnExport)
local BtnRiwayatBlacklist = makeRiwBtn(MY+272, "🚫 Riwayat Blacklist",     THEME.BtnDelete)


-- ========================================================================
-- 3. KOLOM KANAN (AUTO PLAY/JOIN, TABLE LIST, SEARCH, WORD LIST)
-- ========================================================================
local RY = 52
local function makeRSep(y, col)
    local s = Instance.new("Frame", Frame)
    s.Size = UDim2.new(0,RW,0,1); s.Position = UDim2.new(0,RX,0,y)
    s.BackgroundColor3 = col or THEME.Neon; s.BackgroundTransparency = 0.5; s.BorderSizePixel = 0
end

local BtnPlay = Instance.new("TextButton", Frame)
BtnPlay.Size = UDim2.new(0,174,0,33); BtnPlay.Position = UDim2.new(0,RX,0,RY)
BtnPlay.BackgroundColor3 = THEME.BtnStop; BtnPlay.Text = "Auto Play Off"
BtnPlay.TextColor3 = THEME.TextColor; BtnPlay.Font = THEME.Font; BtnPlay.TextSize = 11
AddStyle(BtnPlay, 6)

local BtnAutoJoin = Instance.new("TextButton", Frame)
BtnAutoJoin.Size = UDim2.new(0,174,0,33); BtnAutoJoin.Position = UDim2.new(0,RX+181,0,RY)
BtnAutoJoin.BackgroundColor3 = THEME.BtnStop; BtnAutoJoin.Text = "Auto Join Off"
BtnAutoJoin.TextColor3 = THEME.TextColor; BtnAutoJoin.Font = THEME.Font; BtnAutoJoin.TextSize = 11
AddStyle(BtnAutoJoin, 6)

local function applyDynamicHover(btn, getActiveState)
    btn.MouseEnter:Connect(function()
        local c = getActiveState() and THEME.BtnStart or THEME.BtnStop
        local h,s,v = Color3.toHSV(c)
        TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3=Color3.fromHSV(h,s,math.clamp(v+0.15,0,1))}):Play()
    end)
    btn.MouseLeave:Connect(function()
        local c = getActiveState() and THEME.BtnStart or THEME.BtnStop
        TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3=c}):Play()
    end)
end
applyDynamicHover(BtnPlay, function() return autoTypeEnabled end)
applyDynamicHover(BtnAutoJoin, function() return isAutoJoin end)

makeRSep(RY+43, THEME.TitleColor)

local AJTitleLbl = Instance.new("TextLabel", Frame)
AJTitleLbl.Size = UDim2.new(0,RW,0,14); AJTitleLbl.Position = UDim2.new(0,RX,0,RY+47)
AJTitleLbl.BackgroundTransparency = 1; AJTitleLbl.Text = "─── SELECT AUTO JOIN TABLE ───"
AJTitleLbl.TextColor3 = THEME.TitleColor; AJTitleLbl.Font = THEME.Font
AJTitleLbl.TextSize = 10; AJTitleLbl.TextXAlignment = Enum.TextXAlignment.Center

local AJScroll = Instance.new("ScrollingFrame", Frame)
AJScroll.Size = UDim2.new(0,RW,0,92); AJScroll.Position = UDim2.new(0,RX,0,RY+65)
AJScroll.BackgroundColor3 = THEME.BoxBg; AJScroll.BorderSizePixel = 0
AJScroll.ScrollBarThickness = 4; AJScroll.ScrollBarImageColor3 = THEME.TitleColor
AJScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; AJScroll.CanvasSize = UDim2.new(0,0,0,0)
AddStyle(AJScroll, 6)
local AJLayout = Instance.new("UIListLayout", AJScroll)
AJLayout.FillDirection = Enum.FillDirection.Horizontal; AJLayout.Wraps = true
AJLayout.SortOrder = Enum.SortOrder.LayoutOrder; AJLayout.Padding = UDim.new(0,4)
local AJPad = Instance.new("UIPadding", AJScroll)
AJPad.PaddingLeft = UDim.new(0,4); AJPad.PaddingTop = UDim.new(0,4); AJPad.PaddingBottom = UDim.new(0,4)

local ajBtnRefs = {}
for i, tbl in ipairs(TableList) do
    local b = Instance.new("TextButton", AJScroll)
    b.Size = UDim2.new(0,100,0,20)
    b.BackgroundColor3 = (tbl == selectedTable) and THEME.TitleColor or THEME.SlotBg
    b.Text = tbl; b.Font = Enum.Font.GothamMedium; b.TextSize = 9; b.LayoutOrder = i
    b.TextColor3 = (tbl == selectedTable) and Color3.new(0,0,0) or THEME.TextWhite
    AddStyle(b, 4)
    ajBtnRefs[tbl] = b
    b.MouseButton1Click:Connect(function()
        for _, rb in pairs(ajBtnRefs) do rb.BackgroundColor3 = THEME.SlotBg; rb.TextColor3 = THEME.TextWhite end
        b.BackgroundColor3 = THEME.TitleColor; b.TextColor3 = Color3.new(0,0,0)
        selectedTable = tbl
        LblAutoJoinTarget.Text = "Target: "..tbl
        if not isAutoJoin then
            LblAutoJoinStatus.Text = "AJ Status: Siap Join"
            LblAutoJoinStatus.TextColor3 = THEME.Cyan
        end
    end)
end

makeRSep(RY+165)

local SearchBox = Instance.new("TextBox", Frame)
SearchBox.Size = UDim2.new(0,RW,0,25); SearchBox.Position = UDim2.new(0,RX,0,RY+174)
SearchBox.BackgroundColor3 = THEME.SlotBg; SearchBox.TextColor3 = THEME.Yellow
SearchBox.Font = Enum.Font.GothamSemibold; SearchBox.TextSize = 11
SearchBox.PlaceholderText = "🔍 Cari Awalan Manual (Bantu Teman)..."
SearchBox.Text = ""; SearchBox.ClearTextOnFocus = false; AddStyle(SearchBox, 6)

local Scroll = Instance.new("ScrollingFrame", Frame)
Scroll.Size = UDim2.new(0,RW,0,226); Scroll.Position = UDim2.new(0,RX,0,RY+204)
Scroll.BackgroundColor3 = THEME.BoxBg; Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 4; Scroll.ScrollBarImageColor3 = THEME.TitleColor
Scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; Scroll.CanvasSize = UDim2.new(0,0,0,0)
AddStyle(Scroll, 6)
local ScrollLayout = Instance.new("UIListLayout", Scroll)
ScrollLayout.SortOrder = Enum.SortOrder.LayoutOrder; ScrollLayout.Padding = UDim.new(0,2)
local ScrollPad = Instance.new("UIPadding", Scroll)
ScrollPad.PaddingLeft = UDim.new(0,5); ScrollPad.PaddingTop = UDim.new(0,5); ScrollPad.PaddingBottom = UDim.new(0,5)

local function setScrollPlaceholder(txt, col)
    for _, ch in ipairs(Scroll:GetChildren()) do
        if ch:IsA("TextLabel") or ch:IsA("TextButton") then ch:Destroy() end
    end
    local l = Instance.new("TextLabel", Scroll)
    l.Size = UDim2.new(1,-10,0,20); l.BackgroundTransparency = 1
    l.Text = txt; l.TextColor3 = col; l.Font = Enum.Font.GothamMedium; l.TextSize = 11
    l.LayoutOrder = 0; l.TextXAlignment = Enum.TextXAlignment.Left
end
setScrollPlaceholder("Menunggu database...", THEME.Neon)

-- ============================================================
-- EXPORT & IMPORT (SMART MERGE LOGIC)
-- ============================================================
BtnExpComb.MouseButton1Click:Connect(function()
    if setclipboard then
        local data = { LocalDB = LocalDB, BlacklistDB = BlacklistDB }
        setclipboard(HttpService:JSONEncode(data))
        LblStatus.Text="DB & Blacklist Disalin!"; LblStatus.TextColor3=THEME.Neon
    else 
        LblStatus.Text="Executor tidak support Copy!"; LblStatus.TextColor3=THEME.Red 
    end
end)

BtnImpComb.MouseButton1Click:Connect(function()
    local jt = tostring(ImportBox.Text)
    if jt == "" then LblStatus.Text="Paste JSON dulu!"; LblStatus.TextColor3=THEME.Red; return end
    
    local ok, data = pcall(function() return HttpService:JSONDecode(jt) end)
    if ok and type(data) == "table" then
        local cntDB, cntBlk = 0, 0
        
        -- Step 1: Process Blacklist (Highest Priority)
        if data.BlacklistDB then
            for k, v in pairs(data.BlacklistDB) do
                local word = tostring(k):lower()
                if not BlacklistDB[word] then
                    BlacklistDB[word] = true
                    cntBlk = cntBlk + 1
                end
                -- Auto remove from LocalDB if it was blacklisted by friend
                if LocalDB[word] then LocalDB[word] = nil end
            end
        end
        
        -- Step 2: Process LocalDB
        local sourceDB = data.LocalDB or (not data.BlacklistDB and data) or {}
        for k, v in pairs(sourceDB) do 
            local word = tostring(k):lower()
            if #word > 2 and not BlacklistDB[word] then
                if not LocalDB[word] then
                    LocalDB[word] = true
                    cntDB = cntDB + 1
                else
                    totalDuplicates = totalDuplicates + 1
                end
            end
        end
        
        SaveDatabases(); UpdateDBStatUI()
        LblStatus.Text="Imported "..cntDB.." DB & "..cntBlk.." Blk!"
        LblStatus.TextColor3=THEME.Neon; ImportBox.Text=""
    else 
        LblStatus.Text="JSON Tidak Valid!"; LblStatus.TextColor3=THEME.Red 
    end
end)

-- ============================================================
-- POPUP FRAME: RIWAYAT DB & BLACKLIST
-- ============================================================
local function openRiwayatPopup(titleTxt, getData, itemColor)
    local existing = ScreenGui:FindFirstChild("RiwayatPopup")
    if existing then existing:Destroy() end
    local pop = Instance.new("Frame", ScreenGui)
    pop.Name = "RiwayatPopup"
    pop.Size = UDim2.new(0,310,0,390); pop.AnchorPoint = Vector2.new(0.5,0.5)
    pop.Position = UDim2.new(0.5,0,0.5,0); pop.BackgroundColor3 = THEME.MainBackground
    pop.BackgroundTransparency = 0.03; pop.ZIndex = 100; AddStyle(pop, 10)

    local popTitle = Instance.new("TextLabel", pop)
    popTitle.Size = UDim2.new(1,-40,0,28); popTitle.Position = UDim2.new(0,10,0,8)
    popTitle.BackgroundTransparency = 1; popTitle.Text = titleTxt
    popTitle.TextColor3 = THEME.TitleColor; popTitle.Font = THEME.Font; popTitle.TextSize = 12; popTitle.ZIndex = 101
    popTitle.TextXAlignment = Enum.TextXAlignment.Left

    local popClose = Instance.new("TextButton", pop)
    popClose.Size = UDim2.new(0,26,0,26); popClose.Position = UDim2.new(1,-34,0,8)
    popClose.BackgroundColor3 = THEME.BtnStop; popClose.Text = "X"; popClose.Font = THEME.Font
    popClose.TextSize = 12; popClose.TextColor3 = THEME.TextColor; popClose.ZIndex = 101
    AddStyle(popClose, 5); ApplyHover(popClose, THEME.BtnStop, false)
    popClose.MouseButton1Click:Connect(function()
        local s2 = Instance.new("UIScale", pop); s2.Scale = 1
        local t = TweenService:Create(s2, tweenFast, {Scale=0})
        t:Play(); t.Completed:Connect(function() pop:Destroy() end)
    end)

    local popLine = Instance.new("Frame", pop)
    popLine.Size = UDim2.new(1,-16,0,1); popLine.Position = UDim2.new(0,8,0,40)
    popLine.BackgroundColor3 = THEME.Neon; popLine.BackgroundTransparency = 0.6; popLine.BorderSizePixel = 0

    local popScroll = Instance.new("ScrollingFrame", pop)
    popScroll.Size = UDim2.new(1,-14,1,-50); popScroll.Position = UDim2.new(0,7,0,45)
    popScroll.BackgroundColor3 = THEME.BoxBg; popScroll.BorderSizePixel = 0
    popScroll.ScrollBarThickness = 4; popScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    popScroll.CanvasSize = UDim2.new(0,0,0,0); popScroll.ZIndex = 101; AddStyle(popScroll, 6)
    local popLayout = Instance.new("UIListLayout", popScroll)
    popLayout.SortOrder = Enum.SortOrder.LayoutOrder; popLayout.Padding = UDim.new(0,2)
    local popPad = Instance.new("UIPadding", popScroll)
    popPad.PaddingLeft = UDim.new(0,6); popPad.PaddingTop = UDim.new(0,5)

    local data = getData(); local cnt = 0
    for _, wd in ipairs(data) do
        cnt = cnt + 1
        local lbl = Instance.new("TextLabel", popScroll)
        lbl.Size = UDim2.new(1,-10,0,15); lbl.BackgroundTransparency = 1
        lbl.Text = cnt..". "..tostring(wd):upper(); lbl.TextColor3 = itemColor
        lbl.Font = Enum.Font.GothamMedium; lbl.TextSize = 10
        lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.LayoutOrder = cnt; lbl.ZIndex = 102
    end
    if cnt == 0 then
        local el = Instance.new("TextLabel", popScroll)
        el.Size = UDim2.new(1,-10,0,20); el.BackgroundTransparency = 1; el.Text = "(Kosong)"
        el.TextColor3 = Color3.fromRGB(150,150,150); el.Font = Enum.Font.GothamMedium; el.TextSize = 11
        el.TextXAlignment = Enum.TextXAlignment.Left; el.ZIndex = 102
    end

    local ps = Instance.new("UIScale", pop); ps.Scale = 0
    TweenService:Create(ps, tweenBounce, {Scale=1}):Play()

    local dp, ds, dsp = false, nil, nil
    pop.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            dp=true; ds=i.Position; dsp=pop.Position
        end
    end)
    table.insert(scriptConnections, UserInputService.InputChanged:Connect(function(i)
        if dp and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
            local d = ((i.Position or Vector3.zero)-(ds or Vector3.zero))/ResponsiveScale.Scale
            pop.Position = UDim2.new(dsp.X.Scale, dsp.X.Offset+d.X, dsp.Y.Scale, dsp.Y.Offset+d.Y)
        end
    end))
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dp=false end
    end)
end

BtnRiwayatDB.MouseButton1Click:Connect(function()
    local list = {}
    for k,_ in pairs(LocalDB) do table.insert(list, k) end
    table.sort(list)
    openRiwayatPopup("📚 New Local DB ("..#list.." kata)", function() return list end, THEME.Neon)
end)
BtnRiwayatBlacklist.MouseButton1Click:Connect(function()
    local list = {}
    for k,_ in pairs(BlacklistDB) do table.insert(list, k) end
    table.sort(list)
    openRiwayatPopup("🚫 Blacklist ("..#list.." kata)", function() return list end, THEME.Red)
end)

-- ============================================================
-- DRAG (MAIN FRAME)
-- ============================================================
local draggingFrame, dragStart, startPos
Frame.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        for _,t in ipairs(dropdowns) do t(true) end
        draggingFrame=true; dragStart=i.Position; startPos=Frame.Position
    end
end)
table.insert(scriptConnections, UserInputService.InputChanged:Connect(function(i)
    if draggingFrame and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
        local d = ((i.Position or Vector3.zero)-(dragStart or Vector3.zero))/ResponsiveScale.Scale
        Frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X, startPos.Y.Scale, startPos.Y.Offset+d.Y)
    end
end))
UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then draggingFrame=false end
end)

-- ============================================================
-- MINIMIZE CIRCLE
-- ============================================================
local MinCircle = Instance.new("TextButton", ScreenGui)
MinCircle.Size = UDim2.new(0,50,0,50); MinCircle.AnchorPoint = Vector2.new(0.5,0.5)
MinCircle.Position = UDim2.new(0.5,0,0,45); MinCircle.BackgroundColor3 = THEME.MainBackground
MinCircle.Text = "PH"; MinCircle.Font = Enum.Font.GothamBlack; MinCircle.TextSize = 20
MinCircle.TextColor3 = THEME.TitleColor; MinCircle.Visible = false
Instance.new("UICorner", MinCircle).CornerRadius = UDim.new(1,0)
local CircleStroke = Instance.new("UIStroke", MinCircle)
CircleStroke.Color = THEME.TitleColor; CircleStroke.Thickness = 3; CircleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
ApplyHover(MinCircle, THEME.MainBackground, false)
local MinCircleScale = Instance.new("UIScale", MinCircle); MinCircleScale.Scale = 0

local isAnimatingUI = false
MinBtn.MouseButton1Click:Connect(function()
    if isAnimatingUI then return end; isAnimatingUI = true
    local t = TweenService:Create(MainScale, tweenFast, {Scale=0}); t:Play()
    t.Completed:Connect(function()
        Frame.Visible=false; MinCircle.Visible=true
        TweenService:Create(MinCircleScale, tweenBounce, {Scale=1}):Play(); isAnimatingUI=false
    end)
end)

local draggingCircle, dragStartCircle, startPosCircle, hasMovedCircle = false, nil, nil, false
MinCircle.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        draggingCircle=true; hasMovedCircle=false; dragStartCircle=i.Position; startPosCircle=MinCircle.Position
    end
end)
table.insert(scriptConnections, UserInputService.InputChanged:Connect(function(i)
    if draggingCircle and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
        local d = ((i.Position or Vector3.zero)-(dragStartCircle or Vector3.zero))/ResponsiveScale.Scale
        if d.Magnitude>5 then hasMovedCircle=true end
        if hasMovedCircle then
            MinCircle.Position = UDim2.new(startPosCircle.X.Scale, startPosCircle.X.Offset+d.X, startPosCircle.Y.Scale, startPosCircle.Y.Offset+d.Y)
        end
    end
end))
MinCircle.InputEnded:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        draggingCircle=false
        if not hasMovedCircle then
            if isAnimatingUI then return end; isAnimatingUI=true
            local t = TweenService:Create(MinCircleScale, tweenFast, {Scale=0}); t:Play()
            t.Completed:Connect(function()
                MinCircle.Visible=false; Frame.Visible=true
                TweenService:Create(MainScale, tweenBounce, {Scale=1}):Play(); isAnimatingUI=false
            end)
        end
    end
end)

-- ============================================================
-- OVERLAYS (Confirm dialogs: Clear DB & Close)
-- ============================================================
local function createOverlay(titleTxt, confirmCb)
    local ov = Instance.new("Frame", ScreenGui)
    ov.Size = UDim2.new(1,0,1,0); ov.BackgroundTransparency = 1
    ov.BackgroundColor3 = Color3.new(0,0,0); ov.Visible = false; ov.ZIndex = 100
    local box = Instance.new("Frame", ov)
    box.Size = UDim2.new(0,260,0,120); box.AnchorPoint = Vector2.new(0.5,0.5)
    box.Position = UDim2.new(0.5,0,0.5,0); box.BackgroundColor3 = THEME.MainBackground; box.ZIndex = 101
    AddStyle(box, 12)
    local sc = Instance.new("UIScale", box); sc.Scale = 0
    local txt = Instance.new("TextLabel", box)
    txt.Size = UDim2.new(1,0,0,60); txt.BackgroundTransparency = 1; txt.Text = titleTxt
    txt.Font = THEME.Font; txt.TextColor3 = THEME.TextColor; txt.TextSize = 13; txt.ZIndex = 102
    local bY = Instance.new("TextButton", box)
    bY.Size = UDim2.new(0,100,0,35); bY.Position = UDim2.new(0,20,1,-50)
    bY.BackgroundColor3 = THEME.BtnStop; bY.Text = "YES"; bY.Font = THEME.Font
    bY.TextColor3 = THEME.TextColor; bY.TextSize = 14; bY.ZIndex = 102
    AddStyle(bY, 8); ApplyHover(bY, THEME.BtnStop, false)
    local bN = Instance.new("TextButton", box)
    bN.Size = UDim2.new(0,100,0,35); bN.Position = UDim2.new(1,-120,1,-50)
    bN.BackgroundColor3 = Color3.fromRGB(100,100,100); bN.Text = "NO"; bN.Font = THEME.Font
    bN.TextColor3 = THEME.TextColor; bN.TextSize = 14; bN.ZIndex = 102
    AddStyle(bN, 8); ApplyHover(bN, Color3.fromRGB(100,100,100), false)
    local function hide()
        TweenService:Create(sc, tweenFast, {Scale=0}):Play()
        local ft = TweenService:Create(ov, tweenFast, {BackgroundTransparency=1}); ft:Play()
        ft.Completed:Connect(function() ov.Visible=false end)
    end
    bN.MouseButton1Click:Connect(hide)
    bY.MouseButton1Click:Connect(function() confirmCb(); hide() end)
    return ov, sc
end

local DelOverlay, DelScale = createOverlay("Are you sure delete ALL DB?", function()
    LocalDB = {}
    BlacklistDB = {}
    if delfile then 
        pcall(function() delfile(DB_FILENAME) end)
        pcall(function() delfile(BLACKLIST_FILENAME) end)
    end
    -- Create fresh files
    SaveDatabases()
    UpdateDBStatUI()
    AddLog("All Databases CLEARED (Files deleted & recreated)")
end)

local CloseOverlay, CloseScale = createOverlay("Are you sure you want to close?", function()
    SaveDatabases() 
    scriptActive = false
    autoTypeEnabled = false
    if mainThread then task.cancel(mainThread) end
    for _,c in ipairs(scriptConnections) do if c.Connected then c:Disconnect() end end
    
    KamusDict, WordCache, UsedWords, TempIgnored, GithubDict, LocalDB, BlacklistDB = {}, {}, {}, {}, {}, {}, {}
    AddLog("PrawiraHub Closed & Saved")
    ScreenGui:Destroy()
end)

BtnClrAll.MouseButton1Click:Connect(function()
    DelOverlay.Visible=true
    TweenService:Create(DelOverlay, TweenInfo.new(0.2), {BackgroundTransparency=0.5}):Play()
    TweenService:Create(DelScale, tweenBounce, {Scale=1}):Play()
end)

CloseBtn.MouseButton1Click:Connect(function()
    CloseOverlay.Visible=true
    TweenService:Create(CloseOverlay, TweenInfo.new(0.2), {BackgroundTransparency=0.5}):Play()
    TweenService:Create(CloseScale, tweenBounce, {Scale=1}):Play()
end)

-- ============================================================
-- THE TRUE DATA RESETTER (Reset Otomatis Data Match)
-- ============================================================
local function ForceClearDataUse()
    if next(UsedWords) ~= nil or next(TempIgnored) ~= nil or totalDuplicates > 0 then
        UsedWords = {}
        TempIgnored = {}
        totalDuplicates = 0
        UpdateDBStatUI()
        if TriggerListRefresh then TriggerListRefresh() end
        if LblStatus then LblStatus.Text="Ronde Selesai! Data Use & Dup Di-reset."; LblStatus.TextColor3=THEME.Cyan end
    end
end

table.insert(scriptConnections, LocalPlayer:GetAttributeChangedSignal("CurrentTable"):Connect(function()
    if not LocalPlayer:GetAttribute("CurrentTable") then ForceClearDataUse() end
end))

local remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
if remotes and remotes:FindFirstChild("ResultUI") then
    table.insert(scriptConnections, remotes.ResultUI.OnClientEvent:Connect(function() ForceClearDataUse() end))
end

-- ============================================================
-- SPY MODULE (Mendeteksi Musuh & Turn)
-- ============================================================
if remotes and remotes:FindFirstChild("TurnCamera") then
    table.insert(scriptConnections, remotes.TurnCamera.OnClientEvent:Connect(function(plr)
        pcall(function()
            currentPlayerTurn = plr
            lastValidSpiedWord = ""
            if plr then
                if plr == LocalPlayer then
                    LblGiliran.Text = "Giliran: KITA! (Giliranmu)"
                    LblGiliran.TextColor3 = THEME.Neon
                    LblNama.Text = "Nama: "..tostring(LocalPlayer.Name).." (Kamu)"
                    LblNama.TextColor3 = THEME.Neon
                    
                    local delayVal = tonumber(currentTurnDelay) or 0.7
                    turnDelayEnd = tick() + delayVal
                else
                    LblGiliran.Text = "Giliran: "..tostring(plr.DisplayName)
                    LblGiliran.TextColor3 = Color3.fromRGB(200,150,255)
                    LblNama.Text = "Nama: "..tostring(plr.DisplayName)
                    LblNama.TextColor3 = THEME.Yellow
                    turnDelayEnd = 0
                end
            else
                LblGiliran.Text = "Giliran: -"; LblGiliran.TextColor3 = Color3.fromRGB(200,150,255)
                LblNama.Text = "Nama: -"; LblNama.TextColor3 = THEME.Yellow
                LblSpy.Text = "Ngetik: -"; turnDelayEnd = 0
            end
        end)
    end))
end

task.spawn(function()
    while scriptActive do
        task.wait(0.1)
        pcall(function()
            if currentPlayerTurn then
                if currentPlayerTurn == LocalPlayer then
                    LblSpy.Text = "Ngetik: (Giliranmu)"
                    LblSpy.TextColor3 = THEME.TextWhite
                else
                    local char = currentPlayerTurn.Character
                    if char then
                        local head = char:FindFirstChild("Head")
                        if head then
                            local bb = head:FindFirstChild("TurnBillboard")
                            if bb then
                                local tl = bb:FindFirstChild("Text")
                                if tl and tl:IsA("TextLabel") then
                                    local tx = tostring(tl.Text):gsub("<[^>]+>", "")
                                    tx = tx:gsub("[%s%p]", "")
                                    if tx~="" and tx:lower()~="label" and tx:lower()~="textbox" then
                                        lastValidSpiedWord = tx
                                        LblSpy.Text = "Ngetik: "..tx:upper()
                                        LblSpy.TextColor3 = THEME.Red
                                    elseif tx=="" then
                                        LblSpy.Text = "Ngetik: ..."; LblSpy.TextColor3 = THEME.Red
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end)
    end
end)

-- ============================================================
-- SNIFFER (Menangkap Keberhasilan Musuh & System Use vs Blacklist)
-- ============================================================
local wordStatus = "waiting"
if remotes then
    local updateWordIndex = remotes:FindFirstChild("UpdateWordIndex")
    if updateWordIndex then
        table.insert(scriptConnections, updateWordIndex.OnClientEvent:Connect(function(data)
            if type(data) == "table" and data.NewWord and type(data.NewWord) == "string" then
                local cw = data.NewWord:lower():gsub("[^%a]", "")
                if #cw > 0 then
                    if #cw < 3 then
                        BlacklistDB[cw] = true; SaveDatabases()
                    else
                        UsedWords[cw] = true 
                        if RegisterWord(cw) then
                            LocalDB[cw] = true; SaveDatabases()
                        else
                            totalDuplicates = totalDuplicates + 1
                        end
                        UpdateDBStatUI()
                        if TriggerListRefresh then TriggerListRefresh() end
                    end
                end
            end
        end))
    end

    if remotes:FindFirstChild("PlayerCorrect") then
        table.insert(scriptConnections, remotes.PlayerCorrect.OnClientEvent:Connect(function(plr)
            pcall(function()
                if plr == LocalPlayer then
                    wordStatus = "correct"
                else
                    -- Jika Musuh berhasil ngetik, amankan katanya ke Use
                    if lastValidSpiedWord and lastValidSpiedWord ~= "" then
                        local cw = lastValidSpiedWord:lower()
                        if #cw > 2 then
                            UsedWords[cw] = true
                            lastRiwayatWord = cw; UpdateRiwayatUI()
                            if not KamusDict[cw] and not BlacklistDB[cw] then
                                LocalDB[cw]=true; SaveDatabases(); RegisterWord(cw)
                            end
                            if LocalPlayer:GetAttribute("CurrentTable") then
                                LblStatus.Text = "⛔ Terpakai musuh: "..cw:upper()
                                LblStatus.TextColor3 = Color3.fromRGB(255,150,50)
                            end
                            UpdateDBStatUI()
                            if TriggerListRefresh then TriggerListRefresh() end
                            AddLog("Enemy Success: " .. cw)
                        else
                            BlacklistDB[cw] = true; SaveDatabases()
                        end
                    end
                end
            end)
        end))
    end
    
    -- JIKA KATA SUDAH DIGUNAKAN (UsedWordWarn dari Server)
    if remotes:FindFirstChild("UsedWordWarn") then
        table.insert(scriptConnections, remotes.UsedWordWarn.OnClientEvent:Connect(function() 
            wordStatus = "used" 
        end))
    end
end

-- ============================================================
-- getPrefix (100% AMAN - KUNCI KE WordServer)
-- ============================================================
local function getPrefix()
    local prefix = nil
    pcall(function()
        local mUI = LocalPlayer.PlayerGui:FindFirstChild("MatchUI")
        if not mUI or not mUI.Enabled then return end
        
        local bUI = mUI:FindFirstChild("BottomUI")
        if not bUI or not bUI.Visible then return end
        
        -- Target utama: UI Game WordServer agar tidak terganggu teks ketikan yang jalan
        local ws = bUI:FindFirstChild("TopUI") 
            and bUI.TopUI:FindFirstChild("WordServerFrame") 
            and bUI.TopUI.WordServerFrame:FindFirstChild("WordServer")
        
        if ws and ws:IsA("TextLabel") and ws.Visible then
            local t = tostring(ws.Text):gsub("%s+","")
            if t:match("^%a+$") and #t <= 3 then
                prefix = t
                return
            end
        end
        
        -- Fallback: Cari label yang berbunyi "Huruf..:"
        if not prefix then
            for _, v in ipairs(mUI:GetDescendants()) do
                if v:IsA("TextLabel") and v.Visible then
                    local match = v.Text:match("[Hh]uruf.*:%s*(%a+)")
                    if match then 
                        prefix = match 
                        return 
                    end
                end
            end
        end
    end)
    return prefix and prefix:lower() or nil
end

-- ============================================================
-- TypeSingleWord (AMU VIM METHOD - ZERO CRASH / ZERO TYPO)
-- ============================================================
local function TypeSingleWord(kata, passedPrefix)
    local safePrefix = tostring(passedPrefix or "")
    if safePrefix == "" then
        if LblStatus then LblStatus.Text = "❌ Gagal: Prefix kosong/nil!" end
        return false
    end

    if currentPlayerTurn and currentPlayerTurn ~= LocalPlayer then
        if LblStatus then LblStatus.Text = "❌ TERTUNDA: Giliran Orang Lain!"; LblStatus.TextColor3 = THEME.Red end
        return false
    end
    
    local wKasar = tostring(kata)
    if LblTyping then LblTyping.Text = "TARGET: "..wKasar:upper() end
    if LblStatus then LblStatus.Text = "Menghapus sisa teks..."; LblStatus.TextColor3 = THEME.Yellow end

    for b = 1, 15 do
        if getPrefix() == nil then return false end
        VIM:SendKeyEvent(true, Enum.KeyCode.Backspace, false, game)
        task.wait(0.01) 
        VIM:SendKeyEvent(false, Enum.KeyCode.Backspace, false, game)
    end
    task.wait(0.05) 

    if LblStatus then LblStatus.Text = "Mencoba: "..wKasar:upper(); LblStatus.TextColor3 = THEME.Cyan end

    local sisaKata = ""
    pcall(function()
        local escapePrefix = safePrefix:gsub("([^%w])", "%%%1")
        sisaKata = wKasar:gsub("^" .. escapePrefix, "", 1)
    end)
    
    wordStatus = "waiting"

    local ketikSpd = tonumber(TypingSpeed) or 0.05
    for i = 1, #sisaKata do
        if getPrefix() == nil then return false end
        local charToType = ""
        pcall(function() charToType = string.sub(sisaKata, i, i) end)
        
        local kc = Enum.KeyCode[string.upper(charToType)]
        if kc then
            VIM:SendKeyEvent(true, kc, false, game)
            task.wait(0.02) 
            VIM:SendKeyEvent(false, kc, false, game)
        end
        task.wait(ketikSpd)
    end

    -- ============================================================
    -- DELAY ENTER FEATURE
    -- ============================================================
    if EnterDelay > 0 then
        if LblStatus then LblStatus.Text = "Menunggu Enter ("..string.format("%.2f", EnterDelay).."s)..."; LblStatus.TextColor3 = THEME.Yellow end
        task.wait(EnterDelay)
    else
        task.wait(0.05)
    end

    if getPrefix() == nil or (currentPlayerTurn and currentPlayerTurn ~= LocalPlayer) then return false end

    -- MENEKAN ENTER TEPAT 1x
    VIM:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
    task.wait(0.05) 
    VIM:SendKeyEvent(false, Enum.KeyCode.Return, false, game)

    local timeout = tick() + 1.5
    local isAccepted = false
    
    while tick() < timeout and scriptActive do
        task.wait(0.05)
        -- Validasi bahwa giliran kita sukses lewat
        if wordStatus == "correct" or (currentPlayerTurn ~= LocalPlayer) then
            isAccepted = true
            break
        end
        if wordStatus == "wrong" or wordStatus == "used" then break end
    end

    if isAccepted then
        UsedWords[wKasar] = true
        lastRiwayatWord = wKasar; UpdateRiwayatUI()
        if LblStatus then LblStatus.Text = "✓ BENAR: "..wKasar:upper(); LblStatus.TextColor3 = THEME.Neon end
        
        if RegisterWord(wKasar) then LocalDB[wKasar]=true; SaveDatabases()
        else totalDuplicates=totalDuplicates+1 end
        
        UpdateDBStatUI()
        if TriggerListRefresh then TriggerListRefresh() end
        AddLog("Successfully typed: " .. wKasar)
        return true 
        
    elseif wordStatus == "used" then
        -- KATA SUDAH DIGUNAKAN (MASUK KE TABEL USE)
        UsedWords[wKasar] = true 
        if LblStatus then LblStatus.Text = "⚠️ SUDAH TERPAKAI: "..wKasar:upper(); LblStatus.TextColor3 = Color3.fromRGB(255,150,50) end
        
        local hapusSpd = tonumber(DeleteSpeed) or 0.05
        for _ = 1, #sisaKata do
            VIM:SendKeyEvent(true, Enum.KeyCode.Backspace, false, game)
            task.wait(0.015) 
            VIM:SendKeyEvent(false, Enum.KeyCode.Backspace, false, game)
            task.wait(hapusSpd)
        end
        
        UpdateDBStatUI()
        if TriggerListRefresh then TriggerListRefresh() end
        task.wait(0.1) 
        return false
        
    else
        -- KATA DITOLAK SERVER KARENA TIDAK TERDAFTAR (MASUK BLACKLIST)
        TempIgnored[wKasar] = true 
        if LblStatus then LblStatus.Text = "❌ TIDAK TERDAFTAR (BLACKLIST)"; LblStatus.TextColor3 = THEME.Red end
        
        local hapusSpd = tonumber(DeleteSpeed) or 0.05
        for _ = 1, #sisaKata do
            VIM:SendKeyEvent(true, Enum.KeyCode.Backspace, false, game)
            task.wait(0.015) 
            VIM:SendKeyEvent(false, Enum.KeyCode.Backspace, false, game)
            task.wait(hapusSpd)
        end
        
        BlacklistDB[wKasar] = true
        if LocalDB[wKasar] then LocalDB[wKasar] = nil end
        SaveDatabases()
        
        UpdateDBStatUI()
        if TriggerListRefresh then TriggerListRefresh() end
        task.wait(0.1) 
        return false
    end
end

-- ============================================================
-- FILTERING ENGINE
-- ============================================================
local function getSortedPool(prefix)
    local listSME,listIF,listAH,listEX,listEH,listIA,listMEO,listAEK = {},{},{},{},{},{},{},{}
    local listMedis,listNasional,listKiamat,nList,allValid,added = {},{},{},{},{},{}
    local poolCache = WordCache[prefix]
    if not poolCache then return {} end

    for _, kata in ipairs(poolCache) do
        -- Cek ketat: Kalau sudah di Use / Blacklist / TempIgnored, dilewati!
        if not UsedWords[kata] and not BlacklistDB[kata] and not TempIgnored[kata] then
            if not added[kata] then
                added[kata] = true
                table.insert(allValid, kata)
                local w = tostring(kata):lower()
                local isKiamat = w:match("[wxzvfq]$") or w:match("uz$")
                if     currentFilterIndex==2  and isKiamat         then table.insert(listKiamat, kata)
                elseif currentFilterIndex==16 and isMedicalWord(w) then table.insert(listMedis,  kata)
                elseif currentFilterIndex==17 and isNationalWord(w) then table.insert(listNasional,kata)
                elseif w:match("sme$")                      then table.insert(listSME,  kata)
                elseif w:match("if$")                       then table.insert(listIF,   kata)
                elseif w:match("ah$")                       then table.insert(listAH,   kata)
                elseif w:match("ex$") or w:match("eks$")    then table.insert(listEX, kata)
                elseif w:match("eh$")                       then table.insert(listEH,   kata)
                elseif w:match("ia$")                       then table.insert(listIA,   kata)
                elseif w:match("meo$")                      then table.insert(listMEO,  kata)
                elseif w:match("aek$")                      then table.insert(listAEK,  kata)
                else                                             table.insert(nList,    kata)
                end
            end
        end
    end

    local function applySort(lst)
        if     currentSortIndex==2 then table.sort(lst,function(a,b) return #a>#b end)
        elseif currentSortIndex==3 then table.sort(lst,function(a,b) return #a<#b end)
        elseif currentSortIndex==4 then
            for i=#lst,2,-1 do local j=math.random(1,i); lst[i],lst[j]=lst[j],lst[i] end
        end
    end

    if currentFilterIndex==1 then
        local p={}; for _,k in ipairs(allValid) do table.insert(p,k) end; applySort(p); return p
    end

    for _,l in ipairs({listKiamat,listSME,listIF,listAH,listEX,listEH,listIA,listMEO,listAEK,listMedis,listNasional,nList}) do applySort(l) end

    local finalPool={}
    local function addR(...) for _,l in ipairs({...}) do for _,k in ipairs(l) do table.insert(finalPool,k) end end end
    local function interleave(...)
        local ls={...}; local mx=0; for _,l in ipairs(ls) do if #l>mx then mx=#l end end
        for i=1,mx do for _,l in ipairs(ls) do if l[i] then table.insert(finalPool,l[i]) end end end
    end
    local function mergeAndSort(...)
        local m={}; for _,l in ipairs({...}) do for _,k in ipairs(l) do table.insert(m,k) end end
        applySort(m); for _,k in ipairs(m) do table.insert(finalPool,k) end
    end
    local useGS = (currentSortIndex~=1)
    local function applyRotasi(pri, res)
        if useGS then mergeAndSort(table.unpack(pri)) else interleave(table.unpack(pri)) end
        addR(table.unpack(res))
    end

    if     currentFilterIndex==2  then if useGS then mergeAndSort(listKiamat,listSME,listIF,listAH,listEX,listEH,listIA,listMEO,listAEK) else addR(listKiamat,listSME,listIF,listAH,listEX,listEH,listIA,listMEO,listAEK) end; addR(nList)
    elseif currentFilterIndex==16 then if useGS then mergeAndSort(listMedis,listSME,listIF,listAH,listEX,listEH,listIA,listMEO,listAEK) else addR(listMedis,listSME,listIF,listAH,listEX,listEH,listIA,listMEO,listAEK) end; addR(nList)
    elseif currentFilterIndex==17 then if useGS then mergeAndSort(listNasional,listSME,listIF,listAH,listEX,listEH,listIA,listMEO,listAEK) else addR(listNasional,listSME,listIF,listAH,listEX,listEH,listIA,listMEO,listAEK) end; addR(nList)
    elseif currentFilterIndex==3  then applyRotasi({listSME,listIF,listAH,listEX,listEH,listIA,listMEO,listAEK},{})
    elseif currentFilterIndex==4  then applyRotasi({listSME,listIF,listAH,listEX},{listEH,listIA,listMEO,listAEK})
    elseif currentFilterIndex==5  then applyRotasi({listEH,listIA,listMEO,listAEK},{listSME,listIF,listAH,listEX})
    elseif currentFilterIndex==6  then applyRotasi({listSME,listIF,listAH},{listEX,listEH,listIA,listMEO,listAEK})
    elseif currentFilterIndex==7  then applyRotasi({listSME,listIF,listEX},{listAH,listEH,listIA,listMEO,listAEK})
    elseif currentFilterIndex==8  then applyRotasi({listSME,listAH,listEX},{listIF,listEH,listIA,listMEO,listAEK})
    elseif currentFilterIndex==9  then applyRotasi({listIF,listAH,listEX},{listSME,listEH,listIA,listMEO,listAEK})
    elseif currentFilterIndex==10 then applyRotasi({listSME,listIF},{listAH,listEX,listEH,listIA,listMEO,listAEK})
    elseif currentFilterIndex==11 then applyRotasi({listSME,listAH},{listIF,listEX,listEH,listIA,listMEO,listAEK})
    elseif currentFilterIndex==12 then applyRotasi({listSME,listEX},{listIF,listAH,listEH,listIA,listMEO,listAEK})
    elseif currentFilterIndex==13 then applyRotasi({listIF,listAH},{listSME,listEX,listEH,listIA,listMEO,listAEK})
    elseif currentFilterIndex==14 then applyRotasi({listIF,listEX},{listSME,listAH,listEH,listIA,listMEO,listAEK})
    elseif currentFilterIndex==15 then applyRotasi({listAH,listEX},{listSME,listIF,listEH,listIA,listMEO,listAEK})
    end

    addR(nList); return finalPool
end

-- ============================================================
-- UI LIST
-- ============================================================
local function updateListUI(prefix)
    local pool = getSortedPool(prefix)
    for _, ch in ipairs(Scroll:GetChildren()) do
        if ch:IsA("TextLabel") or ch:IsA("TextButton") then ch:Destroy() end
    end
    local header = Instance.new("TextLabel", Scroll)
    header.Size = UDim2.new(1,-10,0,20); header.BackgroundTransparency=1
    header.Font = Enum.Font.GothamBold; header.TextSize=11
    header.TextXAlignment=Enum.TextXAlignment.Left; header.LayoutOrder=0
    if #pool>0 then
        header.Text="["..#pool.." kata] Klik utk Ketik/Salin:"; header.TextColor3=THEME.Neon
        for i, kata in ipairs(pool) do
            if i>300 then break end
            local btn = Instance.new("TextButton", Scroll)
            btn.Size = UDim2.new(1,-10,0,18); btn.BackgroundTransparency=1
            btn.Font = Enum.Font.GothamMedium; btn.TextSize=12
            btn.TextXAlignment=Enum.TextXAlignment.Left; btn.LayoutOrder=i
            local w = tostring(kata):lower(); local tc = THEME.TextColor
            if w:match("[wxzvfq]$") or w:match("uz$") then tc=THEME.Kiamat
            elseif currentFilterIndex==16 and isMedicalWord(w) then tc=THEME.Pink
            elseif currentFilterIndex==17 and isNationalWord(w) then tc=THEME.Nasional
            elseif w:match("sme$") then tc=Color3.fromRGB(180,100,255)
            elseif w:match("if$")  then tc=THEME.Neon
            elseif w:match("ah$")  then tc=Color3.fromRGB(200,255,100)
            elseif w:match("ex$") or w:match("eks$") then tc=Color3.fromRGB(255,120,120)
            elseif w:match("eh$")  then tc=Color3.fromRGB(150,255,255)
            elseif w:match("ia$")  then tc=Color3.fromRGB(100,150,255)
            elseif w:match("meo$") then tc=Color3.fromRGB(255,170,50)
            elseif w:match("aek$") then tc=Color3.fromRGB(150,255,50)
            end
            btn.Text = i..". "..tostring(kata):upper(); btn.TextColor3 = tc
            btn.MouseEnter:Connect(function() TweenService:Create(btn, tweenFast, {BackgroundTransparency=0.8, BackgroundColor3=THEME.TitleColor}):Play() end)
            btn.MouseLeave:Connect(function() TweenService:Create(btn, tweenFast, {BackgroundTransparency=1}):Play() end)
            btn.MouseButton1Click:Connect(function()
                if isTyping then return end
                if currentPlayerTurn and currentPlayerTurn~=LocalPlayer then
                    LblStatus.Text="Bukan giliranmu! Tahan..."; LblStatus.TextColor3=THEME.Red; return
                end
                local searchTxt = tostring(SearchBox.Text):lower():gsub("[^%a]","")
                local p = getPrefix()
                local safeP = tostring(p or "")
                
                local kataCheck = ""
                pcall(function() kataCheck = string.sub(kata, 1, string.len(safeP)) end)
                
                if p and kataCheck == safeP and searchTxt=="" then
                    task.spawn(function() isTyping=true; TypeSingleWord(kata,p); isTyping=false end)
                else
                    if setclipboard then
                        setclipboard(tostring(kata):upper())
                        LblStatus.Text="📋 TERSALIN: "..tostring(kata):upper(); LblStatus.TextColor3=THEME.Cyan
                    else LblStatus.Text="Gagal Salin!"; LblStatus.TextColor3=THEME.Red end
                end
            end)
        end
    else
        header.Text=">> KATA HABIS / DIBLACKLIST <<"; header.TextColor3=THEME.Red
    end
end

function TriggerListRefresh()
    local st = tostring(SearchBox.Text):lower():gsub("[^%a]","")
    if st~="" then updateListUI(st)
    else local p=getPrefix(); if p then updateListUI(p) end end
end

SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    if isTyping then return end
    local st = tostring(SearchBox.Text):lower():gsub("[^%a]","")
    if st~="" then
        if autoTypeEnabled then
            autoTypeEnabled=false; BtnPlay.Text="Auto Play Off"
            TweenService:Create(BtnPlay, TweenInfo.new(0.2), {BackgroundColor3=THEME.BtnStop}):Play()
            UpdateInfoUI()
        end
        TriggerListRefresh()
    end
end)

-- ============================================================
-- AUTO-TYPE
-- ============================================================
local function ExecuteAutoType(prefix, searchPool)
    local strikes = 0
    -- Mencoba berurutan dari list nomor 1, 2, 3..
    for _, kata in ipairs(searchPool) do
        if not autoTypeEnabled or not scriptActive then break end
        if strikes >= 4 then LblStatus.Text="BAHAYA! 4x Gagal, Manual!"; LblStatus.TextColor3=THEME.Red; task.wait(2); break end
        local ok = TypeSingleWord(kata, prefix)
        if ok then break else strikes=strikes+1 end
    end
end

-- ============================================================
-- MAIN LOOP
-- ============================================================
mainThread = task.spawn(function()
    local lastPrefix = nil; local lastSearch = nil
    while scriptActive do
        task.wait(0.1)
        if not dbLoaded then continue end
        local searchTxt = tostring(SearchBox.Text):lower():gsub("[^%a]","")
        if searchTxt~="" then
            LblJoin.Text="🔍 MODE PENCARIAN MANUAL"; LblJoin.TextColor3=THEME.Cyan
            LblPre.Text="CARI AWALAN: "..searchTxt:upper()
            LblTyping.Text="Klik kata untuk COPY 📋"
            LblStatus.Text="Membantu teman..."; LblStatus.TextColor3=THEME.Yellow
            if searchTxt~=lastSearch then lastSearch=searchTxt; updateListUI(searchTxt) end
            isTyping=false; continue
        else lastSearch=nil end

        local function isJoinedFast()
            local char = LocalPlayer.Character
            if char and char:FindFirstChild("Humanoid") then
                if char.Humanoid.Sit == false then return false end
            end
            local ok, r = pcall(function()
                local m = LocalPlayer.PlayerGui:FindFirstChild("MatchUI")
                return m and m.Enabled and m:FindFirstChild("BottomUI") and m.BottomUI.Visible
            end)
            return ok and r
        end

        if not isJoinedFast() then
            LblJoin.Text="● Belum join meja"; LblJoin.TextColor3=THEME.Red
            LblPre.Text="HURUF AWAL: -"; LblStatus.Text="Menunggu join meja..."
            LblTyping.Text="TARGET: -"
            if lastPrefix~=nil then lastPrefix=nil; setScrollPlaceholder("Silakan Join Meja.", THEME.Neon) end
            continue
        end

        LblJoin.Text="● Sudah join meja"; LblJoin.TextColor3=THEME.Neon
        local prefix = getPrefix()
        if prefix then
            if prefix~=lastPrefix then
                lastPrefix=prefix; LblPre.Text="HURUF AWAL: "..prefix:upper()
                TempIgnored = {} 
                AddLog("Prefix terbaca: " .. tostring(prefix))
                updateListUI(prefix)
            end
            if not isTyping then
                if autoTypeEnabled then
                    if currentPlayerTurn==LocalPlayer then
                        local curTick = tick()
                        local endTick = tonumber(turnDelayEnd) or 0
                        if curTick < endTick then
                            local sisaWkt = math.max(0, endTick - curTick)
                            LblStatus.Text="[DELAY] Menunggu "..string.format("%.1f", sisaWkt).."s..."
                            LblStatus.TextColor3=THEME.Yellow
                        else
                            isTyping=true; LblStatus.Text="Mendeteksi & Mengetik..."; LblStatus.TextColor3=THEME.Yellow
                            ExecuteAutoType(prefix, getSortedPool(prefix)); isTyping=false
                        end
                    else LblStatus.Text="Menunggu giliran orang lain (AUTO)..."; LblStatus.TextColor3=THEME.Red end
                else
                    LblStatus.Text="Giliranmu! (Ketik Manual / Klik List)"; LblStatus.TextColor3=THEME.Cyan
                    LblTyping.Text="Pilih dari list di atas"
                end
            end
        else
            lastPrefix=nil; LblPre.Text="HURUF AWAL: -"
            LblStatus.Text = autoTypeEnabled and "Menunggu giliran (AUTO)..." or "Menunggu giliran (MANUAL)..."
            LblStatus.TextColor3 = autoTypeEnabled and THEME.Yellow or Color3.fromRGB(255,150,50)
            LblTyping.Text="TARGET: -"; isTyping=false
        end
    end
end)

-- ============================================================
-- BUTTON EVENTS
-- ============================================================
BtnPlay.MouseButton1Click:Connect(function()
    if not dbLoaded then return end
    local st = tostring(SearchBox.Text):lower():gsub("[^%a]","")
    if st~="" then LblStatus.Text="Hapus teks pencarian dulu!"; LblStatus.TextColor3=THEME.Red; return end
    
    autoTypeEnabled = not autoTypeEnabled
    if autoTypeEnabled then
        BtnPlay.Text="Auto Play On"
        TweenService:Create(BtnPlay, TweenInfo.new(0.2), {BackgroundColor3=THEME.BtnStart}):Play()
        AddLog("Auto Play Activated")
    else
        BtnPlay.Text="Auto Play Off"
        TweenService:Create(BtnPlay, TweenInfo.new(0.2), {BackgroundColor3=THEME.BtnStop}):Play()
        AddLog("Auto Play Deactivated")
    end
    UpdateInfoUI()
end)

BtnAutoJoin.MouseButton1Click:Connect(function()
    isAutoJoin = not isAutoJoin
    if isAutoJoin then
        BtnAutoJoin.Text="Auto Join On"
        TweenService:Create(BtnAutoJoin, TweenInfo.new(0.2), {BackgroundColor3=THEME.BtnStart}):Play()
        LblAutoJoinStatus.Text="AJ Status: AKTIF"; LblAutoJoinStatus.TextColor3=THEME.Neon
        AddLog("Auto Join Activated")
    else
        BtnAutoJoin.Text="Auto Join Off"
        TweenService:Create(BtnAutoJoin, TweenInfo.new(0.2), {BackgroundColor3=THEME.BtnStop}):Play()
        LblAutoJoinStatus.Text="AJ Status: IDLE"; LblAutoJoinStatus.TextColor3=THEME.Cyan
        AddLog("Auto Join Deactivated")
    end
    UpdateInfoUI()
end)

BtnExpComb.MouseButton1Click:Connect(function()
    if setclipboard then 
        local data = { LocalDB = LocalDB, BlacklistDB = BlacklistDB }
        setclipboard(HttpService:JSONEncode(data))
        LblStatus.Text="DB & Blacklist Disalin!"; LblStatus.TextColor3=THEME.Neon
    else LblStatus.Text="Executor tidak support Copy!"; LblStatus.TextColor3=THEME.Red end
end)

BtnImpComb.MouseButton1Click:Connect(function()
    local jt = tostring(ImportBox.Text)
    if jt=="" then LblStatus.Text="Paste JSON dulu!"; LblStatus.TextColor3=THEME.Red; return end
    local ok, data = pcall(function() return HttpService:JSONDecode(jt) end)
    if ok and type(data)=="table" then
        local cntDB, cntBlk = 0, 0
        if data.LocalDB or data.BlacklistDB then
            if data.LocalDB then
                for k,v in pairs(data.LocalDB) do 
                    if #tostring(k) > 2 and not BlacklistDB[k] then LocalDB[k]=v; cntDB=cntDB+1 end
                end
            end
            if data.BlacklistDB then
                for k,v in pairs(data.BlacklistDB) do BlacklistDB[k]=v; cntBlk=cntBlk+1 end
            end
        else
            for k,v in pairs(data) do
                if #tostring(k) > 2 and not BlacklistDB[k] then LocalDB[k]=v; cntDB=cntDB+1 end
            end
        end
        SaveDatabases(); UpdateDBStatUI()
        LblStatus.Text="Imported "..cntDB.." DB & "..cntBlk.." Blk!"; LblStatus.TextColor3=THEME.Neon; ImportBox.Text=""
    else LblStatus.Text="JSON Tidak Valid!"; LblStatus.TextColor3=THEME.Red end
end)

-- ============================================================
-- DB LOADER (CLEAN LOCAL DB FROM GITHUB DUPLICATES & LENGTH < 3)
-- ============================================================
task.spawn(function()
    local totalKata = 0
    for i, url in ipairs(URLS) do
        Title.Text = "Loading DB "..i.."/"..#URLS.."..."
        local ok, res = pcall(function() return game:HttpGet(url) end)
        if ok and res then
            for line in string.gmatch(res,"[^\r\n]+") do
                local w = string.match(line,"([%a]+)")
                if w then
                    local wl = w:lower()
                    if #wl < 3 then
                        BlacklistDB[wl] = true
                    else
                        GithubDict[wl] = true
                        if RegisterWord(wl) then totalKata=totalKata+1 end
                    end
                end
            end
        end
    end

    local cleanCnt = 0
    local blkCnt = 0
    for k,_ in pairs(LocalDB) do
        if #k < 3 then
            LocalDB[k] = nil
            BlacklistDB[k] = true
            blkCnt = blkCnt + 1
        elseif GithubDict[k] then 
            LocalDB[k] = nil
            cleanCnt = cleanCnt + 1
            totalDuplicates = totalDuplicates + 1 
        end
    end
    if cleanCnt > 0 or blkCnt > 0 then SaveDatabases() end

    dbLoaded = true
    Title.Text = "PrawiraHub - Sambung Kata V2"
    LblStatus.Text = "Siap! "..math.floor(totalKata/1000).."k+ kata"..(cleanCnt>0 and " | Bersih DB:"..cleanCnt or "")
    LblStatus.TextColor3 = THEME.Neon
    UpdateDBStatUI(); UpdateRiwayatUI()
    setScrollPlaceholder("Silakan Join Meja.", THEME.Neon)
    AddLog("Database Loaded successfully")
end)

-- ============================================================
-- AUTO JOIN LOOP
-- ============================================================
task.spawn(function()
    local Remotes2 = ReplicatedStorage:WaitForChild("Remotes", 10)
    if not Remotes2 then warn("[AutoJoin] Remotes not found!"); return end
    local JoinTable = Remotes2:WaitForChild("JoinTable", 5)

    while task.wait(0.6) do
        if not scriptActive then break end
        if isAutoJoin and JoinTable then
            local curTable = LocalPlayer:GetAttribute("CurrentTable")
            if not curTable then
                JoinTable:FireServer(selectedTable)
                LblAutoJoinStatus.Text = "AJ: Mengirim Join..."
                LblAutoJoinStatus.TextColor3 = THEME.Yellow
            else
                LblAutoJoinStatus.Text = "AJ: Sudah Join Meja ✓"
                LblAutoJoinStatus.TextColor3 = THEME.Neon
            end
        end
    end
end)

-- ============================================================
-- ANTI-AFK
-- ============================================================
table.insert(scriptConnections, LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
    if LblInfo then LblInfo.Text="🛡️ Anti-AFK aktif!"; task.delay(3, UpdateInfoUI) end
end))

-- Entry Animation
MainScale.Scale = 0
TweenService:Create(MainScale, tweenBounce, {Scale=1}):Play()
