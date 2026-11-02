-- unselect-all.yazi/init.lua
-- 專門為了解決跨目錄多重選擇無法快速一鍵取消的痛點

return {
	entry = function(self, job)
		-- 呼叫 Yazi 核心的 escape 事件，並指定只清除全域的選取狀態（visual = true）
		ya.emit("escape", { select = true })
		
		-- 彈出一個輕量通知，提示使用者所有選取已成功清空
		ya.notify {
			title = "選取已清空",
			content = "已一鍵取消所有跨目錄的多重選取狀態",
			level = "info",
			timeout = 2,
		}
	end,
}
