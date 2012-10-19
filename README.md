git-deliver is a delivery system based on git.

It uses "git push" as a way of delivering a project to various environments (git remotes) securely.

To get started, in a git project, type :
git deliver --init

This will create a .deliver directory next to the .git one. 

git deliver --init drupal

Hooks are bash scripts. They should exit with a status of 0 if everything went well. If a hook returns a status that is higher than 0, it is assumed that aborting the delivery is is necessary, and rollback hooks will be called. #TODO: two rollback stages ? no : hooks get access to a LAST_STAGE variable telling them how far the process went

Hooks have access to the following global variables (for reading only ! TODO: reinit hook variables before calling each hook for safety ?)


ALL STAGES:

$VERSION
$DELIVERY_PATH : path where the version will be delivered on the remote

PRE-DELIVERY:

POST-CHECKOUT:

POST-SYMLINK:

ROLLBACK:

$LAST_STAGE : what stage the delivery was in before rollback was initiated. This allows the hooks to know what needs to be undone to perform the rollback
$FAILED_HOOK : name of the hook that failed, triggering the rollback. Empty if the rollback was caused by human intervention (CTRL+C ... TODO)
$FAILED_HOOK_EXIT_STATUS : exit status of the hook that failed, triggering the rollback
