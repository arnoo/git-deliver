#!/bin/bash

oneTimeSetUp()
	{
	ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
	OLD_PWD=`pwd`

	mkdir "$ROOT_DIR/test_repo"
	cd "$ROOT_DIR/test_repo"
	git init
	echo "blah blah" > a
	git add a
	git commit -m "test commit"
	cd $ROOT_DIR
	}

oneTimeTearDown()
	{
	rm -rf "$ROOT_DIR/test_repo"
	cd $OLD_PWD
	}

tearDown()
	{
	rm -rf "$ROOT_DIR/test_repo/.deliver"
	cd $ROOT_DIR
	}

testHelp1()
	{
	cd "$ROOT_DIR/test_repo"
	$ROOT_DIR/deliver.sh | grep "git deliver <REMOTE> <VERSION>" > /dev/null
	assertEquals 0 $?
	}

testListHooks()
	{
	cd "$ROOT_DIR/test_repo"
	local RESULT=`$ROOT_DIR/deliver.sh --list-hooks`
	local ERRLINES=`echo "$RESULT" 2| wc -l`
	assertEquals "0" "$ERRLINES"
	echo "$RESULT" | grep "Generic git-deliver hooksI" > /dev/null 2>&1
	assertEquals 0 $?
	}

testInit()
	{
	cd "$ROOT_DIR/test_repo"
	$ROOT_DIR/deliver.sh --init
	assertTrue "[ -d .deliver ]"
	assertTrue "[ -d .deliver/hooks ]"
	assertTrue "[ -d .deliver/hooks/check ]"
	assertTrue "[ -f .deliver/hooks/check/01-core-disk-space.sh ]"
	assertTrue "[ -f .deliver/hooks/check/01-core-mem-free.sh ]"
	assertTrue "[ -d .deliver/hooks/init-remote ]"
	assertTrue "[ -d .deliver/hooks/post-checkout ]"
	assertTrue "[ -d .deliver/hooks/post-symlink ]"
	assertTrue "[ -d .deliver/hooks/rollback ]"
	}

testInitHook()
	{
	cd "$ROOT_DIR/test_repo"
	"$ROOT_DIR/deliver.sh" --init php
	assertTrue "[ -f .deliver/hooks/php/01TODO ]"

	}

testUnknownRemote()
	{
	cd "$ROOT_DIR/test_repo"
	RESULT=`"$ROOT_DIR/deliver.sh" --batch non_existent_remote master 2>&1`
	assertEquals "Remote non_existent_remote not found." "$RESULT"
	}

testUnknownRef()
	{
	cd "$ROOT_DIR/test_repo"
	RESULT=`"$ROOT_DIR/deliver.sh" --batch origin non_existent_ref 2>&1`
	assertEquals "Ref non_existent_ref not found." "$RESULT"
	}

testBasicDeliver1()
	{
	cd "$ROOT_DIR/test_repo"
	mv "$ROOT_DIR/test_repo" "$ROOT_DIR/test_remote"
	git clone --bare "$ROOT_DIR/test_remote" "$ROOT_DIR/test_repo" 
	"$ROOT_DIR/deliver.sh" origin master 
	assertTrue [ -d "$ROOT_DIR/test_remote/delivered" ]
	assertTrue [ -d "$ROOT_DIR/test_remote/delivered/master" ]

	}

. lib/shunit2
