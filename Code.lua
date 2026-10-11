-- Reaver Vandal replacer (same engine as dragon_skin.lua / archrambit_skin.lua)
-- Meshes, sounds + icons are all downloaded from GitHub the first time and cached in <executor workspace>/Vandal/
--
-- Credits: Sounds + model - @𝕯𝖊𝖒𝖔𝖓𝖙
--          Splitting the model up + baking textures + config work - @randomck23

local CONFIG = [==[
{
  "replacement_rules": [
    {
      "type": "group", "name": "Model",
      "children": [
        { "name": "Body Replace",  "replace_ids": [12613284036], "mode": "cdn", "enabled": true, "cdn_url": "https://github.com/mrbeanissohot/Bean-sVandal/raw/refs/heads/main/reaver_body.mesh" },
        { "name": "Upper Replace", "replace_ids": [12613284249], "mode": "cdn", "enabled": true, "cdn_url": "https://github.com/mrbeanissohot/Bean-sVandal/raw/refs/heads/main/reaver_bits.mesh" },
        { "name": "Bolt Replace",  "replace_ids": [12613283355], "mode": "cdn", "enabled": true, "cdn_url": "https://github.com/mrbeanissohot/Bean-sVandal/raw/refs/heads/main/reaver_bolt.mesh" },
        { "name": "Mag Replace",   "replace_ids": [12613284529], "mode": "cdn", "enabled": true, "cdn_url": "https://github.com/mrbeanissohot/Bean-sVandal/raw/refs/heads/main/reaver_mag.mesh" },
        { "name": "Hide Extras",   "replace_ids": [12613283569, 14652718299, 12613284768], "mode": "id", "enabled": true }
      ]
    },
    {
      "type": "group", "name": "Sound",
      "children": [
        { "name": "Shoot Replace", "replace_ids": [13087362838], "mode": "cdn", "enabled": true, "cdn_url": "https://github.com/mrbeanissohot/Bean-sVandal/raw/refs/heads/main/reaver%20shoot.mp3" },
        { "name": "Reload Replace1", "replace_ids": [13236549929, 13236549962], "mode": "cdn", "enabled": true, "cdn_url": "https://github.com/mrbeanissohot/Bean-sVandal/raw/refs/heads/main/reaver%20load1.mp3" },
        { "name": "Reload Replace", "replace_ids": [13455395017], "mode": "cdn", "enabled": true, "cdn_url": "https://github.com/mrbeanissohot/Bean-sVandal/raw/refs/heads/main/reaver%20load2.mp3" }
      ]
    },
    {
      "type": "group", "name": "Icon",
      "children": [
        { "name": "Icon Replace 1", "replace_ids": [17160682738], "mode": "cdn", "enabled": true, "cdn_url": "https://github.com/mrbeanissohot/Bean-sVandal/raw/refs/heads/main/reaver%20vandel%20thumbnail.png" },
        { "name": "Icon Replace 2", "replace_ids": [13197584241], "mode": "cdn", "enabled": true, "cdn_url": "https://github.com/mrbeanissohot/Bean-sVandal/raw/refs/heads/main/reaver%20vandel%20thumbnail%202.png" }
      ]
    }
  ]
}
]==]

local FOLDER = "Vandal"
local SCALE = 1.35      -- size multiplier for the replaced meshes
-- "native" = each mesh uses its own real size (x SCALE)  <- try this first
-- "keep"   = keep the old part's size (x SCALE), mesh gets fitted into it
local SIZE_MODE = "native"
-- performance settings
local WATCH_ALL = false        -- true = listen for changes on EVERY mesh/decal (old behaviour, laggy). false = only on matched ones
local RESCAN_INTERVAL = 0      -- seconds between full rescans of the game. 0 = off (DescendantAdded already catches new parts)
local NIL_SCAN_INTERVAL = 15   -- seconds between scans of nil-parented instances. 0 = off
local REFRESH = false       -- true = delete cached sound/icon downloads and download again

---------------------------------------------------------------------
local missing = {}
for _, p in ipairs({
	{ "isfile", isfile }, { "writefile", writefile }, { "getcustomasset", getcustomasset },
	{ "makefolder", makefolder }, { "isfolder", isfolder },
}) do
	if type(p[2]) ~= "function" then missing[#missing + 1] = p[1] end
end
if #missing > 0 then
	warn("[Vandal] executor is missing: " .. table.concat(missing, ", ") .. " - cannot run")
	return
end

if not isfolder(FOLDER) then pcall(makefolder, FOLDER) end
if REFRESH and listfiles and delfile then
	for _, f in ipairs(listfiles(FOLDER)) do
		if not f:lower():find("%.mesh$") then pcall(delfile, f) end -- keeps your meshes
	end
	print("[Vandal] download cache cleared")
end

local HttpService = game:GetService("HttpService")
local AssetService = game:GetService("AssetService")
local rules = HttpService:JSONDecode(CONFIG).replacement_rules
local lookup, cache, meshCache = {}, {}, {}
local registered, skipped, swapped = 0, 0, 0
local failedList = {}

local function parseId(v)
	return tonumber(tostring(v):match("(%d+)"))
end

local function loadAsset(path)
	if cache[path] then return cache[path] end
	for _ = 1, 5 do
		if isfile(path) then
			local ok, asset = pcall(getcustomasset, path)
			if ok and asset then
				cache[path] = asset
				return asset
			end
		end
		task.wait(0.3)
	end
	return nil
end

---------------------------------------------------------------------
-- downloads (meshes + sounds + icons)
local function hashStr(s)
	local h = 5381
	for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
	return string.format("%08x", h)
end

local function download(url)
	local ok, res = pcall(function() return game:HttpGet(url) end)
	if ok and type(res) == "string" and #res > 0 then return res end
	local req = request or http_request or (syn and syn.request)
	if req then
		local ok2, r = pcall(req, { Url = url, Method = "GET" })
		if ok2 and r and r.StatusCode == 200 and type(r.Body) == "string" and #r.Body > 0 then
			return r.Body
		end
	end
	return nil
end

local function loadCdn(url)
	local clean = url:gsub("%?.*$", "")
	local name = clean:match("[^/]+$") or clean
	local ext = (clean:match("%.(%w+)$") or "bin"):lower()
	local path = FOLDER .. "/" .. hashStr(url) .. "." .. ext

	if not isfile(path) then
		print("[Vandal] downloading " .. name)
		local data = download(url)
		if not data then
			failedList[#failedList + 1] = name .. " (download failed)"
			return nil
		end
		if #data < 200 and data:find("404") then
			failedList[#failedList + 1] = name .. " (404 not found)"
			return nil
		end
		if not pcall(writefile, path, data) then
			failedList[#failedList + 1] = name .. " (could not save)"
			return nil
		end
	end
	local asset = loadAsset(path)
	if not asset then failedList[#failedList + 1] = name .. " (getcustomasset failed)" end
	return asset
end

---------------------------------------------------------------------
-- rules
local function resolve(rule)
	if rule.mode == "local" then
		local asset = loadAsset(rule.local_path)
		if not asset then failedList[#failedList + 1] = rule.local_path .. " (not found in workspace)" end
		return asset
	end
	if rule.mode == "cdn" then return loadCdn(rule.cdn_url) end
	if rule.with_id then return "rbxassetid://" .. rule.with_id end
	return ""
end

local function flatten(list, out)
	for _, r in ipairs(list) do
		if r.type == "group" then
			flatten(r.children or {}, out)
		elseif r.enabled then
			out[#out + 1] = r
		end
	end
	return out
end

-- resolve every rule at the same time
local active = flatten(rules, {})
local targets = {}
local pending = #active
for i, rule in ipairs(active) do
	task.spawn(function()
		local ok, res = pcall(resolve, rule)
		if ok then targets[i] = res end
		pending -= 1
	end)
end
while pending > 0 do task.wait() end

local meshAssets = {}
for i, rule in ipairs(active) do
	local target = targets[i]
	if target == nil then
		skipped += 1
	else
		registered += 1
		-- .mesh files carry baked vertex colours, so they need the old texture removed
		local baked = rule.mode == "cdn" and tostring(rule.cdn_url):lower():gsub("%?.*$", ""):find("%.mesh$") ~= nil
		if baked then meshAssets[target] = true end
		for _, id in ipairs(rule.replace_ids) do
			local n = parseId(id)
			if n then lookup[n] = { target = target, baked = baked } end
		end
	end
end

-- pre-load the meshes so the swap is instant
local warming = 0
for asset in pairs(meshAssets) do
	warming += 1
	task.spawn(function()
		pcall(function() meshCache[asset] = AssetService:CreateMeshPartAsync(asset) end)
		warming -= 1
	end)
end
local t0 = os.clock()
while warming > 0 and os.clock() - t0 < 15 do task.wait() end

print(("[Vandal] rules registered: %d, skipped: %d"):format(registered, skipped))
for _, f in ipairs(failedList) do warn("[Vandal] FAILED: " .. f) end

---------------------------------------------------------------------
-- apply
local PROPS = {
	MeshPart = { "MeshId" },
	SpecialMesh = { "MeshId" },
	Sound = { "SoundId" },
	Decal = { "Texture" },
	Texture = { "Texture" },
	ImageLabel = { "Image" },
	ImageButton = { "Image" },
}
-- classes whose id changes at runtime (inventory icons, sounds reused by the game)
local WATCH_ALWAYS = { Sound = true, ImageLabel = true, ImageButton = true }

local seen = setmetatable({}, { __mode = "k" })
local watched = setmetatable({}, { __mode = "k" })
local keepSize = setmetatable({}, { __mode = "k" })
local nilSeen = setmetatable({}, { __mode = "k" })

local function getProp(inst, p) return inst[p] end

local function hideMesh(inst)
	pcall(function()
		if inst:IsA("MeshPart") then
			inst.Transparency = 1
		elseif inst:IsA("SpecialMesh") then
			inst.Scale = Vector3.new(0, 0, 0)
		end
	end)
end

local function applyMesh(inst, asset)
	if inst:IsA("MeshPart") then
		local ok, err = pcall(function()
			local mp = meshCache[asset]
			if not mp then
				mp = AssetService:CreateMeshPartAsync(asset)
				meshCache[asset] = mp
			end
			inst:ApplyMesh(mp)
		end)
		if not ok then
			warn("[Vandal] ApplyMesh failed: " .. tostring(err))
			pcall(function() inst.MeshId = asset end)
		end
	else
		pcall(function() inst.MeshId = asset end)
	end
end

-- size the part so the mesh isn't stretched into the old part's box
local function sizeMesh(inst, asset)
	if not inst:IsA("MeshPart") then return end
	if not keepSize[inst] then keepSize[inst] = inst.Size end
	local ref = keepSize[inst]
	task.wait(0.1)
	pcall(function()
		if SIZE_MODE == "keep" then
			inst.Size = ref * SCALE
		else
			local mp = meshCache[asset]
			if mp then inst.Size = mp.Size * SCALE end
		end
	end)
end

-- the mesh has its colours baked in, so remove the old texture and keep it removed
local function bake(inst)
	local isMeshPart = inst:IsA("MeshPart")
	local tprop = isMeshPart and "TextureID" or "TextureId"
	pcall(function() inst[tprop] = "" end)
	pcall(function()
		if isMeshPart then
			inst.Color = Color3.new(1, 1, 1)
		else
			inst.VertexColor = Vector3.new(1, 1, 1)
		end
	end)
	for _, c in ipairs(inst:GetChildren()) do
		if c:IsA("SurfaceAppearance") then c:Destroy() end
	end
	if not watched[inst] then
		watched[inst] = true
		inst.ChildAdded:Connect(function(c)
			if c:IsA("SurfaceAppearance") then
				task.defer(function() pcall(function() c:Destroy() end) end)
			end
		end)
		pcall(function()
			inst:GetPropertyChangedSignal(tprop):Connect(function()
				if inst[tprop] ~= "" then pcall(function() inst[tprop] = "" end) end
			end)
		end)
	end
end

-- does the heavy work (may yield) for an instance that matched a rule
local function process(inst, p, entry, id)
	local new = entry.target
	swapped += 1
	if swapped <= 15 then
		print("[Vandal] swapped " .. inst.ClassName .. "." .. p .. " (" .. tostring(id) .. ")")
	end

	if p == "MeshId" then
		if new == "" then
			hideMesh(inst)
		else
			applyMesh(inst, new)
			if entry.baked then
				bake(inst)
				sizeMesh(inst, new)
			end
		end
	else
		pcall(function() inst[p] = new end)
	end
end

-- cheap check; returns true if the instance matched a rule
local function handle(inst, p)
	local ok, cur = pcall(getProp, inst, p)
	if not ok or cur == "" then return false end
	local id = parseId(cur)
	local entry = id and lookup[id]
	if not entry then return false end
	task.spawn(process, inst, p, entry, id)
	return true
end

local function apply(inst)
	local props = PROPS[inst.ClassName]
	if not props or seen[inst] then return end
	seen[inst] = true
	local always = WATCH_ALL or WATCH_ALWAYS[inst.ClassName]
	for i = 1, #props do
		local p = props[i]
		local matched = handle(inst, p)
		-- only listen for changes where it matters (matched parts, UI images, sounds)
		if matched or always then
			pcall(function()
				inst:GetPropertyChangedSignal(p):Connect(function() handle(inst, p) end)
			end)
		end
	end
end

local function scan()
	local n = 0
	for _, d in ipairs(game:GetDescendants()) do
		apply(d)
		n += 1
		if n % 1000 == 0 then task.wait() end
	end
end

local function scanNil()
	if type(getnilinstances) ~= "function" then return end
	local ok, list = pcall(getnilinstances)
	if not ok then return end
	local n = 0
	for _, d in ipairs(list) do
		if not nilSeen[d] then -- each nil root is only walked once
			nilSeen[d] = true
			apply(d)
			for _, c in ipairs(d:GetDescendants()) do
				apply(c)
				n += 1
				if n % 1000 == 0 then task.wait() end
			end
		end
	end
end

game.DescendantAdded:Connect(apply)
task.spawn(function()
	scan()
	scanNil()
	print("[Vandal] initial scan done")
end)

-- optional slow background passes
if RESCAN_INTERVAL > 0 then
	task.spawn(function()
		while true do
			task.wait(RESCAN_INTERVAL)
			scan()
		end
	end)
end
if NIL_SCAN_INTERVAL > 0 then
	task.spawn(function()
		while true do
			task.wait(NIL_SCAN_INTERVAL)
			scanNil()
		end
	end)
end

print("[Vandal] loaded")
