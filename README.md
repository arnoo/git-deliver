Introduction
============

Git-deliver is a GPL licensed delivery system based on Git.

It uses "git push" combined with SSH as a way of delivering a project to various environments (Git remotes) securely.

Each delivery remote is a bare Git repository, in the root of which Git-deliver creates a "delivered" folder. This folder will contain one non-bare clone of the base repository for each delivery.

The git clones share their metadata with the main repository for the remote, to avoid excessive space usage / copy time.

The current version's clone is used through a "current" symlink, which is switched once the new version is ready, to make the delivery "atomic".

A delivery is done in stages. Between each stage, Bash scripts can be run to adapt the delivery process to the project.


Installation
============

All platforms
-------------

Clone this repository in the directory of your choice.

In your .gitconfig, add this line in the `[alias]` section:

    deliver = "!bash <path_to_clone>/deliver.sh"

Where `<path_to_clone>` is the path to the root of the git clone you just made.


Note that Git-deliver has only been tested on Windows (msys) and Linux so far.


Windows
-------

To use Git-deliver on Windows, you'll need to copy the libintl-8.dll and getopt.exe from the "msys" folder of the git-deliver clone to your "C:\Program Files (x86)\Git\bin" or "C:\Program Files\Git\bin". These are files from the MinGW project (http://www.mingw.org/) which are included with Git-deliver for convenience.

BSD
---

BSD users need to install GNU getopts (cd /usr/ports/misc/getopt/ && sudo make install)


A simple example (TL;DR)
========================

Let's assume for this example that you have a simple project for which a delivery just means copying files.

Git-deliver will allow you to deliver the project (as of a specific git commit) to servers, to rollback a delivery, and to keep track of what is delivered on which server.

The example below assumes that the server is accessible with SSH. You'll want to setup SSH public key authentication, as Git-deliver will open lots of SSH connections (this should change in future versions). See http://stackoverflow.com/questions/7260/how-do-i-setup-public-key-authentication for instructions.

To setup your project for Git-deliver, in your project directory, run:

    git deliver --init
    git add .deliver && git commit # to track and share delivery files

Create a bare repository on the server where you want the project delivered, and add it as a remote in your local Git project, or ask Git-deliver to do it:

    git deliver --init-remote test_server user@test_server.example.com:/project_files

You can then perform your first delivery (here, of your local "master"):

    git deliver test_server master

Your project is now accessible on test_server.example.com at /project_files/delivered/current

Let's deliver another version (tagged "v1.0"):

    git deliver test_server v1.0

You can ask Git-deliver what the current version on test_server is, who delivered it and when:

    git deliver --status test_server


Usage
=====

    git deliver <REMOTE> <REF>

deliver `<REF>` (sha1, tag, branch) on `<REMOTE>`.


    git deliver --status [REMOTE]

Returns the version delivered (if any) on `[REMOTE]`, or on all remotes if `[REMOTE]` is not specified.

	git deliver --rollback <REMOTE> [PREVIOUSLY_DELIVERED_FOLDER]

Switches back to a previously delivered version on `<REMOTE>`. This is like a regular delivery, except we reuse an already delivered folder and use it to start the process at stage pre-symlink. You can give the name of a previous delivery folder; if you don't, the "previous" version is used.

    git deliver --gc <REMOTE>

"garbage collection": remove all previously delivered versions on `<REMOTE>`, except the last three ("current", "previous", "preprevious")

    git deliver --init [presets]

Initialise this repository for git-deliver, optionally including stage scripts for `[presets]`

    git deliver --init-remote <REMOTE_NAME> [REMOTE_URL]

Initialize Git remote `<REMOTE_NAME>` for git-deliver. The remote needs to be bare. If it does not exist yet, it can be created at `[REMOTE_URL]`. If the remote exists but does not point to a bare repository, the repository will be created.

    git deliver --list-presets

List available presets for --init


How it works
============

To get started, you'd run `git deliver --init` in your Git working folder. This would create an empty ".deliver" folder next to the ".git" one. You'd then be able to create scripts in this folder to customize the delivery process should you want to. You could keep the .deliver folder under version control and share it with your team that way.

If you wanted to start with presets for a given environment, you'd give init a list of preset names: something like `git deliver --init rails rails-pgsql` would copy both the "rails" scripts and the "rails-pgsql" scripts, both of which might depend on others which will be automatically copied as well. The list of available presets can be viewed by running `git deliver --list-presets`.

Note that presets are pretty much inexistent right now; I very much welcome contributions in this area.

Once our working copy is ready, if you have "init-remote" scripts, you'll need to run `git deliver --init-remote <remote>` to run those. They might be used to install external dependencies on the remote. If you don't have "init-remote" scripts, remote initialization is not needed.

A delivery is then initiated by running `git deliver <remote> <ref>`. Here's the timeline of what happens:

* We run preliminary checks. By default, we just check the available disk space on the remote, but you can create "pre-delivery" scripts to add checks.

* The commit to deliver is pushed to the remote, and the remote repository cloned in the delivered folder. "post-checkout" scripts are then run.

* Your scripts might change the delivered files (add production passwords for instance). We therefore do a commit in the clone repository, to save the delivered state. We then run the "pre-symlink" scripts.

* We change the "current", "previous" and "preprevious" symlinks atomically to point to the corresponding new folders, and run the "post-symlink" scripts.

* If any of the run scripts fails (has a non zero exit status) or if an internal git-deliver step fails, we'll stop the delivery there and initiate a rollback. To do this, we'll run the "rollback-pre-symlink" scripts, switch the symlinks back if necessary (if we went as far in the process as to change them in the first place), then run the "rollback-post-symlink" scripts.

Stage scripts
=============

Stage scripts can read a few environment variables to gather information about the delivery process.

All stages have access to:

    $VERSION               the ref being delivered, as it was specified on the command line
    $VERSION_SHA           sha1 of the ref being delivered
    $PREVIOUS_VERSION_SHA  sha1 of the previously delivered ref
    $GIT_DELIVER_PATH      path to where git-deliver is stored
    $REPO_ROOT             root of the local git repo
    $DELIVERY_DATE         date and time the delivery was initiated (using date +'%F_%H-%M-%S')
    $REMOTE_SERVER         hostname or IP of the server we are delivering to, empty if doing a local delivery
    $REMOTE_PATH           path to the bare remote repository we are delivering to
    $REMOTE                name of the Git remote we are delivering to
    $DELIVERY_PATH         path where the version will be delivered on the remote ($REMOTE_PATH/delivered/$VERSION_$DELIVERY_DATE)
	$IS_ROLLBACK		   boolean, true if this delivery is a rollback to a previously installed version

Scripts for stages rollback-pre-symlink and rollback-post-symlink have access to:

    $LAST_STAGE_REACHED       The last stage the delivery reached before rollback had to be called. This allows the rollback stage scripts to know what needs to be undone to perform the rollback. Empty if delivery stopped before stage "pre-delivery".
    $FAILED_SCRIPT              Name of the stage script that failed, triggering the rollback. Empty if the rollback was caused by an error in the standard Git-deliver process.
    $FAILED_SCRIPT_EXIT_STATUS  Exit status of the stage script that failed, triggering the rollback. 0 if the rollback was caused by a SIGINT (CTRL+C).

Stage scripts can use the `run_remote` bash function to run commands on the remote through SSH (as the SSH user setup for the remote in Git). `run_remote` also works for "local" remotes, the command will then be run as the user running git-deliver.

Scripts with a name ending in .remote.sh will be executed entirely on the remote.


Status, Roadmap
===============

Although I have started using it often, git-deliver is still in it's early stages. "It works for me", but your mileage may vary.

See the output of `grep -r TODO` for an idea of coming changes and fixes.

I welcome all suggestions and code contributions.
