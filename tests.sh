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
	}

oneTimeTearDown()
	{
	rm -rf "$ROOT_DIR/test_repo"
	cd $OLD_PWD
	}

tearDown()
	{
	rm -rf "$ROOT_DIR/.deliver"
	}

testHelp1()
	{
	cd "$ROOT_DIR/test_repo"
	$ROOT_DIR/deliver.sh
	}

testInit()
	{
	cd "$ROOT_DIR/test_repo"
	$ROOT_DIR/deliver.sh --init
	assertTrue [[ -d .deliver ]]
	assertTrue [[ -d .deliver/hooks ]]
	}

testInitHook()
	{
	cd test_repo
	$ROOT_DIR/deliver.sh --init php
	assertTrue [[ -d .deliver ]]
	assertTrue [[ -d .deliver/hooks ]]
	}

. lib/shunit2
