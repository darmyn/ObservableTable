local runService = game:GetService("RunService")
local players = game:GetService("Players")

local isServer = runService:IsServer()

local getInitialTableRF: RemoteFunction
local valueChangedRE: RemoteEvent

export type updateDetails = {
	key: any,
	value: any,
	tableId: number
}

type updateBatch = {updateDetails}

local observableTable = {}
observableTable.interface = {
	active = {} :: {[id]: observableTable}
}
observableTable.behavior = {}
observableTable.meta = {__index = observableTable.behavior}

local function deepCopy(original)
	local copy
	if type(original) == "table" then
		copy = {}
		for key, value in pairs(original) do
			copy[deepCopy(key)] = deepCopy(value)
		end
		setmetatable(copy, deepCopy(getmetatable(original)))
	else -- non-table types
		copy = original
	end
	return copy
end

local function serializeLookup(lookup)
	for id, t in pairs(lookup) do
		t._id = id
	end
	local output = deepCopy(lookup)
	for id, t in pairs(lookup) do
		t._id = nil
	end
	return output
end

local function deserializeLookup(serializedLookup)
	local tableMap = {}

	local function traverseTable(t)
		if t._id then
			if tableMap[t._id] then
				return tableMap[t._id]
			else
				tableMap[t._id] = t
			end
		end

		for key, value in pairs(t) do
			if type(value) == "table" then
				t[key] = traverseTable(value)
			end
		end
		t._id = nil
		return t
	end

	return traverseTable(serializedLookup)
end

local function applyMetatable(self: observableTable, copy, original)
	local mt = {
		__index = original,
		__newindex = function(t, k, v)
			local updateDetails = {
				key = k,
				value = v,
				tableId = copy._id
			}
			original[k] = v
			self._events.valueChanged:Fire(updateDetails)
			for i, batchedUpdate: updateDetails in ipairs(self._replicationBatch) do
				if batchedUpdate.key == batchedUpdate.key and batchedUpdate.tableId == updateDetails.value then
					self._replicationBatch[i] = updateDetails
					return
				end
			end
			table.insert(self._replicationBatch, updateDetails)
		end
	}
	setmetatable(copy, mt)
end

local function createCopy(self: observableTable, original)
	local copy = {}
	for key, value in pairs(original) do
		if type(value) == "table" then
			copy[key] = createCopy(self, value) 
		end
	end

	copy._id = self._nextId
	self._tableLookup[self._nextId] = original
	self._nextId += 1

	applyMetatable(self, copy, original)

	return copy
end

local function rebuildData(self: observableTable, _data)
	local lookup = self._tableLookup
	local data = _data or self.data
	local rawData = lookup[data._id]
	applyMetatable(self, data, rawData)
	for k, proxy in pairs(data) do
		if typeof(proxy) == "table" then
			rebuildData(self, proxy)
		end
	end
	return rawData
end

if isServer then
	getInitialTableRF = Instance.new("RemoteFunction")
	getInitialTableRF.Name = "getInitialTable"

	valueChangedRE = Instance.new("RemoteEvent")
	valueChangedRE.Name = "valueChanged"

	getInitialTableRF.Parent = script
	valueChangedRE.Parent = script

	getInitialTableRF.OnServerInvoke = function(player, id: id)
		local target = observableTable.interface.active[id]
		if target then
			if target:canAccess(player) then
				return target.data, serializeLookup(target._tableLookup)
			end
		end
        return
	end

	valueChangedRE.OnServerEvent:Connect(function(player: Player, id: id, updateBatch: updateDetails)
		local target = observableTable.interface.active[id]
		if target then
			if target:canAccess(player) then
				for _, batchedUpdate: updateDetails in ipairs(updateBatch) do
					local targetTable = target._tableLookup[batchedUpdate.tableId]
					if targetTable and target.auth(batchedUpdate) then
						targetTable[batchedUpdate.key] = batchedUpdate.value
						target._events.valueChanged:Fire(batchedUpdate)
					end
				end

			end
		end
	end)
else
	getInitialTableRF = script:WaitForChild("getInitialTable") :: RemoteFunction
	valueChangedRE = script:WaitForChild("valueChanged") :: RemoteEvent

	valueChangedRE.OnClientEvent:Connect(function(id: id, updateBatch: updateBatch)
		while not observableTable.interface.active[id] do
			task.wait()
		end
		local target = observableTable.interface.active[id]
		for _, batchedUpdate: updateDetails in ipairs(updateBatch) do
			target._tableLookup[batchedUpdate.tableId][batchedUpdate.key] = batchedUpdate.value
			target._events.valueChanged:Fire(batchedUpdate)
		end
	end)
end

type id = Instance & string & number
type tableId = number
type auth = (tableId, any, any) -> boolean

function observableTable.interface.new(id: id, rawData, auth: auth)
	assert(isServer, "must be called from server")
	local self = setmetatable({}, observableTable.meta)
	self._events = {
		valueChanged = Instance.new("BindableEvent")
	}
	self.signals = {
		valueChanged = self._events.valueChanged.Event
	}
	self.id = id
	self._sharedWith = {}
	self._sharedWithAll = false
	self.rawData = rawData
	self.auth = auth
	self._tableLookup = {}
	self._nextId = 1
	self._replicationBatch = {}
	self._garbage = {}
	self.data = createCopy(self, rawData)
	observableTable.interface.active[self.id] = self
	return self
end

function observableTable.interface.connect(id: id)
	assert(not isServer, "must be called from client")
	local self = setmetatable({}, observableTable.meta)
	self.id = id
	self._events = {
		valueChanged = Instance.new("BindableEvent")
	}
	self.signals = {
		valueChanged = self._events.valueChanged.Event
	}
	local data, lookup = getInitialTableRF:InvokeServer(id)
	if not data then
		warn("Attempt to access table("..id..") but permission is not granted!")
	end
	self.data = data
	self._tableLookup = deserializeLookup(lookup)
	self.rawData = rebuildData(self, self.data)
	self._replicationBatch = {}
	observableTable.interface.active[id] = self
	return self
end

function observableTable.behavior.getTableFromID(self: observableTable, id: number)
	return self._tableLookup[id]	
end


function observableTable.behavior.share(self: observableTable, sharedWith: {Player})
	for _, player in pairs(sharedWith) do
		if typeof(player) == "Instance" and player:IsA("Player") then
			self._sharedWith[player] = true
		end
	end
end

function observableTable.behavior.stopSharing(self: observableTable, player: Player)
	self._sharedWith[player] = nil
end

function observableTable.behavior.canAccess(self: observableTable, player: Player)
	if self._sharedWith[player] or self._sharedWithAll then
		return true
	else
		return false
	end
end

function observableTable.behavior.shareAll(self: observableTable, value: boolean)
	self._sharedWithAll = (value) and value or true
end

function observableTable.behavior.hide(self: observableTable, players: {Player})
	for _, player in pairs(players) do
		self._sharedWith[player] = false
	end
end

function observableTable.behavior.replicate(self: observableTable)
	if isServer then
		if self._sharedWithAll then
			for _, player in ipairs(players:GetPlayers()) do
				valueChangedRE:FireClient(player, self.id, self._replicationBatch)
			end
		else
			for player in pairs(self._sharedWith) do
				valueChangedRE:FireClient(player, self.id, self._replicationBatch)
			end
		end
	else
		valueChangedRE:FireServer(self.id, self._replicationBatch)
	end
	table.clear(self._replicationBatch)
end

function observableTable.behavior.destroy(self: observableTable)
	observableTable.interface.active[self.id] = nil
	for _, connection in ipairs(self._garbage) do
		if typeof(connection) == "Instance" then
			connection:Destroy()
		elseif typeof(connection) == "RBXScriptConnection" then
			connection:Disconnect()
		end
	end
end

type observableTable = typeof(observableTable.interface.new())

return observableTable.interface