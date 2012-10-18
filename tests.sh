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

testInit()
	{
	cd "$ROOT_DIR/test_repo"
	$ROOT_DIR/deliver.sh --init
	assertTrue "[ -d .deliver ]"
	assertTrue "[ -d .deliver/hooks ]"
	assertTrue "[ -d .deliver/hooks/check ]"
	assertTrue "[ -d .deliver/hooks/init-remote ]"
	assertTrue "[ -d .deliver/hooks/post-checkout ]"
	assertTrue "[ -d .deliver/hooks/post-symlink ]"
	assertTrue "[ -d .deliver/hooks/rollback ]"
	ls -l .deliver/hooks
	}

testInitHook()
	{
	cd test_repo
	$ROOT_DIR/deliver.sh --init php
	assertTrue [[ -d .deliver ]]
	assertTrue [[ -d .deliver/hooks ]]
	}

. lib/shunit2
