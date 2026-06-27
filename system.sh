# SCRIPT ARGUMENTS {{{
  NEEDED=false
  DOTS=false
  DM_ON=false
  DM_OFF=false
  SET_SHELL=false
  MAKE_DIRS=false
  for arg in "$@"; do
    case "$arg" in
      --needed) NEEDED=true ;;
      --dots) DOTS=true ;;
      --dm-on) DM_ON=true ;;
      --dm-off) DM_OFF=true ;;
      --set-shell) SET_SHELL=true ;;
      --make-dirs) MAKE_DIRS=true ;;
    esac
  done
# }}}
# LOVEDECK {{{
# The condensed lovedeck menu (5 files) → ~/.scripts/lovedeck. Uses LÖVE's default
# font (no .ttf bundled). Launcher delegates all spawning to Hyprland via hyprctl.
_write_lovedeck_() {
  echo 'Writing lovedeck menu'
  # conf.lua {{{
  cat > "$HOME/.scripts/lovedeck/conf.lua" <<'EOF'
function love.conf(t)
	t.identity = "lovedeck"
	t.window.title = "lovedeck"
	t.window.width = 480          -- quarter of 1920: a left sidebar overlay
	t.window.height = 1080
	t.window.fullscreen = false
	t.window.borderless = true
	t.window.vsync = 0
	t.window.resizable = false
end
EOF
  # }}}
  # apps.lua {{{
  cat > "$HOME/.scripts/lovedeck/apps.lua" <<'EOF'
-- apps.lua — every launcher entry in one ledger. order doubles as workspace.
return {
	{ label = "Steam",    icon = "", order = 1, class = "steam",           run = "steam -gamepadui", default = 1 },
	{ label = "Emulator", icon = "", order = 2, class = "retroarch",       run = "retroarch" },
	{ label = "Browser",  icon = "", order = 3, class = "vivaldi-stable",  run = "vivaldi" },
	{ label = "Files",    icon = "", order = 4, class = "org.kde.dolphin", run = "dolphin" },
	{ label = "Terminal", icon = "", order = 5, class = "ghostty",         run = "ghostty" },
	{ label = "Discord",  icon = "", order = 6, class = "vesktop",         run = "vesktop" },
	{ label = "Monitor",  icon = "", order = 7, class = "btop",            run = "ghostty --class=btop -e btop" },
}
EOF
  # }}}
  # launcher.lua {{{
  cat > "$HOME/.scripts/lovedeck/launcher.lua" <<'EOF'
launcher = {}
launcher.entries = {}
launcher.selected = 1

function launcher.load()
	launcher.entries = require("apps")
	for _, entry in ipairs(launcher.entries) do
		print(entry.label)
	end

	table.sort(launcher.entries, function(a, b)
		return a.order < b.order
	end)
end

-- live workspace peek is parked: under the Lua config, switching the workspace
-- beneath the overlay steals focus from the menu (class:love) and kills
-- controller nav, and there is no confirmed focus-by-class dispatcher yet.
-- Re-enable once we can refocus the menu after the switch.
function launcher.preview()
end

function launcher.down()
	if launcher.selected < #launcher.entries then
		launcher.selected = launcher.selected + 1
		launcher.preview()
	end
end

function launcher.up()
	if launcher.selected > 1 then
		launcher.selected = launcher.selected - 1
		launcher.preview()
	end
end

-- ask Hyprland whether a window of this class already liveth (a query, not a
-- dispatch, so the classic CLI still answers it)
function launcher.isRunning(class)
	local handle = io.popen("hyprctl clients -j")
	if not handle then
		return false
	end
	local out = handle:read("*a")
	handle:close()
	return out:find('"class": "' .. class .. '"', 1, true) ~= nil
end

-- NOTE: this Hyprland runs the Lua config, so the legacy
-- `hyprctl dispatch exec ghostty` is gone. `hyprctl dispatch <X>` now evaluates
-- `hl.dispatch(<X>)`, so we feed it the hl.dsp.* dispatcher tables directly.
function launcher.select()
	local choice = launcher.entries[launcher.selected]
	local ws = choice.workspace or choice.order
	if choice.class and launcher.isRunning(choice.class) then
		-- already alive — carry thee to its workspace (no clone)
		os.execute("hyprctl dispatch 'hl.dsp.focus({ workspace = " .. ws .. " })'")
	else
		-- summon it through Hyprland; window rules place it on its workspace
		os.execute("hyprctl dispatch 'hl.dsp.exec_cmd(\"" .. choice.run .. "\")'")
	end
	-- dismiss the overlay so thou land within
	os.execute("hyprctl dispatch 'hl.dsp.workspace.toggle_special(\"menu\")'")
end

return launcher
EOF
  # }}}
  # status.lua {{{
  cat > "$HOME/.scripts/lovedeck/status.lua" <<'EOF'
status = {}
local statusFont

function status.load()
	statusFont = love.graphics.newFont(24)
end

function status.draw()
	local w = love.graphics.getWidth()
	local topY = 18
	love.graphics.setFont(statusFont)

	-- clock, centered
	local clock = os.date("%a | %b %d | %H:%M")
	love.graphics.setColor(1, 1, 1)
	love.graphics.print(clock, dividerX + (w - dividerX - statusFont:getWidth(clock)) / 2, topY)

	-- battery, right-aligned (percent is nil on a desktop with no battery)
	local state, percent = love.system.getPowerInfo()
	if percent then
		local bw, bh, pad, nub = 44, 22, 3, 4
		local label = percent .. "%"
		local total = bw + nub + 10 + statusFont:getWidth(label)
		local bx = w - 20 - total

		-- fill colored by level
		if percent <= 20 then
			love.graphics.setColor(0.9, 0.3, 0.3)
		elseif percent <= 50 then
			love.graphics.setColor(0.95, 0.8, 0.3)
		else
			love.graphics.setColor(0.4, 0.85, 0.5)
		end
		love.graphics.rectangle("fill", bx + pad, topY + pad, (bw - pad * 2) * (percent / 100), bh - pad * 2)
		love.graphics.setColor(1, 1, 1)
		love.graphics.rectangle("line", bx, topY, bw, bh, 3, 3)
		love.graphics.rectangle("fill", bx + bw, topY + (bh - 8) / 2, nub, 8)
		love.graphics.print(label, bx + bw + 10, topY -1)
	end

	love.graphics.setColor(1, 1, 1)
end

return status
EOF
  # }}}
  # main.lua {{{
  cat > "$HOME/.scripts/lovedeck/main.lua" <<'EOF'
require("launcher")
require("status")

function love.load()
	launcher.load()

	-- Vertical gradient background: a unit-square mesh with per-vertex colors
	-- (lighter top, darker bottom), scaled to fill the window when drawn.
	local top = {0.16, 0.17, 0.23}
	local bottom = {0.05, 0.05, 0.08}
	background = love.graphics.newMesh({
		{0, 0, 0, 0, top[1], top[2], top[3]},
		{1, 0, 0, 0, top[1], top[2], top[3]},
		{1, 1, 0, 0, bottom[1], bottom[2], bottom[3]},
		{0, 1, 0, 0, bottom[1], bottom[2], bottom[3]},
	}, "fan")

	font = love.graphics.newFont(40)

	status.load()

	-- auto-launch the default program once at boot
	for i, entry in ipairs(launcher.entries) do
		if entry.default == 1 then
			launcher.selected = i
			launcher.select()
			break
		end
	end
end

function love.draw()
	love.graphics.draw(background, 0, 0, 0, love.graphics.getWidth(), love.graphics.getHeight())

	local w, h = love.graphics.getDimensions()
	dividerX = w * 0.20

	love.graphics.setColor(0.3, 0.32, 0.4)
	love.graphics.setLineWidth(2)
	love.graphics.line(dividerX, 0, dividerX, h)
	love.graphics.setColor(1, 1, 1)


	love.graphics.setFont(font)
	for i, entry in ipairs(launcher.entries) do
		if i == launcher.selected then
			love.graphics.print("[ " .. entry.label .. " ]", 100, i * 70)
		else
			love.graphics.print(entry.label, 100, i * 70)
		end
	end

	status.draw()
end

-- left-stick navigation: fire once on flick, then repeat steadily while held
local stickThreshold = 0.5
local stickDir = 0       -- -1 up, 1 down, 0 neutral
local repeatTimer = 0
local initialDelay = 0.4 -- pause before hold-to-scroll kicks in
local repeatInterval = 0.12

local function stickStep(dir)
	if dir < 0 then
		launcher.up()
	else
		launcher.down()
	end
end

function love.update(dt)
	-- deaf to the controller unless the menu is the focused overlay
	if not love.window.hasFocus() then
		stickDir = 0
		return
	end

	local js = love.joystick.getJoysticks()[1]
	if not js or not js:isGamepad() then
		return
	end

	local y = js:getGamepadAxis("lefty") -- -1 up, +1 down
	local dir = 0
	if y <= -stickThreshold then
		dir = -1
	elseif y >= stickThreshold then
		dir = 1
	end

	if dir == 0 then
		stickDir = 0
	elseif dir ~= stickDir then
		-- fresh push (or flicked straight to the other direction): step once now
		stickDir = dir
		repeatTimer = initialDelay
		stickStep(dir)
	else
		-- held in the same direction: count down to each repeat
		repeatTimer = repeatTimer - dt
		if repeatTimer <= 0 then
			repeatTimer = repeatInterval
			stickStep(dir)
		end
	end
end

function love.keypressed(key)
	if not love.window.hasFocus() then return end
	if key == "down" then
		launcher.down()
	elseif key == "up" then
		launcher.up()
	elseif key == "return" then
		launcher.select()
	end
end

function love.gamepadpressed(joystick, button)
	if not love.window.hasFocus() then return end
	if button == "dpdown" then
		launcher.down()
	elseif button == "dpup" then
		launcher.up()
	elseif button == "a" then
		launcher.select()
	end
end
EOF
  # }}}
}
# }}}
# PACKAGES {{{
  # ARCH PACKAGES {{{
  gitPaks=(
    yay::https://aur.archlinux.org/yay-git
    paru::https://aur.archlinux.org/paru.git
  )
  yayPaks=(
      ani-cli
      ani-skip-git
      nerd-fonts
	  vesktop-bin
  )
  pacPaks=(
    base-devel
    eza
    awww
    retroarch
    retroarch-assets-glui
    retroarch-assets-ozone
    retroarch-assets-xmb
    slurp
    ntfs-3g
    grim
    github-cli
    pavucontrol
    pipewire
    pipewire-audio
    pipewire-pulse
    pipewire-alsa
    pipewire-jack
    wireplumber
    mpv                     # Music & Video: Terminal-based
    audacious               # Music 1: Graphical-based
    kate                    # Graphical-based
    neovim                  # Terminal-based
    noto-fonts
    noto-fonts-cjk
    steam                   # Game Launcher
    obs-studio              # Screen Recording & Streaming
	inputplumber

  # HYPRLAND
    hyprland
    polkit-kde-agent
    qt5-wayland
    qt6-wayland
    xdg-desktop-portal-hyprland

  # IDE
    lua-language-server     # Neovim LSP Support
    pyright                 # Python Syntax Checker

  # LANGUAGE INPUT METHOD
    fcitx5-im

  # RICING
    cava                    # Audio Visualizer
	hyprlauncher
    fuzzel

  # SHELLS
    zsh                     # Z Shell

  # SYS-UTILS
    amd-ucode               # Hardware Improvements for AMD CPU

    btop                    # System Monitor 2
    fastfetch               # System Info

    curl                    # Download from URL
    wget                    # Download from URL
    yt-dlp                  # Download from YT

    gvfs                    # Dependency for External Drives
    udisks2                 # Dependency for External Drives

    gum			            # Dependency for Vible script

    brightnessctl           # Adjust Brightness
    git                     # git Command Set
    jq                      # Parsing Tool for Java
    man-db                  # Manual Pages
	dolphin
    networkmanager	        # Connect to Wi-Fi
    polkit		            # ?
    xdg-utils		        # ?
    tldr                    # Summary of Manual Pages

  # TERMINALS
    ghostty                 # Ghostty Terminal as Default

  # WEB
    vivaldi                 # Broswer: Default
  )
  # }}}
# }}}
# FUNCTIONS {{{
  # DOTFILES {{{
    # .ZPROFILE {{{
    _write_zprofile_() {
    echo 'Overwriting .zprofile'
    sleep 0.1
    cat > "$HOME/.zprofile" <<'EOF'
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
   start-hyprland
elif [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty2" ]; then
   niri --session
fi
EOF
    }
    # }}}
    # .ZSHRC {{{
    _write_ARCH_zshrc_() {
    echo ''
    echo 'Overwriting .zshrc'
    sleep 0.1
    cat > "$HOME/.zshrc" <<'EOF'
alias chat='tgpt'
alias surfshark='surfshark-client'
alias minecraft='prismlauncher'
alias '..'='cd ..'
alias '...'='cd ~'
alias update='sudo pacman -Syyu'
alias ls='eza -a --icons'
alias lsv='ls -1 --color=auto'
alias lst='eza --tree'
alias lsn='eza --icons'
alias search='pacman -Ss'
alias install='sudo pacman -S'
alias aurinstall='paru -S'
alias remove='sudo pacman -Rns'
alias aurremove='paru -Rns'
alias aursearch='paru -Ss'
alias reboot='sudo systemctl reboot'
alias sleep='sudo systemctl suspend'
alias off='poweroff'
alias logitech='solaar'
alias sbmin='brightnessctl set 1%'
alias sbmid='brightnessctl set 44%'
alias sbmax='brightnessctl set 64%'
alias sb='brightnessctl set'
alias sv='pactl set-sink-volume @DEFAULT_SINK@'
alias svmax='pactl set-sink-volume @DEFAULT_SINK@ 117%'
alias svmidhi='pactl set-sink-volume @DEFAULT_SINK@ 64%'
alias svmid='pactl set-sink-volume @DEFAULT_SINK@ 44%'
alias svmin='pactl set-sink-volume @DEFAULT_SINK@ 10%'
alias anime='ani-cli --skip'
alias dlmp3='yt-dlp -x --audio-format mp3 --no-playlist'
alias dlvid='yt-dlp --no-playlist'
alias mov="$HOME/.scripts/movies.sh"
alias weather='curl wttr.in?&u'
alias dots='cd ~/sync/Lua_Projects/dots/'

setopt AUTO_CD
setopt prompt_subst
PROMPT=$'\n%F{69}%~ %F{129}%B》%b%f '
# cd ~/.house/.gameroom/Love
export PATH=$PATH:$HOME/go/bin

export PATH="$HOME/.local/bin:$PATH"
EOF
    }
    # }}}
    # .BASH_PROFILE {{{
    _write_bash_profile_() {
    echo ''
    echo 'Overwriting .bash_profile'
    sleep 0.1
    cat > "$HOME/.bash_profile" <<'EOF'
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
   start-hyprland
elif [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty2" ]; then
   niri --session
fi
[[ -f ~/.bashrc ]] && . ~/.bashrc
EOF
    }
    # }}}
    # .BASHRC {{{
    _write_bashrc_() {
    echo ''
    echo 'Overwriting .bashrc'
    sleep 0.1
    cat > "$HOME/.bashrc" <<'EOF'
alias chat='tgpt'
alias surfshark='surfshark-client'
alias minecraft='prismlauncher'
alias '..'='cd ..'
alias '...'='cd ~'
alias update='sudo pacman -Syyu'
alias ls='eza -a --icons'
alias lsv='ls -1 --color=auto'
alias lst='eza --tree'
alias lsn='eza --icons'
alias search='pacman -Ss'
alias install='sudo pacman -S'
alias aurinstall='paru -S'
alias remove='sudo pacman -Rns'
alias aurremove='paru -Rns'
alias aursearch='paru -Ss'
alias reboot='sudo systemctl reboot'
alias sleep='sudo systemctl suspend'
alias off='poweroff'
alias logitech='solaar'
alias sbmin='brightnessctl set 1%'
alias sbmid='brightnessctl set 44%'
alias sbmax='brightnessctl set 64%'
alias sb='brightnessctl set'
alias sv='pactl set-sink-volume @DEFAULT_SINK@'
alias svmax='pactl set-sink-volume @DEFAULT_SINK@ 117%'
alias svmidhi='pactl set-sink-volume @DEFAULT_SINK@ 64%'
alias svmid='pactl set-sink-volume @DEFAULT_SINK@ 44%'
alias svmin='pactl set-sink-volume @DEFAULT_SINK@ 10%'
alias anime='ani-cli --skip'
alias dlmp3='yt-dlp -x --audio-format mp3 --no-playlist'
alias dlvid='yt-dlp --no-playlist'
alias mov="$HOME/.scripts/movies.sh"
alias weather='curl wttr.in?&u'
alias dots='cd ~/sync/Lua_Projects/dots/'

shopt -s autocd
PS1='\n\[\e[1;38;5;69m\]><(( \[\e[0;38;5;129m\]\w\[\e[1;38;5;69m\] ))°>\[\e[0m\] '
export PATH=$PATH:$HOME/go/bin

export PATH="$HOME/.local/bin:$PATH"
EOF
    }
    # }}}
    # HYPRLAND {{{
    _write_hyprland_() {
    echo ''
    echo 'Overwriting hyprland.lua'
    sleep 0.1
    cat > $HOME/.config/hypr/hyprland.lua <<'EOF'
-- https://wiki.hypr.land/Configuring/Start/
-- require("myColors")

-- MONITORS {{{
-- See https://wiki.hypr.land/Configuring/Basics/Monitors/

hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})
-- }}}
-- PROGRAM VARIABLES {{{
-- Set programs that you use

local terminal    = "ghostty"
local fileManager = "dolphin"
local menu        = "hyprlauncher"
-- }}}
-- AUTOSTART {{{
-- See https://wiki.hypr.land/Configuring/Basics/Autostart/

hl.on("hyprland.start", function ()
	hl.exec_cmd(terminal)
--	hl.exec_cmd("nm-applet")
--	hl.exec_cmd("waybar & hyprpaper & firefox")
	hl.exec_cmd("love ~/.scripts/lovedeck")
	hl.exec_cmd("~/.scripts/load-inputplumber-profile.sh")
end)
-- }}}
-- ENVIRONMENT VARIABLES {{{
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
-- }}}
-- PERMISSIONS {{{
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Permissions/

-- hl.config({
--   ecosystem = {
--     enforce_permissions = true,
--   },
-- })

-- hl.permission("/usr/(bin|local/bin)/grim", "screencopy", "allow")
-- hl.permission("/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland", "screencopy", "allow")
-- hl.permission("/usr/(bin|local/bin)/hyprpm", "plugin", "allow")
-- }}}
-- GAPS & SUCH {{{
-- Refer to https://wiki.hypr.land/Configuring/Basics/Variables/
hl.config({
    general = {
        gaps_in  = 5,
        gaps_out = 20,

        border_size = 2,

        col = {
            active_border   = { colors = {"rgba(33ccffee)", "rgba(00ff99ee)"}, angle = 45 },
            inactive_border = "rgba(595959aa)",
        },

        -- Set to true to enable resizing windows by clicking and dragging on borders and gaps
        resize_on_border = false,

        -- Please see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before you turn this on
        allow_tearing = false,

        layout = "dwindle",
    },

    decoration = {
        rounding       = 10,
        rounding_power = 2,

        -- Change transparency of focused and unfocused windows
        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = 0xee1a1a1a,
        },

        blur = {
            enabled   = true,
            size      = 3,
            passes    = 1,
            vibrancy  = 0.1696,
        },
    },

    animations = {
        enabled = true,
    },
})

-- Default curves and animations, see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1}    } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })

-- Default springs
hl.curve("easy",           { type = "spring", mass = 1, stiffness = 71.2633, dampening = 15.8273644 })

hl.animation({ leaf = "global",        enabled = true,  speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true,  speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true,  speed = 4.79, spring = "easy" })
hl.animation({ leaf = "windowsIn",     enabled = true,  speed = 4.1,  spring = "easy",         style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true,  speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true,  speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true,  speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true,  speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true,  speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true,  speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true,  speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true,  speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true,  speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true,  speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true,  speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true,  speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor",    enabled = true,  speed = 7,    bezier = "quick" })

-- Ref https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
-- "Smart gaps" / "No gaps when only"
-- uncomment all if you wish to use that.
-- hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
-- hl.workspace_rule({ workspace = "f[1]",   gaps_out = 0, gaps_in = 0 })
-- hl.window_rule({
--     name  = "no-gaps-wtv1",
--     match = { float = false, workspace = "w[tv1]" },
--     border_size = 0,
--     rounding    = 0,
-- })
-- hl.window_rule({
--     name  = "no-gaps-f1",
--     match = { float = false, workspace = "f[1]" },
--     border_size = 0,
--     rounding    = 0,
-- })

-- See https://wiki.hypr.land/Configuring/Layouts/Dwindle-Layout/ for more
hl.config({
    dwindle = {
        preserve_split = true, -- You probably want this
    },
})

-- See https://wiki.hypr.land/Configuring/Layouts/Master-Layout/ for more
hl.config({
    master = {
        new_status = "master",
    },
})

-- See https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/ for more
hl.config({
    scrolling = {
        fullscreen_on_one_column = true,
    },
})
-- }}}
-- MISC {{{
hl.config({
    misc = {
        force_default_wallpaper = -1,    -- Set to 0 or 1 to disable the anime mascot wallpapers
        disable_hyprland_logo   = false, -- If true disables the random hyprland logo / anime girl background. :(
    },
})
-- }}}
-- INPUT {{{
hl.config({
    input = {
        kb_layout  = "us",
        kb_variant = "",
        kb_model   = "",
        kb_options = "",
        kb_rules   = "",

        follow_mouse = 1,

        sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.

        touchpad = {
            natural_scroll = false,
        },
    },
})

hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace"
})

-- Example per-device config
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Devices/ for more
hl.device({
    name        = "epic-mouse-v1",
    sensitivity = -0.5,
})
-- }}}
-- KEYBINDS {{{
local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- Example binds, see https://wiki.hypr.land/Configuring/Basics/Binds/ for more
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal))
local closeWindowBind = hl.bind(mainMod .. " + C", hl.dsp.window.close())
-- closeWindowBind:set_enabled(false)
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + F", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))    -- dwindle only

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,             hl.dsp.focus({ workspace = i}))
    hl.bind(mainMod .. " + SHIFT + " .. key,     hl.dsp.window.move({ workspace = i }))
end

-- Example special workspace (scratchpad)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- lovedeck menu overlay: the "guide button" — slides the menu in/out over whatever's running
hl.bind(mainMod .. " + M",         hl.dsp.workspace.toggle_special("menu"))
-- controller's Guide (Control Center) button arrives as F13 via InputPlumber
hl.bind("F13",                     hl.dsp.workspace.toggle_special("menu"))

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Laptop multimedia keys for volume and LCD brightness
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { locked = true, repeating = true })

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })
-- }}}
-- WINDOWRULES {{{
-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- and https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

-- Example window rules that are useful

local suppressMaximizeRule = hl.window_rule({
    -- Ignore maximize requests from all apps. You'll probably like this.
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})
-- suppressMaximizeRule:set_enabled(false)

hl.window_rule({
    -- Fix some dragging issues with XWayland
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})

-- Layer rules also return a handle.
-- local overlayLayerRule = hl.layer_rule({
--     name  = "no-anim-overlay",
--     match = { namespace = "^my-overlay$" },
--     no_anim = true,
-- })
-- overlayLayerRule:set_enabled(false)

-- Hyprland-run windowrule
hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },

    move  = "20 monitor_h-120",
    float = true,
})

-- DEKKOS app placement: each launcher app to its sworn chamber, fullscreen for console feel.
-- None silent: every app is summoned by intention and thou art carried to its chamber.
hl.window_rule({ name = "ws-steam",   match = { class = "steam" },           workspace = "1", fullscreen = true })
hl.window_rule({ name = "ws-emu",     match = { class = "retroarch" },       workspace = "2", fullscreen = true })
hl.window_rule({ name = "ws-browser", match = { class = "vivaldi-stable" },  workspace = "3", fullscreen = true })
hl.window_rule({ name = "ws-files",   match = { class = "org.kde.dolphin" }, workspace = "4", fullscreen = true })
hl.window_rule({ name = "ws-term",    match = { class = "ghostty" },         workspace = "5", fullscreen = true })
hl.window_rule({ name = "ws-discord", match = { class = "vesktop" },         workspace = "6", fullscreen = true })
hl.window_rule({ name = "ws-monitor", match = { class = "btop" },            workspace = "7", fullscreen = true })

-- lovedeck menu: a slide-in sidebar overlay on its own special chamber
hl.window_rule({ name = "lovedeck", match = { class = "love" }, workspace = "special:menu", float = true, move = "0 0" })
-- }}}
EOF
    }
    # }}}
    # GHOSTTY {{{
    _write_ghostty_() {
    echo ''
    echo 'Overwriting ghostty'
    sleep 0.1
    cat > "$HOME/.config/ghostty/config" <<'EOF'
font-family = "VictorMono Nerd Font"
font-size = 13

background-opacity = 0.1
confirm-close-surface = false

window-padding-x = 10
window-padding-y = 6

cursor-style = "block"
cursor-style-blink = true

foreground = "#cdd6f4"
background = "#0b0f1a"
palette = 0=#1b1f2b
palette = 1=#f38ba8
palette = 2=#94e2d5
palette = 3=#f9e2af
palette = 4=#89b4fa
palette = 5=#cba6f7
palette = 6=#89dceb
palette = 7=#bac2de
palette = 8=#313244
palette = 9=#f38ba8
palette = 10=#94e2d5
palette = 11=#f9e2af
palette = 12=#89b4fa
palette = 13=#cba6f7
palette = 14=#89dceb
palette = 15=#ffffff
EOF
    }
    # }}}
  # PACMAN.CONF {{{
    _write_pacman_() {
    echo ''
    echo 'Overwriting pacman.conf'
    sleep 0.1
    # JAMES 4:7 #
    sudo tee /etc/pacman.conf > /dev/null <<'EOF'
# /etc/pacman.conf
#
# See the pacman.conf(5) manpage for option and repository directives

#
# GENERAL OPTIONS
#
[options]
# The following paths are commented out with their default values listed.
# If you wish to use different paths, uncomment and update the paths.
# RootDir     = /
# DBPath      = /var/lib/pacman/
# CacheDir    = /var/cache/pacman/pkg/
# LogFile     = /var/log/pacman.log
# GPGDir      = /etc/pacman.d/gnupg/
# HookDir     = /etc/pacman.d/hooks/
HoldPkg     = pacman glibc
# XferCommand = /usr/bin/curl -L -C - -f -o %o %u
# XferCommand = /usr/bin/wget --passive-ftp -c -O %o %u
# CleanMethod = KeepInstalled
Architecture = auto

# Pacman won't upgrade packages listed in IgnorePkg and members of IgnoreGroup
# IgnorePkg   =
# IgnoreGroup =

# NoUpgrade   =
# NoExtract   =

# Misc options
UseSyslog
Color
# NoProgressBar
CheckSpace
VerbosePkgLists
ParallelDownloads = 7
DownloadUser = alpm
# DisableSandbox

# By default, pacman accepts packages signed by keys that its local keyring
# trusts (see pacman-key and its man page), as well as unsigned packages.
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional
# RemoteFileSigLevel = Required

# NOTE: You must run `pacman-key --init` before first using pacman; the local
# keyring can then be populated with the keys of all official Arch Linux
# packagers with `pacman-key --populate archlinux`.

#
# REPOSITORIES
#   - can be defined here or included from another file
#   - pacman will search repositories in the order defined here
#   - local/custom mirrors can be added here or in separate files
#   - repositories listed first will take precedence when packages
#     have identical names, regardless of version number
#   - URLs will have $repo replaced by the name of the current repo
#   - URLs will have $arch replaced by the name of the architecture
#
# Repository entries are of the format:
#       [repo-name]
#       Server = ServerName
#       Include = IncludePath
#
# The header [repo-name] is crucial - it must be present and
# uncommented to enable the repo.
#

# The testing repositories are disabled by default. To enable, uncomment the
# repo name header and Include lines. You can add preferred servers immediately
# after the header, and they will be used before the default mirrors.

# [core-testing]
# Include = /etc/pacman.d/mirrorlist

[core]
Include = /etc/pacman.d/mirrorlist

# [extra-testing]
# Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

# If you want to run 32 bit applications on your x86_64 system,
# enable the multilib repositories as required here.

# [multilib-testing]
# Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist

# An example of a custom package repository.  See the pacman manpage for
# tips on creating your own repositories.
# [custom]
# SigLevel = Optional TrustAll
# Server = file:///home/custompkgs 
EOF
    }
    # }}}
  # VERSES {{{
  _write_verses_() {
  echo ''
  echo 'Overwriting verses'
  sleep 0.1
  cat > "$HOME/.scripts/Vible/verses.txt" <<'EOF'
GENESIS 1 : 1 | In the beginning God created the heavens and the earth.
GENESIS 1 : 2 | The earth was without form and void; and darkness was on the face of the deep. And the Spirit of God was hovering over the face of the waters.
GENESIS 2 : 7 | And the LORD God formed man of the dust of the ground, and breathed into his nostrils the breath of life; and man became a living being.
GENESIS 5 : 24 | And Enoch walked with God; and he was not, for God took him.
JOB 19 : 15 | Those who dwell in my house, and my maidservants, Count me as a stranger; I am an alien in their sight.
PSALMS 4 : 4 | Be angry, and do not sin. Meditate within your heart on your bed, and be still.
PSALMS 22 : 11 | Be not far from Me, For trouble is near; For there is none to help.
PSALMS 23 : 1 | The LORD is my shepherd; I shall not want.
PSALMS 23 : 4 | Yea, though I walk through the valley of the shadow of death, I will fear no evil; For You are with me; Your rod and Your staff, they comfort me.
PSALMS 139 : 4 | For there is not a word on my tongue, But behold, O LORD, You know it altogether.
PSALMS 139 : 7 | Where can I go from Your Spirit? Or where can I flee from Your presence?
PSALMS 139 : 8 | If I ascend into heaven, You are there; If I make my bed in hell, behold, You are there.
PSALMS 139 : 9 | If I take the wings of the morning, And dwell in the uttermost parts of the sea,
PSALMS 139 : 10 | Even there Your hand shall lead me, And Your right hand shall hold me.
PROVERBS 25 : 26 | A righteous man who falsters before the wicked is like a murky spring and polluted well.
PROVERBS 31 : 3 | Do not give your strength to women, Nor your ways to that which destroys kings.
ISAIAH 1 : 18 | "Come now, and let us reason together," Says the LORD, "Though your sins are like scarlet, They shall be as white as snow. Though they are red like crimson, They shall be as wool.
ISAIAH 41: 10 | Fear not, for I am with you; Be not dismayed, for I am your God. I will strengthen you, Yes, I will help you, I will uphold you with My righteous right hand.
ISAIAH 49 : 15 | "Can a woman forget her nursing child, And not have compassion on the son of her womb? Surely they may forget, Yet I will not forget you.
ISAIAH 49 : 16 | See, I have inscribed you on the palms of My hands; Your walls are continually before Me.
JEREMIAH 17 : 9 | "The heart is deceitful above all things, And desperately wicked; Who can know it?
JEREMIAH 29 : 11 | For I know the thoughts that I think toward you, says the LORD, thoughts of peace and not of evil, to give you a future and a hope. JEREMIAH 30 : 8 | "For it shall come to pass in that day,' Says the LORD of hosts, 'That I will break his yoke from your neck, And will burst your bonds; Foreigners shall no more enslave them.
JEREMIAH 33 : 3 | 'Call to Me, and I will answer you, and show you great and mighty things, which you do not know.'
LAMENTATION 5 : 2 | Our inheritance has been turned over to aliens, And our houses to foreigners.
EZEKIEL 36 : 25 | Then I will sprinkle clean water on you, and you shall be clean; I will cleanse you from all your filthiness and from all your idols.
MATTHEW 6 : 14 | "For if you forgive men their trespasses, your heavenly Father will also forgive you.
MATTHEW 6 : 15 | But if you do not forgive men their trespasses, neither will your Father forgive your trespasses.
MATTHEW 6 : 22 | "The lamp of the body is the eye. If therefore your eye is good, your whole body will be full of light."
MATTHEW 6 : 23 | But if your eye is bad, your whole body will be full of darkness. If therefore the light that is in you is darkness, how great is that darkness!
MATTHEW 7 : 1 | "Judge not, that you not be judged.
MATTHEW 7 : 7 | "Ask, and it will be given to you; seek, and you will find; knock, and it will be opened to you.
MATTHEW 18 : 12 | "What do you think? If a man has a hundred sheep, and one of them goes astray, does he not leave the ninety-nine and go to the mountains to seek the one that is straying?
MATTHEW 18 : 14 | Even so it is not the will of your Father who is in heaven that one of these little ones should perish.
MARK 12 : 30 | And you shall love the LORD your God with all your heart, with all your sol, with all your mind, and with all your strength.' This is the first commandment.
MARK 12 : 31 | And the second, like it, is this: 'You shall love your neighbor as yourself.' There is no other commandment greater than these."
LUKE 8 : 17 | For nothing is secret that will not be revealed, nor anything hidden that will not be known and come to light.
JOHN 1 : 1 | In the beginning was the Word, and the Word was with God, and the Word was God.
JOHN 1 : 2 | He was in the beginning with God.
JOHN 1 : 3 | All things were made through Him, and without Him nothing was made that was made.
JOHN 1 : 4 | In Him was life, and the life was the light of men.
JOHN 1 : 5 | And the light shines in the darkness, and the darkness did not comprehend it.
JOHN 1 : 10 | He was in the world, and the world was made through Him, and the world did not know Him.
JOHN 1 : 11 | He came to His own, and His own did not receive Him.
JOHN 1 : 12 | But as many as received Him, to them He gave the right to become children of God, to those who believe in His name:
JOHN 1 : 14 | And the Word became flesh and dwelt among us, and we beheld His glory, the glory as of the only begotten of the Father, full of grace and truth.
JOHN 3 : 5 | Jesus answered, "Most assuredly, I say to you, unless one is born of water and the Spirit, he cannot enter the kingdom of God.
JOHN 3 : 8 | The wind blows where it wishes, and you hear the sound of it, but cannot tell where it comes from and where it goes. So is everyone who is born of the Spirit.
JOHN 3 : 16 | For God so loved the world that He gave His only begotten Son, that whoever believes in Him should not perish but have everlasting life.
JOHN 3 : 20 | For everone practicing evil hates the light and does not come to the light, lest his deeds should be exposed.
JOHN 3 : 21 | But he who does the truth comes to the light, that they have been done in God."
JOHN 6 : 29 | Jesus answered and said to them, "This is the work of God, that you believe in Him whom He sent."
JOHN 6 : 33 | For the bread of God is He who comes down from heaven and gives life to the world."
JOHN 6 : 35 | And Jesus said to them, "I am the bread of life. He who comes to Me shall never hunger, and he who believes in Me shall never thirst.
JOHN 6 : 40 | And this is the will of Him who sent Me, that everyone who sees the Son and believes in Him may have everylasting life; and I will raise him up at the last day."
JOHN 6 : 44 | No one can come to Me unless the Father who sent Me draws him; and I will raise him up at the last day.
JOHN 6 : 60 | Therefore many of His disciples, when they heard of this, said, "This is a hard saying; who can understand it?"
JOHN 6 : 63 | It is the Spirit who gives life; the flesh profits nothing. The words that I speak to you are spirit, and they are life.
JOHN 8 : 12 | Then Jesus spoke to them again, saying, "I am the light of the world. He who follows Me shall not walk in darkness, but have the light of life."
JOHN 13 : 34 | A new commandment I give to you, that you love one another; as I have loved you, that you also love one another.
JOHN 14 : 6 | Jesus said to him, "I am the way, the truth, and the life. No one comes to the Father except through Me."
JOHN 14 : 14 | If you ask anything in My name, I will do it.
JOHN 15 : 3 | You are already clean because of the word which I have spoken to you.
JOHN 15 : 4 | Abide in Me, and I in you. As the branch cannot bear fruit of itself, unless it abides in the vine, neither can you, unless you abide in Me.
JOHN 15 : 26 | But when the Helper comes, whom I shall send to you from the Father, the Spirit of truth who proceeds from the Father, He will testify of Me.
JOHN 16 : 4 | But these things I have told you, that when the time comes, you may remember that I told you of them. And these things I did not say to you at the beginning, because I was with you.
JOHN 16 : 7 | Nevertheless I tell you the truth. It is to your advantage that I go away; for if I do not go away, the Helper will not come to you; but if I depart, I will send Him to you.
JOHN 16 : 33 | These things I have spoken to you, that in Me you may have peace. In the world you will have tribulation; but be of good cheer, I have overcome the world."
ACTS 2 : 38 | Then Peter said to them, "Repent, and let every one of you be baptized in the name of Jesus Christ for the remission of sins; and you shall receive the gift of the Holy Spirit.
ACTS 2 : 39 | For the promise is to you and to your children, and to all who are afar off, as many as the LORD our God will call.
ACTS 13 : 38 | Therefore let it be known to you, brethren, that through this Man is preached to you the forgiveness of sins;
ACTS 13 : 39 | and by Him everyone who believes is justified from all things from which you could not be justified by the law of Moses.
ACTS 22 : 16 | And now why are you waiting? Arise and be baptized, and wash away your sins, calling on the name of the Lord.'
EOF
  }
  # }}}
  # }}}
  # MAKE DIRECTORIES {{{
  _make_dirs_() {
    mkdir -p "$HOME/.scripts/config_sh"
    mkdir -p "$HOME/.scripts/lovedeck"
    mkdir -p "$HOME/.config/hypr"
    mkdir -p "$HOME/.config/ghostty"
    mkdir -p "$HOME/.config/nvim"
    mkdir -p "$HOME/.config/waybar"
    mkdir -p "$HOME/.scripts/Vible"
    mkdir -p "$HOME/Downloads/gitClones"
  }
  # }}}
  # WHICH DISTRO {{{
  _which_distro_() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    distro=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
   else
    echo "Error: Distrobution not determined."
  fi
}
  # }}}
  # DISPLAY MANAGER {{{
    # SUPPORTED MANAGERS {{{
    displayManagers=(
      gdm
      gdm3
      lightdm
      sddm
      lxdm
    )
    # }}}
    # ENABLE {{{
    _enable_dm_() {
      for dm in "${displayManagers[@]}"; do
        systemctl list-unit-files | grep -q "^$dm.service" && sudo systemctl enable --now "$dm" && break;
      done
    }
    # }}}
    # DISABLE {{{
    _disable_dm_() {
      for dm in "${displayManagers[@]}"; do
        systemctl list-unit-files | grep -q "^$dm.service" && sudo systemctl disable --now "$dm";
      done
    }
    # }}}
    # AUTOLOGIN {{{
    _enable_autologin_() {
      echo 'Enabling tty1 autologin'
      sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
      sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf >/dev/null <<EOF
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin $USER --noclear %I \$TERM
EOF
    }
    # }}}
  # }}}
  # INPUTPLUMBER {{{
  # Bridge: Ally Control Center (Guide) → KeyF13, which Hyprland binds to toggle the lovedeck menu.
  _enable_inputplumber_() {
    echo 'Enabling inputplumber service'
    sudo systemctl enable --now inputplumber
  }

  _write_inputplumber_() {
    echo 'Writing inputplumber lovedeck profile + loader'
    mkdir -p "$HOME/.config/inputplumber/profiles"

    cat > "$HOME/.config/inputplumber/profiles/lovedeck.yaml" <<'EOF'
version: 1
kind: DeviceProfile
name: lovedeck
mapping:
  - name: Guide to F13
    source_event:
      gamepad:
        button: Guide
    target_events:
      - keyboard: KeyF13
EOF

    cat > "$HOME/.scripts/load-inputplumber-profile.sh" <<'EOF'
#!/usr/bin/env bash
# Load the lovedeck Guide→F13 profile onto every InputPlumber composite device.
# Run from Hyprland autostart; retries briefly while the service settles.
PROFILE="$HOME/.config/inputplumber/profiles/lovedeck.yaml"
for attempt in $(seq 1 10); do
  loaded=0
  for i in $(seq 0 8); do
    dev="/org/shadowblip/InputPlumber/CompositeDevice$i"
    if busctl --system call org.shadowblip.InputPlumber "$dev" \
         org.shadowblip.Input.CompositeDevice LoadProfilePath s "$PROFILE" 2>/dev/null; then
      loaded=1
    fi
  done
  [ "$loaded" -eq 1 ] && exit 0
  sleep 1
done
EOF
    chmod +x "$HOME/.scripts/load-inputplumber-profile.sh"
  }
  # }}}
  # PROCESS PACMAN PACKAGES {{{

  _process_pacman_packages_() {
  echo -e "\e[36m|== PACMAN PACKAGES ==|\e[0m" > ~/packageLog.txt
  echo -e "\e[38;5;226mPackages being processed...\e[0m"

  # INSTALL packages.
  sudo pacman -Syu
  for pacPackage in "${pacPaks[@]}"; do
    echo ''
    echo -e "\e[38;5;202mProcessing ==> $pacPackage\e[0m";
    sleep 0.1
    if [[ "$NEEDED" == true ]]; then
      sudo pacman -S --needed --noconfirm "$pacPackage"
    else
      sudo pacman -S --noconfirm "$pacPackage"
    fi

  # LOG installed packages.
      if pacman -Q "$pacPackage" &>/dev/null; then
        echo -e "\e[38;5;46m$pacPackage installed successfully.\e[0m"
        echo -e "\e[38;5;202m$pacPackage\e[0m \e[38;5;46m==> INSTALLED\e[0m \e[35m$(date '+%F %T')\e[0m" >> ~/packageLog.txt
        echo "$pacPackage" >> ~/.cache/installed-pacpaks.txt
        sleep 0.05
      else
        echo -e "\e[31m$pacPackage install failed.\e[0m"
        echo -e "\e[38;5;202m$pacPackage\e[0m \e[31m==> NOT INSTALLED\e[0m \e[35m$(date '+%F %T')\e[0m" >> ~/packageLog.txt
      fi
  done
      echo
      echo "|== Checking for packages that should be manually uninstalled ==|"
      echo

      if [[ ! -f ~/.cache/installed-pacpaks.txt ]]; then
        echo "No previous pacman install log found. Skipping check."
        return
      fi

      installedPackageLog=($(cat ~/.cache/installed-pacpaks.txt))

      for installed in "${installedPackageLog[@]}"; do
        if [[ ! " ${pacPaks[@]} " =~ " $installed " ]]; then
	        echo " $installed (no longer declared - consider uninstalling)"
        fi
      done
  }
  # }}}
  # PROCESS YAY PACKAGES {{{
  _process_yay_packages_() { 
      echo -e "\e[36m|== YAY PACKAGES ==|\e[0m" >> ~/packageLog.txt
      echo -e "\e[38;5;226mPackages being processed...\e[0m"

      for yayPackage in "${yayPaks[@]}"; do
        echo -e "\e[38;5;202m==> $yayPackage\e[0m";
        sleep 0.05
        if [[ "$NEEDED" == true ]]; then
          yay -S --needed --noconfirm --removemake --answerdiff=None --answerclean=None --mflags "--noconfirm" "$yayPackage"
        else
          yay -S --noconfirm --removemake --answerdiff=None --answerclean=None --mflags "--noconfirm" "$yayPackage"
        fi

        if pacman -Q "$yayPackage" &>/dev/null; then
          echo -e "\e[38;5;46m$yayPackage installed successfully.\e[0m"
          echo -e "\e[38;5;202m$yayPackage\e[0m \e[38;5;46m==> INSTALLED\e[0m \e[35m$(date '+%F %T')\e[0m" >> ~/packageLog.txt
	      echo "$yayPackage" >> ~/.cache/installed-yaypaks.txt
          sleep 0.05
        else
          echo -e "\e[31m$yayPackage install failed.\e[0m"
          echo -e "\e[38;5;202m$yayPackage\e[0m \e[31m==> NOT INSTALLED\e[0m \e[35m$(date '+%F %T')\e[0m" >> ~/packageLog.txt
        fi
      done
  }
  # }}}
  # PROCESS GITS {{{
  _clone_gits_() {
  # MAKE DIRECTORY to store cloned Git packages.
    if [[ ! -d "$HOME/Downloads/gitClones" ]]; then
      mkdir -p $HOME/Downloads/gitClones
      echo -e "\e[38;5;226mCreating Directory: gitClones...\e[0m"
      sleep 0.1
      echo -e "\e[38;5;46mDirectory created.\e[0m"
    fi

  # SHOW packages to be cloned.
    echo -e "\e[38;5;226mGits being cloned...\e[0m"
    echo -e "\e[31m|== GIT CLONES ==|\e[0m" >> ~/packageLog.txt
    for entry in "${gitPaks[@]}"; do
      name="${entry%%::*}"
      url="${entry##*::}"

  # CLONE & INSTALL if command not found.
      if ! command -v "$name" &>/dev/null; then
        echo -e "\e[38;5;202m==> $name\e[0m"
        git clone "$url" "$HOME/Downloads/gitClones/$name"
        cd "$HOME/Downloads/gitClones/$name" && makepkg -si --noconfirm
        cd ~
        echo -e "\e[38;5;226m$name = processed.\e[0m"
        sleep 0.1
      fi
    
  # LOG installed gits.
      if command -v "$name" &>/dev/null; then
        echo -e "\e[38;5;46m$name installed successfully.\e[0m"
        echo -e "\e[38;5;202m$name\e[0m \e[38;5;46m==> INSTALLED\e[0m \e[35m$(date '+%F %T')\e[0m" >> ~/packageLog.txt
        sleep 0.05
      fi
    done
  }
  # }}}
  # SET SHELL {{{
  _set_shell_() {
      echo 'Setting default shell to zsh'
      sudo chsh -s /bin/zsh "$USER"
      zsh
  }
  # }}}
  # INSTALL SH {{{
  _install_sh_() {
      dest="$HOME/.scripts/config_sh/system.sh"
      echo 'Installing system.sh to ~/.scripts/config_sh/'
      curl -sL https://raw.githubusercontent.com/theDRen/DEKKOS/main/system.sh -o "$dest"
      chmod +x "$dest"
      echo "system.sh installed to $dest"
      sleep 0.1
  }
  # }}}
# }}}
# MAIN {{{
 # --make-dirs {{{
  if [[ "$MAKE_DIRS" == true ]]; then
      _make_dirs_
  # }}}
  # --set-shell {{{
  elif [[ "$SET_SHELL" == true ]]; then
      _set_shell_
  # }}}
  # --dm-on {{{
  elif [[ "$DM_ON" == true ]]; then
      _enable_dm_
  # }}}
  # --dm-off {{{
  elif [[ "$DM_OFF" == true ]]; then
      _disable_dm_
  # }}}
  # --dots {{{
  elif [[ "$DOTS" == true ]]; then
    _which_distro_
    if [ "$distro" = "arch" ]; then
      echo 'Distro = Arch'
      sleep 0.1
      _make_dirs_
      _write_zprofile_
      _write_ARCH_zshrc_
      _write_bash_profile_
      _write_bashrc_
      _write_pacman_
      _write_hyprland_
      _write_inputplumber_
      _write_lovedeck_
      _write_ghostty_
      _write_cava_
      _write_verses_

    elif [ "$distro" = "nixos" ]; then
      echo 'Distro = NixOS'
      sleep 0.1
      echo "$distro is not supported."
#      _write_nix_

    else
      echo "$distro is not supported."
    fi
  # }}}
  # DEFAULT {{{
  else
    _which_distro_
    if [ "$distro" = "arch" ]; then
      echo 'Distro = Arch'
      echo 'fetching wallpaper from w.wallhaven.cc/full/76/wallhaven-769y2o.png'
      curl -L -o ~/Pictures/dscity.png "https://w.wallhaven.cc/full/76/wallhaven-769y2o.png"
      echo 'Wallpaper downloaded. You may need to logout for the wallpaper to reply.'
      sleep 0.1
      _make_dirs_
      _install_sh_
      _process_pacman_packages_
      _clone_gits_
      _process_yay_packages_
      _enable_autologin_
      _write_zprofile_
      _write_ARCH_zshrc_
      _write_bash_profile_
      _write_bashrc_
      _write_pacman_
      _write_hyprland_
      _enable_inputplumber_
      _write_inputplumber_
      _write_lovedeck_
      _write_ghostty_
      _set_shell_

    elif [ "$distro" = "nixos" ]; then
      echo 'Distro = NixOS'
      echo "$distro is not supported."
      sleep 0.1
#      _write_nix_

    else
      echo "$distro is not supported."
    fi
    # }}}
  fi
# }}}
