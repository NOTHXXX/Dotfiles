test ! -e "$HOME/.x-cmd.root/local/data/fish/rc.fish" || source "$HOME/.x-cmd.root/local/data/fish/rc.fish" # boot up x-cmd.
if status is-interactive
# Commands to run in interactive sessions can go here
	# ── Homebrew Shell Environment
		if test -x /opt/homebrew/bin/brew
		/opt/homebrew/bin/brew shellenv | source
	end
	# 自动初始化linux  Homebrew 环境
		if test -d /home/linuxbrew/.linuxbrew
    			eval (/home/linuxbrew/.linuxbrew/bin/brew shellenv)
		else if test -d ~/.linuxbrew
    			eval (~/.linuxbrew/bin/brew shellenv)
	end

	# Starship
		if command -q starship
			starship init fish | source
		end

	# ── FZF
		set -gx FZF_DEFAULT_OPTS "\
			--height 75% \
			--layout=reverse \
			--border \
			--info=inline"	
		set -gx FZF_DEFAULT_COMMAND 'fd --hidden --follow --exclude .git'
		set -g fzf_fd_opts --hidden --follow --exclude .git
		set -g fzf_preview_dir_cmd eza --all --color=always --icons --git --tree --level=2
		set -g fzf_preview_file_cmd bat --style=numbers --color=always --line-range :500
		set -g fzf_history_time_format %d-%m-%y

		fzf_configure_bindings --directory=\cf --history=\cr
	
	# zoxide cd改成z
    if type -q zoxide
        zoxide init fish | source
		abbr -a cd z
    end
end

function y --description "Yazi with auto-cd"
    set -l tmp (mktemp -t "yazi-cwd.XXXXXX")
    # 这里直接用 yazi，如果已执行 eval brew shellenv，Fish 能找到它
    yazi $argv --cwd-file=$tmp
    
    if test -f "$tmp"
        set -l last_cwd (cat $tmp)
        if test -n "$last_cwd" -a "$last_cwd" != "$PWD" -a -d "$last_cwd"
            builtin cd -- "$last_cwd"
        end
        rm -f "$tmp"
    end
end

#bat主题
set -gx BAT_THEME "Catppuccin Mocha"

# 别名
	# Eza
    abbr -a el 'eza --long --header --icons --git --all'
    abbr -a et 'eza --tree --level=2 --long --header --icons --git'

	# Homebrew
    abbr -a bi 'brew install'
    abbr -a bui 'brew uninstall --zap'
    abbr -a bs 'brew search'
    abbr -a bif 'brew info'
    abbr -a bl 'brew leaves; and brew list --cask'
    abbr -a bd 'brew deps --installed --tree'
    abbr -a bu 'brew update; and brew upgrade'
    abbr -a bc 'brew autoremove; and brew cleanup --prune=all'
