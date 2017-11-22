#!/bin/bash
#
# buildscript to run under cygwin.
# Expects cygwin to have access to 'git' command to allow it to extract the git commit-id

log() {
	echo "$1"
	echo "$1" >> $logfile
}

maven-failed() {
	echo "mvn $1 command failed, is mvn available?"
	exit 1
}

git-failed() {
	echo "git $1 command failed"
	exit 1
}

run-mvn() {
	MSG=$1
	log "--> clean install $MSG"
	mvn clean install >> $logfile || maven-failed "clean install"
}	

mvn-deploy() {
	log "--> deploy"
	mvn deploy -Dmaven.test.skip=true -DaltDeploymentRepository=nexus.belfast::default::http://bfs-pdt-nexus-1:8081/nexus/content/repositories/lagan-releases >> $logfile || maven-failed "deploy"
}	

versions-set() {
	for dir in .
	do
		log "--> set $dir to $1"
		pushd $dir
		mvn versions:set -DnewVersion=$1 >> $logfile || maven-failed "set $dir"
		popd
	done

	run-mvn "to verify state of $1"

	log "--> commit versions"
	mvn versions:commit >> $logfile || maven-failed "versions:commit"
}

git-fetch-all() {
	log "--> track all remote branches"
	for remote in `git branch -r`; do git branch --track $remote; done
	log "--> fetch all"
	git fetch --all
	log "--> pull all"
	git pull --all
}

if [ $# -lt 2 ]; then
    echo "Usage: build.sh <branch-to-build> <new version number> (<new SNAPSHOT version number>)"
    exit 1
fi

GITBRANCH=$1
NEWVERSION=$2

if [ $# -eq 2 ]; then
	# NOTE, expects version in format X.Y.Z, we will bump Y
	maj=$(echo $NEWVERSION | cut -f1 -d.)
	min=$(echo $NEWVERSION | cut -f2 -d.)
	ver=$(echo $NEWVERSION | cut -f3 -d.)
	((min++))
	NEWSNAPSHOT=$(echo $NEWVERSION | cut -f1 -d.).$min.0-SNAPSHOT
else
	NEWSNAPSHOT=$3
fi

mkdir build-logs
logfile="`pwd`/build-logs/build-log_`date +%Y%m%d_%H%M%S`"

log "Building Version: $NEWVERSION"
log "Next Snapshot   : $NEWSNAPSHOT"
log "Logging to      : $logfile"

#git-fetch-all
log "--> git checkout $GITBRANCH"
git checkout $GITBRANCH

run-mvn "current SNAPSHOT"

versions-set $NEWVERSION

log "--> git commit and tag"
git commit -am "Release $NEWVERSION" >> $logfile || git-failed "commit $NEWVERSION" 
git tag -a v$NEWVERSION -m "Release $NEWVERSION" >> $logfile || git-failed "tag"

run-mvn "to check deploy $NEWVERSION"
mvn-deploy "deploy $NEWVERSION"

versions-set $NEWSNAPSHOT

log "--> commit and push $NEWSNAPSHOT"
git commit -am "Reset development $NEWSNAPSHOT" >> $logfile || git-failed "commit $NEWSNAPSHOT"

git push >> $logfile || git-failed "push"
git push origin v$NEWVERSION >> $logfile || git-failed "push tag v$NEWVERSION"

exit 0

