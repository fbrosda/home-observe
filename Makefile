.PHONY: %

%:
	$(MAKE) -C systemd $@
	$(MAKE) -C home-observe $@
