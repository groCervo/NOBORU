Threads = {}

local IMAGE_CACHE_PATH = "ux0:data/noboru/cache.img"

local Order = {}
local Task = nil

local Trash = {
    Type = nil,
    Garbadge = nil
}

local net_inited = false
local bytes = 0
local uniques = {}

function Threads.update()
    if net_inited and not Task and #Order == 0 then
        Network.term()
        net_inited = false
    end
    if not net_inited and (#Order ~= 0 or Task) then
        Network.init()
        net_inited = true
    end
    if (#Order == 0 and not Task) or System.getAsyncState() == 0 then
        return
    end
    if not Task then
        Task = table.remove(Order, 1)
        if Task.Type == "StringRequest" then
            Network.requestStringAsync(Task.Link, USERAGENT, Task.HttpMethod, Task.PostData, Task.ContentType, Task.Cookie)
        elseif Task.Type == "FileDownload" or Task.Type == "ImageDownload" then
            if System.doesFileExist(Task.Path) then
                System.deleteFile(Task.Path)
            end
            Network.downloadFileAsync(Task.Link, Task.Path, USERAGENT, Task.HttpMethod, Task.PostData, Task.ContentType, Task.Cookie)
            if Task.Type == "ImageDownload" then
                Task.Type = "Image"
            end
        elseif Task.Type == "Skip" then
            Task = nil
            Console.write("NET: Skip", Color.new(255, 255, 0))
        end
        if Task then
            Console.write(string.format("NET: #%s %s", 4 - Task.Retry, Task.Link), Color.new(0, 255, 0))
        end
    else
        Console.write("(" .. Task.Type .. ")NET: " .. Task.Link, Color.new(0, 255, 0))
        local f_save = function()
            Trash.Type = Task.Type
            Trash.Link = Task.Link
            if Task.Type == "StringRequest" then
                Task.Table[Task.Index] = System.getAsyncResult()
                bytes = bytes + Task.Table[Task.Index]:len()
                if Task.Table[Task.Index]:len() < 100 then
                    Console.write("NET:" .. Task.Table[Task.Index])
                end
            elseif Task.Type == "Image" then
                if System.doesFileExist(Task.Path) then
                    local handle = System.openFile(Task.Path, FREAD)
                    bytes = bytes + System.sizeFile(handle)
                    System.closeFile(handle)
                    local Width, Height = System.getPictureResolution(Task.Path)
                    Console.write(Width .. "x" .. Height .. " Image got")
                    if GetTextureMemoryUsed() + bit32.band(bit32.bor(Width, 7), bit32.bnot(7)) * Height * 4 > 96 * 1024 * 1024 then
                        Console.error("No enough memory to load image")
                        uniques[Task.UniqueKey] = nil
                        Task = nil
                    else
                        if Height > 4096 and Height / Width > 2 then
                            if not (Width and Height) or Width <= 0 or Height <= 0 then
                                error("measure problem")
                            end
                            Task.Image = {
                                Width = Width,
                                Height = Height,
                                Parts = math.ceil(Height / 4096)
                            }
                            Console.write(Task.Image.Parts)
                            Task.Type = "ImageLoadTable"
                        else
                            Graphics.loadImageAsync(IMAGE_CACHE_PATH)
                            Task.Type = "ImageLoad"
                        end
                    end
                else
                    uniques[Task.UniqueKey] = nil
                    Task = nil
                end
                return
            elseif Task.Type == "ImageLoad" then
                if System.doesFileExist(Task.Path) then
                    Task.Table[Task.Index] = Image:new(System.getAsyncResult(), FILTER_LINEAR)
                end
            elseif Task.Type == "ImageLoadTable" then
                if not Task.Image.i then
                    Task.Image.i = 0
                    Task.Table[Task.Index] = {}
                    Task.Table[Task.Index].Parts = Task.Image.Parts
                    Task.Table[Task.Index].SliceHeight = math.floor(Task.Image.Height / Task.Image.Parts)
                    Task.Table[Task.Index].Height = Task.Image.Height
                    Task.Table[Task.Index].Width = Task.Image.Width
                elseif Task.Image.i < Task.Image.Parts then
                    Task.Image.i = Task.Image.i + 1
                    if Task.Table[Task.Index] == Trash.Garbadge then
                        Trash.Garbadge = Image:new(System.getAsyncResult())
                        Trash.Type = "ImageLoadTable2"
                        return
                    end
                    Task.Table[Task.Index][Task.Image.i] = Image:new(System.getAsyncResult(), FILTER_LINEAR)
                    if not Task.Table[Task.Index][Task.Image.i] then
                        error("error with part function")
                    else
                        Console.write(string.format("Got %s image", Task.Image.i))
                    end
                else
                    uniques[Task.UniqueKey] = nil
                    Task = nil
                    return
                end
                local Height = Task.Table[Task.Index].SliceHeight
                if Task.Image.i == Task.Image.Parts - 1 then
                    Height = Task.Image.Height - (Task.Image.i) * Height
                end
                if Task.Image.i < Task.Image.Parts then
                    Console.write(string.format("Getting %s %sx%s Image", Task.Table[Task.Index].SliceHeight * Task.Image.i, Task.Image.Width, Height))
                    Graphics.loadPartImageAsync(Task.Path, 0, Task.Table[Task.Index].SliceHeight * Task.Image.i, Task.Image.Width, Height)
                else
                    uniques[Task.UniqueKey] = nil
                    Task = nil
                end
                return
            elseif Task.Type == "FileDownload" then
                local handle = System.openFile(Task.Path, FREAD)
                bytes = bytes + System.sizeFile(handle)
                System.closeFile(handle)
            elseif Task.Type == "Skip" then
                Console.error("WOW HOW THAT HAPPENED?")
            end
            uniques[Task.UniqueKey] = nil
            Task = nil
        end
        local success, err = pcall(f_save)
        if not success then
            Console.error("NET: " .. err)
            Task.Retry = Task.Retry - 1
            if Task.Retry > 0 then
                table.insert(Order, Task)
            else
                uniques[Task.UniqueKey] = nil
            end
            Task = nil
        end
    end
    if Trash.Garbadge then
        if Trash.Type == "ImageLoad" then
            Console.write("NET:(Freeing Image)" .. Trash.Link, Color.new(255, 0, 255))
            Trash.Garbadge:free()
        elseif Trash.Type == "ImageLoadTable2" then
            Console.write("NET:(Freeing Table Image)" .. Trash.Link, Color.new(255, 0, 255))
            Trash.Garbadge:free()
        end
        Trash.Garbadge = nil
    end
end

---Delete all traces
function Threads.clear()
    Order = {}
    uniques = {}
    Task.Table = Trash
    Task.Index = "Garbadge"
end

function Threads.isDownloadRunning()
    return System.getAsyncState() == 0 or #Order ~= 0 or Task ~= nil
end

function Threads.DownloadString(Link)
    repeat
        until System.getAsyncState() ~= 0
    if not net_inited then
        Network.init()
        local content = Network.requestString(Link)
        Network.term()
        return content
    else
        return Network.requestString(Link)
    end
end

function Threads.DownloadFile(Link, Path)
    repeat
        until System.getAsyncState() ~= 0
    if not net_inited then
        Network.init()
        Network.downloadFile(Link, Path)
        Network.term()
    else
        Network.downloadFile(Link, Path)
    end
end

function Threads.DownloadImage(Link)
    repeat
        until System.getAsyncState() ~= 0
    local Image
    if not net_inited then
        Network.init()
        Network.downloadFile(Link, IMAGE_CACHE_PATH)
        Image = Image:new(Graphics.loadImage(IMAGE_CACHE_PATH), FILTER_LINEAR)
        System.deleteFile(IMAGE_CACHE_PATH)
        Network.term()
    else
        Network.downloadFile(Link, IMAGE_CACHE_PATH)
        Image = Image:new(Graphics.loadImage(IMAGE_CACHE_PATH), FILTER_LINEAR)
        System.deleteFile(IMAGE_CACHE_PATH)
    end
    return Image
end
local function taskcheck(T)
    local task = T
    if task.Type == "FileDownload" then
        if task.Link and task.Path then
            return true
        end
    else
        return true
    end
    return false
end
local function taskete(UniqueKey, T, foo)
    if UniqueKey and uniques[UniqueKey] and taskcheck(T) then
        return false
    end
    local newTask = {
        Type = T.Type,
        Link = T.Link,
        Table = T.Table,
        Index = T.Index,
        Path = T.Path and ("ux0:data/noboru/" .. T.Path) or IMAGE_CACHE_PATH,
        Retry = 3,
        HttpMethod = T.HttpMethod or GET_METHOD,
        PostData = T.PostData or "",
        ContentType = T.ContentType or XWWW,
        Cookie = T.Cookie or "",
        UniqueKey = UniqueKey
    }
    foo(newTask)
    uniques[UniqueKey] = newTask
    return true
end

local function taskinsert(task)
    table.insert(Order, 1, task)
end

---@param UniqueKey string
---@param T table
---@return boolean
---Inserts task to threads
function Threads.insertTask(UniqueKey, T)
    return taskete(UniqueKey, T, taskinsert)
end

local function taskadd(task)
    Order[#Order + 1] = task
end
---@param UniqueKey string
---@param T table
---@return boolean
---Adds task to threads
function Threads.addTask(UniqueKey, T)
    return taskete(UniqueKey, T, taskadd)
end

---Terminates Threads functions and net features
function Threads.terminate()
    if net_inited then
        Threads.clear()
        while Task do
            Threads.update()
        end
        Network.term()
        net_inited = false
    end
end

---@param UniqueKey string
---Removes task by `UniqueKey`
function Threads.remove(UniqueKey)
    if uniques[UniqueKey] then
        if Task == uniques[UniqueKey] then
            Task.Table, Task.Index = Trash, "Garbadge"
        else
            uniques[UniqueKey].Type = "Skip"
        end
        uniques[UniqueKey] = nil
    end
end

---@param UniqueKey string
---Checks if task is in order by `UniqueKey`
function Threads.check(UniqueKey)
    return uniques[UniqueKey] ~= nil
end

---@return number
---Returns count of bytes downloaded by Threads functions
function Threads.getMemoryDownloaded()
    return bytes
end

---@return integer number of tasks
---Returns quantity of tasks in order
function Threads.getTasksNum()
    return #Order + (Task and 1 or 0)
end
