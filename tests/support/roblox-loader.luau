--!strict

local fs = require("@lune/fs")
local luau = require("@lune/luau")
type LuneRoblox = {
	Vector3: { new: (number, number, number) -> any },
	Vector3int16: { new: (number, number, number) -> any },
	Region3: any,
	Enum: any,
}

-- Lune exposes these runtime datatypes, but its generated module typedef omits them.
local roblox = require("@lune/roblox") :: LuneRoblox

local Loader = {}

type VirtualNode = {
	name: string,
	path: string?,
	parent: VirtualNode?,
	[string]: any,
}

local function normalizePath(path: string): string
	local parts = {}
	for part in string.gmatch(path, "[^/]+") do
		if part == ".." then
			table.remove(parts)
		elseif part ~= "." then
			table.insert(parts, part)
		end
	end
	return table.concat(parts, "/")
end

local function createNode(name: string, path: string?, parent: VirtualNode?): VirtualNode
	return {
		Name = name,
		name = name,
		path = path,
		Parent = parent,
		parent = parent,
	}
end

local function buildTree(): (VirtualNode, { [string]: VirtualNode })
	local root = createNode("src", "src", nil)
	local nodes: { [string]: VirtualNode } = {
		["src"] = root,
	}

	local function visit(directory: string, parent: VirtualNode)
		local entries = fs.readDir(directory)
		table.sort(entries)
		for _, entry in entries do
			local path = directory .. "/" .. entry
			if fs.isDir(path) then
				local node = createNode(entry, path, parent)
				parent[entry] = node
				nodes[path] = node
				visit(path, node)
			elseif fs.isFile(path) and string.match(entry, "%.luau$") then
				local name = string.gsub(entry, "%.luau$", "")
				local node = createNode(name, path, parent)
				parent[name] = node
				nodes[path] = node
			end
		end
	end

	visit("src", root)
	return root, nodes
end

local function createRandom(): any
	local Random = {}
	Random.__index = Random

	function Random.new(seed: number?): any
		local value = math.floor(seed or 0) % 2147483647
		if value == 0 then
			value = 1
		end
		return setmetatable({ state = value }, Random)
	end

	local function nextUnit(self: any): number
		self.state = (self.state * 48271) % 2147483647
		return self.state / 2147483647
	end

	function Random:NextNumber(minimum: number?, maximum: number?): number
		local value = nextUnit(self)
		if minimum == nil then
			return value
		end
		local upper = maximum or minimum
		return minimum + (upper - minimum) * value
	end

	function Random:NextInteger(minimum: number, maximum: number): number
		return math.floor(self:NextNumber() * (maximum - minimum + 1)) + minimum
	end

	function Random:Shuffle(values: { any }): ()
		for index = #values, 2, -1 do
			local other = self:NextInteger(1, index)
			values[index], values[other] = values[other], values[index]
		end
	end

	return Random
end

local _, nodes = buildTree()
local cache: { [string]: any } = {}
local loaded: { [string]: boolean } = {}

local function loadNode(node: VirtualNode): any
	assert(node.path ~= nil, "cannot require a virtual directory")
	if loaded[node.path] then
		return cache[node.path]
	end

	local source = fs.readFile(node.path)
	local environment = {
		script = node,
		Vector3 = roblox.Vector3,
		Vector3int16 = roblox.Vector3int16,
		Region3 = roblox.Region3,
		Enum = roblox.Enum,
		Random = createRandom(),
	}

	local function requireNode(target: any): any
		if type(target) == "table" and target.path ~= nil then
			return loadNode(target)
		end
		error(string.format("unsupported Roblox require target %s", tostring(target)), 2)
	end
	environment.require = requireNode

	local chunk = luau.load(source, {
		debugName = node.path,
		environment = environment,
	})
	local result = chunk()
	cache[node.path] = result
	loaded[node.path] = true
	return result
end

function Loader.load(path: string): any
	local normalizedPath = normalizePath(path)
	local node = nodes[normalizedPath]
	assert(node ~= nil, string.format("module not found: %s", normalizedPath))
	return loadNode(node)
end

return Loader
