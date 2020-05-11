# The config file defines some directories and the path to some programs.
include config.mk

# This program assumes that you're creating a course with the following directory structure:
#
# chapter-1/
# chapter-2/
# ...
#
# For each chapter, make will copy ./Makefile.subdir into the chapter directory and run make there.

SUBDIRS := $(shell ls -d */)
SUBDIRS := $(filter-out $(DIR_DIST)/,$(SUBDIRS))

.PHONY: clean subdirs dist $(SUBDIRS)

dist: subdirs
	for subdir in $(SUBDIRS); do \
		DIR_CHAPTER=$(DIR_DIST)/$${subdir}; \
		mkdir -p $${DIR_CHAPTER}; \
		cp $${subdir}$(DIR_OUT)/$(DIR_BUILD)/* $${DIR_CHAPTER}; \
	done

subdirs: $(SUBDIRS)

$(SUBDIRS):
	cp Makefile.subdir $@Makefile
	$(MAKE) -C $@

clean:
	for subdir in $(SUBDIRS); do \
		MAKEFILE=$${subdir}Makefile; \
		if [ -e $${MAKEFILE} ]; then \
			rm -rf $${subdir}${DIR_BUILD}; \
			rm -rf $${MAKEFILE}; \
		fi; \
	done

dist-clean: clean
	for subdir in $(SUBDIRS); do \
		rm -rf $${subdir}${DIR_OUT}; \
	done
	rm -rf $(DIR_DIST)


