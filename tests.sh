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
	echo "[ -d .deliver ]"
	assertTrue "[ -d .deliver ]"
	echo "[ -d .deliver/hooks ]"
	assertTrue "[ -d .deliver/hooks ]"
	echo "[ -d .deliver/hooks/pre-delivery ]"
	assertTrue "[ -d .deliver/hooks/pre-delivery ]"
	echo "[ -f .deliver/hooks/pre-delivery/001-core-disk-space.sh ]"
	assertTrue "[ -f .deliver/hooks/pre-delivery/01-core-disk-space.sh ]"
	echo "[ -f .deliver/hooks/pre-delivery/001-core-mem-free.sh ]"
	assertTrue "[ -f .deliver/hooks/pre-delivery/01-core-mem-free.sh ]"
	echo "[ -d .deliver/hooks/init-remote ]"
	assertTrue "[ -d .deliver/hooks/init-remote ]"
	echo "[ -d .deliver/hooks/post-checkout ]"
	assertTrue "[ -d .deliver/hooks/post-checkout ]"
	echo "[ -d .deliver/hooks/post-symlink ]"
	assertTrue "[ -d .deliver/hooks/post-symlink ]"
	echo "[ -d .deliver/hooks/rollback ]"
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
	git clone --bare "$ROOT_DIR/test_repo" "$ROOT_DIR/test_remote" 
	cd "$ROOT_DIR/test_repo"
	git remote add origin "$ROOT_DIR/test_remote"
	"$ROOT_DIR/deliver.sh" origin master 
	assertTrue [ -d "$ROOT_DIR/test_remote/delivered" ]
	assertTrue [ -d "$ROOT_DIR/test_remote/delivered/master" ]
	}

. lib/shunit2
