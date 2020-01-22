local ffi = require 'ffi'
ffi.cdef[[
    typedef struct {double x, y;} __attribute__ ((packed)) Point_t;
    typedef struct{
		static const int8_t NONE = 0;
		static const int8_t READ = 1;
		static const int8_t SLIDE = 2;
		int8_t MODE;
    } __attribute__ ((packed)) TOUCH;
    typedef struct{
        double Y;
        double V;
        double TouchY;
        int ItemID;
    } __attribute__ ((packed)) Slider;
]]
dofile "app0:assets/libs/parser.lua"
LUA_GRADIENT    = Graphics.loadImage("app0:assets/images/gradient.png")
LUA_GRADIENTH   = Graphics.loadImage("app0:assets/images/gradientH.png")
LUA_PANEL       = Graphics.loadImage("app0:assets/images/panel.png")

USERAGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36"

COLOR_WHITE = Color.new(255, 255, 255)
COLOR_BLACK = Color.new(  0,   0,   0)
COLOR_GRAY  = Color.new(128, 128, 128)

FONT    = Font.load("app0:roboto.ttf")
FONT12  = Font.load("app0:roboto.ttf")
FONT30  = Font.load("app0:roboto.ttf")
FONT26  = Font.load("app0:roboto.ttf")

Font.setPixelSizes(FONT30, 30)
Font.setPixelSizes(FONT26, 26)
Font.setPixelSizes(FONT12, 12)

MANGA_WIDTH     = 160
MANGA_HEIGHT    = math.floor(MANGA_WIDTH * 1.5)

GlobalTimer = Timer.new()

PI = 3.14159265359

if not System.doesDirExist("ux0:data/Moondayo/") then
    System.createDirectory("ux0:data/Moondayo")
end

if System.doesDirExist("ux0:data/Moondayo/parsers/") then
    local path = "ux0:data/Moondayo/parsers/"
    local files = System.listDirectory(path)
    for _, file in pairs(files) do
        if not file.directory then
            local suc, err = pcall(function() dofile (path..file.name) end)
            if not suc then
                Console.writeLine("Cant load "..path..":"..err, Color.new(255,0,0))
            end
        end
    end
else
    System.createDirectory("ux0:data/Moondayo/parsers")
end

function CreateManga(Name, Link, ImageLink, ParserID, RawLink)
    if Name and Link and ImageLink and ParserID then
        return {Name = Name or "", Link = Link, ImageLink = ImageLink, ParserID = ParserID, RawLink = RawLink or ""}
    else
        return nil
    end
end

local DrawMangaName = function (Manga)
    Manga.PrintName = {}
    local width = Font.getTextWidth(FONT, Manga.Name)
    if width < MANGA_WIDTH - 20 then
        Manga.PrintName.s = Manga.Name
    else
        local f, s = {}, {}
        local tf = false
        for c in it_utf8(Manga.Name) do
            if tf and Font.getTextWidth(FONT, table.concat(s)) > MANGA_WIDTH - 40 then
                s[#s + 1] = "..."
                break
            elseif tf then
                s[#s + 1] = c
            elseif not tf and Font.getTextWidth(FONT, table.concat(f)) > MANGA_WIDTH - 30 then
                f = table.concat(f)
                s[#s + 1] = (f:match(".+%s(.-)$") or f:match(".+-(.-)$") or f)
                s[#s + 1] = c
                f = f:match("^(.+)%s.-$") or f:match("(.+-).-$") or ""
                tf = true
            elseif not tf then
                f[#f + 1] = c
            end
        end
        if type(s) == "table" then s = table.concat(s) end
        if type(f) == "table" then f = table.concat(f) end
        s = s:gsub("^(%s+)", "")
        if s == "" then s,f = f,"" end
        Manga.PrintName.f = f or ""
        Manga.PrintName.s = s
    end
end

function DrawManga(x, y, Manga, M)
    local Mflag = M ~= nil
    M = M or 1
    if Manga.Image and Manga.Image.e then
        local width, height = Manga.Image.Width, Manga.Image.Height
        local draw = false
        if width < height then
            local scale = MANGA_WIDTH / width
            local h = MANGA_HEIGHT / scale
            local s_y = (height - h) / 2
            if s_y >= 0 then
                Graphics.drawImageExtended(x, y, Manga.Image.e, 0, s_y, width, h, 0, scale*M, scale*M)
                draw = true
            end
        end
        if not draw then
            local scale = MANGA_HEIGHT / height
            local w = MANGA_WIDTH / scale
            local s_x = (width - w) / 2
            Graphics.drawImageExtended(x, y, Manga.Image.e, s_x, 0, w, height, 0, scale*M, scale*M)
        end
    else
        Graphics.fillRect(x - MANGA_WIDTH * M / 2, x + MANGA_WIDTH * M / 2, y - MANGA_HEIGHT * M / 2, y + MANGA_HEIGHT * M / 2, Color.new(101, 115, 146))
    end
    local alpha = M
    if Mflag then
        alpha = (0.25 - (M - 1)) / 0.25
    end
    Graphics.drawScaleImage(x - MANGA_WIDTH * M / 2, y + MANGA_HEIGHT * M / 2 - 120, LUA_GRADIENT, MANGA_WIDTH * M, 1, Color.new(255,255,255,255*alpha))
    if Manga.Name then
        if Manga.PrintName == nil then
            pcall(DrawMangaName, Manga)
        else
            if Manga.PrintName.f then
                Font.print(FONT, x - MANGA_WIDTH / 2 + 10, y + MANGA_HEIGHT*M / 2 - 45, Manga.PrintName.f, Color.new(255, 255, 255,255*alpha))
            end
            Font.print(FONT, x - MANGA_WIDTH / 2 + 10, y + MANGA_HEIGHT*M / 2 - 25, Manga.PrintName.s, Color.new(255, 255, 255,255*alpha))
        end
    end
end

local function setmt__gc(t, mt)
    local prox = newproxy(true)
    getmetatable(prox).__gc = function()
        mt.__gc(t)
    end
    t[prox] = true
    return setmetatable(t, mt)
end
local GPU_MEM = 0
Image = {
    __gc = function(self)
        Image.free(self)
    end,
    new = function(self, image)
        if image == nil then
            return nil
        end
        local p = {e = image, Width = Graphics.getImageWidth(image), Height = Graphics.getImageHeight(image)}
        p.mem = bit32.band(p.Width + 7, bit32.bnot(7)) * p.Height * 4
        GPU_MEM = GPU_MEM + p.mem
        setmt__gc(p, self)
        self.__index = self
        return p
    end,
    free = function (self)
        if self.e then
            Graphics.freeImage(self.e)
            Console.writeLine("Freed!")
            self.e = nil
            GPU_MEM = GPU_MEM - self.mem
        end
    end,
    GetMem = function ()
       return GPU_MEM
    end
}
