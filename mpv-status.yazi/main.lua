-- ~/.config/yazi/plugins/mpv-status.yazi/init.lua
local M = {}

function M:entry()
    -- 透過 macOS 內建的 os.execute 抓取 mpv 的返回資料，完全避開環境變數與 Yazi shell 限制
    local handle = io.popen("echo '{\"command\": [\"get_property\", \"media-title\"]}' | /usr/bin/nc -U /tmp/mpv-socket 2>/dev/null")
    if not handle then return end
    
    local result = handle:read("*a")
    handle:close()

    local title = "目前無播放音樂"
    if result and result ~= "" then
        -- 簡單用 Lua 正則表達式精確撈出 json 中的 data 欄位，不需安裝 jq
        local data = string.match(result, '"data"%s*:%s*"([^"]+)"')
        if data then
            title = data
        end
    end

    -- 呼叫 Yazi 26.9.1 最新版內建的 ya.notify 通知元件
    ya.notify({
        title   = "背景播放中",
        content = title,
        level   = "info",
        timeout = 3,
    })
end

return M
