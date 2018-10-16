#!/usr/bin/awk -f
BEGIN {
	REPO_URL = getRepoURL()
	# Prefixes that determine whether a commit will be printed

	JIRA_TICKET = "[a-zA-z]+-[0-9]+"
	BUGFIX_INF = "fix|fixed|hotfix|hotFix"
	UPDATE_INF = "chore|test|refactoring|update|ci"
	FEAT_INF = "feat|feature|add|added"
	DOCS_INF = "changelog|docs|doc"

	CHANGELOG_REGEX = JIRA_TICKET "[:; ]+.*(" BUGFIX_INF "|"  FEAT_INF "|" UPDATE_INF "doc|docs)[:; ]+"
	FS="|"

	# Prefixes used to classify commits

	FEATURE_REGEX = "(" FEAT_INF ")[: ]?"
	DOCS_REGEX    = "(" DOCS_INF ")[: ]?"
	BUG_FIX_REGEX = "(" BUGFIX_INF ")[: ]?"
	UPDATE_REGEX  = "(" UPDATE_INF ")[: ]?"

	FEATURE_COUNT = 0
	BUG_FIX_COUNT = 0
	DOCS_COUNT = 0
	UPDATE_COUNT = 0
	OUTPUT_COUNT = 0

	# Skip commits with matched message
	MSG_SKIP_REGEX = "^(Merge branch.*|jenkins produced Build_[0-9]+|update|cleanup|ready_to_build||)$"

	# Get git log and store in array

	# %D: tags
	# %s: commit message
	# %H: long hash
	# %h: short hash

	i = 1
	while ("git log --date=short --pretty='%D|%s|%H|%h|%cd|%an' --no-merges --reverse " REVISION_RANGE  | getline) {
		LINES[i] = $0
		i++
	}

	# Iterate over array and store output in chronogical order

	i = 1
	while (LINES[i]) {

		# Split line into pieces defined above

		split( LINES[i], pieces, "|" )

		tag = pieces[1]
		message = pieces[2]
		longHash = pieces[3]
		shortHash = pieces[4]
		date = pieces[5]
		name = pieces[6]

		IS_GIT_TAG = length(tag) && match(tag, /tag:/)

		if (IS_GIT_TAG){

			# This represents a new version
			# Commits before this point should be printed before the tag

			printUpdates()
			printDocumentation()
			printBugFixes()
			printFeatures()

			# Add version

			printTag(tag, date)

		} else {

			# Determine if this commit is something to show in CHANGELOG

			classifyCommit(message, longHash, shortHash, date, name)

		}

		i++
	}

	# Print remaining commits
	# Anything here is pending release on next version

	if (FEATURE_COUNT > 0 || BUG_FIX_COUNT > 0 || DOCS_COUNT > 0 || UPDATE_COUNT > 0) {

		printUpdates()
		printDocumentation()
		printBugFixes()
		printFeatures()

		if (TYPE == "plain") {
			storeOutput("Current\n")
		} else {
			storeOutput("## Current\n")
		}

	}

	printOutput()
}

function printOutput() {

	# Print stored output in reverse order

	while (OUTPUT_COUNT) {
		print(OUTPUT[--OUTPUT_COUNT])
	}
}
function printFeatures() {
	if (FEATURE_COUNT > 0){
		while (FEATURE_COUNT){
			storeOutput(FEATURES[--FEATURE_COUNT])
		}

		storeHeader(sprintf("### New Features\n"))
		FEATURE_COUNT = 0
	}
}

function printBugFixes() {
	if (BUG_FIX_COUNT > 0){
		while (BUG_FIX_COUNT){
			storeOutput(BUG_FIXES[--BUG_FIX_COUNT])
		}

		storeHeader(sprintf("### Bug Fixes\n"))
		BUG_FIX_COUNT = 0
	}
}

function printDocumentation() {
	if (DOCS_COUNT > 0){
		while (DOCS_COUNT){
			storeOutput(DOCS[--DOCS_COUNT])
		}

		storeHeader(sprintf("### Documentation Changes\n"))
		DOCS_COUNT = 0
	}
}

function printUpdates() {
	if (UPDATE_COUNT > 0){
		while (UPDATE_COUNT){
			storeOutput(UPDATES[--UPDATE_COUNT])
		}

		storeHeader(sprintf("### Updates\n"))
		UPDATE_COUNT = 0
	}
}

function classifyCommit(message, longHash, shortHash, date, name) {
	if ( name == "Jenkins Agent" ) { return }
	if ( match(message, MSG_SKIP_REGEX) ) {
		return
	}
	sub(" *ready_to_build[;: ]*", "", message)

	if ( match(message, FEATURE_REGEX) ) {
		FEATURES[FEATURE_COUNT++] = getCommitLine(message, longHash, shortHash, date, name)
		return
	}
	if ( match(message, BUG_FIX_REGEX) ) {
		BUG_FIXES[BUG_FIX_COUNT++] = getCommitLine(message, longHash, shortHash, date, name)
		return
	}
	if ( match(message, DOCS_REGEX) ) {
		DOCS[DOCS_COUNT++] = getCommitLine(message, longHash, shortHash, date, name)
		return
	}
	if ( match(message, UPDATE_REGEX) ) {
		UPDATES[UPDATE_COUNT++] = getCommitLine(message, longHash, shortHash, date, name)
		return
	}
	if ( match(message, JIRA_TICKET) ) {
		FEATURES[FEATURE_COUNT++] = getCommitLine(message, longHash, shortHash, date, name)
		return
	}
}

function getCommitLine(message, longHash, shortHash, date, name) {
	sub(CHANGELOG_REGEX, "", message)
	if (TYPE == "plain")
		return sprintf("\t- %s\n", message, makeCommitLink(REPO_URL, shortHash, longHash) )
	else
		return sprintf("- %s (%s) (%s)\n", message, makeCommitLink(REPO_URL, shortHash, longHash), name )
}

function printTag(input, date) {
	# Cut out text up to tag
	sub(/.*tag: v/, "", input)
	# Cut out text after tag
	sub(/,.*/, "", input)

	split(input, parts, ".")

	format = "##"

	MAJOR_VERSION = parts[1]
	MINOR_VERSION = parts[2]
	PATCH_VERSION = parts[3]

	if (TYPE == "plain")
		storeOutput(sprintf("\n%s (%s)\n", input, date))
	else
		storeOutput(sprintf("\n%s %s (%s)\n", format, input, date))
}
function printCommit(input, longHash, shortHash) {
	if ( match(input, CHANGELOG_REGEX) ) {
		sub(CHANGELOG_REGEX, "", input)
		if (TYPE == "plain")
			sprintf("\t- %s\n", input, makeCommitLink(REPO_URL, shortHash, longHash) )
		else
			sprintf("- %s (%s)\n", input, makeCommitLink(REPO_URL, shortHash, longHash) )
	}
}
function makeCommitLink(repoUrl, shortHash, longHash) {
	return ("[" shortHash "](" repoUrl "/commit/" longHash ")")
}
# Get Git repo URL
function getRepoURL() {
	"git config --get remote.upstream.url || git config --get remote.origin.url || git config --get remote.dev.url" | getline REPO_URL
	sub(/:/, "/", REPO_URL)
	sub(/git@|https?:?\/+/, "https://", REPO_URL)
	sub(/\.git/, "", REPO_URL)
	return REPO_URL
}
function storeOutput(string) {
	OUTPUT[OUTPUT_COUNT++] = string
}
function storeHeader(string) {
	if (TYPE == "plain"){
		sub(/\#+ /, "\t", string)
	}
	# sub(/\s/, "\t", string)
	OUTPUT[OUTPUT_COUNT++] = string
}
