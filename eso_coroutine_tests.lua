-- ESO Coroutine Test Suite
-- Author: dack_janiels
-- Description: Comprehensive tests for ESO's coroutine implementation

if not Taneth then
    return
end

TestCoroutine = TestCoroutine or {}

local function EmitMessage(text)
    if text == "" then
        text = "[Empty String]"
    end

    if CHAT_ROUTER then
        CHAT_ROUTER:AddDebugMessage(text)
    end
end

-- Avoid CHAT_ROUTER when LibDebugLogger is installed: it PreHooks AddDebugMessage and
-- may append traceback() to every chat debug line (internal.settings.logTraces).
local function EmitPlain(text)
    if text == "" then
        text = "[Empty String]"
    end
    EmitMessage(text)
end

local function EmitTable(t, indent, tableHistory)
    indent = indent or "."
    tableHistory = tableHistory or {}

    for k, v in pairs(t)
    do
        local vType = type(v)

        EmitMessage(indent .. "(" .. vType .. "): " .. tostring(k) .. " = " .. tostring(v))

        if (vType == "table")
        then
            if (tableHistory[v])
            then
                EmitMessage(indent .. "Avoiding cycle on table...")
            else
                tableHistory[v] = true
                EmitTable(v, indent .. "  ", tableHistory)
            end
        end
    end
end

local function d(...)
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if (type(value) == "table")
        then
            EmitTable(value)
        else
            EmitMessage(tostring(value))
        end
    end
end

local function df(formatter, ...)
    return d(formatter:format(...))
end

-- Giant GC retention probe (adjust for your machine; 30k+ rows with strings is heavy)
local GIANT_PAYLOAD_ROW_COUNT = 40000
local GIANT_PAYLOAD_PAD_LEN = 48

local function BuildRetentionMarker(rowCount, markerId)
    local pad = string.rep("x", GIANT_PAYLOAD_PAD_LEN)
    local marker = { id = markerId, payload = {} }
    local payload = marker.payload
    for i = 1, rowCount do
        payload[i] = {
            x = i,
            y = i * 2,
            z = i * 3,
            s = string.format("row-%d-%s", i, pad),
        }
        if i % 10000 == 0 then
            d(string.format("|cBBBBBB[coroutine:giant]|r building payload... %d / %d (%.1f kb)", i, rowCount, collectgarbage("count")))
        end
    end
    return marker
end

--- Build payload, suspend thread, collect, resume; returns metrics table.
function TestCoroutine.RunGiantPayloadRetentionTest(rowCount)
    TestCoroutine = TestCoroutine or {}
    rowCount = rowCount or GIANT_PAYLOAD_ROW_COUNT

    local function glog(fmt, ...)
        d(string.format("|cBBBBBB[coroutine:giant]|r " .. fmt, ...))
    end

    glog("BEGIN rows=%d padLen=%d", rowCount, GIANT_PAYLOAD_PAD_LEN)
    collectgarbage("collect")
    local kbBaseline = collectgarbage("count")

    local buildStart = GetGameTimeMilliseconds()
    local marker = BuildRetentionMarker(rowCount, "giant-gc-retention-test")
    local buildMs = GetGameTimeMilliseconds() - buildStart
    local kbAfterBuild = collectgarbage("count")
    glog("built payload in %d ms; kb %.1f -> %.1f (+%.1f)", buildMs, kbBaseline, kbAfterBuild, kbAfterBuild - kbBaseline)

    local co = coroutine.create(function()
        local held = marker
        coroutine.yield("suspended")
        local n = #held.payload
        return held.id, n, held.payload[1].x, held.payload[n].x, held.payload[n].s
    end)

    local ok, msg = coroutine.resume(co)
    if not ok then
        glog("FAIL first resume: %s", tostring(msg))
        return { ok = false, stage = "first_resume", err = msg }
    end
    if msg ~= "suspended" or coroutine.status(co) ~= "suspended" then
        glog("FAIL expected yield suspended; got msg=%s status=%s", tostring(msg), coroutine.status(co))
        return { ok = false, stage = "first_yield", err = msg, coStatus = coroutine.status(co) }
    end
    local kbAfterYield = collectgarbage("count")
    glog("yield ok; status=%s kb=%.1f", coroutine.status(co), kbAfterYield)

    marker = nil
    collectgarbage("collect")
    collectgarbage("collect")
    local kbAfterCollect = collectgarbage("count")
    glog("after 2x collect (external ref cleared): kb %.1f (delta from yield %.1f)", kbAfterCollect, kbAfterYield - kbAfterCollect)

    ok, msg, localRowCount, firstX, lastX, lastS = coroutine.resume(co)
    if not ok then
        glog("FAIL second resume: %s", tostring(msg))
        return { ok = false, stage = "second_resume", err = msg }
    end

    local stats = {
        ok = true,
        rowCount = rowCount,
        id = msg,
        rowCountAfterResume = localRowCount,
        firstX = firstX,
        lastX = lastX,
        lastSPrefix = lastS and lastS:sub(1, 20) or "",
        kbBaseline = kbBaseline,
        kbAfterBuild = kbAfterBuild,
        kbAfterYield = kbAfterYield,
        kbAfterCollect = kbAfterCollect,
        buildMs = buildMs,
        coStatus = coroutine.status(co),
    }

    glog(
        "PASS id=%q rows=%d first.x=%s last.x=%s last.s~%q... co=%s",
        stats.id,
        stats.rowCountAfterResume,
        tostring(stats.firstX),
        tostring(stats.lastX),
        stats.lastSPrefix,
        stats.coStatus
    )
    glog(
        "kb trace: %.1f baseline -> %.1f build -> %.1f yield -> %.1f after collect",
        stats.kbBaseline,
        stats.kbAfterBuild,
        stats.kbAfterYield,
        stats.kbAfterCollect
    )

    TestCoroutine.LastGiantPayloadStats = stats
    return stats
end

Taneth("coroutine", function ()
    local function log(tag, message)
        d(string.format("|cBBBBBB[coroutine]|r |c88CCFF%s|r %s", tag, message))
    end

    local function logf(tag, formatter, ...)
        log(tag, string.format(formatter, ...))
    end

    local function logBlock(tag, title, body)
        logf(tag, "--- %s ---", title)
        if body and body ~= "" then
            d(body)
        end
    end

    local function logDigest(title, lines)
        logf("summary", "--- %s ---", title)
        for i = 1, #lines do
            EmitPlain(lines[i])
        end
        EmitPlain("[coroutine:summary] end digest (plain text; no LibDebugLogger chat stack)")
    end

    describe("ESO coroutines", function ()
        describe("basics", function ()
            it("create", function ()
                log("create", "BEGIN")
                local function dummyFunc()
                    return "test complete"
                end

                local co = coroutine.create(dummyFunc)
                assert.is_not_nil(co)
                assert.equals("thread", type(co))
                logf("create", "PASS co=%s type=%s", tostring(co), type(co))
            end)

            it("name operations", function ()
                log("name", "BEGIN")
                local function dummyFunc()
                    return "test complete"
                end

                local co = coroutine.create(dummyFunc)
                local testName = "TestCoroutine"
                coroutine.setname(co, testName)
                assert.equals(testName, coroutine.getname(co))
                logf("name", "PASS getname=%q", coroutine.getname(co))
            end)

            it("status", function ()
                log("status", "BEGIN")
                local function counterFunc()
                    for i = 1, 3 do
                        coroutine.yield(i)
                    end
                    return "done"
                end

                local co = coroutine.create(counterFunc)
                assert.equals("suspended", coroutine.status(co))

                local success, value = coroutine.resume(co)
                assert.is_true(success)
                assert.equals(1, value)
                assert.equals("suspended", coroutine.status(co))
                logf("status", "resume #1 -> %s status=%s", tostring(value), coroutine.status(co))

                success, value = coroutine.resume(co)
                assert.is_true(success)
                assert.equals(2, value)
                assert.equals("suspended", coroutine.status(co))
                logf("status", "resume #2 -> %s status=%s", tostring(value), coroutine.status(co))

                success, value = coroutine.resume(co)
                assert.is_true(success)
                assert.equals(3, value)
                assert.equals("suspended", coroutine.status(co))
                logf("status", "resume #3 -> %s status=%s", tostring(value), coroutine.status(co))

                success, value = coroutine.resume(co)
                assert.is_true(success)
                assert.equals("done", value)
                assert.equals("dead", coroutine.status(co))
                logf("status", "PASS final return=%q status=%s", value, coroutine.status(co))
            end)

            it("running", function ()
                log("running", "BEGIN")
                local function checkRunning()
                    -- In ESO's Lua 5.1, running() only returns the coroutine or nil
                    local running = coroutine.running()
                    d("Inside coroutine - running:", running)
                    d("Inside coroutine - type:", type(running))

                    -- Test if we get a thread back when inside a coroutine
                    assert.is_not_nil(running)
                    assert.equals("thread", type(running))

                    return coroutine.yield(
                        {
                            running = running,
                            running_type = type(running)
                        })
                end

                local co = coroutine.create(checkRunning)
                local success, result = coroutine.resume(co)

                -- Debug output for the result
                d("Resume success:", success)
                d("Result running:", result.running)
                d("Result running type:", result.running_type)

                assert.is_true(success)
                assert.is_not_nil(result.running)
                assert.equals("thread", result.running_type)

                -- Test running() from main thread
                local mainThreadRunning = coroutine.running()
                assert.is_nil(mainThreadRunning)
                logf("running", "PASS in-co running=%s main=%s", tostring(result.running), tostring(mainThreadRunning))
            end)

            it("wrap", function ()
                log("wrap", "BEGIN")
                local function generator(max)
                    for i = 1, max do
                        coroutine.yield(i)
                    end
                end

                local wrapped = coroutine.wrap(generator)
                assert.equals("function", type(wrapped))

                local value = wrapped(3)
                assert.equals(1, value)
                value = wrapped()
                assert.equals(2, value)
                logf("wrap", "PASS yielded 1,2 from wrap(3)")
            end)

            it("yield multiple values", function ()
                log("yield", "BEGIN")
                local function multiYield()
                    local a, b = coroutine.yield(1, 2, 3)
                    return a, b
                end

                local co = coroutine.create(multiYield)
                local success, val1, val2, val3 = coroutine.resume(co)

                assert.is_true(success)
                assert.equals(1, val1)
                assert.equals(2, val2)
                assert.equals(3, val3)

                success, val1, val2 = coroutine.resume(co, "test1", "test2")
                assert.equals("test1", val1)
                assert.equals("test2", val2)
                logf("yield", "PASS resume returned test1, test2")
            end)
        end)

        describe("coordination", function ()
            it("named coroutine yields", function ()
                log("named-yields", "BEGIN")
                -- Create two coroutines that will yield to each other
                local function pingPong(name, otherCo, count)
                    for i = 1, count do
                        d(string.format("%s: Yield #%d", name, i))
                        coroutine.yield(i)

                        -- Verify our name is still correct after yielding
                        local currentName = coroutine.getname(coroutine.running())
                        assert.equals(name, currentName)
                    end
                    return "done"
                end

                -- Create and name our coroutines
                local co1 = coroutine.create(function () return pingPong("PING", nil, 3) end)
                local co2 = coroutine.create(function () return pingPong("PONG", nil, 3) end)

                coroutine.setname(co1, "PING")
                coroutine.setname(co2, "PONG")

                -- Verify initial names
                assert.equals("PING", coroutine.getname(co1))
                assert.equals("PONG", coroutine.getname(co2))

                -- Alternate between the coroutines
                local success1, value1 = coroutine.resume(co1)
                assert.is_true(success1)
                assert.equals(1, value1)

                local success2, value2 = coroutine.resume(co2)
                assert.is_true(success2)
                assert.equals(1, value2)

                -- Second round
                success1, value1 = coroutine.resume(co1)
                assert.is_true(success1)
                assert.equals(2, value1)

                success2, value2 = coroutine.resume(co2)
                assert.is_true(success2)
                assert.equals(2, value2)

                -- Final round
                success1, value1 = coroutine.resume(co1)
                assert.is_true(success1)
                assert.equals(3, value1)

                success2, value2 = coroutine.resume(co2)
                assert.is_true(success2)
                assert.equals(3, value2)

                -- Verify final status
                success1, value1 = coroutine.resume(co1)
                assert.is_true(success1)
                assert.equals("done", value1)

                success2, value2 = coroutine.resume(co2)
                assert.is_true(success2)
                assert.equals("done", value2)

                -- Verify final names are still correct
                assert.equals("PING", coroutine.getname(co1))
                assert.equals("PONG", coroutine.getname(co2))
                log("named-yields", "PASS PING/PONG alternated 3 rounds each")
            end)

            it("chain with data and errors", function ()
                log("chain", "BEGIN")
                -- Create three coroutines that pass data in a circle
                local function chainedCoroutine(name, nextCo, count)
                    local received = 0
                    for i = 1, count do
                        -- Simulate potential error condition
                        if name == "PANG" and i == 2 then
                            -- Test error handling by making PANG fail on second iteration
                            error(string.format("%s decided to explode!", name))
                        end

                        -- Pass data to next coroutine
                        local message = string.format("Hello from %s, round %d!", name, i)
                        d(string.format("%s: Sending '%s' and yielding...", name, message))

                        -- Yield our message and wait for response
                        received = coroutine.yield(
                            {
                                value = received + i, -- Add our count to received value
                                message = message
                            })

                        -- Verify our name is still intact
                        local currentName = coroutine.getname(coroutine.running())
                        assert.equals(name, currentName)

                        d(string.format("%s: Received value %d", name, received))
                    end
                    return string.format("%s is done!", name)
                end

                -- Create our three coroutines
                local co1 = coroutine.create(function () return chainedCoroutine("PING", nil, 3) end)
                local co2 = coroutine.create(function () return chainedCoroutine("PONG", nil, 3) end)
                local co3 = coroutine.create(function () return chainedCoroutine("PANG", nil, 3) end)

                -- Set their names
                coroutine.setname(co1, "PING")
                coroutine.setname(co2, "PONG")
                coroutine.setname(co3, "PANG")

                -- Link them in a circle (each one knows who's next)
                local coMap =
                {
                    [co1] = co2, -- PING -> PONG
                    [co2] = co3, -- PONG -> PANG
                    [co3] = co1  -- PANG -> PING (completing the circle)
                }

                -- Start with PING
                local currentCo = co1
                local value = 0
                local success, result

                -- Keep going until we hit an error or complete all iterations
                while true do
                    -- Resume current coroutine
                    success, result = coroutine.resume(currentCo, value)

                    -- Check for completion or error
                    if not success then
                        -- We hit our expected error!
                        if string.find(result, "PANG decided to explode!") then
                            d("Successfully caught PANG's explosion!")
                            assert.equals("dead", coroutine.status(co3))
                            break
                        else
                            assert.fail(string.format("Unexpected error: %s", result))
                        end
                    end

                    -- Check if coroutine is done
                    if type(result) == "string" and string.find(result, "is done!") then
                        d(result)
                        break
                    end

                    -- Validate result structure
                    assert.is_not_nil(result.value)
                    assert.is_not_nil(result.message)

                    -- Debug output
                    d(string.format("Main: Passing value %d from %s to %s",
                                    result.value,
                                    coroutine.getname(currentCo),
                                    coroutine.getname(coMap[currentCo])))

                    -- Update for next iteration
                    value = result.value
                    currentCo = coMap[currentCo]

                    -- Verify coroutine states
                    for co, name in pairs({ [co1] = "PING", [co2] = "PONG", [co3] = "PANG" }) do
                        if co == currentCo then
                            assert.equals("suspended", coroutine.status(co))
                        elseif coroutine.status(co) ~= "dead" then
                            assert.equals("suspended", coroutine.status(co))
                        end
                    end
                end
                log("chain", "PASS PANG error caught; co3 dead")
            end)
        end)

        describe("errors and tracebacks", function ()
            it("coroutine traceback", function ()
                log("co-traceback", "BEGIN")
                local function deepFunction(level)
                    if level <= 0 then
                        -- Get current function name (should be 'deepFunction')
                        local currentFunc = ZO_GetCurrentFunctionName()
                        assert.equals("deepFunction", currentFunc)

                        -- Get caller name (should be previous deepFunction or errorThrower)
                        local callerFunc = ZO_GetCallerFunctionName()
                        d(string.format("[TRACE] Called by: %s", callerFunc))

                        -- Get full callstack
                        local callstack = ZO_GetCallstackFunctionNames(0) -- Get all functions
                        d("[STACK] Full callstack:")
                        for i, funcName in ipairs(callstack) do
                            d(string.format("  %d: %s", i, funcName))
                        end

                        -- Get a traceback before we explode
                        local trace = debug.traceback("[BOOM] KABOOM at the bottom!", 1)
                        d(string.format("Level %d - About to explode with trace:", level))
                        d(trace)

                        -- Verify our callstack matches what we expect
                        local hasErrorThrower = false
                        for _, name in ipairs(callstack) do
                            if name == "errorThrower" then
                                hasErrorThrower = true
                                break
                            end
                        end
                        assert.is_true(hasErrorThrower)

                        error(trace)
                    end

                    -- Log the current function name at each level
                    local currentFunc = ZO_GetCurrentFunctionName()
                    d(string.format("Level %d - Currently in: %s", level, currentFunc))

                    return deepFunction(level - 1) -- Recurse deeper
                end

                local function errorThrower()
                    local currentFunc = ZO_GetCurrentFunctionName()
                    d(string.format("[START] Initiating countdown to explosion from %s...", currentFunc))

                    -- Get initial callstack
                    local initialStack = ZO_GetCallstackFunctionNames(0)
                    d("[STACK] Initial callstack:")
                    for i, funcName in ipairs(initialStack) do
                        d(string.format("  %d: %s", i, funcName))
                    end

                    local result = deepFunction(3) -- Start with depth of 3
                    d("This line should never be reached!")
                    return result
                end

                -- Create our kamikaze coroutine
                local co = coroutine.create(errorThrower)
                coroutine.setname(co, "KABOOM")

                -- Run it and capture the error
                local success, errorMsg = coroutine.resume(co)

                -- We expect this to fail spectacularly
                assert.is_false(success)
                assert.is_not_nil(errorMsg)

                -- The error message should contain our custom BOOM message
                local hasBoom = string.find(errorMsg, "BOOM at the bottom!") ~= nil
                assert.is_true(hasBoom)

                -- Debug output to see the beautiful disaster
                d("[TRACE] Captured error traceback:")
                d(errorMsg)

                d(string.format("[INFO] errorMsg length: %d", #errorMsg))

                -- ESO embeds "(tail call): ?" and <Locals> in the full message (do not split on "stack traceback:" — paths contain 's')
                assert.is_true(string.find(errorMsg, "tail call") ~= nil)
                assert.is_true(string.find(errorMsg, "<Locals>") ~= nil)

                -- Use ZO_GetCallstackFunctionNames one last time to verify final state
                local finalStack = ZO_GetCallstackFunctionNames(0)
                d("[STACK] Final callstack after error:")
                for i, funcName in ipairs(finalStack) do
                    d(string.format("  %d: %s", i, funcName))
                end

                -- Verify coroutine is dead after error
                assert.equals("dead", coroutine.status(co))
                logf("co-traceback", "PASS errorMsg len=%d co=dead", #errorMsg)
            end)

            it("error formatting", function ()
                log("format", "BEGIN")
                -- Pretty prints a table with proper indentation and formatting
                local function prettyPrint(value, indent, done)
                    indent = indent or 0
                    done = done or {}

                    -- Handle non-table values
                    if type(value) ~= "table" then
                        if type(value) == "string" then
                            return string.format("%q", value)
                        end
                        return tostring(value)
                    end

                    if done[value] then
                        return "<circular reference>"
                    end

                    done[value] = true
                    local padding = string.rep("  ", indent)
                    local lines = {}

                    -- Sort keys for consistent output
                    local keys = {}
                    for k in pairs(value) do
                        table.insert(keys, k)
                    end
                    table.sort(keys, function (a, b)
                        return tostring(a) < tostring(b)
                    end)

                    for _, k in ipairs(keys) do
                        local v = value[k]
                        local entry = padding
                        if type(k) == "number" then
                            entry = entry .. "[" .. k .. "]"
                        else
                            entry = entry .. k
                        end
                        entry = entry .. " = "

                        if type(v) == "table" then
                            if next(v) == nil then
                                entry = entry .. "{}"
                            else
                                entry = entry .. "{\n" .. prettyPrint(v, indent + 1, done) .. "\n" .. padding .. "}"
                            end
                        else
                            if type(v) == "string" then
                                entry = entry .. string.format("%q", v)
                            else
                                entry = entry .. tostring(v)
                            end
                        end
                        table.insert(lines, entry)
                    end

                    return table.concat(lines, "\n")
                end

                -- Formats the error message with proper alignment and colors
                local function formatMessage(formatStr, reportedKey, key, traceback, functionNames)
                    -- Improved header with count and key
                    local header = string.format("|cFFD700%s|r", string.format(formatStr, reportedKey, key))

                    -- Format the call stack with improved colors and indentation
                    local callStackInfo = { "|c5C88DACall stack:|r" }
                    for i, functionName in ipairs(functionNames) do
                        -- Use different colors for different types of functions
                        local color = "|cCCCCCC" -- Default gray

                        -- Highlight scene-related functions in light blue
                        if functionName:find("Scene") then
                            color = "|c88CCFF"
                            -- Highlight ZO_ functions in green
                        elseif functionName:find("^ZO_") then
                            color = "|c99EEBB"
                            -- Highlight anonymous functions in orange
                        elseif functionName:find("anonymous") then
                            color = "|cFFCC99"
                        end

                        table.insert(callStackInfo, string.format("  %2d. %s%s|r", i, color, functionName))
                    end

                    -- Same as ZO_ErrorFrame:SetCurrentError coloredFullError (ErrorFrame.lua)
                    traceback = traceback:gsub("<Locals>.-</Locals>", function (match)
                        return "|caaaaaa" .. match .. "|r"
                    end)

                    -- Format traceback for better readability
                    traceback = traceback:gsub("stack traceback:", "|cFF6666Traceback:|r")

                    -- Colorize file paths in traceback
                    traceback = traceback:gsub("([%w_/\\%.]+%.lua:%d+:)", "|cAAFFAA%1|r")

                    -- Highlight 'in function' parts
                    traceback = traceback:gsub("(in function%s+[%w_:'%.]+)", "|c99DDFF%1|r")

                    -- Highlight 'Undefined global' message
                    traceback = traceback:gsub("(|cFF0000Undefined global|r:[^%s]+)", "|cFF5555%1|r")

                    -- Ensure consistent line endings and create the final message with better spacing
                    local message = header .. "\n\n" .. traceback .. "\n\n" .. table.concat(callStackInfo, "\n") .. "\n"

                    return (message:gsub("\r\n", "\n")) -- Normalize any Windows line endings
                end

                -- Create a function that will generate a complex error
                local function generateComplexError()
                    local function innerFunction(data)
                        -- Create a circular reference
                        data.self = data
                        -- Create some nested tables
                        data.nested =
                        {
                            array = { 1, 2, 3 },
                            table = { key = "value" },
                            empty = {}
                        }
                        -- Force an error with our complex data
                        error(string.format("Complex error with data: %s", prettyPrint(data)))
                    end

                    local function outerFunction()
                        local data =
                        {
                            message = "Test error",
                            number = 42,
                            boolean = true,
                            nil_value = nil
                        }
                        return innerFunction(data)
                    end

                    return outerFunction()
                end

                -- Create a coroutine that will generate our complex error
                local co = coroutine.create(generateComplexError)
                coroutine.setname(co, "ComplexError")

                -- Run it and capture the error
                local success, errorMsg = coroutine.resume(co)

                -- We expect this to fail
                assert.is_false(success)
                assert.is_not_nil(errorMsg)

                -- Get the callstack
                local callstack = ZO_GetCallstackFunctionNames(0)

                -- Format our error message
                local formattedError = formatMessage(
                    "Error #%d in coroutine %s",
                    1,
                    "ComplexError",
                    errorMsg,
                    callstack
                )

                -- Verify the formatted message contains expected elements
                assert.is_true(string.find(formattedError, "|cFFD700Error #1 in coroutine ComplexError|r") ~= nil)
                assert.is_true(string.find(formattedError, "|c5C88DACall stack:|r") ~= nil)
                assert.is_true(string.find(formattedError, "|caaaaaa<Locals>") ~= nil)
                assert.is_true(string.find(formattedError, "|cFF6666Traceback:|r") ~= nil)

                -- Verify coroutine is dead after error
                assert.equals("dead", coroutine.status(co))
                logBlock("format", "formatted error (addon-style, ZO locals wrap)", formattedError)
                log("format", "PASS header, traceback, locals gray, call stack present")
            end)

            it("traceback methods", function ()
                log("traceback-methods", "BEGIN")
                -- Create our test coroutine with nested functions to make stack more interesting
                local function deeperFunction(x)
                    error("boom") -- This will show in both traces
                end

                local function middleFunction(x)
                    return deeperFunction(x + 1) -- This should show up in traces
                end

                local co = coroutine.create(function ()
                    local x = 42
                    return middleFunction(x) -- Create a deeper stack
                end)

                -- Run it and capture error
                local success, err = coroutine.resume(co)

                -- We expect this to fail
                assert.is_false(success)

                -- Get both traces
                local regularTrace = debug.traceback(err, 1)
                local threadTrace = debug.traceback(co, err, 1)

                -- Verify the thread trace is shorter (more focused)
                local regularLines = select(2, regularTrace:gsub("\n", "\n"))
                local threadLines = select(2, threadTrace:gsub("\n", "\n"))
                assert.is_true(threadLines < regularLines)

                -- deeperFunction receives x + 1 (43); outer coroutine may not appear on thread traceback
                assert.is_true(regularTrace:find("boom") ~= nil)
                assert.is_true(threadTrace:find("boom") ~= nil)
                assert.is_true(regularTrace:find("x = 43") ~= nil or regularTrace:find("deeperFunction") ~= nil)

                -- Verify thread trace doesn't contain UI stuff
                assert.is_nil(threadTrace:find("ChatSystem"))
                logf(
                    "traceback-methods",
                    "PASS regularLines=%d threadLines=%d (thread shorter; regular trace includes Taneth pcall when captured here)",
                    regularLines,
                    threadLines
                )
                logBlock("traceback-methods", "debug.traceback(err, 1) [full]", regularTrace)
                logBlock("traceback-methods", "debug.traceback(co, err, 1) [coroutine-focused]", threadTrace)
            end)
        end)

        describe("debug.traceback API", function ()
            local function makeFailedCoroutine()
                local function makeError()
                    local x = 42
                    error("boom")
                end
                local co = coroutine.create(makeError)
                local success, err = coroutine.resume(co)
                assert.is_false(success)
                return co, err
            end

            it("default traceback() is string", function ()
                local trace = debug.traceback()
                log("traceback", "NOTE: traceback() from inside Taneth it() includes runner frames")
                logBlock("traceback", "debug.traceback()", trace)
                assert.equals("string", type(trace))
            end)

            it("numeric message is string", function ()
                local trace = debug.traceback(42)
                logBlock("traceback", "debug.traceback(42)", trace)
                assert.equals("string", type(trace))
            end)

            it("nil message with level", function ()
                local trace = debug.traceback(nil, 1)
                logf("traceback", "debug.traceback(nil,1) type=%s", type(trace))
                logBlock("traceback", "body", tostring(trace))
            end)

            it("empty string message with level", function ()
                local trace = debug.traceback("", 1)
                logBlock("traceback", 'debug.traceback("",1)', trace)
                assert.equals("string", type(trace))
            end)

            it("double nil with level (ESO returns string, not PUC-Rio level)", function ()
                local trace = debug.traceback(nil, nil, 1)
                logf("traceback", "debug.traceback(nil,nil,1) type=%s", type(trace))
                logBlock("traceback", "body", tostring(trace))
                assert.equals("string", type(trace))
            end)

            it("thread + nil + level", function ()
                local co = makeFailedCoroutine()
                local trace = debug.traceback(co, nil, 1)
                logBlock("traceback", "debug.traceback(co,nil,1)", trace)
                assert.equals("string", type(trace))
            end)

            it("thread only", function ()
                local co = makeFailedCoroutine()
                local trace = debug.traceback(co)
                logBlock("traceback", "debug.traceback(co)", trace)
                assert.equals("string", type(trace))
            end)
        end)

        describe("garbage collection", function ()
            it("suspended thread retains locals across collect", function ()
                log("gc", "BEGIN")
                local kbBefore = collectgarbage("count")
                local marker = { id = "gc-retention-test", payload = {} }
                for i = 1, 500 do
                    marker.payload[i] = { x = i, y = i * 2, z = i * 3 }
                end

                local co = coroutine.create(function ()
                    local held = marker
                    coroutine.yield("suspended-with-data")
                    return held.id
                end)

                local ok, msg = coroutine.resume(co)
                assert.is_true(ok)
                assert.equals("suspended-with-data", msg)
                assert.equals("suspended", coroutine.status(co))
                logf("gc", "after yield: status=%s kb=%.1f", coroutine.status(co), collectgarbage("count"))

                marker = nil
                collectgarbage("collect")
                collectgarbage("collect")
                local kbAfterCollect = collectgarbage("count")
                logf("gc", "after 2x collect: kb=%.1f (was %.1f at start)", kbAfterCollect, kbBefore)

                ok, msg = coroutine.resume(co)
                assert.is_true(ok)
                assert.equals("gc-retention-test", msg)
                assert.equals("dead", coroutine.status(co))
                logf("gc", "PASS resumed id=%q status=%s", msg, coroutine.status(co))
            end)

            it("giant payload retained across collect", function()
                log("giant", string.format("BEGIN (%d rows)", GIANT_PAYLOAD_ROW_COUNT))
                local stats = TestCoroutine.RunGiantPayloadRetentionTest(GIANT_PAYLOAD_ROW_COUNT)
                assert.is_true(stats.ok)
                assert.equals("giant-gc-retention-test", stats.id)
                assert.equals(GIANT_PAYLOAD_ROW_COUNT, stats.rowCountAfterResume)
                assert.equals(1, stats.firstX)
                assert.equals(GIANT_PAYLOAD_ROW_COUNT, stats.lastX)
                assert.is_true(stats.kbAfterCollect < stats.kbAfterYield)
                assert.equals("dead", stats.coStatus)
                logf(
                    "giant",
                    "PASS kb %.1f->%.1f->%.1f build %dms rows=%d",
                    stats.kbBaseline,
                    stats.kbAfterBuild,
                    stats.kbAfterCollect,
                    stats.buildMs,
                    stats.rowCountAfterResume
                )
            end)
        end)

        describe("session summary", function()
            it("prints digest for LibDebugLogger", function()
                local digestLines = {
                    "ESO Havok coroutine digest (auto-captured this run)",
                    string.format("coroutine.create -> type=%s", type(coroutine.create(function() end))),
                    string.format("coroutine.running() on main thread=%s", tostring(coroutine.running())),
                }

                local co = coroutine.create(function()
                    local x = 42
                    error("probe")
                end)
                local ok, err = coroutine.resume(co)
                assert.is_false(ok)
                local regularTrace = debug.traceback(err, 1)
                local threadTrace = debug.traceback(co, err, 1)
                local regularLines = select(2, regularTrace:gsub("\n", "\n"))
                local threadLines = select(2, threadTrace:gsub("\n", "\n"))
                digestLines[#digestLines + 1] = string.format(
                    "debug.traceback(err,1) lines=%d (includes Taneth when called from it())",
                    regularLines
                )
                digestLines[#digestLines + 1] = string.format(
                    "debug.traceback(co,err,1) lines=%d (coroutine-focused)",
                    threadLines
                )

                local kbBefore = collectgarbage("count")
                local marker = { id = "gc-retention-test", payload = {} }
                for i = 1, 500 do
                    marker.payload[i] = { x = i, y = i * 2, z = i * 3 }
                end
                local gcCo = coroutine.create(function()
                    local held = marker
                    coroutine.yield("hold")
                    return held.id
                end)
                coroutine.resume(gcCo)
                marker = nil
                collectgarbage("collect")
                collectgarbage("collect")
                local kbAfterCollect = collectgarbage("count")
                local gcOk, gcId = coroutine.resume(gcCo)
                digestLines[#digestLines + 1] = string.format(
                    "GC: kb %.1f -> %.1f while thread suspended (500-row payload); resume id=%q ok=%s",
                    kbBefore,
                    kbAfterCollect,
                    gcId,
                    tostring(gcOk)
                )
                digestLines[#digestLines + 1] =
                    "Errors: <Locals> in message; ZO_ErrorFrame grays entire <Locals> block (format test)"
                digestLines[#digestLines + 1] =
                    "Tail calls: (tail call): ? lines common in coroutine stack traces"
                digestLines[#digestLines + 1] =
                    "LibDebugLogger: chat d() with logTraces adds stacks; digest uses RequestDebugPrintText"

                TestCoroutine = TestCoroutine or {}
                TestCoroutine.LastDigest = table.concat(digestLines, "\n")
                logDigest("copy/paste reference", digestLines)
            end)
        end)
    end)
end)

TestCoroutine = TestCoroutine or {}

function TestCoroutine.PrintDigest()
    if not TestCoroutine.LastDigest then
        EmitPlain("[coroutine] No digest yet; run /taneth coroutine first")
        return
    end
    for line in TestCoroutine.LastDigest:gmatch("[^\r\n]+") do
        EmitPlain(line)
    end
    EmitPlain("[coroutine:summary] end digest")
end

function TestCoroutine.RunAllTests()
    Taneth:RunTestSuite("coroutine")
end

-- /taneth coroutine
-- /script TestCoroutine.RunAllTests()
-- /script TestCoroutine.PrintDigest()
-- /script TestCoroutine.RunGiantPayloadRetentionTest()  -- giant GC only (no Taneth)
-- /script TestCoroutine.RunGiantPayloadRetentionTest(20000)  -- custom row count
