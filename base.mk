null :=# Make sure there's no trailing space here!
space := $(null) $(null)# Make sure there's no trailing space here!
comma :=,# Make sure there's no trailing space here!
dquote :="# Make sure there's no trailing space here!
json_sep := $(dquote)$(comma)$(dquote)

json_parse_cmd	= cat $(1) | $(JSON_SH) | egrep '\[$(dquote)$(strip $(2))$(dquote)\]' | cut $(if $(findstring undefined,$(origin 3)),-f 2,$(3))
# Need echo to strip out "s
json_parse	= $(shell echo $(shell $(json_parse_cmd)))
# Uncomment to debug
#json_parse	= $(json_parse_cmd)

META_parse	= $(call json_parse,META.json,$(1))
META_parse2	= $(call json_parse,META.json,$(1),$(2))

# Second argument becomes 'provides","$(1)","version', which gets wrapped in
# '["..."]' by json_parse_cmd.
META_extversion	= $(call META_parse,provides$(json_sep)$(1)$(json_sep)version)

PGXNTOOL_DIR := pgxntool
JSON_SH := $(PGXNTOOL_DIR)/JSON.sh

PGXN		= $(call META_parse,name)
PGXNVERSION	= $(call META_parse,version)

# Get list of all extensions defined in META.json
# The second argument first expands to 'provides","[^"]*', which after
# expansion in json_parse becomes '\["provides","[^"]*"\]' (excluding single
# quotes in both cases).  The third argument is '-d\" -f4'.
#
# This ultimately has the effect of finding every key name under the provides
# object in META.json.
EXTENSIONS	= $(call META_parse2,provides$(json_sep)[^$(dquote)]*,-d\$(dquote) -f4)

define extension--version_rule
EXTENSION_$(1)_VERSION		:= $(call META_extversion,$(1))
EXTENSION_$(1)_VERSION_FILE	= sql/$(1)--$$(EXTENSION_$(1)_VERSION).sql
EXTENSION_VERSION_FILES		+= $$(EXTENSION_$(1)_VERSION_FILE)
$$(EXTENSION_$(1)_VERSION_FILE): sql/$(1).sql META.json
	cp $$< $$@
endef
$(foreach ext,$(EXTENSIONS),$(eval $(call extension--version_rule,$(ext)))): META.json
# TODO: Add support for creating .control files
#$(foreach ext,$(EXTENSIONS),$(info $(call extension--version_rule,$(ext))))

DATA         = $(EXTENSION_VERSION_FILES)
DOCS         = $(wildcard doc/*.asc)
ifeq ($(strip $(DOCS)),)
DOCS =# Set to NUL so PGXS doesn't puke
endif

PG_CONFIG   ?= pg_config
TESTDIR		?= test
TESTOUT		?= $(TESTDIR)
TEST_FILES	+= $(notdir $(wildcard $(TESTDIR)/input/*.source))
TEST_FILES	+= $(notdir $(wildcard $(TESTDIR)/sql/*.sql))
REGRESS		 = $(sort $(subst .source,,$(subst .sql,,$(TEST_FILES)))) # Sort is to get unique list
REGRESS_OPTS = --inputdir=$(TESTDIR) --outputdir=$(TESTOUT) --load-language=plpgsql
MODULES      = $(patsubst %.c,%,$(wildcard src/*.c))
ifeq ($(strip $(MODULES)),)
MODULES =# Set to NUL so PGXS doesn't puke
endif

EXTRA_CLEAN  = $(wildcard ../$(PGXN)-*.zip) $(EXTENSION_VERSION_FILES)

# Get Postgres version, as well as major (9.4, etc) version. Remove '.' from MAJORVER.
VERSION 	 = $(shell $(PG_CONFIG) --version | awk '{print $$2}' | sed -e 's/devel$$//')
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

#
# META.json
#
all: META.json
META.json: META.in.json pgxntool/build_meta.sh
	pgxntool/build_meta.sh $< $@
distclean:
	rm -f META.json

#
# testdeps
#
.PHONY: testdeps
testdeps: pgtap

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

pgxntool-sync-release	:= git@github.com:decibel/pgxntool.git release
pgxntool-sync-local		:= ../pgxntool release
# NOTE! If you pull anything other than release you're likely to get a bunch of
# stuff you don't want in your history!
pgxntool-sync: pgxntool-sync-release

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
