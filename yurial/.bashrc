# /etc/skel/.bashrc
#
# This file is sourced by all *interactive* bash shells on startup,
# including some apparently interactive shells such as scp and rcp
# that can't tolerate any output.  So make sure this doesn't display
# anything or bad things will happen !


# Test for an interactive shell.  There is no need to set anything
# past this point for scp and rcp, and it's important to refrain from
# outputting anything in those cases.
if [[ $- != *i* ]] ; then
	# Shell is non-interactive.  Be done now!
	return
fi

source /etc/profile

HISTSIZE=1000000
HISTFILESIZE=1000000

EDITOR=vim
PATH="~/.bin:/usr/sbin:/sbin:$PATH"

alias agrep="grep --colour=auto --colour=auto --exclude-dir=.git --exclude-dir=deps --exclude-dir=build --exclude-dir=new_reports -Rn"
alias cstyle="ya tool clang-format -style=file -i"

# Put your fun stuff here.
