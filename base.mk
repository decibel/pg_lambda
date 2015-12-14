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

PGXN		:= $(call META_parse,name)
PGXNVERSION	:= $(call META_parse,version)

# Get list of all extensions defined in META.json
# The second argument first expands to 'provides","[^"]*', which after
# expansion in json_parse becomes '\["provides","[^"]*"\]' (excluding single
# quotes in both cases).  The third argument is '-d\" -f4'.
#
# This ultimately has the effect of finding every key name under the provides
# object in META.json.
EXTENSIONS	:= $(call META_parse2,provides$(json_sep)[^$(dquote)]*,-d\$(dquote) -f4)

define extension--version_rule
EXTENSION_$(1)_VERSION		:= $(call META_extversion,$(1))
EXTENSION_$(1)_VERSION_FILE	= sql/$(1)--$$(EXTENSION_$(1)_VERSION).sql
EXTENSION_VERSION_FILES		+= $$(EXTENSION_$(1)_VERSION_FILE)
$$(EXTENSION_$(1)_VERSION_FILE): sql/$(1).sql META.json
	cp $$< $$@
endef
$(foreach ext,$(EXTENSIONS),$(eval $(call extension--version_rule,$(ext))))
#$(foreach ext,$(EXTENSIONS),$(info $(call extension--version_rule,$(ext))))

DATA         = $(filter-out $(wildcard sql/*-*-*.sql),$(wildcard sql/*.sql))
DOCS         = $(wildcard doc/*.asc)
TESTS        = $(wildcard test/sql/*.sql)
REGRESS      = $(patsubst test/sql/%.sql,%,$(TESTS))
REGRESS_OPTS = --inputdir=test --load-language=plpgsql
#
# Uncoment the MODULES line if you are adding C files
# to your extention.
#
#MODULES      = $(patsubst %.c,%,$(wildcard src/*.c))
PG_CONFIG    = pg_config

EXTRA_CLEAN  = $(wildcard ../$(PGXN)-*.zip) $(EXTENSION_VERSION_FILES)

# Get Postgres version, as well as major (9.4, etc) version. Remove '.' from MAJORVER.
VERSION 	 = $(shell $(PG_CONFIG) --version | awk '{print $$2}' | sed -e 's/devel$$//')
MAJORVER 	 = $(shell echo $(VERSION) | cut -d . -f1,2 | tr -d .)

# Function for testing a condition
test		 = $(shell test $(1) $(2) $(3) && echo yes || echo no)

GE91		 = $(call test, $(MAJORVER), -ge, 91)

ifeq ($(GE91),yes)
all: $(EXTENSION_VERSION_FILES)

DATA = $(wildcard sql/*--*.sql)
endif

PGXS := $(shell $(PG_CONFIG) --pgxs)
# Need to do this because we're not setting EXTENSION
MODULEDIR = extension
DATA += $(wildcard *.control)

# Don't have installcheck bomb on error
.IGNORE: installcheck

#
# pgtap
#
.PHONY: pgtap
pgtap: $(DESTDIR)$(datadir)/extension/pgtap.control

$(DESTDIR)$(datadir)/extension/pgtap.control:
	pgxn install pgtap

#
# testdeps
#
.PHONY: testdeps
testdeps: pgtap

.PHONY: test
test: clean testdeps install installcheck
	@if [ -r regression.diffs ]; then cat regression.diffs; fi

.PHONY: results
results: test
	rsync -rlpgovP results/ test/expected

rmtag:
	git fetch origin # Update our remotes
	@test -z "$$(git branch --list $(PGXNVERSION))" || git branch -d $(PGXNVERSION)
	@test -z "$$(git branch --list -r origin/$(PGXNVERSION))" || git push --delete origin $(PGXNVERSION)

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

# To use this, do make print-VARIABLE_NAME
print-%	: ; $(info $* is [${$*}])@echo -n

#
# subtree sync support
#
# This is setup to allow any number of pull targets by defining special
# variables. pgxntool-sync-release is an example of this.
.PHONY: pgxn-sync-%
pgxntool-sync-%:
	git subtree pull -P pgxntool $($@)

pgxntool-sync-release	:= git@github.com:decibel/pgxntool.git release
pgxntool-sync-dev		:= git@github.com:decibel/pgxntool.git master
pgxntool-sync-local		:= ../pgxntool master
pgxntool-sync: pgxntool-sync-release

include $(PGXS)
