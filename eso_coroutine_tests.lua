-- ESO Coroutine Test Suite
-- Author: TARS (your favorite fucking test writer)
-- Description: Comprehensive tests for ESO's coroutine implementation

local function EmitMessage(text)
    if text == "" then
        text = "[Empty String]"
    end

    if CHAT_ROUTER then
        CHAT_ROUTER:AddDebugMessage(text)
    elseif RequestDebugPrintText then
        RequestDebugPrintText(text)
    end
end

local function EmitTable(t, indent, tableHistory)
    indent          = indent or "."
    tableHistory    = tableHistory or {}
    
    for k, v in pairs(t)
    do
        local vType = type(v)

        EmitMessage(indent.."("..vType.."): "..tostring(k).." = "..tostring(v))
        
        if(vType == "table")
        then
            if(tableHistory[v])
            then
                EmitMessage(indent.."Avoiding cycle on table...")
            else
                tableHistory[v] = true
                EmitTable(v, indent.."  ", tableHistory)
            end
        end
    end    
end

local function d(...)    
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if(type(value) == "table")
        then
            EmitTable(value)
        else
            EmitMessage(tostring (value))
        end
    end
end

local function df(formatter, ...)
    return d(formatter:format(...))
end

local function AssertEqual(expected, actual, message)
    if expected ~= actual then
        d(string.format("Test Failed: %s\nExpected: %s\nActual: %s", message, tostring(expected), tostring(actual)))
        return false
    end
    return true
end

local function AssertNotNil(value, message)
    if value == nil then
        d(string.format("Test Failed: %s\nValue was nil!", message))
        return false
    end
    return true
end

TestCoroutine = {
    name = "CoroutineTests",
    tests = {}
}

-- Test create and basic functionality
function TestCoroutine.tests.TestCreate()
    local function dummyFunc()
        return "test complete"
    end

    local co = coroutine.create(dummyFunc)
    AssertNotNil(co, "Coroutine creation should return a thread")
    AssertEqual("thread", type(co), "Created object should be of type thread")
end

-- Test getname and setname
function TestCoroutine.tests.TestNameOperations()
    local function dummyFunc()
        return "test complete"
    end

    local co = coroutine.create(dummyFunc)
    local testName = "TestCoroutine"
    coroutine.setname(co, testName)
    AssertEqual(testName, coroutine.getname(co), "Coroutine name should match set name")
end

-- Test status transitions
function TestCoroutine.tests.TestStatus()
    local function counterFunc()
        for i = 1, 3 do
            coroutine.yield(i)
        end
        return "done"
    end

    local co = coroutine.create(counterFunc)
    AssertEqual("suspended", coroutine.status(co), "Initial status should be suspended")

    local success, value = coroutine.resume(co)
    AssertEqual(true, success, "Resume should succeed")
    AssertEqual(1, value, "First yield should return 1")
    AssertEqual("suspended", coroutine.status(co), "Status after yield should be suspended")

    success, value = coroutine.resume(co)
    AssertEqual(2, value, "Second yield should return 2")
end

-- Test running
function TestCoroutine.tests.TestRunning()
    local function checkRunning()
        -- In ESO's Lua 5.1, running() only returns the coroutine or nil
        local running = coroutine.running()
        d("Inside coroutine - running:", running)
        d("Inside coroutine - type:", type(running))

        -- Test if we get a thread back when inside a coroutine
        AssertNotNil(running, "coroutine.running() should return a thread when inside coroutine")
        AssertEqual("thread", type(running), "running() should return a thread")

        return coroutine.yield({
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

    AssertEqual(true, success, "Resume should succeed")
    AssertNotNil(result.running, "Running coroutine should not be nil")
    AssertEqual("thread", result.running_type, "Running should return a thread type")

    -- Test running() from main thread
    local mainThreadRunning = coroutine.running()
    AssertEqual(nil, mainThreadRunning, "running() should return nil in main thread")
end

-- Test wrap functionality
function TestCoroutine.tests.TestWrap()
    local function generator(max)
        for i = 1, max do
            coroutine.yield(i)
        end
    end

    local wrapped = coroutine.wrap(generator)
    AssertEqual("function", type(wrapped), "Wrap should return a function")

    local value = wrapped(3)
    AssertEqual(1, value, "First call should return 1")
    value = wrapped()
    AssertEqual(2, value, "Second call should return 2")
end

-- Test yield and resume with multiple values
function TestCoroutine.tests.TestYieldMultipleValues()
    local function multiYield()
        local a, b = coroutine.yield(1, 2, 3)
        return a, b
    end

    local co = coroutine.create(multiYield)
    local success, val1, val2, val3 = coroutine.resume(co)

    AssertEqual(true, success, "Resume should succeed")
    AssertEqual(1, val1, "First yielded value should be 1")
    AssertEqual(2, val2, "Second yielded value should be 2")
    AssertEqual(3, val3, "Third yielded value should be 3")

    success, val1, val2 = coroutine.resume(co, "test1", "test2")
    AssertEqual("test1", val1, "First returned value should match first resume argument")
    AssertEqual("test2", val2, "Second returned value should match second resume argument")
end

-- Test yielding between named coroutines
function TestCoroutine.tests.TestNamedCoroutineYields()
    -- Create two coroutines that will yield to each other
    local function pingPong(name, otherCo, count)
        for i = 1, count do
            d(string.format("%s: Yield #%d", name, i))
            coroutine.yield(i)

            -- Verify our name is still correct after yielding
            local currentName = coroutine.getname(coroutine.running())
            AssertEqual(name, currentName, string.format("Coroutine should maintain name '%s' after yield", name))
        end
        return "done"
    end

    -- Create and name our coroutines
    local co1 = coroutine.create(function() return pingPong("PING", nil, 3) end)
    local co2 = coroutine.create(function() return pingPong("PONG", nil, 3) end)

    coroutine.setname(co1, "PING")
    coroutine.setname(co2, "PONG")

    -- Verify initial names
    AssertEqual("PING", coroutine.getname(co1), "First coroutine should be named PING")
    AssertEqual("PONG", coroutine.getname(co2), "Second coroutine should be named PONG")

    -- Alternate between the coroutines
    local success1, value1 = coroutine.resume(co1)
    AssertEqual(true, success1, "First PING resume should succeed")
    AssertEqual(1, value1, "First PING yield should return 1")

    local success2, value2 = coroutine.resume(co2)
    AssertEqual(true, success2, "First PONG resume should succeed")
    AssertEqual(1, value2, "First PONG yield should return 1")

    -- Second round
    success1, value1 = coroutine.resume(co1)
    AssertEqual(true, success1, "Second PING resume should succeed")
    AssertEqual(2, value1, "Second PING yield should return 2")

    success2, value2 = coroutine.resume(co2)
    AssertEqual(true, success2, "Second PONG resume should succeed")
    AssertEqual(2, value2, "Second PONG yield should return 2")

    -- Final round
    success1, value1 = coroutine.resume(co1)
    AssertEqual(true, success1, "Third PING resume should succeed")
    AssertEqual(3, value1, "Third PING yield should return 3")

    success2, value2 = coroutine.resume(co2)
    AssertEqual(true, success2, "Third PONG resume should succeed")
    AssertEqual(3, value2, "Third PONG yield should return 3")

    -- Verify final status
    success1, value1 = coroutine.resume(co1)
    AssertEqual(true, success1, "PING should complete successfully")
    AssertEqual("done", value1, "PING should return 'done'")

    success2, value2 = coroutine.resume(co2)
    AssertEqual(true, success2, "PONG should complete successfully")
    AssertEqual("done", value2, "PONG should return 'done'")

    -- Verify final names are still correct
    AssertEqual("PING", coroutine.getname(co1), "First coroutine should still be named PING")
    AssertEqual("PONG", coroutine.getname(co2), "Second coroutine should still be named PONG")
end

-- Test complex coroutine interactions with data passing, chain execution, and error handling
function TestCoroutine.tests.TestCoroutineChainWithDataAndErrors()
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
            received = coroutine.yield({
                value = received + i, -- Add our count to received value
                message = message
            })

            -- Verify our name is still intact
            local currentName = coroutine.getname(coroutine.running())
            AssertEqual(name, currentName, string.format("Coroutine should maintain name '%s' after yield", name))

            d(string.format("%s: Received value %d", name, received))
        end
        return string.format("%s is done!", name)
    end

    -- Create our three coroutines
    local co1 = coroutine.create(function() return chainedCoroutine("PING", nil, 3) end)
    local co2 = coroutine.create(function() return chainedCoroutine("PONG", nil, 3) end)
    local co3 = coroutine.create(function() return chainedCoroutine("PANG", nil, 3) end)

    -- Set their names
    coroutine.setname(co1, "PING")
    coroutine.setname(co2, "PONG")
    coroutine.setname(co3, "PANG")

    -- Link them in a circle (each one knows who's next)
    local coMap = {
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
                AssertEqual("dead", coroutine.status(co3), "PANG should be dead after error")
                break
            else
                -- Unexpected error
                error(string.format("Unexpected error: %s", result))
            end
        end

        -- Check if coroutine is done
        if type(result) == "string" and string.find(result, "is done!") then
            d(result)
            break
        end

        -- Validate result structure
        AssertNotNil(result.value, "Yield result should contain a value")
        AssertNotNil(result.message, "Yield result should contain a message")

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
                AssertEqual("suspended", coroutine.status(co),
                    string.format("%s should be suspended before resume", name))
            elseif coroutine.status(co) ~= "dead" then
                AssertEqual("suspended", coroutine.status(co),
                    string.format("%s should be suspended when not active", name))
            end
        end
    end
end

-- Test error tracebacks in coroutines
function TestCoroutine.tests.TestCoroutineTraceback()
    local function deepFunction(level)
        if level <= 0 then
            -- Get current function name (should be 'deepFunction')
            local currentFunc = ZO_GetCurrentFunctionName()
            AssertEqual("deepFunction", currentFunc, "Current function name should be deepFunction")
            
            -- Get caller name (should be previous deepFunction or errorThrower)
            local callerFunc = ZO_GetCallerFunctionName()
            d(string.format("[TRACE] Called by: %s", callerFunc))
            
            -- Get full callstack
            local callstack = ZO_GetCallstackFunctionNames(0)  -- Get all functions
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
            AssertEqual(true, hasErrorThrower, "Callstack should contain errorThrower")
            
            error(trace)
        end
        
        -- Log the current function name at each level
        local currentFunc = ZO_GetCurrentFunctionName()
        d(string.format("Level %d - Currently in: %s", level, currentFunc))
        
        return deepFunction(level - 1)  -- Recurse deeper
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
        
        local result = deepFunction(3)  -- Start with depth of 3
        d("This line should never be reached!")
        return result
    end

    -- Create our kamikaze coroutine
    local co = coroutine.create(errorThrower)
    coroutine.setname(co, "KABOOM")

    -- Run it and capture the error
    local success, errorMsg = coroutine.resume(co)
    
    -- We expect this to fail spectacularly
    AssertEqual(false, success, "Coroutine should fail due to error")
    AssertNotNil(errorMsg, "Error message should not be nil")
    
    -- The error message should contain our custom BOOM message
    local hasBoom = string.find(errorMsg, "BOOM at the bottom!") ~= nil
    AssertEqual(true, hasBoom, "Error should contain our BOOM message")
    
    -- Debug output to see the beautiful disaster
    d("[TRACE] Captured error traceback:")
    d(errorMsg)
    
    -- Split and analyze the stack trace parts
    local traces = {}
    -- Capture everything between "stack traceback:" and the next "stack traceback:" or end
    for trace in string.gmatch(errorMsg, "stack traceback:([^s]*)") do
        table.insert(traces, trace)
    end
    
    d(string.format("[INFO] Found %d stack trace sections", #traces))
    
    -- Debug output to see what we're working with
    for i, trace in ipairs(traces) do
        d(string.format("[DEBUG] Stack trace %d:", i))
        d(trace)
    end
    
    -- Verify we have at least one stack trace
    AssertNotNil(traces[1], "Should have at least one stack trace")
    
    -- Check for tail calls in ALL stack traces
    local hasTailCalls = false
    for _, trace in ipairs(traces) do
        if string.find(trace, "%(tail call%):") then
            hasTailCalls = true
            break
        end
    end
    AssertEqual(true, hasTailCalls, "At least one stack trace should show tail calls")
    
    -- Check for local variables in ALL stack traces
    local hasLocals = false
    for _, trace in ipairs(traces) do
        if string.find(trace, "<Locals>") then
            hasLocals = true
            break
        end
    end
    AssertEqual(true, hasLocals, "At least one stack trace should show local variables")
    
    -- Use ZO_GetCallstackFunctionNames one last time to verify final state
    local finalStack = ZO_GetCallstackFunctionNames(0)
    d("[STACK] Final callstack after error:")
    for i, funcName in ipairs(finalStack) do
        d(string.format("  %d: %s", i, funcName))
    end
    
    -- Verify coroutine is dead after error
    AssertEqual("dead", coroutine.status(co), "Coroutine should be dead after error")
end

-- Test error formatting and stack trace visualization
function TestCoroutine.tests.TestErrorFormatting()
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

        -- Extract locals from traceback if present
        local locals = traceback:match("<[Ll]ocals>(.+)</[Ll]ocals>")
        if locals then
            -- Convert common ESO boolean flags
            locals = locals:gsub("=%s*F%s*[,}]", "= false%1")
            locals = locals:gsub("=%s*T%s*[,}]", "= true%1")

            -- Handle array-style tables [table:1]
            locals = locals:gsub("%[table:(%d+)%]", "{}")

            -- Convert the locals string into a proper table format
            locals = locals:gsub("=%s*{%s*}", "= {}") -- Handle empty tables

            -- Clean up the locals string to make it valid Lua
            locals = locals:gsub("=%s*{([^}]+)}", function (content)
                -- Format table contents properly
                local cleaned = content:gsub("%s+", " ")        -- Normalize whitespace
                    :gsub("([%w_]+)%s*=%s*([^,}]+)", "%1 = %2") -- Fix key-value pairs
                    :gsub(",%s*}", "}")                         -- Remove trailing commas
                return "= {" .. cleaned .. "}"
            end)

            -- Add quotes around string keys if needed
            locals = locals:gsub("([%w_]+)%s*=", function (keyName)
                -- Don't quote 'self' as it's a special case
                if keyName == "self" then return keyName .. " =" end
                return string.format("%q = ", keyName)
            end)

            local localsFunc, _ = LoadString("return {" .. locals .. "}", "locals")
            if localsFunc then
                local success, result = pcall(localsFunc)
                if success and type(result) == "table" then
                    locals = "\n|cE6CC80Locals:|r\n" .. prettyPrint(result, 1) .. "\n"
                    traceback = traceback:gsub("<[Ll]ocals>.+</[Ll]ocals>", locals)
                end
            end
        end

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
            data.nested = {
                array = {1, 2, 3},
                table = {key = "value"},
                empty = {}
            }
            -- Force an error with our complex data
            error(string.format("Complex error with data: %s", prettyPrint(data)))
        end

        local function outerFunction()
            local data = {
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
    AssertEqual(false, success, "Coroutine should fail due to error")
    AssertNotNil(errorMsg, "Error message should not be nil")

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

    -- Debug output to see our beautiful error
    d("[FORMATTED] Error message:")
    d(formattedError)

    -- Verify the formatted message contains expected elements
    AssertEqual(true, string.find(formattedError, "|cFFD700Error #1 in coroutine ComplexError|r") ~= nil,
        "Formatted message should contain colored header")
    AssertEqual(true, string.find(formattedError, "|c5C88DACall stack:|r") ~= nil,
        "Formatted message should contain call stack header")
    AssertEqual(true, string.find(formattedError, "|cE6CC80Locals:|r") ~= nil,
        "Formatted message should contain locals section")
    AssertEqual(true, string.find(formattedError, "|cFF6666Traceback:|r") ~= nil,
        "Formatted message should contain traceback header")

    -- Verify coroutine is dead after error
    AssertEqual("dead", coroutine.status(co), "Coroutine should be dead after error")
end

-- Test different ways of getting tracebacks from coroutines
function TestCoroutine.tests.TestCoroutineTracebackMethods()
    -- Create our test coroutine with nested functions to make stack more interesting
    local function deeperFunction(x)
        error("boom") -- This will show in both traces
    end
    
    local function middleFunction(x)
        return deeperFunction(x + 1) -- This should show up in traces
    end
    
    local co = coroutine.create(function() 
        local x = 42
        return middleFunction(x) -- Create a deeper stack
    end)
    
    -- Run it and capture error
    local success, err = coroutine.resume(co)
    
    -- We expect this to fail
    AssertEqual(false, success, "Coroutine should fail")
    
    -- Get both traces
    local regularTrace = debug.traceback(err, 1)
    local threadTrace = debug.traceback(co, err, 1)
    
    -- Output both for comparison
    d("[COMPARE] Regular vs Thread traceback:")
    d("Regular:", regularTrace)
    d("Thread:", threadTrace)
    
    -- Verify the thread trace is shorter (more focused)
    local regularLines = select(2, regularTrace:gsub("\n", "\n"))
    local threadLines = select(2, threadTrace:gsub("\n", "\n"))
    AssertEqual(true, threadLines < regularLines, 
        "Thread-based trace should be more focused (fewer lines)")
    
    -- Verify both traces show our local variable
    AssertEqual(true, regularTrace:find("x = 42") ~= nil, 
        "Regular trace should show local variable")
    AssertEqual(true, threadTrace:find("x = 42") ~= nil, 
        "Thread trace should show local variable")
    
    -- Verify thread trace doesn't contain UI stuff
    AssertEqual(nil, threadTrace:find("ChatSystem"),
        "Thread trace should not contain UI call stack")
end

-- Test the cursed behavior of debug.traceback
function TestCoroutine.tests.TestTracebackCursedBehavior()
    local function makeError()
        local x = 42
        error("boom")
    end

    local co = coroutine.create(makeError)
    local success, err = coroutine.resume(co)
    
    -- Test 1: Normal usage (should work)
    local trace1 = debug.traceback()
    d("[TEST1] Basic traceback:")
    d(trace1)
    AssertEqual("string", type(trace1), "Basic traceback should return string")
    
    -- Test 2: Message as number
    local trace2 = debug.traceback(42)
    d("[TEST2] Number as message:")
    d(trace2)
    AssertEqual("string", type(trace2), "Traceback with number message should return string")
    
    -- Test 3: The nil trap
    local trace3 = debug.traceback(nil, 1)
    d("[TEST3] Nil + level:")
    d(trace3)
    d("Type:", type(trace3))
    
    -- Test 4: Empty string message
    local trace4 = debug.traceback("", 1)
    d("[TEST4] Empty string + level:")
    d(trace4)
    AssertEqual("string", type(trace4), "Traceback with empty string should return string")
    
    -- Test 5: The ultimate trap
    local trace5 = debug.traceback(nil, nil, 1)
    d("[TEST5] Double nil + level:")
    d(trace5)
    d("Type:", type(trace5))
    AssertEqual("number", type(trace5), "The cursed behavior returns the last argument!")
    
    -- Test 6: Thread + nil + level (what we actually want)
    local trace6 = debug.traceback(co, nil, 1)
    d("[TEST6] Thread + nil + level (correct usage):")
    d(trace6)
    AssertEqual("string", type(trace6), "Thread-based traceback should return string")
    
    -- Test 7: Just the thread
    local trace7 = debug.traceback(co)
    d("[TEST7] Just thread:")
    d(trace7)
    AssertEqual("string", type(trace7), "Thread-only traceback should return string")
end

-- Run all tests
function TestCoroutine.RunAllTests()
    d("Starting Coroutine Tests...")
    local passCount = 0
    local totalTests = 0

    for testName, testFunc in pairs(TestCoroutine.tests) do
        totalTests = totalTests + 1
        d(string.format("Running test: %s", testName))

        local success, error = pcall(testFunc)
        if success then
            passCount = passCount + 1
            d(string.format("%s passed", testName))
        else
            d(string.format("%s failed: %s", testName, error))
        end
    end

    d(string.format("Test Results: %d/%d passed", passCount, totalTests))
end

-- /script TestCoroutine.RunAllTests()
