local config = require(script.Parent.config)
local EnemiesUtils = {}

function EnemiesUtils.rollChance(chance: number): boolean
	assert(chance >= 0 and chance <= 100, 'chance must be between 0 and 100')
	local gen = math.random(1, 100)
	return gen >= 1 and gen <= chance
end

function EnemiesUtils.rollAttackTriggerDistance(): number
	return config.ATTACK_DISTANCE_REF - math.random() * config.ATTACK_DISTANCE_MAX_REDUCTION
end

function EnemiesUtils.rollAttackDuration(): number
	return config.ATTACK_TIME_MIN + math.random() * (config.ATTACK_TIME_MAX - config.ATTACK_TIME_MIN)
end

function EnemiesUtils.rollStunDuration(): number
	return config.STUN_TIME_MIN + math.random() * (config.STUN_TIME_MAX - config.STUN_TIME_MIN)
end

function EnemiesUtils.horizontalUnit(direction: Vector3, fallback: Vector3): Vector3
	local horizontalDirection = Vector3.new(direction.X, 0, direction.Z)
	if horizontalDirection.Magnitude == 0 then
		return fallback
	end
	return horizontalDirection.Unit
end

return EnemiesUtils
