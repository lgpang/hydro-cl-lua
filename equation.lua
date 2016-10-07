local class = require 'ext.class'
local range = require 'ext.range'

local Equation = class()

function Equation:init()
	-- default # states is # of conservative variables
	if not self.numStates then 
		self.numStates = #self.consVars 
	else
		assert(self.numStates == #self.consVars)
	end
	-- default # waves is the # of states
	if not self.numWaves then self.numWaves = self.numStates end 
end

function Equation:getTypeCode()
	return require 'makestruct'('cons_t', self.consVars)
end

function Equation:getEigenInfo()
	-- TODO autogen the name so multiple solvers don't collide
	local eigenType = 'eigen_t'
	return {
		type = eigenType,
		typeCode = 'typedef struct { real evL[' .. (self.numStates * self.numWaves) .. '], evR[' .. (self.numStates * self.numWaves) .. ']; } ' .. eigenType .. ';',
		code = '#include "eigen.cl"',
		displayVars = range(self.numStates * self.numWaves):map(function(i)
			local row = (i-1)%self.numWaves
			local col = (i-1-row)/self.numWaves
			return 'evL_'..row..'_'..col
		end):append(range(self.numStates * self.numWaves):map(function(i)
			local row = (i-1)%self.numStates
			local col = (i-1-row)/self.numStates
			return 'evR_'..row..'_'..col
		end))
	}
end

return Equation
