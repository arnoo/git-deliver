#!/bin/bash

assertTrueEcho()
	{
	$1 || ( echo "$1" && assertTrue false )
	}

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
	rm -rf "$ROOT_DIR/test_remote"
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
	echo "$RESULT" | grep "Core git deliver hooks" > /dev/null
	assertEquals 0 $?
	}

testInit()
	{
	cd "$ROOT_DIR/test_repo"
	$ROOT_DIR/deliver.sh --init
	assertTrueEcho "[ -d .deliver ]"
	assertTrueEcho "[ -d .deliver/hooks ]"
	assertTrueEcho "[ -d .deliver/hooks/pre-delivery ]"
	assertTrueEcho "[ -f .deliver/hooks/pre-delivery/01-core-disk-space.sh ]"
	assertTrueEcho "[ -f .deliver/hooks/pre-delivery/01-core-mem-free.sh ]"
	assertTrueEcho "[ -d .deliver/hooks/init-remote ]"
	assertTrueEcho "[ -d .deliver/hooks/post-checkout ]"
	assertTrueEcho "[ -d .deliver/hooks/post-symlink ]"
	assertTrueEcho "[ -d .deliver/hooks/rollback ]"
	}

testInitHook()
	{
	cd "$ROOT_DIR/test_repo"
	"$ROOT_DIR/deliver.sh" --init php
	assertTrueEcho "[ -f .deliver/hooks/pre-delivery/01-php-syntax-check.sh ]"
	}

testUnknownRemote()
	{
	cd "$ROOT_DIR/test_repo"
	local RESULT=`$ROOT_DIR/deliver.sh --batch non_existent_remote master 2>&1`
	echo "RESULT:  $RESULT"
	assertEquals "Remote non_existent_remote not found." "$RESULT"
	}

#testUnknownRef()
#	{
#	cd "$ROOT_DIR/test_repo"
#	RESULT=`"$ROOT_DIR/deliver.sh" --batch origin non_existent_ref 2>&1`
#	assertEquals "Ref non_existent_ref not found." "$RESULT"
#	}
#
#testBasicDeliver1()
#	{
#	git clone --bare "$ROOT_DIR/test_repo" "$ROOT_DIR/test_remote" 
#	cd "$ROOT_DIR/test_repo"
#	git remote add origin "$ROOT_DIR/test_remote"
#	"$ROOT_DIR/deliver.sh" origin master 
#	assertTrue [ -d "$ROOT_DIR/test_remote/delivered" ]
#	assertTrue [ -d "$ROOT_DIR/test_remote/delivered/master" ]
#	}

. lib/shunit2
