# Info:

See src/shared/observableTable.lua for source code

See src/shared/example1 for example

You can use the default.project.json with Rojo, or open the RBXL file to load the example and test it out yourself.

# Description:

Detect changes inside a table (supports nested tables) and replicate the changes across the network boundary. Assign access to the data initialized on the server, and allow clients to connect to them. Set rules for client to be able to update values on the server under strict conditions. All changes are batched and then manually replicated upon :replicate() call allowing full control on when replication occurs. The table will behave just like the original data, it will have the same structure, but now it will have the additional benifit of detectable and replicatable changes.