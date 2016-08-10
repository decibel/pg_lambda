PGXNTOOL_DIR := pgxntool

#
# META.json
#
PGXNTOOL_distclean += META.json
META.json: META.in.json $(PGXNTOOL_DIR)/build_meta.sh
	@$(PGXNTOOL_DIR)/build_meta.sh $< $@

#
# meta.mk
#
# Buind meta.mk, which contains info from META.json, and include it
PGXNTOOL_distclean += meta.mk
meta.mk: META.json Makefile $(PGXNTOOL_DIR)/base.mk $(PGXNTOOL_DIR)/meta.mk.sh
	@$(PGXNTOOL_DIR)/meta.mk.sh $< >$@

-include meta.mk

DATA         = $(EXTENSION_VERSION_FILES) $(wildcard sql/*--*--*.sql)
DOCS         = $(wildcard doc/*.asc)
ifeq ($(strip $(DOCS)),)
DOCS =# Set to NUL so PGXS doesn't puke
endif

PG_CONFIG   ?= pg_config
TESTDIR		?= test
TESTOUT		?= $(TESTDIR)
TEST_SOURCE_FILES	+= $(wildcard $(TESTDIR)/input/*.source)
TEST_OUT_FILES		 = $(subst input,output,$(TEST_SOURCE_FILES))
TEST_SQL_FILES		+= $(wildcard $(TESTDIR)/sql/*.sql)
TEST_RESULT_FILES	 = $(patsubst $(TESTDIR)/sql/%.sql,$(TESTDIR)/expected/%.out,$(TEST_SQL_FILES))
TEST_FILES	 = $(TEST_SOURCE_FILES) $(TEST_SQL_FILES)
REGRESS		 = $(sort $(notdir $(subst .source,,$(TEST_FILES:.sql=)))) # Sort is to get unique list
REGRESS_OPTS = --inputdir=$(TESTDIR) --outputdir=$(TESTOUT) --load-language=plpgsql
MODULES      = $(patsubst %.c,%,$(wildcard src/*.c))
ifeq ($(strip $(MODULES)),)
MODULES =# Set to NUL so PGXS doesn't puke
endif

EXTRA_CLEAN  = $(wildcard ../$(PGXN)-*.zip) $(EXTENSION_VERSION_FILES)

# Get Postgres version, as well as major (9.4, etc) version. Remove '.' from MAJORVER.
VERSION 	 = $(shell $(PG_CONFIG) --version | awk '{print $$2}' | sed -Ee 's/\(alpha|beta|devel\).*//')
MAJORVER 	 = $(shell echo $(VERSION) | cut -d . -f1,2 | tr -d .)

# Function for testing a condition
test		 = $(shell test $(1) $(2) $(3) && echo yes || echo no)

GE91		 = $(call test, $(MAJORVER), -ge, 91)

ifeq ($(GE91),yes)
all: $(EXTENSION_VERSION_FILES)

#DATA = $(wildcard sql/*--*.sql)
endif

PGXS := $(shell $(PG_CONFIG) --pgxs)
# Need to do this because we're not setting EXTENSION
MODULEDIR = extension
DATA += $(wildcard *.control)

# Don't have installcheck bomb on error
.IGNORE: installcheck
installcheck: $(TEST_RESULT_FILES) $(TEST_OUT_FILES)

#
# testdeps
#
.PHONY: testdeps
testdeps: pgtap

$(TESTDIR)/sql:
	@mkdir -p $@

$(TESTDIR)/expected/:
	@mkdir -p $@
$(TEST_RESULT_FILES): $(TESTDIR)/expected/
	@touch $@

$(TESTDIR)/output/:
	@mkdir -p $@
$(TEST_OUT_FILES): $(TESTDIR)/output/ $(TESTDIR)/expected/ $(TESTDIR)/sql/
	@touch $@

.PHONY: test
test: clean testdeps install installcheck
	@if [ -r $(TESTOUT)/regression.diffs ]; then cat $(TESTOUT)/regression.diffs; fi

.PHONY: results
results: test
	rsync -rlpgovP $(TESTOUT)/results/ $(TESTDIR)/expected

rmtag:
	git fetch origin # Update our remotes
	@test -z "$$(git branch --list $(PGXNVERSION))" || git branch -d $(PGXNVERSION)
	@test -z "$$(git branch --list -r origin/$(PGXNVERSION))" || git push --delete origin $(PGXNVERSION)

# TODO: Don't puke if tag already exists *and is the same*
tag:
	@test -z "$$(git status --porcelain)" || (echo 'Untracked changes!'; echo; git status; exit 1)
	git branch $(PGXNVERSION)
	git push --set-upstream origin $(PGXNVERSION)

.PHONY: forcetag
forcetag: rmtag tag

.PHONY: dist
dist: tag dist-only

dist-only:
	git archive --prefix=$(PGXN)-$(PGXNVERSION)/ -o ../$(PGXN)-$(PGXNVERSION).zip $(PGXNVERSION)

.PHONY: forcedist
forcedist: forcetag dist

# Target to list all targets
# http://stackoverflow.com/questions/4219255/how-do-you-get-the-list-of-targets-in-a-makefile
.PHONY: no_targets__ list
no_targets__:
list:
	sh -c "$(MAKE) -p no_targets__ | awk -F':' '/^[a-zA-Z0-9][^\$$#\/\\t=]*:([^=]|$$)/ {split(\$$1,A,/ /);for(i in A)print A[i]}' | grep -v '__\$$' | sort"

# To use this, do make print-VARIABLE_NAME
print-%	: ; $(info $* is $(flavor $*) variable set to "$($*)") @true


#
# subtree sync support
#
# This is setup to allow any number of pull targets by defining special
# variables. pgxntool-sync-release is an example of this.
.PHONY: pgxn-sync-%
pgxntool-sync-%:
	git subtree pull -P pgxntool --squash -m "Pull pgxntool from $($@)" $($@)
pgxntool-sync: pgxntool-sync-release

# DANGER! Use these with caution. They may add extra crap to your history and
# could make resolving merges difficult!
pgxntool-sync-release	:= git@github.com:decibel/pgxntool.git release
pgxntool-sync-stable	:= git@github.com:decibel/pgxntool.git stable
pgxntool-sync-local		:= ../pgxntool release # Not the same as PGXNTOOL_DIR!
pgxntool-sync-local-stable	:= ../pgxntool stable # Not the same as PGXNTOOL_DIR!

distclean:
	rm -f $(PGXNTOOL_distclean)

ifndef PGXNTOOL_NO_PGXS_INCLUDE
include $(PGXS)
#
# pgtap
#
# NOTE! This currently MUST be after PGXS! The problem is that
# $(DESTDIR)$(datadir) aren't being expanded. This can probably change after
# the META handling stuff is it's own makefile.
#
.PHONY: pgtap
pgtap: $(DESTDIR)$(datadir)/extension/pgtap.control

$(DESTDIR)$(datadir)/extension/pgtap.control:
	pgxn install pgtap

endif # fndef PGXNTOOL_NO_PGXS_INCLUDE
