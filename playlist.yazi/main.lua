--- @since 26.8.15

local selected_or_hovered = ya.sync(function()
	local tab, urls, paths = cx.active, {}, {}
	for i, f in pairs(tab.selected) do
		urls[i], paths[i] = f.url, tostring(f.path)
	end
	if #paths == 0 and tab.current.hovered then
		table.insert(urls, tab.current.hovered.url)
		table.insert(paths, tostring(tab.current.hovered.path))
	end
	return urls, paths
end)

-- 透過 ya.sync 安全取得當前工作目錄 (cwd)
local get_current_cwd = ya.sync(function()
	return tostring(cx.active.current.cwd)
end)

return {
	entry = function(self, job)
	ya.emit("escape", { visual = true })
	
    -- Get selected files
    local urls, selected_files = selected_or_hovered()

    if #selected_files == 0 then
        ya.notify({ title = "Playlist Generator", content = "No files selected!", level = "warn", timeout = 2 })
        return
    end

    -- Prompt user for the playlist name
    local name, value = ya.input({
        title = "Create Playlist",
        value = "playlist.m3u",
        pos = { "center", w = 50, h = 3 },
    })

    if not name or value == "" then return end

    -- Open file for writing
    local file, err = io.open(name, "w")
    if not file then
        ya.notify({ title = "Error", content = "Could not create file: " .. tostring(err), level = "error", timeout = 3 })
        return
    end
	--ya.notify ({ title = "debug", content = tostring(selected_files), level = "info", timeout = 5 })
    -- Write M3U header and selected absolute file paths
    -- 寫入 M3U 標頭與選擇的檔案絕對路徑
    file:write("#EXTM3U\n")
    for _, item in ipairs(selected_files) do
        local clean_path = tostring(item):gsub("/+$", "")
        file:write(clean_path .. "\n")
    end
    file:close()

    ya.notify({ title = "Success", content = "Playlist saved to " .. value, level = "info", timeout = 3 })
end

}
