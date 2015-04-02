#
# The purpose of this module is in mutation process. In real nature,
# organisms have DNA inside all cells. This DNA may be mutated during copy.
# In most cases mutations add errors and garbage to DNA. But in very small
# cases, they add new abilities... In our case DNA is a organism's script
# on Julia language. Like with DNA, it changes this script. Every change or 
# mutation is a small add, change or remove operation on script line. It's 
# impossible to mutate the script with syntax error. But it's possible to 
# create logical errors. For example it's possible to have stack overflow. 
# This is normal situation. An exception in this case will occure and 
# organism will lost some energy. Main method here is called mutate(). It 
# makes one change/add/remove operation with script. It works in a simple 
# way:
#
#   1. Finds random block of code in Script.Code.blocks array
#   2. Finds one line in block
#   2. Chooses one operation (add, remove, change)
#   3. apply operation to this line
#
# So, all you need to do is call mutate(script, probabilities). Second 
# argument is a probabilities array. It sets probabilities for add, remove,
# and change operations. For example: [3,2,1] means that mutator will add(3)
# new operand more often, then delete(1) or change(2).
#
# There are many organisms in our virtual world. So, we have to have an
# ability to switch between them. For this, Mutator adds produce() calls
# in every block. In our case: for, if, else, function.
# This module uses special expression for describing operands. For example:
#     
#    var = [sign]{const|var} [op [sign]{const|var}]
#
# It means:
#    
#     var   - Variable
#     sign  - One of possible signs. See _sign for details
#     const - constant. e.g.: 34 or 0
#     op    - operator. e.g.: +,-,^ and so on
#     []    - optional expression
#     {|}   - one value should be choosed
#
# Usage:
#     creature = Organism.create()
#     Mutator.mutate(creature.script, [3,2,1])
#
# @author DeadbraiN
#
# TODO: every private method should have standart description of operation it
# TODO: works with. e.g.: if {var|const} op {var|const} end
# TODO: usage...
# TODO: describe [], {|}, var, op, sign, const keywords
# TODO: think about functions copy (like gene copy)
# TODO: Check if we can move some constants to global Config module
# TODO: describe, that every block contains one produce() call
#
# OPT : add speed tests before and after optimization
# OPT : Replace Dictionaries to typed arrays
# OPT : add types to increase the speed
#
module Mutator
  export mutate

  import Script
  import Exceptions
  # TODO: remove this module
  using  Debug

  #
  # Do one random mutation of script. It may be: add, remove or change.
  # Depending on probability (prob argument) it makes a desicion about
  # type of operation (add, del, change) and modifies script (code
  # parameter).
  # @param code Organism's script we have to mutate
  # @param prob Strategy of mutating. See Config.mutator["addDelChange"] 
  # for details.
  #
  function mutate(code::Script.Code, prob::Array{Int})
    #
    # This code calculates index. This index is used for choosing between 
    # [add, remove, change] operation. 1 - add, 2 - remove, 3 - change
    #
    index = _getProbIndex(prob)
    if index === 1      # add
      _addCb[rand(1:length(_addCb))](code)
    elseif index === 2  # change
      _processLine(code, _changeCb)
    else                # delete
      _processLine(code, _delCb)
    end
  end
  #
  # Adds variable into the random block within the script. Possible
  # variants:
  #
  #   var = [sign]{const|var} [op [sign]{const|var}]
  #
  # First(new) variable will be added to code.blocks[xxx]["vars"] array. 
  # code.blocks field must contain at least one block. Details about
  # code.blocks see in description of Script.Code.blocks field. Examples:
  #
  #   var1 = 3
  #   var2 = ~var1
  #   var2 = -var2 * ~34
  #
  # @param {Script.Code} code Script of some particular organism, we 
  # have to mutate (in this case, add new variable).
  #
  function _addVar(code::Script.Code)
    block  = _getRandBlock(code)
    vars   = block["vars"]
    ex     = _getVarOrNum(vars)
    newVar = _getNewOrLocalVar(vars, code)
    #
    # If true, then "ex" obtains full form: 
    # var = [sign]{const|var} [op [sign]{const|var}]
    #
    if (_randTrue())
      ex = Expr(:call, _getOperation(), ex, _getVarOrNum(vars))
    end
    push!(vars, newVar)
    push!(block["block"].args, Expr(:(=), newVar, ex))
  end
  #
  # Adds new "for" keyword into the random block within the script. Possible
  # variants:
  #
  #   for var = {var|const}:{var|const};end
  #
  # "for" operator adds new block into existing one. This block is between
  # "for" and "end" operators. Also, this block contains it's variables scope.
  # "var" (loop variable) will be first in this scope.
  # Examples:
  #
  #   for i = 2:3;end
  #   for i = 7:k;end
  #   for i = m:k;end
  #
  # @param {Script.Code} code Script of particular organism we have to mutate
  # (add new for operator).
  #
  function _addFor(code::Script.Code)
    block   = _getRandBlock(code)
    newVar  = _getNewVar(code)
    newBody = Expr(:block,)
    newFor  = Expr(:for, Expr(:(=), newVar, Expr(:(:), _getVarOrNum(block["vars"], true), _getVarOrNum(block["vars"], true))), newBody)

    push!(newBody.args, Expr(:call, :produce))
    push!(block["block"].args, newFor)
    push!(code.blocks, ["parent"=>block, "vars"=>[newVar], "block"=>newBody]);
  end
  #
  # Adds new if operator into random block within a script. Format:
  #
  #   if {var|const} Cond {var|const};else;end
  #
  # "if" operator adds new block into existing one. But, this block doesn't
  # contain variables scope. It uses parent's scope.
  # Examples:
  #
  #   if 1<2;end
  #   if i<3;else;end
  #   if i>k;end
  #
  # @param {Script.Code} code Script of particulat organism, we have to mutate
  # (add new if operator).
  #
  function _addIf(code::Script.Code)
    block    = code.blocks[rand(1:length(code.blocks))]
    vars     = block["vars"]
    ifParams = [:if, Expr(:comparison, _getVarOrNum(vars, true), _cond[rand(1:length(_cond))], _getVarOrNum(vars, true)), Expr(:block,)]
    #
    # else block is optional
    #
    if _randTrue()
      body = Expr(:block,)
      push!(ifParams, body)
      push!(body.args, Expr(:call, :produce))
      push!(code.blocks, ["parent"=>block, "vars"=>vars, "block"=>body])
    end

    push!(block["block"].args, apply(Expr, ifParams))
    push!(ifParams[3].args, Expr(:call, :produce))
    push!(code.blocks, ["parent"=>block, "vars"=>vars, "block"=>ifParams[3]])
  end
  # TODO: describe function creation details
  # Adds new named function into the main block within script. Format:
  #
  #   function XXX(args);end
  #
  # "function" operator adds new block into existing one. This block is in a 
  # body of the function. Also, this block contains it's own variables scope.
  # It's important, that all functions will leave in main block only.
  # Example:
  #
  #   function func1();end
  #
  # @param {Script.Code} code Script of particular organism we have to mutate
  # (add new function).
  #
  function _addFunc(code::Script.Code)
    newBlock  = Expr(:block,)
    newFunc   = _getNewFunc(code)
    func      = [:call, newFunc]
    maxParams = rand(0:code.funcMaxArgs)
    funcArgs  = (Dict{ASCIIString, Any})[]
    vars      = (Symbol)[]

    for i = 1:maxParams
      arg = _getNewVar(code)
      push!(funcArgs, ["name"=>string(arg), "type"=>Int])
      push!(func, arg)
      push!(vars, arg)
    end
    push!(code.funcs, ["name"=>string(newFunc), "args"=>funcArgs])
    push!(code.fnBlock.args, Expr(:function, apply(Expr, func), newBlock))
    push!(newBlock.args, Expr(:call, :produce))
    push!(code.blocks, ["parent"=>code.fnBlock, "vars"=>vars, "block"=>newBlock])
  end
  #
  # Adds new function call into the random block within script. Format:
  #
  #   [var=]funcXXX([args])
  #
  # This call doesn't add new code block. It may return a value. So, if 
  # current block contains variables one of them will be set into funcation
  # return value. There is no difference between embedded and generated
  # functions. So it's possible to call clone() or funcXXX(). Example:
  #
  #     var3 = func1(var1, 12)
  #     clone()
  #     var1 = grabEnergyLeft(var2)
  #
  # @param {Script.Code} code Script of particular organism we have to mutate
  #
  function _addFuncCall(code::Script.Code)
    block  = code.blocks[rand(1:length(code.blocks))]
    vars   = block["vars"]
    if (length(code.funcs) < 1) return nothing end
    func   = code.funcs[rand(1:length(code.funcs))]
    args   = Any[:call, symbol(func["name"])]
    varLen = length(vars)

    # TODO: possible problem here. we don't check var type.
    # TODO: we assume, that all vars are Int
    for i = 1:length(func["args"]) push!(args, _getVarOrNum(vars, true)) end
    #
    # If no variables in current block, just call the function and ignore return
    #
    # TODO: we should use new or existing var, but not only existing
    push!(block["block"].args, varLen === 0 || _randTrue() ? apply(Expr, args) : Expr(:(=), vars[rand(1:varLen)], apply(Expr, args)))
  end
  #
  # Works in two steps: first, it finds random block. Second - it finds random 
  # line in this block. Depending of line type (e.g. var assignment, if operator, 
  # function call,...) it calls special callback function. Callback functions
  # should be in this order:
  #
  #     [cbVar, cbFor, cbIf, cbFunc, cbFuncCall]
  #
  # Every callback function will be called with two arguments: 
  #
  #     block::Array{Dict{ASCIIString, Any}}, line::Expr
  #
  # @param {Script.Code} code Script of particular organism we have to mutate
  # @param {Array{Function}} cbs Callback functions for every type of operator
  #
  function _processLine(code::Script.Code, cbs::Array{Function})
    #
    # We can't change code, because there is no code at the moment.
    #
    if length(code.blocks) === 0 || length(code.blocks) === 1 && length(code.blocks[1]["block"].args) === 0 return nothing end
    block  = code.blocks[rand(1:length(code.blocks))]
    if length(block["block"].args) === 0 return nothing end
    index  = uint(rand(1:length(block["block"].args)))
    line   = block["block"].args[index]
    if typeof(line) !== Expr return nothing end # empty lines
    head   = line.head

    #
    # We have to skip produce() calls all the time.
    #
    if head === :call && line.args[1] === :produce
      return nothing
    #
    # Possible operations: funcXXX(args), varXXX = funcXXX(args)
    #
    elseif head === :call || (head === :(=) && typeof(line.args[2]) === Expr && line.args[2].head === :call)
      cbs[5](block, line, index)
    #
    # Possible operations: function funcXXX(args)...end
    #
    elseif head === :function
      cbs[4](block, line, index)
    #
    # Possible operations: if...end
    #
    elseif head == :if
      cbs[3](block, line, index)
    #
    # Possible operations: for varXXX = 1:XXX...end
    #
    elseif head == :for
      cbs[2](block, line, index)
    #
    # Possible operations: varXXX = {varXXX|number}[ op {varXXX|number}]
    #
    elseif head === :(=)
      cbs[1](block, line, index)
    end
  end
  #
  # TODO: describe how changer works. it desn't increase/decrease
  # TODO: length of line, just change var/number in one place
  # TODO: possible problem with only one supported type Int
  # @param {Dict} block Current block of code
  # @param {Expr} line  Line with variables to change
  # @param {Uint} index Index of "line" in "block"
  #
  function _changeVar(block, line::Expr, index::Uint)
    #
    # map of variables, numbers and operations for changing
    #
    vars = Dict{ASCIIString, Any}[]
    #
    # We can't change first variable, because it may cause an errors.
    # This variable me be used later in code, so we can't remove it.
    # 2 means - skip first variable: varXXX = ...
    #
    _parseVars(vars, line, 2)
    #
    # There are three types of change: var, number, operation.
    #We can't change first variable: varXXX = ...
    # TODO: describe these ifs
    #
    v = vars[rand(1:length(vars))]
    #
    # This is a variable. We may change it to another variable or number
    #
    if (v["var"])
      v["expr"].args[v["index"]] = _getVarOrNum(block["vars"], true)
    #
    # This is a sign (+, -, ~)
    #
    elseif findfirst(_sign, v["expr"].args[v["index"]]) > 0
      v["expr"].args[v["index"]] = _sign[rand(1:length(_sign))]
    #
    # This is an operator (+,-,/,$,^,...)
    #
    else
      v["expr"].args[v["index"]] = _getOperation()
    end
  end
  #
  # Changes for operator. It's possible to change min or max expression.
  # It's impossible to change variable. For example, we can't change "i"
  # in this loop:
  #
  #     for i = 1:k;end
  #
  # It changes only one variable|number per one call.
  # @param {Dict} block Current block of code 
  # @param {Expr} line  Line with for operator to change
  # @param {Uint} index Index of "line" in "block"
  #
  function _changeFor(block, line::Expr, index::Uint)
    v = _getVarOrNum(block["vars"], true)
    line.args[1].args[2].args[_randTrue() ? 1 : 2] = (v === line.args[1].args[1] ? _getNum(true) : v)
  end
  #
  # Change in this case means, changing of operator or 
  # variables. For example we may change "<", "v1" or "v2":
  #
  #     if v1 < v2...else...end
  #
  # @param {Dict} block Current block of code 
  # @param {Expr} line  Line with for operator to change
  # @param {Uint} index Index of "line" in "block"
  #
  function _changeIf(block, line::Expr, index::Uint)
    #
    # 2 - condition, 1,3 - variables or numbers
    #
    index = _randTrue() ? 2 : (_randTrue() ? 1: 3)
    line.args[1].args[index] = (index === 2 ? _cond[rand(1:length(_cond))] : _getVarOrNum(block["vars"], true))
  end
  #
  # Change in this case means changing one function argument.
  # We can't change function name, because in this case we have
  # to change all arguments too, but they related to function's
  # body code.
  # @param {Dict} block Current block of code 
  # @param {Expr} line  Line with for operator to change
  # @param {Uint} index Index of "line" in "block"
  #
  function _changeFuncCall(block, line::Expr, index::Uint)
    v = _getVarOrNum(block["vars"], true)
    if line.head === :(=)
      if length(line.args[2].args) > 1 line.args[2].args[rand(2:length(line.args[2].args))] = v end
    else
      if length(line.args) > 1 line.args[rand(2:length(line.args))] = v end
    end
  end
  #
  # Removes one line of code with index in specified block.
  # @param {Dict} block Current block of code 
  # @param {Expr} line  Line with variables to change
  # @param {Uint} index Index of "line" in "block"
  #
  function _delLine(block, line::Expr, index::Uint)
    splice!(block["block"].args, index)
  end

  #
  # It calculates probability index from variable amount of components.
  # Let's imagine we have three actions: one, two and three. We want 
  # these actions to be called randomly, but with different probabilities.
  # For example it may be [3,2,1]. It means that one should be called
  # in half cases, two in 1/3 cases and three in 1/6 cases. Probabilities
  # should be greated then -1.
  # @param {Array{Int}} prob Probabilities array. e.g.: [3,2,1] or [1,3]
  # @return {Int}
  #
  function _getProbIndex(prob::Array{Int})
    if length(prob) < 1 throw(UserException("Invalid parameter prob: $prob. Array with at least one element expected.")) end

    num = rand(1:sum(prob))
    s   = 0
    i   = 1

    for i = 1:length(prob)
      if num <= (s += prob[i]) break end
    end

    i
  end
  #
  # Parses expression recursively and collects all variables and numbers
  # into "vars" map. Every varible or number is a record in vars. Example:
  #
  #     ["expr"=>expr, "index"=>1]
  #
  # This line means that expr.args[1] contains variable or number
  # @params {Array} vars Container for variables: [["expr"=>Expr, "index"=>Number],...]
  # TODO:
  # TODO:
  #
  function _parseVars(vars::Array{Dict{ASCIIString, Any}}, parent::Expr, index)
    expr = parent.args[index]
    #
    # "var"=>true means that current operand is a variable or a number const
    #
    if typeof(expr) !== Expr
      push!(vars, ["expr"=>parent, "index"=>index, "var"=>true])
      return nothing
    end
    for i = 1:length(expr.args)
      if typeof(expr.args[i]) === Expr
        _parseVars(vars, expr, i)
      elseif typeof(expr.args[i]) === Symbol
        push!(vars, ["expr"=>expr, "index"=>i, "var"=>i!==1])
      else
        push!(vars, ["expr"=>expr, "index"=>i, "var"=>true])
      end
    end
  end
  #
  # Chooses (returns) true or false randomly. Is used to choose between two
  # variants of something. For example + or - sign.
  # @return {Bool}
  #
  function _randTrue()
    rand(1:2) === 1
  end
  #
  # Generates new variable symbol.
  # @param  {Script.Code} code Script of current organism.
  # @return {Symbol} New symbol in format: "varXXX", where XXX - Uint
  #
  function _getNewVar(code::Script.Code)
    symbol("var$(code.vIndex = code.vIndex + 1)")
  end
  #
  # Generates new function symbol.
  # @param  {Script.Code} code Script of current organism.
  # @return {Symbol} New symbol in format: "funcXXX", where XXX - Uint
  #
  function _getNewFunc(code::Script.Code)
    symbol("func$(code.fIndex = code.fIndex + 1)")
  end
  #
  # Returns an expresion for variable or a number in format: [sign]{var|const}
  # @param  {Expr} vars   Variables array in current block
  # @param  {Bool} simple true if method should return only {var|const} without sign
  # @return {Expr}
  #
  function _getVarOrNum(vars, simple=false)
    if (length(vars) === 0) return _getNum(simple) end
    v = vars[rand(1:length(vars))]
    if _randTrue() 
      if simple 
        v
      else
        Expr(:call, _sign[rand(1:length(_sign))], v)
      end
    else
      _getNum(simple)
    end
  end
  #
  # Returns expression for number in format: [sign]const
  # @param  {Bool} true if it should return only const without sign
  # @return {Expr}
  #
  function _getNum(simple=false)
    num = rand(0:typemax(Int))
    simple ? num : Expr(:call, _sign[rand(1:length(_sign))], num)
  end
  #
  # Returns random block from all available
  # @return {Dict{ASCIIString, Any}}
  #
  function _getRandBlock(code::Script.Code)
    code.blocks[rand(1:length(code.blocks))]
  end
  #
  # Returns new or existing variable is specified vars scope. Returns 
  # new variable in case when _randTrue() returns true.
  # @param vars All available variables in current scope
  # @param code Code of specified organism
  # @return {Symbol}
  #
  function _getNewOrLocalVar(vars::Array{Symbol}, code::Script.Code)
    if _randTrue() && length(vars) > 0 
      return vars[rand(1:length(vars))]
    end
    _getNewVar(code))
  end
  #
  # Returns random operation. See "_op" for details. For example:
  #
  #     var = var + var
  #
  # In this example "+" is an operation
  # @return {Function}
  #
  function _getOperation()
    _op[rand(1:length(_op))]
  end
  #
  # {Array} Available signs. Is used before numeric variables. e.g.: -x or ~y.
  # ! operator should be here.
  #
  const _sign     = [:+, :-, :~]
  #
  #
  #
  const _cond     = [:<, :>, :(==), :(!==), :<=, :>=]
  #
  # {Array} Available operators. Is used between numeric variables and constants
  #
  const _op       = [+, -, \, *, $, |, &, ^, %, >>>, >>, <<]
  #
  # {Array{Array{Function}}} Available operation for script lines. This is:
  # adding, removing and changing lines.
  #
  const _addCb    = [_addVar,    _addFor,    _addIf,    _addFunc,    _addFuncCall   ]
  const _changeCb = [_changeVar, _changeFor, _changeIf, ()->nothing, _changeFuncCall]
  const _delCb    = [_delLine,   _delLine,   _delLine,   _delLine,   _delLine       ]
end