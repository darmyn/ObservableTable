-- in this example we couple our code that handles the observed table in a module that will be required by both the server and the client
-- this allows us to take advantage of the ability to generate types describing our data so that we can assign it to the observableTable.data so we have accurate type descriptions

local runService = game:GetService("RunService")
local replicatedStorage = game:GetService("ReplicatedStorage")

local isServer = runService:IsServer()

local observableTable = require(replicatedStorage.Shared.observableTable)

local testPart1: Part
local testPart2: Part

if isServer then
	testPart1 = Instance.new("Part")
	testPart1.Name = "testPart1"

	testPart2 = Instance.new("Part")
	testPart2.Name = "testPart2"

	testPart1.Parent = workspace
	testPart2.Parent = workspace
else
	testPart1 = workspace:WaitForChild("testPart1")
	testPart2 = workspace:WaitForChild("testPart2")
end

local function makeDataTemplate()
	return {
		test1 = 23,
		test2 = false,
		test3 = true,
		test4 = nil,
		test5 = "_example_",
		test6 = testPart1,
		test7 = {
			test7A = 42,
			test7B = false,
			test7C = true,
			test7D = nil,
			test7E = "_example_",
			test7F = testPart2,
			test7G = {
				test7G1 = {
					test7G1A = false
				}
			}
		}
	}
end

type dataTemplate = typeof(makeDataTemplate())
type updateDetails = observableTable.updateDetails

-- it is important to note then when using this architecture not all 
-- types presented to you will exist in the object. The client version of 
-- observable table does not recieve all of the values during replication, only the ones that are necessary.
local observedTable
observedTable = (isServer) and observableTable.new(
	"example_1",
	makeDataTemplate(), -- the data in this table is your raw data. It is the table being observed. However, you should now use the ObservedTable.data (exact replica) in order to take advantage of the features of this module as making changes to raw data will cause changes to not be detected
	function(updateDetails: updateDetails) -- this is your authorizer. It decides whether to accept a change from the client.
		-- In this test case the server is authorizing all client changes. YOU SHOULD NEVER DO THIS.
		local tableBeingUpdated = observedTable:getTableFromID(updateDetails.tableId)
		local key = updateDetails.key
		local value = updateDetails.value
		-- insert auth logic here
		return true -- return true permits the change being authorized.
	end
) or observableTable.connect("example_1")

observedTable:shareAll() --> you can share to individual clients using share({Player})

observedTable.signals.valueChanged:Connect(function(updateDetails: updateDetails)
	-- print fancy message displaying the update details
	local output = ""
	if isServer then
		output ..= "Server: "
	else
		output ..= "Client: "
	end
	output ..= "Table("..updateDetails.tableId..") -> "..tostring(updateDetails.key).." = "..tostring(updateDetails.value)
	print(output) --> description of value update
	print(observedTable.rawData) --> displays raw data after the update so you can see the changes in output
end)

local tableAccessor = observedTable.data :: dataTemplate

if isServer then
	tableAccessor.test1 *= tableAccessor.test7.test7A
	tableAccessor.test2 = not tableAccessor.test2
	tableAccessor.test3 = "_swapped_type_"
	tableAccessor.test4 = true
	observedTable:replicate() -- in my test cases, these changes get replicated to nobody, as no players have loaded in the game. 
	-- Instead, these changes are simply passed to the client as the initial table.
	task.wait(8)
	tableAccessor.test5 = 5329087239057
	tableAccessor.test6 = testPart2
	tableAccessor.test7.test7A -= 21
	print(observedTable)
	observedTable:replicate()
else
	tableAccessor.test1 /= 2
	observedTable:replicate()
	tableAccessor.test7.test7B = true --> this change happens immediately upon client connection
	task.wait(10)
	observedTable:replicate() --> the changes never replicate to the server until long after
end

return observedTable