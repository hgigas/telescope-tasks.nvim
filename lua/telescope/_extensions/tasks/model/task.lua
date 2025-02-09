local util = require "telescope._extensions.tasks.util"
local setup = require "telescope._extensions.tasks.setup"

---@class Task
---@field name string: This is taken from the key in vim.g.telescope_tasks table
---@field env table: A table of environment variables.
---@field cmd table|string: The command, may either be a string or a table. When a table, the first element should be executable.
---@field cwd string: The working directory of the task.
---@field errorformat string|nil
---@field __generator_opts table|nil
---@field __meta table
---@field create_job function

---@type Task
local Task = {}
Task.__index = Task

local format_cmd

---Create an task from a table
---
---@param o table|string: Task's fields or just a command.
---@param generator_opts table|nil: The options of the generator that created this task.
---@return Task
function Task:new(o, generator_opts)
  ---@type Task
  local a = {
    __generator_opts = generator_opts,
  }
  setmetatable(a, Task)

  --NOTE: verify task's fields,
  --if any errors occur, stop with the creation and return
  --the error string.
  if type(o) == "string" then
    o = { o }
  elseif type(o) ~= "table" then
    local ok = true
    for k, v in pairs(o) do
      if type(k) ~= "number" or type(v) ~= "string" then
        ok = false
        break
      end
    end
    if ok then
      o = { o }
    end
  end
  assert(type(o) == "table", "Task should be a table or a string!")

  local name = o.name or o[1]
  assert(type(name) == "string", "Task's 'name' should be a string!")
  a.name = name

  local errorformat = o.errorformat
  assert(
    errorformat == nil or type(errorformat) == "string",
    "Task '" .. a.name .. "'s `errorformat` field should be a string!"
  )
  a.errorformat = errorformat

  local cmd = o.cmd
  assert(
    type(cmd) == "table" or type(cmd) == "string",
    "Task '" .. a.name .. "' should have a string or a table `cmd` field!"
  )
  if type(cmd) == "table" then
    local t = nil
    for k, v in pairs(cmd) do
      if t ~= nil then
        assert(
          type(k) == t,
          "cmd table should have either all number or all string keys."
        )
      end
      assert(
        (type(v) == "table" and type(k) == "string") or type(v) == "string",
        "Commands should have string or table values!"
      )
      t = type(k)
    end
  end
  a.cmd = cmd

  local cwd = o.cwd
  assert(
    cwd == nil or type(cwd) == "string",
    "Task '" .. a.name .. "'s `cwd` field should be a string!"
  )
  a.cwd = cwd or vim.fn.getcwd()

  local env = o.env
  assert(
    env == nil or type(env) == "table",
    "Task '" .. a.name .. "'s env should be a table!"
  )
  a.env = o.env or {}

  if type(o.__meta) == "table" then
    a.__meta = o.__meta
    if type(a.__meta.name) == "string" then
      local data_dir = setup.opts.data_dir
      if type(data_dir) == "string" then
        local data = util.fetch_data(data_dir, a.__meta.name)
        if type(data) == "string" then
          a.cmd = data
        end
      end
    end
  else
    assert(
      o.__meta == nil or type(o.__meta) == "table",
      "__meta field should be a table"
    )
  end

  a.cmd = format_cmd(a.cmd)

  return a
end

local copy_cmd

---Create a job from the task's fields.
---Returns a function that startes the job in the provided buffer
---and returns the started job's id.
---
---@return function?
function Task:create_job(callback, lock)
  local cmd = self.cmd
  cmd = copy_cmd(cmd)

  local opts = {
    env = next(self.env or {}) and self.env or nil,
    cwd = self.cwd,
    clear_env = false,
    detach = false,
    on_exit = callback,
  }

  if not lock then
    local cmd_string = cmd
    if type(cmd_string) == "table" then
      cmd_string = table.concat(cmd_string, " ")
    end
    cmd_string = util.trim_string(cmd_string)

    local cmd_string2 = vim.fn.input("$ ", cmd_string .. " ")
    if not cmd_string2 or cmd_string2:len() == 0 then
      return nil
    end
    cmd_string2 = util.trim_string(cmd_string2)

    local set_cmd = false
    if type(self.__meta) == "table" and type(self.__meta.name) == "string" then
      if cmd_string2 ~= cmd_string then
        local data_dir = setup.opts.data_dir
        if type(data_dir) == "string" then
          util.save_data(data_dir, self.__meta.name, cmd_string2)
          set_cmd = true
        end
      end
    end
    cmd = format_cmd(cmd_string2)
    if set_cmd then
      self.cmd = cmd
    end
  end

  return function(buf)
    local job_id = nil
    vim.api.nvim_buf_call(buf, function()
      local ok, id = pcall(vim.fn.termopen, cmd, opts)
      if not ok and type(id) == "string" then
        util.error(id)
      else
        job_id = id
      end
    end)
    return job_id
  end
end

function Task:get_definition()
  local def = {}
  table.insert(def, { key = "name", value = self.name })
  local cmd = self.cmd
  if type(cmd) == "string" then
    table.insert(def, { key = "cmd", value = cmd })
  elseif type(cmd) == "table" then
    table.insert(
      def,
      { key = "cmd", value = "[" .. table.concat(cmd, ", ") .. "]" }
    )
  else
    table.insert(def, { key = "cmd", value = table.concat(cmd) })
  end
  if type(self.cwd) == "string" then
    table.insert(def, { key = "cwd", value = self.cwd })
  else
    table.insert(def, { key = "cwd", vim.inspect(self.cwd) })
  end
  if type(self.env) == "table" then
    table.insert(
      def,
      { key = "env", value = "[" .. table.concat(self.env, ", ") .. "]" }
    )
  end

  if self.__generator_opts then
    table.insert(def, {})
    if next(self.__generator_opts or {}) and self.__generator_opts.name then
      table.insert(
        def,
        { key = "#  generator", value = self.__generator_opts.name }
      )
      for k, v in pairs(self.__generator_opts) do
        if k ~= "name" and type(v) == "table" then
          table.insert(
            def,
            { key = "#   " .. k, value = "[" .. table.concat(v, ", ") .. "]" }
          )
        elseif k == "experimental" and v then
          table.insert(def, { key = "#   " .. k, value = "true" })
        end
      end
    end
  end
  return def
end

copy_cmd = function(cmd)
  local _cmd = nil
  if type(cmd) == "string" then
    _cmd = cmd
  elseif type(cmd) == "table" then
    _cmd = {}
    for _, v in ipairs(cmd) do
      table.insert(_cmd, v)
    end
  end
  return _cmd
end

format_cmd = function(cmd)
  local cmd2 = {}
  if type(cmd) == "string" then
    cmd = vim.split(cmd, " ")
  end
  for _, v in ipairs(cmd) do
    if type(v) == "string" and v:len() > 0 then
      table.insert(cmd2, v)
    end
  end
  if #cmd2 == 0 then
    return ""
  end
  cmd = cmd2
  if vim.fn.executable(cmd[1]) ~= 1 then
    cmd = table.concat(cmd, " ")
  end
  return cmd
end

return Task
