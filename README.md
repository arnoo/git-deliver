Git-deliver is a GPL licensed delivery system based on Git.


It uses "git push" combined with SSH as a way of delivering a project to various environments (Git remotes) securely.

Each delivery remote is a bare Git repository, in the root of which Git-deliver creates a "delivered" folder. This folder will contain one non-bare clone of the base repository for each delivery.

Since git clone uses hard-links to the original repository when on the same filesystem, this does not result in excessive space usage / copy time.

The current version's clone is used through a "current" symlink, which makes the delivery "atomic".

A remote's "delivered" folder might look like this :

TODO (ls -l de mg/delivered)


A delivery is done in stages. Between each stage, Bash scripts can be run to adapt the delivery process to the project's needs.




To get started, you'd run "git deliver --init" in your git working folder. This would create an empty .deliver folder next to the ".git" one. You'd then be able to create scripts in this folder to customize the delivery process should you want to. You could keep the .deliver folder under version control.

If you want to start with presets for a given environment, you'd give init a list of preset names: something like "git deliver --init rails rails-pgsql" would copy both the "rails" scripts and the "rails-pgsql" scripts, both of which might depend on others which will be automatically copied as well. The list of available presets can be viewed by running "git deliver --list-presets".

Note that there are nearly no presets right now; I very much welcome contributions in this area. The "yisti" preset, which is build for a custom Common-Lisp environement shows how scripts can get delivery information, how dependencies are defined, how to execute scripts on the remote, and how to signal errors.

Once our working copy is ready, each remote needs to be initialized (by running "git deliver --init-remote <remote>", where <remote> is the name of bare Git remote. This will result in the creation of the "delivered" folder on the remote. If you have "init-remote" scripts, they will be run. This might be used to install external dependencies on the remote.

A delivery is then initiated by running "git deliver <remote> <ref>". Here's the timeline of what happens :

* We run preliminary checks. By default, we just check the available disk space on the remote, but you can create "pre-delivery" scripts to add checks.

* The commit to deliver is pushed to the remote, and the remote repository cloned in the delivered folder. "post-checkout" scripts are then run.

* Your scripts might change the delivered files (add production passwords for instance). We therefore do a commit in the clone repository, to save the delivered state. We then change the "current", "previous" and "preprevious" symlinks atomically to point to the corresponding new folders, and run the "post-symlink" scripts.

* If any of the run scripts fails (has a non zero exit status) or if an internal git-deliver step fails, we'll not run the others, and instead initiate a rollback. To do this, we'll run the "rollback-pre-symlink" scripts, switch the symlinks back if necessary (if we went as far in the process as to change them in the first place), then run the "rollback-post-symlink" scripts.



Stage scripts can read a few envrionment variables to gather information about the delivery process.

ALL STAGES:

$VERSION
$DELIVERY_PATH : path where the version will be delivered on the remote


PRE-DELIVERY:

POST-CHECKOUT:

POST-SYMLINK:

ROLLBACK:
$LAST_STAGE_REACHED : the last stage the delivery reached before rollback had to be called

$LAST_STAGE : what stage the delivery was in before rollback was initiated. This allows the hooks to know what needs to be undone to perform the rollback
$FAILED_HOOK : name of the hook that failed, triggering the rollback. Empty if the rollback was caused by human intervention (CTRL+C ... TODO)
$FAILED_HOOK_EXIT_STATUS : exit status of the hook that failed, triggering the rollback


Although I have started using it often, git-deliver is still in it's early stages.

Roadmap / TODO:


I welcome all suggestions and code contributions.
