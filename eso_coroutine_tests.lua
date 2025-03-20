-- ESO Coroutine Test Suite
-- Author: TARS (your favorite fucking test writer)
-- Description: Comprehensive tests for ESO's coroutine implementation

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
            -- Get a traceback before we explode
            local trace = debug.traceback("BOOM at the bottom!")
            error(trace)
        end
        return deepFunction(level - 1)  -- Recurse deeper
    end

    local function errorThrower()
        d("Starting the countdown to explosion...")
        return deepFunction(3)  -- Start with depth of 3
    end

    -- Create our kamikaze coroutine
    local co = coroutine.create(errorThrower)
    coroutine.setname(co, "KABOOM")  -- Because why not name it appropriately?

    -- Run it and capture the error
    local success, errorMsg = coroutine.resume(co)
    
    -- We expect this to fail spectacularly
    AssertEqual(false, success, "Coroutine should fail due to error")
    
    -- Verify we got a proper traceback
    AssertNotNil(errorMsg, "Error message should not be nil")
    
    -- The error message should contain our custom BOOM message
    local hasBoom = string.find(errorMsg, "BOOM at the bottom!") ~= nil
    AssertEqual(true, hasBoom, "Error should contain our BOOM message")
    
    -- The traceback should show our call hierarchy
    local hasDeepFunction = string.find(errorMsg, "deepFunction") ~= nil
    AssertEqual(true, hasDeepFunction, "Traceback should show deepFunction calls")
    
    -- Debug output to see the beautiful disaster
    d("Captured error traceback:")
    d(errorMsg)
    
    -- Verify coroutine is dead after error
    AssertEqual("dead", coroutine.status(co), "Coroutine should be dead after error")
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
