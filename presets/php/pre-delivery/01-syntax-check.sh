PHPL=`find ./ -type f -name \*.php -exec php -l {} \; 2>&1`
echo "$PHPL" | grep "Parse error"
if [[ $? -gt 0 ]]; then
	exit 0;
else
	exit 1;
fi
