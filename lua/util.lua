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

local dirname = function(filename)
    local sep='/'
    local dir = filename:match("(.*"..sep..")")
    if (dir == nil) then
        dir = "."
    end
    return dir
end

local basename = function(filename)
    local sep='/'
    local name = filename:match(".*"..sep.."(.*)")
    if (name == nil) then
        name = filename
    end
    return name
end

local blame_parse = function(output)
    local commits = {}
    local hashes = {}
    local hash=""
    local commit = {}

    for index, line in ipairs(output) do 
        for k, v in line:gmatch("([a-z0-9-]+) ([^\n]+)\n?") do
            -- print(k .. ' -> ' .. v)
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

    vim.b.blamer_hash_to_commit = commits
    vim.b.blamer_line_to_hash   = hashes
end


local job_event = function(chan_id, data, event)

    if (vim.b.blamer_job_output == nil) then
        vim.b.blamer_job_output = {}
    end

    local output = vim.b.blamer_job_output

    if event == 'stdout' then
        table.move(data, 1, #data, #output + 1, output)
        vim.b.blamer_job_output = output
    elseif event == 'exit' then
        blame_parse(output)
        print("background parse complete");

        vim.b.blamer_job_id     = nil
        vim.b.blamer_job_output = nil
    end
end

local blame_launch = function(filename)
    if vim.b.blamer_job_id ~= nil then
        -- already one running
        return
    end

    -- TODO need some checking here before we actually launch a job -- 
    local dir     = dirname(filename)
    local name    = basename(filename)

    if vim.b.blamer_enabled == nil then
        -- run some checks before we actually try to blame in the background
        -- specifically we need to check to see if this file is in a git repo
        -- and if this file is part of that repo.  
        --
        -- An error code from this command means that one of the two isn't true
        local command = "git -C " .. dir .. " ls-files --error-unmatch " .. name
        local output = vim.fn.system(command)
        output = output:lower()
        if output:match("^fatal: not a git repository") or 
           output:match("^error: pathspec .* did not match any file") then
             vim.b.blamer_enabled = false
             return
        end
        vim.b.blamer_enabled = true
    end

    if vim.b.blamer_enabled == false then
        -- we've decided that we can't blame for this file.  Skip it
        return;
    end

    local command = "git -C " .. dir .. " blame --porcelain --incremental " .. name
    print("starting background blame with command: '" .. command .. "'")
    vim.b.blamer_job_id = vim.fn.jobstart(command, { on_stdout = job_event, on_exit = job_event })
    return
end

-- git_blame_line_info returns (blame_info, error)
local git_blame_line_info = function(filename, line_num)

    local err = nil

    local line_to_hash = vim.b.blamer_line_to_hash
    local hash = nil
    if line_to_hash ~= nil then
        hash = line_to_hash[line_num]
    end

    if hash == nil then
        -- start a background job to collect git blame information
        blame_launch(filename)

        -- there's nothing to show right now
        return nil, err
    end

    local hash_to_commit = vim.b.blamer_hash_to_commit
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
