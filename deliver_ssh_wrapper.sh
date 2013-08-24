#!/bin/bash

#
#   Copyright 2012 Arnaud Betremieux <arno@arnoo.net>
#   Adapted with authorization from Ross Patterson's SSH wrapper
#   (http://ratterson.net/blog/re-using-and-multiplexing-ssh)
#
#   The program in this file is free software: you can redistribute it
#   and/or modify it under the terms of the GNU General Public License
#   as published by the Free Software Foundation, either version 3 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

## This is a Wrapper script for ssh that creates a control master
## in the background if one isn't already started.


master_id=$1
shift

if [[ $# == 0 ]]; then
	ssh -q -S ${master_id} -O exit not_used &> /dev/null
	exit
fi

## OpenSSH as included in the current msys install does not support
## multiplexing with privilege separation -> forget it
if [[ "$OSTYPE" == "msys" ]] && [[ `ssh -V 2>&1 | cut -d, -f1` == "OpenSSH_4.6p1" ]]; then
	exec ssh "$@"
fi

## Same with cygwin (on the TODO list since forever)
if [[ "$OSTYPE" == "cygwin" ]] && [[ `ssh -V 2>&1 | cut -d, -f1` == "OpenSSH_6.2p2" ]]; then
	exec ssh "$@"
fi

## optstring assembled from `man ssh`
optstring="+1246AaCfgKkMNnqsTtVvXxYb:c:D:e:F:i:L:l:m:O:o:p:R:S:w:z"
## get ssh options
opts=`getopt -- "$optstring" "$@"`

## the non-option args follow "--"
## convert to an array of IFS separated strings
args=(${opts#*--})

## the host is the first non-option arg
## use eval to process the quoted strings returned by getopt
host=`eval echo ${args[0]}`

## if the master isn't running, start it in the background
ssh -S $master_id -q -O check not_used 2>/dev/null || { SSH_OPTION=`ssh -V 2>&1 | awk 'BEGIN {FS="_"} $2>=5.6 { print "-o ControlPersist=5m"}'` ; ssh $SSH_OPTION -S $master_id -MNf $host > /dev/null || exit 255; }

## replace ourselves with the reall ssh call
exec ssh -S $master_id "$@"
