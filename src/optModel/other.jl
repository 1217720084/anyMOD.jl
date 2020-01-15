
# <editor-fold desc= create other elements of model"

# XXX create variables and capacity constraints for trade variables
function createTradeVarCns!(partTrd::OthPart,anyM::anyModel)
	for type in (:Buy, :Sell)
		trdPrc_sym = Symbol(:trd,type,:Prc)
		trd_sym = Symbol(:trd,type)
		if trdPrc_sym in keys(partTrd.par) && :C in names(partTrd.par[trdPrc_sym].data)

			# <editor-fold desc="create trade variables"
			c_arr = unique(partTrd.par[trdPrc_sym].data[!,:C])

			# create dataframe with all potential entries for trade/sell variable
			var_df = createPotDisp(c_arr,anyM)

			# match all potential variables with defined prices
			var_df = matchSetParameter(var_df,partTrd.par[trdPrc_sym],anyM.sets,anyM.report)[!,Not(:val)]

			var_df = createVar(var_df,string(:trd,type),getUpBound(var_df,anyM),anyM.optModel,anyM.lock,anyM.sets)
			partTrd.var[trd_sym] = orderDf(var_df)
			produceMessage(anyM.options,anyM.report, 3," - Created variables for $(type == :Buy ? "buying" : "selling") carriers")
			# </editor-fold>

			# <editor-fold desc="create capacity constraint on variable"
			trdCap_sym = Symbol(trd_sym,:Cap)
			if trdCap_sym in keys(partTrd.par)
				cns_df = matchSetParameter(var_df,partTrd.par[trdCap_sym],anyM.sets,anyM.report,newCol = :cap)
				sca_arr = getScale(cns_df,anyM.sets[:Ts],anyM.supTs)
				cns_df[!,:cap] = cns_df[!,:cap] .* sca_arr

				withlock(anyM.lock) do
					cns_df[!,:cns] = map(x -> @constraint(anyM.optModel, x.var <= x.cap),eachrow(cns_df))
				end
				partTrd.cns[trdCap_sym] = orderDf(cns_df[!,[intCol(cns_df)...,:cns]])
				produceMessage(anyM.options,anyM.report, 3," - Created capacity restrictions for $(type == :Buy ? "buying" : "selling") carriers")
			end

			# </editor-fold>
		end
		produceMessage(anyM.options,anyM.report, 2," - Created variables and constraints for $(type == :Buy ? "buying" : "selling") carriers")
	end
	produceMessage(anyM.options,anyM.report, 1," - Created variables and constraints for trade")
end

# XXX create all energy balances (and curtailment variables if required)
function createEnergyBal!(techIdx_arr::Array{Int,1},anyM::anyModel)

	partBal = anyM.parts.bal
	c_arr = filter(x -> x != 0,getfield.(values(anyM.sets[:C].nodes),:idx))
	allDim_df = createPotDisp(c_arr,anyM)
	bal_tup = (:C,:Ts_dis)
	agg_tup = (:C, :R_dis, :Ts_dis)

	# <editor-fold desc="create potential curtailment variables

	# get defined entries
	varCrt_df = DataFrame()
	for crtPar in intersect(keys(partBal.par),(:crtUp,:crtLow,:crtFix,:costCrt))
		varCrt_df = vcat(varCrt_df,matchSetParameter(allDim_df,partBal.par[crtPar],anyM.sets,anyM.report)[!,Not(:val)])
	end

	# obtain upper bound for variables and create them
	if !isempty(varCrt_df)
		partBal.var[:crt] = orderDf(createVar(varCrt_df,"crt",getUpBound(varCrt_df,anyM),anyM.optModel,anyM.lock,anyM.sets))
	end
	# </editor-fold>

	# <editor-fold desc="create actual balance"

	# XXX add demand and scale it

	cns_df = matchSetParameter(allDim_df,partBal.par[:dem],anyM.sets,anyM.report)
	cns_df[!,:dem] = cns_df[!,:val] .* getScale(cns_df,anyM.sets[:Ts],anyM.supTs)
	cns_df[!,:eq] = map(x -> anyM.cInfo[x].eq , cns_df[!,:C])

	# XXX get relevant variables
	src_df = copy(cns_df[!,Not([:val,:eq,:Ts_disSup])])

	# add tech variables
	cns_df[!,:techVar] = getTechEnerBal(src_df,techIdx_arr,anyM.parts.tech,anyM.sets,agg_tup,bal_tup)


	# add curtailment variables
	if :crt in keys(partBal.var)
		cns_df[!,:crtVar] = partBal.var[:crt] |> (x -> aggregateVar(x,src_df,agg_tup,anyM.sets,srcFilt = bal_tup)[1])
	else
		cns_df[!,:crtVar] .= AffExpr()
	end

	# add trade variables
	if !isempty(anyM.parts.trd.var)
		cns_df[!,:trdVar] = sum([anyM.parts.trd.var[trd] |> (x -> aggregateVar(x,src_df,agg_tup,anyM.sets,srcFilt = bal_tup)[1] |> (y -> trd != :trdSell ? y : -1.0 * y)) for trd in keys(anyM.parts.trd.var)])
	else
		cns_df[!,:trdVar] .= AffExpr()
	end

	# add exchange variables
	if !isempty(anyM.parts.exc.var)
		excVarTo_df = anyM.parts.exc.var[:exc]
		excVarFrom_df = convertExcCol(copy(excVarTo_df))

		# apply loss values to from dataframe of from variables
		lossPar_obj = copy(anyM.parts.exc.par[:lossExc])
		lossPar_obj.data = lossPar_obj.data |> (x -> vcat(x,rename(x,:R_a => :R_b, :R_b => :R_a)))
		excVarFrom_df = matchSetParameter(excVarFrom_df,lossPar_obj,anyM.sets,anyM.report,newCol = :loss)

		# overwrite symmetric losses with any directed losses provided
		if :lossExcDir in keys(anyM.parts.exc.par)
			oprCol_arr = intCol(excVarFrom_df)
			dirLoss_df = matchSetParameter(excVarFrom_df[!,oprCol_arr],anyM.parts.exc.par[:lossExcDir],anyM.sets,anyM.report,newCol = :lossDir)
			excVarFrom_df = joinMissing(excVarFrom_df,dirLoss_df,oprCol_arr,:left,Dict(:lossDir => nothing))
			excVarFrom_df[!,:val] = map(x -> isnothing(x.lossDir) ? x.loss : x.lossDir,eachrow(excVarFrom_df[!,[:loss,:lossDir]]))
			select!(excVarFrom_df,Not(:lossDir))
		end

		# apply loss values to from variables
		excVarFrom_df[!,:var] = excVarFrom_df[!,:var] .* (1.0 .- excVarFrom_df[!,:loss])
		select!(excVarFrom_df,Not(:loss))

		balTo_tup, balFrom_tup = [tuple(replace(collect(bal_tup),:R_dis => x)...) for x in [:R_to, :R_from]]

		excFrom_arr = aggregateVar(convertExcCol(excVarFrom_df),rename(src_df,:R_dis => :R_to),(:Ts_dis,:R_to,:C),anyM.sets, srcFilt = balTo_tup)[1]
		excTo_arr  = aggregateVar(excVarTo_df,rename(src_df,:R_dis => :R_from),(:Ts_dis,:R_from,:C),anyM.sets, srcFilt = balFrom_tup)[1]

		cns_df[!,:excVar] =  excFrom_arr .- excTo_arr
	else
		cns_df[!,:excVar] .= AffExpr()
	end

	# XXX create final constaint splited into equality and non-equality cases
	cns_arr = Array{ConstraintRef}(undef,size(cns_df,1))
	eqIdx_arr = findall(cns_df[!,:eq])
	noEdIdx_arr = setdiff(1:size(cns_df,1),eqIdx_arr)

	cns_arr[eqIdx_arr] =   map(x -> @constraint(anyM.optModel, 0.1 * (x.techVar + x.excVar + x.trdVar) ==  0.1 * (x.dem + x.crtVar)),eachrow(cns_df)[eqIdx_arr])
	cns_arr[noEdIdx_arr] = map(x -> @constraint(anyM.optModel, 0.1 *  (x.techVar + x.excVar + x.trdVar) >= 0.1 * (x.dem + x.crtVar)),eachrow(cns_df)[noEdIdx_arr])
	cns_df[!,:cns] = cns_arr

	partBal.cns[:enerBal] = orderDf(cns_df[!,[intCol(cns_df)...,:cns]])
	produceMessage(anyM.options,anyM.report, 1," - Created energy balances for all carriers")
	# </editor-fold>
end

# XXX aggregate all technology variables for energy balance
function getTechEnerBal(src_df::DataFrame,techIdx_arr::Array{Int,1},tech_dic::Dict{Int,TechPart},sets_dic::Dict{Symbol,Tree},agg_tup::Tuple,bal_tup::Tuple)
	techVar_arr = Array{Array{AffExpr,1},1}()
	itr_arr = vcat([intersect((:use,:gen,:stExtIn,:stExtOut),keys(tech_dic[x].var)) |> (y -> collect(zip(fill(x,length(y)),y))) for x in techIdx_arr]...)
	# loop over technology / variable type combinations,
	Threads.@threads for x in itr_arr
		part = tech_dic[x[1]]
		push!(techVar_arr,aggregateVar(part.var[x[2]],src_df,agg_tup,sets_dic, srcFilt = bal_tup)[1] |> (y -> x[2] in (:use,:stExtIn) ? -1.0 .* y : y))
	end

	sum_arr = map(x -> sum(x),eachrow(hcat(techVar_arr...)))

	return sum_arr
end

# XXX create constarints that enforce any type of limit (Up/Low/Fix) on any type of variable
function createLimitCns!(techIdx_arr::Array{Int,1},partLim::OthPart,anyM::anyModel)

	techLim_arr = filter(x ->  any(map(y -> occursin(string(y),string(x)),[:Up,:Low,:Fix])) ,string.(keys(partLim.par)))
	limVar_arr = map(x -> map(k -> Symbol(k[1]) => Symbol(k[2][1]), filter(z -> length(z[2]) == 2,map(y -> y => split(x,y),["Up","Low","Fix"])))[1], techLim_arr)
	varToPar_dic = Dict(y => getindex.(filter(z -> z[2] == y,limVar_arr),1) for y in unique(getindex.(limVar_arr,2)))

	# loop over all variables that are subject to any type of limit (except emissions)
	allKeys_arr = collect(keys(varToPar_dic))
	Threads.@threads for va in allKeys_arr

		varToPart_dic = Dict(:exc => :exc, :crt => :bal,:trdSell => :trd, :trdBuy => :trd)

		# obtain all variables relevant for limits
		allVar_df = getAllVariables(va,anyM)

		# check if acutally any variables were obtained
		if isempty(allVar_df)
			push!(anyM.report,(2,"limit",string(va),"limits for variable provided, but none of these variables are actually created"))
			continue
		end

		allLimit_df = DataFrame(var = AffExpr[])
		# XXX loop over respective type of limits to obtain data
		for lim in varToPar_dic[va]
			par_obj = copy(partLim.par[Symbol(va,lim)])
			agg_tup = tuple(intCol(par_obj.data)...)

			# aggregate search variables according to dimensions in limit parameter
			grpVar_df = by(convertExcCol(allVar_df),collect(agg_tup), var = [:var] => x -> sum(x.var))

			# try to aggregate variables to limits directly provided via inputs
			limit_df = copy(par_obj.data)
			limit_df[!,:var] = aggregateVar(grpVar_df, limit_df, agg_tup, anyM.sets, aggFilt = agg_tup, srcFilt = agg_tup)[1]

			# gets provided limit parameters, that no variables could assigned to so far and tests if via inheritance any could be assigned
			mtcPar_arr, noMtcPar_arr  = findall(map(x -> x != AffExpr(),limit_df[!,:var])) |>  (x -> [x, setdiff(1:size(par_obj.data,1),x)])
			# removes entries with no parameter assigned from limits
			limit_df = limit_df[mtcPar_arr,:]

			if !isempty(noMtcPar_arr)
				# tries to inherit values to existing variables only for parameters without variables aggregated so far
				aggPar_obj = copy(par_obj,par_obj.data[noMtcPar_arr,:])
				aggPar_obj.data = matchSetParameter(grpVar_df[!,Not(:var)],aggPar_obj,anyM.sets,anyM.report, useNew = false)
				# again performs aggregation for inherited parameter data and merges if original limits
				aggLimit_df = copy(aggPar_obj.data)
				aggLimit_df[!,:var]  = aggregateVar(grpVar_df, aggLimit_df, agg_tup, anyM.sets, aggFilt = agg_tup)[1]
				limit_df = vcat(limit_df,aggLimit_df)
			end

			# merge limit constraint to other limits for the same variables
			join_arr = [intersect(intCol(allLimit_df),intCol(limit_df))...,:var]
			miss_arr = [intCol(allLimit_df),intCol(limit_df)] |> (y -> union(setdiff(y[1],y[2]), setdiff(y[2],y[1])))
			allLimit_df = joinMissing(allLimit_df, convertExcCol(rename(limit_df,:val => lim)), join_arr, :outer, merge(Dict(z => 0 for z in miss_arr),Dict(:Up => nothing, :Low => nothing, :Fix => nothing)))
		end

		# XXX check for contradicting values
		limitCol_arr = intersect(names(allLimit_df),(:Fix,:Up,:Low))
		entr_int = size(allLimit_df,1)
		if :Low in limitCol_arr || :Up in limitCol_arr
			# upper and lower limit contradicting each other
			if :Low in limitCol_arr && :Up in limitCol_arr
				filter!(x -> any(isnothing.([x.Low,x.Up])) ? true : x.Low < x.Up,allLimit_df)
				if entr_int != size(allLimit_df,1)
					push!(anyM.report,(2,"limit",string(va),"contradicting or equal values for upper and lower limit detected, both values were ignored in these cases"))
				end
			end
			# upper or lower limit of zero
			if !isempty(limitCol_arr |> (y -> filter(x -> collect(x[y]) |> (z -> any(isnothing.(z)) ? false : any(z .== 0)),allLimit_df))) && va != :emission
				push!(anyM.report,(2,"limit",string(va),"upper or lower limit of zero detected, please consider to use fix instead"))
				entr_int = size(allLimit_df,1)
			end
		end

		# value is fixed, but still a upper a lower limit is provided
		if :Fix in limitCol_arr && (:Low in limitCol_arr || :Up in limitCol_arr)
			if !isempty(limitCol_arr |> (z -> filter(x -> all([!isnothing(x.Fix),any(.!isnothing.(x[z]))]) ,allLimit_df)))
				push!(anyM.report,(2,"limit",string(va),"upper and/or lower limit detected, although variable is already fixed"))
			end
		end

		# XXX create final constraints
		for lim in limitCol_arr
			relLim_df = filter(x -> !isnothing(x[lim]),allLimit_df[!,Not(filter(x -> x != lim,limitCol_arr))])
            if isempty(relLim_df) continue end


			withlock(anyM.lock) do
				if lim == :Up
					relLim_df[!,:cns] = map(x -> @constraint(anyM.optModel, x.var <=  x.Up),eachrow(relLim_df))
				elseif lim == :Low
					relLim_df[!,:cns] = map(x -> @constraint(anyM.optModel, x.var >=  x.Low),eachrow(relLim_df))
				elseif lim == :Fix
					relLim_df[!,:cns] = map(x -> @constraint(anyM.optModel, x.var ==  x.Fix),eachrow(relLim_df))
				end
			end

			partLim.cns[Symbol(va,lim)] = orderDf(relLim_df[!,[intCol(relLim_df)...,:cns]])
			produceMessage(anyM.options,anyM.report, 3," - Created constraints for $(lim == :Up ? "upper" : (lim == :Low ? "lower" : "fixed")) limit of variable $va")
		end
		produceMessage(anyM.options,anyM.report, 2," - Created constraints to limit variable $va")
	end
	produceMessage(anyM.options,anyM.report, 1," - Created all limiting constraints")
end

# </editor-fold>

# <editor-fold desc= utility"

# XXX connect capacity and expansion variables
function createCapaCns!(part::TechPart,prepTech_dic::Dict{Symbol,NamedTuple},anyM::anyModel)
    for capaVar in filter(x -> occursin("capa",string(x)),keys(prepTech_dic))

        index_arr = intCol(part.var[capaVar])
        join_arr = part.type != :mature ? index_arr : filter(x -> x != :Ts_expSup,collect(index_arr))

        # joins corresponding capacity and expansion variables together
		expVar_sym = Symbol(replace(string(capaVar),"capa" => "exp"))
		if !(expVar_sym in keys(part.var)) continue end
        expVar_df = flatten(part.var[expVar_sym],:Ts_disSup)
        cns_df = rename(join(part.var[capaVar],by(expVar_df,join_arr, exp = :var => x -> sum(x)); on = join_arr, kind = :inner),:var => :capa)

        # creates final equation
        withlock(anyM.lock) do
            cns_df[!,:cns] = map(x -> @constraint(anyM.optModel, x.capa - x.capa.constant == x.exp),eachrow(cns_df))
        end
        part.cns[Symbol(capaVar)] = orderDf(cns_df[!,Not([:capa,:exp])])
    end
end

# XXX adds column with JuMP variable to dataframe
function createVar(setData_df::DataFrame,name_str::String,upBd_any::Union{Nothing,Float64,Array{Float64,1}},optModel::Model,lock::SpinLock,sets::Dict{Symbol,Tree})
	# adds an upper bound to all variables if provided within the options
	#if isempty(setData_df) return DataFrame(var = AffExpr[]) end
	arr_boo = typeof(upBd_any) <: Array
	if arr_boo
		info = VariableInfo.(true, 0.0, true, upBd_any, false, NaN, false, NaN, false, false)
		var_obj = JuMP.build_variable.(error, info)
	else
		info = VariableInfo(true, 0.0, false, isnothing(upBd_any) ? NaN : upBd_any, false, NaN, false, NaN, false, false)
		var_obj = JuMP.build_variable(error, info)
	end

	# writes full name for each variable
	setData_df = orderDf(setData_df)
	dim_arr = map(x -> Symbol(split(String(x),"_")[1]), filter(r -> r != :id,intCol(setData_df)))
	dim_int = length(dim_arr)
	setData_df[!,:name] = string.(name_str,"[",map(x -> join(map(y -> sets[dim_arr[y]].nodes[x[y]].val,1:dim_int),", "),eachrow(setData_df)),"]")

	withlock(lock) do
		if arr_boo
			setData_df[!,:var] = [AffExpr(0,JuMP.add_variable(optModel, nameItr[1], nameItr[2]) => 1) for nameItr in zip(var_obj,setData_df[!,:name])]
		else
			setData_df[!,:var] = [AffExpr(0,JuMP.add_variable(optModel, var_obj, nameItr) => 1) for nameItr in setData_df[!,:name]]
		end
	end

	return setData_df[!,Not(:name)]
end

# </editor-fold>
