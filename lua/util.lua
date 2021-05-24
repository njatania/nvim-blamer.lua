#!/usr/bin/env lua
-- show_date_relative port from git blame.c
function show_date_relative(ts)
    local diff
    local now = os.time()

    local timestamp = tonumber(ts)
    if timestamp == nil then
        return ts
    end
    if (now < timestamp) then
        return "in the future"
    end

    diff = now - timestamp

    if (diff < 90) then
        return diff .. " seconds ago"
    end
    -- /* Turn it into minutes */
    diff = math.floor((diff + 30) / 60)
    if (diff < 90) then
        return diff .. " minutes ago"
    end

    -- /* Turn it into hours */
    diff = math.floor((diff + 30) / 60)
    if (diff < 36) then
        return diff .. " hours ago"
    end

    -- /* We deal with number of days from here on */
    diff = math.floor((diff + 12) / 24)
    if (diff < 14) then
        return diff .. " days ago"
    end

    -- /* Say weeks for the past 10 weeks or so */
    if (diff < 70) then
        return math.floor((diff + 3) / 7) .. " weeks ago"
    end

    -- /* Say months for the past 12 months or so */
    if (diff < 365) then
        return math.floor((diff + 15) / 30) .. " months ago"
    end

    -- /* Give years and months for 5 years or so */
    if (diff < 1825) then
        local totalmonths = (diff * 12 * 2 + 365) / (365 * 2)
        local years = math.floor(totalmonths / 12)
        local months = math.floor(totalmonths % 12)
        if (months) then
            local sb = years .. " years, " .. months .. (" months ago")
            return sb
        else
            local sb = years .. " years ago"
            return sb
        end
    end
    -- /* Otherwise, just years. Centuries is probably overkill. */
    return math.floor((diff + 183) / 365) .. " years ago"
end

-- Not Committed Yet
local git_not_committed_hash = '0000000000000000000000000000000000000000'

-- {
--   "filename": "lua/blamer.lua",
--   "hash": "db43ae622dbec1ba3fd8172c2d4fed1b2980c39c",
--   "summary": "fix: bypass ft list: rename LuaTree to NvimTree. do not show Not Committed Yet msg",
--
--   "committer": "荒野無燈",
--   "committer-mail": "<a@example.com>",
--   "committer-tz": "+0800",
--   "committer-time": "1610563580",
--
--   "author": "荒野無燈",
--   "author-mail": "<a@example.com>",
--   "author-time": "1610563580",
--   "author-tz": "+0800",
-- }

local job_id = nil
local job_output = {}

local hash_to_commit = {}
local line_to_hash = {}

local get_blame_info_impl = function(filename, line_num)
    return vim.fn.system(string.format('LC_ALL=C git --no-pager blame --line-porcelain -L %d,+1 %s', line_num, filename))
end

local blame_parse = function(output)
    local commits = {}
    local hashes = {}
    local hash=""
    local commit = {}

    for index, line in ipairs(output) do 
        for k, v in line:gmatch("([a-z0-9-]+) ([^\n]+)\n?") do
            print(k .. ' -> ' .. v)
            local field = k:match('^([a-z0-9-]+)')
            if field then
                if field:len() == 40 then
                    commit.hash = field

                    -- mark all of the lines that are covered by this block as being covered by this commit hash
                    local line_number, count = v:match("[0-9]+ +([0-9]+) +([0-9]+)")
                    line_number = tonumber(line_number)
                    count = tonumber(count)
                    while (count > 0) do
                        count = count - 1
                        hashes[line_number + count ] = commit.hash
                    end
                elseif field == 'filename' then
                    print "end of a block"
                    if commits[commit.hash] == nil then
                        commits[commit.hash] = commit
                    end
                    commit = {}
                else
                    if field == 'author-time' or field == 'committer-time' then
                        commit[k .. '-human'] = show_date_relative(v)
                        commit[k] = os.date('%Y-%m-%d %H:%M:%S', v)
                    else
                        commit[k] = v
                    end
                end
            end
        end
    end

    for k,v in pairs(commits) do
        print(k,v)
        for ck, cv in pairs(v) do
            print("    " .. ck .. cv)
        end
    end

    line_to_hash   = hashes
    hash_to_commit = commits
end


local job_event = function(chan_id, data, event)
    if event == 'stdout' then
        table.move(data, 1, #data, #job_output + 1, job_output)
    elseif event == 'exit' then
        vim.api.nvim_command('echomsg "background blame complete"')
        blame_parse(job_output)
        vim.api.nvim_command('echomsg "background parse complete"')

        job_id     = nil
        job_output = {}
    end
end

local blame_launch = function(filename)
    -- TODO need some checking here before we actually launch a job -- 
    print("starting background blame")
    local command = "git blame --porcelain --incremental " .. filename
    job_id = vim.fn.jobstart(command, { on_stdout = job_event, on_exit = job_event })
    return
end

-- git_blame_line_info returns (blame_info, error)
local git_blame_line_info = function(filename, line_num)

    local err = nil

    local hash = line_to_hash[line_num]
    print("hash value is: ", hash)
    if hash == nil then
        -- either this file isn't in git or our background job is running.

        print("job_id value is: ", job_id)
        if job_id == nil then
            job_id = blame_launch(filename)
        end

        -- regardless, there's nothing to show right now, so just return
        return nil, err
    end

    local info = hash_to_commit[hash]
    if info == nil then
        return nil, err
    end

    return info, err
end

local M = {
    git_blame_line_info = git_blame_line_info,
    show_date_relative = show_date_relative,
}

return M
