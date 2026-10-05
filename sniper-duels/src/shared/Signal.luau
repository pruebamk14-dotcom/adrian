--!strict
-- Signal mínimo para comunicación entre servicios.

local Signal = {}
Signal.__index = Signal

export type Signal = typeof(setmetatable({} :: { _handlers: { (...any) -> () } }, Signal))

function Signal.new(): Signal
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal.Connect(self: Signal, fn: (...any) -> ())
	table.insert(self._handlers, fn)
	return {
		Disconnect = function()
			local i = table.find(self._handlers, fn)
			if i then
				table.remove(self._handlers, i)
			end
		end,
	}
end

function Signal.Fire(self: Signal, ...: any)
	for _, fn in table.clone(self._handlers) do
		task.spawn(fn, ...)
	end
end

return Signal
