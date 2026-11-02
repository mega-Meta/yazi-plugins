--- @since 26.8.15
--- to get selected or hovered files or directories 
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

-- get current working directory (CWD) by ya.sync
local get_current_cwd = ya.sync(function()
	return tostring(cx.active.current.cwd)
end)

-- get path of history records
local function get_history_filepath()
	local home = os.getenv("HOME") or os.getenv("USERPROFILE")
	if not home then return nil end
	return home .. "/.config/yazi/copyto_history"
end

-- get history records from path(get_history_filepath())
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

-- save and freash history records by stack mode, maximum limit can be modify by you
local function save_history(new_dir)
	local path = get_history_filepath()
	if not path or not new_dir or new_dir == "" then return end

	local home = os.getenv("HOME") or os.getenv("USERPROFILE")
	local new_dir_display = new_dir:gsub("^" .. home, "~")

	local history = load_history()
	
	-- 移除重複的舊紀錄
	local clean_history = {}
	table.insert(clean_history, new_dir_display) -- update newest to first record
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

-- 完美分流修復版：修正直接 Enter 時的行數擷取錯誤，路徑恆定在第二行
local function pick_directory_via_fzf(default_type)
	local home = os.getenv("HOME") or os.getenv("USERPROFILE")
	if not home then
		return nil, "無法取得家目錄路徑"
	end

	local cwd = get_current_cwd()
	local history = load_history()
	local prefix_items = {}

	if default_type == "home" then
		local home_tilde = home:gsub("^" .. home, "~")
		table.insert(prefix_items, home_tilde)
	elseif default_type == "cwd" then
		local cwd_display = cwd:gsub("^" .. home, "~")
		table.insert(prefix_items, cwd_display)
	end

	for _, h in ipairs(history) do
		table.insert(prefix_items, h)
	end

	local prefix_cmd = ""
	if #prefix_items > 0 then
		local formatted = {}
		for _, item in ipairs(prefix_items) do
			table.insert(formatted, string.format("printf '%%s\\n' '%s';", item))
		end
		prefix_cmd = table.concat(formatted, " ")
	end

	local tmp_file = os.tmpname()      -- 專門存放基礎大目錄
	local tmp_subfile = os.tmpname()   -- 專門存放子目錄名稱
	local default_sub = os.date("%m%d")

	-- 修正版：不管按什麼鍵，FZF --expect 機制傳回的目標路徑永遠在第 2 行 (2p)
	local cmd_str = string.format([[
		tmp_choice=$(mktemp)
		
		# 1. 執行 FZF 選擇基礎目錄
		{ %s fd --type d --max-depth 4 . '%s' '/Volumes' | sed 's|^%s|~|'; } | awk '!seen[$0]++' | fzf --prompt '選擇目標目錄 (Enter: 直接放入 | Ctrl-N: 新增子目錄) > ' --height 40%% --expect=ctrl-n > "$tmp_choice"
		
		exit_code=$?
		if [ $exit_code -eq 0 ]; then
			key_pressed=$(sed -n '1p' "$tmp_choice")
			path_selected=$(sed -n '2p' "$tmp_choice")

			# 【關鍵核心修正】：如果路徑不為空，老老實實把第 2 行的路徑寫入暫存檔，不要再去抓第 1 行的空行！
			if [ -n "$path_selected" ]; then
				echo "$path_selected" > "%s"
				
				# 2. 如果是按 ctrl-n，才跳出輸入視窗
				if [ "$key_pressed" = "ctrl-n" ]; then
					clear
					printf "\033[1;32m目標基礎目錄：\033[0m %%s\n" "$path_selected"
					printf "\033[1;33m請輸入要新增的子目錄名稱 (預設 %s): \033[0m" "%s"
					read input_name
					if [ -z "$input_name" ]; then
						input_name="%s"
					fi
					echo "$input_name" > "%s"
				fi
			fi
		fi
		rm -f "$tmp_choice"
	]], prefix_cmd, home, home, tmp_file, default_sub, default_sub, default_sub, tmp_subfile)

	local permit = ui.hide()
	local status = Command("sh")
		:arg("-c"):arg(cmd_str)
		:stdin(Command.INHERIT)
		:stdout(Command.INHERIT)
		:stderr(Command.INHERIT)
		:status()
	permit:drop()

	-- 由 Lua 安全解析這兩個獨立通道
	local base_path, sub_name = nil, nil
	if status and status.success then
		local f1 = io.open(tmp_file, "r")
		if f1 then base_path = f1:read("*l") f1:close() end
		
		local f2 = io.open(tmp_subfile, "r")
		if f2 then sub_name = f2:read("*l") f2:close() end
	end
	
	os.remove(tmp_file)
	os.remove(tmp_subfile)

	-- 在安全可靠的 Lua 內還原與拼接真實絕對路徑
	if base_path and base_path ~= "" then
		local full_base = base_path:gsub("^~", home)
		
		if sub_name and sub_name ~= "" then
			return full_base:gsub("/+$", "") .. "/" .. sub_name, nil
		else
			return full_base, nil
		end
	end
	return nil, "取消選擇"
end

-- check files or directories existing in target path or not 
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

-- auto rename by file existing rule
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

-- popup inquiry window by fzf buildin fuction to get ors_choice (overwrite/rename/skip)decision when file existing
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

	local ors_choice = nil
	if status and status.success then
		local f = io.open(tmp_file, "r")
		if f then ors_choice = f:read("*l") f:close() end
	end
	os.remove(tmp_file)

	if ors_choice then
		if string.match(ors_choice, "覆寫") then return 1 end
		if string.match(ors_choice, "改名") then return 2 end
		if string.match(ors_choice, "忽略") then return 3 end
	end
	return nil
end

local function fail(op, s, ...)
	ya.notify {
		title = op .. " file to",
		content = string.format(s, ...),
		level = "error",
		timeout = 5,
	}
end

-- main program 
return {
	entry = function(self, job)
		ya.emit("escape", { visual = true })

		-- 修正 Yazi 傳入引數解析
		local op_type = "copy"
		if job and job.args and job.args[1] then
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

		-- 自動建立完整絕對子目錄
		if not path_exists(dest_dir) then
			local mkdir_status = Command("mkdir"):arg("-p"):arg(dest_dir):status()
			if not mkdir_status or not mkdir_status.success then
				return fail(op_name, "無法建立子目錄: %s", dest_dir)
			end
		end

		-- 逐一處理同名衝突與檔案傳輸
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

		-- 儲存歷史紀錄
		pcall(save_history, dest_dir)

		-- 刷新 Yazi 視窗
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

		if op_type == "move" then
			ya.emit("reload", {})
		end

		local home = os.getenv("HOME") or os.getenv("USERPROFILE")
		local display_path = dest_dir:gsub("^" .. home, "~")
		ya.notify { title = op_name .. "成功", content = "檔案已" .. op_name .. "至 " .. display_path, level = "info", timeout = 3 }
	end,
}
