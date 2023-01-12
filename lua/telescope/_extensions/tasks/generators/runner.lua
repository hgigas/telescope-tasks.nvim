local enum = require "telescope._extensions.tasks.enum"
local cache = require "telescope._extensions.tasks.generators.cache"
local Task = require "telescope._extensions.tasks.model.task"
local current = require "telescope._extensions.tasks.generators.current"

local should_run_generators

local runner = {}

---provided, the currently available generators from the cache will be run.
---Runs all the available generators and returns the found tasks.
---@param to_run table|nil: A table of generators to run, if not
function runner.run(to_run)
  if current.is_empty() or not should_run_generators() then
    return
  end
  local cached_tasks = cache.get_for_current_context()
  if cached_tasks then
    return
  end

  local found_tasks = {}

  current.iterate_available(function(generator, opts)
    local ok, tasks = pcall(generator, vim.fn.bufnr())

    if not ok and type(tasks) == "string" then
      vim.notify(tasks, vim.log.levels.ERROR, {
        title = enum.TITLE,
      })
      return
    elseif type(tasks) ~= "table" then
      if tasks ~= nil then
        vim.notify("Genrator should return a table", vim.log.levels.ERROR, {
          title = enum.TITLE,
        })
      end
      return
    end

    if tasks.name or tasks.cmd or tasks.env then
      tasks = { tasks }
    end
    for _, o in pairs(tasks) do
      local task
      ok, task = pcall(Task.new, o, opts)
      if not ok and type(task) == "string" then
        vim.notify(task, vim.log.levels.WARN, {
          title = enum.TITLE,
        })
      else
        found_tasks[task.name] = task
      end
    end
  end, to_run)

  cache.set_for_current_context(found_tasks)
end

---Create the BufEnter and DirChanged autocomands.
---These will run the generators.
function runner.init()
  vim.api.nvim_clear_autocmds {
    event = { "BufEnter", "DirChanged" },
    group = enum.TASKS_AUGROUP,
  }

  vim.api.nvim_create_autocmd("BufEnter", {
    group = enum.TASKS_AUGROUP,
    callback = function()
      runner.run()
    end,
  })
  vim.api.nvim_create_autocmd("DirChanged", {
    group = enum.TASKS_AUGROUP,
    callback = function()
      runner.run()
    end,
  })
  if not current.is_empty() then
    runner.run()
  end
end

---Checks whether the generators should be run in the current buffer.
---@return boolean: Whether the generators should be run
should_run_generators = function()
  local buf = vim.fn.bufnr()

  local buftype = vim.api.nvim_buf_get_option(buf, "buftype")
  return buftype:len() == 0
end

return runner