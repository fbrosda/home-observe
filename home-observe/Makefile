PREFIX = /usr
BINDIR = $(PREFIX)/local/bin
GUILE_VERSION = 3.0
MODDIR = $(PREFIX)/share/guile/site/$(GUILE_VERSION)/home-observe
MODULES = plenticore.scm aes.scm

install:
	install -m 755 main.scm $(BINDIR)/home-observe
	install -d $(MODDIR)
	install -m 644 -t $(MODDIR) $(MODULES)

uninstall:
	-rm $(BINDIR)/home-observe
	for f in $(MODULES); do \
		rm $(MODDIR)/$$f; \
	done
	-rmdir $(MODDIR)

.PHONY: install uninstall
