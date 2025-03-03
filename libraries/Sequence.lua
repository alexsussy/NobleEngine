--
-- Sequence library created by Nic Magnier
-- https://github.com/NicMagnier/PlaydateSequence
--

--[[
class to create simple animations using easing as building blocks

To create a simple sequence:
	animation = Sequence.new():from(0):to(1,2.0,"outQuad"):mirror()

In your game loop
	Sequence.update()
	currentValue = animation:get()

Add hooks or callback
	animation = Sequence.new():from(0):to(1,2.0,"outQuad"):callback(function() print("end animation") end):mirror()
]]--
import 'CoreLibs/easing'

Sequence = {}
Sequence.__index = Sequence

-- private member
local _easings = playdate.easingFunctions
if not _easings then
	print("Sequence warning: easing function not found. Don't forget to call import 'CoreLibs/easing'")
	return
end

local _runningSequences = table.create(32,0)


-- This can be useful when you want your Sequence to continue in realtime
-- when using playdate.stop() / .wait(milliseconds) / .start().
--
-- If you don't set __currentTime, it defaults to playdate.getCurrentTimeMilliseconds()
-- Examples:
-- Use Sequence.setPreviousUpdateTime() before you call playdate.start().
-- Use Sequence.setPreviousUpdateTime(playdate.getCurrentTimeMilliseconds() + milliseconds)
-- before using playdate.wait(milliseconds).
function Sequence.setPreviousUpdateTime(currentTime)
	if (currentTime == nil) then
		currentTime = playdate.getCurrentTimeMilliseconds()
	end

	_previousUpdateTime = currentTime
end

-- create a new sequence

function Sequence.new()
	local new_sequence = {
		-- runtime values
		time = 0,  -- in ms
		cachedResultTimestamp = nil,
		cachedResult = 0,
		previousUpdateEasingIndex = nil,
		isRunning = false,

		duration = 0,  -- in ms
		loopType = false,
		easings = table.create(4, 0),
		easingCount = 0,
		callbacks = nil,
	}

	return setmetatable(new_sequence, Sequence)
end

-- put a low pacing to slow down all animations, great for tweaking
function Sequence.update( pacing )
	pacing = pacing or 1
	local deltaTime = math.floor(Noble.getDeltaTime() * 1000 * pacing)  -- Convert seconds to milliseconds

	for index = #_runningSequences, 1, -1 do
		local seq = _runningSequences[index]

		if seq.isRunning == true then
			local previousTime = seq.time

			seq.time = seq.time + deltaTime
			seq.cachedResultTimestamp = nil
			
			seq:triggerCallbacks( previousTime, seq.time )

			if seq:isDone() then
				seq.isRunning = false
			end
		end

		if seq.isRunning == false then
			table.remove(_runningSequences, index)
		end
	end
end

function Sequence.print()
	local seqs = sequence.getRunningSequencesDbg()

	print("Sequences running:", #seqs)
	for index, seq in pairs(seqs) do
		print(" Sequence", index, seq)
	end
end

function Sequence:clear()
	self:stop()
	self.time = 0
	self.duration = 0
	self.loopType = false
	self.easingCount = 0
	self.cachedResultTimestamp = nil
	self.cachedResult = 0
	self.previousUpdateEasingIndex = nil
	self.callbacks = {}
end

-- Reinitialize the sequence
function Sequence:from( from )
	from = from or 0

	-- release all easings
	self:clear()

	-- setup first empty easing at the beginning of the sequence
	local newEasing = self:newEasing()
	newEasing.timestamp = 0 -- in ms
	newEasing.from = from -- in ms
	newEasing.to = from -- in ms
	newEasing.duration = 0 -- in ms
	newEasing.fn = _easings.flat

	return self
end

function Sequence:to( to, duration, easingFunction, ... )
	if not self then return end

	-- default parameters
	to = to or 0
	duration = toMilliseconds(duration) or 300
	easingFunction = easingFunction or _easings.inOutQuad
	if type(easingFunction)=="string" then
		easingFunction = _easings[easingFunction] or _easings.inOutQuad
	end

	local lastEasing = self.easings[self.easingCount]
	local newEasing = self:newEasing()

	-- setup first empty easing at the beginning of the sequence
	newEasing.timestamp = lastEasing.timestamp + lastEasing.duration
	newEasing.from = lastEasing.to
	newEasing.to = to
	newEasing.duration = duration
	newEasing.fn = easingFunction
	newEasing.params = {...}

	-- update overall sequence infos
	self.duration = self.duration + duration

	return self
end

function Sequence:set( value )
	if not self then return end

	local lastEasing = self.easings[self.easingCount]
	local newEasing = self:newEasing()

	-- setup first empty easing at the beginning of the sequence
	newEasing.timestamp = lastEasing.timestamp + lastEasing.duration
	newEasing.from = value
	newEasing.to = value
	newEasing.duration = 0
	newEasing.fn = _easings.flat

	return self
end

-- @repeatCount: number of times the last easing as to be duplicated
-- @mirror: bool, does the repeating easings have to be mirrored (yoyo effect)
function Sequence:again( repeatCount, mirror )
	if not self then return end

	repeatCount = repeatCount or 1

	local previousEasing = self.easings[self.easingCount]

	for i = 1, repeatCount do
		local newEasing = self:newEasing()

		-- setup first empty easing at the beginning of the sequence
		newEasing.timestamp = previousEasing.timestamp + previousEasing.duration
		newEasing.duration = previousEasing.duration
		newEasing.fn = previousEasing.fn
		newEasing.params = previousEasing.params

		if mirror then
			newEasing.from = previousEasing.to
			newEasing.to = previousEasing.from
		else
			newEasing.from = previousEasing.from
			newEasing.to = previousEasing.to
		end

		-- update overall sequence infos
		self.duration = self.duration + newEasing.duration

		previousEasing = newEasing
	end

	return self
end

function Sequence:sleep( duration )
	if not self then return end

	duration = toMilliseconds(duration) or 500
	if duration==0 then
		return self
	end

	local lastEasing = self.easings[self.easingCount]
	local new_easing = self:newEasing()

	-- setup first empty easing at the beginning of the sequence
	new_easing.timestamp = lastEasing.timestamp + lastEasing.duration
	new_easing.from = lastEasing.to
	new_easing.to = lastEasing.to
	new_easing.duration = duration
	new_easing.fn = _easings.flat

	-- update overall sequence infos
	self.duration = self.duration + duration

	return self
end

function Sequence:callback( fn, timeOffset )
	if not self then return end

	timeOffset = toMilliseconds(timeOffset) or 0

	local lastEasing = self.easings[self.easingCount]

	local cb = self:newCallback()
	cb.timestamp = lastEasing.timestamp + lastEasing.duration + timeOffset
	cb.fn = fn

	return self
end

function Sequence:loop()
	self.loopType = "loop"
	return self
end

function Sequence:mirror()
	self.loopType = "mirror"
	return self
end

function Sequence:newEasing()
	self.easingCount = self.easingCount + 1
	return self:getEasingByIndex(self.easingCount)
end

function Sequence:newCallback()
	local newCallback = {
		fn = nil,
		timestamp = nil,
	}
	table.insert( self.callbacks, newCallback)
	return newCallback
end

function Sequence:getEasingByIndex( index )

	local easing = self.easings[index]
	if type(easing)=="table" then
		easing.params = nil
		easing.callback = nil
		return easing
	end

	local new_easing = {
		timestamp = 0,
		from = 0,
		to = 0,
		duration = 0,
		params = nil,
		fn = _easings.flat
	}

	self.easings[index] = new_easing

	return new_easing
end

function Sequence:getEasingByTime( clampedTime )
	if self:isEmpty() then
		print("Sequence warning: empty animation")
		return nil
	end

	local easingIndex = self.previousUpdateEasingIndex or 1
	local foundEasing = false

	while easingIndex>=1 and easingIndex<=self.easingCount do
		local easing = self.easings[easingIndex]

		if clampedTime < easing.timestamp then
			easingIndex = easingIndex - 1
		elseif clampedTime > (easing.timestamp+easing.duration) then
			easingIndex = easingIndex + 1
		elseif clampedTime == (easing.timestamp+easing.duration) then
			-- if the time is in between two easings, we prioritize the highest index (if it exists)
			if self.easings[easingIndex + 1] then
				easingIndex = easingIndex + 1
			else
				foundEasing = true
			end
		else
			foundEasing = true
		end

		if foundEasing then
			self.previousUpdateEasingIndex = easingIndex
			return easing, easingIndex
		end
	end

	-- we didn't the correct part
	print("Sequence warning: couldn't find sequence part. clampedTime probably out of bound.", clampedTime, self.duration)
	return self.easings[1]
end

function Sequence:get( time )
	if not self then return nil end

	if self:isEmpty() then
		return 0
	end

	time = toMilliseconds(time) or self.time

	-- try to get cached result
	if self.cachedResultTimestamp==time then
		return self.cachedResult
	end

	-- we calculate and cache the result
	local clampedTime = self:getClampedTime(time)
	local easing = self:getEasingByTime(clampedTime)
	local result
	if easing.duration == 0 then
		result = easing.to
	else
		result = easing.fn(clampedTime-easing.timestamp, easing.from, easing.to-easing.from, easing.duration, table.unpack(easing.params or {}))
	end
	
	-- cache
	self.cachedResultTimestamp = clampedTime
	self.cachedResult = result

	return result
end

function Sequence:triggerCallbacks( startTime, endTime )
	if #self.callbacks==0 then
		return
	end
	if endTime<=startTime then
		return
	end

	local deltaTime = endTime - startTime
	
	local triggerCallbacksClampedTimeRange = function( clampedStart, clampedEnd)
		local isForward = true
		if clampedStart>clampedEnd then
			clampedStart, clampedEnd = clampedEnd, clampedStart
			isForward = false
		end

		for index, cbObject in pairs(self.callbacks) do
			local doTrigger = false

			if cbObject.timestamp>clampedStart and cbObject.timestamp<clampedEnd then
				doTrigger = true
			elseif isForward and cbObject.timestamp==clampedEnd then
				doTrigger = true
			elseif isForward==false and cbObject.timestamp==clampedStart then
				doTrigger = true
			elseif clampedStart==0 and cbObject.timestamp==0 and isForward then
				doTrigger = true
			end

			if doTrigger and type(cbObject.fn)=="function" then
				cbObject.fn()
			end
		end
	end

	-- most straightforward case: no loop
	if not self.loopType then
		local startTimeClamped = self:getClampedTime( startTime )
		triggerCallbacksClampedTimeRange(startTimeClamped, startTimeClamped+deltaTime)
		return
	end

	--
	-- now we handle loops

	-- probably rare case but we have to handle it
	if deltaTime>self.duration then
		triggerCallbacksClampedTimeRange(0, self.duration)
	end

	local startTimeClamped, isForward = self:getClampedTime( startTime )
	if isForward then
		endTime = startTimeClamped + deltaTime
	else
		endTime = startTimeClamped - deltaTime
	end

	if endTime<0 then
		triggerCallbacksClampedTimeRange(0, math.max(startTimeClamped, self:getClampedTime( endTime )))
	elseif endTime>self.duration then
		if self.loopType=="loop" then
			triggerCallbacksClampedTimeRange(startTimeClamped, self.duration)
			triggerCallbacksClampedTimeRange(0, self:getClampedTime( endTime ))
		else
			triggerCallbacksClampedTimeRange(math.min(startTimeClamped, self:getClampedTime( endTime )), self.duration)
		end
	else
		triggerCallbacksClampedTimeRange(startTimeClamped, endTime)
	end
end

-- get the time clamped in the sequence duration
-- manage time using loop setting
function Sequence:getClampedTime( time )
	time = time or self.time

	local isForward = true

	-- time is looped
	if self.loopType=="loop" then
		return math.floor(time%self.duration), isForward

	-- time is mirrored / yoyo
	elseif self.loopType=="mirror" then
		time = time%(self.duration*2)
		if time>self.duration then
			isForward = false
			time = self.duration + self.duration - time
		end

		return math.floor(time), isForward
	end

	-- time is normally clamped
	return math.clamp(time, 0, self.duration), isForward
end

function Sequence:addRunning()
	if self:isEmpty() or self.isRunning then
		return
	end

	table.insert(_runningSequences, self)
	self.isRunning = true
end

function Sequence:removeRunning()
	-- _runningSequences table will be updated in the next sequence.update() 
	self.isRunning = false
end

function Sequence:start()
	self:addRunning()
	return self
end

function Sequence:stop()
	self:removeRunning()
	self.time = 0
	self.cachedResultTimestamp = nil
	self.previousUpdateEasingIndex = nil
	return self
end

function Sequence:pause()
	self:removeRunning()
	return self
end

function Sequence:restart()
	self.time = 0
	self.cachedResultTimestamp = nil
	self.previousUpdateEasingIndex = nil
	self:start()
	return self
end

function Sequence:isDone()
    return self.time>=self.duration and (not self.loopType)
end

function Sequence:isEmpty()
    return self.easingCount==0
end

function Sequence.getRunningSequencesDbg()
	local result = {}

	for index, seq in pairs(_runningSequences) do
		if seq.isRunning then
			table.insert( result, seq)
		end
	end

	return result
end

-- new easing function
function _easings.flat(t, b, c, d)
	return b
end

math.clamp = math.clamp or function(a, min, max)
	if min > max then
		min, max = max, min
	end
	return math.max(min, math.min(max, a))
end

-- convert a floating point second to a rounded int millisecond
function toMilliseconds(seconds)
	if seconds==nil then return nil end
	return math.floor(1000*seconds)
end
