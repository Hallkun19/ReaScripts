-- @description HL_QuickFX
-- @author halkun19
-- @version 1.0
-- @changelog 初版
-- @provides [main]=HL_QuickFX.lua
-- @link https://github.com/Hallkun19/ReaScripts
-- @about
--   # HL_QuickFX
--   A quick and easy FX search tool for REAPER.
--
--   License: MIT

if not reaper.ImGui_GetBuiltinPath then
    reaper.MB("ReaImGuiが必要です。ReaPackからインストールしてください。", "Error", 0)
    return
end

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.9'

-- ==========================================
-- 設定・変数
-- ==========================================
local ctx = ImGui.CreateContext('HL_QuickFX')
local FLT_MIN = ImGui.NumericLimits_Float()

-- フォント設定 (18px)
local font_size = 18
local font = ImGui.CreateFont('sans-serif', font_size)
ImGui.Attach(ctx, font)

local plugin_list_cache = {}
local filtered_list = {}
local search_query = ""
local filter_mode = "All" -- "All", "VST", "JS"
local selected_idx = 1
local is_open = true
local first_run = true
local focus_search = true
local scroll_to_selected = false
local frame_count = 0

-- ==========================================
-- スタイル設定
-- ==========================================
local function PushStyle()
    ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg,       0x1E1E1EFF)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg,        0x333333FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_Header,         0x3A3A3AFF)
    ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered,  0x4A4A4AFF) 
    ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive,   0x37ADEDFF) -- リスト選択時の色 (#37ADED)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button,         0x333333FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive,   0x37ADEDFF) -- ボタン押下時の色 (#37ADED)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered,  0x444444FF)
    
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 10)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding,  6)
    
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing,    0, 6) 
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding,   8, 6) 
end

local function PopStyle()
    ImGui.PopStyleColor(ctx, 8)
    ImGui.PopStyleVar(ctx, 4)
end

-- ==========================================
-- フィルタリングロジック
-- ==========================================
local function UpdateFilter()
    local f, w = {}, {}
    for s in search_query:gmatch("%S+") do table.insert(w, s:lower()) end
    
    for _, p in ipairs(plugin_list_cache) do
        local pl = p:lower()
        local type_match = (filter_mode == "All") or 
                           (filter_mode == "VST" and pl:match("^vst")) or 
                           (filter_mode == "JS" and pl:match("^js"))
        
        if type_match then
            local match_all = true
            for _, v in ipairs(w) do if not pl:match(v, 1, true) then match_all = false break end end
            if match_all then table.insert(f, p) end
        end
    end
    filtered_list = f
    selected_idx = 1
end

-- ==========================================
-- プラグイン取得・追加
-- ==========================================
local function GetPluginList()
    local list = {}
    local res_path = reaper.GetResourcePath()
    local function Add(pre, n) if n and n~="" then table.insert(list, pre..": "..n:gsub("^%s+","")) end end
    
    -- VSTとVST3の取得
    local f = io.open(res_path .. "/reaper-vstplugins64.ini", "r")
    if f then 
        for l in f:lines() do 
            local file, data = l:match("^(.-)=(.+)$")
            if file and data then
                local n = data:match(",([^,]+)$")
                if n and n ~= "" then
                    if file:lower():match("%.vst3$") then
                        Add("VST3", n)
                    else
                        Add("VST", n)
                    end
                end
            end
        end 
        f:close() 
    end
    
    -- JSFXの取得 (ファイルパスではなく表示名を抽出する)
    f = io.open(res_path .. "/reaper-jsfx.ini", "r")
    if f then 
        for l in f:lines() do 
            local file, name = l:match('^NAME%s+"([^"]+)"%s+"([^"]+)"')
            if not name then
                file = l:match('^NAME%s+"([^"]+)"')
                if file then
                    name = file:match("[^/%\\]+$") or file
                end
            end
            if name then
                name = name:gsub("^JS:%s+", "")
                Add("JS", name)
            end
        end 
        f:close() 
    end
    
    table.sort(list)
    return list
end

local function AddFX(name)
    reaper.Undo_BeginBlock()
    local count = reaper.CountSelectedTracks(0)
    for i = 0, count-1 do
        local track = reaper.GetSelectedTrack(0, i)
        if track then reaper.TrackFX_AddByName(track, name, false, -1) end
    end
    reaper.Undo_EndBlock("HL_QuickFX Add: " .. name, -1)
end

-- ==========================================
-- メインループ
-- ==========================================
local function main()
    frame_count = frame_count + 1
    PushStyle()
    ImGui.PushFont(ctx, font)
    
    if first_run then
        local mx, my = reaper.GetMousePosition()
        ImGui.SetNextWindowPos(ctx, mx - 240, my - 20)
        ImGui.SetNextWindowSize(ctx, 480, 260)
        first_run = false
    end

    local window_flags = ImGui.WindowFlags_NoTitleBar | ImGui.WindowFlags_NoResize
    local visible, open = ImGui.Begin(ctx, 'HL_QuickFX', true, window_flags)
    
    if visible then
        if frame_count > 5 and not ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_RootAndChildWindows) then
            is_open = false
        end
        if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then is_open = false end

        -- 【上部エリア】検索窓 + フィルターボタン
        ImGui.SetNextItemWidth(ctx, -190)
        
        if focus_search then
            ImGui.SetKeyboardFocusHere(ctx)
            focus_search = false
        end
        
        local changed, new_q = ImGui.InputTextWithHint(ctx, '##search', 'Search FX...', search_query)
        if changed then
            search_query = new_q
            UpdateFilter()
            scroll_to_selected = true
        end

        ImGui.SameLine(ctx)
        ImGui.Dummy(ctx, 6, 0)
        ImGui.SameLine(ctx)
        
        local btn_w = 48
        if ImGui.Button(ctx, (filter_mode == "All" and "[A]" or "All"), btn_w) then filter_mode = "All" UpdateFilter() focus_search = true end
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, (filter_mode == "VST" and "[V]" or "VST"), btn_w) then filter_mode = "VST" UpdateFilter() focus_search = true end
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, (filter_mode == "JS" and "[J]" or "JS"), btn_w) then filter_mode = "JS" UpdateFilter() focus_search = true end

        -- キー操作
        if ImGui.IsKeyPressed(ctx, ImGui.Key_UpArrow) then selected_idx = math.max(1, selected_idx - 1) scroll_to_selected = true end
        if ImGui.IsKeyPressed(ctx, ImGui.Key_DownArrow) then selected_idx = math.min(#filtered_list, selected_idx + 1) scroll_to_selected = true end

        -- 【リスト表示】
        if ImGui.BeginListBox(ctx, '##list', -FLT_MIN, -FLT_MIN) then
            for i, p in ipairs(filtered_list) do
                local is_sel = (i == selected_idx)
                
                if ImGui.Selectable(ctx, p, is_sel) then
                    AddFX(p)
                    is_open = false
                end
                
                if is_sel and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter)) then
                    AddFX(p)
                    is_open = false
                end

                if is_sel and scroll_to_selected then
                    ImGui.SetScrollHereY(ctx, 0.5)
                    scroll_to_selected = false
                end
            end
            ImGui.EndListBox(ctx)
        end
        ImGui.End(ctx)
    end

    ImGui.PopFont(ctx)
    PopStyle()

    if is_open and open then
        reaper.defer(main)
    end
end

-- 初期化
plugin_list_cache = GetPluginList()
filtered_list = plugin_list_cache
main()