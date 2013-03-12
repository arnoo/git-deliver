DB_DIFF=`git diff $RUNNING_GIT $NEW_GIT $DB_FILES`
LISP_DIFF_LINES=`git diff $RUNNING_GIT $NEW_GIT *.lisp | wc -l`
if [[ `echo "$DB_DIFF" | wc -l` != "1" ]]; then
echo "    Warning : there are database changes."
echo "$DB_DIFF"
echo "    You'll have to apply them manually, either now or when the new Lisp is ready"
read -p "    Press any key to continue"
fi
