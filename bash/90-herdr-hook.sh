# herdr-automatic-rename: live tab naming hook.
# Sources the plugin's shell hook when the plugin is installed; a no-op otherwise.
#
# herdr-automatic-rename: live tab naming hook
for _f in $HOME/.config/herdr/plugins/github/herdr-automatic-rename-*/shell/hook.bash; do
  [ -r "$_f" ] && { source "$_f"; break; }
done
