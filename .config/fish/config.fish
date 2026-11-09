source /usr/share/cachyos-fish-config/cachyos-config.fish

# overwrite greeting
# potentially disabling fastfetch
#function fish_greeting
#    # smth smth
#end

# Environment (kept here rather than in fish_variables, which is machine-local)
set -gx EDITOR nvim
set -gx LIBVIRT_DEFAULT_URI qemu:///system
fish_add_path -g ~/.local/bin

# UWSM autostart for Hyprland (TTY1 only)
if status is-login
   if test -z "$DISPLAY" -a -z "$WAYLAND_DISPLAY" -a "$XDG_VTNR" = 1
      exec uwsm start hyprland.desktop
   end
end

function fish_greeting
   if test "$TERM_PROGRAM" != "vscode" -a -f ~/.cache/wallust/sequences
       fastfetch
       cat ~/.cache/wallust/sequences
   end
end


# Generated for envman. Do not edit.
test -s ~/.config/envman/load.fish; and source ~/.config/envman/load.fish
