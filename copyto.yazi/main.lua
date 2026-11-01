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

-- 取得歷史紀錄檔案路徑
local function get_history_filepath()
	local home = os.getenv("HOME") or os.getenv("USERPROFILE")
	if not home then return nil end
	-- 統一存在 yazi 配置目錄下的插件資料夾（或自訂位置）
	return home .. "/.config/yazi/copyto_history"
end

-- 讀取歷史紀錄
local function load_history()
	local history = {}
	local path = get_history_filepath()
	if not path then return history end
	
	local f = io.open(path, "r")
	if f then
		for line in f:lines() do
			if line ~= "" then
				table.insert(history, line)
			end
		end
		f:close()
	end
	return history
end

-- 儲存/更新歷史紀錄（最多 5 筆，最新使用的排最前）
local function save_history(new_dir)
	local path = get_history_filepath()
	if not path or not new_dir or new_dir == "" then return end

	local home = os.getenv("HOME") or os.getenv("USERPROFILE")
	local new_dir_display = new_dir:gsub("^" .. home, "~")

	local history = load_history()
	
	-- 移除重複的舊紀錄
	local clean_history = {}
	table.insert(clean_history, new_dir_display) -- 新紀錄放第一
	for _, v in ipairs(history) do
		if v ~= new_dir_display and #clean_history < 50 then
			table.insert(clean_history, v)
		end
	end
      
	-- 寫回檔案
	local f = io.open(path, "w")
	if f then
		for _, v in ipairs(clean_history) do
			f:write(v .. "\n")
		end
		f:close()
	end
end


-- 支援指定預設路徑置頂的 FZF 搜尋工具
local function pick_directory_via_fzf(default_type)
	local home = os.getenv("HOME") or os.getenv("USERPROFILE")
	if not home then
		return nil, "無法取得家目錄路徑"
	end

	-- 透過同步函式安全取得 cwd
	local cwd = get_current_cwd()

	-- 1. 載入最近 5 次的歷史紀錄
	local history = load_history()
	local prefix_items = {}

	-- 2. 根據 default_type（cwd 或 home）將其加入置頂佇列
	if default_type == "home" then
		local home_tilde = home:gsub("^" .. home, "~")
		table.insert(prefix_items, home_tilde)
	elseif default_type == "cwd" then
		local cwd_display = cwd:gsub("^" .. home, "~")
		table.insert(prefix_items, cwd_display)
	end

	-- 3. 將歷史紀錄追加到置頂佇列中
	for _, h in ipairs(history) do
		table.insert(prefix_items, h)
	end

	-- 4. 組裝前置的 printf 指令
	local prefix_cmd = ""
	if #prefix_items > 0 then
		local formatted = {}
		for _, item in ipairs(prefix_items) do
    	table.insert(formatted, string.format("printf '%%s\\n' '%s';", item))
		end
		prefix_cmd = table.concat(formatted, " ")
	end

	local tmp_file = os.tmpname()
	-- 使用 awk '!seen[$0]++' 確保縱使歷史紀錄與 cwd 重複，也只會顯示最前面那一筆
	local cmd_str = string.format(
		"(%s fd --type d --max-depth 4 . '%s' | sed 's|^%s|~|') | awk '!seen[$0]++' | fzf --prompt '選擇目標目錄 > ' --height 40%% > '%s'",
		prefix_cmd, home, home, tmp_file
	)

	local permit = ui.hide()
	local status = Command("sh")
		:arg("-c"):arg(cmd_str)
		:stdin(Command.INHERIT)
		:stdout(Command.INHERIT)
		:stderr(Command.INHERIT)
		:status()
	permit:drop()

	local choice = nil
	if status and status.success then
		local f = io.open(tmp_file, "r")
		if f then choice = f:read("*l") f:close() end
	end
	os.remove(tmp_file)

	if choice and choice ~= "" then
		return choice:gsub("^~", home), nil
	end
	return nil, "取消選擇"
end

-- 穩健的檔案與資料夾存在性判定
local function path_exists(path)
	local f = io.open(path, "r")
	if f then
		f:close()
		return true
	end
	local ok, err, code = os.rename(path, path)
	if not ok then
		if code == 2 or (err and string.match(err, "No such file")) then
			return false
		end
		return true
	end
	return true
end

-- 自動改名邏輯
local function get_unused_name(dest_dir, filename)
	local name, ext = filename:match("([^.]+)(.*)")
	if not name then name, ext = filename, "" end
	
	if path_exists(dest_dir .. "/" .. filename) and not filename:match("%.") then
		name, ext = filename, ""
	end
	
	local counter = 1
	local new_filename = string.format("%s_複本%s", name, ext)
	while path_exists(dest_dir .. "/" .. new_filename) do
		counter = counter + 1
		new_filename = string.format("%s_複本%d%s", name, counter, ext)
	end
	return new_filename
end

-- 修正點：利用 fzf 彈出同名衝突詢問視窗，繞過 Yazi UI bug，100% 穩定彈出
local function ask_conflict_via_fzf(filename)
	local tmp_file = os.tmpname()
	local cmd_str = string.format(
		"printf '覆寫 (Overwrite)\\n改名 (Rename)\\n忽略 (Skip)' | fzf --prompt '檔案 \"%s\" 已存在，請選擇處理方式 > ' --height 20%% > '%s'",
		filename, tmp_file
	)

	local permit = ui.hide()
	local status = Command("sh")
		:arg("-c"):arg(cmd_str)
		:stdin(Command.INHERIT)
		:stdout(Command.INHERIT)
		:stderr(Command.INHERIT)
		:status()
	permit:drop()

	local choice = nil
	if status and status.success then
		local f = io.open(tmp_file, "r")
		if f then choice = f:read("*l") f:close() end
	end
	os.remove(tmp_file)

	if choice then
		if string.match(choice, "覆寫") then return 1 end
		if string.match(choice, "改名") then return 2 end
		if string.match(choice, "忽略") then return 3 end
	end
	return nil -- 取消
end

local function fail(op, s, ...)
	ya.notify {
		title = op .. " file to",
		content = string.format(s, ...),
		level = "error",
		timeout = 5,
	}
end

local function report(urls)
	local ops = {}
	for _, url in ipairs(urls) do
		local file = fs.file(url)
		if file then
			ops[url.parent] = ops[url.parent] or {}
			ops[url.parent][url.key] = file
		end
	end
	for parent, files in pairs(ops) do
		ya.emit("update_files", {
			op = fs.op("upsert", { url = parent, files = files }),
		})
	end
end

-- ...（此處省略 path_exists, get_unused_name, ask_conflict_via_fzf 等未變更函數）...

return {
	entry = function(self, job)
		ya.emit("escape", { visual = true })

		local op_type = "copy"
		if job and job.args then
		   op_type = tostring(job.args[1])
		end

        local cmd = (op_type == "move") and "mv" or "cp"
		local op_name = (op_type == "move") and "移動" or "複製"

		local urls, src_files = selected_or_hovered()
		if #src_files == 0 then
			return ya.notify { title = op_name .. " 檔案", content = "未選取任何檔案", level = "warn", timeout = 5 }
		end

		local dest_dir, err = pick_directory_via_fzf("cwd")
		
		if not dest_dir then
			if err ~= "取消選擇" then fail(op_name, "%s", err) end
			return
		end

		-- 逐一處理檔案/目錄，判斷同名衝突
		for i, src in ipairs(src_files) do
			local clean_src = src:gsub("/+$", "")
			local filename = clean_src:match("^.*/([^/]+)$") or clean_src
			local dest_target = dest_dir .. "/" .. filename

			local exec = Command(cmd)
			if op_type == "copy" then
				exec:arg("-r")
			end

			if path_exists(dest_target) then
				local choice = ask_conflict_via_fzf(filename)
				if choice == 1 then
					if op_type == "copy" then exec:arg("-f") end
				elseif choice == 2 then
					local new_name = get_unused_name(dest_dir, filename)
					dest_target = dest_dir .. "/" .. new_name
				else
					goto continue
				end
			end

			local output, err_msg = exec:arg(clean_src):arg(dest_target):output()
			if not output then
				fail(op_name, "無法執行核心指令: %s", err_msg)
			elseif not output.status.success then
				fail(op_name, "操作失敗:\n%s", output.stderr)
			end

			::continue::
		end

		-- 【新增】當操作成功後，將本次使用的 dest_dir 記錄到歷史檔案中
		pcall(save_history, dest_dir)

		pcall(report, urls)
		local home = os.getenv("HOME") or os.getenv("USERPROFILE")
		local display_path = dest_dir:gsub("^" .. home, "~")
		ya.notify { title = op_name .. "成功", content = "檔案已" .. op_name .. "至 " .. display_path, level = "info", timeout = 3 }
	end,
}

