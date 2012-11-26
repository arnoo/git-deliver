cat $REPO_ROOT/.deliver/hooks/dependencies/yisti/switch.sh | run_remote "cat > /tmp/yisti_switch.sh"

run_remote "bash /tmp/yisti_switch.sh \"$DELIVERY_PATH\" && rm -f /tmp/yisti_switch.sh"
exit $?
