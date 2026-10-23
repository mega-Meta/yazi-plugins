-- ~/.config/yazi/plugins/mpv-play.yazi/init.lua
local SOCKET_PATH = "/tmp/mpv-socket"

local selected_or_hovered = ya.sync(function()
	-- selected files process first
	local tab, urls, paths = cx.active, {}, {}
	for i, f in pairs(tab.selected) do
		urls[i], paths[i] = f.url, tostring(f.path)
	end
	-- if not selected file then process the hovered file 
	if #paths == 0 and tab.current.hovered then
		table.insert(urls, tab.current.hovered.url)
		table.insert(paths, tostring(tab.current.hovered.path))
	end
	return urls, paths
end)

-- 發送指令給 mpv socket
local function send_mpv_cmd(cmd)
   -- local exec_str = string.format("printf %s | nc -U %s >/dev/null 2>&1", cmd, SOCKET_PATH)
   local exec_str = string.format("echo \'%s\' | nc -U %s", -- >/dev/null 2>&1", 
   cmd, 
   SOCKET_PATH)
   --ya.notify({ title = "MPV-cmd", content = tostring(exec_str), level = "info", timeout = 5 })
   os.execute(exec_str)
end

-- 顯示目前播放狀態 (OSD 通知)
local function show_status()
    local cmd = string.format("echo '{\"command\": [\"get_property\", \"medis-title\"]}' | nc -U %s >/dev/null",SOCKET_PATH)
    --local cmd = string.format("echo \'get_property\' \'media-title\' | nc -U %s 2>/dev/null",SOCKET_PATH)

    local handle = io.popen(cmd)
    if not handle then return end
    
    local result = handle:read("*a")
    handle:close()

    local title = "目前無播放音樂"
    if result and result ~= "" then
        local data = string.match(result, '"data"%s*:%s*"([^"]+)"')
        if data then
            title = data
        end
    end

    ya.notify({title = "背景播放中",content = "曲目:" .. title, level = "info", timeout = 2})
end

--- get mpv properties
local target_properties = {
    "path", "filename", "file-size", "duration", "playback-time", 
    "percent-pos", "volume", "mute", "pause", "width", "height", "fps"
}

local function dump_all_properties()
   -- print("--- MPV Properties Status ---")
    for _, prop_name in ipairs(target_properties) do
        -- 拿取原始格式 (支援 table、boolean、number 等型態)
        local value = mpv.get_property_native(prop_name)
        
        if value == nil then
            print(prop_name .. ": (nil / 不可用)")
        elseif type(value) == "table" then
            print(prop_name .. ": [Table Data]")
        else
            print(prop_name .. ": " .. tostring(value))
        end
    end
   -- print("-----------------------------")
end

-- Main program 
local M = {}

function M:entry( job)
    -- 取消 Yazi 的視覺選取狀態
    ya.emit("escape", { visual = true })

    if not job or not job.args or #job.args == 0 then
        ya.notify({ title = "MPV 錯誤", content = "未提供操作指令", level = "error", timeout = 3 })
        return
    end

    -- 解析參數：job.args[1] 會是 "play /path/to/file" 或 "pause"
    -- 我們將其切開來取得真正的操作 (op_type) 與 檔案路徑 (file_path)
    local full_arg = tostring(job.args[1])
    local op_type, file_path = string.match(full_arg, "^([^%s]+)%s*(.*)$")
    
    if not op_type then
        op_type = full_arg
    end

    -- 1. 播放功能
    if op_type == "play" then
    	
        local urls, paths = selected_or_hovered()
		if #paths == 0 then
           ya.notify({ title = "MPV 播放", content = "未選取任何檔案", level = "warn", timeout = 3 })
		end
			
        -- 先清理舊的 mpv 行程
        os.execute("killall mpv 2>/dev/null")
        -- 在背景啟動 mpv (將展開後的 file_path 加上雙引號防空格)
        local play_list = ""
        for i, src in ipairs(paths) do
			local clean_src = src:gsub("/+$", "")
			local filename = clean_src:match("^.*/([^/]+)$") or clean_src
        	if filename then
        	   play_list = play_list .. '\"' .. tostring(filename) .. '\" '
        	end
        end
        		 
        local mpv_cmd = string.format(
       		"mpv --no-video --audio-format=float --input-ipc-server=%s %s >/dev/null 2>&1 &", 
       		SOCKET_PATH, 
       		play_list
        )
        ya.notify({ title = "96-cmd", content = mpv_cmd, level = "warn", timeout = 5 })

        os.execute(mpv_cmd)
        ya.notify({ title = "MPV 播放", content = "MPV開始背景播放", -- .. tostring(play_list), 
        level = "info", timeout = 2 })

    -- 2. 停止功能
    elseif op_type == "stop" then
        os.execute("killall mpv 2>/dev/null")
        ya.notify({ title = "MPV 播放", content = "已停止所有播放", level = "info", timeout = 2 })

    -- 3. 暫停/恢復
    elseif op_type == "pause" then
        send_mpv_cmd("cycle pause")

    -- 4. 下一首
    elseif op_type == "playnext" then
        send_mpv_cmd("playlist-next")
		show_status()
    -- 5. 上一首
    elseif op_type == "playprev" then
        send_mpv_cmd("playlist-prev")
		show_status()
    -- 6. 音量增加 (+10%)
    elseif op_type == "volumeup" then
        send_mpv_cmd("add volume 10")

    -- 7. 音量減少 (-10%)
    elseif op_type == "volumedown" then
        send_mpv_cmd("add volume -15")

    -- 8. 顯示狀態
    elseif op_type == "status" then
        --show_status()
		dump_all_properties()
    -- 9. 靜音切換
    elseif op_type == "mute" then
        send_mpv_cmd("cycle mute")

    -- 10. 追加檔案到現有播放清單末尾
    elseif op_type == "add" then
        local urls, paths = selected_or_hovered()
		if #paths == 0 then
           ya.notify({ title = "MPV 播放", content = "未選取任何檔案", level = "warn", timeout = 3 })
           return
		end
		local play_list = {}
        for i, src in ipairs(paths) do
			local clean_src = src:gsub("/+$", "")
			local filename = clean_src:match("^.*/([^/]+)$") or clean_src
			--local cmd = {}
        	if filename then
        		-- 使用 mpv IPC 的 loadfile 指令追加檔案
       		 	send_mpv_cmd("loadfile " .. tostring(filename) .. " append-play")
        		
        		--send_mpv_cmd(cmd)
        
        		ya.notify({ title = "MPV 追加", content = "已將音檔加至播放清單末尾", level = "info", timeout = 2 })
        	end
         end
    else
        ya.notify({ title = "MPV 錯誤", content = "未知的指令參數: " .. op_type, level = "error", timeout = 3 })
    end
end

return M
