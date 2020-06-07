include Tuprules.tup


SUBDIRS := $(shell ls -d content/*/)


dist:
	for subdir in $(SUBDIRS); do \
		mkdir -p $${subdir}images $${subdir}videos; \
		ln -sf ../../Tupfile.SUBDIR $${subdir}Tupfile; \
	done
	tup
	sed -Ei 's|<figcaption>.+</figcaption>||' $(DIR_DIST)/**/*.html


dist-clean: clean
	rm -rf .tup
	rm -rf $(DIR_DIST)

clean:
	for subdir in $(SUBDIRS); do \
		find $${subdir} -empty -type d -delete; \
		rm -rf $${subdir}$(DIR_BUILD) $${subdir}$(DIR_OUT); \
		rm -f $${subdir}/Tupfile; \
	done


.PHONY: dist dist-clean clean
