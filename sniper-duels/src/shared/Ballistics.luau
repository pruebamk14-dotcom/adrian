--!strict
-- Balística compartida cliente/servidor: caída de bala + intersección rayo/OBB.
-- El servidor re-simula la misma trayectoria que ve el cliente, así el
-- trazador visual y el impacto real coinciden.

local Ballistics = {}

export type Segment = {
	From: Vector3,
	To: Vector3,
	T0: number, -- tiempo de vuelo al inicio del segmento
	T1: number,
}

-- Posición analítica en tiempo t (sin resistencia del aire).
function Ballistics.PositionAt(origin: Vector3, velocity: Vector3, gravity: number, t: number): Vector3
	return origin + velocity * t + Vector3.new(0, -0.5 * gravity * t * t, 0)
end

-- Itera los segmentos de la trayectoria hasta maxDistance. El callback
-- devuelve true para detener la simulación.
function Ballistics.Trace(
	origin: Vector3,
	direction: Vector3,
	speed: number,
	gravity: number,
	maxDistance: number,
	step: number,
	callback: (Segment) -> boolean
)
	local velocity = direction.Unit * speed
	local maxTime = maxDistance / speed * 1.25
	local t = 0
	local last = origin
	while t < maxTime do
		local nt = t + step
		local pos = Ballistics.PositionAt(origin, velocity, gravity, nt)
		if callback({ From = last, To = pos, T0 = t, T1 = nt }) then
			return
		end
		last = pos
		t = nt
	end
end

-- Intersección segmento vs caja orientada (slab test en espacio local).
-- Devuelve la fracción [0,1] del segmento donde entra, o nil.
function Ballistics.SegmentOBB(from: Vector3, to: Vector3, boxCFrame: CFrame, boxSize: Vector3): number?
	local lo = boxCFrame:PointToObjectSpace(from)
	local ld = boxCFrame:PointToObjectSpace(to) - lo
	local half = boxSize * 0.5
	local tMin, tMax = 0, 1

	local axes = {
		{ lo.X, ld.X, half.X },
		{ lo.Y, ld.Y, half.Y },
		{ lo.Z, ld.Z, half.Z },
	}
	for _, a in axes do
		local o, d, h = a[1], a[2], a[3]
		if math.abs(d) < 1e-8 then
			if o < -h or o > h then
				return nil
			end
		else
			local inv = 1 / d
			local t1 = (-h - o) * inv
			local t2 = (h - o) * inv
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			tMin = math.max(tMin, t1)
			tMax = math.min(tMax, t2)
			if tMin > tMax then
				return nil
			end
		end
	end
	return tMin
end

-- Aplica dispersión cónica (grados) a una dirección.
function Ballistics.ApplySpread(direction: Vector3, degrees: number, rng: Random): Vector3
	if degrees <= 0 then
		return direction.Unit
	end
	local cf = CFrame.lookAt(Vector3.zero, direction)
	local angle = math.rad(degrees) * math.sqrt(rng:NextNumber())
	local roll = rng:NextNumber() * math.pi * 2
	return (cf * CFrame.Angles(0, 0, roll) * CFrame.Angles(angle, 0, 0)).LookVector
end

return Ballistics
