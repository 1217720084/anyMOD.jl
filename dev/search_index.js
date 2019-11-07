var documenterSearchIndex = {"docs":
[{"location":"sets/#","page":"Sets","title":"Sets","text":"All model sets are created based on a table from a corresponding csv file. To organize sets within a hierarchical tree structure, each level of the tree corresponds to a column in the table. By writing a set name into a column, a node is created on the respective level of the table. If several set names are written into the same row, these nodes are connected via an edge of the tree. The reserved keyword all is a placeholder for all nodes defined on the respective level and facilitates the creation of large trees.","category":"page"},{"location":"sets/#","page":"Sets","title":"Sets","text":"The input tables for carrier and technology have additional columns to define further attributes of nodes as documented below. To document the purpose of these columns, the set tables of the example model and their corresponding trees are listed below. All plots were created using the drawNodeTree function.","category":"page"},{"location":"sets/#Timestep-1","page":"Sets","title":"Timestep","text":"","category":"section"},{"location":"sets/#","page":"Sets","title":"Sets","text":"All timesteps within the model are provided by the set_timestep.csv file.","category":"page"},{"location":"sets/#","page":"Sets","title":"Sets","text":"timestep_1 timestep_2 timestep_3 timestep_4\n2020   \n2030   \n2040   \nall d001 hh0001 h0001\nall d001 hh0001 h0002\nall d001 hh0001 h0003\nall d001 hh0001 h0004\nall d001 hh0002 h0005\n... ... ... ...","category":"page"},{"location":"sets/#","page":"Sets","title":"Sets","text":"Here the all keyword is used to avoid the repetition of the day/4-hour step/hour part of the table for each year. The example also demonstrates, that node names are not unique, because different nodes on the same level can be named d001, for example. The plot below obviously only shows a section of the corresponding tree.","category":"page"},{"location":"sets/#","page":"Sets","title":"Sets","text":"(Image: )","category":"page"},{"location":"sets/#Region-1","page":"Sets","title":"Region","text":"","category":"section"},{"location":"sets/#","page":"Sets","title":"Sets","text":"Regions are defined within the set_region.csv file.","category":"page"},{"location":"sets/#","page":"Sets","title":"Sets","text":"region_1 region_2\nEast EastNorth\nEast EastSouth\nWest WestNorth\nWest WestSouth","category":"page"},{"location":"sets/#","page":"Sets","title":"Sets","text":"The table leads to the following simple tree. (Image: )","category":"page"},{"location":"sets/#Carrier-1","page":"Sets","title":"Carrier","text":"","category":"section"},{"location":"sets/#","page":"Sets","title":"Sets","text":"All carriers within the model are provided by the set_carrier.csv file.","category":"page"},{"location":"sets/#","page":"Sets","title":"Sets","text":"carrier_1 carrier_2 timestep_dispatch timestep_invest region_dispatch region_invest\nelectricity  4 1 1 2\nheat districtHeat 3 1 2 2\ngas naturalGas 2 1 1 1\ngas synthGas 2 1 1 1\ncoal  1 1 1 1\nhydrogen  1 1 1 1","category":"page"},{"location":"sets/#","page":"Sets","title":"Sets","text":"In addition to the carrier tree itself, the file also defines the carrier-specific temporal and spatial resolution for dispatch and investment by providing the respective levels. There are certain restrictions on the relation of these levels for each carrier:","category":"page"},{"location":"sets/#","page":"Sets","title":"Sets","text":"timestep_dispatch leq timestep_invest  Rightarrow temporal resolution of dispatch needs to be at least as detailed as temporal resolution of investment\nregion_invest leq region_dispatch  Rightarrow spatial resolution of investment needs to be at least as detailed as spatial resolution of dispatch","category":"page"},{"location":"sets/#","page":"Sets","title":"Sets","text":"The resolution of carriers without a separate row in the input table is set to the coarsest resolution of all its children.","category":"page"},{"location":"sets/#","page":"Sets","title":"Sets","text":"(Image: )","category":"page"},{"location":"sets/#Technology-1","page":"Sets","title":"Technology","text":"","category":"section"},{"location":"sets/#","page":"Sets","title":"Sets","text":"Technologies are defined within the set_technology.csv file. Only nodes at the end of a branch correspond to an actual technology and all other nodes are used to enable inheritance of parameters and setting of limits. Referring to the table below for example, any availability parameter provided for solar would ultimately be inherited by openspace, photovoltaic and solarThermal. Furthermore, any limit on the installed capacites of rooftop would apply to the sum of photovoltaic and solarThermal capacities.","category":"page"},{"location":"sets/#","page":"Sets","title":"Sets","text":"technology_1 technology_2 technology_3 mode carrier_conversion_in carrier_conversion_out carrier_stored_in carrier_stored_out technology_type region_disaggregate\nwind     electricity   mature yes\nsolar openspace    electricity   mature yes\nsolar rooftop photovoltaic   electricity  electricity mature yes\nsolar rooftop solarThermal   heat  heat mature yes\ngasPlant ccgtPlant noCHP  gas electricity   stock no\ngasPlant ccgtPlant CHP moreHeat; moreElec gas electricity; heat < districtHeat   mature no\ngasPlant ocgtPlant   gas electricity   mature no\nheatpump    electricity heat   mature no\nelectrolysis    electricity hydrogen   emerging no\nfuelCell    hydrogen electricity; heat   emerging no","category":"page"},{"location":"sets/#","page":"Sets","title":"Sets","text":"The technology table includes a lot of additional columns that characterize the specific technology. If a column contains multiple values, these need to be separated by ;.","category":"page"},{"location":"sets/#","page":"Sets","title":"Sets","text":"Modes\n  Each technology can have a arbitrary number of operational modes, that can effect all its dispatch related parameters (efficiency , availability, variable cost etc.). Since we do not use any integer variables, these modes are not exclusive. Instead, the current operating status can be any linear combination of all modes defined.\nTechnology carriers\n  Carriers below the tree's top level have to be provided with a < (as a symbolization of the tree's edges) between the name of the different nodes.\nconversion: Input and output carriers to the conversion process of the respective technology.\nstorage: Carriers the technology can charge (input) or discharge (output) to the energy balance of the respective carrier. It is reasonable to have a carrier, that can only be discharged to the energy balance, if at the same carrier it is an output of the conversion process. The same applies vice versa to conversion inputs and charging.\nType of technology\n  This column controls how investment into the respective technology is handled. The column allows for three different keywords:\nstock: Technology does not allow investment and can only be used where residual capacities are provided.\nmature: Dispatch related parameters (efficiency , availability, variable cost etc.) cannot depend on the period of capacity investment. However, all its investment related parameters (lifetime, investment costs etc.) still can be time-dependent.\nemerging: Dispatch related parameters can vary by the period of capacity investment.","category":"page"},{"location":"sets/#","page":"Sets","title":"Sets","text":"warning: Warning\nFor emerging technologies, the number of dispatch variables and constraints exponentially grows with the number of investment timesteps. Otherwise, the dependency between period of investment and dispatch parameters cannot be modelled. Therefore, emerging technologies should be chosen carefully.","category":"page"},{"location":"sets/#","page":"Sets","title":"Sets","text":"Disaggregate regions\n  By default the spatial dispatch level of each technology is determined by the spatial dispatch level of its carriers. Consequently, in our case each technology producing electricity would be dispatched at the spatial level 1. Even though its spatial investment level is 2, for dispatch constraints all capacities would be aggregated on level 1. As a result, different availability curves for renewables in different regions of the same country could not be modelled. To prevent this, the region_disaggregate column can be set to yes to ensure the respective technology is always dispatched at the spatial investment instead of the spatial dispatch level.","category":"page"},{"location":"sets/#","page":"Sets","title":"Sets","text":"(Image: )","category":"page"},{"location":"vis/#","page":"Visualizations","title":"Visualizations","text":"drawNodeTree","category":"page"},{"location":"vis/#anyMOD.drawNodeTree","page":"Visualizations","title":"anyMOD.drawNodeTree","text":"drawNodeTree(Tree_df::DataFrame, options::modOptions; args...)\n\nDraw a tree for all nodes provided by the set data frame and copies it to the output directory defined within options.\n\nOptions and default values:\n\nrgb = (0.251,0.388,0.847)\nColor of nodes.\ntrans = 4.5\nControls fading of color going further down the tree.\nwide = fill(1.0,maximum(Tree_df[!,:lvl]))\nRatio of distances between nodes that have and do not have the same parent (separate on each level).\nname = \"graph\"\nName of the output file.\nlabelsize = 7\nSize of labels in graph.\n\n\n\n\n\n","category":"function"},{"location":"csvtab/#","page":"CSV Tables","title":"CSV Tables","text":"printObject","category":"page"},{"location":"csvtab/#anyMOD.printObject","page":"CSV Tables","title":"anyMOD.printObject","text":"printObject(print_obj::AbstractModelElement,sets::Dict{Symbol,DataFrame},options::modOptions)\n\nPrints the data table of a model element (parameter, variable or equation) as a csv-File to the output directory defined within options.\n\nOptions and default values:\n\nthreshold = 0.001\nVariables or parameter with a value below the threshold will not be included in output table. Set to nothing, if all values should be included.\nfilterFunc::Union{Nothing,Function} = nothing\nDefines a function to filter only certain entries of data table of the element for output.\n\n\n\n\n\n","category":"function"},{"location":"#anyMOD-1","page":"Introduction","title":"anyMOD","text":"","category":"section"},{"location":"#","page":"Introduction","title":"Introduction","text":"anyMOD.jl is a Julia framework to set up large scale linear energy system models with a focus on multi-period capacity expansion. It was developed to address the challenges in modelling high-levels of intermittent generation and sectoral integration.","category":"page"},{"location":"#","page":"Introduction","title":"Introduction","text":"The framework's key characteristic is, that all sets (time-steps, regions, energy carriers, and technlogies) are each organized within a hierarchical tree structure. This allows for several unique features:","category":"page"},{"location":"#","page":"Introduction","title":"Introduction","text":"The spatial and temporal resolution at which generation, use and transport of energy is modelled can be varied by energy carrier. For example, within the same model electricity can be modelled at an hourly, but gas at a daily resolution, while still allowing for technologies that convert gas to electricity, or vice versa. As a result, a substantial decrease of computational effort can be achieved.\nThe substitution of energy carriers with regard to conversion, consumption and transport can be modelled. As an example, residential and district heat can both equally satisfy overall heat demand, but technologies to produce these carriers and how they are constrained are different.\nInheritance within the trees can be exploited to dynamically obtain the model's parameters from the input data provided. In case of a technology’s efficiency for instance, parameters can vary by hour, day or be irrespective of time, depending on whether input data was provided hourly, daily or without any temporal dimension specified.","category":"page"},{"location":"#","page":"Introduction","title":"Introduction","text":"The tool relies on the JuMP package to create optimization problems and uses JuliaDB to store and process their elements.","category":"page"},{"location":"#Quick-Start-1","page":"Introduction","title":"Quick Start","text":"","category":"section"},{"location":"#","page":"Introduction","title":"Introduction","text":"The example project \"demo\" is used to introduce the packages’ top-level functions. After adding anyMOD to your project, the function anyModel constructs an anyMOD model object by reading in the csv files found within the directory specified by the first argument. The second argument specifies a directory all model outputs are written to. Furthermore, default model options can be overwritten via optional arguments. In this case, the distance between investment time-steps is set to 10 instead of 5 years as per default and the level of reporting is extended to 3 to produce more detailed output messages.","category":"page"},{"location":"#","page":"Introduction","title":"Introduction","text":"using anyMOD\nanyM = anyModel(\"examples/demo\",\"output\"; shortInvest = 10, reportLvl = 3)","category":"page"},{"location":"#","page":"Introduction","title":"Introduction","text":"addVariables! and addConstraints! determine, which optimization variables and constraints the specific model requires and adds them.","category":"page"},{"location":"#","page":"Introduction","title":"Introduction","text":"addVariables!(anyM)\naddConstraints!(anyM)","category":"page"},{"location":"#","page":"Introduction","title":"Introduction","text":"Afterwards, setObjective! sets the objective function of the optimization problem. The first argument serves as a key for the respective objective. To enable multi-objective optimization, instead of a single symbol this can also be a dictionary that assigns a respective keyword to its weight in the final objective function. So far only costs have been implemented as an objective.","category":"page"},{"location":"#","page":"Introduction","title":"Introduction","text":"setObjective!(:costs,anyM)","category":"page"},{"location":"#","page":"Introduction","title":"Introduction","text":"Finally, the JuMP model object of is be passed to a solver. Afterwards, the value of optimization variables can be printed to csv files via the printObject command.","category":"page"},{"location":"#","page":"Introduction","title":"Introduction","text":"using Gurobi\nJuMP.optimize!(anyM.optModel,with_optimizer(Gurobi.Optimizer, OutputFlag=1))\nprintObject(anyM.sets.variables[:capaConv],anyM.sets , anyM.options)","category":"page"}]
}
