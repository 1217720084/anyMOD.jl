
# XXX sets the objective function according to the arguments provided in obj_dic
function setObjective!(obj_dic::Union{Dict{Symbol,Float64},Symbol},anyM::anyModel,minimize::Bool=true)

    # XXX converts input into dictionary, if only a symbol was provided, if :none keyword was provided returns a dummy objective function
    if typeof(obj_dic) == Symbol
        if obj_dic == :none @objective(anyM.optModel, Min, 1); return, produceMessage(anyM.options,anyM.report, 1," - Set an empty objective function") end
        obj_dic = Dict(obj_dic => 1.0)
    end

    # XXX create empty variables table for objective variables, if already other object defined, these variables and equations are removed from the model
    partObj = anyM.parts.obj

	if !(:objVar in keys(partObj.var))
		partObj.var[:objVar] = DataFrame(name = Symbol[], group = Symbol[], var = AffExpr[])
		partObj.cns[:objEqn] = DataFrame(name = Symbol[], group = Symbol[], cns = ConstraintRef[])
	end

    # XXX create variables and equations required for specified objectives
    for objGrp in setdiff(keys(obj_dic),unique(partObj.var[:objVar][!,:group]))
        createObjective!(objGrp,partObj,anyM)
    end

    # XXX sets overall objective variable with upper limits and according to weights provided in dictionary
	objBd_flt = anyM.options.bound.obj |> (x -> isnan(x) ? NaN : x / anyM.options.scaFac.obj)
	obj_var = JuMP.add_variable(anyM.optModel, JuMP.build_variable(error, VariableInfo(false, NaN, !isnan(objBd_flt), objBd_flt, false, NaN, false, NaN, false, false)),"obj") * anyM.options.scaFac.obj
	obj_eqn = @constraint(anyM.optModel, obj_var == sum(map(x -> sum(filter(r -> r.group == x,partObj.var[:objVar])[!,:var])*obj_dic[x], collect(keys(obj_dic)))))

    if minimize
        @objective(anyM.optModel, Min, obj_var / anyM.options.scaFac.obj)
    else
        @objective(anyM.optModel, Max, obj_var / anyM.options.scaFac.obj)
    end

	produceMessage(anyM.options,anyM.report, 1," - Set objective function according to inputs")
end

createObjective!(objGrp::Symbol, partObj::OthPart,anyM::anyModel) = createObjective!(Val{objGrp}(), partObj::OthPart,anyM::anyModel)

# XXX create variables and equations for cost objective
function createObjective!(objGrp::Val{:costs},partObj::OthPart,anyM::anyModel)

	parObj_arr = collect(keys(partObj.par))
	techIdx_arr = collect(keys(anyM.parts.tech))
	varToPart_dic = Dict(:exc => :exc, :ctr => :bal,:trdSell => :trd, :trdBuy => :trd)

	# computes discount factors from discount rate provided and saves them as new parameter elements
	computeDisFac!(partObj,anyM)

	# XXX add elements for expansion costs of technologies
	for va in (:Conv, :StIn, :StOut, :StSize, :Exc)

		# XXX compute expansion costs
		var_sym = Symbol(:exp,va)
		costPar_sym = Symbol(:costExp,va)

		if !(costPar_sym in parObj_arr) continue end

		# get all variables
		allExp_df = rename(getAllVariables(var_sym,anyM),:var => :exp)

		# add economic lifetime to table where it is defined
		if Symbol(:lifeEco,va) in parObj_arr
			ecoLife_df = matchSetParameter(allExp_df,partObj.par[Symbol(:lifeEco,va)],anyM.sets,newCol = :life)
			noEcoLife_df = join(allExp_df,ecoLife_df, on = intCol(allExp_df), kind = :anti)
			noEcoLife_df[!,:life] .= nothing
			allExp_df = vcat(ecoLife_df,noEcoLife_df)
		else
			allExp_df[!,:life] .= nothing
		end

		techFilt_arr = filter(y -> var_sym in keys(anyM.parts.tech[y].var), techIdx_arr)

		# use technical lifetime where no economic lifetime could be obtained
		if va != :Exc
			allPar_arr = filter(w -> !(isempty(w)),map(x -> anyM.parts.tech[x].par[Symbol(:life,va)].data,filter(y -> var_sym in keys(anyM.parts.tech[y].var), techFilt_arr)))
			union(intCol.(allPar_arr)...) |> (z -> map(x -> map(y -> insertcols!(x,1,(y => fill(0,size(x,1)))) , setdiff(z,intCol(x)) ) ,allPar_arr))
			lifePar_obj = copy(anyM.parts.tech[techFilt_arr[1]].par[Symbol(:life,va)],vcat(allPar_arr...))
		else
			lifePar_obj = anyM.parts.exc.par[:lifeExc]
		end

		techLife_df = matchSetParameter(filter(x -> isnothing(x.life),allExp_df)[!,Not(:life)],lifePar_obj,anyM.sets,newCol = :life)
		allExp_df = vcat(techLife_df,filter(x -> !isnothing(x.life),allExp_df))

		# gets expansion costs and interest reat to compute annuity
		allExp_df = matchSetParameter(convertExcCol(allExp_df),partObj.par[costPar_sym],anyM.sets,newCol = :costExp)
		allExp_df = matchSetParameter(allExp_df,partObj.par[Symbol(:rateExp,va)],anyM.sets,newCol = :rate)
		allExp_df[!,:costAnn] = map(x -> x.costExp * (x.rate * (1 + x.rate)^x.life) / ((1 + x.rate)^x.life-1), eachrow(allExp_df))
		select!(allExp_df,Not([:costExp,:life,:rate]))
		allExp_df = flatten(allExp_df,:Ts_disSup)

		# adds discount factor and computes cost expression
		allExp_df = matchSetParameter(convertExcCol(allExp_df),partObj.par[va != :Exc ? :disFac : :disFacExc],anyM.sets,newCol = :disFac)

		# XXX groups cost expressions by technology, scales groups expression and creates a variables for each grouped entry
		allExp_df = by(allExp_df,va != :Exc ? [:Ts_disSup,:R_exp,:Te] : [:Ts_disSup,:C], expr = [:disFac,:exp,:costAnn] => x -> sum(x.disFac .* x.exp .* x.costAnn))
		transferCostEle!(allExp_df, partObj,costPar_sym,anyM.optModel,anyM.lock,anyM.sets,anyM.options.coefRng,anyM.options.scaFac.costCapa,anyM.options.checkRng)
	end
	produceMessage(anyM.options,anyM.report, 3," - Created expression for expansion costs")

	# XXX add elements for operational costs of technologies
	# if decommissioning is enabled, capacity costs depend on commissioned and not on installed capacities
	capaTyp_sym =  anyM.options.decomm != :none ? :commCapa : :capa
	for va in (:Conv, :StIn, :StOut, :StSize, :Exc)

		var_sym = Symbol(capaTyp_sym,va)
		costPar_sym = Symbol(:costOpr,va)

		if !(costPar_sym in parObj_arr) continue end

		# get all variables
		allCapa_df = rename(getAllVariables(var_sym,anyM),:var => :capa)

		# joins costs and discount factors to create cost expression
		allCapa_df = matchSetParameter(convertExcCol(allCapa_df),partObj.par[costPar_sym],anyM.sets,newCol = :costOpr)
		allCapa_df = matchSetParameter(convertExcCol(allCapa_df),partObj.par[va != :Exc ? :disFac : :disFacExc],anyM.sets,newCol = :disFac)

		# XXX groups cost expressions by technology, scales groups expression and creates a variables for each grouped entry
		allCapa_df = by(allCapa_df,va != :Exc ? [:Ts_disSup,:R_exp,:Te] : [:Ts_disSup,:C], expr = [:disFac,:capa,:costOpr] => x -> sum(x.disFac .* x.capa .* x.costOpr))
		transferCostEle!(allCapa_df, partObj,costPar_sym,anyM.optModel,anyM.lock,anyM.sets,anyM.options.coefRng,anyM.options.scaFac.costCapa,anyM.options.checkRng)
	end
	produceMessage(anyM.options,anyM.report, 3," - Created expression for capacity costs")

	# XXX add elements for variable costs of technologies
	for va in (:use,:gen,:stIn,:stOut,:stSize,:exc)

		costPar_sym = string(va) |> (x -> Symbol(:costVar,uppercase(x[1]),x[2:end]))

		if !(costPar_sym in parObj_arr || (va == :use && :emissionPrc in parObj_arr && :emissionFac in keys(anyM.parts.lim.par))) continue end

		# obtain all variables
		allDisp_df = rename(getAllVariables(va,anyM),:var => :disp)

		# special case for variable costs of exchange (direct and symmetric values need to be considered both) and of use (emission price needs to be considered)
		if va == :exc
			if :costVarExcDir in parObj_arr
				dirCost_df = matchSetParameter(convertExcCol(allDisp_df),anyM.parts.obj.par[:costVarExcDir],anyM.sets,newCol = :costVar)
			else
				dirCost_df = convertExcCol(allDisp_df[[],:])
			end
			noDirCost_df = matchSetParameter(join(convertExcCol(allDisp_df),dirCost_df, on = intCol(dirCost_df), kind = :anti),anyM.parts.obj.par[costPar_sym],anyM.sets,newCol = :costVar)

			allDisp_df = rename(convertExcCol(vcat(dirCost_df,noDirCost_df)),:var => :disp)
		elseif va == :use && :emissionPrc in parObj_arr && :emissionFac in keys(anyM.parts.lim.par)
			# get emission prices as a costs entry
			emPrc_df = matchSetParameter(select(allDisp_df,Not(:disp)),partObj.par[:emissionPrc],anyM.sets, newCol = :prc)
			emPrc_df = matchSetParameter(emPrc_df,anyM.parts.lim.par[:emissionFac],anyM.sets, newCol = :fac)
			emPrc_df[!,:costEms] = emPrc_df[!,:prc] .*  emPrc_df[!,:fac] ./ 1000
			select!(emPrc_df,Not([:prc,:fac]))
			# merge emission costs with other variable costs or just use emission costs if there are not any other
			if costPar_sym in parObj_arr
				otherVar_df = matchSetParameter(select(allDisp_df,Not(:disp)),anyM.parts.obj.par[costPar_sym],anyM.sets,newCol = :costVar)
				allCost_df = joinMissing(otherVar_df,emPrc_df,intCol(emPrc_df),:outer,merge(Dict{Symbol,Any}(:costVar => 0.0, :costEms => 0.0),Dict{Symbol,Any}(x => 0 for x in intCol(emPrc_df))) )
				allCost_df[!,:costVar] = allCost_df[!,:costVar] .+ allCost_df[!,:costEms]
				select!(allCost_df,Not(:costEms))
			else
				allCost_df = emPrc_df
				rename!(allCost_df,:costEms => :costVar)
			end

			allDisp_df = join(allCost_df,allDisp_df, on = intCol(allDisp_df), kind = :inner)
		else
			allDisp_df = matchSetParameter(allDisp_df,anyM.parts.obj.par[costPar_sym],anyM.sets,newCol = :costVar)
		end

		# renames dispatch regions to enable join with discount factors
		if va != :exc rename!(allDisp_df,:R_dis => :R_exp) end
		allDisp_df = matchSetParameter(allDisp_df,partObj.par[va != :exc ? :disFac : :disFacExc],anyM.sets,newCol = :disFac)

		# XXX groups cost expressions by technology, scales groups expression and creates a variables for each grouped entry
		allDisp_df = by(allDisp_df,va != :exc ? [:Ts_disSup,:R_exp,:Te] : [:Ts_disSup,:C], expr = [:disFac,:disp,:costVar] => x -> sum(x.disFac .* x.disp .* x.costVar) ./ 1000.0)
		transferCostEle!(allDisp_df, partObj,costPar_sym,anyM.optModel,anyM.lock,anyM.sets,anyM.options.coefRng,anyM.options.scaFac.costDisp,anyM.options.checkRng)
	end
	produceMessage(anyM.options,anyM.report, 3," - Created expression for variables costs")

	# XXX add elements curtailment costs of energy carriers
	if :crt in keys(anyM.parts.bal.var)
		# compute discounted curtailment costs
		allCrt_df = rename(matchSetParameter(anyM.parts.bal.var[:crt],anyM.parts.bal.par[:costCrt],anyM.sets,newCol = :costCrt),:var => :crt)
		allCrt_df = matchSetParameter(rename(allCrt_df,:R_dis => :R_exp),partObj.par[:disFac],anyM.sets,newCol = :disFac)
		# groups cost expressions by carrier, scales groups expression and creates a variables for each grouped entry
		allCrt_df = by(allCrt_df, [:Ts_disSup,:R_exp,:C], expr = [:disFac,:crt,:costCrt] => x -> sum(x.disFac .* x.crt .* x.costCrt) ./ 1000.0)
		transferCostEle!(allCrt_df, partObj,:costCrt,anyM.optModel,anyM.lock,anyM.sets,anyM.options.coefRng,anyM.options.scaFac.costDisp,anyM.options.checkRng, NaN)
	end

	# XXX add elements for trade costs of energy carriers (buy and sell)
	for va in (:trdBuy, :trdSell)
		if va in keys(anyM.parts.trd.var)
			# compute discounted trade costs
			allTrd_df = rename(matchSetParameter(anyM.parts.trd.var[va],anyM.parts.trd.par[Symbol(va,:Prc)],anyM.sets,newCol = :costTrd),:var => :trd)
			allTrd_df = matchSetParameter(rename(allTrd_df,:R_dis => :R_exp),partObj.par[:disFac],anyM.sets,newCol = :disFac)
			# groups cost expressions by carrier, scales groups expression and creates a variables for each grouped entry
			allTrd_df = by(allTrd_df, [:Ts_disSup,:R_exp,:C], expr = [:disFac,:trd,:costTrd] => x -> sum(x.disFac .* x.trd .* x.costTrd) ./ (va == :trdSell ? -1000.0 : 1000.0) )
			transferCostEle!(allTrd_df, partObj,Symbol(:cost,uppercase(string(va)[1]),string(va)[2:end]),anyM.optModel,anyM.lock,anyM.sets,anyM.options.coefRng,anyM.options.scaFac.costDisp,anyM.options.checkRng,(va == :trdSell ? NaN : 0.0))
		end
	end
	produceMessage(anyM.options,anyM.report, 3," - Created expression for curtailment and trade costs")

	# XXX creates overall costs variable considering scaling parameters
	relBla = filter(x -> x != :objVar, collect(keys(partObj.var)))
	objVar_arr = map(relBla) do varName
		# sets lower limit of zero, except for curtailment and revenues from selling, because these can incure "negative" costs
		lowBd_tup = !(varName in (:costCrt,:costTrdSell)) |> (x -> (x,x ? 0.0 : NaN))
		info = VariableInfo(lowBd_tup[1], lowBd_tup[2], false, NaN, false, NaN, false, NaN, false, false)
		return JuMP.add_variable(anyM.optModel, JuMP.build_variable(error, info),string(varName))
	end

	# create dataframe with for overall cost equations and scales it
	objExpr_arr = [objVar_arr[idx] - sum(partObj.var[name][!,:var]) for (idx, name) in enumerate(relBla)]
	cns_df = DataFrame(group = fill(:costs,length(objExpr_arr)), name = relBla, cnsExpr = objExpr_arr)

	# add variables and equations to overall objective dataframes
	partObj.cns[:objEqn] = vcat(partObj.cns[:objEqn],createCns(cnsCont(cns_df,:equal),anyM.optModel))
	partObj.var[:objVar] = vcat(partObj.var[:objVar],DataFrame(group = fill(:costs,length(objVar_arr)), name = relBla, var = objVar_arr))
end

# XXX transfers provided cost dataframe into dataframe of overall objective variables and equations (and scales them)
function transferCostEle!(cost_df::DataFrame, partObj::OthPart,costPar_sym::Symbol,optModel::Model,lock_::SpinLock,sets_dic::Dict{Symbol,Tree},
												coefRng_tup::NamedTuple{(:mat,:rhs),Tuple{Tuple{Float64,Float64},Tuple{Float64,Float64}}}, scaCost_fl::Float64, checkRng_fl::Float64, lowBd::Float64 = 0.0)

	# create variables for cost entry and builds corresponding expression for equations controlling them
	cost_df = createVar(cost_df,string(costPar_sym),NaN,optModel,lock_,sets_dic, scaFac = scaCost_fl, lowBd = lowBd)
	cost_df[!,:cnsExpr] = map(x -> x.expr - x.var, eachrow(cost_df))
	select!(cost_df,Not(:expr))

	# scales cost expression
	scaleCnsExpr!(cost_df,coefRng_tup,checkRng_fl)
	cost_df[!,:var] = cost_df[!,:var]

	# writes equations and variables
	partObj.cns[costPar_sym] = createCns(cnsCont(select(cost_df,Not(:var)),:equal),optModel)
	partObj.var[costPar_sym] = select(cost_df,Not(:cnsExpr))
end
