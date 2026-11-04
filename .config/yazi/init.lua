-- ~/.config/yazi/init.lua
function Linemode:size_and_mtime()
    local time = math.floor(self._file.cha.mtime or 0)
    if time == 0 then
        time = ""
    elseif os.date("%Y", time) == os.date("%Y") then
        time = os.date("%b %d %H:%M", time)
    else
        time = os.date("%b %d  %Y", time)
    end

    local size = self._file:size()
    local uid = self._file.cha.uid
    local user = uid and ya.user_name(uid) or "-"

    return string.format("%s %s %s", size and ya.readable_size(size) or "-", user, time)
end

-- duckdb.yazi requires setup(); every option is set explicitly so the behaviour
-- does not change with plugin defaults.
require("duckdb"):setup({
    -- Default view; `M` (or `K` at the top of a file) toggles to "summarized".
    mode = "standard",
    -- Row numbers only while scrolled sideways, always as the left-most column.
    row_id = "dynamic",
    -- Rows cached for standard mode. Run `yazi --clear-cache` after changing it.
    cache_size = 1000,
    -- Characters shown in the min/max columns of summarized mode.
    minmax_column_width = 21,
    -- Average characters per column, used to decide how many columns to fetch.
    -- Tuned per the README: at 10.0 a file of 7-char columns drew the right border
    -- with 22 columns still hidden; 7.73 keeps overspilling even then.
    column_fit_factor = 7.73,
})
