# Login-session environment. .profile already sources .bashrc for bash, so the
# shared fragment keeps PATH/PAGER identical when only .profile runs.
[ -r "$HOME/.bashrc.d/00-env.sh" ] && . "$HOME/.bashrc.d/00-env.sh"
