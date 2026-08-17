--!strict

local PREVIEW_NAME = "__CameraSystemPreview"

local CameraSystemPreview = {}
CameraSystemPreview.__index = CameraSystemPreview

export type Preview = typeof(setmetatable({} :: {
	workspace: Workspace,
	folder: Folder,
}, CameraSystemPreview))

local function configureMarker(part: Part)
	part.Archivable = false
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

function CameraSystemPreview.new(workspace: Workspace): Preview
	local oldPreview = workspace:FindFirstChild(PREVIEW_NAME)
	if oldPreview ~= nil then
		oldPreview:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = PREVIEW_NAME
	folder.Archivable = false
	folder.Parent = workspace

	return setmetatable({
		workspace = workspace,
		folder = folder,
	}, CameraSystemPreview) :: Preview
end

function CameraSystemPreview.clear(self: Preview)
	for _, child in self.folder:GetChildren() do
		child:Destroy()
	end
end

function CameraSystemPreview.refresh(self: Preview, shots: { BasePart }, zones: { BasePart })
	self:clear()

	for shotIndex, shot in shots do
		local color = Color3.fromHSV(((shotIndex - 1) % 8) / 8, 0.8, 1)
		local direction = shot.CFrame.LookVector
		local lengths = { 3, 2, 1 }
		local previousDistance = 0
		for segmentIndex, length in lengths do
			local centerDistance = previousDistance + length / 2
			local segment = Instance.new("Part")
			segment.Name = string.format("Shot_%s_%d", shot.Name, segmentIndex)
			segment.Size = Vector3.new(0.18, 0.18, length)
			segment.CFrame = CFrame.lookAt(shot.Position + direction * centerDistance, shot.Position + direction * (centerDistance + 1))
			segment.Color = color
			configureMarker(segment)
			segment.Parent = self.folder
			previousDistance += length + 0.2
		end
	end

	for zoneIndex, zone in zones do
		local marker = Instance.new("Part")
		marker.Name = string.format("Zone_%s", zone.Name)
		marker.CFrame = zone.CFrame
		marker.Size = zone.Size
		marker.Color = Color3.fromHSV(((zoneIndex - 1) % 8) / 8, 0.65, 1)
		marker.Transparency = 0.75
		configureMarker(marker)
		marker.Parent = self.folder
	end
end

return CameraSystemPreview
